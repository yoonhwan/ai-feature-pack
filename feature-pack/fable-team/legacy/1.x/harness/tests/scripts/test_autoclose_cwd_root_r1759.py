"""r1759 — 자동 닫기(갈래=착지기록 · 갈래=승인)가 ft-nano-close 를 «데이터 루트(FT_ROOT = BYZ 꼴)» 안에서 부른다.

① 착지기록 갈래: 스캐너 cwd = 팩 꼴 · o.root(FT_ROOT) = BYZ 꼴 → close 스텁이 본 toplevel = BYZ 꼴 · «auto-close CLOSED … 갈래=착지기록» (기준판 = 팩 꼴 «REJECT 팀 env 없음» = Red)
② 승인 갈래: 같은 꼴 → toplevel = BYZ 꼴 · «auto-close CLOSED <좌석> set=<세트>» (기준판 = Red)
③ 데이터 루트가 없는 폴더 → 호출 0 · «판정 불가 auto-close <좌석> 데이터 루트 없음(<값>)» 1줄 · tried 변화 0
④ close-due 호출 cwd = 기준판 그대로(스캐너 cwd) · close 로 가는 인자 꼴 그대로(A4) · 꺼짐(FT_NANO_AUTO_CLOSE 없음) = 호출 0
M1 land_close 의 cwd 지움 → ① FAIL · M2 승인 갈래 cwd 지움 → ② FAIL · M3 데이터 루트 검사 지움 → ③ FAIL (변이마다 원본 대조 1회)

격리: close·close-due 는 이 파일이 만든 스텁(자기 cwd 의 git toplevel·팀 env 유무를 본다) · 실 좌석·실 tmux·실 닫기·네트워크 0 ·
      o.now=0(stamp 고정 — 바이트 대조) · sleep 0 · 70초 안. R1759_BIN = 시험할 bin 폴더(기본 = 추적본 kit · 변이 대조 때 덮는다).
"""
from __future__ import annotations

import json
import os
import shutil
import stat
import subprocess
import sys
import time
from pathlib import Path

import pytest

BIN = Path(os.environ.get("R1759_BIN") or Path(__file__).resolve().parents[2] / "kit/fable-team/bin")
SEAT = "byz-harness-nano-pk#0"
SET_SHA = "b" * 40
REC = "r1"
STAMP = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(0))
TEAM_ENV = ".fable-team/bin-harness/harness-env.sh"


# ── 스텁·세계 ────────────────────────────────────────────────────────────────
def _stub(path: Path, body: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("#!/usr/bin/env bash\n" + body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)
    return path


def _close_stub(tmp: Path) -> Path:
    """close 스텁 — 자기 cwd 의 git toplevel 과 팀 env 유무를 본다(실 도구의 :249~:280 과 같은 판정 꼴)."""
    return _stub(
        tmp / "close.sh",
        'printf "%s\\n" "$*" >> "$STUB_ARGS"\n'
        'top="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"\n'
        'printf "%s\\n" "${top:-none}" >> "$STUB_TOP"\n'
        'if [ -f "$top/' + TEAM_ENV + '" ]; then echo "CLOSED $1"; exit 0; fi\n'
        'echo "REJECT 팀 env 없음: $top/' + TEAM_ENV + '"\n'
        "exit 1\n",
    )


def _due_stub(tmp: Path, rows: list[str], rc: int = 0) -> Path:
    body = 'printf "%s\\n" "$PWD" >> "$STUB_DUE_CWD"\n' + "".join(
        'printf "%s\\n" "' + r.replace('"', '\\"') + '"\n' for r in rows
    )
    return _stub(tmp / "due.sh", body + f"exit {rc}\n")


def _git(cwd: Path, *args: str) -> str:
    p = subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True, check=False)
    assert p.returncode == 0, f"git {args} rc={p.returncode} {p.stderr[:200]}"
    return p.stdout.strip()


def _world(tmp: Path) -> dict:
    """팩 꼴(PACK · 팀 env 없음) + BYZ 꼴(ROOT · 팀 env·명부·장부·전달 기록) — 실 좌석·실 tmux 0."""
    os.environ.update(
        GIT_CONFIG_GLOBAL="/dev/null",
        GIT_CONFIG_SYSTEM="/dev/null",
        GIT_AUTHOR_NAME="t",
        GIT_AUTHOR_EMAIL="t@t",
        GIT_COMMITTER_NAME="t",
        GIT_COMMITTER_EMAIL="t@t",
    )
    for k in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY"):
        os.environ.pop(k, None)
    pack, root = tmp / "pack", tmp / "root"
    for repo in (pack, root):
        repo.mkdir(parents=True, exist_ok=True)
        _git(repo, "init", "-q", "-b", "main")
    (pack / "p").write_text("p\n", encoding="utf-8")
    _git(pack, "add", "-A")
    _git(pack, "commit", "-qm", "pack")
    env_sh = root / TEAM_ENV
    env_sh.parent.mkdir(parents=True, exist_ok=True)
    env_sh.write_text("#!/usr/bin/env bash\nprintf 'ENV-STUB\\n'\n", encoding="utf-8")
    fb = root / ".fable-team"
    (fb / "seats-harness.json").write_text(
        json.dumps({"_master": "byz-harness-master-pi#217", SEAT: {"role": "nano", "agent": "pi"}}, ensure_ascii=False),
        encoding="utf-8",
    )
    (root / "a").write_text("a\n", encoding="utf-8")
    _git(root, "add", "-A")
    _git(root, "commit", "-qm", "root")
    landed = _git(root, "rev-parse", "HEAD")
    _git(root, "update-ref", "refs/remotes/origin/main", landed)
    state = fb / "state"
    state.mkdir(parents=True, exist_ok=True)
    (state / "land-record-notified.json").write_text(
        json.dumps({"close": {f"{SEAT}|{landed}": {"rec": REC, "pr": 1}}}, ensure_ascii=False), encoding="utf-8"
    )
    (state / "land-record-turn.jsonl").write_text(
        json.dumps({"pr": 1, "repo": str(root), "target": "main", "landed": landed, "pr_head": landed,
                    "by": "t", "cards": [], "ts": "t"}, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return {"pack": pack, "root": root, "landed": landed, "state": state,
            "args": tmp / "args.txt", "top": tmp / "top.txt", "due": tmp / "due_cwd.txt"}


def _line_land(landed: str) -> str:
    return (f"닫기 차례 {SEAT} 팀=harness 가지=nano/pk landed={landed} main=abc1234567 갈래=착지기록 rec={REC} set={SET_SHA} — "
            f"bash ft-nano-close.sh {SEAT} --landed-pr - --result /tmp/x.md --recv 7")


def _line_ok() -> str:
    return (f"닫기 차례 {SEAT} 팀=harness 갈래=승인 set={SET_SHA} main=abc1234567 — "
            f"bash ft-nano-close.sh {SEAT} --approved /tmp/da.md --result /tmp/r.md --recv 7")


def _import_scan(bin_dir: Path):
    for k in [k for k in sys.modules if k.startswith("ft_")]:   # 사본 bin 의 짝 모듈까지 다시 읽는다(캐시된 원본을 쓰면 변이가 안 먹는다)
        sys.modules.pop(k, None)
    if str(bin_dir) not in sys.path:
        sys.path.insert(0, str(bin_dir))
    import ft_stall_scan as m  # noqa: PLC0415 — 사본 bin 을 그때그때 import(변이 시험)

    return m


def _scan(bin_dir: Path, root, state: Path):
    o = object.__new__(_import_scan(bin_dir).Scan)   # __init__(자동 배정·명부 조회) 없이 auto_close() 만(단위)
    o.root, o.state_dir, o.now = Path(root), Path(state), 0
    o.state_dir.mkdir(parents=True, exist_ok=True)
    return o


def _rows(w: dict, rows: list[str]) -> list[str]:
    return [(_line_land(w["landed"]) if r == "__LAND__" else _line_ok()) for r in rows]


def _run(tmp: Path, monkeypatch, rows: list[str], root: Path | None = None, auto: str | None = "1", bin_dir: Path | None = None):
    w = _world(tmp)
    monkeypatch.chdir(w["pack"])   # 스캐너 cwd = 팩 꼴(launchd 작업 폴더 · 팩 나노 worktree 꼴)
    for k, v in (("STUB_ARGS", w["args"]), ("STUB_TOP", w["top"]), ("STUB_DUE_CWD", w["due"])):
        monkeypatch.setenv(k, str(v))
    monkeypatch.setenv("FT_NANO_CLOSE_DUE", str(_due_stub(tmp, _rows(w, rows))))
    monkeypatch.setenv("FT_NANO_CLOSE", str(_close_stub(tmp)))
    monkeypatch.delenv("FT_NANO_AUTO_CLOSE", raising=False)
    if auto is not None:
        monkeypatch.setenv("FT_NANO_AUTO_CLOSE", auto)
    out = _scan(bin_dir or BIN, root or w["root"], w["state"]).auto_close()
    sf = w["state"] / "nano-auto-close.json"
    tried = json.loads(sf.read_text(encoding="utf-8")) if sf.exists() else {}
    tops = w["top"].read_text(encoding="utf-8").splitlines() if w["top"].exists() else []
    args = w["args"].read_text(encoding="utf-8").splitlines() if w["args"].exists() else []
    due_cwd = w["due"].read_text(encoding="utf-8").splitlines() if w["due"].exists() else []
    return w, out, tried, tops, args, due_cwd


# ── 반례 ①~④ ───────────────────────────────────────────────────────────────
def test_a1_land_branch_runs_in_data_root(tmp_path, monkeypatch):
    w, out, tried, tops, args, _ = _run(tmp_path, monkeypatch, ["__LAND__"])
    assert out == [f"{STAMP} auto-close CLOSED {SEAT} 갈래=착지기록 rec={REC}"], out   # 기준판 = «auto-close 실패 … REJECT 팀 env 없음» = Red
    assert tops == [str(w["root"])], f"close 스텁이 본 toplevel = 데이터 루트 여야 한다: {tops}"
    assert args == [f"{SEAT} --landed-pr - --result /tmp/x.md --recv 7"], args
    assert tried == {}, "성공은 tried 에서 지운다"


def test_a2_approval_branch_runs_in_data_root(tmp_path, monkeypatch):
    w, out, tried, tops, args, _ = _run(tmp_path, monkeypatch, [_line_ok()])
    assert out == [f"{STAMP} auto-close CLOSED {SEAT} set={SET_SHA}"], out   # 기준판 = 실패 줄 = Red
    assert tops == [str(w["root"])], tops
    assert args == [f"{SEAT} --approved /tmp/da.md --result /tmp/r.md --recv 7"], args
    assert tried == {}


def test_a3_missing_data_root_is_unknown_line(tmp_path, monkeypatch):
    gone = tmp_path / "no-such-root"
    _, out, tried, _, args, _ = _run(tmp_path, monkeypatch, [_line_ok()], root=gone)
    assert out == [f"{STAMP} 판정 불가 auto-close {SEAT} 데이터 루트 없음({gone})"], out
    assert args == [], "데이터 루트가 없으면 close 호출 0(하드 룰 20)"
    assert tried == {}, "tried 갱신 0 — 다음 회차 다시"


def test_a4_rest_unchanged(tmp_path, monkeypatch):
    w, out, _, _, args, due_cwd = _run(tmp_path, monkeypatch, [_line_ok()])
    assert due_cwd == [str(w["pack"])], f"close-due cwd 는 기준판(스캐너 cwd) 그대로: {due_cwd}"
    assert args == [f"{SEAT} --approved /tmp/da.md --result /tmp/r.md --recv 7"], args
    assert out == [f"{STAMP} auto-close CLOSED {SEAT} set={SET_SHA}"], out
    # 꺼짐(FT_NANO_AUTO_CLOSE 없음) = close-due 호출도 close 호출도 0(지금 그대로)
    _, out2, tried2, _, args2, due2 = _run(tmp_path / "off", monkeypatch, [_line_ok()], auto=None)
    assert (out2, args2, due2) == ([], [], []), (out2, args2, due2)
    assert tried2 == {}


# ── 변이 M1~M3 (사본에서만 · 변이마다 원본 대조 1회) ─────────────────────────
MUT = {
    "M1 land_close cwd 지움": ("ft_nano_record_auto.py", ", 70, cwd=cwd)", ", 70)",
                              dict(rows=["__LAND__"]), "auto-close CLOSED"),
    "M2 승인 갈래 cwd 지움": ("ft_stall_scan.py", ", 70, cwd=cwd)", ", 70)",
                             dict(rows=["__OK__"]), "auto-close CLOSED"),
    "M3 데이터 루트 검사 지움": ("ft_stall_scan.py",
                                 'root_why = f"데이터 루트 없음({cwd})" if cwd is not None and not cwd.is_dir() else ""',
                                 'root_why = ""',
                                 dict(rows=["__OK__"], root_missing=True), "판정 불가 auto-close"),
}


def _mutant(tmp: Path, name: str, fn: str, anchor: str, repl: str) -> Path:
    d = tmp / f"mut-{name.split()[0]}"
    d.mkdir(parents=True, exist_ok=True)
    for p in sorted(BIN.glob("*.py")):
        shutil.copy(p, d / p.name)
    src = (d / fn).read_text(encoding="utf-8")
    assert src.count(anchor) == 1, f"변이 앵커 {src.count(anchor)}곳: {anchor[:70]}"
    (d / fn).write_text(src.replace(anchor, repl, 1), encoding="utf-8")
    return d


@pytest.mark.parametrize("mid", list(MUT))
def test_mutations(mid, tmp_path, monkeypatch):
    fn, anchor, repl, case, want = MUT[mid]

    def once(tag: str, bin_dir: Path):
        sub = tmp_path / tag
        sub.mkdir()
        w = _world(sub)
        monkeypatch.chdir(w["pack"])
        for k, v in (("STUB_ARGS", w["args"]), ("STUB_TOP", w["top"]), ("STUB_DUE_CWD", w["due"])):
            monkeypatch.setenv(k, str(v))
        monkeypatch.setenv("FT_NANO_CLOSE_DUE", str(_due_stub(sub, _rows(w, case["rows"]))))
        monkeypatch.setenv("FT_NANO_CLOSE", str(_close_stub(sub)))
        monkeypatch.setenv("FT_NANO_AUTO_CLOSE", "1")
        root = (sub / "no-such-root") if case.get("root_missing") else w["root"]
        out = _scan(bin_dir, root, w["state"]).auto_close()
        return out

    good = once("orig", BIN)                                     # 원본 대조 — 같은 사례는 통과
    assert good and want in good[0], f"원본 대조 실패 {mid}: {good}"
    bad = once("mut", _mutant(tmp_path, mid, fn, anchor, repl))
    assert not (bad and want in bad[0]), f"{mid} 변이인데 통과 = 검출 실패 {bad}"
