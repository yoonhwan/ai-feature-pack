#!/bin/bash
# shellcheck disable=SC2034  # 아래 전역(WT·SEATS·STATE_DIR·PASS_MAX·FT_TICK_DEADLINE·ACCT_LOCK_WHO)은 source 한 ft-tick-acct-lib.sh 가 읽는다
# ft-acct-watch.sh — 2.0 루트의 계정 한도 정지·풀림 재개 5분 잡 (r2001 · launchd com.byz.ft-acct-watch · StartInterval 300 · 판정 DA#10 #304257)
#   1.x ft-tick 이 내리던 두 단계(acct_pause_watch · acct_notice)를 ft-tick 없이 부른다 — 한 판 = acct_cycle <루트>(ft-tick-acct-lib.sh 공통 진입점).
#   같은 루트의 ft-tick 이 다시 적재돼도 같은 잠금(<루트>/.fable-team/state/acct-notice/cycle.lock)·같은 소유 기록(STATE_DIR/acct-notice/)을 쓴다.
#   순서 = 재개 먼저(예측이 예산을 다 써도 재개는 굶지 않는다) → 예측·정지·풀림.
#   상한: 한 판 전체 FT_ACCT_WATCH_SEC(25초) · 항목 FT_ACCT_WATCH_ITEM_SEC(7초 — 예측 상한 · 정지 도구 배치) · 넘으면 끊고 «남은 단계 다음 판» 1줄 · sleep 0.
#   ft-acct-watch.sh [--root <루트>] [--dry-run]
#   env: FT_ROOT(루트 · --root 가 우선) · FT_TICK_SEATS(기본 <루트>/.fable-team/seats.json — 명부 이름 조건으로 안내가 통째 건너뛰지 않게)
#        FT_TICK_STATE_DIR(기본 /tmp/ft-tick-state = 1.x 루트 틱과 같은 자리) · FT_TICK_MBOX(기본 공용 루트 comm/mbox.sh) · FT_TICK_ACCT_NOTIFY(안내 대상 · 기본 명부 _hil_route/_master)
#   좌석 kill·pane 입력 0 — 정지·재개 쪽지와 ring 은 ft-acct-pause.sh 가 한다(규칙·파일 꼴 그대로).
set -uo pipefail
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"; export PATH
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_ARG=""; DRY=0; INNER=0; ARGS=("$@")
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT_ARG="${2:-}"; shift 2;;
    --dry-run) DRY=1; shift;;
    --inner) INNER=1; shift;;
    *) echo "usage: $0 [--root <루트>] [--dry-run]" >&2; exit 2;;
  esac
done
log() { echo "$(date '+%F %T') $*"; }
WALL="${FT_ACCT_WATCH_SEC:-25}"; ITEM="${FT_ACCT_WATCH_ITEM_SEC:-7}"
[ -f "$HERE/ft-tick-acct-lib.sh" ] || { log "ERROR acct_watch: ft-tick-acct-lib.sh 없음 — 설치 누락 ($HERE)" >&2; exit 3; }
if [ "$INNER" = 0 ]; then   # 바깥 = 전체 상한만 — 끊기면 안쪽 trap 이 잠금을 닫고(KILL 이면 다음 판이 죽은 주체 잠금을 회수) 여기서 1줄
  timeout -k 2 "$WALL" bash "$0" --inner ${ARGS[@]+"${ARGS[@]}"}; rc=$?
  case "$rc" in 124|137) log "acct_watch: ${WALL}초 넘음 — 판 끊음 · 남은 단계 다음 판"; exit 0;; esac
  exit "$rc"
fi
# shellcheck source=/dev/null
. "$HERE/ft-harness-root.sh"
ROOT="${ROOT_ARG:-${FT_ROOT:-}}"
[ -n "$ROOT" ] || ROOT="$(ft_repo_root "$HERE")" || { log "ERROR acct_watch: 루트 판정 불가 — --root 로 지정하라 ($HERE)" >&2; exit 3; }
[ -d "$ROOT/.fable-team" ] || { log "ERROR acct_watch: $ROOT/.fable-team 없음 — 판정 불가" >&2; exit 3; }
WT="$ROOT"
SEATS="${FT_TICK_SEATS:-$ROOT/.fable-team/seats.json}"
STATE_DIR="${FT_TICK_STATE_DIR:-/tmp/ft-tick-state$([ "$DRY" = 1 ] && echo -dry)}"
MBOX="${FT_TICK_MBOX:-}"
if [ -z "$MBOX" ]; then _CM="$(FT_ROOT="$ROOT" ft_comm_dir "$HERE")" || { log "ERROR acct_watch: comm 폴더 판정 불가" >&2; exit 3; }; MBOX="$_CM/mbox.sh"; fi
export FT_ACCT_ROOT="${FT_ACCT_ROOT:-$ROOT}"                 # 정지 도구가 같은 루트의 ACCT_PAUSE 를 쓴다
export FT_ACCT_BATCH_SEC="${FT_ACCT_BATCH_SEC:-$ITEM}"        # 재개(status) 배치 = 항목 상한
export FT_TICK_ACCT_MAX="${FT_TICK_ACCT_MAX:-$ITEM}"          # 예측 상한 = 항목 상한
PASS_MAX="$WALL"; FT_TICK_DEADLINE="$(( $(date +%s) + WALL - 1 ))"
# shellcheck source=/dev/null
. "$HERE/ft-tick-acct-lib.sh"
ACCT_LOCK_WHO="ft-acct-watch"
trap 'acct_lock_drop' EXIT
trap 'acct_lock_drop; exit 143' TERM INT
acct_cycle "$ROOT"
