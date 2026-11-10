#!/usr/bin/env bash
# test_wt_sweep_attach_live_bin_r1298.sh — 카드 r1298 단계 4: ft-wt-sweep --launchd 의 하루 1회 명부 lint 가
#   «루트 shim 폴더($FT_ROOT/.fable-team/bin)» 가 아니라 «이 스크립트가 있는 LIVE_BIN 사본» 의 ft_team_lib·ft-team-attach 를 쓴다.
#   사건: 루트 shim 의 ft_team_lib.py(:24 «import 금지» raise)를 import → ImportError · «WARN 팀 명부 lint planner _master 판정 불가» · sweep rc=1.
#   ⓐ planner _master 를 읽는다(WARN 0 · ImportError 0) ⓑ 명부 lint 가 LIVE_BIN 의 ft-team-attach 를 --notify <planner _master> 로 부른다 ⓒ 루트 shim 쪽 attach 는 불리지 않는다 ⓓ sweep rc 0
# 임시 FT_ROOT(루트 shim 폴더 = import 금지 raise 연결 파일) + LIVE_BIN 사본 + 가짜 tmux·lsof·du·mbox 만 — 실 리포·tmux·mbox 0 · 외부 호출 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # 실 상태 지문 + git 밖 cwd 재실행(재진입 표지 RSG_ACTIVE)
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="${WT_TEST_SRC:-$HERE/../../harness/kit/fable-team/bin}"   # 기준판·변이 코드로 돌릴 때만 덮어쓴다
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:500}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:500}";; *) ok "$3";; esac; }

# LIVE_BIN 사본 — 진짜 ft_team*.py + sweep. attach 입구는 «부른 인자만 기록하는» 대역으로 바꾼다(명부 lint 본체는 이 시험 소관 아님).
mkdir -p "$T/bin" "$T/fake" "$T/hil"
cp "$SRC"/ft_team*.py "$SRC/ft-wt-sweep.sh" "$T/bin/"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\nexit 0\n' "$T/live-attach.args" > "$T/bin/ft-team-attach.sh"
bash -n "$T/bin/ft-wt-sweep.sh" && ok "bash -n" || bad "bash -n"
printf '#!/usr/bin/env bash\necho "no server running on /tmp/fake"; exit 1\n' > "$T/fake/tmux"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/fake/lsof"
printf '#!/usr/bin/env bash\nprintf "1\\t%%s\\n" "$2"\n' > "$T/fake/du"
chmod +x "$T/bin/"* "$T/fake/"*

# 임시 FT_ROOT — git 리포 + 팀 명단(planner 현역) + 명부 + 루트 shim 폴더
REPO="$T/repo"; mkdir -p "$REPO/.fable-team/bin" "$REPO/.fable-team/state" "$REPO/design/teams/planner/cards"
git -C "$REPO" init -q -b main
printf '.worktree-info.json\n' > "$REPO/.gitignore"
git -C "$REPO" add .gitignore && git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m init
printf '| 팀 | 폴더 | 상태 |\n|---|---|---|\n| planner | design/teams/planner/ | 현역 |\n' > "$REPO/design/TEAMS.md"
printf '{"_master":"byz-planner-master-claude#9","_cards":"design/teams/planner/cards"}\n' > "$REPO/.fable-team/seats-planner.json"
printf 'raise ImportError("ft-root-bin-shim 의 .py 연결 파일 — import 금지")\n' > "$REPO/.fable-team/bin/ft_team_lib.py"
printf '#!/usr/bin/env bash\necho called >> "%s"\nexit 0\n' "$T/root-attach.called" > "$REPO/.fable-team/bin/ft-team-attach.sh"
chmod +x "$REPO/.fable-team/bin/ft-team-attach.sh"

out="$( cd "$T" && env -i HOME="$HOME" PATH="$T/fake:$PATH" FT_ROOT="$REPO" FT_WT_ARCHIVE=0 FT_WT_LAND_PLAN=0 FT_WT_SHELL_SCAN_SEC=0 \
  FT_MBOX_SH=/usr/bin/true FT_TMUX_BIN="$T/fake/tmux" FT_LSOF_BIN="$T/fake/lsof" FT_DU_BIN="$T/fake/du" HIL_DIR="$T/hil" HIL_CLIP=0 \
  timeout 60 bash "$T/bin/ft-wt-sweep.sh" --launchd 2>&1 )"; rc=$?

hasnt "$out" "planner _master 판정 불가" "ⓐ planner _master 를 읽음 — WARN 0"
hasnt "$out" "ImportError" "ⓐ  └ import 금지 연결 파일을 안 부름(ImportError 0)"
has "$(cat "$T/live-attach.args" 2>/dev/null)" "--all --check --notify byz-planner-master-claude#9" "ⓑ LIVE_BIN 의 attach 를 planner _master 로 부름"
[ ! -e "$T/root-attach.called" ] && ok "ⓒ 루트 shim 폴더의 attach 는 불리지 않음" || bad "ⓒ 루트 shim attach 가 불림"
[ "$rc" = 0 ] && ok "ⓓ sweep rc 0" || bad "ⓓ sweep rc=$rc ← ${out:0:400}"

echo "== 결과: FAIL=$fail"
[ "$fail" = 0 ]
