#!/usr/bin/env bash
# r880 ⓔ 변이 — 변이 사본 2개로 같은 시험을 돌려 «FAIL» 이어야 한다(시험이 그 길을 잡는다는 증거).
#   M1 착지 조상 검사 제거 → ⓒ 미착지 사본이 목록에 들어감 · M2 계획 대신 바로 지우기 → ⓑ «삭제 호출 0» FAIL
# 쓰는 법: bash mutation.sh <빈 작업 폴더>
set -uo pipefail
H="$(cd -- "$(dirname -- "$0")/../.." && pwd)"; S="${1:?작업 폴더}"
T="$H/tests/test_wt_sweep_land_plan_r880.sh"; B="$H/kit/fable-team/bin/ft-wt-sweep.sh"
run() { local m="$1" want="$2" o rc; o="$(WT_TEST_SRC="$S/$m" bash "$T" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ] && printf '%s\n' "$o" | grep -qF -- "$want"; then echo "KILLED $m — rc=$rc · $(printf '%s\n' "$o" | grep -F -- "$want" | head -1 | cut -c1-160)"
  else echo "SURVIVED $m — rc=$rc (기대 FAIL 줄: $want)"; return 1; fi; }
mkdir -p "$S/M1" "$S/M2"
grep -v 'merge-base --is-ancestor "\$h" "\$m"' "$B" > "$S/M1/ft-wt-sweep.sh"
sed 's#printf '"'"'land_rm %q %q  \# %s KB\\n'"'"' "\$p" "\$h" "\$kb" >> "\$tmp"#git -C "$SCAN_ROOT" worktree remove "$p"#' "$B" > "$S/M2/ft-wt-sweep.sh"
cmp -s "$B" "$S/M1/ft-wt-sweep.sh" && { echo "M1 변이 적용 실패"; exit 2; }
cmp -s "$B" "$S/M2/ft-wt-sweep.sh" && { echo "M2 변이 적용 실패"; exit 2; }
r=0
run M1 "FAIL ⓒ land-unlanded 계획 밖" || r=1
run M2 "FAIL ⓑ 삭제 호출 0" || r=1
exit "$r"
