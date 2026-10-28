#!/usr/bin/env bash
# test_distill_role_model_r1067.sh — r1067: 증류(ft-tmux-distill.sh)도 --model 생략이면 «역할 기본»을 쓴다.
#   arch = claude-opus-5-5[1m] · 팀장(master) = claude-sonnet-5-5[1m] · 그 밖(나노) = 지금 승계 순서(라이브 argv) 그대로 · 명시 --model 우선.
#   ⓐ R1 byz-cfo-arch-claude#59 (옛 argv sonnet) · 생략 → open 인자 claude-opus-5-5[1m] (변이: 역할 분기 끔 → 라이브 argv 복사 → FAIL)
#   ⓑ R2 byz-cfo-master-claude#118 (옛 argv opus) · 생략 → claude-sonnet-5-5[1m]
#   ⓒ R3 arch 이름 + --model claude-fable-5-1 명시 → 그 값 그대로 (변이: 명시도 덮음 → FAIL)
#   ⓓ R4 ft-v65-temp-sb-x#0 나노 이름 · 옛 argv sonnet → sonnet (지금 동작)
#   ⓔ R5 ft-v65-arch-claude#110 · 생략 → claude-opus-5-5[1m]
# 가짜 tmux·tmuxc·spawn(PATH 아님 · 같은 bin 디렉터리) — 실 세션·tmux·명부 쓰기 0 · sleep 0(스텁이 handover 토큰을 즉시 씀).
# 변이: FT_R1067_MUTATE=arch|explicit — 계약을 «지운» 사본으로 같은 시험을 돌린다(그 행이 FAIL 이어야 한다).
set -uo pipefail
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/root"; B="$R/.fable-team/bin"; FK="$TMP/fake"; LOG="$TMP/argv.log"
mkdir -p "$B" "$FK" "$R/.fable-team"
printf '{}\n' > "$R/.fable-team/install.json"
cp -p "$KIT/ft-tmux-distill.sh" "$KIT/ft-lib.sh" "$B/"
DISTILL="$B/ft-tmux-distill.sh"
bash -n "$DISTILL" && ok "bash -n ft-tmux-distill.sh" || bad "bash -n ft-tmux-distill.sh"

# 변이 = 계약을 지운 사본(같은 시험을 다시 돌린다 — 자기 파일 재호출 아님)
case "${FT_R1067_MUTATE:-}" in
  '') ;;
  arch)     sed -i.bak '/\*-arch-\*)/d' "$DISTILL" && rm -f "$DISTILL.bak"
            grep -q 'opus-5-5\[1m\]";' "$DISTILL" && { echo "FAIL 변이 arch 적용 실패"; exit 1; } ;;
  explicit) awk 'BEGIN{d=0} { if(!d && index($0,"[ \"$AGENT\" = \"claude\" ] && [ -z \"$MODEL\" ]")){ sub(/ && \[ -z "\$MODEL" \]/,""); d=1 } print }' \
              "$DISTILL" > "$TMP/mut" && mv "$TMP/mut" "$DISTILL"
            [ "$(grep -c '&& \[ -z "\$MODEL" \]' "$DISTILL")" -eq 2 ] || { echo "FAIL 변이 explicit 적용 실패"; exit 1; } ;;
  *) echo "FAIL 모르는 변이: $FT_R1067_MUTATE"; exit 1 ;;
esac

# 가짜 tmux(세션 목록 없음) · tmuxc(라이브 argv = 옛 좌석 모델) · spawn(인자 캡처 + handover 토큰 즉시 기록)
printf '#!/usr/bin/env bash\ncase "$1" in ls) exit 0;; esac\nexit 0\n' > "$FK/tmux"
printf '#!/usr/bin/env bash\ncase "$1" in model) printf "model=%%s\\neffort=high\\n" "$LIVE_MODEL";; esac\nexit 0\n' > "$FK/tmuxc"
cat > "$B/ft-tmux-spawn.sh" <<'SPAWN'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$ARGV_LOG"
inp=""; prev=""
for a in "$@"; do [ "$prev" = "--input" ] && inp="$a"; prev="$a"; done
hp="$(printf '%s' "$inp" | sed -n 's/.*후 \(.*\) 에 토큰.*/\1/p')"
tk="$(printf '%s' "$inp" | sed -n "s/.*토큰 '\([^']*\)'.*/\1/p")"
[ -n "$hp" ] && [ -n "$tk" ] && { mkdir -p "$(dirname "$hp")"; printf '%s\n' "$tk" > "$hp"; }
exit 0
SPAWN
chmod +x "$FK/tmux" "$FK/tmuxc" "$B/ft-tmux-spawn.sh"

# run <구 좌석> <라이브 모델> [--model 값] → rc · spawn 인자 = $LOG · stderr = $TMP/err
run() {
  local sess="$1" live="$2"; shift 2
  rm -f "$LOG" "$TMP/err"
  local tok="$TMP/token.$RANDOM"
  printf 'op=distill\ntarget=%s\nexpires=%s\n' "$sess" "$(( $(date +%s) + 300 ))" > "$tok"
  PATH="$FK:$PATH" LIVE_MODEL="$live" ARGV_LOG="$LOG" HOME="$TMP/home" \
    bash "$DISTILL" "$sess" --op-token "$tok" "$@" > "$TMP/out" 2> "$TMP/err"
  RC=$?
}
argv_model() { grep -A1 -x -- '--model' "$LOG" 2>/dev/null | sed -n '2p'; }

# ⓐ R1 arch 이름 · 옛 argv sonnet · 생략 → claude-opus-5-5[1m] (변이 대상)
run 'byz-cfo-arch-claude#59' 'claude-sonnet-5-5[1m]'
{ [ "$RC" -eq 0 ] && [ "$(argv_model)" = 'claude-opus-5-5[1m]' ] && grep -q '역할 기본 arch → claude-opus-5-5\[1m\]' "$TMP/err"; } \
  && ok "ⓐ R1 arch + 생략 → open --model claude-opus-5-5[1m] · stderr 이유 1줄 · rc0" \
  || bad "ⓐ rc=$RC model=$(argv_model) argv=$(tr '\n' ' ' < "$LOG" 2>/dev/null) err=$(cat "$TMP/err")"

# ⓑ R2 팀장 이름 · 옛 argv opus · 생략 → claude-sonnet-5-5[1m]
run 'byz-cfo-master-claude#118' 'claude-opus-5-5[1m]'
{ [ "$RC" -eq 0 ] && [ "$(argv_model)" = 'claude-sonnet-5-5[1m]' ] && grep -q '역할 기본 팀장 → claude-sonnet-5-5\[1m\]' "$TMP/err"; } \
  && ok "ⓑ R2 master + 생략 → open --model claude-sonnet-5-5[1m] · rc0" \
  || bad "ⓑ rc=$RC model=$(argv_model) argv=$(tr '\n' ' ' < "$LOG" 2>/dev/null) err=$(cat "$TMP/err")"

# ⓒ R3 arch 이름 + --model 명시 → 그 값 그대로 (변이 대상)
run 'byz-cfo-arch-claude#59' 'claude-sonnet-5-5[1m]' --model claude-fable-5-1
{ [ "$RC" -eq 0 ] && [ "$(argv_model)" = 'claude-fable-5-1' ] && ! grep -q 'claude-opus-5-5' "$LOG" && [ ! -s "$TMP/err" ]; } \
  && ok "ⓒ R3 --model 명시 → claude-fable-5-1 그대로(역할 기본이 덮지 않음) · rc0" \
  || bad "ⓒ rc=$RC model=$(argv_model) argv=$(tr '\n' ' ' < "$LOG" 2>/dev/null) err=$(cat "$TMP/err")"

# ⓓ R4 나노 이름 · 옛 argv sonnet → sonnet (지금 동작 = 라이브 argv 승계)
run 'ft-v65-temp-sb-x#0' 'claude-sonnet-5-5[1m]'
{ [ "$RC" -eq 0 ] && [ "$(argv_model)" = 'claude-sonnet-5-5[1m]' ] && [ ! -s "$TMP/err" ]; } \
  && ok "ⓓ R4 나노 이름 + 생략 → 라이브 argv sonnet 그대로 · rc0" \
  || bad "ⓓ rc=$RC model=$(argv_model) argv=$(tr '\n' ' ' < "$LOG" 2>/dev/null) err=$(cat "$TMP/err")"

# ⓔ R5 ft- 꼴 옛 arch 이름 · 옛 argv sonnet · 생략 → claude-opus-5-5[1m] (변이 대상)
run 'ft-v65-arch-claude#110' 'claude-sonnet-5-5[1m]'
{ [ "$RC" -eq 0 ] && [ "$(argv_model)" = 'claude-opus-5-5[1m]' ]; } \
  && ok "ⓔ R5 ft-v65-arch-claude#110 + 생략 → claude-opus-5-5[1m] · rc0" \
  || bad "ⓔ rc=$RC model=$(argv_model) argv=$(tr '\n' ' ' < "$LOG" 2>/dev/null) err=$(cat "$TMP/err")"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
