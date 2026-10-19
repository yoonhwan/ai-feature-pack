"""magazine_goal — 아침 매거진(오빠 확인판)에 자율 골 표(A6)를 싣는 문 (R362 · magazine_doc.py 가 부른다).

골 표 = ft-goal-table.sh render 출력(마커 2줄 사이 표) — 뿌리 글 첫 줄 바로 뒤 + HTML 맨 위 절. 판정은 ft-goal-table.sh check --block-only(판정기 하나).
팀별 완성 진행 = ft-goal-table.sh teams 출력(R458) — 골 표 바로 뒤 · 없거나 실패 = WARN + 빈 글(무장이어도 거절 0 · 골 표 게이트만 그대로).
무장 표식 = <FT_ROOT>/.fable-team/state/goal-gate.armed — 있으면 렌더·판정 실패 = GoalGateError(MirrorError 계열 → magazine_doc.main 의 «발행 실패» 경로 1개 · 게시·상태 쓰기 0) ·
없으면 WOULD-REJECT 한 줄(state/mbox-guard-goal.log)만 남기고 골 표 없이 진행(설치 전환 · 되돌림 = 표식 삭제).
env: FT_ROOT(magazine_from_news.sh 가 필수로 준다) · FT_GOAL_TABLE(판정기 경로 · 기본 <FT_ROOT>/.fable-team/bin/ft-goal-table.sh). 외부 호출 0(로컬 스크립트 1회 · 7초 상한).
"""
import html
import logging
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path

from mirror_lib import MirrorError

LOG = logging.getLogger("magazine_goal")
LIMIT_S = 7


class GoalGateError(MirrorError):
    pass


def _root() -> Path:
    root = os.environ.get("FT_ROOT")
    if not root:
        raise GoalGateError("FT_ROOT 없음 — 골 표 판정기 위치를 알 수 없다")
    return Path(root)


def armed() -> bool:
    return bool(os.environ.get("FT_ROOT")) and (Path(os.environ["FT_ROOT"]) / ".fable-team" / "state" / "goal-gate.armed").is_file()


def _run(*args: str, text: str | None = None) -> str:
    tool = Path(os.environ.get("FT_GOAL_TABLE") or _root() / ".fable-team" / "bin" / "ft-goal-table.sh")
    if not tool.is_file():
        raise GoalGateError(f"골 표 판정기 없음 {tool}")
    try:
        done = subprocess.run(["bash", str(tool), *args], input=text, capture_output=True, text=True, encoding="utf-8", timeout=LIMIT_S, check=False)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise GoalGateError(f"골 표 판정기 실행 실패: {e}") from e
    if done.returncode != 0:
        raise GoalGateError(f"골 표 판정기 rc={done.returncode}: {(done.stdout + done.stderr).strip()[:200]}")
    return done.stdout


def block() -> str:
    """골 표 블록(마커 2줄 포함) — 무장이면 실패 = raise · 아니면 WOULD-REJECT 로그 + 빈 글."""
    try:
        got = _run("render")
        _run("check", "-", "--block-only", text=got)
        return got.strip("\n")
    except GoalGateError as e:
        if armed():
            _log(f"REJECT magazine {str(e)[:200]}")
            _notify(str(e))
            raise
        LOG.warning("골 표 없이 진행(비무장): %s", e)
        _log(f"WOULD-REJECT magazine {str(e)[:200]}")
        return ""


def teams_block() -> str:
    """팀별 완성 진행 블록(마커 2줄 포함 · R458) — 실패·표 없음 = WARN + 빈 글(발행 거절 0)."""
    try:
        return _run("teams").strip("\n")
    except GoalGateError as e:
        LOG.warning("팀별 완성 진행 없이 진행: %s", e)
        return ""


def _notify(why: str) -> None:
    """무장 거절 → planner [긴급] 1통(ft-goal-table.sh notify · 10분 중복 억제). 통지 실패는 로그만 — 거절(발행 0)은 이미 났다."""
    try:
        tool = Path(os.environ.get("FT_GOAL_TABLE") or _root() / ".fable-team" / "bin" / "ft-goal-table.sh")
        subprocess.run(["bash", str(tool), "notify", str(_root()), "magazine", why], capture_output=True, check=False, timeout=LIMIT_S * 3)
    except (OSError, subprocess.TimeoutExpired, GoalGateError) as e:
        LOG.warning("planner 거절 알림 실패: %s", e)


def _log(line: str) -> None:
    root = os.environ.get("FT_ROOT")
    if not root:
        return
    try:
        state = Path(root) / ".fable-team" / "state"
        state.mkdir(parents=True, exist_ok=True)
        with (state / "mbox-guard-goal.log").open("a", encoding="utf-8") as f:
            f.write(f"{datetime.now(timezone.utc):%Y-%m-%dT%H:%M:%SZ} {line}\n")
    except OSError as e:
        LOG.warning("골 표 문 로그 쓰기 실패: %s", e)


def with_root(first_line_rest: str, goal: str) -> str:
    """뿌리 글 본문 — 첫 줄은 그대로(find_root 가 첫 줄 «정확 일치» 로 찾는다) · 골 표는 그 바로 뒤."""
    head, _, rest = first_line_rest.partition("\n")
    return "\n".join(x for x in (head, goal, rest) if x)


def html_section(goal: str) -> str:
    """HTML 맨 위 절 — 표 원문 그대로(이스케이프) · 골 표가 없으면 빈 글."""
    return f"<h2>자율 골 표</h2>\n<pre>{html.escape(goal)}</pre>" if goal else ""
