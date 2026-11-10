#!/usr/bin/env bash
# serena-mcp.sh — Serena MCP 싱글톤 매니저 (oraios/serena 공식 권장: Discussion #1103)
#
# 정책: 프로젝트당 Serena HTTP 서버 1개 (streamable-http). 세션들은 connect만.
#   - 서버가 안 떠 있으면 ensure이 띄운다 (포트 = 프로젝트 경로 해시, 안정적)
#   - 서버는 클라이언트 밖에서 상주 (공식: "started by yourself, outside the client")
#   - 세션당 uvx serena 스폰(N세션=N인스턴스, ~750MB×N + LSP 자식) → 프로젝트당 1세트로 축소
#
# 사용:
#   serena-mcp.sh ensure <project-path>   # 서버 없으면 기동 (멱등) — tmuxc open 훅
#   serena-mcp.sh url <project-path>      # 접속 URL 출력 (config 작성용)
#   serena-mcp.sh port <project-path>     # 배정 포트 출력
#   serena-mcp.sh status [<path>|all]     # 서버 상태
#   serena-mcp.sh stop <project-path>     # 해당 프로젝트 서버 종료
#   serena-mcp.sh stop-all                # 전체 종료
#
# Claude 측 설정 (.claude.json / .mcp.json):
#   "serena": {"type": "http", "url": "http://127.0.0.1:<port>/mcp"}
set -uo pipefail

SERENA_HOME="$HOME/.serena"
BRIDGE_DIR="$SERENA_HOME/bridges"
PORT_BASE=9200
PORT_RANGE=700
LOG_DIR="$SERENA_HOME"
SERENA_UVX="${SERENA_UVX:-/opt/homebrew/bin/uvx}"   # 시험 주입 seam — 기본값 동일

die() { printf '❌ %s\n' "$*" >&2; exit 1; }

port_for() {
  local p="$1"
  echo $((PORT_BASE + $(printf '%s' "$p" | cksum | awk '{print $1}') % PORT_RANGE))
}

is_up() {
  local port="$1"
  local code
  code=$(curl -s --connect-timeout 1 --max-time 2 -o /dev/null -w "%{http_code}" \
    "http://127.0.0.1:${port}/mcp" \
    -X POST -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
    -d '{"jsonrpc":"2.0","method":"ping","id":1}' 2>/dev/null)
  [[ "$code" != "000" && -n "$code" ]]
}

state_file() { printf '%s/%s.json' "$BRIDGE_DIR" "$(port_for "$1")"; }

cmd_port() {
  local p="${1:?project required}"
  local port; port=$(port_for "$p")
  # 포트가 다른 프로세스(serena 아님)에 점유됐으면 +1 순방 이동 (최대 20)
  local try=$port
  while (( try < port + 20 )); do
    if is_up "$try" || ! lsof -nP -iTCP:"$try" -sTCP:LISTEN >/dev/null 2>&1; then
      echo "$try"; return 0
    fi
    try=$((try + 1))
  done
  echo "$port"
}

cmd_url() {
  local p="${1:?project-path required}"
  printf 'http://127.0.0.1:%s/mcp\n' "$(cmd_port "$p")"
}

cmd_ensure() {
  local t0=$SECONDS
  local p="${1:?project-path required}"
  [[ -d "$p" ]] || die "project path 없음: $p"
  local port; port=$(port_for "$p")
  mkdir -p "$BRIDGE_DIR" "$SERENA_HOME"

  if is_up "$port"; then
    echo "✅ serena 공유서버 이미 기동 (port=$port project=$p)"
    return 0
  fi

  # 서버는 죽었는데 프로세스 잔존 시 정리
  pkill -f "start-mcp-server.*--port ${port}" 2>/dev/null || true

  local log="$SERENA_HOME/serena-http-${port}.log"
  echo "🚀 serena 공유서버 기동 중 (port=$port project=$p) ..."
  nohup "$SERENA_UVX" --from git+https://github.com/oraios/serena serena \
    start-mcp-server --transport streamable-http --host 127.0.0.1 \
    --port "$port" --open-web-dashboard False --project "$p" \
    >> "$log" 2>&1 &
  local launcher=$!

  # 대기는 «실경과» 기준 마감 — 횟수 루프는 is_up(curl 최대 2s)가 느리면 ~227s 까지 늘어난다 (전역 하드 룰 12 · 총 70s 천장).
  # 마감 60s + 마지막 is_up 2s + sleep 0.5 + 앞선 is_up 2s ≈ 65s < 70s.
  local deadline_s="${SERENA_ENSURE_DEADLINE_S:-60}"
  while (( SECONDS - t0 < deadline_s )); do
    if is_up "$port"; then
      printf '{"project": "%s", "port": %s, "started": "%s"}\n' "$p" "$port" "$(date '+%F %T')" > "$(state_file "$p")"
      echo "✅ serena 공유서버 READY (port=$port, pid=$(server_pid "$port"), log=$log)"
      return 0
    fi
    sleep 0.5
  done
  die "serena 서버 기동 실패 (${deadline_s}초 초과) — 로그: $log (tail: $(tail -3 "$log" 2>/dev/null | tr '\n' ' '))"
}

server_pid() {  # 포트에서 실제 serena 프로세스 pid 찾기 (없으면 빈값)
  local port="$1"
  ps -axww -o pid=,command= | grep -E "start-mcp-server.*--port ${port}( |$)" | grep -v grep | awk '{print $1}' | head -1
}

cmd_status() {
  local target="${1:-all}"
  if [[ "$target" == "all" ]]; then
    local found=0 f port proj
    for f in "$BRIDGE_DIR"/*.json; do
      [[ -f "$f" ]] || { echo "기동된 serena 공유서버 없음"; return 0; }
      port=$(python3 -c "import json,sys; print(json.load(open('$f')).get('port',''))" 2>/dev/null)
      proj=$(python3 -c "import json,sys; print(json.load(open('$f')).get('project',''))" 2>/dev/null)
      [[ -z "$port" ]] && continue
      if is_up "$port"; then
        echo "✅ port=$port project=$proj pid=$(server_pid "$port")"
      else
        echo "💀 port=$port project=$proj (다운 — ensure로 재기동)"
      fi
      found=1
    done
    [[ "$found" -eq 0 ]] && echo "기록된 bridges 없음 (~/.serena/bridges/)"
    return 0
  fi
  local port; port=$(port_for "$target")
  if is_up "$port"; then
    echo "✅ serena 공유서버 기동 (port=$port project=$target pid=$(server_pid "$port"))"
  else
    echo "💀 serena 공유서버 다운 (port=$port) — ensure 실행 필요"
    return 1
  fi
}

cmd_stop() {
  local p="${1:?project-path required}"
  local port; port=$(port_for "$p")
  local pid; pid=$(server_pid "$port")
  if [[ -z "$pid" ]]; then echo "serena 서버 없음 (port=$port)"; rm -f "$(state_file "$p")"; return 0; fi
  kill -TERM "$pid" 2>/dev/null
  sleep 1
  pid=$(server_pid "$port")
  [[ -n "$pid" ]] && kill -9 "$pid" 2>/dev/null
  rm -f "$(state_file "$p")"
  echo "🛑 serena 공유서버 종료 (port=$port)"
}

cmd_stop_all() {
  local f
  for f in "$BRIDGE_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    local proj
    proj=$(python3 -c "import json; print(json.load(open('$f')).get('project',''))" 2>/dev/null)
    [[ -n "$proj" ]] && cmd_stop "$proj"
  done
  # 기록 없이 떠 있는 streamable-http serena도 정리
  pkill -f "start-mcp-server --transport streamable-http" 2>/dev/null && echo "🛑 미기록 serena http 서버도 종료" || true
}

case "${1:-}" in
  ensure)   shift; cmd_ensure "$@" ;;
  url)      shift; cmd_url "$@" ;;
  port)     shift; cmd_port "$@" ;;
  status)   shift; cmd_status "${1:-all}" ;;
  stop)     shift; cmd_stop "$@" ;;
  stop-all) cmd_stop_all ;;
  *) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
