# 인덱스: SecondWindStudio 리포 정책 훅 — ①리포 범위 검사 ②main 삭제·재작성만 차단 ③Tank 래퍼 pr-create 활성화
<!-- ledger: design/teams/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 6-b(오케 개선요청 접수·협의) · 원문 7. 핵심 한 줄: Tank 봇(byz-tank)이 write 권한을 받았고 무료 플랜이라 서버 쪽 브랜치 보호가 없다 — 오빠 값 「브랜치 삭제 ref 삭제도 가능함. main 삭제 리베이스는 안되도록 main 에만 제한」 대로 main 만 지키고, PR 은 Tank 이름으로 연다. 출처: master 발주 58475 · arch 58408·58437·58473 판정.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
가드 훅 `scripts/harness-install/fable-team/templates/hooks/gh-issue-author-guard.sh`(PreToolUse:Bash · python 으로 명령을 구간 단위로 파싱 · 홈 `~/.claude/hooks/` 에 같은 바이트로 설치됨)는 지금 gh issue 쓰기·gh pr comment·gh api …/issues 쓰기를 리포 구분 없이 막는다 — 홈 settings 라 오빠 개인 리포(yoonhwan 계정 11개)까지 막고, 안내하는 래퍼는 BYZ 에만 있다. 리포는 private 무료 플랜이라 branch protection·rulesets API 가 403(Upgrade to GitHub Pro) — main 을 서버가 못 지킨다. 래퍼 `scripts/fable-team-bin/ft-gh-as-tank.sh` 의 pr-create 는 지금 --apply 시 exit 2(dry-run 전용); 실측으로 Tank 토큰은 PR 생성 인증을 통과한다(없는 head 로 POST /pulls → 422 · 헤더 pull_requests=write). 참고 스펙(코드 복사 금지 · 동작만 참고): 로컬 미push 커밋 `38fc91b9e4`(브랜치 feat/gh-as-tank-pr-create)의 pr-create 부분. 전역 훅 `~/.claude/hooks/block-destructive.sh` 가 이미 모든 git push --force/-f 와 git branch -D 를 막는다 — 이 카드는 그 훅을 건드리지 않는다. 훅 입력 JSON 에는 세션 작업 디렉터리 `cwd` 가 들어온다.

## 구현 범위 (이 셋만 — 닫힌 목록)
1. 훅 `scripts/harness-install/fable-team/templates/hooks/gh-issue-author-guard.sh`:
   ⓐ리포 범위 — 차단 사유가 나온 구간에 대해 대상 리포 owner 를 정해 `secondwindstudio`(대소문자 무시)일 때만 exit 2. owner 결정 순서: `-R/--repo` 인자 → 구간 앞 `GH_REPO=` 대입 → gh api 경로 `repos/<owner>/<repo>/…`(`{owner}` 면 다음) → git push 의 원격 인자(URL 이면 그 URL, 이름이면 `git -C <cwd> remote get-url <이름>`, 생략이면 origin) → 훅 입력 `cwd` 의 origin URL(`[:/]SecondWindStudio/` 매칭 · git 호출 timeout 2초). ★판정 불가 = 통과 + stderr 1줄★(기존 fail-open 관례). 상수 `GUARDED_OWNERS = {"secondwindstudio"}` 하나.
   ⓑmain 보호(새 위반 종류 · 리포 범위 ⓐ 그대로 적용): git push 구간에서 refspec 의 대상(콜론 뒤, 없으면 그 자체 · 앞의 `+` 제거)이 `main` 또는 `refs/heads/main` 이고 [refspec 이 `:` 로 시작(삭제) 또는 `+` 로 시작(강제)] 이면 차단 · `--delete`/`-d` 와 main 대상이 같이 있으면 차단 · `--mirror` 또는 `--prune` 이 있으면 차단(원격 main 을 지우거나 덮을 수 있다). gh api 구간에서 메서드 DELETE 또는 PATCH 이고 경로가 `git/refs/heads/main` 으로 끝나거나 `branches/main` 을 포함하면 차단. `gh repo delete` 차단. ★main 이 아닌 브랜치의 삭제·강제는 이 훅이 막지 않는다★(오빠 값). --force/-f 에 refspec 이 없는 경우는 block-destructive 몫이라 여기선 통과. 차단 메시지 = 「main 삭제·재작성(강제 push·리베이스 후 강제)은 금지 — 오빠 10-07」.
   ⓒ머리 주석에 「차단 범위 = SecondWindStudio 리포 · 판정 불가 = 통과 · main 만 보호」 반영.
2. 래퍼 `scripts/fable-team-bin/ft-gh-as-tank.sh` pr-create `--apply` 활성화: `--base main` 고정(아니면 exit 2) · `--head` 필수 · 생성 전 `gh api repos/$REPO/branches/<head>` 로 원격 실재 확인(없으면 exit 1 · PR 생성 시도 0) · 생성 뒤 PR 작성자가 byz-tank 인지 확인(아니면 exit 1 · URL 출력). dry-run 은 지금처럼 --base/--head 생략 가능. 토큰 값 출력 0 · 폴백 0.
3. 시험 `tests/harness/test_gh_as_tank.sh` 케이스 추가(가짜 gh · 임시 git 리포를 mktemp 로 만들고 origin 지정 · 실제 GitHub 호출 0):
   리포 범위 — ⓐcwd=SecondWindStudio + gh issue comment → 2 ⓑcwd=다른 owner → 0 ⓒcwd=git 아님 → 0 ⓓcwd 다른 owner + `-R SecondWindStudio/byz-agents` → 2 ⓔcwd SWS + `-R yoonhwan/x` → 0 ⓕ`GH_REPO=SecondWindStudio/byz-agents gh issue comment` (cwd 다른 owner) → 2 ⓖ`gh api repos/yoonhwan/x/issues/1/comments -f body=y` (cwd SWS) → 0.
   main 보호(cwd SWS) — 차단 2: `git push origin :main` · `git push origin +main` · `git push origin +HEAD:main` · `git push origin --delete main` · `git push origin -d refs/heads/main` · `git push --mirror origin` · `git push --prune origin` · `gh api -X DELETE repos/SecondWindStudio/byz-agents/git/refs/heads/main` · `gh api --method PATCH repos/SecondWindStudio/byz-agents/git/refs/heads/main -F force=true` · `gh repo delete SecondWindStudio/byz-agents --yes`. 통과 0: `git push origin main` · `git push origin HEAD:main` · `git push origin --delete feat/x` · `git push origin :feat/x` · `git push origin +feat/x` · `gh api -X DELETE repos/SecondWindStudio/byz-agents/git/refs/heads/feat/x` · cwd 다른 owner 에서 `git push origin :main`.
   pr-create — dry-run 출력 · `--apply --base dev` → 2 · `--apply` head 없음 → 2 · 가짜 gh 가 branches 조회 실패 → 1(pr create 호출 0) · 가짜 gh 가 작성자 다른 값 → 1.
   기존 케이스는 cwd 를 SWS 원격 임시 리포로 주도록 맞춰 전부 통과.
커밋은 자기 브랜치, **push 금지**. **금지**: `~/.claude` 수정(홈 설치는 ops) · block-destructive.sh 수정 · PR 쓰기 명령 확장(pr review·pr close -c·pr edit·pulls API·graphql — 다음 단위) · 실제 GitHub 호출(--apply 실행 포함) · 토큰 값 출력.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_gh_as_tank.sh` fail=0(기존 + 위 신규 전부) · 훅·래퍼 `bash -n` OK · 변경 파일 = 위 3개뿐.
- RESULT 에 실측 표(케이스 · 기대 rc · 실제 rc) 1장.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 78d6fee6114b31a862e06dbfddf1eb4c02b83e66 (spawn 2026-10-07)
- base: PR 841(feat/gh-as-tank) 병합 뒤 최신 origin/main — 훅 템플릿·래퍼가 그 PR 에서 처음 들어온다.
- 2026-10-07 — 대기/ 생성 (byz-harness-arch-claude#5 · master 발주 58409 → 58475 로 범위 확장 · 이전 슬러그 gh-guard-repo-scope 대체).
- 정본 영향 없음: 하네스 훅 템플릿·래퍼·시험만 수정 — docs/architect 제품 정본 변경 없음
- 2026-10-07 12:01 — 대기→진행 · 좌석 byz-harness-nano-gh-guard-scope-main-prcreate#0
- 세트: 374d70ae11652d995fe40a1f3f2da8a67c890629 · 시험: bash tests/harness/test_gh_as_tank.sh rc=0 · 이슈: 0
- 2026-10-07 12:09 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§23
