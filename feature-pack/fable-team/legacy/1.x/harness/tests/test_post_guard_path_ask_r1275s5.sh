#!/usr/bin/env bash
# test_post_guard_path_ask_r1275s5.sh — r1275 단계 5: 오빠가 경로를 달라 한 글에 답할 때만 post_guard 묶음2 의 abs-path·worktree-path 2칸 면제.
# W1~W9 + 변이 2. 슬랙·네트워크·실 토큰 0 — post 는 대역(기록만) · 수신 원장·명부는 임시 폴더 · 자기 재호출 0(mutant 는 python 만 다시 돌린다).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="${R1275S5_KIT:-$HERE/../kit/slack-mirror}"   # 기준판 대조용 덮어쓰기
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/root/.fable-team"
printf '{"_slack_channel": "CHUMAN"}\n' > "$TMP/root/.fable-team/seats-x.json"

cat > "$TMP/scn.py" <<'PY'
import argparse, json, os, sys
sys.path.insert(0, sys.argv[1])
tmp = sys.argv[2]
os.environ.update(FT_ROOT=f"{tmp}/root", FT_SLACK_INBOUND_LEDGER=f"{tmp}/ledger.json", FT_SLACK_ANSWERED=f"{tmp}/ans.json",
                  BYZ_DESK_CHANNEL="CDESK", FT_APPROVAL_GATE_REPOS="")
import post_guard as pg
import thread_reply_slack as tr
posts = []
pg.post = lambda base, token, channel, text, thread_ts=None: (posts.append((channel, text)) or f"1800000000.{len(posts):06d}")
pg.with_status_head = lambda text: text
tr.root_text = lambda *a: "오빠 글 뿌리"
PATH = "경로는 /Users/yoonhwan/Project/x/.worktrees/y 입니다"
ASK = "오빠(Slack) 발화 (추정: 열린 질문 없음) — 원문:\n폴더주소 풀패스 알려줘"

def reply(entry, body):
    json.dump({"ledger": {"1793752389.718629": entry}}, open(f"{tmp}/ledger.json", "w"), ensure_ascii=False)
    a = argparse.Namespace(to_slack="1793752389.718629", channel="CHUMAN", left=None, asked=1, answered=1)
    t = argparse.Namespace(base="http://x", token="t")
    n = len(posts)
    try:
        tr.reply_to_slack(a, t, body)
        return "posted" if len(posts) > n else "none"
    except pg.PostGuardError as e:
        return str(e)

def res(name, cond, why=""):
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else f" — {why}"))

r = reply({"thread": "1793750142.429419", "text": ASK}, PATH)
res("W1 경로 요청 글 · 답에 경로 → 게시 통과", r == "posted", r)
try:
    pg.guarded_post("b", "t", "CHUMAN", PATH, None, human=True); r = "posted"
except pg.PostGuardError as e:
    r = str(e)
res("W2 오빠 글 답 아님(allow 없음) → 지금처럼 거부 abs-path·worktree-path", "묶음2:abs-path" in r and "묶음2:worktree-path" in r, r)
r = reply({"thread": "1", "text": "오빠(Slack) 발화 — 원문:\n진행 상황?"}, PATH)
res("W3 경로 요청 아님 → 거부", "묶음2:abs-path" in r, r)
r = reply({"thread": "1", "text": ASK}, PATH + " byz-planner-desk-claude#3")
res("W4 경로 요청 · 좌석 이름 섞임 → seat-name 만 거부", "묶음2:seat-name" in r and "abs-path" not in r and "worktree-path" not in r, r)
r = reply({"thread": "1", "text": ASK}, PATH + " xoxb-123")
res("W5 경로 요청 · 토큰 → 묶음1 거부", "묶음1:slack-token" in r, r)
r1, r2, r3 = reply({"thread": "1"}, PATH), reply({"thread": "1", "text": ""}, PATH), reply({"thread": "1", "text": 7}, PATH)
res("W6 원장 text 없음·빔·문자열 아님 → 면제 0", all("묶음2:abs-path" in x for x in (r1, r2, r3)), (r1, r2, r3))
try:
    pg.check("x", "CHUMAN", human=True, allow=frozenset({"cost"})); r = "no error"
except ValueError as e:
    r = "ValueError"
res("W7 allow 가 경로 두 칸 밖(cost) → ValueError", r == "ValueError", r)
try:
    pg.check("비용 $5 /Users/a", "CHUMAN", human=True); r = "no error"
except pg.PostGuardError as e:
    r = str(e)
res("W8 allow 기본값 → 지금 판정(cost·abs-path 거부)", "묶음2:cost" in r and "묶음2:abs-path" in r, r)
# W9 desk 사본도 같은 allow 로 검사한다(본글만 나가고 사본이 거부되는 반쪽 게시 0)
pg.lib.desk_head = lambda text: "h"
import mirror_desk
mirror_desk.desk_text = lambda text, mention: text
n = len(posts)
try:
    pg.guarded_post("b", "t", "CHUMAN", PATH, "1.1", human=True, allow=pg.path_allow("풀패스")); r = "ok"
except pg.PostGuardError as e:
    r = str(e)
res("W9 allow 있는 글의 desk 사본도 통과(게시 2건)", r == "ok" and len(posts) == n + 2, (r, len(posts) - n))
PY

run() { python3 -I "$TMP/scn.py" "$1" "$TMP" 2>&1; }
out="$(run "$KIT")"; echo "$out"
echo "$out" | grep -q '^FAIL' && bad "정상 판에 FAIL 있음" || ok "정상 판 W1~W9 FAIL 0"
[ "$(echo "$out" | grep -c '^PASS W')" = 9 ] && ok "W1~W9 9건 모두 PASS" || bad "PASS W 줄 수 ≠ 9"

# 변이: 사본 폴더에서 한 줄을 고쳐 시험이 FAIL 로 잡는지 본다
mutant() { # <이름> <기대 FAIL 접두> <py 치환식>
  local d="$TMP/m_$1"; cp -R "$KIT" "$d"
  python3 -I - "$d/post_guard.py" "$3" <<'PY'
import sys
p, expr = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
old, new = expr.split("=>", 1)
assert old in s, "치환 대상 없음: " + old
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
  [ $? = 0 ] || { bad "변이 $1 치환 실패"; return; }
  run "$d" | grep -q "^FAIL $2" && ok "변이 $1 → $2 FAIL (시험이 잡음)" || bad "변이 $1 을 시험이 못 잡음"
}
mutant 1 "W3" 'if isinstance(asked_text, str) and PATH_ASK.search(asked_text) else frozenset()=>if isinstance(asked_text, str) else frozenset()'
mutant 2 "W4" 'PATH_ALLOW = frozenset({"abs-path", "worktree-path"})=>PATH_ALLOW = frozenset(INTERNAL)'

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES $fail"
exit $((fail > 0))
