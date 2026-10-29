#!/bin/bash
# 파일 기반 세션 메시지 큐 (mbox) — 파일 큐 + push 알림 하이브리드.
# send = 파일 append + 수신자 tmux에 recv 트리거 주입(push). 본문은 파일(유실0), tmux엔 트리거만.
# LIFO·per-to 10 ring·fcntl.flock·consume-on-read·to==me grep.
# Usage: mbox.sh {send <to> <from> <body...> [--urgent] | recv <me> | peek <me> | ring <sess> [seq]}
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MBOXPY="$DIR/mbox.py"
SELF="$DIR/mbox.sh"

# 도어벨 도우미(_check_name·pane_of·doorbell·doorbell_status) = 같은 폴더 mbox_doorbell.sh — 200줄 규칙 분리
source "$DIR/mbox_doorbell.sh"
# 수신자 판정(은퇴·닫힌 좌석 REJECT)·planner 앞 허용 머리 = 같은 폴더 mbox_guard.sh (N3 · 판정 1070·1079) — 200줄 규칙 분리
source "$DIR/mbox_guard.sh"
# ★알림 여부는 «보내는 사람»이 아니라 «레지스트리»가 정한다★ (2026-09-14 · 하네스 업그레이드 §2-2 · 오빠 결정 Q1)
#   실측: --no-notify 를 틱 없는 좌석(arch-fable#40)에 써서 4틱 무응답(CLAUDE.md STRUCTURAL FIX).
#   HARNESS-TREE 는 「좌석→master 는 무음」, CLAUDE.md 는 「틱 없는 좌석엔 금지」 — 둘 다 맞고
#   ★보내는 쪽이 받는 쪽의 틱 유무를 알 길이 없어서★ 매 send 가 사람 판단이었다.
#   seats.json 의 tick 필드가 그 판단을 대신한다: tick 있음 → 조용히(자기 틱이 recv 한다),
#   tick 없음·미등록 → 울린다(모르는 좌석을 침묵시키지 않는다 — 안 울려 못 받는 쪽이 더 나쁘다).
#   `--urgent` 만 남는다(항상 울림). `--no-notify` 는 받아 주되 ★무시하고 경고★한다 —
#   옛 호출부(틱 스크립트·좌석 습관)가 한동안 남기 때문이고, 무시해야 이 결정이 «강제»가 된다.
#   레지스트리 경로: 정본 우편함 옆 (<루트>/.fable-team/seats.json). env FT_SEATS_JSON 이 이긴다.
_seats_json() {
  [ -n "${FT_SEATS_JSON:-}" ] && { printf '%s' "$FT_SEATS_JSON"; return; }
  local d="$DIR"
  while [ "$d" != "/" ]; do
    case "$(basename "$d")" in .worktrees) printf '%s/.fable-team/seats.json' "$(dirname "$d")"; return;; esac
    d="$(dirname "$d")"
  done
  printf '%s/../seats.json' "$DIR"
}
# echoes: quiet | ring — 판정 불가(파일 없음·JSON 깨짐)는 ring (fail-loud 쪽).
notify_policy() {
  local to="$1" sj; sj="$(_seats_json)"
  [ -f "$sj" ] || { echo ring; return 0; }
  python3 - "$sj" "$to" <<'PY' 2>/dev/null || echo ring
import json, sys
sj, to = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(sj, encoding="utf-8"))
except Exception:
    print("ring"); sys.exit(0)
e = d.get(to)
print("quiet" if isinstance(e, dict) and e.get("tick") else "ring")
PY
}

# ★오빠 대면 좌석(현역 planner = seats-planner.json `_master`)에는 doorbell 을 주입하지 않는다 — 큐만 적재(10-10 오빠 「이렇게 잘라먹는데」 · 판정 876).
#   doorbell 은 pane 에 `[발주 #N] recv …` 를 send-keys 로 쳐 넣어 오빠가 치는 문장 중간에 끼어 절단된다(오늘 5회+). planner 는 세션 안 감시(ft-inbox-watch.sh + Monitor)로 받는다 · 10분 틱은 안전망.
#   --urgent·분류 ①~④ 도 이 좌석엔 울리지 않는다. 명시적 `ring` 명령만 예외(사람이 일부러 부를 때). 판정 불가(파일 없음·깨짐)는 기존대로.
#   되돌림: 이 함수 본문을 `return 1` 로 바꾸거나 mbox.sh.bak-userfacing-1010 복원.
user_facing() {
  local sj pj; sj="$(_seats_json)"; pj="$(dirname "$sj")/seats-planner.json"
  [ -f "$pj" ] || return 1
  python3 - "$pj" "$1" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(1)
sys.exit(0 if d.get("_master") == sys.argv[2] else 1)
PY
}
# ★user_facing 좌석의 quiet = 세션 안 감시와 한 쌍(r408)★ — 판정기는 bin/ft-mbox.sh watch-alive 하나(팩 키트 send 와 같은 판정). 오빠 pane 주입 0(876 불변).
#   감시 없음 → db 꼬리 `(WATCH 없음)`(quiet → `quiet(WATCH 없음)`) + 하네스 master(seats-harness.json `_master`) 긴급 1통(같은 좌석 10분 1회 · 표식 <루트>/.fable-team/state/planner-watch-missing.<좌석> · 본문에 계기 쪽지 번호 = 같은 본문 재발신 가드에 재알림이 막히지 않게).
#   ★r928 r3 유예★: 표본 파일(state/planner-watch-absent-since.<좌석> = «<표본 epoch>\t<처음 없음 epoch | 0=감시 있음>» · 쓰는 쪽 = ft-tick 60초 표본기 `bin/ft-mbox.sh watch-sample` 하나 · 감시는 쓰기 0)을 읽기만 한다.
#     표본 180초(FT_WATCH_SAMPLE_STALE_SEC) 안 ∧ 처음 없음 300초(FT_WATCH_REARM_GRACE_SEC) 안 → 긴급 0 · stderr `WATCH-REARM 대기 <분>` 1줄 — Monitor 30분 한도 뒤 «다시 거는 틈»(판정 1125).
#     이상은 모두 긴급 쪽 — 표본기 실패 표식(<표본 파일>.broken · r4)·표본 없음·멈춤·심링크·폴더·state 쓰기 불가·읽기 실패·정수 두 칸 아님·미래 값 → stderr `WATCH-ABSENT 표본 멈춤(<사유>)`/`WATCH-ABSENT 이상(<사유>)` 1줄. 판정 본문은 bin/ft-mbox.sh 와 같은 함수(_absent_grace).
#     긴급 본문 근거 줄 = `감시 프로세스 0(pgrep) · <처음 없음 HH:MM(N분) | 표본 이상(<사유>)>`.
#   판정 불가 = 꼬리 `(WATCH 판정 불가)` + stderr(조용한 통과 0) · 적재 실패·master 없음 = stderr 1줄(표식 0 → 다음 send 재시도).
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
uf_watch() {  # <to> <계기 쪽지 seq>
  local to="$1" ft="$DIR/.." o rc=0 hm mk af ev q grc=0
  o="$(bash "${FT_BIN:-$DIR/../bin}/ft-mbox.sh" watch-alive "$to" 2>/dev/null)" || rc=$?
  [ "$rc" = 0 ] && return 0
  case "$rc:$o" in 3:"NO watch"*) ;; *) db="${db}(WATCH 판정 불가)"; echo "WARN planner watch 판정 불가 rc=$rc $to: ${o:0:80}" >&2; return 0;; esac
  db="${db}(WATCH 없음)"
  mk="$ft/state/planner-watch-missing.$(printf '%s' "$to" | tr -c 'A-Za-z0-9._#-' '_')"
  af="$ft/state/planner-watch-absent-since.$(printf '%s' "$to" | tr -c 'A-Za-z0-9._#-' '_')"
  [ -n "$(find "$mk" -mmin -10 2>/dev/null)" ] && return 0
  ev="$(_absent_grace "$af" "${FT_WATCH_REARM_GRACE_SEC:-300}" "${FT_WATCH_SAMPLE_STALE_SEC:-180}")" || grc=$?
  if [ "$grc" = 0 ]; then
    echo "WATCH-REARM 대기 $ev — $to 다시 거는 틈이라 긴급 0통($af)" >&2
    return 0
  fi
  hm="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8")).get("_master") or "")' "${FT_HARNESS_SEATS_JSON:-$ft/seats-harness.json}" 2>/dev/null)" || hm=""
  [ -n "$hm" ] || { echo "WARN planner watch 없음 $to — 하네스 master 를 못 찾음 · 긴급 0통" >&2; return 0; }
  q="$(python3 "$MBOXPY" send "$hm" ft-watch-alarm "[긴급 · planner watch 없음] $to · 감지 $(date +%H:%M) · 계기 쪽지 #${2:-?} · 감시 프로세스 0(pgrep) · $ev · 시작: Monitor → bash $(cd "$ft" && pwd)/bin/ft-inbox-watch.sh $to")" \
    || { echo "WARN planner watch 없음 $to — 긴급 적재 실패(다음 send 재시도)" >&2; return 0; }
  mkdir -p "$ft/state" && : > "$mk"
  echo "WARN planner watch 없음 $to — 하네스 master $hm 긴급 $(seq_of "$q" || true)" >&2
}

# py 의 `QUEUED seq=<N> …` 한 줄에서 이번 발주의 번호만 뽑는다. 못 뽑으면 빈 값.
# ★`set -euo pipefail` 이라 실패를 «반드시» 삼켜야 한다★ — grep 이 0건이면 rc1 이고
#   pipefail 이 그것을 파이프라인 rc 로 올린다. 호출부에서 `|| seq=""` 로 받는다.
seq_of() { printf '%s\n' "$1" | grep -oE 'seq=[0-9]+' | head -1 | cut -d= -f2; }

# 인박스 적재(판정 425-B) — 큐 적재 직후 1줄 · 규칙표만 즉시(Haiku 는 ft-inbox 가 분리 실행) · 실패는 stderr WARN, 전송 rc 불변.
#   적재 줄 `INGEST … cls=<분류>` 의 분류를 INBOX_CLS 에 둔다 — 알림 결정(inbox_must_ring)이 읽는다(판정 423 ③).
inbox_ingest() {
  INBOX_CLS=""; [ -n "$1" ] || return 0
  local o
  o="$(FT_ROOT="${FT_ROOT:-$DIR/../..}" bash "$DIR/../bin/ft-inbox.sh" ingest "$1" 2>/dev/null)" || { echo "WARN inbox ingest 실패 seq=$1 (쪽지 전송은 완료)" >&2; return 0; }
  INBOX_CLS="$(printf '%s\n' "$o" | sed -n 's/^INGEST .* cls=\([^ ]*\) .*/\1/p' | head -1)" || INBOX_CLS=""
  return 0
}
# ①~④·미상(보고 의무 분류)이면 받는 좌석의 tick 유무와 무관하게 울린다. ⑤⑥·적재 실패·SKIP 은 notify_policy 그대로.
inbox_must_ring() { case "$INBOX_CLS" in ①|②|③|④|미상) return 0;; *) return 1;; esac; }

# ★doorbell 대상 = 그 역할의 현역 세션(r1116 R7)★ — 우편함 키가 역할이라 옛 번호·역할 이름으로 보내도 현역 pane 을 깨운다. 해석 실패 = 받은 이름 그대로.
holder_of() { local h; h="$(python3 "$MBOXPY" holder "$1" 2>/dev/null)" && [ -n "$h" ] && _check_name "$h" 2>/dev/null && echo "$h" || echo "$1"; }

cmd="${1:-}"; shift || true
case "$cmd" in
  send)
    to="${1:?to}"; from="${2:?from}"; shift 2
    force=(); dbf=0; urgent=0
    args=()
    for a in "$@"; do
      case "$a" in
        --no-notify) echo "WARN --no-notify 는 무시된다 — 알림은 seats.json 이 정한다(§2-2). 급하면 --urgent" >&2 ;;
        --urgent)    urgent=1 ;;
        --force)     force=(--force); dbf=1 ;;
        *)           args+=("$a") ;;
      esac
    done
    guard_check "$to" "${args[*]}" "$from" || exit $?   # rc 3 = REJECT(큐 적재 0) · 후계 전달·[합치기] 치환은 GUARD_TO·GUARD_BODY
    to="$GUARD_TO"; args=("$GUARD_BODY"); dbto="$(holder_of "$to")"
    case "${args[*]}" in "[레디]"*) dbto="$to";; esac   # [레디] = 은퇴한 옛 세션 앞 핸드셰이크 회신 — 현역(후계 자신) 말고 그 pane 을 깨운다(r1116 ②)
    if [ "$urgent" = 1 ] || [ "$(notify_policy "$dbto")" = ring ]; then notify=1; else notify=0; fi
    # 가드 거부(exit 3) 시 doorbell 을 울리지 않는다 — 큐에 들어간 게 없다.
    # ★출력을 «잡는다»★ (2026-09-06, F5) — doorbell 에 실을 seq 가 그 안에 있다.
    #   `$( )` 로 잡으면 py 의 stdout 이 여기서 멈추므로 ★아래에서 반드시 그대로 다시 찍는다★.
    #   안 그러면 `QUEUED seq=…` 를 읽던 사람·스크립트가 조용히 아무것도 못 보게 된다.
    #   stderr(BLOCKED·DROPPED)는 안 잡으므로 지금처럼 그대로 흐른다.
    # 사건 원장 훅(PLAN-status-sheet §3-1 · 근원 ⑥ · fix2 F6): 머리 [정지 레디]·[완료]·[완료·휴식] 만 — 본문 sha16 키 · prepared 를 «먼저»(못 쓰면 큐 적재 0) · 적재 성공 뒤 committed.
    #   헬퍼 = $FT_BIN 또는 $DIR/../bin (inbox_ingest 와 같은 규칙). 없으면 훅 0 + stderr 1줄(send 는 그대로).
    SE="${FT_BIN:-$DIR/../bin}/ft-sheet-events.sh"; SK=""
    case "${args[*]}" in "[정지 레디]"*|"[완료]"*|"[완료·휴식]"*)
      if [ -f "$SE" ]; then SK="$(bash "$SE" key mbox "$from" "${args[*]}" 2>/dev/null)" || SK=""
      else echo "WARN 사건 원장 훅 건너뜀 — ft-sheet-events.sh 없음($SE)" >&2; fi;;
    esac
    if [ -n "$SK" ]; then
      bash "$SE" prepare "$SK" "$(python3 -c 'import json,sys;print(json.dumps(dict(zip(("ev","team","id","seat","ref","by"),sys.argv[1:]))))' "${SK%%:*}" "" "" "$from" "" mbox)" >/dev/null \
        || { echo "REJECT 사건 원장 prepared 실패 — 큐 적재 0" >&2; exit 1; }
    fi
    py_out="$(python3 "$MBOXPY" send "$to" "$from" "${args[*]}" ${force[@]+"${force[@]}"})" || { _rc=$?; [ -z "$SK" ] || bash "$SE" abort "$SK"; exit $_rc; }
    seq="$(seq_of "$py_out")" || seq=""
    [ -z "$SK" ] || bash "$SE" commit "$SK" --ref "seq $seq" >/dev/null || true
    inbox_ingest "$seq"
    if inbox_must_ring; then notify=1; fi
    uf=0; if user_facing "$to"; then notify=0; uf=1; fi
    # ★`[ ] && doorbell` 로 쓰지 않는다★ — set -e 에서 notify=0 이면 리스트가 실패로 끝나 exit 1.
    if [ "$notify" = 1 ]; then db="$(doorbell_status "$dbto" "$dbf" "$seq")"; else db=quiet; fi
    if [ "$uf" = 1 ]; then uf_watch "$to" "$seq"; fi
    echo "$py_out doorbell=$db"
    ;;
  relay)
    # 긴 본문의 정본 절차: 원문을 /tmp/mbox 로 복사하고 요약+경로만 큐잉.
    to="${1:?to}"; from="${2:?from}"; file="${3:?file}"; shift 3
    urgent=0; args=()
    for a in "$@"; do
      case "$a" in
        --no-notify) echo "WARN --no-notify 는 무시된다 — 알림은 seats.json 이 정한다(§2-2). 급하면 --urgent" >&2 ;;
        --urgent)    urgent=1 ;;
        *)           args+=("$a") ;;
      esac
    done
    guard_check "$to" "${args[*]}" "$from" "$file" || { _rc=$?; guard_tmp_clean; exit $_rc; }
    to="$GUARD_TO"; args=("$GUARD_BODY"); dbto="$(holder_of "$to")"
    [ -z "$GUARD_TMP" ] || trap guard_tmp_clean EXIT   # 검사 사본 폴더는 끝에 지운다
    [ -z "$GUARD_FILE" ] || file="$GUARD_FILE"          # 대상 relay 는 «검사한 그 사본» 만 전달한다(R362 · 사본 실패는 가드가 REJECT — 원본 후퇴 0)
    if [ "$urgent" = 1 ] || [ "$(notify_policy "$dbto")" = ring ]; then notify=1; else notify=0; fi
    # relay 도 결국 send 를 타므로 출력에 `seq=` 가 있다 — 같은 번호를 창에도 싣는다.
    py_out="$(python3 "$MBOXPY" relay "$to" "$from" "$file" "${args[*]}")" || exit $?
    seq="$(seq_of "$py_out")" || seq=""
    inbox_ingest "$seq"
    if inbox_must_ring; then notify=1; fi
    uf=0; if user_facing "$to"; then notify=0; uf=1; fi
    if [ "$notify" = 1 ]; then db="$(doorbell_status "$dbto" 0 "$seq")"; else db=quiet; fi
    if [ "$uf" = 1 ]; then uf_watch "$to" "$seq"; fi
    echo "$py_out doorbell=$db"
    ;;
  recv)  me="${1:?me}"; shift
         # ★recv 스탬프 touch — doorbell outstanding 판정의 «소비» 신호★. exec 전에 해야 실행된다.
         : > "${TMPDIR:-/tmp}/mbox-recv-$(printf '%s' "$me" | tr -c 'A-Za-z0-9._#-' '_')" 2>/dev/null || true
         exec python3 "$MBOXPY" recv "$me" "$@" ;;
  peek)  exec python3 "$MBOXPY" peek "${1:?me}" ;;
  # ★승계 마무리(r1116)★ — handover <구> <후계> [«손 항목»…] = 남은 쪽지 끝까지 recv + 미표시·h·bg 를 [인계] 로 보내고 그 쪽지들을 «인계» 표시 ·
  #   ready <후계> <구> = [인계] 항목마다 «받음» [레디] 회신 · mark·unmarked·close-check = 표시·검사(retire·닫기 관문이 부른다)
  handover) old="${1:?old}"; new="${2:?new}"; shift 2; _check_name "$old" && _check_name "$new" || exit 1
         b="$(python3 "$MBOXPY" handover-body "$old" "$new" "$@")" || exit $?
         out="$(bash "$DIR/mbox.sh" send "$new" "$old" "$b")" || { _rc=$?; echo "REJECT [인계] 보내기 실패 rc=$_rc — 표시 0(다시 handover)" >&2; exit $_rc; }
         echo "$out"; s="$(printf '%s\n' "$b" | sed -n 's/^- #\([0-9][0-9]*\) .*/\1/p' | paste -sd, -)"
         [ -z "$s" ] || python3 "$MBOXPY" mark "$old" "$s" 인계 ;;
  ready) new="${1:?new}"; old="${2:?old}"; b="$(python3 "$MBOXPY" ready-body "$new" "$old")" || exit $?
         exec bash "$DIR/mbox.sh" send "$old" "$new" "$b" ;;
  mark|unmarked|close-check) exec python3 "$MBOXPY" "$cmd" "$@" ;;
  # ring — ★큐를 건드리지 않고 doorbell 만 울린다★ (2026-09-06, 나)
  #   재발주가 이 경로로 온다. 이전엔 재발주가 `send` 재호출이라 ★같은 본문이 큐에 두 번★
  #   들어갔고, 좌석은 recv 에서 같은 발주를 2건 봤다(실측: pending=2, mailbox.jsonl 2행).
  #   중복의 «자리»가 창에서 큐로 옮겨갔을 뿐 총량은 그대로였다.
  #   ★seq 를 그대로 다시 싣는다★ — 새 번호를 만들지 않으므로 1차 마커가 그대로 유효하다.
  #   ★force=1 로 억제를 뚫는다★ — 재발주는 «반드시» 창에 떠야 한다. 억제되면 아무것도
  #   안 뜨고 그건 미도달과 구분이 안 된다(팩 ring 과 같은 계약).
  ring)  sess="${1:?sess}"; _check_name "$sess" || exit 1; sess="$(holder_of "$sess")"
         db="$(doorbell_status "$sess" 1 "${2:-}")"; echo "RING $sess doorbell=$db" ;;
  *) echo "usage: mbox.sh {send <to> <from> <body> [--urgent] [--force]|relay <to> <from> <file> <summary>|recv <me> [<from>] [--all]|peek <me>|ring <sess> [seq]|handover <구> <후계>|ready <후계> <구>|mark <me> <seq,…> 처리함·인계|unmarked <me>|close-check <좌석> [--no-ready]}" >&2; exit 2;;
esac
