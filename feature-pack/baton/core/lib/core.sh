#!/usr/bin/env bash
# baton lib/core.sh — 명령 디스패처 + 옵션 B 가드 + 워크트리 lifecycle

set -euo pipefail

BATON_HOME="${BATON_HOME:-$HOME/.baton/current}"

. "$BATON_HOME/lib/version.sh"
. "$BATON_HOME/lib/ports.sh"
. "$BATON_HOME/lib/handoff.sh"
. "$BATON_HOME/lib/archive.sh"
. "$BATON_HOME/lib/archive_search.sh"
. "$BATON_HOME/lib/harnesses.sh"
. "$BATON_HOME/lib/verify.sh"
. "$BATON_HOME/lib/tmux.sh"


baton_detect_agent() {
  if [[ -n "${BATON_AGENT:-}" ]]; then
    echo "$BATON_AGENT"
  elif [[ -n "${CODEX_THREAD_ID:-}" || -n "${CODEX_CI:-}" || -n "${CODEX_MANAGED_BY_NPM:-}" || -n "${OMX_SESSION_ID:-}" ]]; then
    echo "codex"
  elif [[ -n "${CLAUDECODE:-}" || -n "${CLAUDE_CODE_SESSION_ID:-}" || -n "${CLAUDE_SESSION_ID:-}" ]]; then
    echo "claude-code"
  else
    echo "claude-code"
  fi
}

baton_runtime_execution_hint() {
  local agent
  agent=$(baton_detect_agent)
  case "$agent" in
    codex)
      if [[ -n "${OMX_SESSION_ID:-}" ]] || command -v omx >/dev/null 2>&1; then
        echo '$autopilot (OMX/Codex) 또는 codex exec'
      else
        echo 'codex exec'
      fi
      ;;
    claude-code)
      echo '/oh-my-claudecode:autopilot 또는 claude'
      ;;
    gemini)
      echo 'gemini 또는 gemini -p'
      ;;
    *)
      echo 'claude, codex exec, gemini 등 현재 에이전트 런타임'
      ;;
  esac
}

baton_runtime_verify_hint() {
  local agent
  agent=$(baton_detect_agent)
  case "$agent" in
    codex)
      if [[ -n "${OMX_SESSION_ID:-}" ]] || command -v omx >/dev/null 2>&1; then
        echo '$code-review 또는 $ultraqa (OMX/Codex)'
      else
        echo 'codex 기반 테스트/리뷰 명령'
      fi
      ;;
    claude-code)
      echo '/oh-my-claudecode:verify 또는 /oh-my-claudecode:critic'
      ;;
    *)
      echo '현재 에이전트의 verify/review 하네스'
      ;;
  esac
}

# === 프로젝트 root 찾기 — main worktree 항상 반환 ===
# linked worktree에서 호출해도 main worktree 경로 반환 (archive 위치 일관성).
baton_project_root() {
  # 1순위: git worktree list --porcelain 첫 entry = main worktree
  local main_root
  main_root=$(git worktree list --porcelain 2>/dev/null | awk '/^worktree / {print $2; exit}')
  if [[ -n "$main_root" && -d "$main_root" ]]; then
    echo "$main_root"
    return
  fi
  # fallback: 부모 방향으로 .baton/config.json 또는 .git 찾기 (git 환경 외)
  local d="$PWD"
  while [[ "$d" != "/" ]]; do
    [[ -f "$d/.baton/config.json" ]] && { echo "$d"; return; }
    [[ -d "$d/.git" || -f "$d/.git" ]] && { echo "$d"; return; }
    d=$(dirname "$d")
  done
  echo "$PWD"
}

# 워크트리에서 호출되면 그 워크트리 root, main이면 project root
baton_active_root() {
  local d="$PWD"
  while [[ "$d" != "/" ]]; do
    [[ -d "$d/.baton/handoff" ]] && { echo "$d"; return; }
    d=$(dirname "$d")
  done
  baton_project_root
}

# === 프로젝트 .baton/ 초기화 ===
baton_init_project() {
  local root="${1:-$(baton_project_root)}"
  mkdir -p "$root/.baton/archive"
  if [[ ! -f "$root/.baton/config.json" ]]; then
    local proj
    proj=$(basename "$root")
    sed "s|{{PROJECT_NAME}}|$proj|g" \
      "$BATON_HOME/templates/config.json.template" > "$root/.baton/config.json"
    echo "✓ .baton/config.json 생성"
  fi
  if [[ ! -f "$root/.baton/version.lock" ]]; then
    baton_write_version_lock "$root/.baton/version.lock"
    echo "✓ .baton/version.lock 생성"
  fi
}

# === /baton:plan ===
baton_cmd_plan() {
  baton_guard_main_root plan || return 1
  local phase_id="${1:-}"
  local root
  root=$(baton_active_root)

  # phase.json 없으면 wt-create 안 거치고 워크트리 진입한 케이스 — stub 생성
  if [[ ! -f "$root/.baton/phase.json" ]]; then
    if [[ -z "$phase_id" ]]; then
      echo "사용법: /baton:plan <phase-id> [title]"
      echo "  (phase.json 미존재. /baton:wt-create 안 거쳤다면 phase-id 필수)"
      return 1
    fi
    local title="${2:-$phase_id}"
    baton_init_phase_json "$root/.baton/phase.json" "$phase_id" "$title"
    [[ ! -d "$root/.baton/handoff" ]] && baton_init_handoff "$root/.baton/handoff" "$phase_id" "$title" \
      "$(git -C "$root" branch --show-current 2>/dev/null || echo unknown)" "$root" \
      "$(baton_detect_agent)"
    echo "✓ phase.json + 4-template 생성: $phase_id"
  else
    # 이미 활성 phase — 그대로 통과
    local existing
    existing=$(jq -r '.phase_id' "$root/.baton/phase.json" 2>/dev/null)
    echo "📌 활성 phase: $existing (그대로 사용)"
  fi

  echo

  # PLAN.md 상태로 분기
  local plan_md="$root/.baton/handoff/PLAN.md"
  local has_real_plan=false
  if [[ -f "$plan_md" ]]; then
    # stub은 "Plan v0 (stub)" 만 있고 실제 내용 없음
    if grep -qE '^## .* — Plan v[1-9]' "$plan_md" 2>/dev/null; then
      has_real_plan=true
    fi
  fi

  if $has_real_plan; then
    echo "✓ PLAN.md 에 이미 작성된 plan 있음:"
    grep -E '^## ' "$plan_md" | head -5 | sed 's/^/    /'
    echo
    echo "다음 plan 추가 작성하려면 외부 하네스 다시 호출:"
  else
    echo "📝 PLAN.md 비어 있음 (stub). 외부 하네스로 채우세요:"
  fi
  echo
  baton_plan_recommend "$root/.baton/config.json" || true
  echo
  baton_tmux_attach_hint
}

# === /baton:wt-create ===
baton_cmd_wt_create() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    echo "사용법: /baton:wt-create <name>"
    return 1
  fi
  local root
  root=$(baton_project_root)
  baton_init_project "$root"
  local branch="feat/$name"
  local wt_dir="$root/.worktrees/$name"
  if [[ -d "$wt_dir" ]]; then
    echo "❌ 이미 존재: $wt_dir" >&2
    return 1
  fi
  local idx
  idx=$(baton_next_worktree_index "$root")
  if git -C "$root" rev-parse --verify "$branch" >/dev/null 2>&1; then
    git -C "$root" worktree add "$wt_dir" "$branch"
  else
    git -C "$root" worktree add -b "$branch" "$wt_dir"
  fi
  local now
  now=$(date +"%Y-%m-%d")
  cat > "$wt_dir/.worktree-info.json" <<EOF
{
  "branch": "$branch",
  "created_at": "$now",
  "purpose": "$name",
  "index": $idx
}
EOF
  mkdir -p "$wt_dir/.baton/handoff"
  ln -sf "$root/.baton/config.json" "$wt_dir/.baton/config.json"
  ln -sf "$root/.baton/version.lock" "$wt_dir/.baton/version.lock"
  ln -sf "$root/.baton/archive" "$wt_dir/.baton/archive"

  # 심링
  local cfg="$root/.baton/config.json"
  local links
  links=$(jq -r '.shared_links[]?' "$cfg" 2>/dev/null)
  for l in $links; do
    if [[ -e "$root/$l" && ! -e "$wt_dir/$l" ]]; then
      ln -s "$root/$l" "$wt_dir/$l"
    fi
  done

  # 포트
  baton_write_worktree_env "$wt_dir" "$idx" "$cfg"
  local ports_json
  ports_json=$(baton_ports_json_from_env "$wt_dir/.env.worktree")

  # phase.json 이전 또는 stub
  if [[ -f "$root/.baton/phase.json" ]]; then
    mv "$root/.baton/phase.json" "$wt_dir/.baton/phase.json"
    jq --argjson ports "$ports_json" --arg branch "$branch" --arg worktree ".worktrees/$name" \
      '.ports = $ports | .branch = $branch | .worktree = $worktree' \
      "$wt_dir/.baton/phase.json" > "$wt_dir/.baton/phase.json.tmp"
    mv "$wt_dir/.baton/phase.json.tmp" "$wt_dir/.baton/phase.json"
    [[ -d "$root/.baton/handoff" ]] && {
      cp -r "$root/.baton/handoff/." "$wt_dir/.baton/handoff/"
      rm -rf "$root/.baton/handoff"
    }
  else
    baton_init_phase_json "$wt_dir/.baton/phase.json" "$name" "$name" "$branch" ".worktrees/$name" "$ports_json"
    baton_init_handoff "$wt_dir/.baton/handoff" "$name" "$name" "$branch" \
      ".worktrees/$name" "$(baton_detect_agent)"
  fi

  # gitignore 추가
  cat "$BATON_HOME/templates/.gitignore.template" > "$wt_dir/.baton/.gitignore"

  echo "✓ 워크트리 생성: $wt_dir"
  echo "  Branch: $branch"
  echo "  Index: $idx"
  echo "  Ports:"
  grep _PORT= "$wt_dir/.env.worktree" | sed 's/^/    /'
  echo

  # tmux 통합 (v1.2: default 표준 — tmux 설치되어 있으면 자동)
  if baton_tmux_enabled; then
    baton_tmux_create_session "$name" "$wt_dir"
    echo
    echo "다음: tmux attach -t $(baton_tmux_session_name "$name")"
    echo "       (또는 cd $wt_dir 직접)"
  else
    echo "다음: cd $wt_dir"
    echo "       그 후 작업 시작 (예: $(baton_runtime_execution_hint))"
    if ! command -v tmux >/dev/null 2>&1; then
      echo "       💡 tmux 표준 권장: brew install tmux (또는 apt install tmux)"
    fi
  fi
}

# === /baton:save (v1.2.4+ — race-free snapshot pipeline) ===
# 흐름:
#   1. lock 획득 (동시 save 차단)
#   2. .events.jsonl → .events.snapshot-*.jsonl 선 rotate (atomic)
#   3. spawn 중 새 hook event는 새 .events.jsonl에 적재됨 (다음 save가 처리)
#   4. spawn에 snapshot 경로 전달 → JOURNAL/CURRENT/NEXT 정리
#   5. 성공 → snapshot → .processed-*. 실패 → snapshot → .failed-* (raw 보존)
#   6. lock 해제
baton_cmd_save() {
  local skip_spawn=false
  for a in "$@"; do
    [[ "$a" == "--skip-spawn" ]] && skip_spawn=true
  done

  baton_guard_main_root save || return 1
  local root
  root=$(baton_active_root)
  local handoff_dir="$root/.baton/handoff"
  local current="$handoff_dir/CURRENT.md"
  local events_file="$handoff_dir/.events.jsonl"

  [[ -f "$current" ]] || {
    echo "❌ CURRENT.md 없음. /baton:wt-create 또는 /baton:plan 먼저"
    return 1
  }

  # status → paused (frontmatter만 — 워크트리 lock 안전)
  baton_current_set_status paused "$current"
  # v1.2.5+ — last_commit 갱신 (resume 가드 mismatch 비교용)
  local _save_last_commit
  _save_last_commit=$(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo "—")
  baton_current_set last_commit "$_save_last_commit" "$current"
  echo "✓ status → paused, last_updated/last_commit 갱신"

  # sidecar 이벤트 없으면 종료 (RESUME_MSG.md만 갱신)
  if [[ ! -s "$events_file" ]]; then
    echo "✓ 미처리 이벤트 없음 — 메타데이터만 갱신"
    baton_resume_msg_build "$handoff_dir" >/dev/null 2>&1 \
      && { echo; baton_resume_msg_print "$handoff_dir"; }
    baton_tmux_attach_hint
    return 0
  fi

  local event_count
  event_count=$(wc -l < "$events_file" 2>/dev/null | tr -d ' ' || echo 0)
  echo "  미처리 이벤트: ${event_count}개 (.events.jsonl)"

  if $skip_spawn; then
    echo "  --skip-spawn 지정됨 — 헤드리스 정리 skip (events 보존)"
    # bash-only 경로: RESUME_MSG.md 빌더 호출
    baton_resume_msg_build "$handoff_dir" >/dev/null 2>&1 \
      && { echo; baton_resume_msg_print "$handoff_dir"; }
    baton_tmux_attach_hint
    return 0
  fi

  # ── (1) save lock 획득 — 동시 save 방지 ──
  if ! baton_save_lock_acquire "$handoff_dir"; then
    echo "  ⚠️  save 동시 실행 방지: 다른 save 완료 대기 후 재시도하세요."
    return 2
  fi
  # 단순 trap (spawn 중 SIGINT시 lock 해제 보장)
  trap "baton_save_lock_release '$handoff_dir'; trap - INT TERM EXIT" INT TERM EXIT

  # ── (2) 선 rotate snapshot — race 원천 차단 ──
  local snapshot
  snapshot=$(baton_events_snapshot_for_save "$handoff_dir")
  if [[ -z "$snapshot" || ! -s "$snapshot" ]]; then
    echo "  ⚠️  snapshot 생성 실패 — abort"
    baton_save_lock_release "$handoff_dir"; trap - INT TERM EXIT
    return 1
  fi
  echo "  📸 snapshot: $(basename "$snapshot") (${event_count} events)"

  # ── (3-4) spawn ──
  local spawn_rc=0
  if baton_save_spawn_agent "$root" "$snapshot"; then
    # ── (5a) 성공: snapshot → processed ──
    local processed
    processed=$(baton_events_processed_finalize "$handoff_dir" "$snapshot" "processed")
    if [[ -n "$processed" ]]; then
      echo "✓ 컨텍스트 정리 완료 → $(basename "$processed")"
    else
      echo "✓ 컨텍스트 정리 완료 (processed 회전 경고)"
    fi
    # v1.2.5+ — LLM이 본문 작성한 RESUME_MSG.md에 footer append (없으면 bash-only로 fallback)
    if [[ -f "$handoff_dir/RESUME_MSG.md" ]]; then
      baton_resume_msg_footer_append "$handoff_dir" || true
    else
      baton_resume_msg_build "$handoff_dir" >/dev/null 2>&1 || true
    fi
  else
    # ── (5b) 실패: fallback dump 시도 → snapshot → failed (raw 보존) ──
    spawn_rc=1
    if baton_save_fallback_dump "$root" "$snapshot"; then
      local processed
      processed=$(baton_events_processed_finalize "$handoff_dir" "$snapshot" "processed")
      [[ -n "$processed" ]] && echo "  ✓ fallback 성공 → $(basename "$processed")"
    else
      local failed
      failed=$(baton_events_processed_finalize "$handoff_dir" "$snapshot" "failed")
      [[ -n "$failed" ]] && echo "  ⚠️  fallback 실패 — events 보존: $(basename "$failed")"
    fi
    # v1.2.5+ — spawn 실패 경로도 bash-only RESUME_MSG.md 생성
    baton_resume_msg_build "$handoff_dir" >/dev/null 2>&1 || true
  fi

  # ── (6) lock 해제 ──
  baton_save_lock_release "$handoff_dir"
  trap - INT TERM EXIT

  echo
  baton_resume_msg_print "$handoff_dir" 2>/dev/null || true
  baton_tmux_attach_hint
  return 0
}

# baton_events_processed_finalize는 lib/handoff.sh로 이동됨 (1.2.4)

# 헤드리스 에이전트 자동 감지 (BATON_SAVE_AGENT 환경변수 우선)
baton_save_detect_agent() {
  if [[ -n "${BATON_SAVE_AGENT:-}" ]]; then
    echo "$BATON_SAVE_AGENT"
    return
  fi
  # 현 환경 우선 — Claude Code 안이면 claude, OMX/Codex면 codex
  if [[ -n "${CLAUDECODE:-}" ]] && command -v claude >/dev/null 2>&1; then
    echo claude
  elif [[ -n "${CODEX_THREAD_ID:-}${OMX_SESSION_ID:-}" ]] && command -v codex >/dev/null 2>&1; then
    echo codex
  elif command -v codex >/dev/null 2>&1; then
    echo codex
  elif command -v claude >/dev/null 2>&1; then
    echo claude
  elif command -v opencode >/dev/null 2>&1; then
    echo opencode
  elif command -v gemini >/dev/null 2>&1; then
    echo gemini
  else
    echo none
  fi
}

# 헤드리스 spawn — return 0 성공, 1 실패
# 인자: root, snapshot_path
baton_save_spawn_agent() {
  local root=$1
  local snapshot="${2:-}"
  local agent
  agent=$(baton_save_detect_agent)
  [[ "$agent" == "none" ]] && {
    echo "  ⚠️  헤드리스 에이전트 미발견 (claude/codex/gemini/opencode)"
    return 1
  }

  local prompt_template="$BATON_HOME/templates/save-prompt.md.template"
  [[ -f "$prompt_template" ]] || {
    echo "  ⚠️  save-prompt.md.template 없음 — fallback"
    return 1
  }

  local handoff_dir="$root/.baton/handoff"
  local prompt
  # snapshot이 있으면 snapshot 경로를 input으로, 없으면 .events.jsonl (legacy 호환)
  local input_path="${snapshot:-$handoff_dir/.events.jsonl}"
  prompt=$(sed \
    -e "s|{{HANDOFF_DIR}}|$handoff_dir|g" \
    -e "s|{{SNAPSHOT_FILE}}|$input_path|g" \
    "$prompt_template")

  echo "  🤖 ${agent} 헤드리스 정리 시작..."
  local log_file="$handoff_dir/.save.log"
  local rc=0

  case "$agent" in
    claude)
      # --bare 제거: OAuth/keychain 인증 거부함 → 일반 사용자 로그인 안 먹음
      # baton hook은 BATON_SKIP_HOOKS=1로 차단. 다른 hook은 race 무관 (자기 read→edit)
      # </dev/null: prompt를 인자로 주는데 stdin 대기로 멈추는 현상 방지
      BATON_SKIP_HOOKS=1 claude -p "$prompt" \
        --dangerously-skip-permissions \
        --output-format text \
        </dev/null \
        2>>"$log_file" >>"$log_file" || rc=$?
      ;;
    codex)
      BATON_SKIP_HOOKS=1 codex exec \
        --skip-git-repo-check \
        --dangerously-bypass-approvals-and-sandbox \
        -C "$root" \
        --ephemeral \
        "$prompt" </dev/null 2>>"$log_file" >>"$log_file" || rc=$?
      ;;
    gemini)
      BATON_SKIP_HOOKS=1 gemini -p "$prompt" --yolo \
        </dev/null 2>>"$log_file" >>"$log_file" || rc=$?
      ;;
    opencode)
      BATON_SKIP_HOOKS=1 opencode run --pure "$prompt" \
        </dev/null 2>>"$log_file" >>"$log_file" || rc=$?
      ;;
    *)
      echo "  ⚠️  알 수 없는 에이전트: $agent"
      return 1
      ;;
  esac

  if [[ "$rc" -ne 0 ]]; then
    echo "  ⚠️  ${agent} spawn 실패 (rc=$rc) — 로그: $log_file"
    return 1
  fi
  echo "  ✓ ${agent} 정리 완료"
  return 0
}

# LLM spawn 실패 시 jq로 raw dump
# 인자: root, events_file (default: snapshot path 또는 .events.jsonl)
# return: 0 성공, 1 실패 (caller가 .failed-* 회전 결정)
baton_save_fallback_dump() {
  local root=$1
  local events="${2:-$root/.baton/handoff/.events.jsonl}"
  local handoff_dir="$root/.baton/handoff"
  local journal="$handoff_dir/JOURNAL.md"
  [[ -f "$events" ]] || { echo "  ⚠️  fallback: events 파일 없음 ($events)"; return 1; }
  [[ -f "$journal" ]] || { echo "  ⚠️  fallback: JOURNAL.md 없음"; return 1; }
  command -v jq >/dev/null 2>&1 || { echo "  ⚠️  fallback: jq 미설치"; return 1; }

  echo "  ⚙️  fallback: jq raw dump"
  local ts
  ts=$(baton_human_now)
  # atomic write: tmp에 쓴 후 mv
  local tmp_journal
  tmp_journal=$(mktemp "${TMPDIR:-/tmp}/baton-journal.XXXXXX") || return 1
  cp "$journal" "$tmp_journal" || { rm -f "$tmp_journal"; return 1; }
  {
    echo
    echo "## ${ts} — Fallback dump (LLM spawn 실패, raw events)"
    echo "- **INTENT** (사용자 발화 ≤10):"
    jq -r 'select(.type=="intent") | "  - " + (.text // "?")' < "$events" 2>/dev/null | head -10
    echo "- **HARNESS** (외부 하네스 ≤10):"
    jq -r 'select(.type=="harness") | "  - " + (.name // "?")' < "$events" 2>/dev/null | sort -u | head -10
    echo "- **ACTIONS**: -"
    echo "- **TODO**: 다음 세션에서 /baton:save 재시도 권장"
  } >> "$tmp_journal" || { rm -f "$tmp_journal"; return 1; }
  mv "$tmp_journal" "$journal" 2>/dev/null || { rm -f "$tmp_journal"; return 1; }
  return 0
}

# === /baton:resume (v1.2.5+ — 4분류 가드 강화) ===
# 분류:
#   match         — 워크트리 + commit 일치 → 기존 동작
#   commit_only   — 해시만 다름 (main에 새 커밋 머지 등) → INFO + 1s wait + 자동 진행
#   worktree_only — 다른 워크트리 → TTY [y/N] / non-TTY mismatch info stdout + NEXT.md
#   both          — 둘 다 다름 → TTY [y/N] / non-TTY mismatch info stdout + NEXT.md
# Hard abort:
#   /tmp/baton-extracted/* 경로 (archive extract) — --force로도 우회 불가
baton_cmd_resume() {
  local force=false
  for a in "$@"; do
    [[ "$a" == "--force" ]] && force=true
  done

  # ── 1. archive extract 경로 hard abort (force로도 우회 불가) ──
  # macOS의 /tmp는 /private/tmp 심링크 → pwd -P 가 /private/tmp/... 반환.
  # /tmp 와 */baton-extracted/* 둘 다 매치.
  local pwd_real
  pwd_real=$(cd "$PWD" 2>/dev/null && pwd -P || echo "$PWD")
  if [[ "$pwd_real" == */baton-extracted/* || "$PWD" == /tmp/baton-extracted/* ]]; then
    cat >&2 <<EOF
🚨 archive extract 경로에서 resume 금지: $pwd_real
   archive extract는 읽기 전용 검토 용도입니다.
   이어서 작업하려면 /baton:wt-create 로 새 워크트리를 만드세요.
EOF
    return 1
  fi

  baton_guard_main_root resume || return 1
  local root
  root=$(baton_active_root)
  local current="$root/.baton/handoff/CURRENT.md"
  local next="$root/.baton/handoff/NEXT.md"

  # CURRENT.md 없으면 NEXT.md만 출력 (구버전 호환)
  if [[ ! -f "$current" ]]; then
    baton_handoff_resume "$next"
    echo
    baton_tmux_attach_hint
    return 0
  fi

  # ── 2. frontmatter 읽기 + legacy 빈 값 silent 백필 ──
  local saved_worktree saved_commit
  saved_worktree=$(baton_current_field worktree "$current" 2>/dev/null)
  saved_commit=$(baton_current_field last_commit "$current" 2>/dev/null)

  local main_root
  main_root=$(baton_project_root)

  if [[ -z "$saved_worktree" || "$saved_worktree" == "null" ]]; then
    if [[ -n "$main_root" && "$root" == "$main_root"* && "$root" != "$main_root" ]]; then
      saved_worktree="${root#$main_root/}"
    else
      saved_worktree="."
    fi
    baton_current_set worktree "$saved_worktree" "$current" 2>/dev/null || true
  fi

  if [[ -z "$saved_commit" || "$saved_commit" == "—" || "$saved_commit" == "null" ]]; then
    saved_commit=$(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo "—")
    if grep -q "^last_commit:" "$current" 2>/dev/null; then
      baton_current_set last_commit "$saved_commit" "$current" 2>/dev/null || true
    else
      local _tmp
      _tmp=$(mktemp)
      awk -v lc="$saved_commit" '
        /^---$/ { fm = !fm; print; next }
        fm && /^last_harness:/ { print; print "last_commit: " lc; next }
        { print }
      ' "$current" > "$_tmp" && mv "$_tmp" "$current"
    fi
  fi

  # ── 3. realpath 정규화 ──
  local current_real expected_real
  current_real=$(cd "$root" 2>/dev/null && pwd -P || echo "$root")
  if [[ "$saved_worktree" == /* ]]; then
    expected_real=$(cd "$saved_worktree" 2>/dev/null && pwd -P || echo "$saved_worktree")
  elif [[ "$saved_worktree" == "." || -z "$saved_worktree" ]]; then
    expected_real=$(cd "$main_root" 2>/dev/null && pwd -P || echo "$main_root")
  else
    expected_real=$(cd "$main_root/$saved_worktree" 2>/dev/null && pwd -P \
      || echo "$main_root/$saved_worktree")
  fi

  local current_commit
  current_commit=$(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo "—")

  # ── 4. 4분류 ──
  local wt_match=true commit_match=true
  if [[ "$current_real" != "$expected_real" ]]; then
    # basename 이중 체크 (path 정규화 차이 흡수)
    if [[ "$(basename "$current_real")" != "$(basename "$expected_real")" ]]; then
      wt_match=false
    fi
  fi
  if [[ "$saved_commit" != "—" && "$current_commit" != "—" \
        && "$saved_commit" != "$current_commit" ]]; then
    commit_match=false
  fi

  local kind="match"
  if   $wt_match     && ! $commit_match; then kind="commit_only"
  elif ! $wt_match   && $commit_match;   then kind="worktree_only"
  elif ! $wt_match   && ! $commit_match; then kind="both"
  fi
  $force && kind="match"

  case "$kind" in
    match)
      ;;
    commit_only)
      cat >&2 <<EOF
ℹ️  commit hash가 달라요 (저장: $saved_commit → 현재: $current_commit)
   main에 새 커밋이 머지됐을 가능성. 1초 후 자동 진행...
EOF
      sleep 1
      ;;
    worktree_only|both)
      local kind_label="워크트리 경로 mismatch"
      [[ "$kind" == "both" ]] && kind_label="워크트리 + commit 모두 mismatch"
      cat >&2 <<EOF
⚠️  $kind_label
   저장: $expected_real ($saved_commit)
   현재: $current_real ($current_commit)
   다른 워크트리에서 resume 시도 중일 수 있음.
EOF
      if [[ -t 0 ]]; then
        local ans
        read -r -p "  계속 진행할까요? [y/N] " ans
        if [[ ! "${ans:-N}" =~ ^[Yy]$ ]]; then
          echo "  취소됨. --force 로 우회 가능." >&2
          return 1
        fi
      else
        # non-TTY: abort 대신 mismatch info stdout + NEXT.md (LLM이 사용자 확인)
        cat <<EOF
[baton-resume-mismatch] kind=$kind saved_worktree=$expected_real saved_commit=$saved_commit current_worktree=$current_real current_commit=$current_commit
EOF
      fi
      ;;
  esac

  baton_handoff_resume "$next"
  echo
  baton_tmux_attach_hint
}

# === /baton:status ===
baton_cmd_status() {
  local root
  root=$(baton_active_root)
  echo "─────────────────────────────────────────"
  echo "📊 baton status — $root"
  echo "─────────────────────────────────────────"
  if [[ -f "$root/.baton/phase.json" ]] && command -v jq >/dev/null; then
    jq -r '"  Phase: \(.phase_id) — \(.title)\n  Branch: \(.branch)\n  Worktree: \(.worktree)\n  Started: \(.started_at)\n  Sessions: \(.sessions | length)"' "$root/.baton/phase.json"
  else
    echo "  (활성 phase.json 없음)"
  fi
  if [[ -f "$root/.baton/handoff/CURRENT.md" ]]; then
    echo
    local s a u h
    s=$(baton_current_field status "$root/.baton/handoff/CURRENT.md")
    a=$(baton_current_field agent "$root/.baton/handoff/CURRENT.md")
    u=$(baton_current_field last_updated "$root/.baton/handoff/CURRENT.md")
    h=$(baton_current_field last_harness "$root/.baton/handoff/CURRENT.md")
    echo "  Handoff: $s (by $a, $u)"
    echo "  Last harness: $h"
  fi
  # main root에서 호출되면 활성 워크트리 목록 + tmux 세션 정보
  if baton_is_main_root "$PWD"; then
    echo
    echo "  활성 워크트리:"
    if [[ -d "$root/.worktrees" ]]; then
      for wt in "$root/.worktrees"/*; do
        [[ -d "$wt" ]] || continue
        local wb tmux_suffix
        wb=$(git -C "$wt" branch --show-current 2>/dev/null)
        tmux_suffix=$(baton_tmux_status_suffix "$(basename "$wt")")
        echo "    - $(basename "$wt") ($wb)$tmux_suffix"
      done
    else
      echo "    (없음)"
    fi
    if baton_tmux_enabled; then
      echo
      echo "  tmux 통합: ✓ enabled (default — v1.2 표준)"
    fi
  fi
  baton_archive_lazy_prune 7 || true
}

# === /baton:wt-clean ===
baton_cmd_wt_clean() {
  local target=""
  local merged_only=false
  # --skip-save 옵션 처리 (finish가 이미 save 한 경우)
  for a in "$@"; do
    case "$a" in
      --merged)    merged_only=true ;;
      --skip-save) export BATON_WT_CLEAN_SKIP_SAVE=1 ;;
      *) [[ -z "$target" ]] && target="$a" ;;
    esac
  done
  local root
  root=$(baton_project_root)
  if $merged_only; then
    for wt in "$root/.worktrees"/*; do
      [[ -d "$wt" ]] || continue
      for mb in main master; do
        if git -C "$wt" merge-base --is-ancestor HEAD "$mb" 2>/dev/null; then
          baton_wt_clean_one "$wt" "$root"; break
        fi
      done
    done
    return
  fi
  [[ -z "$target" ]] && target="$PWD"
  # 인자 정규화: 절대경로 아니면 .worktrees/<name>/ 으로 자동 매핑
  if [[ "$target" != /* ]]; then
    if [[ "$target" == .worktrees/* ]]; then
      target="$root/$target"
    elif [[ -d "$root/.worktrees/$target" ]]; then
      target="$root/.worktrees/$target"
    fi
  fi
  # cwd 무효화 방지: archive_create 호출 전에 main worktree로 이동
  cd "$root"

  # tmux 세션 감지 시 사용자에게 묻기
  if baton_tmux_enabled; then
    local phase_id_for_tmux
    phase_id_for_tmux=$(basename "$target")
    local tmux_session
    tmux_session=$(baton_tmux_session_name "$phase_id_for_tmux")
    if baton_tmux_session_exists "$tmux_session"; then
      echo
      echo "⚠️  tmux 세션 활성: $tmux_session"
      read -r -p "  세션 종료할까요? [y/N] " ans
      if [[ "${ans:-N}" =~ ^[Yy]$ ]]; then
        baton_tmux_kill_session "$tmux_session"
      else
        echo "  세션 보존. 수동 종료: tmux kill-session -t $tmux_session"
      fi
      echo
    fi
  fi

  baton_wt_clean_one "$target" "$root"
  baton_archive_prune 30 false
}

baton_wt_clean_one() {
  local wt_path=$1 root=$2
  # 안전장치: 호출 시점에 cwd 가 wt_path 안이면 root 로 탈출 (archive 생성 시 git 명령 안전)
  case "$PWD" in
    "$wt_path"|"$wt_path"/*) cd "$root" ;;
  esac

  # archive 직전 fallback save (finish 안 거친 워크트리 대비)
  # 이미 finish가 save를 호출했다면 events.jsonl이 비어 있어 immediate skip.
  if [[ "${BATON_WT_CLEAN_SKIP_SAVE:-0}" != "1" && -d "$wt_path/.baton/handoff" ]]; then
    local _ev_count
    _ev_count=$(baton_events_count "$wt_path/.baton/handoff")
    if [[ "${_ev_count:-0}" -gt 0 ]]; then
      echo "📝 archive 전 sidecar 정리 (${_ev_count} events)..."
      ( cd "$wt_path" && baton_cmd_save ) || echo "  ⚠️  save 실패 — 그대로 archive"
      echo
    fi
  fi

  local branch
  branch=$(git -C "$wt_path" branch --show-current 2>/dev/null || echo "unknown")
  echo "─────────────────────────────────────────"
  echo "🗄️  워크트리 정리 — Archive 자동 보관"
  echo "─────────────────────────────────────────"
  echo "대상: $wt_path"
  echo "브랜치: $branch"
  local merged_status="✗ 미머지"
  for mb in main master; do
    if git -C "$wt_path" merge-base --is-ancestor HEAD "$mb" 2>/dev/null; then
      merged_status="✓ $mb 머지됨"; break
    fi
  done
  echo "머지 상태: $merged_status"
  echo
  echo "📦 아카이브 생성 중..."
  local archive_file
  archive_file=$(baton_archive_create "$wt_path" "")
  echo "📍 위치: $archive_file"
  echo "⏳ 보관: 30일"
  echo "🔍 검색: /baton:archive search [keyword]"
  echo
  echo "🗑️  워크트리 삭제..."
  git -C "$root" worktree remove --force "$wt_path"
  echo "✓ 정리 완료"
}

# === /baton:finish ===
baton_cmd_finish() {
  # --skip-save: 정리 spawn 건너뛰기 (드물게 사용)
  local skip_save=false
  for a in "$@"; do
    [[ "$a" == "--skip-save" ]] && skip_save=true
  done

  baton_guard_main_root finish || return 1
  local root
  root=$(baton_active_root)
  local current="$root/.baton/handoff/CURRENT.md"
  local handoff_dir="$root/.baton/handoff"

  # save를 먼저 호출 — sidecar 정리 (race 안전, /baton:finish 가 적합한 시점)
  if ! $skip_save && [[ -d "$handoff_dir" ]]; then
    local event_count
    event_count=$(baton_events_count "$handoff_dir")
    if [[ "${event_count:-0}" -gt 0 ]]; then
      echo "─────────────────────────────────────────"
      echo "📦 finish 직전 컨텍스트 정리 (${event_count} events)"
      echo "─────────────────────────────────────────"
      baton_cmd_save || true
      echo
    fi
  fi

  [[ -f "$current" ]] && baton_current_set_status done "$current"
  echo "✓ status → done"
  echo
  echo "다음 단계 (사용자가 직접):"
  echo "  1. verify (예: $(baton_runtime_verify_hint))"
  echo "  2. PR 생성·머지: gh pr create / gh pr merge"
  echo "  3. /baton:wt-clean  # archive 자동 보관"
  echo
  baton_tmux_attach_hint
}

# === /baton:migrate (v1.2.4+) ===
# 기존 워크트리(v1.2.2 이하)의 .baton/handoff를 v1.2.4 sidecar 패턴으로 마이그레이션.
# 비파괴: 기존 JOURNAL/CURRENT/NEXT 보존, .events.jsonl 빈 파일만 보장, version.lock 갱신.
baton_cmd_migrate() {
  local dry_run=false
  local target=""
  for a in "$@"; do
    case "$a" in
      --dry-run) dry_run=true ;;
      *) [[ -z "$target" ]] && target="$a" ;;
    esac
  done

  local root
  root=$(baton_project_root)

  echo "─────────────────────────────────────────"
  echo "🔄 baton migrate — v1.2.4 sidecar 패턴 적용"
  echo "─────────────────────────────────────────"
  $dry_run && echo "  (dry-run 모드 — 실제 변경 없음)"
  echo

  local current_version
  current_version="$(cat "$BATON_HOME/VERSION" 2>/dev/null || echo "unknown")"
  echo "  Current baton: $current_version"
  echo "  Project root:  $root"
  echo

  # 마이그레이션 대상 워크트리 목록
  local -a worktrees=()
  if [[ -n "$target" ]]; then
    worktrees+=("$target")
  else
    if [[ -d "$root/.worktrees" ]]; then
      while IFS= read -r wt; do
        [[ -d "$wt/.baton/handoff" ]] && worktrees+=("$wt")
      done < <(find "$root/.worktrees" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)
    fi
  fi

  if [[ ${#worktrees[@]} -eq 0 ]]; then
    echo "  (마이그레이션 대상 워크트리 없음)"
    return 0
  fi

  echo "  대상: ${#worktrees[@]} 워크트리"
  echo

  local migrated=0 skipped=0 already_ok=0

  for wt in "${worktrees[@]}"; do
    local handoff="$wt/.baton/handoff"
    local lock_file="$wt/.baton/version.lock"
    local wt_name
    wt_name=$(basename "$wt")
    [[ -d "$handoff" ]] || { skipped=$((skipped+1)); continue; }

    echo "  ── $wt_name ──"

    # ── 이미 v1.2.4 이상? (JSON/plain 둘 다 인식) ──
    local lock_ver=""
    if [[ -f "$lock_file" ]]; then
      if command -v jq >/dev/null 2>&1; then
        lock_ver=$(jq -r '.baton_version // empty' "$lock_file" 2>/dev/null || echo "")
      fi
      if [[ -z "$lock_ver" ]]; then
        lock_ver=$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' "$lock_file" 2>/dev/null | head -1 || echo "")
      fi
    fi
    if [[ -n "$lock_ver" ]] && [[ "$lock_ver" == "$current_version" ]]; then
      echo "    ✓ 이미 $lock_ver (skip)"
      already_ok=$((already_ok+1))
      continue
    fi

    # ── 작업 1: .events.jsonl 보장 ──
    if [[ ! -f "$handoff/.events.jsonl" ]]; then
      if $dry_run; then
        echo "    + .events.jsonl 생성 (dry-run)"
      else
        touch "$handoff/.events.jsonl" 2>/dev/null || true
        echo "    + .events.jsonl 생성"
      fi
    fi

    # ── 작업 2: JOURNAL.md 백업 ──
    if [[ -f "$handoff/JOURNAL.md" && ! -f "$handoff/JOURNAL.md.pre-1.2.4.bak" ]]; then
      if $dry_run; then
        echo "    + JOURNAL.md.pre-1.2.4.bak 백업 (dry-run)"
      else
        cp "$handoff/JOURNAL.md" "$handoff/JOURNAL.md.pre-1.2.4.bak" 2>/dev/null || true
        echo "    + JOURNAL.md.pre-1.2.4.bak 백업"
      fi
    fi

    # ── 작업 2-b (v1.2.5+): CURRENT.md frontmatter last_commit 백필 ──
    if [[ -f "$handoff/CURRENT.md" ]]; then
      local _has_lc=""
      _has_lc=$(awk '/^---$/{f=!f; next} f && /^last_commit:/{print "yes"; exit}' "$handoff/CURRENT.md")
      if [[ -z "$_has_lc" ]]; then
        local _wt_commit
        _wt_commit=$(git -C "$wt" rev-parse --short HEAD 2>/dev/null || echo "—")
        if $dry_run; then
          echo "    + last_commit: $_wt_commit (dry-run)"
        else
          # last_harness 라인 뒤에 last_commit 라인 추가 (frontmatter 안에서만)
          local _tmp
          _tmp=$(mktemp)
          awk -v lc="$_wt_commit" '
            /^---$/ { fm = !fm; print; next }
            fm && /^last_harness:/ { print; print "last_commit: " lc; next }
            { print }
          ' "$handoff/CURRENT.md" > "$_tmp"
          mv "$_tmp" "$handoff/CURRENT.md"
          echo "    + last_commit: $_wt_commit"
        fi
      fi
    fi

    # ── 작업 3: version.lock 갱신 (JSON 우선, plain text fallback) ──
    if [[ -n "$current_version" ]]; then
      if $dry_run; then
        echo "    + version.lock → $current_version (dry-run, ${lock_ver:-?} → $current_version)"
      else
        local _migrated_at
        _migrated_at=$(baton_iso_now)
        local _from="${lock_ver:-pre-1.2.4}"

        if [[ -f "$lock_file" ]]; then
          # JSON 형식 감지 (첫 글자 '{')
          local first_char
          first_char=$(head -c 1 "$lock_file" 2>/dev/null || echo "")
          if [[ "$first_char" == "{" ]] && command -v jq >/dev/null 2>&1; then
            local tmp
            tmp=$(mktemp)
            if jq --arg v "$current_version" --arg from "$_from" --arg at "$_migrated_at" \
                '.baton_version = $v | .migrated_from = $from | .migrated_at = $at' \
                "$lock_file" > "$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
              mv "$tmp" "$lock_file"
              echo "    + version.lock(JSON) → $current_version"
            else
              rm -f "$tmp"
              echo "    ⚠️  version.lock JSON 변환 실패 — skip"
            fi
          else
            # plain text 갱신 또는 append
            if grep -q "baton_version" "$lock_file" 2>/dev/null; then
              local tmp
              tmp=$(mktemp)
              sed "s|baton_version[: =].*|baton_version: $current_version|" "$lock_file" > "$tmp" 2>/dev/null \
                && mv "$tmp" "$lock_file" \
                && echo "    + version.lock(plain) → $current_version" \
                || { rm -f "$tmp"; echo "    ⚠️  version.lock plain 변환 실패"; }
            else
              echo "baton_version: $current_version" >> "$lock_file"
              echo "    + version.lock(append) → $current_version"
            fi
          fi
        else
          # version.lock 없으면 신규 plain
          cat > "$lock_file" <<EOF
baton_version: $current_version
phase_id: $wt_name
migrated_from: $_from
migrated_at: $_migrated_at
EOF
          echo "    + version.lock(new) → $current_version"
        fi
      fi
    fi

    migrated=$((migrated+1))
  done

  echo
  echo "─────────────────────────────────────────"
  echo "  마이그레이션 결과"
  echo "─────────────────────────────────────────"
  echo "  ✓ migrated:  $migrated"
  echo "  - already:   $already_ok"
  echo "  ⚠ skipped:   $skipped"
  echo
  if [[ "$migrated" -gt 0 ]] && ! $dry_run; then
    echo "✓ 마이그레이션 완료. 다음 hook 발화부터 sidecar 패턴 적용."
    echo "  기존 JOURNAL.md 누적 turn은 보존됨."
    echo "  롤백 필요 시: JOURNAL.md.pre-1.2.4.bak 복원 + ~/.baton/current 심링크 변경"
  fi
}

# === /baton:hotfix-mode ===
baton_cmd_hotfix_mode() {
  if ! baton_is_main_root "$PWD"; then
    echo "❌ hotfix-mode는 main/master 브랜치 root에서만"
    return 1
  fi
  echo "─────────────────────────────────────────"
  echo "🚨 hotfix-mode 활성화"
  echo "─────────────────────────────────────────"
  echo "main에서 직접 작업 모드입니다. baton 메모리 비활성."
  echo "종료 시: /baton:hotfix-mode finish (archive에 tag:hotfix 만 남김)"
  if [[ "${1:-}" == "finish" ]]; then
    local root
    root=$(baton_project_root)
    baton_archive_init
    # 가벼운 archive: 최근 commit + diff 만
    local ts
    ts=$(date +"%Y%m%d_%H%M")
    local archive_file
    archive_file="$(baton_archive_dir)/hotfix_${ts}.tar.gz"
    # HEAD~5 안전화: commit 수가 5 미만이면 첫 commit까지만
    local commit_count base
    commit_count=$(git rev-list --count HEAD 2>/dev/null || echo 1)
    if [[ "$commit_count" -le 1 ]]; then
      base=$(git rev-list --max-parents=0 HEAD 2>/dev/null || echo HEAD)
      git diff "$base..HEAD" > /tmp/baton-hotfix-${ts}.patch 2>/dev/null || true
    else
      local n=$((commit_count > 5 ? 5 : commit_count - 1))
      git diff "HEAD~${n}..HEAD" > /tmp/baton-hotfix-${ts}.patch 2>/dev/null || true
    fi
    tar czhf "$archive_file" -C /tmp "baton-hotfix-${ts}.patch" 2>/dev/null || true
    chmod 600 "$archive_file"
    rm -f /tmp/baton-hotfix-${ts}.patch
    echo "✓ hotfix archive: $archive_file (tag:hotfix)"
    # INDEX append
    jq -nc \
      --arg id "hotfix_${ts}" \
      --arg ts "$(date +"%Y-%m-%dT%H:%M:%S%z")" \
      '{id:$id, branch:"main", phase:"hotfix", archived_at:$ts, worktree:".", commits:[], size_bytes:0, merged_to_main:true, tags:["hotfix"]}' \
      >> "$(baton_archive_index)"
  fi
}

# === /baton:help ===
baton_cmd_help() {
  cat <<'HELP'
─────────────────────────────────────────────────────────────────
baton — Universal Standard Workflow
─────────────────────────────────────────────────────────────────

핵심 원칙:
  - 워크트리 + 아카이브 + 작업 메모리 표준화
  - 작업의 앞/뒤만 baton, 중간은 외부 하네스 (superpowers/OMC/...)
  - main/master root에서는 baton 거부 (옵션 B strict)

라이프사이클 시퀀스:
  사용자        baton             외부 하네스           Git
    │             │                   │                  │
    │ /plan ID    │                   │                  │
    ├────────────▶│ phase.json + 4-template            │
    │             │                                      │
    │ /wt-create  │                                      │
    ├────────────▶│ 워크트리 + 포트 + 심링 + 메모리 이전 │
    │             ├─────────────────────────────────────▶│
    │                                                    │
    │ (작업: 런타임별 하네스 — OMX/Codex, OMC/Claude 등) │
    │             │                   │                  │
    │ Stop / Compact / UserPrompt                        │
    │             │ ◀── dump 지시 ───┤                  │
    │             │ JOURNAL/CURRENT/NEXT 갱신           │
    │             │                                      │
    │ [새 세션] "이어서"                                  │
    ├────────────▶│ resume → NEXT.md 출력               │
    │                                                    │
    │ /finish     │                                      │
    ├────────────▶│ status=done                         │
    │ /wt-clean   │                                      │
    ├────────────▶│ archive 보관 + 워크트리 삭제        │
    │             ├─────────────────────────────────────▶│

명령 (17개):
  /baton:plan <id>              phase.json + 4-template (워크트리에서만)
  /baton:wt-create <name>       워크트리 생성
  /baton:save                   핸드오프 dump
  /baton:resume                 NEXT.md 출력
  /baton:finish                 페이즈 완료
  /baton:wt-clean [path?] [--merged]  정리 + archive
  /baton:status                 상태
  /baton:help                   이 화면
  /baton:install                인터뷰형 설치
  /baton:doctor                 진단
  /baton:upgrade                새 버전 설치
  /baton:hotfix-mode [finish]   main 직접 작업 모드
  /baton:archive list [--days N] [--global]
  /baton:archive search <q> [--global]
  /baton:archive show <id>
  /baton:archive extract <id>
  /baton:archive close <id>
  /baton:archive prune [--dry-run] [--days N]

키워드 트리거:
  "이어서" / "진행" / "go" / "continue" / "next"  →  resume

옵션 B (main strict):
  main/master root에서 plan/save/resume/finish 거부.
  허용: wt-create, status, archive list/search, hotfix-mode, install/doctor/upgrade.

자동 정책:
  - SessionStart: paused 알림 + 환경 체크 + lazy prune (7일)
  - UserPromptSubmit: INTENTS → JOURNAL.md
  - PostToolUse: 하네스 사용 자동 추출 + verification
  - PreCompact / SessionEnd: 백업 dump
  - wt-clean 시 archive 자동 + 30일 prune
─────────────────────────────────────────────────────────────────
HELP
}

# === /baton:doctor ===
baton_cmd_doctor() {
  local root
  root=$(baton_project_root)
  echo "─────────────────────────────────────────"
  echo "🩺 baton doctor"
  echo "─────────────────────────────────────────"
  echo "  baton version: $(baton_version)"
  echo "  spec version:  $(baton_spec_version)"
  echo "  HOME:          $BATON_HOME"
  echo "  project root:  $root"
  echo "  archive dir:   $(baton_archive_dir 2>/dev/null || echo "-")"
  echo
  if command -v jq >/dev/null; then
    echo "  ✓ jq"
  else
    echo "  ❌ jq missing — brew install jq (REQUIRED)"
  fi
  if [[ -f "$root/.baton/version.lock" ]]; then
    if baton_check_compat "$root/.baton/version.lock"; then
      echo "  ✓ 호환성 OK"
    fi
  else
    echo "  (version.lock 없음 — 신규 프로젝트?)"
  fi
  if baton_is_main_root "$PWD"; then
    echo "  ⚠️  현재 main/master root — phase 작업 비활성 (옵션 B)"
  fi
  echo
  baton_archive_lazy_prune 7 || true
}
