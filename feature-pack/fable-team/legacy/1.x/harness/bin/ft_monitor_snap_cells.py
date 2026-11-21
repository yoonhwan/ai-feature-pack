"""ft_monitor_snap_cells — 모니터 스냅샷 11칸 조립(틱 쪽 원천 + collect_all) (r2409 · 기획서 §2.1 · S1 그림자).

칸 꼴·유효성 규칙은 ft_monitor_snap_src 머리말 하나(lib) — 이 파일은 그 규칙으로 원천을 읽기만 한다.
한 칸이 터지거나 7초를 넘겨도 그 칸만 unknown 이고 다른 칸·파일 쓰기는 그대로다(스냅샷 쓰기를 멈추지 않는다).
env 대역(시험·이식): FT_MONITOR_AUTONOMY · FT_MONITOR_HIL · FT_MONITOR_STALL · FT_MONITOR_BLOCKS
  · FT_MONITOR_MAILLOG · FT_MONITOR_DIRECTIVE · FT_MONITOR_BOARD
"""
from __future__ import annotations  # mini python 3.9.6

import json
import re
from datetime import datetime
from pathlib import Path

import ft_monitor_snap_src as src_lib
from ft_monitor_snap_src import cell, cmd_cell, env, iso, run, stale_q, state_path, tool, unk

CELLS = ("goals", "goal_facts", "waiting", "oppa_wait", "autonomy", "hil", "blocked_sessions",
         "keeper_unknown", "planner_check", "directives", "collect_fail")
STALE = {"blocked_sessions": 600, "keeper_unknown": 600, "planner_check": 1800}
AUTONOMY_LINE = re.compile(r"\[자율\s*(ON|OFF)\b")
DIRECTIVE_LINE = re.compile(r"^담당 없는 오빠 지시\s*(\d+)\s*·\s*멈춘 오빠 지시\s*(\d+)")


def _cmd(name_env: str, default: str, root) -> str:
    return env(name_env, tool(default, root), root)


def autonomy(root, at: str) -> dict:
    """`ft-autonomy.sh status` 첫 줄 «[자율 ON|OFF …]» — rc≠0 이거나 꼴 다름 = unknown."""
    path = _cmd("FT_MONITOR_AUTONOMY", "ft-autonomy.sh", root)
    cmd = [path, "status"] if path.endswith(".sh") else path.split() + ["status"]

    def parse(rc, out, s, at):
        first = out.splitlines()[0] if out.splitlines() else ""
        m = AUTONOMY_LINE.search(first)
        return cell(m.group(1), s, at) if rc == 0 and m else unk(s + " (첫 줄 꼴 다름·rc)", at)
    return cmd_cell(root, at, cmd, path, parse)


def hil(root, at: str) -> dict:
    """`ft-hil.sh --pending --each` 줄 수 = 실행 기다리는 h(0 이면 출력 0줄 → 0 · q=ok)."""
    path = _cmd("FT_MONITOR_HIL", "ft-hil.sh", root)
    cmd = [path, "--pending", "--each"] if path.endswith(".sh") else path.split() + ["--pending", "--each"]
    return cmd_cell(root, at, cmd, path,
                    lambda rc, out, s, at: cell(sum(1 for l in out.splitlines() if l.strip()), s, at)
                    if rc == 0 else unk(s + f" rc={rc}", at))


def blocked_sessions(root, at: str, now: float) -> dict:
    """stall-scan.last.json 팀 중 f ≥ 1 팀 수(diag 팀 셈 0) — 10분 넘게 낡음 = stale · 못 읽음 = unknown."""
    path = state_path(root, ".fable-team/state/stall-scan.last.json", "FT_MONITOR_STALL")
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
        ts = float(doc.get("ts") or 0)
    except (OSError, ValueError, TypeError, UnicodeDecodeError):
        return unk(str(path), at)
    teams = doc.get("teams") or {}
    n = sum(1 for v in teams.values() if isinstance(v, dict) and isinstance(v.get("f"), int) and v["f"] >= 1)
    return cell({"blocked": n, "ts": iso(ts) if ts else None}, str(path), iso(ts) if ts else at,
                stale_q(now, ts, STALE["blocked_sessions"]))


def keeper_unknown(root, at: str, now: float = 0.0) -> dict:
    """keeper 판정 불가 = 장부 줄 중 도구 «ft2-keeper:*» — 장부 자체가 없으면 0(ok) · 꼴 깨짐 = unknown."""
    d = state_path(root, ".fable-team/state/blocks", "FT_MONITOR_BLOCKS")
    owner = d.parent / "blocks-owner.json"
    files = [owner] if owner.is_file() else (sorted(d.glob("*.json")) if d.is_dir() else [])
    if not files:
        return cell({"unknown_keeper": 0}, str(d) + " (장부 없음 — r2072 장부도 0)", at)
    try:
        seen = max(f.stat().st_mtime for f in files)
    except OSError:
        return unk(str(d) + " (장부 못 읽음)", at)
    n = 0
    for f in files:
        try:
            rows = json.loads(f.read_text(encoding="utf-8"))
        except (OSError, ValueError, UnicodeDecodeError):
            return unk(str(f) + " (꼴 다름)", at)
        rows = rows if isinstance(rows, list) else [rows]
        n += sum(1 for r in rows if isinstance(r, dict)
                 and str(r.get("tool") or r.get("by") or "").startswith("ft2-keeper"))
    return cell({"unknown_keeper": n}, str(d), iso(seen), stale_q(now, seen, STALE["keeper_unknown"]))


def planner_check(root, at: str, now: float) -> dict:
    """planner 팀장(seats-planner.json `_master`) «[정리]» 마지막 1통 → N분 전(mailbox.log.jsonl 끝 2000줄)."""
    path = state_path(root, ".fable-team/comm/mailbox.log.jsonl", "FT_MONITOR_MAILLOG")
    seats = state_path(root, ".fable-team/seats-planner.json", "FT_MONITOR_SEATS_PLANNER")
    try:
        master = str(json.loads(seats.read_text(encoding="utf-8")).get("_master") or "")
        lines = path.read_text(encoding="utf-8").splitlines()[-2000:]
    except (OSError, ValueError, UnicodeDecodeError):
        return unk(str(path), at)
    if not master:
        return unk(str(seats) + " (_master 빔)", at)
    stamp = None
    for line in lines:
        try:
            row = json.loads(line)
        except ValueError:
            continue
        if not isinstance(row, dict) or str(row.get("to") or "") != master:
            continue
        head = str(row.get("subject") or (row.get("body") or "").splitlines()[:1][0] if row.get("body") else "")
        if head.startswith("[정리]"):
            stamp = row.get("ts") or stamp
    if stamp is None:
        return unk(str(path) + f" ({master} [정리] 0통)", at)
    try:
        ts = float(stamp)
    except (TypeError, ValueError):
        ts = datetime.fromisoformat(str(stamp)).timestamp()
    return cell({"minutes": int((now - ts) // 60)}, str(path), iso(ts), stale_q(now, ts, STALE["planner_check"]))


def directives(root, at: str) -> dict:
    """`ft-directive-watch.sh status` — 정상 = rc ∈ {0,1} ∧ 첫 줄 «담당 없는 오빠 지시 N · 멈춘 오빠 지시 M» · 둘째 줄 이하 0."""
    path = _cmd("FT_MONITOR_DIRECTIVE", "ft-directive-watch.sh", root)
    cmd = ["python3", path, "status"] if path.endswith(".py") else ["bash", path, "status"]

    def parse(rc, out, s, at):
        first = out.splitlines()[0] if out.splitlines() else ""
        m = DIRECTIVE_LINE.match(first)
        if rc in (0, 1) and m:
            return cell({"no_owner": int(m.group(1)), "stopped": int(m.group(2))}, s, at)
        return unk(s + f" (rc={rc} · 첫 줄 꼴 다름)", at)
    return cmd_cell(root, at, cmd, path, parse)


def collect_fail(root, at: str) -> dict:
    """ft_board.py collect 팀 블록 error = {팀: 사유} — 그 팀 카드가 걸린 골 줄 끝 «<팀> 수집 실패».

    로컬 하네스 호출이라 상한 25초(하드 룰 12 «런타임 7초 · 로컬 하네스 25초») — 실측 10.7초."""
    path = _cmd("FT_MONITOR_BOARD", "ft-board.py", root)
    tmp = root / ".fable-team/state/board/.monitor-collect.json"
    tmp.parent.mkdir(parents=True, exist_ok=True)
    rc, out = run(["python3", path, "collect", "--out", str(tmp)], root, timeout=25)
    if rc is None:
        return unk(path + " collect (25초 초과·도구 없음)", at)
    if rc != 0:
        return unk(path + f" collect rc={rc}", at)
    try:
        doc = json.loads(tmp.read_text(encoding="utf-8"))
    except (OSError, ValueError, UnicodeDecodeError):
        return unk(path + " collect (출력 꼴 다름)", at)
    fails = {t.get("key"): t.get("error") for t in (doc.get("teams") or [])
             if isinstance(t, dict) and t.get("error")}
    return cell(fails, path + " collect 팀 error", at)


def collect_all(root, at: str, now: float) -> dict:
    """11칸 전부 — 한 칸 예외는 그 칸만 unknown(다른 칸·파일 쓰기는 그대로 · 하드 룰 20)."""
    root = Path(root)
    try:
        cards = src_lib.cards(root)
    except Exception as e:  # noqa: BLE001 — 카드 폴더 못 읽음 = 그 두 칸만 unknown
        cards, why = None, f"카드 폴더 못 읽음 {type(e).__name__}"
    out = {}
    for name in CELLS:
        try:
            if name == "goals":
                out[name] = src_lib.goals(root, at, now)
            elif name == "goal_facts":
                out[name] = unk(why, at) if cards is None else src_lib.goal_facts(root, at, cards)
            elif name == "waiting":
                out[name] = unk(why, at) if cards is None else src_lib.waiting(root, at, cards)
            elif name == "oppa_wait":
                out[name] = src_lib.oppa_wait(root, at, now)
            elif name == "blocked_sessions":
                out[name] = blocked_sessions(root, at, now)
            elif name == "planner_check":
                out[name] = planner_check(root, at, now)
            elif name == "keeper_unknown":
                out[name] = keeper_unknown(root, at, now)
            else:
                out[name] = globals()[name](root, at)
        except Exception as e:  # noqa: BLE001 — 칸 격리(조용한 0 금지 → unknown)
            out[name] = unk(f"수집 예외 {type(e).__name__}", at)
    return {name: out[name] for name in CELLS}
