# r428 master 집행 순서 (나노 손 0 · push·PR·설치·실사건은 master)

카드: BYZ `design/harness/indices/진행/r428-stall-scan-reads-spawn-hold-file-before-spawn-nag.md`
브랜치: `nano/r428-stall-scan-reads-spawn-hold-file-be` (ai-feature-pack · base origin/main 7e4fc49e · 버전 1.1.16 — `manifest.json` · CHANGES 절 머리 반영됨)

1. push · PR → main. (main 이 그새 1.1.16 이상으로 올랐으면 r2 가지로 재적용 + 버전 한 칸 올림.)
2. 착지 뒤 설치 — 되돌림 먼저:
   `L="$(head -1 /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/LIVE_BIN)"; for f in ft_stall_scan.py ft_stall_detect.py; do cp "$L/$f" "$L/$f.bak-r428"; done`
   `bash feature-pack/fable-team/harness/install.sh --apply --project /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents`
3. 확인: 새 LIVE_BIN 에서 `cmp "$L/ft_stall_scan.py" feature-pack/fable-team/harness/kit/fable-team/bin/ft_stall_scan.py` · `ft_stall_detect.py` 같은 cmp → 둘 다 cmp0
   + `ft-live-install-check.sh --range <병합 전 main>..<착지 sha>` OK (BOOT 36).
4. `launchctl kickstart -k gui/$UID/com.byz.ft-stall-scan` 1회 → `tail -3 /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/state/stall-scan.log`.
5. 실사건 1회(카드 `- 실사건:` 줄로):
   - 정지 파일이 걸린 동안(`ft-spawn-hold.sh status` → `REJECT hold <번호> …`) `stall-scan.log` 에 `act=c … hold=<번호>` 1행 · 그 시간대 `[stall a]` 쪽지 0.
   - 또는 정지 레디 팀(명부 `_master` 행 role=stop-ready · tmux 생존)이 있으면 planner 에 `[정지 파일 0] <팀> …` 1통 · 그 팀 `[stall a]` 0.
   ★운영 몫(카드 ⓒ · 코드 밖): 오빠 정지를 걸 땐 `ft-spawn-hold.sh set --verdict … --until … --release … --reason …` 로 정지 파일을 만든다(BOOT 38).★

press 필요: 없음(하네스 감시기 · 오디오 경로 0).
