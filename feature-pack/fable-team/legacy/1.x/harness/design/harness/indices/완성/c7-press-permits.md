# 인덱스: C7 허가 2종 파일(세트 · 장치) + 획득/해제 스크립트 — 시험 병렬은 순차로
<!-- ledger: design/teams/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: 원문 7(시험 병렬 폭) · 표 A. 핵심 한 줄: 오디오 장치는 1개뿐이라, 서버 세트끼리는 병렬로 두되 소리를 내는 시험은 한 번에 하나만 들어가게 기계가 막아야 한다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
시험 허가를 두 종류로 나눈다: ①세트 허가(`held` + 멤버 목록 — 같은 세트에 참여하는 시험 수) ②장치 허가(오디오 장치 1개). 멤버 상한은 1로 시작하고 실측으로 올린다. 규칙: 멤버가 있는 동안 두 번째 가입 요청은 REJECT, 멤버가 남은 채 세트 해제도 REJECT, 한 바퀴는 가입→장치 허가→해제→탈퇴 순서. 실제 마이크·오디오 실행은 이 카드에서 하지 않는다(허가 파일 조작만). 정본: `design/teams/harness/issue-improvement/MERGED-20261005.md` §4 행 C7 · `design/teams/harness/issue-improvement/SPEC-test-input-parallel-20261005.md` 3-B · `design/teams/harness/issue-improvement/SPEC-roles-mission-flow-20261005.md` P2-3.

## 구현 범위 (이 셋만 — 닫힌 목록)
1. `scripts/fable-team-bin/ft-press-permit.sh set-acquire|set-release|join|leave|device-acquire|device-release|status` — 허가 파일은 `FT_PERMIT_DIR`(기본 `.fable-team/state/permits/`, 시험은 mktemp)에 JSON 원자 갱신(임시파일 후 mv) · 멤버 상한 `FT_PERMIT_MAX_MEMBERS` 기본 1 · 위반은 exit 1 + 사유.
2. 순차 시나리오 시험 `tests/harness/test_press_permit.sh` — ①mic 멤버 가입→장치 획득→해제→탈퇴 1바퀴 ②이어서 api 멤버 1바퀴 ③멤버가 있는 동안 2번째 가입 REJECT ④멤버가 남은 채 세트 해제 REJECT ⑤장치 허가 중 두 번째 장치 요청 REJECT.
3. 회귀: `bash -n` · 시험 ALL PASS 출력 첨부 · 기존 `ft-press-gate.sh` 는 수정하지 않는다. 기존 도구 예: `scripts/fable-team-bin/ft-nano-close.sh`. 커밋은 자기 브랜치, **push 금지**. 금지: 실제 press·마이크·오디오 실행 · 라이브 `.fable-team/state` 쓰기 · 기존 gate 스크립트 수정.

## 완료 조건 (닫힘 판정 기준 — master+DA 테스트 소관)
- test_press_permit.sh 5 시나리오 PASS(출력 첨부).
- 시험이 mktemp 디렉터리만 쓰고 라이브 상태 디렉터리를 만들거나 바꾸지 않았다(전후 비교).
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>` — ops 가 수락 판정문을 남긴다.

## 상태
- base_sha: 5fbe72746463c286269751d1ed87a75526b051fd (spawn 2026-10-06)
- 2026-10-06 — 대기/ 생성 (ft-harness-ops#4).
- 2026-10-06 00:17 — 대기→진행 · 좌석 ft-harness-temp-c7-press-permits#0
- 정본 영향 없음: 하네스 스크립트·시험만 추가 — docs/architect 제품 정본 변경 없음
- 세트: 8698d482a788f9f0466e677bd5d3d20abcc75be0 · 시험: bash tests/harness/test_press_permit.sh rc=0 · 이슈: 0
- 2026-10-06 00:23 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§13
