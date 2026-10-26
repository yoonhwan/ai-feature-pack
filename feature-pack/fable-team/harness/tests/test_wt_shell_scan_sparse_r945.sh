#!/usr/bin/env bash
# test_wt_shell_scan_sparse_r945.sh — 카드 r945: 껍데기 경보(shell_scan)가 sparse 워크트리(문서·카드 작업 공간)를 «반쯤 지워진 껍데기» 로 세지 않는다.
#   ⓐ cone sparse(d0 만) · d0 있음 → 껍데기 0 (옛 셈은 sparse 밖 부재를 부재로 세서 껍데기 1)
#   ⓑ cone sparse(d0 만) · d0 도 없음 → 껍데기 1 (진짜 반쯤 지워짐)
#   ⓒ 일반 워크트리 · 최상위 2개 부재 → 껍데기 1(회귀 0) · 1개 부재 → 0(회귀 0)
#   ⓓ sparse 표식만 있고 패턴을 못 읽음 → 껍데기 0 + «판정 불가 <경로>» 1줄(오빠 HIL 0 · 삭제 0)
#   ⓐ2(DA⑥ r1 반례 ①) 비cone `/d0/absent` `/d2/absent` `/d1/` → 껍데기 0 (패턴을 손으로 접으면 오탐)
#   ⓑ2(반례 ②-워크트리 config) 비cone `**/*.md` + d1 삭제 → 껍데기 1 (r1 은 «**/» 를 벗겨 놓침)
#   ⓑ3(반례 ②-공용 config·! 제외) 비cone `/d1/` + `!/d1/excluded/` + d1 삭제 → 껍데기 1
#   ⓓ2(반례 ④) 비cone `/*` 뒤 패턴 파일을 «폴더» 로 교체 → 판정 불가 1줄(부재 개수와 무관하게 sparse 면 항상 본다)
#   ⓔ 제외 규칙(.git/info/exclude)에 걸린 이름이 H 인데 디스크에 없음 → 껍데기 0 (실측: 이 필터가 없으면 sparse 125석 중 40석이 .serena 로 오탐)
#   ⓕ(DA⑥ r2 반례 ① + 보강 1) cone d0 · core.quotePath true/false 둘 다 · 이름에 한글·공백·큰따옴표·줄바꿈 · 최상위 심볼릭 링크 있음 → 껍데기 0 (r2 는 따옴표를 최상위 이름으로 읽어 오탐)
#   ⓖ(DA⑥ r2 반례 ②) 추적 «파일» keep 삭제 + 폴더 규칙 `keep/` → 껍데기 1 · 추적 «폴더» kdir 삭제 + 파일 규칙 `kdir` → 1 · 폴더 규칙 `kdir2/` → 0
#   변이 5: skip-worktree 필터 끔(WT_TEST_MUT=1) → ⓐ 빨강 · 판정 불가 «항상» 끔(2) → ⓓ 빨강 · 제외 필터 끔(3) → ⓔ 빨강
#           · `-z` 빼고 줄 단위(4) → ⓕ 빨강 · 제외 패턴 종류 구분 끔(5) → ⓖ 빨강
# WT_TEST_BASH=/bin/bash 로 돌리면 도구를 macOS 기본 bash 3.2 로 실행한다(카드 완료 조건). WT_TEST_SRC=<bin> 으로 옛 도구를 물린다.
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
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:700}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:700}";; *) ok "$3";; esac; }

mkdir -p "$T/bin" "$T/state"
cp "$SRC/ft-wt-sweep.sh" "$T/bin/"
# 변이 — 시험 사본만 고친다(워크트리 파일은 그대로).
MUTP() { python3 - "$T/bin/ft-wt-sweep.sh" "$1" "$2" <<'PY' || exit 2
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding="utf-8").read()
assert old in s, "변이 대상 없음: %r" % old[:60]
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
case "${WT_TEST_MUT:-0}" in
  0) ;;
  1) MUTP '    tag="${item%% *}"; [ "$tag" = S ] && continue' '    tag="${item%% *}"'
     echo "MUT 1 — skip-worktree(S) 필터 끔";;
  2) MUTP 'if [ "$lrc" -ne 0 ] || [ "$src" -ne 0 ] || [ -s "$err" ] || [ ! -s "$raw" ]; then' 'if false; then'
     echo "MUT 2 — 판정 불가를 «껍데기 아님» 으로";;
  3) MUTP '    case "$pat" in */) j=$((j+1));; esac' '    : # MUT3 제외 규칙 필터 끔'
     echo "MUT 3 — 제외 규칙(.git/info/exclude) 필터 끔";;
  4) MUTP 'ls-files -z -t -s > "$raw"' 'ls-files -t -s > "$raw"'
     MUTP "  while IFS= read -r -d '' item; do" '  while IFS= read -r item; do'
     echo "MUT 4 — -z 빼고 줄 단위로 읽기";;
  5) MUTP '    case "$pat" in */) j=$((j+1));; esac' '    j=$((j+1))  # MUT5 패턴 종류 구분 끔'
     echo "MUT 5 — 제외 패턴 종류 구분 끔";;
  *) echo "usage: WT_TEST_MUT=0|1|2|3|4|5"; exit 2;;
esac
"${WT_TEST_BASH:-bash}" -n "$T/bin/ft-wt-sweep.sh" && ok "본보기 bash -n(${WT_TEST_BASH:-bash})" || bad "bash -n"

REPO="$T/repo"; mkdir -p "$REPO"; git -C "$REPO" init -q -b main
GIT() { git -C "$REPO" -c user.email=t@t -c user.name=t "$@"; }
mkdir -p "$REPO/d0/absent" "$REPO/d1/excluded" "$REPO/d2/absent" "$REPO/d3" "$REPO/kdir" "$REPO/kdir2"
for f in d0/x d0/absent/f d1/x d1/note.md d1/excluded/g d2/x d2/absent/f d3/x ex/f keep kdir/f kdir2/f; do mkdir -p "$(dirname "$REPO/$f")"; echo "$f" > "$REPO/$f"; done
# ⓕ 이름 글자 꼴 묶음(DA⑥ r2 반례 ①) — 한글·공백·큰따옴표·줄바꿈이 «하위 경로» 에 들어가면 최상위 이름 추출이 글자 해석에 기대게 된다
printf 'h\n' > "$REPO/d0/한글 이름.md"
printf 'q\n' > "$REPO/d0/dq\"name.md"
printf 'n\n' > "$REPO/d0/nl$(printf '\n')name.md"
ln -s d3 "$REPO/top-link"                                 # 보강 1 — 최상위 심볼릭 링크(mode 120000) 는 디스크에 링크로 있다 = 정상
GIT add -A && GIT commit -q -m init

# swp <계획 디렉터리> [quotePath true|false] — sweep 1회(껍데기 스캔 간격 0 = 매번 훑는다)
swp() { mkdir -p "$1"; ( cd "$T" && env -i HOME="$HOME" PATH="$PATH" ${2:+GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.quotePath GIT_CONFIG_VALUE_0=$2} FT_WT_CLEAN_DIR="$1" FT_WT_SCAN_ROOT="$REPO" FT_WT_SHELL_SCAN_SEC=0 \
  FT_WT_ORPHANS_TSV="$T/state/orphans.tsv" FT_WT_SWEEP_LOG="$T/state/wt-sweep.log" FT_WT_ORPHANS_SCAN_SEC=999999 \
  "${WT_TEST_BASH:-bash}" "$T/bin/ft-wt-sweep.sh" 2>&1 ); }
# mksparse <이름> <cone|noconc> <패턴…> — --no-checkout + sparse-checkout(문서 워크트리 꼴) → 체크아웃
mksparse() {
  local n="$1" mode="$2"; shift 2
  GIT worktree add -q --no-checkout "$REPO/.worktrees/$n" -b "$n"
  if [ "$mode" = cone ]; then git -C "$REPO/.worktrees/$n" sparse-checkout set "$@" >/dev/null 2>&1
  else git -C "$REPO/.worktrees/$n" sparse-checkout set --no-cone "$@" >/dev/null 2>&1; fi
  git -C "$REPO/.worktrees/$n" read-tree -mu HEAD >/dev/null 2>&1
}
mknormal() { GIT worktree add -q "$REPO/.worktrees/$1" -b "$1"; }

mksparse sp1 cone d0                      # ⓐ
mksparse sp2 cone d0                      # ⓑ (d0 를 지운다)
mksparse sp3 noconc 'd1/'                 # 보론: 비cone
mknormal n1; mknormal n2                  # ⓒ
mksparse br1 cone d0                      # ⓓ (패턴 파일 삭제)
mksparse da1 noconc '/d0/absent' '/d2/absent' '/d1/'   # ⓐ2 반례 ①
mksparse da2 noconc '**/*.md'                          # ⓑ2 반례 ②
mksparse da3 noconc '/d1/' '!/d1/excluded/'            # ⓑ3 반례 ② 공용 config·! 제외
mksparse da4 noconc '/*'                               # ⓓ2 반례 ④
mksparse ig1 noconc '/*'                               # ⓔ 전체 체크아웃 뒤 ex 를 지우고 제외 규칙을 넣는다
mksparse g1 noconc '/*'                                # ⓖ-1 파일 keep 삭제 + «폴더 규칙» keep/
mksparse g2 noconc '/*'                                # ⓖ-2 폴더 kdir 삭제 + «파일 규칙» kdir
mksparse g3 noconc '/*'                                # ⓖ-3 폴더 kdir2 삭제 + «폴더 규칙» kdir2/
mksparse ln1 noconc '/*'                               # ⓕ-링크 최상위 심볼릭 링크가 있는 정상 sparse(전체 체크아웃)
rm -rf "$REPO/.worktrees/sp2/d0"
rm -rf "$REPO/.worktrees/n2/d0" "$REPO/.worktrees/n2/d1"   # 최상위 2개 부재
rm -rf "$REPO/.worktrees/n1/d0"                            # 최상위 1개 부재(껍데기 아님)
rm -rf "$REPO/.worktrees/da2/d1" "$REPO/.worktrees/da3/d1"
rm -f "$REPO/.git/worktrees/br1/info/sparse-checkout"      # sparse 표식(core.sparseCheckout=true)만 남김
rm -rf "$REPO/.worktrees/ig1/ex"; printf 'ex/\n' >> "$REPO/.git/info/exclude"   # H 인데 디스크에 없고 제외 규칙에 걸린 이름(실측 .serena 꼴)
rm -f "$REPO/.worktrees/g1/keep"; rm -rf "$REPO/.worktrees/g2/kdir" "$REPO/.worktrees/g3/kdir2"
printf 'keep/\nkdir\nkdir2/\n' >> "$REPO/.git/info/exclude"   # ⓖ — 같은 종류 규칙만 부재를 정상으로 본다
G4="$(git -C "$REPO/.worktrees/da4" rev-parse --git-path info/sparse-checkout)"
rm -f "$G4"; mkdir -p "$G4"                                 # 패턴 파일 자리를 «폴더» 로(반례 ④)

[ -d "$REPO/.worktrees/sp1/d0" ] && [ ! -e "$REPO/.worktrees/sp1/d1" ] && ok "전제: sp1 은 sparse(cone d0) — d0 만 있고 d1~d3 없음" || bad "전제 실패: sp1 체크아웃"
[ "$(git -C "$REPO/.worktrees/sp1" config --bool --get core.sparseCheckout)" = true ] && ok "전제: sp1 core.sparseCheckout=true" || bad "전제 실패: sp1 sparse 표식"
[ -d "$REPO/.worktrees/da1/d0/absent" ] && [ -d "$REPO/.worktrees/da1/d1" ] && [ ! -e "$REPO/.worktrees/da1/d3" ] && ok "전제: da1 은 비cone 3패턴 — d0·d1·d2 있고 d3 없음" || bad "전제 실패: da1 체크아웃"
[ ! -e "$REPO/.worktrees/da3/d1" ] && [ -d "$REPO/.worktrees/da4/d3" ] && ok "전제: da3 d1 삭제 · da4 는 전체 체크아웃(패턴 /*)" || bad "전제 실패: da3/da4"
[ -d "$REPO/.worktrees/ig1/d0" ] && [ ! -e "$REPO/.worktrees/ig1/ex" ] && [ "$(git -C "$REPO/.worktrees/ig1" ls-files -t | grep -c "^H ex/")" -ge 1 ] && ok "전제: ig1 은 ex 가 H 인데 디스크에 없고 제외 규칙(ex/)에 걸림" || bad "전제 실패: ig1"
[ -f "$REPO/d0/한글 이름.md" ] && [ -f "$REPO/d0/dq\"name.md" ] && [ -d "$REPO/.worktrees/sp1/d0" ] && ok "전제: ⓕ 꼴 묶음(한글·공백·따옴표·줄바꿈)이 d0 안에 있고 cone sparse(sp1) 가 그것을 받았다" || bad "전제 실패: ⓕ 꼴 묶음"
[ ! -e "$REPO/.worktrees/g1/keep" ] && [ ! -e "$REPO/.worktrees/g2/kdir" ] && [ ! -e "$REPO/.worktrees/g3/kdir2" ] && ok "전제: ⓖ g1 파일 keep 부재 · g2 폴더 kdir 부재 · g3 폴더 kdir2 부재" || bad "전제 실패: ⓖ 배치"
[ -L "$REPO/.worktrees/ln1/top-link" ] && [ "$(git -C "$REPO/.worktrees/ln1" ls-files -s top-link | cut -d' ' -f1)" = 120000 ] && ok "전제: ⓕ ln1 에 최상위 심볼릭 링크(120000) 가 디스크에 있음" || bad "전제 실패: ⓕ 링크"

echo "== ⓐⓑⓒⓓ + DA⑥ r1 반례 4칸 + r2 반례 ⓕⓖ — 한 번의 스캔"
out="$(swp "$T/scan")"
has  "$out" "껍데기 6곳(전체 6곳): da2 da3 g1 g2 n2 sp2" "ⓑⓑ2ⓑ3ⓒⓖ 진짜 껍데기만 — sp2(d0 부재) · da2(**/*.md · d1 부재) · da3(/d1/ + ! 제외 · d1 부재) · n2(일반 최상위 2개 부재) · g1(파일 keep + 폴더 규칙) · g2(폴더 kdir + 파일 규칙)"
hasnt "$out" "sp1"                        "ⓐ cone sparse(d0 있음) → 껍데기 0"
hasnt "$out" "sp3"                        "보론 비cone(d1/) sparse → 껍데기 0"
hasnt "$out" "da1"                        "ⓐ2 비cone /d0/absent · /d2/absent · /d1/ → 껍데기 0 (r1 은 하위 경로를 접어 오탐)"
hasnt "$out" " n1"                        "ⓒ 일반 워크트리 · 최상위 1개 부재 → 껍데기 아님(회귀 0)"
hasnt "$out" "ig1"                        "ⓔ 제외 규칙에 걸린 이름(H 인데 디스크에 없음) → 껍데기 0"
hasnt "$out" "g3"                         "ⓖ-3 추적 «폴더» kdir2 삭제 + 폴더 규칙 kdir2/ → 껍데기 0(같은 종류 규칙)"
hasnt "$out" "ln1"                        "ⓕ-링크 최상위 심볼릭 링크(120000) 가 디스크에 있음 → 껍데기 0 (보강 1: 종류를 mode 로 받는 자리)"
has  "$out" "판정 불가 2곳"                "ⓓⓓ2 패턴을 못 읽은 sparse 2곳 → «판정 불가» 1줄"
has  "$out" "br1"                         "  └ 판정 불가 줄에 경로(br1 — 패턴 파일 삭제)"
has  "$out" "da4"                         "  └ 판정 불가 줄에 경로(da4 — 패턴 파일 자리가 폴더)"
case "$out" in *"[HIL] seat=byz-harness-wt-shell 반쯤 지워진 워크트리 껍데기 6곳(전체 6곳): da2 da3 g1 g2 n2 sp2 —"*) ok "  └ 껍데기 줄 꼴 그대로(팀 미상 = harness · r444)";; *) bad "껍데기 줄 꼴이 달라짐 ← ${out:0:400}";; esac
case "$out" in *"판정 불가 2곳 —"*) ok "  └ 판정 불가 줄 꼴 그대로";; *) bad "판정 불가 줄 꼴이 달라짐 ← ${out:0:400}";; esac
outq="$(swp "$T/scan-q" false)"
has  "$outq" "껍데기 6곳(전체 6곳): da2 da3 g1 g2 n2 sp2" "ⓕ core.quotePath=false 로도 같은 목록 — 경로 글자와 상관없이 판정"
hasnt "$outq" "sp1"                        "ⓕ 한글·공백·큰따옴표·줄바꿈 이름이 드는 cone sparse(d0) → 껍데기 0 (기본 scan = quotePath=true 로도 0 · r2 는 따옴표를 최상위 이름으로 읽어 오탐)"
out2="$(swp "$T/scan")"
hasnt "$out2" "[HIL]"                     "  └ 바뀐 것 없음 → 같은 목록이면 두 번째 스캔은 경보 0(바뀐 때만)"
hasnt "$out2" "판정 불가"                  "  └ 판정 불가 목록도 그대로면 다시 0"
rm -rf "$REPO/.worktrees/n1/d1"           # 일반 워크트리 최상위 2개 부재 → 껍데기
out3="$(swp "$T/scan")"
has  "$out3" "껍데기 7곳(전체 7곳): da2 da3 g1 g2 n1 n2 sp2" "ⓒ 일반 워크트리 부재가 2개로 늘면 다시 껍데기(n1 추가)"
[ -d "$REPO/.worktrees/sp1/d0" ] && [ -d "$REPO/.worktrees/da1" ] && [ -d "$REPO/.worktrees/br1" ] && ok "  └ 경보는 읽기만 — 워크트리 손 0" || bad "경보가 워크트리를 건드림"
[ -z "$(ls "$T/scan"/.sparse-* 2>/dev/null)" ] && ok "  └ sparse 임시 파일 남김 0" || bad "sparse 임시 파일이 남음"
[ -z "$(ls -d "$REPO"/.worktrees/*.deleting-* 2>/dev/null)" ] && ok "  └ 삭제·이름 바꿈 0" || bad "스캔이 워크트리를 지움"

echo "== 결과"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAIL $fail"; exit 1
