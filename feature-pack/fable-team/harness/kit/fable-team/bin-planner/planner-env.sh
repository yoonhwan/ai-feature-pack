# source 해서 쓴다 — v6-realtime-live/.fable-team/bin 의 Seatbelt 스크립트를 planner 트랙 값으로 돌린다 (byz-planner-arch#0 · 2026-10-04 · kk-env.sh 꼴)
export FT_SEATS_JSON=/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/seats-planner.json
export FT_NANO_PREFIX=byz-planner-nano-
export FT_NANO_WT_PREFIX=planner-
export FT_ACTIVE_TAG=@zc_planner_active
export FT_NANO_LEDGER_WT=/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/v6-realtime-live
export FT_NANO_LEDGER=design/planner/NANO-LEDGER-planner.md
export FT_GOAL_LEDGER=design/planner/GOAL-planner.md
export FT_GOAL_LINES_FILE=/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/bin-planner/goal-lines-planner.txt   # ft-index-lint 골 3줄 = GOAL-planner.md 원문 줄 3개(P2 · 파일 전체를 읽으면 제목줄이 골 1줄이 된다)
export FT_SEATBELT_README=design/planner/README.md
export FT_IMPL_MODEL='claude-sonnet-5-5[1m]'
export FT_SEND_FROM='byz-planner-arch#0'
export FT_NEWS_TREE=/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/v6-realtime-live/design/planner/NEWS-TREE.md
export FT_BIN=/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/v6-realtime-live/.fable-team/bin
export FT_NANO_FEAT=feat/v6-realtime-live
# planner 는 나노를 열지 않는다(문서만) — 위 나노 변수는 공용 스크립트 호출 호환용 기본값.
export FT_MBOX_SH=/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh   # 추적 사본(scripts/harness-install)에서 spawn 을 돌려도 mbox 를 찾게 한다 (R20)
