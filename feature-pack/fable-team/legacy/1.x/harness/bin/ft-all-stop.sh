#!/usr/bin/env bash
# ft-all-stop.sh on "<사유>"|off|status|check   (r626 · 오빠 «자율 상태와 별개로 전팀 정지 상태 … 정지 상태일 때는 내가 요청하거나 플랜팀장이 요청한 내용에 대해 간단 작업하고 대답»)
#   on     : <리포 루트>/.fable-team/state/ALL_STOP.json {since,by,reason} + 전 팀 master 에 [전팀 정지] 1통(--urgent) · 이미 켜짐 = 변경 0
#   off    : 파일을 ALL_STOP.released-<시각> 로 옮김 + 전 팀 master 에 «재개 — STATE.md «정지 직전» 절 읽고 이어감 → 다음 카드»
#   status : on/off + since + 팀별 STATE.md «정지 직전» 절이 since 뒤에 적혔나 O/X
#   check  : nano·role spawn · tmux-spawn · press 게이트·device-acquire 가 부른다 — 켜짐·상태 파일 깨짐이면 `REJECT 전팀 정지 중(…)` rc 1
#   check --succession <구> <새> : ft-successor-open 이 부른다 — 진짜 승계(구 좌석 명부 있음 + 새 이름 = 같은 계보 #N+1)만 통과
#   통지 실패 = 상태는 바뀌고 rc 3 + 상태 파일 notify_failed · 같은 on/off 재실행 = 실패분만 재통지 (DA⑥ r1)
#   켜기·끄기는 오빠 `!` 한 줄 또는 planner 팀장만 — 좌석 직접 실행은 autonomy-state-guard 훅이 막는다. PENALTY_STOP·SPAWN_HOLD·RESOURCE_FREEZE·자율과 별개 파일.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
[ -f "$HERE/ft_all_stop.py" ] || { echo "REJECT ft_all_stop.py 없음: $HERE (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }
exec python3 "$HERE/ft_all_stop.py" "$@"
