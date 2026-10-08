# 인덱스: 나노 닫기 cherry 게이트 — squash 랜딩 PR 전용 플래그 --squashed-pr + 문서 종류만 WARN (R29)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 요청 원장 R29(feature master#3 #62204 · planner#9 승인 조건 ③ · master#14 #62205)
- 상태: 대기
- 선행: 없음(안 = design/harness/PLAN-r29-squash-superset-close-20261008.md §3 r1)
- 시험 입력: 임시 git 리포(시험 안에서 생성) + 가짜 gh(env FT_CHERRY_GH 로 주입 · state·mergeCommit·headRefOid 지정) — 실제 GitHub 호출 0
- 기준값: 사례 nano/f-guest-jwt-impl-s1 → 지금 REJECT(merge-tree 충돌 + 「tip 내용이 origin/main 역사에 없는 경로」) · 코드 21 중 같음 19 · PR #905 안에서 고쳐짐 2 · 유일한 통과 길 = 사유만 받는 --override

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 6-b(개선요청 접수·협의). 핵심 한 줄: squash 랜딩 뒤 «나노 내용이 PR 안에서 고쳐져 들어간» 경우를 사유만 받는 우회 대신 «기계가 사실을 가르고 사람이 의미를 표명하는» 좁은 플래그로.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
`ft-nano-cherry-gate.sh` 는 나노를 닫을 때 «나노 커밋 내용이 feat(main)에 들어왔는가»를 본다: git cherry «+» → merge-tree 실제 delta → 경로마다 나노 tip (mode,blob) 이 분기 뒤 feat 역사에 있었나(superseded). squash 랜딩은 PR 의 최종 트리만 남기므로, PR 안에서 나노 내용 뒤에 커밋이 더 있으면(리뷰 수정·리팩터) 나노 blob 이 main 역사에 없어 REJECT 된다(사례 PR #905: 나노 내용 96b67fdda9 → 같은 PR 리팩터 b52a55dc6a → squash cef86d391a). DA 는 «PR 중간 blob 존재 = 최종 반영» 이 거짓 통과를 만든다고 반례로 보였다(PR 안에서 되돌림). 그래서 자동 통과가 아니라 전용 플래그다 — 기계는 PR 사실과 경로별 분류(같음 / PR 안에서 고쳐짐 / 되돌림·제거·없음)를 가르고, «PR 안에서 고쳐짐»의 의미 보존은 사람이 사유로 표명하며, 되돌림·제거가 하나라도 있으면 플래그로도 안 된다. 함께, 혼합 커밋의 문서 경로 WARN 을 «문서 파일 종류»로 좁힌다(design/ 아래 SQL·스크립트는 코드로 검사).

## 사전검증
- 소환: 예
- DA: design/harness/DA-r29-squash-superset-20261008.md

## 조사 근거
- `scripts/fable-team-bin/ft-nano-cherry-gate.sh:40` «+» 커밋 분류(design/ 밖 경로 = block · design/ 만 = warn) 루프 시작.
- `scripts/fable-team-bin/ft-nano-cherry-gate.sh:63` merge-tree 실제 delta(content_landed_via_merge_tree) · `scripts/fable-team-bin/ft-nano-cherry-gate.sh:85` superseded 증거 구간 = merge-base(NANO,FEAT)..FEAT.
- `scripts/fable-team-bin/ft-nano-cherry-gate.sh:92` 경로마다 tip ls-tree (mode,blob) · `scripts/fable-team-bin/ft-nano-cherry-gate.sh:101` feat 역사에서 같은 mode·blob 탐색 — 플래그 분류가 재사용할 비교.
- `scripts/fable-team-bin/ft-nano-cherry-gate.sh:135` --override 원장(cherry-gate-override.log) 행 합성·ERROR 로그 — 플래그 원장 행이 따를 꼴.

## 구현 범위 (닫힌 목록 · 추적본 + 키트 사본 같은 바이트 · 안 §3 r1)
1. `scripts/fable-team-bin/ft-nano-cherry-gate.sh`(+ `scripts/harness-install/fable-team/bin/` 사본): 새 인자 `--squashed-pr <N> --reason "<사유>"`(둘 다 필요 · 사유 빈 문자열 REJECT · --override 와 동시 사용 = usage 2).
   - PR 사실: `${FT_CHERRY_GH:-gh} pr view N --json state,mergeCommit,headRefOid` → MERGED ∧ mergeCommit=S ∧ S ∈ merge-base..FEAT · H 로컬 없으면 `git fetch origin pull/N/head` · 실패 = REJECT.
   - 코드 경로(§2 의 분류 대상)마다 (mode,type,blob): «같음» = 나노 tip == FEAT HEAD · «PR 안에서 고쳐짐» = 나노 tip 이 merge-base(H,FEAT)..H 에 새 blob 으로 있음 ∧ S 의 경로 존재 ∧ S 의 경로 ≠ 분기 시점(merge-base(NANO,FEAT)) 경로 · 그 밖(되돌림·제거·PR 에 없음) = REJECT(플래그로도 불가).
   - REJECT 칸 0 일 때만 통과: 경로 표 출력(같음 n · PR 안에서 고쳐짐 경로마다 그 경로를 바꾼 PR 커밋 sha·제목) + 한계 문구 1줄 「S≠분기 시점은 의미 보존의 자동 증명이 아니다 — 보존 판단은 사유 작성자 책임 · 부분 변경 가능」 + override 원장에 `kind=squashed-pr pr=#N head=<H8> squash=<S8> paths=<목록> reason=<사유>` 1행 + stderr ERROR. 원장 기록 실패 = REJECT.
   - 플래그 없을 때 동작 = 지금 그대로(자동 통과 추가 0).
2. 같은 파일: 혼합 «+» 커밋의 superseded 검사에서 WARN 으로 낮추는 경로 = `design/` 아래 확장자 md·html·png·jpg·jpeg·svg·pdf 만. design/ 아래 그 밖(sql·sh·py·json·yaml·toml·확장자 없음 등) = 코드 경로로 남긴다. NUL-safe 완독 뒤 분류. (design/ 만 건드린 «+» 커밋 전체 WARN 규칙은 그대로 — 이번엔 혼합 커밋만.)
3. 파일 151줄 — 200 넘으면 PR 분류를 `scripts/fable-team-bin/ft-nano-cherry-pr.sh`(source 전용 · 같은 두 사본)로 분리.
4. 시험 `tests/harness/test_cherry_gate_squash.sh`(안 §4 ①~⑨ 그대로): 플래그 없음 REJECT · 플래그 PASS+원장+표+한계 문구 · ★PR 중간 P1→head P0 되돌림 → 플래그 REJECT★ · ★PR head 에서 경로 제거 → REJECT★ · mergeCommit 불일치·CLOSED·gh 실패 REJECT · 사유 빈 값 REJECT · mode 만 다름 = 같음 아님 · 혼합 커밋 design/x.md 미랜딩 WARN · ★design/rag/sql/x.sql·design/x/run.sh 미랜딩 REJECT★ · 기존 cherry 게이트 시험 PASS · `test_kit_bin_sync.sh` PASS.

커밋은 자기 브랜치, **push 금지**. **금지**: 플래그 없는 자동 통과 · PR 중간 blob 만으로 통과 · design/ 접두사 전체 WARN · 실제 gh·원격 호출(시험) · 라이브 FT_BIN 쓰기.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_cherry_gate_squash.sh` rc=0 · 기존 cherry 게이트 시험 PASS · `test_kit_bin_sync.sh` PASS · 사본 cmp · bash -n.
- RESULT 에 시험 ③(되돌림 → 플래그 REJECT) 출력 2줄 복붙.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_cherry_gate_squash.sh rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖): 라이브 FT_BIN cp · `ft-live-bin-drift-check.sh` OK · 실제 1회 = byz-feature-nano-f-guest-jwt-impl-s1#0 을 `--squashed-pr 905 --reason "<feature master 사유>"` 로 닫고 원장 1행 확인 → 원장 R29 반영.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 418c5e248960e238905c9310b54b15e9df68c2d5 (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#12 · 원장 R29 · DA HOLD 1 → 교정 1 APPROVE #62323).
- 정본 영향 없음: 하네스 닫기 게이트·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 13:47 — 대기→진행 · 좌석 byz-harness-nano-r29-cherry-gate-squashed-pr#0

세트: ea1a256723ad6cd2c545fd97c596cffe76945088 · 시험: bash tests/harness/test_cherry_gate_squash.sh rc=0 · 이슈: 0
- 2026-10-08 14:05 — 진행→완성 · 좌석 byz-harness-nano-r29-cherry-gate-squashed-pr#0 · DA design/harness/OPS-VERDICTS-20261006.md#§56
