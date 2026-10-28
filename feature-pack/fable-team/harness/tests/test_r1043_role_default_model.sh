#!/usr/bin/env bash
# test_r1043_role_default_model.sh — r1043: 기본 브레인을 «역할»로 정한다 — arch = Opus 5.5 · 팀장(master)만 Sonnet 5.5 (두 도구).
#   ⓐ successor-open «-arch-» + agent claude + --model 생략 → open --model claude-opus-5-5 · rc0 (변이: 새 줄 제거 → ⓐ FAIL)
#   ⓑ arch + --model sn(명시) → 그 값 그대로 · arch + agent codex + 생략 → usage rc2
#   ⓒ role-spawn master(claude) 생략 → claude-sonnet-5-5[1m] (변이: master 분기 제거 → ⓒ FAIL)
#   ⓓ role-spawn arch·da·pm·tester 생략 → 기본 그대로(claude-opus-5-5[1m]) · master --model 명시 → 그 값
#   ⓔ 두 도구 쌍 cmp 0 · 문서 3곳 새 값 grep 1건 이상
# 전부 mktemp 안 — 가짜 tmux·tmuxc·pgrep·send·mbox·reach(PATH 스텁) + 임시 git 리포. 실 세션·홈·명부 쓰기 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1 FT_TEAMSET=0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_ROLE_BASE_PREFIX FT_PENALTY_TEAM
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

for f in ft-successor-open.sh ft-role-spawn.sh; do bash -n "$KIT/$f" && ok "bash -n $f" || bad "bash -n $f"; done

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
B="$TMP/bin"; FK="$TMP/fake"; mkdir -p "$B" "$FK"
cp -p "$KIT/ft-successor-open.sh" "$KIT/ft-role-spawn.sh" "$B/"
# 변이(mutate) = 카드 계약을 «지운» 사본으로 같은 시험을 돌린다 → 그 계약의 행이 FAIL 이어야 한다
if [ -n "${FT_R1043_MUTATE:-}" ]; then
  case "$FT_R1043_MUTATE" in
    arch)   grep -v 'MODEL="claude-opus-5-5"' "$B/ft-successor-open.sh" > "$B/x" && mv "$B/x" "$B/ft-successor-open.sh"
            grep -q 'MODEL="claude-opus-5-5"' "$B/ft-successor-open.sh" && { echo "FAIL 변이 arch 적용 실패"; exit 1; } ;;
    master) grep -v 'MODEL="claude-sonnet-5-5\[1m\]"' "$B/ft-role-spawn.sh" > "$B/x" && mv "$B/x" "$B/ft-role-spawn.sh"
            grep -q 'MODEL="claude-sonnet-5-5\[1m\]"' "$B/ft-role-spawn.sh" && { echo "FAIL 변이 master 적용 실패"; exit 1; } ;;
    *) echo "FAIL 모르는 변이: $FT_R1043_MUTATE"; exit 1 ;;
  esac
fi
SO="$B/ft-successor-open.sh"; RS="$B/ft-role-spawn.sh"

# ── 픽스처: 임시 리포(v65 팀 폴더·README·인박스·명부) ──
R="$TMP/repo"; mkdir -p "$R/.fable-team" "$TMP/live-root"
for _r in arch master da pm tester; do mkdir -p "$R/design/v65/indices/inbox/$_r"; done
git init -q "$R"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| v65 | `design/v65/` | x | 현역 |\n' > "$R/design/TEAMS.md"
: > "$R/design/v65/SEATBELT-README.md"
printf '{"_version":"t","_master":"byz-v65-master-claude#1","_arch":"byz-v65-arch-claude#1","byz-v65-arch-claude#1":{"role":"arch","agent":"claude"}}\n' > "$R/.fable-team/seats.json"
printf '%s\n' "$TMP/live-root" > "$R/.fable-team/LIVE_ROOT"
mkdir -p "$R/.fable-team/state/successor"; STATE="$R/.fable-team/state/successor"
printf '#!/usr/bin/env bash\nexit 0\n' > "$B/ft-all-stop.sh"
printf '#!/usr/bin/env bash\necho "SENT $*"\nexit 0\n' > "$B/ft-send-verified.sh"
for f in ft-team-lib.sh ft_raised.py ft-resource-gate.sh ft-resource-swap-lib.sh ft-reclaim-capped.sh ft_teamset.py ft_spawn_queue.py ft-resource-sample.sh ft-harness-root.sh; do
  [ -f "$KIT/$f" ] && cp -p "$KIT/$f" "$B/"
done
cp -p "$KIT"/ft*.py "$B/" 2>/dev/null   # ft_all_stop·ft_penalty·ft_stall_detect 등 import 사슬 통째
chmod +x "$B"/*.sh 2>/dev/null

# ── 가짜 tmux·tmuxc·pgrep·send·mbox·reach ──
OPENED="$TMP/opened"; LOG="$TMP/calls.log"; BODY="$TMP/body.txt"; BODY_OUT="$TMP/sent_body.txt"
mkstub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$FK/$1"; chmod +x "$FK/$1"; }
mkstub tmux 'case "$1" in
  has-session) [ -f "$OPENED" ] && exit 0; exit 1;;
  list-panes) echo 4242;;
  send-keys) echo enter >> "$LOG";;
  display-message) echo "$PANE_CWD";;
  ls) exit 0;;
esac; exit 0'
mkstub tmuxc 'echo "tmuxc $*" >> "$LOG"; [ "${TMUXC_RC:-0}" = 0 ] && : > "$OPENED"; exit "${TMUXC_RC:-0}"'
mkstub pgrep 'case "$*" in "-a -x claude"|"-a -x codex") exec "$SENSORS/pgrep" "$@";; esac; echo pgrep >> "$LOG"; echo 5555; exit 0'
mkstub send 'echo send >> "$LOG"; printf "%s" "${2:-}" > "$BODY_OUT"; echo "QUEUED seq=777 to=$1 pending=1 doorbell=sent"; exit "${SEND_RC:-0}"'
mkstub mbox 'echo "mbox $1" >> "$LOG"; echo "RING seq=$3 doorbell=sent"; exit 0'
: > "$FK/mbox_doorbell.sh"
mkstub reach 'echo reach >> "$LOG"; exit "${REACH_RC:-0}"'
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$TMP/sensors" ok; SENSORS="$TMP/sensors/fake-sensors"; RES="$FT_RES_ROOT"
printf '골 원문 1줄\n골 원문 2줄\n골 원문 3줄\n본문 나머지\n' > "$BODY"

# run_so <구 좌석> <후계> [환경…] — MODEL_ARG: 없음 = --model 생략 · 그 밖 = 그 값 · AGENT_ARG 기본 claude
run_so() {
  local old="$1" new="$2"; shift 2
  rm -f "$LOG" "$OPENED" "$BODY_OUT"; rm -rf "$STATE"; mkdir -p "$STATE"
  local marg=(); [ -n "${MODEL_ARG:-}" ] && marg=(--model "$MODEL_ARG")
  env HOME="$TMP/home" PANE_CWD="$TMP/pane" PATH="$FK:$PATH" LOG="$LOG" OPENED="$OPENED" BODY_OUT="$BODY_OUT" \
      FT_SO_POLL=0 FT_SO_WAIT_MAX=2 FT_RES_ROOT="$RES" SENSORS="$SENSORS" \
      FT_SEND_VERIFIED="$FK/send" FT_MBOX_SH="$FK/mbox" FT_REACH_CHECK="$FK/reach" "$@" \
      bash "$SO" "$old" "$R" --name "$new" --agent "${AGENT_ARG:-claude}" "${marg[@]}" --ctx 1m --effort high --body-file "$BODY" > "$TMP/out" 2>&1
}
rs() { rm -f "$OPENED"; (cd "$R" && PATH="$FK:$PATH" LOG="$LOG" OPENED="$OPENED" FT_RES_ROOT="$RES" SENSORS="$SENSORS" bash "$RS" "$@" 2>&1); }

A_OLD='byz-t-harness-arch-claude#1'; A_NEW='byz-t-harness-arch-claude#2'
M_OLD='byz-t-harness-master-claude#1'; M_NEW='byz-t-harness-master-claude#2'

# ⓐ arch + claude + --model 생략 → claude-opus-5-5 · rc0 (변이 대상)
MODEL_ARG='' AGENT_ARG='claude' run_so "$A_OLD" "$A_NEW"; RC=$?
{ [ "$RC" -eq 0 ] && grep -q -- '--model claude-opus-5-5' "$LOG" && [ "$(jq -r '.model' "$STATE/$A_OLD.json" 2>/dev/null)" = "claude-opus-5-5" ]; } \
  && ok "ⓐ arch + 생략 → claude-opus-5-5 · 도달 파일 model 동일 · rc0" || bad "ⓐ rc=$RC log=$(tr '\n' ' ' < "$LOG" 2>/dev/null) out=$(cat "$TMP/out")"

# ⓑ arch + --model sn 명시 → 그 값 그대로 / arch + agent codex + 생략 → usage rc2
MODEL_ARG='sn' AGENT_ARG='claude' run_so "$A_OLD" "$A_NEW"; RC=$?
{ [ "$RC" -eq 0 ] && grep -q -- '--model claude-sonnet-5-5' "$LOG" && ! grep -q 'claude-opus-5-5' "$LOG"; } \
  && ok "ⓑ arch + --model sn → claude-sonnet-5-5 그대로(덮음 0)" || bad "ⓑ-1 rc=$RC log=$(tr '\n' ' ' < "$LOG" 2>/dev/null) out=$(cat "$TMP/out")"
MODEL_ARG='' AGENT_ARG='codex' run_so "$A_OLD" "$A_NEW"; RC=$?
{ [ "$RC" -eq 2 ] && grep -q 'usage:' "$TMP/out" && [ ! -s "$LOG" ]; } \
  && ok "ⓑ arch + agent codex + 생략 → usage rc2 · 부작용 0" || bad "ⓑ-2 rc=$RC log=$(tr '\n' ' ' < "$LOG" 2>/dev/null) out=$(cat "$TMP/out")"
AGENT_ARG=''

# ⓒ 팀장 회귀 — master + claude + 생략 → claude-sonnet-5-5 (r1034 그대로)
MODEL_ARG='' run_so "$M_OLD" "$M_NEW"; RC=$?
{ [ "$RC" -eq 0 ] && grep -q -- '--model claude-sonnet-5-5' "$LOG" && ! grep -q 'claude-opus-5-5' "$LOG"; } \
  && ok "ⓒ master + 생략 → claude-sonnet-5-5 (r1034 회귀)" || bad "ⓒ rc=$RC log=$(tr '\n' ' ' < "$LOG" 2>/dev/null) out=$(cat "$TMP/out")"
# ⓒ-2 role-spawn master(claude) 생략 → claude-sonnet-5-5[1m] (변이 대상)
o="$(rs master --dry-run)"; rc=$?
{ [ "$rc" -eq 0 ] && [[ "$o" == *"PLAN seat=byz-v65-master-claude#0 role=master agent=claude model=claude-sonnet-5-5[1m]"* ]]; } \
  && ok "ⓒ-2 role-spawn master + 생략 → claude-sonnet-5-5[1m]" || bad "ⓒ-2 rc=$rc $o"

# ⓓ role-spawn arch·da·pm·tester 생략 → claude-opus-5-5[1m] · master + --model 명시 → 그 값
for r in arch da pm tester; do
  o="$(rs "$r" --dry-run)"; rc=$?
  { [ "$rc" -eq 0 ] && [[ "$o" == *"role=$r agent=claude model=claude-opus-5-5[1m]"* ]]; } \
    && ok "ⓓ role-spawn $r + 생략 → claude-opus-5-5[1m]" || bad "ⓓ $r rc=$rc $o"
done
o="$(rs master --model claude-fable-5-1 --raise "r1043 시험" --raise-card "$R/design/v65/indices/inbox/arch/x.md" --dry-run)"; rc=$?
{ [ "$rc" -eq 0 ] && [[ "$o" == *"model=claude-fable-5-1"* ]]; } \
  && ok "ⓓ role-spawn master + --model 명시 → 그 값 그대로" || bad "ⓓ master 명시 rc=$rc $o"

# ⓔ 두 도구 쌍 cmp 0 · 문서 3곳 새 값
cmp -s "$KIT/ft-successor-open.sh" "$HERE/../bin/ft-successor-open.sh" && ok "ⓔ ft-successor-open.sh 쌍 cmp 0" || bad "ⓔ ft-successor-open.sh 쌍 다름"
cmp -s "$KIT/ft-role-spawn.sh" "$HERE/../bin/ft-role-spawn.sh" && ok "ⓔ ft-role-spawn.sh 쌍 cmp 0" || bad "ⓔ ft-role-spawn.sh 쌍 다름"
FP="$HERE/../.."
for pair in "skill/references/main-team-governance.md:arch 기본 = Opus 5.5" \
            "skill/templates/rules/orchestration.md:opus-5-5 (기본)" \
            "harness/kit/fable-team/templates/rules/orchestration.md:opus-5-5 (기본)"; do
  f="$FP/${pair%%:*}"; pat="${pair#*:}"
  { [ -f "$f" ] && [ "$(grep -c -- "$pat" "$f")" -ge 1 ]; } && ok "ⓔ 문서 ${pair%%:*} 에 «${pat}»" || bad "ⓔ 문서 ${pair%%:*} 에 «${pat}» 없음"
done
grep -qF 'opus-5-5 (기본)** — **fable-5는 에스컬레이션 전용' "$FP/skill/templates/rules/orchestration.md" \
  && ok "ⓔ 템플릿 architect 칸 «opus-5-5 (기본)» + fable 문구 유지" || bad "ⓔ 템플릿 architect 칸 문구"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
