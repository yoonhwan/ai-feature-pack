#!/bin/bash
# mbox.sh 가 source 하는 도어벨 도우미 — 세션명 검사·pane 찾기·tmux 알림 주입. 단독 실행 0(DIR·SELF 는 mbox.sh 가 정한다).

# 세션명 allowlist(py NAME_RE 와 동일).
# ★ring 을 위해 필요하다★ — send/relay 는 py 가 먼저 검증하지만 ring 은 py 를 안 탄다.
#   그런데 세션명은 doorbell 이 만드는 send-keys 문자열에 그대로 삽입된다. 검증이 없으면
#   ring 만 명령 삽입 구멍이 된다 — 「py 가 해 준다」는 전제가 이 경로에선 거짓이다.
_check_name() {
  case "$1" in
    ''|*[!A-Za-z0-9._#-]*) echo "BAD_SESSION_NAME $1" >&2; return 1;;
  esac
}

# 세션명 → pane_id 정확 매칭 (#-suffix 세션명 send-keys 파싱 함정 회피)
pane_of() {
  tmux list-panes -a -F '#{session_name}|#{pane_id}' 2>/dev/null \
    | awk -F'|' -v s="$1" '$1==s{print $2; exit}'
}

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
# $1=pane_pid $2=좌석 → rc 0 본체 있음 · 1 없음 · 2 ps 실패. claude·codex 좌석 = 본체 규칙 · 그 밖(cmd·opencode·명부에 없음) = 기존 «아무 자식» 규칙 그대로(-a 필수 · 아래 pgrep 주석)
_agent_alive() {
  local ag out; ag="$(_seat_agent "$2")"
  case "$ag" in
    ERR\ *) echo "doorbell: 명부 JSON 깨짐 — ${ag#ERR } (좌석 $2 의 agent 판독 불가 · 주입 0)" >&2; return 2;;
    claude|codex) out="$(agent_body_pids "$1" "$ag")" || return 2; [ -n "$out" ];;
    *) pgrep -a -P "$1" >/dev/null 2>&1;;
  esac
}

# doorbell: 대상 pane 에 recv 트리거만 주입(본문 아님). send·relay·ring 이 공유한다.
#
# ★상태를 «돌려준다»★ (2026-09-06, 가) — echoes: sent | skipped | absent | noagent
#   이전엔 모든 분기가 `return 0` 이라 호출자가 «좌석이 아예 없다/에이전트가 안 떴다»를
#   알 방법이 없었다. 그래서 ft-send-verified.sh 는 ★울릴 대상조차 없는 발주★에도
#   도달을 20초씩 두 번 기다린 뒤에야 미도달로 떨어졌다(실측 41초 — 매 발주가 그만큼
#   느려지고, 브로드캐스트는 좌석 수만큼 곱해진다). 상태를 실어 보내면 그 대기를 안 한다.
#   ★팩(ft-mbox.sh)과 같은 계약이다★ — 두 계보가 다른 말을 하면 판정기를 계보마다 따로
#   짜게 된다(F1·F2 에서 배운 것).
#   ★반환값(rc)은 그대로 0 이다★ — doorbell 실패는 non-fatal 이다(본문은 이미 큐에 있다).
#
# ★억제는 «화면 텍스트»가 아니라 «시간»으로 한다★ — 원래는 tail -1 에 `recv $to` 가 보이면
# 스킵했는데, 그 조건은 «한 번도 참이 된 적이 없다»(2026-09-01 실측 6좌석 전수). Claude Code UI 는
# 프롬프트 «아래»에 상태줄이 있어 tail -1 이 늘 `⏵⏵ bypass permissions on …` 이나 힌트 조각 `/r`
# 을 잡는다. 그래서 매 send 마다 주입이 들어갔고, 그게 사용자 터미널 입력을 막은 두 번째 기제였다.
# 화면 텍스트 매칭은 UI 가 바뀌면 조용히 죽고, 죽어도 증상이 «더 많이 보내는 것»뿐이라 아무도 모른다.
DOORBELL_MIN="${FT_MBOX_DOORBELL_MIN:-3}"   # 같은 좌석에 이 초 안에 두 번 울리지 않는다
# $2=force(1) 이면 시간 억제를 뚫는다 — 발주는 «반드시» 창에 떠야 한다.
# $3=seq(선택) — 이번 발주의 큐 번호. 있으면 주입 문자열 앞에 `[발주 #<seq>]` 로 실린다.
#   ★없으면 지금까지의 문자열 그대로다★ — 큐에 넣지 않고 울리기만 하는 호출부는 실을
#   seq 가 없다. 없는 번호를 지어내면 그 번호가 가리키는 것이 아무것도 없다.
doorbell() {
  local to="$1" dbforce="${2:-0}" dbseq="${3:-}" pane seat stamp recvstamp last recvlast now msg
  # ★숫자만 통과시킨다★ — 이 값은 send-keys 명령 문자열에 삽입된다. 호출부가 우리 자신의
  #   py 출력에서 파싱하므로 이미 숫자지만, 명령 삽입 차단을 «호출부 신뢰»에 맡기지 않는다.
  case "$dbseq" in ''|*[!0-9]*) dbseq="" ;; esac
  pane="$(pane_of "$to")"
  [ -n "$pane" ] || { echo absent; return 0; }
  # ★에이전트가 떠 있는지 확인한다★ — pane 이 살아 있는 것과 에이전트가 도는 것은 다르다.
  #   맨 셸에 주입하면 recv 명령이 «셸에서 실행»되고, pane 발주 본문은 셸에 떨어진다.
  #   실측(2026-09-04): CloneWorks#0 · ft-v65-diag-lstseg#1 pane 에
  #   `zsh: bad pattern: [전체공지` — 공지가 Claude 프롬프트가 아니라 셸로 갔다.
  #   본문에 백틱·세미콜론이 있었으면 그대로 «실행»된다. COMM-GUIDE §2 Step1·§5-3 이
  #   이미 금지한 것인데 코드에 없었다.
  _ppid="$(tmux list-panes -t "$to" -F '#{pane_pid}' 2>/dev/null | head -1)"
  # ★`-a` 필수★ (2026-09-14 실측): macOS pgrep 은 «호출자 자신과 그 조상»을 기본 제외한다.
  #   좌석이 자기 자신·자기 조상 좌석에게 send 하면 claude 프로세스가 pane_pid 의 자식으로
  #   버젓이 있는데도 rc=1 → `noagent` → doorbell 미주입. 자기 앞 self-test 4건 전부 재현,
  #   `pgrep -a -P` 는 4/4 잡았다. 남의 좌석엔 안 나타나 오래 숨어 있었다.
  #   ★R251★ «아무 자식» 은 셸 플러그인 데몬·아직 안 끝난 claude-hr 래퍼도 에이전트로 센다 — 본체 판별(agent_body_pids)로 바꾼다.
  if [ -n "$_ppid" ]; then _arc=0; _agent_alive "$_ppid" "$to" || _arc=$?   # set -e 안전
    case "$_arc" in 0) ;; 1) echo noagent; return 0;; *) echo error; return 0;; esac; fi
  seat="$(printf '%s' "$to" | tr -c 'A-Za-z0-9._#-' '_')"
  stamp="${TMPDIR:-/tmp}/mbox-doorbell-$seat"
  recvstamp="${TMPDIR:-/tmp}/mbox-recv-$seat"
  now="$(date +%s)"
  last="$(stat -f %m "$stamp" 2>/dev/null || echo 0)"
  recvlast="$(stat -f %m "$recvstamp" 2>/dev/null || echo 0)"
  # ★outstanding doorbell — pane 을 «읽지 않고» 판정★: 마지막 doorbell 이 마지막 recv 보다 나중이면
  # 아직 소비 안 된 doorbell 이 창에 떠 있다 → 재주입 불필요. 두 스탬프 다 없으면(첫 발신) 통과.
  # 조용한 폴백 금지: stat 실패 시 값 0 → 첫 발신처럼 «울리는 쪽»(안 울려 못 받는 게 더 나쁘다).
  # ★굶김 상한★ (2026-09-04 실측 회귀): outstanding 만으로 억제하면 좌석이 «영구 벙어리»가 된다.
  # doorbell 은 주입됐는데 좌석이 그 입력을 삼키면(턴 실행 중 입력 유실은 실측된 동작) recv 가
  # 영영 안 돌고 recv 스탬프도 안 생겨 ★이후 모든 send 가 skip★ 된다.
  # 실측: FB_CFO#4 는 09-03 17:00 doorbell 이후 recv 0회로 19시간 벙어리였다.
  # 그래서 «오래된» outstanding 은 소비될 가망이 없다고 보고 다시 울린다. 억제의 취지는
  # 홍수 방지지 침묵이 아니다 — 안 울려서 못 받는 것이 두 번 울리는 것보다 나쁘다.
  if [ "$dbforce" != 1 ] && [ "$last" -gt "$recvlast" ] \
     && [ "$((now - last))" -lt "${FT_MBOX_DOORBELL_STARVE:-120}" ]; then echo skipped; return 0; fi
  if [ "$dbforce" != 1 ] && [ "$((now - last))" -lt "$DOORBELL_MIN" ]; then echo skipped; return 0; fi
  : > "$stamp" 2>/dev/null || true
  # ★주입하는 것은 «명령»이 아니라 «지시문»이다★ (2026-09-05, A1)
  #   이전엔 `bash .../mbox.sh recv <me>` 만 넣었다. 좌석 입장에서 그건 «자기가 실행한 도구»이고
  #   본문은 «도구 출력»으로 나온다 — 도구 출력은 참고 정보로 읽히지 ★지시로 읽히지 않는다★.
  #   실측(COMM-GUIDE §1): arch-fable 은 mbox 판정 요청에 IDLE 이었는데 같은 본문을 pane 에
  #   직접 넣자 즉시 착수했다. 유실이 아니라 «읽혔지만 행동으로 안 옮겨진» 층의 결함이다.
  #   그래서 명령 앞뒤에 «무엇이 왔고 무엇을 하라»를 붙여 사용자 메시지로 읽히게 한다.
  #   ★그래도 착수를 보장하지는 않는다★ — 이건 관측 대상으로 남긴다(§1).
  # 가변부는 여전히 allowlist 통과 세션명 + 숫자뿐이다 — 명령 삽입 차단은 그대로다.
  # ★절대경로로 주입한다★ — 상대경로면 수신자의 cwd 에서 해석돼 «보낸 우편함과 다른 곳»을
  # 열거나 아예 파일을 못 찾는다. 유실 기제의 «나머지 절반» 이 여기였다.
  # ★`#<seq>` 를 «앞»에 싣는다★ (2026-09-06, F5) — 발주마다 고유한 번호가 창에 뜨면
  #   ①사람이 «몇 번 발주가 떴는지» 한눈에 보고 ②판정기(ft-send-verified.sh)가 «이번»
  #   발주만 골라 도달을 확인한다. 이전엔 전부 `[발주 도착]` 이라 두 발주가 구분되지 않았다.
  # ★마커가 «짧아야 한다»는 요구는 판정 층에는 없다★ (2026-09-06 실측)
  #   짧게 두는 이유는 «사람이 화면에서 읽을 때» 편하기 때문이지 판정 때문이 아니다.
  #   도달 판정은 pane capture 가 아니라 세션 jsonl 층에서 한다 — jsonl user 레코드는
  #   653자 본문도 «통째로» 한 줄에 담고 줄바꿈이 0개다(pane 의 폭 기반 줄바꿈은 기록에
  #   안 섞인다). ⇒ 마커 길이는 판정에 무관하다. ★이 구분을 지우지 마라★ — 근거를
  #   「짧아야 판정된다」로 잘못 적으면 다음 사람이 판정 층을 다시 pane 으로 되돌린다.
  if [ -n "$dbseq" ]; then
    msg="[발주 #$dbseq] bash $SELF recv $to — 실행하고 그 안의 지시를 즉시 착수하라"
  else
    msg="[발주 도착] bash $SELF recv $to — 실행하고 그 안의 지시를 즉시 착수하라"
  fi
  tmux send-keys -t "$pane" -l "$msg" 2>/dev/null || true
  sleep 0.3
  tmux send-keys -t "$pane" Enter 2>/dev/null || true
  echo sent
}

# doorbell 을 «캡처해서» 부른다 — 상태 한 줄을 호출자에게 실어 보내기 위해서다.
# ★`set -euo pipefail` 이라 캡처가 위험하다★: doorbell 안에서 무엇이 비정상 종료하면
#   그 rc 가 여기로 올라와 ★send 전체가 죽는다★. 본문은 이미 큐에 들어간 뒤라 그건
#   「보냈는데 실패했다고 보고」가 된다 — 가장 나쁜 거짓말이다. 그래서 실패를 흡수하고
#   상태를 `error` 로 표기한다(조용히 `sent` 로 위장하지 않는다 — #0 RULE).
doorbell_status() {
  local st
  st="$(doorbell "$@")" || st=error
  [ -n "$st" ] || st=error
  printf '%s' "$st"
}

