# REQ — 하네스 구성 실측 요청 (ft-harness-arch#0 → ft-harness-nano#1 · 2026-10-05)

> 골 원문(GOAL-harness.md 복붙):
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
>
> 골의 축: 축 A(모니터) 의 «현재 구성 지도» · 발주 = `ORDER-harness-composition-20261005.md` nano 행. Slack 은 읽지 않는다.

## 규칙
- **읽기 전용**. 수정·kill·launchd·gh write 0. `gh` 는 워크트리에서 `unset GH_TOKEN` 뒤 실행.
- 산출 = `design/harness/issue-improvement/FACTS-composition-20261005.md` (tracked · 커밋은 ft-harness-ops#1 에 요청). 항목마다 **명령 1줄 + 결과 수치 + 예시 1~2개**. 사실/추측 분리. «0» 은 어느 명령에서 본 0 인지.
- 표는 짧게. 긴 원본 출력은 `design/harness/issue-improvement/facts-raw/` 에 파일로 두고 경로만.

## 실측 항목 (8)

### F1. 좌석 명부 ↔ 실재
- `tmux ls -F '#{session_name} #{session_created}'` 전 세션(29 예상) · 각 세션 pane pid 의 자식 프로세스 1줄(`pgrep -P <pane_pid> -l`) → 에이전트 종류(claude/codex/opencode/없음).
- 각 세션이 `.fable-team/seats-*.json`(seats · harness · issues · planner · kk · cfo) 어느 파일에 행으로 있나 · 없으면 «명부 밖».
- 명부 쪽: 파일별 행 수 · `status` 값 어휘와 건수(stop-ready/stopped/closed/active/…) · 행은 있는데 tmux 세션 없는 수.

### F2. 팀별 키트 차이
- `.fable-team/bin-{cfo,harness,issues,kk,planner}/*-env.sh` 의 변수 집합을 표로(행=변수, 열=팀). 빠진 변수에 X.
- 공용 bin `.worktrees/v6-realtime-live/.fable-team/bin/`: 전체 파일 수 · `.bak*` 수 · 실 스크립트 수. 실 스크립트 중 `grep -l 'v6-realtime-live\|/seats.json\|v65-\|ft-v65-'` 로 **v65 경로·이름이 하드코딩된 파일 목록**(= 다른 팀·머신에서 그대로 못 쓰는 것) vs `FT_SEATS_JSON`/`FT_NANO_PREFIX` 등 env 를 읽는 파일 목록.
- `~/.claude/skills/fable-team/scripts/` 와 위 공용 bin 의 **같은 이름 파일** 목록 + 내용 동일 여부(`cmp`).

### F3. tick · launchd
- `launchctl list | grep -i 'byz\|ft-\|hermes\|tick'` → 라벨 · pid · 마지막 exit. plist 경로(`~/Library/LaunchAgents/*.plist` 중 해당).
- 어느 팀에 tick 이 있고 없는지(seats 파일 `_doc`/`tick` 필드 또는 bin-* 의 `ft-tick-*.plist`).

### F4. GitHub Issue 체계 (실측 · H13·H14 검증)
- `gh label list --limit 100` → 라벨 전체(이름·건수).
- `gh issue list --state all --limit 300 --json number,title,state,labels,createdAt,closedAt,assignees,milestone` → 총수 · open/closed 수 · `status:*` 라벨 분포(needs-triage 몇 건) · `team:*` 분포 · 마일스톤 유무 · **closed 중 PR 로 닫힌 수**(`gh pr list --state merged --limit 150 --json number,title,body,mergedAt` 본문의 `Closes #N`/`Fixes #N` 추출 → 그 N 이 실제 closed 인지).
- 최근 14일 생성 Issue 의 «생성자»(사람 vs 좌석 gh) 구분 가능하면 건수.
- 상태 전이 규칙이 적힌 파일이 있나: `grep -rl 'needs-triage' design/ docs/ .github/ scripts/ 2>/dev/null`.

### F5. issue-manager 흐름
- `ls design/issues/` · `GOAL-issues.md` 머리 10줄 · 출범(③) 흐름을 적은 문서 경로와 그 절 5줄 이내 인용.
- `.fable-team/comm/mailbox.log.jsonl`(+`.1`) 에서 `from` 이 `ft-issue-manager#` 인 행 수 · `to` 별 건수 상위 5 · 본문에 `#8[0-9][0-9]` 가 있는 행 수(= Issue 번호가 붙은 발주).
- `seats-issues.json` 의 `_persona_pool_nano` 내용 요약(몇 개 · 모델).

### F6. mbox 흐름 전체(통신 부하 실측)
- `mailbox.log.jsonl`(+`.1`): 총 행 · 첫/마지막 ts · 최근 7일 일별 건수 · `from→to` 상위 10 쌍 · 본문 첫 줄 `[HIL]` 행 수 · `relay`(bodies 경로 포함) 행 수 · `to` 가 `byz-planner-arch#` 인 행 수.
- `tools/comm-canonical/mbox.py` 머리 주석(LIFO·ring 상한·consume-on-read) 인용 5줄.

### F7. 멀티 머신 현황
- `gh issue view 816 --json title,state,body` · `gh issue view 818 --json title,state,body` → 제목·상태·본문 요약 3줄(라이브 bin 1:1 이 무엇인지).
- `ls scripts/harness-install/` 전체 · `design/harness/RELEASE-0.1.md`·`RELEASE-0.2.md` 의 「반영됨 <machine> <sha>」 행 전부 인용.
- 머신 이름이 문서에 몇 번 나오나: `grep -rio 'jarvis\|hermes(로컬)\|loom\|c2c\|mac mini\|macmini' design/harness design/planner docs/rules 2>/dev/null | cut -d: -f2 | sort | uniq -c`.
- `ls ~/.tmuxc/` · `ls ~/.tmm/` 상위 1단(파일명만).

### F8. 워크트리·나노 상한(정리 경로 실재)
- `git worktree list | wc -l` · 접두별 건수(`v65-`·`kk-`·`harness-`·`issues-`·기타).
- `ft-nano-slots.sh` 가 읽는 상한 변수 이름과 기본값(파일 머리 grep) · 팀별 env 에 그 변수가 있나.

## 회신
mbox 3줄: 「FACTS 경로 · F1~F8 중 못 한 항목과 이유 · 사실/추측 비율」. 커밋은 ft-harness-ops#1 에 요청(경로 지정 add).
