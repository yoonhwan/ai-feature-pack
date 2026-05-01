#!/usr/bin/env bash
# baton post-tool-use hook (v1.2.3+)
# sidecar 전용 — Claude Edit tool과의 mtime race 방지
# 이전 버전이 JOURNAL.md / CURRENT.md / phase.json 을 매 도구 사용마다 mutate하던
# 로직은 제거됨. 모든 정리는 /baton:save 에서 헤드리스 에이전트가 일괄 처리.

set -euo pipefail

# 헤드리스 spawn 무한 루프 방지
[[ -n "${BATON_SKIP_HOOKS:-}" ]] && exit 0

BATON_HOME="${BATON_HOME:-$HOME/.baton/current}"
[[ -d "$BATON_HOME" ]] || exit 0

# ---------------------------------------------------------------------------
# 하네스 도구 (Skill/Agent/Task) 만 기록
# ---------------------------------------------------------------------------
_HARNESS_TOOL_NAMES=("Skill" "Agent" "Task")

_is_harness_tool() {
  local name="$1"
  for h in "${_HARNESS_TOOL_NAMES[@]}"; do
    [[ "$name" == "$h" ]] && return 0
  done
  return 1
}

_jq_field() {
  local json="$1" path="$2"
  if command -v jq &>/dev/null; then
    echo "$json" | jq -r "$path // empty" 2>/dev/null
  fi
}

_find_handoff_dir() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    [[ -d "$dir/.baton/handoff" ]] && { echo "$dir/.baton/handoff"; return 0; }
    dir="$(dirname "$dir")"
  done
  return 1
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
raw_input=""
if ! IFS= read -t 1 -r raw_input 2>/dev/null; then
  exit 0
fi
[[ -z "$raw_input" ]] && exit 0

command -v jq &>/dev/null || exit 0

tool_name="$(_jq_field "$raw_input" '.tool_name')"
[[ -z "$tool_name" ]] && exit 0

_is_harness_tool "$tool_name" || exit 0

# 하네스 이름 추출
harness_name=""
case "$tool_name" in
  Skill)
    harness_name="$(_jq_field "$raw_input" '.tool_input.skill')"
    ;;
  Agent|Task)
    harness_name="$(_jq_field "$raw_input" '.tool_input.subagent_type')"
    [[ -z "$harness_name" ]] && \
      harness_name="$(_jq_field "$raw_input" '.tool_input.agent_type')"
    ;;
esac
[[ -z "$harness_name" ]] && exit 0

# sidecar에만 append — lib/handoff.sh 통일
handoff_dir=""
handoff_dir="$(_find_handoff_dir 2>/dev/null)" || exit 0

# baton_events_append은 generic. tool 메타까지 포함하려면 inline jq 사용.
# (post-tool은 tool 정보가 의미 있으므로 schema 살짝 다름)
events_file="$handoff_dir/.events.jsonl"
ts="$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date -u '+%Y-%m-%dT%H:%M:%SZ')"
jq -nc --arg t "$ts" --arg n "$harness_name" --arg tool "$tool_name" \
  '{type:"harness", ts:$t, name:$n, tool:$tool}' >> "$events_file" 2>/dev/null || true

exit 0
