"""ft-sheet-events — 사건 원장 `sheet-events.jsonl` 훅 헬퍼 (PLAN-status-sheet r4 §3·§3-1 · 근원 ⑥).

사실을 «미는» 도구 5곳이 부른다. 순서(admission): 사건 키 → `prepare`(<key>.prepared · 못 쓰면 rc≠0 = 작업 거절) → 작업 →
성공 직후 `commit`(원자 rename → <key>.committed → append · 실패 시 파일 유지 + stderr SHEET-EVENT-PENDING · rc 0) / 실패 시 `abort`.
`reconcile` 은 .committed 만 원장에 넣는다 · .prepared 는 `--confirm`(authoritative 확인)으로만 승격 — 성공 사건이 아니다.
  ft-sheet-events.sh key <ev> <a> [b] | prepare <key> <json> | commit <key> [--ref R] | abort <key> | append <key> | reconcile [--confirm] | pending | gh-state <번호>
env: FT_SHEET_ROOT(있으면 루트 대신 이것 — 설치 폴더 밖 시험용) · FT_ROOT · FT_BOARD_NOW(시각 주입) · FT_SHEET_CONFIRM_CMD(승격 확인 명령 · `<ev> <key> <ref>` rc 0 = 확인됨 · 시험용 스텁)
"""
import fcntl
import json
import os
import shlex
import subprocess
import sys
from contextlib import contextmanager
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ft_board_env as env  # noqa: E402
from ft_sheet_key import make_key  # noqa: E402

OLD_S = 600  # 10분 넘은 prepared = «오래됨»


def state_dir(root: Path) -> Path:
    return root / ".fable-team" / "state"


def _file(root: Path, key: str, suffix: str) -> Path:
    return state_dir(root) / "sheet-events.pending" / (key.replace("/", "%2F") + suffix)


def has_key(root: Path, key: str) -> bool:
    p = state_dir(root) / "sheet-events.jsonl"
    needle = json.dumps({"key": key}, ensure_ascii=False)[1:-1]
    return p.is_file() and any(needle in ln for ln in p.read_text(encoding="utf-8").splitlines())


def prepare(root: Path, key: str, raw: str) -> int:
    row = json.loads(raw)
    if has_key(root, key) or _file(root, key, ".committed").exists():
        print(f"sheet-event: dup {key}")
        return 0
    row.update(key=key, ts=env.now().isoformat(timespec="seconds"), state="prepared")
    d = _file(root, key, ".prepared")
    try:
        d.parent.mkdir(parents=True, exist_ok=True)
        tmp = d.with_suffix(".tmp")
        with tmp.open("w", encoding="utf-8") as f:
            f.write(json.dumps(row, ensure_ascii=False))
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, d)
    except OSError as e:
        print(f"REJECT sheet-events prepared 실패 — 작업 거절: {e}", file=sys.stderr)
        return 1
    return 0


@contextmanager
def _locked(root: Path):
    """원장 append 구간 전체(has_key → write → unlink)를 한 flock 으로 — commit 과 reconcile 의 동시 append 가 같은 key 를 두 번 쓰지 못한다."""
    lock = state_dir(root) / "sheet-events.jsonl.lock"
    lock.parent.mkdir(parents=True, exist_ok=True)
    with lock.open("a") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        yield


def _append(root: Path, key: str) -> bool:
    com = _file(root, key, ".committed")
    try:
        with _locked(root):
            if not com.exists():  # 다른 프로세스가 먼저 처리했다
                return True
            row = json.loads(com.read_text(encoding="utf-8"))
            row.pop("state", None)
            if has_key(root, key):
                print(f"sheet-event: dup {key}")
            else:
                with (state_dir(root) / "sheet-events.jsonl").open("a", encoding="utf-8") as f:
                    f.write(json.dumps(row, ensure_ascii=False) + "\n")
                    f.flush()
                    os.fsync(f.fileno())
            com.unlink(missing_ok=True)
    except OSError:
        print(f"SHEET-EVENT-PENDING {key}", file=sys.stderr)
        return False
    return True


def _mark_commit_pending(prep: Path) -> None:
    try:
        row = json.loads(prep.read_text(encoding="utf-8"))
        row["state"] = "commit-pending"
        tmp = prep.with_suffix(".tmp")
        tmp.write_text(json.dumps(row, ensure_ascii=False), encoding="utf-8")
        os.replace(tmp, prep)
    except OSError:
        pass  # 표식도 못 쓰면 prepared 는 «prepared» 그대로 — 보존 보장 없음(stderr 에 PENDING 이 이미 나갔다)


def commit(root: Path, key: str, ref: str | None = None) -> int:
    prep, com = _file(root, key, ".prepared"), _file(root, key, ".committed")
    if prep.exists():
        if ref is not None:
            row = json.loads(prep.read_text(encoding="utf-8"))
            row["ref"] = ref
            prep.write_text(json.dumps(row, ensure_ascii=False), encoding="utf-8")
        try:
            os.rename(prep, com)  # 원자 — 실패하면 prepared 가 남는다(성공 사건 아님)
        except OSError as e:
            _mark_commit_pending(prep)  # 생산자 EXIT trap 의 abort 가 이 prepared 를 지우지 못하게 — 복구는 reconcile --confirm
            print(f"SHEET-EVENT-PENDING {key} (rename 실패: {e})", file=sys.stderr)
            return 0
    if not com.exists():
        if has_key(root, key):
            print(f"sheet-event: dup {key}")
            return 0
        print(f"sheet-events: prepared 없음 — {key}", file=sys.stderr)
        return 1
    _append(root, key)
    return 0


def abort(root: Path, key: str) -> int:
    prep = _file(root, key, ".prepared")
    if prep.exists() and json.loads(prep.read_text(encoding="utf-8")).get("state") == "commit-pending":
        print(f"SHEET-EVENT-KEPT {key} (commit 의 rename 실패 — 지우지 않는다 · reconcile --confirm 으로 복구)", file=sys.stderr)
        return 0
    prep.unlink(missing_ok=True)
    return 0


def _confirmed(row: dict) -> bool:
    cmd = os.environ.get("FT_SHEET_CONFIRM_CMD")
    if not cmd:
        import ft_sheet_confirm
        return ft_sheet_confirm.confirm(row)
    return subprocess.run(shlex.split(cmd) + [row["ev"], row["key"], str(row.get("ref", ""))], timeout=30).returncode == 0


def reconcile(root: Path, confirm: bool = False) -> str:
    pend = state_dir(root) / "sheet-events.pending"
    done = promoted = 0
    if confirm:
        for p in sorted(pend.glob("*.prepared")):
            row = json.loads(p.read_text(encoding="utf-8"))
            if _confirmed(row):
                os.rename(p, p.with_suffix(".committed"))
                promoted += 1
    for p in sorted(pend.glob("*.committed")):
        done += _append(root, json.loads(p.read_text(encoding="utf-8"))["key"])
    return f"reconcile: appended {done} · confirmed {promoted} · prepared {len(list(pend.glob('*.prepared')))}"


def pending_counts(root: Path) -> dict:
    """시트 머리 «확인 중 N» — prepared 만(성공 아님). committed 는 곧 원장에 들어갈 사건이라 세지 않는다."""
    now = env.now().timestamp()
    ps = list((state_dir(root) / "sheet-events.pending").glob("*.prepared"))
    return {"prepared": len(ps), "old": sum(1 for p in ps if now - p.stat().st_mtime > OLD_S)}


def main(argv: list[str]) -> int:
    root, cmd, a = Path(os.environ.get("FT_SHEET_ROOT") or env.ft_root()), (argv[0] if argv else ""), argv[1:]
    if cmd == "key" and 2 <= len(a) <= 3:
        try:
            k = make_key(*a)
        except ValueError:
            print(f"REJECT unknown ev {a[0]} — 등록된 사건 종류만 (ft_sheet_key.EVS)", file=sys.stderr)
            return 2
        print(k)
        return 0 if k else 1
    if cmd == "prepare" and len(a) == 2:
        return prepare(root, *a)
    if cmd == "commit" and len(a) in (1, 3) and (len(a) == 1 or a[1] == "--ref"):
        return commit(root, a[0], a[2] if len(a) == 3 else None)
    if cmd == "abort" and len(a) == 1:
        return abort(root, a[0])
    if cmd == "append" and len(a) == 1:
        return 0 if _append(root, a[0]) else 1
    if cmd == "reconcile" and a in ([], ["--confirm"]):
        print(reconcile(root, bool(a)))
        return 0
    if cmd == "pending" and not a:
        print(json.dumps(pending_counts(root)))
        return 0
    if cmd == "gh-state" and len(a) == 1:
        import ft_sheet_confirm
        return ft_sheet_confirm.gh_state(a[0])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as e:  # noqa: BLE001 — 숨기지 않고 사유와 rc≠0 (#0 RULE)
        print(f"ft-sheet-events: {type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(1)
