# 인덱스: gh 가드에 PR 쓰기 5종 차단 추가 + Tank 래퍼 pr-edit·pr-close (R6 ②)
<!-- ledger: design/teams/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 6-b(오케 개선요청 접수·협의). 핵심 한 줄: 원장 R6 ② — arch#5 사후 검토 #58408 「안 막히는 PR 쓰기 5종」 · 안 design/teams/harness/PLAN-r6b-pr-write-guard-20261007.md · master#10 승인 #60270(리뷰 approve/request-changes 는 대체 없이 차단 — 사람만).

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
가드 `scripts/harness-install/fable-team/templates/hooks/gh-issue-author-guard.sh`(홈 `~/.claude/hooks/` 사본과 지금 같은 바이트)는 Bash 명령을 토막(segment)으로 나눠 `violation()`(199행)에서 판정한다. gh 쓰기가 «작성자가 남는 쓰기»면 종류 author 로 exit 2 하고, 안내문(242–244행)에 Tank 래퍼 명령을 보여 준다. 리포 범위 검사 `scoped()` 가 있어 SecondWindStudio/ 리포만 막는다(개인 리포 통과). PR 쪽은 222행 `gh pr comment` 하나만 막는다. 그래서 `gh pr review` 판정·코멘트, `gh pr close -c`, `gh pr edit --body/--title`, `gh api …/pulls/N…` 쓰기, `gh api graphql` mutation 은 사람 계정 이름으로 남는다. 래퍼 `scripts/fable-team-bin/ft-gh-as-tank.sh`(+ 키트 사본 같은 바이트)는 동작별로 gh 인자 배열 CMD 를 만들고, 기본 dry-run(출력만) · `--apply` 면 Tank 토큰으로 실행한다. Issue `edit`(15–18행)은 수정 «전» 원문을 보관하고, 보관에 실패하면 수정 0 이다. 시험 `tests/harness/test_gh_as_tank.sh` 는 PATH 맨 앞 가짜 gh 로 GitHub 호출 0 이고, `block`/`pass` 도우미(151–152행)를 쓴다.

## 사전검증
- 소환: 아니오
- 면제: 기존 author 차단 규약·안내문·범위 검사를 그대로 쓰고 분기만 넓힌다. 래퍼 두 동작은 Issue edit/close 를 PR 판으로 복제한다. 되돌림 1커밋 revert. 최종 DA 는 완성 이동 때 1회. — arch 서명 byz-harness-arch-claude#7

## 조사 근거
- `scripts/harness-install/fable-team/templates/hooks/gh-issue-author-guard.sh:222` PR 분기(comment 만) · 110행 `api_is_issue_write` · 199행 `violation` · 242–244행 안내문.
- `scripts/fable-team-bin/ft-gh-as-tank.sh:15` Issue edit 보관 규약(15–18행) · 32행 usage · 9–23행 동작 목록.
- `tests/harness/test_gh_as_tank.sh:151` block/pass 도우미 · 159행 이후 차단 목록.

## 구현 범위 (이 셋만 — 닫힌 목록)
1. **가드 템플릿** `scripts/harness-install/fable-team/templates/hooks/gh-issue-author-guard.sh`:
   - 222행 PR 분기를 넓힌다(종류 author · 사유 문자열 `gh pr <동사>`).
     - `comment` — 지금처럼 차단.
     - `review` — `--approve`·`--request-changes`·`--comment`·`-b`/`--body`/`-F`/`--body-file` 중 하나라도 있으면 차단.
     - `close` — `-c`/`--comment` 가 있을 때만 차단. 코멘트 없는 close 는 통과.
     - `edit` — `--body`/`-b`/`--body-file`/`-F`/`--title`/`-t` 가 있을 때만 차단. label·reviewer·assignee 만이면 통과.
   - `api_is_issue_write` 옆에 `api_is_pr_write(method, has_body, path)` — `repos/O/R/pulls/N` 의 PATCH, `repos/O/R/pulls/N/(comments|reviews)` 와 그 하위의 POST·PATCH(본문 있음) → author.
   - `gh api graphql` — `-f`/`-F`/`--field`/`--raw-field` 의 `query=` 값이 공백을 뺀 뒤 `mutation` 으로 시작하면 author. query 는 통과.
   - 5행 머리 주석·242–244행 안내문 동작 목록에 `pr-edit|pr-close` 추가 + 「PR 리뷰 판정은 사람만 — 래퍼 대체 없음, 코멘트는 pr-comment」 1줄.
2. **래퍼** `scripts/fable-team-bin/ft-gh-as-tank.sh`(+ 키트 `scripts/harness-install/fable-team/bin/ft-gh-as-tank.sh` 같은 바이트):
   - `pr-edit <번호> [--title T] [--body-file F]` — Issue `edit` 와 같은 검증·보관 규약. 보관은 `gh pr view <번호> --json title,body` · 파일명 `pr<번호>-<UTC>.body.md`/`.title.txt` · 같은 폴더 · 보관 실패면 수정 0 · exit 1 · 성공 출력 끝 `bak=` + 되돌림 1줄.
   - `pr-close <번호> [--comment <본문파일>]` — CMD=`(pr close <번호> -R $REPO [--comment "<파일 내용>"])`. `gh pr close` 에는 파일 인자가 없으므로 래퍼가 파일을 읽어 문자열로 넘긴다. 파일이 없으면 exit 2(need_file).
   - 머리 주석 동작 목록·usage(32행)에 두 동작 추가. 다른 동작 출력 무변화.
3. **시험** `tests/harness/test_gh_as_tank.sh`:
   - block 추가: `gh pr review 5 --approve` · `gh pr review 5 --comment -b x` · `gh pr close 5 -c bye` · `gh pr edit 5 --body x` · `gh pr edit 5 --title t` · `gh api -X PATCH repos/SecondWindStudio/byz-agents/pulls/5 -f body=x` · `gh api repos/SecondWindStudio/byz-agents/pulls/5/comments -f body=x` · `gh api graphql -f query='mutation { x }'`.
   - pass 추가: `gh pr close 5` · `gh pr edit 5 --add-label x` · `gh pr review 5`(플래그 없음 = 대화형 · 좌석은 못 씀 — 통과로 둔다) · `gh api graphql -f query='query { x }'` · 개인 리포 `gh pr edit 5 --body x -R yoonhwan/p`.
   - 래퍼 dry-run: pr-edit 제목만/본문만/둘 다 3줄 · pr-close 코멘트 있음/없음 2줄 · pr-edit --apply 보관 실패 시 STUB_LOG 에 `pr edit` 0건.

커밋은 자기 브랜치, **push 금지**. **금지**: 홈 `~/.claude/hooks/**` 쓰기(설치는 master) · 리뷰 판정 대체 동작 추가 · 범위 검사·main 보호 분기 변경 · 기존 차단·통과 사례의 기대값 변경.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_gh_as_tank.sh` rc=0 · `bash tests/harness/test_kit_bin_sync.sh` rc=0 · 래퍼 두 사본 `cmp` 동일 · 가드·래퍼 `bash -n`(가드 python 블록은 `python3 -c 'import ast'` 로 구문 확인) OK.
- RESULT 에 가드 차단 안내문 실제 출력 1개(`gh pr edit 5 --body x`) + 래퍼 dry-run 2줄(pr-edit · pr-close) 복붙.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개): `세트: <40hex> · 시험: bash tests/harness/test_gh_as_tank.sh rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖): 홈 가드 cp + cmp + 실측 1회(`gh pr edit 1 --body x` 가 차단 메시지) · 라이브 RT 래퍼 단독 cp.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 03223aff5f5eeb0bf310d716029886894962d79f (spawn 2026-10-07)
- base: PR 874 병합 뒤 최신 origin/main(master 지시 · ★874 병합 전 spawn 금지★).
- 2026-10-07 — 대기/ 생성 (byz-harness-arch-claude#7 · 원장 R6 ② · 승인 #60270).
- 정본 영향 없음: 하네스 가드 템플릿·래퍼·시험만 — docs/architect 제품 정본 변경 없음
- 2026-10-07 22:09 — 대기→진행 · 좌석 byz-harness-nano-r6b-pr-write-guard#0
- 2026-10-07 — 증거(나노 byz-harness-nano-r6b-pr-write-guard#0 · 골 축 6-b 원장 R6 ② · arch#7 재현):
  - 코드 변경 4파일: 가드 템플릿(PR 분기 comment·review·close -c·edit 본문/제목 · api_is_pr_write · graphql mutation · 안내문) · ft-gh-as-tank.sh 추적본+키트(pr-edit 원문 보관 · pr-close) · tests/harness/test_gh_as_tank.sh.
  - arch 실측(가드 직접 호출): `gh pr edit 5 --body x`·`gh pr review 5 --approve`·graphql mutation → rc=2 / `gh pr close 5`·`gh pr edit 5 --add-label x`·graphql query·개인 리포 `-R yoonhwan/p` → rc=0.
- 세트: fb18b3a37006fa74c78e8fe1ee107c2b83915ef0 · 시험: bash tests/harness/test_gh_as_tank.sh rc=0 · 이슈: 0
- 추가 시험: bash tests/harness/test_kit_bin_sync.sh rc=0 (ALL PASS) · 래퍼 두 사본 cmp 동일 · 가드·래퍼 bash -n OK
- 정본 영향: 하네스 gh 가드 템플릿·Tank 래퍼·시험만 — docs/architect 제품 정본 변경 없음 · 홈 가드 설치(cp+cmp+실측 1회)·라이브 RT 래퍼 cp 는 master 집행.
- 2026-10-07 22:13 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§38
