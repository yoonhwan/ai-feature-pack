#!/bin/bash
# ft-tick-acct-lib.sh — ft-tick 의 시계·표식 helper + 계정 정지·안내 단계(acct_pause_watch · acct_notice) 1곳 (r2001 · source 전용 · 단독 실행 0)
#   부르는 쪽 = ft-tick.sh(바퀴 단계) · ft-acct-watch.sh(2.0 루트 5분 잡). 부르는 쪽이 먼저 정한다: HERE ROOT WT SEATS STATE_DIR MBOX DRY (PASS_MAX · FT_TICK_DEADLINE 선택).
#   [structure] 옮기기 — 함수 본문·출력 바이트는 ft-tick.sh 에 있던 그대로.
# shellcheck disable=SC2034  # ACCT_* 는 부르는 쪽(ft-tick acct_paused)도 쓴다

log() { echo "$(date '+%F %T') $*"; }
# r1253: 가상 시각 — FT_TICK_NOW_BASE 가 있으면 «기준 + 실제 경과» (시계는 흐른다 · 시험 전용) · 없으면 date (기존 호출자 동작 불변). 시계는 이 함수 하나.
NOW_BASE="${FT_TICK_NOW_BASE:-}"; NOW_P0=0; [ -z "$NOW_BASE" ] || NOW_P0="$(date +%s)"
now() { if [ -n "$NOW_BASE" ]; then echo $(( NOW_BASE + $(date +%s) - NOW_P0 )); else date +%s; fi; }
STAMP_PREFIX="${FT_TICK_STAMP_PREFIX:-/tmp/ft-tick-}"   # R27: 시험이 scratch 로 돌릴 수 있게(기본값=원본 동작)
stamp_of() { echo "${STAMP_PREFIX}$1${2:+.$2}.last"; }
# ★r874 r3 stamp 쓰기·읽기 — 끊김(TERM→SIGKILL) 뒤에도 stamp 는 «옛 값» 이거나 «새 값» 이다(빈 파일 0)★
#   쓰기 = write_stamp 하나(같은 폴더 임시 파일에 쓰고 mv 로 원자 교체). 리다이렉션 직접 쓰기(`now > "$stamp"`) 0 — 그 꼴이 트렁케이트 도중
#   끊기면 빈 stamp 가 남고, 빈 stamp 는 다음 바퀴 `$(( now - ))` 산술 오류로 «바퀴 전체» 를 죽여 wt-sweep·뉴스가 영영 안 돌았다(DA⑥ r1 HOLD R1).
write_stamp() {   # $1 = stamp 경로 · $2 = 값(기본 now)
  local f="$1" v="${2:-$(now)}" d t
  d="$(dirname -- "$f")"; [ -d "$d" ] || mkdir -p "$d" 2>/dev/null
  t="$f.tmp.$$"
  if printf '%s\n' "$v" > "$t" 2>/dev/null && mv -f "$t" "$f" 2>/dev/null; then return 0; fi
  rm -f "$t" 2>/dev/null
  echo "$(date '+%F %T') WARN stamp 쓰기 실패 $f — 이번 바퀴는 계속(다음 바퀴에 다시 씀)" >&2; return 1
}
#   읽기 = read_stamp 하나 — 숫자가 아니면(빈 파일 포함) 0 으로 읽고 WARN 1줄을 남긴 뒤 «그 바퀴를 계속한다»(조용한 중단 0).
#   파일 «없음» 은 첫 바퀴라 정상 — 0 만 쓰고 조용히 간다(경고 없음). 경고는 stderr 로만(값이 stdout 으로 갈 때 섞이지 않게).
read_stamp() {   # $1 = stamp 경로 → stdout 에 정수
  local v=''
  [ -e "$1" ] || { echo 0; return 0; }
  v="$(cat "$1" 2>/dev/null)"
  case "$v" in
    ''|*[!0-9]*) echo "$(date '+%F %T') WARN stamp 숫자 아님 — 0 으로 읽고 바퀴 진행: $1 = '${v}'" >&2; echo 0;;
    *) echo "$v";;
  esac
}
stamp_gap() { echo $(( $(now) - $(read_stamp "$1") )); }   # $1 = stamp 경로 → 경과초

# ── r1214 계정 풀 정지 (ACCT_PAUSE) ────────────────────────────────────────────────────────────────
#   계정 한도로 풀이 막히면 pane 입력을 «멈춘다» — 문은 발사뿐이다(좌석 kill 0 · pane Escape 0 · 하드 룰 2·7).
#   acct_paused <좌석> <kind> = 판정 1회 · rc1 이면 그 자리에서 발사 0(회차당 좌석 1줄 기록 · clear→set 새 회차는 다시 1줄).
#   호출 3곳 = fire() 첫 줄 · stall() 깨움 send-keys 직전 · goal() 직전. 읽기 전용 감시(idle_watch·뉴스·표식)는 그대로.
#   acct_pause_watch() = 한 바퀴 1회 판정기(만료·풀림·부분 재시도 주체) — rc4 는 ERROR 1줄만, 틱은 계속. FT_TICK_ACCT_PAUSE=0 으로 끔.
ACCT_PAUSE="${FT_TICK_ACCT_PAUSE_BIN:-$HERE/ft-acct-pause.sh}"
ACCT_FILE="${FT_TICK_ACCT_PAUSE_FILE:-${ROOT:-$WT}/.fable-team/state/ACCT_PAUSE}"
acct_pause_watch() {   # 한 바퀴 1회 — 만료·풀림·부분 재시도 주체(ft-acct-pause.sh status)
  local out rc
  [ "${FT_TICK_ACCT_PAUSE:-1}" = 1 ] || return 0
  if [ "$DRY" = 1 ]; then echo "DRY kind=acct-pause bin=$ACCT_PAUSE file=$ACCT_FILE"; return 0; fi
  [ -f "$ACCT_FILE" ] || return 0
  [ -f "$ACCT_PAUSE" ] || { log "ERROR acct_pause — 도구 없음 $ACCT_PAUSE (설치 누락)"; return 0; }
  out="$(bash "$ACCT_PAUSE" status 2>&1)"; rc=$?
  case "$rc" in
    0) printf '%s\n' "$out" | grep -E '^(RELEASED|EXPIRED|CLEARED|GAVE_UP) ' | while IFS= read -r l; do log "acct_pause: $l"; done;;
    3) printf '%s\n' "$out" | grep -E '^(PAUSED|RELEASING|GAVE_UP) ' | while IFS= read -r l; do log "acct_pause: $l"; done;;
    *) log "ERROR acct_pause rc=$rc: $(printf '%s\n' "$out" | tail -1 | cut -c1-200)";;
  esac
  return 0
}

# ── r1215 계정 안내 + 자동 정지·재개 (acct_notice · Issue #5345 ④ · 판정 2889) ─────────────────────────
#   10분에 1회 예측 도구(r1213)를 돌려 표본을 쌓고, 풀 머리 줄이 «바뀔 때만» 알림 대상에 «[계정 안내]» 1통.
#   풀 가용 0(원인 a) 또는 claude 장애 OUTAGE(원인 b)면 정지 파일(r1214)을 걸고, 가용 복귀·장애 OK 면 «내 회차만» 푼다(clear --round).
#   pass() 의 마지막 함수 · 도구 실패는 ERROR 1줄만 남기고 틱은 계속 · FT_TICK_ACCT=0 으로 끔.
#   env: FT_TICK_ACCT_BIN · FT_TICK_ACCT_PAUSE_BIN(정지 도구 · acct_pause 와 공용) · FT_TICK_ACCT_NOTIFY(공백 목록) · FT_TICK_ACCT_NOW(시험 가상 시각)
#        FT_TICK_ACCT_INTERVAL(600) · FT_TICK_ACCT_MAX(예측 상한 40) · FT_TICK_ACCT_MARGIN(5) · FT_TICK_ACCT_MIN_BUDGET(15) · FT_TICK_ACCT_POST(처리 상한 5)
#        r1258: FT_TICK_ACCT_EXHAUST_MIN(30 · 소진 예상 시각이 지난 안내보다 이만큼(분) 이상 달라야 «바뀜» · 0 = 옛 글자 비교) · FT_TICK_ACCT_RELEASE_MIN(2 · 풀림 시각 · 0 = 옛 글자 비교)
#              FT_TICK_ACCT_HELD_RETRY_SEC(120 · set 이 «옛 회차가 남아 있다» 로 거절된 바퀴 뒤 재시도까지 초)
ACCT_BIN="${FT_TICK_ACCT_BIN:-$HERE/ft-acct-forecast.sh}"
acct_rows() {   # $1 = 예측 JSON 파일 · $2 = 지금(epoch) → 풀마다 TSV 1줄: 풀 가용 계정수 소진(분) 풀림(분) 풀림ISO 불명 until_a(ISO) until_a(HH:MM) until_b(ISO) until_b(HH:MM)
  python3 - "$1" "$2" <<'PY'
import datetime as dt, json, sys
pools = json.load(open(sys.argv[1])); now = int(sys.argv[2])
loc = lambda s: dt.datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone() if s else None
iso = lambda e: dt.datetime.fromtimestamp(e, dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
hm = lambda e: dt.datetime.fromtimestamp(e).strftime("%H:%M")
mn = lambda d: d.strftime("%Y-%m-%d %H:%M") if d else "—"
for p in pools:
    if p.get("model"): continue
    e, r = loc((p.get("earliest") or {}).get("at")), loc(p.get("pool_reset"))
    rep = int(r.timestamp()) if r else 0
    use = rep if rep > now else 0   # 미래 풀림 시각은 보존(release-at) · 이미 지난 값만 버린다 → until 지금+1h
    ua = min(max(use, now + 60), now + 28800) if use else now + 3600   # until = 도구가 받는 최소(지금+60초) ~ 8h 상한
    k = sum(1 for a in (p.get("rows") or []) if a.get("judge") == "판정 불가")
    print("\t".join(map(str, [p["pool"], p["available"], p["accounts"], mn(e), mn(r), iso(use) if use else "—", k, iso(ua), hm(ua), iso(now + 3600), hm(now + 3600)])))
PY
}
acct_join() { local sep="$1" o="" x; shift; for x in "$@"; do o="${o:+$o$sep}$x"; done; printf '%s' "$o"; }
acct_run() {   # 처리 상한(ACCT_POST_DL) 안에서만 외부 호출 — 넘으면 rc 124
  local l=$(( ACCT_POST_DL - $(now) ))
  [ "$l" -gt 0 ] || return 124
  timeout "$l" "$@"
}
acct_pause_run() {   # 정지 도구 호출 — 도구 내부 배치(FT_ACCT_BATCH_SEC)를 남은 예산−2초로 줘서 «회차 반환·기록까지» 끝내고 끝나게 한다(남은 예산 3초 미만이면 호출 0 → rc 124 · 다음 바퀴 재시도)
  local l=$(( ACCT_POST_DL - $(now) ))
  [ "$l" -ge 3 ] || return 124
  FT_ACCT_BATCH_SEC=$(( l - 2 )) timeout "$l" bash "$ACCT_PAUSE" "$@"
}
acct_mins() {   # r1258: «YYYY-MM-DD HH:MM»(지역 시각 글자) → ACCT_MINS(일련 분 · 서로 뺄 값 · 외부 호출 0) · 꼴이 아니면 rc1
  local y m d mp
  [[ "$1" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})\ ([0-9]{2}):([0-9]{2})$ ]] || return 1
  y=$((10#${BASH_REMATCH[1]})); m=$((10#${BASH_REMATCH[2]})); d=$((10#${BASH_REMATCH[3]}))
  [ "$m" -gt 2 ] || y=$(( y - 1 )); mp=$(( (m + 9) % 12 ))
  ACCT_MINS=$(( (365 * y + y / 4 - y / 100 + y / 400 + (153 * mp + 2) / 5 + d) * 1440 + 10#${BASH_REMATCH[4]} * 60 + 10#${BASH_REMATCH[5]} ))
}
acct_time_moved() {   # $1 지난 값 · $2 이번 값 · $3 문턱(분) → rc0 바뀜 · rc1 안 바뀜 (ⓐ 글자 같음=안 바뀜 ⓑ 값↔«—»=바뀜 ⓒ 둘 다 값: 문턱 0=바뀜 · >0 = |차| ≥ 문턱)
  local a b
  [ "$1" != "$2" ] || return 1
  [ "$1" != "—" ] && [ "$2" != "—" ] || return 0
  [ "${3:-0}" -gt 0 ] 2>/dev/null || return 0
  acct_mins "$1" || return 0; a="$ACCT_MINS"; acct_mins "$2" || return 0; b="$ACCT_MINS"
  [ $(( a > b ? a - b : b - a )) -ge "$3" ]
}
acct_head_changed() {   # r1258: $1 = 지난 안내 비교값(풀|가용/계정|소진|풀림|불명) · $2 = 이번 값 → rc0 바뀜 · rc1 같음 · 옛 꼴(칸 수 다름)은 바뀜 1회
  local -a o n
  IFS='|' read -r -a o <<< "$1"; IFS='|' read -r -a n <<< "$2"
  [ "${#o[@]}" = 5 ] && [ "${#n[@]}" = 5 ] || return 0
  [ "${o[0]}|${o[1]}|${o[4]}" = "${n[0]}|${n[1]}|${n[4]}" ] || return 0
  acct_time_moved "${o[2]}" "${n[2]}" "${FT_TICK_ACCT_EXHAUST_MIN:-30}" && return 0
  acct_time_moved "${o[3]}" "${n[3]}" "${FT_TICK_ACCT_RELEASE_MIN:-2}" && return 0
  return 1
}
acct_held_note() {   # r1258: $1 상태 폴더 · $2 풀 · $3 남은 옛 회차 → 회차가 바뀔 때만 INFO 1줄(표식 held-<풀>.txt)
  [ "$(cat "$1/held-$2.txt" 2>/dev/null)" = "$3" ] || { printf '%s\n' "$3" > "$1/held-$2.txt"; log "acct_notice: $2 옛 회차 $3 남음 — 재정지 대기"; }
}
acct_notice() {
  [ "${FT_TICK_ACCT:-1}" = 1 ] && [ -z "${FT_TICK_TEAM:-}" ] || return 0   # 팀 틱은 건너뜀(루트 틱 1곳 · 중복 안내·중복 정지 0)
  # 명부가 <루트>/.fable-team/seats.json 꼴이 아니면(임시 명부 시험) 실 계정 조회를 부르지 않는다 — 도구를 FT_TICK_ACCT_BIN 으로 직접 지정한 시험만 예외(model_swap 과 같은 틀)
  [ -n "${FT_TICK_ACCT_BIN:-}" ] || { [ "$(basename "$SEATS")" = seats.json ] && [ "$(basename "$(dirname "$SEATS")")" = .fable-team ]; } || return 0
  local sd="$STATE_DIR/acct-notice" notify nowe real left lim jf rc rows astate apio ACCT_POST_DL
  local P av tot early reset repiso K ua uah ub ubh key human cause chk crc pf rid rrid rcause sout src rel why t fail changed body defer=0 c2 held holdwait=0 tok
  local -a pk=() hs=() ss=() acts=() targets=()
  notify="${FT_TICK_ACCT_NOTIFY:-$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(" ".join(dict.fromkeys(x for x in (d.get("_hil_route"),d.get("_master")) if isinstance(x,str) and x)))' "$SEATS" 2>/dev/null)}"
  if [ "$DRY" = 1 ]; then echo "DRY kind=acct-notice bin=$ACCT_BIN pause=$ACCT_PAUSE notify=${notify:--}"; return 0; fi
  nowe="${FT_TICK_ACCT_NOW:-$(now)}"
  acct_me; tok="acct-auto:$(basename "${ROOT:-$WT}"):$nowe-$ACCT_ME"   # r2001 ⓑ: 이번 시도 id — set 마다 --set-by 로 남기고, set 결과가 불명이면 이 값으로만 소유를 확인한다
  # ⓪ 주기 — 지난 실행 뒤 INTERVAL 미만이면 건너뜀(틱이 몇 종류든 10분에 1회)
  left=$(( nowe - $(read_stamp "$sd/last-run") ))
  if [ -f "$sd/last-run" ] && [ "$left" -lt "${FT_TICK_ACCT_INTERVAL:-600}" ]; then log "acct_notice: skip ${left}s"; return 0; fi
  # ① 예측 1회 — 제한 = min(MAX, 틱 남은 예산 − MARGIN) · 예산이 MIN_BUDGET 미만이면 이번 바퀴는 건너뜀(표식 갱신 0)
  real="$(now)"; left=$(( ${FT_TICK_DEADLINE:-$(( real + ${PASS_MAX:-70} ))} - real ))
  [ "$left" -ge "${FT_TICK_ACCT_MIN_BUDGET:-15}" ] || { log "acct_notice: skip 예산 ${left}s"; return 0; }
  lim=$(( left - ${FT_TICK_ACCT_MARGIN:-5} )); [ "$lim" -le "${FT_TICK_ACCT_MAX:-40}" ] || lim="${FT_TICK_ACCT_MAX:-40}"
  mkdir -p "$sd" 2>/dev/null; jf="$sd/forecast.json"
  timeout "$lim" bash "$ACCT_BIN" --json >"$jf" 2>"$sd/forecast.err"; rc=$?
  write_stamp "$sd/last-run" "$nowe"   # 표식은 ERROR 바퀴도 갱신(표본은 도구 안에서 쌓인다)
  ACCT_POST_DL=$(( $(now) + ${FT_TICK_ACCT_POST:-5} ))
  case "$rc" in 0|3) rows="$(acct_rows "$jf" "$nowe" 2>"$sd/rows.err")" || rc=99;; esac
  case "$rc" in 0|3) ;; *)
    echo "$(date '+%F %T') acct_notice: ERROR forecast rc=$rc: $(tail -c 300 "$jf" "$sd/forecast.err" "$sd/rows.err" 2>/dev/null | grep -v '^==>' | grep . | tail -1 | cut -c1-200)" >&2; return 0;;
  esac
  [ -n "$rows" ] || { log "acct_notice: 풀 0"; return 0; }
  astate="${FT_TICK_API_OUTAGE_STATE:-${ROOT:-$WT}/.fable-team/state/api-outage/$(basename "$SEATS")}"
  apio="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("status",""))' "$astate" 2>/dev/null)"
  while IFS=$'\t' read -r P av tot early reset repiso K ua uah ub ubh; do
    key="$P|$av/$tot|$early|$reset|$K"
    human="풀 $P: 가용 $av/$tot · 가장 이른 소진 $([ "$early" = "—" ] && echo '근거 없음' || echo "$early") · 풀림 $reset · 불명 $K"
    # ②③ 원인: a = 가용 0 · b = claude 장애(api-outage 는 claude 좌석 jsonl 로만 판정하므로 claude 고정)
    #   r1258 결함 3: a 는 «알려진 계정(tot−불명) ≥ 1» 일 때만 — 풀 계정이 전부 불명이면 소진이 아니라 «모름» 이라 정지 원인이 아니다
    cause=""; if [ "$tot" -gt 0 ] && [ "$av" = 0 ] && [ $(( tot - K )) -ge 1 ]; then cause=a; elif [ "$P" = claude ] && [ "$apio" = OUTAGE ]; then cause=b; fi
    pf="$sd/pause-$P.json"; src="없음"; why=""
    chk="$(acct_pause_run status --check "$P" 2>&1)"; crc=$?
    case "$crc" in
      0) [ ! -f "$pf" ] || { rm -f "$pf"; log "acct_notice: $P 정지 이미 끝남 — 기록 삭제"; }
         if [ -n "$cause" ]; then
           if [ "$cause" = a ]; then rel=""; [ "$repiso" = "—" ] || rel="$repiso"; why="a"; sout="$(acct_pause_run set --provider "$P" --until "$ua" ${rel:+--release-at "$rel"} --reason "acct_notice 자동(a): $human" --set-by "$tok" 2>&1)"; src=$?
           else why="b"; sout="$(acct_pause_run set --provider "$P" --until "$ub" --reason "acct_notice 자동(b): $human" --set-by "$tok" 2>&1)"; src=$?; fi
           rid="$(printf '%s\n' "$sout" | sed -n 's/.*round=\([^ ]*\).*/\1/p' | head -1)"
           held=""; [ "$src" != 1 ] || held="$(printf '%s\n' "$sout" | sed -n 's/.*항목이 이미 있다(round=\([^)]*\)).*/\1/p' | head -1)"   # r1258: 옛 회차가 남아 있다(RELEASING·만료 대기)는 도구의 거절 = 정상 상태
           if [ -z "$held" ] && { [ "$src" != 0 ] || [ -z "$rid" ]; }; then   # 끊김·실패 → 도구가 정지를 걸었는지 확인(별도 2초)
             chk="$(timeout 2 bash "$ACCT_PAUSE" status --check "$P" 2>&1)"; c2=$?
             # r2001 ⓑ: «지금 보인다 = 내 회차» 채택 0 — ACCT_PAUSE 항목의 set_by 가 이번 시도 id 일 때만 그 round 를 소유로 쓴다(다르거나 못 읽음 = 소유 기록 0 · 다음 판)
             if [ "$c2" = 3 ]; then
               if [ "$(acct_entry_field "$P" set_by)" = "$tok" ]; then rid="$(acct_entry_field "$P" round_id)"; [ -z "$rid" ] || src=0
               else rid=""; log "acct_notice: $P set 결과 불명 · 지금 항목은 이번 시도가 아님(손·다른 주체·판독 불가) — 소유 기록 0 · 다음 판"; fi
             fi
           fi
           if [ -n "$held" ]; then
             acct_held_note "$sd" "$P" "$held"; holdwait=1; acts+=("재정지 대기"); ss+=("$P 재정지 대기($held)")
           elif [ "$src" = 0 ] && [ -n "$rid" ]; then
             printf '{"round_id": "%s", "cause": "%s", "set_at": %s}\n' "$rid" "$why" "$nowe" > "$pf"; rm -f "$sd/held-$P.txt"
             acts+=("set"); ss+=("$P 있음 until $([ "$why" = a ] && echo "$uah" || echo "$ubh")(자동)")
           else
             echo "$(date '+%F %T') acct_notice: ERROR $P set rc=$src: $(printf '%s\n' "$sout" | tail -1 | cut -c1-200)" >&2
             defer=1; acts+=("보류"); ss+=("$P 보류")
           fi
         else rm -f "$sd/held-$P.txt"; acts+=("없음"); ss+=("$P 없음"); fi;;
      3) rm -f "$sd/held-$P.txt"
         rrid="$(printf '%s\n' "$chk" | sed -n 's/.*round=\([^ ]*\).*/\1/p' | head -1)"
         rcause="$([ -f "$pf" ] && sed -n 's/.*"cause": *"\([ab]\)".*/\1/p' "$pf" | head -1)"
         rid="$([ -f "$pf" ] && sed -n 's/.*"round_id": *"\([^"]*\)".*/\1/p' "$pf" | head -1)"
         if [ -n "$rid" ] && [ "$rid" = "$rrid" ] && ! acct_auto_entry "$P"; then   # r2001 ⓒ: 지금 항목이 자동(set_by acct-auto:)이 아니면 소유 기록이 맞아도 clear 0
           log "acct_notice: $P 지금 항목 set_by 가 자동 아님 — clear 0(손 정지 보존)"
           acts+=("유지"); ss+=("$P 있음 until $(printf '%s\n' "$chk" | sed -n 's/.*until_hhmm=\([0-9:]*\).*/\1/p' | head -1)(손)")
         elif [ -n "$rid" ] && [ "$rid" = "$rrid" ]; then
           if { [ "$rcause" = a ] && { [ "$av" -ge 1 ] || { [ "$tot" -gt 0 ] && [ $(( tot - K )) -lt 1 ]; }; }; } || { [ "$rcause" = b ] && [ "$apio" = OK ]; }; then
             sout="$(acct_pause_run clear --provider "$P" --round "$rid" 2>&1)"; src=$?
             case "$src" in
               0) chk="$(acct_pause_run status --check "$P" 2>&1)"; crc=$?
                  if [ "$crc" = 0 ]; then rm -f "$pf"; acts+=("clear"); ss+=("$P 없음")
                  else log "acct_notice: $P clear 뒤에도 정지 있음(재개 진행 중) — 소유 기록 유지(rc=$crc)"; acts+=("유지"); ss+=("$P 있음 until $(printf '%s\n' "$chk" | sed -n 's/.*until_hhmm=\([0-9:]*\).*/\1/p' | head -1)(자동 · 재개 중)"); fi;;
               3) log "acct_notice: $P 정지 유지(교체됨)"; acts+=("유지"); ss+=("$P 있음 until $(printf '%s\n' "$chk" | sed -n 's/.*until_hhmm=\([0-9:]*\).*/\1/p' | head -1)(손)");;
               *) echo "$(date '+%F %T') acct_notice: ERROR $P clear rc=$src: $(printf '%s\n' "$sout" | tail -1 | cut -c1-200)" >&2; defer=1; acts+=("보류"); ss+=("$P 보류");;
             esac
           else acts+=("유지"); ss+=("$P 있음 until $(printf '%s\n' "$chk" | sed -n 's/.*until_hhmm=\([0-9:]*\).*/\1/p' | head -1)(자동)"); fi
         else
           log "acct_notice: $P 정지 유지(손|다른 회차)"
           acts+=("유지"); ss+=("$P 있음 until $(printf '%s\n' "$chk" | sed -n 's/.*until_hhmm=\([0-9:]*\).*/\1/p' | head -1)(손)")
         fi;;
      *) echo "$(date '+%F %T') acct_notice: ERROR $P status --check rc=$crc: $(printf '%s\n' "$chk" | tail -1 | cut -c1-200)" >&2
         defer=1; acts+=("보류"); ss+=("$P 보류");;
    esac
    pk+=("$P"$'\t'"$key"); hs+=("$human")
  done <<< "$rows"
  # 정지 도구를 못 부른 바퀴(예산 부족·끊김)는 안내 상태를 바꾸지 않는다 — 표식을 지워 다음 바퀴가 다시 하고, 정지가 걸린 «뒤 바퀴» 에 안내 1통(옛 «판정 불가» 안내가 남지 않는다)
  if [ "$defer" = 1 ]; then rm -f "$sd/last-run"; log "acct_notice: 보류(정지 도구를 못 마침) — 안내 0 · 다음 바퀴 재시도"; return 0; fi
  # ⑤ 안내 — ③④ 를 먼저 끝낸 최종 상태로 본문을 만들고, 머리 줄이 지난 것과 다를 때만 알림 대상 전부에 1통(전부 QUEUED 뒤에만 last 갱신)
  #   r1258: 옛 회차가 남아 거절된 풀이 있으면 120초 뒤(HELD_RETRY_SEC) 다시 — 주기 표식을 «지금 − 주기 + 120» 으로 당겨 둔다(10분 기다림 0 · 매 바퀴 예측 0)
  [ "$holdwait" = 0 ] || write_stamp "$sd/last-run" "$(( nowe - ${FT_TICK_ACCT_INTERVAL:-600} + ${FT_TICK_ACCT_HELD_RETRY_SEC:-120} ))"
  changed=0
  for t in "${pk[@]}"; do acct_head_changed "$(cat "$sd/last-${t%%$'\t'*}.txt" 2>/dev/null)" "${t#*$'\t'}" && changed=1; done
  if [ "$changed" = 1 ]; then
    body="[계정 안내] $(acct_join ' / ' "${hs[@]}") · 정지: $(acct_join ' / ' "${ss[@]}")"
    read -r -a targets <<< "$notify"; fail=0
    [ "${#targets[@]}" -gt 0 ] || { echo "$(date '+%F %T') acct_notice: ERROR no notify target (_hil_route/_master) in $SEATS" >&2; fail=1; targets=(-); }
    for t in "${targets[@]}"; do [ "$t" != - ] || continue; acct_run bash "$MBOX" send "$t" ft-tick "$body" >/dev/null 2>&1 || { echo "$(date '+%F %T') acct_notice: ERROR mbox failed to=$t" >&2; fail=1; }; done
    if [ "$fail" = 0 ]; then for t in "${pk[@]}"; do printf '%s\n' "${t#*$'\t'}" > "$sd/last-${t%%$'\t'*}.txt"; done; else changed=0; fi
  fi
  log "acct_notice: $(acct_join ' / ' "${hs[@]}") · 안내 $changed · 정지 $(acct_join , "${acts[@]}")"
  return 0
}

# ── r2001 공통 진입점 acct_cycle (ft-tick 바퀴 · ft-acct-watch 5분 잡 공용 · 판정 DA#10 #304257) ─────────────────────
#   acct_cycle <루트> [all|resume|notice] — 루트별 잠금 <루트>/.fable-team/state/acct-notice/cycle.lock(mkdir · 대기 0) 안에서만
#   재개(acct_pause_watch) → 예측·정지·풀림(acct_notice) 을 돈다. 못 잡으면 쓰기 0 + 로그 1줄 + 다음 판. 다른 루트 = 다른 잠금.
#   잠금 = 잡은 주체가 정상·실패 모두 닫는다(acct_lock_drop) · 끊긴 주체(KILL)의 잠금은 owner(pid·시작 시각)가 죽었을 때만 세대 표식으로 회수(보정 R2) —
#   살아 있는 남의 잠금 삭제 0 · owner 를 쓰기 전 잠금(빈 폴더)은 FT_ACCT_LOCK_ORPHAN_SEC(120)초가 지나야 회수.
#   소유 기록·주기 표식(STATE_DIR/acct-notice/)은 그대로 쓴다(이관 0) · DRY 는 잠금 없이 DRY 줄만.
acct_me() { ACCT_ME="${BASHPID:-}"; [ -n "$ACCT_ME" ] || ACCT_ME="$(exec sh -c 'echo $PPID')"; }   # 지금 셸(배경 바퀴 subshell 포함)의 pid → ACCT_ME · 명령 치환 안에서 부르지 않는다
acct_entry_field() {   # $1 provider $2 칸 → ACCT_PAUSE 항목의 그 칸(문자열) · 판독 실패·없음 = 빈 줄 rc1
  python3 -c 'import json,sys
e=(json.load(open(sys.argv[1])) or {}).get(sys.argv[2])
v=e.get(sys.argv[3]) if isinstance(e,dict) else None
print(v if isinstance(v,str) else ""); sys.exit(0 if isinstance(v,str) and v else 1)' "$ACCT_FILE" "$1" "$2" 2>/dev/null
}
acct_auto_entry() { case "$(acct_entry_field "$1" set_by)" in acct-auto:*) return 0;; *) return 1;; esac; }   # $1 provider → rc0 = 자동 주체가 건 항목
acct_proc_start() { ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//'; }
acct_owner_put() { ( set -C; printf '%s\t%s\t%s\n' "$2" "$3" "${ACCT_LOCK_WHO:-acct}" > "$1/owner" ) 2>/dev/null; }   # $1 잠금 $2 pid $3 시작 시각 → owner 가 «없을 때만» 만든다(O_EXCL)
acct_owner_line() { local x=""; IFS= read -r x 2>/dev/null < "$1/owner"; printf '%s' "$x"; }   # $1 잠금 → owner 첫 줄(없으면 빈 값)
acct_reclaim_mark() {   # $1 잠금 $2 첫 표식 이름 $3 나 $4 내 시작 시각 → rc0 = 이 세대 회수 권리(ACCT_MARK) · rc1 = 물러남(로그 1줄)
  #   r2001 보정 R2 ⓐⓓⓔ: 회수 권리 = 죽은 owner 세대 이름의 표식 mkdir 1회(원자 · 1명). 표식 안 owner = 회수자 pid·시작 시각.
  #   표식이 이미 있으면 그 회수자가 살아 있으면 물러나고, 죽었으면 «<표식>.<죽은 회수자 pid>» 로 한 단 더(단마다 죽은 프로세스 1개 · 상한 8단).
  local l="$1" m="$2" i ml mpid mst mm age
  for i in 1 2 3 4 5 6 7 8; do
    if mkdir "$l/$m" 2>/dev/null; then
      printf '%s\t%s\n' "$3" "$4" > "$l/$m/owner" 2>/dev/null
      ACCT_MARK="$l/$m"; return 0
    fi
    ml=""; IFS= read -r ml 2>/dev/null < "$l/$m/owner"; mpid=""; mst=""; IFS=$'\t' read -r mpid mst _ <<< "$ml"
    if [ -z "$mpid" ]; then   # 표식 owner 없음 = 쓰는 중이거나 쓰기 전에 죽음 · 폴더가 없어졌으면 회수가 이미 끝남
      mm="$(stat -f %m "$l/$m" 2>/dev/null || stat -c %Y "$l/$m" 2>/dev/null)"
      [ -n "$mm" ] || { log "acct_cycle: 회수 경쟁(표식 사라짐) — 쓰기 0 · 다음 판"; return 1; }
      age=$(( $(date +%s) - mm ))
      [ "$age" -ge "${FT_ACCT_LOCK_ORPHAN_SEC:-120}" ] || { log "acct_cycle: 회수 경쟁($m 쓰는 중) — 쓰기 0 · 다음 판"; return 1; }
      m="$m.noowner"; continue
    fi
    if kill -0 "$mpid" 2>/dev/null && [ "$(acct_proc_start "$mpid")" = "$mst" ]; then log "acct_cycle: 회수 경쟁(회수자 pid=$mpid 살아 있음) — 쓰기 0 · 다음 판"; return 1; fi
    m="$m.$mpid"   # ⓓ 죽은 회수자 → 한 단 더
  done
  log "acct_cycle: 회수 표식 8단 넘음 — 쓰기 0 · 다음 판"; return 1
}
acct_lock_take() {   # $1 잠금 폴더 → rc0 잡음(ACCT_LOCK_HELD) · rc1 못 잡음(로그 1줄 · 쓰기 0)
  #   r2001 보정 R2(DA HOLD-IMPL #304538 B1): 잠금 폴더를 옮기는 회수 0 · 산 잠금을 지우는 길 0.
  #   ⓐ owner 죽음 확인 → 표식 mkdir "$l/reclaim.<죽은 pid>"(owner 없는 옛 폴더 = reclaim.noowner · 120초 규칙) ⓑ 표식 뒤 owner 를 다시 읽어 처음 본 줄과 같을 때만
  #   ⓒ rm -rf "$l" → mkdir "$l"(보통 획득자가 먼저면 rc1) → owner O_EXCL. 다르면 내 표식만 지우고 rc1(남의 폴더·owner 손 0).
  local l="$1" me st line opid ost m age mark
  acct_me; me="$ACCT_ME"; st="$(acct_proc_start "$me")"
  mkdir -p "$(dirname "$l")" 2>/dev/null
  if mkdir "$l" 2>/dev/null; then
    acct_owner_put "$l" "$me" "$st" || { log "acct_cycle: 새 잠금 owner 를 다른 주체가 먼저 씀 — 쓰기 0 · 다음 판"; return 1; }
    ACCT_LOCK_HELD="$l"; return 0
  fi
  line="$(acct_owner_line "$l")"; opid=""; ost=""; IFS=$'\t' read -r opid ost _ <<< "$line"
  if [ -z "$opid" ]; then
    m="$(stat -f %m "$l" 2>/dev/null || stat -c %Y "$l" 2>/dev/null)"
    [ -n "$m" ] || { log "acct_cycle: 잠금 판정 불가($l) — 쓰기 0 · 다음 판"; return 1; }
    age=$(( $(date +%s) - m ))
    [ "$age" -ge "${FT_ACCT_LOCK_ORPHAN_SEC:-120}" ] || { log "acct_cycle: 잠금 owner 쓰는 중(${age}s) — 쓰기 0 · 다음 판"; return 1; }
    mark="reclaim.noowner"
  else
    if kill -0 "$opid" 2>/dev/null && [ "$(acct_proc_start "$opid")" = "$ost" ]; then log "acct_cycle: 잠금 사용 중(pid=$opid) — 쓰기 0 · 다음 판"; return 1; fi
    mark="reclaim.$opid"
  fi
  acct_reclaim_mark "$l" "$mark" "$me" "$st" || return 1
  if [ "$(acct_owner_line "$l")" != "$line" ]; then
    rm -rf "$ACCT_MARK"; log "acct_cycle: 표식 뒤 owner 가 바뀜(다른 주체가 회수) — 내 표식만 지움 · 다음 판"; return 1
  fi
  rm -rf "$l"
  mkdir "$l" 2>/dev/null || { log "acct_cycle: 회수 뒤 보통 획득자가 먼저 — 쓰기 0 · 다음 판"; return 1; }
  acct_owner_put "$l" "$me" "$st" || { log "acct_cycle: 회수 뒤 owner 경쟁 — 쓰기 0 · 다음 판"; return 1; }
  log "acct_cycle: 끊긴 주체 잠금 회수(${ACCT_MARK##*/})"; ACCT_LOCK_HELD="$l"; return 0
}
acct_lock_drop() {   # 내가 잡은 잠금만 닫는다(owner pid = 나) · 여러 번 불러도 안전
  local l="${ACCT_LOCK_HELD:-}" own=""
  [ -n "$l" ] || return 0
  IFS=$'\t' read -r own _ 2>/dev/null < "$l/owner"
  acct_me; [ "$own" = "$ACCT_ME" ] && rm -rf "$l" 2>/dev/null
  ACCT_LOCK_HELD=""; return 0
}
acct_cycle() {   # $1 루트 · $2 = all(재개 → 안내) | resume | notice
  local root="${1:-${ROOT:-$WT}}" ph="${2:-all}"
  if [ "$DRY" != 1 ]; then acct_lock_take "$root/.fable-team/state/acct-notice/cycle.lock" || return 0; fi
  case "$ph" in
    resume) acct_pause_watch;;
    notice) acct_notice;;
    *) acct_pause_watch; acct_notice;;
  esac
  [ "$DRY" = 1 ] || acct_lock_drop
  return 0
}
