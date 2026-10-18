# PLAN — R27 현역 master 좌석 정본 하나로 (틱 role 선택 vs _master) · 2026-10-08 · byz-harness-arch-claude#12

## 골 원문 (GOAL-harness.md 복붙)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

골의 축: C(업그레이드·반영) — 승계 때 틱이 옛 master 에 뉴스를 보내면 «모니터» 자체가 끊긴다. 원장 R27(R21 곁가지 · master#14 #62016 접수).

## §1 실측 (2026-10-08 12:4x)
| 무엇 | 값 |
|---|---|
| R21 증상 | feature 틱 로그 `master sent to byz-feature-master-claude#1 (%851)` 가 12:41 까지 — `_master` = #2 인데 |
| 원인 | `ft-tick.sh` `master_seat()`(키트 69행 · 141·199·258·281·298행 사용) = 좌석표에서 `role=="master"` 인 «첫» 현역 행. `_master` 는 안 읽는다 |
| 반대편 | `_master` 를 읽는 곳 = `ft-plan-handoff.sh:49·51` · `ft-issue-create-pair.sh:37` · 틱 plist 뉴스 문구(R21 뒤 ops·loom·feature) |
| 자동 교정 | `RETARGET`(키트 109행 부근)은 «세션이 없을 때»만 계보 후계로 옮긴다 — 옛 master 가 살아 있으면 안 옮긴다(이번 #1·#2 둘 다 생존) |
| 같은 어긋남 (전 좌석표 스캔) | seats-harness.json `_master`=#13 (현역 #14 · role master 첫 행 = ft-harness-ops#3) · seats-issues.json `_master`=#3 / role 첫 행 #1 · seats-planner.json `_master`=#9 / role 첫 행 #4 · seats.json(v65) `_master` 없음 / role 첫 행 #145(#146 행 없음) |
| 지금 피해 | feature 만(틱 있음 · R21 로 명부 정정 완료 12:48:16 `master sent to …#2`). harness·issues·planner 는 틱 plist 가 없어 «잠복» — 틱을 붙이는 순간 옛 좌석으로 간다 |

## §2 안 — `_master` 하나만 정본, role 은 검사용
1. `ft-tick.sh` `master_seat()` 를 `_master` 를 읽게 바꾼다. 그 행이 ①없거나 ②`_replaced_by` 가 있거나 ③role≠master 면 ERROR 로그 + `DEAD-SEATS.alert` 1줄 + 그 루프 master 전송 0(폴백 0 · #0 규칙 — role 첫 행으로 넘어가지 않는다).
2. role=="master" 현역 행이 둘 이상이면 WARN 로그 1줄(전송은 `_master` 로 그대로). 승계 때 옛 행 정리 누락을 화면에 드러내는 용도.
3. 좌석표 쪽 정리(명부 = master 손 · 코드 0): `_master` 없는 seats.json·seats-kk.json 에 `_master` 추가, harness `_master`→#14, 옛 master 행에 `_replaced_by` 표시.
4. 승계 절차 한 줄(governance §6 승계 표): 「명부 갱신 = `_master` 교체 + 새 행 추가 + 옛 행 `_replaced_by` — 셋 같이」.

대안(채택 안 함): `_master` 를 없애고 role 만 쓰기 — `_master` 를 읽는 스크립트 2종·plist 문구·`_hil_route` 관행을 다 바꿔야 하고, «role=master 첫 행»은 순서 의존이라 정본으로 약하다.

## §3 범위 (나노 1장 분량)
- `scripts/fable-team-bin/ft-tick.sh` + 키트 사본(같은 바이트): `master_seat()` 와 그 호출 5곳(rows 대신 좌석표 경로를 넘기게).
- 시험: `tests/harness/` 틱 시험(픽스처 좌석표 3종 — 정상 / `_master` 행 없음 / role master 2행)에서 대상 좌석·ERROR·WARN 줄 확인. `--dry-run` 전송 생략 경로 사용.
- 파일 길이: 키트 ft-tick.sh 지금 334줄(200 한도 이미 초과 · 기존). 이번 변경으로 늘리지 않는다 — `master_seat` 는 줄 수 그대로 교체.

## §4 함께 본 별건 (이 카드 범위 밖 · master 판단)
- 팀 틱 사본 드리프트: `.fable-team/bin-{cfo,feature,kk,loom,ops}/ft-tick.sh` 5개가 같은 md5(cb379b08…)인데 키트(4770b0d0…)보다 옛판 — idle_watch(Seatbelt 1.1)·wt-sweep·드리프트 경고가 없고 master 주기 900초(키트 300초). `ft-live-bin-drift-check.sh` 는 `*/.fable-team/bin` 만 본다. 의도된 고정인지 확인 필요 — 의도가 아니면 이 R27 설치 때 같은 cp 로 맞춘다.

## §5 사전검증
- 소환: 아니오 — 바깥 계약(틱 주기·문구·전송 경로) 동일, 대상 좌석을 고르는 한 함수만 바뀌고 픽스처로 전부 시험된다. 되돌림 = 1커밋 revert + 팀 bin cp. 최종 DA 는 완성 이동 때 1회.

## §6 닫는 증거
랜딩 sha + 팀 bin 설치 cmp + 팀 틱 1개 이상 로그 `master sent to <_master 값>` 1줄 + 좌석표 스캔(위 §1 스크립트) MISMATCH 0.

## §7 명부 수정 요청문 초안 (master#14 가 각 팀 master 에 relay · 2026-10-08 r2)
- byz-issues-master-claude#3 앞: 「[harness->issues] seats-issues.json 정리 부탁(코드 0) — _master = byz-issues-master-claude#3 인데 role master 첫 현역 행 = #1. #1·#2 행에 role stop-ready · tick null · _replaced_by = 다음 계보(#2·#3)를 적고, #3 행이 role master 인지 확인. 이유: 틱·정지 감시가 R27 이전엔 role 첫 행을 고른다(R21 feature 실측 — 옛 master 에 뉴스). 확인 = 회신에 python 한 줄 스캔 결과(_master == role master 유일 행).」
- byz-planner-master-claude#9 앞: 「[harness->planner] seats-planner.json 정리 부탁(코드 0) — _master = byz-planner-master-claude#9 인데 role master 첫 현역 행 = #4. #4~#8 행에 role stop-ready · tick null · _replaced_by 를 적고 #9 행이 role master 인지 확인. 이유·확인 방법은 위와 같음.」

## §8 r2 정정 (2026-10-08 · arch#12) — §4 「틱 사본 옛판」은 틀렸다
팀 틱 5개는 키트의 옛판이 아니라 «갈라진 판»이다(팀 판에만 RETARGET·FT_TICK_STAMP_PREFIX·FT_TICK_MASTER_MSG/PM_MSG · 키트에만 idle_watch·wt-sweep·drift). 팀 plist 4개가 FT_TICK_MASTER_INTERVAL=900 과 뉴스 문구를 env 로 고정한다. 키트로 덮으면 팀 뉴스 문구가 v65 기본 문구로 바뀌고 RETARGET 이 사라진다 → 동기화 대신 팀 판을 ft-tick-team.sh 로 main 에 들여온다(카드 커밋 A). 두 판 합치기는 이 카드 밖(완성 후).
