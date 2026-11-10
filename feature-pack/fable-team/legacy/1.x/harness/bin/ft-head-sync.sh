#!/usr/bin/env bash
# ft-head-sync.sh [--table | --apply [--all --confirm <N>]] [--base <ref=origin/main>] [--repo <dir>]   (R230 · 판정 1860·1862 · R749 · R882)
#   열린 브랜치(워크트리가 있는 것)를 새 main 위로 최신화하는 도구. 기본(=--table) = 전수 표만(읽기 전용). --apply 일 때만 merge.
#   · ★R882: --apply(--all 없음) = cwd 워크트리 1곳만 git 호출(남의 워크트리 스캔 0) · 전수 표 = --table(인자 없음과 같음 · --apply 와 같이 못 씀)
#     커널 flock(죽으면 커널이 풂) · r3: 쓰기 키 = 그 워크트리 git 폴더 `ft-head-sync.flock` 하나(1곳 = 실행 내내 · 전수 = 워크트리마다 잡고-쓰고-풂 · 남이 쥐면 «건너뜀») · 순회 키 = 공용 git 폴더 `ft-head-sync-scan.flock`(표·전수끼리 직렬) — 잡혀 있으면 «이미 실행 중 pid N · 시작 HH:MM» rc 0
#   · 대상 = `git worktree list` 의 브랜치 워크트리 중 main·배포·문서 줄기(제외 목록 ft-head-skip.txt · FT_HEAD_SYNC_SKIP 환경변수가 있으면 그 값) 제외
#   · 줄마다: contains_main(is-ancestor base HEAD) · 미랜딩 패치(git cherry) · ft-nano-freshness 분류 · 미커밋 수 · 진행 중 연산
#   · ★R749: --apply 의 쓰기 대상 = «부른 자리(cwd)의 워크트리 1개» 뿐이다. 그 워크트리가 대상 목록(제외 목록 밖 브랜치 워크트리)에 없으면 REJECT rc 2 · 쓰기 0.
#     전 순회는 `--apply --all --confirm <N>` 만 — N 은 표 모드가 세는 «최신화 필요» 수와 같아야 한다(다르거나 없으면 REJECT rc 2 · 쓰기 0). 다른 워크트리를 이름으로 고르는 인자 0.
#   · --apply: 미커밋 0 ∧ 진행 중 연산 0 이면 그 워크트리에서 `git merge --no-edit <base 40hex>` (r5: 충돌은 merge 전 merge-tree 로 판정 → merge 안 함 «충돌·사람» · merge 실패 = abort 0 · 상태 그대로 «오류·사람» rc1 · 도구 안 abort 0 · r3 «최신화함» = 병합 뒤 HEAD ⊇ base ∧ 미커밋 0 일 때만 · 아니면 ERROR rc1) · 미커밋>0 = «보류(미커밋 N)» · 진행 중 연산 = «보류(진행 중 연산)» · ★rebase·reset·force push·원격 push 0★ (원격 push 는 각 팀 몫)
#   · 비파괴 증거: 병합 안 한 워크트리는 전후 HEAD·staged diff·상태·미커밋 파일 내용 해시가 같아야 한다(다르면 rc 1)
#   base sha 는 실행 시작에 한 번 풀어 40hex 로 고정한다(표 머리에 기록). exit 0 = 정상 · 1 = 비파괴 위반·오류 · 2 = usage/REJECT
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/ft-merge-lib.sh"
APPLY=0; ALL=0; TABLE=0; CONFIRM=""; BASE="origin/main"; REPO=""
usage() { echo "usage: $0 [--table | --apply [--all --confirm <N>]] [--base <ref=origin/main>] [--repo <dir>]" >&2; exit 2; }
while [ $# -gt 0 ]; do case "$1" in
  --apply) APPLY=1; shift;;
  --table) TABLE=1; shift;;
  --all) ALL=1; shift;;
  --confirm) [ $# -ge 2 ] || usage; CONFIRM="$2"; shift 2;;
  --base) [ $# -ge 2 ] || usage; BASE="$2"; shift 2;;
  --repo) [ $# -ge 2 ] || usage; REPO="$2"; shift 2;;
  *) usage;; esac; done
if [ "$APPLY" -eq 0 ]; then { [ "$ALL" -eq 0 ] && [ -z "$CONFIRM" ]; } || usage; else [ "$TABLE" -eq 0 ] || usage; fi
ONE=0; [ "$APPLY" -eq 1 ] && [ "$ALL" -eq 0 ] && ONE=1
[ -n "$REPO" ] || REPO="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR repo 를 찾을 수 없음"; exit 1; }
SKIP_RE="${FT_HEAD_SYNC_SKIP:-}"   # 환경변수가 우선 · 없으면 같은 폴더 ft-head-skip.txt(R249 · 한 줄 = 정규식 1개) — 못 읽거나 0줄이면 ERROR
if [ -z "$SKIP_RE" ]; then
  SKIP_PATS="$(grep -vE '^[[:space:]]*(#|$)' "$HERE/ft-head-skip.txt" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | paste -sd'|' -)"
  [ -n "$SKIP_PATS" ] || { echo "ERROR 제외 목록 $HERE/ft-head-skip.txt 를 읽을 수 없거나 정규식 줄이 없음"; exit 1; }
  SKIP_RE="^($SKIP_PATS)\$"
fi
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT; trap 'exit 130' INT TERM
flock_nb() {  # flock_nb <fd> <경로> — 커널 잠금(같은 열린 파일 설명이라 python 이 끝나도 셸 fd 가 쥠 · 셸이 죽으면 커널이 풂 = 고아 0) · 0 잡음 · 3 남이 쥠
  local rc=0; python3 -I -c 'import fcntl, sys
try: fcntl.flock(int(sys.argv[1]), fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError: sys.exit(3)' "$1" || rc=$?
  [ "$rc" -eq 0 ] && { printf 'pid %s · 시작 %s\n' "$$" "$(date +%H:%M)" 1<>"$2"; return 0; }   # 안내 글자만 · 자르기 0(1<>) — 읽는 쪽이 빈 첫 줄을 보는 틈 0
  [ "$rc" -eq 3 ] || { echo "ERROR 잠금 $2 를 잡지 못함(python3 flock rc=$rc)"; exit 1; }; return 3; }
# lock_take <경로> = 실행 잠금 fd 9(1곳 = 그 워크트리 쓰기 키 · 전수 = 순회 키) · 남이 쥐면 1줄 rc0
lock_take() { exec 9>>"$1" || { echo "ERROR 잠금 파일 $1 를 열지 못함"; exit 1; }; flock_nb 9 "$1" || { echo "이미 실행 중 $(head -1 "$1" 2>/dev/null) — 겹쳐 돌지 않고 끝낸다($1)"; exit 0; }; }
# wt_lock <워크트리> = R882 r3 전수 쓰기 잠금 fd 8 · 1곳 --apply 와 같은 키(그 워크트리 git 폴더) · 1 = 남이 씀(fd 닫음)
wt_lock() { local p; p="$(gitdir "$1")/ft-head-sync.flock"; exec 8>>"$p" || { echo "ERROR 잠금 파일 $p 를 열지 못함"; exit 1; }; flock_nb 8 "$p" && return 0; exec 8>&-; return 1; }
gitdir() { git -C "$1" rev-parse --path-format=absolute --git-dir; }
pending_op() {  # 진행 중 연산 이름(없으면 빈 값)
  local gd f; gd="$(gitdir "$1")" || { echo "git-dir 오류"; return; }
  for f in MERGE_HEAD rebase-merge rebase-apply CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG; do [ -e "$gd/$f" ] && { echo "$f"; return; }; done
}
dirty_count() { git -C "$1" status --porcelain=v2 -z --untracked-files=all | tr -cd '\0' | wc -c | tr -d ' '; }
snap() {
  local wt="$1" f
  { git -C "$wt" rev-parse HEAD; git -C "$wt" diff --cached --binary | shasum
    git -C "$wt" status --porcelain=v2 -z --untracked-files=all | shasum
    git -C "$wt" ls-files -m -o --exclude-standard -z | while IFS= read -r -d '' f; do printf '%s ' "$f"; shasum < "$wt/$f" 2>/dev/null || echo missing; done | shasum; } | shasum | cut -c1-16
}

# ── 0단계: 대상 고르기 — 워크트리 목록(메타)만 읽는다. --apply 1곳이면 cwd 워크트리 1줄만 남긴다(R882 · 남의 워크트리 git 0)
CWDW="$(git rev-parse --show-toplevel 2>/dev/null)"; [ -n "$CWDW" ] && CWDW="$(cd -- "$CWDW" 2>/dev/null && pwd -P)"
git -C "$REPO" worktree list --porcelain | awk '/^worktree /{w=substr($0,10)} /^branch refs\/heads\//{print w "\t" substr($0,19)}' > "$TMP/all"
: > "$TMP/targets"
while IFS=$'\t' read -r wt br; do
  [ -d "$wt" ] || continue
  printf '%s' "$br" | grep -Eq "$SKIP_RE" && continue
  [ "$ONE" -eq 1 ] && [ "$(cd -- "$wt" && pwd -P)" != "${CWDW:-/nonexistent}" ] && continue   # R882 cwd 한정
  printf '%s\t%s\n' "$wt" "$br" >> "$TMP/targets"
done < "$TMP/all"
[ "$ONE" -eq 1 ] && ! grep -q . "$TMP/targets" && { echo "REJECT 이 자리는 최신화 대상 워크트리가 아니다(${CWDW:-cwd 를 못 읽음}) — --apply 는 부른 자리의 워크트리 1개만 최신화한다 · 전 순회는 --apply --all --confirm <N>" >&2; exit 2; }
if [ "$ONE" -eq 1 ]; then LKP="$(git -C "$CWDW" rev-parse --path-format=absolute --git-dir)/ft-head-sync.flock"; else LKP="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)/ft-head-sync-scan.flock"; fi   # 전수 키 = 순회끼리 직렬만(쓰기 보호 아님 · r3)
lock_take "$LKP"
case "$BASE" in origin/*) fm_fetch "$REPO" origin "${BASE#origin/}" || { echo "ERROR fetch $BASE 실패(7 s + 재시도 1)"; exit 1; };; esac
BSHA="$(git -C "$REPO" rev-parse --verify -q "$BASE^{commit}")" || { echo "ERROR base $BASE 확인 실패"; exit 1; }

# ── 1단계: 대상 «읽기만» — 표 모드 출력과 --confirm 대조값이 여기서 나온다(쓰기 0)
: > "$TMP/scan"; : > "$TMP/before"
while IFS=$'\t' read -r wt br; do
  printf '%s\t%s\n' "$wt" "$(snap "$wt")" >> "$TMP/before"
  contains=no; git -C "$wt" merge-base --is-ancestor "$BSHA" HEAD 2>/dev/null && contains=yes
  unl="$(git -C "$wt" cherry "$BSHA" HEAD 2>/dev/null | grep -c '^+')"
  ( cd "$wt" && bash "$HERE/ft-nano-freshness.sh" --root "$BSHA" "$wt" >/dev/null 2>&1 </dev/null ); frc=$?   # freshness 는 cwd 저장소를 본다 — 그 워크트리에서 실행
  case "$frc" in 0) cls=FRESH;; 1) cls=STALE;; 2) cls=STALE-OVERLAP;; 3) cls=LANDED;; *) cls=ERR;; esac
  op="$(pending_op "$wt")"; op="${op:--}"   # 빈 칸은 탭 연속이 되어 read 가 접는다 — 표식 "-"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$wt" "$br" "$cls" "$contains" "$unl" "$(dirty_count "$wt")" "$op" "$(cd "$wt" && pwd -P)" >> "$TMP/scan"
done < "$TMP/targets"
need="$(awk -F'\t' '$4=="no"' "$TMP/scan" | grep -c .)"

# ── 2단계: 전 순회 게이트(R749) — 통과 전에는 어떤 워크트리도 안 건드린다(1곳 게이트는 0단계)
if [ "$APPLY" -eq 1 ] && [ "$ALL" -eq 1 ]; then
  [ -n "$CONFIRM" ] || { echo "REJECT --all 은 --confirm <대상 수> 가 필요하다 — 지금 «최신화 필요» $need 곳" >&2; exit 2; }
  [ "$CONFIRM" = "$need" ] || { echo "REJECT --confirm $CONFIRM 은 지금 «최신화 필요» $need 곳과 다르다 — 표 모드 숫자를 보고 다시" >&2; exit 2; }
fi

# ── 3단계: 결과 칸 · merge 는 고른 워크트리만 · ★R882 r3: 쓰기는 그 워크트리 잠금을 쥔 채(검사→merge-tree→merge→검증) — 1곳·전수 같은 키★
: > "$TMP/rows"; : > "$TMP/merged"; viol=0
while IFS=$'\t' read -r wt br cls contains unl dirty op real; do
  res=""
  if [ "$contains" = yes ]; then res="최신"
  elif [ "$APPLY" -eq 0 ]; then res="최신화 필요"
  elif [ "$op" != "-" ]; then res="보류(진행 중 연산 $op)"
  elif [ "$dirty" -gt 0 ]; then res="보류(미커밋 $dirty)"
  elif [ "$ONE" -eq 0 ] && ! wt_lock "$wt"; then res="건너뜀 (다른 실행 중)"; echo "$wt" >> "$TMP/merged"   # 남이 쓰는 중 — 전후 대조 밖
  else
    mh="$(gitdir "$wt")/MERGE_HEAD"; mrc=0; trc=0; if [ -e "$mh" ]; then res="보류(진행 중 연산 MERGE_HEAD)"   # r5: 충돌은 merge «전» merge-tree 로 판정 · 도구 안 merge --abort 0
    else git -C "$wt" merge-tree --write-tree HEAD "$BSHA" >/dev/null 2>"$TMP/mt.err" || trc=$?   # 0 깨끗 · 1 충돌 · 그 밖 오류(작업 트리·index 무변경)
      if [ "$trc" -eq 1 ]; then res="충돌·사람"   # merge 안 함 — 상태 무변경
      elif [ "$trc" -ne 0 ]; then res="오류(merge-tree rc=$trc)"; viol=1; echo "ERROR merge-tree rc=$trc: $wt — $(head -c 120 "$TMP/mt.err" | tr '\n' ' ')"
      else LC_ALL=C GIT_MERGE_AUTOEDIT=no git -C "$wt" merge --no-edit "$BSHA" >"$TMP/merge.out" 2>&1 </dev/null || mrc=$?; echo "$wt" >> "$TMP/merged"
        if [ "$mrc" -eq 0 ] && git -C "$wt" merge-base --is-ancestor "$BSHA" HEAD && [ "$(dirty_count "$wt")" = 0 ]; then res="최신화함"
        elif [ "$mrc" -eq 0 ]; then res="오류(병합 뒤 검증 실패)"; viol=1; echo "ERROR 병합 뒤 검증 실패(HEAD 가 base 를 안 품거나 미커밋 남음): $wt"
        else res="오류·사람(merge rc=$mrc · MERGE_HEAD $([ -e "$mh" ] && echo "$mh 남음" || echo 없음))"; viol=1; echo "ERROR merge 실패(rc=$mrc · abort 0 · 상태 그대로 — 사람이 그 자리에서 마무리하거나 git merge --abort): $wt — $(head -c 120 "$TMP/merge.out" | tr '\n' ' ')"; fi; fi; fi
    [ "$ONE" -eq 0 ] && exec 8>&-   # 다음 워크트리로 넘어가기 전 풂
    [ "$res" = "최신화함" ] && [ "$unl" -eq 0 ] && res="최신화함·랜딩됨(닫기 후보)"
    [ "$res" = "충돌·사람" ] && [ "$unl" -eq 0 ] && res="충돌·사람·랜딩됨(닫기 후보)"
  fi
  [ "$contains" = no ] && [ "$unl" -eq 0 ] && [ "$APPLY" -eq 0 ] && res="최신화 필요·랜딩됨(닫기 후보)"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$br" "$(basename "$wt")" "$cls" "$contains" "$unl" "$res" >> "$TMP/rows"
done < "$TMP/scan"
echo "base=$BSHA ($BASE) apply=$APPLY all=$ALL"
{ printf '브랜치\t워크트리\t분류\tcontains_main\t미랜딩\t결과\n'; cat "$TMP/rows"; } | column -t -s $'\t'
n() { cut -f6 "$TMP/rows" | grep -c "^$1"; }
echo "요약: 총 $(grep -c . "$TMP/rows") · 최신 $(n 최신$) · 최신화함 $(n 최신화함) · 충돌·사람 $(n 충돌·사람) · 보류 $(n 보류) · 최신화 필요 $(n '최신화 필요') · 오류 $(n 오류) · 건너뜀 $(n 건너뜀)"
: >> "$TMP/merged"; chk=0
while IFS=$'\t' read -r wt s0; do
  grep -qxF "$wt" "$TMP/merged" && continue
  chk=$((chk+1))
  [ "$(snap "$wt")" = "$s0" ] || { echo "VIOLATION 비파괴 위반(전후 해시 다름): $wt"; viol=1; }
done < "$TMP/before"
[ "$viol" -eq 0 ] && echo "비파괴 증거: 병합 안 한 워크트리 $chk 개 전후 HEAD·staged·상태·미커밋 내용 해시 동일 · 건너뜀 $(n 건너뜀)(다른 실행이 쓰는 중 — 대조 밖)"
exit "$viol"
