#!/usr/bin/env bash
# baton lib/ports.sh — 워크트리별 deterministic 포트 할당
# 룰: worktree_port = base_port + (offset × index)
# index = max(existing index) + 1 (race 방지)

set -euo pipefail

BATON_HOME="${BATON_HOME:-$HOME/.baton/current}"

baton_require_jq() {
  command -v jq >/dev/null || { echo "❌ jq required (brew install jq)" >&2; exit 2; }
}

baton_read_config() {
  local key=$1
  local cfg="${2:-./.baton/config.json}"
  [[ -f "$cfg" ]] || { echo "❌ config.json not found: $cfg" >&2; return 1; }
  baton_require_jq
  jq -r "$key // empty" "$cfg"
}

# 모든 .worktree-info.json에서 max(index) + 1 (deterministic)
baton_next_worktree_index() {
  local project_root="${1:-.}"
  local wt_dir="$project_root/.worktrees"
  [[ -d "$wt_dir" ]] || { echo 1; return; }
  baton_require_jq
  local max=0
  for info in "$wt_dir"/*/.worktree-info.json; do
    [[ -f "$info" ]] || continue
    local idx
    idx=$(jq -r '.index // 0' "$info" 2>/dev/null)
    [[ "$idx" -gt "$max" ]] && max=$idx
  done
  echo $((max + 1))
}

baton_compute_port() {
  local service=$1 idx=$2
  local cfg="${3:-./.baton/config.json}"
  baton_require_jq
  local base offset
  base=$(jq -r ".base_ports.${service} // empty" "$cfg")
  offset=$(jq -r ".worktree_port_offset // 10" "$cfg")
  [[ -z "$base" ]] && { echo "❌ base_ports.$service not in config" >&2; return 1; }
  echo $((base + offset * idx))
}

baton_write_worktree_env() {
  local wt_path=$1 idx=$2
  local cfg="${3:-./.baton/config.json}"
  baton_require_jq
  local services
  services=$(jq -r '.base_ports | keys[]' "$cfg")
  local env_file="$wt_path/.env.worktree"
  : > "$env_file"
  echo "# baton auto-generated worktree env (index=$idx)" >> "$env_file"
  for svc in $services; do
    local port
    port=$(baton_compute_port "$svc" "$idx" "$cfg")
    local var
    var=$(echo "$svc" | tr '[:lower:]' '[:upper:]')
    echo "${var}_PORT=${port}" >> "$env_file"
  done
  local proj branch
  proj=$(baton_read_config '.project_name' "$cfg")
  branch=$(git -C "$wt_path" branch --show-current 2>/dev/null || echo "unknown")
  echo "COMPOSE_PROJECT_NAME=${proj}-${branch//\//-}" >> "$env_file"
  echo "BATON_WORKTREE_INDEX=$idx" >> "$env_file"
}
