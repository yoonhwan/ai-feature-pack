#!/usr/bin/env bash
# baton pre-compact hook
set -euo pipefail
BATON_HOME="${BATON_HOME:-$HOME/.baton/current}"
[[ -d "$BATON_HOME" ]] || exit 0  # baton 미설치 시 silent skip

# shellcheck source=../../core/lib/core.sh
. "$BATON_HOME/lib/core.sh"

# ---------------------------------------------------------------------------
# 탐색 헬퍼
# ---------------------------------------------------------------------------
_find_current_md() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    [[ -f "$dir/.baton/handoff/CURRENT.md" ]] && {
      echo "$dir/.baton/handoff/CURRENT.md"
      return 0
    }
    dir="$(dirname "$dir")"
  done
  return 1
}

_read_frontmatter_field() {
  local file="$1" field="$2"
  awk '/^---$/{f=!f; next} f{print}' "$file" \
    | grep "^${field}:" \
    | head -1 \
    | sed "s/^${field}:[[:space:]]*//"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
current_md=""
current_md="$(_find_current_md 2>/dev/null)" || exit 0

status="$(_read_frontmatter_field "$current_md" "status")"

# active 페이즈가 있을 때만 안내 출력
[[ "$status" != "active" ]] && exit 0

echo "[baton PreCompact] 컨텍스트 압축 직전입니다. 압축 전에 다음을 갱신해주세요:"
echo "1. .baton/handoff/JOURNAL.md 의 마지막 Turn 섹션에 ACTIONS/TODO 정리"
echo "2. .baton/handoff/CURRENT.md 의 📌 핵심 결정 / 🔗 핵심 파일 갱신"
echo "3. .baton/handoff/NEXT.md 다음 세션 1페이지 요약"

exit 0
