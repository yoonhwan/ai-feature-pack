#!/usr/bin/env python3
"""_gh_graphql_stub.py — 시험용 gh 대역(로컬) · r1395 이슈 일일 표 쪽 읽기.

부르는 꼴 (가짜 gh 안에서):
    python3 _gh_graphql_stub.py --fixture <시나리오.json> "$@"

하는 일 = gh 인자(argv)를 읽어 «고정 JSON» 1개를 stdout 으로 낸다. 실 GitHub 호출 0 · 네트워크 0 · sleep 0.
  · api graphql + query 에 issues(states:OPEN  → 열린 이슈 1쪽(50건)
  · api graphql + query 에 search(type:ISSUE  → 닫힌(24h) 1쪽(100건)
  · api graphql + query 에 issue(number:$num  → 그 Issue 코멘트 이어 읽기 1쪽(100건)
  · repo view --json owner,name               → {"owner":{"login":…},"name":…}
  · issue list --state open|closed …          → 옛 경로(기준판)용 평면 배열
시간 초과 흉내 = 시나리오 "timeout" 칸의 «남은 횟수» 를 하나 줄이고 exit 124 (고정 sleep 0).

시나리오(JSON) 꼴:
  {"repo": {"owner": "byz", "name": "pack"},
   "open":   {"totalCount": 120, "pages": [[<gh issue list 행>, …], …]},
   "closed": {"issueCount": 250, "pages": [[{"number": 1, "closedAt": "…"}], …]},
   "timeout": {"open:2": 1, "closed:1": 2}}

<gh issue list 행> = {"number","title","labels":[{"name"}],"createdAt","updatedAt","body",
                      "comments":[{"body","createdAt"}]}

모드 = 100644 (실행 비트 없이 python3 로 부른다 · r1305).
"""
from __future__ import annotations

import json
import os
import sys

OPEN = "issues(states:OPEN"
CLOSED = "search(type:ISSUE"
COMMENTS = "issue(number:$num"


def die(msg: str) -> "None":
    print(f"stub: {msg}", file=sys.stderr)
    raise SystemExit(1)


def load(path: str) -> dict:
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        die(f"시나리오를 못 읽었다 {path}: {exc}")
    return data if isinstance(data, dict) else die("시나리오가 객체가 아니다")


def log(argv: list[str]) -> None:
    path = os.environ.get("GH_LOG")
    if path:
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(" ".join(argv) + "\n")


def take_timeout(path: str, key: str) -> bool:
    """시나리오 timeout[key] > 0 이면 1 줄이고 True(이번 호출 = 초과 흉내)."""
    data = load(path)
    table = data.get("timeout")
    if not isinstance(table, dict):
        return False
    left = int(table.get(key) or 0)
    if left <= 0:
        return False
    table[key] = left - 1
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False)
    return True


def args_map(argv: list[str]) -> tuple[str, dict[str, str]]:
    """-f/-F key=value 를 모은다. query 는 따로 돌려준다."""
    query = ""
    fields: dict[str, str] = {}
    i = 0
    while i < len(argv):
        if argv[i] in ("-f", "-F") and i + 1 < len(argv):
            key, _, val = argv[i + 1].partition("=")
            if key == "query":
                query = val
            else:
                fields[key] = val
            i += 2
            continue
        i += 1
    return query, fields


def cursor_page(fields: dict[str, str]) -> int:
    """endCursor 규약 = c<N> (N = 1부터). 없으면 1쪽."""
    raw = str(fields.get("c") or "")
    if raw.startswith("c") and raw[1:].isdigit():
        return max(1, int(raw[1:]))
    return 1


def pages_of(block: object, page: int) -> tuple[list, bool]:
    pages = block.get("pages") if isinstance(block, dict) else None
    pages = pages if isinstance(pages, list) else []
    nodes = pages[page - 1] if page <= len(pages) else []
    nodes = nodes if isinstance(nodes, list) else []
    return nodes, page < len(pages)


def issue_row(row: dict) -> dict:
    """gh issue list 행 → GraphQL Issue node (라벨·코멘트는 1쪽만 + totalCount)."""
    labels = [lab for lab in (row.get("labels") or []) if isinstance(lab, dict)]
    comments = [cm for cm in (row.get("comments") or []) if isinstance(cm, dict)]
    head = comments[:100]
    return {
        "number": int(row.get("number") or 0),
        "title": row.get("title") or "",
        "createdAt": row.get("createdAt") or "",
        "updatedAt": row.get("updatedAt") or "",
        "body": row.get("body") or "",
        "labels": {"totalCount": len(labels), "nodes": [{"name": lab.get("name") or ""} for lab in labels[:50]]},
        "comments": {
            "totalCount": len(comments),
            "pageInfo": {"hasNextPage": len(comments) > 100, "endCursor": "c2" if len(comments) > 100 else ""},
            "nodes": [{"body": cm.get("body") or "", "createdAt": cm.get("createdAt") or ""} for cm in head],
        },
    }


def find_row(data: dict, num: int) -> dict:
    pages = ((data.get("open") or {}).get("pages") or [])
    for page in pages:
        for row in page if isinstance(page, list) else []:
            if isinstance(row, dict) and int(row.get("number") or 0) == num:
                return row
    return {}


def main(argv: list[str]) -> int:
    fixture = ""
    rest: list[str] = []
    i = 0
    while i < len(argv):
        if argv[i] == "--fixture" and i + 1 < len(argv):
            fixture = argv[i + 1]
            i += 2
            continue
        rest.append(argv[i])
        i += 1
    if not fixture:
        die("--fixture <시나리오.json> 필요")
    log(rest)
    data = load(fixture)

    if rest[:2] == ["repo", "view"]:
        repo = data.get("repo") if isinstance(data.get("repo"), dict) else {}
        print(json.dumps({"owner": {"login": repo.get("owner") or "byz"},
                          "name": repo.get("name") or "pack"}))
        return 0

    if rest[:2] == ["issue", "list"]:
        state = rest[rest.index("--state") + 1] if "--state" in rest[:-1] else "open"
        block = data.get(state) or {}
        rows: list = []
        for page in (block.get("pages") or []):
            rows.extend(page if isinstance(page, list) else [])
        print(json.dumps(rows if state == "closed" else rows, ensure_ascii=False))
        return 0

    if rest[:2] != ["api", "graphql"]:
        die(f"모르는 호출 {' '.join(rest)}")

    query, fields = args_map(rest)
    page = cursor_page(fields)
    if OPEN in query:
        if take_timeout(fixture, f"open:{page}"):
            return 124
        block = data.get("open") or {}
        nodes, more = pages_of(block, page)
        conn = {
            "totalCount": int(block.get("totalCount") or 0),
            "pageInfo": {"hasNextPage": more, "endCursor": f"c{page + 1}" if more else ""},
            "nodes": [issue_row(row) for row in nodes if isinstance(row, dict)],
        }
        print(json.dumps({"data": {"repository": {"issues": conn}}}, ensure_ascii=False))
        return 0

    if CLOSED in query:
        if take_timeout(fixture, f"closed:{page}"):
            return 124
        block = data.get("closed") or {}
        nodes, more = pages_of(block, page)
        count = block.get("issueCount")
        if count is None:
            count = sum(len(p) for p in (block.get("pages") or []) if isinstance(p, list))
        conn = {
            "issueCount": int(count),
            "pageInfo": {"hasNextPage": more, "endCursor": f"c{page + 1}" if more else ""},
            "nodes": [{"number": int(r.get("number") or 0), "closedAt": r.get("closedAt") or ""}
                      for r in nodes if isinstance(r, dict)],
        }
        print(json.dumps({"data": {"search": conn}}, ensure_ascii=False))
        return 0

    if COMMENTS in query:
        num = int(fields.get("num") or 0)
        if take_timeout(fixture, f"comments{num}:{page}"):
            return 124
        row = find_row(data, num)
        comments = [cm for cm in (row.get("comments") or []) if isinstance(cm, dict)]
        start = (page - 1) * 100
        nodes = comments[start:start + 100]
        more = start + 100 < len(comments)
        conn = {
            "pageInfo": {"hasNextPage": more, "endCursor": f"c{page + 1}" if more else ""},
            "nodes": [{"body": cm.get("body") or "", "createdAt": cm.get("createdAt") or ""} for cm in nodes],
        }
        print(json.dumps({"data": {"repository": {"issue": {"comments": conn}}}}, ensure_ascii=False))
        return 0

    die("query 에 아는 꼴이 없다")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
