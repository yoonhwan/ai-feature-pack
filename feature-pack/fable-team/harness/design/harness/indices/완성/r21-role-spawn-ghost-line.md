# 인덱스: ft-role-spawn 후계 첫 발주(BODY)에 고스트 서제스천 1줄 — 전 역할 (R21)
<!-- ledger: design/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 6-b(오케 개선요청 접수·협의). 핵심 한 줄: 원장 R21 — planner#6 이 v65 master#145 pane 의 `❯` 뒤 자동완성 제안을 오빠 미제출 입력으로 읽고 인터뷰까지 띄움(오빠 「심각하네 그거 서제스천인데 … 착각하지 마라 메인 지침」 · planner #60104 → master#10 #60111). 안 = design/harness/PLAN-r21-ghost-suggestion-20261007.md.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
대상은 추적본 `scripts/fable-team-bin/ft-role-spawn.sh` + 키트 `scripts/harness-install/fable-team/bin/ft-role-spawn.sh`(지금 같은 바이트 · 둘 다 같이 고친다). 이 스크립트는 역할 좌석(master·arch·da·pm·tester·checker 등) 후계를 열고 첫 발주 문장 `BODY` 를 보낸다(57행). 59행 `case "$ROLE" in master|arch)` 는 master·arch 에만 크론 문장(R13)을 덧붙인다. 고스트 서제스천 규칙은 남의 pane 을 읽는 모든 역할에 필요하므로 «전 역할» BODY 끝에 붙인다. 시험 `tests/harness/test_role_spawn_name.sh` 는 `--dry-run` 이 찍는 `BODY ` 줄을 관측점으로 쓴다(60–70행 · R13 사례).

## 사전검증
- 소환: 아니오
- 면제: 문장 1개를 BODY 끝에 붙이는 변경이고 dry-run 관측점이 이미 있다. 되돌림 1커밋 revert. 최종 DA 는 완성 이동 때 1회. — arch 서명 byz-harness-arch-claude#7

## 조사 근거
- `scripts/fable-team-bin/ft-role-spawn.sh:57` BODY 정의 · 59행 master|arch 크론 덧붙임 · 62행 `--dry-run` 이 `BODY $BODY` 출력.
- `tests/harness/test_role_spawn_name.sh:60` R13 BODY 사례(62행 `body()` 도우미 · 65행 grep -qF) — 같은 틀로 사례 추가.

## 구현 범위 (이 둘만 — 닫힌 목록)
1. 두 사본(같은 바이트): 59행 `case` 줄 «다음»에 한 줄 추가 — 역할 무관하게 BODY 끝에 아래 문장을 붙인다.
   `BODY="$BODY ★남의 pane ❯ 뒤 글자 = 자동완성 제안 — 사용자 입력으로 착각 금지 · 그 줄로 보고·인터뷰·Enter 0 · 판단 근거는 jsonl·✻ done 줄뿐 (BOOT 17)★"`
   - 그 위에 주석 1줄: `# 고스트 서제스천(R21 · BOOT 17) — 남의 pane 을 읽는 전 역할에 붙인다.`
   - 다른 줄 변경 0 · master·arch 의 크론 문장은 그대로(고스트 문장이 그 뒤에 온다).
2. `tests/harness/test_role_spawn_name.sh`: 사례 추가 — master·arch·tester·da 각각의 dry-run BODY 에 `자동완성 제안` 과 `BOOT 17` 이 둘 다 있다 · master BODY 에서 크론 문장(`CronCreate 10분`)이 고스트 문장보다 앞에 있다. 기존 사례 무변화.

커밋은 자기 브랜치, **push 금지**. **금지**: `ft-nano-spawn.sh` 수정(나노는 남의 pane 을 읽지 않는다 — 범위 밖) · 라이브 FT_BIN 쓰기 · 홈 파일(~/.claude·~/.codex·~/.tmuxc) 쓰기.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_role_spawn_name.sh` rc=0 · `bash tests/harness/test_kit_bin_sync.sh` rc=0 · 두 사본 `bash -n` OK · `cmp` 두 사본 동일.
- RESULT 에 dry-run BODY 실제 출력 2줄(master·tester) 복붙.
- 카드 증거 줄 형식(필수 · 없으면 반송): `세트: <sha> · 시험: <명령> rc=0 · 이슈: 0`.
- 라이브 RT 반영(단독 cp — 라이브 ft-role-spawn 은 R13 줄도 없는 옛판이라 이 cp 로 같이 들어온다)은 master 집행 · 카드 범위 밖.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 35166fc56e2f3fec908a0c3e1b77e81bd9fb17b7 (spawn 2026-10-07)
- base: 최신 origin/main.
- 2026-10-07 — 대기/ 생성 (byz-harness-arch-claude#7 · 원장 R21 · master#10 #60111).
- 정본 영향 없음: 하네스 스크립트·시험만 — docs/architect 제품 정본 변경 없음
- 2026-10-07 21:22 — 대기→진행 · 좌석 byz-harness-nano-r21-role-spawn-ghost-line#0
- 2026-10-07 — 증거(나노 byz-harness-nano-r21-role-spawn-ghost-line#0 · 골 축 6-b 원장 R21 · arch#7 재현):
  - 변경: ft-role-spawn.sh 추적본+키트 각 2줄(주석 1 · 전 역할 BODY 끝 고스트 문장 1) · tests/harness/test_role_spawn_name.sh 9줄(전 역할 BODY 에 「자동완성 제안」·「BOOT 17」 · master 는 크론 문장이 앞).
  - 브랜치에는 PR 874 분(R15 H · TOP_MODELS 정합)이 base 로 같이 있다 — 이 카드의 diff 는 위 3파일뿐.
- 세트: 94e94b88faa1789c3c394738c6537299499ddf24 · 시험: bash tests/harness/test_role_spawn_name.sh rc=0 · 이슈: 0
- 추가 시험: bash tests/harness/test_kit_bin_sync.sh rc=0 (ALL PASS) · 두 사본 cmp 동일 · bash -n OK
- 정본 영향: 하네스 승계 스크립트(추적본·키트)·시험만 — docs/architect 제품 정본 변경 없음 · 라이브 RT ft-role-spawn 은 랜딩 뒤 단독 cp(R13 크론 줄도 같이 들어옴).
- 2026-10-07 21:25 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§36
