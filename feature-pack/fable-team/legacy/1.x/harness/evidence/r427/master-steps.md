# r427 master 집행 순서 (나노는 push 0)

나노 커밋: (커밋 뒤 mbox 에 sha) · 브랜치 `nano/r427-seat-close-dead-seat-roster-row-and` · base origin/main 7e4fc49e(r413 #72 · r416 #73 포함) · 팩 워크트리 `/Users/yoonhwan/Project/ai-feature-pack/.worktrees/r427-seat-close-dead`

1. push + PR: `git -C <팩 워크트리> push -u origin nano/r427-seat-close-dead-seat-roster-row-and` → `gh pr create --base main` (제목 = 커밋 첫 줄)
2. 착지 뒤 설치: `bash <팩>/feature-pack/fable-team/harness/install.sh --apply --project /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents` → LIVE_BIN 1.1.16 의 ft-seat-close.sh·ft-seat-retire.sh cmp0
3. (선택 · 되돌림 쉬움) 지워진 기록 되살리기: `mv ~/.claude/state/seat-resume/'byz-feature-da-codex#2.json.stale-20261019091458' ~/.claude/state/seat-resume/'byz-feature-da-codex#2.json'` — codex 좌석은 죽은 뒤 대화 기록 탐색이 안 되므로(rollout) 이것을 하면 4 에서 record=kept, 안 하면 NORECORD 로 닫힌다
4. 실사건(feature 13석 · 2026-10-19 10:4x 실측 = 명부 활성 행 15 중 세션 없음 13) — 루트 cwd 에서 판정 번호는 13석 HELD 때 쓴 그 번호:
   `for s in byz-feature-arch-claude#2 byz-feature-arch-claude#10 byz-feature-nano-f-eli5-4days-regen-r3#0 byz-feature-arch-claude#12 byz-feature-arch-claude#13 byz-feature-tester-claude#1 byz-feature-nano-f-1395g-redis-port-race-pin#0 byz-feature-da-codex#1 byz-feature-da-codex#2 byz-feature-arch-claude#31 byz-feature-tester-claude#2 byz-feature-tester-claude#3 byz-feature-arch-claude#41; do bash .fable-team/bin/ft-seat-close.sh "$s" --reason "판정 2341 팀장 하나만 · 죽은 좌석" --verdict <번호> --seats .fable-team/seats-feature.json; done`
   → `CLOSED-DEAD` 13줄 · `_da`(#2)·`_tester`(#3) 칸 "" + «교대 0 · planner 1줄» 2건 → planner 에 1줄(후임 지정) · `_arch` 는 지금 #42(살아 있음 — 손대지 않음)
   · 확인: `ls ~/.claude/state/seat-resume/ | wc -l` 전후 — 기존 파일은 그대로(바이트 불변) · 기록 없던 좌석은 대화 기록에서 새로 생길 수 있음(record=new · 나노 실측 4/5 생성 0.1~0.2초 · 생성본이 `zombie-clean.sh resume --dry-run` rc0)
5. 별도 고침 단위(이 카드 밖 · base 7e4fc49e 에서도 같은 실패): `test_seat_retire.sh` FAIL 5(①② stall dry-run 빈 출력 3 · ⑧ test_ft_tick_master_seat rc44 · test_role_spawn_name rc1) · `test_boot_report_gate.sh` FAILED 6 · `test_mbox_guard.sh` FAILED 24

press 필요: 없음(하네스 도구 · 오디오 경로 0)
