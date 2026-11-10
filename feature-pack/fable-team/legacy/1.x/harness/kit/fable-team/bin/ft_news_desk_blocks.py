#!/usr/bin/env python3
"""ft_news_desk_blocks — 뉴스 전문의 ①골 표(원장)·②팀별 표(명단·카드 흐름·명부·보드 스냅샷) 블록 재료 (r1055 · 파일 상한 200줄 분리).

각 블록은 «못 읽은 재료 = 그 블록만 확인 불가 1줄» 규칙을 지킨다(빈 표·0 금지 · R2 · R3). 조립·digest·relay = ft_news_desk.py.
env: FT_DESK_LEDGER_FILE · FT_DESK_LEDGER_REF · FT_DESK_LEDGER_TIMEOUT · FT_DESK_GIT(느린 ref 흉내) · FT_CARD_FLOW · FT_DESK_CARD_TIMEOUT
"""
import json
import logging
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from ft_news_status import latest_snapshot  # noqa: E402
from ft_team_lib import TeamPathError, team_rel, team_root, teams_md  # noqa: E402

LOG = logging.getLogger("ft_news_desk")
NO_ENV = "확인 불가(FT_HARNESS_ROOT 없음)"  # r1064 R2: 꼴3 인데 env 가 비면 지도 폴백 대신 이 글자
GOAL = re.compile(r"^##\s+메인 골")
CLOCK = re.compile(r"\b\d{1,2}:\d{2}\b")
TABLE_SEP = re.compile(r"^\|[\s:|-]+\|$")
CARD_NUMS = re.compile(r"대기 (\d+) · 진행 (\d+)")
DOING_CHARS = 40


def _run(cmd: list[str], timeout: float) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise RuntimeError(f"{Path(cmd[0]).name} 실행 실패: {e}") from e


def _timeout(name: str) -> float:
    try:
        return float(os.environ.get(name, "7"))
    except ValueError:
        return 7.0


def _why(e: Exception) -> str:
    return re.sub(r"\s+", " ", str(e)).strip()[:DOING_CHARS]


def ledger_text(root: Path) -> str:
    """원장 본문 — 픽스처 파일(FT_DESK_LEDGER_FILE) 아니면 `git show <ref>:<경로>` 1회(7초). 실패 = RuntimeError."""
    if f := os.environ.get("FT_DESK_LEDGER_FILE"):
        try:
            return Path(f).read_text(encoding="utf-8")
        except OSError as e:
            raise RuntimeError(f"원장 파일 읽기 실패 {f}: {e.strerror}") from e
    repo = os.environ.get("FT_LEDGER_REPO") or (root / ".fable-team" / "LIVE_ROOT").read_text(encoding="utf-8").split("\n")[0].strip()
    rel = os.environ.get("FT_LEDGER_PATH") or "design/teams/planner/PLAN-oppa-ledger.md"
    ref = os.environ.get("FT_DESK_LEDGER_REF") or "origin/main"
    done = _run([os.environ.get("FT_DESK_GIT") or "git", "-C", repo, "show", f"{ref}:{rel}"], _timeout("FT_DESK_LEDGER_TIMEOUT"))
    if done.returncode != 0:
        raise RuntimeError(f"원장 ref 읽기 실패 rc={done.returncode} {done.stderr.strip()[:DOING_CHARS]}")
    return done.stdout


def goal_rows(text: str) -> list[list[str]]:
    """원장 `## 메인 골` 절 첫 표의 데이터 행 — [골, 지금 상태, 닫히려면 남은 것] 그대로(자르기 0 · R1)."""
    lines = text.splitlines()
    start = next((i for i, ln in enumerate(lines) if GOAL.match(ln)), None)
    if start is None:
        raise RuntimeError("원장에 «## 메인 골» 절이 없다")
    rows: list[list[str]] = []
    for ln in lines[start + 1:]:
        if not ln.startswith("|"):
            if rows:
                break
            continue
        cells = [c.strip() for c in ln.strip().strip("|").split("|")]
        if TABLE_SEP.match(ln.strip()) or cells[0].startswith("골"):
            continue
        if len(cells) < 3 or not all(cells[:3]):
            raise RuntimeError(f"원장 골 표 행 칸이 3개가 아니거나 비었다: {ln[:DOING_CHARS]}")
        rows.append(cells)
    if not rows:
        raise RuntimeError("원장 골 표에 행이 없다")
    return rows


def goal_block(root: Path) -> list[str]:
    try:
        rows = goal_rows(ledger_text(root))
    except (RuntimeError, OSError) as e:
        LOG.error("골 표 확인 불가: %s", e)
        return [f"확인 불가 — 원장 골 표를 못 읽었다({_why(e)})"]
    body = [f"| {i} | {c[0]} | {c[1]} | {c[2]} |" for i, c in enumerate(rows, 1)]
    return [f"## 골 {len(rows)}줄 지금 상태", "", "| # | 골 | 지금 상태 | 닫히려면 남은 것 |", "|---|---|---|---|", *body]


def team_list(root: Path) -> list[str]:
    """명단(TEAMS.md) 표의 현역 팀 이름 — 「팀 | 폴더 | 오케 좌석 계열 | 상태」."""
    out: list[str] = []
    for ln in teams_md(root).read_text(encoding="utf-8").splitlines():
        cells = [c.strip() for c in ln.strip().strip("|").split("|")] if ln.startswith("|") else []
        if len(cells) >= 4 and cells[0] != "팀" and not TABLE_SEP.match(ln.strip()) and cells[3] == "현역":
            out.append(cells[0])
    return out


def card_nums(root: Path, team: str, folder: Path | None) -> tuple[str, str, str]:
    """ft-card-flow 1회 = (대기, 진행, 완성). 도구를 못 돌리면 셋 다 «확인 불가»(R3 — 숫자를 지어내지 않는다)."""
    if folder is None:
        return "확인 불가", "확인 불가", "확인 불가"
    tool = os.environ.get("FT_CARD_FLOW") or str(HERE / "ft-card-flow.sh")
    try:
        done = _run(["bash", tool, "--team", team, "--root", str(root), "--dir", str(folder)], _timeout("FT_DESK_CARD_TIMEOUT"))
    except RuntimeError as e:
        LOG.error("%s 카드 숫자 확인 불가: %s", team, e)
        return "확인 불가", "확인 불가", "확인 불가"
    if done.returncode != 0 or not (m := CARD_NUMS.search(done.stdout)):
        LOG.error("%s 카드 숫자 확인 불가: rc=%s %s", team, done.returncode, done.stdout.strip()[:DOING_CHARS])
        return "확인 불가", "확인 불가", "확인 불가"
    try:
        done_n = len([p for p in (folder / "indices" / "완성").iterdir() if p.name.endswith(".md")])
    except OSError as e:
        LOG.error("%s 완성 카드 수 확인 불가: %s", team, e)
        return m[1], m[2], "확인 불가"
    return m[1], m[2], str(done_n)


def open_seats(root: Path, team: str) -> str:
    """명부 열린 좌석 수 = 닫힘(_closed)·대체(_replaced_by)·은퇴(stop-ready·_retired_role) 아닌 행."""
    for name in (f"seats-{team}.json", "seats.json"):
        path = root / ".fable-team" / name
        if not path.is_file():
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as e:
            LOG.error("%s 명부 못 읽음: %s", team, e)
            return "확인 불가"
        if not isinstance(data, dict):
            return "확인 불가"
        rows = [v for k, v in data.items() if not k.startswith("_") and isinstance(v, dict)]
        return str(sum(1 for v in rows if not v.get("_closed") and not v.get("_replaced_by")
                       and not v.get("_retired_role") and v.get("role") not in ("", "stop-ready")))
    return "확인 불가"


def snapshot(root: Path) -> dict[str, dict]:
    """보드 스냅샷(ft_news_status 재료와 같은 한 장) → {팀 key: 그 팀 dict}. 못 읽음 = 빈 dict(«지금 하는 일» 칸이 확인 불가)."""
    try:
        return {t["key"]: t for t in json.loads(latest_snapshot(root)[0].read_text(encoding="utf-8"))["teams"] if t.get("key")}
    except (RuntimeError, OSError, ValueError, KeyError, TypeError) as e:
        LOG.error("보드 스냅샷 확인 불가: %s", e)
        return {}


def _short(title: str) -> str:
    return re.sub(r"\s+", " ", (title or "").split(" — ", 1)[-1]).replace("|", "/")[:DOING_CHARS]


def doing(team: dict | None) -> str:
    if team is None:
        return "보드 스냅샷 없음"
    if team.get("error"):
        return "못 읽음: " + _why(Exception(str(team["error"])))
    cards = [_short(c.get("title", "")) for c in (team.get("progress") or {}).values() if isinstance(c, dict)]
    queue = [_short(c.get("title", "")) for c in (team.get("queue") or []) if isinstance(c, dict)]
    head = "진행: " + " · ".join(c for c in cards[:2] if c) if cards else "진행 카드 없음"
    return head + (f" / 다음 대기: {queue[0]}" if queue and queue[0] else "")


def _needs_env(team: str, root: Path) -> bool:
    """명단 폴더가 꼴3($FT_HARNESS_ROOT 꼴)인데 env 가 비었다 — 뉴스 데몬은 지도로 안 넘어간다(r1064 · R2)."""
    try:
        return team_rel(team, root).startswith(("$FT_HARNESS_ROOT/", "${FT_HARNESS_ROOT}/")) and not os.environ.get("FT_HARNESS_ROOT")
    except (TeamPathError, OSError):
        return False


def team_block(root: Path, snap: dict[str, dict]) -> list[str]:
    try:
        teams = team_list(root)
    except OSError as e:
        LOG.error("팀 명단 확인 불가: %s", e)
        return [f"확인 불가 — 팀 명단을 못 읽었다({_why(e)})"]
    body = []
    for team in teams:
        if _needs_env(team, root):
            LOG.error("%s 카드 숫자 확인 불가: env FT_HARNESS_ROOT 없음(지도 폴백 0)", team)
            body.append(f"| {team} | {doing(snap.get(team))} | {NO_ENV} | {NO_ENV} | {NO_ENV} | {open_seats(root, team)} |")
            continue
        try:
            folder: Path | None = team_root(team, root)
        except (TeamPathError, OSError) as e:
            LOG.error("%s 폴더 확인 불가: %s", team, e)
            folder = None
        wait, doing_n, done_n = card_nums(root, team, folder)
        body.append(f"| {team} | {doing(snap.get(team))} | {wait} | {doing_n} | {done_n} | {open_seats(root, team)} |")
    return ["## 팀별 작업 상황", "",
            "카드 수 = ft-card-flow(대기·진행) + indices/완성 파일 수 · 열린 좌석 = 명부 · «지금 하는 일» = 보드 스냅샷", "",
            "| 팀 | 지금 하는 일 | 대기 | 진행 | 완성 | 열린 좌석 |", "|---|---|---|---|---|---|", *body]

