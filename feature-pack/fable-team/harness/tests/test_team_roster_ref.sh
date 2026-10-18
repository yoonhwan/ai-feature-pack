#!/usr/bin/env bash
# test_team_roster_ref.sh — R406: spawn·lint 가 팀 명단을 «ref(FT_TEAMS_REF · 기본 origin/main)» 에서 읽고 폴더는 호출 워크트리의 꼴·쌍둥이 후보 중 «실재 1개»
#   ⓐ 공유 루트 꼴(명단 없는 옛 워크트리 · 카드 꼴1) cwd spawn --dry-run → PLAN · lint OK ledger=꼴1 + SEATBELT·planner 판정도 ref 명단
#   ⓑ ref 못 읽음 → REJECT  ⓒ 후보 0 → REJECT  ⓓ 후보 2 → REJECT  ⓔ 명단 있는 보통 워크트리(꼴2) → 그대로 OK · 명시 env 가 이긴다
# 임시 bare origin + 클론 + 워크트리 · 가짜 tmux/tmuxc/sleep · 스크립트 사본만 — 실 리포·홈·seats·tmux 0.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_TEAMS_REF FT_GOAL_LEDGER FT_SEATBELT_README
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
T0="$(mktemp -d)"; trap 'rm -rf "$T0"' EXIT; T="$(cd "$T0" && pwd -P)"
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$T/sensors" ok
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }
for f in ft-nano-spawn.sh ft-index-lint.sh ft-team-lib.sh; do bash -n "$SRC/$f" && ok "bash -n $f" || bad "bash -n $f"; done

# ── 사본 bin · 가짜 도구
BIN="$T/bin"; mkdir -p "$BIN" "$T/fake"
for f in ft-nano-spawn.sh ft-index-lint.sh ft-index-lint-install.sh ft-proposal-gate.sh ft-index-move.sh ft-sheet-events.sh ft_sheet_events.py ft_sheet_confirm.py ft_sheet_key.py ft_board_env.py ft_board_mail.py ft-nano-cherry-gate.sh ft-nano-spawn-undo.sh ft-resource-gate.sh ft_raised.py ft_teamset.py ft_spawn_queue.py ft-team-lib.sh; do cp "$SRC/$f" "$BIN/" 2>/dev/null; done
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/ft-send-verified.sh"; printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/ft-agent-ready.sh"
printf '#!/usr/bin/env bash\ncase "$1" in has-session) exit 1;; esac\nexit 0\n' > "$T/fake/tmux"
printf '#!/usr/bin/env bash\necho "TMUXC $*"\n' > "$T/fake/tmuxc"; printf '#!/bin/sh\nexit 0\n' > "$T/fake/sleep"; chmod +x "$BIN/"* "$T/fake/"*
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
printf 'G1\nG2\nG3\n' > "$T/goal3"
CLOSE='시험 카드 닫는 증거 문장 스무 자 이상 복붙용'
card() { printf '# 인덱스: x\n- 제안서: 없음 — 시험 카드\n## 골 원문 (항상 이 3줄)\nG1\nG2\nG3\n## 골좌표\nM1 / 닫는 증거: 「%s」\n## 배경\nx\n## 구현 범위\n- x\n## 완료 조건\n- x\n## 상태\n- 대기\n' "$CLOSE" > "$1"; }
GITC() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

# ── 리포: 옛 꼴(명단 0 · design/v65/) 커밋 A → main 에서 꼴2 이동 + TEAMS.md 커밋 B → origin/main = B · 공유 루트 = A 의 워크트리
git init -q --bare "$T/origin.git"; git clone -q "$T/origin.git" "$T/main" 2>/dev/null; M="$T/main"
mkdir -p "$M/design/v65/indices/대기" "$M/design/planner/indices/대기"
printf '## 원장\n- M1 / 닫는 증거: %s\n' "$CLOSE" > "$M/design/v65/GOAL-LEDGER-v65.md"; echo sb > "$M/design/v65/SEATBELT-README.md"
card "$M/design/v65/indices/대기/x.md"; card "$M/design/planner/indices/대기/p.md"; printf '.worktrees/\n.fable-team/\n' > "$M/.gitignore"
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n| planner | `design/planner/` | p | 현역 |\n' > "$M/design/TEAMS.md"   # 실제 공유 루트(v6-realtime-live) 꼴: 옛 명단 = harness·planner 행만 · v65 행 0 (arch#94 재현 «v65 은 팀 명단에 없다»)
GITC "$M" add -A; GITC "$M" commit -q -m old -b main 2>/dev/null || { GITC "$M" checkout -q -b main; GITC "$M" commit -q -m old; }
OLD="$(git -C "$M" rev-parse HEAD)"
mkdir -p "$M/design/teams"; GITC "$M" mv design/v65 design/teams/v65; GITC "$M" mv design/planner design/teams/planner
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/teams/harness/` | h | 현역 |\n| planner | `design/teams/planner/` | p | 현역 |\n| v65 | `design/teams/v65/` | v | 현역 |\n' > "$M/design/TEAMS.md"
GITC "$M" add -A; GITC "$M" commit -q -m teams; git -C "$M" push -q origin HEAD:main 2>/dev/null; git -C "$M" fetch -q origin
L="$M/.worktrees/live"; git -C "$M" worktree add -q -b live "$L" "$OLD" 2>/dev/null
mkdir -p "$L/.fable-team" "$M/.fable-team"; echo '{}' > "$L/.fable-team/seats.json"; echo '{}' > "$M/.fable-team/seats.json"

sp() { local wt="$1"; shift; ( cd "$wt" && env -i HOME="$HOME" LC_ALL=en_US.UTF-8 PATH="$T/fake:$PATH" FT_TEAMSET=0 FT_RES_ROOT="$FT_RES_ROOT" FT_SHEET_ROOT="$FT_SHEET_ROOT" FT_GOAL_LINES_FILE="$T/goal3" "$@" 2>&1 ); }
spawn() { local wt="$1" c="$2"; shift 2; sp "$wt" "$@" bash "$BIN/ft-nano-spawn.sh" "$c" --base origin/main --dry-run; }
lib() { ( cd "$1" && env -i HOME="$HOME" PATH="$PATH" "${@:3}" bash -c '. "$1"; '"$2" _ "$BIN/ft-team-lib.sh" 2>&1 ); }
o="$(lib "$L" 'ft_team_in "$PWD" v65')"; { [[ "$o" == *"v65 은 팀 명단(TEAMS.md)에 없다"* ]] && git -C "$L" rev-parse -q --verify origin/main >/dev/null; } && ok "픽스처: 공유 루트 = 옛 명단(v65 행 0 · 옛 규칙이면 arch#94 ERROR) · origin/main ref 있음" || bad "픽스처 꼴이 틀림 ← $o"

echo "== ⓐ 공유 루트 cwd — 명단 = origin/main · 폴더 = 꼴1 실재 1개"
o="$(spawn "$L" design/v65/indices/대기/x.md)"; rc=$?
[ "$rc" = 0 ] && ok "ⓐ spawn --dry-run rc0" || bad "ⓐ spawn rc=$rc ← ${o:0:400}"
has "$o" "OK design/v65/indices/대기/x.md (ledger=design/v65/GOAL-LEDGER-v65.md)" "ⓐ lint OK · 기본 골 원장 = 공유 루트 꼴1"
has "$o" "PLAN seat=" "ⓐ PLAN 출력까지"
printf '%s\n' "$o" | grep -q '^REJECT' && bad "ⓐ REJECT 줄 있음" || ok "ⓐ REJECT 줄 0"
o="$(lib "$L" 'ft_team_file_ref "$PWD" v65 SEATBELT-README.md')"; [ "$o" = "$L/design/v65/SEATBELT-README.md" ] && ok "ⓐ SEATBELT-README = 공유 루트 꼴1(ref 명단)" || bad "ⓐ SEATBELT ← $o"
lib "$L" 'ft_team_has_ref "$PWD" planner design/planner/indices/대기/p.md indices/' >/dev/null; rc=$?
[ "$rc" = 0 ] && ok "ⓐ planner 카드 판정(ft_team_has_ref) = 꼴1 카드도 planner(ref 꼴2 의 쌍둥이)" || bad "ⓐ planner has_ref rc=$rc"
lib "$L" 'ft_team_has_ref "$PWD" planner design/v65/indices/대기/x.md indices/' >/dev/null; rc=$?
[ "$rc" = 1 ] && ok "ⓐ v65 카드는 planner 아님 rc1" || bad "ⓐ v65 카드 has_ref rc=$rc"

echo "== ⓑ ref 못 읽음 → REJECT"
o="$(spawn "$L" design/v65/indices/대기/x.md FT_TEAMS_REF=없는ref)"; rc=$?
{ [ "$rc" != 0 ] && [[ "$o" == *"명단(없는ref:design/TEAMS.md)을 못 읽음"* ]] && [[ "$o" == *"REJECT lint 실패"* ]]; } && ok "ⓑ spawn REJECT · «명단(없는ref:…)을 못 읽음»" || bad "ⓑ rc=$rc ← ${o:0:400}"
o="$(lib "$L" 'ft_team_file_ref "$PWD" v65 SEATBELT-README.md' FT_TEAMS_REF=없는ref)"; rc=$?
{ [ "$rc" = 1 ] && [[ "$o" == *"을 못 읽음"* ]]; } && ok "ⓑ SEATBELT 풀이 rc1 · 못 읽음" || bad "ⓑ SEATBELT rc=$rc ← $o"
lib "$L" 'ft_team_has_ref "$PWD" planner design/planner/indices/대기/p.md indices/' FT_TEAMS_REF=없는ref >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "ⓑ planner 판정 rc2(못 읽음 = 비허용)" || bad "ⓑ planner has_ref rc=$rc"

echo "== ⓒ 후보 0 → REJECT"
mv "$L/design/v65/GOAL-LEDGER-v65.md" "$T/ledger.bak"
o="$(spawn "$L" design/v65/indices/대기/x.md)"; rc=$?
{ [ "$rc" != 0 ] && [[ "$o" == *"실재 후보 0개"* ]] && [[ "$o" == *"design/teams/v65"* ]] && [[ "$o" == *"REJECT"* ]]; } && ok "ⓒ 후보 0 → REJECT(후보 경로 문구)" || bad "ⓒ rc=$rc ← ${o:0:400}"
mv "$T/ledger.bak" "$L/design/v65/GOAL-LEDGER-v65.md"

echo "== ⓓ 후보 2 → REJECT"
mkdir -p "$L/design/teams/v65"; cp "$L/design/v65/GOAL-LEDGER-v65.md" "$L/design/teams/v65/"; cp "$L/design/v65/SEATBELT-README.md" "$L/design/teams/v65/"
o="$(spawn "$L" design/v65/indices/대기/x.md)"; rc=$?
{ [ "$rc" != 0 ] && [[ "$o" == *"실재 후보 2개"* ]] && [[ "$o" == *"REJECT"* ]]; } && ok "ⓓ 후보 2 → REJECT(고르지 않음)" || bad "ⓓ rc=$rc ← ${o:0:400}"
o="$(lib "$L" 'ft_team_file_ref "$PWD" v65 SEATBELT-README.md')"; rc=$?
{ [ "$rc" = 1 ] && [[ "$o" == *"실재 후보 2개"* ]]; } && ok "ⓓ SEATBELT 후보 2 rc1" || bad "ⓓ SEATBELT rc=$rc ← $o"
rm -rf "$L/design/teams"

echo "== ⓔ 명단 있는 보통 워크트리(꼴2) · 명시 env 우선"
o="$(spawn "$M" design/teams/v65/indices/대기/x.md)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *"OK design/teams/v65/indices/대기/x.md (ledger=design/teams/v65/GOAL-LEDGER-v65.md)"* ]] && [[ "$o" == *"PLAN seat="* ]]; } && ok "ⓔ 보통 워크트리 OK · ledger=꼴2(동작 불변)" || bad "ⓔ rc=$rc ← ${o:0:400}"
o="$(spawn "$L" design/v65/indices/대기/x.md FT_TEAMS_REF=없는ref FT_GOAL_LEDGER=design/v65/GOAL-LEDGER-v65.md)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *"(ledger=design/v65/GOAL-LEDGER-v65.md)"* ]]; } && ok "ⓔ FT_GOAL_LEDGER 명시가 ref 보다 이긴다" || bad "ⓔ FT_GOAL_LEDGER rc=$rc ← ${o:0:400}"
grep -q 'if \[ -n "${FT_SEATBELT_README:-}" \]; then _SBR="$WT/$FT_SEATBELT_README"' "$SRC/ft-nano-spawn.sh" && ok "ⓔ FT_SEATBELT_README 명시 분기가 먼저(코드)" || bad "ⓔ FT_SEATBELT_README 분기 없음"

[ "$(git config --get core.bare)" != true ] && ok "core.bare != true" || bad "core.bare = true"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit $fail
