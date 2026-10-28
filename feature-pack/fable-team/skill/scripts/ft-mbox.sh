#!/bin/bash
# ft-mbox.sh — 파일 기반 세션 메시지 큐 래퍼 (fable-team). COMM-GUIDE §1 {mbox}의 실체.
# 본문 = 파일 큐(ft-mbox.py, 유실0), tmux엔 doorbell(recv 트리거)만 주입 — 손상·유실 안전.
# v6-realtime-live mbox.sh 계승 + ft-lib 통합(swap_guard·ROOT 해석)·ft_sess_alive 게이트·ring.
# Usage: ft-mbox.sh {send <to> <from> <body...> [--urgent] | recv <me> [<from>] | peek <me> | ring <sess> [seq]}
# Seatbelt 1.0.0: 알림 여부는 seats.json(tick) 이 정한다 — --no-notify 는 WARN+무시, --urgent 는 항상 울림.
set +e
BINDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$BINDIR/ft-lib.sh"                       # ft_swap_guard 발동 + ft_sess_alive 등 헬퍼
# ★2026-08-25 — 여기서 FT_MBOX_DIR 을 «덮어쓰지» 않는다★
# 이전: ROOT 를 cwd 기준(ft_resolve_root)으로 잡아 FT_MBOX_DIR 을 export 했다. 그래서
# (a) 같은 스크립트가 «부른 사람의 cwd» 에 따라 다른 우편함을 썼고 (b) 사용자가 env 로
# 명시한 FT_MBOX_DIR 마저 덮어써서 회피가 불가능했다 — 실제로 메시지 유실이 났다.
# 지금: 경로 결정은 ft-mbox.py 가 «스크립트 위치에서 유도한 정본» 으로 한다.
# ★ft_resolve_root 자체는 안 건드렸다★ — 다른 ft-* 8개가 그 함수를 쓴다(최소 절개).
MBOXPY="$BINDIR/ft-mbox.py"

# 세션명 allowlist(py NAME_RE와 동일) — 세션명이 doorbell send-keys 명령에 삽입되므로 하드 거부.
_check_name() {
  case "$1" in
    ''|*[!A-Za-z0-9._#-]*) echo "BAD_SESSION_NAME $1" >&2; return 1;;
  esac
}

# 세션명 → pane_id 정확 매칭(#-suffix 세션명 send-keys 파싱 함정 회피, v6 계승)
pane_of() {
  tmux list-panes -a -F '#{session_name}|#{pane_id}' 2>/dev/null \
    | awk -F'|' -v s="$1" '$1==s{print $2; exit}'
}

# doorbell: 대상 세션에 recv 트리거만 주입(본문 아님). 전부 non-fatal(본문은 이미 큐에).
# echoes: sent | skipped | absent
# $2=force(1) 이면 시간 억제를 뚫는다 — 발주는 «반드시» 창에 떠야 한다.
# $3=seq(선택) — 이번 발주의 큐 번호. 있으면 주입 문자열 앞에 `[발주 #<seq>]` 로 실린다.
#   ★없으면 지금까지의 문자열 그대로다★ — ring 처럼 «큐에 넣지 않고 울리기만» 하는
#   호출부는 실을 seq 가 없다. 없는 번호를 지어내면 그 번호가 가리키는 것이 아무것도 없다.
doorbell() {
  local to="$1" dbforce="${2:-0}" dbseq="${3:-}" dbcomm="${4:-}" cap pane _seat _db_stamp _db_recv _db_last _db_recv_last _ppid _msg _env _tail
  # ★숫자만 통과시킨다★ — 이 값은 send-keys 명령 문자열에 삽입된다. 지금 호출부는 우리
  #   자신의 py 출력(`seq=<digits>`)에서 파싱하므로 이미 숫자지만, 명령 삽입 차단을 «호출부
  #   신뢰»에 맡기지 않는다(세션명 allowlist 와 같은 이유). 이상하면 조용히 버리고 무번호로 간다.
  case "$dbseq" in ''|*[!0-9]*) dbseq="" ;; esac
  ft_sess_alive "$to" || { echo absent; return 0; }
  # ★에이전트가 떠 있는지 확인한다 — pane 이 «살아 있다»와 «에이전트가 돈다»는 다르다★
  #   ft_sess_alive 는 pane_pid 에 kill -0 만 하므로 ★맨 셸도 통과★한다. 그 상태에서
  #   주입하면 recv 명령이 «셸에서 실행»되고, 더 나쁘게는 pane 발주 본문이 셸에 떨어진다.
  #   실측(2026-09-04): CloneWorks#0 · ft-v65-diag-lstseg#1 pane 에
  #   `zsh: bad pattern: [전체공지` — 공지가 Claude 프롬프트가 아니라 셸에 떨어졌다.
  #   본문에 백틱·세미콜론이 있었으면 그대로 «실행»된다. COMM-GUIDE §2 Step1·§5-3 이
  #   이미 금지한 것인데 코드에 없었다.
  #   ★ft_sess_alive 자체는 안 고친다★ — 다른 ft-* 스크립트들이 공유하는 함수라
  #   의미를 바꾸면 그쪽 계약까지 흔든다. 여기서만 한 겹 더 본다.
  _ppid="$(tmux list-panes -t "$to" -F '#{pane_pid}' 2>/dev/null | head -1)"
  # ★`-a` 필수★ (2026-09-14 실측): macOS pgrep 은 «호출자 자신과 그 조상»을 기본 제외한다.
  #   좌석이 자기 자신·자기 조상 좌석에게 send 하면 claude 프로세스가 pane_pid 의 자식으로
  #   버젓이 있는데도 rc=1 → `noagent` → doorbell 미주입. 자기 앞 self-test 4건 전부 재현,
  #   `pgrep -a -P` 는 4/4 잡았다. 남의 좌석엔 안 나타나 오래 숨어 있었다.
  if [ -n "$_ppid" ] && ! pgrep -a -P "$_ppid" >/dev/null 2>&1; then
    echo noagent; return 0
  fi
  _seat="$(printf '%s' "$to" | tr -c 'A-Za-z0-9._#-' '_')"
  _db_stamp="${TMPDIR:-/tmp}/mbox-doorbell-$_seat"
  _db_recv="${TMPDIR:-/tmp}/mbox-recv-$_seat"
  # ★outstanding doorbell — pane 을 «읽지 않고» 판정한다★ (설계 §3-2):
  # 마지막 doorbell 이 마지막 recv 보다 나중이면 «아직 소비 안 된 doorbell 이 창에 떠 있다» →
  # 재주입 불필요. capture-pane 을 부르기 «전»에 파일 stat 만으로 끝낸다.
  # 두 스탬프 다 없으면(첫 발신) 통과. --force/dbforce=1 은 뚫는다.
  # ★조용한 폴백 금지★: stat 이 못 읽으면 값이 0 이 되어 첫 발신과 같이 «울리는 쪽»으로 기운다
  #   (안 울려서 못 받는 것이 더 나쁘다).
  # ★굶김 상한★ (2026-09-04 실측 회귀 — 이 상한이 없으면 좌석이 «영구 벙어리»가 된다)
  #   outstanding 만으로 억제하면 이런 경로가 열린다: doorbell 은 주입됐는데 좌석이
  #   그 입력을 «삼켰다»(턴 실행 중 입력 유실은 실측된 동작) → recv 가 영영 안 돌고
  #   recv 스탬프도 안 생긴다 → 이후 모든 send 가 skip → ★그 좌석은 다시는 안 울린다★.
  #   실측: FB_CFO#4 는 09-03 17:00 doorbell 이후 recv 0회로 19시간 벙어리였다.
  #   그래서 «오래된» outstanding 은 소비될 가망이 없다고 보고 다시 울린다.
  #   안 울려서 못 받는 것이 두 번 울리는 것보다 나쁘다 — 억제의 취지는 홍수 방지지
  #   침묵이 아니다.
  _db_last="$(stat -f %m "$_db_stamp" 2>/dev/null || echo 0)"
  _db_recv_last="$(stat -f %m "$_db_recv" 2>/dev/null || echo 0)"
  _db_age="$(( $(date +%s) - _db_last ))"
  if [ "$dbforce" != 1 ] && [ "$_db_last" -gt "$_db_recv_last" ] \
     && [ "$_db_age" -lt "${FT_MBOX_DOORBELL_STARVE:-120}" ]; then
    echo skipped; return 0
  fi
  # 시간 억제(기존 FT_MBOX_DOORBELL_MIN) — 여전히 파일 stat 만, capture-pane 앞이다.
  if [ "$dbforce" != 1 ] && [ "$(( $(date +%s) - _db_last ))" -lt "${FT_MBOX_DOORBELL_MIN:-3}" ]; then
    echo skipped; return 0
  fi
  # ★여기까지 통과했을 때만 pane 을 읽는다★ — 옵션모드 보호와 ❯ 잔류 정리는 실제 주입 직전에만 필요하다.
  # 상태 판독: 옵션모드(Enter to select)면 skip(Escape 금지 — HIL 프롬프트 파괴 방지, 본문은 큐에 안전).
  # 미제출 잔류(❯ 텍스트)면 C-u로 클리어. capture는 invalid UTF-8 섞임 → LC_ALL=C grep -a 바이트매치(V3).
  cap="$(tmux capture-pane -p -t "$to" 2>/dev/null)"
  if printf '%s\n' "$cap" | LC_ALL=C grep -aq 'Enter to select'; then
    echo skipped; return 0
  fi
  if printf '%s\n' "$cap" | LC_ALL=C grep -aqE '❯[[:space:]]+[^[:space:]]'; then
    tmux send-keys -t "$to" C-u 2>/dev/null || true; sleep 0.2
  fi
  pane="$(pane_of "$to")"
  [ -n "$pane" ] || { echo absent; return 0; }
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
  # ★정본 우편함을 명시 env 로 싣는다★ (r403 · 2026-10-19) — 라이브 bin 은 조상 유도가 안 되므로
  #   받는 좌석의 cwd 가 무엇이든 «보낸 우편함» 을 열게 `FT_MBOX_DIR=<절대경로>` 1토큰을 명령 앞에 둔다.
  #   머리 `[발주 #N]` 첫 토큰은 불변(ft-send-verified 판정 영향 0). 경로도 allowlist(명령 삽입 차단).
  _env=""
  case "$dbcomm" in
    /*) case "$dbcomm" in *[!A-Za-z0-9._/#-]*) echo "WARN doorbell 우편함 경로 allowlist 밖 — env 없이 주입: $dbcomm" >&2 ;; *) _env="FT_MBOX_DIR=$dbcomm " ;; esac ;;
  esac
  # ★알림줄 꼬리 — `FT_DOORBELL_TAIL=ultrathink` 일 때만 « ultrathink» 한 낱말★ (r1036)
  #   왜 allowlist(낱말 하나)인가: 이 값도 send-keys 문자열에 들어간다 — 바로 위 r403 경로
  #   allowlist 와 같은 이유다. 아무 글자나 통과시키면 `ultrathink; …` 가 창에 «지시문» 으로 떨어진다.
  #   allowlist 밖은 조용히 무시하지 않고 WARN 1줄(stderr) — 붙기를 기대한 쪽이 «안 붙었다» 를 알아야 한다.
  #   환경변수가 없거나 빈 값이면 지금까지와 «바이트 동일»(WARN 0).
  _tail=""
  if [ -n "${FT_DOORBELL_TAIL:-}" ]; then
    if [ "$FT_DOORBELL_TAIL" = "ultrathink" ]; then
      _tail=" ultrathink"
    else
      echo "WARN doorbell 꼬리 allowlist 밖 — 붙이지 않음" >&2
    fi
  fi
  if [ -n "$dbseq" ]; then
    _msg="[발주 #$dbseq] ${_env}bash $BINDIR/ft-mbox.sh recv $to — 실행하고 그 안의 지시를 즉시 착수하라${_tail}"
  else
    _msg="[발주 도착] ${_env}bash $BINDIR/ft-mbox.sh recv $to — 실행하고 그 안의 지시를 즉시 착수하라${_tail}"
  fi
  tmux send-keys -t "$pane" -l "$_msg" 2>/dev/null || true
  sleep 0.3
  tmux send-keys -t "$pane" Enter 2>/dev/null || true
  : > "$_db_stamp" 2>/dev/null || true   # ★실제 주입 직후에만 doorbell 스탬프 갱신★
  echo sent
}

# ★알림 여부는 «보내는 사람»이 아니라 «레지스트리»가 정한다★ (2026-09-14 · Seatbelt §2-2 · 오빠 결정 Q1)
#   실측: --no-notify 를 틱 없는 좌석(arch-fable#40)에 써서 4틱 무응답(CLAUDE.md STRUCTURAL FIX).
#   HARNESS-TREE 는 「좌석→master 는 무음」, CLAUDE.md 는 「틱 없는 좌석엔 금지」 — 둘 다 맞고
#   ★보내는 쪽이 받는 쪽의 틱 유무를 알 길이 없어서★ 매 send 가 사람 판단이었다.
#   seats.json 의 tick 필드가 그 판단을 대신한다: tick 있음 → 조용히(자기 틱이 recv 한다),
#   tick 없음·미등록 → 울린다(모르는 좌석을 침묵시키지 않는다 — 안 울려 못 받는 쪽이 더 나쁘다).
#   `--urgent` 만 남는다(항상 울림). `--no-notify` 는 받아 주되 ★무시하고 경고★한다 —
#   옛 호출부(틱 스크립트·좌석 습관)가 한동안 남기 때문이고, 무시해야 이 결정이 «강제»가 된다.
#   레지스트리 경로: 정본 우편함 옆 (<루트>/.fable-team/seats.json). env FT_SEATS_JSON 이 이긴다.
#   ★팩에서는 우편함 자리를 py 가 정한다(위 2026-08-25 주석)★ — 셸은 같은 규칙을 «그대로» 따라간다:
#   우편함 자리(`_mbox_dir` · py CANON 과 같은 순서)의 옆 = `<comm>/../seats.json`.
#   못 찾으면 빈 값 → notify_policy 가 ring(fail-loud).
_seats_json() {
  [ -n "${FT_SEATS_JSON:-}" ] && { printf '%s' "$FT_SEATS_JSON"; return; }
  local md; md="$(_mbox_dir)"
  [ -n "$md" ] && printf '%s/../seats.json' "$md"
}
# echoes: quiet | ring — 판정 불가(파일 없음·JSON 깨짐)는 ring (fail-loud 쪽).
notify_policy() {
  local to="$1" sj; sj="$(_seats_json)"
  [ -f "$sj" ] || { echo ring; return 0; }
  python3 - "$sj" "$to" <<'PYEOF' 2>/dev/null || echo ring
import json, sys
sj, to = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(sj, encoding="utf-8"))
except Exception:
    print("ring"); sys.exit(0)
e = d.get(to)
print("quiet" if isinstance(e, dict) and e.get("tick") else "ring")
PYEOF
}

# py 의 `QUEUED seq=<N> …` 한 줄에서 이번 발주의 번호만 뽑는다. 못 뽑으면 빈 값 —
# doorbell 은 그때 무번호 문자열로 간다(조용히 틀린 번호를 싣지 않는다).
seq_of() { printf '%s\n' "$1" | grep -oE 'seq=[0-9]+' | head -1 | cut -d= -f2; }

# 인박스 적재(판정 425-B · R180) — comm/mbox.sh 의 inbox_ingest·inbox_must_ring 과 같은 계약: 전송 직후 1줄 · 실패는 stderr WARN, 전송 rc 불변.
#   적재 줄 `INGEST … cls=<분류>` 의 분류를 INBOX_CLS 에 둔다. 적재 본체(규칙표·중복 seq SKIP)는 ft-inbox 한 곳 — 여기는 부르기만 한다.
#   ★적재 루트 = «py 가 실제 고른 우편함»에서만 유도한다★ (DA⑥ H1) — ft-mbox.py CANON 과 같은 순서: ①FT_MBOX_DIR ②스크립트 위 `.fable-team` 조상(`.worktrees` 조상이 있으면 그 부모)의 .fable-team/comm
#   ③cwd git 공용 루트의 .fable-team/comm «실재» 할 때만(r403 · 라이브 bin) ④빈 값.
#   env FT_ROOT 는 보지 않는다(py 가 안 보므로 — 보면 전송한 우편함과 다른 곳에서 쪽지를 찾아 큐 0). ft-inbox 에는 FT_ROOT=<우편함 두 단계 위> 로 덮어 넘긴다.
_mbox_dir() {
  [ -n "${FT_MBOX_DIR:-}" ] && { printf '%s' "$FT_MBOX_DIR"; return; }
  local d="$BINDIR" root="" gc
  while [ "$d" != "/" ]; do
    if [ "$(basename "$d")" = ".fable-team" ]; then
      root="$(dirname "$d")"; local a="$root"
      while [ "$a" != "/" ]; do [ "$(basename "$a")" = ".worktrees" ] && { root="$(dirname "$a")"; break; }; a="$(dirname "$a")"; done
      break
    fi
    d="$(dirname "$d")"
  done
  [ -n "$root" ] && { printf '%s/.fable-team/comm' "$root"; return; }
  gc="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 0
  [ -n "$gc" ] && [ -d "$(dirname "$gc")/.fable-team/comm" ] && printf '%s/.fable-team/comm' "$(dirname "$gc")"
}
# py `QUEUED … file=<우편함>/mailbox.jsonl` 에서 «이번 send 가 실제로 쓴» 우편함 절대경로. 못 뽑으면 빈 값.
comm_of() {
  local f; f="$(printf '%s\n' "$1" | grep -oE 'file=[^ ]+' | head -1 | cut -d= -f2-)"
  [ -n "$f" ] && (cd "$(dirname "$f")" 2>/dev/null && pwd)
}
# r488 자가 점검: 보낸 seq 행이 보관 로그(mailbox.log.jsonl)에 정확히 1행인가 — 아니면 stderr WARN(전송 rc 불변 · fail-open).
sent_log_check() {  # <seq> <우편함 comm 절대경로>
  local n f="$2/mailbox.log.jsonl"
  [ -n "$1" ] && [ -n "$2" ] || return 0
  n="$(grep -c "\"seq\": $1," "$f" 2>/dev/null)" || true
  [ "${n:-0}" = 1 ] || echo "WARN sent-log ${n:-0} seq=$1 file=$f" >&2
  return 0
}
inbox_ingest() {
  INBOX_CLS=""; [ -n "$1" ] || return 0
  local o md root
  md="$(_mbox_dir)"; md="$(cd "$md" 2>/dev/null && pwd -P)"
  case "$md" in
    */.fable-team/comm) root="${md%/.fable-team/comm}" ;;
    *) echo "WARN inbox ingest 건너뜀 — 우편함 경로가 <루트>/.fable-team/comm 꼴 아님: ${md:-$(_mbox_dir)} (쪽지 전송은 완료)" >&2; return 0 ;;
  esac
  o="$(FT_ROOT="$root" bash "$BINDIR/ft-inbox.sh" ingest "$1" 2>/dev/null)" || { echo "WARN inbox ingest 실패 seq=$1 (쪽지 전송은 완료)" >&2; return 0; }
  INBOX_CLS="$(printf '%s\n' "$o" | sed -n 's/^INGEST .* cls=\([^ ]*\) .*/\1/p' | head -1)" || INBOX_CLS=""
  return 0
}
# ①~④·미상(보고 의무 분류)이면 받는 좌석의 tick 유무와 무관하게 울린다. ⑤⑥·적재 실패·SKIP 은 notify_policy 그대로.
inbox_must_ring() { case "$INBOX_CLS" in ①|②|③|④|미상) return 0;; *) return 1;; esac; }

# ★오빠 대면 좌석(현역 planner = seats-planner.json `_master`)에는 doorbell 을 주입하지 않는다 — 큐만 적재(판정 876 · comm/mbox.sh user_facing 과 같은 계약).
#   doorbell 이 오빠가 치는 문장 중간에 끼어 절단된다. --urgent·분류 ①~④ 도 이 좌석엔 울리지 않는다. 명시적 `ring` 명령만 예외. 판정 불가(레지스트리 경로·파일 없음·깨짐)는 기존대로(울림).
user_facing() {
  local sj pj; sj="$(_seats_json)"; [ -n "$sj" ] || return 1
  pj="$(dirname "$sj")/seats-planner.json"
  [ -f "$pj" ] || return 1
  python3 - "$pj" "$1" <<'PYEOF' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(1)
sys.exit(0 if d.get("_master") == sys.argv[2] else 1)
PYEOF
}

# ★user_facing 좌석의 quiet 는 세션 안 감시(`ft-inbox-watch.sh <좌석>` · Monitor)와 한 쌍이다(판정 876·881)★ — 감시가 없으면 quiet = «아무도 안 받음»(r408 · 승계 #71→#72 뒤 미기동 · 큐 3~5분 적체).
#   감시의 실체 = ft-inbox-watch.sh 가 exec 한 `python3 -u - <bin> <좌석>`(셸 이름은 프로세스에 안 남는다 · 10-19 실측 planner#72 pid 60861).
#   판정 = 그 꼴의 끝 인자가 좌석 이름과 정확 일치(접두 일치 0 — #7 ≠ #72) ∧ <bin>/ft-inbox-watch.sh 실재 · 본문에 시작 명령을 실은 send 프로세스는 꼴이 달라 제외.
#   목록 = FT_PGREP(시험 대체) 또는 pgrep -lf (`<pid> <명령줄>`).
watch_alive() {
  local d
  while IFS= read -r d; do [ -f "$d/ft-inbox-watch.sh" ] && return 0; done < <(
    "${FT_PGREP:-pgrep}" -lf 'ython[^ ]* -u - /' 2>/dev/null | awk -v to="$1" '
      $NF == to && $(NF-2) == "-" && $(NF-3) == "-u" && $(NF-4) ~ /(^|\/)[Pp]ython[0-9.]*$/ { print $(NF-1) }')
  return 1
}
# 감시 없음 → 하네스 master(seats-harness.json `_master`)에 긴급 1통 · 같은 좌석 10분 1회(표식 <루트>/.fable-team/state/planner-watch-missing.<좌석> mtime).
#   ★r928 r3 유예 = 표본기가 본 «처음 없음»★ — 감시(ft-inbox-watch.sh)는 아무것도 쓰지 않는다(R1). 쓰는 쪽은 60초 표본기 하나(ft-tick 매 루프 → `ft-mbox.sh watch-sample`).
#     표본 파일 state/planner-watch-absent-since.<좌석> = «<표본 epoch>\t<처음 없음 epoch | 0=감시 있음>» 1줄 — absent-since 와 heartbeat 를 한 파일 두 칸으로(임시 파일+mv 원자 교체 · 두 파일 사이 경합 0).
#     송신 쪽(여기)은 읽기만(R2): 표본이 FT_WATCH_SAMPLE_STALE_SEC(180) 안 ∧ 처음 없음이 FT_WATCH_REARM_GRACE_SEC(300) 안 → 긴급 0 · stderr `WATCH-REARM 대기 <분>` 1줄.
#       감시가 살아 있던 동안 송신이 없어도 «처음 없음» 은 표본기가 60초마다 지운다 — 다음 공백 첫 송신에 옛 시각으로 곧장 긴급이 나가지 않는다(RESEARCH H2·H3).
#     ★이상은 모두 긴급 쪽(R3)★ — 표본기 실패 표식(<표본 파일>.broken · r4)·표본 없음·180초 넘음(표본 멈춤)·심링크·일반 파일 아님·state 폴더 쓰기 불가·읽기 실패·본문이 정수 두 칸 아님·미래 값 → 유예 0 + stderr `WATCH-ABSENT 표본 멈춤(<사유>)`/`WATCH-ABSENT 이상(<사유>)` 1줄.
#     Monitor 는 최대 30분이면 꺼지고 다시 거는 틈이 생긴다 — 그 틈을 «감시 없음» 긴급으로 보내면 받는 쪽이 오탐으로 의심한다(판정 1125 · 300초 = 재걸기 공백 67% 를 덮는 값).
#   큐 직접 적재(py send · 이 래퍼 send 재귀 0 · 발신자 = 도구 이름이라 FANOUT·RATE 면제 · 본문에 계기 쪽지 번호 = 같은 본문 재발신 가드(RESEND_COOLDOWN)에 10분 뒤 재알림이 막히지 않게) · 실패·master 없음 = stderr 1줄(표식 0 → 다음 send 재시도). 오빠 pane 주입 0(876 불변).
#   긴급 본문의 근거 줄 = `감시 프로세스 0(pgrep) · <처음 없음 HH:MM(N분) | 표본 이상(<사유>)>` — 받는 쪽이 오탐·진짜를 바로 가른다.
#   _absent_grace <표본 파일> <유예초> <표본 신선초> → rc0 유예 · rc1 유예 밖 · rc3 이상(stderr 1줄) — 셋 다 stdout = 근거 조각
_ep_hhmm() { date -r "$1" +%H:%M 2>/dev/null || date -d "@$1" +%H:%M 2>/dev/null || printf '?'; }
_absent_grace() {
  local f="$1" grace="$2" stale="$3" line s="" a="" now why=""
  now="$(date +%s)"
  if [ -e "$f.broken" ] || [ -L "$f.broken" ]; then why="표본기 실패 표식"
  elif [ -L "$f" ]; then why="심링크"
  elif [ -e "$f" ] && [ ! -f "$f" ]; then why="일반 파일 아님"
  elif [ ! -e "$f" ]; then why="표본 없음"
  elif [ ! -w "$(dirname "$f")" ]; then why="state 쓰기 불가"
  elif ! line="$(head -1 "$f" 2>/dev/null)"; then why="읽기 실패"
  else
    case "$line" in *$'\t'*) s="${line%%$'\t'*}"; a="${line#*$'\t'}" ;; esac
    case "$s" in ''|*[!0-9]*) why="본문 깨짐" ;; esac
    case "$a" in ''|*[!0-9]*) why="본문 깨짐" ;; esac
    if [ -z "$why" ] && { [ "${#s}" -gt 12 ] || [ "${#a}" -gt 12 ]; }; then why="본문 깨짐"; fi
    if [ -z "$why" ]; then
      s=$((10#$s)); a=$((10#$a))
      if [ "$s" -gt "$now" ]; then why="미래 표본"
      elif [ $((now - s)) -gt "$stale" ]; then why="표본 멈춤 $((now - s))초 전"
      elif [ "$a" -gt "$s" ]; then why="미래 처음 없음"
      fi
    fi
  fi
  if [ -n "$why" ]; then
    case "$why" in 표본\ 없음|표본\ 멈춤*) echo "WATCH-ABSENT 표본 멈춤($why) $f" >&2 ;; *) echo "WATCH-ABSENT 이상($why) $f" >&2 ;; esac
    printf '표본 이상(%s)' "$why"; return 3
  fi
  if [ "$a" = 0 ]; then printf '0분 · 처음 없음 표본 전(마지막 표본 %s 감시 있음)' "$(_ep_hhmm "$s")"; return 0; fi
  if [ $((now - a)) -lt "$grace" ]; then printf '%s분 · 처음 없음 %s' "$(( (now - a) / 60 ))" "$(_ep_hhmm "$a")"; return 0; fi
  printf '처음 없음 %s(%s분)' "$(_ep_hhmm "$a")" "$(( (now - a) / 60 ))"; return 1
}
watch_alarm() {  # <to> <우편함 comm 절대경로(빈 값 → _mbox_dir)> <계기 쪽지 seq>
  local to="$1" ft hs hm mk af ev q grc=0
  ft="$(dirname "${2:-$(_mbox_dir)}")"
  mk="$ft/state/planner-watch-missing.$(printf '%s' "$to" | tr -c 'A-Za-z0-9._#-' '_')"
  af="$ft/state/planner-watch-absent-since.$(printf '%s' "$to" | tr -c 'A-Za-z0-9._#-' '_')"
  [ -n "$(find "$mk" -mmin -10 2>/dev/null)" ] && return 0
  ev="$(_absent_grace "$af" "${FT_WATCH_REARM_GRACE_SEC:-300}" "${FT_WATCH_SAMPLE_STALE_SEC:-180}")" || grc=$?
  if [ "$grc" = 0 ]; then
    echo "WATCH-REARM 대기 $ev — $to 다시 거는 틈이라 긴급 0통($af)" >&2
    return 0
  fi
  hs="${FT_HARNESS_SEATS_JSON:-$ft/seats-harness.json}"
  hm="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8")).get("_master") or "")' "$hs" 2>/dev/null)"
  [ -n "$hm" ] || { echo "WARN planner watch 없음 $to — 하네스 master 를 못 찾음($hs) · 긴급 0통" >&2; return 0; }
  q="$(python3 "$MBOXPY" send "$hm" ft-watch-alarm "[긴급 · planner watch 없음] $to · 감지 $(date +%H:%M) · 계기 쪽지 #${3:-?} · 감시 프로세스 0(pgrep) · $ev · 시작: Monitor → bash $ft/bin/ft-inbox-watch.sh $to")" \
    || { echo "WARN planner watch 없음 $to — 긴급 적재 실패(다음 send 재시도)" >&2; return 0; }
  mkdir -p "$ft/state" && : > "$mk"
  echo "WARN planner watch 없음 $to — 하네스 master $hm 긴급 seq=$(seq_of "$q")" >&2
}
# user_facing send/relay 공통: 감시 없으면 db 에 꼬리 «(WATCH 없음)» 을 붙이고(quiet → quiet(WATCH 없음)) 알린다. 감시 있으면 db 그대로.
uf_watch() { watch_alive "$1" && return 0; db="${db}(WATCH 없음)"; watch_alarm "$1" "$2" "$3"; }
# ★r928 r3 표본기 — 표본 파일의 유일한 쓰는 쪽★ (ft-tick 이 60초마다 `watch-sample <planner _master> <comm>`)
#   감시 있음 → «<지금>\t0» · 없음 → 앞 표본이 «정상»(두 칸 정수 · 표본 ≤ 지금 · 처음 없음 ≤ 표본)이고 처음 없음 > 0 이면 그 값 그대로, 없거나 0(감시 있었음)이면 «<지금>\t<지금>».
#   ★r4 원칙 «표본기가 실패하면 옛 파일을 믿지 않는다»(DECISION-r928-r4-final 고침 1·2)★ — 아래는 모두 _sample_fail: stderr `WATCH-ABSENT 이상(<사유>)` 1줄 + 표본 파일 지움
#     (못 지우면 같은 폴더 `<파일>.broken` 표식 · 그것도 실패면 stderr 1줄 더) + rc1. 송신 쪽은 표본 없음·.broken 을 긴급으로 본다 · 지운 뒤 다음 표본이 새로 시작한다.
#     쓰기 실패(감시 없음) · 지우기 실패(감시 있음 = 0 으로 덮기) · 앞 표본이 심링크·일반 파일 아님·읽기 실패·본문 깨짐·미래(첫 칸이든 둘째 칸이든 «되살리기» 0).
#   표본을 쓰는 데 성공하면 .broken 표식을 지운다(못 지우면 stderr + rc1 — 송신 쪽은 계속 긴급).
_sample_put() {  # <파일> <처음 없음 epoch|0> <지금> — 같은 폴더 임시 파일 + mv(원자 · 반쯤 쓴 표본 0)
  local t
  t="$(mktemp "$(dirname "$1")/.watch-sample.XXXXXX" 2>/dev/null)" || return 1
  printf '%s\t%s\n' "$3" "$2" > "$t" 2>/dev/null && mv -f "$t" "$1" 2>/dev/null && return 0
  rm -f "$t" 2>/dev/null; return 1
}
_sample_fail() {  # <파일> <사유> — 언제나 rc1
  echo "WATCH-ABSENT 이상($2) $1" >&2
  rm -f "$1" 2>/dev/null
  if [ -e "$1" ] || [ -L "$1" ]; then
    : > "$1.broken" 2>/dev/null || echo "WATCH-ABSENT 이상(.broken 표식 실패 · 옛 표본 남음) $1" >&2
  fi
  return 1
}
_sample_ok() {  # <파일> — 쓰기 성공 뒤 .broken 표식 정리
  rm -f "$1.broken" 2>/dev/null
  if [ -e "$1.broken" ] || [ -L "$1.broken" ]; then echo "WATCH-ABSENT 이상(.broken 표식 못 지움) $1" >&2; return 1; fi
  return 0
}
watch_sample() {  # <좌석> <우편함 comm 절대경로(빈 값 → _mbox_dir)>
  local to="$1" st f now line s="" a=""
  st="$(dirname "${2:-$(_mbox_dir)}")/state"
  f="$st/planner-watch-absent-since.$(printf '%s' "$to" | tr -c 'A-Za-z0-9._#-' '_')"
  now="$(date +%s)"; mkdir -p "$st" 2>/dev/null
  if [ -L "$f" ] || { [ -e "$f" ] && [ ! -f "$f" ]; }; then _sample_fail "$f" "일반 파일 아님"; return 1; fi
  if watch_alive "$to"; then
    _sample_put "$f" 0 "$now" || { _sample_fail "$f" "지우기 실패"; return 1; }
    _sample_ok "$f" || return 1
    echo "SAMPLE alive $to"; return 0
  fi
  if [ -e "$f" ]; then
    line="$(head -1 "$f" 2>/dev/null)" || { _sample_fail "$f" "읽기 실패"; return 1; }
    case "$line" in *$'\t'*) s="${line%%$'\t'*}"; a="${line#*$'\t'}" ;; *) s="x" ;; esac
    case "$s" in ''|*[!0-9]*) _sample_fail "$f" "본문 깨짐"; return 1 ;; esac
    case "$a" in ''|*[!0-9]*) _sample_fail "$f" "본문 깨짐"; return 1 ;; esac
    if [ "${#s}" -gt 12 ] || [ "${#a}" -gt 12 ]; then _sample_fail "$f" "본문 깨짐"; return 1; fi
    s=$((10#$s)); a=$((10#$a))
    if [ "$s" -gt "$now" ] || [ "$a" -gt "$s" ]; then _sample_fail "$f" "미래 값"; return 1; fi
  fi
  [ -n "$a" ] && [ "$a" != 0 ] || a="$now"
  _sample_put "$f" "$a" "$now" || { _sample_fail "$f" "쓰기 실패"; return 1; }
  _sample_ok "$f" || return 1
  echo "SAMPLE absent $to since=$a"; return 0
}

cmd="${1:-}"; shift || true
case "$cmd" in
  send)
    to="${1:?to}"; from="${2:?from}"; shift 2
    force=(); dispatch=(); dbf=0; urgent=0
    args=()
    for a in "$@"; do
      case "$a" in
        --no-notify) echo "WARN --no-notify 는 무시된다 — 알림은 seats.json 이 정한다(§2-2). 급하면 --urgent" >&2 ;;
        --urgent)    urgent=1 ;;
        --force)     force=(--force); dbf=1 ;;
        --dispatch)  dispatch=(--dispatch); dbf=1 ;;   # ★F5: 발주 — EMPTY_BODY만 판정, doorbell 강제 유지.
        *)           args+=("$a") ;;
      esac
    done
    if [ "$urgent" = 1 ] || [ "$(notify_policy "$to")" = ring ]; then notify=1; else notify=0; fi
    # py가 allowlist 검증(BAD_SESSION_NAME exit 1) + 발신 가드(BLOCKED exit 3) + 큐잉.
    # 거부되면 doorbell 을 울리지 않는다 — 큐에 들어간 게 없다.
    # 사건 원장 훅(PLAN-status-sheet §3-1): 머리 [정지 레디]·[완료]·[완료·휴식] 만 — 본문 sha16 키 · prepared 못 쓰면 적재 0
    SE="$BINDIR/ft-sheet-events.sh"; SK=""
    if [ -f "$SE" ]; then SK="$(bash "$SE" key mbox "$from" "${args[*]}" 2>/dev/null)"; fi
    if [ -n "$SK" ]; then
      bash "$SE" prepare "$SK" "$(python3 -c 'import json,sys;print(json.dumps(dict(zip(("ev","team","id","seat","ref","by"),sys.argv[1:]))))' "${SK%%:*}" "" "" "$from" "" mbox)" >/dev/null || { echo "REJECT 사건 원장 prepared 실패 — 큐 적재 0" >&2; exit 1; }
    fi
    py_out="$(python3 "$MBOXPY" send "$to" "$from" "${args[*]}" ${force[@]+"${force[@]}"} ${dispatch[@]+"${dispatch[@]}"})" || { _rc=$?; [ -z "$SK" ] || bash "$SE" abort "$SK"; exit $_rc; }
    [ -z "$SK" ] || bash "$SE" commit "$SK" --ref "seq $(seq_of "$py_out")" >/dev/null || true
    sent_log_check "$(seq_of "$py_out")" "$(comm_of "$py_out")"
    inbox_ingest "$(seq_of "$py_out")"
    if inbox_must_ring; then notify=1; fi
    uf=0; if user_facing "$to"; then notify=0; uf=1; fi
    if [ "$notify" = 1 ]; then db="$(doorbell "$to" "$dbf" "$(seq_of "$py_out")" "$(comm_of "$py_out")")"; else db=quiet; fi
    [ "$uf" = 0 ] || uf_watch "$to" "$(comm_of "$py_out")" "$(seq_of "$py_out")"
    echo "$py_out doorbell=$db"
    ;;
  relay)
    # 긴 본문의 정본 절차: 원문을 RELAY_DIR(기본 /tmp/mbox)로 복사하고 요약+경로만 큐잉.
    to="${1:?to}"; from="${2:?from}"; file="${3:?file}"; shift 3
    args=(); force=(); urgent=0
    for a in "$@"; do
      case "$a" in
        --no-notify) echo "WARN --no-notify 는 무시된다 — 알림은 seats.json 이 정한다(§2-2). 급하면 --urgent" >&2 ;;
        --urgent)    urgent=1 ;;
        --force)     force=(--force) ;;   # ★F3: relay 도 재발신 탈출구 — 요약 텍스트에 안 섞이게 파싱.
        *)           args+=("$a") ;;
      esac
    done
    if [ "$urgent" = 1 ] || [ "$(notify_policy "$to")" = ring ]; then notify=1; else notify=0; fi
    py_out="$(python3 "$MBOXPY" relay "$to" "$from" "$file" "${args[*]}" ${force[@]+"${force[@]}"})" || exit $?
    # relay 도 결국 send 를 타므로 출력에 `seq=` 가 있다 — 같은 번호를 창에도 싣는다.
    sent_log_check "$(seq_of "$py_out")" "$(comm_of "$py_out")"
    inbox_ingest "$(seq_of "$py_out")"
    if inbox_must_ring; then notify=1; fi
    uf=0; if user_facing "$to"; then notify=0; uf=1; fi
    if [ "$notify" = 1 ]; then db="$(doorbell "$to" 0 "$(seq_of "$py_out")" "$(comm_of "$py_out")")"; else db=quiet; fi
    [ "$uf" = 0 ] || uf_watch "$to" "$(comm_of "$py_out")" "$(seq_of "$py_out")"
    echo "$py_out doorbell=$db"
    ;;
  recv)  me="${1:?me}"; shift
         # ★recv 스탬프 touch — doorbell outstanding 판정의 «소비» 신호★. py 는 여러 경로로 불리므로
         #   sh 래퍼의 recv case 에서 touch 한다(설계 §3-2). exec 전에 해야 실행된다.
         : > "${TMPDIR:-/tmp}/mbox-recv-$(printf '%s' "$me" | tr -c 'A-Za-z0-9._#-' '_')" 2>/dev/null || true
         exec python3 "$MBOXPY" recv "$me" "$@" ;;
  peek)  exec python3 "$MBOXPY" peek "${1:?me}" ;;
  # ring — ★큐를 건드리지 않고 doorbell 만 울린다★. 재발주가 이 경로로 온다.
  #   ★seq 를 실을 수 있다★ (2026-09-06, 나) — 재발주는 1차 발주의 번호를 «그대로» 다시
  #   울린다. 새 번호를 만들면 큐에 없는 번호가 창에 뜨고, 판정 마커도 따라 바뀐다.
  #   ★force=1★ — 재발주는 «반드시» 창에 떠야 한다. 시간·outstanding 억제에 걸려 아무것도
  #   안 뜨면 그건 미도달과 구분이 안 된다. 억제의 취지는 홍수 방지지 재발주 봉쇄가 아니다.
  ring)  sess="${1:?sess}"; _check_name "$sess" || exit 1
         _rc_md="$(_mbox_dir)"; _rc_md="$( [ -n "$_rc_md" ] && cd "$_rc_md" 2>/dev/null && pwd )"
         db="$(doorbell "$sess" 1 "${2:-}" "$_rc_md")"; echo "RING $sess doorbell=$db" ;;
  # watch-alive — 세션 안 감시 실재 판정(판정기 하나 · ft_teamset.py 도 이것을 부른다 · r408). rc0 `OK` / rc3 `NO` · 큐·pane 무변경.
  watch-alive) sess="${1:?sess}"; if watch_alive "$sess"; then echo "OK watch $sess"; else echo "NO watch $sess"; exit 3; fi ;;
  # watch-sample — r928 r3 표본기(ft-tick 60초 루프 · 표본 파일의 유일한 쓰는 쪽). rc0 `SAMPLE alive|absent …` / rc1 이상(stderr 1줄) · 큐·pane 무변경.
  watch-sample) sess="${1:?sess}"; watch_sample "$sess" "${2:-}" || exit 1 ;;
  *) echo "usage: ft-mbox.sh {send <to> <from> <body> [--urgent] [--force]|relay <to> <from> <file> <summary>|recv <me> [<from>] [--all]|peek <me>|ring <sess> [seq]|watch-alive <sess>|watch-sample <sess> [<comm>]}" >&2; exit 2;;
esac
