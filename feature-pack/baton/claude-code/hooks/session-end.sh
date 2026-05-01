#!/usr/bin/env bash
# baton session-end hook (v1.2.3+)
# 안내 출력만. CURRENT.md frontmatter mutation은 제거됨 (race 방지).
# status 전환은 /baton:save 또는 /baton:finish 가 담당.

set -euo pipefail

[[ -n "${BATON_SKIP_HOOKS:-}" ]] && exit 0

BATON_HOME="${BATON_HOME:-$HOME/.baton/current}"
[[ -d "$BATON_HOME" ]] || exit 0

# shellcheck source=../../core/lib/core.sh
. "$BATON_HOME/lib/core.sh"

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

current_md=""
current_md="$(_find_current_md 2>/dev/null)" || exit 0

status="$(_read_frontmatter_field "$current_md" "status")"
phase_id="$(_read_frontmatter_field "$current_md" "phase_id")"

[[ "$status" != "active" ]] && exit 0

# events.jsonl 통계 안내 — 사용자가 /baton:save 호출 권장 시점 인지
handoff_dir="$(dirname "$current_md")"
events_file="$handoff_dir/.events.jsonl"
event_count=0
[[ -f "$events_file" ]] && event_count=$(wc -l < "$events_file" 2>/dev/null | tr -d ' ' || echo 0)

echo "[baton SessionEnd] 세션 종료. Phase: ${phase_id:-?}"
if [[ "${event_count:-0}" -gt 0 ]]; then
  echo "  ⚠️  미정리 이벤트 ${event_count}개 (sidecar). 다음 세션에서 /baton:save 권장."
fi
echo "  다음 세션 시작 시 .baton/handoff/NEXT.md 를 먼저 확인."
echo "  이어서 작업: \"이어서\" / \"continue\" / \"go\""

exit 0
