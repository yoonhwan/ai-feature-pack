#!/usr/bin/env bash
# test_r1043_role_default_model.sh — r1043: 기본 브레인을 «역할»로 정한다 — arch = Opus 5.5 · 팀장(master)만 Sonnet 5.5 (두 도구).
#   ⓐ successor-open «-arch-» + --agent pi + --model 생략 → 표 기본 행 값 claude-opus-5-5 · rc0
#   ⓑ arch + --model 올림 값(표 값) → 그 값 그대로 · arch + agent codex + 생략 → usage rc2
#   ⓒ master + --agent pi + 생략 → 표 값 claude-opus-5-5 · ⓒ-2 role-spawn master 둘 다 생략 → 표 쌍 pi(claude-fable 기본값·sonnet 기본값 폐지)
#   ⓓ role-spawn arch 생략 → 표 쌍 · da·pm·tester(표에 행 없음) 생략 → REJECT rc2 · master --model 명시 → 그 값
#   ⑦ OPEN argv 대조(M6 변이) · ⑧ 한쪽만 준 길 4갈래(M7 변이) · @up 행 = ft-successor-open --tier up 몫(별 시험)
#   ⓔ 두 도구 쌍 cmp 0 · 문서 3곳 새 값 grep 1건 이상
# 전부 mktemp 안 — 가짜 tmux·tmuxc·pgrep·send·mbox·reach(PATH 스텁) + 임시 git 리포. 실 세션·홈·명부 쓰기 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1 FT_TEAMSET=0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_ROLE_BASE_PREFIX FT_PENALTY_TEAM
export FT_SEND_FROM='byz-v65-master-claude#1'   # r1244: 팀 기본값 = «부른 좌석 팀» — 이 시험의 부른 좌석은 v65 팀장(안 적으면 REJECT rc2)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

for f in ft-successor-open.sh ft-role-spawn.sh; do bash -n "$KIT/$f" && ok "bash -n $f" || bad "bash -n $f"; done

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
B="$TMP/bin"; FK="$TMP/fake"; mkdir -p "$B" "$FK"
cp -p "$KIT/ft-successor-open.sh" "$KIT/ft-role-spawn.sh" "$KIT/runtime-policy.tsv" "$KIT/ft-name-lint.sh" "$B/"   # r2403: 표·이름 lint 를 같은 폴더에
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
cp -p "$KIT"/ft*.py "$B/" 2>/dev/null
printf 'import sys\nsys.exit(0)\n' > "$B/ft_teamset.py"   # arch 상시 게이트 = 이 시험 범위 밖(통과 · r1569 시험과 같은 스텁)   # ft_all_stop·ft_penalty·ft_stall_detect 등 import 사슬 통째
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
printf 'print("OPEN-WORK 1 시험 — 받을 일 있음")\nraise SystemExit(1)\n' > "$FK/openwork"   # r1539 받을 일 판정 = 이 시험 범위 밖(일 있음 · python3 로 돈다)
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$TMP/sensors" ok; SENSORS="$TMP/sensors/fake-sensors"; RES="$FT_RES_ROOT"
printf '골 원문 1줄\n골 원문 2줄\n골 원문 3줄\n본문 나머지\n열린 칸 감시: 없음\n' > "$BODY"   # r1957: «열린) 칸 감시» 1줄 필수

# run_so <구 좌석> <후계> [환경…] — MODEL_ARG: 없음 = --model 생략 · 그 밖 = 그 값 · AGENT_ARG 기본 claude
run_so() {
  local old="$1" new="$2"; shift 2
  rm -f "$LOG" "$OPENED" "$BODY_OUT"; rm -rf "$STATE"; mkdir -p "$STATE"
  local marg=(); [ -n "${MODEL_ARG:-}" ] && marg=(--model "$MODEL_ARG")
  env HOME="$TMP/home" PANE_CWD="$TMP/pane" PATH="$FK:$PATH" LOG="$LOG" OPENED="$OPENED" BODY_OUT="$BODY_OUT" \
      FT_SO_POLL=0 FT_SO_WAIT_MAX=2 FT_RES_ROOT="$RES" SENSORS="$SENSORS" \
      FT_SEND_VERIFIED="$FK/send" FT_MBOX_SH="$FK/mbox" FT_REACH_CHECK="$FK/reach" FT_SEAT_OPEN_WORK="$FK/openwork" FT_GOV_MD="$HERE/../../skill/references/main-team-governance.md" "$@" \
      bash "$SO" "$old" "$R" --name "$new" --agent "${AGENT_ARG:-claude}" "${marg[@]}" --ctx 1m --effort high --body-file "$BODY" > "$TMP/out" 2>&1
}
rs() { rm -f "$OPENED"; : > "$LOG"; (cd "$R" && PATH="$FK:$PATH" LOG="$LOG" OPENED="$OPENED" FT_RES_ROOT="$RES" SENSORS="$SENSORS" env ${RSPOL:+FT_RUNTIME_POLICY=$RSPOL} bash "$RS" "$@" 2>&1); }   # RSPOL = 임시 정책표(r2403)

A_OLD='byz-v65-arch-claude#1'; A_NEW='byz-v65-arch-claude#2'
M_OLD='byz-v65-master-claude#1'; M_NEW='byz-v65-master-claude#2'
AP_OLD='byz-v65-arch-pi#1';   AP_NEW='byz-v65-arch-pi#2'
MP_OLD='byz-v65-master-pi#1'; MP_NEW='byz-v65-master-pi#2'

# ⓐ arch + --agent pi + --model 생략 → 표 기본 행 값 claude-opus-5-5 · rc0 (r2403: 손 입력도 표와 같아야 한다 · agnet 꼬리 = --agent)
MODEL_ARG='' AGENT_ARG='pi' run_so "$AP_OLD" "$AP_NEW"; RC=$?
{ [ "$RC" -eq 0 ] && grep -q -- '--model claude-opus-5-5' "$LOG" && [ "$(jq -r '.model' "$STATE/$AP_OLD.json" 2>/dev/null)" = "claude-opus-5-5" ]; } \
  && ok "ⓐ arch + --agent pi + 생략 → 표 값 claude-opus-5-5 · 도달 파일 model 동일 · rc0" || bad "ⓐ rc=$RC log=$(tr '\n' ' ' < "$LOG" 2>/dev/null) out=$(cat "$TMP/out")"

# ⓑ 표 값(올림 행) 명시 → 그 값 그대로 / arch + agent codex + 생략 → usage rc2
MODEL_ARG='claude-fable-5-2' AGENT_ARG='pi' run_so "$AP_OLD" "$AP_NEW"; RC=$?
{ [ "$RC" -eq 0 ] && grep -q -- '--model claude-fable-5-2' "$LOG" && ! grep -q 'claude-opus-5-5' "$LOG"; } \
  && ok "ⓑ arch + --model 올림 값 → claude-fable-5-2 그대로(덮음 0)" || bad "ⓑ-1 rc=$RC log=$(tr '\n' ' ' < "$LOG" 2>/dev/null) out=$(cat "$TMP/out")"
MODEL_ARG='' AGENT_ARG='codex' run_so "$A_OLD" "$A_NEW"; RC=$?
{ [ "$RC" -eq 2 ] && grep -q 'usage:' "$TMP/out" && [ ! -s "$LOG" ]; } \
  && ok "ⓑ arch + agent codex + 생략 → usage rc2 · 부작용 0" || bad "ⓑ-2 rc=$RC log=$(tr '\n' ' ' < "$LOG" 2>/dev/null) out=$(cat "$TMP/out")"
AGENT_ARG=''

# ⓒ 팀장도 표 쌍 — master + --agent pi + 생략 → 표 기본 행 값 claude-opus-5-5 (r1034 sonnet 기본값 폐지 · r2403)
MODEL_ARG='' AGENT_ARG='pi' run_so "$MP_OLD" "$MP_NEW"; RC=$?
{ [ "$RC" -eq 0 ] && grep -q -- '--model claude-opus-5-5' "$LOG" && ! grep -q 'claude-sonnet-5-5' "$LOG"; } \
  && ok "ⓒ master + --agent pi + 생략 → 표 값 claude-opus-5-5(sonnet 기본값 폐지)" || bad "ⓒ rc=$RC log=$(tr '\n' ' ' < "$LOG" 2>/dev/null) out=$(cat "$TMP/out")"
# ⓒ-2 role-spawn master(둘 다 생략) → 표 쌍 pi · claude-opus-5-5 (r1043 «master∧claude→sonnet» 기본값 폐지 · r2403)
o="$(rs master --dry-run)"; rc=$?
{ [ "$rc" -eq 0 ] && [[ "$o" == *"PLAN seat=byz-v65-master-pi#0 role=master agent=pi model=claude-opus-5-5"* ]]; } \
  && ok "ⓒ-2 role-spawn master + 생략 → 표 쌍 pi · claude-opus-5-5" || bad "ⓒ-2 rc=$rc $o"

# ⑦ OPEN argv 실물 대조(M6 변이 = agent claude 고정 → FAIL) — 가짜 tmuxc 가 받은 argv 에 둘 다 있어야 한다
o="$(rs master --dry-run)"; rc=$?
{ [ "$rc" -eq 0 ] && grep -q -- '--agent pi --model claude-opus-5-5' "$LOG"; } \
  && ok "⑦ role-spawn master argv = --agent pi ∧ --model 표 값" || bad "⑦ rc=$rc log=$(tr '\n' ' ' < "$LOG") out=$o"
# ⑦-2 임시 표(master → codex gpt-x) → 그 쌍 그대로
RSPOL="$TMP/pol-codex.tsv"; printf '# 임시\nmaster\tcodex\tgpt-x\narch\tpi\tclaude-opus-5-5\n' > "$RSPOL"
o="$(rs master --dry-run)"; rc=$?
{ [ "$rc" -eq 0 ] && grep -q -- '--agent codex --model gpt-x' "$LOG"; } \
  && ok "⑦-2 임시 표 master = codex gpt-x → argv 그 쌍" || bad "⑦-2 rc=$rc log=$(tr '\n' ' ' < "$LOG") out=$o"
RSPOL=""

# ⑧ 한쪽만 준 길 4갈래(표 있는 역할 · 없는 역할) — M7 변이 = «--agent 만 ∧ 표와 다름» 거절 뺌 → ⑧-a FAIL
o="$(rs master --agent claude --dry-run)"; rc=$?
{ [ "$rc" -eq 2 ] && [[ "$o" == *"REJECT --model 필요"* ]] && [ ! -s "$LOG" ]; } \
  && ok "⑧-a master --agent claude(표 agent pi 와 다름) → REJECT rc2 · tmuxc 호출 0" || bad "⑧-a rc=$rc log=$(tr '\n' ' ' < "$LOG") out=$o"
o="$(rs master --agent pi --dry-run)"; rc=$?
{ [ "$rc" -eq 0 ] && [[ "$o" == *"agent=pi model=claude-opus-5-5"* ]]; } \
  && ok "⑧-b master --agent pi 만 → model = 표 값" || bad "⑧-b rc=$rc $o"
o="$(rs master --model claude-fable-5-2 --raise "r2403 ⑧" --raise-card "$R/design/v65/indices/inbox/arch/x.md" --dry-run)"; rc=$?
{ [ "$rc" -eq 0 ] && [[ "$o" == *"agent=pi model=claude-fable-5-2"* ]]; } \
  && ok "⑧-c master --model 만 → agent = 표 pi" || bad "⑧-c rc=$rc $o"
o="$(rs pm --model any-x --dry-run)"; rc=$?
{ [ "$rc" -eq 0 ] && [[ "$o" == *"role=pm agent=claude model=any-x"* ]]; } \
  && ok "⑧-d pm(표에 행 없음) --model 만 → agent=claude 그대로" || bad "⑧-d rc=$rc $o"
o="$(rs pm --dry-run)"; rc=$?
{ [ "$rc" -eq 2 ] && [[ "$o" == *"REJECT --model 필요"* ]]; } \
  && ok "⑧-e pm 둘 다 생략 → REJECT rc2" || bad "⑧-e rc=$rc $o"

# ⑥⑧ 변이 M6·M7 — 사본에서 한 줄만 바꿔 «잡힘» 을 본다(자기 재호출 0)
mutant_rs() {   # mutant_rs <이름> <바꿀 글자> <바꿔 넣을 글자> → $MUTRS
  local d="$TMP/mutrs-$1"; mkdir -p "$d"; cp -p "$B"/* "$d/" 2>/dev/null; MUTRS="$d/ft-role-spawn.sh"
  python3 - "$MUTRS" "$2" "$3" <<'PY' || return 1
import sys
p, a, b = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
n = s.replace(a, b, 1)
if n == s: print("변이 미적용: " + a); sys.exit(1)
open(p, "w", encoding="utf-8").write(n)
PY
}
mutant_rs M6 'AGENT="${_row%% *}"; MODEL="${_row#* }"' 'AGENT="claude"; MODEL="${_row#* }"'
rs_m6() { RS="$MUTRS" rs "$@"; }; o="$(rs_m6 master --dry-run)"; rc=$?
{ [ "$rc" -eq 0 ] && ! grep -q -- '--agent pi' "$LOG"; } \
  && ok "M6 agent claude 고정으로 되돌림 → ⑦ 빨강(잡힘 · argv --agent claude)" || bad "M6 안 잡힘 log=$(tr '\n' ' ' < "$LOG")"
mutant_rs M7 '[ "$AGENT" = "${_row%% *}" ] || { echo "REJECT --model 필요' ': || { echo "REJECT --model 필요'
RS="$MUTRS"; o="$(rs master --agent claude --dry-run)"; rc=$?; RS="$B/ft-role-spawn.sh"
{ [ "$rc" -eq 0 ] || [ -s "$LOG" ]; } \
  && ok "M7 «--agent 만 ∧ 표와 다름» 거절 뺌 → ⑧-a 빨강(잡힘)" || bad "M7 안 잡힘 rc=$rc out=$o"

# ⓓ role-spawn arch 생략 → 표 쌍 · 표에 행 없는 역할(da·pm·tester) 생략 = REJECT rc2(--model 필요)
for r in arch; do
  o="$(rs "$r" --dry-run)"; rc=$?
  { [ "$rc" -eq 0 ] && [[ "$o" == *"role=$r agent=pi model=claude-opus-5-5"* ]]; } \
    && ok "ⓓ role-spawn $r + 생략 → 표 쌍 pi · claude-opus-5-5" || bad "ⓓ $r rc=$rc $o"
done
for r in da pm tester; do
  o="$(rs "$r" --dry-run)"; rc=$?
  { [ "$rc" -eq 2 ] && [[ "$o" == *"REJECT --model 필요"* ]]; } \
    && ok "ⓓ role-spawn $r + 생략 → REJECT rc2(표에 행 없음 · 박힌 기본 모델 0)" || bad "ⓓ $r rc=$rc $o"
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
