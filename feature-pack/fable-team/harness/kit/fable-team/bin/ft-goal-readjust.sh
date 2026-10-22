#!/usr/bin/env bash
# ft-goal-readjust.sh --request "<요청 출처 1줄>" [--retry] — 골 재조정 «회차» 1회 실행 = ★수동 진입점 하나★ (r714a · 설계 r3 §5 + 오빠 10-22 정정).
#   ★자동 시계 0★ — launchd 없음. 회차는 «요청받을 때만» 돈다(오빠·오케가 이 한 줄을 부른다). 요청 없는 날은 회차 0.
#   ★--request 필수★(출처는 회차 파일 `request` 칸) — 없으면 usage rc2 · 모르는 인자도 rc2.
#   ★하루 최대 2회★ — 오늘 회차가 2 면 3번째 요청은 `REJECT 오늘 2회 다 씀 · 다음 = 내일` rc2(쪽지 0 · 파일 0) · run = <YYYYMMDD>-<k>(k = 그날 몇 번째 요청).
#   --retry = 마지막 회차를 이어서(측정값만 다시 잼 · 쪽지 상한 그대로). 미완 회차(ERROR·claimed 무영수증)는 인자 없이도 자동으로 이어간다.
#   ★총 마감 70초★: 래퍼가 `timeout 70` 으로 감싸고, 본체는 FT_GOAL_READJUST_BUDGET(기본 65초)을 측정 «중»에도 넘기면 스스로 ERROR 회차를 남긴다.
#   잠금 선점 실패 = `SKIP busy` 1줄 + rc0(쪽지 0 · 회차 파일 0) · rc = 0 OK · 1 ERROR 회차 · 2 usage/REJECT · 3 송신 실패·모름(회차는 끝남).
#   쓰기 = <루트>/.fable-team/state/goal-readjust/ 아래 + git fetch 뿐(작업 트리·refs/heads 무변경) · 쪽지 = run 당 1통.
#   ★python3 -B★ — 설치 사본 bin 아래 __pycache__ 를 만들지 않는다(쓰기 허용 목록 밖 쓰기 0 · DA H11).
set -uo pipefail
PYTHONDONTWRITEBYTECODE=1
export PYTHONDONTWRITEBYTECODE
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BODY="$HERE/ft_goal_readjust.py"
[ -f "$BODY" ] || { echo "ERROR 골 재조정 — 본체 없음: $BODY" >&2; exit 1; }
timeout 70 python3 -B "$BODY" "$@"
rc=$?
if [ "$rc" = 124 ]; then
  echo "ERROR 골 재조정 — 70초 초과(timeout)로 끊겼다 · 이번 회차는 끝까지 못 돌았다(회차 파일이 없을 수 있다 · ERROR 회차도 못 남겼다)" >&2
  exit 1
fi
exit "$rc"
