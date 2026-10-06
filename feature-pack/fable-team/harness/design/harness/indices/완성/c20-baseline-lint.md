# 인덱스: C20 기준값 코멘트 템플릿 + 카드 머리줄 기준값 lint + 5항 기준값 대비 칸
<!-- ledger: design/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: 원문 7(동시 처리의 안전판) · 표 A. 핵심 한 줄: 수정 전 값을 적어 두지 않으면 고친 뒤 나빠졌는지 알 수 없다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
Issue 를 시작할 때 그 Issue 가 건드리는 지표의 수정 전 값을 `baseline:` 코멘트(지표 이름 · 값 · 측정 세트 sha · 러너 경로 · 시각)로 기록하고, 카드 머리줄에 `기준값:` 1줄을 둔다. 지표가 없으면 「없음 → 대체 축」을 명시해야 하며 빈칸은 안 된다. 닫을 때는 같은 세트로 다시 재서 비교한다. 정본: `design/harness/issue-improvement/SPEC-github-issue-driven-20261006.md` §12-1 · §8 C20 · `design/harness/issue-improvement/MERGED-20261005.md` §4.

## 구현 범위 (이 셋만 — 닫힌 목록)
1. `design/harness/BASELINE-TEMPLATE.md` — `baseline:` 코멘트 템플릿(필드 5개 · v65 예시는 골 정본의 p90 다섯 숫자 이름만 · 값은 비워 둠) + 「없음 → 대체 축」 작성 예 1.
2. `scripts/fable-team-bin/ft-nano-spawn.sh` 카드 lint 에 `기준값:` 머리줄 검사 추가 — 없거나 빈칸이면 REJECT 가 아니라 «후보 제외» 경고(앞서 머리줄 4줄 검사와 같은 방식 · 기존 동작 보존) · `design/harness/ISSUE-TRANSITIONS.md` 의 5항 표에 「기준값 대비」 칸 1개 추가(기존 칸 무변경).
3. 회귀: `bash -n` · `tests/harness/test_baseline_lint.sh` — 기준값 있음/없음→대체 축/빈칸 3케이스(경고 출력 확인). 기존 도구 예: `scripts/fable-team-bin/ft-nano-close.sh`. 커밋은 자기 브랜치, **push 금지**. 금지: Issue 코멘트 작성 · gh 쓰기 · 실제 spawn.

## 완료 조건 (닫힘 판정 기준 — master+DA 테스트 소관)
- test_baseline_lint.sh 3 케이스 PASS(출력 첨부).
- ISSUE-TRANSITIONS.md 는 칸 추가만이고 기존 행의 삭제 줄이 0 이다(diff 첨부).
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>` — ops 가 수락 판정문을 남긴다.

## 상태
- base_sha: 5fbe72746463c286269751d1ed87a75526b051fd (spawn 2026-10-06)
- 2026-10-06 — 대기/ 생성 (ft-harness-ops#4).
- 2026-10-06 00:17 — 대기→진행 · 좌석 ft-harness-temp-c20-baseline-lint#0
- 정본 영향 없음: 하네스 폼·스크립트·문서만 추가 — docs/architect 제품 정본 변경 없음
- 세트: 7c01a1221f15e2486599e27c3ac752cf433021b7 · 시험: bash tests/harness/test_baseline_lint.sh rc=0 · 이슈: 0
- 2026-10-06 00:23 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§15
