"""status_head — 사람 채널 슬랙 글 맨 앞에 붙는 «카운팅 머리줄» (r1089 · 오빠 지시 2026-10-28).

planner 틱이 30 분마다 갱신하는 TEAM-STATUS.md 첫 줄(`스크립트 N · 인터뷰 N · 막힌 팀 대기 N`)을 그대로 옮긴다.
그 줄이 낡았으면 끝에 ` (낡음 N분)` 을 붙이고(하루를 넘기면 옛 수 대신 `카운팅 확인 불가(낡음)` · r2064), 파일이 없거나 못 읽거나 형식이 다르면 `카운팅 확인 불가(사유)` 를 낸다
— 조용히 빼지 않는다(#0 RULE). 숫자 뒤 «(메모)» 는 받아들인다(r1190). 형식이 깨지면 그 판(mtime)마다 한 번 1행을 쓰는
planner 에게 mbox [경보] 1통을 보낸다(r1190 · 표식 = <루트>/.fable-team/state/status-head-alarm.txt). 슬랙·명부 쓰기 0.
"""
from __future__ import annotations  # mini python 3.9.6 — `float | None` 주석을 문자열로 미뤄 import TypeError 를 막는다

import json
import logging
import os
import re
import subprocess
import time
from pathlib import Path

from post_guard import DEFAULT_ROOT, ROOT_ENV  # 루트 규칙은 한 곳(post_guard)에만 둔다

FILE_ENV = "FT_TEAM_STATUS_FILE"
STALE_ENV = "FT_TEAM_STATUS_STALE_MIN"
DEFAULT_STALE_MIN = 30.0
DAY_CAP_MIN = 1440  # r2064 — 이보다 낡으면 옛 수를 내지 않는다(env 문턱과 무관한 고정 상한)
REL_PATH = Path(".fable-team") / "state" / "planner-tick" / "TEAM-STATUS.md"
SHAPE = re.compile(r"^스크립트 (?:\d+|\?)(?:\([^)\n]*\))? · 인터뷰 (?:\d+|\?)(?:\([^)\n]*\))? · 막힌 팀 대기 (?:\d+|\?)(?:\([^)\n]*\))?(?![\d(])")
# r2390 — 칸 8개 머리 줄(ft_team_status_line.py r2390). 옛 3칸 꼴도 계속 받는다(착지 순서 어느 쪽이든 경보 0).
SHAPE8 = re.compile(
    r"^자율 (?:ON A\d+ [^·\n]+|OFF|\?) · 오빠 답 기다림 (?:\d+|\?)(?:\(가장 오래 [^)\n]*\))?"
    r" · 스크립트 (?:\d+|\?)(?:\([^)\n]*\))? · 막힌 팀 (?:\d+|\?)(?:\([^)\n]*\))?"
    r" · planner \[정리\] (?:\d\d:\d\d\(\d+분 전\)|\?) · 원장 낡음 (?:\d+|\?)(?:\([^)\n]*\))?"
    r" · 오빠 지시 멈춤 (?:\d+|\?) · 담당 없음 (?:\d+|\?)(?![\d(])")
FORM = "스크립트 N · 인터뷰 N · 막힌 팀 대기 N(숫자 뒤 (메모) 허용)"
CANNOT = "카운팅 확인 불가"
ALARM_REL = Path(".fable-team") / "state" / "status-head-alarm.txt"
PLANNER_REL = Path(".fable-team") / "seats-planner.json"
MBOX_REL = Path(".fable-team") / "comm" / "mbox.sh"
ALARM_SEC = 7  # 외부 호출 7초 룰


def path() -> Path:
    """env FT_TEAM_STATUS_FILE 우선 · 없으면 <루트>/TEAM-STATUS.md (루트 = post_guard 와 같은 규칙)."""
    return Path(os.environ.get(FILE_ENV) or (Path(os.environ.get(ROOT_ENV) or DEFAULT_ROOT) / REL_PATH))


def stale_minutes() -> float:
    try:
        return float(os.environ.get(STALE_ENV) or DEFAULT_STALE_MIN)
    except ValueError:
        logging.getLogger(__name__).warning("status_head: %s 값이 숫자 아님 — 기본 %s분", STALE_ENV, DEFAULT_STALE_MIN)
        return DEFAULT_STALE_MIN


def cannot(reason: str, detail: str = "") -> str:
    logging.getLogger(__name__).error("status_head: %s — %s%s", CANNOT, reason, f" · {detail}" if detail else "")
    return f"{CANNOT}({reason})"


def alarm(f: Path, first: str) -> str:
    """형식이 깨진 판(mtime)마다 planner(_master)에게 [경보] 1통. 반환 = 실패 사유(보냄·이미 보낸 판 = "")."""
    root = Path(os.environ.get(ROOT_ENV) or DEFAULT_ROOT)
    mark = root / ALARM_REL
    body = f"[경보] TEAM-STATUS 1행 형식 — {first[:80]} · 꼴: {FORM} 또는 r2390 8칸 꼴"
    try:
        edition = str(f.stat().st_mtime_ns)
        if mark.is_file() and mark.read_text(encoding="utf-8").strip() == edition:
            return ""
        planner = json.loads((root / PLANNER_REL).read_text(encoding="utf-8")).get("_master")
        if not planner:
            return "경보 생략: seats-planner.json _master 비어 있음"
        run = subprocess.run(["bash", str(root / MBOX_REL), "send", planner, "status-head", body],
                             capture_output=True, text=True, timeout=ALARM_SEC)
        if run.returncode != 0:
            return f"경보 실패: mbox rc={run.returncode} {run.stderr.strip()[-160:]}"
        mark.write_text(edition + "\n", encoding="utf-8")
    except (OSError, ValueError, subprocess.TimeoutExpired) as e:
        return f"경보 실패: {e}"
    return ""


def head(now: float | None = None) -> str:
    """머리줄 1줄. now = 초 단위 시각(기본 지금) — 시험이 고정값을 넣는다."""
    f = path()
    try:
        first = f.read_text(encoding="utf-8").splitlines()[0].strip()
        age = ((time.time() if now is None else now) - f.stat().st_mtime) / 60
    except FileNotFoundError:
        return cannot("파일 없음")
    except (OSError, UnicodeDecodeError, IndexError):
        return cannot("읽기 실패")
    if not (SHAPE.match(first) or SHAPE8.match(first)):
        return cannot("형식", alarm(f, first))
    if age > DAY_CAP_MIN:
        return cannot("낡음", f"{int(age)}분")
    return f"{first} (낡음 {int(age)}분)" if age > stale_minutes() else first
