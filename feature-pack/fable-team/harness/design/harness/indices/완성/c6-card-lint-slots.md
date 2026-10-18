# 인덱스: C6 카드 머리줄 4줄 lint + 슬롯 정정(노는 석≠빈 석 · 예약석 +1)
<!-- ledger: design/teams/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: 원문 7(동시 처리 폭 — 빈 석을 같은 턴에 채운다). 핵심 한 줄: 노는 석을 빈 석으로 세는 오류가 상한 초과 spawn 을 부른다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
나노 슬롯 계산을 정정한다: 점유 = 살아 있는 석 전부(일하는 석 + 노는 석), 빈 석 = 상한 − 살아 있는 석, 후보 = 활성 Issue 카드만, 라이브 예약석 +1. 카드 머리줄 4줄(`Issue:`·`상태:`·`선행:`·`시험 입력:`)이 없는 카드는 spawn 후보에서 «제외만»(REJECT 아님 · 오빠 값). 정본: `design/teams/harness/issue-improvement/MERGED-20261005.md` §4 행 C6 · `design/teams/harness/issue-improvement/SPEC-roles-mission-flow-20261005.md` P3-1·P3-2·P3-5·P3-7 · `design/teams/harness/issue-improvement/SPEC-test-input-parallel-20261005.md` 3-A.

## 구현 범위 (이 셋만 — 닫힌 목록)
1. `scripts/fable-team-bin/ft-nano-slots.sh` 점유·빈 석 계산 정정(상한 기본 5 · 예약석 +1 · 후보 = 활성 Issue 카드) · 머리줄 4줄이 없는 카드는 후보 출력에서 제외하고 제외 사유를 1줄로 보고.
2. `scripts/fable-team-bin/ft-nano-spawn.sh` 의 lint 단계에 같은 머리줄 검사를 추가하되 REJECT 가 아니라 «후보 제외» 경고로(현행 동작 보존 · 기본 변경 최소).
3. 회귀: `bash -n` · `tests/harness/test_nano_slots.sh` — 가짜 seats/카드 디렉터리로 ①노는 석이 빈 석으로 안 세어짐 ②머리줄 없는 카드 제외 ③예약석 1 비어 있음. 커밋은 자기 브랜치, **push 금지**. 금지: 실제 나노 spawn·kill · 라이브 seats 파일 수정.

## 완료 조건 (닫힘 판정 기준 — master+DA 테스트 소관)
- test_nano_slots.sh 3 케이스 PASS(출력 첨부).
- 기존 시험 또는 `bash -n` 회귀 0 · 실제 seats 파일 무변경(git status).
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>` — ops 가 수락 판정문을 남긴다.

## 상태
- base_sha: e22ae247ac9583a99ebb1cbaff4cdfdfde80c78d (spawn 2026-10-06)
- 2026-10-06 — 대기/ 생성 (ft-harness-ops#4).
- 2026-10-06 00:05 — 대기→진행 · 좌석 ft-harness-temp-c6-card-lint-slots#0
- 정본 영향 없음: 하네스 스크립트·시험만 추가 — docs/architect 제품 정본 변경 없음
- 세트: 264eeab8b414ddef3792367f917b25ae0b07e2f8 · 시험: bash tests/harness/test_nano_slots.sh rc=0 · 이슈: 0
- 2026-10-06 00:13 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§8
