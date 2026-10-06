# ORDER — P11 사실 수집 (ft-harness-arch#4 → ft-harness-nano#1 · 2026-10-06 · 읽기 전용)

> 골 원문(GOAL-harness.md 복붙):
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
> 정말 많은 양의 이슈와 테스트, 그리고 큰 병렬적인 메인 플랜(메인 기획)을 얼마나 잘 수행해내느냐에 핵심이 달려 있는 거예요. 지금 이 골(Goal)들은 그 세부 항목들을 다 잘 처리해서, 결국엔 그 루트인 큰일을 얼마나 별개로 쪼개서 동시에 아주 잘 해결하느냐에 달려 있는 거죠. 이게 기획에 반영되어야 해요.
> 골의 축: 표 A(모니터·오빠 요청 → Issue) · 표 B(접수·협의) · 원문 7. 이 발주 = 상위 ORDER-github-issue-driven-20261006.md 할 일 1·2·3 의 사실.

## 규칙 (HARD)
- **읽기 전용**: `gh` 는 `list`·`view`·`api GET` 만 · 설정 변경 0 · 커밋 0(ops).
- **시크릿 0**: 토큰·webhook·채널 ID 값 0. 경로·변수 이름·개수만.
- 줄마다 **[사실] 출처**(명령 그대로 또는 `파일:줄`) · 못 보면 **[추측]**.
- 산출 1장: `design/harness/issue-improvement/FACTS-P11-20261006.md` · 끝나면 mbox 로 arch 에 「완료 · 줄 수 · [추측] 수」 3줄. 상한 10분 · 명령 출력 40줄씩. 선행 사실은 `FACTS-P10-20261005.md` 재사용(중복 조사 금지).

## 1. 입력 경로 4종의 현재 실재
```bash
cd /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops; unset GH_TOKEN
ls .github/ISSUE_TEMPLATE/ 2>/dev/null; cat .github/ISSUE_TEMPLATE/config.yml 2>/dev/null | head -20
gh issue list --state all --limit 60 --json number,title,author,labels,createdAt | python3 -c "import json,sys,collections;d=json.load(sys.stdin);print(collections.Counter(i['author']['login'] for i in d));print(collections.Counter(l['name'] for i in d for l in i['labels']).most_common(30))"
gh api repos/:owner/:repo/collaborators --jq '.[].login' 2>&1 | head -20
gh api repos/:owner/:repo --jq '{private,has_issues,permissions}'
grep -rln "gh issue create" design/ scripts/ .fable-team/ 2>/dev/null | head -20
```
적을 것: ①Issue 템플릿·폼 유무 ②등록 작성자 분포(오빠·세션 에이전트·사내 멤버 구분 가능한 근거) ③협업자 수·역할(이름 대신 개수) · 사내 멤버가 Issue 를 올릴 권한/알림 경로 ④세션이 `gh issue create` 를 쓰는 실례 경로 목록.

## 2. 임시 기획 세션 → issue-manager 인계 경로
```bash
grep -rn "issue-manager\|임시 마스터\|기획 세션" design/harness/issue-improvement/SPEC-roles-mission-flow-20261005.md design/harness/issue-improvement/DESIGN-harness-composition-20261005.md | cut -c1-200 | head -20
ls /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/ | head -40
```
적을 것: 오빠가 임의로 연 기획 세션이 정리본을 issue-manager 에 넘기는 현행 경로가 있나(mbox·파일·명령) · 없으면 [사실: 없음].

## 3. 완주(시험·정본화·워크트리/브랜치 정리) 현행
```bash
git worktree list | wc -l; git branch -r | wc -l; ls .worktrees | wc -l
ls scripts/ | grep -iE 'wt|worktree|clean|sweep' ; grep -rn "wt-clean\|wt-sweep\|nano-close" design/harness/issue-improvement/SPEC-full-flow-20261005.md | cut -c1-180 | head -10
ls design/*/CLOSEOUT* 2>/dev/null | head -10
```
적을 것: 워크트리·원격 브랜치 수 · 정리 도구 목록 · 누가 어느 단계에서 호출하는지(삭제 HIL 지점 표시) · CLOSEOUT 정본 실례 수.
