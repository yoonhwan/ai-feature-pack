# DA 요청 — v423b planner 보고 의무 훅 2종 구현 검토 (arch#18 · 2026-10-08 · 구현 DA 1회 · 10분 + 정정 10분)

## 골 원문 (3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
골의 축: A(모니터·오빠 요청 — planner 가 읽고 안 올리는 26%).

## 고정 대상 (bounded_da_review 계약)
- 커밋 `0c466f66caa824e1544c4af22a05db72e61a6cc6`(브랜치 `nano/v423b-report-hooks` · 새 파일 4 · 기존 파일 변경 0):
  `scripts/harness-install/fable-team/templates/hooks/report-coverage.sh`(Stop) · `scripts/harness-install/fable-team/templates/hooks/drain-before-interview.sh`(PreToolUse:AskUserQuestion) · `tests/harness/test_report_hooks.sh` · `tests/harness/fixtures/stub-ft-inbox.py`.
- 카드: `design/harness/indices/대기/v423b-report-hooks.md`(구현 범위 1 + 「전역/planner 훅 영향 점검 표」 5행) · 설계 `design/harness/DESIGN-news-tree-workqueue-viz-20261009.md:50-57`·`:143-146` · 사전 DA `design/harness/DA-news-board-20261009.md`(N2 잔여 = 이 구현 DA 에서 재확인).
- 지원 범위: planner 좌석 1개의 settings 에만 등록(전역 0) · Claude Code jsonl transcript · 인박스 = origin/main `scripts/fable-team-bin/ft-inbox.sh`(show·report) · `tools/comm-canonical/mbox.sh peek`(`pending=N …` 한 줄).
- 증거(arch 재현 · origin/main + 이 커밋): `test_report_hooks.sh` rc=0(16 PASS) · 실제 ft-inbox 로 돌리면 실패 주입 3건만 FAIL(스텁 전용 · 나머지 13 PASS) · `test_kit_bin_sync.sh` rc=0 · bash -n 0 · 755. 실데이터: planner 인박스 ①~④ 미닫힘 **119** seq(①5 · ②73 · ③30 · ④11 · 23:2x) · planner transcript 2.0MB 전체 파싱 0.06 s.
- 후속 소유: 수정 = 같은 나노 반송 · 설치·등록·첫 2일 관찰 = master.

## 질문 (모두 «영구 차단 0 · 의무 소실 0» 하나의 수락 표로 · 반례는 코드 줄 + 재현 입력으로)
- **Q1 영구 차단·루프**: 두 훅이 같은 사용자 턴에 2회 이상 block/deny 하거나, 오류·조회 실패·stop_hook_active·session_id 없음·transcript 없음에서 사람 입력을 막는 경로가 있는가? (`report-coverage.sh` 의 `log()` 는 `sys.exit(0)` — 예외 뒤 `left` 미정의 경로 포함 확인)
- **Q2 턴 키**: «마지막 사용자 레코드 uuid»(type=user ∧ text 블록 비어 있지 않음 ∧ isMeta/isSidechain 아님 ∧ 「Stop hook feedback」 접두 아님)가 ①같은 사용자 턴 안에서 바뀌어 block 이 반복되거나 ②다른 사용자 턴인데 안 바뀌어 다음 턴 의무가 빠지는 실제 레코드 꼴(도구 결과 · 시스템 리마인더 · 대기열 메시지 · 크론 프롬프트 · 훅 피드백)이 있는가? 「Stop hook feedback」 접두는 가정 — 틀렸을 때 피해가 stop_hook_active 로 막히는지.
- **Q3 보고 판정**: 최종 답변의 `#[0-9]{4,}`(인용 `>` 줄 제외) ∩ show 목록 → `ft-inbox report` — PR·Issue 번호 오인, 묶음 그룹 일부만 인용, `last_assistant_message` 와 transcript 최종 텍스트가 다를 때 reported 가 잘못 서는 경로.
- **Q4 drain**: `mbox.sh peek` 이 상태를 바꾸지 않는가(읽기 전용) · pending 이 다른 계보 쪽지만인 경우 · deny 사유 길이.
- 범위 밖(새 요구 금지): 119건 백로그 처리 방식 · 로그 파일 위치 통합 · 미상 분류.

## 판정문
`design/harness/DA-v423b-report-hooks-20261008.md` 에 r1 — Q 별 APPROVE/HOLD + 근거 줄 · 끝 줄 APPROVE 또는 HOLD.

## r2 (arch#19 · 2026-10-08 · bounded — Q3 + 시험 ①~⑤만 · 새 요구 0 · 10분 + 정정 10분)
- 고정 대상: 커밋 `8567db092392521683d3e2bc2de8c8fc0d5eb284`(r1 `0c466f66ca` 위 [fix] 1개 · 같은 브랜치 · 파일 4개 그대로) · 반송서 `.fable-team/state/drafts-r21/REJECT-v423b-report-hooks-r1.md`.
- 식별 규칙(arch 결정 · 반송서 §1): 쪽지 seq = `쪽지 #<seq>` 꼴만(「쪽지」 뒤 공백 0~1칸 · 숫자 4자리+ · `·`/`,` 로 이은 `#<seq>` 묶음 인정) · `PR #`·`Issue #`·`이슈 #`·접두 없는 `#숫자` = 보고 0 · 인용 `>` 줄 제외 유지.
- 증거(arch#19 재현 · origin/main b4ce4ab0a5 아카이브 + `git diff 44e45993f6 8567db0923` 적용): `test_report_hooks.sh` rc=0(24 PASS · 반송 시험 ①~⑦ 포함 · ⑦ 변이 대조 = 접두 조건 제거 시 「PR #70001」 보고) · `test_kit_bin_sync.sh` rc=0.
- **Q3r2**: 새 `cited()` 가 ①PR·Issue·이슈·맨 `#숫자` 를 보고하는 경로 ②`쪽지 #a·#b` 묶음에서 이어지지 않은 뒤쪽 `#숫자`(예: 「쪽지 #70001 · PR #70002」)를 묶음으로 삼키는 경로 ③묶음 G 일부만 인용 시 나머지가 reported 로 서는 경로 ④`last_assistant_message` 와 transcript 가 다를 때 transcript 쪽을 쓰는 경로 — 하나라도 있으면 코드 줄 + 재현 입력.
- 범위 밖(r1 그대로): Q1·Q2·Q4(r1 APPROVE) · 로그 위치(반송서 §2 는 시험 ⑥으로 확인) · 백로그 119건.
- 판정문: `design/harness/DA-v423b-report-hooks-20261008.md` 에 r2 절 · 끝 줄 APPROVE 또는 HOLD.
