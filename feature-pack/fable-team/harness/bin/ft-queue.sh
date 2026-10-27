#!/usr/bin/env bash
# ft-queue.sh — 오빠 큐(AUTONOMY-QUEUE.md) 줄 하나씩: 보여준 시각 · 재질문 대상 · 꺼내 재개 (r529 · 오빠 10-20 «노출시간이 한시간 이상 지나면 다시 물어보고 팀장이 꺼내서 다시 진행»)
#   ft-queue.sh shown <qN> [--at "YYYY-MM-DD HH:MM"]        그 줄 «보여준 시각» 칸만 바꿈(기본 지금) — desk 가 오빠께 물은 그 턴에 부른다
#   ft-queue.sh due [--team <팀>] [--min 60]                 재질문 대상: 대기 ∧ (보여준 시각 ≤ 지금−min ∨ -) · 보류 ∧ 재확인 시각 지남(tag=재확인)
#                                                           줄마다 `DUE <qN> team= kind= shown= age= tag= q=` · 끝줄 `QUEUE-DUE n=<n> old=<번호 없는 열린 옛 줄>` · --team planner = 팀 - 줄 포함
#   ft-queue.sh take <qN> --value <오빠 값> --by <master> --verdict <N>   상태 «진행 — <master>» · 사유 끝 «오빠 값: … (판정 N)» · 출력 `RESUME <qN> team= kind= → <재개 안내>`
#   ft-queue.sh remind --rosters <명부 폴더> --mbox <mbox.sh> [--min 60]   (틱 queue_watch) due 줄마다 그 팀 명부 _master 에 [재질문] 1통(팀 -·명부 없는 팀 = planner _master)
#                                                           같은 줄(번호·보여준 시각·tag) = min 분 안 다시 0 · 자율 ON = 쪽지 0 · <상태>/queue-reask-morning.md 아침 묶음 1줄(r291)
#   ft-queue.sh add --ev E --kind K --q Q --choice C --why W [--team T]   (ft-proxy-decide QUEUE 전용) 새 줄 번호 q<최대+1> · 보여준 시각 - · 옛 머리면 머리·구분 행만 10칸
# 본체 = 같은 폴더 ft_queue.py · ft_queue_remind.py · 칸 = 머리 이름으로 찾음(번호·팀·보여준 시각 = 상태 칸 뒤 · 옛 7칸 줄은 셋 다 - 로 읽음 · 옛 줄 고쳐 쓰기 0) · 파서 = ft_queue_state.py(r528 그대로)
# 한 번에 한 줄만 바꿈(다른 줄 바이트 0 변경 · 같은 폴더 임시 파일 → rename) · 쓰기 줄은 ft-proxy-decide 와 같은 락(<상태>/.proxy.lock)
# rc 0 = 됨 · 1 = 대상 없음·REJECT·쪽지 실패 · 2 = 큐·명부·자율 상태 읽기 실패 · 4 = 인자 오류 · 5 = 쓰기 실패 (조용한 통과 0 · #0 RULE)
# 환경: FT_ROOT · FT_AUTONOMY_STATE_DIR · FT_PLANNER_DIR · FT_QUEUE_FILE(큐 파일 직접) · FT_TEAMS_REF(큐 origin/main 판 읽기 · 기본 origin/main) · FT_LEDGER_REPO(그 판을 읽을 리포 · 기본 ROOT) · FT_NOW(시각 고정 · 시험) · FT_QUEUE_AUTONOMY_BIN(기본 같은 폴더 ft-autonomy.sh)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
cmd="${1:-}"
case "$cmd" in shown|due|take|remind|add) ;; *) echo "usage: ft-queue.sh shown|due|take|remind|add …" >&2; exit 4 ;; esac
# r557: «읽기만» 하는 명령(remind·due)은 큐를 origin/main 판에서 읽는다 — 틱 루트(공용 루트 체크아웃)엔 새 자리 design/teams/planner/ 가 없어 ft_planner_queue 가 옛 자리로 후퇴하면 매 틱 «큐 읽기 실패» ERROR(r545·r551 과 같은 꼴). 쓰는 명령(shown·take·add) 자리 변경 0.
#   읽기 함수 = ft-team-lib.sh ft_planner_queue_ref(r839 · ft-queue.sh 는 호출만 · 같은 이름 옛 ft_queue_ref 삭제)
QUEUE="${FT_QUEUE_FILE:-}"; ROOT="${FT_ROOT:-}"
if [ -z "$QUEUE" ]; then
  [ -n "$ROOT" ] || { . "$HERE/ft-harness-root.sh" && ROOT="$(ft_data_root "$HERE")"; } || { echo "ERROR 라이브 루트를 못 풂(FT_ROOT)" >&2; exit 2; }
  . "$HERE/ft-team-lib.sh" || { echo "ERROR ft-team-lib.sh 를 못 읽음" >&2; exit 2; }
  case "$cmd" in remind|due) [ -n "${FT_PLANNER_DIR:-}" ] || { QUEUE="$(ft_planner_queue_ref "$ROOT")" || exit 2; trap 'rm -f "$QUEUE"' EXIT; } ;; esac
  if [ -z "$QUEUE" ]; then
    QUEUE="$(ft_planner_queue "$ROOT")" || { echo "ERROR 오빠 큐 자리를 못 풂(ft_planner_queue · FT_ROOT=$ROOT)" >&2; exit 2; }
  fi
fi
STATE="${FT_AUTONOMY_STATE_DIR:-${ROOT:-$(dirname "$QUEUE")}/.fable-team/state}"
MODE=""
if [ "$cmd" = remind ]; then
  MODE="$(bash "${FT_QUEUE_AUTONOMY_BIN:-$HERE/ft-autonomy.sh}" mode 2>/dev/null)" && [ -n "$MODE" ] || { echo "ERROR 자율 모드를 못 읽음 — 쪽지·아침 묶음 0" >&2; exit 2; }
fi
case "$cmd" in shown|take|add)
  mkdir -p "$STATE" || { echo "ERROR 상태 폴더 생성 실패: $STATE" >&2; exit 5; }
  i=0; until mkdir "$STATE/.proxy.lock" 2>/dev/null; do i=$((i+1)); [ "$i" -le 50 ] || { echo "ERROR 락 선점 중: $STATE/.proxy.lock" >&2; exit 5; }; sleep 0.1; done
  trap 'rmdir "$STATE/.proxy.lock" 2>/dev/null' EXIT ;;
esac
FT_QUEUE_MODE="$MODE" python3 "$HERE/ft_queue.py" "$QUEUE" "$STATE" "$@"   # 본체 = ft_queue.py(remind = ft_queue_remind.py) · rc 그대로
