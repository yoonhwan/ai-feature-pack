#!/usr/bin/env bash
# test_wt_shell_scan_sparse_r945.sh — 카드 r945: 껍데기 경보(shell_scan)가 sparse 워크트리(문서·카드 작업 공간)를 «반쯤 지워진 껍데기» 로 세지 않는다.
#   ★r5★ 판정 = git 에게 직접 묻기 — `git ls-files -d -z` 의 «삭제된 추적 파일» 수 ≥ 1 = 껍데기 · 7초 상한 · git 규칙(sparse 패턴·exclude·부정규칙·이름 글자) 흉내 0.
#   ⓐ cone sparse(d0 만) · d0 있음 → 껍데기 0 (옛 셈은 sparse 밖 부재를 부재로 세서 껍데기 1)
#   ⓑ cone sparse(d0 만) · d0 도 없음 → 껍데기 1 (진짜 반쯤 지워짐)
#   ⓒ 일반 워크트리 · 최상위 2개 부재 → 껍데기 1(회귀 0) · 1개 부재 → 0(회귀 0 · 일반 규칙은 그대로)
#   ⓓ sparse 표식만 있고 git 이 삭제 목록을 못 줌(인덱스 망가짐 rc≠0) → 껍데기 0 + «판정 불가 <경로>» 1줄(오빠 HIL 0 · 삭제 0)
#   ⓐ2(DA⑥ r1 반례 ①) 비cone `/d0/absent` `/d2/absent` `/d1/` → 껍데기 0 (패턴을 손으로 접으면 오탐)
#   ⓑ2(반례 ②-워크트리 config) 비cone `**/*.md` + d1 삭제 → 껍데기 1
#   ⓑ3(반례 ②-공용 config·! 제외) 비cone `/d1/` + `!/d1/excluded/` + d1 삭제 → 껍데기 1
#   ⓓ2(반례 ④ · r6 동결 기대 복원) 비cone `/*` 뒤 패턴 파일을 «폴더» 로 교체 → «판정 불가» 1줄(동결값 1 · 껍데기 0 · 삭제 0) — sparse 표식이 true 면 패턴을 읽을 수 있는지 한 번 묻는다
#   ⓦ(결정 5 · r8) 가짜 git «전 명령 rc128» 전수 실패 — 루트 미지정 = «:init» 1줄 · u=1 / 루트 지정 = init+worktree-list+orphan-list · u=3 · 껍데기 0 · HIL 0 · 삭제 0 · git7 자리 수 == 시험이 아는 자리 수(새 자리 = FAIL)
#   ⓣ(결정 4 ①) sparse 안 «하위 파일 1개» 만 부재(d0/a · d0 폴더는 디스크에 있음) → 껍데기 0(최상위로 접는다) · 폴더가 통째로 사라지면 1
#   ⓤ(결정 4 ②) 판정 불가가 있으면 요약 줄에 «u=N» 이 붙는다
#   ⓥ(결정 4 ③) 공용 config 가 깨져도 orphan 검사는 git7 을 지난다(«:orphan-list» 1줄 · python 이 git 을 직접 부르지 않는다 · 직접 호출 정적 검사 0)
#   ⓠⓡⓢ(r6 · 동결 계약 ④) git 호출 실패 3경로 — 워크트리 설정 깨짐(:config) · 공용 config 깨짐(:worktree-list) · 트리 객체 없음(:ls-tree) → 각각 «판정 불가» 1줄 · 껍데기 0 · HIL 0 · 삭제 0(조용한 0 · 일반 후퇴 0)
#   ⓔ 제외 규칙(.git/info/exclude)에 걸린 이름이 H 인데 디스크에 없음 → 껍데기 1 (r5: git 은 추적 파일 부재를 제외 규칙으로 안 가린다 · 옛 판은 «정상» 으로 숨겼다)
#   ⓙ(DA⑥ r4 반례) `.git/info/exclude` 의 제외 취소 규칙(`!keep`)이 진짜 부재를 숨기지 않는다 → 껍데기 1
#   ⓗ(DA⑥ r3 반례 1·2) 최상위 이름에 제어문자(줄바꿈·탭·0x01·0x7F) 가 있는 sparse — 이름을 «안 읽으므로» 판정 불가가 아니라 «정확히» 센다: 이름이 다 있으면 0 · 줄바꿈 이름 폴더를 지우면 1
#   ⓘ(DA⑥ r3 반례 3) 추적 «파일» keep2 삭제(파일 규칙 keep2) → 1 · 추적 «파일» keep3 삭제(폴더 규칙 keep3/) → 1 (r5: 제외 규칙은 판정에 안 들어온다)
#   ⓕ core.quotePath=false 로도 같은 목록 · 한글·공백·큰따옴표·줄바꿈 이름이 든 cone sparse → 0 (따옴표를 경로로 읽지 않는다)
#   변이 8: 판정 불가를 «껍데기 아님» 으로(1) → ⓓ 빨강 · 개수 ≥1 → ≥2(2) → ⓑ 빨강 · sparse 분기 끔(3) → ⓑ 빨강 · 개수 ≥1 → ≥0(4) → ⓐ 빨강 · gitfail 의 «판정 불가» 기록 끔(5) → ⓓⓓ2ⓠⓡⓢ 빨강 · 접기(최상위 존재 확인) 끔(6) → ⓣ 빨강 · SCAN_U 올리기 제거(7) → ⓦ 빨강 · || pwd 부활(8) → ⓦ 빨강
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
  1) MUTP 'if ! missing="$(sparse_deleted "$p" "$spx")"; then' 'missing="$(sparse_deleted "$p" "$spx")"; if false; then'
     echo "MUT 1 — 판정 불가를 «껍데기 아님» 으로";;
  2) MUTP '      [ "$missing" -ge 1 ] || continue' '      [ "$missing" -ge 2 ] || continue   # MUT2 임계 2'
     echo "MUT 2 — 개수 임계 ≥1 → ≥2";;
  3) MUTP '    if [ "$crc" -eq 0 ] && [ "$spcfg" = true ]; then' '    if false; then   # MUT3 sparse 분기 끔(sparse 를 일반 규칙으로)'
     echo "MUT 3 — sparse 분기 끔(패턴 해석 없이 일반 규칙)";;
  4) MUTP '      [ "$missing" -ge 1 ] || continue' '      [ "$missing" -ge 0 ] || continue   # MUT4 임계 0'
     echo "MUT 4 — 개수 임계 ≥1 → ≥0(0 개도 껍데기)";;
  5) MUTP 'gitfail() { und="$und$1:$2 "; ucnt=$((ucnt+1)); }' 'gitfail() { : ; }   # MUT5 실패를 «판정 불가» 로 안 셈'
     echo "MUT 5 — git7 실패를 «판정 불가» 로 안 셈(조용히 넘김)";;
  6) MUTP '    [ -e "$p/$top" ] || [ -L "$p/$top" ] && continue   # 최상위가 디스크에 있으면 그 안 하위 파일 부재는 껍데기가 아니다' '    :   # MUT6 최상위 접기(존재 확인) 끔'
     echo "MUT 6 — 삭제 파일을 최상위로 접지 않음(하위 부재도 껍데기)";;
  7) MUTP '    SCAN_U=$((SCAN_U+1))   # ★r8★ 판정 불가 셈은 한 카운터(SCAN_U) 하나로 모은다' '    :   # MUT7 판정 불가 셈을 SCAN_U 에 안 올림'
     echo "MUT 7 — SCAN_U 올리기 제거";;
  8) MUTP 'WT="$(git7 "$PWD" rev-parse --show-toplevel 2>/dev/null)"; INIT_RC=$?' 'WT="$(git7 "$PWD" rev-parse --show-toplevel 2>/dev/null || pwd)"; INIT_RC=0   # MUT8 || pwd 부활'
     echo "MUT 8 — || pwd 부활(초기 조회 실패를 삼킴)";;
  *) echo "usage: WT_TEST_MUT=0|1|2|3|4|5|6|7|8"; exit 2;;
esac
"${WT_TEST_BASH:-bash}" -n "$T/bin/ft-wt-sweep.sh" && ok "본보기 bash -n(${WT_TEST_BASH:-bash})" || bad "bash -n"

REPO="$T/repo"; mkdir -p "$REPO"; git -C "$REPO" init -q -b main
GIT() { git -C "$REPO" -c user.email=t@t -c user.name=t "$@"; }
mkdir -p "$REPO/d0/absent" "$REPO/d1/excluded" "$REPO/d2/absent" "$REPO/d3" "$REPO/kdir" "$REPO/kdir2"
for f in d0/x d0/absent/f d1/x d1/note.md d1/excluded/g d2/x d2/absent/f d3/x ex/f keep keep2 keep3 kdir/f kdir2/f; do mkdir -p "$(dirname "$REPO/$f")"; echo "$f" > "$REPO/$f"; done
# ⓕ 이름 글자 꼴 묶음(DA⑥ r2 반례 ①) — 한글·공백·큰따옴표·줄바꿈이 «하위 경로» 에 들어가도 이름을 읽지 않으므로 판정이 흔들리지 않는다
printf 'h\n' > "$REPO/d0/한글 이름.md"
printf 'q\n' > "$REPO/d0/dq\"name.md"
printf 'n\n' > "$REPO/d0/nl$(printf '\n')name.md"
ln -s d3 "$REPO/top-link"                                 # 보강 1 — 최상위 심볼릭 링크(120000) 는 디스크에 링크로 있다 = 정상
GIT add -A && GIT commit -q -m init

# swp <계획 디렉터리> [quotePath true|false] [스캔루트] — sweep 1회(껍데기 스캔 간격 0 = 매번 훑는다)
swp() { mkdir -p "$1"; ( cd "${3:-$REPO}" && env -i HOME="$HOME" PATH="$PATH" ${2:+GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.quotePath GIT_CONFIG_VALUE_0=$2} FT_WT_CLEAN_DIR="$1" FT_WT_SCAN_ROOT="${3:-$REPO}" FT_WT_SHELL_SCAN_SEC=0 \
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
mksparse br1 cone d0                      # ⓓ (sparse 표식만 남기고 git 이 목록을 못 주게)
mksparse da1 noconc '/d0/absent' '/d2/absent' '/d1/'   # ⓐ2 반례 ①
mksparse da2 noconc '**/*.md'                          # ⓑ2 반례 ②
mksparse da3 noconc '/d1/' '!/d1/excluded/'            # ⓑ3 반례 ② 공용 config·! 제외
mksparse da4 noconc '/*'                               # ⓓ2 반례 ④
mksparse ig1 noconc '/*'                               # ⓔ 전체 체크아웃 뒤 ex 를 지우고 제외 규칙을 넣는다
mksparse g1 noconc '/*'                                # ⓙ 제외 취소 규칙(!keep) 아래 keep 삭제
mksparse i1 noconc '/*'                                # ⓘ-1 파일 keep2 삭제 + «파일 규칙» keep2
mksparse i2 noconc '/*'                                # ⓘ-2 파일 keep3 삭제 + «폴더 규칙» keep3/
mksparse ln1 noconc '/*'                               # ⓕ-링크 최상위 심볼릭 링크가 있는 정상 sparse(전체 체크아웃)
rm -rf "$REPO/.worktrees/sp2/d0"
rm -rf "$REPO/.worktrees/n2/d0" "$REPO/.worktrees/n2/d1"   # 최상위 2개 부재
rm -rf "$REPO/.worktrees/n1/d0"                            # 최상위 1개 부재(껍데기 아님)
rm -rf "$REPO/.worktrees/da2/d1" "$REPO/.worktrees/da3/d1"
rm -rf "$REPO/.worktrees/ig1/ex"; printf 'ex/\n' >> "$REPO/.git/info/exclude"   # H 인데 디스크에 없고 제외 규칙에 걸린 이름(실측 .serena 꼴)
rm -rf "$REPO/.worktrees/g1/keep"; printf 'keep\n!keep\n' >> "$REPO/.git/info/exclude"   # ⓙ 제외 취소 규칙(DA⑥ r4 반례)
rm -f "$REPO/.worktrees/i1/keep2" "$REPO/.worktrees/i2/keep3"
printf 'keep2\nkeep3/\n' >> "$REPO/.git/info/exclude"          # ⓘ — r5 는 제외 규칙을 판정에 안 쓴다(추적 파일 부재는 그대로 센다)
G4="$(git -C "$REPO/.worktrees/da4" rev-parse --git-path info/sparse-checkout)"
rm -f "$G4"; mkdir -p "$G4"                                 # 패턴 파일 자리를 «폴더» 로(반례 ④) — r5 는 패턴을 안 읽으므로 정상 판정
printf 'garbage' > "$(git -C "$REPO/.worktrees/br1" rev-parse --git-path index)"   # ⓓ 인덱스 망가짐 = git 이 삭제 목록을 못 줌(rc=128)

[ -d "$REPO/.worktrees/sp1/d0" ] && [ ! -e "$REPO/.worktrees/sp1/d1" ] && ok "전제: sp1 은 sparse(cone d0) — d0 만 있고 d1~d3 없음" || bad "전제 실패: sp1 체크아웃"
[ "$(git -C "$REPO/.worktrees/sp1" config --bool --get core.sparseCheckout)" = true ] && ok "전제: sp1 core.sparseCheckout=true" || bad "전제 실패: sp1 sparse 표식"
[ -d "$REPO/.worktrees/da1/d0" ] && [ -d "$REPO/.worktrees/da1/d1" ] && [ ! -e "$REPO/.worktrees/da1/d3" ] && ok "전제: da1 은 비cone 3패턴 — d0·d1·d2 있고 d3 없음" || bad "전제 실패: da1 체크아웃"
[ ! -e "$REPO/.worktrees/da3/d1" ] && [ -d "$REPO/.worktrees/da4/d3" ] && ok "전제: da3 d1 삭제 · da4 는 전체 체크아웃(패턴 /*)" || bad "전제 실패: da3/da4"
[ -d "$REPO/.worktrees/ig1/d0" ] && [ ! -e "$REPO/.worktrees/ig1/ex" ] && [ "$(git -C "$REPO/.worktrees/ig1" ls-files -t | grep -c "^H ex/")" -ge 1 ] && ok "전제: ig1 은 ex 가 H 인데 디스크에 없고 제외 규칙(ex/)에 걸림" || bad "전제 실패: ig1"
[ -f "$REPO/d0/한글 이름.md" ] && [ -f "$REPO/d0/dq\"name.md" ] && [ -d "$REPO/.worktrees/sp1/d0" ] && ok "전제: ⓕ 꼴 묶음(한글·공백·따옴표·줄바꿈)이 d0 안에 있고 cone sparse(sp1) 가 그것을 받았다" || bad "전제 실패: ⓕ 꼴 묶음"
[ -L "$REPO/.worktrees/ln1/top-link" ] && [ "$(git -C "$REPO/.worktrees/ln1" ls-files -s top-link | cut -d' ' -f1)" = 120000 ] && ok "전제: ⓕ ln1 에 최상위 심볼릭 링크(120000) 가 디스크에 있음" || bad "전제 실패: ⓕ 링크"
[ ! -e "$REPO/.worktrees/i1/keep2" ] && [ ! -e "$REPO/.worktrees/i2/keep3" ] && ok "전제: ⓘ i1 파일 keep2 부재 · i2 파일 keep3 부재" || bad "전제 실패: ⓘ 배치"
[ ! -e "$REPO/.worktrees/g1/keep" ] && ok "전제: ⓙ g1 keep 부재(제외 취소 규칙 !keep 아래)" || bad "전제 실패: ⓙ 배치"
[ "$(git -C "$REPO/.worktrees/br1" ls-files -d 2>/dev/null; echo "rc=$?")" = "rc=128" ] && ok "전제: ⓓ br1 은 인덱스가 망가져 git 이 삭제 목록을 못 준다(rc=128)" || bad "전제 실패: ⓓ 인덱스"
[ "$(git -C "$REPO/.worktrees/da4" ls-files -d 2>/dev/null; echo "rc=$?")" = "rc=0" ] && ok "전제: ⓓ2 da4 는 패턴 파일이 폴더여도 ls-files -d 는 rc=0(r5 가 패턴을 안 읽는다)" || bad "전제 실패: ⓓ2"

echo "== ⓐⓑⓒⓓⓔⓙ + DA⑥ r1·r2·r3·r4 반례 — 한 번의 스캔"
out="$(swp "$T/scan")"
has  "$out" "껍데기 8곳(전체 8곳): da2 da3 g1 i1 i2 ig1 n2 sp2" "ⓑⓑ2ⓑ3ⓔⓙⓒⓘ 진짜 부재만 — sp2(d0 부재) · da2(**/*.md · d1 부재) · da3(/d1/ + ! 제외 · d1 부재) · n2(일반 최상위 2개 부재) · ig1(H 인 ex 부재 · 제외 규칙에 걸려도 센다) · g1(!keep 아래 keep 부재) · i2(파일 keep3 부재)"
hasnt "$out" "sp1"                        "ⓐ cone sparse(d0 있음) → 껍데기 0"
hasnt "$out" "sp3"                        "보론 비cone(d1/) sparse → 껍데기 0"
hasnt "$out" "da1"                        "ⓐ2 비cone /d0/absent · /d2/absent · /d1/ → 껍데기 0 (패턴을 손으로 접으면 오탐)"
hasnt "$out" " n1"                        "ⓒ 일반 워크트리 · 최상위 1개 부재 → 껍데기 아님(회귀 0)"
hasnt "$out" "ln1"                        "ⓕ-링크 최상위 심볼릭 링크(120000) 가 디스크에 있음 → 껍데기 0"
has  "$out" "판정 불가 2곳"                "ⓓⓓ2 git 호출이 실패한 sparse 2곳 → «판정 불가» 1줄"
has  "$out" "br1:ls-files"                 "  └ 판정 불가 줄에 «경로:단계»(br1:ls-files — 인덱스 망가짐)"
has  "$out" "da4:sparse-list"              "ⓓ2 패턴 파일 자리가 폴더 → «경로:단계»(da4:sparse-list · 동결 기대 복원)"
case "$out" in *"[HIL] seat=byz-harness-wt-shell 반쯤 지워진 워크트리 껍데기 8곳(전체 8곳): da2 da3 g1 i1 i2 ig1 n2 sp2 —"*) ok "  └ 껍데기 줄 꼴 그대로(팀 미상 = harness · r444)";; *) bad "껍데기 줄 꼴이 달라짐 ← ${out:0:400}";; esac
case "$out" in *"판정 불가 2곳 — git 호출 실패로 껍데기 판정 보류"*) ok "  └ 판정 불가 줄 꼴 그대로(«경로:단계» 포함)";; *) bad "판정 불가 줄 꼴이 달라짐 ← ${out:0:400}";; esac
outq="$(swp "$T/scan-q" false)"
has  "$outq" "껍데기 8곳(전체 8곳): da2 da3 g1 i1 i2 ig1 n2 sp2" "ⓕ core.quotePath=false 로도 같은 목록 — 경로 글자와 상관없이 판정"
hasnt "$outq" "sp1"                        "ⓕ 한글·공백·큰따옴표·줄바꿈 이름이 드는 cone sparse(d0) → 껍데기 0 (따옴표를 경로로 읽지 않는다)"
out2="$(swp "$T/scan")"
hasnt "$out2" "[HIL]"                     "  └ 바뀐 것 없음 → 같은 목록이면 두 번째 스캔은 경보 0(바뀐 때만)"
hasnt "$out2" "판정 불가"                  "  └ 판정 불가 목록도 그대로면 다시 0"
rm -rf "$REPO/.worktrees/n1/d1"           # 일반 워크트리 최상위 2개 부재 → 껍데기
out3="$(swp "$T/scan")"
has  "$out3" "껍데기 9곳(전체 9곳): da2 da3 g1 i1 i2 ig1 n1 n2 sp2" "ⓒ 일반 워크트리 부재가 2개로 늘면 다시 껍데기(n1 추가)"
[ -d "$REPO/.worktrees/sp1/d0" ] && [ -d "$REPO/.worktrees/da1" ] && [ -d "$REPO/.worktrees/br1" ] && ok "  └ 경보는 읽기만 — 워크트리 손 0" || bad "경보가 워크트리를 건드림"
[ -z "$(ls "$T/scan"/.sparse-* 2>/dev/null)" ] && ok "  └ sparse 임시 파일 남김 0" || bad "sparse 임시 파일이 남음"
[ -z "$(ls -d "$REPO"/.worktrees/*.deleting-* 2>/dev/null)" ] && ok "  └ 삭제·이름 바꿈 0" || bad "스캔이 워크트리를 지움"

echo "== ⓠⓡⓢ git 호출 실패 3경로(r6 동결 계약 ④) — 판정 불가 1줄 · 껍데기 0 · HIL 0 · 삭제 0"
# ⓠ 워크트리 설정(config.worktree)이 깨짐 → 설정 조회 rc128 → «경로:config»
R3="$T/repo3"; mkdir -p "$R3"; git -C "$R3" init -q -b main
G3() { git -C "$R3" -c user.email=t@t -c user.name=t "$@"; }
mkdir -p "$R3/d0" "$R3/d1"; echo x > "$R3/d0/x"; echo y > "$R3/d1/y"
G3 add -A && G3 commit -q -m c3
G3 worktree add -q --no-checkout "$R3/.worktrees/q1" -b q1
git -C "$R3/.worktrees/q1" sparse-checkout set d0 >/dev/null 2>&1
git -C "$R3/.worktrees/q1" read-tree -mu HEAD >/dev/null 2>&1
C3="$(git -C "$R3/.worktrees/q1" rev-parse --git-path config.worktree)"
printf '[invalid\n' >> "$C3"
[ "$(git -C "$R3/.worktrees/q1" config --bool --get core.sparseCheckout 2>/dev/null; echo "rc=$?")" = "rc=128" ] && ok "전제: ⓠ q1 설정 조회 rc=128" || bad "전제 실패: ⓠ 설정"
outq1="$(swp "$T/scan-q1" '' "$R3")"
has   "$outq1" "판정 불가 1곳"            "ⓠ 워크트리 설정이 깨지면 «판정 불가» 1줄(일반 워크트리로 후퇴해 껍데기 1 로 세지 않는다)"
has   "$outq1" "q1:config"                "  └ 단계 이름 = config"
hasnt "$outq1" "[HIL]"                    "  └ 오빠 HIL 0"
hasnt "$outq1" "반쯤 지워진"                "  └ 껍데기 0(조용한 0 이 아니라 «판정 불가»)"
[ -d "$R3/.worktrees/q1/d0" ] && ok "  └ 경보는 읽기만 — 워크트리 손 0(ⓠ)" || bad "경보가 워크트리를 건드림(ⓠ)"
has   "$outq1" "u=1"                      "ⓤ 판정 불가 수가 요약 줄에 «u=1» 로 나온다(결정 4 ②)"
# ⓡ 공용 config(.git/config)가 깨짐 → worktree list rc128 → «경로:worktree-list» · 조용한 0 아님
R4="$T/repo4"; mkdir -p "$R4"; git -C "$R4" init -q -b main
G4R() { git -C "$R4" -c user.email=t@t -c user.name=t "$@"; }
mkdir -p "$R4/d0"; echo x > "$R4/d0/x"; G4R add -A && G4R commit -q -m c4
G4R worktree add -q "$R4/.worktrees/w1" -b w1
rm -rf "$R4/.worktrees/w1/d0"             # 진짜 껍데기(목록을 못 읽어 «판정 불가» 로 보류돼야 한다)
printf '[invalid\n' >> "$R4/.git/config"
[ "$(git -C "$R4" worktree list --porcelain 2>/dev/null; echo "rc=$?")" = "rc=128" ] && ok "전제: ⓡ worktree list rc=128" || bad "전제 실패: ⓡ 공용 config"
outr1="$(swp "$T/scan-r1" '' "$R4")"
has   "$outr1" "판정 불가 1곳"            "ⓡ 공용 config 가 깨지면 «판정 불가» 1줄(조용한 «껍데기 0» 으로 끝나지 않는다)"
has   "$outr1" "worktree-list"            "  └ 단계 이름 = worktree-list"
hasnt "$outr1" "[HIL]"                    "  └ 오빠 HIL 0"
has   "$outr1" ":orphan-list"              "ⓥ 공용 config 가 깨지면 orphan 검사도 «:orphan-list» 판정 불가 1줄(git7 경유 · 결정 4 ③)"
hasnt "$outr1" "git worktree list rc="     "  └ python 이 git 을 직접 부르지 않는다(옛 메시지 사라짐)"
grep -q 'subprocess.run(\["git"' "$T/bin/ft-wt-sweep.sh" && bad "  └ 직접 git 호출 잔존(python)" || ok "  └ 직접 git 호출 0(python 정적 검사)"
grep -nE '^[^#]*\$\(git |^[^#]*git -C "' "$T/bin/ft-wt-sweep.sh" | grep -vE '^[0-9]+:(git7|sgit)' | grep -v 'cap "' | grep -q . && bad "  └ 직접 git 호출 잔존(셸)" || ok "  └ 직접 git 호출 0(셸 정적 검사 — 전부 git7 또는 r844 sgit/cap 경유)"
# ⓢ 트리 객체가 없음 → ls-tree rc128 → «경로:ls-tree»(일반 워크트리)
R5="$T/repo5"; mkdir -p "$R5"; git -C "$R5" init -q -b main
G5() { git -C "$R5" -c user.email=t@t -c user.name=t "$@"; }
mkdir -p "$R5/d0" "$R5/d1"; echo x > "$R5/d0/x"; echo y > "$R5/d1/y"; G5 add -A && G5 commit -q -m c5
G5 worktree add -q "$R5/.worktrees/s1" -b s1
OBJ="$(G5 rev-parse 'HEAD^{tree}')"; OP="$R5/.git/objects/${OBJ:0:2}/${OBJ:2}"
mkdir -p "$T/objhold"; mv "$OP" "$T/objhold/$OBJ"
[ "$(git -C "$R5" ls-tree --name-only HEAD 2>/dev/null; echo "rc=$?")" = "rc=128" ] && ok "전제: ⓢ ls-tree rc=128(트리 객체 없음)" || bad "전제 실패: ⓢ 트리 객체"
outs1="$(swp "$T/scan-s1" '' "$R5")"
has   "$outs1" "판정 불가 1곳"            "ⓢ 트리 객체가 없으면 «판정 불가» 1줄(조용한 «껍데기 0» 아님)"
has   "$outs1" "s1:ls-tree"               "  └ 단계 이름 = ls-tree"
hasnt "$outs1" "[HIL]"                    "  └ 오빠 HIL 0"
mkdir -p "$R5/.git/objects/${OBJ:0:2}"; mv "$T/objhold/$OBJ" "$OP"   # 되돌림(임시 사본 정리)
[ "$(git -C "$R5" ls-tree --name-only HEAD >/dev/null 2>&1; echo "rc=$?")" = "rc=0" ] && ok "  └ 되돌림 확인(객체 복구 rc=0)" || bad "되돌림 실패: ⓢ 객체"

echo "== ⓣ 결정 4 ① 하위 파일 부재로 접기 — 폴더가 살아 있으면 껍데기 0"
R6="$T/repo6"; mkdir -p "$R6"; git -C "$R6" init -q -b main
G6() { git -C "$R6" -c user.email=t@t -c user.name=t "$@"; }
mkdir -p "$R6/d0" "$R6/d1"; echo a > "$R6/d0/a"; echo b > "$R6/d0/b"; echo y > "$R6/d1/y"; G6 add -A && G6 commit -q -m c6
g6sp() { local n="$1"; shift
  G6 worktree add -q --no-checkout "$R6/.worktrees/$n" -b "$n"
  git -C "$R6/.worktrees/$n" sparse-checkout set "$@" >/dev/null 2>&1
  git -C "$R6/.worktrees/$n" read-tree -mu HEAD >/dev/null 2>&1; }
g6sp t1 d0; g6sp t2 d0
rm -f "$R6/.worktrees/t1/d0/a"                    # ⓣ 하위 파일 1개만 부재(d0 폴더는 있음)
rm -rf "$R6/.worktrees/t2/d0"                     # 대조: 폴더가 통째로 사라짐
[ -d "$R6/.worktrees/t1/d0" ] && [ ! -e "$R6/.worktrees/t1/d0/a" ] && ok "전제: ⓣ t1 은 d0 살아 있고 d0/a 만 없음" || bad "전제 실패: ⓣ t1"
has   "$(git -C "$R6/.worktrees/t1" ls-files -d 2>/dev/null)" "d0/a" "전제: git 은 d0/a 를 «삭제된 추적 파일» 로 본다(그래서 접기가 필요)"
outt="$(swp "$T/scan-t" '' "$R6")"
has   "$outt" "껍데기 1곳(전체 1곳): t2" "ⓣ 하위 파일 1개 부재(t1) → 껍데기 0 · 폴더가 통째로 사라진 t2 → 껍데기 1"
hasnt "$outt" " t1"                       "  └ t1 이 목록에 없다(최상위로 접었으므로)"
[ -f "$R6/.worktrees/t1/d0/b" ] && ok "  └ 경보는 읽기만 — 워크트리 손 0(ⓣ)" || bad "경보가 워크트리를 건드림(ⓣ)"

echo "== ⓗ 제어문자 이름(DA⑥ r3 반례 1·2) — 이름을 안 읽으므로 «정확히» 센다(오탐 0 · 누락 0 · 삭제 0)"
R2="$T/repo2"; mkdir -p "$R2"; git -C "$R2" init -q -b main
G2() { git -C "$R2" -c user.email=t@t -c user.name=t "$@"; }
NL="$(printf 'a\nb')"; TB="$(printf 'tab\there')"; C1="$(printf 'c\001here')"; D7="$(printf 'd\177here')"
mkdir -p "$R2/d0" "$R2/$NL"; echo x > "$R2/d0/x"; echo n > "$R2/$NL/f"
printf 't\n' > "$R2/$TB"; printf 'c\n' > "$R2/$C1"; printf 'z\n' > "$R2/$D7"
G2 add -A && G2 commit -q -m c2
# g2sp <이름> <cone|noconc> <패턴…> — 같은 꼴의 sparse 워크트리(최상위 이름에 제어문자가 드는 리포)
g2sp() { local n="$1" mode="$2"; shift 2
  G2 worktree add -q --no-checkout "$R2/.worktrees/$n" -b "$n"
  if [ "$mode" = cone ]; then git -C "$R2/.worktrees/$n" sparse-checkout set "$@" >/dev/null 2>&1
  else git -C "$R2/.worktrees/$n" sparse-checkout set --no-cone "$@" >/dev/null 2>&1; fi
  git -C "$R2/.worktrees/$n" read-tree -mu HEAD >/dev/null 2>&1; }
g2sp c1 noconc '/*'        # 이름이 다 있으면 제어문자 글자가 있어도 껍데기 0(오탐 0)
g2sp c2 noconc '/*'        # 줄바꿈 이름 폴더 삭제 → 껍데기 1(조용한 누락 0 — 옛 판은 «판정 불가» 로 보류했다)
g2sp c3 noconc '/d0/'      # 제어문자 이름을 «안 받는» sparse → 정상 판정
g2sp c4 noconc '/d0/'      # d0 삭제 → 껍데기 1
rm -rf "$R2/.worktrees/c2/$NL" "$R2/.worktrees/c4/d0"
[ -d "$R2/.worktrees/c1/$NL" ] && [ ! -e "$R2/.worktrees/c2/$NL" ] && [ -d "$R2/.worktrees/c4" ] && ok "전제: ⓗ c1 에 줄바꿈 이름 폴더 있음 · c2 는 삭제 · c4 는 d0 삭제" || bad "전제 실패: ⓗ 배치"
out7="$(swp "$T/scan-h" '' "$R2")"
has   "$out7" "껍데기 2곳(전체 2곳): c2 c4" "ⓗ 줄바꿈 이름 폴더 삭제(c2) · d0 삭제(c4) → 껍데기 2 (옛 판은 c2 를 «판정 불가» 로 보류)"
has   "$out7" " c2"                      "  └ 껍데기 줄에 이름(c2 — 제어문자 이름이어도 누락 0)"
hasnt "$out7" "worktrees/c1"             "ⓗ 이름이 다 있는 sparse(c1) → 껍데기 0 (오탐 0)"
hasnt "$out7" "worktrees/c3"             "ⓗ 제어문자 이름을 «안 받는» sparse(c3) → 정상 판정(껍데기 0)"
hasnt "$out7" "판정 불가"                 "ⓗ 제어문자 이름 때문에 «판정 불가» 로 보류하지 않는다(r5 — 이름을 안 읽는다)"
[ -d "$R2/.worktrees/c1/d0" ] && [ -d "$R2/.worktrees/c3/d0" ] && ok "  └ 경보는 읽기만 — 워크트리 손 0" || bad "경보가 워크트리를 건드림(r5 ⓗ)"
[ -z "$(ls "$T/scan-h"/.sparse-* 2>/dev/null)" ] && ok "  └ sparse 임시 파일 남김 0" || bad "sparse 임시 파일이 남음(r5 ⓗ)"

echo "== ⓦ 결정 5/r8 가짜 git 전수 실패 — 판정 불가 1줄 · u=N · 껍데기 0 · HIL 0"
mkdir -p "$T/fakegit"; printf '#!/bin/bash\nexit 128\n' > "$T/fakegit/git"; chmod +x "$T/fakegit/git"
R7="$T/repo7"; mkdir -p "$R7/.worktrees"; git -C "$R7" init -q -b main
# swpf <계획 디렉터리> [스캔루트] — PATH 앞에 «모든 하위 명령 rc128» 가짜 git 을 둔다
swpf() { mkdir -p "$1"; ( cd "${2:-$T}" && env -i HOME="$HOME" PATH="$T/fakegit:$PATH" FT_WT_CLEAN_DIR="$1" ${2:+FT_WT_SCAN_ROOT="$2"} FT_WT_SHELL_SCAN_SEC=0 \
  FT_WT_ORPHANS_TSV="$T/state/orphans.tsv" FT_WT_SWEEP_LOG="$T/state/wt-sweep.log" FT_WT_ORPHANS_SCAN_SEC=999999 \
  "${WT_TEST_BASH:-bash}" "$T/bin/ft-wt-sweep.sh" 2>&1 ); }
SITES="$(( $(grep -c 'git7 "' "$T/bin/ft-wt-sweep.sh") + $(grep -cE '^(sgit\(\)|[^#]*cap "\$SHELL_GIT_SEC")' "$T/bin/ft-wt-sweep.sh") ))"
[ "$SITES" -eq 13 ] && ok "  └ git 호출 자리 13개(git7 10 + r844 sgit/cap 3) — 새 자리가 생기면 이 시험이 FAIL" || bad "git 호출 자리 수 변화($SITES ≠ 13) — 새 자리를 시험이 모른다"
for st in init config worktree-list sparse-list ls-files ls-tree orphan-list; do
  grep -q "$st" "$T/bin/ft-wt-sweep.sh" && ok "  └ 단계 이름 $st 가 도구에 있다" || bad "단계 이름 $st 없음"
done
outw1="$(swpf "$T/scan-w1")"
has   "$outw1" ":init"                    "ⓦ 루트 미지정 · 전 명령 실패 → «:init» 판정 불가 1줄(|| pwd 폴백 0)"
has   "$outw1" "u=1"                      "  └ 요약 u=1"
hasnt "$outw1" "반쯤 지워진"               "  └ 껍데기 0(조용한 0 이 아니라 판정 불가로 남는다)"
hasnt "$outw1" "[HIL]"                    "  └ 오빠 HIL 0"
[ -z "$(ls -d "$R7"/.worktrees/*.deleting-* 2>/dev/null)" ] && ok "  └ 삭제·이름 바꿈 0" || bad "전수 실패 실행이 워크트리를 지움"
outw2="$(swpf "$T/scan-w2" "$R7")"
has   "$outw2" ":init"                    "ⓦ 루트 지정 · 전 명령 실패 → «:init» 1줄"
has   "$outw2" ":worktree-list"           "  └ «:worktree-list» 1줄(shell_scan 의 공용 목록 조회)"
has   "$outw2" ":orphan-list"             "  └ «:orphan-list» 1줄(등록 없는 폴더 검사)"
has   "$outw2" "u=3"                      "  └ 요약 u=3(자리 3곳이 모두 셈에 들어간다)"
hasnt "$outw2" "[HIL]"                    "  └ 오빠 HIL 0"
[ -d "$R7/.worktrees" ] && ok "  └ 경보는 읽기만 — 리포 손 0(ⓦ)" || bad "전수 실패 실행이 리포를 건드림"

echo "== 결과"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAIL $fail"; exit 1
