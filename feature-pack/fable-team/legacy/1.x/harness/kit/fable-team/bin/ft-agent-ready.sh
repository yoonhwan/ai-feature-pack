#!/usr/bin/env bash
# ft-agent-ready.sh — 좌석 기동 확인 (R251 · 판정 1945 후속 · ft-nano-spawn.sh 가 부른다)
#   --proxy <작업폴더> [--agent A]   기동 전 추론 프록시 확인. 7초 룰(하드 룰 12 · r669): 시도당 curl -m 7 × 최대 2회(사이 2 s) = 총 16 s 이하.
#                                    상한 = FT_PROXY_PROBE_MAX(기본 7 · 7 초과 주입은 7 로 제한 + WARN) · 재시도 1회는 «첫 바이트 전 실패»(연결 거절·시간 초과)만 —
#                                    HTTP 응답이 왔는데 비정상(500 등 curl rc22)이면 재시도 0 즉시 실패. 직결·codex 는 호출 0
#                                    실패 = `REJECT 프록시 <url> 2회 실패` rc1 (직결로 바꾸지 않는다 — #0 RULE · 부르는 쪽이 순번 큐로 넘긴다)
#   --pane <pane_id>|--pid <pid> --agent A [--wait 20] [--restart "<기동 명령>"]
#                                    pane_pid 자손에서 «에이전트 본체» 를 1 s 간격으로 최대 wait 초 찾는다.
#                                    READY <pid> rc0 · NOAGENT rc3 · ERROR <사유> rc1(ps 실패 — 조용한 READY 0)
#                                    --restart = 본체가 없을 때 «같은 pane 에 1회» 그 명령을 입력하고 다시 wait (이 실행이 연 pane 만 넘길 것)
# 본체 판별 = agent_body_pids (harness/comm/mbox_doorbell.sh 와 같은 글자 — test_spawn_agent_ready.sh 가 비교한다).
set -uo pipefail

# 본체 판별 규칙: root 와 그 자손 중 claude = args 에 --dangerously-skip-permissions 또는 «basename 이 정확히 claude 인 토큰 뒤의 토큰 --resume»(R335 복구 좌석 형 · zombie-clean resume·ft-resume-cmd · 다른 프로그램의 --resume 은 아님) ∧ claude-hr(래퍼) 아님 · codex = args 공백 토큰 중 basename 이 정확히 codex(경로 끝 /codex · @openai/codex) · 그 밖(cmd·opencode) = root 아래 아무 자식(이름 미실측 — 조용히 NOAGENT 로 바꾸지 않는다). ps 실패 rc1
agent_body_pids() {
  local tab; tab="$(${FT_PS_CMD:-ps} -axo pid=,ppid=,args=)" || return 1
  printf '%s\n' "$tab" | awk -v root="$1" -v ag="$2" '
    { pp[$1]=$2; ar[$1]=$0; sub(/^ *[0-9]+ +[0-9]+ */, "", ar[$1]); o[++n]=$1 }
    END { for (i=1; i<=n; i++) { p=o[i]; q=p; in_=0
      for (d=0; q!="" && q!=0 && d<12; d++) { if (q==root) { in_=1; break }; q=pp[q] }
      if (!in_) continue
      if (ag=="claude") { if (ar[p] !~ /claude-hr/) { if (ar[p] ~ /--dangerously-skip-permissions/) print p
        else { nt=split(ar[p], tk, " "); sc=0; for (k=1; k<=nt; k++) { if (tk[k] ~ /(^|\/)claude$/) sc=1; else if (sc && (tk[k]=="--resume" || tk[k] ~ /^--resume=/)) { print p; break } } } } }
      else if (ag=="codex") { nt=split(ar[p], tk, " "); for (k=1; k<=nt; k++) if (tk[k] ~ /(^|\/)codex$/) { print p; break } }
      else if (p!=root) print p } }'
}

# r669: 옛 판은 시도당 3초 고정 — 부하 때 프록시 첫 응답이 7.0초면 두 번 다 실패해 «거짓 REJECT»(v65 3회 · 직후 curl 은 200/0.003초).
#   하드 룰 12 기준값(시도당 7초 + 재시도 1회 · 재시도는 첫 바이트 전 실패만)으로 맞춘다.
proxy_probe_max() { # stdout = 시도당 상한 초 (1..7)
  local v="${FT_PROXY_PROBE_MAX:-7}"
  case "$v" in ''|*[!0-9]*) echo "WARN FT_PROXY_PROBE_MAX='$v' 숫자 아님 — 7 로 본다" >&2; v=7;; esac
  [ "$v" -ge 1 ] || { echo "WARN FT_PROXY_PROBE_MAX=$v < 1 — 1 로 본다" >&2; v=1; }
  [ "$v" -le 7 ] || { echo "WARN FT_PROXY_PROBE_MAX=$v > 7 — 7 로 제한(하드 룰 12)" >&2; v=7; }
  echo "$v"
}

proxy_check() { # $1=작업폴더 $2=agent
  [ "$2" = claude ] || return 0
  local st urls=() u i rc max; st="$(cd "$1" && eval "${FT_ROUTE_STATUS_CMD:-$HOME/.headroom/claude-hr.sh route status}" 2>&1)" \
    || { echo "REJECT 경유 판독 실패 — claude-hr.sh route status ($1)"; return 1; }
  printf '%s\n' "$st" | awk '$1=="cliproxy"||$1=="headroom"{f=1} END{exit !f}' || { echo "REJECT 경유 판독 실패 — route status 출력에 headroom/cliproxy 줄 없음"; return 1; }
  printf '%s\n' "$st" | awk '$1=="headroom"&&$3=="on"{f=1} END{exit !f}' && urls+=("http://127.0.0.1:8790/health")
  printf '%s\n' "$st" | awk '$1=="cliproxy"&&$3=="on"{f=1} END{exit !f}' && urls+=("${FT_PROXY_PROBE_URL:-http://127.0.0.1:8317/v1/models}")
  max="$(proxy_probe_max)"
  for u in ${urls[@]+"${urls[@]}"}; do
    for i in 1 2; do
      curl -sf -m "$max" -o /dev/null "$u"; rc=$?
      [ "$rc" = 0 ] && continue 2
      # rc22 = HTTP 응답은 왔는데 -f 가 비정상 코드(4xx·5xx)로 실패 — 첫 바이트 전 실패가 아니므로 재시도 0
      [ "$rc" != 22 ] || { echo "REJECT 프록시 $u HTTP 응답 비정상(curl rc=22) — 응답이 왔으므로 재시도 0"; return 1; }
      echo "INFO 프록시 확인 시도 $i/2 실패(curl rc=$rc · 상한 ${max}s) $u" >&2; [ "$i" = 2 ] || sleep 2
    done
    echo "REJECT 프록시 $u 2회 실패 — 직결로 바꾸지 않는다(부작용 0)"; return 1
  done
}

MODE=""; DIR_=""; PANE=""; PID_=""; AG="claude"; WAIT=20; RCMD=""
while [ $# -gt 0 ]; do case "$1" in
  --proxy) MODE=proxy; DIR_="${2:-}"; shift 2;; --pane) MODE=pane; PANE="${2:-}"; shift 2;; --pid) MODE=pane; PID_="${2:-}"; shift 2;;
  --agent) AG="${2:-}"; shift 2;; --wait) WAIT="${2:-}"; shift 2;; --restart) RCMD="${2:-}"; shift 2;;
  *) echo "usage: $0 --proxy <dir> [--agent A] | --pane <id>|--pid <pid> --agent A [--wait N] [--restart CMD]" >&2; exit 2;; esac; done
[ "$MODE" = proxy ] && { proxy_check "$DIR_" "$AG"; exit $?; }
[ "$MODE" = pane ] || { echo "usage: --proxy 또는 --pane/--pid 필요" >&2; exit 2; }
[ -n "$PID_" ] || PID_="$(tmux display-message -p -t "$PANE" '#{pane_pid}' 2>/dev/null)"
[ -n "$PID_" ] || { echo "ERROR pane_pid 못 읽음: $PANE"; exit 1; }
find_body() { # 0 = READY(stdout) · 3 = 없음 · 1 = ps 실패
  local out i; for ((i=0; i<=WAIT; i++)); do
    out="$(agent_body_pids "$PID_" "$AG")" || { echo "ERROR ps 실패 — 본체 판별 불가"; return 1; }
    [ -n "$out" ] && { echo "READY ${out%%$'\n'*}"; return 0; }
    [ "$i" -lt "$WAIT" ] && sleep 1
  done; return 3
}
find_body; rc=$?
if [ "$rc" = 3 ] && [ -n "$RCMD" ] && [ -n "$PANE" ]; then
  echo "INFO 본체 없음 — 같은 pane($PANE)에 기동 명령 1회 재입력" >&2
  tmux send-keys -t "$PANE" -l "$RCMD"; sleep 0.3; tmux send-keys -t "$PANE" Enter
  find_body; rc=$?; [ "$rc" = 0 ] && echo "INFO 재기동 1회로 READY" >&2
fi
[ "$rc" = 3 ] && echo NOAGENT
exit "$rc"
