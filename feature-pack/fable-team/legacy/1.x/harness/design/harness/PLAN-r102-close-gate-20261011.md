# PLAN — R102 이슈 닫기 게이트 (원인 확정 · 같은 증상 보류 · 관찰 중) · arch#28 · 2026-10-11

골 원문(GOAL-harness):
「내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.」
「하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.」「메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.」
골의 축: 개선요청 접수·협의 + 업그레이드·커밋·push·반영 — 요청 원장 R102 (판정 1059 · 발주 ORDER-r102-close-gate-design-20261011.md).

## 0. 실측 (설계 근거 · 2026-10-11 21:2x)

| 사실 | 값 |
|---|---|
| #922 닫힘 경로 | ClosedEvent actor=byz-tank · closer=없음(PR 아님) 08:46:04Z → Reopened 12:14:58Z — ★Tank 래퍼 `close --apply` 로 닫힘★ |
| 래퍼 close 게이트 | origin/main `scripts/fable-team-bin/ft-gh-as-tank.sh`(199줄) close 분기 = 인자 검사뿐 · close-check 호출 0 |
| close-check 위치 | 6항 정본 = origin/main `ft-issue-close-check.sh`(83줄) · 라이브 `<루트>/.fable-team/bin/ft-issue-close-check.sh` = main 과 diff 0 · 전이표상 «close 뒤» 사후 검사(S4→S5 · ISSUE-TRANSITIONS §1) |
| 6항 정본 문서 | `design/teams/harness/ISSUE-TRANSITIONS.md` §3 + `.github/PULL_REQUEST_TEMPLATE.md` 「완료 6항」 |
| issues master 래퍼 설치 | 세션마다 `git show origin/main:scripts/fable-team-bin/{ft-gh-as-tank.sh,…}` → scratchpad 추출(HANDOFF-issues-master r3·r4) |
| 라벨 | `status:observing` 없음(status:* 13개 실측) |
| 이 워크트리 | ops/main-base 는 origin/main(e9cef9a6ed) 뒤 — ★구현 나노는 origin/main 기준★ |

즉 구멍은 둘: ①닫는 6항에 «원인 확정»·«같은 증상 보류» 칸이 없다 ②래퍼 close 가 아무 검사도 안 하고 닫는다(검사는 닫은 뒤). 이 설계는 둘 다 닫는다.

## 1. 닫는 항목 6 → 8 (설계 1)

닫는 코멘트에 두 줄을 더한다(줄 모양은 1~6항과 같다 · `<…>` 자리표시는 미기재):

| 항 | 줄 | 통과 | 관찰 중으로 |
|---|---|---|---|
| 7 원인 확정 | `원인 확정: Y — <근거 ≥10자>` | Y + 근거 10자 이상 | `원인 확정: N — <이유>` |
| 8 같은 증상 보류 | `같은 증상 보류: 0` | `0` | `같은 증상 보류: <경로>[, <경로>]` (0 이 아닌 값) |

- ★여러 코멘트에 있으면 «마지막 줄»이 이긴다★(1~6항은 «어디든 있으면» 그대로) — 수리 뒤 새 닫는 코멘트의 Y·0 이 옛 N·보류를 덮는다.
- ★r2(DA F1): 선택이 먼저, 검증이 나중★ — 키 정규식 `^\s*[-*]?\s*(\[[ xX]\]\s*)?원인 확정\s*[:：]`(8항도 같은 꼴)로 값과 상관없이 «가장 마지막 줄»을 고른 뒤 그 줄만 검증한다. 마지막 줄이 비었거나 `<…>` 거나 근거 미달이면 «빈 칸» — 앞의 옛 Y·0 으로 내려가지 않는다(기존 `canon_lines` 는 무효 줄을 먼저 버리므로 재사용 금지 · 별도 함수). `--extra-comment` 파일이 «가장 마지막» 코멘트다.
- 줄이 없거나 Y 근거 10자 미만 = 빈 칸.
- ★r2(DA F1 · 발주서 15행 「두 칸이 비었거나 N/보류 있음이면 … 거절 → 관찰 중」 그대로): 빈 칸도 N·보류와 똑같이 거절 + 관찰 중★. 빈 칸 rc 1 따로 두지 않는다. 실수로 빈 칸을 낸 경우의 해제는 planner 값(라벨 해제 · §3)뿐.
- 고칠 정본 문서: `ISSUE-TRANSITIONS.md` §3 표 2행 + 제목 「완료 6항」→「완료 8항」 · `.github/PULL_REQUEST_TEMPLATE.md` 「완료 6항」→「완료 8항」 2줄 + 1줄: «원인 미확정·같은 증상 보류가 있으면 `Closes #N` 대신 `Refs #N`»(PR 병합 자동 close 경로 차단 — §5 한계 ①).

## 2. 래퍼가 닫기를 거절 → 관찰 중 (설계 2)

### 2-1 변경 파일 (코드 3 + 미러 · 시험 1 + 픽스처)

| 파일 | 변경 | 줄 |
|---|---|---|
| `scripts/fable-team-bin/ft-issue-close-check.sh` | ①7·8항 함수 `pick_last_line`(키만으로 마지막 줄 선택 → 검증 · §1 r2) ②`--gate`(7·8항+관찰 조건만 · 1~6항·Closes 생략 · rc 0 통과 / 3 거절) ③`--extra-comment <파일>`(곧 올릴 닫는 코멘트를 JSON 코멘트 «맨 끝»에 붙여 함께 읽음 · jq) ④gh view 필드에 `labels` 추가 ⑤관찰 상태 판정 함수(§3) ⑥gh view = `timeout 7` + 재시도 1(실패 rc 2) | 83 → ~150 |
| `scripts/fable-team-bin/ft-issue-close-gate.sh` (신규) | 래퍼 close 전 호출 · close-check `--gate` → rc 0 통과 · rc 3 이면 거절 + (apply 면) §2-3 쓰기 순서 · 쓰기 실패 rc 1(fail-closed) · 조회 실패 rc 2 | ~90 |
| `scripts/fable-team-bin/ft-gh-as-tank.sh` | ★1줄★ — case 블록 뒤·dry-run 분기 앞(origin/main 기준 case 끝 `esac` 바로 뒤): `[ "$ACTION" = close ] && [ "$REASON" != "not planned" ] && { bash "$HERE/ft-issue-close-gate.sh" "$NUM" "${COMMENT_FILE:-}" "$APPLY" \|\| exit $?; }` | 199 → 200 |
| `scripts/harness-install/fable-team/bin/` 위 3파일 | 같은 commit 미러(cmp 0) | — |
| `tests/harness/test_issue_close_gate.sh` (신규) + `tests/fixtures/issue_close/gate-*.json` + 가짜 쓰기 스텁 `tests/harness/stubs/fake-tank.sh` | §4 | — |
| 기존 픽스처 `closed-with-6items-canon.json`·`closed-with-6items-no-impact.json`·`closed-partial-two-sha.json` | PASS 기대 픽스처에 7·8 줄 추가(규칙이 바뀌었으므로 · 기대값 무변경) | — |

- 게이트는 dry-run 에서도 돈다(읽기만) — dry-run 은 REJECT 문장 + «apply 면 할 쓰기» 목록만 출력.
- 래퍼 1줄 위치 검증(DA r1 F3 확인): completed·기본 reason close = 게이트 · not-planned close·label·comment·reopen·edit = 게이트 안 탐.
- 래퍼 1줄로 200줄 = BYZ 180줄 리팩터 트리거 이미 초과(현 199). ★이 단위는 1줄만 넣고, 래퍼 분할 + 래퍼 자체 gh 호출 7초 룰 적용은 별도 [structure] 카드로 master 에 제안★(수술적 · 행위·구조 커밋 분리).

### 2-2 거절 메시지 (stderr · 그대로 · 모두 rc 3)

- 빈 칸·무효: `REJECT close #<N> — 7항 「원인 확정」/8항 「같은 증상 보류」 마지막 줄이 비었거나 무효(<어느 항>) → 닫지 않고 «관찰 중»(status:observing). 실수면 planner 값으로 라벨 해제 뒤 다시.`
- N·보류: `REJECT close #<N> — 원인 확정=<Y|N> · 같은 증상 보류=<값> → 닫지 않고 «관찰 중»(status:observing). 닫는 조건 = 오빠 폰에서 서로 다른 판(sha) 2회 재현 0 — 코멘트에 「관찰: 판=<40hex> · 결과=재현 0 · 판정=<번호>」 2줄(판이 서로 달라야 함).`
- 관찰 중·미달: `REJECT close #<N> — 관찰 중 · 재현 0 판 <k>/2 (<sha 앞 10자 목록>) — 서로 다른 판 <2-k>회 더.`
- 관찰 중·재현 있음: `REJECT close #<N> — 관찰 중 재현 있음(판 <sha 앞10>) — 수리 랜딩 뒤 「관찰 시작: … · 수리 랜딩=<40hex>」 로 새 관찰을 연다.`
- 관찰 중·마커 없음(라벨만): `REJECT close #<N> — status:observing 인데 「관찰 시작:」 줄 없음 — 복구 쓰기 재시도.`
- 쓰기 실패(rc 1): `REJECT close #<N> — 거절 기록 쓰기 실패(<단계>) · 이슈는 열린 채 · 같은 명령을 다시 실행하면 이어서 복구한다.`

### 2-3 거절 시 쓰기 (rc 3 + `--apply` 일 때만 · 게이트가 래퍼를 다시 부른다 · ★순서 고정 · fail-closed★)

관찰 상태의 원천 = ★코멘트의 「관찰 시작:」 마커★(라벨은 표시). 마커가 하나라도 있으면 라벨이 없어도 관찰 중이다.

1. ★거절된 닫는 코멘트 보존(DA r1 F2)★ — `--comment` 파일이 있으면 그 본문을 머리줄 `[닫기 거절 · R102 · token=<UTC ts>-<N>]` 을 붙여 `comment` 로 게시. 안에 있던 「관찰: … 재현 있음」 같은 사실이 이슈에 남는다(다음 close 가 옛 2판 PASS 로 통과하지 못함).
2. 마커 — 이슈 전체(+extra)에 「관찰 시작:」 줄이 하나도 없을 때만 게시: 
   ```
   관찰 시작: <UTC ISO> · 사유: <빈 칸|원인 확정 N|같은 증상 보류 <값>> · token=<UTC ts>-<N>
   닫는 조건: 오빠 폰에서 서로 다른 판(sha) 2회 재현 0
   기록 칸(issues master 가 오빠 값을 받을 때마다 1줄):
   관찰: 판=<40hex> · 결과=재현 0|재현 있음 · 판정=<번호>
   ```
3. 라벨 — `label <N> --add status:observing`(이미 있으면 생략 · 멱등).

- 실패 처리: 1·2 가 실패하면 그 뒤 단계 0 · rc 1 · 이슈는 열린 채(닫힘 0 = fail-closed). 3 만 실패하면 마커가 이미 있으므로 관찰 중은 성립 · rc 1 + 다음 close 시도가 라벨을 다시 붙인다.
- ★7초 룰(DA r1 F3)★: 쓰기 1회 = `timeout 7 bash ft-gh-as-tank.sh <동사> … --apply`(래퍼 안의 `gh api user` + 쓰기 둘을 한 7초 상한으로 묶음) + 재시도 1.
- ★결과 불명 중복 방지★: 재시도 «전»에 close-check 의 gh view(7초+1)로 그 단계의 `token=` 이 이미 게시됐는지 확인 → 있으면 재시도 생략. 라벨은 멱등이라 확인 없이 재시도.
- ★token 단계 구분(DA r2 F2-b · r3 APPROVE)★: token 은 단계별로 구분 — `token=<UTC ts>-<N>-keep` · `-marker` (라벨은 멱등이라 token 없음).
- 재귀 호출 동사(comment·label)는 게이트를 다시 타지 않는다 · 토큰·작성자 확인은 래퍼 그대로.
- 거절 뒤 exit 3 — 이슈는 열린 채.

`status:observing` 라벨은 설치 때 1회 생성(§6 ③).

## 3. 관찰 중 → 닫는 조건과 값 기록 칸 (설계 3)

- 관찰 중 = 「관찰 시작:」 마커 1개 이상 ∨ 라벨 `status:observing`. (라벨만 있고 마커 0 = 2-2 «마커 없음» 거절 + 복구 쓰기.)
- ★pending(DA r2 F2-b · r3 APPROVE #75885)★: 관찰 중 원천에 «미완료 거절 기록»을 더한다 — `[닫기 거절 · R102 · token=…]` 머리줄 코멘트가 1개라도 있고 그 뒤 유효 마커가 없으면 «관찰 대기(pending)» = 관찰 중과 같게 취급 → 새 Y·0 close 거절 + 마커 복구 쓰기. 회귀: 보존 성공→마커 실패→(같은 입력 재시도 / 다른 입력 Y·0) 둘 다 rc 3 + 마커 1개.
- 값 기록 칸 = 이슈 코멘트 줄 `관찰: 판=<40hex> · 결과=재현 0|재현 있음 · 판정=<번호>` (issues master 가 planner 의 오빠 값 판정을 받아 Tank `comment` 로). `판정=` 은 숫자 필수(출처 — #7 RULE). 닫는 코멘트(extra) 안의 `관찰:` 줄도 같은 줄로 센다(보존 단계 1 과 일치).
- ★관찰 구간(epoch · DA r1 F2 + r3 APPROVE #75885)★: 유효 마커 = ①첫 「관찰 시작:」 마커 ②그 뒤 마커 중 `수리 랜딩=<40hex>` 가 붙고 (가)그 sha 가 `cat-file` 실재 + `FT_LAND_REF`(기본 origin/main) 조상 (나)앞선 모든 마커의 sha 와 다름 (다)앞 구간 수리 sha(있으면)가 새 sha 의 조상(더 새 랜딩) (라)현재 구간에 `결과=재현 있음` 1줄 이상 — 넷 다 맞는 것만. 구간 = 마지막 유효 마커 뒤. 그 밖의 마커(중복 게시·같은 수리 sha 재게시·옛 sha 재사용·재현 없는 새 마커)는 구간을 «옮기지 않는다».
- 새 구간을 여는 손 = issues master 가 수리 랜딩 sha 를 받아 `comment` 로 `관찰 시작: <UTC> · 수리 랜딩=<40hex>` 1줄(명시적 epoch). 래퍼·게이트는 수리 랜딩 마커를 쓰지 않는다.
- 통과 = 구간 안에서 ①`결과=재현 있음` 0 ②`결과=재현 0` 줄의 판이 서로 다른 것 2개 이상 ③각 판 = 40hex + `git cat-file -e <sha>^{commit}`(fetch 0 · 없으면 「git fetch 후 다시」 — 6항 정본 검사와 같은 규약).
- ★관찰 중인 이슈는 7·8항이 나중에 Y·0 이 되어도 위 관찰 조건을 요구한다★(#922 교훈: 폰 PASS 1회로 닫지 않는다). 해제는 planner 값이 있을 때만(라벨 제거 + 해제 코멘트 `관찰 해제: 판정=<번호>` — 게이트는 마지막 유효 마커보다 뒤에 이 줄이 있으면 관찰 중이 아니다).
- 관찰 조건 통과로 닫을 때 닫는 코멘트의 7·8항은 사실대로(N·보류 그대로 허용 — 관찰이 대신 닫는다).

## 4. 시험 (TDD — 빨강 먼저 · `tests/harness/test_issue_close_gate.sh` · 임시 git 리포 + 픽스처 · 실 gh 호출·Issue 쓰기 0)

- 조회: env `FT_CLOSE_CHECK_FROM_JSON=<상태 파일>` 이면 close-check 가 `--from-json` 으로 그 파일을 읽는다.
- 쓰기: env `FT_TANK_WRAPPER=<스텁>` 이면 게이트가 래퍼 대신 스텁을 부른다. 스텁 `fake-tank.sh` = 호출을 로그에 1줄 남기고 ★상태 파일(JSON)에 코멘트·라벨을 실제로 추가★(GitHub 흉내) · env `FAKE_FAIL=<단계>`(실패) · `FAKE_TIMEOUT_AFTER_WRITE=<단계>`(써 놓고 rc 124 = 결과 불명).

| # | 입력 | 기대 |
|---|---|---|
| ① 빈 칸 거절 | 1~6항만 · dry-run close | 래퍼 rc 3 · 「비었거나 무효」 문장 · 할 쓰기 목록(보존·마커·라벨) · close 출력 0 |
| ①b 옛 유효 → 최신 무효 | 옛 코멘트 `원인 확정: Y — 근거…` · 최신 extra `원인 확정: <근거>` | rc 3(옛 Y 로 내려가지 않음) |
| ② 보류 거절 | Y + `같은 증상 보류: design/graphics/CLOSEOUT-g922-wave-mobile-20261011.md` | rc 3 · 「관찰 중」 문장 |
| ③ 정상 통과 | Y(10자+) + 보류 0 · 관찰 이력 0 | gate rc 0 · 래퍼 「DRY as=byz-tank gh issue close 9000 …」 rc 0 |
| ④ 관찰 2판 통과 | 마커 + 관찰 2줄(임시 리포 sha 2개 · 재현 0) · 7항 N | rc 0 |
| ⑤ 관찰 상태·실패·재시작(스텁 apply) | (a) 마커+옛 PASS 2판 + extra 에 「재현 있음」 → rc 3 · 상태 파일에 보존 코멘트 추가 · 다음 close(extra 없음) 도 rc 3 (b) `FAKE_FAIL=comment-marker` → rc 1 · 라벨 호출 0 · 닫힘 0 (c) `FAKE_FAIL=label` → rc 1 · 마커 있음 · 재실행 시 마커 재게시 0 + 라벨 붙음 (d) 재시작: 마커 있는 상태에서 거절 반복 → 마커 1개 유지 (e) `FAKE_TIMEOUT_AFTER_WRITE=comment-marker` → 재시도 전 token 발견 · 마커 1개 (f) 재현 있음 뒤 새 수리 sha(main 조상 · 앞 수리의 후손) 마커 → 구간 리셋 · 수리 랜딩 없는 마커 / 같은 수리 sha 재게시 / 옛 sha 재사용 / 재현 없이 새 마커 → 구간 불변 (j) pending: 보존 성공→마커 실패 뒤 같은 입력 재시도·다른 입력 Y·0 → 둘 다 rc 3 + 마커 1개 복구 (g) 같은 sha 2줄 → rc 3 (h) 라벨만·마커 0 → rc 3 + 마커 복구 쓰기 (i) `관찰 해제: 판정=` 뒤 Y·0 → rc 0 | 각 줄의 기대 |
| ⑥ not-planned | ① 입력 + `--reason not-planned` | 게이트 생략 · DRY close rc 0 |
| ⑦ 회귀 | 기존 `test_issue_close_canon.sh` · `test_gh_as_tank.sh` | 전부 PASS(PASS 픽스처 7·8 줄 추가 뒤) |

발주서의 «시험 3건» = ①②③ · 나머지는 DA r1 F1·F2 와 설계 3을 닫는 추가.

## 5. 한계 · 범위 밖 예외 (기계 검사 밖 · 정본에 적는다)

1. ★범위 밖 예외 ① — `--reason not-planned` close★: 게이트 생략(중복·폐기는 원인 확정 대상 아님). 오용(수리 미완을 not-planned 로 닫기)은 기계로 못 막는다 — 사후 원장 몫.
2. ★PR 병합 `Closes #N` 자동 close — 판정 1060 값② 재오픈★: 래퍼를 안 탄다. 막는 자리 ① PR 템플릿 1줄(«원인 미확정·보류면 Refs»). ② 그래도 자동 close 된 건은 사후 close-check(전체 모드 · S4→S5)가 7·8항 FAIL → issues master 가 그 틱에 `ft-issue-reopen.sh <N>` + §2-3 쓰기(보존 없음 · 마커 → 라벨)로 «관찰 중». 판정 795(자동 close 재오픈 0)는 7·8항 FAIL 건에 한해 1060 이 덮는다(1~6항·Closes 만의 FAIL 은 795 그대로 사후 코멘트). 문서: ISSUE-TRANSITIONS §4 reopen 에 1줄.
3. 닫는 사람이 `원인 확정: Y` 를 거짓으로 쓰면 못 막는다 — 근거 10자 요구 + 사후 DA·재오픈 원장 몫. CLOSEOUT 문서 글자를 기계로 긁는 검사는 넣지 않는다(판정기 금지).
4. 이미 닫힌 옛 이슈의 사후 close-check 는 7·8 MISS 로 FAIL 이 뜬다(읽기 전용 · 영향 0) — issues master 공지 1줄에 적는다.
5. 래퍼 자체의 기존 gh 호출(게이트 밖 동사)에는 7초 상한이 없다 — 이 단위는 게이트가 부르는 쓰기를 `timeout 7` 로 감싸는 데까지. 래퍼 내부 적용은 §2-1 의 [structure] 카드.

## 6. 설치 (DA⑥ 통과 + main 랜딩 뒤 · master 집행)

1. 라이브 bin 백업 + 복사: `cp <루트>/.fable-team/bin/ft-issue-close-check.sh{,.bak-r102-<UTC ts>}` → `git show origin/main:scripts/fable-team-bin/ft-issue-close-check.sh > <루트>/.fable-team/bin/ft-issue-close-check.sh` → `cmp` 0. 같은 방식으로 `ft-issue-close-gate.sh` 신규 복사(백업 대상 없음 · chmod +x).
2. Tank 래퍼는 라이브 bin 사본이 없다(issues master 가 세션마다 origin/main 에서 추출) → issues master 에 mbox 1통: «ft-gh-as-tank.sh · ft-issue-close-gate.sh · ft-issue-close-check.sh 3개 재추출 + chmod(같은 폴더) · 닫는 코멘트 8항 · 관찰 줄·수리 랜딩 마커 모양 · 한계 1·2·4».
3. 라벨 1회: `ft-gh-as-tank.sh label-create status:observing --color FBCA04 --description "관찰 중 — 서로 다른 판 2회 재현 0 뒤 close (R102)" --apply` → `EXISTS` 또는 생성 확인.
4. 확인: 라이브 사본으로 ③ 픽스처 dry-run 1회 rc 0 · ② rc 3.
5. 발행: 하네스 표준 배포 공지(슬랙) + REQUEST-LEDGER R102 처리 칸.

## 7. 순서 · 제약

설계(이 문서 r2) → DA 반박 r2(byz-harness-da-codex#1 · bounded — r2 HOLD 면 중단·3차는 planner 허가) → master: 나노 1좌석 발주(origin/main 기준 · 한 번에 하나: ①시험 빨강 ②close-check ③gate+래퍼 1줄 ④문서 2 ⑤미러) → DA⑥ → 랜딩 → §6 설치.
- graphics#4 의 #922 수리 파일(웹·물결·캔버스) 접촉 0 — 이 단위가 고치는 파일은 위 표뿐. #922 자체 라벨·코멘트도 이 단위에서 건드리지 않는다(다음 닫기 때 게이트를 탄다).
- 외부 호출 = gh view(7초+1) + 거절 apply 때 래퍼 쓰기 최대 3회(각 7초+1 · 재시도 전 token 확인).

## 변경 이력
- r1 (21:3x) → DA HOLD #75853: F1 빈 칸도 관찰 중 · 마지막 줄 선택 후 검증 / F2 거절 입력 보존 · 마커 원천 · fail-closed · 수리 랜딩 epoch / F3 쓰기 7초+1 · 결과 불명 중복 방지 · 범위 밖 예외 명시.
- r2 = 위 셋 반영(§1 r2 줄 · §2-1~2-3 · §3 epoch · §4 ①b·⑤ · §5 1·2·5).

- r2 → DA HOLD #75868(2회째 · bounded 중단): F1·F3 닫힘 · F2-a(같은 수리 sha 마커 재게시로 구간 이동) · F2-b(보존 성공·마커 실패 뒤 Y·0 통과) 남음.
- r3 초안 = F2-a·F2-b 고칠 문장만 §2-3·§3 에 «r3 초안(DA 미검토)» 줄로 추가 · 3차 DA 는 planner 허가 뒤.
- 판정 1060(planner): 값① 3차 DA 1회(F2-a·F2-b 문장만 · 10+10분 · 다시 HOLD 면 arch Fable 5.1 로 r4) · 값② 자동 close 7·8 FAIL = 재오픈+관찰 중 → §5-2 반영.
- r3 → DA APPROVE #75885(설계 한정 · 구현 시험 PASS 아님): r3 문장을 §2-3·§3 정본 줄에 합침 · r2 epoch 문장과 §4 ⑤(f) 기대를 r3 로 교체 · ⑤(j) pending 회귀 추가. 최종본.
