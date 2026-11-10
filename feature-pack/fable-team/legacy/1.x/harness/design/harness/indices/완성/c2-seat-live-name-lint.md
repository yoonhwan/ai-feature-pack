# 인덱스: C2 명부 생성기(seats.live.json) + test_bundle 선언 lint + 세션명 문법 lint
<!-- ledger: design/teams/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: 원문 5(머신별 독립 배분 — 좌석 명부가 실제 세션과 일치) · 원문 7. 핵심 한 줄: 살아 있는 좌석 목록과 이름 규칙이 기계로 맞아야 여러 팀이 부딪히지 않는다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
좌석 명부의 «입력» 파일(`seats-<팀>.json`)은 그대로 두고, 살아 있는 tmux 세션과 합친 «산출» `seats.live.json`을 만드는 읽기 전용 생성기와, 새 세션 이름이 P6 문법(`<프로젝트>-<팀>-<역할>-<에이전트>#N`)에 맞는지 검사하는 lint, 팀 개설 선언 칸 `test_bundle` 빈칸 REJECT 검사를 만든다. 정본: `design/teams/harness/issue-improvement/MERGED-20261005.md` §4 행 C2 · `design/teams/harness/issue-improvement/SPEC-session-naming-20261005.md` · `design/teams/harness/issue-improvement/SPEC-team-essentials-20261005.md`(test_bundle 칸).

## 구현 범위 (이 셋만 — 닫힌 목록)
1. `scripts/fable-team-bin/ft-seat-live.sh`(신규 · 읽기 전용) — `tmux ls` + `seats-*.json` → `seats.live.json` 산출(단일 쓰기 · 임시파일 후 mv) · live 행 수 == 접두 세션 수 검증.
2. `scripts/fable-team-bin/ft-name-lint.sh <세션명>`(신규) — P6 문법 통과/REJECT(역할 좌석은 에이전트 꼬리 필수) · `scripts/fable-team-bin/ft-test-bundle-lint.sh <seats-x.json>` — test_bundle 선언 빈칸이면 REJECT.
3. 회귀: `bash -n` · `tests/harness/test_name_lint.sh` 통과 3·REJECT 3 케이스 · 현재 실제 세션 이름 전부를 lint 에 넣은 결과 표(통과/REJECT 수) 첨부. 커밋은 자기 브랜치, **push 금지**. 기존 도구 예: `scripts/fable-team-bin/ft-nano-close.sh`. 금지: tmux 세션 변경 · 기존 seats-*.json 수정 · ft-role-spawn/ft-nano-spawn 수정(다음 카드).

## 완료 조건 (닫힘 판정 기준 — master+DA 테스트 소관)
- ft-name-lint 가 문법 통과 3·REJECT 3 케이스를 바르게 판정(시험 출력).
- ft-seat-live.sh 의 live 행 수와 접두 세션 수가 일치(출력 첨부) · 입력 파일 수정 0(git status).
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>` — ops 가 수락 판정문을 남긴다.

## 상태
- base_sha: e22ae247ac9583a99ebb1cbaff4cdfdfde80c78d (spawn 2026-10-06)
- 2026-10-06 — 대기/ 생성 (ft-harness-ops#4).
- 2026-10-06 00:04 — 대기→진행 · 좌석 ft-harness-temp-c2-seat-live-name-lint#0
- 정본 영향 없음: 하네스 스크립트·시험만 추가 — docs/architect 제품 정본 변경 없음
- 세트: 466d62474e75b40462e06ff33794e9967ce416b5 · 시험: bash tests/harness/test_name_lint.sh + test_seat_live.sh rc=0 · 이슈: 0
- 2026-10-06 00:13 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§9
