# 인덱스: C19 좌석 없는 팀 Issue → planner 「좌석 필요」 값 → 좌석 개설 요청 사슬 (dry-run)
<!-- ledger: design/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: 표 B · 원문 7(좌석 없는 cfo 46건이 0 으로 못 가는 병목). 핵심 한 줄: 일할 손이 없는 팀의 Issue 를 매니저가 planner 에 한 통으로 올려 harness-ops 가 좌석을 열게 한다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
오빠 값(Q2): 맡을 팀 오케 세션이 0 인 Issue 는 매니저가 planner 에 「좌석 필요 · Issue # 목록」 값 1통을 보내고, 집행은 harness-ops 가 좌석을 열어 맡긴다(소유 1 유지). 이 카드는 그 사슬의 «문구 생성과 목록 산출»을 만든다. 실제 좌석 개설은 하지 않는다(승인된 사람 또는 ops 가 수동 실행). 정본: `design/harness/issue-improvement/SPEC-github-issue-driven-20261006.md` §6 6-3 · §7 Q2 · §8 C19 · 오빠 값 원장은 VALUES-pieces 문서(읽기 전용).

## 구현 범위 (이 셋만 — 닫힌 목록)
1. `scripts/fable-team-bin/ft-seat-request.sh [--from-json <파일>]` — 읽기 전용: 열린 Issue 를 `team:` 라벨로 묶고 `seats-*.json`·tmux 세션에서 팀 오케 좌석 유무를 대조해 «좌석 없는 팀 · Issue 번호 목록 · 건수»를 표로 출력 + planner 로 보낼 「좌석 필요」 메시지 본문(3~5줄)을 출력만(발신 0).
2. `tests/harness/test_seat_request.sh` + `tests/fixtures/seat_request/` — 좌석 있음/없음 팀 혼합 JSON 으로 분류 검증 · 실제 열린 Issue 로 1회 실행한 결과(현재 좌석 없는 팀과 건수)를 보고서에 첨부.
3. 회귀: `bash -n` · 시험 PASS 출력 첨부. 기존 도구 예: `scripts/fable-team-bin/ft-nano-close.sh`. 커밋은 자기 브랜치, **push 금지**. 금지: mbox 실제 발신 · 좌석 spawn · gh 쓰기.

## 완료 조건 (닫힘 판정 기준 — master+DA 테스트 소관)
- test_seat_request.sh 가 좌석 있음/없음 혼합 fixture 에서 좌석 없는 팀만 골라낸다(출력 첨부).
- 실제 열린 Issue 실행 결과에 cfo 46건 같은 현황이 표로 나오고 발신·spawn 은 0 이다.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>` — ops 가 수락 판정문을 남긴다.

## 상태
- base_sha: 05e876bbc5a3cd2c803b7bae302365683176ef80 (spawn 2026-10-06)
- 2026-10-06 — 대기/ 생성 (ft-harness-ops#4).
- 2026-10-06 00:20 — 대기→진행 · 좌석 ft-harness-temp-c19-seat-request#0
- 정본 영향 없음: 하네스 스크립트·시험만 추가 — docs/architect 제품 정본 변경 없음
- 세트: 4be185dfbec59ed4d181d1acb396b94eea6e1476 · 시험: bash tests/harness/test_seat_request.sh rc=0 · 이슈: 0
- 2026-10-06 00:27 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§18
