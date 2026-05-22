#!/usr/bin/env bash
# baton session-end hook (v1.2.5+)
# - status 무관하게 RESUME_MSG.md 갱신 (bash-only, race 안전 — Claude는 RESUME_MSG.md 안 읽음)
# - events_count ≥ 1 시 stale 마킹 (commit 라인에 인라인)
# - CURRENT.md frontmatter mutation은 여전히 안 함 (v1.2.3+ race 정책)

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

handoff_dir="$(dirname "$current_md")"
phase_id="$(_read_frontmatter_field "$current_md" "phase")"

events_file="$handoff_dir/.events.jsonl"
event_count=0
[[ -f "$events_file" ]] && event_count=$(wc -l < "$events_file" 2>/dev/null | tr -d ' ' || echo 0)

# v1.2.5+ — bash-only RESUME_MSG.md 갱신 (status 무관)
baton_resume_msg_build "$handoff_dir" >/dev/null 2>&1 || true

# events ≥ 1 이면 stale 마킹 (commit 라인에 인라인 — frontmatter 안 건드림)
if [[ "${event_count:-0}" -gt 0 && -f "$handoff_dir/RESUME_MSG.md" ]]; then
  _tmp=$(mktemp)
  awk -v ev="$event_count" '
    /^commit:/ && !done { print $0 " (stale, events=" ev ")"; done=1; next }
    { print }
  ' "$handoff_dir/RESUME_MSG.md" > "$_tmp" && mv "$_tmp" "$handoff_dir/RESUME_MSG.md"
fi

echo "[baton SessionEnd] 세션 종료. Phase: ${phase_id:-?}"
if [[ "${event_count:-0}" -gt 0 ]]; then
  echo "  ⚠️  미정리 이벤트 ${event_count}개 (sidecar). 다음 세션에서 /baton:save 권장."
  echo "  📋 RESUME_MSG.md에 stale 마킹됨: $handoff_dir/RESUME_MSG.md"
else
  echo "  📋 RESUME_MSG.md 갱신: $handoff_dir/RESUME_MSG.md"
fi
echo "  다음 세션 시작 시 RESUME_MSG.md 내용 복붙 권장."
echo "  이어서 작업: \"이어서\" / \"continue\" / \"go\""

exit 0
