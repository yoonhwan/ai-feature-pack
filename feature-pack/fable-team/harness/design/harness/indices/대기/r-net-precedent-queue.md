# 인덱스: 선례 1명령 + 합치기 큐 1명령 + 인박스 Haiku 7초 (N4 · 팀 운영 구조 근원 수정 · 판정 1070·1079 · arch#29)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → planner ORDER(판정 1069·1070) · 설계 PLAN-harness-networking-20261011.md §2 D5·D6 · §4
- 제안서: 없음 — 오빠 판정 1070 으로 착수 승인된 하네스 구조 수정(판정 1079 3차 DA APPROVE #76290)
- 상태: 대기
- 선행: N3(`[결정]` lint 가 `선례:` 줄을 요구한다 — 이 카드의 출력 문자열과 맞춘다) · 설계 = `git show f0d974ab20:design/teams/harness/PLAN-harness-networking-20261011.md`(r2 · ★나노 워크트리에는 없다★)
- 시험 입력: 원장 픽스처(VERDICTS 2파일·hil-approvals.log·HIL-LEDGER·REQUEST-LEDGER·MERGE-QUEUE 발췌) · 임시 MERGE-QUEUE.md · gh 스텁(env `FT_GH_CMD` · 정상/`sleep 9`/rc 1) · `FT_SEND_DRY=1` — 실 gh·실 큐·실 쪽지 0
- 기준값(arch#29 실측 · 2026-10-11): 선례 원장 5곳 흩어짐(VERDICTS-planner-NN · `.fable-team/state/hil-approvals.log` · `design/teams/harness/HIL-LEDGER.md` · REQUEST-LEDGER · MERGE-QUEUE) · 한 명령 0 · 판정 중 «오빠 인터뷰» 238줄(합치기 36 · push 22 · 손 명령 25 · REVIEW §4 ②) · MERGE-QUEUE.md 표 8열(접수·팀·PR/세트·head·한 줄·막힘·실측·상태 · 판정 1058) · `ft_inbox_core.py` Haiku 분류 `FT_INBOX_HAIKU_TIMEOUT` 기본 20초(하루 710회 · 실패 54).

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
상위 제약(제품 골 · CLAUDE.md ACTIVE TRACK GOAL 바이트 일치): 목표는 빠른 유용 원문, 실시간 교정, N언어의 병렬·독립 발행, 소실·비의도 중복 없는 최종 말풍선이다. / LST ON 우선이며 LST OFF/전환과 기존 M0–M7·통합 조건도 남긴다. / 단순히 실패 사례를 많이 모았다는 이유로 실험을 닫지 않는다.
planner 원문 2(팀 배정·운영) / 닫는 증거(PLAN §6 N4 복붙): 「[결정] 쪽지 100% 에 `선례:` 줄 · MERGE-QUEUE 행이 손 쪽지 0 으로 쌓임」 + §9 ② 「AskUserQuestion … 115/일 → ≤15/일 · 그중 `[합치기]` ≤1/일」.
골의 축: 근원 ②(오빠 질문 과다 — 선례 미조회 · 합치기 1건씩) — 채택안 B.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
되돌릴 수 있는 것까지 오빠께 묻고, 이미 결정된 판정을 안 찾아보고 다시 묻고, 합치기 요청을 팀마다 한 통씩 보내 planner 가 «합치기만 묻는 세션»이 됐다. 이 카드는 도구 둘로 그 길을 바꾼다. ①`ft-precedent.sh "<검색어>" [--since MM-DD]` — 원장 5곳(VERDICTS-planner-*.md 판정 줄 · hil-approvals.log · HIL-LEDGER.md · REQUEST-LEDGER.md · MERGE-QUEUE.md)을 한 번에 grep 해 `판정 N · 날짜 · 한 줄 · 파일:행` 표(최신 위 · ≤20행 · 넘치면 `… 전체 <N>행`)를 내고, 0건이면 정확히 `0건` 1줄(N3 의 `[결정]` lint 가 `선례: 없음(ft-precedent "<검색어>" 0건)` 문자열을 받는다). ②`ft-merge-queue.sh add --team <팀> --pr <N>|--branch <b> --head <sha> --line "<한 줄>" [--blocks "<막힘>"]` — planner 워크트리의 `design/planner/MERGE-QUEUE.md`(절대 경로 · `flock`) 에 기존 8열 꼴로 행 1 추가 + `[합치기] <팀> <PR> <head> — 큐 행 추가` 1줄 mbox(`FT_SEND_DRY` 지원) · `list` = 표 출력 · `measure` = planner 가 인터뷰 전 행마다 `gh pr checks`/`gh pr view`(`timeout 7`+재시도 1) + 로컬 `git merge-tree --write-tree` 로 checks·head·CLEAN 칸을 채우고 실패 행은 `실측 실패(<이유>)`(빈 값·통과 추정 0). ③`ft_inbox_core.py` Haiku 호출 상한 기본 20→7초 + 재시도 1(실패 때 출력 앞 200자 로그 — PROPOSAL-inbox §4 그대로 · 분류 규칙 무변경). 세부는 PLAN §2 D5·D6 · §4 가 정본.

## 사전검증
- 소환: 예 — DA byz-harness-da-codex#1 r0 HOLD #76217 · r1 HOLD #76265 · r2 APPROVE #76290(판정 1079) — arch 서명 byz-harness-arch-claude#29
- 조사 근거: `design/planner/MERGE-QUEUE.md`(8열 · 즉시 질문 예외 2) · `design/planner/VERDICTS-planner-2[56]-20261011.md`(판정 줄 꼴 `NNNN planner 결정(…)`) · `.fable-team/state/hil-approvals.log` 꼴 · `design/teams/harness/HIL-LEDGER.md` 8칸 · `scripts/fable-team-bin/ft_inbox_core.py`(`haiku()` · `FT_INBOX_HAIKU_TIMEOUT`) · `scripts/fable-team-bin/ft-hil-ask.sh`(원장 쓰기 꼴 재사용)
- 7초 룰 점검(판정 666): `measure` 의 gh 2종 `timeout 7`+1 · Haiku 7+1 · grep·파일은 로컬

## 구현 범위 (닫힌 목록 · 나노 · PLAN §6 N4 · 한 번에 하나)
관련 파일(기존 · origin/main 실재 · 나노 base): scripts/fable-team-bin/ft-hil-ask.sh · scripts/fable-team-bin/ft_inbox_core.py · scripts/fable-team-bin/ft-inbox.py · tests/harness/test_inbox.sh
1. ①시험 빨강 먼저 — 새 `tests/harness/test_precedent_queue.sh` + 픽스처(원장 5종 발췌 · MERGE-QUEUE 빈 표/행 있음 · gh 스텁 3종). precedent: 매칭 3건 표 · 0건 → `0건` · 21건 → 20행+전체 줄 · `--since` 필터. queue: add 1행(8열 · flock 2중 호출 순서 보존) · list · measure 정상/타임아웃→`실측 실패(timeout)`/rc1→`실측 실패(rc=1)` · DRY 쪽지 본문 1줄. inbox: 스텁 `claude` `sleep 9` → 7초 실패 → 재시도 1 → 미상 + 로그 200자. 이 커밋 rc≠0(빨강).
2. ②새 `scripts/fable-team-bin/ft-precedent.sh`(≤120줄).
3. ③새 `scripts/fable-team-bin/ft-merge-queue.sh`(≤200줄 · 큐 경로 env `FT_MERGE_QUEUE` 기본 = v6-realtime-live/design/planner/MERGE-QUEUE.md).
4. ④`scripts/fable-team-bin/ft_inbox_core.py` `haiku()` — 상한 기본 7 + 재시도 1 + 실패 로그 200자(1 hunk · 분류 정규식 무변경).
5. ⑤미러: `scripts/harness-install/fable-team/bin/` `cmp` 0.

커밋은 자기 브랜치(단계별 · [test]→[feature]→[fix] 분리), **push 금지**. **금지**: 실 MERGE-QUEUE.md 쓰기(시험은 임시 파일) · 실 gh 호출 · 실 쪽지 · 라이브 bin 쓰기 · 분류 ①~⑥ 규칙·보고 의무 훅 변경 · 위 목록 밖 파일 수정 0.

## 완료 조건 (닫힘 판정 기준)
- `bash tests/harness/test_precedent_queue.sh` rc=0 · 기존 inbox 시험(`tests/harness/test_inbox*.sh` 있으면) rc=0 · `bash -n`·`py_compile` · 미러 `cmp` 0.
- 카드 증거 줄(«세트:» 로 시작 · 접두 없음): 세트: <40hex> · 시험: bash tests/harness/test_precedent_queue.sh rc=0 · 이슈: 0
- 루트 지침: 완료 그 턴에 증거 줄 + arch#29 에 `[완료·휴식]` 1통.

## 상태
- base: origin/main 32d0374ed0e8c600e3c7ae07537cc814be989b60 (arch#29 카드 작성 시점 · spawn 때 `--base origin/main` 으로 다시 고정 · base_sha 줄은 spawn 도구가 쓴다)
- 2026-10-12 — 대기/ 생성 (byz-harness-arch-claude#29 · N4 · 설계 PLAN r2 f0d974ab20 · DA APPROVE #76290 · 판정 1070·1079).
- 정본 영향: 하네스 키트 bin 신규 2 · ft_inbox_core 1 hunk(7초) · 실 MERGE-QUEUE.md 는 planner 소유(도구가 쓰는 자리 · 이 카드가 내용을 바꾸지 않음).
