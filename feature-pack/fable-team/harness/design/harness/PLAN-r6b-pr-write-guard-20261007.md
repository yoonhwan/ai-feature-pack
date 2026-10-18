# PLAN — R6 ② PR 쓰기 5종 가드 확장 (arch#7 안 · 2026-10-07 · 인계 열린 일 6)

## 골 원문 (GOAL-harness.md 복붙)
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

골 축: 6-b(원장 R6 ② — arch#5 사후 검토 #58408 「채택 · 다음 단위」).

## 결론
**승인 — 가드에 PR 쓰기 5종을 «author» 종류로 추가 + 래퍼에 대체 동작 2개(pr-edit · pr-close).** 나노 1장(가드 템플릿 + 래퍼 + 시험). 홈 가드 설치는 랜딩 뒤 master cp(키트 = 홈 지금 같은 바이트 · 실측).

## 실측
- 가드 `gh-issue-author-guard.sh`(홈 = 키트 템플릿 바이트 같음 · 255행)의 `violation()`: PR 쪽은 `gh pr comment` 하나만 author 차단. 통과 목록(5행)에 pr create/merge/checkout/diff/view.
- 안 막히는 5종(R6 ②): `gh pr review --comment|--approve|--request-changes -b` · `gh pr close -c` · `gh pr edit --body|--body-file|--title` · `gh api …/pulls/N/(comments|reviews)` 쓰기 · `gh api graphql` mutation.
- 래퍼 `ft-gh-as-tank.sh` 동작: create · comment · pr-comment · pr-create · label · edit(Issue · 원문 보관) · close · reopen. PR 수정·닫기 동작 없음.

## 이유 3줄
1. PR 본문·리뷰·닫기 코멘트도 «작성자가 남는 쓰기»라 Issue 와 같은 규칙(Tank 이름) 밖에 있으면 안 된다 — 지금은 사람 계정 이름으로 조용히 남는다.
2. 막기만 하고 길이 없으면 우회가 생긴다 → 막는 3종(edit·close·리뷰 코멘트)은 래퍼 대체를 같이 준다. 리뷰(approve/request-changes)는 Tank 가 할 일이 아니라 대체 없이 막고 안내문을 `pr-comment` 로 보낸다.
3. 범위 검사(SecondWindStudio/ 리포만 · R6 ①)는 이미 있다 → 개인 리포 오탐 0.

## 카드 범위 (승인 뒤 arch 가 대기/ 카드로 씀)
1. 가드 템플릿 `violation()`: `pos[0]=="pr"` 분기를 넓힌다 — `comment` · `review`(본문·판정 플래그가 있을 때 · 순수 조회 플래그는 없음) · `close`(`-c`/`--comment` 있을 때만 · 코멘트 없는 close 는 통과) · `edit`(`--body`/`--body-file`/`--title` 있을 때 · label·reviewer 만이면 통과). `api_is_issue_write` 옆에 `api_is_pr_write`(…/pulls/N 의 PATCH · …/pulls/N/comments·reviews 의 POST) · `gh api graphql` 에 `-f query=` 값이 `mutation` 으로 시작하면 author 차단. 안내문에 래퍼 대체 명령 1줄씩.
2. 래퍼: `pr-edit <번호> [--title] [--body-file]`(Issue edit 과 같은 원문 보관·보관 실패 시 수정 0) · `pr-close <번호> [--comment-file]`. 머리 주석·usage 갱신 · 다른 동작 무변화.
3. 시험: 기존 `tests/harness/test_gh_as_tank.sh` 의 block/pass 목록에 5종 × (차단 사례 · 통과 사례 1개씩: 코멘트 없는 close · label 만 edit · 조회 graphql) + 래퍼 dry-run 2동작.

## 열린 값 (master 판단 · 오빠 값 불요로 봄)
- PR 리뷰 approve 는 사람(오빠)만 한다는 전제로 «대체 없이 차단» — 다르면 master 가 되돌려 줌.

## 닫는 증거
나노 랜딩 sha + test_gh_as_tank rc=0 + 홈 가드 cmp 1줄 + 설치 뒤 `gh pr edit 1 --body x` 가 실제 차단되는 1회 실측.
