#!/usr/bin/env bash
# baton lib/verify.sh — 하네스 출력 검증 + retry
# da 권고: mtime만으로 부족, min_lines + required_sections 검증

set -euo pipefail

BATON_HOME="${BATON_HOME:-$HOME/.baton/current}"

# 출력 파일이 유효한지 (min_lines, required_sections)
baton_verify_output() {
  local file=$1
  local min_lines="${2:-5}"
  local required_section_pattern="${3:-^## }"
  if [[ ! -f "$file" ]]; then
    echo "FAIL: file missing"
    return 1
  fi
  local lines
  lines=$(wc -l < "$file" | tr -d ' ')
  if [[ "$lines" -lt "$min_lines" ]]; then
    echo "FAIL: too short ($lines < $min_lines)"
    return 1
  fi
  if ! grep -qE "$required_section_pattern" "$file"; then
    echo "FAIL: required section missing ($required_section_pattern)"
    return 1
  fi
  echo "PASS"
  return 0
}

# 핸드오프 4파일 health check
baton_verify_handoff_dir() {
  local dir="${1:-./.baton/handoff}"
  [[ -d "$dir" ]] || { echo "FAIL: handoff dir missing"; return 1; }
  local errors=0
  for f in PLAN.md JOURNAL.md CURRENT.md NEXT.md; do
    if [[ ! -f "$dir/$f" ]]; then
      echo "MISSING: $f"
      errors=$((errors + 1))
    fi
  done
  # CURRENT.md frontmatter 검증
  if [[ -f "$dir/CURRENT.md" ]]; then
    if ! head -3 "$dir/CURRENT.md" | grep -q '^---$'; then
      echo "INVALID: CURRENT.md frontmatter"
      errors=$((errors + 1))
    fi
  fi
  [[ "$errors" -eq 0 ]] && echo "PASS" || return 1
}

# phase.json 스키마 검증 (jq)
baton_verify_phase_json() {
  local f="${1:-./.baton/phase.json}"
  command -v jq >/dev/null || { echo "FAIL: jq required"; return 2; }
  [[ -f "$f" ]] || { echo "FAIL: phase.json missing"; return 1; }
  for key in schema_version phase_id branch worktree started_at sessions; do
    if [[ "$(jq -r ".$key // \"\"" "$f")" == "" ]]; then
      echo "FAIL: phase.json missing $key"
      return 1
    fi
  done
  echo "PASS"
  return 0
}
