#!/usr/bin/env bash
# ft-branch-archive.sh <브랜치|폴더> [--repo <리포>] — 끝난 가지를 refs/heads → refs/archive 로 «옮긴다»(r444 · 판정 2354 안 1 · 삭제 0).
#   판정 = ft-finished-check.sh 하나 — FINISHED 일 때만. EMPTY·ACTIVE·ORPHAN·판정 불가 = 이동 0(SKIP 1줄).
#   ①`git update-ref refs/archive/<이름> <sha> ""`(새로 만들 때만 · 있던 보관 ref 덮기 0) ②보관 ref 가 그 sha 인지 다시 읽음 ③그 뒤에만 가지 목록에서 뺀다:
#     `git branch -d`(합쳐진 가지) → 거절이면(squash 착지) `git update-ref -d refs/heads/<가지> <sha>`(그 sha 일 때만 · 커밋은 보관 ref 가 쥔다). `git branch -D` 0.
#   ★보관이 실패하면(update-ref rc≠0 · HEAD 없음 · 이름 불가) 가지·폴더를 건드리지 않는다 — SKIP + 로그★. 폴더 삭제는 이 도구 몫이 아니다(정리 계획 = ft-wt-sweep).
#   가지를 폴더가 쓰는 중이면 보관 ref 만 만들고 가지는 둔다(다음 sweep 이 폴더 정리 뒤 다시 본다). 분리 HEAD 폴더 = refs/archive/detached/<폴더 이름>.
#   이름의 공백은 `_` 로. 로그 = <FT_ROOT|리포>/.fable-team/state/branch-archive.log · 되살림 `git branch <가지> refs/archive/<이름>`.
#   rc 0 = 보관함(또는 이미 같은 sha 로 보관됨) · 1 = SKIP · 2 = 사용법·리포 오류. env: FT_FINISHED_CHECK(판정기 경로 · 시험용)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
T="${1:-}"; shift 2>/dev/null; R=""
while [ $# -gt 0 ]; do case "$1" in --repo) R="${2:-}"; shift 2;; *) echo "usage: $0 <브랜치|폴더> [--repo <리포>]" >&2; exit 2;; esac; done
[ -n "$T" ] || { echo "usage: $0 <브랜치|폴더> [--repo <리포>]" >&2; exit 2; }
if [ -z "$R" ]; then
  if [ -d "$T" ]; then R="$(git -C "$T" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
  else R="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"; fi
fi
[ -n "$R" ] && [ -d "$R" ] || { echo "ERROR 리포를 못 찾음(--repo 필요): ${R:-<없음>}" >&2; exit 2; }
LOG="${FT_ROOT:-$R}/.fable-team/state/branch-archive.log"; mkdir -p "$(dirname "$LOG")" 2>/dev/null
say() { echo "$1"; printf '%s %s\n' "$(date '+%F %T')" "$1" >> "$LOG" 2>/dev/null; }
skip() { say "SKIP $1"; exit 1; }
CHK="${FT_FINISHED_CHECK:-$HERE/ft-finished-check.sh}"
out="$(bash "$CHK" "$T" --repo "$R" 2>&1)"; v="${out%%$'\n'*}"; v="${v%% *}"
[ "$v" = FINISHED ] || skip "$T ${v:-판정 없음} — 이동 0 ($(printf '%s' "$out" | grep -E '^E[0-3] no' | head -1))"
BR=""; DIR=""
if [ -d "$T" ]; then DIR="$(cd "$T" && pwd -P)"; BR="$(git -C "$DIR" symbolic-ref -q --short HEAD 2>/dev/null)"; else BR="${T#refs/heads/}"; fi
if [ -n "$BR" ]; then SHA="$(git -C "$R" rev-parse -q --verify "refs/heads/$BR^{commit}")" || skip "$T 가지 HEAD 없음 — 이동 0"; NAME="$BR"
else SHA="$(git -C "$DIR" rev-parse -q --verify "HEAD^{commit}")" || skip "$T 폴더 HEAD 없음 — 이동 0"; NAME="detached/$(basename "$DIR")"; fi
NAME="${NAME// /_}"; REF="refs/archive/$NAME"
git check-ref-format "$REF" || skip "$T 보관 ref 이름 불가: $REF — 이동 0"
cur="$(git -C "$R" rev-parse -q --verify "$REF" 2>/dev/null)"
if [ "$cur" != "$SHA" ]; then
  git -C "$R" update-ref "$REF" "$SHA" "" 2>/dev/null || skip "$T update-ref-failed $REF ← $SHA (있던 보관 ref ${cur:-없음}) — 가지·폴더 그대로"
  [ "$(git -C "$R" rev-parse -q --verify "$REF")" = "$SHA" ] || skip "$T update-ref-failed $REF 다시 읽기 불일치 — 가지·폴더 그대로"
fi
[ -n "$BR" ] || { say "ARCHIVED $NAME $SHA (분리 HEAD 폴더 · 폴더는 그대로) restore: git branch <이름> $REF"; exit 0; }
used="$(git -C "$R" worktree list --porcelain | awk -v b="branch refs/heads/$BR" '/^worktree /{p=substr($0,10)} $0==b{print p; exit}')"
[ -z "$used" ] || { say "ARCHIVED $NAME $SHA (가지 유지 — 폴더 $used 가 쓰는 중) restore: git branch $BR $REF"; exit 0; }
git -C "$R" branch -d "$BR" >/dev/null 2>&1 || git -C "$R" update-ref -d "refs/heads/$BR" "$SHA" \
  || skip "$T 보관 ref 는 만들었으나 가지 목록에서 못 뺌 — $REF 와 가지 둘 다 남음"
say "ARCHIVED $NAME $SHA restore: git branch $BR $REF"
