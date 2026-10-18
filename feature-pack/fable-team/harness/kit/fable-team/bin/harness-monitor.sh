#!/usr/bin/env bash
# harness-monitor — 축 A 모니터 체크 1벌 (읽기 전용 · 좌석이 10분마다 직접 실행 · 틱 데몬 0)
# 사용: bash harness/bin/harness-monitor.sh   (종료코드 = WARN 개수, 0 = 전부 OK)
set -u
ROOT="${FT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}"
COMMON="$(git -C "$ROOT" rev-parse --git-common-dir 2>/dev/null | sed 's#/\.git$##')"
MAILBOX="${FT_MAILBOX:-$COMMON/.fable-team/comm/mailbox.jsonl}"
RING="${FT_MBOX_RING:-10}"
warn=0
ok()   { printf 'OK   %s\n' "$1"; }
bad()  { printf 'WARN %s\n' "$1"; warn=$((warn + 1)); }

# 1. 훅 — 문법(셔뱅 그대로 bash -n) + 게이트 로그 최근 오류
broken=""
for f in "$HOME"/.claude/hooks/*.sh "$ROOT"/.claude/hooks/*.sh; do
  [ -f "$f" ] || continue
  bash -n "$f" 2>/dev/null || broken="$broken $(basename "$f")"
done
[ -z "$broken" ] && ok "훅 문법 전부 통과" || bad "훅 문법 오류:$broken"
for log in "$HOME"/.claude/logs/*gate*.log; do
  [ -f "$log" ] || continue
  n=$(tail -200 "$log" | grep -E "^($(date +%Y-%m-%d)|$(date -v-1d +%Y-%m-%d))" | grep -ciE 'traceback|error|exception')
  [ "$n" -eq 0 ] && ok "훅 로그 $(basename "$log") 최근 이틀 오류 0" || bad "훅 로그 $(basename "$log") 최근 이틀 오류 ${n}건"
done

# 2. 좌석 부팅 실패 — 세션 pane 의 실행 명령이 셸이면 agent 가 없다 (agent 는 버전 문자열로 보임)
dead=""
live=""
while IFS=' ' read -r sess cmd; do
  live="$live $sess"
  case "$sess" in *'#'[0-9]*) ;; *) continue ;; esac
  case "$cmd" in zsh|bash|sh|fish|-zsh|-bash) dead="$dead $sess" ;; esac
done < <(tmux list-panes -a -F '#{session_name} #{pane_current_command}' 2>/dev/null)
[ -z "$dead" ] && ok "좌석 pane 전부 agent 실행 중" || bad "agent 없는 좌석(셸만 남음):$dead"

# 3. mbox 적체 — ring($RING) 포화 직전 수신자 (DROPPED 는 stderr 로만 나가 로그가 없으므로 pending 으로 대신 본다)
if [ -f "$MAILBOX" ]; then
  # 살아 있는 세션이 받는 큐만 경고(주인 없는 큐는 정보로만 — 읽을 좌석이 없다)
  out=$(python3 - "$MAILBOX" "$RING" "$live" <<'PY'
import json, sys, collections
c = collections.Counter()
for ln in open(sys.argv[1], encoding="utf-8"):
    try: c[json.loads(ln)["to"]] += 1
    except Exception: pass
lim, live = int(sys.argv[2]) - 2, set(sys.argv[3].split())
hot = [f"{t}={n}" for t, n in c.items() if n >= lim and t in live]
orphan = sum(1 for t, n in c.items() if t not in live)
print(" ".join(hot) + "|" + str(orphan))
PY
)
  hot="${out%%|*}"; orphan="${out##*|}"
  [ -z "$hot" ] && ok "mbox 살아 있는 좌석 pending 전부 ring-2 미만 (주인 없는 큐 ${orphan}개)" || bad "mbox ring 포화 임박(DROPPED 위험): $hot (주인 없는 큐 ${orphan}개)"
else
  bad "mailbox 없음: $MAILBOX"
fi

# 4. 자동로드 예산 (#3 RULE)
h=$(bash "$ROOT/.claude/skills/byz-ops/scripts/hygiene-check.sh" rules 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -m3 '⚠' | sed 's/^ *//' | cut -c1-110)
[ -z "$h" ] && ok "자동로드 예산 한도 안" || bad "자동로드 예산: $h"

echo "harness-monitor: WARN=$warn"
exit "$warn"
