#!/usr/bin/env bash
# test_send_verified_mbox_consumed_r1750.sh — 검증 송신의 두 번째 도달 원본 = 우편함 소비 (카드 r1750 · A1~A4).
# 반례(동결): ① REACH rc5(codex 꼴) · peek SEQ 없음 → rc0 REACHED(recv)  ② rc4×2 · ring 뒤 SEQ 없음 → rc0 · ring 1
#   ③ rc4×2 · SEQ 남음 → rc2 · ring 1  ④ rc5 · drops seqs 칸에 SEQ → rc5 «버려짐(ring 포화)»  ⑤ peek rc1 → «판정 불가 우편함 소비» 1줄 · 기준판 rc(2)
#   ⑥ doorbell=absent → rc5 · peek 0  ⑦ ft-nano-spawn 송신 줄 → FT_REACH_AGENT=<에이전트>  ⑧ REACH rc0 → 출력·rc 그대로 · peek 0
#   변이(사본만): M1 drops 대조 지움 → ④ FAIL · M2 peek rc 검사 지움 → ⑤ FAIL · M3 env 지움 → ⑦ FAIL
# 실 tmux·실 좌석·실 우편함 0 · 시험 안 sleep 0 · 대기 = FT_SV_DEADLINE(지금+2초)로 clip.
# env SV_UNDER_TEST / NS_UNDER_TEST = 다른 판(기준판 Red 확인용)을 갈아끼운다 · 기본 = comm·kit 두 벌 모두.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
H="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
SVS="${SV_UNDER_TEST:-$H/comm/ft-send-verified.sh $H/kit/fable-team/bin/ft-send-verified.sh}"
NSS="${NS_UNDER_TEST:-$H/bin/ft-nano-spawn.sh $H/kit/fable-team/bin/ft-nano-spawn.sh}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
S="nano-r1750-test#0"; SEQ=4242
mkdir -p "$TMP/fake" "$TMP/canon"
cat > "$TMP/fake/tmux" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
# mbox 대역 — send = QUEUED seq · peek = 진짜 꼴 «pending=N latest_seq=M» (PEEKS = 호출마다 «N:M» · 끝 값 반복 · PEEKS_RING = ring 뒤 값) · ring = doorbell
cat > "$TMP/fake/mbox" <<'EOF'
#!/usr/bin/env bash
echo "mbox $*" >> "$LOG"
case "$1" in
  send) echo "QUEUED seq=$FAKE_SEQ to=$2 doorbell=${FAKE_DB:-sent}";;
  peek) n=$(grep -c "^mbox peek" "$LOG"); [ -n "${PEEKS_RING:-}" ] && grep -q "^mbox ring" "$LOG" && PEEKS="$PEEKS_RING"; set -- $PEEKS; [ "$n" -le $# ] || n=$#; eval "v=\${$n}"
        echo "pending=${v%%:*} latest_seq=${v#*:} from=x scanned=1 lineage=$S"; exit "${PEEK_RC:-0}";;
  ring) echo "RING seq=$3 doorbell=${RING_DB:-sent}";;
esac
EOF
# reach 대역 — 기준 프로브(FT_REACH_COUNT_ONLY) = PROBE_RC · 판정 호출 = REACH_RCS 순서대로
cat > "$TMP/fake/reach" <<'EOF'
#!/usr/bin/env bash
[ -n "${FT_REACH_COUNT_ONLY:-}" ] && exit "${PROBE_RC:-0}"
echo "reach $*" >> "$LOG"; n=$(grep -c '^reach ' "$LOG"); set -- $REACH_RCS; [ "$n" -le $# ] || n=$#; eval "exit \${$n}"
EOF
chmod +x "$TMP/fake/"*
# run <ft-send-verified 원본> VAR=… → RC · $TMP/out(stdout) · $TMP/err(stderr) · $LOG(호출) · DROPSLINE=1 = 버림 원장에 SEQ 1줄
DL="$TMP/canon/mailbox.drops.log"
run() {
  local src="$1"; shift; local d="$TMP/sv"; rm -rf "$d"; mkdir -p "$d"
  cp "$src" "$d/ft-send-verified.sh"; cp "$TMP/fake/reach" "$d/ft-reach-check.sh"
  LOG="$TMP/log"; : > "$LOG"; : > "$DL"
  case " $* " in *" DROPSLINE=1 "*) echo "2026-11-12T07:50:00 to=$S dropped=2 oldest_seq=4240 seqs=4240,$SEQ" > "$DL";; esac
  env PATH="$TMP/fake:$PATH" LOG="$LOG" FAKE_SEQ="$SEQ" S="$S" FT_MBOX_SH="$TMP/fake/mbox" FT_MBOX_DIR="$TMP/canon" \
      FT_SV_DEADLINE="$(( $(date +%s) + 2 ))" PEEKS="1:$SEQ" REACH_RCS=4 "$@" \
      bash "$d/ft-send-verified.sh" "$S" "본문" > "$TMP/out" 2> "$TMP/err"; RC=$?
}
n() { grep -c "^$1" "$LOG"; }
got() { echo "rc=$RC peek=$(n 'mbox peek') ring=$(n 'mbox ring') out=$(tr '\n' '|' < "$TMP/out" | cut -c1-160) err=$(tr '\n' '|' < "$TMP/err" | cut -c1-200)"; }
recv_line() { [ "$(grep -c "^REACHED(recv) session=$S seq=$SEQ\$" "$TMP/out")" = 1 ]; }
case1() { run "$1" REACH_RCS=5 PEEKS="0:0"; [ "$RC" = 0 ] && recv_line; }
case4() { run "$1" REACH_RCS=5 PEEKS="0:0" DROPSLINE=1; [ "$RC" = 5 ] && [ "$(grep -c "seq=$SEQ 버려짐(ring 포화)" "$TMP/err")" = 1 ] && ! grep -q 'REACHED' "$TMP/out"; }
case5() { run "$1" REACH_RCS=5 PEEKS="0:0" PEEK_RC=1; [ "$RC" = 2 ] && [ "$(grep -c '판정 불가 우편함 소비' "$TMP/err")" = 1 ] && ! grep -q 'REACHED' "$TMP/out"; }
for SV in $SVS; do
  tag="$(basename "$(dirname "$SV")")"
  case1 "$SV" && ok "① [$tag] rc5(codex 꼴) · SEQ 소비 → rc0 REACHED(recv) 1줄" || bad "① [$tag] $(got)"
  run "$SV" PROBE_RC=5 PEEKS="0:0"
  { [ "$RC" = 0 ] && recv_line; } && ok "①b [$tag] 기준 프로브 rc5 갈래도 SEQ 소비 → rc0" || bad "①b [$tag] $(got)"
  run "$SV" REACH_RCS="4 4" PEEKS="1:$SEQ" PEEKS_RING="0:0"
  { [ "$RC" = 0 ] && recv_line && [ "$(n 'mbox ring')" = 1 ]; } && ok "② [$tag] rc4×2 · ring 뒤 SEQ 소비 → rc0 · ring 1" || bad "② [$tag] $(got)"
  run "$SV" REACH_RCS="4 4" PEEKS="1:$SEQ"
  { [ "$RC" = 2 ] && [ "$(n 'mbox ring')" = 1 ] && grep -q '^NOT_SUBMITTED' "$TMP/err"; } && ok "③ [$tag] SEQ 남음 → rc2 · ring 1(기존 갈래)" || bad "③ [$tag] $(got)"
  run "$SV" REACH_RCS="4 4" PEEKS="2:$((SEQ+1))"
  { [ "$RC" = 2 ] && [ "$(n 'mbox ring')" = 1 ]; } && ok "③b [$tag] 뒤 쪽지가 쌓여 SEQ 를 가림 → 소비로 안 봄 · rc2" || bad "③b [$tag] $(got)"
  case4 "$SV" && ok "④ [$tag] SEQ 가 drops seqs 칸 → rc5 «버려짐(ring 포화)» 1줄" || bad "④ [$tag] $(got)"
  case5 "$SV" && ok "⑤ [$tag] peek rc1 → «판정 불가 우편함 소비» 1줄 · rc2 그대로(기준판 = jsonl rc5 도 ring 갈래로 감)" || bad "⑤ [$tag] $(got)"
  run "$SV" FAKE_DB=absent PEEKS="0:0"
  { [ "$RC" = 5 ] && [ "$(n 'mbox peek')" = 0 ] && grep -q 'doorbell=absent' "$TMP/err"; } && ok "⑥ [$tag] doorbell=absent → rc5 · peek 0" || bad "⑥ [$tag] $(got)"
  run "$SV" FAKE_DB=absent PROBE_RC=5 PEEKS="0:0"
  { [ "$RC" = 5 ] && [ "$(n 'mbox peek')" = 0 ]; } && ok "⑥b [$tag] 프로브 rc5 + doorbell=absent → rc5 · peek 0" || bad "⑥b [$tag] $(got)"
  run "$SV" REACH_RCS=0 PEEKS="0:0"
  { [ "$RC" = 0 ] && [ "$(n 'mbox peek')" = 0 ] && [ "$(cat "$TMP/out")" = "QUEUED seq=$SEQ to=$S doorbell=sent" ]; } \
    && ok "⑧ [$tag] REACH rc0 → 출력 그대로 · peek 0" || bad "⑧ [$tag] $(got)"
done
# ⑦ ft-nano-spawn 송신 줄 — 그 1줄만 떼어 send 대역(env 덤프)으로 돌린다(좌석·명부·카드 0)
case7() {
  local line d="$TMP/ns"; rm -rf "$d"; mkdir -p "$d"
  line="$(grep -m1 'bash "\$HERE/ft-send-verified.sh" "\$NAME" "\$BODY"' "$1")" || return 1
  printf '#!/usr/bin/env bash\necho "FT_REACH_AGENT=${FT_REACH_AGENT:-} FT_SEND_FROM=${FT_SEND_FROM:-}" > "%s/env"\n' "$d" > "$d/ft-send-verified.sh"
  HERE="$d" AGENT=codex FROM=x-master NAME=n BODY=b bash -c "$line" >/dev/null 2>&1
  [ "$(cat "$d/env" 2>/dev/null)" = "FT_REACH_AGENT=codex FT_SEND_FROM=x-master" ]
}
for NS in $NSS; do
  tag="$(basename "$(dirname "$(dirname "$NS")")")/$(basename "$(dirname "$NS")")"
  case7 "$NS" && ok "⑦ [$tag] spawn 송신 → FT_REACH_AGENT=codex 전달" || bad "⑦ [$tag] env=$(cat "$TMP/ns/env" 2>/dev/null)"
done
# 변이 — 기본 판(comm·bin)을 쓸 때만 · 변이마다 원본으로 같은 사례 1회 더(반대 결과 대조)
if [ -z "${SV_UNDER_TEST:-}${NS_UNDER_TEST:-}" ]; then
  SV0="$H/comm/ft-send-verified.sh"; NS0="$H/bin/ft-nano-spawn.sh"; M="$TMP/mut"; mkdir -p "$M"
  grep -v 'r1750-M1' "$SV0" > "$M/m1.sh"; [ "$(wc -l < "$M/m1.sh")" -lt "$(wc -l < "$SV0")" ] || bad "M1 적용 실패"
  { ! case4 "$M/m1.sh" && [ "$RC" = 0 ] && case4 "$SV0"; } && ok "M1 drops 대조 지움 → ④ FAIL(rc0) · 원본 PASS" || bad "M1 이 ④ 에 안 잡힘 $(got)"
  grep -v 'r1750-M2' "$SV0" > "$M/m2.sh"; [ "$(wc -l < "$M/m2.sh")" -lt "$(wc -l < "$SV0")" ] || bad "M2 적용 실패"
  { ! case5 "$M/m2.sh" && [ "$RC" = 0 ] && case5 "$SV0"; } && ok "M2 peek rc 검사 지움 → ⑤ FAIL(조용한 rc0) · 원본 PASS" || bad "M2 가 ⑤ 에 안 잡힘 $(got)"
  sed 's/ FT_REACH_AGENT="\$AGENT"//' "$NS0" > "$M/m3.sh"; cmp -s "$M/m3.sh" "$NS0" && bad "M3 적용 실패"
  { ! case7 "$M/m3.sh" && case7 "$NS0"; } && ok "M3 env 지움 → ⑦ FAIL · 원본 PASS" || bad "M3 가 ⑦ 에 안 잡힘"
  # comm·kit 두 벌의 r1750 블록이 같은 바이트인지
  blk() { sed -n '/^# ★r1750 우편함 소비/,/^# ★r1750 끝★/p' "$1"; }
  { [ -n "$(blk "$SV0")" ] && [ "$(blk "$SV0")" = "$(blk "$H/kit/fable-team/bin/ft-send-verified.sh")" ]; } && ok "ⓑ comm·kit r1750 블록 같음" || bad "ⓑ comm·kit 블록 다름"
fi
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
