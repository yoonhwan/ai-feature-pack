# 인덱스: C18 브랜치 정리 후보 목록 생성기 (읽기 전용 · 변경 0)
<!-- ledger: design/teams/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: 표 A·원문 7(원격 브랜치 419 vs 마감 정본 5 — 생성이 정리보다 빠르다). 핵심 한 줄: 매니저가 브랜치를 건드리지 않고 «정리 후보 + 근거» 목록만 만들어 오빠 승인을 한 번에 받게 한다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
브랜치 정리(삭제)는 사람 승인 필수(HIL 유지 · 오빠 확정). 이 카드는 «목록 생성»만 한다: 원격·로컬 브랜치별로 ①랜딩 여부(main 에 내용이 있는가: is-ancestor 또는 cherry) ②마지막 커밋 시각 ③main 에 없는 커밋 수 ④tar 보관 유무를 표로 낸다. 정리 명령 문구는 «사람이 실행할 명령»으로 문서에만 적고 실행하지 않는다. 정본: `design/teams/harness/issue-improvement/SPEC-github-issue-driven-20261006.md` §1 1-7 · §8 C18 · `design/teams/harness/issue-improvement/SPEC-full-flow-20261005.md` §3 브랜치 행.

## 구현 범위 (이 셋만 — 닫힌 목록)
1. `scripts/fable-team-bin/ft-branch-candidates.sh [--remote]` — 읽기 전용(for-each-ref · cherry · merge-base --is-ancestor 만) → `design/issues/BRANCH-CANDIDATES.md` 생성(표: 브랜치 · 랜딩 여부 · 미랜딩 커밋 수 · 마지막 커밋 · 분류 SAFE/REVIEW/KEEP).
2. 분류 기준 3줄을 문서 머리에 명시(SAFE = main 에 내용 있음+미랜딩 0 · KEEP = 미랜딩 커밋 있음 또는 최근 활동 · REVIEW = 그 외) · 실제 리포 실행 결과(분모 수와 분류별 수)를 보고서에 첨부.
3. 회귀: `bash -n` · `tests/harness/test_branch_candidates.sh` — mktemp 저장소로 SAFE/KEEP/REVIEW 각 1 · 실제 리포 실행 전후 `git branch -a | wc -l` 불변. 기존 도구 예: `scripts/fable-team-bin/ft-nano-close.sh`. 커밋은 자기 브랜치, **push 금지**. 금지: 브랜치·워크트리·tmux 세션을 지우거나 바꾸는 모든 명령.

## 완료 조건 (닫힘 판정 기준 — master+DA 테스트 소관)
- test_branch_candidates.sh 가 SAFE/KEEP/REVIEW 분류를 바르게 낸다(출력 첨부).
- 실제 리포 실행 전후 브랜치 수가 같다(불변 증거).
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>` — ops 가 수락 판정문을 남긴다.

## 상태
- base_sha: b609602067d7d7baa560c39fbe5d1a6d1f2615aa (spawn 2026-10-06)
- 2026-10-06 — 대기/ 생성 (ft-harness-ops#4).
- 2026-10-06 00:13 — 대기→진행 · 좌석 ft-harness-temp-c18-branch-candidates#0
- 정본 영향 없음: 하네스 스크립트·시험·후보 목록만 추가 — docs/architect 제품 정본 변경 없음
- 세트: 8403cd27a7f7b14f54e25b413423cc2590a3e30a · 시험: bash tests/harness/test_branch_candidates.sh rc=0 · 이슈: 0
- 2026-10-06 00:35 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§19
