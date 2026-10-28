#!/usr/bin/env bash
# test_tail_remote_write_r1075.sh — r1075 칸: 원격 송신도 로컬 agent_inject 절차(상자 기다림 → 입력줄 전문 확인 →
# session-id 기록으로 제출 판정 → 절반 시점 재전송 1회) · 원격 open --session-id · ft-reach-check id 우선.
#   반례 집합 r2(arch#173 · #182367 동결): R1~R7 · 변이 3(기다림 끔/입력줄 확인 끔/재전송 끔).
#   대역(가짜 ssh·가짜 tmux·run_tool)은 _harness_tail_remote_write.sh(공용).
set -uo pipefail
export LC_ALL=C
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/_harness_tail_remote_write.sh"

# ── ⓘ r1075 — 원격 주입 = 로컬 agent_inject 절차(상자 기다림 → 입력줄 전문 확인 → session-id 기록 판정 → 재전송 1) ──
# 반례 집합 r2(arch#173 · #182367 · 동결): R1 상자 3초 뒤 → 기다렸다 넣음 · rc0 / R2 상한 안에 안 뜸 → send 0 · rc5 not-ready /
#  R3 이미 상자 있음 → 기다림 0 / R4 원격 open --session-id 1개 + env 같은 값 + 판정이 그 파일(warn 0) /
#  R5 TMUXC_READY_MAX 빈 값·글자 → 30 / R6 글자가 1초 뒤 완성 → Enter 는 전문 뒤 1번 · rc0 / R7 첫 Enter 삼킴 → 재전송 1번 · Enter 총 2 · rc0
t0="$(now_ms)"
e="$T/i"; mk_env "$e"
SID1="11111111-1111-1111-1111-111111111111"
SID2="22222222-2222-2222-2222-222222222222"
SID3="33333333-3333-3333-3333-333333333333"

# R1 — 상자를 3초 뒤에 그리는 좌석 → 기다렸다 넣고 제출 확인(rc0)
mk_seat "$e" byz-satnano-nano-r1#0 "$e/remote/repo" claude
seat_props "$e" byz-satnano-nano-r1#0 "$SID1" 3
: > "$e/state/sessions/byz-satnano-nano-r1#0/record"
st1="$(cat "$e/state/sessions/byz-satnano-nano-r1#0/start")"
out="$(TMUXC_READY_MAX=10 TMUXC_SUBMIT_WAIT=2 run_tool "$e" "$TMUXC" send mini/byz-satnano-nano-r1#0 "R1-BODY-ONE" 2>&1)"; rc=$?
txt_ts="$(awk -F'\t' '$2=="TEXT" && $3 ~ /R1-BODY-ONE/ { print $5 }' "$e/state/sent.log" 2>/dev/null | tail -1)"
n="$(awk -F'\t' '$2=="TEXT" && $3 ~ /R1-BODY-ONE/ { n++ } END{ print n+0 }' "$e/state/sent.log" 2>/dev/null)"
if [ "$rc" = 0 ] && [ "$n" = 1 ] && [ -n "$txt_ts" ] && [ $(( txt_ts - st1 )) -ge 3 ]; then
  pass "R1 상자 3초 뒤 → 기다렸다 넣음(wait $(( txt_ts - st1 ))s) · rc0 · send-keys 1"
else fail "R1 rc=$rc n=$n wait=$(( ${txt_ts:-0} - ${st1:-0} ))s (기대 rc0·1회·≥3s) out=$out"; fi

# R2 — 상한 안에 상자가 안 뜸 → send-keys 0 · rc5 state=not-ready
mk_seat "$e" byz-satnano-nano-r2#0 "$e/remote/repo" claude
seat_props "$e" byz-satnano-nano-r2#0 "$SID2" 999
out="$(TMUXC_READY_MAX=2 TMUXC_SUBMIT_WAIT=1 run_tool "$e" "$TMUXC" send mini/byz-satnano-nano-r2#0 "R2-BODY" 2>&1)"; rc=$?
n="$(awk -F'\t' '$2=="TEXT" && $3 ~ /R2-BODY/ { n++ } END{ print n+0 }' "$e/state/sent.log" 2>/dev/null)"
e2="$(awk -F'\t' '$1=="byz-satnano-nano-r2#0" && $2=="ENTER" { n++ } END{ print n+0 }' "$e/state/sent.log" 2>/dev/null)"
if [ "$rc" = 5 ] && [ "$n" = 0 ] && [ "$e2" = 0 ]; then pass "R2 상자 안 뜸 → rc5 · send-keys 0 · Enter 0"
else fail "R2 rc=$rc text=$n enter=$e2 (기대 rc5·0·0) out=$out"; fi
case "$out" in *state=not-ready*) pass "R2 state=not-ready 줄(주입 0 사유)" ;; *) fail "R2 not-ready 줄 없음: $out" ;; esac

# R3 — 이미 상자가 떠 있는 좌석 → 기다림 0 · rc0
mk_seat "$e" byz-satnano-nano-r3#0 "$e/remote/repo" claude
seat_props "$e" byz-satnano-nano-r3#0 "$SID3"
: > "$e/state/sessions/byz-satnano-nano-r3#0/record"
k0="$(now_ms)"
out="$(TMUXC_READY_MAX=10 TMUXC_SUBMIT_WAIT=2 run_tool "$e" "$TMUXC" send mini/byz-satnano-nano-r3#0 "R3-BODY" 2>&1)"; rc=$?
el3=$(( $(now_ms) - k0 ))
if [ "$rc" = 0 ] && [ "$el3" -lt 3000 ]; then pass "R3 이미 상자 → 기다림 0(${el3}ms) · rc0"
else fail "R3 rc=$rc ${el3}ms (기대 rc0·<3000ms) out=$out"; fi

# R4 — 원격 open claude = --session-id 1개 · env 같은 값 · ft-reach-check 가 그 파일로 특정(warn 0)
mf="claude-sonnet-5-5"
dout="$(run_tool "$e" "$TMUXC" open "$e/remote/repo" --host mini --name byz-satnano-nano-r4#0 --agent claude --model "$mf" --dry-run 2>&1)"
n_sid="$(printf '%s\n' "$dout" | grep -oE -- '--session-id [0-9a-f-]{36}' | wc -l | tr -d ' ')"
case "$dout" in *'command='*'--session-id '*) pass "R4 dry-run 명령에 --session-id 1개" ;; *) fail "R4 dry-run session-id 없음: $dout" ;; esac
run_tool "$e" "$TMUXC" open "$e/remote/repo" --host mini --name byz-satnano-nano-r4#0 --agent claude --model "$mf" >/dev/null 2>&1
cmd_sid="$(awk -F'\t' '$2=="TEXT" && $3 ~ /--session-id/ { print $3; exit }' "$e/state/sent.log" 2>/dev/null | grep -oE -- '--session-id [0-9a-f-]{36}' | awk '{print $2}')"
env_sid="$(awk -F= '$1=="TMUXC_CLAUDE_SESSION_ID"{print $2; exit}' "$e/state/sessions/byz-satnano-nano-r4#0/env" 2>/dev/null)"
if [ -n "$cmd_sid" ] && [ "$cmd_sid" = "$env_sid" ]; then pass "R4 명령·env 의 session-id 같다(${cmd_sid:0:8}…)"
else fail "R4 cmd_sid=$cmd_sid env_sid=$env_sid (기대 같은 uuid)"; fi
# 그 id 의 기록으로 판정되고 warn(디렉터리 전수) 줄이 없어야 한다
enc="$(printf '%s' "$e/remote/repo" | sed 's|[^A-Za-z0-9]|-|g')"
mkdir -p "$e/home/.claude/projects/$enc"
printf '{"type":"user","message":{"content":"PROBE-R4"}}\n' > "$e/home/.claude/projects/$enc/$cmd_sid.jsonl"
rout="$(run_tool "$e" "$REACH" byz-satnano-nano-r4#0 "PROBE-R4" 2 0 2>&1)"; rrc=$?
if [ "$rrc" = 0 ]; then pass "R4 도달 판정이 그 id 파일로 REACHED"; else fail "R4 reach rc=$rrc out=$rout"; fi
case "$rout" in *"warn: 좌석 파일 특정 실패"*) fail "R4 warn 줄 있음(전수 폴백) : $rout" ;; *) pass "R4 warn 줄 0(디렉터리 전수 아님)" ;; esac

# R5 — TMUXC_READY_MAX 가 글자 → 30 으로 정규화(기록 id 없는 좌석은 rc6 + ready_max=30 줄)
mk_seat "$e" byz-satnano-nano-r5#0 "$e/remote/repo" claude
out="$(TMUXC_READY_MAX="abc" TMUXC_SUBMIT_WAIT=1 run_tool "$e" "$TMUXC" send mini/byz-satnano-nano-r5#0 "R5-BODY" 2>&1)"; rc=$?
case "$out" in *ready_max=30*) pass "R5 글자 상한 → ready_max=30 (rc=$rc)" ;; *) fail "R5 정규화 안 됨: $out" ;; esac
# 기록 id 없는 좌석은 내부 신호 rc6 → 호출자가 ft-reach-check 로 넘긴다(이 시험의 최종 rc = 그 판정).
case "$out" in *state=sent-no-id*) pass "R5 기록 id 없는 좌석 = rc6 내부 신호 후 reach 판정(rc=$rc)" ;; *) fail "R5 sent-no-id 줄 없음: $out" ;; esac

# R6 — 글자가 1초 뒤에 다 그려짐 → Enter 는 전문이 그려진 뒤 1번 · rc0
SID6="66666666-6666-6666-6666-666666666666"
mk_seat "$e" byz-satnano-nano-r6#0 "$e/remote/repo" claude
seat_props "$e" byz-satnano-nano-r6#0 "$SID6" "" 1
: > "$e/state/sessions/byz-satnano-nano-r6#0/record"
out="$(TMUXC_READY_MAX=10 TMUXC_SUBMIT_WAIT=3 run_tool "$e" "$TMUXC" send mini/byz-satnano-nano-r6#0 "R6-BODY-LONG-ENOUGH" 2>&1)"; rc=$?
n_enter="$(awk -F'\t' '$1=="byz-satnano-nano-r6#0" && $2=="ENTER" { n++ } END{ print n+0 }' "$e/state/sent.log" 2>/dev/null)"
gap="$(awk -F'\t' '$1=="byz-satnano-nano-r6#0" { if ($2=="TEXT") t=$5; else if ($2=="ENTER" && !t2) t2=$5 } END{ print (t2&&t)?t2-t:0 }' "$e/state/sent.log" 2>/dev/null)"
if [ "$rc" = 0 ] && [ "$n_enter" = 1 ] && [ "${gap:-0}" -ge 1 ]; then pass "R6 그리기 지연 → Enter 전문 뒤 1번(gap ${gap}s) · rc0"
else fail "R6 rc=$rc enters=$n_enter gap=${gap:-0} (기대 rc0·1·≥1s) out=$out"; fi
case "$out" in *delivered=*) pass "R6 제출 확인(delivered) 줄" ;; *) fail "R6 delivered 줄 없음: $out" ;; esac

# R7 — 첫 Enter 가 삼켜짐 → 절반 시점 재전송 1번 · Enter 총 2 · rc0
SID7="77777777-7777-7777-7777-777777777777"
mk_seat "$e" byz-satnano-nano-r7#0 "$e/remote/repo" claude
seat_props "$e" byz-satnano-nano-r7#0 "$SID7" "" "" swallow
: > "$e/state/sessions/byz-satnano-nano-r7#0/record"
out="$(TMUXC_READY_MAX=10 TMUXC_SUBMIT_WAIT=4 run_tool "$e" "$TMUXC" send mini/byz-satnano-nano-r7#0 "R7-BODY" 2>&1)"; rc=$?
n_enter="$(awk -F'\t' '$1=="byz-satnano-nano-r7#0" && $2=="ENTER" { n++ } END{ print n+0 }' "$e/state/sent.log" 2>/dev/null)"
if [ "$rc" = 0 ] && [ "$n_enter" = 2 ]; then pass "R7 첫 Enter 삼킴 → 재전송 1회(총 2) · rc0"
else fail "R7 rc=$rc enters=$n_enter (기대 rc0·2) out=$out"; fi
el_i=$(( $(now_ms) - t0 ))
printf 'info ⓘ R1~R7 합계 %sms\n' "$el_i"
[ "$el_i" -le 70000 ] && pass "ⓘ 단계 초 ${el_i}ms (≤70000)" || fail "ⓘ 단계 초 ${el_i}ms > 70000"

# ── 변이 3 (r1075) — libexec/agent-inject.sh 사본을 뜯어 고친다(자기 파일 재호출 0) ──
# 변이 ①: 상자 기다림 끔 → R1 이 rc0 이 아니게 된다(상자 전 주기 = 판독 불가)
em1="$T/i-mut1"; rm -rf "$em1"; cp -R "$e" "$em1"; : > "$em1/state/sent.log"
rm -f "$em1/state/sessions/byz-satnano-nano-r1#0/enters"; date +%s > "$em1/state/sessions/byz-satnano-nano-r1#0/start"
mk_socket "$em1/home/.ssh/ft-cm/mini"
ml1="$T/lib-mut-nowait"; cp "$INJECT_LIB" "$ml1"
python3 - "$ml1" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = '  if ! wait_input_box "$pane" "$ready_max"; then'
assert old in s, "변이 지점 없음"
s = s.replace(old, '  if false; then', 1)
open(p, "w", encoding="utf-8").write(s)
PY
mout="$(INJECT_LIB_OVERRIDE="$ml1" TMUXC_READY_MAX=10 TMUXC_SUBMIT_WAIT=2 run_tool "$em1" "$TMUXC" send mini/byz-satnano-nano-r1#0 "R1-MUT" 2>&1)"; mrc=$?
[ "$mrc" != 0 ] && pass "변이① FAIL 확인(상자 기다림 끔 → rc=$mrc ≠ 0)" || fail "변이① 미검출(기다림 없이도 rc0) out=$mout"

# 변이 ②: 입력줄 전문 확인을 0.3초 고정 대기로 되돌리면 R6 이 깨진다(잘린 글이 제출됨)
em2="$T/i-mut2"; rm -rf "$em2"; cp -R "$e" "$em2"; : > "$em2/state/sent.log"
rm -f "$em2/state/sessions/byz-satnano-nano-r6#0/enters"
rm -f "$em2/home/.claude/projects/"*/*.jsonl
# 그리기 지연을 2초로 바꿔 «0.3초 고정 대기» 가 확실히 잘린 글자를 제출하게 만든다(초 경계 흔들림 제거).
printf '2\n' > "$em2/state/sessions/byz-satnano-nano-r6#0/draw_delay"
mk_socket "$em2/home/.ssh/ft-cm/mini"
ml2="$T/lib-mut-confirm"; cp "$INJECT_LIB" "$ml2"
python3 - "$ml2" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
start = s.index('  # ② 그리기 지연을 짧게 기다린다')
end = s.index('  case "$st" in', start)
s = s[:start] + '  sleep 0.3\n  st=0\n' + s[end:]
open(p, "w", encoding="utf-8").write(s)
PY
mout="$(INJECT_LIB_OVERRIDE="$ml2" TMUXC_READY_MAX=10 TMUXC_SUBMIT_WAIT=3 run_tool "$em2" "$TMUXC" send mini/byz-satnano-nano-r6#0 "R6-MUT-BODY" 2>&1)"; mrc=$?
m_enter="$(awk -F'\t' '$1=="byz-satnano-nano-r6#0" && $2=="ENTER" { n++ } END{ print n+0 }' "$em2/state/sent.log" 2>/dev/null)"
# 변이② 의 증상은 «rc≠0» 이 아니라 «Enter 가 일찌감치 여러 번 / 잘린 글이 제출됨» 이다 — 그 축으로 잡는다.
if [ "$mrc" != 0 ] || [ "$m_enter" != 1 ]; then pass "변이② FAIL 확인(입력줄 확인 끔 → Enter ${m_enter}회 · rc=$mrc)"
else fail "변이② 미검출(rc=0 · Enter 1) out=$mout"; fi

# 변이 ③: 재전송을 끄면 R7 이 rc0 이 아니게 된다(첫 Enter 삼킴 그대로)
em3="$T/i-mut3"; rm -rf "$em3"; cp -R "$e" "$em3"; : > "$em3/state/sent.log"
rm -f "$em3/state/sessions/byz-satnano-nano-r7#0/enters"
rm -f "$em3/home/.claude/projects/"*/*.jsonl
mk_socket "$em3/home/.ssh/ft-cm/mini"
ml3="$T/lib-mut-resend"; cp "$INJECT_LIB" "$ml3"
python3 - "$ml3" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = '    if [[ "$resent" -eq 0 && "$now" -ge "$t_mid" ]]; then'
assert old in s, "변이 지점 없음"
s = s.replace(old, '    if false; then', 1)
open(p, "w", encoding="utf-8").write(s)
PY
mout="$(INJECT_LIB_OVERRIDE="$ml3" TMUXC_READY_MAX=10 TMUXC_SUBMIT_WAIT=4 run_tool "$em3" "$TMUXC" send mini/byz-satnano-nano-r7#0 "R7-MUT" 2>&1)"; mrc=$?
[ "$mrc" != 0 ] && pass "변이③ FAIL 확인(재전송 끔 → rc=$mrc ≠ 0)" || fail "변이③ 미검출 rc=$mrc out=$mout"

echo "---"
[ "$FAIL" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILED $FAIL"
exit 1
