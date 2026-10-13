#!/bin/bash
# ft-tick-line.sh — 오케 좌석 체크 틱 = «밖에서 재고 안에는 한 줄» (PLAN-harness-networking D2 · N1 r-net-tick-line). 읽기만 · 외부 호출 0.
# 추적 사본: scripts/fable-team-bin/ft-tick-line.sh · 런타임 자리: <워크트리>/.fable-team/bin/ (gitignore)
#
# usage: ft-tick-line.sh <내 좌석> [--team <명부 파일>]
# 출력 ≤5줄·≤500자. 첫 줄: `TICK <좌석> @<ISO> age=<스냅샷 초>s src=turn-live(<n>)+snapshot@<ISO> …`
#   전부 0 ∧ 전부 측정 성공 → `… 0/0/0 — 할 일 없음` (그 한 줄로 턴을 끝낸다) · 하나라도 모름이면 첫 줄에 `UNKNOWN <k>석[+<o>건]` 개수만 쓰고
#   이유는 행(`UNKNOWN <좌석> <이유>` 1석 1행)으로 내린다 (할 일 없음 금지 · 모름을 0 으로 바꾸지 않는다).
#   정지 분의 «경계»는 스냅샷 값을 쓰지 않는다 — 내 팀 활성 좌석(≤8석, 나 제외)을 매 틱 `ft-seat-status.sh turn` 으로 라이브 측정해
#   틱 시점에 now−턴 끝을 다시 계산한다(ft_board_seat.py 의 cell·rows 와 같은 식 · 3분 경계). 스냅샷은 개입 대상이 아닌 값
#   (관찰 중 건수 · 타 팀 정지 수)에만 쓰고 그 줄에 시각을 붙인다.
#   행(둘째 줄~): 정지/완료 뒤 작업/완료 선언 미처리 · UNKNOWN 좌석 · 큐 주의 seq([결정]/[HIL]/[긴급]/[합치기]/[정지 레디]/[완료]) · 명부 불일치.
#   상한(≤5줄·≤500자)은 첫 줄+행+`… 전체 <N>행 → <경로>` 줄을 «합쳐서» 집행한다. 넘치면 행부터 접고 전체는 <경로> = <FT_TICK_OUT_DIR>/<좌석>-<ts>.txt
#   (좌석당 최근 20개만 남긴다). 본체는 ft_tick_line.py.
# env: FT_ROOT · FT_BOARD_NOW(ISO · 시험) · FT_BOARD_SEAT_STATUS(turn 스텁/경로) · FT_TMUX_LS_CMD · FT_SEATS_GLOB · FT_TICK_OUT_DIR(기본 <루트>/.fable-team/state/tick)
# 틱 안에서 pane 캡처·recv --all·보고문 작성 금지 — 할 일이 나오면 그때 recv.

set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SEAT="${1:-}"; TEAM=""
[ -n "$SEAT" ] || { echo "usage: $0 <내 좌석> [--team <명부 파일>]" >&2; exit 2; }
shift
while [ $# -gt 0 ]; do
  case "$1" in --team) TEAM="${2:-}"; shift 2 ;; *) echo "usage: $0 <내 좌석> [--team <명부 파일>]" >&2; exit 2 ;; esac
done
if [ -z "${FT_ROOT:-}" ]; then
  common="$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || common=""
  [ -n "$common" ] && FT_ROOT="$(dirname "$common")"
fi
export FT_ROOT SEAT TEAM HERE
export FT_SEATS_GLOB="${FT_SEATS_GLOB:-$FT_ROOT/.fable-team/seats*.json}"
export FT_TICK_OUT_DIR="${FT_TICK_OUT_DIR:-$FT_ROOT/.fable-team/state/tick}"
export LINT_OUT; LINT_OUT="$(bash "$HERE/ft-seats-lint.sh" ${TEAM:+--team "$TEAM"} 2>/dev/null)"  # stdout 만 파싱 — 2>&1 은 bash setlocale 경고를 첫 줄로 섞는다(출력이 비면 아래 «해석 실패» UNKNOWN 으로 드러난다)

exec python3 "$HERE/ft_tick_line.py"
