# 인덱스: ft-role-spawn.sh 팀 env 감지 시 REJECT — v65 명부 좌석 오은퇴 차단 (R35 · master GO #62877)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → R35(cfo master#59 #62826 접수 · arch 안 #62876 · master GO #62877 — 하네스 내부 가드라 master 결정)
- 상태: 대기
- 선행: 없음
- 시험 입력: 임시 git 리포 + 가짜 루트 `.fable-team/seats.json`(v65 role 행 1개) + 가짜 팀 명부 `seats-cfo.json` · env FT_SEATS_JSON 주입 · `--dry-run` 만(tmux·claude 호출 0)
- 기준값: 지금 `FT_SEATS_JSON=<팀 명부>` 로 실행해도 `scripts/fable-team-bin/ft-role-spawn.sh:27` 이 루트 seats.json 을 읽고 PLAN 에 v65 교체 대상(`replaces=[…]`)을 낸다 — 실행하면 v65 현역 role 행에 `_replaced_by` 가 찍힘

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: 6-b(개선요청 접수·협의 — CFO master 가 올린 R35). 핵심 한 줄: v65 전용 역할 교체 도구가 팀 env 아래에서 실행되면 v65 현역 좌석을 명부에서 은퇴시키므로, 팀 env 를 감지하면 실행 전에 거부한다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
ft-role-spawn.sh 는 v65 역할 좌석 교체 전용이다 — 명부(루트 seats.json) · 인박스(design/v65/indices/inbox) · README(design/v65/SEATBELT-README.md) · 이름 접두(byz-v65-) · tmux 태그(@zc_v65_active) 가 전부 v65 고정이다. 다른 팀(CFO 등)은 팀 env(`FT_SEATS_JSON` 이 팀 명부를 가리킴)로 도구를 쓰는데, 이 스크립트만 그 env 를 무시하고 v65 명부의 같은 role 행을 교체 대상으로 잡는다. 실제 실행되면 v65 현역 좌석이 `_replaced_by` 로 은퇴 처리된다(실해). 일반화(6곳)는 팀이 role 좌석을 실제로 요구할 때 별 카드로 하고, 이 카드는 «팀 env 가 켜져 있으면 거부»만 한다. CFO 는 지금 ft-nano-spawn 경로를 쓰므로 영향 없음.

## 사전검증
- 소환: 아니오
- 면제: 실행 전 거부 3줄 추가뿐(기존 v65 경로 동작 무변화) · 시험으로 닫음 · master GO #62877 — arch 서명 byz-harness-arch-claude#14

## 조사 근거
- `scripts/fable-team-bin/ft-role-spawn.sh:27` SEATS 고정(루트 seats.json) · `:28`~`:29` v65 인박스·README · `:35`~`:37` 이름 접두 · `:44`~`:47` 교체 대상 계산 · `:76` @zc_v65_active.
- `scripts/fable-team-bin/ft-nano-spawn.sh:68` 팀 env 관례 `SEATS="${FT_SEATS_JSON:-$ROOT/.fable-team/seats.json}"`.
- `tests/harness/test_role_spawn_name.sh` 기존 시험(이름 규칙 · 깨지면 안 됨).

## 구현 범위 (닫힌 목록 · 추적본 + 키트 사본 같은 바이트)
1. `scripts/fable-team-bin/ft-role-spawn.sh`(+ `scripts/harness-install/fable-team/bin/ft-role-spawn.sh` 사본): `:27` SEATS 결정 직후 — `FT_SEATS_JSON` 이 비어 있지 않고 realpath 가 루트 seats.json 과 다르면 stderr 「REJECT ft-role-spawn 은 v65 전용 — 팀 env(FT_SEATS_JSON=<값>) 감지 · 팀 좌석은 ft-nano-spawn 또는 팀 전용 경로(R35)」 + exit 1 · `--dry-run` 에서도 같음(PLAN 출력 0).
2. 시험 `tests/harness/test_role_spawn_team_env.sh`: ①FT_SEATS_JSON=팀 명부 + --dry-run → rc 1 · stdout 에 PLAN 0 · 가짜 v65 seats.json 바이트 불변 ②FT_SEATS_JSON=루트 seats.json 과 같은 경로 → 지금 동작(PLAN 출력) ③FT_SEATS_JSON 미설정 → 지금 동작 · 기존 `test_role_spawn_name.sh` PASS · `test_kit_bin_sync.sh` PASS.

커밋은 자기 브랜치, **push 금지**. **금지**: v65 경로 일반화 · 팀 env 를 따르게 바꾸기(별 카드) · 실제 tmux·claude 실행 · 라이브 명부 쓰기.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_role_spawn_team_env.sh` rc=0 · `test_role_spawn_name.sh` PASS · `test_kit_bin_sync.sh` PASS · 사본 cmp · bash -n.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_role_spawn_team_env.sh rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖): 라이브 FT_BIN cp · `ft-live-bin-drift-check.sh` OK · CFO master 에 R35 닫힘 1줄.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#14 · R35 · master GO #62877 · 우선 낮음).
- 정본 영향 없음: 하네스 도구·시험만 — docs/architect 제품 정본 변경 없음.
