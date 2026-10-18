# 인덱스: 세트 발주 원장 — ft-sets.sh 조회·검사 + SETS.md 틀 + 정본 + 승계 초안 (판정 359)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 359(planner#8 → master#13 발주 · 설계 design/teams/harness/DESIGN-set-dispatch-20261008.md · 조사 SURVEY-file-based-dispatch-20261008.md)
- 상태: 대기
- 선행: DA 사전검증 APPROVE(아래)
- 시험 입력: 임시 git 리포 · 가짜 SETS.md · 가짜 SET-REQUESTS.md · 가짜 발주 파일 2개정 — 원격 0
- 기준값: 세트 원장 0 · 판정 358 CFO 7세트 = mbox + 회수본 design/teams/harness/drafts/file-dispatch/ORDER-358-cfo-sets-relay-20261008.md 뿐

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 6-b(개선요청 접수 → 협의 → 개선) + planner 골 원문 2(팀 배정·운영 · 연결 관리 정리). 핵심 한 줄: 판정 359 오빠 원문 「큰작업은 세션이관에 메모리되고 상태를 바로 파악하고 이슈매니저와 협의하는 파일기반 발주」.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
큰 작업(여러 Issue·카드를 묶은 «세트»)의 발주가 mbox·/tmp relay 로만 가서 승계·이슈 매니저가 파일로 못 본다(판정 358 CFO 7세트 실례). 설계(DA APPROVE)는 세트 원장 `design/issues/SETS.md` 한 장(쓰는 손 = issues master) · 발주 본문 = `byz-agents@<sha>:<리포 상대경로>#<앵커>` + 보호 ref `refs/orders/<판정>-<팀>` · 상태 변경 = 팀 `design/<팀>/orders/SET-REQUESTS.md` 선기록 → mbox `[SET-REQ <id>]` → issues master 가 «같은 적용 id 면 재ACK 우선 → 전 상태 불일치면 적용 0 → 갱신·커밋» → `[SET-ACK <id>] … 원장 <sha>` → 팀이 `적용 <sha>` 기입. 이 카드는 그 원장들을 읽어 보여 주고 검사하는 도구 `ft-sets.sh`(읽기 전용 · 원격 0 · 키트 bin 밖)와 빈 틀·정본·승계 초안만 만든다. 원장 행 기입·라벨·LOOP-LEDGER 「세트=」 는 issues master·planner 몫(나노 0). 형식(칸 이름·상태 5종·이름 정규식·요청 줄 형식)은 설계 §1·§3-b 문자 그대로.

## 사전검증
- 소환: 예
- DA: design/teams/harness/DA-set-dispatch-20261008.md

## 조사 근거
- `scripts/fable-team-bin/ft-harness-info.sh:39` — map 하위 명령(정본 목차 `references/harness-map.md` 를 읽음 · 행 1개 추가 대상은 홈 파일).
- `scripts/harness-install/proposal/ft-proposal-register.sh:27` — 키트 bin 밖 도구 배치 선례(드리프트 BLOCK 회피) · 머리줄 정확 1개 검사 방식.
- `design/issues` 는 issues master 작업 트리(`.worktrees/issue-manager/design/issues/LOOP-LEDGER.md` · 11열)에 정본 — SETS.md 틀은 이 카드에서 리포 경로로 만들고, 실제 원장은 issues master 가 자기 트리에 둔다.
- 설계 §1 형식 · §2 발주 식별자·보호 ref · §3-b 요청 왕복 · §5 도구 · §8 시험 1~3.

## 구현 범위 (이 목록만 — 닫힌 목록)
1. `scripts/harness-install/sets/ft-sets.sh` 신규 — `[팀]` 표 출력(머리줄 = 원장 경로 @ 마지막 commit · 미커밋 표시 · 팀 필터면 pending/stale) · `--check`(이름·상태·발주 칸 `git cat-file -e`·보호 ref·Issue 겹침 경고). 원장 경로 = `FT_SETS_FILE` 하나(없으면 rc≠0 · 다른 경로로 넘어가기 0).
2. `docs/rules/set_dispatch.md` 정본(설계 §0~§5 요약 · 자동 로드 아님) · `design/issues/SETS.md` 빈 원장(머리+빈 표) · `design/cfo/orders/SET-REQUESTS.md` 빈 틀.
3. 홈 초안: `design/teams/harness/drafts/set-dispatch/fable-team/references/context-management.md`(승계 6단계 ① 스냅샷에 「열린 세트」 1줄) · `design/teams/harness/drafts/set-dispatch/fable-team/references/harness-map.md`(행 1개) — 홈 파일 cp 후 추가만.
4. 시험 `tests/harness/test_ft_sets.sh` · `tests/harness/test_set_requests.sh`(설계 §8 1·2 — 재ACK 우선 · 불일치 적용 0 · close 일부 실패 = 보류 · pending/stale · 같은 경로 이후 개정본 안 읽음 · 없는 sha = 미전달).

5. 기존 `scripts/fable-team-bin/ft-harness-info.sh`·`scripts/harness-install/proposal/ft-proposal-register.sh` 는 참고만 — 수정 0.

커밋은 자기 브랜치, **push 금지**. **금지**: 원장 행 기입 · Issue 라벨·Tank 호출 · 보호 ref 실제 생성(시험 리포 안에서만) · 키트 bin·.fable-team/bin 수정 · 홈 파일 직접 수정.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_ft_sets.sh` rc=0 · `bash tests/harness/test_set_requests.sh` rc=0(출력 PASS 줄 복붙).
- 홈 초안 diff 2개 = 추가뿐(`diff 홈 초안` 출력 복붙).
- `FT_SETS_FILE=<빈 SETS.md> bash scripts/harness-install/sets/ft-sets.sh cfo` 출력 복붙(머리줄 + 「세트 진행 0 · 발주 0 · 보류 0 · 닫힘 0」).
- 카드 증거 줄 형식(필수 · 이유 칸에 가운뎃점 금지): `세트: <40hex> · 시험: bash tests/harness/test_ft_sets.sh rc=0 · 이슈: 0`.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 56c8ea41d5426f42aabf1c5ce004a3e0f7914490 (카드 작성 시점 · spawn 때 갱신)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#10 · 판정 359). spawn 은 master 판단.
- 정본 영향 없음: docs/rules 에 하네스 절차 정본 1장 신규와 하네스 도구·시험이고 docs/architect 제품 정본 변경 없음.
- 2026-10-08 09:55 — 대기→진행 · 좌석 byz-harness-nano-set-dispatch-tools#0
- 2026-10-08 — 나노 산출 #61331 · arch#11 독립 재현(시험 25·12 ALL PASS · shellcheck 0 · 홈 초안 diff 추가 각 1줄 · 빈 원장 끝줄 확인) → 판정서 §51 초안.
세트: 043a9801c87a7fd80efb30831622711114b83679 · 시험: bash tests/harness/test_ft_sets.sh rc=0 · 이슈: 0
- 2026-10-08 10:06 — 진행→완성 · 좌석 byz-harness-nano-set-dispatch-tools#0 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§51
