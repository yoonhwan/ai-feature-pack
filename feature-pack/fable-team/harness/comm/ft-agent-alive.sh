#!/bin/bash
# ft-agent-alive.sh — «이 좌석의 pane 에 에이전트가 받을 수 있게 떠 있나» 판정기 하나 (R346).
#   doorbell(mbox_doorbell.sh)이 source 하고 · ft-tick·ft-tick-team·ft-seat-live·ft-harness-info 는 CLI 로 부른다 — 판정기 두 벌 0.
#   CLI: ft-agent-alive.sh <좌석>   한 줄 ALIVE|NOAGENT seat=… fg=<전경 명령> body=<pid|none> · UNKNOWN seat=… reason=…
#        rc 0 alive · 1 noagent · 2 판정 불가(세션 없음·ps/tmux 판독 실패·명부 깨짐 — alive 로 돌리지 않는다 · #0 RULE)
#   NOAGENT = ①전경이 셸(zsh·bash·sh·…) — 누가 받아도 셸이 받는다 · claude 본체 이름은 버전 숫자(「2.1.302」)로 뜨므로 «셸이면 아니오» 로 판정 ②살아 있는 본체 없음
#   («살아 있는» = ps stat 첫 글자가 T(정지)·Z(좀비) 가 아님 · 래퍼(claude-hr·caffeinate·timeout…)·그 인자 속 --resume 은 본체가 아님)
#   env: FT_TMUX(tmux 대체) · FT_PS_CMD(ps 대체 — 시험용) · FT_AGENT_ALIVE_TIMEOUT(외부 조회 상한 초 — 7 이하만) · FT_PS_SNAPSHOT(틱 루프의 ps 스냅샷 파일 — 필드 7 · ps 호출 0)

# ── 외부 조회 상한 (전역 하드 룰 12 · 7초 룰) ── 판정기 안 ps·tmux 는 전부 timeout 7(FT_AGENT_ALIVE_TIMEOUT 로 낮출 수만 있다 — 7 초과·비숫자는 7 로 클램프). timeout 발동·명령 없음 = 판정 불가(rc2).
_aa_timeout_s() { local n="${FT_AGENT_ALIVE_TIMEOUT:-7}"; case "$n" in ''|*[!0-9]*) n=7;; esac; [ "$n" -ge 1 ] || n=7; [ "$n" -le 7 ] || n=7; echo "$n"; }
# bash -c 로 감싸는 이유 = timeout 은 외부 명령이라 export -f 한 함수(시험 대역)를 못 부른다 — bash 가 함수를 먼저 잡는다.
_aa_run() {
  local tm; tm="$(command -v timeout || command -v gtimeout)" || { echo "agent-alive: timeout 명령 없음 — 판정 불가 (무제한 조회 금지)" >&2; return 125; }
  "$tm" "$(_aa_timeout_s)" bash -c '"$@"' _ "$@"
}

# ps 표 → 정규화 행 «pid ppid stat args…» 를 stdout 에. 1회만 부른다(stat 을 같은 조회에서 얻는다).
#   FT_PS_SNAPSHOT=<파일> 이 있으면 그 파일(필드 7 `pid ppid pgid lstart time stat command` · LC_ALL=C · lstart 5토큰 · R347 계약)만 읽는다 — 자기 ps 호출 0 ·
#   못 읽거나 필드가 모자란/깨진 줄이 하나라도 있으면 실패(자기 ps 로 폴백 0 — 실패 은폐 금지). 신선도·루프 id 는 R347 착지 때 합치는 담당 = R347 카드.
#   자기 ps 의 stat 이 비었거나 깨진 pid 행·빈 출력·rc≠0 도 실패 — 판정 불가(rc2)이지 NOAGENT 도 ALIVE 도 아니다.
_ps_rows() {
  local raw
  if [ -n "${FT_PS_SNAPSHOT:-}" ]; then
    raw="$(cat "$FT_PS_SNAPSHOT" 2>/dev/null)" || { echo "agent-alive: FT_PS_SNAPSHOT 읽기 실패 ($FT_PS_SNAPSHOT) — 판정 불가 (자기 ps 폴백 0)" >&2; return 1; }
    printf '%s\n' "$raw" | awk 'NF==0{next}
      { if (NF<11 || $1!~/^[0-9]+$/ || $2!~/^[0-9]+$/ || $3!~/^[0-9]+$/ || $4!~/^[A-Z][a-z][a-z]$/ || $5!~/^[A-Z][a-z][a-z]$/ || $6!~/^[0-9]+$/ || $7!~/^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]$/ || $8!~/^[0-9][0-9][0-9][0-9]$/ || $9!~/^[0-9:.-]+$/ || $10!~/^[A-Z?][A-Za-z0-9+<>?]*$/) { bad++; next }
        c=$11; for (i=12; i<=NF; i++) c=c " " $i; print $1, $2, $10, c; n++ }
      END { exit (bad>0 || n==0) ? 3 : 0 }' || { echo "agent-alive: FT_PS_SNAPSHOT 필드 7 형식 아님/빈 파일 ($FT_PS_SNAPSHOT) — 판정 불가 (자기 ps 폴백 0)" >&2; return 1; }
  else
    raw="$(LC_ALL=C _aa_run ${FT_PS_CMD:-ps} -axo pid=,ppid=,stat=,args=)" || { echo "agent-alive: ps 실패/시간 초과 — 판정 불가" >&2; return 1; }
    printf '%s\n' "$raw" | awk '/^ *[0-9]+ +[0-9]+ / { if ($3 !~ /^[A-Z?][A-Za-z0-9+<>?]*$/) bad++; else { n++; print } }
      END { exit (bad>0 || n==0) ? 3 : 0 }' || { echo "agent-alive: ps 출력 stat 칸 깨짐/빈 출력 — 판정 불가" >&2; return 1; }
  fi
}

# 본체 판별: stdin = _ps_rows · $1=root(pane_pid) $2=agent → root 와 그 자손 중 «본체» pid(정지 T·좀비 Z 제외)를 줄마다 하나씩.
#   본체 = «실제 실행 주체»가 에이전트인 프로세스 — argv0(또는 node·npm·npx·bun·deno·pnpm·python 뒤 첫 비플래그 인자)의 basename 으로 판정한다.
#   caffeinate·timeout·env·nohup·setsid·bash·claude-hr 같은 래퍼는 후보가 아니다 — 래퍼 «인자» 속 claude --resume 는 본체가 아니다(DA⑥ H1).
#   claude = 실행 주체 claude(경로 끝 /claude · claude-code/) ∧ 그 뒤 인자에 --dangerously-skip-permissions 또는 --resume[=]  ·  codex = 실행 주체 codex(경로 끝 /codex · npm exec @openai/codex)
#   그 밖(cmd·opencode·명부에 없음) = root 아래 아무 자손(이름 미실측 — 조용히 NOAGENT 로 바꾸지 않는다).
agent_body_pids() {
  awk -v root="$1" -v ag="$2" '
    { pp[$1]=$2; st[$1]=$3; a=$0; sub(/^ *[0-9]+ +[0-9]+ +[^ ]+ */, "", a); ar[$1]=a; o[++n]=$1 }
    END { for (i=1; i<=n; i++) { p=o[i]; q=p; in_=0
      for (d=0; q!="" && q!=0 && d<12; d++) { if (q==root) { in_=1; break }; q=pp[q] }
      if (!in_ || st[p] ~ /^[TZ]/) continue
      if (ag!="claude" && ag!="codex") { if (p!=root) print p; continue }
      nt=split(ar[p], tk, " "); if (nt==0) continue
      ei=1; ex=tk[1]; b=tk[1]; sub(/.*\//, "", b)
      if (b ~ /^(node|npm|npx|bun|bunx|deno|pnpm|python|python3)$/) { ex=""; for (k=2; k<=nt; k++) { if (tk[k] ~ /^-/ || tk[k]=="exec" || tk[k]=="run" || tk[k]=="dlx") continue; ex=tk[k]; ei=k; break } }
      if (ex=="") continue
      if (ag=="claude") { if (ex ~ /(^|\/)claude$|\/claude-code\//) { for (k=ei+1; k<=nt; k++) if (tk[k]=="--dangerously-skip-permissions" || tk[k]=="--resume" || tk[k] ~ /^--resume=/) { print p; break } } }
      else if (ex ~ /(^|\/)codex$|^@openai\/codex$|\/@openai\/codex\//) print p } }'
}

# mbox.sh 밖(CLI)에서만 정의 — mbox.sh 가 source 하면 mbox.sh 의 것을 쓴다(같은 규칙: FT_SEATS_JSON → .worktrees 위 루트 .fable-team/seats.json).
if ! declare -F _seats_json >/dev/null; then
  _seats_json() {
    [ -n "${FT_SEATS_JSON:-}" ] && { printf '%s' "$FT_SEATS_JSON"; return; }
    local d; d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    while [ "$d" != "/" ]; do
      case "$(basename "$d")" in .worktrees) printf '%s/.fable-team/seats.json' "$(dirname "$d")"; return;; esac
      d="$(dirname "$d")"
    done
    printf '%s/../seats.json' "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  }
fi

# 좌석의 에이전트 종류(agent 칸) — _seats_json 파일을 먼저, 그다음 같은 폴더 seats.json·seats-*.json 전부에서 첫 일치(팀 명부 좌석 — loom·ops·harness). 못 찾으면 빈 값 · ★못 찾았고 깨진(JSON 파싱 실패) 명부가 있으면 `ERR <파일>`★ (조용히 옛 규칙으로 후퇴 0 · #0 RULE). rc 0 고정.
_seat_agent() {
  local sj; sj="$(_seats_json 2>/dev/null)"; [ -n "$sj" ] || return 0
  python3 - "$sj" "$1" 2>/dev/null <<'PY'
import glob, json, os, sys
sj, name = sys.argv[1:3]
d = os.path.dirname(sj) or "."
bad = []
for p in dict.fromkeys([sj] + sorted(glob.glob(os.path.join(d, "seats.json")) + glob.glob(os.path.join(d, "seats-*.json")))):
    try: row = json.load(open(p, encoding="utf-8")).get(name)
    except OSError: continue
    except (ValueError, AttributeError): bad.append(p); continue
    if isinstance(row, dict) and row.get("agent"): print(row["agent"]); sys.exit(0)
if bad: print("ERR " + bad[0])
PY
  return 0
}

# $1=pane_pid $2=좌석 $3=pane_id → rc 0 에이전트 있음 · 1 없음 · 2 판정 불가. 부수: AA_FG(전경 명령) · AA_BODY(살아 있는 본체 첫 pid | none)
#   claude·codex 좌석 = 본체 규칙 · 그 밖(cmd·opencode·명부에 없음) = «아무 자식» 규칙(-a 필수 — macOS pgrep 은 호출자 조상을 기본 제외)
AA_FG=""; AA_BODY=none
_agent_alive() {
  local ag rows pids fg
  AA_FG=""; AA_BODY=none
  ag="$(_seat_agent "$2")"
  case "$ag" in ERR\ *) echo "agent-alive: 명부 JSON 깨짐 — ${ag#ERR } (좌석 $2 의 agent 판독 불가 · 판정 불가)" >&2; return 2;; esac
  rows="$(_ps_rows)" || return 2
  pids="$(printf '%s\n' "$rows" | agent_body_pids "$1" "$ag")"
  fg="$(_aa_run ${FT_TMUX:-tmux} display-message -p -t "$3" '#{pane_current_command}' 2>/dev/null)" || fg=""
  [ -n "$fg" ] || { echo "agent-alive: 전경 명령 판독 실패/시간 초과 ($2 $3) — 판정 불가" >&2; return 2; }
  AA_FG="$fg"; [ -z "$pids" ] || AA_BODY="${pids%%$'\n'*}"
  case " zsh bash sh dash fish ksh tcsh csh " in *" ${fg#-} "*) return 1;; esac   # 전경이 셸 = 누가 받아도 셸이 받는다
  [ -n "$pids" ]
}

# CLI — 직접 실행했을 때만(source 하면 실행 0)
_aa_main() {
  local seat="${1:-}" line pane pid rc=0
  case "$seat" in ''|*[!A-Za-z0-9._#-]*) echo "usage: ft-agent-alive.sh <좌석>" >&2; return 2;; esac
  line="$(_aa_run ${FT_TMUX:-tmux} list-panes -a -F '#{session_name}|#{pane_id}|#{pane_pid}' 2>/dev/null)" || rc=$?
  [ "$rc" != 124 ] && [ "$rc" != 125 ] || { echo "UNKNOWN seat=$seat reason=tmux-timeout"; return 2; }
  rc=0; line="$(printf '%s\n' "$line" | awk -F'|' -v s="$seat" '$1==s{print $2" "$3; exit}')"
  [ -n "$line" ] || { echo "UNKNOWN seat=$seat reason=session-absent"; return 2; }
  read -r pane pid <<< "$line"
  _agent_alive "$pid" "$seat" "$pane" || rc=$?
  case "$rc" in
    0) echo "ALIVE seat=$seat fg=$AA_FG body=$AA_BODY";;
    1) echo "NOAGENT seat=$seat fg=$AA_FG body=$AA_BODY";;
    *) echo "UNKNOWN seat=$seat reason=judge-failed"; rc=2;;
  esac
  return "$rc"
}
if [ "${BASH_SOURCE[0]}" = "$0" ]; then set -uo pipefail; _aa_main "$@"; exit $?; fi
