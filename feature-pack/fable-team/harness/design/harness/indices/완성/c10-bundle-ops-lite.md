# 인덱스: C10-라이트 시험 묶음 운영 — 결과 분류 기록 + test_bundle 상태 전이 + tester 발주 템플릿 (실측 제외)
<!-- ledger: design/teams/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: 원문 7(시험 병렬) · 표 A. 핵심 한 줄: 묶음 tester 의 결과가 architect 에게 가고 상태가 한 바퀴 도는 기계가 있어야 시험이 병렬로 닫힌다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
시험 묶음은 카드 1개당 묶음 1개이고 상태는 open→reported→classified→closed 로 간다(P7). 이 카드는 «기계 부분»만 만든다: ①`test_bundle.state` 를 규칙대로만 바꾸는 스크립트(허용되지 않은 전이는 거부) ②최종 게이트 보고의 결과 분류(PASS 수락 / FAIL·미측정 → reopen)를 기록하는 줄 ③tester 부팅 발주 템플릿(보고 수신 = architect). 같은 세트 N 실측(N=1→2→4)과 `api` 로컬 러너, 멤버 상한 승격은 **하지 않는다**(관측 프로필 승인 뒤 · 별도). 정본: `design/teams/harness/issue-improvement/MERGED-20261005.md` §4 행 C10 · `design/teams/harness/issue-improvement/SPEC-team-essentials-20261005.md` §1-C · `design/teams/harness/issue-improvement/SPEC-test-input-parallel-20261005.md`.

## 구현 범위 (이 셋만 — 닫힌 목록)
1. `scripts/fable-team-bin/ft-bundle-state.sh <seats-x.json> <카드#> open|reported|classified|closed` — 허용 전이(open→reported→classified→closed · FAIL/미측정이면 classified→open 재오픈 1회 경로)만 통과 · 그 외 exit 1 · JSON 원자 갱신(mktemp 후 mv) · 시험은 복사본만 만진다.
2. `design/teams/harness/TESTER-BRIEF-TEMPLATE.md` — tester 부팅 발주 템플릿(골 원문 3줄 자리 · 시험 프로필 press|alt · 보고 수신 = architect · 증거 등급 2값 E2E 통과/미측정 · 허가 획득 명령 순서는 `ft-press-permit.sh` 를 가리킴).
3. 회귀: `bash -n` · `tests/harness/test_bundle_state.sh` — 정상 1바퀴 · 금지 전이 3종 거부 · 재오픈 경로 · 원본 JSON 불변. 기존 도구 예: `scripts/fable-team-bin/ft-nano-close.sh`. 커밋은 자기 브랜치, **push 금지**. 금지: 실제 tester 좌석 spawn · 실측(N) · press · 원본 명부 수정.

## 완료 조건 (닫힘 판정 기준 — master+DA 테스트 소관)
- test_bundle_state.sh 가 정상 1바퀴·금지 전이 거부·재오픈 경로를 통과(출력 첨부).
- 원본 seats JSON 이 시험 전후 바이트 동일하다(md5 첨부).
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>` — ops 가 수락 판정문을 남긴다.

## 상태
- base_sha: 05e876bbc5a3cd2c803b7bae302365683176ef80 (spawn 2026-10-06)
- 2026-10-06 — 대기/ 생성 (ft-harness-ops#4).
- 2026-10-06 00:20 — 대기→진행 · 좌석 ft-harness-temp-c10-bundle-ops-lite#0
- 정본 영향 없음: 하네스 스크립트·시험만 추가 — docs/architect 제품 정본 변경 없음
- 세트: edd6fa134e373ecb771d358e9e3d00fb662a73c7 · 시험: bash tests/harness/test_bundle_state.sh rc=0 · 이슈: 0
- 2026-10-06 00:27 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§17
