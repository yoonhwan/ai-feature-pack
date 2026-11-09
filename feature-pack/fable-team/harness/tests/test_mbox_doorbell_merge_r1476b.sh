#!/usr/bin/env bash
# test_mbox_doorbell_merge_r1476b.sh — r1476 후반부(T9~T15). ★r1524 분할★ — doorbell 이 주입 직전 미읽음을 세게 되면서
#   앞부분(T1~T8)이 74초가 되어 사례 70초 상한을 넘었다(DA #276870 「시간 상한은 시험 분할로 해결」). 계약·기대값·본문 무변경.
#  T9 held seq = 그 send 의 py seq · 발신 실패면 held 0 + 환불 · T10 전달 실패 보존+환불
#  T11 동시 예약 6/4 · T12 직접 ring 예산 · T13 소유자 1곳(이중 차감 0) · T14 fail-closed · T15 planner nudge
#  격리: 앞부분과 같은 규칙(임시 박스·TMPDIR·명부·fakebin tmux·fake ps·가짜 시계) — 실 우편함·실 pane 0.
set -uo pipefail
# ★상한 «동작» 시험은 상한을 스스로 소유한다(r1499 · test_mbox_doorbell_merge_r1476.sh 와 같은 줄)★ — T11 의 6 · T12 의 6
export FT_MBOX_WAKE_SEAT_MAX=6 FT_MBOX_WAKE_TEAM_MAX=30

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
