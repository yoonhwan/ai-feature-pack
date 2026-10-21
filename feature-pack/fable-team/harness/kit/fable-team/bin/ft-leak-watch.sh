#!/bin/bash
# ft-leak-watch.sh — 틱이 매 루프 한 번 부르는 «유출 부하 경보» (R347 · ft-tick.sh · ft-tick-team.sh 공용)
#   ps 1회 스냅샷(ft-leak-reap.sh --snapshot) → 같은 스냅샷으로 ft-leak-reap.sh --dry-run --quiet → 결과를 경보 큐(_hil_route planner, 없으면 _master)로.
#   ★틱은 영구히 dry-run 경보만 — 사살(--kill) 실행자는 머신당 launchd 가드 1 이다. 이 파일은 --kill 을 부르지 않는다★
#   rc 0(유출 0) → 미해소 유출이 있었으면 [부하 유출 해소] 1통 · rc 10(발견) → [부하 유출 N건] · 그 밖 전부(리퍼 없음·mktemp 실패·python3 없음·rc 20 …) → [부하 유출 조사 실패]
#   ★경보 상태 = 머신 공통 두 칸·잠금 안에서만 갱신★ — $FT_LEAK_ALERT_STATE(미해소 유출 «지문 시각») · $FT_LEAK_ALERT_STATE.err(조사 실패 «지문 시각 연속횟수 다음재조사시각»).
#   ★r670★ 조사 실패(rc 20) 칸은 «연속 N회 · 다음 재조사 60초 뒤» 를 같이 남긴다 — 600초 억제는 «알림 빈도» 만 줄이고, 조사·연속 횟수 갱신은 경과한 틱마다 계속한다(부하 꼭대기에서 눈감지 않기).
#   잠금(mkdir $FT_LEAK_ALERT_STATE.lock · 120s 넘은 잔재는 회수) 안에서 «최신 상태 재조회 → 송신 → 성공 시 원자 교체(mv)/해소 시 삭제» — 못 잡으면 이 틱은 알림만 건너뛴다(다음 틱).
#   같은 지문은 FT_LEAK_REALERT_SEC(600s)에 1통 · 유출 → 조사 실패 → 정상 에서도 유출 칸이 보존돼 해소 1통이 나간다 · 해소 판단은 «내 관측 시각 이후에 쓴 상태»를 건드리지 않는다.
#   오류 지문 = 임시 경로·긴 숫자를 지운 «안정된 원인 문자열» cksum · 수신자 조회는 python3 없이(grep)
#   stdout = 틱이 로그 한 줄로 싣는 «leak-reap: …»(유출 0 이면 조용) · env: FT_TICK_SEATS FT_TICK_MBOX FT_LEAK_REAP_BIN FT_LEAK_ALERT_STATE FT_LEAK_REALERT_SEC FT_LEAK_LOCK_STALE
#   usage: ft-leak-watch.sh [--dry-run]   (--dry-run = DRY 한 줄만 · 호출·송신 0)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REAP="${FT_LEAK_REAP_BIN:-$HERE/ft-leak-reap.sh}"
SEATS="${FT_TICK_SEATS:-}"; MBOX="${FT_TICK_MBOX:-}"
LEAK_ST="${FT_LEAK_ALERT_STATE:-/tmp/ft-leak-alert.state}"; ERR_ST="$LEAK_ST.err"; LOCK="$LEAK_ST.lock"
REALERT="${FT_LEAK_REALERT_SEC:-600}"; LOCK_STALE="${FT_LEAK_LOCK_STALE:-120}"; RECHECK="${FT_LEAK_RECHECK_SEC:-60}"
[ "${1:-}" = --dry-run ] && { echo "DRY kind=leak-reap bin=$REAP"; exit 0; }
now() { date +%s; }
OBS="$(now)"; SNAP=""; HAVE_LOCK=0
trap '[ -z "$SNAP" ] || rm -rf "$SNAP"; [ "$HAVE_LOCK" = 0 ] || rmdir "$LOCK" 2>/dev/null' EXIT

seat_key() {   # $1 = 키 — python3 없이 명부에서 문자열 값(null·없음이면 빈 값)
  grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$SEATS" 2>/dev/null | head -1 | sed 's/.*:[[:space:]]*"\(.*\)"/\1/'
}
route="$(seat_key _hil_route)"; [ -n "$route" ] || route="$(seat_key _master)"
send() {   # $1 = 본문 — 실패면 rc 1(상태를 남기지 않아 다음 틱이 재시도)
  [ -n "$MBOX" ] || { echo "ft-leak-watch: ERROR FT_TICK_MBOX 없음 — 경보 못 보냄" >&2; return 1; }
  [ -n "$route" ] || { echo "ft-leak-watch: ERROR 경보 수신 좌석 없음(_hil_route·_master · SEATS=${SEATS:-없음})" >&2; return 1; }
  bash "$MBOX" send "$route" ft-tick "$1" >/dev/null 2>&1 || { echo "ft-leak-watch: mbox failed to=$route" >&2; return 1; }
}
acquire() {
  mkdir "$LOCK" 2>/dev/null && { HAVE_LOCK=1; return 0; }
  local m; m="$(stat -f %m "$LOCK" 2>/dev/null || stat -c %Y "$LOCK" 2>/dev/null || now)"
  [ $(( $(now) - m )) -gt "$LOCK_STALE" ] && rmdir "$LOCK" 2>/dev/null && mkdir "$LOCK" 2>/dev/null && { HAVE_LOCK=1; return 0; }
  return 1
}
put() { printf '%s %s\n' "$2" "$(now)" > "$1.tmp$$" && mv "$1.tmp$$" "$1"; }   # 원자 교체
put_err() { printf '%s %s %s %s\n' "$1" "$2" "$3" "$4" > "$ERR_ST.tmp$$" && mv "$ERR_ST.tmp$$" "$ERR_ST"; }   # 지문 시각 연속횟수 다음재조사시각(r670)
# 직전 조사 실패의 «다음 재조사 시각» — 예정 시각을 넘겼으면 이번 틱이 그 재조사다(r670 · 같은 틱 안 대기 금지)
PREV_NEXT=0; read -r _pf _pt _pc PREV_NEXT 2>/dev/null < "$ERR_ST" || PREV_NEXT=0
[ "${PREV_NEXT:-0}" -gt 0 ] 2>/dev/null || PREV_NEXT=0

# ── 조사: 어느 분기든 실패는 rc 20 으로 같은 경보 경로에 합류(조용한 종료 0) ──
rc=0; out=""
if [ ! -f "$REAP" ]; then rc=20; out="ft-leak-watch: ERROR 리퍼 없음 $REAP"
elif ! SNAP="$(mktemp)"; then SNAP=""; rc=20; out="ft-leak-watch: ERROR mktemp 실패 — 조사 못 함"
else
  out="$(bash "$REAP" --snapshot="$SNAP" 2>&1)" || rc=$?
  [ "$rc" != 0 ] || { out="$(FT_PS_SNAPSHOT="$SNAP" bash "$REAP" --dry-run --quiet 2>&1)"; rc=$?; }
fi

fp=""; body=""; n=""
case "$rc" in
  0) ;;
  10)
    fp="$(printf '%s\n' "$out" | sed -n 's/.*fp=\([0-9a-f]\{8\}\).*/\1/p' | tail -1)"
    n="$(printf '%s\n' "$out" | sed -n 's/.*유출 \([0-9]*\)건 fp=.*/\1/p' | tail -1)"
    echo "leak-reap: ${out//$'\n'/ | }"
    cand="$(printf '%s\n' "$out" | grep '유출 후보' | head -3 | sed 's/^leak-reap: \[dry\] 유출 후보 //' | cut -c1-90 | tr '\n' ';')"
    body="[부하 유출 ${n:-?}건] 지문 ${fp:-?} — 고아(PPID=1)·부하 시그니처·누적 CPU 30s↑ 프로세스를 dry-run 으로 발견했다. 후보: ${cand} 사살은 틱이 하지 않는다(머신 launchd 가드 담당). 같은 지문은 ${REALERT}초에 1통.";;
  *)
    err="$(printf '%s\n' "$out" | grep -m1 . | cut -c1-160)"
    stable="$(printf '%s' "$err" | sed -E 's#(/[^ :;,]+)+#<경로>#g; s/[0-9]{3,}/N/g')"; fp="ERR:$(printf '%s' "$stable" | cksum | cut -d' ' -f1)"
    echo "leak-reap: ERROR rc=$rc ${err}"
    [ "$PREV_NEXT" -eq 0 ] || [ "$OBS" -lt "$PREV_NEXT" ] || echo "ft-leak-watch: 재조사 — 직전 실패의 예정 시각($PREV_NEXT) 경과 — 이번 틱이 그 1회다"
    body="[부하 유출 조사 실패] 유출 조사를 못 했다(rc=$rc) — ${err}. 유출 0 이 아니라 «못 봤다»다. 연속 @N@회 · 다음 재조사 ${RECHECK}초 뒤 · 같은 오류는 ${REALERT}초에 1통.";;
esac

acquire || exit 0   # 다른 틱이 상태를 쥐고 있다 — 이 틱의 알림은 건너뛴다(다음 틱이 이어받는다)
read -r lfp lts 2>/dev/null < "$LEAK_ST" || { lfp=""; lts=0; }
read -r efp ets ecnt enext 2>/dev/null < "$ERR_ST" || { efp=""; ets=0; ecnt=0; enext=0; }
[ -n "${ets:-}" ] || ets=0; case "${ecnt:-}" in ''|*[!0-9]*) ecnt=0;; esac
if [ "$rc" = 0 ]; then
  [ -z "$efp" ] || { rm -f "$ERR_ST"; echo "leak-reap: 조사 오류 해소($efp · 연속 ${ecnt}회였다)"; }
  [ -n "$lfp" ] || exit 0
  [ "$lts" -lt "$OBS" ] || exit 0   # 내 관측보다 늦게 쓴 유출 상태 — 해소 판단 보류(다음 틱)
  send "[부하 유출 해소] 지문 $lfp 의 고아 부하 프로세스가 더는 보이지 않는다(dry-run 재조사 0건)." && { rm -f "$LEAK_ST"; echo "leak-reap: 유출 해소 지문=$lfp"; }
  exit 0
fi
if [ "$rc" = 10 ]; then
  [ -z "$efp" ] || rm -f "$ERR_ST"   # 유효한 조사 결과가 나왔다 — 오류 칸 해소(연속 횟수 0)
  [ "$lfp" = "$fp" ] && [ $(( $(now) - lts )) -lt "$REALERT" ] && exit 0
  send "$body" && put "$LEAK_ST" "$fp"
  exit 0
fi
# ── 조사 실패(r670): 연속 횟수 · 다음 재조사 시각을 «억제 중에도» 남간다 — 알림(600초)과 조사(경과 틱마다)는 별개다 ──
[ "$efp" = "$fp" ] || ecnt=0
cnt=$(( ecnt + 1 )); body="${body/@N@/$cnt}"; next=$(( OBS + RECHECK ))
if [ "$efp" = "$fp" ] && [ $(( $(now) - ets )) -lt "$REALERT" ]; then
  put_err "$fp" "$ets" "$cnt" "$next"   # 같은 오류 600초 안 — 송신 0, 상태(연속·다음 시각)는 진행
  exit 0
fi
send "$body" && { put_err "$fp" "$OBS" "$cnt" "$next"; exit 0; }   # 송신 실패 = 상태를 남기지 않는다(다음 틱 재시도)
exit 0
