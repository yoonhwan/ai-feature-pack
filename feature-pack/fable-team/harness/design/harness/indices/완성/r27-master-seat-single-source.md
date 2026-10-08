# 인덱스: 틱의 master 뉴스 대상 = 좌석표 _master 하나 — role·tick 행 순서로 고르지 않는다 (R27)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 요청 원장 R27(design/harness/REQUEST-LEDGER.md · R21 곁가지 · master#14 #62016 접수)
- 상태: 대기 — 사전검증 DA 대기(아래 「사전검증」)
- 선행: 없음(안 = design/harness/PLAN-r27-master-seat-single-source-20261008.md)
- 시험 입력: 픽스처 좌석표(tests/harness/fixtures/ 아래 새 json 5종 + 가짜 tmux 스텁) + 각 틱의 --dry-run(전송 0 · tmux 무관 경로만)
- 기준값: R21 실측 — feature 틱 로그 「master sent to byz-feature-master-claude#1 (%851)」 12:41 까지(그때 _master = #2) · 좌석표 정정 뒤 12:48:16 「master sent to byz-feature-master-claude#2 (%887)」

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: C(업그레이드·커밋·push·반영). 핵심 한 줄: 승계 때 틱이 옛 master 에 뉴스를 보내면 팀 모니터가 끊긴다(R21 실측) — 정본을 _master 하나로.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
launchd 틱(`ft-tick.sh`)은 1분마다 좌석표(seats*.json)를 읽고, `tick` 이 `ft-master-tick` 인 현역 행(교체 표시 `_replaced_by` 없음)마다 master 뉴스를 보낸다. 승계 때 좌석표 맨 위 `_master` 만 새 좌석으로 바꾸고 옛 행을 그대로 두면, 틱은 옛 좌석에 뉴스를 계속 보낸다(R21: feature `_master`=#2 인데 #1 로 발송). 정지 감시·pm 보고 대상도 «role=master 인 첫 행»으로 고른다. 반대로 Issue 등록 도구(`ft-plan-handoff.sh`·`ft-issue-create-pair.sh`)와 팀 뉴스 문구는 `_master` 를 읽는다 — 정본이 둘이다. 틱 실행본도 두 판이다: ①키트 `scripts/fable-team-bin/ft-tick.sh`(334줄 · v65 틱이 사용 · idle_watch·wt-sweep·드리프트 경고) ②팀 틱 5개가 쓰는 `.fable-team/bin-{cfo,feature,kk,loom,ops}/ft-tick.sh`(233줄 · 5개 같은 바이트 md5 cb379b08966214ac4136a6402588fdc5 · CFO 계보 — 죽은 좌석 자동 승계 RETARGET·팀별 stamp 접두 FT_TICK_STAMP_PREFIX·뉴스 문구 env FT_TICK_MASTER_MSG/FT_TICK_PM_MSG). ②는 main 에 추적본이 없다(판정 ㊼ 사본은 cfo 브랜치 design/cfo/harness/ft-tick-cfo.sh 뿐). ★②를 ①로 덮으면 팀 뉴스 문구·RETARGET 이 사라진다 — 동기화 금지, 별도 파일로 들여온다★.

## 사전검증
- 소환: 예
- DA: design/harness/DA-r27-master-seat-20261008.md (byz-harness-da-codex#0 — 라이브 틱 5개(cfo·feature·loom·ops + kk 비활성)와 v65 틱의 좌석 선택이 바뀐다)

## 조사 근거
- `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/bin-feature/ft-tick.sh:55` `master_seat()` = role=="master" 첫 행 · `:171` stall 의 master 도 같은 방식 · `:205` pm report_to = master_seat.
- `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/bin-feature/ft-tick.sh:211` `ft-master-tick)` 분기 — tick 이 ft-master-tick 인 «모든» 현역 행에 fire(= R21 원인).
- `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/bin-feature/ft-tick.sh:79` `retarget_seat` — 죽은 좌석 행을 후계로 옮기지만 `_master` 는 안 고친다.
- `scripts/fable-team-bin/ft-tick.sh:69` 키트 `master_seat()` 같은 방식 · 141·199·258·281·298행 사용.
- `scripts/fable-team-bin/ft-plan-handoff.sh:49` · `scripts/fable-team-bin/ft-issue-create-pair.sh:37` — `_master` 를 jq 로 읽고 없으면 die(폴백 0) — 이 꼴을 따른다.
- 좌석표 스캔(12:5x): seats-harness `_master` #13(현역 #14 — master#14 정정 완료) · seats-issues `_master` #3 / role 첫 행 #1 · seats-planner `_master` #9 / role 첫 행 #4 · seats-kk·seats.json `_master` 없음(seats.json 은 tick 행 0 — v65 틱 로그 「no active seat with tick」).

## 구현 범위 (닫힌 목록 · 추적본 + 키트 사본 같은 바이트 · 커밋 2개 분리)
커밋 A `[structure]` — 동작 변경 0:
1. `scripts/fable-team-bin/ft-tick-team.sh` 신설 = `.fable-team/bin-feature/ft-tick.sh` 를 «바이트 그대로» 복사(md5 cb379b08966214ac4136a6402588fdc5) + `scripts/harness-install/fable-team/bin/ft-tick-team.sh` 같은 바이트. 다른 수정 0.

커밋 B `[feature]` — 두 틱(`ft-tick.sh`·`ft-tick-team.sh`, 각 두 사본) 같은 규칙:
2. `master_seat()` = 좌석표 `_master` 값. 그 행이 있고 · `_replaced_by` 없고 · role=="master" 일 때만 출력, 아니면 빈 값. (python 한 번에 읽는다 — 인자를 rows 문자열 대신 좌석표로.)
3. `pass()` 의 `ft-master-tick` 분기: 좌석 == master_seat 일 때만 fire+goal. 아니면 로그 `WARN master-tick row <좌석> ≠ _master <값> — skipped` 를 좌석당 1회(stamp `<좌석>.mtwarn`)만 남기고 건너뛴다.
4. ★뉴스 행 검사(DA HOLD-R27-A 교정)★ — «유효 master»(2번)와 «활성 뉴스 행»을 따로 본다. 현역 ft-master-tick 행이 하나 이상이면, 그 가운데 master_seat 와 같은 행이 «정확히 1개» 있어야 한다. 아니면(①master_seat 빈 값 ②master_seat 행의 tick 이 ft-master-tick 이 아님 — 새 행은 있는데 tick 이 null·다른 종류이고 옛 행만 뉴스 tick 을 가진 승계 중간 상태 포함) 로그 `ERROR master news row invalid (_master=<값> · news rows=<목록>) — master news 0` + 알림 파일 1줄(team = `${STAMP_PREFIX}DEAD-SEATS.alert` · 키트 = `/tmp/ft-tick-DEAD-SEATS.alert`). ERROR·알림은 «상태 서명»(_master 값 + 뉴스 행 목록)이 바뀔 때마다 1회 — 3번의 WARN stamp 와 별개라 WARN 이 조용해져도 ERROR 는 안 사라진다. role 첫 행으로 넘어가지 않는다(#0 규칙 · 폴백 0). 현역 ft-master-tick 행이 0 이면 지금처럼 조용히(명시적 비활성 — v65 seats.json·cfo·loom·ops 지금 이 상태).
5. 정지 감시·idle_watch·drift·pm report_to 의 master 도 master_seat 하나로(141·199·258·281·298 · 팀 171·205).
6. ★팀 판 자동 후계 조건(DA HOLD-R27-B 교정)★ — `heir_of <dead>` 는 같은 base 의 살아 있는 세션 중 «N > dead 의 N» 인 최대 N 만 돌려준다(낮거나 같은 N = 옛 incarnation · 후계 아님). `retarget_seat` 는 후계 행이 이미 있고 `_replaced_by` 가 붙어 있으면(은퇴한 좌석) 쓰지 않는다. 둘 중 하나라도 걸리면 명부 쓰기 0 + 기존 DEAD 알림 경로(로그 1회 + `${STAMP_PREFIX}DEAD-SEATS.alert` 1줄). 다른 base 로 이름이 바뀌는 승계(예: ft-harness-ops#3 → byz-harness-master-claude#N)는 자동으로 추측하지 않는다 — 승계 절차(새 `_master` + 새 행 + 옛 행 `_replaced_by`)가 정본. `_master` 는 «`_master` == dead» 이고 위 조건을 통과한 후계일 때만 같은 json.dump 안에서 바꾼다 — `_master` 가 이미 다른 좌석이면 그대로 둔다.
7. 파일 길이: 키트 334줄·팀 233줄 이미 200 초과(기존) — 이번 변경은 순증 30줄 이내. 넘으면 master_seat 판정만 `ft-tick-master-seat.py`(두 틱 공용 · 두 사본)로 뗀다.
8. 시험 `tests/harness/test_ft_tick_master_seat.sh` 신설: 픽스처 5종(+ 팀 판 후계 5경우)을 FT_TICK_SEATS 로 두 틱 각각 `--dry-run`(키트는 FT_TICK_IDLE_ENABLED=0 FT_TICK_WT_SWEEP=0 FT_TICK_DRIFT=0 · STATE_DIR 은 scratch) —
   - 정상(_master=#2 · #1 은 stop-ready): DRY master 줄 대상 = #2 만.
   - R21 재현(_master=#2 · #1 도 role master·tick ft-master-tick · #2 행 있음): DRY master 줄 = #2 만 + WARN 줄 1개(#1).
   - _master 행 없음: DRY master 줄 0 + ERROR 줄 1개 · 알림 파일 1줄.
   - 승계 중간(_master=#2 행 있음·role master·tick null · #1 행 role master·tick ft-master-tick): DRY master 줄 0 + ERROR 줄 1개 · 같은 픽스처로 2회 연속 돌려도 ERROR 는 서명 동일이라 알림 1줄 유지 · 서명이 바뀌면(픽스처 교체) 1줄 추가.
   - 뉴스 행 0(모든 행 tick null): DRY master 줄 0 · ERROR 0 · WARN 0.
   - (팀 판 · 가짜 tmux — PATH 맨 앞 스텁이 `tmux ls` 결과를 env 로 냄) heir_of·retarget_seat 를 픽스처 사본에 직접 호출: ①dead=X#3 · 생존 X#5 → _master·행 X#5 로 갱신 ②dead=X#3 · 생존 X#2 만 → 명부 바이트 불변 + DEAD 알림 1줄 ③dead=X#3 · 생존 X#4 인데 X#4 행에 _replaced_by → 불변 + 알림 ④dead=ft-harness-ops#3 · 생존 ft-harness-ops#2 와 byz-harness-master-claude#14 → 불변(#2 로 회귀 0) ⑤_master 가 이미 Y#9(≠dead) → 행만 갱신 · _master 불변.
   기존 `tests/harness/test_kit_bin_sync.sh` PASS(두 사본 같은 바이트).

커밋은 자기 브랜치, **push 금지**. **금지**: 키트 ft-tick.sh 로 팀 판을 덮기 · role 첫 행 폴백 · 좌석표 쓰기(retarget 외) · 라이브 `.fable-team/bin-*` 쓰기 · plist 변경.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_ft_tick_master_seat.sh` rc=0 · `tests/harness/test_kit_bin_sync.sh` PASS · 네 사본 `bash -n` OK · 사본 쌍 `cmp` 동일 · 커밋 A 의 ft-tick-team.sh md5 = cb379b08966214ac4136a6402588fdc5.
- RESULT 에 R21 재현 픽스처의 DRY master 줄·WARN 줄 2줄 복붙.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_ft_tick_master_seat.sh rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖 · 순서 고정): ①명부 — 틱 있는 좌석표 전부 `_master` 유효(cfo·feature·loom·ops 지금 유효 · kk 는 tick 비활성이라 추가만) ②`ft-tick-team.sh` 를 `.fable-team/bin-{cfo,feature,kk,loom,ops}/ft-tick.sh` 로 cp+cmp(이름 유지 — plist 무변경) · 키트 ft-tick.sh 는 `.worktrees/v6-realtime-live/.fable-team/bin/` 로 cp+cmp ③각 plist bootout→bootstrap ④팀 틱 1개 이상 로그 `master sent to <_master 값>` 1줄 + WARN·ERROR 0줄.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 0b1ca4e93849f1be1509fa8c2df3d1dbe6f4eba3 (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#12 · 원장 R27 · master#14 #62022). 사전검증 DA 소환 → APPROVE 뒤 master spawn.
- 2026-10-08 — DA HOLD 1(#62067 · DA 파일 §4·§5) → 교정 1: 구현 범위 4번(뉴스 행 검사 분리 · 서명 단위 ERROR) · 6번(후계 N 증가·은퇴 행 거부·다른 base 추측 0) · 8번 픽스처 추가. DA 교정 검토 1회 남음.
- 정본 영향 없음: 하네스 틱·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 — DA 교정 1 APPROVE(#62074 · DA 파일 §8·§9) → lint OK · spawn 가능(master). 나노 브랜치 nano/r27-master-seat · 커밋 A(structure)·B(feature) 분리.
- 2026-10-08 12:59 — 대기→진행 · 좌석 byz-harness-nano-r27-master-seat-single-source#0
- 2026-10-08 13:07 — 진행→완성 · 좌석 byz-harness-nano-r27-master-seat-single-source#0 · DA design/harness/OPS-VERDICTS-20261006.md#§54
세트: 6dc923936dac0033a16ab5ec9e35ca642418d1cf · 시험: bash tests/harness/test_ft_tick_master_seat.sh rc=0 · 이슈: 0
