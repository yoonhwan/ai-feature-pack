#!/usr/bin/env bash
# baton post-tool-use hook
set -euo pipefail
BATON_HOME="${BATON_HOME:-$HOME/.baton/current}"
[[ -d "$BATON_HOME" ]] || exit 0  # baton 미설치 시 silent skip

# shellcheck source=../../core/lib/core.sh
. "$BATON_HOME/lib/core.sh"

# ---------------------------------------------------------------------------
# 하네스 호출 도구 이름 목록 (tool_name 기준)
# ---------------------------------------------------------------------------
_HARNESS_TOOL_NAMES=("Skill" "Agent" "Task")

_is_harness_tool() {
  local name="$1"
  for h in "${_HARNESS_TOOL_NAMES[@]}"; do
    [[ "$name" == "$h" ]] && return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# stdin JSON에서 필드 추출
# ---------------------------------------------------------------------------
_jq_field() {
  local json="$1" path="$2"
  if command -v jq &>/dev/null; then
    echo "$json" | jq -r "$path // empty" 2>/dev/null
  fi
}

# ---------------------------------------------------------------------------
# 탐색 헬퍼
# ---------------------------------------------------------------------------
_find_file_upward() {
  local filename="$1"
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    [[ -f "$dir/$filename" ]] && { echo "$dir/$filename"; return 0; }
    dir="$(dirname "$dir")"
  done
  return 1
}

_find_journal()    { _find_file_upward ".baton/handoff/JOURNAL.md"; }
_find_current_md() { _find_file_upward ".baton/handoff/CURRENT.md"; }
_find_phase_json() { _find_file_upward ".baton/phase.json"; }

# ---------------------------------------------------------------------------
# JOURNAL.md 마지막 Turn의 HARNESS 필드 갱신
# ---------------------------------------------------------------------------
_update_last_turn_harness() {
  local journal="$1" harness_name="$2"
  local tmp
  tmp="$(mktemp)"
  # 마지막 "- **HARNESS**: -" 줄을 교체 (macOS/Linux 호환: tac 미사용, single-pass awk)
  awk -v name="$harness_name" '
    /^- \*\*HARNESS\*\*: -$/ { last_line = NR }
    { lines[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        if (i == last_line) print "- **HARNESS**: " name
        else                 print lines[i]
      }
    }
  ' "$journal" > "$tmp"
  mv "$tmp" "$journal"
}

# ---------------------------------------------------------------------------
# CURRENT.md frontmatter last_harness 갱신
# ---------------------------------------------------------------------------
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
# phase.json sessions[].harnesses_used 배열에 추가 (중복 제거)
# ---------------------------------------------------------------------------
_record_harness_in_phase_json() {
  local phase_json="$1" harness_name="$2"
  command -v jq &>/dev/null || return 0
  [[ -f "$phase_json" ]] || return 0

  local tmp
  tmp="$(mktemp)"
  # sessions 배열 마지막 요소의 harnesses_used에 추가 (없으면 생성)
  jq --arg h "$harness_name" '
    if (.sessions | length) > 0 then
      .sessions[-1].harnesses_used = (
        (.sessions[-1].harnesses_used // []) + [$h] | unique
      )
    else
      .
    end
  ' "$phase_json" > "$tmp" && mv "$tmp" "$phase_json" || rm -f "$tmp"
}

# ---------------------------------------------------------------------------
# 하네스 결과 검증 (baton_harness_verify 또는 내부 구현)
# ---------------------------------------------------------------------------
_verify_harness_output() {
  local harness_name="$1"
  # 표준 verification (yaml 폐기 v2): lib/harnesses.sh의 baton_harness_verify에 위임
  # 모든 하네스 공통 룰 — file exists + min 5 lines + ^## 섹션 존재
  if command -v baton_harness_verify &>/dev/null; then
    baton_harness_verify "$harness_name" && return 0
    echo "[baton] ⚠️ 하네스 ${harness_name} 결과 검증 실패: 출력 파일이 비어있거나 형식 부적합."
    echo "재시도 또는 수동 저장 권장."
    return 1
  fi
  # baton_harness_verify 미정의 (베이스 환경) — 검증 skip
  return 0
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

# stdin 읽기 (JSON payload)
raw_input=""
if ! IFS= read -t 1 -r raw_input 2>/dev/null; then
  exit 0
fi
[[ -z "$raw_input" ]] && exit 0

# JSON 파싱 가능 여부
command -v jq &>/dev/null || exit 0

tool_name="$(_jq_field "$raw_input" '.tool_name')"
[[ -z "$tool_name" ]] && exit 0

# 하네스 도구가 아니면 silent skip
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

# JOURNAL.md HARNESS 갱신
journal=""
if journal="$(_find_journal 2>/dev/null)"; then
  _update_last_turn_harness "$journal" "$harness_name"
fi

# CURRENT.md last_harness 갱신
current_md=""
if current_md="$(_find_current_md 2>/dev/null)"; then
  _update_frontmatter_field "$current_md" "last_harness" "$harness_name"
fi

# phase.json harnesses_used 갱신
phase_json=""
if phase_json="$(_find_phase_json 2>/dev/null)"; then
  _record_harness_in_phase_json "$phase_json" "$harness_name"
fi

# 하네스 결과 검증 (실패 시만 stdout 출력)
_verify_harness_output "$harness_name" || true

exit 0
