#!/usr/bin/env bash
# ft-bg-watch.sh — 좌석 밖 «끝이 있는 반복» 감시 도우미 (r1572 · 카드 r1572-detached-watch-ttl · 수용 ⓐ)
#   본체 = «1회 작업 명령»(한 번 돌고 끝나는 명령). 도우미가 --every 간격마다 1회씩 부르고, 회차 «시작 전» 에 --end-at 을 검사한다.
#   대기는 min(--every, 남은 기한) — 기한을 넘겨 남지 않는다(DA R2).
#   끝 시각이 지났으면 새 회차 0 · 장부 «끝남» · 도우미 종료. 회차가 상한(기본 25초)을 넘으면 «그 회차 자식만» 끝내고
#   장부 «실패 — 1회 작업이 안 끝남» + 소유자 1통 + 도우미 종료(새 회차 0). 상주형(본체가 스스로 도는 while True)은 대상이 아니다 — 그건 ft-bg-loop.sh 쪽.
#   필수 4개 — --seat <소유 좌석> --until <끝 조건 1줄> --end-at <epoch|YYYY-MM-DDTHH:MM[:SS]> --every <초> · 옵션만 있고 값이 없어도 «실행 전» rc2(기본값 대체 0)
#   장부 = <데이터 루트>/.fable-team/state/bg-watch.tsv (env FT_BGW_LEDGER) · 한 줄 = event seat uid pid lstart cmdhash end_at every until ts cmd (탭 11칸)
#     up=띄움 · round=회차(«시각만» 적고 성공 표시 0) · done=끝남 · fail=실패 — 1회 작업이 안 끝남
#   출력 1줄 `bg-watch seat=<좌석> rounds=<n> end=deadline|fail rc=<n>` · kill 은 «이 도우미의 회차 자식» 만(다른 프로세스 0)
#   --adopt <pid> = «이미 도는» 프로세스를 kill 없이 장부에 올린다(띄우지 않는다 · 회차 0). uid·pid·lstart·명령줄해시는 ps 에서 읽고 every 칸은 «-»
#     필수 = --adopt·--seat·--until·--end-at · pid 없음·내 uid 아님·ppid ≠ 1·시작 시각 못 읽음·끝 시각 지남 = rc2(쓰기 0)
#     출력 1줄 `bg-watch adopt pid=<n> key=<uid:pid:lstart:cmdhash> rc=0` · 거절 1줄 `bg-watch adopt pid=<n> 거절|판정 불가 <사유> rc=2(쓰기 0)`
#   env(시험·이식): FT_BGW_LEDGER · FT_BGW_ROUND_SEC · FT_BGW_NOW_CMD · FT_BGW_SLEEP_CMD · FT_BGW_MBOX · FT_BGW_UID · FT_BGW_PS_CMD
#   사용: nohup bash ft-bg-watch.sh --seat <좌석> --until "<끝 조건>" --end-at <끝 시각> --every <초> -- <1회 명령…> &
set -uo pipefail
USAGE="usage: $0 --seat <좌석> --until <끝 조건 1줄> --end-at <epoch|YYYY-MM-DDTHH:MM[:SS]> --every <초> -- <1회 명령…>"
UADOPT="usage: $0 --adopt <pid> --seat <좌석> --until <끝 조건 1줄> --end-at <epoch|YYYY-MM-DDTHH:MM[:SS]>"
SEAT=""; UNTIL=""; END=""; EVERY=""; ADOPT=""
while [ $# -gt 0 ]; do case "$1" in
  --seat|--until|--end-at|--every|--adopt)
    { [ $# -ge 2 ] && [ -n "${2:-}" ]; } || { echo "$USAGE — $1 값이 없다(실행 0)" >&2; exit 2; }
    case "$1" in --seat) SEAT="$2";; --until) UNTIL="$2";; --end-at) END="$2";; --every) EVERY="$2";; --adopt) ADOPT="$2";; esac; shift 2;;
  --) shift; break;; *) echo "$USAGE" >&2; exit 2;; esac; done
if [ -n "$ADOPT" ]; then
  { [ -n "$SEAT" ] && [ -n "$UNTIL" ] && [ -n "$END" ]; } ||
    { echo "$UADOPT — --adopt·--seat·--until·--end-at 이 모두 필요하다(기본값 대체 0 · 쓰기 0)" >&2; exit 2; }
else
  { [ -n "$SEAT" ] && [ -n "$UNTIL" ] && [ -n "$END" ] && [[ "$EVERY" =~ ^[1-9][0-9]*$ ]] && [ $# -gt 0 ]; } ||
    { echo "$USAGE — --seat·--until·--end-at·--every·명령이 모두 필요하다(기본값 대체 0 · 실행 0)" >&2; exit 2; }
fi
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
now() { if [ -n "${FT_BGW_NOW_CMD:-}" ]; then eval "$FT_BGW_NOW_CMD"; else date +%s; fi; }
waits() { if [ -n "${FT_BGW_SLEEP_CMD:-}" ]; then eval "$FT_BGW_SLEEP_CMD $1"; else sleep "$1"; fi; }
wait_sec() { local left w; left=$(( END_AT - $(now) )); w="$1"; [ "$left" -lt "$w" ] && w="$left"; [ "$w" -gt 0 ] && waits "$w"; }
END_AT="$(python3 -c 'import sys,time
s=sys.argv[1].strip()
try: print(int(s)); raise SystemExit
except ValueError: pass
for f in ("%Y-%m-%dT%H:%M:%S","%Y-%m-%dT%H:%M","%Y-%m-%d %H:%M:%S","%Y-%m-%d %H:%M"):
    try: print(int(time.mktime(time.strptime(s,f)))); raise SystemExit
    except ValueError: pass' "$END" 2>/dev/null)"
[[ "${END_AT:-}" =~ ^[0-9]+$ ]] || { echo "ft-bg-watch: ERROR --end-at 을 못 읽음 «${END}» — 실행 0" >&2; exit 2; }
LDG="${FT_BGW_LEDGER:-}"
if [ -z "$LDG" ]; then
  . "$HERE/ft-harness-root.sh"; DR="$(ft_data_root "$HERE" 2>/dev/null)" || DR=""
  [ -n "$DR" ] || { echo "ft-bg-watch: ERROR 데이터 루트를 못 풂(FT_ROOT·LIVE_ROOT 없음) — 장부 자리 모름" >&2; exit 2; }
  LDG="$DR/.fable-team/state/bg-watch.tsv"
fi
mkdir -p "$(dirname "$LDG")" 2>/dev/null || true
ROW() { local o= f; for f; do f="${f//[$'\t\n\r']/ }"; o="$o$(printf '\t%s' "$f")"; done; printf '%s\n' "${o:1}" >>"$LDG"; }
UID_N="${FT_BGW_UID:-$(id -u)}"
if [ -n "$ADOPT" ]; then   # 등록 전용 — 띄우지 않는다(프로세스 변경 0) · 거절이면 장부에 아무것도 쓰지 않는다
  [[ "$ADOPT" =~ ^[1-9][0-9]*$ ]] || { echo "bg-watch adopt 판정 불가 --adopt 값이 pid 숫자가 아니다 «${ADOPT}» rc=2(쓰기 0)"; exit 2; }
  PS_A="env LC_ALL=C TZ=UTC ${FT_BGW_PS_CMD:-ps -axo uid=,pid=,ppid=,lstart=,command=}"
  PSLINE="$(eval "$PS_A" 2>/dev/null | awk -v p="$ADOPT" '$2==p{ if ($4=="-") { lst="-"; c=""; for(i=5;i<=NF;i++) c=c (i>5?" ":"") $i } else { lst=$4" "$5" "$6" "$7" "$8; c=""; for(i=9;i<=NF;i++) c=c (i>9?" ":"") $i } printf "%s\t%s\t%s\t%s\n", $1, $3, lst, c; exit }')"
  IFS=$'\t' read -r A_UID A_PPID A_LST A_CMD <<<"$PSLINE"
  [ -n "${A_UID:-}" ] || { echo "bg-watch adopt pid=$ADOPT 판정 불가 프로세스 없음 rc=2(쓰기 0)"; exit 2; }
  [ "$A_UID" = "$UID_N" ] || { echo "bg-watch adopt pid=$ADOPT 거절 내 uid 아님(uid=$A_UID · 내 uid=$UID_N) rc=2(쓰기 0)"; exit 2; }
  [ "$A_PPID" = "1" ] || { echo "bg-watch adopt pid=$ADOPT 거절 고아가 아니다(ppid=$A_PPID) rc=2(쓰기 0)"; exit 2; }
  [ -n "$A_LST" ] && [ "$A_LST" != "-" ] || { echo "bg-watch adopt pid=$ADOPT 판정 불가 시작 시각을 못 읽음 rc=2(쓰기 0)"; exit 2; }
  A_NOW="$(now)"
  [ "$A_NOW" -lt "$END_AT" ] || { echo "bg-watch adopt pid=$ADOPT 거절 끝 시각이 이미 지났다(end_at=$END_AT · 지금=$A_NOW) rc=2(쓰기 0)"; exit 2; }
  A_CMDH="$(printf '%s' "$A_CMD" | shasum -a 1 2>/dev/null | cut -c1-12)"; [ -n "$A_CMDH" ] || A_CMDH="-"
  A_KEY="$A_UID:$ADOPT:$A_LST:$A_CMDH"   # 인스턴스 키 — lstart 이 다르면 다른 인스턴스(옛 줄을 면제로 쓰지 않는다)
  ROW adopt "$SEAT" "$A_UID" "$ADOPT" "$A_LST" "$A_CMDH" "$END_AT" - "$UNTIL" "$A_NOW" "${A_CMD:0:80}"
  echo "bg-watch adopt pid=$ADOPT key=$A_KEY rc=0"; exit 0
fi
CMD_SELF="$(ps -o command= -p "$$" 2>/dev/null | sed 's/^ *//')"
LST="$(LC_ALL=C TZ=UTC ps -o lstart= -p "$$" 2>/dev/null | tr -s ' ' | sed 's/^ //; s/ $//')"
CMDH="$(printf '%s' "$CMD_SELF" | shasum -a 1 2>/dev/null | cut -c1-12)"; [ -n "$CMDH" ] || CMDH="-"
PID_N="$$"
KEY="$UID_N:$PID_N:$LST:$CMDH"
ROW up "$SEAT" "$UID_N" "$PID_N" "${LST:--}" "$CMDH" "$END_AT" "$EVERY" "$UNTIL" "$(now)" "${CMD_SELF:0:80}"
notify() { local mb="${FT_BGW_MBOX:-}" c
  if [ -z "$mb" ]; then . "$HERE/ft-harness-root.sh"; c="$(ft_comm_dir "$HERE" 2>/dev/null)" || c=""; [ -n "$c" ] && mb="$c/mbox.sh"; fi
  [ -n "$mb" ] && [ -f "$mb" ] && { FT_MBOX_DIR="$(dirname "$mb")" bash "$mb" send "$SEAT" ft-bg-watch "$1" >/dev/null 2>&1 || true; }; }
ROUND_SEC="${FT_BGW_ROUND_SEC:-25}"; ROUNDS=0
while :; do
  T="$(now)"
  if [ "$T" -ge "$END_AT" ]; then ROW done "$SEAT" "$UID_N" "$PID_N" "${LST:--}" "$CMDH" - - - "$T" -; echo "bg-watch seat=$SEAT rounds=$ROUNDS end=deadline rc=0"; exit 0; fi
  set -m; "$@" & CP=$!; set +m
  i=0; cap=$((ROUND_SEC*5))
  while kill -0 "$CP" 2>/dev/null && [ "$i" -lt "$cap" ]; do sleep 0.2; i=$((i+1)); done
  if kill -0 "$CP" 2>/dev/null; then
    kill -TERM -- "-$CP" 2>/dev/null; sleep 0.5; kill -KILL -- "-$CP" 2>/dev/null; wait "$CP" 2>/dev/null
    ROW fail "$SEAT" "$UID_N" "$PID_N" "${LST:--}" "$CMDH" - - - "$(now)" -
    notify "좌석 밖 감시 회차가 상한 ${ROUND_SEC}초를 넘었다 — 그 회차 자식만 끝내고 도우미를 멈춘다(새 회차 0)
- 좌석 $SEAT · pid $PID_N · lstart ${LST:--}
- 끝 조건: $UNTIL (끝 시각 $END_AT)
- 본체가 스스로 도는 상주형이면 이 도우미 대상이 아니다(ft-bg-loop.sh 쪽) · 장부 = $LDG"
    echo "bg-watch seat=$SEAT rounds=$ROUNDS end=fail rc=1"; exit 1
  fi
  wait "$CP" 2>/dev/null; ROUNDS=$((ROUNDS+1))
  ROW round "$SEAT" "$UID_N" "$PID_N" "${LST:--}" "$CMDH" - - - "$T" -
  wait_sec "$EVERY"      # R2 — 간격과 남은 기한 중 작은 값만 기다린다(기한을 넘겨 남지 않는다)
done
