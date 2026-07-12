#!/bin/bash
# ft-tmux-spawn.sh — tmuxc open(또는 승인된 raw_launch_fallback)의 검증 래퍼 (§1-3①)
# 세션 생성 실행 주체 = tmuxc open. capability 갭(P-T0 확정: model_full_id=false,
# env_passthrough=false) 시 승인된 raw_launch_fallback 경로로 headroom 기동을 합성한다.
#
# Usage:
#   ft-tmux-spawn.sh --root <dir> --name <sess> --agent claude|codex --role <role> \
#     --model <id> --effort <e> --prompt-file <계약경로> --input "<1줄>" [--retain-on-fail]
#
# Exit: 0 성공 / 1 부팅실패 / 3 APPROVAL_REQUIRED(스폰 예외) / 4 CAPABILITY_GAP /
#       6 USE_AGENT_V2(spawn_backend=agent-v2 — 오케 롤백 분기) /
#       7 MODEL_MISMATCH(스폰 후 실모델 ≠ 기대세대 — 모델 leak 방지 kill·abort, 2026-07-12)
set +e
LIB="$(cd "$(dirname "$0")" && pwd)/ft-lib.sh"; . "$LIB"

ROOT="" NAME="" AGENT="claude" ROLE="" MODEL="" EFFORT="" PROMPT_FILE="" INPUT="" RETAIN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="$2"; shift 2;;
    --name) NAME="$2"; shift 2;;
    --agent) AGENT="$2"; shift 2;;
    --role) ROLE="$2"; shift 2;;
    --model) MODEL="$2"; shift 2;;
    --effort) EFFORT="$2"; shift 2;;
    --prompt-file) PROMPT_FILE="$2"; shift 2;;
    --input) INPUT="$2"; shift 2;;
    --retain-on-fail) RETAIN=1; shift;;
    *) echo "ft-tmux-spawn: unknown arg: $1" >&2; exit 1;;
  esac
done
ROOT="$(ft_resolve_root "$ROOT")"
[ -n "$NAME" ] && [ -n "$ROLE" ] || { echo "ft-tmux-spawn: --name·--role 필수" >&2; exit 1; }

# ── ② spawn_backend 분기 (agent-v2 → 롤백 디스패처로) ──────
BACKEND="$(ft_ijson "$ROOT" spawn_backend.default)"; [ -z "$BACKEND" ] && BACKEND="tmux"
# checker는 default를 따른다(롤백 시 default=agent-v2면 checker도 agent-v2 → exit 6).
# checker 키의 유일한 발산 값은 "workflow"(checker_workflow 예외) — 그때만 오버라이드.
if [ "$ROLE" = "checker" ]; then
  cbe="$(ft_ijson "$ROOT" spawn_backend.checker)"
  [ "$cbe" = "workflow" ] && BACKEND="workflow"
fi
if [ "$BACKEND" = "agent-v2" ]; then
  echo "ft-tmux-spawn: spawn_backend=agent-v2 — 오케 legacy 디스패처로 분기" >&2
  exit 6
fi
if [ "$BACKEND" = "workflow" ]; then
  # checker 전용 예외 — 레지스트리에 checker_workflow 없으면 무시하고 tmux로 진행
  if [ "$ROLE" = "checker" ] && ft_has_exception "$ROOT" checker_workflow; then
    echo "ft-tmux-spawn: checker workflow 예외 — 오케 Workflow 경로 사용" >&2
    exit 6
  fi
  # 승인 안 된 workflow 설정은 무시(tmux 스폰 진행)
fi

# ── ① 신호 디렉토리 pre-create ─────────────────────────────
if [ "$ROLE" = "pm" ]; then SIG="$(ft_pm_signals "$ROOT")"; else
  SIG="$(ft_signals_for_sess "$ROOT" "$NAME")"   # 비-ft(오케 자기증류)는 global로 라우팅(MINOR-7)
fi
mkdir -p "$SIG/archive" 2>/dev/null

# ── capability 판정 ────────────────────────────────────────
MODEL_FULL="$(ft_ijson "$ROOT" tmuxc_caps.model_full_id)"   # true/false/""
LAUNCH_MODE="tmuxc"   # tmuxc | raw
if [ "$AGENT" = "claude" ]; then
  # claude 워커는 모델 full-ID 지정이 필요. tmuxc가 못 하면 raw_launch_fallback.
  if [ "$MODEL_FULL" != "true" ] && [ -n "$MODEL" ]; then
    if ft_has_exception "$ROOT" raw_launch_fallback; then
      LAUNCH_MODE="raw"
    else
      echo "ft-tmux-spawn: CAPABILITY_GAP — tmuxc 모델 지정 불가 + raw_launch_fallback 미승인" >&2
      exit 4
    fi
  fi
fi

# tmuxc role 매핑(codex 경로용 — tmuxc는 worker|analysis|orchestrator|implementer|architect만)
tmuxc_role() {  # <role> [agent]
  local role="$1" agent="${2:-}"
  # codex는 tmuxc resolve_codex_cmd 매핑을 탄다: worker=medium / verifier=high / (미등록 role=die).
  # da/da2/architect=codex를 worker로 두면 침묵 강등(medium) → verifier(high)로 승격(M-4).
  if [ "$agent" = "codex" ]; then
    case "$role" in
      da|da2|architect) echo verifier;;
      *) echo worker;;
    esac
    return 0
  fi
  case "$role" in
    architect) echo architect;; analyst) echo analysis;; implementer) echo implementer;;
    *) echo worker;;
  esac
}

# ── ③ 세션 기동 ────────────────────────────────────────────
launch_ok=0
if [ "$LAUNCH_MODE" = "raw" ]; then
  # 승인된 raw_launch_fallback: headroom 기동 명령을 tmux 세션으로 합성.
  # FT_WORKER_ROLE env는 exec 교체되는 claude 프로세스까지 셸 레벨 전파(P-T1 실측).
  HR="${FT_HR_BIN:-$HOME/.headroom/claude-hr.sh}"        # MINOR-8: 이식성 env 오버라이드
  # M-6: [1m] 창 선택자가 sh 글롭에 노출되지 않도록 --model 을 큰따옴표로(tmuxc와 동일 인용).
  CMD="$HR --dangerously-skip-permissions --model \"$MODEL\""
  [ -n "$EFFORT" ] && CMD="$CMD --effort $EFFORT"
  CMD="$CMD --remote-control $NAME"
  # B-1b: role=orch/미상(오케 자기증류 후계)은 워커 마커 생략 — 후계 오케가 워커로 오염되지 않게.
  case "$ROLE" in
    orch|"") ;;
    *) CMD="FT_WORKER_ROLE=$ROLE $CMD";;
  esac
  tmux new-session -d -s "$NAME" -c "$ROOT" "$CMD" 2>/dev/null && launch_ok=1
else
  # 정본 경로: tmuxc open (COMM-GUIDE 주입은 tmuxc UC1 step 8)
  TR="$(tmuxc_role "$ROLE" "$AGENT")"
  set -- tmuxc open "$ROOT" --name "$NAME" --agent "$AGENT" --role "$TR"
  [ -n "$PROMPT_FILE" ] && set -- "$@" --prompt "$PROMPT_FILE"
  # V2: tmuxc 경로도 model/effort 승계. tmuxc --model/--effort는 claude 전용(codex는 role→effort 고정,
  #     codex에 --model 넘기면 tmuxc가 die)이므로 claude일 때만 전달.
  if [ "$AGENT" = "claude" ]; then
    [ -n "$MODEL" ]  && set -- "$@" --model "$MODEL"
    [ -n "$EFFORT" ] && set -- "$@" --effort "$EFFORT"
  fi
  "$@" >/dev/null 2>&1 && launch_ok=1
fi
if [ "$launch_ok" != "1" ]; then
  echo "ft-tmux-spawn: 세션 기동 실패($LAUNCH_MODE) $NAME" >&2
  exit 1
fi

# ── ④ readiness 프로브 (5초 간격, 총 90초) ─────────────────
CLAUDE_READY_RE="${FT_CLAUDE_READY_REGEX:-ctx:|\? for shortcuts|esc to interrupt}"
CODEX_READY_RE="$(ft_ijson "$ROOT" probe.codex_ready_regex)"
[ -z "$CODEX_READY_RE" ] && CODEX_READY_RE='^[[:space:]]*[A-Za-z0-9._-]+[[:space:]]+(minimal|low|medium|high)[[:space:]]+·'
ready=0; waited=0
while [ "$waited" -lt 90 ]; do
  cap="$(tmux capture-pane -p -t "$NAME" 2>/dev/null)"
  if [ "$AGENT" = "codex" ]; then
    printf '%s\n' "$cap" | grep -qE "$CODEX_READY_RE" && { ready=1; break; }
  else
    printf '%s\n' "$cap" | grep -qE "$CLAUDE_READY_RE" && { ready=1; break; }
  fi
  sleep 5; waited=$((waited+5))
done
if [ "$ready" != "1" ]; then
  # 부팅 실패: 마지막 30줄 저장 후 반부팅 세션 정리(부팅 실패 pane에 send 금지)
  tmux capture-pane -p -t "$NAME" 2>/dev/null | tail -30 > "$SIG/$NAME.bootfail.log" 2>/dev/null
  if [ "$RETAIN" != "1" ]; then tmuxc kill "$NAME" >/dev/null 2>&1; fi
  echo "ft-tmux-spawn: readiness timeout(90s) $NAME — bootfail.log 저장" >&2
  exit 1
fi

# ── ④.5 [2026-07-12] 모델 leak 사후 검증 (claude 워커 — 전 스폰경로 공통 보장) ──
#   tmuxc/Agent 어느 경로도 install.json 세대를 구조적으로 보장하지 않는다(호출자 --model 신뢰).
#   실제 status-line 모델을 기대세대와 정규화 대조해 세션모델 leak을 잡는다.
#   기대 = 호출자 --model 우선, 없으면 install.json placeholders.<ROLE>_MODEL. codex는 대상 아님(effort 표기).
if [ "$AGENT" = "claude" ] && [ -n "$ROLE" ] && [ "$ROLE" != "orch" ]; then
  # 정규화: claude- 프리픽스 제거 후 소문자 [a-z0-9]만 (claude-opus-4-8 ↔ "Opus 4.8" → 둘 다 opus48) — C1
  ft_norm_model() { printf '%s' "$1" | sed -E 's/^claude-//; s/\[1m\]$//' | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9'; }
  # 기대 모델 SSOT = install.json canonical (호출자 --model은 SSOT와 대조만, 덮어쓰기 금지) — H2
  CANON=""
  case "$ROLE" in
    architect)      CANON="$(ft_ijson "$ROOT" placeholders.ARCHITECT_MODEL)";;
    analyst)        CANON="$(ft_ijson "$ROOT" placeholders.ANALYST_MODEL)";;
    checker)        CANON="$(ft_ijson "$ROOT" placeholders.CHECKER_MODEL)";;
    implementer)    CANON="$(ft_ijson "$ROOT" placeholders.IMPLEMENTER_MODEL)";;
    tester|tester2) CANON="$(ft_ijson "$ROOT" placeholders.TESTER_MODEL)";;
    pm)             CANON="$(ft_ijson "$ROOT" pm.model)";;
  esac
  # H2: 호출자 --model이 canonical과 불일치면 스폰된 세션을 kill하고 거부(잘못된 세대 요청 차단)
  if [ -n "$MODEL" ] && [ -n "$CANON" ] && [ "$(ft_norm_model "$MODEL")" != "$(ft_norm_model "$CANON")" ]; then
    echo "ft-tmux-spawn: --model($MODEL) ≠ install.json canonical($CANON) role=$ROLE — 거부·kill" >&2
    tmuxc kill "$NAME" >/dev/null 2>&1; exit 7
  fi
  EXPECT_MODEL="${CANON:-$MODEL}"
  if [ -n "$EXPECT_MODEL" ]; then
    exp_n="$(ft_norm_model "$EXPECT_MODEL")"
    mdl_disp=""; mtry=0
    while [ "$mtry" -lt 5 ]; do
      mdl_disp="$(tmux capture-pane -p -t "$NAME" 2>/dev/null | grep -oE 'Model:[[:space:]]*[A-Za-z]+[[:space:]]*[0-9][0-9.]*' | tail -1 | sed 's/.*Model:[[:space:]]*//')"
      [ -n "$mdl_disp" ] && break
      sleep 3; mtry=$((mtry+1))
    done
    act_n="$(ft_norm_model "$mdl_disp")"
    # H1: EXPECT 있는데 판독 실패 = fail-closed(미탐 방지). M1: RETAIN 무관 kill.
    if [ -z "$act_n" ]; then
      tmux capture-pane -p -t "$NAME" 2>/dev/null | tail -20 > "$SIG/$NAME.modelunread.log" 2>/dev/null
      ft_append "$SIG/spawn-audit.log" "$(date +%s) $NAME MODEL_UNREAD expect=$EXPECT_MODEL"
      echo "ft-tmux-spawn: 모델 status-line 판독 실패(role=$ROLE, expect=$EXPECT_MODEL) — fail-closed kill+abort" >&2
      tmuxc kill "$NAME" >/dev/null 2>&1; exit 7
    fi
    if [ "$exp_n" != "$act_n" ]; then
      tmux capture-pane -p -t "$NAME" 2>/dev/null | tail -20 > "$SIG/$NAME.modelmismatch.log" 2>/dev/null
      ft_append "$SIG/spawn-audit.log" "$(date +%s) $NAME MODEL_MISMATCH expected=$EXPECT_MODEL actual=$mdl_disp"
      echo "ft-tmux-spawn: MODEL_MISMATCH role=$ROLE expected=$EXPECT_MODEL actual='$mdl_disp' — 모델 leak 방지 kill+abort" >&2
      tmuxc kill "$NAME" >/dev/null 2>&1; exit 7
    fi
  fi
fi

# ── ⑤ 계약 + 입력 send (send 래퍼 경유) ────────────────────
SEND="$(dirname "$0")/ft-tmux-send.sh"
# M-2: raw 모드는 tmuxc UC1 step8을 우회하므로 COMM-GUIDE가 자동 주입되지 않는다 →
#      readiness 통과 후 spawn 래퍼가 직접 주입(send 래퍼가 §2 도달검증 수행). tmuxc 경로는 이미 주입됨.
if [ "$LAUNCH_MODE" = "raw" ] && [ "$AGENT" = "claude" ]; then
  bash "$SEND" "$NAME" --from orch "통신 표준: ~/.claude/skills/tmuxc/COMM-GUIDE.md 를 지금 Read하고 그대로 따를 것. 너의 세션명(me)=$NAME. 세션간 송신은 검증 송신 프로토콜(§2) 준수 — 도달 확인 전 '전송 완료' 보고 금지." >/dev/null 2>&1
fi
if [ -n "$PROMPT_FILE" ] || [ -n "$INPUT" ]; then
  MSG="계약: ${PROMPT_FILE:-없음} Read 후 시작."
  [ -n "$INPUT" ] && MSG="$MSG 입력: $INPUT"
  bash "$SEND" "$NAME" --from orch "$MSG" >/dev/null 2>&1
fi

# ── ⑥ spawn-audit append ───────────────────────────────────
PANEPID="$(tmux list-panes -t "$NAME" -F '#{pane_pid}' 2>/dev/null | head -1)"
ft_append "$SIG/spawn-audit.log" "$(date +%s) $NAME ${MODEL:-<tmuxc-role>} ${PANEPID:-?}"

# ── ⑦ PM 스폰 시: watchd 싱글턴 확보 + pm-session 주소록 기록 ──
if [ "$ROLE" = "pm" ]; then
  PMSIG="$(ft_pm_signals "$ROOT")"; mkdir -p "$PMSIG" 2>/dev/null
  ft_atomic_write "$PMSIG/pm-session" "$NAME"
  WATCHD="$(dirname "$0")/ft-pm-watchd.sh"
  bash "$WATCHD" --root "$ROOT" --ensure >/dev/null 2>&1 &
fi

echo "SPAWNED $NAME mode=$LAUNCH_MODE ready=1"
exit 0
