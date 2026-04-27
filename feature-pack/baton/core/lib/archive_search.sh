#!/usr/bin/env bash
# baton lib/archive_search.sh — 메타+내용 검색
# 기본 현재 프로젝트, --global 로 모든 프로젝트 (da 권고: 보안)

set -euo pipefail

BATON_HOME="${BATON_HOME:-$HOME/.baton/current}"

# 검색 범위 결정 — 현재 프로젝트 또는 글로벌
baton_search_indices() {
  local global="${1:-false}"
  if $global; then
    # 글로벌은 deprecated, 모든 .baton/archive/INDEX.jsonl 검색
    find / -maxdepth 6 -path "*/.baton/archive/INDEX.jsonl" -type f 2>/dev/null || true
  else
    local project_root
    project_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
    local super
    super=$(git rev-parse --show-superproject-working-tree 2>/dev/null)
    [[ -n "$super" ]] && project_root="$super"
    echo "$project_root/.baton/archive/INDEX.jsonl"
  fi
}

# 메타 검색
baton_archive_search_meta() {
  local query=$1
  local global="${2:-false}"
  command -v jq >/dev/null || { echo "❌ jq required" >&2; return 2; }
  local indices
  indices=$(baton_search_indices "$global")
  for idx in $indices; do
    [[ -s "$idx" ]] || continue
    jq -r --arg q "$query" '
      select(
        (.id | test($q; "i")) or
        (.branch | test($q; "i")) or
        (.phase | test($q; "i")) or
        ((.tags // []) | tostring | test($q; "i"))
      )
      | .id
    ' "$idx"
  done
}

# 내용 검색 (tar streaming grep)
baton_archive_search_content() {
  local query=$1
  local global="${2:-false}"
  local searcher="grep"
  command -v rg >/dev/null && searcher="rg"
  local indices
  indices=$(baton_search_indices "$global")
  for idx in $indices; do
    [[ -s "$idx" ]] || continue
    local archive_dir
    archive_dir=$(dirname "$idx")
    while IFS= read -r line; do
      local id
      id=$(echo "$line" | jq -r '.id' 2>/dev/null) || continue
      local archive_file="$archive_dir/${id}.tar.gz"
      [[ -f "$archive_file" ]] || continue
      local hits
      if [[ "$searcher" == "rg" ]]; then
        hits=$(tar -xzOf "$archive_file" 2>/dev/null | rg -n --color=never "$query" | head -5 || true)
      else
        hits=$(tar -xzOf "$archive_file" 2>/dev/null | grep -n "$query" | head -5 || true)
      fi
      if [[ -n "$hits" ]]; then
        echo "[$id] $(echo "$line" | jq -r '.branch')"
        echo "$hits" | sed 's/^/    /'
        echo
      fi
    done < "$idx"
  done
}

baton_archive_search() {
  local query=$1
  local global="${2:-false}"
  echo "🔍 메타 매칭"
  echo "─────────────────────────────────────────"
  local meta_ids
  meta_ids=$(baton_archive_search_meta "$query" "$global")
  if [[ -z "$meta_ids" ]]; then
    echo "(없음)"
  else
    echo "$meta_ids"
  fi
  echo
  echo "🔍 내용 매칭"
  echo "─────────────────────────────────────────"
  baton_archive_search_content "$query" "$global"
  echo
  echo "상세: /baton:archive show <id>"
  echo "압축해제: /baton:archive extract <id>"
}
