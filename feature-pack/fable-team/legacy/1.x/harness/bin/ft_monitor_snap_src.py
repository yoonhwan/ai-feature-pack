"""ft_monitor_snap_src — 모니터 스냅샷 칸 원천 읽기(공통 도구 + 원장·카드·장부 칸) (r2409 · 기획서 §2.1 · S1 그림자).

칸 꼴은 전부 같다: {"v": 값, "src": "출처 1곳", "at": "잰 시각", "q": "ok|stale|unknown"}.
  unknown = 못 잼(원천 없음 · 꼴 다름 · rc≥2 · 7초 초과) → v = null («0» 으로 채우지 않는다 · 하드 룰 20).
  stale   = 원천이 칸 문턱보다 낡음(STALE 초) → 값은 그대로 두고 q 만 stale.
시각은 부르는 쪽이 준 now(epoch) 하나만 쓴다 — 같은 입력·같은 now = 같은 바이트(기획서 §2.4 G4) · 원천 1곳 7초.
env 대역(시험·이식): FT_MONITOR_GOAL_MD · FT_MONITOR_CARDS_DESIGN · FT_MONITOR_REPLY_WAIT
"""
from __future__ import annotations  # mini python 3.9.6

import json
import os
import re
import subprocess
from datetime import datetime
from pathlib import Path

TIMEOUT = 7  # 원천 1개 상한(하드 룰 12)
FOLDERS = ("대기", "진행", "완성")
STALE = {"goals": 7200, "oppa_wait": 600}
DEFAULT_GOAL_MD = "gitref:origin/main:design/teams/planner/PLAN-oppa-ledger.md"
GOAL_SECTION = re.compile(r"^##\s+골 진행\b")
REASON = ("- 대기 사유:", "- 배정: 대기(", "- 선행:")


def iso(ts: float) -> str:
    return datetime.fromtimestamp(ts).strftime("%Y-%m-%dT%H:%M:%S")


def cell(v, src: str, at: str, q: str = "ok") -> dict:
    return {"v": v, "src": src, "at": at, "q": q}


def unk(src: str, at: str) -> dict:
    return cell(None, src, at, "unknown")


def _num(value: str):
    """«—»·«?» = 모름(None) — 모르는 수를 0 으로 채우지 않는다(원장 규칙 «n·m 을 모르면 —»)."""
    return int(value) if str(value).isdigit() else None


def stale_q(now: float, at_ts: float, secs: int) -> str:
    return "stale" if at_ts and (now - at_ts) > secs else "ok"


def run(cmd: list, root: Path, timeout: int = TIMEOUT) -> tuple:
    """(rc | None, stdout) — 시간 초과·도구 없음 = (None, "") (예외 0)."""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, cwd=str(root))
    except (OSError, subprocess.SubprocessError):
        return None, ""
    return r.returncode, r.stdout


def env(name: str, default: str, root: Path) -> str:
    return os.environ.get(name) or default


def tool(name: str, root: Path) -> str:
    return str(Path(__file__).resolve().parent / name)


def state_path(root: Path, rel: str, name: str) -> Path:
    return Path(env(name, str(root / rel), root))


def spec_read(spec: str, root: Path) -> tuple:
    """(본문 | None, 마지막 커밋 시각 | None) — `gitref:<ref>:<경로>` · 보통 파일 둘 다."""
    if spec.startswith("gitref:"):
        _, ref, path = spec.split(":", 2)
        rc, out = run(["git", "-C", str(root), "show", f"{ref}:{path}"], root)
        if rc != 0:
            return None, None
        rc2, out2 = run(["git", "-C", str(root), "log", "-1", "--format=%ct", ref, "--", path], root)
        return out, (float(out2.strip()) if rc2 == 0 and out2.strip().isdigit() else None)
    try:
        return Path(spec).read_text(encoding="utf-8"), Path(spec).stat().st_mtime
    except (OSError, UnicodeDecodeError):
        return None, None


def cmd_cell(root: Path, at: str, cmd: list, src: str, parse) -> dict:
    rc, out = run(cmd, root)
    if rc is None:
        return unk(src + " (7초 초과·도구 없음)", at)
    return parse(rc, out, src, at)


def goals(root: Path, at: str, now: float) -> dict:
    """planner 원장 «## 골 진행» 첫 표 → {골: {n, m}} · 표 없음·꼴 다름 = unknown · 원장 커밋 2시간 = stale."""
    spec = env("FT_MONITOR_GOAL_MD", DEFAULT_GOAL_MD, root)
    text, committed = spec_read(spec, root)
    if text is None:
        return unk(spec, at)
    head, out, inside = None, {}, False
    for line in text.splitlines():
        if GOAL_SECTION.match(line):
            inside, head = True, None
            continue
        if not inside:
            continue
        if not line.strip() or not line.lstrip().startswith("|"):
            if head:
                break
            continue
        cols = [c.strip() for c in line.strip().strip("|").split("|")]
        if head is None:
            if any("닫힘" in c for c in cols) and any("전체" in c for c in cols):
                head = cols
            continue
        if all(set(c) <= set("-: ") for c in cols):
            continue
        try:
            name = cols[next(i for i, c in enumerate(head) if "이름" in c)]
            n = _num(cols[next(i for i, c in enumerate(head) if "닫힘" in c)])
            m = _num(cols[next(i for i, c in enumerate(head) if "전체" in c)])
        except (StopIteration, IndexError):
            return unk(spec + " (표 꼴 다름)", at)
        if name:
            out[name] = {"n": n, "m": m}
    if head is None or not out:
        return unk(spec + " («## 골 진행» 표 없음)", at)
    return cell(out, spec, iso(committed) if committed else at, stale_q(now, committed or 0, STALE["goals"]))


def cards(root: Path) -> dict:
    """{카드 id: {state, goal, reasons}} — design/**/indices/{대기,진행,완성}/*.md («- 골좌표:» 머리 12줄)."""
    out: dict = {}
    design = Path(env("FT_MONITOR_CARDS_DESIGN", str(root / "design"), root))
    for path in sorted(design.glob("**/indices/*/*.md")):
        if path.parent.name not in FOLDERS:
            continue
        try:
            with path.open(encoding="utf-8") as f:
                lines = [f.readline().rstrip("\n") for _ in range(40)]
        except (OSError, UnicodeDecodeError):
            continue
        goal = next((l.split(":", 1)[1].strip() for l in lines[:12] if l.startswith("- 골좌표:")), "")
        why = [next((l.split(":", 1)[1].strip() for l in lines if l.startswith(p)), "") for p in REASON]
        out[path.stem] = {"state": path.parent.name, "goal": goal, "reasons": [r for r in why if r]}
    return out


def goal_facts(root: Path, at: str, card_map: dict) -> dict:
    """골별 대기·진행·완성 카드 목록 + 완성 카드의 origin/main 착지 시각(git 1회 · 실패 = unknown)."""
    rc, out = run(["git", "-C", str(root), "log", "--format=C%ct", "--name-only", "-n", "600", "origin/main",
                   "--", "design"], root)
    if rc != 0:
        return unk("git -C %s log origin/main -- design rc=%s" % (root, rc), at)
    landed: dict = {}
    stamp = None
    for line in out.splitlines():
        if line.startswith("C") and line[1:].strip().isdigit():
            stamp = float(line[1:])
        elif line.strip() and stamp is not None:
            landed.setdefault(line.strip(), stamp)
    per_goal: dict = {}
    for cid, info in sorted(card_map.items()):
        if not info["goal"]:
            continue
        slot = per_goal.setdefault(info["goal"], {"대기": [], "진행": [], "완성": [], "착지": {}})
        slot[info["state"]].append(cid)
        if info["state"] == "완성":
            ts = next((v for k, v in landed.items() if Path(k).stem == cid), None)
            slot["착지"][cid] = iso(ts) if ts else None
    return cell(per_goal, "카드 폴더 design/*/indices/{대기,진행,완성} + git origin/main 착지", at)


def waiting(root: Path, at: str, card_map: dict) -> dict:
    """골별 «서 있는 이유» 줄(카드 «- 대기 사유:» «- 배정: 대기(…)» «- 선행:») — 완성 카드는 뺀다."""
    out: dict = {}
    for cid, info in sorted(card_map.items()):
        if info["goal"] and info["reasons"] and info["state"] != "완성":
            out.setdefault(info["goal"], []).extend(f"{cid}: {r}" for r in info["reasons"])
    return cell(out, "카드 «- 대기 사유:» «- 배정: 대기(…)» «- 선행:» 줄", at)


def oppa_wait(root: Path, at: str, now: float) -> dict:
    """질문 장부 열린 줄 수(kind 전부 · 열쇠 (kind, q_ts) 마다 마지막 줄) — 깨진 줄 1개 = unknown."""
    path = state_path(root, ".fable-team/state/desk-reply-wait.jsonl", "FT_MONITOR_REPLY_WAIT")
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
        mtime = path.stat().st_mtime
    except (OSError, UnicodeDecodeError):
        return unk(str(path), at)
    last: dict = {}
    for line in lines:
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except ValueError:
            return unk(str(path) + " (깨진 줄)", at)
        if not isinstance(row, dict):
            return unk(str(path) + " (깨진 줄)", at)
        last[(row.get("kind") or "h", row.get("q_ts"))] = row
    open_rows = [(key, r) for key, r in last.items() if r.get("state") != "closed"]
    v = {"open": len(open_rows), "keys": sorted(f"{key[0]}:{r.get('key') or ''}" for key, r in open_rows)}
    return cell(v, str(path), iso(mtime), stale_q(now, mtime, STALE["oppa_wait"]))
