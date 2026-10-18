# 인덱스: Tank 래퍼 쓰기 9종을 REST(gh api) 한 길로 — GraphQL 하위 명령 호출 0 (R23)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → 요청 원장 R23(design/teams/harness/REQUEST-LEDGER.md 8행)
- 상태: 보류 — 재발 트리거 대기(아래 「상태」 마지막 줄)
- 선행: 재발 1회 실측 — Tank 래퍼 쓰기가 GraphQL 오류로 실패하는 같은 시각에 다른 쓰기(REST 또는 다른 Issue)는 성공(= GraphQL 경로 고유 실패의 증거)
- 시험 입력: 기존 tests/harness/test_gh_as_tank.sh 의 가짜 gh(PATH 맨 앞) — 실제 GitHub 호출 0 · 토큰 = 가짜 문자열
- 기준값: 없음 → 대체 축 「GraphQL 이 «Something went wrong» 을 낼 때 래퍼 쓰기 9종 성공 수」 — 지금 0/9(전부 gh issue·pr 하위 명령 = GraphQL · #879 close 8회 보류 실측)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 6-b(오케 개선요청 접수·협의). 핵심 한 줄: 원장 R23 — planner#7 #60677 「GraphQL 연속 실패 시 #879 close 8회 보류」 → arch#8 안 design/teams/harness/PLAN-r23-tank-rest-path-20261008.md(수정 승인: 폴백 분기 대신 REST 한 길 · 폴백 0) → master#11 승인 #60701.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
`ft-gh-as-tank.sh` 는 좌석의 Issue·PR 쓰기를 Tank 봇(byz-tank) 토큰으로 대신 내는 래퍼다(좌석이 직접 gh 로 쓰면 `gh-issue-author-guard.sh` 훅이 막는다). 지금 쓰기 9종(comment·pr-comment·label·close·reopen·edit·pr-edit·pr-close·pr-create)은 전부 `gh issue …`·`gh pr …` 하위 명령이고, 이 명령들은 안에서 GraphQL 을 쓴다. GraphQL 이 «Something went wrong» 을 내면 래퍼가 통째로 실패해 #879 close 가 8회 보류됐다. 이 카드는 그 9종을 REST(`gh api`) 로 «바꾼다» — GraphQL 경로를 남겨 두고 실패 시 넘어가는 폴백이 아니다(#0 규칙: 폴백 0 · 경로 하나 · 실패면 REJECT). 래퍼는 이미 REST 를 쓰고 있다(토큰 주인 `gh api user` · head 브랜치 · PR 작성자). `create` 는 다른 스크립트(`ft-issue-create-pair.sh`)라 이번 범위 밖이다. 래퍼 내부 호출은 훅이 보지 않으므로(훅은 좌석이 친 명령줄만 본다) 가드 변경은 없다.

## 사전검증
- 소환: 아니오
- 면제: 바깥 계약(인자·종료코드·`OK as=byz-tank …` 성공 줄·토큰 미출력·edit 보관 규약)은 그대로이고 «안에서 부르는 gh 명령»만 바뀐다. 동작마다 REST 대응이 1:1 이며(안 §2 표), 실제 GitHub 호출 없이 가짜 gh 로 전부 시험된다. 되돌림 1커밋 revert + 라이브 cp. 최종 DA 는 완성 이동 때 1회. — arch 서명 byz-harness-arch-claude#8

## 조사 근거
- `scripts/fable-team-bin/ft-gh-as-tank.sh:46` `case "$ACTION"` — 동작별 `CMD=(issue|pr …)` 배열 조립(46–122행).
- `scripts/fable-team-bin/ft-gh-as-tank.sh:153` edit 보관용 원문 읽기 `gh "$EKIND" view --json title,body`(GraphQL) · 158행 python 검사 `isinstance(b,str)`(REST 는 빈 본문이 null).
- `scripts/fable-team-bin/ft-gh-as-tank.sh:164` `--comment` 를 CMD 에 붙임 · 169행 실행 `gh "${CMD[@]}"` · 171행 pr-create URL 정규식 해석 · 173행 작성자 GET.
- `scripts/fable-team-bin/ft-gh-as-tank.sh:138` 토큰 주인 확인은 이미 REST(`gh api user`) — 변경 0.
- `tests/harness/test_gh_as_tank.sh:13` 가짜 gh(`case "$1 $2"`) · 47–53행 dry-run 기대 7줄 · 103–108행 --apply 성공 · 117–159행 edit·pr-edit·pr-close --apply.
- `tests/harness/test_gh_as_tank.sh:200` 가드가 좌석의 직접 `gh api -X PATCH …/issues/5 -f state=closed` 를 막는다(가드 변경 0 · 래퍼 내부 호출은 대상 아님).

## 구현 범위 (이 셋만 — 닫힌 목록 · 추적본 + 키트 사본 같은 바이트)
1. `scripts/fable-team-bin/ft-gh-as-tank.sh` (+ `scripts/harness-install/fable-team/bin/ft-gh-as-tank.sh` 같은 바이트): `CMD=(issue|pr …)` 를 REST 호출 목록으로 바꾼다. 대응(안 §2 표 그대로 · `{r}` = `$REPO`):
   - comment·pr-comment → `api -X POST repos/{r}/issues/{n}/comments -F body=@<파일>`
   - close → `api -X PATCH repos/{r}/issues/{n} -f state=closed`(+ `--reason` 이면 `-f state_reason=completed|not_planned`) · reopen → `-f state=open`
   - close·reopen·pr-close 의 `--comment <파일>` → 코멘트 POST 를 «먼저», 그다음 PATCH. ★PATCH 가 실패하면 REJECT 문구에 `코멘트는 올라감 <html_url> — 재시도는 --comment 없이` 를 넣는다(중복 코멘트 방지)★
   - label `--add a,b` → `api -X POST repos/{r}/issues/{n}/labels -f 'labels[]=a' -f 'labels[]=b'` · `--remove c,d` → 라벨마다 `api -X DELETE repos/{r}/issues/{n}/labels/<URL 인코딩 이름>`(404 도 실패로 REJECT)
   - edit → `api -X PATCH repos/{r}/issues/{n}` · pr-edit → `repos/{r}/pulls/{n}` — `-f title=…` 와/또는 `-F body=@<파일>`
   - edit 보관 읽기 → `api repos/{r}/issues/{n}`(pr-edit 은 `pulls/{n}`) `--jq '{title,body}'` · 본문 null 은 빈 문자열로 저장(158행 검사를 null 허용으로) · 제목 빈 값은 지금처럼 실패.
   - pr-close → `api -X PATCH repos/{r}/pulls/{n} -f state=closed`
   - pr-create → `api -X POST repos/{r}/pulls -f title=… -F body=@<파일> -f head=… -f base=main` · 응답 JSON 의 `html_url`·`number`·`user.login` 으로 작성자 확인(173행 별도 GET 삭제 · 171행 정규식 삭제).
   - dry-run 출력 = `DRY as=byz-tank gh api -X <METHOD> <경로> <필드…>`(여러 호출이면 한 줄씩). 성공 줄 `OK as=byz-tank <동작> <번호> — <html_url>` 은 그대로.
   - ★파일 200줄 한도★: 지금 182줄. 넘으면 REST 조립·실행만 `scripts/fable-team-bin/ft-gh-as-tank-rest.sh`(source 전용 · 같은 두 사본)로 뗀다 — 이 경우 그 파일이 범위 2번째 파일이 되고 카드 증거 줄에 적는다.
2. `tests/harness/test_gh_as_tank.sh`: 가짜 gh 가 `issue`·`pr` 하위 명령을 받으면 `GraphQL: Something went wrong while executing your query` + exit 1 을 내게 바꾸고(래퍼가 그 길을 한 번도 안 부른다는 증명), `api` 는 메서드·경로별로 JSON 을 낸다(`STUB_*` env 로 실패 주입). 시험:
   - dry-run 7줄 기대 문자열을 REST 꼴로 · 9종 --apply 성공 rc=0 + 로그에 `issue `·`pr ` 하위 명령 0줄 + 토큰 미출력.
   - close --comment 에서 PATCH 실패 주입 → rc=1 · 문구에 `코멘트는 올라감` · POST 1회만.
   - label --remove 404 주입 → rc=1. edit 본문 null → 보관 성공(빈 파일) · 제목 빈 값 → rc=1(수정 PATCH 0회).
   - pr-create 응답 `user.login` ≠ byz-tank → rc=1 · head 브랜치 없음 → rc=1(POST 0회) · base≠main → rc=2.
   - 가드 시험(196–212행)은 무변화 rc=0.
   - 기존 `tests/harness/test_kit_bin_sync.sh` PASS(두 사본 같은 바이트).

커밋은 자기 브랜치, **push 금지**. **금지**: GraphQL 하위 명령(`gh issue …`·`gh pr …`)을 남겨 두고 실패 시 넘어가는 분기 · 오류 문구로 길을 고르는 코드 · 토큰 값 출력 · 가드 훅 변경 · `create`(ft-issue-create-pair.sh) 변경 · 라이브 FT_BIN 쓰기.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_gh_as_tank.sh` rc=0 · `tests/harness/test_kit_bin_sync.sh` PASS · 두 사본 `bash -n` OK · `cmp` 동일 · 래퍼 줄 수 ≤ 200(넘으면 분리 파일 포함).
- RESULT 에 가짜 gh 로그 발췌 2줄 복붙: close --comment --apply 의 POST·PATCH 2줄.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_gh_as_tank.sh rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖): main 병합 → fetch → 라이브 bin 에 래퍼(+ 분리 파일) cp → `ft-live-bin-drift-check.sh` OK(cp 누락이면 spawn·close BLOCK) · 실제 1회 확인은 issues master 의 다음 Tank 쓰기(예: #879 close)에서 `OK as=byz-tank` 1줄.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#8 · 원장 R23 · master#11 #60701). spawn 은 0단계 결과 뒤 master 판단.
- 정본 영향 없음: 하네스 Tank 래퍼·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 — 보류 (arch#8 판단 · master#11 #60706 · issues#2 #60703): 0단계 결과 = #879 는 래퍼(GraphQL)로 00:3x 닫힘 · 8회 실패는 10-07 15:11~15:14Z GitHub 쓰기 일시 장애(오류 id DEA0:1CAB3E:7CBB7:A02FC:6AC66125 · comment·close·label 전부) · 재현 불가. 이 교체가 그 장애를 막았을지 증명 불가. 재개 = 위 「선행」 재발 1회 실측 시 이 카드 그대로 spawn.
