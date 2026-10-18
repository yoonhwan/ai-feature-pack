# PLAN — R23 Tank 래퍼 쓰기 경로를 REST 하나로 (arch#8 안 · 2026-10-08)

## 골 원문 (GOAL-harness.md 복붙)
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

골 축: 6-b(오케 개선요청 접수·협의) · 닫는 증거 = REQUEST-LEDGER R23 행 + 반영 sha. 요청: planner#7 #60677 → master#11 #60687.

## 결론
**수정 승인.** 「GraphQL 실패 시 REST 폴백 분기」 대신 **쓰기 경로를 REST(`gh api`) 하나로 바꾼다.** 폴백이 없으니 #0 규칙(조용한 폴백 금지)과 부딪힐 자리가 없다. 실패하면 경로가 하나라 원인도 하나다. 단 #879 실패 원인은 아직 모른다 → **착수 전 0단계로 원문 1줄을 먼저 잡는다**(아래).

## 이유 3줄
1. 폴백 분기는 동작마다 두 길(gh CLI·REST)을 만들어 코드와 시험이 두 배가 되고, 「언제 넘어가나」(어느 오류 문구에서) 판정기가 생긴다. 한 길이면 둘 다 없다.
2. 래퍼 쓰기 10종(create 제외 9종) 전부 REST 에 같은 동작이 있다 — **pr-create 도 GraphQL 전용이 아니다**(REST `POST /repos/{o}/{r}/pulls`). 래퍼는 이미 REST 를 쓴다(토큰 주인 `gh api user` · head 브랜치 · PR 작성자 확인 — `scripts/fable-team-bin/ft-gh-as-tank.sh:138·166·173`).
3. REST 응답이 JSON 이라 pr-create 의 URL 정규식 해석(`ft-gh-as-tank.sh:170–172`)이 필요 없어진다 — 응답의 `html_url`·`number`·`user.login` 을 바로 쓴다.

## 0단계 — 원인 1줄 (착수 전 · master/issues master 집행)
- 실측(arch#8 · 읽기만 · Tank 토큰): GraphQL `viewer` 정상(byz-tank) · `gh issue view 879` 정상 · REST `GET issues/879` 정상 · #879 는 BYZ Board 항목(projectItems 1 · Tank 토큰으로도 읽힘). → «지금» GraphQL 이 죽어 있지는 않다. 8회 실패가 일시 장애인지 #879 고정 원인인지 모른다.
- 8회 실패의 오류 원문은 우편함·bodies 에 없다(grep 0). ★다음 #879 close 시도 1회를 `GH_DEBUG=api` 로 돌려 응답 원문(요청 mutation 이름 + errors[].message + type)을 남긴다★.
- ~~그 시도를 REST 로 직접~~ — ★무효(정정 10-08)★: 좌석이 직접 치는 `gh api -X PATCH …/issues/N` 은 gh-issue-author-guard 가 막는다(`tests/harness/test_gh_as_tank.sh:200`). 0단계는 기존 래퍼 + `GH_DEBUG=api` 로만.
- ★0단계 결과(issues#2 #60703 · master#11 #60706)★: #879 는 래퍼(GraphQL)로 00:3x 닫힘 · 8회 실패 = 10-07 15:11~15:14Z GitHub 쓰기 일시 장애(오류 id DEA0:1CAB3E:7CBB7:A02FC:6AC66125 · comment·close·label 전부) · 재현 불가 → **R23 보류**(재발 시 카드 r23-tank-rest-path 그대로 spawn).

## 1. 폴백 형태 (질문 1 답)
폴백을 두지 않는다. 쓰기는 REST 한 길 · 실패면 `REJECT gh api <METHOD> <경로> 실패: <원문>` exit 1(지금과 같은 꼴). 출력 성공 줄은 그대로 `OK as=byz-tank <동작> <번호> — <URL>`.

## 2. 동작별 REST 대응 (질문 2 답 — 전부 «된다»)
| 래퍼 동작 | 지금(gh CLI · GraphQL) | REST |
|---|---|---|
| comment · pr-comment | `gh issue/pr comment` | `POST /repos/{r}/issues/{n}/comments` `-F body=@파일` (PR 도 issues 경로) |
| close (`--reason`) | `gh issue close` | `PATCH /repos/{r}/issues/{n}` `-f state=closed -f state_reason=completed\|not_planned` |
| reopen | `gh issue reopen` | 같은 PATCH `-f state=open` |
| close·reopen·pr-close 의 `--comment` | gh 가 내부에서 코멘트 후 상태 변경(2단계) | 같은 2단계: comments POST → PATCH. ★PATCH 실패면 「코멘트는 올라감 <URL> · 재시도는 --comment 없이」 를 REJECT 문구에 넣는다(중복 코멘트 방지)★ |
| label `--add` | `gh issue edit --add-label` | `POST /repos/{r}/issues/{n}/labels` `-f 'labels[]=a'` … |
| label `--remove` | `gh issue edit --remove-label` | 라벨마다 `DELETE /repos/{r}/issues/{n}/labels/{이름}`(이름은 URL 인코딩 · 없는 라벨 404 = 실패로 보고) |
| edit · pr-edit | `gh issue/pr edit` | `PATCH /repos/{r}/issues/{n}` · `PATCH /repos/{r}/pulls/{n}` `-f title=… -F body=@파일` |
| edit 보관용 원문 읽기 | `gh issue/pr view --json title,body`(GraphQL) | `GET /repos/{r}/issues/{n}` · `GET /repos/{r}/pulls/{n}` `--jq '{title,body}'` (body 가 null 이면 빈 문자열로 저장 — 지금 python 검사의 `isinstance(b,str)` 를 null 허용으로) |
| pr-close | `gh pr close` | `PATCH /repos/{r}/pulls/{n}` `-f state=closed` |
| pr-create | `gh pr create` | `POST /repos/{r}/pulls` `-f title -F body=@파일 -f head -f base` → 응답 `html_url`·`number`·`user.login` 으로 작성자 확인(별도 GET 불요) |
| create | `ft-issue-create-pair.sh` 의 `gh issue create`(GraphQL) | ★이번 범위 밖★ — 다른 스크립트(마커·매니저 알림 규약). 같은 증상이 나면 별건 R 로. |

## 3. 시험 · 나노 범위 (질문 3 답)
- 재현: 기존 `tests/harness/test_gh_as_tank.sh` 의 가짜 gh(PATH 맨 앞 · 38행)를 쓴다. 가짜 gh 가 `issue`·`pr` 하위 명령을 받으면 `GraphQL: Something went wrong while executing your query` + exit 1 을 내게 해 «GraphQL 이 죽어도 래퍼가 성공한다»(= gh CLI 하위 명령을 한 번도 안 부른다)를 본다. `api` 는 인자를 로그에 적고 각 경로에 맞는 JSON 을 낸다.
- 시험 칸: dry-run 7줄(`test_gh_as_tank.sh:47–53`)의 기대 문자열을 REST 꼴로 바꾸고, --apply 경로는 가짜 gh 로그로 「METHOD + 경로 + 필드」 를 대조. close+comment 에서 PATCH 실패 → 문구에 「코멘트는 올라감」 · exit 1. label remove 404 → exit 1. edit 의 body null → 보관 성공. pr-create 응답 user.login ≠ byz-tank → exit 1.
- 나노 1석 · 파일 2개(추적본 `scripts/fable-team-bin/ft-gh-as-tank.sh` + 키트 사본 같은 바이트) + 시험 1개. ★파일이 182줄이라 200줄 한도 근처★ — CMD 배열 대신 `API=(METHOD 경로 필드…)` 배열 하나로 바꾸면 줄 수는 비슷하다. 넘으면 REST 호출 조립만 `ft-gh-as-tank-rest.sh`(source 전용)로 뗀다.
- 금지: GraphQL 경로를 남겨 두고 실패 시 넘어가는 분기 · 오류 문구로 판정하는 코드 · 토큰 값 출력.

## 완성 전/후
- 완성 전(하네스 원문 6-b): 0단계 원인 1줄 → 카드 1장(이 안 승인 뒤 arch 작성) → 랜딩 → 라이브 cp(ft-gh-as-tank.sh — 이제 드리프트 검사가 cp 누락을 막는다).
- 완성 후: `ft-issue-create-pair.sh` 의 create 도 REST 로(같은 증상이 실측될 때만).
