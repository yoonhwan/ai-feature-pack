# DESIGN — 판정 440 팀·이슈 랜딩 때 정본화·문서화 완성 위치·강제 · r2 (2026-10-08 · byz-harness-arch-claude#14 · DA r1 HOLD-L1 교정 §6)

## 골 원문 (GOAL-harness.md 복붙)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

골의 축: 6-b(개선요청 협의) + C(업그레이드·반영). 오빠 원문(10-08): 「이거 각 팀작업과 이슈 작업 랜딩할때 정본화, 문서화 완성은 어디서 어떻게 구성하면 좋을지 기획 da 받아보자」. 발주: planner#11 판정 440 → master#16 #63098. 기획+DA 만 · 집행·코드 0.
읽은 정본: ~/.claude/rules/closeout-policy.md · fable-team references/main-team-governance.md · docs/rules/completion_discipline.md(§4-2 「그림 정본은 한 곳 · 사본 금지」) · docs/rules/commit_discipline.md(「squash 면 PR 본문이 영구 기록」) · design/teams/harness/ISSUE-TRANSITIONS.md §3(close 5항).

## §1 실태 대조 (질문 4 · arch 실측 2026-10-08 · origin/main)
### 1-1. 최근 랜딩 5건 — 정본·문서가 실제 남은 곳
| PR | 무엇 | 남은 곳 | docs/architect 정본 | Issue 닫힘 | 빈 곳 |
|---|---|---|---|---|---|
| #899 (merged · docs) | loom ops↔loom 관리 API 계약 r3 + 카드 11 | design/loom/ 54파일(DA-REQ·DA 판정 20여 장 · CONTRACT · AUDIT · 카드 · NANO-LEDGER) | 변경 0(LOOM_* 7장 있음) | Closes 0 | 계약 정본이 팀 폴더 CONTRACT 에만 · CLOSEOUT 0 · 완성 카드 1장에 정본 줄 0 |
| #913 (merged · fix) | selfhost 에서 Gemini cachedContent 생성 전 raise (판정 406 · Issue #792) | 코드 3파일 · PR 본문 1,240자 | 변경 0 — 그런데 cachedContent 를 다루는 정본 10장 실재(BASE_ARCHITECTURE · CFO_BILLING_SOVEREIGNTY_ARCHITECTURE · LOOM_CACHE_DESIGN 등) | ★#792 OPEN · Closes 0 · 5항 코멘트 0★ | 행동 바뀐 fix 인데 정본 0 · 카드 `design/loom/indices/진행/loom-extcall-a-cache-create-raise.md` 가 랜딩 뒤에도 진행/ |
| #924 (merged · docs) | ROTATE loom_gateway DSN (판정 391) | design/security/ 1장 | 해당 없음(운영 절차서) | — | 없음(기록 문서 자체가 산출물) |
| #925 (OPEN · feature) | 토스 환불 1/2 유출 카운터 (#920) | 코드 3 + design/cfo/evidence/ RESULT 1장 | 변경 0(CREDIT_ARCHITECTURE·COST_BASE_TABLE 실재) | #920 OPEN · 코멘트 0 · Closes 0 | 랜딩 전이라 판정 보류 — 단 PR 에 정본 줄 자리 0 |
| #930 (merged · chore) | CI 비용 차단(판정 436) | ci.yml 1 · 판정서 §61·카드는 ★ops/main-base 브랜치★(design/teams/harness/OPS-VERDICTS-20261006.md) | 해당 없음 | — | ★하네스 판정서·카드가 main 에 없다 — ops/main-base 는 origin/main 보다 269 앞 · 29 뒤★ |

### 1-2. 이미 있는 장치와 그 실효
| 장치 | 무엇을 하나 | 실측 실효 |
|---|---|---|
| `ft-index-move.sh` 정본 게이트(진행→완성) | 카드에 「정본 갱신: docs/architect/….md §절」(파일·절 실재) 또는 「정본 영향 없음: 이유≥10자」 없으면 REJECT · 통과하면 arch-canon 좌석에 「[정본 갱신 요청]」 쪽지 | ★수신 좌석 FB_ARCHDOC#11(seats.json role=arch-canon) tmux 세션 없음 · 쪽지 10건 미읽음(최신 seq 63002 = v436 닫힘)★ — 요청이 아무에게도 안 간다 · 「정본 갱신」 줄은 «그 파일이 이번 변경에서 실제로 고쳐졌는가» 를 안 본다 |
| 완성 카드 정본 줄 분포 | harness 56 = 갱신 0 · 영향 없음 55 / v65 555 = 갱신 10 · 영향 없음 190 · 나머지 게이트 이전 / loom 1 = 둘 다 0 / feature 4 = 둘 다 0 / planner 7 = 영향 없음 1 | 팀 대부분이 ft-index-move 를 안 거치거나 카드가 main 밖(cfo·ops 완성 0) |
| `ft-issue-close-check.sh` 5항 | 닫는 사건 · PR · 재현 PASS · 정리 · 기록(CLOSEOUT·LOOP-LEDGER 경로) + Closes 연결 PR | 「정본」 항목 없음 · 최근 5건 중 Closes 연결 0 |
| `ft-land.sh` | 후보 커밋 계산만(push 0) | 문서·정본 검사 0 |
| `ft-nano-close.sh` | 좌석 닫기(결과·회수·idle·증거 줄·cherry) | 랜딩 문이 아니다(좌석 수명) — 정본 검사 자리 아님 |
| `.github/PULL_REQUEST_TEMPLATE.md` | 「Closes #」 첫 줄 + 완료 5항 체크 + 로컬 검증 체크(정본 자리 0) | 최근 5건 Closes 연결 0 — 템플릿은 있는데 채워지지 않는다(#913 은 제목에 「Issue #792」 만) |
| closeout-policy 2항 | CLOSEOUT 1장 + 원장 정본(LANG_BENCH_LEDGER 등) 반영 | 강제 장치 0 — 사람 규율 |

### 1-3. 빈 곳 (원인 = 출처까지)
- G1 정본 갱신 «요청» 의 수신자가 죽어 있다(FB_ARCHDOC#11) — 장치는 있는데 닫는 사건이 없다(once_set_state_needs_closing_event).
- G2 정본 줄이 «카드 경로»(ft-index-move) 에만 있다 — PR·Issue 로 바로 랜딩하는 일(#913·#925)에는 자리가 없다.
- G3 「정본 갱신: X」 가 «X 가 이번 변경 diff 에 있는가» 를 안 본다 — 줄만 쓰면 통과.
- G4 하네스 정본·판정서가 장수 브랜치(ops/main-base)에 산다 — closeout-policy 3항 「가지를 치지 않는다」 위반 · main 독자는 못 본다.
- G5 Closes 미연결 → Issue 가 랜딩 뒤에도 열림(#792) · close 5항 검사가 돌 기회 0.

## §2 안 (질문 1·2·3)
### 2-1. 어디에 — 정본은 «한 곳», 나머지는 포인터 (completion_discipline §4-2)
| 무엇 | 단일 정본 | 포인터만 두는 곳 |
|---|---|---|
| 제품 동작·아키텍처 | `docs/architect/*.md` 해당 절 | 팀 카드 「정본 갱신:」 줄 · PR 본문 · Issue 닫는 코멘트(절 URL@sha) · CLOSEOUT |
| 측정·원가 원장 | `docs/architect/LANG_BENCH_LEDGER.md` · `COST_BASE_TABLE.md` 등 원장 파일 | 같음 |
| 작업 과정(설계·DA·판정·증거) | 팀 폴더 `design/<팀>/`(카드·DA·판정서·evidence) — 과정 기록이지 정본이 아니다 | — |
| 단위 묶음 마감 | `design/<팀>/CLOSEOUT-*.md` 1장(closeout-policy) — 정본 절 «링크»와 sha 만, 본문 재서술 0 | — |
| 하네스 정본 | fable-team 스킬 references/ · `docs/rules/` · `design/teams/harness/` 판정서 — ★main 에 있어야 정본★ | — |

### 2-2. 어디서·누가·언제 (질문 1)
- **원칙: 정본 diff 는 «그 변경과 같은 PR» 안에 탄다**(랜딩 전). 랜딩 뒤 따로 쓰는 정본은 안 쓰인다(G1 실측) · 같은 PR 이면 CI 1회(판정 436 — 문서만 바뀐 커밋은 CI 0 이고, 열린 PR 에 문서만 따로 push 하지 않는다).
- **팀 작업(카드 경로)**: 쓰는 손 = 구현 나노(코드와 같은 브랜치에 정본 절 수정) · 검토 = 팀 arch(판정서에 「정본 diff 확인」 1줄) · 랜딩 = 팀 master. 카드 「정본 갱신:」 줄은 착수 «전» arch 가 카드에 적는다(무엇을 고칠지 미리 정함).
- **이슈 작업(issues master 경유)**: 쓰는 손 = 배정된 구현 좌석(같은 PR) · PR 본문에 같은 줄 · issue-master 가 닫을 때 close 5항에 «정본» 항목 추가(6항) — 값 = 정본 절 URL@랜딩 sha 또는 「영향 없음: 이유」.
- **CLOSEOUT 과의 관계**: CLOSEOUT 은 «단위 묶음(트랙·축)» 이 끝날 때 1장 — 카드·이슈마다 쓰지 않는다. 내용은 정본 절 포인터와 sha 목록 + 원장 반영 확인(closeout-policy 2항). CLOSEOUT 이 정본을 대신하지 않는다.
- **arch-canon 좌석(G1)**: 상시 좌석으로 살리지 않는다(쓰는 손이 같은 PR 의 나노로 옮겨 오므로 «요청 수신자» 가 필요 없음). ft-index-move 의 「[정본 갱신 요청]」 쪽지는 «팀 명부 `_arch`» 로 «알림» 1통으로 바꾸거나 없앤다 — 아래 2-3 의 diff 검사가 닫는 사건을 대신한다.

### 2-3. 어떻게 강제 (질문 3) — «판정 게이트» 가 아니라 «사실 검사» (no_gatekeeper_in_the_publish_path)
| 문 | 지금 | 바꿀 것 | 판정 기준(기계) |
|---|---|---|---|
| `ft-index-move.sh` 진행→완성 | 정본 줄 존재·파일·절 실재 | ★r2: 「정본 갱신: X §Y」 카드는 `--landed <S>` 필수 — S 는 실제 랜딩 commit(§6-1 범위 규칙) · 쪽지 수신자 = 팀 `_arch`(없으면 쪽지 0)★ | §6-1 ①~③ |
| `ft-issue-close-check.sh` | 5항 + Closes PR | ★r2: 6항 「정본: <X>#<절>@<S>」 또는 「영향 없음: <이유≥10자>」 — S 는 랜딩 commit · 검사 = §6-1 ①~②(Issue 최종 닫는 사건에서만 · 부분 PR 은 §6-3)★ | §6-1 |
| PR 본문(공용 템플릿 `.github/PULL_REQUEST_TEMPLATE.md` 갱신 · 이미 실재) | Closes·5항 자리는 있으나 정본 자리 0 · 미기입 다수 | 「정본: … / 영향 없음: …」 1줄 자리 + 「Closes #N」 자리 | 사람·좌석이 채움 · 검사는 위 두 문이 한다 |
| `ft-land.sh` | 후보 계산 | 변경 0(랜딩 계산 도구 — 문서 판단을 섞지 않는다) | — |
| `ft-nano-close.sh` | 좌석 닫기 | 변경 0(좌석 수명 · 랜딩 문 아님) | — |
| 하네스 브랜치(G4) | ops/main-base 장수 | 하네스 판정서·카드·설계를 «랜딩 단위마다» main 으로(다른 PR 과 같은 squash 규칙) · ops/main-base 는 작업 브랜치로만 | origin/main..ops/main-base 의 design/harness 차이 0 이 «하네스 마감» 조건 |
- 「영향 없음」 남용 방지: 이유 ≥10자 유지 + 코드 경로가 `worker/`·`gateway/`·`shared/` 인 변경에 「영향 없음」 이면 이유에 «왜 정본 절이 안 바뀌는가» 를 쓰게 하는 «경고 줄»(막지 않음 · 기록만 · 보드에 보임). 판정·점수 게이트 0.
- ★한계(r2 · DA Q1 후반)★: 두 문은 «카드 완료·Issue 최종 닫기» 때만 돈다 — 카드도 Closes 도 없는 PR 이 바로 merge 되면 기계 검사는 안 돈다. 이것을 «랜딩 전 강제» 라고 주장하지 않는다. 그 PR 의 정본 책임 = 그 PR 을 랜딩한 팀 master(PR 템플릿 정본 줄 · 집행 체크) · 드러나는 길 = 기존 카드 진행/ 잔류·Issue 열림(보드 v421 의 진행 카드·열린 Issue 칸).
- CI 비용(판정 436) 충돌 0: 정본은 같은 PR(코드 CI 1회에 포함) · 정본만 고치는 PR 은 paths-ignore 로 CI 0 · 열린 PR 에 문서만 따로 push 0(planner 방송 규칙 그대로).

### 2-4. 비교 (부하·메모리)
| 안 | 쓰는 손 | 강제 | 부하 | 메모리 | 닫는 사건 | 실패 계보 |
|---|---|---|---|---|---|---|
| ★가(추천)★ 같은 PR · 나노가 정본 diff · 문 2곳 diff 검사 | 구현 나노 | ft-index-move + issue-close-check 사실 검사 | git diff 1회 · gh 1회(문마다) | 0 | 정본 파일이 랜딩 diff 에 있음 | 없음(좌석 추가 0) |
| 나 정본 전담 좌석 부활(팀별 arch-canon) | 상시 좌석 | 쪽지 + 좌석 처리 | 좌석 상시 1~7 · 쪽지 | claude 상주 프로세스 | 좌석이 처리 표시 | ★FB_ARCHDOC 계보 그대로(#0~#11 · 지금 죽어 쪽지 10 미읽음)★ · pm·HELM 상시 좌석 실패와 같은 꼴 |
| 다 랜딩 뒤 master 가 CLOSEOUT 에서 정리 | master | closeout-policy 규율 | 낮음 | 0 | 사람 규율 | master=집행(내용 쓰기 0) 규칙 위반 · 정본이 PR 뒤로 밀림(G1 과 같은 지연) |

## §3 오빠 결정 필요 (planner 컨펌 때 1문 3안)
- **정본을 누가 쓰나**: ①구현 나노가 같은 PR 에서(팀 arch 검토 · 추천) ②팀마다 정본 전담 좌석(arch-canon 부활) ③랜딩 뒤 master 가 CLOSEOUT 때.
- **하네스 문서 브랜치(G4)**: ①랜딩 단위마다 main 으로(추천) ②ops/main-base 유지하고 주기 병합.

## §4 나노 배분 (컨펌 뒤 · 순서)
1. ft-index-move 정본 diff 검사 + 쪽지 수신자 = 팀 `_arch`(R37 카드와 같은 파일 — R37 뒤 또는 합침).
2. ft-issue-close-check 6항 «정본» + 시험(픽스처 JSON) · ISSUE-TRANSITIONS §3 표 1행.
3. `.github/PULL_REQUEST_TEMPLATE.md` 에 정본·Closes 자리(문서 · CI 0).
4. 하네스 ops/main-base → main 정리(master 집행 · 카드 밖 · 충돌은 문서 줄만).
- 기존 열린 빈 곳 정리(카드 밖 · 각 팀): #792 닫기 판단(issues master) · loom 진행/ 카드 이동 · FB_ARCHDOC#11 명부 은퇴 표시(master).

## §5 DA 질문 (sol low · 10분 1회 · bounded)
- Q1 «같은 PR 안 정본 diff + 문 2곳 사실 검사» 가 G1~G5 를 닫는가 — 남는 우회 경로 1개(있으면).
- Q2 「정본 갱신: X」 diff 검사가 정본 «내용» 이 맞는지까지는 못 본다 — 이 한계를 arch 판정서 1줄(정본 diff 확인)로 두는 것이 충분한가, 아니면 새 원인.
- Q3 arch-canon 좌석을 살리지 않는 결정이 closeout-policy·completion_discipline 과 충돌하는가.

## §6 r2 교정 (DA r1 HOLD-L1 · design/teams/harness/DA-landing-canon-440-20261008.md §2)
### 6-1. 정본 증거 = 실제 랜딩 commit 과 그 확정 범위 (로컬 브랜치 diff 는 증거 아님)
- S = 실제 랜딩 commit(main 에 들어간 sha). 확정 범위 R(S) = `S^1..S`(squash·merge 둘 다 «첫 부모 → S» · ff 랜딩이면 랜딩 전 main tip T 를 ft-land 출력에서 받아 `T..S`). ★merge-base 계산 0★(정상 랜딩 뒤 S 가 main 조상이면 빈 구간 — DA 재현 83c96ba15a).
- 검사 ①`git merge-base --is-ancestor S origin/main`(fetch 후 · 아니면 REJECT 「랜딩 안 됨」) ②`git diff --name-only R(S)` 에 X 포함(아니면 REJECT 「랜딩 commit 에 정본 X 없음 — 로컬에만 고친 것」) ③(Q2) arch 판정서의 확인 줄 `정본 diff 확인: X §Y @<C>`(C = arch 가 검토한 candidate sha) 와 `git rev-parse C:X == S:X`(blob 같음 · 다르면 REJECT 「검토 뒤 정본이 바뀜 — 재검토」).
- 「정본 영향 없음」 카드는 ①만(랜딩 sha 실재) — 이유 ≥10자 유지.
### 6-2. arch 확인 줄 (Q2 수락 조건)
- 판정서에 `정본 diff 확인: <X> §<Y> @<candidate sha> — <무엇이 바뀌었나 1줄>`. 경로 존재가 아니라 «검토한 절·변경 1줄» · candidate sha 에 묶임 → 뒤 HEAD 에 옛 확인 줄이 붙으면 6-1 ③ 에서 blob 불일치로 걸린다. DA 는 내용 정확성을 인증하지 않는다(arch 책임).
### 6-3. 부분 PR 과 Issue
- 큰 Issue 의 부분 PR = 본문 `Refs #N` + PR 본문 정본 줄(그 단위의 정본 변경) · Closes 없음은 오류 아님. Issue 6항(정본)은 «최종 닫는 사건» 때 1번 — 값은 부분 PR 들의 S 목록(`@S1,S2`) 허용 · 각 S 에 6-1 ①②.
### 6-4. CLOSEOUT (Q3 수락 조건)
- 「본문 재서술 0」 = 제품 아키텍처 내용을 CLOSEOUT 에 복제하지 않는다는 뜻 · closeout-policy 2항 필수 필드(골 원문 · 축 상태·닫는 증거 sha · 배포 브랜치·sha·로컬 검증 · 나중에 볼 것 · 다시 여는 법)는 전부 유지 · 정본은 그 필드 안에서 절 링크@S 로 가리킨다.
### 6-5. master 가 검증할 가짜 fixture (나노 시험 · DA 지정 4)
| fixture | 기대 |
|---|---|
| 카드 브랜치엔 X 수정 · 랜딩 S 에는 코드만 | ② REJECT |
| 정상 squash S(X 포함) · S 가 main 조상 | 통과(빈 구간 false REJECT 0) |
| arch 확인 C 뒤 코드 후속 HEAD 에서 X 재수정 → 랜딩 S | ③ REJECT(blob 불일치) |
| 부분 PR(Refs #N · Closes 0) 2개 → 최종 Issue 닫기 6항 `@S1,S2` | 부분 PR 단계 경고 0 · 최종 닫기에서 ①② 각각 |
