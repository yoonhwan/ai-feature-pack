# RESULT — C2 명부 생성기 + 세션명 lint + test_bundle lint (nano ft-harness-temp-c2-seat-live-name-lint#0 · 2026-10-06)

산출: `scripts/fable-team-bin/ft-seat-live.sh` · `ft-name-lint.sh` · `ft-test-bundle-lint.sh` · 시험 `tests/harness/test_name_lint.sh`(통과 3·REJECT 3 + 경계) · `tests/harness/test_seat_live.sh`(가짜 tmux·임시 명부).
금지 준수: tmux 는 `list-*` 만 · 기존 `seats-*.json` 수정 0(실행 전후 md5 동일) · `ft-role-spawn`/`ft-nano-spawn` 수정 0.

## 시험
`bash -n` 5개 OK · `test_name_lint.sh` fail=0 · `test_seat_live.sh` fail=0.

## 실제 세션 전부를 name-lint 에 넣은 결과 (tmux ls 28 · 2026-10-06)
| 결과 | 수 | 사유 |
|---|---|---|
| PASS | 9 | 신 문법 `byz-…`·`<프로젝트>-<팀>-<역할>-…` |
| REJECT | 19 | 역할 좌석 에이전트 꼬리 없음 5 · 역할 `temp` 5 · 허용 문자(대문자·`_`) 3 · 역할 `ops` 3 · `#N` 없음 1(`tmm`) · 역할 `helm` 1 · nano slug 없음 1 |
구 문법은 이행 기간 허용 목록(SPEC §2-D)이라 REJECT 가 정상 — lint 는 «신규 이름» 검사용이다.

## ft-seat-live.sh 실측 (같은 시각, 산출은 스크래치로 `--out`)
`LIVE rows=24 members=24 tmux_total=28 excluded=4` — 행 수 == 접두 세션 수. 제외 4 = `KakaoBot#14` `KakaoBot#17` `ft-airag-helm-claude#5` `tmm`(명부·접두 없는 동거 세션). 회원 판정 = ①명부 행 베이스 일치 ②명부 구 문법 행의 팀 접두(`ft-<팀>-`) ③P6 통과. 처음 ①③만 썼을 때 `ft-harness-arch#2~4`·`da#1`·`nano#1`(harness 명부에 행 없음)이 빠져 회원 19 였다 — ②를 넣어 24.

## test_bundle lint — 실제 명부 6개
`seats-{cfo,harness,issues,kk,planner}.json` · `seats.json` 전부 `REJECT: test_bundle 선언 칸 없음`. 선언 칸 추가(팀 개설 ③)는 이 카드 범위 밖.

## 열린 점 (이 카드 소관 아님)
- 같은 `card` 로 두 번째 open REJECT(SPEC P7 멱등)는 test_bundle 가 파일당 1개라 이 lint 로 검사할 대상이 없다 — 팀 개설 스크립트 쪽 몫.
- seats.live.json 은 P1 표 중 Issue #·마지막 보고 ts·열린 질문 수를 아직 싣지 않는다(카드 구현 범위 밖). 산출 기본 위치 = `<FT_SEATS_DIR>/state/seats.live.json`.
- FE Next.js 이슈(에러 오버레이·console.error): 해당 없음 — 셸 스크립트·문서만 변경.
