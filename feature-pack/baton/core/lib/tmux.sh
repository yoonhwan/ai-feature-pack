#!/usr/bin/env bash
# baton lib/tmux.sh — tmux 통합 (v1.2 표준)
# v1.2부터 tmux는 baton의 default. 설치되어 있으면 자동 사용.
# opt-out: BATON_TMUX_DISABLE=true (강제 비활성)
# legacy: BATON_TMUX_ENABLE=false 도 같은 효과 (호환)

set -euo pipefail

BATON_HOME="${BATON_HOME:-$HOME/.baton/current}"

# === 활성화 여부 (v1.2: default true, opt-out) ===
baton_tmux_enabled() {
  command -v tmux >/dev/null 2>&1 || return 1
  [[ "${BATON_TMUX_DISABLE:-false}" == "true" ]] && return 1
  [[ "${BATON_TMUX_ENABLE:-true}" == "false" ]] && return 1   # legacy 호환
  return 0
}

# === 세션 이름 표준 ===
# baton-{project}-{phase-id} (충돌 방지)
baton_tmux_session_name() {
  local phase_id=$1
  local project="${BATON_PROJECT_NAME:-baton}"
  if [[ -f "./.baton/config.json" ]] && command -v jq >/dev/null 2>&1; then
    project=$(jq -r '.project_name // "baton"' ./.baton/config.json 2>/dev/null)
  fi
  echo "baton-${project}-${phase_id}"
}

# === 세션 존재 여부 ===
baton_tmux_session_exists() {
  local session=$1
  baton_tmux_enabled || return 1
  tmux has-session -t "$session" 2>/dev/null
}

# === 세션 생성 + cd + ready 배너 ===
# args: $1=phase-id, $2=worktree path
baton_tmux_create_session() {
  local phase_id=$1
  local wt_path=$2
  baton_tmux_enabled || return 1
  local session
  session=$(baton_tmux_session_name "$phase_id")

  # 이미 존재하면 skip
  if baton_tmux_session_exists "$session"; then
    echo "ℹ️  tmux 세션 이미 존재: $session"
    return 0
  fi

  # detached 세션 생성 + cd + ready 명령 자동 실행
  tmux new-session -d -s "$session" -c "$wt_path" \
    "echo '─────────────────────────────────────────'; \
     echo '🪃 baton tmux session: $session'; \
     echo '─────────────────────────────────────────'; \
     echo 'Worktree: $wt_path'; \
     echo; \
     bash $BATON_HOME/bin/baton status; \
     echo; \
     echo '─── NEXT.md ───'; \
     cat $wt_path/.baton/handoff/NEXT.md 2>/dev/null || echo '(NEXT.md 없음)'; \
     echo '─────────────────'; \
     echo; \
     echo '다음: 자유롭게 작업 시작 (예: claude, codex exec, 또는 직접 코드 편집)'; \
     exec \$SHELL"

  echo "✓ tmux 세션 생성: $session"
  echo "  접속:        tmux attach -t $session"
  baton_tmux_mobile_ssh_hint "$session" | sed 's/^/  /'
}

# === 세션 종료 ===
baton_tmux_kill_session() {
  local session=$1
  baton_tmux_enabled || return 0
  if baton_tmux_session_exists "$session"; then
    tmux kill-session -t "$session" 2>/dev/null
    echo "✓ tmux 세션 종료: $session"
  fi
}

# === phase-id로 세션 종료 (편의 wrapper) ===
baton_tmux_kill_by_phase() {
  local phase_id=$1
  local session
  session=$(baton_tmux_session_name "$phase_id")
  baton_tmux_kill_session "$session"
}

# === 세션 상태 1줄 (status에서 사용) ===
# returns: " (tmux: <name>)" or ""
baton_tmux_status_suffix() {
  local phase_id=$1
  baton_tmux_enabled || return 0
  local session
  session=$(baton_tmux_session_name "$phase_id")
  if baton_tmux_session_exists "$session"; then
    echo " (tmux: $session — attach: tmux a -t $session)"
  fi
}

# === 모든 baton tmux 세션 목록 ===
baton_tmux_list_sessions() {
  baton_tmux_enabled || return 0
  tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^baton-' || true
}

# === 모바일 SSH 안내 한 줄 (Tailscale 활성 시) ===
# args: $1=session name
baton_tmux_mobile_ssh_hint() {
  local session=$1
  command -v tailscale >/dev/null 2>&1 || return 0
  local tailnet_ip
  tailnet_ip=$(tailscale ip -4 2>/dev/null | head -1)
  [[ -z "$tailnet_ip" ]] && return 0
  local user="${USER:-$(whoami)}"
  echo "📱 모바일 SSH: ssh ${user}@${tailnet_ip}  → tmux a -t ${session}"
}

# === 현재 active phase tmux 세션 attach 안내 한 줄 (plan/save/resume/finish 출력 끝에) ===
baton_tmux_attach_hint() {
  baton_tmux_enabled || return 0
  local phase_id=""
  # phase.json에서 phase_id 추출 (현재 워크트리 또는 부모 방향)
  local d="$PWD"
  while [[ "$d" != "/" ]]; do
    if [[ -f "$d/.baton/phase.json" ]] && command -v jq >/dev/null 2>&1; then
      phase_id=$(jq -r '.phase_id // empty' "$d/.baton/phase.json" 2>/dev/null)
      [[ -n "$phase_id" ]] && break
    fi
    d=$(dirname "$d")
  done
  [[ -z "$phase_id" ]] && return 0
  local session
  session=$(baton_tmux_session_name "$phase_id")
  if baton_tmux_session_exists "$session"; then
    echo "🖥️  tmux 세션 열려 있음 — 바로 진행: tmux a -t $session"
    baton_tmux_mobile_ssh_hint "$session"
  else
    # 세션 없는데 워크트리 안이면 새로 띄울 수 있음 안내
    if [[ -d "$d/.baton/handoff" ]]; then
      echo "💡 tmux 세션 새로 열기: tmux new -s $session -c $d"
    fi
  fi
}
