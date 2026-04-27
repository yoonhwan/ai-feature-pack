#!/usr/bin/env bash
# baton session-end hook
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

_update_frontmatter_field() {
  local file="$1" field="$2" value="$3"
  if grep -q "^${field}:" "$file"; then
    local tmp
    tmp="$(mktemp)"
    sed "s|^${field}:.*|${field}: ${value}|" "$file" > "$tmp"
    mv "$tmp" "$file"
  fi
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
current_md=""
current_md="$(_find_current_md 2>/dev/null)" || exit 0

status="$(_read_frontmatter_field "$current_md" "status")"
phase_id="$(_read_frontmatter_field "$current_md" "phase_id")"

# active 페이즈가 있을 때만 처리
[[ "$status" != "active" ]] && exit 0

# status → paused 자동 전환
iso_ts="$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date -u '+%Y-%m-%dT%H:%M:%SZ')"

if command -v baton_set_current_status &>/dev/null; then
  baton_set_current_status "paused" "$current_md"
else
  _update_frontmatter_field "$current_md" "status" "paused"
fi
_update_frontmatter_field "$current_md" "last_updated" "$iso_ts"

# 사용자 안내 출력
echo "[baton SessionEnd] 세션이 종료됩니다."
echo "  Phase: ${phase_id:-?} → paused 로 저장됨"
echo "  다음 세션 시작 시 .baton/handoff/NEXT.md 를 먼저 확인하세요."
echo "  이어서 작업하려면: \"이어서\" / \"continue\" / \"go\""

exit 0
