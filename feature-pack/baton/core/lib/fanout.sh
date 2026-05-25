#!/usr/bin/env bash
# baton lib/fanout.sh — fan-out/fan-in 브랜치 추적
#
# .baton/branches.json 에 워크트리 분기 이력 기록 (프로젝트 레벨, git-tracked).
# save/finish/resume/status/wt-clean에서 미병합 자식 브랜치 경고/차단.

BATON_HOME="${BATON_HOME:-$HOME/.baton/current}"

baton_fanout_ledger() {
  local root="${1:-$(baton_project_root)}"
  echo "$root/.baton/branches.json"
}

baton_fanout_init() {
  local ledger
  ledger=$(baton_fanout_ledger "${1:-}")
  [[ -f "$ledger" ]] || echo '[]' > "$ledger"
}

# === 동시 쓰기 방지 (mkdir atomic lock) ===
baton_fanout_lock_acquire() {
  local root="$1"
  local lock_dir="$root/.baton/.branches.lock"
  local timeout=5 elapsed=0
  while ! mkdir "$lock_dir" 2>/dev/null; do
    if [[ "$elapsed" -ge "$timeout" ]]; then
      local lock_mtime
      lock_mtime=$(stat -f %m "$lock_dir" 2>/dev/null \
        || stat -c %Y "$lock_dir" 2>/dev/null || echo 0)
      if [[ $(( $(date +%s) - lock_mtime )) -gt 60 ]]; then
        rm -rf "$lock_dir"; continue
      fi
      return 1
    fi
    sleep 1; elapsed=$((elapsed + 1))
  done
  return 0
}

baton_fanout_lock_release() {
  rm -rf "${1:-.}/.baton/.branches.lock" 2>/dev/null || true
}

baton_fanout_register() {
  local root="$1" parent_branch="$2" child_branch="$3"
  local child_worktree="$4" purpose="${5:-}"
  command -v jq >/dev/null 2>&1 || return 0
  local ledger
  ledger=$(baton_fanout_ledger "$root")
  baton_fanout_init "$root"
  if jq -e --arg cb "$child_branch" \
    'any(.[]; .child_branch == $cb)' "$ledger" >/dev/null 2>&1; then
    return 0
  fi
  baton_fanout_lock_acquire "$root" || return 0
  local now
  now=$(baton_iso_now)
  local created_commit
  created_commit=$(git -C "$root" rev-parse "$child_branch" 2>/dev/null || echo "")
  local tmp
  tmp=$(mktemp)
  jq --arg pb "$parent_branch" --arg cb "$child_branch" \
     --arg cw "$child_worktree" --arg p "${purpose:-$child_branch}" --arg ts "$now" \
     --arg cc "$created_commit" \
     '. + [{parent_branch:$pb, child_branch:$cb, child_worktree:$cw, purpose:$p, created_at:$ts, created_commit:$cc, status:"active", merged_at:null}]' \
     "$ledger" > "$tmp" 2>/dev/null && mv "$tmp" "$ledger" || rm -f "$tmp"
  baton_fanout_lock_release "$root"
}

baton_fanout_set_status() {
  local root="$1" child_branch="$2" new_status="$3"
  command -v jq >/dev/null 2>&1 || return 0
  local ledger
  ledger=$(baton_fanout_ledger "$root")
  [[ -f "$ledger" ]] || return 0
  baton_fanout_lock_acquire "$root" || return 0
  local tmp
  tmp=$(mktemp)
  local now
  now=$(baton_iso_now)
  if [[ "$new_status" == "merged" ]]; then
    jq --arg cb "$child_branch" --arg s "$new_status" --arg t "$now" \
      'map(if .child_branch == $cb and .status == "active" then .status = $s | .merged_at = $t else . end)' \
      "$ledger" > "$tmp" 2>/dev/null && mv "$tmp" "$ledger" || rm -f "$tmp"
  else
    jq --arg cb "$child_branch" --arg s "$new_status" \
      'map(if .child_branch == $cb and .status == "active" then .status = $s else . end)' \
      "$ledger" > "$tmp" 2>/dev/null && mv "$tmp" "$ledger" || rm -f "$tmp"
  fi
  baton_fanout_lock_release "$root"
}

# git 상태와 장부 자동 동기화: 머지된/삭제된 브랜치 감지
# per-invocation dedup: 같은 root에 대해 한 번만 실행
baton_fanout_auto_sync() {
  local root="${1:-$(baton_project_root)}"
  [[ "${_BATON_FANOUT_SYNCED:-}" == "$root" ]] && return 0
  _BATON_FANOUT_SYNCED="$root"
  command -v jq >/dev/null 2>&1 || return 0
  local ledger
  ledger=$(baton_fanout_ledger "$root")
  [[ -f "$ledger" ]] || return 0
  local main_branch=""
  for mb in main master; do
    git -C "$root" rev-parse --verify "$mb" >/dev/null 2>&1 && { main_branch="$mb"; break; }
  done
  [[ -n "$main_branch" ]] || return 0
  while IFS=$'\t' read -r cb cc; do
    [[ -n "$cb" ]] || continue
    if ! git -C "$root" rev-parse --verify "$cb" >/dev/null 2>&1; then
      baton_fanout_set_status "$root" "$cb" "merged"
      continue
    fi
    if [[ -n "$cc" ]]; then
      local child_head
      child_head=$(git -C "$root" rev-parse "$cb" 2>/dev/null || echo "")
      [[ "$child_head" == "$cc" ]] && continue
    fi
    if git -C "$root" merge-base --is-ancestor "$cb" "$main_branch" 2>/dev/null; then
      baton_fanout_set_status "$root" "$cb" "merged"
    fi
  done < <(jq -r '.[] | select(.status == "active") | [.child_branch, (.created_commit // "")] | @tsv' "$ledger" 2>/dev/null)
}

baton_fanout_unmerged_count() {
  local root="${1:-$(baton_project_root)}" parent="${2:-}"
  command -v jq >/dev/null 2>&1 || { echo 0; return; }
  local ledger
  ledger=$(baton_fanout_ledger "$root")
  [[ -f "$ledger" ]] || { echo 0; return; }
  if [[ -n "$parent" ]]; then
    jq --arg pb "$parent" \
      '[.[] | select(.parent_branch == $pb and .status == "active")] | length' \
      "$ledger" 2>/dev/null || echo 0
  else
    jq '[.[] | select(.status == "active")] | length' "$ledger" 2>/dev/null || echo 0
  fi
}

# non-main parent 한정 fan-out 여부
baton_fanout_is_fanout() {
  local branch="${1:-}"
  [[ -n "$branch" ]] || return 1
  case "$branch" in main|master|unknown|"") return 1 ;; esac
  return 0
}

# save/resume/wt-clean 경고 (non-main parent 한정)
baton_fanout_warn() {
  local root="${1:-$(baton_project_root)}" branch="${2:-}"
  command -v jq >/dev/null 2>&1 || return 0
  [[ -n "$branch" ]] || branch=$(git -C "$root" branch --show-current 2>/dev/null)
  [[ -n "$branch" ]] || return 0
  case "$branch" in main|master) return 0 ;; esac
  baton_fanout_auto_sync "$root"
  local count
  count=$(baton_fanout_unmerged_count "$root" "$branch")
  [[ "${count:-0}" -gt 0 ]] || return 0
  local ledger
  ledger=$(baton_fanout_ledger "$root")
  echo
  echo "⚠️  이 워크트리에서 분기된 미병합 브랜치 ${count}개:"
  jq -r --arg pb "$branch" \
    '.[] | select(.parent_branch == $pb and .status == "active") | "    - \(.child_branch) (\(.created_at | split("T")[0]))"' \
    "$ledger" 2>/dev/null
  echo "   병합 또는 /baton:wt-clean 후 진행 권장"
}

# finish 차단 (--force로 우회)
baton_fanout_block_finish() {
  local root="$1" branch="${2:-}" force="${3:-false}"
  command -v jq >/dev/null 2>&1 || return 0
  [[ -n "$branch" ]] || branch=$(git -C "$root" branch --show-current 2>/dev/null)
  [[ -n "$branch" ]] || return 0
  case "$branch" in main|master) return 0 ;; esac
  baton_fanout_auto_sync "$root"
  local count
  count=$(baton_fanout_unmerged_count "$root" "$branch")
  [[ "${count:-0}" -gt 0 ]] || return 0
  local ledger
  ledger=$(baton_fanout_ledger "$root")
  echo "❌ 미병합 자식 브랜치 ${count}개 — finish 차단"
  jq -r --arg pb "$branch" \
    '.[] | select(.parent_branch == $pb and .status == "active") | "    - \(.child_branch) (\(.created_at | split("T")[0]))"' \
    "$ledger" 2>/dev/null
  if [[ "$force" == "true" ]]; then
    echo "   --force 지정됨 — 강제 진행"
    return 0
  fi
  echo "   해결: 자식 브랜치를 먼저 병합하거나 /baton:finish --force"
  return 1
}

# status 요약 표시
baton_fanout_status() {
  local root="${1:-$(baton_project_root)}"
  command -v jq >/dev/null 2>&1 || return 0
  local ledger
  ledger=$(baton_fanout_ledger "$root")
  [[ -f "$ledger" ]] || return 0
  baton_fanout_auto_sync "$root"
  local total
  total=$(jq 'length' "$ledger" 2>/dev/null)
  [[ "${total:-0}" -gt 0 ]] || return 0
  local active merged
  active=$(jq '[.[] | select(.status == "active")] | length' "$ledger" 2>/dev/null)
  merged=$(jq '[.[] | select(.status == "merged")] | length' "$ledger" 2>/dev/null)
  echo
  echo "  브랜치 추적 (fan-out/fan-in):"
  echo "    총 ${total}개 (active: ${active:-0}, merged: ${merged:-0})"
  if [[ "${active:-0}" -gt 0 ]]; then
    echo "    미병합:"
    jq -r '.[] | select(.status == "active") | "      ⚠ \(.child_branch) ← \(.parent_branch) (\(.created_at | split("T")[0]))"' \
      "$ledger" 2>/dev/null
  fi
}
