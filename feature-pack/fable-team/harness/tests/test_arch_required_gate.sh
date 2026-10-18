#!/usr/bin/env bash
# test_arch_required_gate.sh — R342: «arch 상시» 팀(TEAMSET 표)의 `_arch` 좌석이 없거나 죽어 있으면
#   ①ft-teamset-check ERR ②ft-successor-open(master·desk 교대) REJECT ③ft-autonomy on(planner) REJECT — 판정기 하나 = ft_teamset.py arch-live.
# 전부 mktemp 안 — 가짜 TEAMSET·가짜 명부·가짜 tmux/tmuxc(PATH)·임시 재개 기록·임시 상태 폴더. 실 tmux·실 자율 전환 0.
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/scripts/fable-team-bin"; KIT="$REPO/scripts/harness-install/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

MD="$T/TEAMSET.md"; ROOT="$T/root"; FAKE="$T/fake"; SESS="$T/sessions.txt"; RES="$T/resume"; LOG="$T/calls.log"
mkdir -p "$ROOT/.fable-team/state" "$FAKE" "$RES"
cat > "$MD" <<'EOF'
# 가짜 팀셋
## 표 1 — 역할 표준
| 역할 | 수 | 모델 | effort | 명부 키 | 승계 | 닫기 |
|---|---|---|---|---|---|---|
| master | 필수 1 | `sonnet-5-5` | high | `_master` | a | b |
| arch | 상시 팀만 1 | `opus-5-5` | high | `_arch` | a | b |
| desk | planner 팀만 1 | `opus-5-5` | high | `_desk` | a | b |
- 나노 상한 기본: 3
- 명부 역할 키(표 1 «명부 키» 열): `_master` `_arch` `_desk`
- 명부 공용 키: `_name` `_doc` `_closed`
## 표 2 — 팀별 덮어쓰기
| 팀 | 나노 상한 | tester | arch 상시 |
|---|---|---|---|
| planner | 3 | 0 | 상시 |
| issues | 3 | 0 | 없음 |
EOF
printf '#!/bin/sh\ncase "$1" in list-sessions) cat %s;; list-panes) echo 4242;; *) exit 0;; esac\n' "$SESS" > "$FAKE/tmux"
printf '#!/bin/sh\necho "tmuxc $*" >> %s\nexit 1\n' "$LOG" > "$FAKE/tmuxc"
for x in send mbox reach; do printf '#!/bin/sh\nexit 1\n' > "$FAKE/$x"; done
chmod 755 "$FAKE"/*
sess() { : > "$SESS"; for n in "$@"; do echo "$n" >> "$SESS"; done; }
# roster <팀> <_master> [<_arch>|-] [<_desk>] — _arch 가 - 이면 칸 없음
roster() {
  local arch=""; [ "${3:--}" != "-" ] && arch=",\"_arch\":\"$3\""
  local desk=""; [ -n "${4:-}" ] && desk=",\"_desk\":\"$4\""
  printf '{"_name":"%s","_master":"%s"%s%s}\n' "$1" "$2" "$arch" "$desk" > "$ROOT/.fable-team/seats-$1.json"
}
FS="$T/fake-status.sh"; printf '#!/bin/sh\necho "IDLE - - - jsonl"\n' > "$FS"
FM="$T/fake-mbox.sh"; printf '#!/bin/sh\nexit 0\n' > "$FM"
chk() { FT_TEAMSET_MBOX="$FM" FT_SEAT_STATUS="$FS" PATH="$FAKE:$PATH" FT_TEAMSET_ROOT="$ROOT" FT_TEAMSET_MD="$MD" ZC_RESUME_DIR="$RES" bash "$BIN/ft-teamset-check.sh" "$@" 2>&1; }

M="byz-planner-master-claude#1"; A="byz-planner-arch-claude#1"; D="byz-planner-desk-claude#1"

# ── ①②③ ft-teamset-check ──
roster planner "$M" -
sess "$M"
o="$(chk planner)"; rc=$?
{ [ "$rc" = 1 ] && [[ "$o" == "planner ERR "*"arch 없음"* ]]; } && ok "① arch 상시 팀 · _arch 칸 없음 → ERR rc1: $o" || bad "① rc=$rc $o"

roster planner "$M" "$A"
sess "$M"
o="$(chk planner)"; rc=$?
{ [ "$rc" = 1 ] && [[ "$o" == "planner ERR "*"arch"*"라이브 아님"* ]]; } && ok "② _arch 있으나 tmux 0 → ERR rc1: $o" || bad "② rc=$rc $o"

printf '{"session":"%s","uuid":"u"}\n' "$A" > "$RES/$A.json"
o="$(chk planner)"; rc=$?
{ [ "$rc" = 1 ] && [[ "$o" == "planner ERR "*"arch"*"라이브 아님"* ]]; } && ok "②-b 재개 기록만 있고 tmux 없는 arch = 죽음 → ERR (DA ⓒ)" || bad "②-b rc=$rc $o"
rm -f "$RES/$A.json"

sess "$M" "$A"
o="$(chk planner)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == "planner OK "* ]]; } && ok "②-c _arch 라이브 → OK rc0" || bad "②-c rc=$rc $o"

roster issues "byz-issues-master-claude#1" -
sess "byz-issues-master-claude#1"
o="$(chk issues)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == "issues OK "* ]]; } && ok "③ 표 «없음» 팀(issues) · _arch 없어도 → OK rc0 (영향 0)" || bad "③ rc=$rc $o"

# ── ④⑤ ft-successor-open ──
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$T/sensors" ok
SRES="$FT_RES_ROOT"; mkdir -p "$SRES/.fable-team"
printf '골 1\n골 2\n골 3\n본문\n' > "$T/body.txt"; git init -q "$T/wt"
so() { # so <구> <후계> — 임시 루트(FT_RES_ROOT)의 명부를 본다 · tmuxc 는 실패 스텁(통과 시 열기 단계에서 멈춘다)
  : > "$LOG"
  cp "$ROOT/.fable-team/seats-planner.json" "$SRES/.fable-team/seats-planner.json"
  env HOME="$T/home" PATH="$FAKE:$PATH" FT_RES_ROOT="$SRES" FT_TEAMSET_MD="$MD" FT_SO_POLL=0 FT_SO_WAIT_MAX=1 \
      FT_SEND_VERIFIED="$FAKE/send" FT_MBOX_SH="$FAKE/mbox" FT_REACH_CHECK="$FAKE/reach" \
      bash "$BIN/ft-successor-open.sh" "$1" "$T/wt" --name "$2" --agent claude --model m --body-file "$T/body.txt" > "$T/out" 2>&1
  RC=$?
}
tmuxc_calls() { grep -c '^tmuxc' "$LOG"; }

roster planner "$M" "$A" "$D"
sess "$M" "$D"
so "$M" "byz-planner-master-claude#2"
{ [ "$RC" -ne 0 ] && grep -q 'REJECT' "$T/out" && grep -q 'arch 좌석 없음' "$T/out" && [ "$(tmuxc_calls)" = 0 ]; } \
  && ok "④ master 교대 · arch 죽음 → REJECT · tmuxc open 0" || bad "④ rc=$RC calls=$(tmuxc_calls) out=$(cat "$T/out")"
so "$D" "byz-planner-desk-claude#2"
{ [ "$RC" -ne 0 ] && grep -q 'arch 좌석 없음' "$T/out" && [ "$(tmuxc_calls)" = 0 ]; } \
  && ok "④-b desk 교대 · arch 죽음 → REJECT · tmuxc open 0" || bad "④-b rc=$RC out=$(cat "$T/out")"

sess "$M" "$A" "$D"
so "$M" "byz-planner-master-claude#2"
{ ! grep -q 'arch 좌석 없음' "$T/out" && [ "$(tmuxc_calls)" = 1 ]; } \
  && ok "④-c master 교대 · arch 라이브 → 통과(열기 단계까지)" || bad "④-c rc=$RC calls=$(tmuxc_calls) out=$(cat "$T/out")"

sess "$M" "$D"
so "$A" "byz-planner-arch-claude#2"
{ ! grep -q 'arch 좌석 없음' "$T/out" && [ "$(tmuxc_calls)" = 1 ]; } \
  && ok "⑤ arch 자신의 교대 · arch 죽음이어도 통과(교착 0)" || bad "⑤ rc=$RC calls=$(tmuxc_calls) out=$(cat "$T/out")"

# ⑦ (DA⑥ r1 H1) 이름순으로 앞선 다른 명부가 planner master 를 «참조 키»(_hil_route·_parent)로 갖고 있어도 소속 판정이 새지 않는다
printf '{"_name":"aaa","_master":"byz-aaa-master-claude#1","_hil_route":"%s","_parent":"%s"}\n' "$M" "$M" > "$SRES/.fable-team/seats-aaa.json"
roster planner "$M" "$A" "$D"; sess "$M" "$D"
so "$M" "byz-planner-master-claude#2"
{ [ "$RC" -ne 0 ] && grep -q 'arch 좌석 없음' "$T/out" && [ "$(tmuxc_calls)" = 0 ]; } \
  && ok "⑦ 앞선 명부의 교차 _hil_route · planner arch 죽음 → 여전히 REJECT(우회 0)" || bad "⑦ rc=$RC out=$(cat "$T/out")"
sess "$M" "$A" "$D"
o="$(PATH="$FAKE:$PATH" python3 "$BIN/ft_teamset.py" arch-live --root "$SRES" --md "$MD" --seat "$M" 2>&1)"; rc=$?
{ [ "$rc" = 0 ] && [ "$o" = "OK planner _master" ]; } && ok "⑦-b arch 라이브 → OK planner _master (참조 키 명부 건너뜀)" || bad "⑦-b rc=$rc $o"
o="$(PATH="$FAKE:$PATH" python3 "$BIN/ft_teamset.py" arch-live --root "$SRES" --md "$MD" --seat "byz-aaa-master-claude#1" 2>&1)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == "OK aaa _master" ]]; } && ok "⑦-c 표에 없는 팀 master → OK(영향 0)" || bad "⑦-c rc=$rc $o"
rm -f "$SRES/.fable-team/seats-aaa.json"

roster issues "byz-issues-master-claude#1" -
cp "$ROOT/.fable-team/seats-issues.json" "$SRES/.fable-team/seats-issues.json"
sess "byz-issues-master-claude#1"
so "byz-issues-master-claude#1" "byz-issues-master-claude#2"
{ ! grep -q 'arch 좌석 없음' "$T/out" && [ "$(tmuxc_calls)" = 1 ]; } \
  && ok "⑤-b 표 «없음» 팀 master 교대 → 통과" || bad "⑤-b rc=$RC calls=$(tmuxc_calls) out=$(cat "$T/out")"
rm -f "$SRES/.fable-team/seats-issues.json" "$SRES/.fable-team/seats-planner.json"

# ── ⑥ ft-autonomy on ──
AS="$T/astate"; AP="$T/aplanner"; mkdir -p "$AS" "$AP"
au() { env PATH="$FAKE:$PATH" FT_ROOT="$ROOT" FT_AUTONOMY_STATE_DIR="$AS" FT_PLANNER_DIR="$AP" FT_TEAMSET_MD="$MD" HIL_DIR="$T" bash "$BIN/ft-autonomy.sh" "$@" 2>&1; }
roster planner "$M" "$A" "$D"
sess "$M" "$D"
o="$(au on)"; rc=$?
{ [ "$rc" = 2 ] && [[ "$o" == *REJECT*"planner arch 없음"* ]] && [ ! -e "$AS/autonomy.json" ] && [ ! -e "$AS/autonomy.log" ] && [ ! -e "$AS/.autonomy.lock" ]; } \
  && ok "⑥ planner arch 죽음 → on REJECT rc2 · json·log·lock 0(상태 불변)" || bad "⑥ rc=$rc $o / $(ls -A "$AS")"
sess "$M" "$A" "$D"
o="$(au on)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *"자율 ON"* ]] && [ -f "$AS/autonomy.json" ]; } && ok "⑥-b planner arch 라이브 → on 통과" || bad "⑥-b rc=$rc $o"
au off >/dev/null; rm -f "$AS"/autonomy.*
rm -f "$ROOT/.fable-team/seats-planner.json"; sess
o="$(au on)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *"자율 ON"* ]]; } && ok "⑥-c planner 명부 없는 환경(개인 리포·시험 루트) → on 통과(검사 대상 아님)" || bad "⑥-c rc=$rc $o"

# ── 키트 사본 cmp 0 · bash/py 문법 ──
for f in ft-teamset-check.sh ft_teamset.py ft-successor-open.sh ft-autonomy.sh; do cmp -s "$BIN/$f" "$KIT/$f" && ok "키트 사본 cmp 0 $f" || bad "키트 사본 불일치 $f"; done
for f in ft-teamset-check.sh ft-successor-open.sh ft-autonomy.sh; do bash -n "$BIN/$f" && ok "bash -n $f" || bad "bash -n $f"; done
python3 -m py_compile "$BIN/ft_teamset.py" && ok "py_compile ft_teamset.py" || bad "py_compile ft_teamset.py"
[ "$(git config --get core.bare)" = false ] && ok "core.bare=false" || bad "core.bare != false"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit $fail
