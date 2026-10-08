# 인덱스: ft-index-move 진행→완성 — 정본 갱신 카드는 실제 랜딩 commit 에 정본 diff 가 있어야 이동 + 쪽지 수신자 팀 _arch + DA 절-카드 대조(R37 합침) (판정 444 · 440 설계 r2 §4 순서 1)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 444(오빠 컨펌 · planner#11 #63243 · master#16 #63247) · 판정 440 설계 r2 DA APPROVE · R37(master#15 #63005 · 이 카드에 합침)
- 상태: 대기
- 선행: 없음 — ★origin/main 최신에서 브랜치★(ft-index-move 슬랙 단계 #929 가 main 에만 있다 · ops/main-base 사본은 123줄 옛판 · 판정 444 ② 하네스 문서·코드는 랜딩 단위마다 main)
- 시험 입력: 임시 git 리포(main 흉내 + 랜딩 commit squash·merge·ff) + 카드·판정문 픽스처 — 실제 indices·판정서·seats.json·mbox 쓰기 0
- 기준값: 지금 「정본 갱신: X §Y」 줄은 X 파일·절 «실재» 만 보고 통과(G3 — 이번 변경에서 X 가 고쳐졌는지 안 봄) · 정본 쪽지는 role=arch-canon 좌석(FB_ARCHDOC#11 · 세션 없음 · 쪽지 10 미읽음)으로 감 · `--da …#§5` 가 `§57` 절에도 걸리고 다른 카드를 닫은 절 인용도 통과(R37 · master 실례 v436→§60)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「RELEASE-<ver>.md 1장 + 머신별 「반영됨 <machine> <sha>」 행 전부」.
골의 축: C(업그레이드·반영 — 랜딩 때 정본이 같은 PR 로 남는다) + 6-b(R37 개선요청). 핵심 한 줄: 카드가 완성으로 갈 때 «정본 갱신» 이 실제 랜딩 commit 에 있는지와 «그 카드를 닫은 판정 절» 인지를 사실로 검사한다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
ft-index-move.sh 진행→완성 문은 지금 세 가지가 비어 있다. ①카드의 「정본 갱신: docs/architect/X.md §Y」 줄은 X 가 있고 절 제목이 있으면 통과한다 — 로컬에서만 고쳤거나 아예 안 고쳐도 통과한다. 판정 440 설계 r2 §6-1 은 증거를 «실제 랜딩 commit S 와 그 확정 범위 R(S)» 로 정했다: squash·merge 랜딩은 R(S)=`S^1..S`, ff 랜딩은 랜딩 전 main tip T 를 받아 `T..S`. merge-base 는 계산하지 않는다(정상 랜딩 뒤 S 가 main 조상이면 빈 구간이 돼 거짓 REJECT — DA 재현). 검사는 (가)S 가 랜딩 브랜치(기본 origin/main) 조상 (나)`git diff --name-only R(S)` 에 X 포함 (다)판정문 그 절의 arch 확인 줄 `정본 diff 확인: X §Y @<C> — <무엇 1줄>` 의 C 와 S 에서 X 의 blob 이 같음(`git rev-parse C:X` == `S:X` · 다르면 «검토 뒤 정본이 바뀜»). 「정본 영향 없음」 카드는 `--landed` 를 줬을 때 (가)만 본다(필수 아님 · 설계 §2-3 표 = 갱신 카드만 필수). ②완성 뒤 정본 쪽지는 seats.json role=arch-canon 좌석으로 가는데 그 좌석이 죽어 있다 — 설계 §2-2 대로 수신자를 명부 최상위 `_arch` 값으로 바꾸고 없으면 쪽지 0(경고 1줄). ③R37: `--da <판정문>#§N` 은 §N 을 «포함» 하는 `## ` 절의 「닫힘」 글자만 본다 — §N 은 정확 일치(뒤가 숫자가 아님)여야 하고 그 절 본문에 카드 basename 이 글자로 있어야 한다. ①(다)의 확인 줄도 이 «정확한 절» 안에서만 찾는다.

## 사전검증
- 소환: 아니오
- 면제: 판정 440 설계 r2 를 DA 가 APPROVE(DA 파일 §4 · #63184) 한 범위(§6-1 ①~③ · §6-5 fixture 3개) 그대로 구현 · R37 부분은 검사 강화만(통과 조건 축소) — arch 서명 byz-harness-arch-claude#15

## 조사 근거
- origin/main 기준 줄: `scripts/fable-team-bin/ft-index-move.sh:2` 사용법(이미 `--landed <sha>` 인자 있음 · 슬랙 결과 답글에 넘김) · `scripts/fable-team-bin/ft-index-move.sh:32` 절 찾기 awk `index($0,s)>0` 포함 비교(R37 접두 충돌) · `scripts/fable-team-bin/ft-index-move.sh:39` 정본 게이트 python(첫 「정본 갱신」 줄 하나만 보고 exit — 여러 줄이면 나머지 미검사) · `scripts/fable-team-bin/ft-index-move.sh:90` 슬랙 단계가 CANON_NOTE 를 읽음(형식 바꾸면 같이).
- origin/main 133~148행: 완성 뒤 정본 쪽지 블록(role=arch-canon 좌석 찾기 · 없으면 WARN).
- `design/harness/DESIGN-landing-canon-440-20261008.md:93` §6-1 범위·검사 ①~③ · `design/harness/DESIGN-landing-canon-440-20261008.md:103` §6-5 fixture 표.
- 명부 키: `.fable-team/seats-harness.json` 최상위 `_arch`(= 현역 arch 좌석명).

## 구현 범위 (닫힌 목록 · 추적본 + 키트 사본 같은 바이트)
1. `scripts/fable-team-bin/ft-index-move.sh`(+ `scripts/harness-install/fable-team/bin/ft-index-move.sh` 사본) 진행→완성:
   - (R37) `--da` 절 찾기 = `## ` 헤더 안 `§N` 정확 일치(`§N` 바로 뒤가 숫자가 아님) · `§` 없는 절 이름은 지금처럼 포함 비교 · 절 본문(헤더 포함)에 카드 basename(`.md` 뺀 이름) 없으면 REJECT 「<판정문>#§N 은 <카드> 를 닫은 절이 아니다(절에 카드 이름 없음) — 이동 0」.
   - 카드에 「정본 갱신:」 줄이 하나라도 있으면 `--landed <S>` 또는 `--landed <T>..<S>` 필수(없으면 REJECT 「정본 갱신 카드는 --landed <랜딩 commit> 필수」) · ★모든★ 「정본 갱신:」 줄마다 (가)(나)(다) · 랜딩 브랜치 ref = env `FT_LAND_REF`(기본 `origin/main` · 시험이 임시 리포 `main` 을 주기 위한 것 · 검사를 끄는 값 없음) · 검사 전에 fetch 하지 않는다(호출자가 fetch · S 가 로컬에 없으면 REJECT 「S 없음 — git fetch 후 다시」).
   - (다) 확인 줄 없음 = REJECT 「판정문 절에 「정본 diff 확인: X §Y @<sha>」 줄 없음 — arch 검토 기록 필요」 · blob 다름 = REJECT 「검토 뒤 정본이 바뀜 — 재검토」.
   - 「정본 영향 없음」 카드 + `--landed` 있음 = (가)만 · 없음 = 지금과 같음. 이유 ≥10자 유지.
   - 완성 뒤 정본 쪽지: 수신자 = seats.json(env `FT_SEATS_JSON` 우선) 최상위 `_arch` · 키 없음·빈 값 = 쪽지 0 + 「INFO 정본 쪽지 생략 — 명부에 _arch 없음」 · role=arch-canon 찾기 삭제.
   - 파일 200줄 이하 유지 — 넘으면 정본·랜딩 검사를 `ft-index-move-canon.sh`(같은 두 사본 · `scripts/harness-install/fable-team/bin/` 와 `scripts/fable-team-bin/`)로 분리하고 본체가 부른다.
2. 시험 `tests/harness/test_index_move_canon_landed.sh`(임시 git 리포 · 실제 리포 쓰기 0): ①카드 브랜치엔 X 수정·랜딩 S 에는 코드만 → REJECT(나) ②정상 squash S(X 포함)·S 가 main 조상 → 통과(빈 구간 거짓 REJECT 0) ③arch 확인 C 뒤 X 재수정 → 랜딩 S → REJECT(다) ④ff 랜딩 `--landed T..S` 통과 ⑤`--landed` 없는 갱신 카드 REJECT ⑥(R37)다른 카드 절 인용 REJECT·파일 위치 불변 ⑦(R37)`§5` 인용이 `§57` 절로 통과 0 ⑧`_arch` 있음 = 그 좌석에 쪽지(FT_MBOX 가짜 스크립트로 인자 기록) · 없음 = 쪽지 0.
3. 기존 시험 무회귀: `tests/harness/test_index_move_slack.sh` · `tests/harness/test_kit_bin_sync.sh` PASS · 사본 cmp · `bash -n`.
4. RESULT 에 재판정 표(읽기만 · 파일 이동·수정 0): origin/main 의 `design/*/indices/완성/*.md` 카드 끝 `· DA <인용>` 줄을 새 R37 규칙으로 판정한 «통과 n / 거부 n · 거부 목록(카드 · 인용 · 사유)».

커밋은 자기 브랜치, **push 금지**. **금지**: 완성 카드 재이동·수정 · 판정서 수정 · 예외 목록·opt-out 환경변수(검사를 끄는 길 0) · 슬랙 단계 동작 변경(CANON_NOTE 형식이 바뀌면 슬랙 단계가 읽는 자리만 맞춤) · seats.json·mbox 실제 쓰기.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_index_move_canon_landed.sh` rc=0(①~⑧) · `test_index_move_slack.sh`·`test_kit_bin_sync.sh` PASS · 사본 cmp · bash -n.
- RESULT 에 재판정 표 — 거부 n>0 이면 arch 가 «판정 절에 카드 이름을 싣는 규칙» 을 팀 판정 꼴에 넣을지 판정(랜딩 전).
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_index_move_canon_landed.sh rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖): 라이브 FT_BIN cp · `ft-live-bin-drift-check.sh` OK · 팀 master 들에 1줄 공지(「정본 갱신 카드 완성 이동 = --landed <랜딩 sha> 필수」).
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: cb0d313486ef2652dfcd2d94c27fbd64e8e888dc (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#15 · 판정 444 · master #63247 · R37 카드 `r37-index-move-da-section-binding` 범위 합침).
- 정본 영향 없음: 하네스 카드 이동 도구·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 16:50 — 대기→진행 · 좌석 byz-harness-nano-v444-index-move-canon-landed#0
- 세트: 57c765fffedab1ddba5059cdb9cb196935749d55 · 시험: bash tests/harness/test_index_move_canon_landed.sh rc=0 · 이슈: 0
세트: baa297a9c516db4090ebf0bf6b283b0a2dc657de · 시험: bash tests/harness/test_index_move_canon_landed.sh rc=0 · 이슈: 0
- 2026-10-08 17:19 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§64
