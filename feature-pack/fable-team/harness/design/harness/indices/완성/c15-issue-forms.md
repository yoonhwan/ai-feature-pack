# 인덱스: C15 GitHub Issue 폼 6개 점검·보강 — 라이브 여부 · 확인 요청 체크 + 기획 정리본 칸
<!-- ledger: design/teams/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: 표 A(요청 → Issue). 핵심 한 줄: 오빠와 사내 멤버가 GitHub 에서 직접 올리는 Issue 가 매니저가 분류할 정보를 담아 들어오게 한다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
`.github/ISSUE_TEMPLATE/` 에 폼 6개가 이미 있다(사실). 새 폼은 만들지 않고 보강만 한다: `live_bug.yml` 에 「라이브(고객 영향) 여부」 체크와 「확인 요청(사내 멤버)」 체크 2개를 추가하고, `planner_task.yml` 에 정리본 경로 · 골좌표 · 닫는 증거 · 선행 칸이 있는지 점검해 없으면 추가한다. 자동 라벨은 **이미 있는 라벨만** 쓴다(없는 라벨 생성은 GitHub 쓰기라 이 카드에서 하지 않고 목록만 보고). `blank_issues_enabled` 는 현행 유지. 정본: `design/teams/harness/issue-improvement/SPEC-github-issue-driven-20261006.md` §2 · §8 C15 · `design/teams/harness/issue-improvement/MERGED-20261005.md` §4.

## 구현 범위 (이 셋만 — 닫힌 목록)
1. `.github/ISSUE_TEMPLATE/live_bug.yml` · `planner_task.yml` 보강(추가만 · 기존 필드 삭제 0) · `config.yml` 은 무변경 · 라벨은 `gh label list`(읽기)로 존재하는 것만 폼에 쓰고, 필요하지만 없는 라벨 이름 목록은 보고서에 적는다.
2. `tests/harness/test_issue_forms.sh` — python 으로 폼 YAML 6개가 파싱되는지 · 보강한 필수 칸 id 가 있는지 · 기존 필드 id 가 하나도 사라지지 않았는지 검사(변경 전 `git show HEAD:` 와 비교).
3. 회귀: YAML 파싱 6/6 OK 출력 첨부. 기존 도구 예: `scripts/fable-team-bin/ft-nano-close.sh`. 커밋은 자기 브랜치, **push 금지**. 금지: `gh label create` 등 gh 쓰기 · 새 폼 파일 생성 · `config.yml` 수정.

## 완료 조건 (닫힘 판정 기준 — master+DA 테스트 소관)
- test_issue_forms.sh PASS — 폼 6/6 파싱 OK · 기존 필드 id 삭제 0 · 보강 칸 id 존재(출력 첨부).
- 폼에 쓴 모든 라벨이 현재 GitHub 에 존재한다(`gh label list` 대조 출력 첨부).
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>` — ops 가 수락 판정문을 남긴다.

## 상태
- base_sha: 5fbe72746463c286269751d1ed87a75526b051fd (spawn 2026-10-06)
- 2026-10-06 — 대기/ 생성 (ft-harness-ops#4).
- 2026-10-06 00:17 — 대기→진행 · 좌석 ft-harness-temp-c15-issue-forms#0
- 정본 영향 없음: 하네스 폼·스크립트·문서만 추가 — docs/architect 제품 정본 변경 없음
- 세트: 3ea186afac2acf7ce0ebde4a119e506759082417 · 시험: bash tests/harness/test_issue_forms.sh rc=0 · 이슈: 0
- 2026-10-06 00:23 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§14
