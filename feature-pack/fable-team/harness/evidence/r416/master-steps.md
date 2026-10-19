# r416 master 집행 순서 (나노 손 0 · push·PR·설치·실사건은 master)

카드: BYZ `design/harness/indices/진행/r416-nano-slots-roster-from-ref-not-cwd-teams-md.md`
브랜치: `nano/r416-nano-slots-roster-from-ref-not-cwd--r2` (ai-feature-pack · base origin/main 35bccbb6e7)

1. push · PR → main (r2 가지 = 팩 origin/main 35bccbb6e7 위 재적용 · 버전 1.1.15 — `manifest.json` · CHANGES 절 머리 반영됨).
2. 착지 뒤 설치: `bash feature-pack/fable-team/harness/install.sh --apply --project /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents`
   (되돌림 = 설치 전 `cp <LIVE_BIN>/ft-nano-slots.sh <LIVE_BIN>/ft-nano-slots.sh.bak-r416`)
3. 확인: `cmp "$(head -1 /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/LIVE_BIN)/ft-nano-slots.sh" feature-pack/fable-team/harness/kit/fable-team/bin/ft-nano-slots.sh` → cmp0
   + `ft-live-install-check.sh --range <병합 전 main>..<착지 sha>` OK (BOOT 36).
4. 실사건 1회: v6-realtime-live cwd 에서 다음 v65 나노 닫기 출력 꼬리에
   `ERROR v65 은 팀 명단(TEAMS.md)에 없다` · `ERROR v65 팀 폴더를 못 풀었다` · `WARN ft-nano-slots 실패` 3줄 0 + `SLOTS nano …` 줄 1 — v65 master 쪽지 1줄을 카드 `- 실사건:` 줄로.
   (공유 루트 shim 은 LIVE_BIN 을 따르므로 v6-live 사본 손질 0 · 그 루트의 옛 `design/TEAMS.md` 는 그대로 둔다.)

press 필요: 없음(하네스 셸 도구 · 오디오 경로 0).
