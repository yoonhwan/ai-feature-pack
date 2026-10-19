# r448 master 집행 순서 (나노 산출 · 착지·설치·실사건은 master 손)

## 실측 정정 (나노 · 2026-10-19)
- 카드 §구현 범위 3 «spawn 3종: 세션 생성 직후 `tmux set-environment -t <세션> FT_SEAT <좌석>`» 는 **이미 뜬 셸·에이전트에 안 닿는다**(실측: set-environment 뒤 pane 셸 `X=none` · `new-session -e FT_SEAT=…` 은 `X=<이름>`). spawn 3종(ft-nano-spawn·ft-role-spawn·ft-successor-open)은 모두 `tmuxc open` → `create_tmux_session` 을 거치므로 **tmuxc 한 곳에 `-e "FT_SEAT=$name"` 1줄**로 바꿨다 → spawn 3종 변경 0 · 키트 9 파일 대신 «키트 7 + tmuxc 1».
- macOS 는 `/bin/sh`·`/bin/zsh`·`/bin/sleep` 같은 플랫폼 바이너리의 env 를 ps 로 숨긴다(brew bash·python·node 는 보임). 10-19 사건 guard.sh 는 `#!/bin/zsh` + 공유 루트 cwd → reap 의 env(②)·cwd(③)로는 안 잡힌다. 그 꼴은 `ft-bg-loop.sh` 래퍼(argv `--seat` = ②b) + 착지 린트로 막는다(시험 ⓓ).
- `stopped` 은 뿌리 수 — 루프가 kill 직전에 낳은 sleep 고아를 2회전이 더 잡으면 1 더 나온다(left=0 불변).

## 순서
1. 착지 1: 팩 `nano/r448-seat-close-reaps-background-loops-l`(r447 착지 뒤 · `ft-merge-land.sh` 는 r447 줄과 다른 자리 · 버전 = 착지 순서대로).
2. 설치(되돌림 = `.bak-r448`):
   - 하네스: `bash <하네스>/install.sh --apply` → LIVE_BIN 의 `ft-seat-reap.sh`·`ft-bg-loop.sh`·`ft-bg-loop-lint.sh`·`ft-seat-close.sh`·`ft-nano-close.sh`·`ft-seat-retire.sh`·`ft-merge-land.sh` 키트와 cmp 0 · `ft-live-install-check.sh --range <병합 전 main>..<착지 sha>` OK.
   - tmuxc: `cp ~/.tmuxc/versions/0.4.0/core/bin/tmuxc{,.bak-r448}` → 착지본 `feature-pack/tmuxc/core/bin/tmuxc` cp → cmp 0. 그 뒤 새로 여는 좌석부터 `FT_SEAT` 이 심긴다(이미 떠 있는 좌석은 ③ cwd·②b 래퍼로만 잡힘).
3. 실사건 1: 설치 뒤 새로 연 좌석 1개가 닫힐 때 닫기 출력 끝 `reap left=0 rc=0`(또는 stderr `reap <좌석> stopped=<n> left=0 rc=0`) 1줄 + 닫힌 뒤 `ps -axEww -o pid=,command= | grep -cE 'FT_SEAT=<그 좌석>( |$)'` = 0 → 카드 `- 실사건:` 줄.
4. 정본 2줄(arch 손 · 착지 뒤): tmuxc `COMM-GUIDE-BOOT.md` 15 «세션만 닫기» 절 + 전역 하드 룰 2 «나노 세션 kill» 줄 — 카드 §정본 그대로.

press 필요: 없음(프로세스·tmux 단위 시험으로 닫힘 · 오디오 경로 무관).
