#!/usr/bin/env python3
"""ft_issues_daily.py — r1115 매일 00:10 «이슈 일일 표» (읽기 전용 · 쓰기 0 · 쪽지 2통).

왜 있나: 골 6 «매일 00시 이슈 정리·중복 묶기» 의 00시가 한 번도 «장치» 가 된 적이 없다 — 세션 크론은 승계·재부팅에 사라졌고
야간 검토는 1회성이었다. 이 파일은 launchd 1개(com.byz.ft-issues-daily · 00:10)가 부르는 «읽기 전용» 표 생성기다.
라벨·배정·닫기·코멘트 쓰기 0 · 좌석 열기 0 · press 0. 결정은 사람(planner·issues master)이 아침에 한다.

산출 = <FT_ROOT>/design/teams/issues/daily/TABLE-daily-<YYYYMMDD>.md 1장 + mbox 2통(본문 다름 — FANOUT 가드).
  ① 머리(건수 · 합 검산 · 어제 차이)   ② 정리(24h 열림/닫힘 · 7일+ 정체 · 중복 후보)
  ③ 분류(작성 경로 4종 = ft-issue-classify 재사용)   ④ 우선순위 후보 ⓐⓒⓑⓓⓔ
  ⑤ 팀 배정 후보   ⑥ 닫기 후보(8항 코멘트 확인 · 실행 0)
전부 «후보» 다 — 판정 낱말(확정·승인)을 쓰지 않는다. 쓰기는 사람이 한다.

실패 = «판정 불가» 표 + rc≠0 (하드 룰 20 — 빈 표로 숨김 0) · gh 쪽 호출 = 쪽마다 25초 + 재시도 1 (로컬 하네스 상한 · 판정 4114).
전팀 정지(ft-all-stop.sh check rc≠0)·자원 동결(RESOURCE_FREEZE) 표식이면 «건너뜀(사유)» 표 1장 + 쪽지 1통(빈 표 0).

r1395 (2026-11-06): 열린 이슈를 한 호출(gh issue list --limit 1000 · 7필드)로 읽던 것을 «50건 1쪽 GraphQL cursor» 로 쪼갠다.
  쪽당 상한이 25초라 열린 Issue·코멘트가 늘어도 «7초 초과» 로 판정 불가가 되지 않는다(쪽 수만 는다 · 쪽 상한 40 = 2,000건).
  닫힌(24h) 칸도 search 쪽 읽기(100건) · 합 != issueCount 면 그 칸만 «판정 불가(잘림)».
  코멘트 100개 초과 Issue 만 이어 읽고, 라벨 50개 초과는 «판정 불가». 상한에 닿은 잘린 목록은 쓰지 않는다.

env: FT_ROOT(리포 공용 루트) · FT_NOW(시험 시계 초) · FT_GH(gh 대역) · FT_MBOX_SH · FT_ISSUES_DAILY_DIR(표 폴더)
     FT_ISSUES_DAILY_TIMEOUT_S(기본 25 · 쪽 호출 상한 초) · FT_ISSUES_DAILY_REPO=<owner>/<repo>(시험 고정 · 없으면 gh repo view 1회)
     FT_ISSUES_DAILY_CLASSIFY(cmd) · FT_ALLSTOP · FT_ISSUES_DAILY_NO_SEND=1
rc: 0 정상 · 5 판정 불가 · 2 usage
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
SENDER = "ft-issues-daily"
DAY = 86400.0
LABEL_APPROVED = "approved"
LABEL_PP = "status:proposal-pending"
LABEL_NT = "needs-triage"
STALE_DAYS = 7
OPEN_PAGE = 50          # 열린 이슈 1쪽 = 50건 (쪽당 0.9~2.0초 실측 · 25초의 1/12)
OPEN_MAX_PAGES = 40     # 2,000건 상한 — 넘으면 «판정 불가» (잘린 목록 0)
LABEL_MAX = 50          # 라벨 50개 초과 = 판정 불가 (이어 읽기 경로 없음 · 실측 최대 12개)
COMMENT_PAGE = 100      # 코멘트 1쪽 = 100건
CLOSED_PAGE = 100       # 닫힌(24h) 1쪽 = 100건
CLOSED_MAX_PAGES = 10   # GitHub search 1,000건 상한
CLOSED_MAX = CLOSED_PAGE * CLOSED_MAX_PAGES


class Unjudgeable(RuntimeError):
    """판정 불가 — 표에 «판정 불가» 로 적고 rc≠0 (조용한 0 금지 · 하드 룰 20)."""


# ── 자리·시계 (정본 순서 = ft-penalty.root ①FT_ROOT ②옛 설치 꼴 ③cwd git 공용 루트) ──
def _common(path: Path) -> Path | None:
    try:
        out = subprocess.run(
            ["git", "-C", str(path), "rev-parse", "--path-format=absolute", "--git-common-dir"],
            capture_output=True, text=True, timeout=25,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    line = out.stdout.strip()
    return Path(line).parent if out.returncode == 0 and line else None


def root() -> Path:
    root_env = os.environ.get("FT_ROOT")
    if root_env:
        return Path(root_env)
    if HERE.name == "bin" and HERE.parent.name == ".fable-team":
        return _common(HERE) or HERE.parent.parent
    common = _common(Path.cwd())
    if common and (common / ".fable-team").is_dir():
        return common
    sys.exit("ERROR 리포 공용 루트를 못 풂 — FT_ROOT 없음 · cwd 가 .fable-team/ 있는 git 리포 아님")


def now() -> float:
    return float(os.environ.get("FT_NOW") or time.time())


def limit_s() -> int:
    try:
        return max(1, int(os.environ.get("FT_ISSUES_DAILY_TIMEOUT_S") or 25))
    except ValueError:
        return 25


# ── 외부 호출: 쪽마다 25초 상한 + 재시도 1 (하드 룰 12 로컬 하네스 · 실패 처리 한 곳) ──
def _timeout_bin() -> str:
    for cand in ("timeout", "gtimeout"):
        found = shutil.which(cand)
        if found:
            return found
    raise Unjudgeable("timeout(coreutils) 없음 — 7초 상한을 걸 수 없다")


def run(argv: list[str], what: str, limit: int | None = None) -> bytes:
    lim = str(limit or limit_s())
    last = ""
    for _ in (1, 2):
        try:
            proc = subprocess.run([_timeout_bin(), lim] + argv, capture_output=True)
        except OSError as exc:
            raise Unjudgeable(f"{what} 실행 실패 — {exc}")
        if proc.returncode == 0:
            return proc.stdout
        if proc.returncode == 124:
            last = f"{lim}초 초과"
        else:
            err = proc.stderr.decode("utf-8", "replace")
            last = next((ln for ln in err.splitlines() if ln.strip()), "") or f"rc={proc.returncode}"
    raise Unjudgeable(f"{what} 실패(2회) — {last}")


# ── 입력 (r1395: 50건 1쪽 GraphQL cursor · 쪽마다 25초 + 재시도 1) ──
OPEN_QUERY = (
    "query($o:String!,$r:String!,$n:Int!,$c:String){"
    "repository(owner:$o,name:$r){issues(states:OPEN,first:$n,after:$c,"
    "orderBy:{field:CREATED_AT,direction:ASC}){totalCount pageInfo{hasNextPage endCursor}"
    "nodes{number title createdAt updatedAt body "
    "labels(first:50){totalCount nodes{name}} "
    "comments(first:100){totalCount pageInfo{hasNextPage endCursor} nodes{body createdAt}}}}}}"
)
COMMENTS_QUERY = (
    "query($o:String!,$r:String!,$num:Int!,$n:Int!,$c:String){"
    "repository(owner:$o,name:$r){issue(number:$num){"
    "comments(first:$n,after:$c){pageInfo{hasNextPage endCursor} nodes{body createdAt}}}}}"
)
CLOSED_QUERY = (
    "query($q:String!,$n:Int!,$c:String){"
    "search(type:ISSUE,query:$q,first:$n,after:$c){issueCount pageInfo{hasNextPage endCursor}"
    "nodes{... on Issue{number closedAt}}}}"
)

_REPO: dict[str, tuple[str, str]] = {}


def _err_text(errors: object) -> str:
    if isinstance(errors, list) and errors:
        first = errors[0]
        if isinstance(first, dict):
            return str(first.get("message") or first)[:200]
        return str(first)[:200]
    return str(errors)[:200]


def _graphql(gh: str, query: str, fields: list[tuple[str, str]], what: str) -> dict:
    """gh api graphql 1회 (run() 경유 = 25초 상한 + 재시도 1) · data 칸을 돌려준다.
    쪽마다 «PAGE <무엇> <초>s» 1줄을 stderr 에 낸다(launchd 로그 · 쪽당 25초 안인지 사람이 본다)."""
    argv = [gh, "api", "graphql", "-f", f"query={query}"]
    for key, val in fields:
        argv += ["-F", f"{key}={val}"]
    started = time.monotonic()
    try:
        raw = run(argv, what)
    finally:
        print(f"PAGE {what} {time.monotonic() - started:.1f}s", file=sys.stderr)
    try:
        data = json.loads(raw.decode("utf-8", "replace"))
    except ValueError as exc:
        raise Unjudgeable(f"{what} JSON 파싱 실패 — {exc}")
    if not isinstance(data, dict):
        raise Unjudgeable(f"{what} 응답이 객체가 아니다")
    if data.get("errors"):
        raise Unjudgeable(f"{what} 오류 — {_err_text(data['errors'])}")
    got = data.get("data")
    if not isinstance(got, dict):
        raise Unjudgeable(f"{what} 응답에 data 칸이 없다")
    return got


def _repo(gh: str) -> tuple[str, str]:
    """owner·name 1회 조회(+캐시) — 시험은 FT_ISSUES_DAILY_REPO 로 고정한다."""
    fixed = os.environ.get("FT_ISSUES_DAILY_REPO") or ""
    owner, _, name = fixed.partition("/")
    if owner and name:
        return owner, name
    if gh in _REPO:
        return _REPO[gh]
    raw = run([gh, "repo", "view", "--json", "owner,name"], "gh repo view")
    try:
        data = json.loads(raw.decode("utf-8", "replace"))
    except ValueError as exc:
        raise Unjudgeable(f"gh repo view JSON 파싱 실패 — {exc}")
    if not isinstance(data, dict):
        raise Unjudgeable("gh repo view 응답이 객체가 아니다")
    owner_obj = data.get("owner")
    owner = str(owner_obj.get("login") or "") if isinstance(owner_obj, dict) else ""
    name = str(data.get("name") or "")
    if not owner or not name:
        raise Unjudgeable("gh repo view — owner·name 없음")
    _REPO[gh] = (owner, name)
    return owner, name


def _comments_rest(gh: str, owner: str, name: str, num: int, got: list[dict], info: dict,
                   want: int) -> list[dict]:
    """코멘트 100개 초과분 이어 읽기(쪽마다 25초 + 재시도 1). 다 못 읽으면 판정 불가."""
    out = list(got)
    cursor = str(info.get("endCursor") or "")
    page = 1
    while info.get("hasNextPage") and len(out) < want:
        page += 1
        if page > OPEN_MAX_PAGES:
            raise Unjudgeable(f"#{num} 코멘트 {want}건 이어 읽기 {OPEN_MAX_PAGES}쪽 초과")
        fields = [("o", owner), ("r", name), ("num", str(num)), ("n", str(COMMENT_PAGE))]
        if cursor:
            fields.append(("c", cursor))
        data = _graphql(gh, COMMENTS_QUERY, fields, f"gh api graphql #{num} 코멘트 {page}쪽")
        repo = data.get("repository") or {}
        issue = (repo.get("issue") if isinstance(repo, dict) else None) or {}
        conn = (issue.get("comments") if isinstance(issue, dict) else None) or {}
        if not isinstance(conn, dict):
            raise Unjudgeable(f"#{num} 코멘트 {page}쪽 — comments 칸이 없다")
        out.extend(c for c in (conn.get("nodes") or []) if isinstance(c, dict))
        info = conn.get("pageInfo") or {}
        nxt = str(info.get("endCursor") or "")
        if info.get("hasNextPage") and (not nxt or nxt == cursor):
            break
        cursor = nxt
    if len(out) < want:
        raise Unjudgeable(f"#{num} 코멘트 {want}건 중 {len(out)}건만 읽었다 — 잘린 목록은 쓰지 않는다")
    return out


def _page_row(gh: str, owner: str, name: str, node: dict) -> dict:
    """GraphQL node 1개 → gh issue list --json 꼴 1행 (라벨 잘림 = 판정 불가 · 코멘트는 이어 읽기)."""
    num = int(node.get("number") or 0)
    labels_obj = node.get("labels") if isinstance(node.get("labels"), dict) else {}
    lab_total = int(labels_obj.get("totalCount") or 0)
    if lab_total > LABEL_MAX:
        raise Unjudgeable(f"#{num} 라벨 {LABEL_MAX}개 초과 — 잘린 목록은 쓰지 않는다")
    labels = []
    for lab in labels_obj.get("nodes") or []:
        label = (lab.get("name") if isinstance(lab, dict) else str(lab)) or ""
        if label:
            labels.append({"name": label})
    cm_obj = node.get("comments") if isinstance(node.get("comments"), dict) else {}
    comments = [c for c in (cm_obj.get("nodes") or []) if isinstance(c, dict)]
    want = int(cm_obj.get("totalCount") or 0)
    if want > len(comments):
        info = cm_obj.get("pageInfo") if isinstance(cm_obj.get("pageInfo"), dict) else {}
        comments = _comments_rest(gh, owner, name, num, comments, info, want)
    return {
        "number": num,
        "title": node.get("title") or "",
        "labels": labels,
        "createdAt": node.get("createdAt") or "",
        "updatedAt": node.get("updatedAt") or "",
        "body": node.get("body") or "",
        "comments": [{"body": c.get("body") or "", "createdAt": c.get("createdAt") or ""}
                     for c in comments],
    }


def gh_open(gh: str) -> tuple[bytes, list[dict], int]:
    """열린 이슈 = 50건 1쪽 GraphQL cursor 쪽 읽기.
    반환 = (gh issue list --json 꼴 bytes · 정규화 이슈 · 첫 쪽 totalCount). 쪽 하나라도 실패 = 판정 불가."""
    owner, name = _repo(gh)
    rows: list[dict] = []
    seen: set[int] = set()
    total: int | None = None
    cursor = ""
    page = 0
    while True:
        page += 1
        if page > OPEN_MAX_PAGES:
            raise Unjudgeable(f"열린 Issue {OPEN_MAX_PAGES * OPEN_PAGE:,}건 초과 — 쪽 수 상한 {OPEN_MAX_PAGES}")
        fields = [("o", owner), ("r", name), ("n", str(OPEN_PAGE))]
        if cursor:
            fields.append(("c", cursor))
        data = _graphql(gh, OPEN_QUERY, fields, f"gh api graphql {page}쪽")
        repo = data.get("repository") or {}
        conn = (repo.get("issues") if isinstance(repo, dict) else None) or {}
        if not isinstance(conn, dict):
            raise Unjudgeable(f"gh api graphql {page}쪽 — issues 칸이 없다")
        if total is None:
            total = int(conn.get("totalCount") or 0)
        for node in conn.get("nodes") or []:
            if not isinstance(node, dict):
                continue
            row = _page_row(gh, owner, name, node)
            num = int(row.get("number") or 0)
            if num in seen:      # 쪽 사이 중복(읽는 사이 새 이슈·순서 이동)은 1번만 셈
                continue
            seen.add(num)
            rows.append(row)
        info = conn.get("pageInfo") or {}
        if not info.get("hasNextPage"):
            break
        nxt = str(info.get("endCursor") or "")
        if not nxt or nxt == cursor:
            raise Unjudgeable(f"쪽 넘김 실패 — {page}쪽 endCursor 없음")
        cursor = nxt
    raw = json.dumps(rows, ensure_ascii=False).encode("utf-8")
    return raw, [norm_issue(r) for r in rows], (total or 0)


def gh_closed_24h(gh: str, now_ts: float, date_arg: str) -> tuple[list[int] | None, str]:
    """닫힌(24h) = search 쪽 읽기(100건 1쪽) · 합 != issueCount 면 (None, "잘림") — 그 칸만 판정 불가."""
    pairs: list[tuple[int, float | None]] = []
    try:
        owner, name = _repo(gh)
        since = datetime.fromtimestamp(now_ts - DAY, timezone.utc).strftime("%Y-%m-%dT%H:%M")
        query = f"repo:{owner}/{name} is:issue is:closed closed:>={since}"
        count: int | None = None
        cursor = ""
        page = 0
        while True:
            page += 1
            if page > CLOSED_MAX_PAGES:
                return None, "잘림"
            fields = [("q", query), ("n", str(CLOSED_PAGE))]
            if cursor:
                fields.append(("c", cursor))
            data = _graphql(gh, CLOSED_QUERY, fields, f"gh api graphql 닫힌 {page}쪽")
            conn = data.get("search") or {}
            if not isinstance(conn, dict):
                return None, f"{page}쪽 search 칸 없음"
            if count is None:
                count = int(conn.get("issueCount") or 0)
            for row in conn.get("nodes") or []:
                if not isinstance(row, dict):
                    continue
                num = int(row.get("number") or 0)
                if num:
                    pairs.append((num, _epoch(row.get("closedAt"))))
            info = conn.get("pageInfo") or {}
            if not info.get("hasNextPage"):
                break
            nxt = str(info.get("endCursor") or "")
            if not nxt or nxt == cursor:
                return None, "쪽 넘김 실패"
            cursor = nxt
        if count is None or len(pairs) != count or count > CLOSED_MAX:
            return None, "잘림"      # 상한·대조 불일치 = 잘린 목록을 쓰지 않는다
    except (Unjudgeable, ValueError, TypeError):
        return None, "gh 호출 실패"
    out = sorted({n for n, stamp in pairs if n and stamp is not None and now_ts - stamp < DAY})
    return out, ""


def _epoch(text: object) -> float | None:
    if not isinstance(text, str) or not text.strip():
        return None
    try:
        return datetime.fromisoformat(text.strip().replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def norm_issue(raw: dict) -> dict:
    labels = []
    for lab in raw.get("labels") or []:
        name = (lab.get("name") if isinstance(lab, dict) else str(lab)) or ""
        if name:
            labels.append(name)
    comments = []
    for cm in raw.get("comments") or []:
        if isinstance(cm, dict) and isinstance(cm.get("body"), str):
            comments.append(cm["body"])
    return {
        "n": int(raw.get("number") or 0),
        "title": re.sub(r"\s+", " ", str(raw.get("title") or "")).strip(),
        "labels": labels,
        "created": _epoch(raw.get("createdAt")),
        "updated": _epoch(raw.get("updatedAt")),
        "body": str(raw.get("body") or ""),
        "comments": comments,
    }


# ── 칸 계산 ──
def bucket(issue: dict) -> str:
    """한 이슈 = 한 칸 (합 검산이 닫히게 순서 고정): 라벨 없음 → approved → proposal-pending → needs-triage → 그 밖."""
    labels = issue["labels"]
    if not labels:
        return "none"
    if LABEL_APPROVED in labels:
        return "approved"
    if LABEL_PP in labels:
        return "pp"
    if LABEL_NT in labels:
        return "nt"
    return "other"


def norm_title(title: str) -> str:
    text = re.sub(r"\[[^\]]*\]", " ", title.lower())          # [v65] 같은 머리꼬리 제거
    text = re.sub(r"[^0-9a-z가-힣]+", "", text)
    return text


def duplicates(issues: list[dict]) -> list[list[int]]:
    groups: dict[str, list[int]] = {}
    for it in issues:
        key = norm_title(it["title"])
        if key:
            groups.setdefault(key, []).append(it["n"])
    return [sorted(ns) for ns in groups.values() if len(ns) > 1]


def priority_axis(issue: dict, stale: bool) -> str:
    """ⓐ 오빠 지시·priority → ⓒ proposal-pending → ⓑ bug+재현 → ⓓ 7일+ 정체 → ⓔ 나머지.
    ⓒ 를 ⓑ 앞에 두는 이유: proposal-pending 은 «게이트 앞» 이라 어느 목록에도 안 실려 묻힌다(판정 2776 · #3807)."""
    labels = issue["labels"]
    if any(lab.startswith("priority:") or lab in ("from:oppa", "from:member") for lab in labels):
        return "ⓐ"
    if LABEL_PP in labels:
        return "ⓒ"
    if "type:bug" in labels and re.search(r"재현", issue["body"] or ""):
        return "ⓑ"
    if stale:
        return "ⓓ"
    return "ⓔ"


TEAM_HINTS = (
    ("v65", ("v65",)),
    ("issues", ("이슈", "issue")),
    ("planner", ("플래너", "planner", "판정")),
    ("knowledge", ("매거진", "magazine", "지식")),
    ("harness", ("하네스", "launchd", "ft-", "biolark")),
)


def team_hint(issue: dict) -> tuple[str, str]:
    """⑤ 팀 배정 후보 — team:* 라벨이 없을 때만. 라벨 쓰기 0 · 결정 = planner/issues master."""
    for lab in issue["labels"]:
        if lab.startswith("team:"):
            return "", ""
    hay = f"{issue['title']}\n{issue['body'][:2000]}".lower()
    for team, words in TEAM_HINTS:
        for word in words:
            if word.lower() in hay:
                return team, f"제목·본문 키워드 «{word}»"
    return "", ""


CLOSE_ITEMS = ("닫는 사건", "PR", "재현 PASS", "정리", "기록")
_LINE = r"^\s*[-*]?\s*(\[[ xX]\]\s*)?{k}\s*[:：]\s*[^<\s]"


def _has_item(comments: list[str], key: str) -> bool:
    rx = re.compile(_LINE.format(k=re.escape(key)))
    return any(rx.search(ln) for body in comments for ln in body.splitlines())


def _pick_last(comments: list[str], key: str) -> str:
    rx = re.compile(_LINE.format(k=re.escape(key)))
    found = [ln.strip() for body in comments for ln in body.splitlines() if rx.search(ln)]
    if not found:
        return ""
    tail = re.sub(r"^\s*[-*]?\s*(\[[ xX]\]\s*)?" + re.escape(key) + r"\s*[:：]\s*", "", found[-1])
    return tail.strip()


def close_candidate(issue: dict) -> tuple[bool, str]:
    """⑥ 닫기 후보 = 8항이 «코멘트로» 다 있는 것 (실행 0 · 여기서 닫지 않는다).
    실행 판정 정본 = ft-issue-close-check.sh (design/harness/ISSUE-TRANSITIONS.md §3) — 이 칸은 «후보» 만 고른다."""
    comments = issue["comments"]
    if not comments:
        return False, ""
    missing = [k for k in CLOSE_ITEMS if not _has_item(comments, k)]
    if missing:
        return False, f"빠진 항목: {','.join(missing)}"
    canon = [_pick_last(comments, "정본"), _pick_last(comments, "정본 영향 없음")]
    if not (_has_item(comments, "정본") or _has_item(comments, "정본 영향 없음")):
        return False, "빠진 항목: 정본"
    if not any(canon):
        return False, "정본 칸이 빈 줄"
    cause = _pick_last(comments, "원인 확정")
    if not re.match(r"^[Yy]\s*[—–-]+\s*\S", cause):
        return False, f"원인 확정={cause or '없음'}"
    hold = _pick_last(comments, "같은 증상 보류")
    if not re.match(r"^0\s*$", hold):
        return False, f"같은 증상 보류={hold or '없음'}"
    return True, "8항 코멘트 확인"


def classify(issues_raw: bytes, root_dir: Path) -> dict | None:
    """③ 작성 경로 4종 — ft-issue-classify.sh --from-json 재사용(규칙 재작성 0). 실패 = None(그 칸 «판정 불가»)."""
    script = Path(os.environ.get("FT_ISSUES_DAILY_CLASSIFY") or HERE / "ft-issue-classify.sh")
    if not script.is_file() or not shutil.which("jq"):
        return None
    tmp = None
    try:
        with tempfile.NamedTemporaryFile("wb", suffix=".json", delete=False) as fh:
            fh.write(issues_raw)
            tmp = Path(fh.name)
        proc = subprocess.run([_timeout_bin(), "20", "bash", str(script), "--from-json", str(tmp)],
                              capture_output=True, text=True)
        if proc.returncode != 0:
            return None
        line = next((ln for ln in reversed(proc.stdout.splitlines()) if ln.startswith("SUMMARY ")), "")
    except (OSError, subprocess.SubprocessError):
        return None
    finally:
        if tmp is not None:
            tmp.unlink(missing_ok=True)
    if not line:
        return None
    return {m.group(1): int(m.group(2)) for m in re.finditer(r"(①|②|③|④|미분류)=(\d+)", line)}


# ── 정지·동결 표식 ──
def guard(root_dir: Path) -> str:
    state = root_dir / ".fable-team/state"
    if (state / "RESOURCE_FREEZE").exists():
        return "자원 동결 표식(RESOURCE_FREEZE)"
    allstop = os.environ.get("FT_ALLSTOP") or str(HERE / "ft-all-stop.sh")
    if not Path(allstop).is_file():
        return ""
    proc = subprocess.run([_timeout_bin(), "20", "bash", allstop, "check"], capture_output=True)
    if proc.returncode != 0:
        return "전팀 정지(ALL_STOP)"
    return ""


# ── 표 ──
def table_path(root_dir: Path, date: str) -> Path:
    base = Path(os.environ.get("FT_ISSUES_DAILY_DIR") or root_dir / "design/teams/issues/daily")
    return base / f"TABLE-daily-{date}.md"


def read_yesterday(root_dir: Path, date: str) -> dict | None:
    prev = (datetime.strptime(date, "%Y%m%d") - timedelta(days=1)).strftime("%Y%m%d")
    path = table_path(root_dir, prev)
    if not path.is_file():
        return None
    text = path.read_text(encoding="utf-8", errors="replace")
    head = re.search(r"열린 총수:\s*(\d+)", text)
    return {"date": prev, "open": int(head.group(1)) if head else None}


def build(issues: list[dict], closed24: list[int] | None, cls: dict | None, yday: dict | None,
          now_ts: float, date: str, total_count: int | None = None,
          closed_note: str = "") -> tuple[str, dict]:
    stamp = datetime.fromtimestamp(now_ts).strftime("%Y-%m-%d %H:%M")
    counts = {"approved": 0, "pp": 0, "nt": 0, "none": 0, "other": 0}
    for it in issues:
        counts[bucket(it)] += 1
    total = len(issues)
    new24 = sorted(it["n"] for it in issues if it["created"] is not None and now_ts - it["created"] < DAY)
    stale = [it for it in issues if it["updated"] is not None and now_ts - it["updated"] >= STALE_DAYS * DAY]
    stale.sort(key=lambda it: it["updated"] or 0)
    dups = duplicates(issues)
    stale_ids = {id(it) for it in stale}
    axes: dict[str, list[dict]] = {"ⓐ": [], "ⓑ": [], "ⓒ": [], "ⓓ": [], "ⓔ": []}
    for it in issues:
        axes[priority_axis(it, id(it) in stale_ids)].append(it)
    team_rows = [it for it in issues if team_hint(it)[0]]
    close_rows = [(it, why) for it, why in ((it, close_candidate(it)[1]) for it in issues) if close_candidate(it)[0]]
    type_labeled = sum(1 for it in issues if any(lab.startswith("type:") for lab in it["labels"]))
    team_labeled = sum(1 for it in issues if any(lab.startswith("team:") for lab in it["labels"]))
    neither = sum(1 for it in issues
                  if not any(lab.startswith(("type:", "team:")) for lab in it["labels"]))

    line: list[str] = []
    add = line.append
    add(f"# 이슈 일일 표 — {stamp} (일일 장치 · launchd com.byz.ft-issues-daily · 00:10)")
    add("")
    add("장치가 쓴 표다. 라벨·배정·닫기·코멘트 쓰기 0 — 결정은 사람(planner · issues master)이 한다.")
    add(f"스냅샷: 열린 이슈 {total}건 · 닫힌(24h) {len(closed24) if closed24 is not None else '판정 불가'}건")
    add("")
    add("## ① 머리")
    add("")
    add(f"- 열린 총수: {total}")
    add(f"- 상태별: approved {counts['approved']} · status:proposal-pending {counts['pp']}"
        f" · needs-triage {counts['nt']} · 라벨 없음 {counts['none']} · 그 밖 {counts['other']}")
    add(f"- 합: {counts['approved']}+{counts['pp']}+{counts['nt']}+{counts['none']}+{counts['other']} = {total}"
        + (f" · totalCount={total_count}" if total_count is not None else "")
        + " (한 이슈 = 한 칸 · approved → proposal-pending → needs-triage → 라벨 없음 → 그 밖 순서 첫 일치)")
    if yday and yday.get("open") is not None:
        delta = total - int(yday["open"])
        add(f"- 어제 대비: +{len(new24)} −{len(closed24) if closed24 is not None else 0}"
            f" · 열린 총수 {yday['open']}→{total} ({delta:+d}) · 어제 표 TABLE-daily-{yday['date']}.md")
    else:
        add("- 어제 대비: 차이: 첫 표")
    add("")
    add("## ② 정리")
    add("")
    add(f"- 새로 열린(24h): {len(new24)}건{' ' + short_nums(new24) if new24 else ''}")
    if closed24 is None:
        add(f"- 닫힌(24h): 판정 불가({closed_note}) — 그 칸만")
    else:
        add(f"- 닫힌(24h): {len(closed24)}건{' ' + short_nums(closed24) if closed24 else ''}")
    add(f"- 7일+ 정체(갱신일 기준): {len(stale)}건"
        + (" " + " ".join(f"#{it['n']}({(now_ts - (it['updated'] or now_ts)) / DAY:.0f}일)" for it in stale[:20])
           if stale else ""))
    if dups:
        add(f"- 중복 후보(제목 정규화 같음): {sum(len(g) * (len(g) - 1) // 2 for g in dups)}쌍 "
            + " · ".join(" ≈ ".join(f"#{n}" for n in g[:3]) for g in dups[:10]))
    else:
        add("- 중복 후보(제목 정규화 같음): 0쌍")
    add("")
    add("## ③ 분류")
    add("")
    if cls is None:
        add("- 작성 경로: 판정 불가 (ft-issue-classify 실패)")
    else:
        add(f"- 작성 경로: ① 기획 세션 {cls.get('①', 0)} · ② 세션 에이전트 {cls.get('②', 0)}"
            f" · ③ 오빠 GitHub {cls.get('③', 0)} · ④ 사내 멤버 {cls.get('④', 0)} · 미분류 {cls.get('미분류', 0)}")
    add(f"- 라벨: type:* {type_labeled}건 · team:* {team_labeled}건 · 둘 다 없음 {neither}건")
    add("")
    add("## ④ 우선순위 후보 (규칙 고정 · 쓰기 0 · 결정 = planner)")
    add("")
    add("축 순서 ⓐ → ⓒ → ⓑ → ⓓ → ⓔ · ⓒ(proposal-pending)를 ⓑ 앞에 두는 이유 = 게이트 앞이라 어느 목록에도 안 실려 묻힌다(판정 2776).")
    add("")
    add("| # | 축 | 제목 | 근거 |")
    add("|---|---|---|---|")
    for axis in ("ⓐ", "ⓒ", "ⓑ", "ⓓ", "ⓔ"):
        for it in axes[axis]:
            add(f"| #{it['n']} | {axis} | {cell(it['title'])} | {axis_why(it, axis, stale)} |")
    if total == 0:
        add("| — | — | 열린 이슈 0 | — |")
    add("")
    add("축별: " + " · ".join(f"{a} {len(axes[a])}" for a in ("ⓐ", "ⓑ", "ⓒ", "ⓓ", "ⓔ")))
    add("")
    add("## ⑤ 팀 배정 후보 (team:* 라벨 없는 것만 · 배정 쓰기 0)")
    add("")
    if team_rows:
        add("| # | 팀 후보 | 근거 |")
        add("|---|---|---|")
        for it in team_rows:
            team, why = team_hint(it)
            add(f"| #{it['n']} | {team}(후보) | {cell(why)} |")
    else:
        add("- 없음 (team:* 없는 이슈에 키워드 근거 0 — 에이전트·planner 가 직접 분류)")
    add("")
    add("## ⑥ 닫기 후보 (8항 코멘트 확인 · 실행 0 · 번호만)")
    add("")
    if close_rows:
        for it, _why in close_rows:
            add(f"- #{it['n']} {cell(it['title'])}")
    else:
        add("- 없음")
    add("")
    add("## 장치가 하지 않은 것")
    add("")
    add("- 라벨 부여·배정·닫기·코멘트 쓰기 0 · 좌석 열기 0 · press 0")
    add("- 카드 대조 = ft-issue-card-audit.sh --tick (이 표 밖 · ref 읽기라 표 시간 상한에 안 넣는다)")
    add("- 닫기 8항 실제 판정 = ft-issue-close-check.sh <#> (정본 design/harness/ISSUE-TRANSITIONS.md §3)")
    counts_out = dict(counts, total=total, stale=len(stale), dups=len(dups),
                      close=len(close_rows), team=len(team_rows), new24=len(new24),
                      closed24=len(closed24) if closed24 is not None else -1)
    return "\n".join(line) + "\n", counts_out


def cell(text: str) -> str:
    return re.sub(r"\s+", " ", text).replace("|", "/")[:70] or "—"


def short_nums(nums: list[int]) -> str:
    return " ".join(f"#{n}" for n in nums[:20]) + (" …" if len(nums) > 20 else "")


def axis_why(issue: dict, axis: str, stale: list[dict]) -> str:
    if axis == "ⓐ":
        hit = [lab for lab in issue["labels"] if lab.startswith("priority:") or lab in ("from:oppa", "from:member")]
        return f"라벨 {','.join(hit)}"
    if axis == "ⓒ":
        return f"라벨 {LABEL_PP} (게이트 앞)"
    if axis == "ⓑ":
        return "라벨 type:bug + 본문 재현"
    if axis == "ⓓ":
        return "갱신 7일+"
    return "위 축 아님"


def skip_table(why: str, date: str, now_ts: float) -> tuple[str, dict]:
    stamp = datetime.fromtimestamp(now_ts).strftime("%Y-%m-%d %H:%M")
    body = "\n".join([
        f"# 이슈 일일 표 — {stamp} (일일 장치 · launchd com.byz.ft-issues-daily · 00:10)",
        "",
        f"## 건너뜀 — {why}",
        "",
        "- 이 회차는 표를 만들지 않았다(빈 표 아님 · 사유를 적는다).",
        "- 해제 뒤 다음 00:10 회차가 표를 쓴다 · 급하면 `ft-issues-daily.sh --date <YYYYMMDD>` 를 손으로 1회.",
        "",
    ])
    return body, {"skipped": why}


def unjudgeable_table(why: str, date: str, now_ts: float) -> tuple[str, dict]:
    stamp = datetime.fromtimestamp(now_ts).strftime("%Y-%m-%d %H:%M")
    body = "\n".join([
        f"# 이슈 일일 표 — {stamp} (일일 장치 · launchd com.byz.ft-issues-daily · 00:10)",
        "",
        "## 판정 불가",
        "",
        f"- 원인: {why}",
        "- 열린 이슈를 못 읽어 표를 만들지 못했다 — 0건으로 적지 않는다(하드 룰 20).",
        "- 다음 회차 = 내일 00:10 · 급하면 `ft-issues-daily.sh --date <YYYYMMDD>` 를 손으로 1회.",
        "",
    ])
    return body, {"unjudgeable": why}


# ── 쪽지 ──
def roster_master(root_dir: Path, team: str) -> str:
    path = root_dir / ".fable-team" / ("seats.json" if team == "v65" else f"seats-{team}.json")
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return ""
    if not isinstance(doc, dict):
        return ""
    master = doc.get("_master")
    if isinstance(master, str) and master.strip():
        return master.strip()
    best, best_n = "", -1
    for name, row in doc.items():
        if name.startswith("_") or not isinstance(row, dict):
            continue
        if row.get("role") != "master" or row.get("_replaced_by"):
            continue
        tail = name.rsplit("#", 1)[-1]
        num = int(tail) if tail.isdigit() else 0
        if num > best_n:
            best, best_n = name, num
    return best


def mail(mbox: str, to: str, body: str) -> int:
    if not to:
        print(f"WARN {SENDER}: 받는 좌석을 못 찾음 — 쪽지 0 ({body.splitlines()[0][:60]})", file=sys.stderr)
        return 1
    argv = ["bash", mbox, "send", to, SENDER, body, "--urgent"]
    try:
        proc = subprocess.run([_timeout_bin(), "30"] + argv, capture_output=True, text=True)
    except (OSError, subprocess.SubprocessError) as exc:
        print(f"WARN {SENDER}: 쪽지 실패 {to} — {exc}", file=sys.stderr)
        return 1
    if proc.returncode != 0:
        tail = next((ln for ln in proc.stderr.splitlines() if ln.strip()), f"rc={proc.returncode}")
        print(f"WARN {SENDER}: 쪽지 실패 {to} — {tail}", file=sys.stderr)
    return proc.returncode


def planner_body(date: str, note: str, counts: dict) -> str:
    if "skipped" in counts or "unjudgeable" in counts:
        why = counts.get("skipped") or counts.get("unjudgeable")
        return (f"[{'건너뜀' if 'skipped' in counts else '판정 불가'}] 00시 이슈 표 {date} — {why}\n"
                f"표: design/teams/issues/daily/TABLE-daily-{date}.md\n"
                "다음: 사유 해제 뒤 다음 00:10 회차 · 급하면 ft-issues-daily.sh 손 1회")
    return (f"[완료] 00시 이슈 표 {date} — 열린 {counts['total']}"
            f"(approved {counts['approved']} · proposal-pending {counts['pp']} · 라벨 없음 {counts['none']})"
            f" · 7일+ {counts['stale']} · 중복 후보 {counts['dups']} · 닫기 후보 {counts['close']} · 팀 후보 {counts['team']}\n"
            "골좌표: A6 이슈 관리 ⑥ «00시 정리 첫 실행 RESULT 1회» — 이 표 1장이 그 RESULT\n"
            f"표: design/teams/issues/daily/TABLE-daily-{date}.md{note}")


def issues_body(date: str, counts: dict) -> str:
    if "skipped" in counts or "unjudgeable" in counts:
        why = counts.get("skipped") or counts.get("unjudgeable")
        return (f"[{'건너뜀' if 'skipped' in counts else '판정 불가'}] 00시 이슈 표 {date} — {why}\n"
                f"표: design/teams/issues/daily/TABLE-daily-{date}.md · 집행 0")
    return (f"[완료] 00시 이슈 표 {date} — 열린 {counts['total']} · 닫기 후보 {counts['close']}"
            f" · 팀 후보 {counts['team']} · 7일+ {counts['stale']}\n"
            "집행 3줄: 1) 닫기 후보는 ft-issue-close-check.sh <#> 실행 뒤 닫기 2) 팀 후보는 team:* 라벨 부여 3) 7일+ 정체는 우선순위 재판정\n"
            f"표: design/teams/issues/daily/TABLE-daily-{date}.md (열 이름·규칙 = GUIDE-issues.md §일일 표)")


# ── main ──
def main(argv: list[str]) -> int:
    dry = False
    date = None
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--dry-run":
            dry = True
            i += 1
        elif arg == "--date" and i + 1 < len(argv):
            date = argv[i + 1]
            i += 2
        else:
            print("usage: ft-issues-daily.sh [--dry-run] [--date YYYYMMDD]", file=sys.stderr)
            return 2
    now_ts = now()
    date = date or datetime.fromtimestamp(now_ts).strftime("%Y%m%d")
    if not re.fullmatch(r"\d{8}", date):
        print(f"usage: --date 는 YYYYMMDD 8자리 (받은 값 {date})", file=sys.stderr)
        return 2
    root_dir = root()
    target = table_path(root_dir, date)
    gh = os.environ.get("FT_GH") or "gh"
    mbox = os.environ.get("FT_MBOX_SH") or str(root_dir / ".fable-team/comm/mbox.sh")
    send_planned = not dry and os.environ.get("FT_ISSUES_DAILY_NO_SEND") != "1"

    why = guard(root_dir)
    rc = 0
    counts: dict = {}
    if why:
        text, counts = skip_table(why, date, now_ts)
    else:
        try:
            raw, issues, total_count = gh_open(gh)
        except Unjudgeable as exc:
            text, counts = unjudgeable_table(str(exc), date, now_ts)
            rc = 5
        else:
            closed24, closed_note = gh_closed_24h(gh, now_ts, date)
            cls = classify(raw, root_dir)
            text, counts = build(issues, closed24, cls, read_yesterday(root_dir, date), now_ts, date,
                                 total_count, closed_note)

    if dry:
        sys.stdout.write(text)
        print(f"DRY 표={target} 쪽지 0 · 판정={'정상' if rc == 0 else '판정 불가'}", file=sys.stderr)
        return rc
    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")
    except OSError as exc:
        print(f"ERROR {SENDER}: 표 쓰기 실패 {target} — {exc}", file=sys.stderr)
        return 1
    print(f"TABLE {target}")
    if rc != 0:
        print(f"ERROR {SENDER}: 판정 불가 — {counts.get('unjudgeable', '')}", file=sys.stderr)
    if send_planned:
        body_args = [k for k in counts if k in ("skipped", "unjudgeable")]
        targets = [("planner", planner_body(date, "", counts))]
        if not body_args:   # R6·R7: 건너뜀·판정 불가 = 쪽지 «1통» (planner) · FANOUT 가드도 2통 본문이 다를 때만 통과
            targets.append(("issues", issues_body(date, counts)))
        bad = 0
        for team, body in targets:
            bad += mail(mbox, roster_master(root_dir, team), body) != 0
        print(f"MAIL sent={len(targets) - bad} failed={bad}")
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
