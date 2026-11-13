"""magazine_collect_gh — Issue 열림·닫힘 (설계 §1 자료 #2). gh 읽기 전용.

열림 = 창 안에 «생성»된 Issue(지금 상태 무관) · 닫힘 = 창 안에 «닫힌» Issue.
300건에 닿으면 창을 반으로 나눠 다시 읽고 number 로 합친다(r1374).
1시간 조각도 300건이면 조용히 자르지 않고 raise.
"""
import json
import subprocess
from datetime import datetime, timedelta, timezone

from magazine_window import MagazineError

LIMIT = 300
GH_TIMEOUT = 7  # 하드 룰 12 · 시간 초과는 재시도 1
MIN_SLICE = timedelta(hours=1)
MAX_CALLS = 8  # 목록 하나당 gh 호출 상한(재시도 포함) · 7초×8 ≤ 70초
FIELDS = "number,title,state,url"


def _z(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _run_list(cmd: list[str], query: str, calls: list[int]) -> subprocess.CompletedProcess[str]:
    for _ in range(2):
        if calls[0] >= MAX_CALLS:
            raise MagazineError(f"gh 조각 상한 {MAX_CALLS}회를 넘었어요({query})")
        calls[0] += 1
        try:
            return subprocess.run(cmd, capture_output=True, text=True, timeout=GH_TIMEOUT)
        except subprocess.TimeoutExpired:
            continue
        except OSError as e:
            raise MagazineError(f"gh 실행 실패({query}): {type(e).__name__}") from e
    raise MagazineError(f"gh 실행 실패({query}): TimeoutExpired {GH_TIMEOUT}초 · 재시도 1회 뒤")


def _fetch(gh_repo: str, state: str, query: str, calls: list[int]) -> list[dict[str, object]]:
    cmd = ["gh", "issue", "list", "--repo", gh_repo, "--state", state, "--search", query, "--json", FIELDS, "--limit", str(LIMIT)]
    r = _run_list(cmd, query, calls)
    if r.returncode != 0:
        raise MagazineError(f"gh issue list rc={r.returncode}({query}): {r.stderr.strip()[:200]}")
    try:
        rows = json.loads(r.stdout)
    except ValueError as e:
        raise MagazineError(f"gh 응답이 JSON 이 아니에요({query})") from e
    if not isinstance(rows, list):
        raise MagazineError(f"gh 응답이 JSON 배열이 아니에요({query})")
    return [{k: row.get(k) for k in FIELDS.split(",")} for row in rows]


def _list(gh_repo: str, state: str, kind: str, start: datetime, end: datetime, calls: list[int]) -> list[dict[str, object]]:
    """창이 LIMIT 에 닿으면 반으로 나눠 다시 읽는다. gh 범위는 양끝 포함 → 경계 중복은 number 로 걸러낸다."""
    query = f"{kind}:{_z(start)}..{_z(end)}"
    rows = _fetch(gh_repo, state, query, calls)
    if len(rows) < LIMIT:
        return rows
    half = (end - start) / 2
    if half < MIN_SLICE:
        raise MagazineError(f"gh 결과가 {LIMIT}건에 닿았어요 — 잘린 목록은 쓰지 않아요({query})")
    merged: dict[object, dict[str, object]] = {}
    for part in (_list(gh_repo, state, kind, start, start + half, calls), _list(gh_repo, state, kind, start + half, end, calls)):
        for row in part:
            merged.setdefault(row["number"], row)
    return list(merged.values())


def _last_comment(gh_repo: str, number: int) -> str | None:
    cmd = ["gh", "issue", "view", str(number), "--repo", gh_repo, "--json", "comments"]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=GH_TIMEOUT)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise MagazineError(f"gh 실행 실패(issue view {number}): {type(e).__name__}") from e
    if r.returncode != 0:
        raise MagazineError(f"gh issue view rc={r.returncode}({number}): {r.stderr.strip()[:200]}")
    try:
        comments = json.loads(r.stdout)["comments"]
    except (ValueError, KeyError, TypeError) as e:
        raise MagazineError(f"gh 응답에 comments 가 없어요({number})") from e
    if not isinstance(comments, list) or any(not isinstance(c, dict) or not isinstance(c.get("body"), str) for c in comments):
        raise MagazineError(f"gh comments 모양이 달라요({number})")
    return comments[-1]["body"] if comments else None


def last_comments(gh_repo: str, numbers: list[int]) -> dict[str, str | None]:
    """닫은 이슈마다 마지막 댓글 전문(= 닫는 증거). 댓글이 하나도 없으면 null."""
    return {str(n): _last_comment(gh_repo, n) for n in numbers}


def collect_gh(gh_repo: str, start: datetime, end: datetime) -> dict[str, list[dict[str, object]]]:
    return {
        "issues_opened": _list(gh_repo, "all", "created", start, end, [0]),
        "issues_closed": _list(gh_repo, "closed", "closed", start, end, [0]),
    }
