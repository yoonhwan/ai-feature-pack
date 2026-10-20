# r525 master 집행 순서 (나노 손 0 · push·PR·설치·실사건은 master)

카드: BYZ `design/harness/indices/진행/r525-stall-scan-off-roster-live-seats.md`
브랜치: `nano/r525-stall-scan-off-roster-live-seats` (ai-feature-pack · 팩 main cd358c0d(r523 · 1.1.81) 병합됨 · 버전 1.1.82 — `manifest.json` · CHANGES 절 머리 반영됨)

1. push · PR → main. (main 이 그새 1.1.82 이상으로 올랐으면 병합 + 버전 한 칸 올림.)
2. 착지 뒤 설치 — 되돌림 먼저:
   `L="$(head -1 /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/LIVE_BIN)"; for f in ft_stall_scan.py ft_stall_detect.py; do cp "$L/$f" "$L/$f.bak-r525"; done`
   `bash feature-pack/fable-team/harness/install.sh --apply --project /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents`
3. 확인: 새 LIVE_BIN 에서 `cmp "$L/ft_stall_scan.py" feature-pack/fable-team/harness/kit/fable-team/bin/ft_stall_scan.py` · `ft_stall_detect.py` 같은 cmp → 둘 다 cmp0
   + `ft-live-install-check.sh --range <병합 전 main>..<착지 sha>` OK (BOOT 36).
4. `launchctl kickstart -k gui/$UID/com.byz.ft-stall-scan` 1회 → `tail -3 /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/state/stall-scan.log`.
5. 실사건 1회(카드 `- 실사건:` 줄로):
   - `stall-scan.log` 요약 줄 `… e=<n> …` + `act=e seat=<좌석> notify=<planner…>` 1행 + planner 우편함 `[정지] <좌석> …` 쪽지 #N.
   - 나노 라이브 dry-run(2026-10-20 09:3x · 쓰기 0)에서 이미 1석 잡힘: `e byz-planner-desk-claude#23 768 교대 표시인데 라이브 · 열린 일 · ctx 14%` (`live-dry-run.txt`) — 설치 시점에 그 좌석이 아직 라이브면 그것이 실사건. 닫혔으면 다른 후보(`live-candidates.txt`) 또는 일부러 둔 명부 밖 쉬는 좌석 1석(30분).
   - 다음 실행(2분 뒤)에 같은 좌석 쪽지 0(서명 `state/stall-scan.e.json`) 확인.

press 필요: 없음(하네스 감시기 · 오디오 경로 0).
