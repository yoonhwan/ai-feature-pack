"""r1309 — 우편 다리(다른 루트 받는이): 기계 루트 명부(roots.tsv)를 «읽기 전용» 으로 읽는다.

정본 = ~/.claude/fable-team/roots.tsv (탭 6칸: 이름 · 루트 절대경로 · 상태(현역/휴면) · 기준ref · 사람우편함 · 틱잠금접두).
  · 파일 없음 = 빈 목록 → 다리 없음(= 지금 동작 그대로 · BYZ 단일 루트)
  · 깨짐 = RootsError → send 가 «받는이 판정 불가» 1줄 rc≠0 으로 끝낸다(조용한 자기 큐 쓰기 0)

★comm 은 ft_team_lib 을 import 하지 않는다★ — comm 과 bin 의 폴더 관계는 설치본(.fable-team/{comm,bin})과 팩(harness/{comm,bin})에서
같지만, comm 만 따로 복사된 옛 루트(kakao = 옛 사본 29파일)도 send 가 죽지 않아야 한다. 그래서 roots.tsv 파서를 여기 작게 다시 둔다.

다리 규칙(기획 3184 §3-4 · X10):
  ① 받는이가 «내 루트 명부» 에 있으면 다리 0(지금 그대로)
  ② 없고 roots.tsv 의 «다른 현역 루트» 명부에 있으면 그 루트의 .fable-team/comm 으로 1줄 쓴다 → 출력 «BRIDGED → <루트> seq=N»
  ③ 어디에도 없으면 «받는이 판정 불가» rc≠0 · 큐 쓰기 0
  ④ 이미 다리로 온 쪽(FT_MBOX_BRIDGED=1)은 다시 다리를 타지 않는다(무한 왕복 0)
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOTS_TSV = "~/.claude/fable-team/roots.tsv"
COLS = 6
STATES = ("현역", "휴면")
OWN_ROOT: Path | None = None
CANON: str | None = None


class RootsError(RuntimeError):
    pass


def roots_tsv(path: Path | str | None = None) -> Path:
    return Path(path) if path else Path(os.path.expanduser(os.environ.get("FT_ROOTS_TSV") or ROOTS_TSV))


def roots(path: Path | str | None = None) -> list[dict[str, object]]:
    file = roots_tsv(path)
    if not file.is_file():
        return []
    out: list[dict[str, object]] = []
    for no, line in enumerate(file.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        cells = [c.strip() for c in line.split("\t")]
        if len(cells) < COLS:
            raise RootsError(f"ERROR 루트 명부 판정 불가: {file}:{no} 칸 {len(cells)}개({COLS} 필요)")
        name, where, state, ref, human, lock = cells[:COLS]
        if not name or not where.startswith("/") or state not in STATES or not ref or not human or not lock:
            raise RootsError(f"ERROR 루트 명부 판정 불가: {file}:{no} 값이 이상하다")
        out.append({"name": name, "path": Path(where), "state": state, "ref": ref, "human_mail": human, "tick_lock": lock})
    return out


def role_key(name: str) -> str:
    """우편함 키 = 역할 이름(mbox_conf.role_key 와 같은 규칙) — 승계 뒤 번호가 달라도 같은 좌석으로 본다."""
    return re.sub(r"#\d+$", "", name or "")


def own_root() -> Path | None:
    """이 우편함이 사는 루트 — CANON(<루트>/.fable-team/comm)에서 먼저 푼다.

    ★mbox.py 의 _ROOT 는 못 쓴다★ — 그 값은 «워크트리 밖 리포 루트» 로 잘라 내므로(kakao 처럼 git toplevel 아래 하위 폴더가 루트인 경우)
    roots.tsv 의 행과 안 맞는다. CANON 이 바뀌었을 때만 _ROOT 로 물러난다."""
    if CANON:
        for anc in (Path(CANON), *Path(CANON).parents):
            if anc.name == ".fable-team":
                return anc.parent
    if OWN_ROOT is not None:
        return Path(OWN_ROOT)
    return None


def _roster_names(base: Path) -> list[str]:
    """그 루트 TEAMS.md 의 «명부» 칸 값들(빈 값은 규칙 기본 이름으로 채운다) · TEAMS.md 가 없으면 빈 목록."""
    md = base / "design" / "TEAMS.md"
    try:
        lines = md.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError):
        return []
    header: list[str] | None = None
    out: list[str] = []
    for line in lines:
        if not line.startswith("|"):
            continue
        cells = [c.strip().strip("`") for c in line.strip().strip("|").split("|")]
        if {"팀", "폴더", "상태"}.issubset(cells):
            header = cells
            continue
        if header is None or all(re.fullmatch(r":?-{3,}:?", c.replace(" ", "")) for c in cells):
            continue
        row = dict(zip(header, cells))
        rel = re.sub(r"[\s`]", "", row.get("폴더", ""))
        team = rel.rstrip("/").rsplit("/", 1)[-1]
        if row.get("상태") not in ("현역", "휴면", "삭제") or not team:
            continue
        value = (row.get("명부") or "").strip()
        out.append(value or ("seats.json" if team == "v65" else f"seats-{team}.json"))
    return out


def roster_keys(base: Path) -> set[str]:
    """그 루트 명부에 적힌 좌석 이름들(역할 키) — TEAMS.md «명부» 칸 파일들 · TEAMS.md 가 없으면 seats*.json."""
    cands = _roster_names(base)
    if not cands:
        try:
            cands = [p.name for p in sorted((base / ".fable-team").glob("seats*.json"))]
        except OSError:
            cands = []
    keys: set[str] = set()
    for name in cands:
        if "/" in name:
            continue
        try:
            doc = json.loads((base / ".fable-team" / name).read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if isinstance(doc, dict):
            keys |= {role_key(k) for k in doc if not k.startswith("_")}
    return keys


def comm_of(base: Path) -> Path:
    return base / ".fable-team" / "comm"


def _child(comm: Path, *args: str, extra_env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    """그 우편함에 1줄 쓰는 자식 — 같은 mbox.sh(없으면 mbox.py)에 FT_MBOX_DIR 을 바꿔 건다(가드·doorbell 그대로)."""
    env = {**os.environ, **extra_env, "FT_MBOX_DIR": str(comm), "FT_MBOX_BRIDGED": "1"}
    sh = Path(comm) / "mbox.sh"
    if sh.is_file():
        return subprocess.run(["bash", str(sh), *args], capture_output=True, text=True, timeout=7, env=env)
    py = Path(comm) / "mbox.py"
    if py.is_file():
        return subprocess.run([sys.executable, str(py), *args], capture_output=True, text=True, timeout=7, env=env)
    raise RootsError(f"ERROR 우편 다리 판정 불가: {comm} 에 mbox.sh·mbox.py 가 없다")


def bridge(to: str, frm: str, body: str) -> str | None:
    """r1309 X10 — 다른 루트 받는이면 그 루트 우편함으로 1줄 쓴다. → 인쇄할 1줄(BRIDGED) | None = 다리 0(지금 경로).

    판정 불가는 예외(RootsError)가 아니라 «1줄 + rc≠0» 으로 끝낸다 — 호출자(mbox_ops.send)가 그대로 종료한다."""
    if os.environ.get("FT_MBOX_BRIDGED") == "1":
        return None
    me = own_root()
    if me is None:
        return None
    try:
        rows = roots()
    except RootsError as e:
        print(f"{e} — 받는이 판정 불가({to})", file=sys.stderr)
        sys.exit(4)
    if not rows:
        return None                       # roots.tsv 없음 = 지금 동작
    live = [r for r in rows if r["state"] == "현역"]
    mine = next((r for r in live if Path(str(r["path"])).resolve() == me.resolve()), None)
    if mine is None:
        return None                       # 명부에 없는 루트(옛 사본) = 지금 동작
    want = role_key(to)
    if want in roster_keys(me):
        return None                       # ① 내 명부에 있으면 다리 0
    for row in live:                      # ② 다른 루트 명부에 있으면 그 루트 우편함으로
        if Path(str(row["path"])).resolve() == me.resolve():
            continue
        if want not in roster_keys(Path(str(row["path"]))):
            continue
        comm = comm_of(Path(str(row["path"])))
        try:
            p = _child(comm, "send", to, frm, body, extra_env={"FT_MBOX_BRIDGED": "1", "FT_MBOX_RECEIPT": "done"})
        except (OSError, subprocess.SubprocessError, RootsError) as e:
            print(f"ERROR 우편 다리 판정 불가({row['name']} · {type(e).__name__}) — 받는이 {to}", file=sys.stderr)
            sys.exit(4)
        out = (p.stdout or "") + (p.stderr or "")
        seq = re.search(r"QUEUED seq=(\d+)", out)
        if p.returncode == 0 and seq:
            import mbox_receipt   # r1416 — 보낸 쪽 기록에 영수 1줄(늦은 import = 두 모듈 서로 부름)
            mbox_receipt.receipt(comm_of(me), to, frm, body, str(row["name"]), int(seq.group(1)))
            return f"BRIDGED → {row['name']} seq={seq.group(1)} to={to} (내 큐 쓰기 0)"
        print(f"ERROR 우편 다리 판정 불가({row['name']} rc={p.returncode}) — 받는이 {to}\n{out.strip()[:200]}", file=sys.stderr)
        sys.exit(4)
    print(f"받는이 판정 불가: {to} — 내 루트({me})와 roots.tsv 현역 루트 어느 명부에도 없다. 큐 쓰기 0", file=sys.stderr)
    sys.exit(2)


def home_receipt(to: str, frm: str, body: str, seq: int) -> None:
    """r1416 B6 — 본문 = mbox_receipt.home(늦은 import · 두 모듈이 서로 부른다)."""
    import mbox_receipt
    mbox_receipt.home(to, frm, body, seq)
