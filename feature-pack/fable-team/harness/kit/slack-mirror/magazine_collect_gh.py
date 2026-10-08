"""magazine_collect_gh — Issue 열림·닫힘 (설계 §1 자료 #2). gh 읽기 전용.

열림 = 창 안에 «생성»된 Issue(지금 상태 무관) · 닫힘 = 창 안에 «닫힌» Issue.
300건에 닿으면 조용히 자르지 않고 raise.
"""
import json
import subprocess
from datetime import datetime, timezone

from magazine_window import MagazineError

LIMIT = 300
GH_TIMEOUT = 120
FIELDS = "number,title,state,url"


def _z(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _list(gh_repo: str, state: str, query: str) -> list[dict[str, object]]:
    cmd = ["gh", "issue", "list", "--repo", gh_repo, "--state", state, "--search", query, "--json", FIELDS, "--limit", str(LIMIT)]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=GH_TIMEOUT)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise MagazineError(f"gh 실행 실패({query}): {type(e).__name__}") from e
    if r.returncode != 0:
        raise MagazineError(f"gh issue list rc={r.returncode}({query}): {r.stderr.strip()[:200]}")
    try:
        rows = json.loads(r.stdout)
    except ValueError as e:
        raise MagazineError(f"gh 응답이 JSON 이 아니에요({query})") from e
    if not isinstance(rows, list):
        raise MagazineError(f"gh 응답이 JSON 배열이 아니에요({query})")
    if len(rows) >= LIMIT:
        raise MagazineError(f"gh 결과가 {LIMIT}건에 닿았어요 — 잘린 목록은 쓰지 않아요({query})")
    return [{k: row.get(k) for k in FIELDS.split(",")} for row in rows]


def collect_gh(gh_repo: str, start: datetime, end: datetime) -> dict[str, list[dict[str, object]]]:
    span = f"{_z(start)}..{_z(end)}"
    return {
        "issues_opened": _list(gh_repo, "all", f"created:{span}"),
        "issues_closed": _list(gh_repo, "closed", f"closed:{span}"),
    }
