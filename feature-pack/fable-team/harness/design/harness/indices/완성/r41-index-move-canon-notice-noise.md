# 인덱스: ft-index-move 완성 이동 — 「정본 영향 없음」 카드에는 [정본 갱신 요청] 쪽지를 보내지 않는다 (R41 · 소음 제거)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → R41(byz-harness-arch-claude#15 개선요청 #63686 · 실례 #63684·#63707·#63747·#63820(v461 완성) · master#16 작성 지시 #63807 · 우선 낮음)
- 상태: 대기
- 선행: 없음 — origin/main 최신에서 브랜치(대상 2파일은 PR #944 1140076188 로 main 이 앞선다 · ops/main-base 사본은 옛 바이트라 기준으로 쓰지 않는다)
- 시험 입력: 기존 `tests/harness/test_index_move_canon_landed.sh` 의 임시 git 리포 + 가짜 mbox 로그 — 실제 좌석·mbox·tmux·원격 쓰기 0
- 기준값: origin/main `scripts/fable-team-bin/ft-index-move.sh:98`~`:110` — 진행→완성 이동이면 카드 종류와 무관하게 명부 `_arch` 에 `[정본 갱신 요청] … · 정본 영향 없음: <이유>` 쪽지 1건 → arch 가 할 일 없는 쪽지를 매번 읽고 버림(실례 3건)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 6-b(개선요청 접수 — arch 좌석 R41) + C(반영). 핵심 한 줄: 정본 쪽지는 «정본을 고칠 일이 있을 때만» 간다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
카드를 진행→완성으로 옮기면 `ft-index-move.sh` 가 이동 «전»에 `ft-index-move-canon.sh` 로 카드의 정본 줄을 검사한다. 결과 `CANON_NOTE` 는 둘 중 하나다 — 「정본 갱신:」 카드면 `정본 docs/architect/<경로> §<절>[ · 정본 …]`, 「정본 영향 없음:」 카드면 `정본 영향 없음: <이유>`(origin/main `scripts/fable-team-bin/ft-index-move-canon.sh:4`·`:40`·`:44`). 이동 «뒤» 쪽지 단계(`ft-index-move.sh:98`~`:110`)는 이 구분 없이 `_arch` 에 쪽지를 보낸다. 그래서 하네스 도구 카드처럼 정본과 무관한 카드가 닫힐 때마다 arch 에게 «할 일 없음» 쪽지가 쌓인다. 고칠 곳은 쪽지 단계 한 곳이다: `CANON_NOTE` 가 `정본 영향 없음:` 으로 시작하면 쪽지 0 + `INFO 정본 쪽지 생략 — 정본 영향 없음 카드` 1줄. 정본 게이트(이동 전 검사)·슬랙 단계·원장 기록·`_arch` 없음 경로는 무변경.

## 사전검증
- 소환: 아니오
- 면제: 쪽지 단계 조건 1개 추가(게이트·이동·원장 무변경) · 발신 실패도 원래 게이트 아님(exit 0) · 되돌림 1커밋 — arch 서명 byz-harness-arch-claude#16

## 조사 근거
- origin/main `scripts/fable-team-bin/ft-index-move.sh:40`~`:41` `CANON_RES`·`CANON_NOTE` 계산 · `:98`~`:110` 쪽지 단계(`_arch` 조회 → `mbox send` → `NOTIFIED`/`WARN`/`INFO`).
- origin/main `ft-index-move-canon.sh` = 라이브 설치본 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/v6-realtime-live/.fable-team/bin/ft-index-move-canon.sh:44`(origin/main 과 cmp 같음) `print("OK\t정본 영향 없음: " + why)`.
- origin/main `test_index_move_canon_landed.sh` = `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-v461-inbox-row-via/tests/harness/test_index_move_canon_landed.sh:104`(origin/main 과 cmp 같음 · ops/main-base 에 없음) ~`:111` ⑧ — 지금 «정본 영향 없음» 카드(`card k8 없음`)로 NOTIFIED 를 기대한다 → 이 변경으로 ⑧ 의 카드를 바꿔야 한다.

## 구현 범위 (닫힌 목록 · 정본 `scripts/fable-team-bin/` + 키트 사본 `scripts/harness-install/fable-team/bin/` 같은 바이트)
1. `scripts/fable-team-bin/ft-index-move.sh` 쪽지 단계(`if [ "$DST" = 완성 ]` 블록 안 · `_arch` 조회 «전»): `case "${CANON_NOTE:-}" in 정본\ 영향\ 없음:*)` 이면 `echo "INFO 정본 쪽지 생략 — 정본 영향 없음 카드"` 후 쪽지 0. 나머지 분기(`_arch` 없음 INFO · 발신 실패 WARN · NOTIFIED) 문구·순서 무변경. 키트 사본 `scripts/harness-install/fable-team/bin/ft-index-move.sh` 같은 바이트.
2. `tests/harness/test_index_move_canon_landed.sh` ⑧: 카드를 «정본 갱신» 카드로 바꾸고(② 와 같은 squash 랜딩 + `--landed` + `정본 diff 확인:` 줄) NOTIFIED 기대 유지 · ⑧b(`_arch` 없음) 무변경 · ⑧c 추가 = `_arch` 있음 + «정본 영향 없음» 카드 → 가짜 mbox 로그 비어 있음 + `INFO 정본 쪽지 생략 — 정본 영향 없음 카드` + `완성/` 에 이동됨.
3. `scripts/fable-team-bin/ft-index-move-canon.sh` 무변경.

커밋은 자기 브랜치, **push 금지**. **금지**: 정본 게이트(이동 전 검사) 완화 · 슬랙 단계·원장 기록 변경 · 실제 mbox 발신.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_index_move_canon_landed.sh` rc=0(⑧·⑧b·⑧c 포함 전 항목 PASS) · `bash tests/harness/test_index_move_slack.sh` rc=0 · `bash tests/harness/test_kit_bin_sync.sh` rc=0 · 사본 cmp · bash -n.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_index_move_canon_landed.sh rc=0 · 이슈: 0`.
  - 나노 워크트리(origin/main 기준)에 이 카드가 없으면 RESULT 맨 끝 줄에 `카드 증거 줄: 세트: <40hex> · 시험: bash tests/harness/test_index_move_canon_landed.sh rc=0 · 이슈: 0` 을 복붙 가능한 그대로 쓴다 — master 가 카드 끝에 옮기고 `ft-nano-evidence-check.sh` 로 확인(master#16 #63821).
- 랜딩 뒤 master 집행(카드 밖): 라이브 FT_BIN cp 1파일(`ft-index-move.sh`) + cmp.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>` — 판정 절에 「대상 카드: r41-index-move-canon-notice-noise」 줄.

## 상태
- base_sha: ed2d07dcfb0c4bc87aa5f0c75f6e775613da2679 (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#16 · R41 · master #63807).
- 정본 영향 없음: 하네스 카드 이동 도구의 쪽지 조건과 시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 18:29 — 대기→진행 · 좌석 byz-harness-nano-r41-index-move-canon-notice-noise#0
세트: 66e26a1edda0e89be171ab291559e78e075185e7 · 시험: bash tests/harness/test_index_move_canon_landed.sh rc=0 · 이슈: 0
- 2026-10-08 18:41 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§72
