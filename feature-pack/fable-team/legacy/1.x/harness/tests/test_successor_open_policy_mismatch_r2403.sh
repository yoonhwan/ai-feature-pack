#!/usr/bin/env bash
# test_successor_open_policy_mismatch_r2403.sh — r2403: 좌석 모델은 정책표 한 곳에서만 정한다 — 올림 행(--tier up) + 손 입력 대조 REJECT + --verdict 풀 길.
#   ① --tier up(agent·model 생략) → arch@up 값 pi · claude-fable-5-2 · 이름 꼬리 pi / 올림 행 뺀 표 → REJECT rc2 · 열기 0
#   ② --agent claude --model claude-fable-5-1 → REJECT rc1 · 표 값 2개 · 열기 0 · 쪽지 0(기준판 = WARN 뒤 열림 → Red)
#   ③ --agent pi --model claude-fable-5-2 → 열림 / --agent pi --model claude-opus-5-5[1m] → 열림(기본 행 · 창 꼬리 뗌)
#   ④ ② + --verdict 4500 → WARN 1줄 · 열림 | ⑤ 기본 행 없는 역할(da) → 지금처럼 열림(대조 0)
#   변이 M1(model 대조 뺌) → ② 빨강 · M2(창 꼬리 떼기 뺌) → ③ 빨강 · M3(--verdict 분기 지움) → ④ 빨강 · M5(올림 행을 기본 행으로) → ① 빨강
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
printf 'import sys\nsys.exit(0)\n' > "$BIN/ft_teamset.py"   # arch 상시 게이트 = 이 시험 범위 밖(통과 · r1569 시험과 같은 스텁)
REPO="$TMP/repo"; FAKE="$TMP/fakebin"; LOG="$TMP/calls.log"; BODY="$TMP/body.txt"; OPENED="$TMP/opened"
mkdir -p "$REPO/.fable-team" "$FAKE" "$TMP/live-root"; git -C "$REPO" init -q
printf '%s\n' "$TMP/live-root" > "$REPO/.fable-team/LIVE_ROOT"
mkstub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$FAKE/$1"; chmod +x "$FAKE/$1"; }
mkstub tmux  'case "$1" in has-session) [ -f "$OPENED" ] && exit 0; exit 1;; list-panes) echo 4242;; display-message) echo "$PANE_CWD";; esac; exit 0'
mkstub tmuxc 'echo "tmuxc $*" >> "$LOG"; : > "$OPENED"; exit 0'
mkstub pgrep 'case "$*" in "-a -x claude"|"-a -x codex"|"-a -x pi") exec "$SENSORS/pgrep" "$@";; esac; echo 5555; exit 0'
mkstub send  'echo "QUEUED seq=777 to=$1 pending=1 doorbell=sent"; exit 0'
mkstub mbox  'echo "RING seq=$3 doorbell=sent"; exit 0'
: > "$FAKE/mbox_doorbell.sh"
mkstub reach 'exit 0'
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$TMP/sensors" ok; SENSORS="$TMP/sensors/fake-sensors"; RES="$FT_RES_ROOT"
printf '골 1\n골 2\n골 3\n본문\n열린 칸 감시: 없음\n' > "$BODY"
# 시험 표 = 기본 행 2 + 올림 행 2(카드 ①~⑤ 그대로 · da 는 기본 행 없이 올림 행만 = ⑤ 의 «기본 행 없는 역할»)
POL="$TMP/policy.tsv"
printf '# 시험 정책표\narch\tpi\tclaude-opus-5-5\nmaster\tpi\tclaude-opus-5-5\narch@up\tpi\tclaude-fable-5-2\nda@up\tcodex\tgpt-6-astra\n' > "$POL"
POLNOUP="$TMP/policy-noup.tsv"; grep -v '@up' "$POL" > "$POLNOUP"

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
sent()   { grep -cE '^(QUEUED|RING)' "$TMP/out" 2>/dev/null; }

A_OLD='byz-t-arch-claude#1'; A_NEW='byz-t-arch-claude#2'      # 정책표 판독이 꼬리를 -pi 로 바꾼다(①)
H_OLD='byz-t-arch-claude#8'; H_NEW='byz-t-arch-claude#9'      # 손 입력 --agent claude(②④)
P_OLD='byz-t-arch-pi#2';     P_NEW='byz-t-arch-pi#3'          # 손 입력 --agent pi(③)
D_OLD='byz-t-da-codex#2';    D_NEW='byz-t-da-codex#3'         # 기본 행 없는 역할(⑤)

# ① --tier up · agent·model 생략 → arch@up 값 · 이름 꼬리 pi
case1() { RP="$POL" run "$1" "$A_OLD" "$A_NEW" --tier up
  [ "$RC" = 0 ] && grep -q 'RUNTIME 정책표 → agent=pi model=claude-fable-5-2' "$TMP/out" \
    && grep -q -- "--name byz-t-arch-pi#2 --agent pi --model claude-fable-5-2" "$LOG"; }
# ①-b 올림 행을 뺀 표 → REJECT rc2 · 열기 0
case1b() { RP="$POLNOUP" run "$1" "$A_OLD" "$A_NEW" --tier up
  [ "$RC" = 2 ] && [ "$(opened)" = 0 ] && grep -q '^REJECT 정책표에 올림 행 없음' "$TMP/out"; }
# ② 표와 다른 손 입력(5-1) → REJECT rc1 · 표 값 2개 · 열기 0 · 쪽지 0
case2() { run "$1" "$H_OLD" "$H_NEW" --agent claude --model claude-fable-5-1
  [ "$RC" = 1 ] && [ "$(opened)" = 0 ] && [ "$(sent)" = 0 ] && grep -q '^REJECT 정책표와 다름' "$TMP/out" \
    && grep -q 'claude-opus-5-5' "$TMP/out" && grep -q 'claude-fable-5-2' "$TMP/out"; }
case2m() { run "$1" "$H_OLD" "$H_NEW" --agent pi --model claude-fable-5-1   # M1 이 잡아야 하는 구(model 만 다름)
  [ "$RC" = 1 ] && [ "$(opened)" = 0 ] && grep -q '^REJECT 정책표와 다름' "$TMP/out"; }
# ③ 올림 행 값 그대로 → 열림 / 기본 행 + 창 꼬리 [1m] → 열림
case3a() { run "$1" "$P_OLD" "$P_NEW" --agent pi --model claude-fable-5-2
  [ "$RC" = 0 ] && [ "$(opened)" = 1 ]; }
case3b() { run "$1" "$P_OLD" "$P_NEW" --agent pi --model 'claude-opus-5-5[1m]'
  [ "$RC" = 0 ] && [ "$(opened)" = 1 ]; }
# ④ --verdict = 사람 판정 → WARN 1줄 · 열림
case4() { run "$1" "$H_OLD" "$H_NEW" --agent claude --model claude-fable-5-1 --verdict 4500
  [ "$RC" = 0 ] && [ "$(opened)" = 1 ] && [ "$(grep -c '^WARN 정책표와 다름' "$TMP/out")" = 1 ]; }
# ⑤ 기본 행이 없는 역할 = 대조 0 → 지금처럼 열림
case5() { run "$1" "$D_OLD" "$D_NEW" --agent codex --model gpt-5.6-sol
  [ "$RC" = 0 ] && [ "$(opened)" = 1 ]; }

case1 "$SO"  && ok "① --tier up → pi · claude-fable-5-2 · 꼬리 pi" || bad "① rc=$RC out=$(tr '\n' ' ' < "$TMP/out") log=$(tr '\n' ' ' < "$LOG")"
case1b "$SO" && ok "①-b 올림 행 없는 표 + --tier up → rc=$RC · 열기 0" || bad "①-b rc=$RC out=$(tr '\n' ' ' < "$TMP/out")"
case2 "$SO"  && ok "② 5-1 손 입력 → rc=$RC · 표 값 2개 · 열기 0 · 쪽지 0" || bad "② rc=$RC out=$(tr '\n' ' ' < "$TMP/out") log=$(tr '\n' ' ' < "$LOG")"
case2m "$SO" && ok "②-b agent pi · model 5-1 손 입력 → rc=$RC · 열기 0" || bad "②-b rc=$RC out=$(tr '\n' ' ' < "$TMP/out")"
case3a "$SO" && ok "③ --model 올림 값 → 열림" || bad "③-a rc=$RC out=$(tr '\n' ' ' < "$TMP/out")"
case3b "$SO" && ok "③-b --model 기본 값 + [1m] → 열림(창 꼬리 뗌)" || bad "③-b rc=$RC out=$(tr '\n' ' ' < "$TMP/out")"
case4 "$SO"  && ok "④ --verdict 4500 → WARN 1줄 · 열림" || bad "④ rc=$RC out=$(tr '\n' ' ' < "$TMP/out")"
case5 "$SO"  && ok "⑤ 기본 행 없는 da → 열림(대조 0)" || bad "⑤ rc=$RC out=$(tr '\n' ' ' < "$TMP/out")"

# ── 변이: 사본에서 한 줄만 지우고 같은 사례를 돌려 «잡힘» 을 본다 ──
mutant() {   # mutant <이름> <바꿀 글자> <바꿔 넣을 글자> → $MUT
  local d="$TMP/mut-$1"; mkdir -p "$d"; cp -R "$BIN/." "$d/"; MUT="$d/ft-successor-open.sh"
  python3 - "$MUT" "$2" "$3" <<'PY' || return 1
import sys
p, a, b = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
n = s.replace(a, b, 1)
if n == s: print("변이 미적용: " + a); sys.exit(1)
open(p, "w", encoding="utf-8").write(n)
PY
}
mutant M1 '&& [ "$_mc" = "${_p#* }" ] ' '' && ! case2m "$MUT" \
  && ok "M1 model 대조 뺌 → ② 빨강(잡힘)" || bad "M1 안 잡힘 out=$(tr '\n' ' ' < "$TMP/out")"
mutant M2 '_mc="${MODEL%%\[*}"' '_mc="$MODEL"' && ! case3b "$MUT" \
  && ok "M2 창 꼬리 떼기 뺌 → ③ 빨강(잡힘)" || bad "M2 안 잡힘 out=$(tr '\n' ' ' < "$TMP/out")"
mutant M3 'if [ -n "$VERDICT" ]; then' 'if false; then' && ! case4 "$MUT" \
  && ok "M3 --verdict 분기 지움 → ④ 빨강(잡힘)" || bad "M3 안 잡힘 out=$(tr '\n' ' ' < "$TMP/out")"
mutant M5 '_row="$_pol"; [ "$TIER" = up ] && _row="$_polup"' '_row="$_pol"' && ! case1 "$MUT" \
  && ok "M5 올림 행을 기본 행으로 → ① 빨강(잡힘)" || bad "M5 안 잡힘 out=$(tr '\n' ' ' < "$TMP/out")"

# S 실은 표 = 올림 행 2(arch@up · da@up) · bin·kit 같은 바이트(도구·표 둘 다)
{ [ "$(awk '!/^#/ && NF>=3 && $1 ~ /@up$/ {print $1}' "$KIT/runtime-policy.tsv" | tr '\n' ' ')" = "arch@up da@up " ] \
  && [ "$(awk '!/^#/ && NF>=3 && $1=="arch@up" {print $2, $3}' "$KIT/runtime-policy.tsv")" = "pi claude-fable-5-2" ] \
  && cmp -s "$KIT/runtime-policy.tsv" "$HERE/../bin/runtime-policy.tsv" && cmp -s "$KIT/ft-successor-open.sh" "$HERE/../bin/ft-successor-open.sh"; } \
  && ok "S 실은 표 올림 행 2 · arch@up = pi claude-fable-5-2 · bin·kit 짝" || bad "S 표·짝 불일치"

echo "RUN 전체 $(( $(date +%s) - T_START ))초"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
