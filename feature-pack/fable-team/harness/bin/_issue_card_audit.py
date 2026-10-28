#!/usr/bin/env python3
"""_issue_card_audit.py — approved 열린 Issue ↔ 팀 카드 «판정» (읽기 전용 · 쓰기 0).

부르는 곳 = ft-issue-card-audit.sh (usage·인자는 그 셸이 갖는다). 출력 글꼴은 _issue_card_audit_out.py.
계약(정본 = design/harness/PLAN-issue-card-audit-20261028.md §2 · 반례 §3):
  연결 = 어떤 카드든 머리(첫 `## ` 앞)의 «- Issue:» 줄에 #N 이 있다
  언급 = 연결 0 이고, 어떤 카드든 본문 어디엔가 #N 이 있다 (그 카드 머리가 다른 이슈를 가리켜도 언급)
  없음 = 둘 다 0
  번호 규칙은 «한 곳» — #N(?![0-9]) (R4: #12 는 #123 에 걸리지 않는다)
  실패 = 호출마다 7초 상한 + 재시도 1 · 2회 실패/시간 초과 = «판정 불가» rc5 · 부분 결과 0 (R6 · R9)
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys

import _issue_card_audit_out as out

HERE = os.path.dirname(os.path.abspath(__file__))
ALIAS_DEFAULT = os.path.join(HERE, "team_aliases.json")

REF_RE = re.compile(r"#(\d+)(?![0-9])")          # 번호 규칙 «한 곳» — R4
ISSUE_LINE_RE = re.compile(r"^\s*[-*]\s*Issue\s*[:：]")
# 카드 경로 두 꼴 — origin/main = design/teams/<팀>/indices/… · ops/main-base = design/<팀>/indices/… (arch#173 반송 r2)
CARD_PATH_RE = re.compile(r"^design/(?:teams/)?[^/]+/indices/(?P<bucket>[^/.][^/]*)/.+\.md$")
FINISHED = ("완성", "아카이브")                   # 닫기 후보 = 연결 카드가 «전부» 여기 (R7)

RC_OK, RC_USAGE, RC_UNJUDGEABLE = 0, 2, 5


class Unjudgeable(Exception):
    """판정 불가 — 한 줄로 보고하고 rc5. 부분 결과를 내지 않는다."""


# ── 외부 호출 (7초 상한 + 재시도 1 · 하드 룰 12 · §2-1 «실패 처리 한 곳») ──
def _timeout_bin():
    for cand in ("timeout", "gtimeout"):
        path = shutil.which(cand)
        if path:
            return path
    raise Unjudgeable("timeout(coreutils) 없음 — 7초 상한을 걸 수 없다")


def _run_once(argv, limit, stdin_text):
    try:
        return subprocess.run(
            [_timeout_bin(), str(limit)] + argv,
            input=stdin_text,
            capture_output=True,
            text=stdin_text is not None,
        )
    except OSError as exc:
        raise Unjudgeable(f"{argv[0]} 실행 실패 — {exc}")


def run(argv, limit, what, stdin_text=None):
    """2회 실패·시간 초과 = Unjudgeable. 성공 = stdout(bytes)."""
    last = ""
    for _ in (1, 2):
        proc = _run_once(argv, limit, stdin_text)
        if proc.returncode == 0:
            data = proc.stdout
            return data if isinstance(data, bytes) else data.encode()
        if proc.returncode == 124:
            last = f"{limit}초 초과"
        else:
            err = proc.stderr
            err = err.decode("utf-8", "replace") if isinstance(err, bytes) else err
            last = next((ln for ln in (err or "").splitlines() if ln.strip()), "")
            last = last or f"rc={proc.returncode}"
    raise Unjudgeable(f"{what} 실패(2회) — {last}")


# ── 입력 ──
def load_issues(path, gh_bin, limit):
    if path:
        try:
            with open(path, encoding="utf-8") as fh:
                data = json.load(fh)
        except (OSError, ValueError) as exc:
            raise Unjudgeable(f"Issue JSON 읽기 실패 {path} — {exc}")
    else:
        raw = run([gh_bin, "issue", "list", "--state", "open", "--limit", "1000",
                   "--json", "number,title,labels"], limit, "gh issue list")
        try:
            data = json.loads(raw.decode("utf-8", "replace"))
        except ValueError as exc:
            raise Unjudgeable(f"gh issue list JSON 파싱 실패 — {exc}")
    if not isinstance(data, list):
        raise Unjudgeable("Issue JSON 이 배열이 아니다")
    issues = []
    for raw in data:
        labels = [(lab.get("name") or "") if isinstance(lab, dict) else str(lab)
                  for lab in (raw.get("labels") or [])]
        issues.append({
            "number": int(raw.get("number") or 0),
            "title": (raw.get("title") or "").strip(),
            "labels": labels,
        })
    return issues


def _blobs(git_bin, repo, shas, limit):
    if not shas:
        return {}
    raw = run([git_bin, "-C", repo, "cat-file", "--batch"], limit,
              "git cat-file --batch", stdin_text="\n".join(shas) + "\n")
    out_map, pos, total = {}, 0, len(raw)
    while pos < total:
        end = raw.find(b"\n", pos)
        if end < 0:
            break
        header = raw[pos:end].decode("utf-8", "replace").strip()
        pos = end + 1
        if not header:
            continue
        parts = header.split()
        if len(parts) != 3 or parts[1] != "blob":
            raise Unjudgeable(f"git cat-file --batch — {header}")
        try:
            size = int(parts[2])
        except ValueError:
            raise Unjudgeable(f"git cat-file --batch 크기 파싱 실패 — {header}")
        out_map[parts[0]] = raw[pos:pos + size]
        pos += size + 1                                   # 본문 뒤 개행 1
    return out_map


def load_cards(git_bin, repo, refs, limit):
    """ref 2개(origin/main · origin/ops/main-base)의 카드. 같은 경로는 1장으로 센다."""
    picked, order = {}, []
    for ref in refs:
        raw = run([git_bin, "-C", repo, "ls-tree", "-r", ref, "--", "design"],
                  limit, f"git ls-tree {ref}")
        for line in raw.decode("utf-8", "replace").splitlines():
            meta, _, path = line.partition("\t")
            fields = meta.split()
            if len(fields) < 3 or fields[1] != "blob":
                continue
            hit = CARD_PATH_RE.match(path)
            if not hit or path in picked:
                continue
            picked[path] = (fields[2], hit.group("bucket"))
            order.append(path)
    texts = _blobs(git_bin, repo, [picked[p][0] for p in order], limit)
    cards = []
    for path in order:
        sha, bucket = picked[path]
        body = texts.get(sha)
        if body is None:
            raise Unjudgeable(f"git cat-file — {path} 본문 없음")
        text = body.decode("utf-8", "replace")
        head = re.split(r"^## ", text, maxsplit=1, flags=re.M)[0]
        issue_lines = [ln for ln in head.splitlines() if ISSUE_LINE_RE.match(ln)]
        cards.append({
            "path": path,
            "bucket": bucket,
            "head_refs": _refs("\n".join(issue_lines)),
            "all_refs": _refs(text),
        })
    return cards


def _refs(text):
    return {int(n) for n in REF_RE.findall(text or "")}


# ── 판정 ──
def audit(issues, cards):
    connected, mentioned = {}, {}
    for card in cards:
        for ref in card["head_refs"]:
            connected.setdefault(ref, []).append(card)
        for ref in card["all_refs"]:
            mentioned.setdefault(ref, []).append(card)
    rows = []
    for issue in issues:
        num = issue["number"]
        conn = connected.get(num, [])
        ment = mentioned.get(num, [])
        if conn:
            status, evidence = "연결", conn
        elif ment:
            status, evidence = "언급만", ment
        else:
            status, evidence = "없음", []
        buckets = []
        for card in evidence:
            if card["bucket"] not in buckets:
                buckets.append(card["bucket"])
        rows.append({
            "number": num,
            "title": issue["title"],
            "labels": issue["labels"],
            "status": status,
            "buckets": buckets,
            "close_candidate": bool(conn) and all(c["bucket"] in FINISHED for c in conn),
        })
    return rows


# ── main ──
def parse_args(argv):
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("--tick", action="store_true")
    ap.add_argument("--table", action="store_true")
    ap.add_argument("--mail")
    ap.add_argument("--all-open", action="store_true")
    ap.add_argument("--from-json")
    ap.add_argument("--repo", default="")
    ap.add_argument("--ref-main", default="origin/main")
    ap.add_argument("--ref-harness", default="origin/ops/main-base")
    return ap.parse_args(argv)


def main(argv):
    args = parse_args(argv)
    if sum(1 for flag in (args.tick, args.table, bool(args.mail)) if flag) != 1:
        print("usage: ft-issue-card-audit.sh <--tick|--table|--mail <팀>> "
              "[--all-open] [--from-json <파일>] [--repo <dir>] "
              "[--ref-main <ref>] [--ref-harness <ref>]", file=sys.stderr)
        return RC_USAGE
    limit = int(os.environ.get("FT_ICA_TIMEOUT_S", "7"))
    git_bin = os.environ.get("FT_ICA_GIT") or "git"
    gh_bin = os.environ.get("FT_ICA_GH") or "gh"
    alias_path = os.environ.get("FT_ICA_ALIAS_FILE") or ALIAS_DEFAULT
    try:
        try:
            aliases = out.load_aliases(alias_path)
        except ValueError as exc:
            raise Unjudgeable(str(exc))
        repo = args.repo or os.getcwd()
        issues = load_issues(args.from_json, gh_bin, limit)
        if not args.all_open:
            issues = [i for i in issues if "approved" in i["labels"]]
        cards = load_cards(git_bin, repo, [args.ref_main, args.ref_harness], limit)
    except Unjudgeable as exc:
        print(f"ISSUE-CARD 판정 불가 — {exc}")
        return RC_UNJUDGEABLE
    rows = audit(issues, cards)
    if args.mail:
        print(out.body_mail(rows, args.mail, repo, aliases))
    elif args.table:
        print(out.line_table(rows, aliases))
    else:
        print(out.line_tick(rows))
    return RC_OK


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
