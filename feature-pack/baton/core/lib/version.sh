#!/usr/bin/env bash
# baton lib/version.sh — 버전 + 호환성 + 옵션 B 가드

set -euo pipefail

BATON_HOME="${BATON_HOME:-$HOME/.baton/current}"

baton_version() { cat "$BATON_HOME/VERSION" 2>/dev/null || echo "unknown"; }
baton_spec_version() { echo "1"; }

baton_semver_cmp() {
  local v1=$1 v2=$2
  [[ "$v1" == "$v2" ]] && { echo 0; return; }
  local IFS=.
  local -a a=($v1) b=($v2)
  for ((i=0; i<3; i++)); do
    local ai=${a[i]:-0} bi=${b[i]:-0}
    (( ai > bi )) && { echo 1; return; }
    (( ai < bi )) && { echo 2; return; }
  done
  echo 0
}

baton_check_compat() {
  local lock="${1:-./.baton/version.lock}"
  [[ -f "$lock" ]] || return 0
  command -v jq >/dev/null || { echo "❌ jq required" >&2; return 2; }
  local current compat min_v max_v
  current=$(baton_version)
  compat=$(jq -r '.compat_range // empty' "$lock")
  [[ -z "$compat" ]] && return 0
  min_v=$(echo "$compat" | grep -oE '>=[0-9.]+' | sed 's/>=//') || true
  max_v=$(echo "$compat" | grep -oE '<[0-9.]+' | sed 's/<//') || true
  if [[ -n "$min_v" ]] && [[ $(baton_semver_cmp "$current" "$min_v") == "2" ]]; then
    echo "❌ baton $current < required $min_v" >&2; return 1
  fi
  if [[ -n "$max_v" ]] && [[ $(baton_semver_cmp "$current" "$max_v") != "2" ]]; then
    echo "❌ baton $current >= upper bound $max_v (major incompat)" >&2; return 1
  fi
  return 0
}

baton_write_version_lock() {
  local target="${1:-./.baton/version.lock}"
  command -v jq >/dev/null || { echo "❌ jq required" >&2; return 2; }
  local current major next_major now
  current=$(baton_version)
  major=$(echo "$current" | cut -d. -f1)
  next_major=$((major + 1))
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq -nc \
    --arg v "$current" \
    --arg c ">=$current <$next_major.0.0" \
    --arg s "$(baton_spec_version)" \
    --arg t "$now" \
    '{baton_version:$v, compat_range:$c, spec_version:$s, locked_at:$t}' > "$target"
}

baton_is_main_root() {
  local path="${1:-$PWD}"
  local repo_root
  repo_root=$(git -C "$path" rev-parse --show-toplevel 2>/dev/null) || return 1
  # macOS /var → /private/var 심링 정규화
  local norm_path norm_root
  norm_path=$(cd "$path" 2>/dev/null && pwd -P) || return 1
  norm_root=$(cd "$repo_root" 2>/dev/null && pwd -P) || return 1
  [[ "$norm_path" != "$norm_root" ]] && return 1
  local super
  super=$(git -C "$path" rev-parse --show-superproject-working-tree 2>/dev/null)
  [[ -n "$super" ]] && return 1
  local branch
  branch=$(git -C "$path" branch --show-current 2>/dev/null)
  local main_branches="main master"
  if [[ -f "$path/.baton/config.json" ]] && command -v jq >/dev/null; then
    main_branches=$(jq -r '(.main_branches // ["main","master"]) | join(" ")' "$path/.baton/config.json" 2>/dev/null) || main_branches="main master"
  fi
  for mb in $main_branches; do
    [[ "$branch" == "$mb" ]] && return 0
  done
  return 1
}

baton_guard_main_root() {
  local cmd=$1
  if baton_is_main_root "$PWD"; then
    case "$cmd" in
      wt-create|status|help|install|doctor|upgrade|hotfix-mode|archive)
        return 0
        ;;
      *)
        cat >&2 <<'GUARD'
❌ main/master 브랜치 root 에서 '/baton:CMD' 거부됩니다 (옵션 B strict).

허용된 명령:
  /baton:wt-create <name>     # 워크트리 생성
  /baton:status               # 활성 워크트리 목록
  /baton:archive list/search  # 조회
  /baton:hotfix-mode          # main 직접 작업 (lite mode)

phase 작업은 워크트리 안에서만 가능합니다.
GUARD
        return 1
        ;;
    esac
  fi
  return 0
}
