#!/usr/bin/env bash
# test_mbox_doorbell_merge_r1476.sh — r1476: doorbell 게이트 1곳(머리 종류 · 좌석/팀 깨움 예산 · 미읽음) + 보류 후속 sweep + recv ACK + close-check
#  격리: 임시 박스(<박스>/.fable-team/{comm,state}) · 임시 FT_MBOX_DIR·FT_MBOX_STATE_DIR·TMPDIR · 임시 명부(FT_SEATS_JSON) ·
#        fakebin tmux(pane 목록·send-keys 기록만) · fake ps(pane_pid 아래 claude 본체) · 가짜 시계 FT_MBOX_NOW · 실 우편함·실 pane 0.
#  T1 억제 3통 → 1회 깨움 + held seq 2 · T2 5분 창 뒤 후속 1회(299초 0) + sweep 단독 재개 · T3 보고 전용 무음
#  T4 즉시(긴급·인계·레디·사람 글) 예산 밖 · T5 좌석 6/창 + 창 바뀐 첫 send 재개 · T6 팀 30 · T7 recv PENDING-AFTER + close-check
#  T8 미읽음 판정 불가(fail-loud) · T9~T15 = test_mbox_doorbell_merge_r1476b.sh (r1524 분할 — 앞부분 74초 > 사례 70초)
set -uo pipefail
# ★상한 «동작» 시험은 상한을 스스로 소유한다(r1499 · 선례 test_mbox_doorbell_sh_tail_r1039.sh:57)★
#   기본값이 100000 으로 올라갔으므로(mbox_wakebudget.sh:76) T5 의 6 · T6 의 30 은 이 줄이 정한다. 본문·기대값 무변경.
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


echo "---"; [ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL $fail"; exit 1; }
