#!/usr/bin/env bash
# test_wt_shell_scan_sparse_r945.sh — 카드 r945: 껍데기 경보(shell_scan)가 sparse 워크트리(문서·카드 작업 공간)를 «반쯤 지워진 껍데기» 로 세지 않는다.
#   ⓐ sparse(d0 만) · d0 있음 → 껍데기 0 (지금은 sparse 밖 최상위 부재를 부재로 세서 껍데기 1)
#   ⓑ sparse(d0 만) · d0 도 없음 → 껍데기 1 (진짜 반쯤 지워짐)
#   ⓒ 일반 워크트리 · 최상위 2개 부재 → 껍데기 1(회귀 0) · 1개 부재 → 0(회귀 0)
#   ⓓ sparse 표식만 있고 패턴을 못 읽음 → 껍데기 목록 0 + «판정 불가 <경로>» 1줄(오빠 HIL 0 · 삭제 0)
#   변이 2: sparse 검사 끔(WT_TEST_MUT=1) → ⓐ 빨강 · 판정 불가를 «껍데기 아님» 으로(WT_TEST_MUT=2) → ⓓ 빨강
# WT_TEST_BASH=/bin/bash 로 돌리면 도구를 macOS 기본 bash 3.2 로 실행한다(카드 완료 조건).
# 임시 git 리포 + 임시 워크트리만 쓴다 — 실 리포·워크트리·mbox·tmux 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="${WT_TEST_SRC:-$HERE/../../harness/kit/fable-team/bin}"   # 옛 도구(결함 있는 판)로 돌려 시험이 그 결함을 잡는지 볼 때만 덮어쓴다
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:600}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:600}";; *) ok "$3";; esac; }

mkdir -p "$T/bin" "$T/state"
cp "$SRC/ft-wt-sweep.sh" "$T/bin/"
# 변이 — 시험 사본만 고친다(워크트리 파일은 그대로).
case "${WT_TEST_MUT:-0}" in
  0) ;;
  1) python3 - "$T/bin/ft-wt-sweep.sh" <<'PY' || exit 2
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
old = 'if [ "$sprc" -eq 1 ]; then'
assert old in s, "변이 1 대상 없음"
open(p, "w", encoding="utf-8").write(s.replace(old, 'if false; then   # MUT1 sparse 검사 끔', 1))
PY
     echo "MUT 1 — sparse 검사 끔(spc=0 고정)";;
  2) python3 - "$T/bin/ft-wt-sweep.sh" <<'PY' || exit 2
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
old = 'if [ "$sprc" -eq 2 ]; then und="$und$p "; ucnt=$((ucnt+1));'
assert old in s, "변이 2 대상 없음"
open(p, "w", encoding="utf-8").write(s.replace(old, 'if [ "$sprc" -eq 2 ]; then', 1))
PY
     echo "MUT 2 — 판정 불가를 «껍데기 아님» 으로";;
  *) echo "usage: WT_TEST_MUT=0|1|2"; exit 2;;
esac
"${WT_TEST_BASH:-bash}" -n "$T/bin/ft-wt-sweep.sh" && ok "본보기 bash -n(${WT_TEST_BASH:-bash})" || bad "bash -n"

REPO="$T/repo"; mkdir -p "$REPO"; git -C "$REPO" init -q -b main
GIT() { git -C "$REPO" -c user.email=t@t -c user.name=t "$@"; }
mkdir -p "$REPO/d0" "$REPO/d1" "$REPO/d2" "$REPO/d3"
for d in d0 d1 d2 d3; do echo "$d" > "$REPO/$d/x"; done
GIT add -A && GIT commit -q -m init

# swp <계획 디렉터리> — sweep 1회(껍데기 스캔 간격 0 = 매번 훑는다)
swp() { mkdir -p "$1"; ( cd "$T" && env -i HOME="$HOME" PATH="$PATH" FT_WT_CLEAN_DIR="$1" FT_WT_SCAN_ROOT="$REPO" FT_WT_SHELL_SCAN_SEC=0 \
  FT_WT_ORPHANS_TSV="$T/state/orphans.tsv" FT_WT_SWEEP_LOG="$T/state/wt-sweep.log" "${WT_TEST_BASH:-bash}" "$T/bin/ft-wt-sweep.sh" 2>&1 ); }
# mksparse <이름> <cone|noconc> <패턴> — --no-checkout + sparse-checkout(문서 워크트리 꼴) → 체크아웃
mksparse() {
  GIT worktree add -q --no-checkout "$REPO/.worktrees/$1" -b "$1"
  if [ "$2" = cone ]; then git -C "$REPO/.worktrees/$1" sparse-checkout set "$3" >/dev/null 2>&1
  else git -C "$REPO/.worktrees/$1" sparse-checkout set --no-cone "$3" >/dev/null 2>&1; fi
  git -C "$REPO/.worktrees/$1" read-tree -mu HEAD >/dev/null 2>&1
}
mknormal() { GIT worktree add -q "$REPO/.worktrees/$1" -b "$1"; }

mksparse sp1 cone d0          # ⓐ sparse(cone · d0 만) · d0 있음
mksparse sp2 cone d0          # ⓑ 같은 꼴 · d0 를 지운다
mksparse sp3 noconc 'd1/'     # 보론: 비cone 패턴(`d1/`)도 같은 판정
mknormal n1; mknormal n2      # ⓒ 일반 워크트리
mksparse br1 cone d0          # ⓓ sparse 표식만 남기고 패턴 파일을 지운다
rm -rf "$REPO/.worktrees/sp2/d0"
rm -rf "$REPO/.worktrees/n2/d0" "$REPO/.worktrees/n2/d1"   # 최상위 2개 부재
rm -rf "$REPO/.worktrees/n1/d0"                            # 최상위 1개 부재(껍데기 아님)
rm -f "$REPO/.git/worktrees/br1/info/sparse-checkout"      # sparse 표식(core.sparseCheckout=true)만 남김

[ -d "$REPO/.worktrees/sp1/d0" ] && [ ! -e "$REPO/.worktrees/sp1/d1" ] && ok "전제: sp1 은 sparse(cone) — d0 만 있고 d1~d3 없음" || bad "전제 실패: sp1 체크아웃"
[ ! -e "$REPO/.worktrees/sp1/d2" ] && ok "전제: sp1 에 d2 없음(sparse 밖 = 정상)" || bad "전제 실패: sp1 에 d2 가 있음(sparse 아님)"
[ "$(git -C "$REPO/.worktrees/sp1" config --bool --get core.sparseCheckout)" = true ] && ok "전제: sp1 core.sparseCheckout=true" || bad "전제 실패: sp1 sparse 표식"
[ -d "$REPO/.worktrees/sp3/d1" ] && [ ! -e "$REPO/.worktrees/sp3/d0" ] && ok "전제: sp3 은 비cone(d1/) — d1 만" || bad "전제 실패: sp3 체크아웃"

echo "== ⓐⓑⓒⓓ 한 번의 스캔"
out="$(swp "$T/scan")"
has  "$out" "껍데기 2곳(전체 2곳): n2 sp2" "ⓑⓒ sparse(d0 만) + d0 부재 = 껍데기(sp2) · 일반 워크트리 최상위 2개 부재 = 껍데기(n2) — 그 둘뿐"
hasnt "$out" "sp1"                        "ⓐ sparse(d0 만) + d0 있음 → 껍데기 0 (지금은 sparse 밖 부재를 세서 껍데기로 오판)"
hasnt "$out" "sp3"                        "보론 비cone(d1/) sparse 도 껍데기 0"
hasnt "$out" " n1"                        "ⓒ 일반 워크트리 · 최상위 1개 부재 → 껍데기 아님(회귀 0)"
has  "$out" "판정 불가 1곳"                "ⓓ sparse 표식만 있고 패턴 못 읽음 → «판정 불가» 1줄"
has  "$out" "br1"                         "  └ 판정 불가 줄에 경로(br1)"
case "$out" in *"[HIL] seat=byz-harness-wt-shell 반쯤 지워진 워크트리 껍데기 2곳(전체 2곳): n2 sp2 —"*) ok "  └ 껍데기 줄 꼴 그대로(팀 미상 = harness · r444)";; *) bad "껍데기 줄 꼴이 달라짐 ← ${out:0:300}";; esac
out2="$(swp "$T/scan")"
hasnt "$out2" "[HIL]"                     "  └ 바뀐 것 없음 → 같은 목록이면 두 번째 스캔은 경보 0(바뀐 때만)"
hasnt "$out2" "판정 불가"                  "  └ 판정 불가 목록도 그대로면 다시 0"
rm -rf "$REPO/.worktrees/n1/d1"           # 일반 워크트리 최상위 2개 부재 → 껍데기(1개 → 2개 축 재확인)
out3="$(swp "$T/scan")"
has  "$out3" "껍데기 3곳(전체 3곳): n1 n2 sp2" "ⓒ 일반 워크트리 · 최상위 2개 부재로 늘면 다시 껍데기(n1 추가)"
[ -d "$REPO/.worktrees/sp1/d0" ] && [ -d "$REPO/.worktrees/n1" ] && [ -d "$REPO/.worktrees/br1" ] && ok "  └ 경보는 읽기만 — 워크트리 손 0" || bad "경보가 워크트리를 건드림"
[ -z "$(ls "$T/scan"/.sparse-scan.* 2>/dev/null)" ] && ok "  └ sparse 임시 파일 남김 0" || bad "sparse 임시 파일이 남음"
[ -z "$(ls -d "$REPO"/.worktrees/*.deleting-* 2>/dev/null)" ] && ok "  └ 삭제·이름 바꿈 0" || bad "스캔이 워크트리를 지움"

echo "== 결과"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAIL $fail"; exit 1
