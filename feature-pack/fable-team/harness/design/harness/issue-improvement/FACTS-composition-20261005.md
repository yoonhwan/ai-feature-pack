# FACTS — 하네스 구성 실측 (ft-harness-arch#0 요청 · ft-harness-nano#1 실행 · 2026-10-05)

> REQ 정본 = `design/teams/harness/issue-improvement/REQ-facts-composition-20261005.md` (커밋 20cd3f3c9b) · ORDER = `design/teams/harness/issue-improvement/ORDER-harness-composition-20261005.md` (03597ca902).
> **읽기 전용.** 수정·kill·launchd·gh write 0. **Slack 미접촉.** `gh` 는 `unset GH_TOKEN` 후 실행.
> 원본 출력 = `design/teams/harness/issue-improvement/facts-raw/` (아래 표의 `raw:` 경로). 긴 출력은 파일만 두고 여기엔 수치·예시만.
> 표기: **[사실]** = 이번에 명령을 돌려 나온 값. **[추측]** = 그 값에서 내린 해석(명령으로 확인 안 됨).
> 측정 시점 HEAD = `feat/slack-inbound-820` `705ab1d9c7` · tmux 세션 30 · 머신 = 로컬 yoonhwan 맥.

---

## F1. 좌석 명부 ↔ 실재

**명령**
```
tmux list-panes -a -F '#{session_name}|#{pane_pid}|#{pane_current_command}'   # 전 세션 30
pgrep -P <pane_pid> -l                                                        # pane 자식 1줄
python3 (seats-*.json 6종 파싱)                                               # 명부 대조
```
raw: `F1-session-pane-agent.tsv` · `F1-registry-vs-live.txt` · `F1-schema-agent.txt` · `F1-seats-files.txt`

**[사실] 실재 세션 = 30** (REQ 예상 29 → +1). 에이전트 종류:

| agent | 수 | pane_current_command 예 |
|---|---|---|
| claude | 26 | `2.1.289`×23 · `2.1.288`×2 · `2.1.287`×1 |
| codex (node) | 2 | `ft-harness-da#1`(gpt-6.1-sol low) · `ft-kakao-da#21`(gpt-6.1-sol high) |
| opencode | 1 | `ft-harness-nano#1` |
| shell (none) | 1 | `tmm` |

**[사실] 라이브 30 중 명부(6파일)에 행이 있는 건 9** — 나머지 **21 = 명부 밖**. 행 있음: `FB_CFO#52`(seats+cfo) · `byz-planner-arch#1/#3`(planner) · `ft-harness-ops#0/#1`(harness) · `ft-issue-manager#0`·`repro-e2e#0`(issues) · `ft-v65-arch-claude#155`·`ft-v65-master-claude#136`·`ft-v65-temp-…#0`×2·`ft-v65-tester-claude#13`(seats).
**[추측]** 명부 밖 21 은 별도 트랙(kakao·airag·ccu 등)의 레지스트리가 없거나 이 6파일 밖에 있어서다 — 6파일에 그 트랙 키가 아예 없다.

**[사실] 명부 파일별 행 수** · `role` 어휘(상태 혼재):

| file | rows | role 어휘(건수) |
|---|---|---|
| seats.json | 799 | stop-ready 486 · arch 98 · stopped 56 · master 44 · da 43 · nano 31 · tester 12 · worker 4 · stop 3 · arch-canon 9 · 기타 |
| seats-cfo.json | 102 | stop-ready 30 · stopped 26 · worker 17 · master 13 · architect 6 · closed 3 · da 2 · arch 2 · impl 1 · orch 1 |
| seats-kk.json | 12 | closed 10 · master 1 · nano 1 |
| seats-planner.json | 5 | closed 4 · arch 1 |
| seats-harness.json | 2 | master 2 |
| seats-issues.json | 2 | master 1 · tester 1 |

**[사실] 일관된 `status` 필드는 없다** — 상태가 세 곳에 흩어져 있다: ① `role` 값에 상태를 겹쳐 씀(`stop-ready`·`stopped`·`closed`) ② 플래그 `_replaced_by` ③ 플래그 `_session:"killed"`. seats.json 만 `_closed`/`_stop_ready`/`_stopped_at` 등 40여 개 underscore 플래그를 쓴다(파일마다 스키마 상이).
**[사실] 행은 있는데 tmux 세션 없음**(active = `_replaced_by` 없고 `_session≠killed` 기준): seats.json **186** · seats-cfo **38** · seats-kk **6** · seats-planner **3** · harness/issues **0**. 노이즈 대부분이 `role:"stop-ready"`(정지 보존)다.

---

## F2. 팀별 키트 차이

**명령**
```
for f in .fable-team/bin-{cfo,harness,issues,kk,planner}/*: env var 추출
ls .worktrees/v6-realtime-live/.fable-team/bin/ ; grep -lE 'v6-realtime-live|/seats\.json|v65-|ft-v65-'
cmp ~/.claude/skills/fable-team/scripts/<f> <common>/<f>
```
raw: `F2-env-matrix.txt` · `F2-common-bin-categorize.txt` · `F2-name-collisions.txt` · `F2-team-bin-dirs.txt`

**[사실] `*-env.sh` 는 4팀만**(harness·issues·kk·planner). **cfo 는 env.sh 없음**(`ft-goal-tick-cfo.sh`·`ft-tick.sh`·plist 만). 변수 행렬:

| VAR | harness | issues | kk | planner |
|---|:--:|:--:|:--:|:--:|
| FT_ACTIVE_TAG · FT_BIN · FT_GOAL_LEDGER · FT_IMPL_MODEL · FT_NANO_FEAT · FT_NANO_LEDGER · FT_NANO_LEDGER_WT · FT_NANO_PREFIX · FT_NANO_WT_PREFIX · FT_SEATS_JSON · FT_SEND_FROM | Y | Y | Y | Y |
| FT_REPRO_WT | X | **Y** | X | X |
| FT_GOAL_LINES_FILE · FT_NEWS_TREE · FT_SEATBELT_README | X | X | **Y** | **Y** |

**[사실] 공용 bin = `.worktrees/v6-realtime-live/.fable-team/bin/`**: 파일 67 = **실 스크립트 39 + `.bak*` 28**(+`__pycache__`).
실 스크립트 39 분류: **v65 하드코딩만 14** · **하드코딩+FT_* env 둘 다 7** · **env 만 0** · 둘 다 아님 18.
→ 즉 **39 중 21(14+7)이 `v6-realtime-live`·`v65-`·`/seats.json` 리터럴을 품는다** (= 다른 머신/팀에서 그대로 못 씀). env 를 읽는 건 7개뿐(`ft-index-move`·`ft-nano-close`·`ft-nano-evidence-check`·`ft-nano-slots`·`ft-nano-spawn`·`ft-press-gate`·`ft-seat-status`) — 이 7개도 대부분 하드코딩 폴백을 함께 갖는다.
예: `ft-nano-spawn.sh` — hard Y, env Y · `ft-tick.sh` — hard Y, env N · `ft-send-verified.sh` — hard N, env N.

**[사실] 추적본(`~/.claude/skills/fable-team/scripts/`, 29) ↔ 공용 bin(39) 같은 이름 16개**: `cmp` 동일 **6** · 상이 **10**.

| SAME | DIFF |
|---|---|
| ft-checkpoint · ft-nano-cherry-gate · ft-nano-evidence-check · ft-nano-slots · ft-nano-spawn · ft-press-gate | ft-index-lint · ft-index-move · ft-nano-close · ft-nano-freshness · ft-role-spawn · ft-seat-status · ft-tick-install · ft-tick.plist · ft-tick |

**[추측]** 공용 bin 은 «머신 독립» 이 아니라 «v6-realtime-live 워크트리에 묶인 라이브 사본» 이다 — #816 본문의 「라이브가 추적본보다 최신」 진단과 일치.

---

## F3. tick · launchd

**명령**
```
launchctl list | grep -iE 'byz|ft-|hermes|tick|airag|slack'
ls ~/Library/LaunchAgents/*.plist
find .fable-team -name 'ft-tick*.plist*'
```
raw: `F3-launchctl.txt` · `F3-launchctl-focused.txt` · `F3-plists.txt`

**[사실] `com.byz.ft-tick*` 는 launchctl 에 0건** (grep count = 0) → **tick 데몬은 전부 bootout 상태**. 현재 loaded (byz/hermes/airag 계열):
`ai.hermes.gateway` pid 11187 (last exit 1) · `ai.hermes.gateway-zion` 702 · `ai.hermes.gateway-watchdog` - · `com.hermes.vertex-openai-proxy` 710 · `com.byz.gce-guard-check` exit 2 · `dev.byz.v6-rate-limit-resume*` 3종 · `com.airag.ft-goal-tick` · `com.airag.ft-news-tick` · `com.airag.notify-master-20260928-2200`.

**[사실] tick plist 보유 팀** — 디스크에만 존재(미로드): cfo(`bin-cfo/ft-tick-cfo.plist` + `~/.…/com.byz.ft-tick-cfo.plist`) · kk(`bin-kk/ft-tick-kk.plist` + `com.byz.ft-tick-kakao.plist`) · v65(`com.byz.ft-tick.plist`) · airag(`com.airag.ft-{goal,news}-tick`).
**harness·issues·planner 는 tick plist 자체가 없다** — seats-* `_doc` 도 「틱 없음 — 좌석 자체 10분 모니터」 라고 적는다(harness·issues 확인).
**[추측]** tick 부재 팀은 좌석이 스스로 모니터해야 해서 멈춤 감지가 좌석의 턴에 의존한다(느슨한 결합).

---

## F4. GitHub Issue 체계

**명령**
```
unset GH_TOKEN
gh label list --limit 100
gh issue list --state all --limit 300 --json number,title,state,labels,createdAt,closedAt,assignees,milestone
gh pr list --state merged --limit 150 --json number,title,body,mergedAt
grep -rl 'needs-triage' design/ docs/ .github/ scripts/
```
raw: `F4-labels.txt` · `F4-issues.json` · `F4-issues-authors.json` · `F4-prs-merged.json` · `F4-analysis.txt` · `F4-authors.txt` · `F4-needs-triage-files.txt`

**[사실] Issue = 총 121 (open 93 · closed 28)** — «close 0 건» 아님.
라벨(71종) 상위: `status:needs-triage` **90** · `scope:main` 87 · `phase:pre-completion` 61 · `team:cfo` 47 · `status:blocked-no-seat` 46 · `type:feature` 38 · `team:v65` 34 · `type:agent-ops` 30. status:* 합 158 · team:* 합 103.
**[사실]** `status:needs-triage` **90/121 (74%)** 가 아직 triage 전인 고정 라벨. assignees 보유 Issue **0**. milestone 6종(`K2 K4 M5 M7 goal-outside p90-five`).
**[사실] 생성자 = 121건 전부 `yoonhwan`** (사람 계정). 좌석 gh 도 같은 계정 키링을 쓰므로 **사람 vs 좌석 생성 구분 불가**. 최근 14일 생성 **93**.
**[사실] merged PR 150개 분석 → 본문 `Closes/Fixes #N` 추출 4건, 4건 모두 실제 closed Issue 지목** (예: PR804→#801 · PR802→#799 · PR808→#805 · PR817→#810).
**[사실] 상태 전이 규칙이 적힌 파일 존재**: `.github/ISSUE_TEMPLATE/{planner_task,live_bug,harness_request}.yml` · `docs/architect/{AGENT_ISSUE_ORCHESTRATION_ARCHITECTURE,BYZ_CORE_PHASES_AND_EXPANSION_MODEL,BYZ_ISSUES_CHANNEL_COMPLETION_GUIDE}.md` (needs-triage 문자열 히트).
**[추측]** 전이 자동화(라벨→다음 상태)는 없다 — needs-triage 74% 고정은 사람/좌석 손 라벨에 의존한다는 뜻.

---

## F5. issue-manager 흐름

**명령**
```
ls design/issues/ ; head design/issues/GOAL-issues.md ; sed design/issues/README.md
python3 (mailbox.log.jsonl from ft-issue-manager# ; seats-issues.json)
```
raw: `F5-design-issues-ls.txt` · `F5-issue-manager-rows.txt` · `F5-seats-issues.txt`

**[사실]** `design/issues/` = `GOAL-issues.md`·`LOOP-LEDGER.md`·`README.md`·`indices/`. GOAL 머리: 「이슈 모니터, 생성기, 종료기, 배분기 … 처리속도가 빠르면 이슈는 0가 되는것 … 메인 하네스들에 배분되는게 원칙이고 작은 이슈나 테스트 ci 수정등은 매니저 하위로 위성」.
**[사실] 출범(③) 흐름 문서 = `design/issues/README.md`** — 「부팅 5단계」(① 골 대조 ② seats-issues.json 내 행 ③ `indices/inbox/arch/00-first-unit.md` ④ `mbox.sh recv` · HIL=[HIL]→`byz-planner-arch#1` ⑤ 첫 보고 byz-planner-arch#1) + 「루프 = 모니터→생성·등록(라벨6+마일스톤)→우선순위→**배분 1건**→감시(10분·2 HOLD 상위화)→완료 5항→종료→다음, 동시 진행 = 메인 하네스당 1」.
**[사실] mailbox.log.jsonl 301행 중 `from=ft-issue-manager#` 28행** — `to` 상위: `byz-planner-arch#3` 16 · `ft-issues-temp-i819-main-ci-red-python-web-test#0` 5 · `ft-v65-master-claude#136` 3 · `repro-e2e#0` 2 · `byz-planner-arch#2` 1. 본문 `#8xx` 포함 **16행**.
**[사실]** `seats-issues.json` `_persona_pool_nano` = `["Trinity","Mouse","Dozer"]` — **3개(이름만, model 필드 없음)**. 좌석: `ft-issue-manager#0`(master, sonnet-5-5[1m]) · `repro-e2e#0`(tester, sonnet-5-5[1m]).

---

## F6. mbox 흐름 전체 (통신 부하)

**명령**
```
wc -l mailbox.log.jsonl mailbox.jsonl
python3 (일별 건수 · from→to 상위 · [HIL] · relay · to byz-planner-arch#)
head tools/comm-canonical/mbox.py
```
raw: `F6-mbox-analysis.txt` · `F6-mbox-py-head.txt`

**[사실]** `mailbox.log.jsonl` = **301행**, 기간 **2026-10-04 16:38:03 → 2026-10-05 12:25:32** (`.1` 로테이션 없음). 일별: **10-04 = 279 · 10-05 = 22** · 그 이전 0.
**[사실]** 큐 `mailbox.jsonl` = **440행**, 기간 **2026-08-10 → 2026-10-05**.
**[추측]** log 파일은 10-04 16:38 이전이 비어 있다 → 그때 로테이션/포맷 교체로 초기화된 것으로 보인다(그 전 이력은 큐 파일에만 남음).
**[사실] from→to 상위 10**: CCU_ARCH#17→FB_CCU#12 22 · CCU_NANO#25→CCU_ARCH#17 20 · FB_CCU#12→CCU_ARCH#17 17 · CCU_ARCH#17→CCU_NANO#25 17 · **ft-issue-manager#0→byz-planner-arch#3 16** · **ft-harness-ops#1→byz-planner-arch#3 14** · byz-planner-arch#3→ft-issue-manager#0 13 · byz-planner-arch#3→ft-harness-ops#1 13 · FB_CCU#12→byz-planner-arch#3 12 · ft-v65-master-claude#136→byz-planner-arch#3 9.
**[사실]** `[HIL]` 본문 **8행** · relay(bodies 경로/본문) **20행** · `to=byz-planner-arch#` **69행**(log 기준) — **단일 최대 수신처가 byz-planner-arch#** (log 301 중 23%).
**[사실] mbox.py 정본 주석**: 「★이 파일을 git 에 커밋하지 마라★ … 추적본이 되는 순간 없는 브랜치로 전환하면 git 이 정리해 심링크 3개가 dangling → mbox 전면 정지 … `.gitignore` 에 `.claude/fable-team/`」. 워크트리 `.fable-team/{bin,comm}/mbox.py` 는 이 파일의 심링크.

---

## F7. 멀티 머신 현황

**명령**
```
gh issue view 816 / 818 --json title,state,body
ls scripts/harness-install/ ; grep -nE '반영됨|jarvis|hermes|loom|c2c|mini' design/teams/harness/RELEASE-0.{1,2}.md
grep -rioE 'jarvis|loom|c2c|hermes\(로컬\)|mac mini|macmini' design/harness design/planner docs/rules
ls ~/.tmuxc/ ; ls ~/.tmm/
```
raw: `F7-issue816.txt` · `F7-issue818.txt` · `F7-harness-install.txt` · `F7-release-rows.txt` · `F7-machine-counts.txt` · `F7-tmuxc.txt` · `F7-tmm.txt`

**[사실] #816 = OPEN** 「[harness] 라이브 하네스 bin = main 추적본 1:1 — 채택·설치·드리프트 검사·FT_BIN 이전」. 본문: 「팀들이 실제 실행하는 `ft-*`(FT_BIN)는 루트 bin 이 아니라 **v6-realtime-live 워크트리의 `.fable-team/bin`**(gitignored 사본) — 38개 중 main 과 같음 24 · 다름 10 · main 에 없음 4」.
**[사실] #818 = OPEN** 「[docs] DESIGN-live-bin-sync — 라이브 하네스 bin = main 추적본 1:1 설계 (#816)」. → **「라이브 bin 1:1」은 아직 설계+이슈 단계, 미구현.**
**[사실] `scripts/harness-install/` = `slack-mirror/` 하나뿐**(16 파일: mirror_*.py · install{,-github,-inbound}.sh · plist 템플릿) — **범용 하네스 설치 스크립트는 없다**.
**[사실] RELEASE 「반영됨」 행**: 0.1 — 「로컬·harness-ops 워크트리 반영됨 dedceb2ba6 (main squash·PR #802)」 · 「그 외 워크트리 130개(10-04 측정): 반영 1 · 구버전 85 · 훅 없음 44」 · 「jarvis **미반영**·머신 키트 뒤」. 0.2 — 슬랙 미러 증거(로컬 yoonhwan 맥)만.
**[사실] 머신 이름 문서 등장 횟수**: `jarvis` 19 · `loom`/`LOOM` 29 · `c2c` 7 · `hermes(로컬)` 6 · `mac mini` 1 · `macmini` 1. → **jarvis=미반영, 나머지는 계획·설계 언급 수준**.
**[사실]** `~/.tmuxc/` = `current`·`snapshots`·`versions`·`termius-mobile-setup.md` · `~/.tmm/` = `categories(+.bak)`·`current`·`forks`·`models(+.generated)`·`versions`.
**[추측]** 「메인 하네스를 머신에 독립 배분」은 로컬 1대 + jarvis 미반영 상태 — 실질 1머신 운용.

---

## F8. 워크트리 · 나노 상한

**명령**
```
git worktree list | wc -l ; 접두별 counts
grep -nE 'FT_NANO_SLOTS|FT_NANO_IDLE_MIN|FT_NANO_LANDING_LEDGER' ft-nano-slots.sh
grep FT_NANO_SLOTS .fable-team/bin-*/*.sh
```
raw: `F8-worktree-count.txt` · `F8-worktree-prefixes.txt` · `F8-env-nano-vars.txt`

**[사실] `git worktree list` = 137개** (FEAT 포함). 접두 분포: `v65-` 27 · `kk-` 26 · `ops-` 12 · `cfo-` 8 · `v6-` 7 · `tmp-` 3 · `issues-` 3 · `fix-` 3 · `credit-` 3 · `harness-` 1 · 기타 30여.
**[사실] 나노 상한 변수 = `FT_NANO_SLOTS` (기본값 6)** — `ft-nano-slots.sh:12` `MAX="${FT_NANO_SLOTS:-6}"`. 부수 변수 `FT_NANO_IDLE_MIN` 기본 10 · `FT_NANO_LANDING_LEDGER`(미설정 시 `$ROOT/.fable-team/state/nano-landing.jsonl`) · `FT_NANO_FEAT` 기본 `feat/v6-realtime-live`.
**[사실] 팀 env 4종 어디에도 `FT_NANO_SLOTS`·`FT_NANO_IDLE_MIN`·`FT_NANO_LANDING_LEDGER` 가 없다** (harness/issues/kk/planner 전부 미설정) → 상한 6 은 **모든 팀 공통 하드코딩 기본값**.
**[추측]** 팀별 나노 상한을 다르게 두는 길은 현재 없다(변수는 있으나 아무도 export 안 함).

---

## 회신용 요약 (3줄용)

- **못 한 항목**: 없음(전부 실행). 유일한 한계 — F4 생성자 구분(`사람 vs 좌석`), 같은 gh 계정 키링(`yoonhwan`)이라 **불가**로 확정. F7 jarvis 실기 접촉은 읽기 전용 원격이라 이번에 안 함(문서 근거만).
- **사실/추측**: 표기 **[사실] 40여 항목 / [추측] 6항목** (F1 명부밖 해석 · F2 공용bin 성격 · F3 tick부재 영향 · F4 전이자동화 부재 · F6 로그 초기화 · F7 1머신 · F8 상한 고정). **비율 ≈ 사실 87% · 추측 13%.**
- **두드러진 4**: ① 실재 30 세션 중 **21이 6-file 명부 밖**(명부 신뢰도 낮음) ② **tick launchd 전부 bootout** ③ Issue **121건 중 needs-triage 90(74%) · assignees 0 · 전건 yoonhwan 명의** ④ 공용 bin **39 중 21이 v65 경로 하드코딩**(머신 이식성 0), **harness 설치 스크립트 부재**.