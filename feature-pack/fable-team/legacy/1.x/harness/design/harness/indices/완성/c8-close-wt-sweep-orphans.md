# 인덱스: C8 close wt= 3값 + sweep 이벤트 재시도 + 고아 카드 목록(dry-run)
<!-- ledger: design/teams/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: 원문 7(빈 석·노는 석·고아 카드가 동시 처리 폭을 갉아먹는다). 핵심 한 줄: 닫힌 나노의 워크트리와 고아 진행 카드가 정리되어야 슬롯이 실제로 비는다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
나노를 닫을 때 원장 행 `wt=` 값이 planned/removed/skipped 3값으로 구분되고, sweep 이 사건(close 직후·tick) 두 지점에서 재시도해야 워크트리가 쌓이지 않는다. 또 진행/ 카드 중 좌석 세션이 없는 «고아 카드»를 찾아 `대기/` 복귀 후보로 «목록만» 만든다(다른 팀 카드 이동은 이 카드에서 하지 않는다). 정본: `design/teams/harness/issue-improvement/MERGED-20261005.md` §4 행 C8 · `design/teams/harness/issue-improvement/SPEC-roles-mission-flow-20261005.md` P3-6·P4-5. 브랜치 삭제 0(HIL).

## 구현 범위 (이 셋만 — 닫힌 목록)
1. `scripts/fable-team-bin/ft-nano-close.sh` 의 원장 행에 `wt=planned|removed|skipped` 3값을 구분해 기록(현행 값 확인 후 최소 수정) · `scripts/fable-team-bin/ft-wt-sweep.sh` 가 존재하면 호출 2지점(close 직후 · tick)에서 실패 시 다음 사건에 재시도(이미 구현돼 있으면 [사실: 있음] 보고) — 없으면 구현하지 말고 보고.
2. `scripts/fable-team-bin/ft-orphan-cards.sh`(신규 · 읽기 전용) — 각 팀 indices 진행/ 카드 ↔ tmux 세션 실재를 대조해 고아 카드 목록을 출력(v65·cfo 포함 · 이동 0 · 삭제 0 · 팀·카드·세션명 3열).
3. 회귀: `bash -n` · 고아 목록 실행 출력 첨부(실제 v65·cfo 고아 수 확인 — MERGED 는 v65 28·cfo 17 로 적음). 커밋은 자기 브랜치, **push 금지**. 금지: 다른 팀 카드 이동·워크트리 삭제·브랜치 삭제·tmux kill.

## 완료 조건 (닫힘 판정 기준 — master+DA 테스트 소관)
- ft-nano-close 원장 행에 wt= 3값이 구분되어 기록(시험 출력 첨부) 또는 [사실: 이미 구현됨].
- ft-orphan-cards.sh 가 팀별 고아 카드 목록을 읽기 전용으로 출력(이동 0 확인 — git status 변화 없음).
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>` — ops 가 수락 판정문을 남긴다.

## 상태
- base_sha: e22ae247ac9583a99ebb1cbaff4cdfdfde80c78d (spawn 2026-10-06)
- 2026-10-06 — 대기/ 생성 (ft-harness-ops#4).
- 2026-10-06 00:04 — 대기→진행 · 좌석 ft-harness-temp-c8-close-wt-sweep-orphans#0
- 정본 영향 없음: 하네스 스크립트·문서만 추가 — docs/architect 제품 정본 변경 없음
- 세트: 367ea794b58a26690f124b76da62ae00e79f7e4c · 시험: bash scripts/fable-team-bin/ft-orphan-cards.sh (읽기 전용 · 상태 변화 0) rc=0 · 이슈: 0
- 2026-10-06 00:10 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§7
