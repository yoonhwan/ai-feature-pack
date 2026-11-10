#!/usr/bin/env bash
# test_role_spawn_team_from_caller_r1244.sh — r1244: ft-role-spawn.sh 팀 기본값 = «부른 좌석 팀»(v65 고정 아님) · 못 읽으면 REJECT rc2.
#   R1 FT_SEND_FROM=byz-ops-master-claude#77 · --team 없음 · tester --dry-run → seats-ops.json · 이름 byz-ops-tester-claude#N · `team=ops(부른 좌석 …)` 1줄
#   R2 ops 좌석이 --team v65 명시 → v65(명시 우선)
#   R3 FT_SEND_FROM 없음 · --from 없음 · --team 없음 → REJECT «--team 필수» rc2
#   R4 FT_SEND_FROM=byz-v65-master-claude#262 · --team 없음 → 지금과 같은 v65 결과(회귀)
#   R5 FT_SEND_FROM=dispatch(좌석 이름 아님) · --team 없음 → REJECT rc2
# 전부 mktemp 안 — 가짜 tmux/tmuxc(PATH)·가짜 송신·가짜 자원 센서. 실 tmux·실 명부·실 쪽지 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1 FT_TEAMSET=0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_ROLE_BASE_PREFIX FT_PENALTY_TEAM FT_SEND_FROM
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$T/sensors" ok

bash -n "$KIT/ft-role-spawn.sh" && ok "bash -n ft-role-spawn.sh" || bad "bash -n ft-role-spawn.sh"
cmp -s "$KIT/ft-role-spawn.sh" "$HERE/../bin/ft-role-spawn.sh" && ok "bin·kit 같은 판" || bad "bin·kit 다름"

# ── 픽스처: 임시 리포 · TEAMS.md(v65 꼴1 · ops 꼴2) · 명부 2장 · 팀 폴더 ──
R="$T/repo"; B="$T/bin"; FK="$T/fake"; mkdir -p "$R/.fable-team" "$B" "$FK"
git init -q "$R"; mkdir -p "$R/design"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| v65 | `design/v65/` | x | 현역 |\n| ops | `design/teams/ops/` | x | 현역 |\n' > "$R/design/TEAMS.md"
mkdir -p "$R/design/v65/indices/inbox/tester" "$R/design/teams/ops/indices/inbox/tester"
: > "$R/design/v65/SEATBELT-README.md"; : > "$R/design/teams/ops/SEATBELT-README.md"
printf '{"_master":"byz-v65-master-claude#262","byz-v65-tester-claude#2":{"role":"tester","agent":"claude","tick":null},"_tester":"byz-v65-tester-claude#2"}\n' > "$R/.fable-team/seats.json"
printf '{"_name":"ops","_master":"byz-ops-master-claude#77"}\n' > "$R/.fable-team/seats-ops.json"

# 실행본 = 키트 사본 + 가짜 송신(실 쪽지 0)
for f in ft-role-spawn.sh ft-team-lib.sh ft_raised.py ft-resource-gate.sh ft-resource-swap-lib.sh ft-reclaim-capped.sh ft_teamset.py ft_team_lib.py ft_spawn_queue.py ft-resource-sample.sh ft-harness-root.sh; do cp -p "$KIT/$f" "$B/"; done
printf '#!/usr/bin/env bash\nexit 0\n' > "$B"/ft-all-stop.sh
printf '#!/bin/bash\necho "SENT $*"\nexit 0\n' > "$B/ft-send-verified.sh"
chmod +x "$B"/*
# 가짜 tmuxc/tmux: dry-run 만 쓰므로 open 외 호출은 0 — 그래도 있으면 통과시킨다
printf '#!/bin/bash\n[ "$1" = open ] && { echo "TMUXC-DRY"; exit 0; }\nexit 0\n' > "$FK/tmuxc"
printf '#!/bin/bash\ncase "$1" in has-session) exit 1;; esac\nexit 0\n' > "$FK/tmux"   # 없는 세션 → «번호 이어받기» 루프가 멈춘다
chmod +x "$FK"/*
rs() { (cd "$R" && PATH="$FK:$PATH" bash "$B/ft-role-spawn.sh" "$@" 2>&1); }   # env -u 는 호출마다 앞에 붙인다

# ── R1 부른 좌석 팀이 기본 ──
o="$(FT_SEND_FROM='byz-ops-master-claude#77' rs tester --dry-run)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *"team=ops(부른 좌석 byz-ops-master-claude#77)"* ]] \
  && [[ "$o" == *"PLAN seat=byz-ops-tester-claude#0 role=tester"* ]] \
  && [[ "$o" == *"inbox=design/teams/ops/indices/inbox/tester"* ]] && [[ "$o" != *"design/v65"* ]]; } \
  && ok "R1 ops 좌석 → team=ops · seats-ops.json · byz-ops-tester-claude#0" || bad "R1 rc=$rc $o"
# R1-b: --from 도 «부른 좌석» 자리다(FT_SEND_FROM 없음)
o="$(rs tester --from 'byz-ops-master-claude#77' --dry-run)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *"team=ops(부른 좌석 byz-ops-master-claude#77)"* ]] && [[ "$o" == *"seat=byz-ops-tester-claude#0"* ]]; } \
  && ok "R1-b --from 으로도 팀을 읽는다" || bad "R1-b rc=$rc $o"

# ── R2 명시가 이김 ──
o="$(FT_SEND_FROM='byz-ops-master-claude#77' rs tester --team v65 --dry-run)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *"team=v65(--team)"* ]] && [[ "$o" == *"PLAN seat=byz-v65-tester-claude#3 role=tester"* ]] \
  && [[ "$o" == *"inbox=design/v65/indices/inbox/tester"* ]]; } \
  && ok "R2 ops 좌석 + --team v65 → v65(명시 우선)" || bad "R2 rc=$rc $o"

# ── R3 부른 좌석 없음 = REJECT ──
o="$(env -u FT_SEND_FROM bash -c 'cd "$1" && PATH="$2:$PATH" bash "$3" tester --dry-run 2>&1' _ "$R" "$FK" "$B/ft-role-spawn.sh")"; rc=$?
{ [ "$rc" = 2 ] && [[ "$o" == *"REJECT --team 필수(부른 좌석 팀을 못 읽음"* ]] && [[ "$o" != *"PLAN "* ]]; } \
  && ok "R3 좌석 이름 없음 → REJECT --team 필수 rc2" || bad "R3 rc=$rc $o"

# ── R4 v65 좌석 = 지금과 같은 결과(회귀) ──
o="$(FT_SEND_FROM='byz-v65-master-claude#262' rs tester --dry-run)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *"team=v65(부른 좌석 byz-v65-master-claude#262)"* ]] \
  && [[ "$o" == *"PLAN seat=byz-v65-tester-claude#3 role=tester"*"replaces=[byz-v65-tester-claude#2]"* ]]; } \
  && ok "R4 v65 좌석 → v65(회귀 0)" || bad "R4 rc=$rc $o"

# ── R5 좌석 이름이 아님 = REJECT ──
o="$(FT_SEND_FROM='dispatch' rs tester --dry-run)"; rc=$?
{ [ "$rc" = 2 ] && [[ "$o" == *"REJECT --team 필수(부른 좌석 팀을 못 읽음: dispatch)"* ]]; } \
  && ok "R5 dispatch(좌석 아님) → REJECT rc2" || bad "R5 rc=$rc $o"
# R5-b: '#' 없는 이름도 REJECT
o="$(FT_SEND_FROM='byz-ops-master-claude' rs tester --dry-run)"; rc=$?
{ [ "$rc" = 2 ] && [[ "$o" == *"REJECT --team 필수"* ]]; } && ok "R5-b #N 없음 → REJECT rc2" || bad "R5-b rc=$rc $o"

# ── 변이 대응: 풀기 «끔»(v65 고정) 이면 R1 이 v65 로 떨어진다 ──
MUT="$T/mut"; mkdir -p "$MUT"; cp -p "$B"/* "$MUT/" 2>/dev/null
python3 - "$MUT/ft-role-spawn.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
s = s.replace('TEAM="$_team"; TEAM_FROM="부른 좌석 $_caller"', 'TEAM="v65"; TEAM_FROM="변이"')
open(p, "w", encoding="utf-8").write(s)
PY
mo="$(cd "$R" && FT_SEND_FROM='byz-ops-master-claude#77' PATH="$FK:$PATH" bash "$MUT/ft-role-spawn.sh" tester --dry-run 2>&1)"; mrc=$?
{ [ "$mrc" = 0 ] && [[ "$mo" == *"seat=byz-v65-tester-claude#3"* ]] && [[ "$mo" != *"seat=byz-ops-tester-claude#0"* ]]; } \
  && ok "변이(풀기 끔) → R1 이 v65 = 이 시험은 FAIL 한다" || bad "변이가 안 걸린다 rc=$mrc $mo"

# ── 바꾼 줄에 600/300 초 0 (7초 룰) ──
n="$(git -C "$HERE/.." diff origin/main -- kit/fable-team/bin/ft-role-spawn.sh 2>/dev/null | grep '^+' | grep -cE '\b(600|300)\b')"
[ "$n" = 0 ] && ok "바꾼 줄 600/300 0" || bad "바꾼 줄에 600/300 $n곳"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
