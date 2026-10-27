#!/usr/bin/env bash
# ft-autonomy.sh — 자율 대리 결정 모드 on/off/status (판정 1314·1322 · DESIGN-autonomy-proxy-decision r3 §1·§2)
#   on | off     오빠 `!` 한 줄(ft-hil.sh --add 가 돌려주는 `! bash /tmp/h<N>`)로만 부른다 — 좌석 경로 0
#   on [--until HH:MM | --for <N>h|<N>m] [--level full|mid|each(기본 full) --max --daily --code-max]  끝·레벨은 켤 때만 정한다(이미 ON 이면 인자 무시) · 틀린 인자 = REJECT rc 2(상태 쓰기 0) · 레벨·학습·인터뷰 = ft-autonomy-level.sh(r466) · 켜기 직전 인증 사전 점검(ft-autonomy-start.sh preflight)이 status 위에 붙는다 — 실패해도 켜기는 진행
#   status       `[자율 ON A7 · 23:41~ · ~08:00까지 · 대리 3 · 큐 1]`(끝 없으면 `끝 없음`) / `[자율 OFF]` / `[자율 ?? 위변조 → OFF]`
#   mode | event 기계용: on|off|tamper · 현재(또는 마지막) 사건 번호 A<N>
#   state-dir    상태 폴더 해석의 유일한 출처(R253) — $STATE 를 1줄 출력(쓰기 0) · ft-merge-land.sh 가 승인 파일 폴더를 여기서 받는다
#   approve-merge <40hex>…  main 병합 승인(판정 1675 · R336 모드 무관) — 오빠 `!` 한 줄로만. ON·OFF 모두: 각 sha 에 대해
#                승인 줄 `approve-merge <sha> A<N>|OFF <epoch>`(OFF 면 이벤트 칸 OFF) 을 autonomy.log 에 먼저 추가한 뒤 $STATE/autonomy-merge-approved/<sha> 에 같은 줄을 쓴다 (병합 가드·merge-land 는 파일 + log 의 글자 그대로 일치만 본다) · 형식 틀림·위변조 = REJECT rc 2(상태 쓰기 0)
# 상태 = $STATE/autonomy.json {mode,since,event,until} + 추가 전용 autonomy.log (모드 줄 = epoch<TAB>on|off<TAB>A<N> · 승인 줄은 탭 없음)
#   expire       끝 시각(until)이 지난 ON 이면 off 줄 1회 + `EXPIRED A<N>` · 아니면 아무것도 안 쓰고 `NOOP`(멱등) — 틱이 매 루프 부른다(R185) · `mode`·`status` 는 쓰지 않고도 until 지난 ON 을 OFF 로 읽는다(status = `[자율 OFF · A<N> 끝 도달 HH:MM]`)
# 이 스크립트만 log 를 쓴다 → json 이 log 의 마지막 «모드 줄»과 어긋나거나 그 뒤에 불완전·모르는 형식의 줄이 있으면 위변조 = OFF 취급. 시간 창·자동 해제 0(끝 시각은 오빠가 켤 때 정한 값뿐).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${FT_ROOT:-}"   # r385: 라이브 루트 = FT_ROOT → ft_data_root(cwd LIVE_ROOT · 옛 설치 꼴) → ERROR (새 설치본 위치로 풀지 않는다)
[ -n "$ROOT" ] || { . "$HERE/ft-harness-root.sh" && ROOT="$(ft_data_root "$HERE")"; } || exit 2
STATE="${FT_AUTONOMY_STATE_DIR:-$ROOT/.fable-team/state}"
# R383: planner 팀 폴더는 ROOT 의 design/TEAMS.md 로(팀 이름 글자 0) — mode·status 같은 훅 경로는 안 쓰므로 «필요할 때만» 푼다 · 못 풀면 stderr ERROR + rc1(옛 경로 후퇴 0 · #0 RULE)
planner_dir() { if [ -n "${FT_PLANNER_DIR:-}" ]; then printf '%s\n' "$FT_PLANNER_DIR"; return 0; fi
  ( . "$HERE/ft-team-lib.sh" && ft_team_in "$ROOT" planner ) || { echo "ERROR planner 팀 폴더를 못 풀었다(design/TEAMS.md · FT_ROOT=$ROOT) — FT_PLANNER_DIR 로 지정하거나 명단을 고친다" >&2; return 1; }; }
JSON="$STATE/autonomy.json"; LOG="$STATE/autonomy.log"; . "$HERE/ft-autonomy-level.sh"   # r466 레벨·학습·인터뷰

jfield() {  # <키> — autonomy.json 한 줄 값(문자열·숫자)
  sed -n "s/.*\"$1\": *\"\{0,1\}\([A-Za-z0-9]*\)\"\{0,1\}[,}].*/\1/p" "$JSON" 2>/dev/null | head -1
}

fmt() { date -r "$1" "+$2" 2>/dev/null || date -d "@$1" "+$2" 2>/dev/null; }  # <epoch> <형식>
hhmm() { fmt "$1" %H:%M || echo "--:--"; }
now_epoch() { echo "${FT_NOW:-$(date +%s)}"; }  # FT_NOW = 시험용 고정 시계

MODE_RE=$'^[0-9]+\t(on|off)\tA[0-9]+$'; APPROVE_RE='^approve-merge [0-9a-f]{40} (A[0-9]+|OFF|D1) [0-9]+$'   # r947: 이벤트 칸 D1 = 상시 승인(ft-autonomy-standing.sh)
# 범위 사전 승인 줄 3꼴(R298 · ft-autonomy-scope.sh 가 쓴다 · r560: scope-use 종류에 equiv = 이미 센 승인의 EQUIV 재승인·셈 0) — 이 꼴 밖의 줄은 지금처럼 위변조
SCOPE_GRANT_RE='^approve-scope S[0-9]+ A[0-9]+ [0-9]+ until=[0-9]+ max=[0-9]+ daily=[0-9]+ classes=(docs|ff|revert|code)(,(docs|ff|revert|code))*( codemax=[0-9]+)?( repos=byz,pack)?( level=(full|mid))?$'
SCOPE_USE_RE='^scope-use S[0-9]+ [0-9a-f]{40} (docs|ff|revert|code|equiv) [0-9]+( repo=pack)?( learned=[a-z0-9,-]+)?$'; SCOPE_STOP_RE=$'^scope-stop S[0-9]+ [0-9]+ [^\t]+$';   DOC_EXEMPT_RE='^doc-exempt [0-9a-f]{40} team=[a-z0-9][a-z0-9_-]* files=[0-9]+ by=[A-Za-z0-9#_-]+$'; DOC_EXEMPT_REJ_RE='^doc-exempt-reject [0-9a-f]{40} by=[A-Za-z0-9#_-]+$'   # R725 문서 전용 PR 예외 착지 기록(ft_doc_exempt.py · merge-land·가드) — 형식 고정
STANDING_GRANT_RE='^approve-standing D1 [0-9]+ repos=pack classes=(code|docs)(,(code|docs))? da=external$'; STANDING_USE_RE='^standing-use D1 [0-9a-f]{40} [0-9]+ pr=[0-9]+ repo=pack da=[0-9a-f]{40}$'; STANDING_STOP_RE=$'^standing-stop D1 [0-9]+ [^\t]+$'   # r947 상시 승인 D1 3꼴(ft-autonomy-standing.sh 가 쓴다)
# log 를 ⓐ정상 모드 줄 ⓑ정당한 부가 줄(승인 줄·범위 승인 줄·형식 고정) ⓒ그 밖 으로 가른다. stdout = 마지막 정상 모드 줄 · rc 1 = 그 뒤에 ⓒ(불완전·모르는 줄) 가 있음 = 위변조
log_last_mode() {
  local line last="" bad=0
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ $MODE_RE ]]; then last="$line"; bad=0
    elif [[ "$line" =~ $APPROVE_RE || "$line" =~ $SCOPE_GRANT_RE || "$line" =~ $SCOPE_USE_RE || "$line" =~ $SCOPE_STOP_RE || "$line" =~ $DOC_EXEMPT_RE || "$line" =~ $DOC_EXEMPT_REJ_RE || "$line" =~ $STANDING_GRANT_RE || "$line" =~ $STANDING_USE_RE || "$line" =~ $STANDING_STOP_RE ]]; then :
    else bad=1; fi
  done 2>/dev/null < "$LOG"
  printf '%s' "$last"; return $bad
}

# json·log 정합 상태 → "on|off|tamper" (파일 없음 = off) — 끝 시각은 보지 않는다
valid_mode() {
  local m s e last bad
  [ -f "$JSON" ] || { echo off; return; }
  m="$(jfield mode)"; s="$(jfield since)"; e="$(jfield event)"
  last="$(log_last_mode)"; bad=$?
  if [ -n "$m" ] && [ "$bad" = 0 ] && [ "$last" = "$(printf '%s\t%s\t%s' "$s" "$m" "$e")" ] && { [ "$m" = on ] || [ "$m" = off ]; }; then
    echo "$m"
  else
    echo tamper
  fi
}

# 정합 ON 이고 끝 시각(until)이 숫자이며 지금 ≥ until 이면 그 until 을 출력(rc 0) — 아니면 rc 1 (끝 없음 null · 아직 전 · OFF · 위변조)
expired_until() {
  local u; [ "$(valid_mode)" = on ] || return 1
  u="$(jfield until)"; [[ "$u" =~ ^[0-9]+$ ]] || return 1
  [ "$(now_epoch)" -ge "$u" ] && printf '%s' "$u"
}

# 유효 상태 → "on|off|tamper" — 끝 시각이 지난 ON 은 off 로 읽는다(R185 · 판정 1720 ①: 훅·대리 도구·틱 전부 이 한 곳을 통해 읽는다)
mode() {
  local m; m="$(valid_mode)"
  if [ "$m" = on ] && expired_until >/dev/null; then echo off; else echo "$m"; fi
}

# 마지막 사건 번호(마지막 모드 줄) — 없으면 빈 값
event() { log_last_mode | cut -f3; }

count_proxy() {  # <A<N>> — 판정 원장의 대리 줄 수
  local n pd; pd="$(planner_dir)" || { echo "?"; return 0; }; n="$(cat "$pd"/VERDICTS-*.md 2>/dev/null | grep -cF "[대리 · 자율 ON $1]")"; echo "${n:-0}"
}
queue_file() { ( . "$HERE/ft-team-lib.sh" && ft_planner_queue "$ROOT" ) || { echo "ERROR 오빠 큐 자리를 못 풀었다(ft_planner_queue · FT_ROOT=$ROOT)" >&2; return 1; }; }   # r515: 대리·결정 셈과 같은 리졸버
count_queue() { local n q; q="$(queue_file)" || { echo "?"; return 0; }; n="$(grep -cF "| $1 |" "$q" 2>/dev/null)"; echo "${n:-0}"; }

status() {
  local m e s u
  m="$(valid_mode)"
  u="$(expired_until)" && m=expired
  case "$m" in
    tamper) echo "[자율 ?? 위변조 → OFF]" ;;
    off) echo "[자율 OFF]" ;;
    expired) echo "[자율 OFF · $(jfield event) 끝 도달 $(hhmm "$u")]" ;;
    on) e="$(jfield event)"; s="$(jfield since)"; u="$(jfield until)"
        case "$u" in ''|null) u="끝 없음" ;; *) u="~$(hhmm "$u")까지" ;; esac
        echo "[자율 ON $e · $(hhmm "$s")~ · $u · 대리 $(count_proxy "$e") · 큐 $(count_queue "$e")$(level_status)]" ;;
  esac
}

write_state() {  # <모드> <사건> [until epoch|null] [레벨] — log 먼저, json 은 임시 파일 → mv (json 이 log 를 앞서지 않는다) · 레벨 칸은 있을 때만(r466)
  local now; now="$(now_epoch)"
  mkdir -p "$STATE" || { echo "REJECT 상태 폴더를 못 만들었다: $STATE" >&2; exit 1; }
  printf '%s\t%s\t%s\n' "$now" "$1" "$2" >> "$LOG" || { echo "REJECT log 쓰기 실패" >&2; exit 1; }
  printf '{"mode":"%s","since":%s,"event":"%s","until":%s%s}\n' "$1" "$now" "$2" "${3:-null}" "${4:+,\"level\":\"$4\"}" > "$JSON.tmp.$$" && mv "$JSON.tmp.$$" "$JSON" || { echo "REJECT json 쓰기 실패" >&2; exit 1; }
}

# 상태 쓰기 전부(on·off·expire·approve-merge)는 같은 mkdir 잠금 안에서 «재확인 → 기록 → 교체» (R185 r3 · DA⑥ H1 · ft-proxy-decide.sh 의 잠금 꼴) — 상한 5초 뒤 rc 1(조용한 통과 0)
LOCKD="$STATE/.autonomy.lock"; HELD=0
unlock() { [ "$HELD" = 1 ] && rmdir "$LOCKD" 2>/dev/null; HELD=0; }
lock() {
  local i=0; mkdir -p "$STATE" || { echo "REJECT 상태 폴더를 못 만들었다: $STATE" >&2; exit 1; }
  until mkdir "$LOCKD" 2>/dev/null; do i=$((i+1)); [ "$i" -le 50 ] || { echo "REJECT 상태 잠금 선점 중: $LOCKD" >&2; exit 1; }; sleep 0.1; done
  HELD=1; trap unlock EXIT
}

reject() { echo "REJECT $1 (usage: on [--until HH:MM | --for <N>h|<N>m] [--level full|mid|each] [--max n --daily n --code-max n])" >&2; exit 2; }

parse_end() {  # on 의 인자 → UNTIL(epoch|null) · ON_LEVEL ON_MAX ON_DAILY ON_CM(r466). 틀리면 REJECT(상태 쓰기 0). --until 은 지난 시각이면 다음 날(DST 보정 0)
  local kind="" val="" now t
  UNTIL=null; ON_LEVEL=""; ON_MAX=""; ON_DAILY=""; ON_CM=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --until|--for) [ -z "$kind" ] || reject "--until 과 --for 는 함께 못 쓴다"
                     [ $# -ge 2 ] || reject "$1 값 없음"; kind="$1"; val="$2"; shift 2 ;;
      --level|--max|--daily|--code-max) [ $# -ge 2 ] || reject "$1 값 없음"; case "$1" in --level) ON_LEVEL="$2" ;; --max) ON_MAX="$2" ;; --daily) ON_DAILY="$2" ;; *) ON_CM="$2" ;; esac; shift 2 ;;
      *) reject "알 수 없는 인자: $1" ;;
    esac
  done
  [ -n "$kind" ] || return 0
  now="$(now_epoch)"
  if [ "$kind" = --until ]; then
    [[ "$val" =~ ^([01][0-9]|2[0-3]):([0-5][0-9])$ ]] || reject "--until 형식 틀림: $val"
    t=$(( now - 10#$(fmt "$now" %H) * 3600 - 10#$(fmt "$now" %M) * 60 - 10#$(fmt "$now" %S) + 10#${BASH_REMATCH[1]} * 3600 + 10#${BASH_REMATCH[2]} * 60 ))
    [ "$t" -gt "$now" ] || t=$(( t + 86400 ))
  else
    [[ "$val" =~ ^([0-9]+)([hm])$ ]] && [ "$((10#${BASH_REMATCH[1]}))" -gt 0 ] || reject "--for 형식 틀림: $val"
    if [ "${BASH_REMATCH[2]}" = h ]; then t=$(( now + 10#${BASH_REMATCH[1]} * 3600 )); else t=$(( now + 10#${BASH_REMATCH[1]} * 60 )); fi
  fi
  UNTIL="$t"
}

cmd_on() {
  local n ev rc=0
  if [ "$(mode)" = on ]; then status; return 0; fi   # 이미 ON 이면 인자 무시 — 끝 시각은 켤 때만 정한다
  parse_end "$@"; level_prepare   # r466: 레벨 기본표 + 덮어쓰기 검사 — 틀리면 상태 쓰기 0
  if [ -f "$ROOT/.fable-team/seats-planner.json" ]; then   # R342: planner(arch 상시 팀)는 `_arch` 라이브가 아니면 ON 0 — 상태·잠금을 만지기 전에 거절 · 명부 없는 환경은 검사 대상 아님
    _ao="$(python3 "$HERE/ft_teamset.py" arch-live --root "$ROOT" --md "${FT_TEAMSET_MD:-gitref:origin/main:design/TEAMSET.md}" --team planner 2>&1)"; _arc=$?
    [ "$_arc" = 0 ] || { [ "$_arc" = 3 ] && echo "REJECT planner arch 없음 — 자율 ON 0 · $_ao · 먼저 planner arch 를 여세요(ft-role-spawn.sh arch)" >&2 || echo "REJECT planner arch 판정 실패(rc=$_arc) — 자율 ON 0 · $_ao" >&2; exit 2; }
  fi
  bash "$HERE/ft-autonomy-start.sh" preflight   # 인증 사전 점검 — 결과를 status 위에 찍을 뿐 켜기를 막지 않는다
  lock
  if [ "$(mode)" = on ]; then unlock; status; return 0; fi   # 잠금을 기다리는 사이 다른 호출이 켰다
  n="$(grep -c "$(printf '\ton\t')" "$LOG" 2>/dev/null)"
  ev="A$(( ${n:-0} + 1 ))"; level_grant_post "$ev"   # 범위 승인 슬랙 게시 «먼저» — 실패면 모드 줄도 0
  write_state on "$ev" "$UNTIL" "$ON_LEVEL"; level_grant_write; unlock
  bash "$HERE/ft-autonomy-start.sh" ledger "$ev" || { echo "ERROR 시작 장부 쓰기 실패 — 자율 상태는 이미 ON ($ev)" >&2; rc=1; }
  status
  return $rc
}

cmd_off() {
  local ev; lock; ev="$(event)"
  if { [ "$(mode)" = off ] && [ -f "$JSON" ]; } || { [ ! -f "$JSON" ] && [ -z "$ev" ]; }; then unlock; echo "[자율 OFF] (이미 OFF)"; return 0; fi
  [ -n "$ev" ] || ev="A0"
  write_state off "$ev" null "$(jfield level)"; unlock   # 레벨 기록 유지(r466)
  echo "[자율 OFF] $ev 구간 요약: 대리 $(count_proxy "$ev") · 큐 $(count_queue "$ev") · 큐 파일 $(queue_file 2>/dev/null || echo "<planner 폴더 못 풂>")"
  interview_note "$ev" off || true   # desk 에 [자율 인터뷰] 1통 — 못 보내면 WARN(stderr) · OFF 는 이미 끝
}

cmd_expire() {  # 끝 도달 기록 — 정합 ON ∧ until 지남일 때만 off 줄 1회(log 먼저·json 나중). 단일 기록자 = 틱 · 끄기만(on 은 오빠 `!` 전용 · R164)
  local ev; lock
  expired_until >/dev/null || { unlock; echo NOOP; return 0; }   # 잠금 안에서 재확인 — 먼저 끝낸 호출이 있으면 NOOP
  ev="$(jfield event)"
  write_state off "$ev" null "$(jfield level)"; unlock
  echo "EXPIRED $ev"
}

cmd_approve_merge() {  # <40hex>… — 검증을 전부 마친 뒤에만 쓴다. 쓰기 순서 = log 먼저, 승인 파일 나중(파일만 있고 log 줄 없음 = 병합 가드 deny)
  local sha ev now dir="$STATE/autonomy-merge-approved" line
  [ $# -ge 1 ] || { echo "REJECT sha 없음 (usage: approve-merge <40hex>…)" >&2; exit 2; }
  for sha in "$@"; do [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "REJECT sha 형식 틀림(40hex 소문자): $sha" >&2; exit 2; }; done
  lock; [ "$(mode)" = tamper ] && { echo "REJECT 자율 상태 위변조(tamper) — 승인 기록 없음" >&2; exit 2; }   # R336: on·off 둘 다 기록(OFF 면 이벤트 칸 OFF)
  ev="$(event)"; [ "$(mode)" = off ] && ev=OFF; now="$(now_epoch)"
  mkdir -p "$dir" || { echo "REJECT 승인 폴더를 못 만들었다: $dir" >&2; exit 1; }
  for sha in "$@"; do
    line="approve-merge $sha $ev $now"
    printf '%s\n' "$line" >> "$LOG" || { echo "REJECT log 쓰기 실패" >&2; exit 1; }
    { printf '%s\n' "$line" > "$dir/$sha.tmp" && mv "$dir/$sha.tmp" "$dir/$sha"; } || { echo "REJECT 승인 파일 쓰기 실패: $dir/$sha" >&2; exit 1; }
    echo "APPROVED $sha $ev"; learn_kind "$sha" "$now"   # r466: 거절 원장에 있던 sha 면 그 종류를 학습(ON ∧ full)
  done; echo "EQUIV 허용 범위: 이 승인은 같은 변경 집합(승인 sha 위에 main 병합만 더한 head)에도 유효 — 병합 훅이 ft_approval_equiv 로 대조(r462)" >&2
}

case "${1:-}" in
  on) shift; cmd_on "$@" ;;
  forget-kind|interview-note|on-check) c="cmd_${1//-/_}"; shift; "$c" "$@" ;;   # r466 학습표에서 종류 빼기(오빠 `!` 전용) · desk 에 [자율 인터뷰] 1통(틱 expire 뒤 · off 는 스스로) · on 인자 검사만(쓰기 0)
  approve-merge) shift; cmd_approve_merge "$@" ;;
  approve-scope|scope-approve|scope-stop|scope-status) c="${1//-/_}"; shift; . "$HERE/ft-autonomy-scope.sh"; "cmd_$c" "$@" ;;  # 범위 사전 승인(R298) — approve-scope = 오빠 `!` 전용
  off) cmd_off ;; expire) cmd_expire ;;
  status) status ;;
  approve-standing|standing-approve|standing-stop|standing-status) c="${1//-/_}"; shift; . "$HERE/ft-autonomy-standing.sh"; "cmd_$c" "$@" ;;  # r947 상시 승인 D1 — approve-standing = 오빠 `!` 전용 · standing-approve = planner master 좌석만
  mode) mode ;; event) event ;;
  state-dir) printf '%s\n' "$STATE" ;;
  *) echo "usage: ft-autonomy.sh on|off|expire|status|mode|event|state-dir|approve-merge <40hex>…|approve-scope|scope-approve|scope-stop|scope-status|approve-standing|standing-approve|standing-stop|standing-status|forget-kind <키>|interview-note <A<N>> <expire|off>" >&2; exit 2 ;;
esac
