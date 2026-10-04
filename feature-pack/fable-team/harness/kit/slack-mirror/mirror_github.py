"""mirror_github — GitHub Issues 목록 읽기(ETag) + 상태 차이(state-diff)로 «전이 이벤트» 도출.

이벤트 id 에 의존하지 않는다: 목록을 읽어 (번호 → {state, hil}) 와 비교해 전이를 만든다.
발행 전이 4종(D6) = 열림 · 닫힘 · 머지 · hil:needed 라벨 붙음. 나머지 변경은 침묵.
실패(토큰 없음·4xx/5xx·네트워크)는 전부 MirrorError — 조용히 넘기지 않는다(BYZ #0 RULE).
"""
import json
import os
import subprocess
import urllib.error
import urllib.request

import mirror_lib as lib

HIL_LABEL = "hil:needed"
PAGE = 100


def read_token() -> str:
    tok = os.environ.get("GITHUB_MIRROR_TOKEN", "").strip()
    if tok:
        return tok
    env = {k: v for k, v in os.environ.items() if k != "GH_TOKEN"}  # 워크트리 gh 함정
    try:
        r = subprocess.run(["gh", "auth", "token"], capture_output=True, text=True, timeout=15, env=env)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise lib.MirrorError(f"gh auth token 실행 실패: {type(e).__name__}") from e
    if r.returncode != 0 or not r.stdout.strip():
        raise lib.MirrorError("GitHub 토큰 없음 — GITHUB_MIRROR_TOKEN 또는 gh auth login")
    return r.stdout.strip()


def _get(url: str, token: str, etag: str | None = None) -> tuple[int, list[dict[str, object]], str | None]:
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json"}
    if etag:
        headers["If-None-Match"] = etag
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=15) as resp:
            return resp.status, json.loads(resp.read().decode("utf-8")), resp.headers.get("ETag")
    except urllib.error.HTTPError as e:
        if e.code == 304:
            return 304, [], etag
        raise lib.MirrorError(f"GitHub 호출 실패: HTTP {e.code}") from e
    except (urllib.error.URLError, OSError, ValueError) as e:
        raise lib.MirrorError(f"GitHub 호출 실패: {type(e).__name__}") from e


def fetch_issues(api: str, repo: str, token: str, since: str | None, etag: str | None) -> tuple[list[dict[str, object]], str | None]:
    """updated 오름차순 이슈·PR 목록. 첫 쪽이 304 면 ([], etag). since=None 이면 열린 것만(baseline)."""
    base = f"{api}/repos/{repo}/issues?per_page={PAGE}&sort=updated&direction=asc"
    base += f"&state=all&since={since}" if since else "&state=open"
    out: list[dict[str, object]] = []
    new_etag = etag
    page = 1
    while True:
        status, items, got = _get(f"{base}&page={page}", token, etag if page == 1 else None)
        if status == 304:
            return [], etag
        if page == 1:
            new_etag = got
        out += items
        if len(items) < PAGE:
            return out, new_etag
        page += 1


def snapshot(issue: dict[str, object]) -> dict[str, object]:
    pr = issue.get("pull_request")
    merged = isinstance(pr, dict) and bool(pr.get("merged_at"))
    raw = issue.get("labels")
    labels = {str(lb.get("name", "")) for lb in raw if isinstance(lb, dict)} if isinstance(raw, list) else set()
    state = "merged" if merged else str(issue.get("state", "open"))
    return {"state": state, "hil": HIL_LABEL in labels and state == "open", "pr": isinstance(pr, dict)}


def transitions(prev: dict[str, object] | None, cur: dict[str, object]) -> list[str]:
    """이전 스냅샷(없으면 처음 봄) → 발행할 전이 종류(opened|merged|closed|hil). 호출부가 advance 로 한 걸음씩 소비한다."""
    if prev is None:
        return ["opened"]
    kinds = []
    if prev["state"] == "open" and cur["state"] != "open":
        kinds.append("merged" if cur["state"] == "merged" else "closed")
    if cur["hil"] and not prev["hil"]:
        kinds.append("hil")
    return kinds


def advance(prev: dict[str, object] | None, kind: str, cur: dict[str, object]) -> dict[str, object]:
    """kind 를 게시한 뒤의 스냅샷 — 크래시 후 같은 전이를 다시 만들지 않는다."""
    base = dict(prev) if prev else {"state": "open", "hil": False, "pr": cur["pr"]}
    if kind in ("closed", "merged"):
        base.update(state=kind, hil=False)
    elif kind == "hil":
        base["hil"] = True
    return base
