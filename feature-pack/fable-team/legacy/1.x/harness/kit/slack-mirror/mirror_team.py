"""mirror_team — 글 1건이 «어느 팀 · 어느 날»의 뿌리 글로 가는가 (판정 623 · 카드 설계 1·2).

날짜 = KST 08:00 경계(매거진 창과 같음). 팀 = 이슈 키 `#N` 은 GitHub 라벨 `team:<x>`, 좌석 키 `byz-<팀>-…` 는 이름의 팀 칸.
라벨 조회 실패 = stderr ERROR + `기타`(조용한 누락 0 · 캐시하지 않아 다음 글에서 다시 조회).
"""
import json
import re
import sys
import time
from collections.abc import Callable
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import NamedTuple

import mirror_lib as lib

TEAMS = ("cfo", "harness", "issues", "feature", "ops", "loom", "v65")  # 메인 팀 7 — 뿌리 글 요약(planner)이 한눈에 묶는 대상
PLANNER = "planner"
MAIN_TEAMS_LABEL = "오늘 메인 팀 7 한눈에"
OTHER = lib.OTHER_KEY
ALIAS = {"shared-harness": "harness", "harness-ops": "harness"}
NO_LABEL = "팀 라벨 없음"
KST = timezone(timedelta(hours=9))
CACHE_MAX = 2000


class Route(NamedTuple):
    team: str
    day: str
    note: str  # 「팀 라벨 없음」 또는 ""

    @property
    def post_key(self) -> str:
        return f"team:{self.team}:{self.day}"

    @property
    def planner_key(self) -> str:
        return f"team:{PLANNER}:{self.day}"

    @property
    def root_keys(self) -> tuple[str, ...]:
        return (self.post_key,) if self.team == PLANNER else (self.post_key, self.planner_key)


def day_of(epoch: float) -> str:
    return (datetime.fromtimestamp(epoch, KST) - timedelta(hours=8)).strftime("%Y-%m-%d")


def hhmm(epoch: float) -> str:
    return datetime.fromtimestamp(epoch, KST).strftime("%H:%M")


def team_from_labels(labels: list[str]) -> str | None:
    """None = team 라벨 자체가 없음. 있는데 목록 밖(ccu·kk 등 위성)이면 `기타`."""
    names = [lb[5:] for lb in labels if lb.startswith("team:")]
    for n in names:
        n = ALIAS.get(n, n)
        if n in TEAMS or n == PLANNER:
            return n
    return OTHER if names else None


def seat_team(key: str) -> str:
    m = re.match(r"byz-([a-z0-9]+)-", key)
    if m and (m.group(1) in TEAMS or m.group(1) == PLANNER):
        return m.group(1)
    return PLANNER if key == OTHER else OTHER  # `기타` 키(GAP 등) = planner


class IssueTeams:
    """이슈 번호 → 팀. 캐시 파일(키 = 번호)은 라벨을 찾았을 때만 쓴다."""

    def __init__(self, cache_path: Path, fetch: Callable[[int], list[str]] | None):
        self.path, self.fetch = cache_path, fetch

    def _load(self) -> dict[str, str]:
        try:
            return {str(k): str(v) for k, v in dict(json.loads(self.path.read_text(encoding="utf-8"))).items()}
        except FileNotFoundError:
            return {}
        except (ValueError, OSError) as e:
            raise lib.MirrorError(f"이슈 팀 캐시 읽기 실패: {self.path} ({type(e).__name__})") from e

    def _remember(self, n: int, team: str) -> None:
        cache = self._load()
        if cache.get(str(n)) == team:
            return
        cache.pop(str(n), None)
        cache[str(n)] = team
        lib.save_state(self.path, dict(list(cache.items())[-CACHE_MAX:]))

    def team(self, n: int, labels: list[str] | None = None) -> tuple[str, str]:
        if labels is None:
            hit = self._load().get(str(n))
            if hit:
                return hit, ""
            try:
                labels = self.fetch(n) if self.fetch else []
            except lib.MirrorError as e:
                print(f"ERROR: 이슈 #{n} 라벨 조회 실패: {e} — 기타 뿌리 글로 보냄(다음 글에서 다시 조회)", file=sys.stderr)
                return OTHER, ""
        team = team_from_labels(labels)
        if team is None:
            return OTHER, NO_LABEL
        self._remember(n, team)
        return team, ""


class Router:
    def __init__(self, issues: IssueTeams, clock: Callable[[], float] = time.time):
        self.issues, self.clock = issues, clock

    def route(self, item: dict[str, object]) -> Route:
        key = str(item.get("key", OTHER))
        m = re.fullmatch(r"#(\d+)", key)
        labels = item.get("labels")
        team, note = self.issues.team(int(m.group(1)), list(labels) if isinstance(labels, list) else None) if m else (seat_team(key), "")
        return Route(team, day_of(self.clock()), note)


def add_args(p, github_api: bool = True) -> None:
    p.add_argument("--team-roots", action="store_true", help="글을 이슈별 뿌리 글이 아니라 «팀·날짜» 뿌리 글 아래 스레드로 올린다(판정 623)")
    if github_api:
        p.add_argument("--github-api", default="https://api.github.com")


def build(a, token: str, threads_path: Path, gh_token: str | None = None):
    """--team-roots 일 때만 TeamRoots 를 만든다(없으면 None = 지금 동작 그대로). 인자 부족은 raise."""
    if not getattr(a, "team_roots", False):
        return None
    import mirror_github as gh
    import mirror_team_roots as tr
    if not a.repo:
        raise lib.MirrorError("--team-roots 는 --repo 가 필요해요(라벨 조회)")
    state = Path(a.state_dir)
    tok = gh_token or gh.read_token()
    issues = IssueTeams(state / "byz_issue_team.json", lambda n: gh.fetch_labels(a.github_api, a.repo, tok, n))
    return tr.TeamRoots(state, a.api_base, token, a.channel, Router(issues))
