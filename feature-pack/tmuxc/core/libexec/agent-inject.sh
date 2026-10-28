#!/usr/bin/env bash
# agent-inject.sh — claude TUI 주입 «한 벌» (r1075 · arch#173 재판단 r2)
#
# 쓰는 곳 셋 — 코드는 «이 파일 하나» 뿐이다(복사본 금지):
#   ① tmuxc 로컬 open·fork 의 부팅 문장 주입  (`inject_message` … kind=agent → agent_inject)
#   ② tmuxc 원격 send                          (h_pipe_write 로 이 파일을 원격에 흘려 실행)
#   ③ tmm 원격 send                            (같은 방식)
# ②③ 은 이 파일을 «원격 bash 가 실행» 한다 — 아래 `BASH_SOURCE == $0` 진입점이 그 경우다.
#
# 절차(로컬 r925 와 같다 · 원격도 같은 순서):
#   ① 입력 상자를 기다린다(상한 TMUXC_READY_MAX 기본 30초) — 안 그려진 TUI 에 넣은 글자는 제출되지 않는다
#   ② 글자를 넣고 «입력줄 = 이번 메시지 전문» 일 때만 Enter(상한 3초 · 아니면 Enter 0)
#   ③ 제출 판정 = 그 좌석 `--session-id` 기록 한 파일(<id>.jsonl)에 대한 새 user 레코드(마감 = 첫 Enter + TMUXC_SUBMIT_WAIT 7초)
#   ④ 절반 시점에 기록 없음 ∧ 입력줄 = 전문이면 Enter 1회 재전송 · 그 밖 재전송 0
#   ⑤ 판독 불가 = rc≠0
#
# 이 파일은 set -euo pipefail 을 «켜지 않는다» — 부르는 쪽(tmuxc)이 이미 켰고, 원격 실행 때는 그 셸이 없다.
# 함수 이름·동작은 tmuxc r925 r3/r4 그대로다(옮기기만 했다 — 동작 변경 0).

# 벽시계 밀리초(bash 3.2 에는 EPOCHREALTIME 이 없다).
now_ms() {
  python3 -c 'import time;print(int(time.time()*1000))'
}

# 입력 박스 내용을 읽는다. Claude Code TUI 는 「세션명 붙은 구분선 / 입력줄 / 구분선 / 상태줄」
# 구조라, 아래에서부터 구분선 두 개를 찾아 그 사이를 입력줄로 본다.
# 구조가 안 맞으면(codex 등 다른 UI) 비-0 으로 끝낸다 — 추측해서 제출하지 않는다.
capture_input_line() {
  local pane="$1" cap
  # r925 P1: 둘째 인자 "join" = -J 로 감긴 줄을 합쳐 읽는다(긴 글자가 폭에 걸려도 한 줄로 본다).
  # r925 r3 R4: capture-pane rc≠0 = 판독 불가(rc2) — 정상 모양 출력이 함께 와도 믿지 않는다.
  # r925 r4: "lines" = -J 로 읽되 입력 상자의 «화면 줄» 을 한 줄씩 그대로 낸다(합치지 않음 · 이어지는 줄의 들여쓰기만 벗김).
  #   claude TUI 는 긴 글을 스스로 여러 줄로 감는다(실측 10-26) — 줄 경계는 input_is_message 가 따로 다룬다.
  if [[ "${2:-}" == "join" || "${2:-}" == "lines" ]]; then
    cap="$(tmux capture-pane -J -t "$pane" -p 2>/dev/null)" || return 2
  else
    cap="$(tmux capture-pane -t "$pane" -p 2>/dev/null)" || return 2
  fi
  # r925 r3 R2: SGR(색·흐림) 은 전부 벗기고 글자만 본다 — 색으로 «우리 글자» 를 가리지 않는다.
  printf '%s\n' "$cap" | awk -v mode="${2:-}" '
    { l[NR] = $0 }
    END {
      for (i = NR; i >= 1; i--)
        if (l[i] ~ /^─────/) { if (!b) { b = i } else { a = i; break } }
      if (!a || !b) exit 1
      out = ""
      for (i = a + 1; i < b; i++) {
        s = l[i]
        gsub(/\033\[[0-9;:]*m/, "", s)
        if (i == a + 1 || mode != "lines") sub(/^[[:space:]]*❯[[:space:]]?/, "", s)
        else sub(/^[[:space:]]+/, "", s)
        sub(/[[:space:]]+$/, "", s)
        if (s == "") continue
        if (mode == "lines") out = (out == "" ? s : out "\n" s)
        else out = (out == "" ? s : out " " s)
      }
      print out
    }'
}

# 입력줄이 «이번 메시지 전문» 인가(r925 r4 R2) — 완전 일치 · 문장 안 공백도 그대로 비교(«통신 표준» ≠ «통 신표준»).
#   정규화 = SGR 벗김 + -J 줄 합침 + 줄 끝 공백 제거뿐. 단 claude TUI 가 스스로 감은 «화면 줄 경계» 에서만
#   원문의 공백·줄바꿈 0개 이상을 건너뛴다(감는 자리에서 공백이 사라지고 이어지는 줄은 들여 쓴다 · 실측 10-26).
#   화면 줄 하나하나는 원문의 그 자리 글자와 바이트까지 같아야 한다. 접두·잘림 인정 0 · 색·흐림 판정 0.
#   rc0 = 전문 · rc1 = 다른 글자(빈 줄·자리표시·사람 글자·잘린 글자·공백 위치 다름) · rc2 = 판독 불가
input_is_message() {
  local cur
  cur="$(capture_input_line "$1" lines)" || return 2
  python3 - "$cur" "$2" <<'PY'
import sys
lines = [l for l in sys.argv[1].split("\n") if l != ""]
msg = sys.argv[2].rstrip(" \t\n")
if not lines:
    sys.exit(1)
pos = 0
for i, line in enumerate(lines):
    if i > 0:
        while pos < len(msg) and msg[pos] in " \t\n":
            pos += 1
    if msg[pos:pos + len(line)] != line:
        sys.exit(1)
    pos += len(line)
sys.exit(0 if pos == len(msg) else 1)
PY
}

# claude 세션 기록 «한 파일» — tmuxc 가 발급한 --session-id 로 <id>.jsonl 만 찾는다(r925 r3 R1 · 디렉터리 전수 판독 0).
#   rc0 = 경로 출력 · rc1 = 아직 없음(새 세션은 첫 제출 때 파일을 만든다) · rc2 = 판정 불가(id 꼴 아님 · 같은 id 둘 이상)
claude_jsonl_of() {
  local sid="$1" base="${TMUXC_CLAUDE_PROJECTS:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects}" f found="" n=0
  [[ "$sid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || return 2
  for f in "$base"/*/"$sid".jsonl; do
    [[ -f "$f" ]] || continue
    found="$f"; n=$((n + 1))
  done
  [[ "$n" -eq 0 ]] && return 1
  [[ "$n" -eq 1 ]] || return 2
  printf '%s\n' "$found"
}

# 그 기록의 지금 크기(바이트 · 파일 없음 = 0) — «주입 시작 뒤에 쓰인 레코드» 의 기준 위치. rc2 = 판정 불가.
claude_jsonl_size() {
  local f rc=0
  f="$(claude_jsonl_of "$1")" || rc=$?
  case "$rc" in
    0) wc -c < "$f" | tr -d '[:space:]' ;;
    1) printf '0\n' ;;
    *) return 2 ;;
  esac
}

# 제출 판정 = 세션 기록(r925 r3 R1) — <id>.jsonl 의 <바이트 위치> 뒤에 쓰인 type=="user" 레코드가 우리 글자 앞 30자(공백 제거)를 담는가.
#   화면(입력 상자 «위») 은 보지 않는다 — 옛 출력이 거짓 증거가 된다(DA⑥ r2).
#   rc0 = 제출됨 · rc1 = 아직 아님 · rc2 = 판정 불가(같은 id 둘 이상 · 파일 못 읽음 · 빈 글자)
claude_submitted_since() {
  local sid="$1" off="$2" text="$3" f rc=0
  f="$(claude_jsonl_of "$sid")" || rc=$?
  [[ "$rc" -eq 1 ]] && return 1
  [[ "$rc" -eq 0 ]] || return 2
  python3 - "$f" "$off" "$text" <<'PY'
import json, sys
path, off, text = sys.argv[1], int(sys.argv[2]), sys.argv[3]
want = "".join(text.split())[:30]
if not want:
    sys.exit(2)
try:
    with open(path, "rb") as fh:
        fh.seek(off)
        data = fh.read()
except OSError:
    sys.exit(2)
for raw in data.splitlines():
    try:
        rec = json.loads(raw)
    except ValueError:
        continue  # 쓰는 중인 마지막 줄 · 기준 위치가 줄 가운데
    if not isinstance(rec, dict) or rec.get("type") != "user":
        continue
    msg = rec.get("message")
    c = msg.get("content") if isinstance(msg, dict) else None
    if isinstance(c, list):
        c = "".join(p["text"] for p in c if isinstance(p, dict) and isinstance(p.get("text"), str))
    if isinstance(c, str) and want in "".join(c.split()):
        sys.exit(0)
sys.exit(1)
PY
}

# 입력 상자가 «그려질 때까지» 기다린다(r925). 안 그려진 TUI 에 넣은 글자는 제출되지 않고 남는다.
wait_input_box() {
  local pane="$1" timeout="${2:-30}" deadline
  deadline=$(( SECONDS + timeout ))
  while :; do
    capture_input_line "$pane" >/dev/null 2>&1 && return 0
    (( SECONDS < deadline )) || return 1
    sleep 0.5
  done
}

# Claude TUI 주입(r925 r3) — open·fork 가 «방금 만든» 세션에만 쓴다(사람 입력 0 · 입력줄 글자는 자리표시 «Try "…"» 뿐 · 실측 10-26).
#   ① 입력 상자가 그려질 때까지 기다린다(고정 sleep 대신 · 상한 TMUXC_READY_MAX 30초)
#   ② 글자를 넣고 입력줄이 «이번 메시지 전문» 이 됐을 때만 Enter(R2) — 아니면 Enter 0 · rc≠0
#   ③ 제출 판정 = 세션 기록(R1) — 넣기 직전 위치 뒤에 우리 글자 앞 30자를 담은 user 레코드(마감 = 첫 Enter + TMUXC_SUBMIT_WAIT 7초 벽시계)
#   ④ 절반 시점까지 기록이 없고 입력줄이 아직 전문이고 직전 재조회에도 없으면 Enter 1회 재전송(R3) · 그 밖은 재전송 0, 마감까지 늦은 기록만 본다
#   ⑤ 판독 불가(capture rc≠0 · 입력줄 못 찾음 · 기록 판정 불가) = rc≠0(R4)
agent_inject() {
  local session="$1" pane="$2" message="$3" sid="$4"
  local ready_max="${TMUXC_READY_MAX:-30}" wait_s="${TMUXC_SUBMIT_WAIT:-7}"
  local off st i round enters=0
  [[ "$wait_s" =~ ^[0-9]+$ ]] || { printf 'state=bad-env session=%s — TMUXC_SUBMIT_WAIT=%s 정수 아님, 주입 0\n' "$session" "$wait_s" >&2; return 1; }
  if ! wait_input_box "$pane" "$ready_max"; then
    printf 'state=not-ready session=%s — 입력 상자가 %s초 안에 안 떴다, 주입 0\n' "$session" "$ready_max" >&2
    return 1
  fi
  if ! off="$(claude_jsonl_size "$sid")"; then
    printf 'state=unreadable session=%s — 세션 기록(%s.jsonl) 판정 불가, 주입 0\n' "$session" "$sid" >&2
    return 1
  fi
  tmux send-keys -t "$pane" -l "$message"
  # ② 그리기 지연을 짧게 기다린다(상한 3초) — 전문이 그려진 입력줄 = TUI 가 우리 글자를 받았다
  st=1
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    sleep 0.2
    st=0; input_is_message "$pane" "$message" || st=$?
    [[ "$st" -eq 1 ]] || break
  done
  case "$st" in
    0) ;;
    2) printf 'state=unreadable session=%s — 입력줄 판독 불가, Enter 0\n' "$session" >&2; return 1 ;;
    *) printf 'state=input-mismatch session=%s — 입력줄이 이번 메시지 전문이 아니다(다른 글자·잘림), Enter 0\n' "$session" >&2; return 1 ;;
  esac
  local now t_end t_mid resent=0 sub
  now="$(now_ms)"; t_end=$(( now + wait_s * 1000 )); t_mid=$(( now + wait_s * 500 ))
  tmux send-keys -t "$pane" Enter; enters=1
  # r925 r4: 마감 = 첫 Enter 시각 + TMUXC_SUBMIT_WAIT초 «벽시계»(조회 횟수 아님 · 조회가 느려도 늘지 않는다).
  #   재전송 판정은 그 절반 시점에 1회(R3) — 기록 없음 ∧ 입력줄 = 전문 ∧ «두 번째 Enter 직전 기록 다시 읽기» 도 없음일 때만.
  #   r7 결과 계약 ① Enter = 첫 1 + 재전송 ≤1 · 재전송은 마감 전에만 · 마감 뒤 Enter 0 (Enter 시각 = send-keys 직전 판정 시각)
  #   ② 증거 없는 rc0 = 0: 기준 위치(inject = 글자 넣기 직전 · boot-enter = Enter 직전 기록 끝) 뒤 우리 글자(공백 뺀 앞 30자) 새 user 레코드만
  #   ③ 총(첫 Enter → rc) ≤ WAIT + 3×D + 1초 · D = 가장 느린 외부 호출 1회(기록 조회·화면 읽기·tmux 입력) (내부 순서·횟수·쉼 값은 계약 아님)
  while :; do
    st=0; claude_submitted_since "$sid" "$off" "$message" || st=$?
    case "$st" in
      0) printf 'state=submitted session=%s enters=%s\n' "$session" "$enters"; return 0 ;;
      2) printf 'state=unreadable session=%s — 세션 기록 판정 불가, 제출 판정 0\n' "$session" >&2; return 1 ;;
    esac
    now="$(now_ms)"
    (( now < t_end )) || break
    if [[ "$resent" -eq 0 && "$now" -ge "$t_mid" ]]; then
      resent=1
      # R3 재전송 판정 — 기록 없음 ∧ 입력줄 = 전문(접두·잘림 인정 0)
      st=0; input_is_message "$pane" "$message" || st=$?
      case "$st" in
        0)
          # 두 번째 Enter 직전에 기록을 한 번 더 읽는다 — 그사이 첫 Enter 가 기록됐으면 재전송 0
          sub=0; claude_submitted_since "$sid" "$off" "$message" || sub=$?
          case "$sub" in
            0) printf 'state=submitted session=%s enters=%s\n' "$session" "$enters"; return 0 ;;
            2) printf 'state=unreadable session=%s — 재전송 전 세션 기록 판정 불가, Enter 0\n' "$session" >&2; return 1 ;;
          esac
          now="$(now_ms)"
          if (( now < t_end )); then tmux send-keys -t "$pane" Enter; enters=2; fi ;;
        2) printf 'state=unreadable session=%s — 재전송 전 입력줄 판독 불가, Enter 0\n' "$session" >&2; return 1 ;;
        *) printf 'state=no-resend session=%s — 입력줄이 전문이 아니다, 재전송 0 · 마감까지 늦은 기록만 본다\n' "$session" >&2 ;;
      esac
    fi
    sleep 0.2
  done
  printf 'state=submit-failed session=%s enters=%s — 제출 실패: %s초 안에 세션 기록에 우리 글자가 없다(글자 재입력 0)\n' "$session" "$enters" "$wait_s" >&2
  return 1
}

# ---------- 원격 진입점 (h_pipe_write 로 이 파일을 원격 bash 가 «실행» 할 때) ----------
# rc 계약: 0 = 제출 확인(그 좌석 --session-id 기록) · 3 = 에이전트 없음(셸 오타이핑 방지) ·
#          4 = 마감까지 기록 없음(NOT_REACHED) · 5 = 판정 불가(상자 안 뜸·입력줄 불일치·판독 불가) ·
#          6 = 기록 id 없음 = «보냈다 · 제출 판정은 호출자(ft-reach-check) 몫»
# 좌석 기록 id 는 «원격 세션 env» 에서 읽는다(원격 open 이 TMUXC_CLAUDE_SESSION_ID 로 심는다 · r1075).
agent_inject_remote() {  # <session> <text> [sid|-] [ready_max] [submit_wait]
  local session="$1" text="$2" sid="${3:-}" arg_rmax="${4:-}" arg_swait="${5:-}"
  local pane="=$session:" cmd err rc=0 ready_max submit_wait
  ready_max="${arg_rmax:-${TMUXC_READY_MAX:-30}}"; [[ "$ready_max" =~ ^[0-9]+$ ]] || ready_max=30
  submit_wait="${arg_swait:-${TMUXC_SUBMIT_WAIT:-7}}"; [[ "$submit_wait" =~ ^[0-9]+$ ]] || submit_wait=7
  export TMUXC_READY_MAX="$ready_max" TMUXC_SUBMIT_WAIT="$submit_wait"
  cmd="$(tmux display -p -t "$pane" '#{pane_current_command}' 2>/dev/null)" || cmd=""
  case "$cmd" in
    zsh|bash|sh|fish|-zsh|-bash|"") printf 'state=no-agent session=%s — 에이전트가 실행 중이 아님(셸 오타이핑 방지 차단)\n' "$session" >&2; return 3 ;;
  esac
  if [[ -z "$sid" || "$sid" == "-" ]]; then
    sid="$(tmux show-environment -t "$pane" TMUXC_CLAUDE_SESSION_ID 2>/dev/null)" || sid=""
    [[ "$sid" == TMUXC_CLAUDE_SESSION_ID=* ]] && sid="${sid#TMUXC_CLAUDE_SESSION_ID=}" || sid=""
  fi
  if [[ -z "$sid" ]]; then
    # 기록 id 없음 = 제출 판정 불가 → ①②만 하고 rc6(호출자가 ft-reach-check 로 판정 · r1047 r3 그대로).
    if ! wait_input_box "$pane" "$ready_max"; then
      printf 'state=not-ready session=%s ready_max=%s — 입력 상자가 안 떴다, 주입 0\n' "$session" "$ready_max" >&2
      return 5
    fi
    tmux send-keys -t "$pane" -l "$text" || return 5
    sleep 0.3
    tmux send-keys -t "$pane" Enter || return 5
    printf 'state=sent-no-id session=%s ready_max=%s\n' "$session" "$ready_max" >&2
    return 6
  fi
  err="$(agent_inject "$session" "$pane" "$text" "$sid" 2>&1 >/dev/null)"; rc=$?
  [[ -n "$err" ]] && printf '%s\n' "$err" >&2
  [[ "$rc" -eq 0 ]] && return 0
  case "$err" in
    *state=submit-failed*) return 4 ;;
    *) return 5 ;;
  esac
}

# 실행 진입점 — source 되면 라이브러리, 실행되면 원격 주입 1회.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  agent_inject_remote "$@"
  exit $?
fi
