#!/usr/bin/env bash
# baton pre-compact hook (v1.2.3+)
# 안내 출력만. /baton:save 호출 권장.
set -euo pipefail
[[ -n "${BATON_SKIP_HOOKS:-}" ]] && exit 0
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

echo "[baton PreCompact] 컨텍스트 압축 직전입니다."
echo "  컨텍스트가 압축되기 전에 핸드오프를 정리하려면:"
echo "    /baton:save  ← 헤드리스 에이전트가 sidecar(.events.jsonl)를 JOURNAL/CURRENT/NEXT로 정리"
echo "  (수동 편집 비권장 — race 위험)"

exit 0
