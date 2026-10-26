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
#   ★r928 유예★: 끝 표식(planner-watch-last.<좌석> = ft-inbox-watch.sh 가 끝날 때 쓰는 «<좌석>\t<epoch>» 1줄)의 mtime 이 유예(FT_WATCH_REARM_GRACE, 기본 5분) 안이고 본문 좌석이 같을 때만 긴급 0 · stderr `WATCH-REARM 대기 <분>` 1줄
#     — Monitor 30분 한도 뒤 «다시 거는 틈»을 오탐 긴급으로 보내지 않는다(판정 1125). 표식이 심링크·폴더·미래 mtime·깨진 본문이면 유예 0(긴급 그대로) + stderr `WATCH-MARK 이상(<사유>)` 1줄(DA⑥ r1 반례 1·2).
#     긴급 본문 근거 줄 = `감시 프로세스 0(pgrep) · 마지막 감시 끝 <HH:MM|기록 없음>`.
#   판정 불가 = 꼬리 `(WATCH 판정 불가)` + stderr(조용한 통과 0) · 적재 실패·master 없음 = stderr 1줄(표식 0 → 다음 send 재시도).
#   _mark_hhmm <표식> → "HH:MM" 또는 "기록 없음" (긴급 본문 근거 줄용)
#   _mark_grace <표식> <좌석> <유예분> → rc0 유예(stdout 경과 분) · rc1 유예 밖 · rc2 표식 없음 · rc3 이상(유예 0 + stderr `WATCH-MARK 이상(<사유>)` 1줄)
_mark_hhmm() {
  local m; m="$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || true)"
  case "$m" in ''|*[!0-9]*) printf '기록 없음'; return 0 ;; esac
  date -r "$m" +%H:%M 2>/dev/null || date -d "@$m" +%H:%M 2>/dev/null || printf '기록 없음'
}
_mark_grace() {
  local f="$1" want="$2" grace="$3" m n line seat now
  if [ -L "$f" ]; then echo "WATCH-MARK 이상(심링크) $f" >&2; return 3; fi
  if [ -e "$f" ] && [ ! -f "$f" ]; then echo "WATCH-MARK 이상(일반 파일 아님) $f" >&2; return 3; fi
  if [ ! -f "$f" ]; then return 2; fi
  m="$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || true)"
  case "$m" in ''|*[!0-9]*) echo "WATCH-MARK 이상(mtime 읽기 실패) $f" >&2; return 3 ;; esac
  line="$(head -1 "$f" 2>/dev/null || true)"
  case "$line" in
    *$'\t'*) seat="${line%%$'\t'*}" ;;
    *) echo "WATCH-MARK 이상(본문 깨짐) $f" >&2; return 3 ;;
  esac
  if [ "$seat" != "$want" ]; then echo "WATCH-MARK 이상(본문 좌석 다름) $f" >&2; return 3; fi
  now="$(date +%s)"
  if [ "$m" -gt "$now" ]; then echo "WATCH-MARK 이상(미래 mtime) $f" >&2; return 3; fi
  n=$(( (now - m) / 60 ))
  if [ "$n" -lt "$grace" ]; then printf '%s' "$n"; return 0; fi
  return 1
}
uf_watch() {  # <to> <계기 쪽지 seq>
  local to="$1" ft="$DIR/.." o rc=0 hm mk q lm emin ld grace sfx grc=0
  o="$(bash "${FT_BIN:-$DIR/../bin}/ft-mbox.sh" watch-alive "$to" 2>/dev/null)" || rc=$?
  [ "$rc" = 0 ] && return 0
  case "$rc:$o" in 3:"NO watch"*) ;; *) db="${db}(WATCH 판정 불가)"; echo "WARN planner watch 판정 불가 rc=$rc $to: ${o:0:80}" >&2; return 0;; esac
  db="${db}(WATCH 없음)"; sfx="$(printf '%s' "$to" | tr -c 'A-Za-z0-9._#-' '_')"
  mk="$ft/state/planner-watch-missing.$sfx"; lm="$ft/state/planner-watch-last.$sfx"
  [ -n "$(find "$mk" -mmin -10 2>/dev/null)" ] && return 0
  grace="${FT_WATCH_REARM_GRACE:-5}"
  emin="$(_mark_grace "$lm" "$to" "$grace")" || grc=$?
  if [ "$grc" = 0 ]; then
    echo "WATCH-REARM 대기 ${emin}분 — $to 감시가 ${grace}분 안에 끝남($lm) · 다시 거는 틈이라 긴급 0통" >&2
    return 0
  fi
  ld="$(_mark_hhmm "$lm")"
  hm="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8")).get("_master") or "")' "${FT_HARNESS_SEATS_JSON:-$ft/seats-harness.json}" 2>/dev/null)" || hm=""
  [ -n "$hm" ] || { echo "WARN planner watch 없음 $to — 하네스 master 를 못 찾음 · 긴급 0통" >&2; return 0; }
  [ -n "$ld" ] || ld="기록 없음"
  q="$(python3 "$MBOXPY" send "$hm" ft-watch-alarm "[긴급 · planner watch 없음] $to · 감지 $(date +%H:%M) · 계기 쪽지 #${2:-?} · 감시 프로세스 0(pgrep) · 마지막 감시 끝 $ld · 시작: Monitor → bash $(cd "$ft" && pwd)/bin/ft-inbox-watch.sh $to")" \
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
    to="$GUARD_TO"; args=("$GUARD_BODY")
    if [ "$urgent" = 1 ] || [ "$(notify_policy "$to")" = ring ]; then notify=1; else notify=0; fi
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
    if [ "$notify" = 1 ]; then db="$(doorbell_status "$to" "$dbf" "$seq")"; else db=quiet; fi
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
    to="$GUARD_TO"; args=("$GUARD_BODY")
    [ -z "$GUARD_TMP" ] || trap guard_tmp_clean EXIT   # 검사 사본 폴더는 끝에 지운다
    [ -z "$GUARD_FILE" ] || file="$GUARD_FILE"          # 대상 relay 는 «검사한 그 사본» 만 전달한다(R362 · 사본 실패는 가드가 REJECT — 원본 후퇴 0)
    if [ "$urgent" = 1 ] || [ "$(notify_policy "$to")" = ring ]; then notify=1; else notify=0; fi
    # relay 도 결국 send 를 타므로 출력에 `seq=` 가 있다 — 같은 번호를 창에도 싣는다.
    py_out="$(python3 "$MBOXPY" relay "$to" "$from" "$file" "${args[*]}")" || exit $?
    seq="$(seq_of "$py_out")" || seq=""
    inbox_ingest "$seq"
    if inbox_must_ring; then notify=1; fi
    uf=0; if user_facing "$to"; then notify=0; uf=1; fi
    if [ "$notify" = 1 ]; then db="$(doorbell_status "$to" 0 "$seq")"; else db=quiet; fi
    if [ "$uf" = 1 ]; then uf_watch "$to" "$seq"; fi
    echo "$py_out doorbell=$db"
    ;;
  recv)  me="${1:?me}"; shift
         # ★recv 스탬프 touch — doorbell outstanding 판정의 «소비» 신호★. exec 전에 해야 실행된다.
         : > "${TMPDIR:-/tmp}/mbox-recv-$(printf '%s' "$me" | tr -c 'A-Za-z0-9._#-' '_')" 2>/dev/null || true
         exec python3 "$MBOXPY" recv "$me" "$@" ;;
  peek)  exec python3 "$MBOXPY" peek "${1:?me}" ;;
  # ring — ★큐를 건드리지 않고 doorbell 만 울린다★ (2026-09-06, 나)
  #   재발주가 이 경로로 온다. 이전엔 재발주가 `send` 재호출이라 ★같은 본문이 큐에 두 번★
  #   들어갔고, 좌석은 recv 에서 같은 발주를 2건 봤다(실측: pending=2, mailbox.jsonl 2행).
  #   중복의 «자리»가 창에서 큐로 옮겨갔을 뿐 총량은 그대로였다.
  #   ★seq 를 그대로 다시 싣는다★ — 새 번호를 만들지 않으므로 1차 마커가 그대로 유효하다.
  #   ★force=1 로 억제를 뚫는다★ — 재발주는 «반드시» 창에 떠야 한다. 억제되면 아무것도
  #   안 뜨고 그건 미도달과 구분이 안 된다(팩 ring 과 같은 계약).
  ring)  sess="${1:?sess}"; _check_name "$sess" || exit 1
         db="$(doorbell_status "$sess" 1 "${2:-}")"; echo "RING $sess doorbell=$db" ;;
  *) echo "usage: mbox.sh {send <to> <from> <body> [--urgent] [--force]|relay <to> <from> <file> <summary>|recv <me> [<from>] [--all]|peek <me>|ring <sess> [seq]}" >&2; exit 2;;
esac
