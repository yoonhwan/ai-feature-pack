#!/bin/bash
# 데일리 트렌드 뷰어 — 대화형 런처. 서버는 백그라운드(nohup)로 실행되어 이 창을 닫아도 유지됨.
# 더블클릭하거나 `./run.command` 로 실행.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
PORT=28088
RUN_DIR="/tmp/daily-trend-viewer-local"
PYTHON_BIN="$(command -v python3)"
LAUNCH_LABEL="com.daily-trend-viewer.local"
mkdir -p "$RUN_DIR"

port_owner() { # $1=port → prints first listener pid if occupied
  lsof -nP -tiTCP:"$1" -sTCP:LISTEN 2>/dev/null | head -n 1
}

is_running() { # → 0 if alive, removes stale pidfile
  local pidf="$RUN_DIR/server.pid"
  [ -f "$pidf" ] || return 1
  local pid
  pid="$(cat "$pidf" 2>/dev/null || true)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && [ "$(port_owner "$PORT")" = "$pid" ]; then
    return 0
  fi
  rm -f "$pidf"
  return 1
}

start_server() {
  local pidf="$RUN_DIR/server.pid"
  if is_running; then
    echo "  - 이미 실행 중: http://127.0.0.1:$PORT/"
  else
    local owner
    owner="$(port_owner "$PORT")"
    if [ -n "$owner" ]; then
      echo "  x 포트 $PORT 사용 중 (PID $owner) - 기동 생략"
      return 1
    fi
    if [ "$(uname -s)" = "Darwin" ] && command -v launchctl >/dev/null 2>&1; then
      launchctl remove "$LAUNCH_LABEL" >/dev/null 2>&1 || true
      : >"$RUN_DIR/server.log"
      launchctl submit -l "$LAUNCH_LABEL" -o "$RUN_DIR/server.log" -e "$RUN_DIR/server.log" -- \
        "$PYTHON_BIN" "$ROOT/app/server.py" >/dev/null
    else
      nohup "$PYTHON_BIN" "$ROOT/app/server.py" >"$RUN_DIR/server.log" 2>&1 &
      disown "$!" 2>/dev/null || true
    fi
    sleep 1
    owner="$(port_owner "$PORT")"
    if [ -n "$owner" ]; then
      echo "$owner" >"$pidf"
      echo "  o 기동 완료: http://127.0.0.1:$PORT/"
    else
      echo "  x 기동 실패 - 로그 확인: $RUN_DIR/server.log"
      return 1
    fi
  fi
  open "http://127.0.0.1:$PORT/"
}

stop_server() {
  local pidf="$RUN_DIR/server.pid"
  if is_running; then
    kill "$(cat "$pidf")" 2>/dev/null && echo "  o 서버 종료 완료"
  else
    echo "  - 실행 중 아님"
  fi
  launchctl remove "$LAUNCH_LABEL" >/dev/null 2>&1 || true
  rm -f "$pidf"
}

status_line() {
  if is_running; then echo "  [ON]  서버  -> http://127.0.0.1:$PORT/"
  else echo "  [off] 서버"; fi
}

while true; do
  echo ""
  echo "======== 데일리 트렌드 뷰어 ========"
  status_line
  echo "------------------------------------"
  echo "  1) 서버 시작"
  echo "  2) 서버 종료"
  echo "  3) 상태 확인"
  echo "  0) 나가기 (서버는 백그라운드 유지)"
  echo "------------------------------------"
  read -rp "선택: " c
  case "$c" in
    1) start_server ;;
    2) stop_server ;;
    3) status_line ;;
    0) echo "종료합니다. (서버는 백그라운드 유지 - 다시 이 메뉴 2번으로 끌 수 있어요)"; exit 0 ;;
    *) echo "  잘못된 선택" ;;
  esac
done
