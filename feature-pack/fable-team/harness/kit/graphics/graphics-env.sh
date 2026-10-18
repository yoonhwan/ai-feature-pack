# source 해서 쓴다 — graphics 팀 값 (ops-env.sh 포크 · 2026-10-09 판정 649·690 · 상시 0 · 요청 때만 planner 가 팀장을 열고 팀장이 좌석을 연다)
# 경로는 이 파일 위치(<ROOT>/.fable-team/bin-graphics/)에서 ROOT 를 구한다 — 임시 ROOT 설치 시험과 실설치가 같은 파일.
_GR_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
export FT_SEATS_JSON="$_GR_ROOT/.fable-team/seats-graphics.json"
export FT_NANO_PREFIX=byz-graphics-nano-
export FT_NANO_WT_PREFIX=graphics-nano-
export FT_ACTIVE_TAG=@zc_graphics_active
export FT_NANO_LEDGER_WT="$_GR_ROOT/.worktrees/harness-ops"
export FT_NANO_LEDGER=design/graphics/NANO-LEDGER-graphics.md
export FT_GOAL_LEDGER=design/graphics/GOAL-graphics.md
# FT_IMPL_MODEL 은 일부러 넣지 않는다 — spawn 기본 agent 는 claude 이고 env 로 agent 를 못 바꾼다. graphics 나노는 발주에서 항상 --agent codex --model gpt-6.1-sol 명시.
export FT_SEND_FROM='byz-graphics-master-claude#0'   # 그래픽스 팀장 — 팀장 승계 때 seats-graphics.json _master 와 같이 고친다
export FT_BIN=/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/v6-realtime-live/.fable-team/bin   # harness-env.sh 와 같은 값
export FT_NANO_FEAT=origin/main
export FT_GOAL_LINES_FILE="$_GR_ROOT/.fable-team/bin-graphics/goal-lines-graphics.txt"
export FT_MBOX_SH="$_GR_ROOT/.fable-team/comm/mbox.sh"   # 추적 사본(scripts/harness-install)에서 spawn 을 돌려도 mbox 를 찾게 한다
export FT_CARD_REQUIRE_PREVERIFY=1   # R16: 카드에 「사전검증」「조사 근거」 절 없으면 spawn lint REJECT
unset _GR_ROOT
