"""ft_desk_head_cells — desk 머리 줄 8칸의 실측 출처 한 곳 (r2390 K1 · K3).

칸마다 출처 1곳 · 외부 호출 7초 · 실패·낡음·꼴 다름 = 그 칸 «?» · 0 은 잰 값이 0 일 때만(조용한 0 금지).
  자율            = ft-autonomy.sh status 첫 줄 → «ON A19 풀자동» | «OFF» | «?»
  오빠 답 기다림  = r2389 ft_board_news_wait.waits(...) 대기 목록 중 답 안 온 장부 줄 수 · 가장 오래 = 그중 가장 이른 등록 시각(시간)
                    한 줄 두 번 세기 0 — 팀장 [HIL] 은 장부에 등록된 줄로만 들어온다(r2389 ⓒ 는 장부 중복을 지우고 남은 것)
  스크립트        = --hil 인자 그대로(r2255 그대로)
  막힌 팀         = stall-scan.last.json teams 중 f ≥ 1(r2255 그대로 · 10분 낡음·없음 = «?»)
  planner [정리]  = mailbox.log.jsonl 끝 2000줄 안 planner 명부 _master 발신 첫 줄 «[정리]» 마지막 1통 → «HH:MM(N분 전)» · 없음 = «?»
  원장 낡음       = 골 진행 원장 시각(ft_board_news.read_md · 2시간 안 = 0)
  오빠 지시 멈춤·담당 없음 = ft-directive-watch.sh status 첫 줄 두 숫자(꼴 다르면 «?»)
출처 글(2행)은 칸마다 «<도구> <잰 HH:MM>» 1구 — 못 잰 칸도 잰 시각을 남긴다(무엇을 못 쟀는지 보이게).
"""
from __future__ import annotations  # mini python 3.9.6

import json
import os
import re
import subprocess
import sys
import time
import types
from pathlib import Path

REL = Path(".fable-team") / "state"
UNKNOWN = "?"
CALL_SEC = 7
STALL_STALE_SEC = 600
LEDGER_FRESH_SEC = 7200
LOG_TAIL = 2000
AUTONOMY = re.compile(r"^\[자율 ON (A[0-9]+)\b")
LEVEL = re.compile(r"·\s*레벨\s+([^·\]]+)")
DIRECTIVE = re.compile(r"^담당 없는 오빠 지시 ([0-9]+) · 멈춘 오빠 지시 ([0-9]+)")
DIGEST = "[정리]"


def hhmm(t: float) -> str:
    return time.strftime("%H:%M", time.localtime(t))


def _run(argv: list, root: Path):
    try:
        return subprocess.run(argv, cwd=str(root), capture_output=True, text=True, timeout=CALL_SEC)
    except (OSError, subprocess.TimeoutExpired):
        return None


def _tool(name: str, root: Path, default: str) -> list:
    exe = os.environ.get(name) or str(Path(__file__).resolve().parent / default)
    return ["bash", exe]


def autonomy(root: Path, now: float) -> tuple:
    """자율 칸 = «ON A<N> <레벨>» | «OFF» | «?» — status 첫 줄만 본다(7초 · rc≠0 = «?»)."""
    where = f"ft-autonomy.sh status {hhmm(now)}"
    r = _run(_tool("FT_DESK_HEAD_AUTONOMY", root, "ft-autonomy.sh") + ["status"], root)
    if r is None or r.returncode != 0:
        return UNKNOWN, where
    head = (r.stdout.splitlines() or [""])[0].strip()
    m, lv = AUTONOMY.match(head), LEVEL.search(head)
    if m:
        return f"ON {m.group(1)} {lv.group(1).strip() if lv else UNKNOWN}", where
    return ("OFF" if head.startswith("[자율 OFF") else UNKNOWN), where


def oppa_wait(root: Path, now: float) -> tuple:
    """«<수>(가장 오래 <N>시간)» — r2389 모듈이 없거나 못 읽으면 «?»(그 모듈 없이 따로 세지 않는다 · K2)."""
    where = f"ft_board_news_wait.waits {hhmm(now)}"
    sys.path.insert(0, os.environ.get("FT_BOARD_NEWS_WAIT_BIN") or str(Path(__file__).resolve().parent))
    try:
        import ft_board_news_wait as w  # r2389 — 이 파일은 대기 세기를 따로 갖지 않는다
        got = w.waits(str(root), [], types.SimpleNamespace(recs=[], err=""), now)
        rows = list(got.get("b") or [])  # 답 안 온 장부 줄 · 팀장 [HIL] 은 장부 등록 줄로 이미 들어 있다
    except Exception:  # 모듈 없음(r2389 미착지) · 꼴 다름 · 깨진 장부 = 판정 불가
        return f"{UNKNOWN}", where
    if got.get("bad") or not isinstance(rows, list):
        return f"{UNKNOWN}", where
    oldest = min([int(x.get("at") or 0) for x in rows if isinstance(x, dict)] or [0])
    hrs = max(0, int((now - oldest) // 3600)) if oldest else 0
    return f"{len(rows)}(가장 오래 {hrs}시간)", where


def stalled(root: Path, now: float) -> tuple:
    """막힌 팀 = stall-scan.last.json teams 중 f ≥ 1 · 10분 넘게 낡음·없음·읽기 실패 = «?»(r2255 그대로)."""
    where = f"stall-scan.last.json {hhmm(now)}"
    p = root / REL / "stall-scan.last.json"
    try:
        d = json.loads(p.read_text(encoding="utf-8"))
        ts, teams = float(d["ts"]), d["teams"]
        if not isinstance(teams, dict) or now - ts > STALL_STALE_SEC:
            return UNKNOWN, where
        return str(sum(1 for t in teams.values()
                       if isinstance(t, dict) and "diag" not in t and (t.get("f") or 0) >= 1)), where
    except (OSError, UnicodeDecodeError, ValueError, KeyError, TypeError):
        return UNKNOWN, where


def planner_digest(root: Path, now: float) -> tuple:
    """planner [정리] = 끝 2000줄 안 planner _master 발신 «[정리]» 마지막 1통 → «HH:MM(N분 전)» · 없음·명부 없음 = «?»."""
    where = f"mailbox.log.jsonl {hhmm(now)}"
    try:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        from ft_board_mail import body_of, lineage
        master = json.loads((root / ".fable-team" / "seats-planner.json").read_text(encoding="utf-8")).get("_master")
        if not isinstance(master, str) or not master:
            return UNKNOWN, where
        log = Path(os.environ.get("FT_TEAM_MAILBOX_LOG") or (root / ".fable-team" / "comm" / "mailbox.log.jsonl"))
        lines = log.read_text(encoding="utf-8").splitlines()[-LOG_TAIL:]
    except (OSError, ValueError, UnicodeDecodeError, ImportError):
        return UNKNOWN, where
    for line in reversed(lines):
        try:
            r = json.loads(line)
        except ValueError:
            return UNKNOWN, where  # 깨진 줄 = 그 출처 판정 불가(#0 RULE)
        if not isinstance(r, dict) or lineage(str(r.get("from") or "")) != lineage(master):
            continue
        try:
            first = body_of(r).strip().splitlines()[0].strip()
            at = time.mktime(time.strptime(str(r["ts"])[:19], "%Y-%m-%dT%H:%M:%S"))
        except (KeyError, IndexError, ValueError, TypeError):
            return UNKNOWN, where
        if first.startswith(DIGEST):
            return f"{hhmm(at)}({max(0, int((now - at) // 60))}분 전)", where
    return UNKNOWN, where


def ledger(root: Path, now: float) -> tuple:
    """원장 낡음 = 골 진행 원장 시각(ft_board_news.read_md) · 2시간 안 = 0 · 시각 모름 = «?»."""
    where = f"ft_board_news.read_md {hhmm(now)}"
    try:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        from ft_board_news import DEFAULT_MD, read_md
        at = read_md(os.environ.get("FT_GOAL_PROGRESS_MD") or DEFAULT_MD, str(root))[2]
        if at is None:
            return UNKNOWN, where
        age = now - at.timestamp()
        return str(0 if age <= LEDGER_FRESH_SEC else int(age // 3600)), where
    except Exception:  # 도구 없음 · 원장 못 읽음 · git 실패
        return UNKNOWN, where


def directive(root: Path, now: float) -> tuple:
    """(담당 없음, 멈춘 오빠 지시) — status 첫 줄 두 숫자 · 꼴 다름·rc3 = 둘 다 «?»."""
    r = _run(_tool("FT_DESK_HEAD_DIRECTIVE", root, "ft-directive-watch.sh") + ["status"], root)
    m = DIRECTIVE.match(((r.stdout.splitlines() if r else None) or [""])[0].strip())
    if r is None or r.returncode not in (0, 1) or not m:
        return UNKNOWN, UNKNOWN
    return m.group(1), m.group(2)


def cells(root: Path, hil: str, now: float) -> list:
    """[ (칸 이름, 칸 값, 출처 구) ] — K1 순서 그대로 8칸."""
    where = f"ft-directive-watch.sh status {hhmm(now)}"
    own, stall = directive(root, now)
    return [
        ("자율", *autonomy(root, now)),
        ("오빠 답 기다림", *oppa_wait(root, now)),
        ("스크립트", hil, "HIL 인자(ft-desk-tick ①)"),
        ("막힌 팀", *stalled(root, now)),
        ("planner [정리]", *planner_digest(root, now)),
        ("원장 낡음", *ledger(root, now)),
        ("오빠 지시 멈춤", stall, where),
        ("담당 없음", own, where),
    ]
