#!/usr/bin/env bash
# r1301 — planner directory resolution must not create or guess a sparse path.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
LIB="$ROOT/harness/bin/ft-team-lib.sh"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
fail=0; n=0
ck() { n=$((n+1)); if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
run_lib() { LC_ALL=C FT_PLANNER_EVENT=A7 bash -c '. "$1"; ft_planner_dir_resolve "$2"' _ "$1" "$2" 2>"$TMP/err"; }
run() { run_lib "$LIB" "$1"; }

FULL="$TMP/full"; SPARSE="$TMP/sparse"; MISSING="$TMP/missing"; OTHER="$TMP/other"
BIN="$ROOT/harness/bin"
mkdir -p "$FULL/design/teams/planner" "$MISSING/design/teams" "$OTHER/design/teams/planner"
printf '%s\n' '| team | folder |' '|---|---|' '| planner | design/teams/planner/ |' > "$FULL/design/TEAMS.md"
printf '%s\n' planner > "$FULL/design/teams/planner/marker"
printf '%s\n' keep > "$FULL/design/teams/planner/keep.md"
printf '%s\n' '| team | folder |' '|---|---|' '| planner | design/teams/planner/ |' > "$MISSING/design/TEAMS.md"
printf '%s\n' '| team | folder |' '|---|---|' '| planner | design/teams/planner/ |' > "$OTHER/design/TEAMS.md"
printf '%s\n' other > "$OTHER/design/teams/planner/marker"
for repo in "$FULL" "$MISSING" "$OTHER"; do
  git -C "$repo" init -q || exit 1
  git -C "$repo" -c user.name=test -c user.email=test@example.invalid add -A || exit 1
  git -C "$repo" -c user.name=test -c user.email=test@example.invalid commit -qm base || exit 1
done
git -C "$FULL" worktree add -q -b test/sparse "$SPARSE" HEAD || exit 1
git -C "$SPARSE" sparse-checkout init --no-cone || exit 1
printf '%s\n' '/*' '!/design/teams/*/' | git -C "$SPARSE" sparse-checkout set --no-cone --stdin || exit 1

out="$(run "$FULL")"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "$FULL/design/teams/planner" ] && [ ! -s "$TMP/err" ]; ck 'full checkout returns configured absolute path' $?

FT_PLANNER_DIR="$FULL/design/teams/planner" out="$(FT_PLANNER_EVENT=A7 FT_PLANNER_DIR="$FULL/design/teams/planner" bash -c '. "$1"; ft_planner_dir_resolve "$2"' _ "$LIB" "$SPARSE" 2>"$TMP/err")"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "$FULL/design/teams/planner" ]; ck 'existing FT_PLANNER_DIR takes precedence' $?

full_real="$(cd -- "$FULL/design/teams/planner" && pwd -P)"
out="$(run "$SPARSE")"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "$full_real" ] && [ "$(wc -l < "$TMP/err" | tr -d ' ')" = 1 ] && grep -q '^NOTE planner 폴더 = 주 워크트리 ' "$TMP/err"; ck 'all-S sparse path resolves through verified primary worktree' $?

git -C "$SPARSE" update-index --no-skip-worktree -- design/teams/planner/marker || exit 1
out="$(run "$SPARSE")"; rc=$?
[ "$rc" != 0 ] && [ -z "$out" ] && grep -q 'S 외 표식' "$TMP/err"; ck 'H marker rejects missing planner without consulting primary worktree' $?

python3 - "$LIB" "$TMP/mutant-skip.sh" skip <<'PY' || exit 1
from pathlib import Path
import sys
src, dst = map(Path, sys.argv[1:3])
text = src.read_text(encoding="utf-8")
old = 'while IFS= read -r line; do [[ "$line" == S\\ * ]] || sparse=0; done <<< "$tracked"'
assert old in text
dst.write_text(text.replace(old, 'while IFS= read -r line; do sparse=1; done <<< "$tracked"', 1), encoding="utf-8")
PY
out="$(run_lib "$TMP/mutant-skip.sh" "$SPARSE")"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "$(cd -- "$FULL/design/teams/planner" && pwd -P)" ]; ck 'mutation S-only check is detected' $?
git -C "$SPARSE" update-index --skip-worktree -- design/teams/planner/marker || exit 1
git -C "$SPARSE" update-index --no-skip-worktree -- design/teams/planner/keep.md || exit 1
git -C "$SPARSE" update-index --assume-unchanged -- design/teams/planner/keep.md || exit 1
out="$(run "$SPARSE")"; rc=$?
[ "$rc" != 0 ] && [ -z "$out" ] && grep -q 'S 외 표식' "$TMP/err" && ! grep -q '^NOTE ' "$TMP/err"; ck 'R5d assume-unchanged h rejects with ERROR and no NOTE' $?
git -C "$SPARSE" update-index --no-assume-unchanged -- design/teams/planner/keep.md || exit 1
git -C "$SPARSE" update-index --skip-worktree -- design/teams/planner/keep.md || exit 1

out="$(run "$MISSING")"; rc=$?
[ "$rc" != 0 ] && [ -z "$out" ] && grep -q '^ERROR ' "$TMP/err"; ck 'non-sparse missing planner fails without guessing' $?
[ ! -d "$MISSING/design/teams/planner" ]; ck 'failed resolution does not create planner directory' $?

R9_DIR="$TMP/plan's dir"; R9_BAD="$R9_DIR/no such"; mkdir -p "$R9_DIR"
out="$(FT_PLANNER_EVENT=A7 FT_PLANNER_DIR="$R9_BAD" LC_ALL=C bash -c '. "$1"; ft_planner_dir_resolve "$2"' _ "$LIB" "$FULL" 2>"$TMP/err")"; rc=$?
[ "$rc" != 0 ] && [ -z "$out" ] && grep -q '^ERROR ' "$TMP/err"; ck 'missing explicit override fails closed' $?
rerun_line="$(grep -o '재실행: .*' "$TMP/err" | head -1)"; rerun_cmd="${rerun_line#재실행: }"
expected="$(printf '%s\n' "FT_ROOT=$FULL" "FT_PLANNER_DIR=$R9_BAD" bash "$BIN/ft-autonomy-start.sh" ledger A7)"
printf '%s\n' "$rerun_cmd" > "$TMP/rerun.sh"; bash -n "$TMP/rerun.sh"; syntax_rc=$?
restored="$(bash -c 'eval "set -- $1" || exit 1; printf "%s\n" "$1" "$2" "$3" "$4" "$5" "$6"' _ "$rerun_cmd")"; restore_rc=$?
[ "$syntax_rc" = 0 ] && [ "$restore_rc" = 0 ] && [ "$restored" = "$expected" ]; ck 'R9 rerun parses and eval restores spaced quoted values' $?

touch "$TMP/file"
python3 - "$LIB" "$TMP/mutant-dir.sh" dir <<'PY' || exit 1
from pathlib import Path
import sys
src, dst = map(Path, sys.argv[1:3])
text = src.read_text(encoding="utf-8")
old = '[ -d "$dir" ] || reason="FT_PLANNER_DIR 폴더 없음: $dir"'
assert old in text
dst.write_text(text.replace(old, '[ -e "$dir" ] || reason="FT_PLANNER_DIR 폴더 없음: $dir"', 1), encoding="utf-8")
PY
out="$(FT_PLANNER_EVENT=A7 FT_PLANNER_DIR="$TMP/file" LC_ALL=C bash -c '. "$1"; ft_planner_dir_resolve "$2"' _ "$TMP/mutant-dir.sh" "$FULL" 2>"$TMP/err")"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "$TMP/file" ]; ck 'mutation directory-existence check is detected' $?

REAL_GIT="$(command -v git)"; export OTHER REAL_GIT; mkdir -p "$TMP/fakebin"
printf '%s\n' '#!/bin/bash' 'if [ "${3:-}" = worktree ] && [ "${4:-}" = list ]; then printf "worktree %s\\n" "$OTHER"; else exec "$REAL_GIT" "$@"; fi' > "$TMP/fakebin/git"
chmod +x "$TMP/fakebin/git"
out="$(PATH="$TMP/fakebin:$PATH" run "$SPARSE")"; rc=$?
[ "$rc" != 0 ] && [ -z "$out" ] && grep -q '같은 저장소의 주 worktree' "$TMP/err"; ck 'different common-dir primary is rejected' $?
python3 - "$LIB" "$TMP/mutant-common.sh" common <<'PY' || exit 1
from pathlib import Path
import sys
src, dst = map(Path, sys.argv[1:3])
text = src.read_text(encoding="utf-8")
old = ' && [ "$common_root" = "$common_primary" ]'
assert old in text
dst.write_text(text.replace(old, '', 1), encoding="utf-8")
PY
out="$(PATH="$TMP/fakebin:$PATH" run_lib "$TMP/mutant-common.sh" "$SPARSE")"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "$OTHER/design/teams/planner" ]; ck 'mutation common-dir check is detected' $?

SEPARATE="$TMP/separate"; SEPARATE_SPARSE="$TMP/separate-sparse"; META="$TMP/meta.git"
mkdir -p "$SEPARATE"; git -C "$SEPARATE" init -q --separate-git-dir="$META" || exit 1
mkdir -p "$SEPARATE/design/teams/planner"
printf '%s\n' '| team | folder |' '|---|---|' '| planner | design/teams/planner/ |' > "$SEPARATE/design/TEAMS.md"
printf '%s\n' keep > "$SEPARATE/design/teams/planner/keep.md"
git -C "$SEPARATE" -c user.name=test -c user.email=test@example.invalid add -A || exit 1
git -C "$SEPARATE" -c user.name=test -c user.email=test@example.invalid commit -qm base || exit 1
git -C "$SEPARATE" worktree add -q -b test/sparse-separate "$SEPARATE_SPARSE" HEAD || exit 1
git -C "$SEPARATE_SPARSE" sparse-checkout init --no-cone || exit 1
printf '%s\n' '/*' '!/design/teams/*/' | git -C "$SEPARATE_SPARSE" sparse-checkout set --no-cone --stdin || exit 1
mkdir -p "$META/design/teams/planner"; printf '%s\n' fake > "$META/design/teams/planner/fake"
out="$(LC_ALL=C FT_ROOT="$SEPARATE_SPARSE" bash "$BIN/ft-autonomy-start.sh" ledger A9 2>"$TMP/err")"; rc=$?
[ "$rc" = 1 ] && [ -z "$out" ] && grep -q '^ERROR .*주 worktree git 루트 조회 실패(rc=128)' "$TMP/err" && ! grep -q '^NOTE ' "$TMP/err" && [ ! -e "$META/design/teams/planner/AUTONOMY-START-A9.md" ]; ck 'R7 separate-git-dir fails closed without writing under git metadata' $?

R8="$TMP/SPARSE-HIDDEN-root"; mkdir -p "$R8"; git -C "$R8" init -q || exit 1
out="$(run "$R8")"; rc=$?
[ "$rc" != 0 ] && [ -z "$out" ] && grep -q '^ERROR .*SPARSE-HIDDEN' "$TMP/err" && ! grep -q '^NOTE ' "$TMP/err"; ck 'R8 hidden-word root with no planner team remains an ERROR' $?

mkdir -p "$TMP/stubs"; printf '%s\n' '#!/bin/bash' 'exit 1' > "$TMP/stubs/gh"; chmod +x "$TMP/stubs/gh"
out="$(LC_ALL=C FT_ROOT="$SPARSE" PATH="$TMP/stubs:$PATH" bash "$BIN/ft-autonomy-start.sh" ledger A7 2>"$TMP/err")"; rc=$?
[ "$rc" = 0 ] && [ -f "$FULL/design/teams/planner/AUTONOMY-START-A7.md" ] && [ ! -e "$SPARSE/design/teams/planner/AUTONOMY-START-A7.md" ]; ck 'ledger writes only to verified primary planner directory' $?
grep -q 'Issue 목록 못 읽음: gh 호출 실패' "$FULL/design/teams/planner/AUTONOMY-START-A7.md"; ck 'ledger keeps explicit issue-read failure note' $?

( cd / && LC_ALL=C FT_ROOT="$FULL" FT_PLANNER_DIR="$FULL/design/teams/planner" FT_AUTONOMY_STATE_DIR="$TMP/r9-state" PATH="$TMP/stubs:$PATH" bash "$BIN/ft-autonomy-start.sh" ledger A9 2>"$TMP/err" ) > "$TMP/r9c.out"; rc=$?
[ "$rc" = 0 ] && [ -f "$FULL/design/teams/planner/AUTONOMY-START-A9.md" ]; ck 'R9 rerun from outside the repository writes to FT_ROOT planner' $?

BLOCKED="$TMP/blocked"; mkdir -p "$BLOCKED/AUTONOMY-START-A8.md"
out="$(LC_ALL=C FT_ROOT="$FULL" FT_PLANNER_DIR="$BLOCKED" PATH="$TMP/stubs:$PATH" bash "$BIN/ft-autonomy-start.sh" ledger A8 2>"$TMP/err")"; rc=$?
[ "$rc" != 0 ] && grep -q '^ERROR 시작 장부 쓰기 실패: ' "$TMP/err" && grep -Fq "재실행: FT_ROOT=$FULL FT_PLANNER_DIR=$BLOCKED bash $BIN/ft-autonomy-start.sh ledger A8" "$TMP/err"; ck 'write error includes same rerun command' $?

echo "== $n checks, fail=$fail"; [ "$fail" = 0 ]
