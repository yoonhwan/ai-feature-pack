#!/usr/bin/env bash
# test_tmuxc_inject_ready_submit.sh — r925 r4 로컬 주입 «기본» 칸(ⓐ ⓑ ⓓ g1~g8 · 계약 전문은 lib 머리 주석).
#   r1075 에서 셋으로 쪼갰다(하드 룰 22 · 부하 43 에 79초 초과 실측): 이 파일(기본) · …_deadline.sh(마감 경계 · 주입) ·
#   …_boot.sh(이어가기 경로 · 마감 경계는 deadline_cases.sh 를 FT_WHOS=boot 로 source).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_harness_tmuxc_inject.sh"

# ⓐ 옛 출력(화면 + 기록)에 같은 메시지 + 새 제출 0(Enter 가 입력줄만 비움) → rc≠0 · «submitted» 0 · 재전송 0
fresh; : > "$D/ready"; printf '%s\n' "$MSG" > "$D/transcript"; seed_rec "$MSG"; : > "$D/submit_void"
TMUXC_SUBMIT_WAIT=1 call_limited inject_message sess "$MSG" agent "$SID"
{ [ "$RC" != 0 ] && ! grep -q 'state=submitted' "$T/out" && grep -q '제출 실패' "$T/out" && [ "$(enters)" = 1 ] && [ "$(rec_count)" = 1 ]; } \
  && ok "ⓐ 옛 출력·옛 기록에 같은 메시지 + 새 제출 0 → rc=$RC «제출 실패» · submitted 0 · Enter 1(재전송 0)" \
  || bad "ⓐ rc=$RC enters=$(enters) rec=$(rec_count) out=$(outline)"

# ⓑ 늦은 기록(첫 Enter 가 3초 뒤 jsonl 에) + 재전송 판정 순간 사람이 같은 접두 25자 입력 → 재전송 0 · 사람 입력 제출 0 · rc0
HUMAN25="$(python3 -c 'import sys;print(sys.argv[1][:25])' "$MSG")"
fresh; : > "$D/ready"; printf '3\n' > "$D/jsonl_delay"; printf '3\n' > "$D/human_at"   # 판독 3번째 = 재전송 판정 순간
HUMAN_TEXT="$HUMAN25" TMUXC_SUBMIT_WAIT=4 call_limited inject_message sess "$MSG" agent "$SID"
{ [ "$RC" = 0 ] && grep -q 'state=submitted' "$T/out" && [ "$(enters)" = 1 ] && [ "$(grep -c . "$D/transcript" | tr -d ' ')" = 1 ] \
  && [ "$(cat "$D/buffer")" = "$HUMAN25" ]; } \
  && ok "ⓑ 늦은 기록 + 사람 접두 25자 → 재전송 0(Enter 1) · 사람 글자 제출 0 · 기록으로 rc=0 (${SECS}s)" \
  || bad "ⓑ rc=$RC enters=$(enters) transcript=[$(tr '\n' '|' < "$D/transcript" 2>/dev/null)] buffer=[$(cat "$D/buffer" 2>/dev/null)] out=$(outline)"

# ⓓ capture-pane 이 정상 모양 출력 + rc1 → 판독 불가 · rc≠0 · 주입 0
fresh; : > "$D/ready"; : > "$D/cap_rc1"
TMUXC_READY_MAX=1 call_limited inject_message sess "$MSG" agent "$SID"
{ [ "$RC" != 0 ] && [ "$(typed_lit)" = 0 ] && [ "$(enters)" = 0 ] && ! grep -q 'state=submitted' "$T/out"; } \
  && ok "ⓓ capture 정상 모양 + rc1 → rc=$RC · 주입 0 · Enter 0" \
  || bad "ⓓ rc=$RC lit=$(typed_lit) enters=$(enters) out=$(outline)"

# g1 준비 6초 늦음 → 준비 확인 뒤 주입 · 기록으로 제출 확인 · 입력줄 빔
fresh; ( sleep 6; : > "$D/ready" ) & bg=$!
call_limited inject_message sess "$MSG" agent "$SID"; wait "$bg" 2>/dev/null
{ [ "$RC" = 0 ] && grep -q 'state=submitted' "$T/out" && [ "$(rec_count)" = 1 ] && [ ! -s "$D/buffer" ]; } \
  && ok "g1 준비 6초 늦음 → 준비 확인 뒤 제출 1(기록) · 입력줄 빔 (${SECS}s)" \
  || bad "g1 rc=$RC rec=$(rec_count) buffer=[$(cat "$D/buffer" 2>/dev/null)] out=$(outline)"

# g2 첫 Enter 유실 → 절반 시점 입력줄 = 전문 · 재조회 0 → 재전송 1회로 제출 · 글자 1회
fresh; : > "$D/ready"; printf '1\n' > "$D/enters_lost"
TMUXC_SUBMIT_WAIT=1 call_limited inject_message sess "$MSG" agent "$SID"
{ [ "$RC" = 0 ] && [ "$(enters)" = 2 ] && [ "$(typed_lit)" = 1 ] && [ "$(rec_count)" = 1 ] && grep -q 'enters=2' "$T/out"; } \
  && ok "g2 첫 Enter 유실 → 재전송 1회 제출 · 글자 1회 (${SECS}s)" \
  || bad "g2 rc=$RC enters=$(enters) lit=$(typed_lit) rec=$(rec_count) out=$(outline)"

# g3 Enter 전부 유실 → 재전송 1회 뒤 rc≠0 «제출 실패» · 글자 재입력 0
fresh; : > "$D/ready"; printf '999\n' > "$D/enters_lost"
TMUXC_SUBMIT_WAIT=1 call_limited inject_message sess "$MSG" agent "$SID"
{ [ "$RC" != 0 ] && [ "$RC" != 124 ] && grep -q '제출 실패' "$T/out" && [ "$(enters)" = 2 ] && [ "$(typed_lit)" = 1 ]; } \
  && ok "g3 Enter 전부 유실 → rc=$RC «제출 실패» · Enter 2(재전송 1) · 글자 1회" \
  || bad "g3 rc=$RC enters=$(enters) lit=$(typed_lit) out=$(outline)"

# g4 준비 빠름 → 제출 1 · 추가 대기(옛 판 sleep 0.3 대비) 0.9초 이내
fresh; : > "$D/ready"
call_limited inject_message sess "$MSG" agent "$SID"
ADD="$(python3 -c "print(round(${SECS}-0.3,2))")"
{ [ "$RC" = 0 ] && [ "$(rec_count)" = 1 ] && python3 -c "import sys; sys.exit(0 if ${ADD} <= 0.9 else 1)"; } \
  && ok "g4 준비 빠름 → 제출 1 · 추가 대기 ${ADD}s (≤0.9)" \
  || bad "g4 rc=$RC 추가대기=${ADD}s out=$(outline)"

# g5 새 claude 의 빈 입력줄 = 자리표시 «Try "…"»(실측 10-26) → 그대로 넣고 제출 1
fresh; : > "$D/ready"; : > "$D/placeholder"
call_limited inject_message sess "$MSG" agent "$SID"
{ [ "$RC" = 0 ] && grep -q 'state=submitted' "$T/out" && [ "$(rec_count)" = 1 ]; } \
  && ok "g5 자리표시 «Try …» 입력줄 → 주입·제출 1 (rc=$RC)" \
  || bad "g5 rc=$RC rec=$(rec_count) out=$(outline)"

# g6 입력줄에 사람 글자 → 넣은 뒤 입력줄 ≠ 전문 → Enter 0 · rc≠0 · 사람 글자 제출 0
fresh; : > "$D/ready"; printf '%s' 'HUMAN DRAFT — 내가 쓰던 글' > "$D/buffer"
call_limited inject_message sess "$MSG" agent "$SID"
{ [ "$RC" != 0 ] && grep -q 'state=input-mismatch' "$T/out" && [ "$(enters)" = 0 ] && [ ! -s "$D/transcript" ] && [ "$(rec_count)" = 0 ]; } \
  && ok "g6 사람 글자 위 → 전문 아님 · Enter 0 · rc=$RC · 사람 글자 제출 0" \
  || bad "g6 rc=$RC enters=$(enters) out=$(outline)"

# g7 agent 주입에 세션 기록 id 가 없다 → rc≠0 · 주입 0
fresh; : > "$D/ready"
call inject_message sess "$MSG" agent
{ [ "$RC" != 0 ] && grep -q 'state=no-session-id' "$T/out" && [ "$(typed_lit)" = 0 ]; } \
  && ok "g7 id 없음 → rc=$RC · 주입 0" || bad "g7 rc=$RC out=$(outline)"

# g8 TUI 가 긴 문장을 폭 40 으로 감아 그림(낱말 경계 공백 사라짐 · 이어지는 줄 들여쓰기 · 실측 꼴) → 전문 일치 · 제출 1
LONG="[byz-harness-master-claude#114→byz-t-new-claude#2] 통신 표준: ~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md(12줄)를 지금 Read하고 그대로 따를 것 — 전문 COMM-GUIDE.md 는 열지 않는다. 너의 세션명(me)=byz-t-new-claude#2."
fresh; : > "$D/ready"; printf '40\n' > "$D/wrap"
call_limited inject_message sess "$LONG" agent "$SID"
{ [ "$RC" = 0 ] && grep -q 'state=submitted' "$T/out" && [ "$(rec_count)" = 1 ]; } \
  && ok "g8 긴 문장 TUI 줄 감김 → 전문 일치 · 제출 1 (rc=$RC)" || bad "g8 rc=$RC out=$(outline)"

# 변이④ (arch#173 반송 r3 · 4) — shim 이 agent-inject.sh 를 «안 읽게» 되돌리면 «고치기 전 사본» 분기로 빠진다.
#   그 분기가 rc0(초록)이면 아무도 모른다 — rc≠0 이어야 한다. 본 시험을 다시 부르지 않는다(재입 0 · lib 만 source).
( TMUXC_AGENT_INJECT_LIB=/nonexistent/agent-inject.sh bash -c '. "$1"' _ "$HERE/_harness_tmuxc_inject.sh" ) > "$T/mut4.out" 2>&1; M4RC=$?
{ [ "$M4RC" != 0 ] && grep -q '고치기 전 사본' "$T/mut4.out"; } \
  && ok "변이④ shim 이 lib 를 안 읽음 → «고치기 전 사본» rc=$M4RC(초록 0)" \
  || bad "변이④ 미검출 rc=$M4RC out=$(tr '\n' ' ' < "$T/mut4.out" | cut -c1-200)"

echo "----"
[ "$fail" = 0 ] && { echo "ALL PASS (mutate=$MUTATE)"; exit 0; }
echo "FAILED $fail (mutate=$MUTATE)"; exit 1
