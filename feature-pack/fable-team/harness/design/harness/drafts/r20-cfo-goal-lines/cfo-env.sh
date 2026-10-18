# source 해서 쓴다 — CFO 팀 값 (feature-env.sh 포크 · 2026-10-07 R18 · arch#7 안)
export FT_SEATS_JSON=/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/seats-cfo.json
export FT_NANO_PREFIX=byz-cfo-nano-
export FT_NANO_WT_PREFIX=cfo-
export FT_ACTIVE_TAG=@zc_cfo_active
export FT_NANO_LEDGER_WT=/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/c-level-planning
export FT_NANO_LEDGER=design/cfo/NANO-LEDGER-cfo.md
export FT_GOAL_LEDGER=design/cfo/GOAL-cfo.md
export FT_IMPL_MODEL='claude-sonnet-5-5[1m]'
export FT_SEND_FROM='byz-cfo-master-claude#56'   # 승계 때 갱신(.bak-succN 관례)
export FT_BIN=/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/v6-realtime-live/.fable-team/bin
export FT_NANO_FEAT=origin/main   # CFO 나노 base = origin/main — 로컬 main 은 18k 커밋 뒤라 cherry 게이트가 무한 대조(R18b 10-07 CFO 실측)
export FT_MBOX_SH=/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh
export FT_GOAL_LINES_FILE=/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/bin-cfo/goal-lines-cfo.txt   # ft-index-lint 골 3줄 = GOAL-cfo.md 13~15행 (R20 · 없으면 v65 3줄로 검사해 REJECT)
