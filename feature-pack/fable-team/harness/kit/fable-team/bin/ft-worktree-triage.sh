#!/usr/bin/env bash
# ft-worktree-triage.sh — 워크트리를 «완성 / 옮기기 / 인터뷰» 로 자동 분류한다. 읽기 전용.
#
# 왜: 실측 119개 중 미커밋 102 · 미머지 112 · ★회귀위험(미머지 ∧ 1000+ 뒤짐) 87★.
#     전부 사람에게 올리면 병목이 사람에게 온다. ★기계가 가를 수 있는 것을 먼저 가른다.★
#
# 사다리(오빠 지시 2026-09-22): ①완성 → ②옮기기(rebase/cherry-pick) → ③드랍(컨텍스트 발행+박제)
#
# ★분류 기준 — DA R1 ⑥ 실측 반영★
#   「충돌 0」이 아니라 ★「겹치는 파일 0」★ 이다.
#   표본 25개가 전부 충돌 0 인데 23개가 «같은 파일을 양쪽이» 고쳤다.
#   텍스트가 안 겹친다고 의미가 맞는 게 아니다.
#
# 출력 (TSV): 상태 · 워크트리 · 브랜치 · 뒤짐 · 앞섬 · 미커밋 · 겹친파일수
#   READY_MERGE  뒤짐 0 · 앞섬>0            → 그냥 머지
#   AUTO_MOVE    겹친 파일 0               → 기계가 옮겨도 된다
#   INTERVIEW    겹친 파일 >0              → 사람에게: 지금도 필요한가
#   DIRTY_ONLY   앞섬 0 · 미커밋>0         → 커밋하거나 버릴지 결정
#   IDLE         앞섬 0 · 미커밋 0         → 그냥 정리 대상
#   NO_OWNER     .worktree-info.json 없음  → 주인 없음(별도 목록, 숨기지 않는다)
#
# ★이 명령은 아무것도 바꾸지 않는다★ — 읽기만 한다. 집행은 사람 판정 뒤에.

set -uo pipefail

BASE_REF="${1:-origin/main}"
ROOT="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
[ -n "$ROOT" ] || { echo "REJECT git 저장소가 아니다" >&2; exit 2; }
cd "$ROOT" || exit 2

git rev-parse --verify --quiet "$BASE_REF" >/dev/null || {
  echo "REJECT 기준 ref 없음: $BASE_REF" >&2; exit 2; }

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 상태 워크트리 브랜치 뒤짐 앞섬 미커밋 겹친파일

git worktree list --porcelain \
  | awk '/^worktree /{w=$2} /^branch /{print w"\t"$2}' \
  | while IFS=$'\t' read -r wt br; do
      b="${br#refs/heads/}"
      [ -d "$wt" ] || continue

      behind="$(git rev-list --count "$b".."$BASE_REF" 2>/dev/null || echo -1)"
      ahead="$(git rev-list --count "$BASE_REF".."$b" 2>/dev/null || echo -1)"
      dirty="$(git -C "$wt" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"

      # ★겹친 파일 = 양쪽이 «건드린» 파일의 교집합★ (merge-tree 충돌 수가 아니다)
      mb="$(git merge-base "$b" "$BASE_REF" 2>/dev/null)"
      overlap=-1
      if [ -n "$mb" ] && [ "$ahead" -gt 0 ] 2>/dev/null; then
        overlap="$(comm -12 \
          <(git diff --name-only "$mb".."$b" 2>/dev/null | sort -u) \
          <(git diff --name-only "$mb".."$BASE_REF" 2>/dev/null | sort -u) \
          | wc -l | tr -d ' ')"
      fi

      if [ ! -f "$wt/.worktree-info.json" ]; then st=NO_OWNER
      elif [ "$ahead" -eq 0 ] 2>/dev/null && [ "$dirty" -eq 0 ]; then st=IDLE
      elif [ "$ahead" -eq 0 ] 2>/dev/null; then st=DIRTY_ONLY
      elif [ "$behind" -eq 0 ] 2>/dev/null; then st=READY_MERGE
      elif [ "$overlap" -eq 0 ] 2>/dev/null; then st=AUTO_MOVE
      else st=INTERVIEW
      fi

      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$st" "$(basename "$wt")" "$b" "$behind" "$ahead" "$dirty" "$overlap"
    done
