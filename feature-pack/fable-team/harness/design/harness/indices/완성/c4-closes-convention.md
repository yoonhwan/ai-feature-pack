# 인덱스: C4 Issue 전이표 5 + Closes 규약 + 랜딩 PR 템플릿 + close 5항 검사 + reopen
<!-- ledger: design/teams/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: 표 A(이상 1건 = Issue 1건 · 검토). 핵심 한 줄: 많은 Issue 를 동시에 닫으려면 «랜딩 ↔ Issue» 연결과 close 검사가 기계로 걸려야 한다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
Issue 상태 라벨을 5개로 줄이는 전이표, 랜딩 PR 에 「Closes #N」 를 넣는 규약, Issue close 시 완료 5항(닫는 사건·PR·재현 PASS·정리·기록) 검사, 회귀 시 reopen(원 Issue 재오픈 + 깬 랜딩 sha 역링크)을 파일로 만든다. 실제 GitHub 라벨 삭제·변경은 외부 상태 변경이라 이 카드에서 하지 않는다(명령 스크립트 + dry-run 출력까지). 정본: `design/teams/harness/issue-improvement/MERGED-20261005.md` §4 행 C4 · `design/teams/harness/issue-improvement/DESIGN-harness-composition-20261005.md` §3-6 3 · `design/teams/harness/issue-improvement/SPEC-github-issue-driven-20261006.md`.

## 구현 범위 (이 셋만 — 닫힌 목록)
1. `.github/PULL_REQUEST_TEMPLATE.md`(있으면 최소 수정) — 「Closes #N」 줄 + 완료 5항 체크칸 · `design/teams/harness/ISSUE-TRANSITIONS.md` 전이표 5(현행 라벨 → 5개 매핑 · 소유 오케 확인칸).
2. `scripts/fable-team-bin/ft-issue-close-check.sh <Issue#>` — `gh issue view` 읽기만 · 완료 5항 코멘트 유무·Closes 연결 PR 유무를 판정(없으면 exit 1 사유 출력) · `ft-issue-reopen.sh <Issue#> <랜딩sha>` 는 `--apply` 없이는 명령만 출력(dry-run 기본).
3. 회귀: `bash -n` · `unset GH_TOKEN` 후 닫힌 Issue 1건·열린 Issue 1건으로 check 시험 출력 첨부(읽기 전용). 기존 도구 예: `scripts/fable-team-bin/ft-nano-close.sh`. 커밋은 자기 브랜치, **push 금지**. 금지: `gh issue edit/close/label delete` 실행 · 라벨 삭제.

## 완료 조건 (닫힘 판정 기준 — master+DA 테스트 소관)
- ft-issue-close-check.sh 가 닫힌 Issue(5항 있음/없음 각 1건)에서 exit 0/1 을 바르게 낸다(출력 첨부).
- PR 템플릿에 Closes 줄 + 5항 칸 · ISSUE-TRANSITIONS.md 에 현행 라벨 전부의 매핑 행 — 매핑 누락 라벨 0.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>` — ops 가 수락 판정문을 남긴다.

## 상태
- base_sha: 866f3c1f9b5c7fc0d472c5f27140a74d40359108 (spawn 2026-10-05)
- 2026-10-06 — 대기/ 생성 (ft-harness-ops#4).
- 2026-10-05 23:55 — 대기→진행 · 좌석 ft-harness-temp-c4-closes-convention#0
- 정본 영향 없음: PR 템플릿과 Issue 검사 스크립트만 추가 — docs/architect 제품 정본 변경 없음
- 2026-10-05 23:59 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§4
- 세트: 2b62f388d0c2a2c1fda4a3b1343fc7ade9e857ee · 시험: bash -n + ft-issue-close-check.sh fixture 5건 rc=0 · 이슈: 0
- 2026-10-06 00:02 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§4
