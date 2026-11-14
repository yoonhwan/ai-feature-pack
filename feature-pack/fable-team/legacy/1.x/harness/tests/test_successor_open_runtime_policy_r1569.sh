#!/usr/bin/env bash
# test_successor_open_runtime_policy_r1569.sh — r1569: 후계 런타임(agent·model)은 옛 좌석이 아니라 역할 정책표에서 고른다 · 이름 꼬리 = 고른 agent.
#   ⓐ arch --agent 생략 → pi · claude-opus-5-5 · 꼬리 -pi# | ⓑ nano → pi deepseek | ⓒ --agent claude 명시 → claude 로 열고 «정책과 다름» 1줄
#   ⓓ 표에 역할 없음 → rc≠0 + 이유 1줄 · 열기 0 | ⓔ 표 파일 없음 → rc≠0 · 열기 0 | S 실은 표 3행 · bin·kit 같은 바이트
#   변이 M1(옛 좌석 agent 상속) → ⓐ 빨강 · M2(역할 없음에 기본값) → ⓓ 빨강 — 이 파일 안에서 사본으로 돌려 «잡힘» 을 본다.
#   격리 HOME · 가짜 tmux·tmuxc(인자 기록만)·pgrep·send·mbox·reach + 임시 git 리포만 — 실 세션·명부·우편함 0 · sleep 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
T_START="$(date +%s)"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"; cp -R "$KIT/." "$BIN/"; SO="$BIN/ft-successor-open.sh"
printf 'import sys\nsys.exit(0)\n' > "$BIN/ft_teamset.py"   # arch 상시 게이트 = 이 시험 범위 밖(통과 · r1468 시험과 같은 스텁)
REPO="$TMP/repo"; FAKE="$TMP/fakebin"; LOG="$TMP/calls.log"; BODY="$TMP/body.txt"; OPENED="$TMP/opened"
mkdir -p "$REPO/.fable-team" "$FAKE" "$TMP/live-root"; git -C "$REPO" init -q
printf '%s\n' "$TMP/live-root" > "$REPO/.fable-team/LIVE_ROOT"
mkstub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$FAKE/$1"; chmod +x "$FAKE/$1"; }
mkstub tmux  'case "$1" in has-session) [ -f "$OPENED" ] && exit 0; exit 1;; list-panes) echo 4242;; display-message) echo "$PANE_CWD";; esac; exit 0'
mkstub tmuxc 'echo "tmuxc $*" >> "$LOG"; : > "$OPENED"; exit 0'
mkstub pgrep 'case "$*" in "-a -x claude"|"-a -x codex") exec "$SENSORS/pgrep" "$@";; esac; echo 5555; exit 0'
mkstub send  'echo "QUEUED seq=777 to=$1 pending=1 doorbell=sent"; exit 0'
mkstub mbox  'echo "RING seq=$3 doorbell=sent"; exit 0'
: > "$FAKE/mbox_doorbell.sh"
mkstub reach 'exit 0'
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$TMP/sensors" ok; SENSORS="$TMP/sensors/fake-sensors"; RES="$FT_RES_ROOT"
printf '골 1\n골 2\n골 3\n본문\n열린 칸 감시: 없음\n' > "$BODY"
POL="$TMP/policy.tsv"   # 카드 시험 입력 그대로
printf '# 시험 정책표\narch\tpi\tclaude-opus-5-5\nmaster\tpi\tclaude-opus-5-5\nnano\tpi\tdeepseek\n' > "$POL"
A_OLD='byz-t-harness-arch-claude#1'; A_NEW='byz-t-harness-arch-claude#2'
N_OLD='byz-t-harness-nano-w#1';      N_NEW='byz-t-harness-nano-w#2'
D_OLD='byz-t-harness-tester-claude#1'; D_NEW='byz-t-harness-tester-claude#2'
run() {   # run <so> <구> <후계> [추가 인자…] — 정책표 = $RP(기본 $POL)
  local so="$1" old="$2" new="$3"; shift 3
  rm -f "$LOG" "$OPENED"; : > "$LOG"; rm -rf "$REPO/.fable-team/state"
  env HOME="$TMP/home" PANE_CWD="$TMP/pane" PATH="$FAKE:$PATH" LOG="$LOG" OPENED="$OPENED" SENSORS="$SENSORS" \
      FT_SO_POLL=0 FT_SO_WAIT_MAX=1 FT_SO_BUDGET=30 FT_SO_SEND_RESERVE=0 FT_RES_ROOT="$RES" FT_RUNTIME_POLICY="${RP:-$POL}" FT_GOV_MD="$HERE/../../skill/references/main-team-governance.md" \
      FT_SEND_VERIFIED="$FAKE/send" FT_MBOX_SH="$FAKE/mbox" FT_REACH_CHECK="$FAKE/reach" FT_PI_SESSIONS_DIR="$TMP/pi-sessions" \
      bash "$so" "$old" "$REPO" --name "$new" "$@" --body-file "$BODY" > "$TMP/out" 2>&1
  RC=$?
}
opened() { grep -c '^tmuxc open' "$LOG" 2>/dev/null; }
case_a() { run "$1" "$A_OLD" "$A_NEW"; grep -q -- "--name byz-t-harness-arch-pi#2 --agent pi --model claude-opus-5-5" "$LOG"; }
case_d() { run "$1" "$D_OLD" "$D_NEW"; [ "$RC" != 0 ] && [ "$(opened)" = 0 ] && [ "$(grep -c '^REJECT 정책표에 역할 없음: byz-t-harness-tester-claude' "$TMP/out")" = 1 ]; }

# ⓐ arch 후계 --agent·--model 생략 → pi · claude-opus-5-5 · 이름 꼬리 -pi#
case_a "$SO" && ok "ⓐ arch 생략 → pi · claude-opus-5-5 · byz-t-harness-arch-pi#2" || bad "ⓐ rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(tr '\n' ' ' < "$TMP/out")"
# ⓑ 나노 → pi deepseek(꼬리가 agent 낱말이 아니면 이름 그대로)
run "$SO" "$N_OLD" "$N_NEW"
grep -q -- "--name byz-t-harness-nano-w#2 --agent pi --model deepseek" "$LOG" \
  && ok "ⓑ nano → pi deepseek" || bad "ⓑ rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(tr '\n' ' ' < "$TMP/out")"
# ⓒ --agent claude 명시 → claude 로 열고 «정책과 다름» 경고 1줄
run "$SO" "$A_OLD" "$A_NEW" --agent claude
{ grep -q -- "--name $A_NEW --agent claude --model claude-opus-5-5" "$LOG" && [ "$(grep -c '정책과 다름' "$TMP/out")" = 1 ]; } \
  && ok "ⓒ --agent claude 명시 → claude 로 열기 · 경고 1줄" || bad "ⓒ rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(tr '\n' ' ' < "$TMP/out")"
# ⓓ 정책표에 역할 없음 → rc≠0 + 이유 1줄 · 열기 0(옛 좌석 agent 로 대체 0)
case_d "$SO" && ok "ⓓ 역할 없음 → rc=$RC · 이유 1줄 · 열기 0" || bad "ⓓ rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(tr '\n' ' ' < "$TMP/out")"
# ⓔ 정책표 파일 없음 → rc≠0 · 열기 0
RP="$TMP/none.tsv" run "$SO" "$A_OLD" "$A_NEW"
{ [ "$RC" != 0 ] && [ "$(opened)" = 0 ] && grep -q '^REJECT 런타임 정책표 없음' "$TMP/out"; } \
  && ok "ⓔ 표 없음 → rc=$RC · 열기 0" || bad "ⓔ rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(tr '\n' ' ' < "$TMP/out")"
# S 실은 표 = 역할 3행(arch·master·nano → pi) · bin·kit 같은 바이트(도구·표 둘 다)
{ [ "$(awk '!/^#/ && NF>=3 && $2=="pi" {print $1}' "$KIT/runtime-policy.tsv" | tr '\n' ' ')" = "arch master nano " ] \
  && cmp -s "$KIT/runtime-policy.tsv" "$HERE/../bin/runtime-policy.tsv" && cmp -s "$KIT/ft-successor-open.sh" "$HERE/../bin/ft-successor-open.sh"; } \
  && ok "S 실은 표 3행 · bin·kit 짝" || bad "S 표·짝 불일치"

# 변이 — 사본 bin 에서 한 줄만 바꾼다
mutant() {   # mutant <이름> <sed 식> → $MUT
  local d="$TMP/mut-$1"; mkdir -p "$d"; cp -R "$BIN/." "$d/"; MUT="$d/ft-successor-open.sh"
  sed -i.bak "$2" "$MUT" && ! cmp -s "$MUT" "$SO"
}
mutant M1 's|AGENT="${_pol%% \*}"; \[|AGENT="${OLD%%#*}"; AGENT="${AGENT##*-}"; [|' && ! case_a "$MUT" \
  && grep -q -- "--agent claude" "$LOG" && ok "M1 옛 좌석 agent 상속 → ⓐ 빨강(잡힘 · claude 로 열림)" || bad "M1 안 잡힘 log=$(tr '\n' ' ' < "$LOG")"
mutant M2 's|\[ -n "$_pol" \] \|\| { echo "REJECT 정책표에 역할 없음.*$|[ -n "$_pol" ] \|\| _pol="claude claude-sonnet-5-5"|' && ! case_d "$MUT" \
  && [ "$(opened)" = 1 ] && ok "M2 역할 없음에 기본값 → ⓓ 빨강(잡힘 · 조용히 열림)" || bad "M2 안 잡힘 out=$(tr '\n' ' ' < "$TMP/out")"

echo "RUN 전체 $(( $(date +%s) - T_START ))초"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
