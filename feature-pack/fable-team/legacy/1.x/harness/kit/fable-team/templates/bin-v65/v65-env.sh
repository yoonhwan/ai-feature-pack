# source 해서 쓴다 — v65 팀 값 (r655 견본 · 실제 설치는 master 가 <루트>/.fable-team/bin-v65/v65-env.sh 로 놓는다)
#   ★r655 부터 v65 나노 접두도 다른 팀과 같은 꼴 byz-v65-nano- 다★ — ft-nano-spawn/close 가 카드 팀이 v65 면 이 파일을 읽는다(예외 없음).
#   이 파일이 없어도 v65 는 기본값 byz-v65-nano-(공용 규칙 ft_teamset.py)로 열린다 — 여기 값은 팀별 조정용이다.
#   전환기: 이 파일이 FT_NANO_PREFIX=byz-v65-nano- 를 줘도 **이미 열려 있는 옛 이름(ft-v65-temp-*) 좌석은 그대로 닫힌다**(공용 규칙이 옛 이름도 v65 나노로 센다).
export FT_SEATS_JSON=<루트>/.fable-team/seats.json
export FT_NANO_PREFIX=byz-v65-nano-
export FT_NANO_WT_PREFIX=v65-
export FT_ACTIVE_TAG=@zc_v65_active
export FT_NANO_LEDGER_WT=<루트>/.worktrees/v6-realtime-live
export FT_NANO_LEDGER=20260912/NANO-LEDGER-pm1-temp-sessions.md
export FT_IMPL_MODEL='claude-sonnet-5-5[1m]'
export FT_MBOX_SH=<루트>/.fable-team/comm/mbox.sh   # 추적 사본(scripts/harness-install)에서 spawn 을 돌려도 mbox 를 찾게 한다
