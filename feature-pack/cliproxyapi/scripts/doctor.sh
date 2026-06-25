#!/usr/bin/env bash
# proxy-stack doctor — Hermes → headroom(8790) → CLIProxyAPI(8317) → 구독 plan
# 전체 스택을 진단하고, 문제마다 복구 명령을 제안한다. read-only(진단)이며
# 자동 변경은 하지 않는다. --fix 플래그를 주면 안전한 복구만 수행한다.
#
# Usage: doctor.sh [--fix]
set -o pipefail

FIX=0
[ "${1:-}" = "--fix" ] && FIX=1

UID_NUM="$(id -u)"
CPA_PORT=8317
HR_PORT=8790
CPA_BIN="$HOME/.cli-proxy-api/bin/cli-proxy-api"
CPA_CONFIG="$HOME/.cli-proxy-api/config.yaml"
CPA_PLIST="$HOME/Library/LaunchAgents/com.cliproxy.api.plist"
HR_PLIST="$HOME/Library/LaunchAgents/com.headroom.proxy.plist"
AUTH_DIR="$HOME/.cli-proxy-api"

green() { printf '\033[32m%s\033[0m\n' "$1"; }
red()   { printf '\033[31m%s\033[0m\n' "$1"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$1"; }
hdr()   { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }

ISSUES=0
note_issue() { ISSUES=$((ISSUES+1)); }

# ── 1. CLIProxyAPI ───────────────────────────────────────────────
hdr "1) CLIProxyAPI (:$CPA_PORT)"
if [ -x "$CPA_BIN" ]; then
  green "binary: $($CPA_BIN --version 2>&1 | head -1)"
else
  red "binary 없음: $CPA_BIN"; note_issue
fi

CPA_STATE="$(launchctl print "gui/$UID_NUM/com.cliproxy.api" 2>/dev/null | awk -F'= ' '/state =/{print $2; exit}')"
if [ "$CPA_STATE" = "running" ]; then
  green "LaunchAgent: running (keepalive)"
elif [ -n "$CPA_STATE" ]; then
  yellow "LaunchAgent: $CPA_STATE"; note_issue
else
  red "LaunchAgent 미등록"; note_issue
  echo "  복구: launchctl bootstrap gui/$UID_NUM \"$CPA_PLIST\""
fi

CPA_MODELS="$(curl -sf -m3 "http://127.0.0.1:$CPA_PORT/v1/models" 2>/dev/null \
  | python3 -c 'import sys,json; print(len(json.load(sys.stdin)["data"]))' 2>/dev/null)"
if [ -n "$CPA_MODELS" ]; then
  green "/v1/models OK ($CPA_MODELS models)"
else
  red "/v1/models 응답 없음 — cliproxy 다운"; note_issue
  echo "  복구: launchctl kickstart -k gui/$UID_NUM/com.cliproxy.api"
  if [ "$FIX" = "1" ]; then
    yellow "  --fix: kickstart 실행"; launchctl kickstart -k "gui/$UID_NUM/com.cliproxy.api" 2>/dev/null
  fi
fi

# ── 2. 계정 / 인증 ───────────────────────────────────────────────
hdr "2) OAuth 계정 (auth-dir)"
ACCTS="$(/bin/ls "$AUTH_DIR" 2>/dev/null | grep -E '^(claude|codex|antigravity|gemini)-.*\.json$')"
if [ -n "$ACCTS" ]; then
  echo "$ACCTS" | while read -r f; do
    PERM="$(stat -f '%Sp' "$AUTH_DIR/$f" 2>/dev/null)"
    case "$PERM" in
      -rw-------) green "  $f ($PERM)";;
      *) yellow "  $f ($PERM) — 토큰 파일은 600 권장 (chmod 600)";;
    esac
  done
else
  red "  계정 없음 — OAuth 로그인 필요"; note_issue
  echo "  복구: 대시보드 http://127.0.0.1:$CPA_PORT/management.html (key: config의 secret-key)"
  echo "        또는 $CPA_BIN -claude-login -config $CPA_CONFIG"
fi

# ── 3. headroom ──────────────────────────────────────────────────
hdr "3) headroom (:$HR_PORT, 압축)"
HR_HEALTH="$(curl -sf -m3 "http://localhost:$HR_PORT/health" 2>/dev/null)"
if echo "$HR_HEALTH" | grep -q '"ready":true'; then
  HR_UP="$(echo "$HR_HEALTH" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("config",{}).get("anthropic_api_url") or "DIRECT(api.anthropic.com)")' 2>/dev/null)"
  green "health: ready | upstream: $HR_UP"
  if [ "$HR_UP" != "http://127.0.0.1:$CPA_PORT" ]; then
    yellow "  체인 미연결: upstream이 cliproxy가 아님"
    echo "  복구: plist ProgramArguments에 --anthropic-api-url http://127.0.0.1:$CPA_PORT 추가 후"
    echo "        launchctl bootout gui/$UID_NUM/com.headroom.proxy && launchctl bootstrap gui/$UID_NUM \"$HR_PLIST\""
    echo "  ⚠️ kickstart -k 는 plist 인자 변경을 반영 안 함 — 반드시 bootout→bootstrap"
  fi
else
  yellow "health 실패 — 미기동이거나 startup(모델 로딩) 중"
  echo "  복구: launchctl kickstart -k gui/$UID_NUM/com.headroom.proxy (기동만)"
  echo "  ※ headroom 미기동이어도 claude-hr.sh 래퍼는 fail-open 직결 — 작업은 무중단"
fi

# health가 ready여도 /v1/messages 실프록시는 막힐 수 있다 (byz: health ≠ active 증명).
# Hermes를 8790으로 라우팅하기 전 반드시 active smoke가 통과해야 안전.
if echo "$HR_HEALTH" | grep -q '"ready":true'; then
  HR_SMOKE="$(curl -sf -m12 -X POST "http://127.0.0.1:$HR_PORT/v1/messages" \
    -H 'content-type: application/json' -H 'x-api-key: dummy' -H 'anthropic-version: 2023-06-01' \
    --data '{"model":"claude-opus-4-8","max_tokens":16,"messages":[{"role":"user","content":"Reply exactly HEADROOM_OK"}]}' 2>/dev/null)"
  if echo "$HR_SMOKE" | grep -q 'HEADROOM_OK'; then
    green "  active /v1/messages: 통과 — 8790 실프록시 OK (Hermes base_url 8790 안전)"
  else
    yellow "  active /v1/messages: 실패/timeout — health ready여도 실프록시 막힘"
    echo "  → Hermes base_url은 8317 direct 유지 권장 (8790 active smoke 통과 전까지)"; note_issue
  fi
fi

# ── 4. Hermes 연동 ───────────────────────────────────────────────
hdr "4) Hermes 연동 (config.yaml)"
HCFG="$HOME/.hermes/config.yaml"
if [ -f "$HCFG" ]; then
  BASE="$(grep -E '^\s*base_url:' "$HCFG" | head -1 | sed 's/.*base_url:\s*//')"
  MODE="$(grep -E '^\s*api_mode:' "$HCFG" | head -1 | sed 's/.*api_mode:\s*//')"
  MODEL="$(grep -E '^\s*default:' "$HCFG" | head -1 | sed 's/.*default:\s*//')"
  echo "  default: $MODEL | api_mode: $MODE"
  echo "  base_url: $BASE"
  case "$BASE" in
    *local.anthropic.com:$HR_PORT*) green "  → headroom 체인 (압축+멀티계정)";;
    *:$CPA_PORT*)                   green "  → cliproxy 직결 (멀티계정, 압축 생략)";;
    *api.anthropic.com*|"")         yellow "  → 직접 Anthropic (스택 미경유)";;
    *)                              echo  "  → 사용자 지정: $BASE";;
  esac
  echo "  cc_tool_cloak gate: base_url이 api.anthropic.com이 아니면 자동 ON (HERMES_CC_TOOL_CLOAK로 강제)"
else
  yellow "  ~/.hermes/config.yaml 없음"
fi

# ── 5. Hermes 게이트웨이 ─────────────────────────────────────────
hdr "5) Hermes 게이트웨이 (Slack/Discord — config·소스 반영)"
GW_LABEL="ai.hermes.gateway"
GW_STATE="$(launchctl print "gui/$UID_NUM/$GW_LABEL" 2>/dev/null | awk -F'= ' '/state =/{print $2; exit}')"
GW_PID="$(launchctl print "gui/$UID_NUM/$GW_LABEL" 2>/dev/null | awk -F'= ' '/pid =/{print $2; exit}')"
if [ "$GW_STATE" = "running" ] && [ -n "$GW_PID" ]; then
  green "LaunchAgent $GW_LABEL: running pid=$GW_PID"
else
  yellow "LaunchAgent $GW_LABEL: ${GW_STATE:-미등록}"; note_issue
  echo "  복구: launchctl kickstart -k gui/$UID_NUM/$GW_LABEL"
  if [ "$FIX" = "1" ]; then
    yellow "  --fix: gateway kickstart"; launchctl kickstart -k "gui/$UID_NUM/$GW_LABEL" 2>/dev/null
  fi
fi
OTHER_GW="$(pgrep -fl 'hermes_cli.main.*gateway run' 2>/dev/null | grep -v "pid $GW_PID" || true)"
if [ -n "$OTHER_GW" ]; then
  yellow "  다른 프로필 게이트웨이도 실행 중 (zion 등):"
  echo "$OTHER_GW" | sed 's/^/    /'
fi
GW_LOG="$HOME/.hermes/logs/gateway.log"
if [ -f "$GW_LOG" ]; then
  LAST_CONN="$(grep -E 'slack connected|discord connected' "$GW_LOG" 2>/dev/null | tail -1)"
  [ -n "$LAST_CONN" ] && echo "  최근: $(echo "$LAST_CONN" | cut -c1-100)..."
fi
echo "  ※ config.yaml·Hermes 소스 패치 후에는 kickstart 필수 (CLI만 고치면 메시징은 옛 코드)"

# ── 6. 스모크 (claude tool 요청) ─────────────────────────────────
hdr "6) 스모크 — claude /v1/messages (tool 포함)"
SMOKE='{"model":"claude-haiku-4-5-20251001","max_tokens":20,"tools":[{"name":"McpReadFile","description":"x","input_schema":{"type":"object","properties":{}}}],"messages":[{"role":"user","content":"reply: DOCTOR_OK"}]}'
RESP="$(curl -sf -m40 -X POST "http://127.0.0.1:$CPA_PORT/v1/messages" \
  -H 'Content-Type: application/json' -H 'anthropic-version: 2023-06-01' \
  --data "$SMOKE" 2>/dev/null)"
if echo "$RESP" | grep -q '"type":"message"'; then
  # cloak system prompt 탓에 "I'm Claude Code…"로 답할 수 있음 — 200 + content면 통과
  green "200 OK — claude가 구독 plan으로 응답 (tool 포함 통과)"
elif echo "$RESP" | grep -qi 'extra usage'; then
  red "400 extra usage — 계정 plan 미적용/소진 또는 tool 핑거프린팅"
  note_issue
  echo "  점검: ① tool 이름 CamelCase인지(McpXxx) ② Hermes가 claude-cli UA를 안 보내는지"
  echo "        ③ 계정 extra usage 잔량/구독 상태 (claude.ai/settings/usage)"
  echo "  상세: references/playbook.md '400 트러블슈팅' 참고"
elif [ -z "$RESP" ]; then
  red "응답 없음 — cliproxy 다운 또는 타임아웃"; note_issue
else
  yellow "예상 외 응답: $(echo "$RESP" | head -c 160)"; note_issue
fi

# ── 7. 과거 에러 로그 stale 오진 방지 ────────────────────────────
# byz 함정: 오래된 error-v1-messages 파일을 현재 장애로 오진하지 말 것.
hdr "7) cliproxy 에러 로그 (stale 오진 방지)"
ERR_DIR="$HOME/.cli-proxy-api/logs"
LATEST_ERR="$(ls -t "$ERR_DIR"/error-v1-messages-* 2>/dev/null | head -1)"
if [ -z "$LATEST_ERR" ]; then
  green "error-v1-messages 로그 없음"
else
  ERR_EPOCH="$(stat -f '%m' "$LATEST_ERR" 2>/dev/null)"
  AGE_MIN=$(( ( $(date +%s) - ${ERR_EPOCH:-0} ) / 60 ))
  if [ "${ERR_EPOCH:-0}" -gt 0 ] && [ "$AGE_MIN" -gt 20 ]; then
    green "최신 에러 ${AGE_MIN}분 전 (>20분=stale, 현재 실패 아님): $(basename "$LATEST_ERR")"
    echo "  ※ 과거 로그는 현재 장애 증거 아님 — 마지막 성공 cron(last_run_at)과 시각 비교할 것"
  else
    yellow "최신 에러 ${AGE_MIN}분 전 (최근) — 내용 확인: $(basename "$LATEST_ERR")"
    echo "  점검: head -c 1500 \"\$LATEST_ERR\" — 단 모델명 '[1m]' unknown provider / quota probe 502는 회귀 아님"
    note_issue
  fi
fi

# ── 요약 ─────────────────────────────────────────────────────────
hdr "요약"
if [ "$ISSUES" = "0" ]; then
  green "✅ 스택 정상 — Hermes → headroom → cliproxy → 구독 plan"
else
  red "⚠️ $ISSUES개 이슈 발견 — 위 복구 명령 참고 (또는 doctor.sh --fix)"
fi
exit 0
