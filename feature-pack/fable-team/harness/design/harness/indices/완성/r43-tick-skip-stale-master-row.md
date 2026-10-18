# 인덱스: 승계 끝난 옛 master 좌석에 stall-wake 가 가지 않게 — 틱은 `_master` 아닌 role=master 행을 건너뛰고, 승계 명부 정리는 도구 한 번으로 (R43)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → R43(master#17 접수 · 카드 요청 #63940 · 실례 cfo#59 439k · feature#3 · v65 `_master` 146 stale)
- 상태: 대기
- 선행: 없음 — origin/main 최신에서 브랜치(대상 `scripts/fable-team-bin/ft-tick.sh`·`scripts/fable-team-bin/ft-role-spawn.sh` 는 ops/main-base 와 origin/main 같은 바이트 · arch#16 cmp)
- 시험 입력: 픽스처 좌석표 JSON + `ft-tick.sh --once --dry-run`(기존 `tests/harness/test_ft_tick_master_seat.sh` 의 dry 꼴) + 임시 좌석표 파일 — 라이브 명부·tmux·stamp 쓰기 0
- 기준값: `.fable-team/seats-cfo.json.bak-succ61`(라이브 백업) — `_master` = byz-cfo-master-claude#60 인데 #59 행이 `role: master` · `_replaced_by` 없음 · #60 행은 아예 없음 → `active_seats()` 가 #59 를 정지 감시 대상으로 골라 승계 뒤에도 stall-wake 를 보냄. master 가 손 정정한 뒤 지금 라이브 9개 명부의 «`_master` 아닌 현역 role=master 행» = 0(arch#16 스캔).

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 6-b(메인 오케 개선요청 — master#17 R43) + C(반영 — 라이브 틱 설치). 핵심 한 줄: 승계 뒤 깨워야 할 master 는 명부 `_master` 하나뿐이고(R27), 옛 행 정리는 사람 손이 아니라 도구가 한다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
틱 데몬 `ft-tick.sh` 는 5분마다 명부(seats*.json)를 다시 읽어 `active_seats()` 가 고른 좌석 중 15분 넘게 jsonl 활동이 없는 좌석에 stall-wake 를 보낸다. `active_seats()` 는 `_replaced_by` 가 있거나 role 이 감시 목록(master·da·pm·nano·impl·checker·harness-design) 밖이면(=stop-ready 포함) 건너뛴다. 그런데 master 승계는 지금 도구 없이 손으로 한다(새 세션을 tmuxc 로 열고 명부의 `_master` 값만 바꿈) — 옛 행에 `_replaced_by`·`role: stop-ready` 가 안 붙고 새 행이 안 생기는 일이 반복됐다(cfo#59 · feature#3). R27 이 «master 정본 = `_master` 하나»로 정했으므로(뉴스 대상 `master_seat()` 는 이미 그렇게 고른다), 정지 감시도 같은 기준을 쓰면 옛 행이 남아도 깨우지 않는다. 그리고 손 정리를 없애려고, 승계 때 한 번 부르는 도구 `ft-seat-retire.sh <구> <후계>` 를 만든다 — 이미 있는 자동 후계 함수 `retarget_seat`(ft-tick-team.sh · 죽은 좌석 → 후계로 행·틱·`_master` 이전)와 같은 규칙을 «살아 있는 승계»에 쓰는 것이다. `ft-role-spawn.sh` 의 옛 행 닫기도 같은 규칙으로 맞춘다(지금은 `_replaced_by` 만 붙이고 role·tick·`_<역할>` 키는 그대로).

## 사전검증
- 소환: 아니오
- 면제: 틱 선택 조건 1개 추가(R27 의 `_master` 정본을 정지 감시에도 적용 · `_master` 키가 없거나 문자열이 아니면 지금 동작 그대로) + 명부 쓰기 도구는 쓰기 전 백업·후계 행이 은퇴 상태면 거부(retarget_seat 와 같은 규칙) · 되돌림 1커밋 — arch 서명 byz-harness-arch-claude#16

## 조사 근거
- `scripts/fable-team-bin/ft-tick.sh:137` `active_seats()` — `:146` 제외 조건(`_replaced_by` · role 목록) · `:154` dry-run 출력 `DRY kind=stall … seats=…`.
- `scripts/fable-team-bin/ft-tick.sh:190` `all_seats()`(idle 전이 알림 대상) — 같은 제외 조건 `:196`.
- `scripts/fable-team-bin/ft-tick.sh:71` `master_seat()` — `_master` 행이 있고 `_replaced_by` 없고 role=master 일 때만(R27 · 폴백 0).
- `scripts/fable-team-bin/ft-tick-team.sh:96` `retarget_seat()` — 백업 `.bak-retarget-<ts>` · 후계 행 은퇴면 rc 3 · 구 행 `tick=None`·`_replaced_by`·`role=stop-ready` · 후계 행 role·tick 상속·`_replaced_by` 제거·`_replaces` 추가 · `_master == 구` 면 `_master = 후계`.
- `scripts/fable-team-bin/ft-role-spawn.sh:87` 옛 행 고르기(같은 계보 · 같은 role) · `:95` `_replaced_by` 만 기록.
- 라이브 백업 `.fable-team/seats-cfo.json.bak-succ60`·`.bak-succ61` — #59 행 `role: master` · `_replaced_by: None` · `_master` 만 #59→#60.

## 구현 범위 (닫힌 목록 · 정본 `scripts/fable-team-bin/` + 키트 사본 `scripts/harness-install/fable-team/bin/` 같은 바이트)
1. `scripts/fable-team-bin/ft-tick.sh` `active_seats()`·`all_seats()`: 명부 최상위 `_master` 가 문자열이면, role=master 인데 키가 `_master` 와 다른 행을 건너뛴다(주석 1줄: R43 · R27 정본). `_master` 없음·문자열 아님 = 지금 동작.
2. 새 `scripts/fable-team-bin/ft-seat-retire.sh <구> <후계> [--seats <파일>]`(≤ 80줄 · python3 · 쓰기 전 `<파일>.bak-retire-<ts>`):
   - 명부 = `--seats` · 없으면 `FT_SEATS_JSON` · 없으면 `<루트>/.fable-team/seats*.json` 중 키 `<구>` 를 가진 파일 정확히 1개(0개·2개 이상 = rc 1 · 쓰기 0).
   - 후계 행이 `_replaced_by` 를 가짐 = rc 3 · 쓰기 0. 구 행이 이미 `_replaced_by == <후계>` = `NOOP` rc 0.
   - 구 행: `tick=None` · `_replaced_by=<후계>` · `role=stop-ready`(원래 role 은 `_retired_role` 에). 후계 행: 없으면 생성(`role`·`agent`·`model` = 구 행 값 · `tick` = 구 행 tick) · 있으면 role·tick(비었을 때만) 상속 · `_replaced_by` 제거 · `_replaces` 에 구 추가.
   - 최상위 `_<이름>` 문자열 키 중 값이 `<구>` 인 것 전부 → `<후계>`(`_master`·`_arch` 등 · `_hil_route` 포함).
   - 출력 1줄 `RETIRED <구> -> <후계> file=<파일> keys=[…]`.
3. `scripts/fable-team-bin/ft-role-spawn.sh` 옛 행 닫기(`:95` 부근): `_replaced_by` 에 더해 같은 규칙(tick=None · role=stop-ready · `_retired_role` · 값이 옛 좌석인 최상위 `_<이름>` 키 → 새 좌석). 새 행 생성·틱 상속·도달 확인 무변경.
4. 시험 `tests/harness/test_seat_retire.sh`(임시 파일만): ①픽스처 `_master=M#2` + `M#1` role=master·`_replaced_by` 없음 → `ft-tick.sh --once --dry-run` 의 `DRY kind=stall … seats=` 에 M#1 없음 · M#2 있음 ②`_master` 없는 픽스처 → M#1·M#2 둘 다 있음(무변경) ③retire 정상(행·키·백업·출력) ④후계 은퇴 → rc 3 · 파일 바이트 그대로 ⑤두 번째 호출 → NOOP ⑥명부 2개에 같은 키 → rc 1 · 쓰기 0 ⑦role-spawn 옛 행 닫기 규칙(spawn 의 python 블록만 — 기존 `tests/harness/test_role_spawn_name.sh` 꼴로 tmux 0) ⑧기존 `test_ft_tick_master_seat.sh`·`test_role_spawn_name.sh`·`test_kit_bin_sync.sh` PASS.

커밋은 자기 브랜치, **push 금지**. **금지**: 라이브 명부 수정 · tmux kill · 틱 데몬 재시작 · `master_seat()`·뉴스 경로 변경 · 다른 role(da·pm·nano…) 선택 규칙 변경.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_seat_retire.sh` rc=0(①~⑧) · 사본 cmp · bash -n · `ft-seat-retire.sh` ≤ 80줄.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_seat_retire.sh rc=0 · 이슈: 0`.
  - 나노 워크트리(origin/main 기준)에 이 카드가 없으면 RESULT 맨 끝 줄에 `카드 증거 줄: 세트: <40hex> · 시험: bash tests/harness/test_seat_retire.sh rc=0 · 이슈: 0` 을 복붙 가능한 그대로 쓴다 — master 가 카드 끝에 옮기고 `ft-nano-evidence-check.sh` 로 확인(master#16 #63821).
- 랜딩 뒤 master 집행(카드 밖): 라이브 FT_BIN cp 3파일(ft-tick.sh · ft-seat-retire.sh · ft-role-spawn.sh) + cmp · 틱 데몬은 매 루프 파일을 다시 읽지 않으므로(셸 스크립트 1회 로드) launchd 틱 재기동 필요 여부 확인 · 승계 절차(전역 CLAUDE.md 「증류 실행 절차」 ⑤ 뒤 · fable-team `main-team-governance.md`)에 「후계 부팅 보고 수신 뒤 `ft-seat-retire.sh <구> <후계>`」 1줄 — 저장소 밖 문서라 master/planner 판단.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>` — 판정 절에 「대상 카드: r43-tick-skip-stale-master-row」 줄.

## 상태
- base_sha: 1189db8256d9921feef67793f6b463c261acc1d9 (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#16 · R43 · master#17 #63940).
- 정본 영향 없음: 하네스 틱 좌석 선택·승계 명부 도구·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 19:09 — 대기→진행 · 좌석 byz-harness-nano-r43-tick-skip-stale-master-row#0
세트: dd002966ce9b70d88607c2d4f5168644c4aa61a3 · 시험: bash tests/harness/test_seat_retire.sh rc=0 · 이슈: 0
- 2026-10-08 19:46 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§74
