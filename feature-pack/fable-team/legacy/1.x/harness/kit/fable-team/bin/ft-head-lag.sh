#!/usr/bin/env bash
# ft-head-lag.sh --event|--cron|--summary [--repo <dir>] [--base <ref=origin/main>]   (R243 · 오빠 메인 지침 «main 랜딩 뒤 베이스 맞추기»)
#   main 이 움직인 뒤 그 위에 있지 않은 워크트리를 찾아, 그 워크트리에 앉은 팀의 master 에 mbox 1통(팀당)을 보낸다. 최신화 자체는 하지 않는다(ft-head-sync.sh --apply 는 그 팀 몫).
#   --event   = 랜딩 직후(ft-merge-land.sh) · 문턱 0 = 즉시        --cron = launchd 30분 안전망 · 문턱 FT_HEAD_LAG_MIN(기본 60분)
#   --summary = 뉴스용 1줄(`베이스 뒤처짐 N곳(가장 오래 <워크트리> N커밋·N시간)` · 0곳이면 빈 출력) · fetch·알림·상태 쓰기 0
#   워크트리당 1회(main sha 가 바뀌어도 그대로 · R836), 6시간(FT_HEAD_LAG_REMIND_H) 뒤 재알림 1회(상한) · 따라잡으면 기록 삭제. 상태 = <루트>/.fable-team/state/head-lag.json
#   7초 룰(판정 666): fetch = fm_fetch(7 s + 재시도 1). exit 0 = 정상 · 2 = usage · 4 = fetch/기준 확인 실패(알림 0) · 5 = mbox 발신 실패 있음
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/ft-merge-lib.sh"
MODE=""; REPO=""; BASE="origin/main"
usage() { echo "usage: $0 --event|--cron|--summary [--repo <dir>] [--base <ref=origin/main>]" >&2; exit 2; }
while [ $# -gt 0 ]; do case "$1" in
  --event|--cron|--summary) [ -z "$MODE" ] || usage; MODE="${1#--}"; shift;;
  --repo) [ $# -ge 2 ] || usage; REPO="$2"; shift 2;;
  --base) [ $# -ge 2 ] || usage; BASE="$2"; shift 2;;
  *) usage;; esac; done
[ -n "$MODE" ] || usage
[ -n "$REPO" ] || REPO="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR repo 를 찾을 수 없음" >&2; exit 4; }
if [ "$MODE" != summary ] && [[ "$BASE" == */* ]] && git -C "$REPO" remote get-url "${BASE%%/*}" >/dev/null 2>&1; then
  fm_fetch "$REPO" "${BASE%%/*}" "${BASE#*/}" || { echo "ERROR fetch $BASE 실패(7 s + 재시도 1) — 알림 0" >&2; exit 4; }
fi
exec python3 -I "$HERE/ft_head_lag.py" "--$MODE" --repo "$REPO" --base "$BASE" --bin "$HERE"
