# 인덱스: ft-issue-close-check 6항 «정본» — 랜딩 commit 에 정본 diff 가 있어야 Issue 닫기 통과 + 시험 픽스처 + ISSUE-TRANSITIONS §3 표 1행 (판정 444 · 440 설계 r2 §4 순서 2)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 444(오빠 컨펌 · planner#11 #63243 · master#16 #63247) · 판정 440 설계 r2 DA APPROVE
- 상태: 대기
- 선행: 없음 — origin/main 최신에서 브랜치(판정 444 ② · 대상 3파일은 ops/main-base 와 main 이 같은 바이트) · v444-index-move-canon-landed 와 파일 겹침 0(동시 진행 가능)
- 시험 입력: 임시 git 리포(main 흉내 + 랜딩 commit) + `tests/fixtures/issue_close/` 모양의 JSON 픽스처 — 실제 GitHub 호출·Issue 쓰기 0
- 기준값: 지금 close 검사 = 5항(닫는 사건·PR·재현 PASS·정리·기록) + Closes 연결 PR · 「정본」 항목 0 · 최근 랜딩 5건 Closes 연결 0 · #913(행동 바뀐 fix)이 정본 0 으로 랜딩(440 설계 §1-1)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「RELEASE-<ver>.md 1장 + 머신별 「반영됨 <machine> <sha>」 행 전부」.
골의 축: C(업그레이드·반영 — 이슈 작업도 랜딩 때 정본이 같은 PR 로 남는다). 핵심 한 줄: Issue 를 닫을 때 정본 절이 실제 랜딩 commit 에 들어갔는지(또는 영향 없음 이유)를 사실로 검사한다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
ft-issue-close-check.sh 는 Issue 코멘트에서 「항목: 값」 줄 5개와 Closes 연결 PR 을 읽는 읽기 전용 검사다. 판정 440 설계 r2 는 6항 「정본」 을 더했다: 코멘트에 `정본: <X>#<절>@<S>` (부분 PR 여러 개면 `@<S1>,<S2>` · ff 랜딩이면 `@<T>..<S>`) 또는 `정본 영향 없음: <이유 ≥10자>` 줄이 있어야 한다. `정본:` 이면 S 마다 (가)S 가 랜딩 브랜치(기본 origin/main) 조상 (나)확정 범위 R(S) 의 바뀐 파일에 X 포함 — R(S) 는 squash·merge 면 `S^1..S`, `T..S` 꼴이면 그 구간이다(merge-base 계산 0 · 정상 랜딩 뒤 빈 구간 거짓 REJECT 방지). 하나라도 아니면 MISS(사유: 「랜딩 안 됨」 / 「랜딩 commit 에 정본 X 없음 — 로컬에만 고친 것」). 「영향 없음」 은 이유 길이만 본다. 이 검사는 Issue «최종 닫는 사건» 에서만 돈다 — 큰 Issue 의 부분 PR 은 `Refs #N` 이고 Closes 가 없어도 오류가 아니다(이 도구는 부분 PR 단계에서 불리지 않는다). 기존 5항·Closes 검사는 그대로다.

## 사전검증
- 소환: 아니오
- 면제: 판정 440 설계 r2 를 DA 가 APPROVE(DA 파일 §4 · #63184) 한 범위(§2-3 표 2행 · §6-1 ①② · §6-3 부분 PR · §6-5 fixture 4행) 그대로 · 읽기 전용 검사에 항목 1개 추가 — arch 서명 byz-harness-arch-claude#15

## 조사 근거
- `scripts/fable-team-bin/ft-issue-close-check.sh:4` 머리 주석 5항 · `scripts/fable-team-bin/ft-issue-close-check.sh:28` 5항 루프(줄 모양 정규식 · 값 비면·`<…>` 면 미기재) · `scripts/fable-team-bin/ft-issue-close-check.sh:35` Closes 연결 PR 검사 · `scripts/fable-team-bin/ft-issue-close-check.sh:16` `--from-json` 시험 경로(gh 대신 파일).
- `scripts/fable-team-bin/ft-close-reason-check.sh:47` 사유=완성 이면 이 도구를 그대로 인용(출력·rc 가 바뀌면 같이 영향 — 무회귀 확인 대상).
- `design/teams/harness/ISSUE-TRANSITIONS.md:34` §3 close 5항 표 · `design/teams/harness/ISSUE-TRANSITIONS.md:43` 「기준값 대비」 행(검사 무변경 행 예시).
- `design/teams/harness/DESIGN-landing-canon-440-20261008.md:93` §6-1 범위·검사 · `design/teams/harness/DESIGN-landing-canon-440-20261008.md:99` §6-3 부분 PR.

## 구현 범위 (닫힌 목록 · 추적본 + 키트 사본 같은 바이트)
1. `scripts/fable-team-bin/ft-issue-close-check.sh`(+ `scripts/harness-install/fable-team/bin/ft-issue-close-check.sh` 사본):
   - 6항 「정본」: 코멘트 줄 `정본: <X>#<절>@<sha 목록>` 또는 `정본 영향 없음: <이유 ≥10자>` 중 하나(5항과 같은 줄 모양 규칙 · `[ ]`/`- ` 접두 허용). 없음 = `MISS 6항 정본 — 코멘트에 「정본: <파일>#<절>@<랜딩 sha>」 또는 「정본 영향 없음: <이유>」 줄 없음`.
   - `정본:` 값 검사 = 위 배경 (가)(나) · sha 목록 각각 · 리포 = 옵션 `--repo <dir>`(기본 = 이 스크립트가 있는 리포 루트) · 랜딩 브랜치 ref = env `FT_LAND_REF`(기본 `origin/main` · 시험이 임시 리포 `main` 을 주기 위한 것 · 검사를 끄는 값 없음) · fetch 하지 않는다(S 가 로컬에 없으면 MISS 「S 없음 — git fetch 후 다시」).
   - 머리 주석·PASS 문구 「5항」 → 「6항」. 나머지 동작(gh 호출 1회 · edit/close/label 0 · exit 0/1/2) 무변경.
2. 픽스처 `tests/fixtures/issue_close/`: 기존 `closed-with-5items.json` 은 «6항 없음 → FAIL» 기대로 두고, 새 `closed-with-6items-canon.json`(정본 줄 · sha 자리는 시험이 임시 리포 sha 로 치환) · `closed-with-6items-no-impact.json`(영향 없음 이유 ≥10자) · `closed-partial-two-sha.json`(`@S1,S2`) 추가.
3. 시험 `tests/harness/test_issue_close_canon.sh`(임시 git 리포 · `--from-json` · 실제 gh 0): ①정본 X 가 랜딩 S 에 있음 → PASS ②카드 브랜치엔 X 수정·랜딩 S 엔 코드만 → MISS(나) ③S 가 main 조상 아님 → MISS(가) ④정상 squash S 가 main 조상 → 거짓 MISS 0 ⑤`@S1,S2` 각각 통과 · 하나라도 X 없으면 MISS ⑥영향 없음 이유 9자 MISS · 10자 PASS ⑦6항 없는 기존 5항 픽스처 = FAIL ⑧`ft-close-reason-check.sh` 사유=완성 경로가 새 출력으로 rc 그대로 전달.
4. `design/teams/harness/ISSUE-TRANSITIONS.md` §3 표에 1행: `| 정본 | 「정본: <X>#<절>@<랜딩 sha>」 또는 「정본 영향 없음: <이유≥10자>」 — 부분 PR 은 최종 닫기 때 @S1,S2 (판정 440 r2 · 444) |` + 검사 줄 「5항」 → 「6항」.

커밋은 자기 브랜치, **push 금지**. **금지**: 실제 Issue 코멘트·close·label · 기존 5항 판정 완화 · 예외 목록·opt-out 환경변수 · PR 템플릿 수정(카드 v444-pr-template-canon-line 몫).

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_issue_close_canon.sh` rc=0(①~⑧) · `tests/harness/test_kit_bin_sync.sh` PASS · 사본 cmp · bash -n.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_issue_close_canon.sh rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖): 라이브 FT_BIN cp · `ft-live-bin-drift-check.sh` OK · issues master 에 1줄 공지(「Issue 닫기 코멘트에 6항 정본 줄 필수」).
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: cb0d313486ef2652dfcd2d94c27fbd64e8e888dc (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#15 · 판정 444 · master #63247).
- 정본 영향 없음: 하네스 Issue 닫기 검사 도구·전이표·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 16:51 — 대기→진행 · 좌석 byz-harness-nano-v444-issue-close-canon-6th#0
세트: ef6fb991436de5d54c0456c96efe3c1a4574d5e6 · 시험: bash tests/harness/test_issue_close_canon.sh rc=0 · 이슈: 0
- 2026-10-08 17:19 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§66
