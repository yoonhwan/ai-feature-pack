#!/usr/bin/env bash
# ft-nano-freshness.sh <nano-branch|worktree-path> [--root <branch>]
#   오래된 나노 워커·워크트리·브랜치를 «루트부터» 확인한다 (읽기 전용 · 오빠 ORDERS 102·103 · 2026-10-02).
#   정본: references/SEATBELT.md §6-3 단일 세트·나노 생애 ①~⑤ (BYZ 어댑터: docs/rules/single_set_testing.md).
#   exit 0 = FRESH(루트 포함) · 1 = STALE(루트 뒤처짐 · 겹침 0) · 2 = STALE-OVERLAP(루트가 같은 파일을 바꿈 · 재대조)
#        3 = 미랜딩 0(이미 다 들어감 → 닫기만) · 4 = usage/입력 오류
set -uo pipefail

# 루트 = $FT_ROOT_BRANCH · 없으면 메인 워크트리(목록 첫 줄)가 체크아웃한 브랜치
ROOT_BRANCH="${FT_ROOT_BRANCH:-$(git worktree list --porcelain | awk '/^branch /{sub("refs/heads/","",$2); print $2; exit}')}"
TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT_BRANCH="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,6p' "$0"; exit 4 ;;
    *) TARGET="$1"; shift ;;
  esac
done
[ -n "$TARGET" ] || { sed -n '2,6p' "$0"; exit 4; }

WT=""
if [ -d "$TARGET" ]; then
  WT="$(cd "$TARGET" && pwd)"
  BR="$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null)" || { echo "ERROR 워크트리 아님: $TARGET"; exit 4; }
else
  BR="$TARGET"
  WT="$(git worktree list --porcelain | awk -v b="refs/heads/$BR" '/^worktree /{w=$2} $0=="branch " b {print w}')"
fi
git rev-parse --verify -q "$BR" >/dev/null || { echo "ERROR 브랜치 없음: $BR"; exit 4; }
git rev-parse --verify -q "$ROOT_BRANCH" >/dev/null || { echo "ERROR 루트 없음: $ROOT_BRANCH"; exit 4; }

ROOT_HEAD="$(git rev-parse --short "$ROOT_BRANCH")"
BASE="$(git merge-base "$BR" "$ROOT_BRANCH")"
BASE_S="$(git rev-parse --short "$BASE")"
BASE_DATE="$(git log -1 --format='%ci' "$BASE" | cut -c1-16)"
BEHIND="$(git rev-list --count "$BASE..$ROOT_BRANCH")"
UNLANDED="$(git cherry "$ROOT_BRANCH" "$BR" 2>/dev/null | grep -c '^+')"
LAST="$(git log -1 --format='%ci' "$BR" | cut -c1-16)"

echo "== 나노 신선도 — 루트부터 확인"
echo "branch    $BR"
echo "worktree  ${WT:-(없음)}"
[ -n "$WT" ] && [ -f "$WT/.worktree-info.json" ] && echo "info      $(tr -d '\n' < "$WT/.worktree-info.json" | cut -c1-200)"
echo "root      $ROOT_BRANCH @ $ROOT_HEAD"
echo "base      $BASE_S ($BASE_DATE) · 루트가 그 뒤로 $BEHIND 커밋 앞섬"
echo "branch    마지막 커밋 $LAST · 루트에 없는 패치 $UNLANDED"

DIRTY=0
if [ -n "$WT" ]; then
  DIRTY="$(git -C "$WT" status --porcelain -- . ':(exclude).serena/project.yml' ':(exclude).worktree-info.json' 2>/dev/null | grep -c .)"
  echo "dirty     $DIRTY (.serena/project.yml·.worktree-info.json 제외)"
fi

if [ "$UNLANDED" -eq 0 ]; then
  echo "VERDICT   LANDED — 브랜치 변경이 전부 루트에 있다 → 생애 ⑤ 닫기만(ft-nano-close)"
  exit 3
fi
if [ "$BEHIND" -eq 0 ]; then
  echo "VERDICT   FRESH — 루트를 포함한다 → 생애 ③ 시험(이 워크트리 세트) → ④ 이슈 확인 → ⑤ squash 랜딩"
  exit 0
fi

OVERLAP="$(comm -12 <(git diff --name-only "$BASE" "$BR" | sort -u) <(git diff --name-only "$BASE" "$ROOT_BRANCH" | sort -u))"
N_OV="$(printf '%s' "$OVERLAP" | grep -c .)"
echo "overlap   브랜치와 루트가 base 이후 둘 다 바꾼 파일 $N_OV"
printf '%s\n' "$OVERLAP" | grep . | head -15 | sed 's/^/  · /'

echo "다음      ① 루트 병합: git -C ${WT:-<wt>} merge --no-edit $ROOT_BRANCH  (병합 중 루트가 또 움직이면 다시)"
echo "          ② merge-base == $ROOT_BRANCH HEAD · 충돌 0 확인 → ③ 이 워크트리 세트로 시험 → ④ 이슈 확인 → ⑤ squash 랜딩"
if [ "$N_OV" -gt 0 ]; then
  echo "VERDICT   STALE-OVERLAP — 루트가 같은 파일을 바꿨다 → 카드·변경 재대조 후 병합 (옛 결과로 판정 금지)"
  exit 2
fi
echo "VERDICT   STALE — 루트 뒤처짐 · 겹침 0 → 병합 후 시험"
exit 1
