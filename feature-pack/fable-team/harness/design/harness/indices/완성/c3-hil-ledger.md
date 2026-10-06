# 인덱스: C3 질문 원장 — ft-hil-ask.sh · ft-hil-answer.sh · tmm h 노출
<!-- ledger: design/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue」.
골의 축: 표 B(오케 개선요청 접수·사용자와 협의). 핵심 한 줄: 하위 좌석이 AskUserQuestion 을 못 쓰므로 사람 질문이 «보이는 한 곳»으로 모여야 한다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
하위 좌석(워커·나노·tester·architect)은 AskUserQuestion 을 띄우지 않고 mbox `[HIL]` 로 최상위 오케에 올리면 오케가 인터뷰를 띄워 값으로 내려보낸다(글로벌 CLAUDE.md 2026-09-25). 이 흐름을 질문 원장 1곳(파일)과 두 스크립트로 만든다: 질문 1건 = 원장 1행(질문·선택지·추천·좌석·seq·상태 open/answered/applied), 답은 좌석 seq 로 도달. 슬랙은 발행 전용·역방향 0(P10 확정) → tmm 이 화면. 정본: `design/harness/issue-improvement/MERGED-20261005.md` §4 행 C3 · `design/harness/issue-improvement/DESIGN-harness-composition-20261005.md` §3-6 1 · `design/harness/issue-improvement/SPEC-issue-manager-slack-tmm-20261005.md` §2~3.

## 구현 범위 (이 셋만 — 닫힌 목록)
1. `scripts/fable-team-bin/ft-hil-ask.sh <질문> --options "a|b|c" --recommend a` — 원장(`design/harness/HIL-LEDGER.md` 형식 · append 원자 · 행 8칸) 1행 추가 + mbox `[HIL]` 로 `seats-harness.json` 의 `_hil_route` 에 1통. `ft-hil-answer.sh <행#> <값>` — 원장 상태 answered → 좌석 seq 로 mbox 회신 → applied.
2. `tmm h` 가 원장의 open 행을 보이게 하는 최소 연결(tmm 이 외부 파일을 읽는 방법이 실재하는지 먼저 사실 확인 — 없으면 구현하지 말고 카드 보고서에 [사실: 불가] + 대안 1줄). 슬랙 코드 0.
3. 회귀: `bash -n` · 임시 원장(`HIL_LEDGER=$(mktemp)`)으로 ask→answer→applied 1바퀴 시험 스크립트 `tests/harness/test_hil_ledger.sh`. 기존 도구 예: `scripts/fable-team-bin/ft-mbox-bridge.sh`. 커밋은 자기 브랜치, **push 금지**. 금지: 실제 `_hil_route` 좌석에 시험 메시지 발송(시험은 `FT_SEND_DRY=1` 로) · 슬랙 · 라이브 mbox 파일 직접 수정.

## 완료 조건 (닫힘 판정 기준 — master+DA 테스트 소관)
- 임시 원장에서 ask→answer→applied 1바퀴 통과(출력 첨부) · open 행이 `tmm h` 또는 대안 경로에서 보이는 증거 또는 [사실: 불가] 보고.
- `bash -n` 전 파일 통과 · 라이브 mbox 무변경.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>` — ops 가 수락 판정문을 남긴다.

## 상태
- base_sha: 866f3c1f9b5c7fc0d472c5f27140a74d40359108 (spawn 2026-10-05)
- 2026-10-06 — 대기/ 생성 (ft-harness-ops#4).
- 2026-10-05 23:55 — 대기→진행 · 좌석 ft-harness-temp-c3-hil-ledger#0
- 정본 영향 없음: 하네스 질문 원장 스크립트만 추가 — docs/architect 제품 정본 변경 없음
- 2026-10-05 23:59 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§3
- 세트: 678b072da7fad1d30a21919beff64de9511a09d5 · 시험: bash tests/harness/test_hil_ledger.sh rc=0 · 이슈: 0
- 2026-10-06 00:02 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§3
