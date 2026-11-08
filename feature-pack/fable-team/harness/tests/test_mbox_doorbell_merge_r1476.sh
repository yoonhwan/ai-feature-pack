#!/usr/bin/env bash
# test_mbox_doorbell_merge_r1476.sh — r1476: doorbell 게이트 1곳(머리 종류 · 좌석/팀 깨움 예산 · 미읽음) + 보류 후속 sweep + recv ACK + close-check
#  격리: 임시 박스(<박스>/.fable-team/{comm,state}) · 임시 FT_MBOX_DIR·FT_MBOX_STATE_DIR·TMPDIR · 임시 명부(FT_SEATS_JSON) ·
#        fakebin tmux(pane 목록·send-keys 기록만) · fake ps(pane_pid 아래 claude 본체) · 가짜 시계 FT_MBOX_NOW · 실 우편함·실 pane 0.
#  T1 억제 3통 → 1회 깨움 + held seq 2 · T2 5분 창 뒤 후속 1회(299초 0) + sweep 단독 재개 · T3 보고 전용 무음
#  T4 즉시(긴급·인계·레디·사람 글) 예산 밖 · T5 좌석 6/창 + 창 바뀐 첫 send 재개 · T6 팀 30 · T7 recv PENDING-AFTER + close-check
#  T8 미읽음 판정 불가(fail-loud) · T9 seq 순서 · 발신 실패 환불 · T10 전달 실패 보존+환불 · T11 동시 예약 6/4 · T12 직접 ring 예산
#  T13 소유자 1곳(이중 차감 0) · T14 fail-closed(잠금 초과·장부 손상) · T15 planner nudge
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
COMM="$HERE/../comm"
T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (기대 '$3' 실제 '$2')"; fi; }

# ── fakebin: tmux(pane 목록 · send-keys 기록) / ps(pane 아래 claude 본체) ────────────────────────
mkdir -p "$T/fakebin"
cat > "$T/fakebin/tmux" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${TMUX_LOG:-/dev/null}"
case "${1:-}" in
  list-panes)
    shift
    if [ "${1:-}" = "-a" ]; then
      i=0; for s in ${TMUX_SEATS:-}; do i=$((i+1)); printf '%s|%%%d\n' "$s" "$i"; done
    else
      printf '%s\n' "${TMUX_PANE_PID:-900001}"
    fi
    exit 0;;
  display-message) printf 'node\n'; exit 0;;
  send-keys) exit 0;;
esac
exit 1
EOF
cat > "$T/fakebin/ps" <<'EOF'
#!/bin/sh
printf '%s\n' '900001     1 S    /bin/zsh' '900002 900001 S    /usr/bin/claude --dangerously-skip-permissions'
EOF
printf '#!/bin/sh\nexit 1\n' > "$T/failpeek.sh"
printf '#!/bin/sh\nexec sleep 9\n' > "$T/slowpeek.sh"
chmod +x "$T/fakebin/tmux" "$T/fakebin/ps" "$T/failpeek.sh" "$T/slowpeek.sh"

cat > "$T/seats.json" <<'EOF'
{"a#1":{"agent":"claude","team":"t1","tick":null},"b#1":{"agent":"claude","team":"t1","tick":null},
 "c#1":{"agent":"claude","team":"t1","tick":null},"d#1":{"agent":"claude","team":"t1","tick":null},
 "e#1":{"agent":"claude","team":"t1","tick":null},"f#1":{"agent":"claude","team":"t1","tick":null},
 "pl#1":{"agent":"pi","team":"t1","tick":null}}
EOF
echo '{"_master":"pl#1"}' > "$T/seats-planner.json"
export PATH="$T/fakebin:$PATH" FT_SEATS_JSON="$T/seats.json" FT_PS_CMD="$T/fakebin/ps" \
       TMUX_LOG="$T/tmux.log" FT_BIN="$T/nobin" \
       FT_MBOX_RATE_N=1000 FT_MBOX_RESEND_COOLDOWN=0 FT_MBOX_RECV_LIMIT=50
ALLSEATS="a#1 b#1 c#1 d#1 e#1 f#1 pl#1"; export TMUX_SEATS="$ALLSEATS"
: > "$TMUX_LOG"

# 가짜 시계 — 창 경계가 결정적이도록 «창 시작»에서 출발(472223 * 3600).
W0=1700002800
NOW="$W0"
BOX=""; C=""
mkbox() {  # <이름> → 새 격리 박스 경로
  local r="$T/box-$1"
  mkdir -p "$r/.fable-team/comm" "$r/.fable-team/state" "$r/tmp"
  cp "$COMM"/mbox*.sh "$COMM"/mbox*.py "$COMM"/ft-agent-alive.sh "$r/.fable-team/comm/"
  printf '%s' "$r"
}
use() {  # <박스경로>
  BOX="$1"; C="$BOX/.fable-team/comm"
  export FT_MBOX_DIR="$C" FT_MBOX_STATE_DIR="$BOX/.fable-team/state" TMPDIR="$BOX/tmp"
  mkdir -p "$BOX/tmp"; : > "$BOX/err"
  unset FT_MBOX_PEEK_CMD FT_MBOX_WAKE_LOCK_TRIES
  export FT_MBOX_RECV_LIMIT=50 TMUX_SEATS="$ALLSEATS"
}
run() {  # <가짜시각> <mbox.sh 하위명령…> → OUT·RC·ERR
  NOW="$1"; shift
  OUT="$(FT_MBOX_NOW="$NOW" bash "$C/mbox.sh" "$@" 2>"$BOX/err")"; RC=$?
  ERR="$(cat "$BOX/err" 2>/dev/null)"
}
S() { run "$NOW" send "$@"; }
R() { run "$NOW" recv "$@"; }
nv() { printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p" | head -1; }
bn() { sed -n 's/.*"n": *\([0-9]*\).*/\1/p' "$BOX/.fable-team/state/wake-budget/$1.json" 2>/dev/null; }
heldn() { cat "$BOX/.fable-team/state/doorbell-held/$1" 2>/dev/null; }
heldput() { mkdir -p "$BOX/.fable-team/state/doorbell-held"; printf 'held ts=%s reason=%s window=%s seat=%s\n%s\n' "$1" "$2" "$3" "$4" "${5:-}" > "$BOX/.fable-team/state/doorbell-held/$4"; }
budput() { mkdir -p "$BOX/.fable-team/state/wake-budget"; printf '{"window": %s, "n": %s}' "$1" "$2" > "$BOX/.fable-team/state/wake-budget/$3.json"; }

BOX="$(mkbox main)"; use "$BOX"; NOW="$W0"

# ── T1: 같은 좌석 3통 연속 → 1회 깨움 · 2·3통 held + held seq 2줄 · 큐 유실 0 ─────────────────────
S a#1 s1#1 "T1 첫 발주";    eq "T1 1통 gate=sent" "$(nv "$OUT" gate)" sent
                            eq "T1 1통 doorbell=sent" "$(nv "$OUT" doorbell)" sent
NOW=$((W0 + 10)); S a#1 s1#1 "T1 둘째 발주"
eq "T1 2통 gate=held" "$(nv "$OUT" gate)" held
eq "T1 2통 doorbell=quiet" "$(nv "$OUT" doorbell)" quiet
NOW=$((W0 + 20)); S a#1 s1#1 "T1 셋째 발주"
eq "T1 3통 gate=held" "$(nv "$OUT" gate)" held
eq "T1 held seq 2줄" "$(grep -c '^seq=' <<<"$(heldn a#1)")" 2
eq "T1 큐 pending 3(유실 0)" "$(nv "$(FT_MBOX_NOW="$NOW" python3 "$C/mbox.py" peek a#1 2>/dev/null)" pending)" 3

# ── T2: 5분 창 — 299초엔 후속 0 · 301초에 후속 1(doorbell=sent) 뒤 held 삭제 · sweep 단독도 같은 결과 ──
NOW=$((W0 + 309)); S b#1 s1#1 "T2 창 안 아무 쪽지"
eq "T2 +299초 followup 0" "$(grep -c 'followup=' <<<"$OUT")" 0
grep -q '^seq=' <<<"$(heldn a#1)" && ok "T2 +299초 held 보존" || bad "T2 +299초 held 보존"
: > "$TMUX_LOG"
NOW=$((W0 + 311)); S b#1 s1#1 "T2 창 끝 뒤 아무 쪽지"
eq "T2 +301초 followup=a#1" "$(nv "$OUT" followup)" a#1
eq "T2 후속 doorbell 주입 1회(recv a#1)" "$(grep -c 'recv a#1' "$TMUX_LOG")" 1
[ -z "$(heldn a#1)" ] && ok "T2 held 삭제(doorbell=sent)" || bad "T2 held 삭제(doorbell=sent)"
S c#1 s1#1 "T2b 보류 만들기"; NOW=$((NOW + 10)); S c#1 s1#1 "T2b 둘째(held)"
run "$NOW" recv b#1 >/dev/null          # b#1 의 T2 보류는 읽어서 닫는다(아래 sweep 은 c#1 만 봐야 한다)
NOW=$((NOW + 400)); run "$NOW" sweep
eq "T2b sweep 단독 followup=c#1" "$(nv "$OUT" followup)" c#1
[ -z "$(heldn c#1)" ] && ok "T2b sweep 단독 held 삭제" || bad "T2b sweep 단독 held 삭제"

# ── T3: 보고 전용 머리 = 큐만(예산 0 · held 0) ────────────────────────────────────────────────
B3="$(mkbox t3)"; use "$B3"; NOW="$W0"
for h in '[정리]' '[회신]' '[완료 보고]'; do
  S d#1 s1#1 "$h r1476 시험 보고"
  eq "T3 $h gate=quiet" "$(nv "$OUT" gate)" quiet
  eq "T3 $h doorbell=quiet" "$(nv "$OUT" doorbell)" quiet
done
[ -z "$(ls "$B3/.fable-team/state/wake-budget" 2>/dev/null)" ] && ok "T3 예산 파일 0(n 불변)" || bad "T3 예산 파일 0(n 불변)"
[ -z "$(ls "$B3/.fable-team/state/doorbell-held" 2>/dev/null)" ] && ok "T3 held 0" || bad "T3 held 0"
eq "T3 큐 적재 3" "$(nv "$(FT_MBOX_NOW="$NOW" python3 "$C/mbox.py" peek d#1 2>/dev/null)" pending)" 3

# ── T4: 즉시(긴급 · --urgent · 인계 · 레디 · 사람 글) = 예산 밖 ────────────────────────────────
B4="$(mkbox t4)"; use "$B4"; NOW="$W0"
S d#1 s1#1 "[긴급] r1476 즉시";        eq "T4 [긴급] gate=sent" "$(nv "$OUT" gate)" sent
S d#1 s1#1 "[인계] a -> b · 항목 0";   eq "T4 [인계] gate=sent" "$(nv "$OUT" gate)" sent
S d#1 s1#1 "[레디] b <- a · 항목 0";   eq "T4 [레디] gate=sent" "$(nv "$OUT" gate)" sent
S e#1 s1#1 "T4 긴급 표시 본문" --urgent;  eq "T4 --urgent gate=sent" "$(nv "$OUT" gate)" sent
S e#1 pl#1 "T4 사람 글";               eq "T4 사람 글 gate=sent" "$(nv "$OUT" gate)" sent
[ -z "$(ls "$B4/.fable-team/state/wake-budget" 2>/dev/null | grep -v '^_ledger.log$')" ] \
  && ok "T4 예산 n 불변(좌석·팀 파일 0)" || bad "T4 예산 n 불변" "$(ls "$B4/.fable-team/state/wake-budget" 2>/dev/null)"

# ── T5: 한 좌석 창 안 6통(+301초 · 사이사이 recv) → 6 sent · 7통 budget · 창 바뀐 첫 send 에 재개 ────
B5="$(mkbox t5)"; use "$B5"; NOW="$W0"
for i in 1 2 3 4 5 6; do
  S a#1 s1#1 "T5 $i 번째"
  eq "T5 $i 통 gate=sent" "$(nv "$OUT" gate)" sent
  R a#1 >/dev/null
  NOW=$((NOW + 301))
done
eq "T5 6통 뒤 좌석 n=6" "$(bn a#1)" 6
S a#1 s1#1 "T5 7 번째"
eq "T5 7통 gate=budget" "$(nv "$OUT" gate)" budget
eq "T5 7통 doorbell=quiet" "$(nv "$OUT" doorbell)" quiet
grep -q 'reason=budget' <<<"$(heldn a#1)" && ok "T5 7통 held(reason=budget)" || bad "T5 7통 held(reason=budget)"
NOW=$((W0 + 3600))
S b#1 s1#1 "[정리] T5 창 바뀐 첫 send"
eq "T5 창 바뀐 첫 send followup=a#1" "$(nv "$OUT" followup)" a#1
eq "T5 재개 뒤 좌석 n=1" "$(bn a#1)" 1
[ -z "$(heldn a#1)" ] && ok "T5 재개 뒤 held 삭제" || bad "T5 재개 뒤 held 삭제"

# ── T6: 팀 합 30 — A~E 각 6통(창 안) 뒤 F 1통 = budget ──────────────────────────────────────────
B6="$(mkbox t6)"; use "$B6"; NOW="$W0"
for s in a#1 b#1 c#1 d#1 e#1; do
  for i in 1 2 3 4 5 6; do
    S "$s" s1#1 "T6 $s $i"
    R "$s" >/dev/null
    NOW=$((NOW + 10))          # 30통이 «한 시각 창» 안에 들어가야 팀 합을 잰다(창 = 3600초)
  done
done
eq "T6 팀 장부 n=30" "$(bn _team-t1)" 30
S f#1 s1#1 "T6 F 한 통"
eq "T6 팀 소진 → gate=budget" "$(nv "$OUT" gate)" budget
B6b="$(mkbox t6b)"; use "$B6b"; NOW="$W0"
budput 472223 30 _team-t1; budput 472223 0 f#1
S f#1 s1#1 "T6b 정합 장부에서 한 통"
eq "T6b 정합 장부(팀 30 · 좌석 0) → budget" "$(nv "$OUT" gate)" budget
eq "T6b 팀 json 원문 불변" "$(cat "$B6b/.fable-team/state/wake-budget/_team-t1.json")" '{"window": 472223, "n": 30}'

# ── T7: recv PENDING-AFTER + held 삭제 + close-check REJECT ────────────────────────────────────
B7="$(mkbox t7)"; use "$B7"; NOW="$W0"
S a#1 s1#1 "T7 하나"; NOW=$((W0 + 10)); S a#1 s1#1 "T7 둘(held)"
export FT_MBOX_RECV_LIMIT=1
run "$NOW" recv a#1; eq "T7 1차 recv PENDING-AFTER 1" "$(tail -1 <<<"$OUT")" "PENDING-AFTER 1"
grep -q '^seq=' <<<"$(heldn a#1)" && ok "T7 남았으면 held 보존" || bad "T7 남았으면 held 보존"
run "$NOW" recv a#1; eq "T7 2차 recv PENDING-AFTER 0" "$(tail -1 <<<"$OUT")" "PENDING-AFTER 0"
[ -z "$(heldn a#1)" ] && ok "T7 PENDING-AFTER 0 → held 삭제" || bad "T7 PENDING-AFTER 0 → held 삭제"
export FT_MBOX_RECV_LIMIT=50
heldput "$NOW" held 472223 b#1 "seq=99"
run "$NOW" close-check b#1
eq "T7 close-check rc 3" "$RC" 3
grep -q '^REJECT b#1 억제된 doorbell 1건 미전달' <<<"$OUT" && ok "T7 close-check REJECT 1줄" || bad "T7 close-check REJECT 1줄" "$OUT"
rm -f "$B7/.fable-team/state/doorbell-held/b#1"
run "$NOW" close-check b#1
grep -q '억제된 doorbell' <<<"$OUT" && bad "T7 held 없으면 억제 REJECT 0" || ok "T7 held 없으면 억제 REJECT 0"

# ── T8: 미읽음 판정 불가 = 울리는 쪽(fail-loud) · 예산 소진이면 budget · 7초 상한 · 재시도 0 ──────
B8="$(mkbox t8)"; use "$B8"; NOW="$W0"
export FT_MBOX_PEEK_CMD="$T/failpeek.sh"
S a#1 s1#1 "T8 판정 불가"; eq "T8 판정 불가 → gate=sent" "$(nv "$OUT" gate)" sent
grep -q 'WARN 미읽음 판정 불가' <<<"$ERR" && ok "T8 stderr WARN 1줄" || bad "T8 stderr WARN 1줄" "$ERR"
eq "T8 판정 불가여도 예산은 썼다(n=1)" "$(bn a#1)" 1
budput 472223 6 a#1
S a#1 s1#1 "T8 소진 상태 판정 불가"; eq "T8 소진 + 판정 불가 → budget(우회 0)" "$(nv "$OUT" gate)" budget
export FT_MBOX_PEEK_CMD="$T/slowpeek.sh"
t0="$(date +%s)"; S c#1 s1#1 "T8 느린 판정(9초 스텁)"; t1="$(date +%s)"
eq "T8 9초 스텁 → 예산 결과대로 sent" "$(nv "$OUT" gate)" sent
[ "$((t1 - t0))" -le 25 ] && ok "T8 send 25초 안 종료($((t1 - t0))s · 판정 7초 상한)" || bad "T8 send 25초 안 종료($((t1 - t0))s)"
unset FT_MBOX_PEEK_CMD

# ── T9: held seq = 그 send 의 py seq(발급 뒤 기록) · 발신 실패면 held 0 + 환불 ────────────────────
B9="$(mkbox t9)"; use "$B9"; NOW="$W0"
S a#1 s1#1 "T9 하나"
NOW=$((W0 + 10)); S a#1 s1#1 "T9 둘째(held)"; s2="$(nv "$OUT" seq)"
NOW=$((W0 + 20)); S a#1 s1#1 "T9 셋째(held)"; s3="$(nv "$OUT" seq)"
eq "T9 held seq = 그 send 의 seq" "$(grep '^seq=' <<<"$(heldn a#1)" | sed 's/seq=//' | paste -sd, -)" "$s2,$s3"
B9b="$(mkbox t9b)"; use "$B9b"; NOW="$W0"
chmod 500 "$B9b/.fable-team/comm"
S a#1 s1#1 "T9 발신 실패"; chmod 700 "$B9b/.fable-team/comm"
[ "$RC" != 0 ] && ok "T9 py send 실패 rc≠0" || bad "T9 py send 실패 rc≠0 (OUT=$OUT)"
[ -z "$(heldn a#1)" ] && ok "T9 발신 실패 → held 0" || bad "T9 발신 실패 → held 0" "$(heldn a#1)"
eq "T9 발신 실패 → 예약 환불(n 0)" "$(bn a#1)" 0

# ── T10: 후속 전달 실패(absent) → held 보존 + last_err + 환불 · 다음 sweep 에 성공 ─────────────
B10="$(mkbox t10)"; use "$B10"; NOW="$W0"
export TMUX_SEATS="b#1"                       # a#1 pane 없음 = absent
heldput "$W0" held 472223 a#1 "seq=7"
budput 472223 5 a#1; budput 472223 5 _team-t1
NOW=$((W0 + 400)); run "$NOW" sweep
eq "T10 전달 실패 followup 0" "$(grep -c 'followup=' <<<"$OUT")" 0
grep -q '^last_err=absent ' <<<"$(heldn a#1)" && ok "T10 held 보존 + last_err=absent" || bad "T10 held 보존 + last_err=absent" "$(heldn a#1)"
eq "T10 전달 실패 → 환불 n=5" "$(bn a#1)" 5
export TMUX_SEATS="$ALLSEATS"
run "$NOW" sweep
eq "T10 다음 sweep 성공 followup=a#1" "$(nv "$OUT" followup)" a#1
[ -z "$(heldn a#1)" ] && ok "T10 다음 sweep held 삭제" || bad "T10 다음 sweep held 삭제"

# ── T11: 동시 예약 10 → 정확히 6 reserved · 4 exhausted · n=6 · .lock 잔존 0 · 죽은 pid 해제 ─────
B11="$(mkbox t11)"; use "$B11"; NOW="$W0"
for i in $(seq 1 10); do ( FT_MBOX_NOW="$NOW" bash "$C/mbox.sh" budget reserve a#1 send >"$B11/o$i" 2>&1 ) & done
wait
eq "T11 reserved 6" "$(grep -l '^reserved ' "$B11"/o* 2>/dev/null | wc -l | tr -d ' ')" 6
eq "T11 exhausted 4" "$(grep -l '^exhausted seat ' "$B11"/o* 2>/dev/null | wc -l | tr -d ' ')" 4
eq "T11 파일 n=6" "$(bn a#1)" 6
[ ! -e "$B11/.fable-team/state/wake-budget/.lock" ] && ok "T11 .lock 잔존 0" || bad "T11 .lock 잔존 0"
mkdir -p "$B11/.fable-team/state/wake-budget/.lock"; printf '999999' > "$B11/.fable-team/state/wake-budget/.lock/pid"
run "$NOW" budget reserve b#1 send
eq "T11 죽은 pid 잠금 해제 뒤 예약 n=1" "$(nv "$OUT" n)" 1
grep -q 'WARN 예산 잠금 죽은 보유 pid 999999 해제' <<<"$ERR" && ok "T11 해제 stderr 1줄" || bad "T11 해제 stderr 1줄" "$ERR"

# ── T12: 직접 ring 7회 → 6 sent · 7회째 quiet gate=budget + held · --reserved 는 추가 차감 0 ────
B12="$(mkbox t12)"; use "$B12"; NOW="$W0"
sent=0; budgetx=0
for i in $(seq 1 7); do
  run "$NOW" ring a#1
  case "$OUT" in *"doorbell=sent"*) sent=$((sent + 1));; *"gate=budget"*) budgetx=$((budgetx + 1));; esac
done
eq "T12 6회 doorbell=sent" "$sent" 6
eq "T12 7회째 doorbell=quiet gate=budget" "$budgetx" 1
eq "T12 원장 6행(1행/예약 · 출처 ring)" "$(grep -c 'src=ring ' "$B12/.fable-team/state/wake-budget/_ledger.log")" 6
grep -q 'reason=budget' <<<"$(heldn a#1)" && ok "T12 7회째 held 기록" || bad "T12 7회째 held 기록"
n_before="$(bn a#1)"
run "$NOW" ring a#1 77 --reserved
eq "T12 --reserved 는 추가 차감 0" "$(bn a#1)" "$n_before"
run "$NOW" budget reserve b#1 silence
eq "T12 공용 예산 API(silence) 도 같은 n 차감" "$(nv "$OUT" n)" 1

# ── T13: 합성 경계(예약 소유자 1곳) — sweep 이 예약하고 ring 은 --reserved(이중 차감 0) ──────────
B13="$(mkbox t13)"; use "$B13"; NOW="$W0"
heldput "$W0" held 472223 a#1 "seq=42"
budput 472223 5 a#1; budput 472223 5 _team-t1
NOW=$((W0 + 400)); : > "$TMUX_LOG"; run "$NOW" sweep
eq "T13 followup=a#1" "$(nv "$OUT" followup)" a#1
eq "T13 원장 +1(출처 followup)" "$(grep -c 'src=followup ' "$B13/.fable-team/state/wake-budget/_ledger.log")" 1
eq "T13 좌석 n=6(이중 차감 0)" "$(bn a#1)" 6
eq "T13 ring 주입 1회(recv a#1)" "$(grep -c 'recv a#1' "$TMUX_LOG")" 1
[ -z "$(heldn a#1)" ] && ok "T13 held 삭제" || bad "T13 held 삭제"
heldput "$W0" held 472223 a#1 "seq=42"
NOW=$((W0 + 500)); : > "$TMUX_LOG"; run "$NOW" sweep
eq "T13 n=6 이면 followup 0" "$(grep -c 'followup=' <<<"$OUT")" 0
eq "T13 n=6 유지" "$(bn a#1)" 6
eq "T13 n=6 이면 ring 0" "$(grep -c 'recv a#1' "$TMUX_LOG")" 0

# ── T14: fail-closed — 잠금 10초 초과 = budget · 장부 손상 = 격리 + budget + 다음은 n=1 ────────────
B14="$(mkbox t14)"; use "$B14"; NOW="$W0"
mkdir -p "$B14/.fable-team/state/wake-budget/.lock"; printf '%s' "$$" > "$B14/.fable-team/state/wake-budget/.lock/pid"
t0="$(date +%s)"; S a#1 s1#1 "T14 잠금 초과"; t1="$(date +%s)"
eq "T14 잠금 초과 → gate=budget" "$(nv "$OUT" gate)" budget
eq "T14 doorbell 0" "$(nv "$OUT" doorbell)" quiet
grep -q 'lock-timeout' "$B14/.fable-team/state/wake-budget/_errors.log" 2>/dev/null && ok "T14 _errors.log 1행" || bad "T14 _errors.log 1행"
# ★stderr 도 1줄★ — gate 가 예산 판정 출력을 삼켜도 «왜 안 울렸는지» 는 보이는 곳에 남아야 한다(조용한 fail-closed 0)
eq "T14 잠금 초과 stderr ERROR 1줄" "$(grep -c '^ERROR ' <<<"$ERR")" 1
grep -q '^ERROR 예산 잠금 10초 초과' <<<"$ERR" && ok "T14 stderr 에 잠금 초과 사유" || bad "T14 stderr 에 잠금 초과 사유" "$ERR"
[ "$((t1 - t0))" -ge 9 ] && ok "T14 10초 상한 준수($((t1 - t0))s)" || bad "T14 10초 상한 준수($((t1 - t0))s)"
rm -rf "$B14/.fable-team/state/wake-budget/.lock"
printf '{깨진' > "$B14/.fable-team/state/wake-budget/a#1.json"
S a#1 s1#1 "T14 장부 손상"
eq "T14 장부 손상 → gate=budget" "$(nv "$OUT" gate)" budget
eq "T14 손상본 .bad-<ts> 격리 1개" "$(ls "$B14/.fable-team/state/wake-budget" | grep -c '^a#1.json.bad-')" 1
eq "T14 장부 손상 stderr ERROR 1줄" "$(grep -c '^ERROR ' <<<"$ERR")" 1
grep -q '^ERROR 예산 장부 손상' <<<"$ERR" && ok "T14 stderr 에 장부 손상 사유" || bad "T14 stderr 에 장부 손상 사유" "$ERR"
S a#1 s1#1 "T14 손상 다음 통"
eq "T14 다음 send 는 sent/n=1" "$(nv "$OUT" gate)/$(bn a#1)" "sent/1"

# ── T15: planner(_master) 보류분 = ring 0 · nudge 파일 1 · via=nudge ──────────────────────────
B15="$(mkbox t15)"; use "$B15"; NOW="$W0"
heldput "$W0" held 472223 pl#1 "seq=55"
NOW=$((W0 + 400)); : > "$TMUX_LOG"; run "$NOW" sweep
eq "T15 followup=pl#1" "$(nv "$OUT" followup)" "pl#1"
grep -q 'via=nudge' <<<"$OUT" && ok "T15 출력에 via=nudge" || bad "T15 출력에 via=nudge" "$OUT"
eq "T15 ring 0(pane 주입 0)" "$(grep -c 'send-keys' "$TMUX_LOG")" 0
eq "T15 nudge 파일 1" "$(ls "$B15/.fable-team/state/pi-wake" 2>/dev/null | grep -c '\.nudge$')" 1
eq "T15 원장 +1(출처 followup)" "$(grep -c 'src=followup ' "$B15/.fable-team/state/wake-budget/_ledger.log")" 1
[ -z "$(heldn pl#1)" ] && ok "T15 held 삭제" || bad "T15 held 삭제"
heldput "$W0" held 472223 pl#1 "seq=56"
run "$NOW" sweep
eq "T15 nudge 이미 있으면 파일 1개(touch 만)" "$(ls "$B15/.fable-team/state/pi-wake" | grep -c '\.nudge$')" 1

echo "---"; [ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL $fail"; exit 1; }
