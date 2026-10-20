#!/usr/bin/env bash
# serena-guard·serena-mcp 설치 + 부팅 ensure launchd (R327 · 재부팅 뒤 Serena 공유 서버 자동 기동)
# 사용: bash install.sh [--apply] [--root <메인 루트>] [--ensure-project <경로>]      (기본 dry-run = 할 일만 출력 · 변경 0)
#   --apply : ①serena-guard.sh → ~/.claude/skills/zombie-clean/scripts/ ②serena-mcp.sh → ~/.claude/scripts/ (cp -p)
#             ③com.byz.serena-ensure.plist 렌더(절대경로) → ~/Library/LaunchAgents/ ④launchctl bootstrap (RunAtLoad = 부팅·로그인 때 ensure 1회)
# ensure 프로젝트 = 좌석이 «실제로 붙는 포트» 의 프로젝트 (R555): --ensure-project > ~/.claude.json serena url 포트의 bridges 기록 > ROOT
# 멱등: 파일이 이미 같으면 cp 생략 · plist 가 같고 적재돼 있으면 ALREADY. 실 Serena 서버는 건드리지 않는다(기동은 launchd 가 부팅 때).
# 시험 주입: SERENA_INSTALL_HOME(홈 대체) · SERENA_INSTALL_LAUNCHCTL(launchctl 대체) — 실 launchctl·실 홈 0 으로 돌릴 때만 쓴다.
# 종료코드: 0 완료(또는 dry-run) · 2 사용/환경
set -uo pipefail
HERE="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="${SERENA_INSTALL_HOME:-$HOME}"
LAUNCHCTL="${SERENA_INSTALL_LAUNCHCTL:-launchctl}"
LABEL="com.byz.serena-ensure"
AGENTS_DIR="$HOME_DIR/Library/LaunchAgents"
PLIST="$AGENTS_DIR/$LABEL.plist"
GUARD_DST="$HOME_DIR/.claude/skills/zombie-clean/scripts/serena-guard.sh"
MCP_DST="$HOME_DIR/.claude/scripts/serena-mcp.sh"
DOMAIN="gui/$(id -u)"
APPLY=0; ROOT=""; ENSURE_PROJECT_ARG=""

die() { local rc="$1"; shift; echo "$*" >&2; exit "$rc"; }
say() { if [ "$APPLY" = 1 ]; then echo "APPLY $*"; else echo "DRY $*"; fi; }

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --root) ROOT="${2:?--root 값 필요}"; shift 2 ;;
    --ensure-project) ENSURE_PROJECT_ARG="${2:?--ensure-project 값 필요}"; shift 2 ;;
    *) die 2 "사용: install.sh [--apply] [--root <메인 루트>] [--ensure-project <경로>]" ;;
  esac
done

if [ -z "$ROOT" ]; then   # 워크트리에서 돌려도 메인 루트(공용 .git 의 부모)를 쓴다
  common="$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || die 2 "메인 루트를 못 찾음 — --root 로 지정"
  ROOT="$(dirname -- "$common")"
fi
[ -d "$ROOT" ] || die 2 "메인 루트 없음: $ROOT"

place() {  # $1=키트 파일 $2=목적지 — 같으면 생략
  [ -f "$1" ] || die 2 "키트 파일 없음: $1"
  if cmp -s "$1" "$2" 2>/dev/null; then say "same $2"; return; fi
  say "cp -p $1 → $2"
  [ "$APPLY" = 1 ] || return 0
  mkdir -p "$(dirname -- "$2")" && cp -p "$1" "$2" && chmod +x "$2" || die 2 "복사 실패: $2"
}

render_plist() {  # $1=출력 경로
  sed -e "s|__SERENA_MCP__|$MCP_DST|g" -e "s|__ENSURE_PROJECT__|$ENSURE_PROJECT|g" -e "s|__HOME__|$HOME_DIR|g" \
      "$HERE/com.byz.serena-ensure.plist.template" > "$1"
}

port_for() {  # serena-mcp.sh:33 port_for 와 같은 식 (프로젝트 경로 해시 포트)
  echo $((9200 + $(printf '%s' "$1" | cksum | awk '{print $1}') % 700))
}

claude_json_serena_url() {  # $1=.claude.json → projects[ROOT].mcpServers.serena.url (없으면 빈값)
  [ -f "$1" ] || return 0
  python3 - "$1" "$ROOT" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
print((((d.get("projects") or {}).get(sys.argv[2]) or {}).get("mcpServers") or {}).get("serena", {}).get("url", ""))
PY
}

resolve_ensure_project() {  # 좌석이 붙는 포트의 프로젝트를 골라 ENSURE_PROJECT·ENSURE_SRC 를 채운다
  local url url_port rec project
  url="$(claude_json_serena_url "$HOME_DIR/.claude.json")"
  url_port="$(printf '%s' "$url" | sed -n 's|.*127\.0\.0\.1:\([0-9][0-9]*\).*|\1|p')"
  if [ -n "$ENSURE_PROJECT_ARG" ]; then
    ENSURE_PROJECT="$ENSURE_PROJECT_ARG"; ENSURE_SRC="--ensure-project"
  elif [ -z "$url" ]; then
    ENSURE_PROJECT="$ROOT"; ENSURE_SRC="기본값 root(좌석 설정 없음)"
    echo "WARN $HOME_DIR/.claude.json projects[$ROOT] 에 mcpServers.serena url 이 없음 — 맞출 대상이 없어 root 로 렌더한다" >&2
  else
    [ -n "$url_port" ] || die 2 "serena url 에서 포트를 못 읽음: $url"
    rec="$HOME_DIR/.serena/bridges/$url_port.json"
    [ -f "$rec" ] || die 2 "좌석 포트 $url_port 의 프로젝트 기록 없음 — `serena-mcp.sh ensure <경로>` 로 한 번 띄우거나 --ensure-project 로 지정"
    project="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("project",""))' "$rec" 2>/dev/null)"
    [ -n "$project" ] || die 2 "기록에 project 없음: $rec"
    ENSURE_PROJECT="$project"; ENSURE_SRC="claude.json url port=$url_port → bridges/$url_port.json"
  fi
  ENSURE_PORT="$(port_for "$ENSURE_PROJECT")"
  [ -z "$url_port" ] || [ "$url_port" = "$ENSURE_PORT" ] \
    || die 2 "ensure project=$ENSURE_PROJECT 의 port_for=$ENSURE_PORT 가 좌석 포트 $url_port 와 다름 (출처 $ENSURE_SRC)"
}

resolve_ensure_project
place "$HERE/serena-guard.sh" "$GUARD_DST"
place "$HERE/serena-mcp.sh" "$MCP_DST"

tmp="$(mktemp)"; trap 'rm -rf "$tmp"' EXIT
render_plist "$tmp"
say "ensure project=$ENSURE_PROJECT port=$ENSURE_PORT (출처 $ENSURE_SRC)"
if command -v plutil >/dev/null 2>&1; then plutil -lint "$tmp" >/dev/null || die 2 "plist lint 실패"; fi
loaded=0; "$LAUNCHCTL" print "$DOMAIN/$LABEL" >/dev/null 2>&1 && loaded=1
if cmp -s "$tmp" "$PLIST" 2>/dev/null && [ "$loaded" = 1 ]; then say "ALREADY $LABEL 적재됨 (ensure project=$ENSURE_PROJECT)"; exit 0; fi
say "plist $PLIST (ensure project=$ENSURE_PROJECT)"
[ "$APPLY" = 1 ] || { say "launchctl bootstrap $DOMAIN $PLIST"; exit 0; }
mkdir -p "$AGENTS_DIR" "$HOME_DIR/.claude/logs" && cp "$tmp" "$PLIST" || die 2 "plist 쓰기 실패"
[ "$loaded" = 1 ] && "$LAUNCHCTL" bootout "$DOMAIN/$LABEL" >/dev/null 2>&1
"$LAUNCHCTL" bootstrap "$DOMAIN" "$PLIST" || die 2 "launchctl bootstrap 실패: $PLIST"
echo "INSTALLED $LABEL plist=$PLIST ensure_project=$ENSURE_PROJECT"
