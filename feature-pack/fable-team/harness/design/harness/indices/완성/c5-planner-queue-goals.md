# 인덱스: C5 planner 큐 절 + 팀 GOAL 2(cfo·ccu) + 「투입≠발주」
<!-- ledger: design/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: 표 A(요청 → Issue → 검토) · 원문 7(큐가 동시 처리의 공급 순서). 핵심 한 줄: v65·cfo 의 쌓인 Issue 를 순서 있게 공급하는 큐가 문서로 먼저 서야 한다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
planner BOARD 에 큐 절(7상태 접수/등록/대기/활성/보류/클리어 · 접수 번호 A-n · 예상 카드 수 · 행 8칸)을 추가하고, 큐가 읽어야 할 팀 골 정본(GOAL-cfo·GOAL-ccu)을 «원문 복붙»으로 만든다(팀 오케·기존 문서에서 골 원문을 찾아 그대로 복사 · 요약 금지 · 못 찾으면 [사실: 원문 없음] 로 보고하고 빈 파일 생성 금지). 「투입 ≠ 발주」 규칙(큐에 넣기=큐 쓰기, 발주=Issue 배분·좌석 지시)을 GUIDE 에 1줄. 정본: `design/harness/issue-improvement/MERGED-20261005.md` §4 행 C5 · `design/harness/issue-improvement/SPEC-planner-issue-queue-20261005.md` §1 · `design/planner/BOARD.md`.

## 구현 범위 (이 셋만 — 닫힌 목록)
1. `design/planner/BOARD.md` 에 「이슈 큐」 절 추가(기존 절 무변경) — 표 헤더 8칸 + 예시 행 1(실제 Issue 번호 1건) + 상태 7값 정의 + 활성 1 규칙.
2. `design/cfo/GOAL-cfo.md` · `design/ccu/GOAL-ccu.md`(경로가 다르면 팀 디렉터리 실재 확인 후 그 위치) — 원문 복붙 + 출처 줄. GUIDE 한 줄 — 위치는 카드 보고서에 적는다.
3. 회귀: markdown 표 열 수 검사 1회(`awk -F"|"`) · 기존 파일의 다른 절 diff 0(`git diff --stat` 첨부). 커밋은 자기 브랜치, **push 금지**. 금지: Issue 생성·라벨 변경 · 코드 파일 수정.

## 완료 조건 (닫힘 판정 기준 — master+DA 테스트 소관)
- BOARD.md 큐 절 표 열 수 일치 · 예시 행이 실제 열린 Issue 번호 1건을 가리킴(`gh issue view` 읽기 확인).
- GOAL-cfo.md·GOAL-ccu.md 가 원문 복붙이거나 [사실: 원문 없음] 보고서 — 요약본 0.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>` — ops 가 수락 판정문을 남긴다.

## 상태
- base_sha: 866f3c1f9b5c7fc0d472c5f27140a74d40359108 (spawn 2026-10-05)
- 2026-10-06 — 대기/ 생성 (ft-harness-ops#4).
- 2026-10-05 23:56 — 대기→진행 · 좌석 ft-harness-temp-c5-planner-queue-goals#0
- 정본 영향 없음: planner 문서와 팀 골 원문 복붙만 추가 — docs/architect 제품 정본 변경 없음
- 2026-10-05 23:59 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§2
- 세트: 1d290f18b8c0e89157db8bbf2e570db1a1e45747 · 시험: awk 열수 8/8/8 + cmp GOAL 원본 rc=0 · 이슈: 0
- 2026-10-06 00:02 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§2
