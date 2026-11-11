#!/usr/bin/env bash
# test_role_spawn_team_prefix_r1683.sh — r1683: ft-role-spawn.sh 의 v65 밖 팀 좌석 접두 = 그 팀 명부 `_master` 이름.
#   ⓐ aifp _master=aifp-ft-master-pi#4 → aifp-ft-arch-pi#0 ⓑ 옛 계보(byz-aifp-*#0)만 → aifp-ft-*#1 + 교체 대상
#   ⓒ 손 승계 뒤 두 계보 #0 → aifp-ft-*#1 + 두 행 모두 교체 ⓓ byz 팀(harness·feature·planner) 불변 ⓔ env FT_ROLE_BASE_PREFIX 우선
#   ⓕ _master 없음/꼴 아님 → 기본 byz-<팀>- + stderr 1줄 · 명부 못 읽음 → REJECT(하드 룰 20) ⓖ v65 불변
#   ⓗ 회귀: 기존 4파일 FAIL 줄 = 앞 판(origin/main)과 같다 + --add 경로 불변.
#      (래퍼 test_r989_role_spawn_add.sh 는 name·team 을 다시 불러 혼자 70초를 넘는다 → 70초 상한 밖 · 완료 보고에서 1회 별도 대조)
# 전부 mktemp 안 — 가짜 tmux/tmuxc(PATH) · 가짜 자원 센서 · --dry-run 만 · 실 tmux·실 명부·실 쪽지 0 · sleep 0.
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1 FT_TEAMSET=0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_ROLE_BASE_PREFIX FT_PENALTY_TEAM
export FT_SEND_FROM='byz-harness-master-pi#199'   # r1244: --team 없는 호출의 팀 기본값 — 이 시험은 늘 --team 을 준다
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"; BIN="$HERE/../bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }

cmp -s "$BIN/ft-role-spawn.sh" "$KIT/ft-role-spawn.sh" && ok "⓪ bin·kit 사본 동기" || bad "⓪ bin·kit 사본이 다르다"
bash -n "$KIT/ft-role-spawn.sh" && ok "⓪ bash -n" || bad "⓪ bash -n"
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$T/sensors" ok   # R218: 자원 문지기 센서를 가짜로

# ── 픽스처: 임시 리포 · TEAMS.md(v65 + byz 3팀 + aifp) · 팀 폴더 · 명부 · 가짜 tmux/tmuxc ──
R="$T/repo"; B="$T/bin"; FK="$T/fake"; mkdir -p "$R/.fable-team" "$B" "$FK" "$R/design/teams"
git init -q "$R"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| v65 | `design/v65/` | x | 현역 |\n| harness | `design/teams/harness/` | x | 현역 |\n| feature | `design/teams/feature/` | x | 현역 |\n| planner | `design/teams/planner/` | x | 현역 |\n| aifp | `design/teams/aifp/` | x | 현역 |\n' > "$R/design/TEAMS.md"
for t in harness feature planner aifp; do d="$R/design/teams/$t"; mkdir -p "$d/indices/inbox/arch" "$d/indices/inbox/da"; : > "$d/SEATBELT-README.md"; done
mkdir -p "$R/design/v65/indices/inbox/arch" "$R/design/v65/indices/inbox/da"; : > "$R/design/v65/SEATBELT-README.md"
for f in ft-role-spawn.sh ft-team-lib.sh ft_raised.py ft-resource-gate.sh ft-resource-swap-lib.sh ft-reclaim-capped.sh ft_teamset.py ft_team_lib.py ft_spawn_queue.py ft-resource-sample.sh ft-harness-root.sh; do cp -p "$KIT/$f" "$B/"; done
printf '#!/usr/bin/env bash\nexit 0\n' > "$B/ft-all-stop.sh"   # r626: .fable-team 이 있으면 늘 전팀 정지 check — 이 시험 주제 밖(통과 스텁)
printf '#!/bin/bash\n[ "$1" = open ] || exit 0\necho TMUXC-DRY\n' > "$FK/tmuxc"
printf '#!/bin/bash\ncase "$1" in has-session) exit 1;; *) exit 0;; esac\n' > "$FK/tmux"   # 열린 세션 0 → 번호는 명부 키로만 결정
chmod +x "$FK"/*
seatfile() { printf '%s\n' "$2" > "$R/.fable-team/seats-$1.json"; }
seatfile v65 '{"_name":"v65","_master":"byz-v65-master-claude#1","byz-v65-arch-claude#3":{"role":"arch","agent":"claude"}}'
cp "$R/.fable-team/seats-v65.json" "$R/.fable-team/seats.json"   # v65 명부 파일 이름은 seats.json(ft_team_lib 규칙)
seatfile harness '{"_master":"byz-harness-master-pi#199","byz-harness-arch-pi#3":{"role":"arch","agent":"pi"}}'
seatfile feature '{"_master":"byz-feature-master-pi#12","byz-feature-arch-pi#1":{"role":"arch","agent":"pi"}}'
seatfile planner '{"_master":"byz-planner-master-pi#7","byz-planner-arch-pi#2":{"role":"arch","agent":"pi"}}'
AIFP="$R/.fable-team/seats-aifp.json"; aifp() { printf '%s\n' "$1" > "$AIFP"; }
rs() { ( cd "$R" && PATH="$FK:$PATH" bash "$B/ft-role-spawn.sh" "$@" 2>&1 ); }
rse() { local p="$1"; shift; ( cd "$R" && FT_ROLE_BASE_PREFIX="$p" PATH="$FK:$PATH" bash "$B/ft-role-spawn.sh" "$@" 2>&1 ); }
expect() { [[ "$2" == *"PLAN seat=$3 "* && "$2" == *"replaces=[$4]"* ]] && ok "$1" || bad "$1 → 기대 seat=$3 replaces=[$4] · 실제: ${2:-<출력 없음>}"; }

# ⓐ aifp 접두 = 명부 _master 앞부분
aifp '{"_name":"aifp","_master":"aifp-ft-master-pi#4"}'
expect "ⓐ aifp → aifp-ft-arch-pi#0" "$(rs arch --team aifp --agent pi --dry-run)" "aifp-ft-arch-pi#0" "<없음>"

# ⓑ 옛 계보(byz-aifp-*)만 있을 때 — 번호 이어받기 + 교체 대상
aifp '{"_name":"aifp","_master":"aifp-ft-master-pi#4","byz-aifp-arch-pi#0":{"role":"arch","agent":"pi"}}'
expect "ⓑ 옛 계보 #0 → aifp-ft-arch-pi#1 · replaces=[byz-aifp-arch-pi#0]" "$(rs arch --team aifp --agent pi --dry-run)" "aifp-ft-arch-pi#1" "byz-aifp-arch-pi#0"

# ⓒ 손 승계 뒤 두 계보에 같은 #0 — arch·da 둘 다
aifp '{"_name":"aifp","_master":"aifp-ft-master-pi#4","byz-aifp-arch-pi#0":{"role":"arch","agent":"pi"},"aifp-ft-arch-pi#0":{"role":"arch","agent":"pi"},"byz-aifp-da-codex#0":{"role":"da","agent":"codex"},"aifp-ft-da-codex#0":{"role":"da","agent":"codex"}}'
expect "ⓒ arch 두 계보 #0 → #1 · 두 행 교체" "$(rs arch --team aifp --agent pi --dry-run)" "aifp-ft-arch-pi#1" "byz-aifp-arch-pi#0 aifp-ft-arch-pi#0"
expect "ⓒ da 두 계보 #0 → #1 · 두 행 교체" "$(rs da --team aifp --agent codex --dry-run)" "aifp-ft-da-codex#1" "byz-aifp-da-codex#0 aifp-ft-da-codex#0"

# ⓓ byz 팀 불변 — _master 가 byz-<팀>-master-* 라 셋(기본·새·옛 계보)이 같다
expect "ⓓ harness 불변" "$(rs arch --team harness --agent pi --dry-run)" "byz-harness-arch-pi#4" "byz-harness-arch-pi#3"
expect "ⓓ feature 불변" "$(rs arch --team feature --agent pi --dry-run)" "byz-feature-arch-pi#2" "byz-feature-arch-pi#1"
expect "ⓓ planner 불변" "$(rs arch --team planner --agent pi --dry-run)" "byz-planner-arch-pi#3" "byz-planner-arch-pi#2"

# ⓔ env 가 명부보다 이긴다
aifp '{"_name":"aifp","_master":"aifp-ft-master-pi#4"}'
expect "ⓔ FT_ROLE_BASE_PREFIX=zz-yy- 우선" "$(rse zz-yy- arch --team aifp --agent pi --dry-run)" "zz-yy-arch-pi#0" "<없음>"

# ⓕ 기본 갈래 2종(없음·꼴 아님) + 명부 못 읽음 = 판정 불가
aifp '{"_name":"aifp"}'
o="$(rs arch --team aifp --agent pi --dry-run)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *"PLAN seat=byz-aifp-arch-pi#0 "* && "$o" == *"접두 출처 = 기본 byz-aifp-"* ]]; } && ok "ⓕ _master 없음 → 기본 byz-aifp- + stderr 1줄" || bad "ⓕ 없음 rc=$rc $o"
aifp '{"_name":"aifp","_master":"foo"}'
o="$(rs arch --team aifp --agent pi --dry-run)"
[[ "$o" == *"PLAN seat=byz-aifp-arch-pi#0 "* && "$o" == *"명부 _master=foo 꼴 아님"* ]] && ok "ⓕ _master 꼴 아님 → 기본 갈래 + 사유" || bad "ⓕ 꼴 $o"
aifp '{"_name":"aifp",'
o="$(rs arch --team aifp --agent pi --dry-run)"; rc=$?
{ [ "$rc" = 1 ] && [[ "$o" == *"REJECT 명부 판정 불가(_master)"* && "$o" != *"PLAN "* ]]; } && ok "ⓕ 명부 못 읽음 → REJECT rc1(기본 접두 대체 0)" || bad "ⓕ 판정불가 rc=$rc $o"

# ⓖ v65 가지는 이 카드가 건드리지 않는다
expect "ⓖ v65 불변" "$(rs arch --team v65 --dry-run)" "byz-v65-arch-claude#4" "byz-v65-arch-claude#3"

# ⓗ --add 경로(교체 0) — 이름 규칙만 같고 계보 계산은 그대로
aifp '{"_name":"aifp","_master":"aifp-ft-master-pi#4"}'
o="$(rs arch --team aifp --agent pi --dry-run --add)"
[[ "$o" == *"PLAN seat=aifp-ft-arch-pi#0 "* && "$o" == *"mode=add"* ]] && ok "ⓗ --add: 이름 규칙 같고 교체 0" || bad "ⓗ --add $o"

# ⓗ 회귀 — 기존 4파일의 FAIL 줄이 «앞 판»과 같다(두 판 병렬 · 70초 상한 안).
#   앞 판 = 고치기 직전 main 의 고정 sha(816fa5e4… · 떠다니는 origin/main 은 착지 뒤 새 코드를 꺼낸다 — r1132 · ft-test-reentry-lint FLOATBASE)
REG="test_role_spawn_name.sh test_role_spawn_team.sh test_role_spawn_team_from_caller_r1244.sh test_role_spawn_ft_root_r1404.sh"
BASE_SHA=816fa5e412a75e3e5801a642f8a9eb1fc39dbb98
PACK="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)"; REL="${HERE#"$PACK"/}"; REL="${REL%/tests}"
stage() { local d="$1"; mkdir -p "$d/harness/tests"; cp -R "$HERE/../kit" "$d/harness/kit"; cp -R "$HERE/../bin" "$d/harness/bin"; cp -R "$HERE/lib" "$d/harness/tests/lib"; cp -R "$HERE/scripts" "$d/harness/tests/scripts"; for f in $REG; do cp -p "$HERE/$f" "$d/harness/tests/"; done; }
stage "$T/pat"; cp -al "$T/pat" "$T/base"   # 하드링크 사본 — 복사 시간 0 · 아래에서 앞 판 파일만 «지우고 새로 만든다»(링크가 끊긴다)
base_ok=1
for k in kit/fable-team/bin bin; do
  rm -f "$T/base/harness/$k/ft-role-spawn.sh"
  git -C "$PACK" show "$BASE_SHA:$REL/$k/ft-role-spawn.sh" > "$T/base/harness/$k/ft-role-spawn.sh" 2>/dev/null || base_ok=0
done
if [ "$base_ok" != 1 ]; then bad "ⓗ 앞 판($BASE_SHA) 사본 못 얻음 — 판정 불가"; elif cmp -s "$T/base/harness/kit/fable-team/bin/ft-role-spawn.sh" "$KIT/ft-role-spawn.sh"; then bad "ⓗ 대조군이 이 판과 같은 파일"; else ok "ⓗ 대조군 준비(앞 판 $BASE_SHA ≠ 이 판)"; fi
reg() { local d="$1"; ( cd "$d/harness/tests" && for f in $REG; do timeout 70 bash "$PWD/$f" 2>&1 | grep -E '^(FAIL |FAILED )' || true; done ) | sed -E 's|/[^ ]*||g' > "$d.fails"; }
{ reg "$T/base" & reg "$T/pat" & wait; }
diff -q "$T/base.fails" "$T/pat.fails" >/dev/null && ok "ⓗ 회귀 4파일 FAIL 줄 = 앞 판(FAIL 줄 $(wc -l < "$T/pat.fails" | tr -d ' ')개)" \
  || bad "ⓗ 회귀 FAIL 줄이 앞 판과 다르다: $(diff "$T/base.fails" "$T/pat.fails" | head -4 | tr '\n' ' ')"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
