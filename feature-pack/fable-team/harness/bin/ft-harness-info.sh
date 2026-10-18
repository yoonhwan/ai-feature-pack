#!/usr/bin/env bash
# ft-harness-info.sh — 모든 세션이 하네스 정본을 한 줄로 조회한다. 읽기 전용(쓰기·tmux 변경 0).
#
# 사용: ft-harness-info.sh <map|rules|seats|requests|find 키워드>
#   map       하네스 지도(정본 목차 1장) 출력 — 스킬 references/harness-map.md
#   rules     정본 경로 목록 + 실재 여부(OK/없음)
#   seats     라이브 tmux 세션 전부 + 이름 규칙(ft-name-lint) 판정 + 팀 명부 절(seats-*.json 파일별 master·arch·hil·좌석·열림)
#   requests  하네스 요청 원장(REQUEST-LEDGER.md) 표 행 — main 기준
#   find KW   정본 문서 본문에서 키워드 검색(파일:줄)
#   exit 0 = 출력 · 2 = usage · 1 = 정본 파일을 못 읽음(폴백 없음)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
SKILL="${FT_SKILL_DIR:-$HOME/.claude/skills/fable-team}"
CMD="${1:-}"; shift || true

main_file() { git -C "$ROOT" show "origin/main:$1" 2>/dev/null; }
usage() { echo "usage: ft-harness-info.sh <map|rules|seats|requests|find 키워드>" >&2; exit 2; }

CANON=(
  "$SKILL/references/harness-map.md"
  "$SKILL/references/main-team-governance.md"
  "$SKILL/references/SEATBELT.md"
  "$HOME/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md"
  "$HOME/.claude/rules/closeout-policy.md"
)
MAIN_CANON=(
  design/harness/GOAL-harness.md
  design/harness/REQUEST-LEDGER.md
  design/harness/OPS-VERDICTS-20261006.md
  design/harness/MACHINES.md
  design/harness/LANDING-LEDGER.md
  design/harness/issue-improvement/SPEC-session-naming-20261005.md
  design/planner/GUIDE-planner.md
  design/issues/GOAL-issues.md
)

case "$CMD" in
  map)
    [ -f "${CANON[0]}" ] || { echo "REJECT 하네스 지도 없음: ${CANON[0]}" >&2; exit 1; }
    cat "${CANON[0]}" ;;
  rules)
    for f in "${CANON[@]}"; do [ -f "$f" ] && echo "OK    $f" || echo "없음  $f"; done
    for f in "${MAIN_CANON[@]}"; do main_file "$f" >/dev/null && echo "OK    origin/main:$f" || echo "없음  origin/main:$f"; done ;;
  seats)
    tmux ls -F '#{session_name}' 2>/dev/null | sort | while IFS= read -r n; do
      r="$(bash "$HERE/ft-name-lint.sh" "$n")"
      case "$r" in PASS*) r="PASS";; *) r="REJECT ${r#*: }";; esac
      # R346: 세션은 살아 있는데 전경이 맨 셸·본체 정지면 표시 — 판정기는 ft-agent-alive.sh 하나(없거나 판정 불가면 표시 0)
      st="$(bash "${FT_AGENT_ALIVE_BIN:-$HERE/../comm/ft-agent-alive.sh}" "$n" 2>/dev/null)"
      case "$st" in NOAGENT*) fg="${st#* fg=}"; r="$r · ⚠ NOAGENT(fg=${fg%% *})";; esac
      printf '%-52s %s\n' "$n" "$r"
    done
    echo "== 팀 명부 (루트 .fable-team/seats-*.json) =="
    for f in "$ROOT"/.fable-team/seats*.json; do
      [ -f "$f" ] || continue
      python3 -I - "$f" <<'PY'
import json, subprocess, sys
p = sys.argv[1]
name = p.rsplit("/", 1)[-1]
try:
    d = json.load(open(p))
    rows = [k for k, v in d.items() if not k.startswith("_") and isinstance(v, dict)]
    up = sum(1 for k in rows if subprocess.run(["tmux", "has-session", "-t", "=" + k], capture_output=True).returncode == 0)
    print("%s master=%s arch=%s hil=%s 좌석=%d 열림=%d" % (name, d.get("_master", "-"), d.get("_arch", "-"), d.get("_hil_route", "-"), len(rows), up))
except Exception:
    print("ERR %s 파싱 실패" % name)
PY
    done ;;
  requests)
    out="$(main_file design/harness/REQUEST-LEDGER.md)" || true
    [ -n "$out" ] || { echo "REJECT origin/main 에서 REQUEST-LEDGER.md 를 못 읽음" >&2; exit 1; }
    printf '%s\n' "$out" | grep -E '^\| R[0-9]+' ;;
  find)
    [ -n "${1:-}" ] || usage
    for f in "${CANON[@]}"; do [ -f "$f" ] && grep -n -- "$1" "$f" | sed "s|^|$f:|"; done
    for f in "${MAIN_CANON[@]}"; do main_file "$f" | grep -n -- "$1" | sed "s|^|origin/main:$f:|"; done ;;
  *) usage ;;
esac
