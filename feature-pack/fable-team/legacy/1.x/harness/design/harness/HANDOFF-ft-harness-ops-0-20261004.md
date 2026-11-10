# HANDOFF — ft-harness-ops#0 → #1 (2026-10-04 · 컨텍스트 401k 증류)

## ★골 원문 3줄 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

★승계 첫 일 = 골 대조 보고★: 위 원문을 읽고 「아래 열린 단위 각각이 골의 어느 줄·어느 닫는 증거(GOAL-harness.md 표 A/B/C)인가」를 planner(현역 byz-planner-arch#N — `.fable-team/seats-harness.json` 의 `_hil_route`)에 3줄로 보고한 뒤에만 착수.

## 내 자리
- 세션 ft-harness-ops#0 · 워크트리 .worktrees/harness-ops · mbox = /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh · 보고 3줄(경로+sha+남은 일)·[HIL] 은 `_hil_route`(지금 byz-planner-arch#3) · AskUserQuestion 금지(mbox [HIL])
- persona = Keymaker+Architect — Slack 채널·yoonhwan 봇·hermes 역할 파일·channel_prompts·토큰·미러 launchd 의 «지속 설정 관리» 소유(오빠 16:3x)

## 완료 (main 에 있음)
| 단위 | 증거 |
|---|---|
| 첫 단위(축 B R1~R3 · 축 C RELEASE-0.1 · 축 A 모니터) | PR #802 dedceb2ba6 · #804 f38294ffac · #806 03368493dd · #807 d0000ef095 |
| Slack 미러 설계 | PR #811 9e50e6750a |
| D1 mbox send 사본 mailbox.log.jsonl | PR #812 db18f53a9a · 라이브 mbox.py 복사 16:37:56 (백업 .bak-20261004-d1) |
| 미러 키트 + 사람 말 3줄 + 스레드 | PR #814 **a37e9773dc**(CI 빨강 2잡 면제 — 오빠 값 a) · 라이브 launchd pid 73454 |
- 라이브 미러: launchd `com.hermes.byz-mbox-slack-mirror` · 스크립트 ~/.hermes/scripts/{byz_mbox_slack_mirror,mirror_lib,mirror_summary}.py(main 과 sha 같음) · 토큰 ~/.hermes/secrets/yoonhwan_bot.env(600) · state ~/.hermes/state/byz_mbox_slack_mirror.byz.json · 로그 ~/.hermes/logs/byz_mbox_slack_mirror.{out,err} · 채널 #byz-planner C0C6MJGRR89 · 멘션 U0AC2JF0M7D · 점검법 = `bash scripts/fable-team-bin/harness-monitor.sh` + Slack history

## 열린 단위 (착수 순서)
1. **ⓔ GitHub→Slack 미러 구현** — 판정 완료(D5 = #byz-planner 같은 이슈 스레드에 합치기 · D6 = 열림·닫힘·머지·hil:needed 4종만). 정본 = DESIGN-slack-mirror.md §10(PR #815 — **아직 머지 전일 수 있음 · main 확인**). 구현 계획: ①`mirror_deliver.py`(Deliverer + flock 공유 (키→thread_ts) 맵 `<state-dir>/byz_slack_threads.<channel>.json` · **작성됨 · 미커밋 → feat/github-mirror 브랜치 커밋 참조**) ②mbox 미러를 Deliverer 로 이전(옛 state 의 threads 는 `seed_threads` 로 이관) + 테스트 갱신 ③`byz_github_slack_mirror.py`(issues?state=all&sort=updated&since= + ETag 304 · state-diff · baseline = 현재 open 전부 기록 · 별도 launchd `com.hermes.byz-github-slack-mirror`) ④가짜 GitHub·Slack 시험 + 변이 ⑤install.sh 확장 ⑥라이브 실측. 시험 helper(FakeSlack)는 tests/scripts/test_byz_mbox_slack_mirror.py 안에 있음 → `_slack_fakes.py` 로 빼서 공용화.
2. **라이브 하네스 bin = main 1:1 (Issue #816 · 설계 PR #818 DESIGN-live-bin-sync.md)** — 판정: 순서 뒤집기(라이브→main 채택 → 설치) 승인 · D8·D9 전부 채택 · **D7(FT_BIN 루트 이동)은 ⓪~② 증거 뒤 [HIL] 재판정**. **DA 1회 진행 중**: codex exec(gpt-6.1-sol · low · headroom)이 백그라운드 실행 — 결과 파일 /private/tmp/claude-501/-Users-yoonhwan-Project-Agent-BYZ-Work-BYZ-Agents--worktrees-harness-ops/dbda6986-6c61-450e-b348-4b6c5109de04/scratchpad/da-livebin-out.md (없으면 같은 폴더 da-livebin-run.log 확인 · 프롬프트 da-livebin-prompt.md 로 재실행 가능). 결과에 따라 설계 수정 → ⓪ 채택 PR(파일별 방향 판정표 필수 · ft-pm-tick.sh 는 추적본이 새로움) → ① 설치 스크립트 → ② 드리프트 검사 → ③ [BLOCK] → ④ README 3줄.
3. 대기 중인 남의 몫: #805(cached_tokens)는 PR #808 로 이미 머지됨 · #813(mbox.sh 추적본≠라이브)은 #816 ⓪ 에 포함되므로 중복 처리 금지.

## 함정 (실측)
- mbox send 본문/인자에 백틱 + `mbox.sh` 가 같은 줄이면 훅이 명령 전체 차단 — 본문은 파일(Write 도구)로 쓰고 `--body-file`/relay. gh 호출은 `unset GH_TOKEN` 먼저.
- `rm -rf`·`git push --force-with-lease` 는 block-destructive 훅이 차단(HIL). 임시 파일 정리는 안 한다 — 스크래치패드에 둔다. 로컬 브랜치를 origin/main 으로 되감은 뒤에는 새 브랜치 이름으로 push.
- `ft-role-spawn.sh` 는 v65 전용: 루트 seats.json 의 현역 DA 행에 `_replaced_by` 를 쓰고 `ft-v65-da-codex#N` 이름을 만든다 → **harness 팀에서 실행 금지**(dry-run 으로 확인). DA 는 `codex exec -s read-only -c model=gpt-6.1-sol -c model_reasoning_effort=low -o <out> "$(cat prompt)" < /dev/null` 일회성으로.
- Serena: 시작 훅이 엉뚱한 워크트리를 활성화함 → `initial_instructions` 로 session_id 받은 뒤 `activate_project(<harness-ops 절대경로>)`. `.serena/project.yml` 이 매번 변경됨 → 커밋 전 `git restore`.
- main CI 의 Python Test·Web Test 는 main 자체 빨강(면제 · issue-manager 가 Issue 등록). 새 PR 도 같은 두 잡만 빨강이면 면제 근거는 오빠 값 (a).
- 라이브 bin 실측: 팀이 실행하는 도구(FT_BIN)는 v6-realtime-live 워크트리의 gitignored 사본 38개 — main 과 같음 24·다름 10·main 에 없음 4. main→라이브 복사 금지(라이브가 대체로 최신).

## 열린 PR (머지 판정 대기)
#815(ⓔ 설계) · #818(라이브 bin 설계) — 머지는 오빠/planner 판정 뒤 내가 squash.
