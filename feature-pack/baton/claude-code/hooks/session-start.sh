#!/usr/bin/env bash
# baton session-start hook (v1.2.3+)
# read-only 알림 + 환경 검증. mutation 없음.
set -euo pipefail
[[ -n "${BATON_SKIP_HOOKS:-}" ]] && exit 0
BATON_HOME="${BATON_HOME:-$HOME/.baton/current}"
[[ -d "$BATON_HOME" ]] || exit 0  # baton 미설치 시 silent skip

# shellcheck source=../../core/lib/core.sh
. "$BATON_HOME/lib/core.sh"

# ---------------------------------------------------------------------------
# 헬퍼: CURRENT.md frontmatter 필드 읽기
# ---------------------------------------------------------------------------
_baton_read_frontmatter() {
  local file="$1" field="$2"
  # ---...--- 사이 YAML frontmatter에서 key: value 추출
  awk '/^---$/{f=!f; next} f{print}' "$file" \
    | grep "^${field}:" \
    | head -1 \
    | sed "s/^${field}:[[:space:]]*//"
}

# ---------------------------------------------------------------------------
# 현재 디렉토리에서 부모 방향으로 .baton/handoff/CURRENT.md 탐색
# ---------------------------------------------------------------------------
_find_current_md() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    local candidate="$dir/.baton/handoff/CURRENT.md"
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

# ---------------------------------------------------------------------------
# 심볼릭 링크 깨진 것 체크
# ---------------------------------------------------------------------------
_check_broken_symlinks() {
  local wt_root="$1"
  local broken=()
  for link in .env .claude .env.local .env.worktree; do
    local p="$wt_root/$link"
    if [[ -L "$p" ]] && [[ ! -e "$p" ]]; then
      broken+=("$link")
    fi
  done
  if [[ ${#broken[@]} -gt 0 ]]; then
    echo "[baton] WARN: 깨진 심볼릭 링크 감지: ${broken[*]}" >&2
  fi
}

# ---------------------------------------------------------------------------
# 시간 차이(분) 계산 — ISO8601 vs now
# ---------------------------------------------------------------------------
_minutes_since() {
  local iso_ts="$1"
  # macOS / Linux 모두 대응
  local epoch_then epoch_now
  if date -j >/dev/null 2>&1; then
    # macOS
    epoch_then=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${iso_ts%%+*}" "+%s" 2>/dev/null \
                 || date -j -f "%Y-%m-%dT%H:%M:%SZ" "${iso_ts%%+*}" "+%s" 2>/dev/null \
                 || echo 0)
  else
    # GNU
    epoch_then=$(date -d "$iso_ts" "+%s" 2>/dev/null || echo 0)
  fi
  epoch_now=$(date "+%s")
  echo $(( (epoch_now - epoch_then) / 60 ))
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
CURRENT_MD=""
if CURRENT_MD="$(_find_current_md 2>/dev/null)"; then
  :
else
  # CURRENT.md 없음 — main/master root 체크
  branch="$(git branch --show-current 2>/dev/null || echo "")"
  if [[ "$branch" == "main" || "$branch" == "master" ]]; then
    echo "─────────────────────────────────────────"
    echo "💡 baton: main/master 브랜치입니다."
    echo "  새 페이즈를 시작하려면: baton new-phase <name>"
    echo "  기존 워크트리 목록:     baton list"
    echo "─────────────────────────────────────────"
  fi
  exit 0
fi

wt_root="$(dirname "$(dirname "$CURRENT_MD")")"

# frontmatter 파싱
status="$(_baton_read_frontmatter "$CURRENT_MD" "status")"
phase_id="$(_baton_read_frontmatter "$CURRENT_MD" "phase_id")"
branch="$(_baton_read_frontmatter "$CURRENT_MD" "branch")"
last_updated="$(_baton_read_frontmatter "$CURRENT_MD" "last_updated")"
last_harness="$(_baton_read_frontmatter "$CURRENT_MD" "last_harness")"

# 알림 출력
if [[ "$status" == "paused" ]]; then
  echo "─────────────────────────────────────────"
  echo "📌 일시정지된 페이즈가 있어요"
  echo "  Phase: ${phase_id:-?} (paused, by claude-code)"
  echo "  Branch: ${branch:-(unknown)}"
  echo "  Last updated: ${last_updated:-(unknown)}"
  [[ -n "${last_harness:-}" ]] && echo "  Last harness: $last_harness"
  echo ""
  echo "이어서: \"이어서\" / \"진행\" / \"go\" / \"continue\" / \"next\""
  echo "다른 작업: 무시하고 새 요청 입력"
  echo "─────────────────────────────────────────"
elif [[ "$status" == "active" && -n "${last_updated:-}" ]]; then
  mins="$(_minutes_since "$last_updated" 2>/dev/null || echo 0)"
  if [[ "$mins" -gt 30 ]]; then
    echo "[baton] WARN: 활성 페이즈가 ${mins}분 동안 갱신되지 않았습니다 (stale)."
    echo "  Phase: ${phase_id:-?} | Branch: ${branch:-(unknown)}"
  fi
fi

# 환경 파일 존재 검증
for f in PLAN.md JOURNAL.md NEXT.md; do
  [[ -f "$wt_root/.baton/handoff/$f" ]] \
    || echo "[baton] WARN: .baton/handoff/$f 가 없습니다 (핸드오프 파일 누락)."
done

# 심볼릭 링크 검증
_check_broken_symlinks "$wt_root"

# Lazy prune (7일 경과 아카이브 정리)
if command -v baton_archive_lazy_prune &>/dev/null; then
  baton_archive_lazy_prune 7
fi

exit 0
