#!/usr/bin/env bash
# test_role_spawn_ft_root_r1404.sh — r1404: ft-role-spawn 의 «데이터 루트» = env FT_ROOT 먼저 · «명부» = TEAMS.md 명부 칸(ft_team_lib.roster_path)
#   K1 kakao 꼴(워크트리 = 데이터 루트 · 공용 루트엔 state 만) + FT_ROOT=<워크트리> → --dry-run rc0 · 명부 = <워크트리>/.fable-team/seats.json
#   K2 같은 꼴 · TEAMS.md «명부» 칸 = seats.json(기본 규칙이면 seats-kakao.json) → seats.json 을 읽는다
#   K3 BYZ 꼴 · FT_ROOT 없음 → 지금과 같음(공용 루트 · seats-<팀>.json — 명부 칸 없는 명단은 옛 규칙)
#   K4 BYZ 꼴 · v65 → seats.json (지금과 같음)
#   K5 FT_ROOT 에 .fable-team 없음 → REJECT «FT_ROOT 에 .fable-team 없음» rc1 · 부작용 0
#   K6 TEAMS.md 못 읽음 → REJECT «팀 명단 판정 불가» rc1 · 부작용 0
#   K7 kakao 실사건 꼴 — cwd(데이터 루트)가 깃 최상위가 «아닌» 하위 폴더 → 팀 폴더도 데이터 루트에서 푼다(README·inbox·index 상대경로)
# 판정 근거는 «동작» 하나 — BODY 의 수신자 = 명부 _master 의 현역 해석(ft_from_current):
#   옳은 명부를 읽으면 _master 세대, 틀린 명부(디코이)를 읽으면 디코이 세대가 찍힌다. 도구에 디버그 줄을 더하지 않는다.
# FT_SPAWN_BIN=<경로> 로 «다른 판»(기준판·변이)을 같은 시험으로 돌린다 — 기본 = 팩 harness/bin/ft-role-spawn.sh.
# 전부 mktemp 안 — 가짜 tmux/tmuxc(PATH)·가짜 송신·가짜 자원 센서. 실 tmux·실 명부·실 쪽지·실 좌석 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1 FT_TEAMSET=0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_ROOT FT_PENALTY_TEAM FT_ROLE_BASE_PREFIX FT_MBOX_DIR FT_SEATS_JSON
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="${FT_SPAWN_BIN:-$HERE/../bin/ft-role-spawn.sh}"
[ -f "$SRC" ] || { echo "REJECT 시험 대상 없음: $SRC"; exit 2; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
B="$T/bin"; FK="$T/fake"; mkdir -p "$B" "$FK"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$T/sensors" ok

bash -n "$SRC" && ok "bash -n 시험 대상($SRC)" || bad "bash -n 시험 대상($SRC)"
cmp -s "$HERE/../bin/ft-role-spawn.sh" "$HERE/../kit/fable-team/bin/ft-role-spawn.sh" \
  && ok "bin·kit 두 벌 같은 파일" || bad "bin·kit 두 벌이 다르다(같은 줄을 두 곳에)"

# 실행본 사본(+ 옆 도구) — 송신·tmux 는 가짜
for f in ft-team-lib.sh ft_raised.py ft-resource-gate.sh ft-resource-swap-lib.sh ft-reclaim-capped.sh ft_teamset.py \
         ft_team_lib.py ft_spawn_queue.py ft-resource-sample.sh ft-harness-root.sh; do cp -p "$HERE/../bin/$f" "$B/"; done
cp -p "$SRC" "$B/ft-role-spawn.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$B/ft-all-stop.sh"   # r626: .fable-team 이 있으면 늘 전팀 정지 check — 이 시험 주제 밖(통과 스텁)
OPENED="$T/opened"; : > "$OPENED"
printf '#!/bin/bash\n[ "$1" = open ] || exit 0\nd=0; while [ $# -gt 0 ]; do [ "$1" = --dry-run ] && d=1; shift; done\n[ "$d" = 1 ] && { echo "TMUXC-DRY"; exit 0; }\n' > "$FK/tmuxc"
printf '#!/bin/bash\ncase "$1" in has-session) exit 1;; list-sessions) exit 0;; *) exit 0;; esac\n' > "$FK/tmux"
printf '#!/bin/bash\necho "SENT $*"\nexit 0\n' > "$B/ft-send-verified.sh"
chmod +x "$B"/* "$FK"/*

# ── 픽스처 A: kakao 꼴 — 공용 루트(KakaoBot) + 워크트리(데이터 루트) ──
KA="$T/kakaobot"; W2="$KA/.worktrees/kakao"
mkdir -p "$KA/design" "$KA/.fable-team/state"
git init -q "$KA"
cat > "$KA/design/TEAMS.md" <<'EOF'
# 팀 명단 — kakao 루트 (가짜)
| 팀 | 폴더 | 오케 좌석 계열 | 상태 | 명부 |
|---|---|---|---|---|
| kakao | `design/kakao/` | byz-kakao-master-claude | 현역 | seats.json |
EOF
git -C "$KA" add -A >/dev/null 2>&1; git -C "$KA" -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1
git -C "$KA" worktree add -q "$W2" -b bootstrap >/dev/null 2>&1
mkdir -p "$W2/.fable-team/comm" "$W2/.fable-team/state" "$W2/design/kakao/indices/inbox/master"
printf '{"_master":"byz-kakao-master-claude#25","byz-kakao-master-claude#25":{"role":"master","agent":"claude","tick":"ft-master-tick"}}\n' > "$W2/.fable-team/seats.json"
printf '{"_master":"byz-kakao-master-claude#9"}\n' > "$W2/.fable-team/seats-kakao.json"   # 디코이: 옛 하드코딩 규칙이 고르는 파일
: > "$W2/design/kakao/SEATBELT-README.md"
cp -p "$W2/.fable-team/seats.json" "$T/seats.kakao.before"
kb() { (cd "$W2" && PATH="$FK:$PATH" FT_SEND_FROM='byz-kakao-master-claude#24' bash "$B/ft-role-spawn.sh" "$@" 2>&1); }

# K1·K2: FT_ROOT=<워크트리> → rc0 · 명부 = seats.json(#25) · 디코이 seats-kakao.json(#9) 아님
o="$(FT_ROOT="$W2" kb master --team kakao --dry-run)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *"PLAN seat=byz-kakao-master-claude#26 "*"replaces=[byz-kakao-master-claude#25]"* ]] \
  && [[ "$o" == *"mbox 로 byz-kakao-master-claude#25"* ]] && [[ "$o" != *"byz-kakao-master-claude#9"* ]]; } \
  && ok "K1·K2 FT_ROOT=<워크트리> → rc0 · 명부 seats.json(#25) · seats-kakao.json(#9) 안 읽음" || bad "K1·K2 rc=$rc $(printf '%s\n' "$o" | head -3)"

# ── 픽스처 B: BYZ 꼴 — 한 리포(워크트리 없음) · 명단에 «명부» 칸 없음 ──
R="$T/byz"; mkdir -p "$R/design/teams/feat/indices/inbox/arch" "$R/design/v65/indices/inbox/master" "$R/.fable-team/state"
git init -q "$R"
printf '| 팀 | 폴더 | 오케 좌석 계열 | 상태 |\n|---|---|---|---|\n| feat | `design/teams/feat/` | x | 현역 |\n| v65 | `design/v65/` | byz-v65-master-claude | 현역 |\n' > "$R/design/TEAMS.md"
: > "$R/design/teams/feat/SEATBELT-README.md"; : > "$R/design/v65/SEATBELT-README.md"
printf '{"_master":"byz-feat-master-claude#31"}\n' > "$R/.fable-team/seats-feat.json"
printf '{"_master":"byz-v65-master-claude#1"}\n' > "$R/.fable-team/seats.json"
printf '{"_master":"byz-v65-master-claude#9"}\n' > "$R/.fable-team/seats-v65.json"   # 디코이
cp -p "$R/.fable-team/seats-feat.json" "$T/seats.feat.before"; cp -p "$R/.fable-team/seats.json" "$T/seats.v65.before"
by() { (cd "$R" && PATH="$FK:$PATH" bash "$B/ft-role-spawn.sh" "$@" 2>&1); }

# K3: FT_ROOT 없음 · 팀 feat → 공용 루트 · seats-feat.json(#31)
o="$(FT_SEND_FROM='byz-feat-master-claude#30' by arch --team feat --dry-run)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *"PLAN seat=byz-feat-arch-claude#0"* ]] && [[ "$o" == *"mbox 로 byz-feat-master-claude#31"* ]]; } \
  && ok "K3 FT_ROOT 없음 · feat → 공용 루트 · seats-feat.json(#31) (불변)" || bad "K3 rc=$rc $(printf '%s\n' "$o" | head -3)"

# K4: FT_ROOT 없음 · v65 → seats.json(#1) · 디코이 seats-v65.json(#9) 아님
o="$(FT_SEND_FROM='byz-v65-master-claude#2' by master --team v65 --dry-run)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *"PLAN seat=byz-v65-master-claude"* ]] && [[ "$o" == *"mbox 로 byz-v65-master-claude#1"* ]] && [[ "$o" != *"byz-v65-master-claude#9"* ]]; } \
  && ok "K4 FT_ROOT 없음 · v65 → seats.json(#1) · seats-v65.json(#9) 안 읽음 (불변)" || bad "K4 rc=$rc $(printf '%s\n' "$o" | head -3)"

# K5: FT_ROOT 에 .fable-team 없음 → REJECT · 부작용 0
mkdir -p "$T/nofable"; cp -p "$W2/.fable-team/seats.json" "$T/seats.k5.before"
o="$(FT_ROOT="$T/nofable" kb master --team kakao --dry-run)"; rc=$?
{ [ "$rc" = 1 ] && [[ "$o" == *"REJECT FT_ROOT 에 .fable-team 없음: $T/nofable"* ]] && [[ "$o" != *"PLAN "* ]] \
  && cmp -s "$W2/.fable-team/seats.json" "$T/seats.k5.before"; } \
  && ok "K5 FT_ROOT 에 .fable-team 없음 → REJECT rc1 · PLAN 0 · 명부 쓰기 0" || bad "K5 rc=$rc $(printf '%s\n' "$o" | head -3)"

# K6: 명단을 못 읽음 → REJECT «팀 명단 판정 불가» · 부작용 0
NM="$T/nomd"; mkdir -p "$NM/.fable-team/comm" "$NM/.fable-team/state"; printf '{"_master":"byz-kakao-master-claude#25"}\n' > "$NM/.fable-team/seats.json"
cp -p "$W2/.fable-team/seats.json" "$T/seats.k6.before"
o="$(FT_ROOT="$NM" kb master --team kakao --dry-run)"; rc=$?
{ [ "$rc" = 1 ] && [[ "$o" == *"REJECT 팀 명단 판정 불가"* ]] && [[ "$o" != *"PLAN seat="* ]] \
  && cmp -s "$W2/.fable-team/seats.json" "$T/seats.k6.before"; } \
  && ok "K6 TEAMS.md 없음 → REJECT 팀 명단 판정 불가 rc1 · PLAN 0 · 명부 쓰기 0" || bad "K6 rc=$rc $(printf '%s\n' "$o" | head -3)"

# K7: 데이터 루트 = 워크트리 안 «하위 폴더»(깃 최상위 아님) — 실사건 꼴
RC="$T/kakaobot2"; WC="$RC/.worktrees/bootstrap"; K3R="$WC/kakao"
mkdir -p "$RC/design" "$RC/.fable-team/state"
git init -q "$RC"
printf '# 팀 명단 — kakao 루트 (가짜)\n| 팀 | 폴더 | 오케 좌석 계열 | 상태 | 명부 |\n|---|---|---|---|---|\n| kakao | `design/kakao/` | byz-kakao-master-claude | 현역 | seats.json |\n' > "$RC/design/TEAMS.md"
git -C "$RC" add -A >/dev/null 2>&1; git -C "$RC" -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1
git -C "$RC" worktree add -q "$WC" -b bootstrap2 >/dev/null 2>&1
mkdir -p "$K3R/.fable-team/comm" "$K3R/.fable-team/state" "$K3R/design/kakao/indices/inbox/master"
printf '# 팀 명단 — kakao 루트 (가짜)\n| 팀 | 폴더 | 오케 좌석 계열 | 상태 | 명부 |\n|---|---|---|---|---|\n| kakao | `design/kakao/` | byz-kakao-master-claude | 현역 | seats.json |\n' > "$K3R/design/TEAMS.md"
printf '{"_master":"byz-kakao-master-claude#25","byz-kakao-master-claude#25":{"role":"master","agent":"claude","tick":"ft-master-tick"}}\n' > "$K3R/.fable-team/seats.json"
: > "$K3R/design/kakao/SEATBELT-README.md"
o="$(cd "$K3R" && PATH="$FK:$PATH" FT_ROOT="$K3R" FT_SEND_FROM='byz-kakao-master-claude#24' bash "$B/ft-role-spawn.sh" master --team kakao --dry-run 2>&1)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *"PLAN seat=byz-kakao-master-claude#26 "*"inbox=design/kakao/indices/inbox/master"* ]] && [[ "$o" == *"mbox 로 byz-kakao-master-claude#25"* ]]; } \
  && ok "K7 데이터 루트 ⊂ 깃 최상위 다른 폴더 → rc0 · 팀 폴더·inbox = 데이터 루트 기준 · index 상대경로" || bad "K7 rc=$rc $(printf '%s\n' "$o" | tail -2)"

# BYZ 쪽 명부 두 벌은 어느 시험에서도 안 바뀐다(dry-run 만)
{ cmp -s "$R/.fable-team/seats-feat.json" "$T/seats.feat.before" && cmp -s "$R/.fable-team/seats.json" "$T/seats.v65.before"; } \
  && ok "BYZ 명부 2벌 쓰기 0" || bad "BYZ 명부가 바뀌었다"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
