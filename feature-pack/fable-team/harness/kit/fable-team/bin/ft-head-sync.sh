#!/usr/bin/env bash
# ft-head-sync.sh [--apply] [--base <ref=origin/main>] [--repo <dir>]   (R230 · 판정 1860·1862)
#   열린 브랜치(워크트리가 있는 것)를 새 main 위로 최신화하는 도구. 기본 = 표만(읽기 전용). --apply 일 때만 merge.
#   · 대상 = `git worktree list` 의 브랜치 워크트리 중 main·배포 브랜치(FT_HEAD_SYNC_SKIP 정규식 · 기본 main|master|release/*|deploy/*) 제외
#   · 줄마다: contains_main(is-ancestor base HEAD) · 미랜딩 패치(git cherry) · ft-nano-freshness 분류 · 미커밋 수 · 진행 중 연산
#   · --apply: contains_main 거짓 전부 → 미커밋 0 ∧ 진행 중 연산 0 이면 그 워크트리에서 `git merge --no-edit <base 40hex>` (충돌이면 이 실행이 시작한 merge 만 abort + «충돌·사람»)
#     미커밋>0 = «보류(미커밋 N)» · 진행 중 연산 = «보류(진행 중 연산)» · ★rebase·reset·force push·원격 push 0★ (원격 push 는 각 팀 몫)
#   · 비파괴 증거: 병합 안 한 워크트리는 전후 HEAD·staged diff·상태·미커밋 파일 내용 해시가 같아야 한다(다르면 rc 1)
#   base sha 는 실행 시작에 한 번 풀어 40hex 로 고정한다(표 머리에 기록). exit 0 = 정상 · 1 = 비파괴 위반·오류 · 2 = usage
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/ft-merge-lib.sh"
APPLY=0; BASE="origin/main"; REPO=""
usage() { echo "usage: $0 [--apply] [--base <ref=origin/main>] [--repo <dir>]" >&2; exit 2; }
while [ $# -gt 0 ]; do case "$1" in
  --apply) APPLY=1; shift;;
  --base) [ $# -ge 2 ] || usage; BASE="$2"; shift 2;;
  --repo) [ $# -ge 2 ] || usage; REPO="$2"; shift 2;;
  *) usage;; esac; done
[ -n "$REPO" ] || REPO="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR repo 를 찾을 수 없음"; exit 1; }
SKIP_RE="${FT_HEAD_SYNC_SKIP:-^(main|master|release/.*|deploy/.*)$}"
case "$BASE" in origin/*) fm_fetch "$REPO" origin "${BASE#origin/}" || { echo "ERROR fetch $BASE 실패(7 s + 재시도 1)"; exit 1; };; esac
BSHA="$(git -C "$REPO" rev-parse --verify -q "$BASE^{commit}")" || { echo "ERROR base $BASE 확인 실패"; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

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

# 대상 수집: "<wt>\t<branch>"
git -C "$REPO" worktree list --porcelain | awk '/^worktree /{w=substr($0,10)} /^branch refs\/heads\//{print w "\t" substr($0,19)}' > "$TMP/targets"
: > "$TMP/rows"; : > "$TMP/before"
while IFS=$'\t' read -r wt br; do
  [ -d "$wt" ] || continue
  printf '%s' "$br" | grep -Eq "$SKIP_RE" && continue
  printf '%s\t%s\n' "$wt" "$(snap "$wt")" >> "$TMP/before"
  contains=no; git -C "$wt" merge-base --is-ancestor "$BSHA" HEAD 2>/dev/null && contains=yes
  unl="$(git -C "$wt" cherry "$BSHA" HEAD 2>/dev/null | grep -c '^+')"
  ( cd "$wt" && bash "$HERE/ft-nano-freshness.sh" --root "$BSHA" "$wt" >/dev/null 2>&1 </dev/null ); frc=$?   # freshness 는 cwd 저장소를 본다 — 그 워크트리에서 실행
  case "$frc" in 0) cls=FRESH;; 1) cls=STALE;; 2) cls=STALE-OVERLAP;; 3) cls=LANDED;; *) cls=ERR;; esac
  dirty="$(dirty_count "$wt")"; op="$(pending_op "$wt")"; res=""
  if [ "$contains" = yes ]; then res="최신"
  elif [ "$APPLY" -eq 0 ]; then res="최신화 필요"
  elif [ -n "$op" ]; then res="보류(진행 중 연산 $op)"
  elif [ "$dirty" -gt 0 ]; then res="보류(미커밋 $dirty)"
  else
    : > "$TMP/started"   # 시작 표식 — merge --abort 는 이 실행이 방금 시작한 merge 에만(진행 중 연산은 위에서 이미 보류)
    if GIT_MERGE_AUTOEDIT=no git -C "$wt" merge --no-edit "$BSHA" >"$TMP/merge.out" 2>&1 </dev/null; then res="최신화함"; echo "$wt" >> "$TMP/merged"
    elif [ -e "$(gitdir "$wt")/MERGE_HEAD" ] && [ -e "$TMP/started" ]; then
      git -C "$wt" merge --abort >/dev/null 2>&1; res="충돌·사람"
    else res="오류(merge 거절: $(head -c 80 "$TMP/merge.out" | tr '\n' ' '))"; fi
    rm -f "$TMP/started"
    [ "$res" = "최신화함" ] && [ "$unl" -eq 0 ] && res="최신화함·랜딩됨(닫기 후보)"
    [ "$res" = "충돌·사람" ] && [ "$unl" -eq 0 ] && res="충돌·사람·랜딩됨(닫기 후보)"
  fi
  [ "$contains" = no ] && [ "$unl" -eq 0 ] && [ "$APPLY" -eq 0 ] && res="최신화 필요·랜딩됨(닫기 후보)"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$br" "$(basename "$wt")" "$cls" "$contains" "$unl" "$res" >> "$TMP/rows"
done < "$TMP/targets"

echo "base=$BSHA ($BASE) apply=$APPLY"
{ printf '브랜치\t워크트리\t분류\tcontains_main\t미랜딩\t결과\n'; cat "$TMP/rows"; } | column -t -s $'\t'
n() { cut -f6 "$TMP/rows" | grep -c "^$1"; }
echo "요약: 총 $(grep -c . "$TMP/rows") · 최신 $(n 최신$) · 최신화함 $(n 최신화함) · 충돌·사람 $(n 충돌·사람) · 보류 $(n 보류) · 최신화 필요 $(n '최신화 필요') · 오류 $(n 오류)"

viol=0; : >> "$TMP/merged"; chk=0
while IFS=$'\t' read -r wt s0; do
  grep -qxF "$wt" "$TMP/merged" && continue
  chk=$((chk+1))
  [ "$(snap "$wt")" = "$s0" ] || { echo "VIOLATION 비파괴 위반(전후 해시 다름): $wt"; viol=1; }
done < "$TMP/before"
[ "$viol" -eq 0 ] && echo "비파괴 증거: 병합 안 한 워크트리 $chk 개 전후 HEAD·staged·상태·미커밋 내용 해시 동일"
exit "$viol"
