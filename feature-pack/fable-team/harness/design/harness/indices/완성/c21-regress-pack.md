# 인덱스: C21 닫힌 Issue 회귀 팩 — issue_pack.jsonl + ft-regress-pack.sh add|select|run|retire
<!-- ledger: design/teams/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: 원문 7(동시 처리의 안전판 — 한 Issue 의 수정이 닫힌 Issue 를 깨지 않아야 한다) · 표 A. 핵심 한 줄: 고쳤던 것이 다시 깨지는 회귀를 랜딩 직전에 잡는다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
닫힌 Issue 의 재현 명령과 기대값을 한 모음(`tests/regression/issue_pack.jsonl` · 행 = issue, closed_sha, repro_cmd, expected, files[], mode(press|alt|unit), team, added_at, retired_at)으로 모으고, 후보 sha 가 바꾼 파일과 `files[]` 가 겹치는 행부터 고른다(select). press 행 상한 N=20(오빠 위임 · ops 값) — 넘으면 오래된 행에 retired_at 기록(삭제 아님). 정본: `design/teams/harness/issue-improvement/SPEC-github-issue-driven-20261006.md` §12-2 · §8 C21 · `design/teams/harness/issue-improvement/SPEC-planner-issue-queue-20261005.md` 게이트 절.

## 구현 범위 (이 셋만 — 닫힌 목록)
1. `scripts/fable-team-bin/ft-regress-pack.sh add|select|run|retire` — add = 행 1 추가(복붙 필드 검증 · 중복 issue 거부) · select <기준sha> <후보sha> = `git diff --name-only` 교집합 행 출력 · run = **unit/alt 모드 행만 실제 실행**(press 행은 목록만 출력 — 오디오 실행은 tester 묶음 소관) · retire = retired_at 기록.
2. `tests/regression/issue_pack.jsonl`(tracked · 시험용 예시 행 2 — 실제 닫힌 Issue 1건 + 합성 1건 표기) · 상한 검사 1줄(press 행 > 20 이면 경고 출력).
3. 회귀: `bash -n` · `tests/harness/test_regress_pack.sh` — mktemp 저장소로 add→select(겹침 있음/없음)→run(unit 행 PASS/FAIL)→retire 1바퀴. 기존 도구 예: `scripts/fable-team-bin/ft-nano-close.sh`. 커밋은 자기 브랜치, **push 금지**. 금지: 실제 press 실행 · gh 쓰기 · 기존 시험 변경.

## 완료 조건 (닫힘 판정 기준 — master+DA 테스트 소관)
- test_regress_pack.sh 가 add→select→run→retire 1바퀴와 상한 경고를 통과(출력 첨부).
- run 이 press 행을 실행하지 않고 목록만 낸다(시험으로 확인).
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>` — ops 가 수락 판정문을 남긴다.

## 상태
- base_sha: eafbbaa4563e2fb6c59bbfd8e0ed28cea02f4625 (spawn 2026-10-06)
- 2026-10-06 — 대기/ 생성 (ft-harness-ops#4).
- 2026-10-06 00:10 — 대기→진행 · 좌석 ft-harness-temp-c21-regress-pack#0
- 정본 영향 없음: 하네스 스크립트·시험만 추가 — docs/architect 제품 정본 변경 없음
- 세트: 28e9e402406d434535b61d96998813b229c1135c · 시험: bash tests/harness/test_regress_pack.sh rc=0 · 이슈: 0
- 2026-10-06 00:16 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§11
