# 인덱스: 역할 좌석 승계 첫 발주에 «체크 크론 10분 + 부팅 보고 cron= 칸» 고정 (원장 R13 A)
<!-- ledger: design/teams/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 6-b(오케 개선요청 접수·협의). 핵심 한 줄: 원장 R13(CFO#54 #59304 · 오빠 10-07 「크론 이관받았어? 못받았으면 버그」) — 승계 좌석이 세션 크론을 안 걸어 오케·arch 가 idle 로 보였다. B(BOOT 16조항)는 ai-feature-pack 71e95b5 로 랜딩 · 이 카드는 프로그램 승계 경로(ft-role-spawn) 보강.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
대상은 추적본 `scripts/fable-team-bin/ft-role-spawn.sh`(100행) + 키트 `scripts/harness-install/fable-team/bin/ft-role-spawn.sh`(같은 바이트 · test_kit_bin_sync 검사). 역할 교체 첫 발주문은 95행 `BODY="[Seatbelt 역할 교체] …"` 한 줄로 만들어져 ft-send-verified.sh 로 간다 — 크론 언급 0. 세션 CronCreate 는 세션 종속이라 승계로 옮겨지지 않는다(launchd 뉴스 틱 ft-tick 은 seats.json tick 칸이 잇지만 별개). 정본 BOOT 16조항(라이브 ~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md): master·planner·arch 는 부팅 보고 그 턴에 CronCreate 10분(mbox recv + 하위 pane 실측 + 오빠 3줄) · 보고에 cron=<job id> · 없으면 착수 0. --dry-run 은 57행에서 PLAN 1줄 + tmuxc dry-run 만 찍고 끝난다(BODY 미출력). 시험 `tests/harness/test_role_spawn_name.sh` 는 임시 리포 + 가짜 tmux/tmuxc 로 PLAN 줄만 본다.

## 구현 범위 (이 둘만 — 닫힌 목록)
1. `scripts/fable-team-bin/ft-role-spawn.sh`(+ 키트 사본 같은 바이트):
   - BODY 를 만드는 줄을 --dry-run 분기(57행) «앞»으로 옮기고, ROLE 이 master 또는 arch 일 때만 BODY 끝에 다음 한 문장을 붙인다(그대로): 「★부팅 보고를 보낸 그 턴에 CronCreate 10분 체크 틱(mbox recv + 하위 pane 실측 + 오빠 3줄)을 건다 — 없으면 착수 0 · 부팅 보고에 cron=<job id> (BOOT 16)★」. da·pm·tester 무변화(pm 은 launchd ft-pm-tick 이 있다 · da·tester 는 발주 이벤트로만 움직인다).
   - --dry-run 일 때 PLAN 줄 다음에 `BODY <본문>` 1줄을 추가로 찍는다(시험용 관측점). 실전 경로 출력·동작 무변화.
2. `tests/harness/test_role_spawn_name.sh`에 사례 추가: --dry-run master → BODY 줄에 「CronCreate 10분」 과 「cron=<job id>」 포함 · arch → 포함 · da·pm·tester → 「CronCreate」 0 · 기존 PLAN 줄 기대값 전부 무변화.
커밋은 자기 브랜치, **push 금지**. **금지**: 라이브 FT_BIN 쓰기 · seats.json tick 칸 로직 변경 · 다른 역할 BODY 변경 · 크론을 스크립트가 대신 거는 시도(크론은 좌석 세션 안에서만 걸린다).

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_role_spawn_name.sh` rc=0 · `bash tests/harness/test_kit_bin_sync.sh` rc=0 · 기존 `tests/harness/test_*.sh` 전부 rc=0 · 두 사본 `bash -n` OK · `cmp` 두 사본 동일.
- RESULT 에 --dry-run master·da 실제 출력 BODY 줄 2개 복붙.
- 라이브 설치와 승계 6단계 5번 문구 3곳(ai-feature-pack · arch 초안 design/teams/harness/drafts/r13/fable-team/)은 master 집행 — 카드 범위 밖.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: b61099d2592b6c4bb629f07ab83831d5af19ff69 (spawn 2026-10-07)
- base: 최신 origin/main(ft-role-spawn 마지막 변경 = role-spawn-byz-default 86d77d5f6a 랜딩판).
- 2026-10-07 — 대기/ 생성 (byz-harness-arch-claude#6 · 원장 R13 A · master#8 #59365).
- 정본 영향 없음: 하네스 스폰 도구·시험만 — docs/architect 제품 정본 변경 없음
- 2026-10-07 18:30 — 대기→진행 · 좌석 byz-harness-nano-r13-role-spawn-cron#0
- 세트: d8de2910d1f5b228ac1b9f25e37274b8ba7b590d · 시험: bash tests/harness/test_role_spawn_name.sh rc=0 · 이슈: 0
- dry-run BODY master (크론 문장 포함):
  `BODY [Seatbelt 역할 교체] 너는 master 후계 좌석(byz-v65-master-claude#146). 먼저 /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-r13-role-spawn-cron/design/v65/SEATBELT-README.md §2 부팅 5단계(첫 보고까지), 그 다음 /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-r13-role-spawn-cron/design/v65/indices/inbox/master/ 를 정렬해 «맨 위» 파일부터 이어간다. 구 좌석 byz-v65-master-claude#145 은 정지 레디(kill 금지). 보고는 mbox 로 dispatch 에. ★부팅 보고를 보낸 그 턴에 CronCreate 10분 체크 틱(mbox recv + 하위 pane 실측 + 오빠 3줄)을 건다 — 없으면 착수 0 · 부팅 보고에 cron=<job id> (BOOT 16)★`
- dry-run BODY da (크론 문장 미포함):
  `BODY [Seatbelt 역할 교체] 너는 da 후계 좌석(byz-v65-da-claude#55). 먼저 /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-r13-role-spawn-cron/design/v65/SEATBELT-README.md §2 부팅 5단계(첫 보고까지), 그 다음 /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-r13-role-spawn-cron/design/v65/indices/inbox/da/ 를 정렬해 «맨 위» 파일부터 이어간다. 구 좌석 없음 은 정지 레디(kill 금지). 보고는 mbox 로 dispatch 에.`
- 2026-10-07 18:55 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§30
