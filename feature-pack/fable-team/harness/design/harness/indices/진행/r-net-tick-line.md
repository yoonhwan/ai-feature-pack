# 인덱스: 틱 한 줄 — ft-tick-line(라이브 turn 경계) + ft-seats-lint + 상태판 ⑤ «오빠가 정할 것» (N1 · 팀 운영 구조 근원 수정 · 판정 1070·1079 · arch#29)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → planner ORDER(판정 1069·1070 · 오빠 「그래」 = REVIEW §6 A~D 채택) · 설계 PLAN-harness-networking-20261011.md §2 D2·D8·D9 · §9
- 제안서: 없음 — 오빠 판정 1070 으로 착수 승인된 하네스 구조 수정(REVIEW-4days-networking §4·§6 · 판정 1079 3차 DA APPROVE #76290)
- 상태: 대기
- 선행: 없음 · 설계 = `git show f0d974ab20:design/teams/harness/PLAN-harness-networking-20261011.md`(r2 · DA APPROVE #76290 · ★나노 워크트리(origin/main)에는 이 파일이 없다 · 위 명령으로 읽는다★) · 순서 N1 → N3 → N2 → N4 → N5
- 시험 입력: 픽스처 명부 json · 가짜 좌석 jsonl(턴 끝 시각 조작) · 가짜 스냅샷 json · 가짜 tmux ls 출력(env `FT_TMUX_LS_CMD`) — 실 tmux·실 명부·루트 `.fable-team/` 쓰기 0 · gh 호출 0(캐시 파일 픽스처)
- 기준값(arch#29 실측 · 2026-10-11): harness master#28 세션 프롬프트 128 중 크론 틱 94(73%) · 16.5h 4.28MB → ctx 402k 증류. 틱 1회 ≈ 15~30KB. `ft-board.py stalled` 실재(v6-realtime-live/.fable-team/bin · launchd 300초 스냅샷 `.fable-team/state/board/<날짜>/*.json`) · `ft-seat-status.sh turn <좌석>` 실재(1줄 5열 STATE TURN_END_ISO DURATION_MS REPORTED SOURCE) · 명부 seats*.json 10개 · tmux 세션 85.

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
상위 제약(제품 골 · CLAUDE.md ACTIVE TRACK GOAL 바이트 일치): 목표는 빠른 유용 원문, 실시간 교정, N언어의 병렬·독립 발행, 소실·비의도 중복 없는 최종 말풍선이다. / LST ON 우선이며 LST OFF/전환과 기존 M0–M7·통합 조건도 남긴다. / 단순히 실패 사례를 많이 모았다는 이유로 실험을 닫지 않는다.
planner 원문 2(팀 배정·운영 · 베이스 팀과 위성팀 연결 관리 정리) / 닫는 증거(PLAN §8 복붙): 「오케 좌석 틱 1회당 jsonl 증가(15~30KB → ≤4KB)」 + 「숫자 3 … 같은 스크립트 · 측정 정의는 §9」.
하네스 GOAL 표 C / 닫는 증거(정본 복붙): 「RELEASE-<ver>.md 1장 + 머신별 「반영됨 <machine> <sha>」 행 전부」 — 라이브 설치는 랜딩 뒤 master 집행.
골의 축: 근원 ①(승계)·⑤(상태 거짓) — 채택안 A·D.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
오케 좌석이 400k 까지 차서 승계를 반복하는 주범은 일감이 아니라 10분 체크 틱이다 — 틱마다 세션 «안»에서 recv·pane 순회·보고문을 쓰니 일이 없어도 시간당 1MB 가 쌓인다(harness master#28 실측 73%). 이 카드는 틱을 «밖에서 재고 안에는 한 줄»로 바꾼다: `ft-tick-line.sh <좌석>` 이 내 팀 좌석(≤8석)을 `ft-seat-status.sh turn` 으로 라이브 측정해 정지 분을 틱 시점에 재계산하고(스냅샷 값으로 경계를 판정하지 않는다 — DA r1 F3 반례: 스냅샷 IDLE 150초·정지 행 0 → 45초 뒤 실제 195초 = 정지 3분 행 1), 큐 머리별 건수·명부 불일치 수·관찰 중 건수를 더해 ≤5줄·≤500자로 낸다. 첫 줄 = `TICK <좌석> @<ISO> src=turn-live(<n>)+snapshot@<ISO> …` · 좌석 jsonl 을 못 읽으면 `UNKNOWN(<이유>)`(0 이 아니다 · 「할 일 없음」 금지) · 5줄 초과는 `… 전체 <N>행 → <경로>`. 같이 만드는 `ft-seats-lint.sh` 는 tmux ls ↔ seats*.json 을 대조해 ⓐ세션 있는데 행 없음(`_closed` 팀의 `_kept=true` 는 제외) ⓑ`_master`/`_hil_route` 가 죽음·은퇴·closed(빈 `_master`+`_opened` 없음 30분 초과도) ⓒrole 활성인데 세션 없음 ⓓ계보당 세션 > 2 ⓔ중복 키 ⓕ파싱 실패(`UNKNOWN <파일>`) 를 `불일치 N (UNKNOWN M)` 로 낸다. `ft-board.py render` 에는 ⑤ 절 «오빠가 정할 것»(HIL-LEDGER open · 큐의 `[HIL]`·`[긴급]` 미처리 · MERGE-QUEUE 대기 · 제안 Issue 중 approved/rejected 없음(gh-cache) · `status:observing` 수)을 더하고, 캐시가 600초 넘거나 실패면 `(캐시 <시각> · 미확인)` 로 쓰고 「없음」으로 접지 않는다. 측정 스크립트 `ft-measure-net.sh succession|interview|planner-mail <from> <to>` 는 PLAN §9 의 정규식·분류 규칙을 코드로 고정한다(baseline 재현: raw 부팅 180 · 승계 154 · 계보 첫 부팅 26 · AskUserQuestion 460). 세부 규칙은 PLAN §2 D2·D8·D9 · §9 가 정본 — 카드와 PLAN 이 다르면 PLAN 이 이긴다.

## 사전검증
- 소환: 예 — DA byz-harness-da-codex#1 r0 HOLD #76217 · r1 HOLD #76265 · r2 APPROVE #76290(판정 1079 3차 허가 · F2·F3·F6 한정 · F1·F4·F5 는 r1 확인) — arch 서명 byz-harness-arch-claude#29
- 조사 근거: 라이브 `v6-realtime-live/.fable-team/bin/ft-board.py`·`ft_board_seat.py`(45~65행 분 계산 · 109~119행 완료 뒤 작업·완료 선언 미처리)·`ft_board_collect.py`·`ft_board_render.py`·`ft-seat-status.sh`(turn 출력 5열) · 추적본 `scripts/fable-team-bin/` 동일 파일 · 명부 `.fable-team/seats*.json` 꼴(`_master`·`_hil_route`·`_replaced_by`·`_kept`·`_closed`)
- 7초 룰 점검(판정 666): 외부 호출 0(tmux·jsonl·파일 읽기만) · gh 는 캐시 파일만 읽음(갱신 0) · 스냅샷 없음·파싱 실패 = UNKNOWN(폴백 실행 0)

## 구현 범위 (닫힌 목록 · 나노 · PLAN §6 N1 · 한 번에 하나)
관련 파일(기존 · origin/main 실재 · 나노 base): scripts/fable-team-bin/ft-seat-status.sh · scripts/fable-team-bin/ft-board.py · scripts/fable-team-bin/ft_board_render.py · scripts/fable-team-bin/ft_board_seat.py · tests/harness/test_board_seat_cell.sh
1. ①시험 빨강 먼저 — 새 `tests/harness/test_tick_line.sh` + 픽스처 `tests/fixtures/tick_line/`(명부 2종 · 좌석 jsonl 3종 · 스냅샷 2종 · tmux ls 2종 · gh-cache 2종 · 측정용 mailbox.log 발췌). PLAN D2 회귀 3(스냅샷 150초 IDLE→틱 195초 행 1 · 스냅샷 WORKING→틱 IDLE 240초 행 1 · 스냅샷 IDLE 500초→틱 WORKING 행 0) · UNKNOWN 경로 · 6행→5행+잘림 줄 · 전부 0 → ‘할 일 없음’ 1줄 · seats-lint ⓐ~ⓕ 각 1 · render ⑤ 신선/오래된 캐시 · measure 3 지표 baseline 재현. 이 커밋에서 새 시험 rc≠0(빨강).
2. ②새 `scripts/fable-team-bin/ft-tick-line.sh`(≤200줄 · 좌석 측정은 `ft-seat-status.sh turn` 호출 · 스냅샷은 최신 파일 1개 읽기 · 출력 규약 PLAN D2 그대로 · 좌석 jsonl 끝 읽기 ≤8회).
3. ③새 `scripts/fable-team-bin/ft-seats-lint.sh`(≤200줄 · env `FT_TMUX_LS_CMD`·`FT_SEATS_GLOB` 시험 훅 · 출력 `불일치 N (UNKNOWN M)` + 행).
4. ④`scripts/fable-team-bin/ft_board_render.py`(+필요 시 `ft_board_collect.py`) 에 ⑤ 절 — 기존 ⓪~④ 출력 무변경 · 파일 200줄 한도 넘으면 `ft_board_decide.py` 로 분리.
5. ⑤새 `scripts/fable-team-bin/ft-measure-net.sh`(PLAN §9 정규식 2개·분류 규칙을 그대로 코드로 · `succession|interview|planner-mail <from> <to>` · 출력 1줄 JSON).
6. ⑥미러: `scripts/harness-install/fable-team/bin/` 에 위 신규·변경 파일 전부 `cmp` 0.

커밋은 자기 브랜치(단계별 · [test]→[feature]→[docs] · 구조·행위 분리), **push 금지**. **금지**: 라이브 `.fable-team/bin`·루트 `.fable-team/` 쓰기 · launchd plist 변경 · BOOT/governance 글 변경(S5 는 arch 초안·master cp) · 실 tmux 세션 조작 · 위 목록 밖 파일 수정 0 · 기존 ft-board 출력 ⓪~④ 변경 0.

## 완료 조건 (닫힘 판정 기준)
- `bash tests/harness/test_tick_line.sh` rc=0 · 기존 `tests/harness/` ft-board 시험 전부 rc=0 · 새·바뀐 sh `bash -n` · py `python3 -m py_compile` · 미러 `cmp` 0 · 각 신규 sh ≤200줄.
- 카드 증거 줄(«세트:» 로 시작 · 접두 없음): 세트: <40hex> · 시험: bash tests/harness/test_tick_line.sh rc=0 · 이슈: 0
- 루트 지침: 완료 그 턴에 증거 줄 + arch#29 에 `[완료·휴식]` 1통(세트 sha 실재 확인 뒤).

## 상태
- base_sha: 32d0374ed0e8c600e3c7ae07537cc814be989b60 (spawn 2026-10-12)
- base: origin/main 32d0374ed0e8c600e3c7ae07537cc814be989b60 (arch#29 카드 작성 시점 · spawn 때 `--base origin/main` 으로 다시 고정 · base_sha 줄은 spawn 도구가 쓴다)
- 2026-10-12 — 대기/ 생성 (byz-harness-arch-claude#29 · N1 · 설계 PLAN r2 f0d974ab20 · DA APPROVE #76290 · 판정 1070·1079).
- 정본 영향: 하네스 키트 bin 신규 3(tick-line·seats-lint·measure-net)+ft_board_render 1 · 미러 · 홈 정본 0 · BOOT 16 글은 S5(arch 초안).
- 2026-10-12 00:13 — 대기→진행 · 좌석 byz-harness-nano-r-net-tick-line#0
