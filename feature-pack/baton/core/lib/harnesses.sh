#!/usr/bin/env bash
# baton lib/harnesses.sh — 표준 instruction (yaml 카탈로그 폐기, da 권고 SIMPLIFY v2)
#
# 이전 버전: harnesses/*.yaml 7개 + 파서. 모든 yaml이 거의 동일한 default를 가져 기술 부채.
# 현재: 표준 instruction 2개 상수 + 이름 매칭 분류 1줄 + 표준 verification 1개.
# 신규 하네스: yaml 작성 불필요. 사용자가 그냥 호출하면 표준 instruction 동적 주입.

set -euo pipefail

BATON_HOME="${BATON_HOME:-$HOME/.baton/current}"

# === 표준 instruction (Claude에게 동적 주입) ===

BATON_PLAN_INSTRUCTION='이 작업의 결과를 .baton/handoff/PLAN.md 에 다음 형식으로 append 하세요:

## YYYY-MM-DD HH:MM — <섹션 제목> (by <harness-name>)

<본문 — markdown 자유 형식>

기존 PLAN.md 내용은 보존하고 끝에 새 섹션 추가만 하세요. 시간순 누적이 핵심입니다.'

BATON_EXECUTION_INSTRUCTION='이 작업의 결과를 .baton/handoff/JOURNAL.md 의 마지막 Turn 섹션에 갱신하거나 새 Turn으로 append 하세요:

## YYYY-MM-DD HH:MM — Turn N
- **INTENT**: <사용자 의도>
- **HARNESS**: <name>
- **ACTIONS**: <한 일 요약>
- **TODO**: <남은 일>

기존 JOURNAL.md 내용은 보존하고 끝에 추가만 하세요.'

# === 이름 매칭 분류 (yaml 대체) ===

baton_classify_harness() {
  local name
  name=$(echo "${1:-}" | tr '[:upper:]' '[:lower:]')
  case "$name" in
    *plan*|*brainstorm*|*interview*|*deep-dive*|*deep-interview*)
      echo "plan" ;;
    *mem-search*|*mem*search*|*memory*)
      echo "memory_search" ;;
    *autopilot*|*team*|*execut*|*ralph*|*ultrawork*|*orchestrate*)
      echo "execution" ;;
    *)
      # 모르는 하네스는 execution 으로 default (보수적)
      echo "execution" ;;
  esac
}

# === 표준 instruction 반환 ===

baton_harness_instruction() {
  local name=$1
  local category
  category=$(baton_classify_harness "$name")
  case "$category" in
    plan) echo "$BATON_PLAN_INSTRUCTION" ;;
    execution) echo "$BATON_EXECUTION_INSTRUCTION" ;;
    memory_search) echo "(memory_search 카테고리 — 출력 파일 누적 없음. 결과는 사용자에게 직접 전달.)" ;;
  esac
}

# === 출력 파일 위치 ===

baton_harness_output_file() {
  local name=$1
  local category
  category=$(baton_classify_harness "$name")
  case "$category" in
    plan) echo ".baton/handoff/PLAN.md" ;;
    execution) echo ".baton/handoff/JOURNAL.md" ;;
    memory_search) echo "" ;;
  esac
}

# === 표준 verification (모든 하네스 공통, da 권고) ===
# Rule: file exists + min 5 lines + ^## 섹션 존재
# 단순함이 핵심. 하네스별 특수 verification 없음.

baton_harness_verify() {
  local name=$1
  local output_file="${2:-}"

  # output 없는 하네스 (memory_search 등) — 항상 PASS
  if [[ -z "$output_file" ]]; then
    output_file=$(baton_harness_output_file "$name")
  fi
  [[ -z "$output_file" ]] && return 0

  if [[ ! -f "$output_file" ]]; then
    echo "⚠️  $name: output file 누락 ($output_file)" >&2
    return 1
  fi

  local lines
  lines=$(wc -l < "$output_file" | tr -d ' ')
  if [[ "$lines" -lt 5 ]]; then
    echo "⚠️  $name: output too short ($lines lines < min 5)" >&2
    return 1
  fi

  if ! grep -qE '^## ' "$output_file"; then
    echo "⚠️  $name: 필수 섹션 (## ...) 누락" >&2
    return 1
  fi

  return 0
}

# === 하네스 사용 기록 (PostToolUse 훅이 호출) ===

baton_harness_record() {
  local name=$1
  # JOURNAL.md 의 마지막 Turn HARNESS 필드 + CURRENT.md last_harness 갱신
  if declare -f baton_journal_set_last_harness >/dev/null 2>&1; then
    baton_journal_set_last_harness "$name" 2>/dev/null || true
  fi
}

# === /baton:plan 시 추천 안내 (yaml 후보 출력 폐기, README 안내) ===

baton_plan_recommend() {
  local cfg="${1:-./.baton/config.json}"
  local preferred="superpowers:writing-plans"
  if [[ -f "$cfg" ]] && command -v jq >/dev/null 2>&1; then
    preferred=$(jq -r '.harnesses.preferred_plan // "superpowers:writing-plans"' "$cfg")
  fi
  cat <<EOF
─── 추천 plan 하네스 (최신 슬래시만) ───
  ⭐ /$preferred (config의 preferred_plan, 또는 default)
──────────────────────────────────────────

다른 옵션:
  /superpowers:brainstorming        모호한 요구사항, 다방향 탐색
  /superpowers:writing-plans        명확한 plan 문서 작성
  /oh-my-claudecode:deep-interview  Socratic 인터뷰
  /oh-my-claudecode:plan            Strategic planning

⚠️  /superpowers:write-plan, /superpowers:brainstorm, /superpowers:execute-plan 는 deprecated. 위 최신 슬래시만 사용하세요.

─── 호출 시 다음 지시 포함하세요 (B+C 패턴) ───

다음을 그대로 복사해서 호출:

/$preferred

이 작업의 결과는 .baton/handoff/PLAN.md 에 다음 형식으로 append 해주세요:

  ## $(date +"%Y-%m-%d %H:%M") — Plan v1 (by $preferred)
  <plan 본문>

기존 PLAN.md 내용은 보존하고 끝에 새 섹션 추가만 하세요.

──────────────────────────────────────────
변경: config.json 의 harnesses.preferred_plan
EOF
}
