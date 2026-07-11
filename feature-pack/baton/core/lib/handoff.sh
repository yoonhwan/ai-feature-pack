#!/usr/bin/env bash
# baton lib/handoff.sh — 4-template 핸드오프 (PLAN/JOURNAL/CURRENT/NEXT)
#
# NOTE: lib는 source 대상이라 'set -euo pipefail' 제거 (호출 쉘 전파 부작용 방지).
# 호출 스크립트가 자체 set 결정.

BATON_HOME="${BATON_HOME:-$HOME/.baton/current}"

baton_iso_now() { date +"%Y-%m-%dT%H:%M:%S%z"; }
baton_human_now() { date +"%Y-%m-%d %H:%M"; }
baton_session_id() { date +"%Y-%m-%d_%H%M"; }

# v1.2.3+ — sidecar 이벤트 append (race-free)
# Hook이 JOURNAL.md/CURRENT.md를 직접 mutate하던 로직을 대체.
# /baton:save 호출 시 헤드리스 에이전트가 이 sidecar를 읽어 JOURNAL/CURRENT/NEXT 정리.
baton_events_append() {
  local handoff_dir=$1 type=$2 payload=$3
  [[ -d "$handoff_dir" ]] || return 1
  local events_file="$handoff_dir/.events.jsonl"
  local ts
  ts=$(baton_iso_now)
  if command -v jq &>/dev/null; then
    case "$type" in
      intent)
        jq -nc --arg t "$ts" --arg x "$payload" '{type:"intent", ts:$t, text:$x}' \
          >> "$events_file" 2>/dev/null || return 1
        ;;
      harness)
        jq -nc --arg t "$ts" --arg n "$payload" '{type:"harness", ts:$t, name:$n}' \
          >> "$events_file" 2>/dev/null || return 1
        ;;
      *)
        jq -nc --arg t "$ts" --arg ty "$type" --arg p "$payload" \
          '{type:$ty, ts:$t, payload:$p}' >> "$events_file" 2>/dev/null || return 1
        ;;
    esac
  else
    return 1
  fi
}

baton_events_rotate() {
  # v1.2.4+ — unique suffix (초당 다중 호출 충돌 방지)
  # 인자 2: bucket (default "processed", fallback 시 "failed")
  # NOTE: zsh에서 'status'는 read-only special var — 'bucket'으로 명명
  local handoff_dir=$1
  local bucket="${2:-processed}"
  local events_file="$handoff_dir/.events.jsonl"
  [[ -s "$events_file" ]] || return 0
  local ts pid rnd target
  ts=$(date +"%Y%m%d_%H%M%S")
  pid=$$
  if command -v gdate >/dev/null 2>&1; then
    rnd=$(gdate +"%6N")
  else
    rnd=$(printf "%06d" $(( RANDOM * 32768 + RANDOM )))
  fi
  target="$handoff_dir/.events.${bucket}-${ts}_${pid}_${rnd}.jsonl"
  while [[ -e "$target" ]]; do
    rnd=$(printf "%06d" $(( RANDOM * 32768 + RANDOM )))
    target="$handoff_dir/.events.${bucket}-${ts}_${pid}_${rnd}.jsonl"
  done
  # 같은 디렉토리 내 mv = rename(2) syscall = atomic on POSIX.
  # truncate 단계 제거: 동시 append 라인 손실 방지.
  if mv "$events_file" "$target" 2>/dev/null; then
    echo "$target"
    return 0
  fi
  echo "[baton] ❌ events rotate 실패: $events_file → $target" >&2
  return 1
}

# v1.2.4+ — save snapshot rotate (LLM에 입력 전 사전 회전)
# spawn 진행 중 새 hook event가 append되어도 snapshot에 포함 안 됨 → race-free
baton_events_snapshot_for_save() {
  local handoff_dir=$1
  local events_file="$handoff_dir/.events.jsonl"
  [[ -s "$events_file" ]] || return 0
  local ts pid rnd target
  ts=$(date +"%Y%m%d_%H%M%S")
  pid=$$
  if command -v gdate >/dev/null 2>&1; then
    rnd=$(gdate +"%6N")
  else
    rnd=$(printf "%06d" $(( RANDOM * 32768 + RANDOM )))
  fi
  target="$handoff_dir/.events.snapshot-${ts}_${pid}_${rnd}.jsonl"
  while [[ -e "$target" ]]; do
    rnd=$(printf "%06d" $(( RANDOM * 32768 + RANDOM )))
    target="$handoff_dir/.events.snapshot-${ts}_${pid}_${rnd}.jsonl"
  done
  if mv "$events_file" "$target" 2>/dev/null; then
    echo "$target"
    return 0
  fi
  echo "[baton] ❌ snapshot rotate 실패" >&2
  return 1
}

baton_events_count() {
  local handoff_dir=$1
  local events_file="$handoff_dir/.events.jsonl"
  [[ -f "$events_file" ]] || { echo 0; return; }
  wc -l < "$events_file" 2>/dev/null | tr -d ' '
}

# v1.2.4+ — snapshot → processed/failed 최종 회전
# 인자: handoff_dir, snapshot_path, bucket(processed|failed)
baton_events_processed_finalize() {
  local handoff_dir=$1 snapshot=$2 bucket=$3
  [[ -f "$snapshot" ]] || return 1
  local base="$(basename "$snapshot")"
  # snapshot suffix 추출 — .events.snapshot-{rest}
  local rest="${base#.events.snapshot-}"
  local target="$handoff_dir/.events.${bucket}-${rest}"
  while [[ -e "$target" ]]; do
    local rnd
    rnd=$(printf "%06d" $(( RANDOM * 32768 + RANDOM )))
    target="$handoff_dir/.events.${bucket}-${rest}.dup-${rnd}"
  done
  if mv "$snapshot" "$target" 2>/dev/null; then
    echo "$target"
    return 0
  fi
  echo "[baton] ❌ finalize 실패: $snapshot → $target" >&2
  return 1
}

# v1.2.4+ — save 동시 호출 lock (mkdir atomic)
# 사용: baton_save_lock_acquire <handoff_dir> || return
#       trap "baton_save_lock_release <handoff_dir>" EXIT
baton_save_lock_acquire() {
  local handoff_dir=$1
  local lock_dir="$handoff_dir/.save.lock"
  local timeout="${BATON_SAVE_LOCK_TIMEOUT:-30}"
  local elapsed=0
  while ! mkdir "$lock_dir" 2>/dev/null; do
    if [[ "$elapsed" -ge "$timeout" ]]; then
      # stale lock 감지 (10분 이상 → 무조건 강탈)
      local lock_age=0
      if [[ -d "$lock_dir" ]]; then
        local lock_mtime
        lock_mtime=$(stat -f %m "$lock_dir" 2>/dev/null || echo 0)
        lock_age=$(( $(date +%s) - lock_mtime ))
      fi
      if [[ "$lock_age" -gt 600 ]]; then
        echo "[baton] ⚠️  stale lock 감지(${lock_age}s) — 강제 해제" >&2
        rm -rf "$lock_dir"
        continue
      fi
      echo "[baton] ❌ save lock 획득 실패 (다른 save 진행 중) — ${timeout}s 초과" >&2
      return 1
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  echo "$$" > "$lock_dir/pid" 2>/dev/null || true
  return 0
}

baton_save_lock_release() {
  local handoff_dir=$1
  local lock_dir="$handoff_dir/.save.lock"
  rm -rf "$lock_dir" 2>/dev/null || true
}

# 4-template 일괄 초기화
baton_init_handoff() {
  local handoff_dir=$1
  local phase_id=$2
  local title="${3:-$phase_id}"
  local branch="${4:-$(git branch --show-current 2>/dev/null || echo unknown)}"
  local worktree="${5:-.}"
  local agent="${6:-claude-code}"
  mkdir -p "$handoff_dir"
  local sid
  sid=$(baton_session_id)
  local now
  now=$(baton_iso_now)
  local human
  human=$(baton_human_now)
  # v1.2.5+ — last_commit 초기 채움 (resume 가드용)
  # 워크트리에서 호출되면 그 워크트리 HEAD, main이면 main HEAD. 비-git 환경은 "—"
  local last_commit
  local git_dir="$worktree"
  [[ "$git_dir" == "." || -z "$git_dir" ]] && git_dir="$PWD"
  last_commit=$(git -C "$git_dir" rev-parse --short HEAD 2>/dev/null || echo "—")

  for tpl in PLAN JOURNAL CURRENT NEXT; do
    sed -e "s|{{SESSION_ID}}|$sid|g" \
        -e "s|{{PHASE_ID}}|$phase_id|g" \
        -e "s|{{PHASE_TITLE}}|$title|g" \
        -e "s|{{BRANCH}}|$branch|g" \
        -e "s|{{WORKTREE}}|$worktree|g" \
        -e "s|{{AGENT}}|$agent|g" \
        -e "s|{{STARTED_AT}}|$now|g" \
        -e "s|{{STARTED_AT_HUMAN}}|$human|g" \
        -e "s|{{LAST_HARNESS}}|null|g" \
        -e "s|{{LAST_COMMIT}}|$last_commit|g" \
        "$BATON_HOME/templates/${tpl}.md.template" > "$handoff_dir/${tpl}.md"
  done
}

# phase.json 초기화
baton_init_phase_json() {
  local target=$1
  local phase_id=$2
  local title="${3:-$phase_id}"
  local branch="${4:-$(git branch --show-current 2>/dev/null || echo unknown)}"
  local worktree="${5:-.}"
  local ports_json="${6:-{\}}"
  local now
  now=$(baton_iso_now)
  mkdir -p "$(dirname "$target")"
  sed -e "s|{{PHASE_ID}}|$phase_id|g" \
      -e "s|{{PHASE_TITLE}}|$title|g" \
      -e "s|{{BRANCH}}|$branch|g" \
      -e "s|{{WORKTREE}}|$worktree|g" \
      -e "s|{{PORTS_JSON}}|$ports_json|g" \
      -e "s|{{STARTED_AT}}|$now|g" \
      "$BATON_HOME/templates/phase.json.template" > "$target"
}

# CURRENT.md frontmatter 필드 읽기
baton_current_field() {
  local field=$1
  local current="${2:-./.baton/handoff/CURRENT.md}"
  [[ -f "$current" ]] || return 1
  awk -v f="$field" '
    /^---$/ { fm = !fm; next }
    fm && $0 ~ "^"f":" { sub("^"f":[[:space:]]*", ""); print; exit }
  ' "$current"
}

# CURRENT.md frontmatter 필드 갱신 (status, last_updated, last_harness)
baton_current_set() {
  local field=$1 value=$2
  local current="${3:-./.baton/handoff/CURRENT.md}"
  [[ -f "$current" ]] || return 1
  local tmp
  tmp=$(mktemp)
  awk -v f="$field" -v v="$value" '
    /^---$/ { fm = !fm; print; next }
    fm && $0 ~ "^"f":" { print f": "v; next }
    { print }
  ' "$current" > "$tmp"
  mv "$tmp" "$current"
}

# CURRENT.md status + last_updated 동시 갱신
baton_current_set_status() {
  local status=$1
  local current="${2:-./.baton/handoff/CURRENT.md}"
  baton_current_set status "$status" "$current"
  baton_current_set last_updated "$(baton_iso_now)" "$current"
}

# JOURNAL.md에 INTENT (사용자 입력) append (UserPromptSubmit 훅이 호출)
baton_journal_append_intent() {
  local intent=$1
  local journal="${2:-./.baton/handoff/JOURNAL.md}"
  [[ -f "$journal" ]] || return 1
  local human
  human=$(baton_human_now)
  cat >> "$journal" <<EOF

## $human — Turn $(baton_journal_next_turn "$journal")
- **INTENT**: $intent
- **HARNESS**: -
- **ACTIONS**: -
- **TODO**: -
EOF
}

# JOURNAL.md에 HARNESS 사용 추가 (PostToolUse 훅이 호출)
baton_journal_set_last_harness() {
  local harness=$1
  local journal="${2:-./.baton/handoff/JOURNAL.md}"
  [[ -f "$journal" ]] || return 1
  # 마지막 Turn의 HARNESS: - 라인을 갱신
  local tmp
  tmp=$(mktemp)
  awk -v h="$harness" '
    /^- \*\*HARNESS\*\*: -$/ { last=NR }
    { lines[NR]=$0 }
    END {
      for(i=1;i<=NR;i++) {
        if (i==last) print "- **HARNESS**: " h
        else print lines[i]
      }
    }
  ' "$journal" > "$tmp"
  mv "$tmp" "$journal"
  # CURRENT.md last_harness 도 갱신
  baton_current_set last_harness "$harness" "$(dirname "$journal")/CURRENT.md" 2>/dev/null || true
}

baton_journal_next_turn() {
  local journal=$1
  [[ -f "$journal" ]] || { echo 1; return; }
  local n
  n=$(grep -cE '^## .* — Turn ' "$journal" 2>/dev/null || echo 0)
  echo $((n + 1))
}

# /baton:resume — RESUME_MSG.md 우선, NEXT.md fallback
baton_handoff_resume() {
  local next="${1:-./.baton/handoff/NEXT.md}"
  local handoff_dir
  handoff_dir="$(dirname "$next")"
  local resume_msg="$handoff_dir/RESUME_MSG.md"

  local source=""
  if [[ -f "$resume_msg" ]]; then
    source="$resume_msg"
  elif [[ -f "$next" ]]; then
    source="$next"
  else
    echo "📌 일시정지된 핸드오프 없음 (NEXT.md 부재)"
    return 1
  fi
  echo "─────────────────────────────────────────"
  echo "📌 핸드오프 재개"
  echo "─────────────────────────────────────────"
  cat "$source"
  echo
  echo "─────────────────────────────────────────"
  echo "참고: PLAN.md 와 JOURNAL.md 도 확인하세요."
  return 0
}

# SessionStart 알림 (자동 주입 X)
baton_handoff_alert() {
  local current="${1:-./.baton/handoff/CURRENT.md}"
  [[ -f "$current" ]] || return 0
  local status phase branch agent updated last_harness
  status=$(baton_current_field status "$current")
  [[ "$status" != "paused" ]] && return 0
  phase=$(baton_current_field phase "$current")
  branch=$(baton_current_field branch "$current")
  agent=$(baton_current_field agent "$current")
  updated=$(baton_current_field last_updated "$current")
  last_harness=$(baton_current_field last_harness "$current")
  cat <<EOF
─────────────────────────────────────────
📌 일시정지된 페이즈가 있어요
  Phase: $phase (paused, by $agent)
  Branch: $branch
  Last updated: $updated
  Last harness: $last_harness

이어서: "이어서" / "진행" / "go" / "continue" / "next"
다른 작업: 무시하고 새 요청 입력
─────────────────────────────────────────
EOF
}

# v1.2.14+ — NEXT.md 히스토리 보존: save Step 1(LLM Write)이 덮어쓰기 전에
# 기존 NEXT.md를 next-archive/로 스냅샷. 라이브 NEXT.md는 건드리지 않음(복사만).
# 인자: handoff_dir (default ./.baton/handoff)
baton_next_snapshot_rotate() {
  local handoff_dir="${1:-./.baton/handoff}"
  local next="$handoff_dir/NEXT.md"
  [[ -s "$next" ]] || return 0   # 없거나 비어있으면 아카이브할 게 없음 — no-op
  local dir="$handoff_dir/next-archive"
  mkdir -p "$dir"
  local ts
  ts="$(date +%Y%m%d-%H%M%S)-$$"   # PID suffix — 같은 초 내 중복 save 시 타임스탬프 충돌(직전 스냅샷 덮어쓰기) 방지
  cp "$next" "$dir/NEXT-${ts}.md"
  # 20개 초과 시 오래된 것부터 정리(파일명이 타임스탬프라 정렬=시간순)
  local n
  n=$(ls "$dir"/NEXT-*.md 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$n" -gt 20 ]]; then
    ls "$dir"/NEXT-*.md | sort | head -n "$((n - 20))" | while read -r f; do rm -f "$f"; done
  fi
}

# ============================================================
# v1.2.5+ — RESUME_MSG.md 자동 생성 (≤500B hard cap)
# ============================================================
# 다음 세션 첫 입력으로 복붙할 시작 메시지를 handoff/RESUME_MSG.md에 작성.
# 본문은 fill-in 템플릿 (자유작문 금지), footer는 항상 bash가 채움.
#
# 사용 분기:
#   - bash-only (--skip-spawn, events=0, SessionEnd): baton_resume_msg_build
#   - LLM spawn 경로: LLM이 본문만 쓰고 baton_resume_msg_footer_append 호출

# v1.2.7+ — NEXT.md 전문 + footer (압축 없음)
# 호출 세션이 풀 컨텍스트로 작성한 NEXT.md를 그대로 사용.
# 인자: handoff_dir (default: ./.baton/handoff)
# stdout: 생성된 RESUME_MSG.md 경로
baton_resume_msg_build() {
  local handoff_dir="${1:-./.baton/handoff}"
  [[ -d "$handoff_dir" ]] || return 1

  local current="$handoff_dir/CURRENT.md"
  local next="$handoff_dir/NEXT.md"
  local out="$handoff_dir/RESUME_MSG.md"

  local branch worktree last_commit
  branch=$(baton_current_field branch "$current" 2>/dev/null)
  worktree=$(baton_current_field worktree "$current" 2>/dev/null)
  last_commit=$(baton_current_field last_commit "$current" 2>/dev/null)
  [[ -z "$branch" ]] && branch="?"
  [[ -z "$worktree" ]] && worktree="?"
  [[ -z "$last_commit" ]] && last_commit="—"

  local body=""
  if [[ -f "$next" ]]; then
    body=$(cat "$next")
  else
    local phase
    phase=$(baton_current_field phase "$current" 2>/dev/null)
    [[ -z "$phase" ]] && phase="?"
    body="${phase} 이어서. NEXT.md 읽고 시작."
  fi

  local footer=$'\n\n---\nworktree: '"$worktree"$'\nbranch: '"$branch"$'\ncommit: '"$last_commit"

  printf '%s%s\n' "$body" "$footer" > "$out"
  echo "$out"
}

# LLM 경로용 footer 보강 — LLM이 본문만 쓴 RESUME_MSG.md에 footer append
# idempotent: 이미 footer 있으면 skip
baton_resume_msg_footer_append() {
  local handoff_dir="${1:-./.baton/handoff}"
  local out="$handoff_dir/RESUME_MSG.md"
  local current="$handoff_dir/CURRENT.md"
  [[ -f "$out" && -f "$current" ]] || return 1

  # 이미 footer 있으면 skip
  grep -qE '^worktree:[[:space:]]' "$out" 2>/dev/null && return 0

  local branch worktree last_commit
  branch=$(baton_current_field branch "$current" 2>/dev/null)
  worktree=$(baton_current_field worktree "$current" 2>/dev/null)
  last_commit=$(baton_current_field last_commit "$current" 2>/dev/null)
  [[ -z "$branch" ]] && branch="?"
  [[ -z "$worktree" ]] && worktree="?"
  [[ -z "$last_commit" ]] && last_commit="—"

  {
    # 마지막 라인 newline 보장
    [[ -s "$out" ]] && tail -c1 "$out" | read -r _ || echo
    echo "---"
    echo "worktree: $worktree"
    echo "branch: $branch"
    echo "commit: $last_commit"
  } >> "$out"

  # hard cap 500B 사후 보정: 초과 시 bash-only 빌더로 재생성 (LLM 본문 폐기)
  local size
  size=$(wc -c < "$out" 2>/dev/null | tr -d ' ')
  if [[ "${size:-0}" -gt 500 ]]; then
    baton_resume_msg_build "$handoff_dir" >/dev/null
  fi
}

# 박스 출력 (save/SessionEnd 마무리)
baton_resume_msg_print() {
  local handoff_dir="${1:-./.baton/handoff}"
  local out="$handoff_dir/RESUME_MSG.md"
  [[ -f "$out" ]] || return 1
  echo "═════ 📋 다음 세션 시작 메시지 (복사용) ═════"
  cat "$out"
  echo
  echo "════════════════════════════════════════════"
  echo "  → 위 메시지를 다음 세션 첫 입력에 복붙하세요."
  echo "  → 파일: $out"
}
