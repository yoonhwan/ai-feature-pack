# r429 master 집행 순서 (나노는 push 0)

나노 커밋: (mbox 에 sha) · 브랜치 `nano/r429-seat-retire-updates-hil-route-in-al` · 팩 워크트리 `/Users/yoonhwan/Project/ai-feature-pack/.worktrees/nano-r429-seat-retire-rosters`
★base = `nano/r427-seat-close-dead-seat-roster-row-and` tip a183c6c8 (r427 미착지 · 같은 `ft-seat-retire.sh` 를 만져 그 위에 쌓음 — 카드 «선행: r427»)★ · 버전 1.1.17(r427 = 1.1.16 다음)

1. r427 착지 먼저(PR · main). 그 뒤 이 브랜치 `git rebase origin/main`(r427 커밋 2개가 빠지고 r429 커밋만 남는다) → push + `gh pr create --base main`.
   r427 이 바뀌어 착지되면 충돌 자리는 `ft-seat-retire.sh` 의 bak/쓰기 꼬리(`ts = …` · `def dump` · `RETIRED` 줄)뿐.
2. 착지 뒤 설치: `bash <팩>/feature-pack/fable-team/harness/install.sh --apply --project /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents` → LIVE_BIN 1.1.17 의 `ft-seat-retire.sh` cmp0 (되돌림 = 이전 버전 LIVE_BIN 링크).
3. 실사건 = 다음 planner master 승계 때 `ft-seat-retire.sh <구> <후계>` 첫 줄 끝 `files=N routes=[…]` 복붙.
   ★N 기준값 정정: 2026-10-19 16:0x 실측 `_hil_route` 칸이 있는 명부 = 11파일(seats-planner 자신 포함 · seats-cfo·seats-kk 는 칸 없음) → 기대 `files=11`(카드의 «12» 아님)★.
   확인: `for f in .fable-team/seats*.json; do jq -r '._hil_route // empty' "$f"; done | sort | uniq -c` → 후계 이름 1종 · 손 갱신 0.
4. 정본 문장(arch 손 · 착지 뒤): `~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md` 2 «retire 칸» 에 «retire 는 전 명부 라우팅 칸(_hil_route…)까지 갱신 · 출력 files=N(r429)».
5. 별도 고침 단위(이 카드 밖 · base a183c6c8 사본에서도 바이트 같은 실패 — r427 master-steps 5 와 같은 묶음): `test_seat_retire.sh` FAIL 5 · `test_mbox_guard.sh` FAIL 25줄(그중 retire 경유 2건도 픽스처 «구 행 없음» 으로 실패 — retire 논리 커버는 `test_seat_retire_rosters.sh`). 원인 단서: 팩 리포 cwd 에서 `ft-tick.sh` 가 `ERROR 라이브 루트를 못 풂 — FT_ROOT 없음`.

press 필요: 없음(하네스 도구 · 오디오 경로 0)
