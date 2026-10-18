#!/usr/bin/env bash
# test_slack_mirror_signature.sh — 판정 442 재발 감시: 슬랙 미러 둘이 «조용히 죽는» 두 경로를 잡는다.
#  ① github 미러 _item 이 현행 mirror_lib.format_row 시그니처로 TypeError 없이 텍스트를 만든다(슬랙 post 0 · 네트워크 0)
#  ② mbox 미러 좌석 정규식 기본값(install.sh)이 현역 planner 이름 byz-planner-master-claude#N 을 매칭한다
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="${SLACK_MIRROR_KIT:-$HERE/../../harness/kit/slack-mirror}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

[ -d "$KIT" ] && ok "kit dir exists" || { bad "kit dir missing: $KIT"; exit 1; }

# ① github 미러 _item — 요약 성공·요약 실패·HIL 세 경로 모두 TypeError 0
out="$(python3 - "$KIT" <<'PYEOF' 2>&1
import argparse, sys, tempfile, textwrap
from pathlib import Path

kit = sys.argv[1]
sys.path.insert(0, kit)
import byz_github_slack_mirror as g

tmp = Path(tempfile.mkdtemp())
(tmp / "sum.py").write_text(textwrap.dedent("""\
    import sys
    p = sys.stdin.read()
    if "SUMFAIL" in p:
        sys.exit(1)
    print('{"what": "무슨 일이에요", "todo": null}')
"""), encoding="utf-8")
a = argparse.Namespace(repo="o/r", mention="U0AC2JF0M7D", summarizer_cmd=f"{sys.executable} {tmp / 'sum.py'}", summary_timeout=10.0)
m = g.GithubMirror.__new__(g.GithubMirror)  # 생성자의 토큰·네트워크 경로를 타지 않는다
m.a = a

def issue(n, title, pr=False):
    d = {"number": n, "title": title, "html_url": f"https://github.com/o/r/{'pull' if pr else 'issues'}/{n}"}
    if pr:
        d["pull_request"] = {}
    return d

def need(label, text, *parts):
    for p in parts:
        if p not in text:
            print(f"MISSING[{label}] {p!r} in {text!r}")
            sys.exit(1)

ok = m._item(issue(7, "새 이슈"), "opened")
need("opened", ok["text"], "↳ 이어가기 · Issue #7", "담당 github", "(github #7 opened)", "링크: https://github.com/o/r/issues/7")
need("opened-what", ok["text"], "무슨 일이에요")
fb = m._item(issue(8, "SUMFAIL 요약 실패 경로"), "closed")
need("summary-fail", fb["text"], "(원문 그대로)", "(github #8 closed)")
hil = m._item(issue(9, "판정 필요", pr=True), "hil")
need("hil", hil["text"], "<@U0AC2JF0M7D>", "결정 자리:", "다음: 결정 대기", "(github #9 hil)", "링크: https://github.com/o/r/pull/9")
print("ITEM_OK")
PYEOF
)"
echo "$out" | tail -1 | grep -qx 'ITEM_OK' && ok "github _item: opened·summary-fail·hil 텍스트 생성(TypeError 0)" || bad "github _item: $(echo "$out" | tail -4 | tr '\n' ';')"

# ② 좌석 정규식 — install.sh 기본값을 그대로 꺼내 쓴다(복사본이 아니라 실물을 시험)
out="$(python3 - "$KIT/install.sh" <<'PYEOF' 2>&1
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'^SEAT="\$\{MIRROR_SEAT:-(.*?)\}"', src, re.M)
if not m:
    print("NO_DEFAULT")
    sys.exit(1)
pat = re.compile(m.group(1).replace("\\$", "$"))
for name in ("byz-planner-master-claude#11", "byz-planner-master-claude#0", "byz-planner-arch#3"):
    if not pat.search(name):
        print(f"NOMATCH {name} /{pat.pattern}/")
        sys.exit(1)
for name in ("byz-cfo-master-claude#53", "byz-harness-master-claude#16", "byz-planner-master-claude#", "xbyz-planner-master-claude#1", "byz-planner-master-claude#1x"):
    if pat.search(name):
        print(f"FALSE_MATCH {name} /{pat.pattern}/")
        sys.exit(1)
print("SEAT_OK")
PYEOF
)"
echo "$out" | tail -1 | grep -qx 'SEAT_OK' && ok "seat default: planner-master-claude#11 · 옛 arch#3 매칭, 무관 이름 비매칭" || bad "seat default: $out"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
