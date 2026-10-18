# 인덱스: C9-기계 LANDING-LEDGER 팀 파일 + ft-land.sh 기계 부분(후보 tree==검사 tree · S10 abort · dry-run)
<!-- ledger: design/teams/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「RELEASE-<ver>.md 1장 + 머신별」.
골의 축: 표 C(커밋 push·반영) · 원문 7(동시 랜딩 금지·루트 이동 통지). 핵심 한 줄: 여러 팀이 동시에 큰일을 올릴 때 main 랜딩 한 줄이 기계로 안전해야 한다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
랜딩 ④(대상 동기화 → 후보 커밋 1개)를 한 명령으로 묶는다: fetch → T=origin/main 기록 → `is-ancestor T feat` 이면 ff 후보, 아니면 `merge-tree --write-tree` → 기대 tree OID 기록 → `commit-tree` 후보 → 후보 tree == 검사 tree 검증 → 불일치·충돌이면 abort(S10 재발 차단). **push 는 하지 않는다(수락 부분은 C7·C10 뒤)**. `design/<팀>/LANDING-LEDGER.md` 행(카드·결과 sha·Issue·방식) 형식도 정한다. 정본: `design/teams/harness/issue-improvement/MERGED-20261005.md` §4 행 C9 · `design/teams/harness/issue-improvement/SPEC-planner-issue-queue-20261005.md` §3 L-1~L-5 · `design/teams/harness/issue-improvement/SPEC-full-flow-20261005.md` 단계 11.

## 구현 범위 (이 셋만 — 닫힌 목록)
1. `scripts/fable-team-bin/ft-land.sh`(신규) — 기본 `--dry-run`, 후보 sha·검사 tree OID·T 를 출력만 · `--push` 옵션은 만들지 않는다(이 카드에서 push 경로 0). `design/teams/harness/LANDING-LEDGER.md`(팀 공통 형식 예시 1행).
2. `tests/harness/test_ft_land.sh` — 임시 git 저장소 3개 시나리오: ①ff 가능 ②main 이 움직여 merge-tree 필요 ③S10 재현(feat 트리로 후보를 만들면 main 의 새 파일 삭제) → ③에서 abort 하는지 검증.
3. 회귀: `bash -n` · 시험 3 시나리오 PASS 출력 첨부 · 실제 리포의 브랜치 변경 0(시험은 mktemp 저장소만). 커밋은 자기 브랜치, **push 금지**. 기존 도구 예: `scripts/fable-team-bin/ft-nano-close.sh`. 금지: 실제 origin push · force · 브랜치 삭제.

## 완료 조건 (닫힘 판정 기준 — master+DA 테스트 소관)
- test_ft_land.sh 3 시나리오 PASS(S10 재현에서 abort 확인).
- ft-land.sh 에 push 경로가 없다(grep 으로 확인) · LANDING-LEDGER.md 형식 1행.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>` — ops 가 수락 판정문을 남긴다.

## 상태
- base_sha: e22ae247ac9583a99ebb1cbaff4cdfdfde80c78d (spawn 2026-10-06)
- 2026-10-06 — 대기/ 생성 (ft-harness-ops#4).
- 2026-10-06 00:04 — 대기→진행 · 좌석 ft-harness-temp-c9m-landing-ledger-machine#0
- 정본 영향 없음: 하네스 스크립트·문서만 추가 — docs/architect 제품 정본 변경 없음
- 세트: 1c65f85aa4488a39dfac1bd2a626e859946fd5cf · 시험: bash tests/harness/test_ft_land.sh rc=0 · 이슈: 0
- 2026-10-06 00:10 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§6
