# r437 master 집행 순서 (나노 손 0 · push·PR·설치·실사건은 master)

카드: BYZ `design/harness/indices/진행/r437-role-spawn-team-flag-and-arch-live-reject-names-exit.md`
브랜치: `nano/r437-role-spawn-team-flag-and-arch-live-` (ai-feature-pack · base origin/main 7e4fc49e)

1. push · PR → main (버전 1.1.16 — `manifest.json` · CHANGES 절 머리 반영됨 · r433 은 이 착지 뒤 재기반 — `ft-successor-open.sh` 겹침).
2. 착지 뒤 설치: `bash feature-pack/fable-team/harness/install.sh --apply --project /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents`
   (되돌림 = 설치 전 LIVE_BIN 의 `ft-role-spawn.sh`·`ft-successor-open.sh`·`ft-teamset-check.sh`·`ft_teamset.py` 를 `.bak-r437` 로 cp)
3. 확인: 위 4파일 `cmp "$(head -1 /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/LIVE_BIN)/<f>" feature-pack/fable-team/harness/kit/fable-team/bin/<f>` → cmp0
   + `ft-live-install-check.sh --range <병합 전 main>..<착지 sha>` OK (BOOT 36).
4. 실사건 1회(둘 중 하나):
   - feature: `ft-teamset-check.sh feature` ERR 줄 끝 `→ 열기: ft-successor-open.sh 'byz-feature-arch-claude#41' <feature 워크트리> --name 'byz-feature-arch-claude#42' …` 를 그대로 실행(워크트리·본문 파일만 채움) → 후계 부팅 retire 로 `_arch=#42` → master `#30→#31` 교대 통과.
   - 또는 `_arch` 칸이 빈 «arch 상시» 팀에서 `ft-role-spawn.sh arch --team <팀>` → `SPAWNED byz-<팀>-arch-claude#N` → 그 팀 master 교대 통과.
   (feature 폴더엔 SEATBELT-README.md 가 아직 없어 `--team feature` 는 `REJECT feature SEATBELT-README.md 없음: …` 이 정답 — 범위 밖 · ft-team-upgrade 몫.)
   결과 1줄을 카드 `- 실사건:` 줄로.

press 필요: 없음(하네스 셸 도구 · 오디오 경로 0).
