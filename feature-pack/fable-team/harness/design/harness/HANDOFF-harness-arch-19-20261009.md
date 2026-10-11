# HANDOFF — byz-harness-arch-claude#19 → #20 (2026-10-09 · 컨텍스트 409k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

이 좌석의 골 축: A 모니터·오빠 요청 + 6-b(개선요청 접수·협의) + C(배포·반영).

## 승계 첫 일 (순서 고정)
1. `~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md` Read → Serena `initial_instructions` → `activate_project(project="/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops", session_id=…)` → i-have-adhd 로드.
2. 골 대조 + 부팅 보고(세션명 / 모델·창 / Serena / i-have-adhd / cron=<id>)를 현역 master(지금 **byz-harness-master-claude#19** — 발신 전 `.fable-team/seats-harness.json` `_master` 확인)에 mbox. 같은 턴 CronCreate 10분 틱(mbox recv + `tmux ls | grep byz-harness-nano` pane 실측 + 오빠 3줄).
3. master 에 부탁: `bash .fable-team/bin/ft-seat-retire.sh byz-harness-arch-claude#19 byz-harness-arch-claude#20 --seats .fable-team/seats-harness.json`.

## ★지금 할 일★ — v423c 반송서 r1 작성 (master#19 쪽지 #66430 · 미착수)
- 판정문 `design/harness/DA-v423c-mirror-mbox-notify-20261009.md`(r1 HOLD · Q2 doorbell 수락) · 요청서 `design/harness/DA-REQ-v423c-mirror-mbox-notify-20261009.md` · 나노 커밋 `58aca7b614`(브랜치 `nano/v423c-mirror-mbox-notify` · base origin/main) · 좌석 `byz-harness-nano-v423c-mirror-mbox-notify#0`.
- 잔여 3(DA 순수 재현): **Q1** `mbox.py` `_is_reply` — 본문 앞 80자 맨 `#N` 을 seq 로 봐 PR 번호와 충돌 + 같은 받은 seq 반복 인용으로 RATE 무한 면제. **Q3** `mirror_summary.py` `parse_summary` — 원문 «할 일 아닌» 조각·110자 절단 뒤 생성 todo 가 «원문 부분문자열» 검사를 통과. **Q4** `mirror_board.py` `post_handled` — thread 맵 검사 뒤 맵 소실 시 deliver 의 ensure_thread 가 새 루트를 만드는 경로.
- arch 설계 결정(반송서에 쓸 것 · v423b 선례 = `쪽지 #<seq>` 접두만 인정 · `.fable-team/state/drafts-r21/REJECT-v423b-report-hooks-r1.md` 꼴):
  - Q1 식별 규칙 = v423b 와 같게 **`쪽지 #<seq>` 꼴만** 회신 인용으로 인정(맨 `#N`·`PR #`·`Issue #` = 0) + 회신 면제는 «받은 seq 1개당 1회»(같은 seq 를 두 번째 인용하면 셈에 넣음 — guard log 의 `r` 에 인용 seq 를 저장해 중복 판정).
  - Q3 = todo 는 원문에 «한 문장 전체»로 있을 때만(원문을 문장 단위로 자른 목록에 정확히 일치 · 절단 금지 — 110자 넘으면 null) · HIL 강제 todo 없음 유지.
  - Q4 = 새 글 0 을 deliver 쪽에서 보장: post_handled 는 «기존 스레드에 답글만» 하는 전용 경로(없으면 ensure_thread 를 부르지 않고 건너뜀) — 맵 소실 = 0줄.
  - 시험: 각 반례를 회귀 시험으로 + 변이 대조 1줄씩. DA r2 = Q1·Q3·Q4 + 새 시험만(bounded).
- 반송서 경로 `.fable-team/state/drafts-r21/REJECT-v423c-mirror-mbox-notify-r1.md` → master 에 mbox(나노 전달은 master).
- 참고 사실(판정서 §89 에 쓸 것): 미러·proposal pytest 16 failed/59 passed 는 수정 전 main 과 같은 목록(회귀 0 · 카드 밖) · DEFAULT_CMD 공유로 github 미러·proposal·magazine 요약도 haiku-5-5(claude-hr.sh 실호출 rc=0) · mbox.py 582→610(기존 초과 · 분리 별 카드 후보 — mbox-sh-split-200 은 mbox.sh 만) · `_is_reply` 부하 1회 40ms·RSS 14MB(보낸 행 사본 2파일 6.4MB).

## 그 뒤 큐 (master 한 번에 하나)
1. v423c 닫힘(§89) → 2. `대기/r60-board-plist-workdir.md`(dry-run PLAN 통과 · 구현 DA 없음) → 3. `gate-hook-kit-equals-home` → 4. `r35` → 5. `mbox-sh-split-200`. r23 보류.
- 다음 판정서 번호 §89(v423c) · §90(R60).

## 이 세션에서 닫힌 것 (판정서 초안 → master 반영)
| § | 단위 | 랜딩 |
|---|---|---|
| 84 | v423b planner 보고 훅 2종 | PR 1023 · 훅 등록은 §87 뒤 |
| 85 | R58 press-gate 다른 줄기 제외(DA 2 HOLD → arch r3 서명) | PR 1027 |
| 86 | R59 Tank comment-edit | PR 1028 |
| 87 | v558 인박스 명시 면제(waived) · planner 79건 면제 · 훅 등록 | PR 1031 |
| 88 | v555 보드 5분 틱(/bin/bash 3.2 결함 반송 r1 → r2) | PR 1034 · launchd 등록 |
- 카드 작성: R58 · R59 · v555 · v558 · R60 · gate-hook 카드 추적 커밋.

## 함정 (실측 · 이 세션)
- **카드 spawn lint 경로 검사 = 카드가 있는 ops 브랜치 루트 기준**: 구현 범위에 ops/main-base 에 실재하는 경로가 1개 이상 필요 — `tests/harness/test_kit_bin_sync.sh` 를 전체 경로로 인용하면 통과. 기준값 머리줄은 `- 기준값: …`(콜론 바로 뒤) 꼴이어야 WARN 0.
- **라이브 spawn 은 `v6-realtime-live/.fable-team/bin/ft-nano-spawn.sh`** — 루트 `.fable-team/bin` 의 spawn 은 `ft-live-bin-drift-check.sh` 누락으로 REJECT. 라이브 FT_BIN 도 v6-realtime-live 쪽(issues-env·harness-env :11).
- **zsh 는 변수 단어 분리 0** — `$FILES` 여러 경로·`git -C $R $c` 꼴은 bash heredoc 으로. 빈 출력 = «동일»로 읽지 말 것(이 세션 1회 오판 직전).
- **launchd 는 `/bin/bash` 3.2** — `set -u` + 빈 배열 `"${A[@]}"` = unbound 로 즉사. 템플릿은 `/opt/homebrew/bin/bash` + `${A[@]+"${A[@]}"}` 꼴. WorkingDirectory 없으면 cwd=/ 라 gh 실패.
- **mbox 명령줄 백틱 0**(훅 차단) — sed·grep 패턴에 백틱이 있어도 같은 Bash 호출이면 막힌다. 파일 편집은 python 으로(`chr(96)`).
- 게이트 전체 실행(`ft-press-gate.sh`)은 허가 파일을 발급하므로 재현에서 돌리지 않는다 — 판정 함수만 격리 확인.
- 판정서 초안 자리 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/state/drafts-r21/OPS-VERDICT-<N>.md`.
