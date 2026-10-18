# FACTS — planner·issue-manager 역할 + 병렬 발주·처리 + 미션 클리어 실측 (ft-harness-arch#1 요청 · ft-harness-nano#1 실행)

> 측정 시각 **2026-10-05 14:46 KST** · 읽기 전용 · 코드·명부 수정 0 · Slack 0.
> 경로 기준 = `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents`. **planner·issues·cfo·ccu·harness 문서는 리포 루트가 아니라 워크트리 안**에 있다(각 표에 실제 경로).
> 원본 = `design/teams/harness/issue-improvement/facts-raw/R*.txt`. 표기 **[사실]** = 명령 출력 · **[추측]** = 해석. REQ = mbox #56967.

---

## R1. planner · issue-manager 가 «실제로» 하는 일

### planner (`.worktrees/v6-realtime-live/design/planner/`)

| 파일 | 인용(파일:줄) | 사실/추측 |
|---|---|---|
| GOAL-planner.md | `:16` 「너는 팀을 배정하고 운영하는 역할… 메인 베이스 팀에 팀을 추가구성하는것도 사용자와 협의 추가」 | [사실] |
| GUIDE-planner.md | `:3` 「원문 골 = GOAL-planner.md(불변) · 구조 정본 = STRUCTURE-main-satellite.md · 이 파일은 «매 턴 planner 가 어떻게 움직이나» 8항」 | [사실] |
| GUIDE-planner.md | `:11` 「분류 값 1통 = 1 Issue = 1값 → issue-manager (★planner 는 발주하지 않는다★) … 출범·추적·닫기 = issue-manager · 하위 좌석(나노·arch·tester)에는 절대 직접 안 보냄」 | [사실] |
| STRUCTURE-main-satellite.md | `:1` 「메인/위성 팀 구조 — planner 정본 r4」 · `:5` 「planner 역할 확장 = 팀 배정·운영 · 기존 베이스↔신규 위성 연결·관리·정리 · 코드·커밋·push 0」 | [사실] |
| BOARD.md | `:1` 「planner BOARD — 이슈·할 일 원장 (단일 정본)」 · `:19` 「★Issue 가 정본 · BOARD 는 인덱스★」 | [사실] |
| NEWS-TREE.md | `:1` 「planner 뉴스 트리 — 상태는 카드 폴더(indices/대기·진행·완성)에서」 | [사실] |
| README.md | `:16` 「`STRUCTURE-main-satellite.md` \| 메인/위성 구조 · ⓪①~④ 판별 · 위성 생애주기·종료 4항 · planner 역할(§1-1-B/C)」 | [사실] |

**[사실] BOARD.md**: `^|` 행 **107** · 정본 표 헤더(`:53`) = **3열** `좌표 | 닫는 증거 원문(복붙) | 정본` · 개정 서술은 r40→r41→r42(10-05 12:3x). 상태 어휘는 **이모지** `[✅]/[🔄]/[⏳]`(NEWS-TREE 트리에서 사용).
**[추측]** planner 의 실질 산출 = BOARD(원장) + NEWS-TREE(트리) + 분류 «값» 이고, 발주·출범·닫기는 issue-manager 로 위임된 상태(문서가 스스로 그렇게 적는다).

### issue-manager (`.worktrees/issue-manager/design/issues/`)

| 파일 | 인용(파일:줄) | 사실/추측 |
|---|---|---|
| GOAL-issues.md | `:4` 「이슈 모니터, 생성기, 종료기, 배분기 … 처리속도가 빠르면 이슈는 0가 되는것 … 작은 이슈나 테스트 ci 수정등은 매니저 하위로 위성」 | [사실] |
| README.md | `:25` 「## 루프 — 시작 노드 ①~⑥ (… planner 는 발주 0, 분류 «값»만)」 | [사실] |
| README.md | `:29` 「출범 — 메인 오케(v65/cfo master)에 「Issue #N 착수」 발주 1통 · 작은 건 = 하위 나노 직접」 | [사실] |
| README.md | `:31` 「랜딩 — PR `Closes #N` → CodeRabbit → DA → 메인 오케 머지」 | [사실] |

**[사실] LOOP-LEDGER.md**: `^|` 행 **31**. 최근 3행 상태값 = 「환경 위험/기록」 · 「#819 후속/PR #823 머지」 · 「신규 #827/등록」 (모두 `10-04`).
**[사실] 좌석 명부**: `seats-planner.json` rows **5** · `_hil_route` = 「오빠 직접(최상위) — planner pane AskUserQuestion · 현역 좌석 = _master」 · `_doc` = 「틱 없음 — planner 는 mbox 수신 기반」. `seats-issues.json` rows **2** · `_hil_route` = `byz-planner-arch#3` · `_doc` = 「틱 없음 — 좌석 자체 10분 모니터」.

---

## R2. planner → 메인팀 발주 실측 (mbox 로그)

원본 = `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mailbox.log.jsonl` (338행, `.1` 없음).

| 항목 | 값 | 사실/추측 |
|---|---|---|
| `from=byz-planner-arch#*` 전수 | **55행** | [사실] |
| to 별 | `ft-issue-manager#0` 15 · `ft-harness-ops#1` 13 · `ft-v65-master-claude#136` 9 · `ft-harness-ops#0` 7 · `FB_CCU#12` 6 · `byz-planner-arch#3` 3 · `#2` 1 · `ft-harness-ops#2` 1 | [사실] |
| 최초·최근 | first `2026-10-04T16:40:13` · last `2026-10-05T12:29:08` | [사실] |
| 본문 첫 줄 예시 3 | `[byz-planner-arch#2->ft-harness-ops#0] ★다음 단위(오빠 17:1x …)★ …` · `[byz-planner-arch#2->ft-harness-ops#0] #56636 수락 · ⓓ ✅ …` · `[byz-planner-arch#2->ft-harness-ops#0] ★오빠 원문 12(17:3x) = …★` | [사실] |
| 반대(to=planner) | **71행** · from: issue-manager 17 · harness-ops#1 14 · FB_CCU 12 · v65#136 11 · harness-ops#0 9 … | [사실] |
| `[HIL]` 포함(로그 전체) | **20행** | [사실] |
| 같은 to 연속 send | **48쌍** (예: `#56632→#56633` · `#56637→#56638` harness-ops#0) | [사실] |

**[추측]** 48 연속쌍 중 상당수는 「#N 수락 → #N+1」 식 **왕복/연쇄**이지 «답 없이 겹쳐 보낸» 것은 아니다 — 로그만으로는 미응답 여부를 못 가른다(seq 쌍만 제시).

---

## R3. 나노·세션 병렬 처리 기계

**[사실] 위치 확정**: 실제 스크립트는 `.worktrees/v6-realtime-live/.fable-team/bin/ft-nano-{slots,spawn,close,freshness,cherry-gate}.sh` (심링크 아님 · 실파일). `scripts/fable-team-bin/` 와 `~/.claude/fable-team/bin/` 에는 **`ft-nano-*` 없음**.

| 스크립트 | 항목 | 파일:줄 + 인용 | 사실/추측 |
|---|---|---|---|
| ft-nano-slots.sh | 상한 기본값 | `:12` `MAX="${FT_NANO_SLOTS:-6}"` | [사실] |
| ft-nano-slots.sh | 슬롯 찬 판정 | `:45-66` live nano 좌석의 **턴 상태**(`working = not(IDLE≥FT_NANO_IDLE_MIN=10분)`) — 카드·워크트리 아님 | [사실] |
| ft-nano-slots.sh | 출력 | `:67` `SLOTS nano 일하는 석={n}/{mx} · 명부 · 노는 석 · 빈 석` | [사실] |
| ft-nano-spawn.sh | 입력 | `:10` `ft-nano-spawn.sh <indices/대기/X.md>` · `:43` 대기/ 카드만 | [사실] |
| ft-nano-spawn.sh | 만드는 것 | `:5-6` ①lint ②워크트리 ③tmuxc open ④태그 ⑤seats 등록 ⑥**인덱스 대기→진행** ⑦첫 발주 | [사실] |
| ft-nano-spawn.sh | 린트 | `:47` `bash ft-index-lint.sh "$IDX"` · `:49-51` 카드 `## 상태 base_sha` 대조 | [사실] |
| ft-nano-close.sh | 닫는 순서 | `:5-6` 「명부 삭제·원장 append·@zc_v65_active 해제·세션 kill」 · 워크트리 정리는 **계획만 생성**(`:10`) | [사실] |
| ft-nano-close.sh | 게이트 | `:74-115` ①계보 세션 자기 0 ②워크트리 cwd 프로세스 0 ③branch `nano/*` ④⑤미커밋/cherry | [사실] |
| ft-nano-freshness.sh | 보는 4값 | `:5-6` FRESH/STALE/**STALE-OVERLAP**/미랜딩 · `:32` base=merge-base · `:44` BEHIND · `:64` overlap | [사실] |
| single_set_testing.md | press 규칙 | `.worktrees/v6-realtime-live/docs/rules/single_set_testing.md:25` 「나노의 press 는 §3 ②(최신 루트 병합 완료) «뒤»에만 … 최신 병합 전 브랜치로 press 금지」 | [사실] |
| DESIGN-ccu-stress-infra.md | GPU 공유 | `.worktrees/ccu-stress/design/ccu/DESIGN-ccu-stress-infra.md:64` 「★GPU 공유★: dev GPU(STT·vLLM)를 v65 로컬 worker 와 같이 쓴다 — 회차 전 v65 master에 mbox 순번 요청 · 섞였으면 회차 무효」 | [사실] |

**[추측]** GPU·press 직렬은 **한 곳에 모인 «규칙»이 아니라** runner 쪽 규율(single_set)·ccu 쪽 mbox 순번(DESIGN §GPU)으로 **분산**돼 있다.

---

## R4. 팀별 미션 큐 현재값 (대기·진행·완성)

| 팀 | indices 경로(실제) | 대기 | 진행 | 완성 | 진행 카드 ↔ 살아있는 tmux |
|---|---|---|---|---|---|
| v65 | `design/v65/indices/` (루트) | 29 | 28 | 32 | **Y 0 / 28** (inbox 4) |
| cfo | `.worktrees/c-level-planning/design/cfo/indices/` | 15 | 17 | 31 | (inbox 3 · `orders/` 평면 ORDER **204**) |
| ccu | `.worktrees/ccu-stress/design/ccu/` | **없음** | **없음** | **없음** | ORDER 77 · RESULT 3 · CLOSEOUT 1 (평면) |
| harness-ops | `.worktrees/harness-ops/design/teams/harness/indices/` | 0 | 0 | 1 | REQUEST-LEDGER 데이터행 3 |
| issue-manager | `.worktrees/issue-manager/design/issues/indices/` | 0 | 0 | 3 | LOOP-LEDGER 행 31 |

**[사실]** 「클리어」 표시 방식 — v65 = 카드가 `indices/완성/` 으로 이동(`00-first-unit.md` 등) · cfo = `indices/완성/` + `CLOSEOUT-cfo-accounts-20261003.md` · ccu = `CLOSEOUT-ccu-u-staircase-20261004.md` · harness = `indices/완성/00-first-unit.md` · issue = LEDGER 행 상태(`LOOP-LEDGER.md`).
**[추측]** v65 진행 28 카드 중 **살아있는 세션과 이름이 맞는 것 0** — 진행 카드 다수가 세션 없이 «진행» 표시로 남아 있다(정지 레디의 흔적).

---

## 회신 요약

- **못 한 항목**: **BOARD.md 상태값 «종류»** 는 이모지(✅/🔄/⏳)로만 확인 — 별도 status: 어휘는 BOARD 에 없음. 그 외 R1~R4 전부 실행.
- **사실/추측**: [사실] 약 30항 / [추측] 4항 → **사실 ≈ 88% · 추측 ≈ 12%**.
- **두드러진 3**: ① planner 는 **발주하지 않는다**(문서 명시 · 값만) — 발주·출범·닫기 = issue-manager ② 나노 기계는 **v6-realtime-live 워크트리 실파일**(추적본·`~/.claude` 에 없음) ③ v65 진행 28 카드 중 살아있는 세션 **0**.