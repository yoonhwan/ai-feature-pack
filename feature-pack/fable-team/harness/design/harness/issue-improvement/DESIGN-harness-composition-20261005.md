# DESIGN — 하네스 구성 (Slack 제외 · 이슈 + 하네스) · r4 (ft-harness-arch#0 · 2026-10-05)

> 골 원문(GOAL-harness.md 복붙):
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
>
> 발주 = `ORDER-harness-composition-20261005.md`(03597ca902) · 오빠 원문 「일단 슬랙을 제외해버리고 하네스 구성 기획」 + 「이슈와 하네스 포함」.
> 골의 축: 축 A(모니터 — §1 구성 지도·§2 병목) + 축 B(개선요청 접수·협의 — §4 질문) + 원문 5 머신 독립 배분(§3-4). 닫는 증거(이 문서 몫) = DA APPROVE + 오빠 질문 5개의 값이 §4 표에 적힘.
> MERGED 반영 r+1 (C11 · 2026-10-06): §3-2 planner 줄 「큐 절 소유 · 랜딩 순번·통지」(충돌 ③) · §3-3 ① 「(좌석 등록 한정)」·② 「from:member 는 재현 뒤 team 전이」(C11++ · P11 §6-2·6-7 · 오빠 값 P11 Q3). 충돌 ⑯(키트·명부 파일 자리)은 이 문서가 정본이라 변경 0.

> 상태: **r4 — FACTS(775ad84a93) 2차 대조 §1-A 불일치 12건 반영(정정 4 · 보강 6 · 신규 1 · 미확정 1 · 결론 불변) · r3 (DA r2 `DA-composition-r2.md` 23ff9eb1d7 발견 3 「Issue 생애주기 책임 = 메인 오케」 §3-1·§3-2·§3-3 ⑥ 반영) — 오빠 값 5건 반영(`VALUES-harness-composition-20261005.md` 8a51bd2f95: Q1 = 「Issue # 는 메인 오케 소유 · 나노는 작업 워커」 · Q2~Q5 추천안 확정) · DA r1 HOLD(`DA-composition-r1.md` 21a1a81c5f) 발견 1~5 반영 · nano FACTS(F1~F8) 2차 대조 완료(§1-A) · **r4 오빠 수락(ops#2 #56943)**.** r2→r3: §3-2·§3-3 ③·§3-6 3·B4 닫는 증거에서 «나노 spawn Issue 게이트» 삭제 → «메인 오케의 Closes 연결률» · §4 = 확정값. r1→r2: §1 수치 정정 5(마일스톤·라벨·[HIL] 술어·jarvis 행·cfo env) + 측정 조건 명시 · §2 절대 주장 → 관측 범위 한정 · §3 소유·복구·완료 게이트 충돌 해소 · §4 선택지 보강. 리서치 = `WIP-swarm-control-research-20261004.md` §2.

## 0. 한 줄 결론

지금 하네스는 **「좌석(tmux) + 파일 큐(mbox) + 손편집 명부(seats-*.json)」** 위에 GitHub Issue 가 «옆에» 붙어 있는 구조다. 일하는 주체·통신·상태가 좌석에 묶여 있어 **좌석 밖에 «열린 질문·진행 상태가 모이는 자리»가 없고**(pane 텍스트와 mbox 큐는 남지만 목록으로 읽히지 않는다), 오빠는 pane 에 붙어야 상태를 본다. 목표 구성은 정본을 셋으로 분리한다 — **일 = GitHub Issue · 실재 = tmux 에서 생성한 명부 · 사람 판정 = 열린 질문 원장** — 좌석·머신은 전부 «갈아끼우는 것»으로 둔다.

## 1. 현재 구성 지도 (실측 · Slack 층 제외)

측정 조건(DA r1 발견 1): 시각 **2026-10-05 12:1x KST** · 루트 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents`(워크트리 harness-ops · `feat/slack-inbound-820`) · `gh` 는 `--limit 1000` · 수치는 **가변 스냅샷**(tmux·큐·bin 은 분 단위로 변한다 — DA 재측 30/23·438·294·66/28 은 변화이지 오류가 아님). 술어는 행마다 적는다.

```
[오빠] ── tmm(폰 TUI: ss/h/s/a/kill/restore) ── tmux attach ──▶ pane 의 AskUserQuestion (동기)
                                                              ▲ 값이 같은 프로세스로 «직접»
[최상위 오케] byz-planner-arch#3 (seats-planner._master · _hil_route=「오빠 직접」)
   ├─ 메인 팀  v65(ft-v65-master-claude#134·#135) · cfo(FB_CFO#52) · planner · issue-manager(ft-issue-manager#0 + repro-e2e#0) · harness-ops(#1)
   ├─ 위성     ccu(FB_CCU#12) · kk(FB_KK#3) · (airag·kakao = 다른 프로젝트 좌석이 같은 tmux 서버에 동거)
   └─ 좌석     arch · da · nano · impl · tester  (tmux 세션 1 = 좌석 1 · 에이전트 = claude/codex/opencode · ★세션 ≠ 살아 있는 에이전트★)
[통신] .fable-team/comm/mbox.sh — 파일 큐 mailbox.jsonl(LIFO · per-to ring 10 · consume-on-read) + 도어벨(pane 1줄) · 사본 로그 mailbox.log.jsonl(10-04 부터)
[명부] .fable-team/seats{,-harness,-issues,-planner,-kk,-cfo}.json — 손편집 · _master · _hil_route
[키트] 공용 bin = .worktrees/v6-realtime-live/.fable-team/bin (gitignored 사본 · FT_BIN) + 팀별 bin-<x>/ (env.sh 4: harness·issues·kk·planner · cfo 는 env.sh 없이 ft-tick-cfo.sh/ft-seat-status.sh 안에 값)
[틱]   launchd com.byz.ft-tick-{kk,cfo} 등 — 지금 0 로드(오빠 「크론도 정지」)
[일]   GitHub Issues 121 · 마일스톤 6종 · Projects 「BYZ Board」 · issue-manager LOOP-LEDGER(건별 1행)
[머신] 이 Mac 1대에서 관측 · jarvis(OCI) 는 RELEASE-0.1 「미반영」 행 · 원격 런타임 유무는 이 측정으로 확인 불가
```

| # | 사실 | 수치(술어) | 명령 |
|---|---|---|---|
| 1-1 | tmux 세션 | 29(계보 21 · `#N` 제거 후 유일 이름) · airag·kakao 7 동거 | `tmux ls -F '#{session_name}'` |
| 1-2 | 명부 vs 실재 | 비메타 행 **922**(seats 799 · cfo 102 · kk 12 · planner 5 · harness 2 · issues 2) · `tmux ls` 와 키 교집합 **6/1/0/2/2/2** · 라이브 30 중 **명부 밖 18~21**(FACTS F1) · 일관된 `status` 필드 없음 — 상태는 `role`(stop-ready 486 등)·`_replaced_by`·`_session:killed` 3곳 분산 · 행 있고 세션 없음 **233**(186+38+6+3) | python: 키 ∩ 세션명 · F1 |
| 1-3 | mbox 살아 있는 큐 | 440행 미소비 · ts < 10-01 **330** · `to`∈{dispatch,--from} 오발송 **15** · 수신자별 상한 10 | `mailbox.jsonl` 파싱 |
| 1-4 | mbox 사본 로그 | 292행(10-04 16:38~ · FACTS 시점 301) · `[HIL]` **부분문자열 18 / 봉투 뒤 첫 태그 5**(seq 56675·56677·56688·56769·56771 · FACTS 술어 8) · **relay 20**(F6 · r3 의 0 은 술어 오류) · to=`byz-planner-arch#*` 69(23%) · seq 누계 56923 | `mailbox.log.jsonl` · `.mbox-seq` · F6 |
| 1-5 | 공용 bin | 67 파일 · `.bak*` 28 · 실 스크립트 **39** · **v65 리터럴 하드코딩 21/39**(리터럴만 14 · +env 7 · env 만 0) · 추적본(~/.claude/skills/fable-team/scripts 29)↔동명 16 중 동일 6·상이 10 · #816 본문: main 과 같음 24 · 다름 10 · 없음 4 | `ls FT_BIN` · F2 · Issue #816 |
| 1-6 | 팀 키트 | `*-env.sh` **4**(harness·issues·kk·planner · 공통 변수 11 · kk/planner +3 · issues +1) · cfo = env.sh 없음(스크립트 안 값) · tick plist = kk·cfo·v65 3(디스크만) · **harness·issues·planner 는 tick plist 없음**(`_doc` 「좌석 자체 10분 모니터」) · `FT_NANO_SLOTS` 기본 6 을 어느 팀도 설정 안 함 | `ls .fable-team/bin-*` · F2·F3·F8 |
| 1-7 | launchd | BYZ `com.byz.ft-tick-*` **0 로드**(com.airag.* 2 · hermes 3 · com.byz.gce-guard-check 1) | `launchctl list` |
| 1-8 | 워크트리 | 137(10-03 160) · 접두 v65 27 · kk 26 · ops 12 · cfo 8 · /private/tmp 9 | `git worktree list` |
| 1-9 | GitHub Issue | **121**(open 93 · closed 28) · 09-28 이후 생성 93 / 종료 10 · author 전부 `yoonhwan`(좌석 gh = 오빠 토큰 → 사람/좌석 구분 불가) | `gh issue list --state all --limit 1000` |
| 1-10 | 라벨·마일스톤·담당 | 라벨 **72**종 · `status:needs-triage` 90 · `status:blocked-no-seat` 46 · `status:in-progress` 5 · `hil:needed` 4 · **마일스톤 비null 101/121**(goal-outside 85 · M7 10 · M5 2 · K2 2 · K4 1 · p90-five 1) · **assignees 0/121**(F4) · 전이 규칙 문서 5곳(README + ISSUE_TEMPLATE 3 + docs/architect 3) · 자동 전이 0 | `gh label list --limit 1000` · F4 |
| 1-11 | Issue↔PR | 09-28 이후 머지 PR 63 · 본문 `Closes/Fixes/Resolves #N` 문자열 **4**(#817→810 · #808→805 · #804→801 · #802→799) · closed 28 중 그 4 가 PR 머지로 닫혔는지는 이벤트 미확인(가설) | `gh pr list --state merged --limit 1000` 본문 scan |
| 1-12 | issue-manager | README 에 루프(모니터→등록 라벨 6+마일스톤→우선→배분 1건→감시→5항→종료) **정의 있음** · LOOP-LEDGER 2행(#731·#745) · 로그에서 from=issue-manager→planner 16 | `design/issues/README.md` · 로그 |
| 1-13 | HIL 경로 | 하위 좌석 `[HIL]` → mbox → `_hil_route`(harness·issues = planner#3) → planner pane AskUserQuestion → 값 mbox = **3홉** · `tmm h` 0건(12:1x) | seats-*.json `_hil_route` · `tmm h` |
| 1-14 | 머신 | RELEASE-0.1 행: 로컬 반영 1 · 워크트리 130(반영 1·구버전 85·훅 없음 44) · **jarvis 「미반영 · 머신 키트 뒤」 1행** · 「반영됨 <원격 머신>」 행 0 · 설치 키트 디렉터리 = `scripts/harness-install/slack-mirror` 1 | `RELEASE-0.1.md:23-26` · `ls scripts/harness-install` |

### 1-A. nano FACTS(`FACTS-composition-20261005.md` 775ad84a93 · F1~F8) 2차 대조 — 불일치 목록과 정정

| # | 설계 r3 §1 | FACTS | 판정·정정 |
|---|---|---|---|
| 1 | 1-1 세션 29 · 1-4 로그 292 · 1-5 실 스크립트 38/.bak 29 | 30 · 301 · **39/28** | 가변 스냅샷(측정 시각 차) — 1-5 는 FACTS 값으로 정정(39 실 · 28 .bak) |
| 2 | 1-2 「`status` 필드 있는 행 4」 | **일관된 status 필드 없음** — 상태가 `role` 값(stop-ready 486·stopped 56·closed …)·`_replaced_by`·`_session:killed` 세 곳에 흩어짐 · 파일마다 스키마 상이 · 행 있고 세션 없음 = seats 186·cfo 38·kk 6·planner 3 | **정정** — B1 증거를 「status 4」가 아니라 「상태가 3곳에 분산 · 행 있고 세션 없음 233」으로 |
| 3 | 1-2 생존 교집합 6/1/0/2/2/2 | 라이브 30 중 명부 행 있음 **9~12**(FACTS 본문 수치 9 · 나열 12 · FB_CFO#52 가 seats+cfo 중복) → **명부 밖 18~21** | 보강 — 「명부 밖」 수치 추가(다른 트랙 kakao·airag·ccu 는 6파일에 키 자체가 없음) |
| 4 | 1-4 `[HIL]` 18/5 · relay 0 | `[HIL]` 8(술어 미기재) · **relay 20** | relay 는 내 술어 오류(`bodies/` 검색) → **20 으로 정정** · [HIL] 은 술어별 18/8/5 병기 |
| 5 | 1-6 cfo env 없음 · tick plist kk·cfo 2 | 같음 + **harness·issues·planner 는 tick plist 자체 없음**(`_doc` 「틱 없음 — 좌석 자체 10분 모니터」) · kk 변수 +3(FT_GOAL_LINES_FILE·FT_NEWS_TREE·FT_SEATBELT_README) · issues +1(FT_REPRO_WT) | 보강 — B8 증거에 「tick 없는 팀 3 = 멈춤 감지가 좌석 턴 의존」 |
| 6 | 1-10 라벨 72 · 1-11 Closes 4 | 라벨 71(`--limit 100` 절단 가능) · Closes 4 **전부 실제 closed Issue 지목** · **assignees 0/121** | 72 유지(DA `--limit 1000`) · ⓓ 부분 확정: 4건은 PR 머지 close · 나머지 24 는 미확인 · **assignees 0 추가** |
| 7 | 1-12 「전이 규칙 README 정의」 | 전이 규칙 문서 **4곳 더**: `.github/ISSUE_TEMPLATE/{planner_task,live_bug,harness_request}.yml` · `docs/architect/{AGENT_ISSUE_ORCHESTRATION_ARCHITECTURE,BYZ_CORE_PHASES_AND_EXPANSION_MODEL,BYZ_ISSUES_CHANNEL_COMPLETION_GUIDE}.md` · 자동 전이 0(추측) | 보강 — B5 「규칙은 5곳에 있고 집행 1곳도 없음」 |
| 8 | 1-5 ⓒ 하드코딩 수 미상 | **39 중 21**(v65 리터럴만 14 · 리터럴+env 7 · env 만 0 · 둘 다 아님 18) · env 읽는 7개도 하드코딩 폴백 보유 · 추적본(~/.claude/skills/fable-team/scripts 29)↔공용 bin 동명 16 중 동일 6·상이 10 | ⓒ 확정 — B6 증거 |
| 9 | 1-14 설치 키트 1 | 같음 + **`mbox.py` 는 의도적 비추적**(주석 「git 에 커밋하지 마라 — 심링크 dangling → mbox 전면 정지」 · 워크트리 `.fable-team/{bin,comm}/mbox.py` 는 루트 `.claude/fable-team/` 심링크) | 보강 — §3-4 키트 정본에 «mbox.py 는 설치 시 비추적 경로로 복사» 조건 |
| 10 | — | F8: `FT_NANO_SLOTS` 기본 6 · 팀 env 4종 어디에도 미설정 → 전 팀 공통 하드코딩 | 신규 — B6 (팀별 상한 분리 경로 없음) |
| 11 | ⓐ 에이전트 실재 | 30 세션 = claude 26 · codex 2 · opencode 1 · shell 1(tmm) — 측정 시점 nano#1 은 opencode 재기동 뒤 | ⓐ 확정(12:2x 시점) |
| 12 | ⓑ cfo 나노 계보 비율 | role 어휘로만 분포(worker 17·master 13·…) · 계보 비율은 미산출 | 미확정(추측 유지) · 구현 단위 2(명부 생성기)에서 자동 산출 |

정정 반영: 1-2·1-4·1-5·1-10 행과 B1·B5·B6·B8 증거(아래). 설계 결론(§0·§3)은 바뀌지 않는다 — FACTS 가 전부 같은 방향을 가리킨다(명부 불신·Issue 미연결·키트 비이식·멈춤 감지 사람 의존).

## 2. 병목·홀 목록 (관측 범위 한정 · DA r1 발견 2 반영)

| # | 문제(이름) | 증거(관측) | 범위·가설 | 닫는 증거 |
|---|---|---|---|---|
| **B1 명부가 실재를 답하지 못함** | 1-2: 922행 중 생존 ≤13 · 라이브 30 중 명부 밖 18~21 · 상태가 3곳 분산(일관 status 필드 0) · 행 있고 세션 없음 233 | 관측 = 이 머신 tmux. 「누가 살아 있나」를 명부로 답한 사례 0(멍청한짓 원장 10-03 「배정 없는 문제」 ×16 은 `tmux ls` 재셈) | 명부 = 등록 계보 접두에 맞는 tmux 세션에서 생성(손편집 0) · 행 수 = 그 접두 세션 수 |
| **B2 HIL 이 3홉·경유 좌석 의존** | 1-13 · H2(좌석 교체 시 미처리 mbox 이관 규칙 0) · 오빠 18:3x 「피드백해도 응답 없음」 | 관측 = 10-04 로그 창(첫 태그 [HIL] 5/292). 「질문 큐가 없다」가 아니라 **«질문만 모은 목록»이 pane·mbox 밖에 없다**(큐에는 남는다) | 열린 질문 원장 1개 · 질문 1건이 planner pane 과 `tmm h` 에 동시에 보임 · 답 1건 → 좌석 seq → 집행 1줄 |
| **B3 종료 좌석의 수신함 잔존** | 1-3: ts<10-01 330행 · 오발송 15 | 범위 = **종료(계보 뒤짐·세션 없음) 수신자만**. 살아 있는 좌석의 미독 발주는 정상이라 대상 아님 | 종료 좌석 수신함 drain 규칙(이관·폐기 기록) · 종료 수신자 미소비 행 0 |
| **B4 Issue 가 일의 정본으로 안 쓰임** | 1-9~1-12: 생성 93/종료 10 · needs-triage 90/121 · Closes 문자열 4/63 · LOOP 2행 | 가설: 메인 오케가 Issue 를 «받아서 닫는 단위»로 안 쓰고 나노·PR 이 Issue 와 무관하게 흐름 | **메인 오케가 받은 Issue 의 랜딩 PR 「Closes #N」 연결률 ≥ 80%** · 머지 → close → 5항 검사 통과(오빠 Q1) |
| **B5 라벨 72종 · 전이 집행 불일치** | 1-10·1-12: README 에 라벨 6+전이 정의 있음, 실재 = needs-triage 90 · in-progress 5 · 마일스톤 goal-outside 85 | 「규칙 0」이 아니라 **규칙은 5곳(README·템플릿 3·docs/architect 3)에 있고 집행 주체·자동 전이 0 · assignees 0**(H13·F4) | 상태 라벨 5 + 전이표 1장 + 집행 주체 1 · 주간 needs-triage 잔존 = 신규 미분류만 |
| **B6 키트가 머신으로 못 감** | 1-5·1-6·1-14: FT_BIN = v65 워크트리 사본 · **v65 리터럴 21/39** · env 읽는 7개도 하드코딩 폴백 · 추적본↔라이브 동명 16 중 상이 10 · env 형태 팀마다 다름 · `FT_NANO_SLOTS` 전 팀 기본 6 · 설치 키트 1(slack-mirror) · `mbox.py` 비추적(심링크) · jarvis 미반영 | 관측 = 로컬. 원격 런타임 「0」은 **미확인**(RELEASE 행 기준 «반영됨 원격 0») | `install.sh` 1회로 빈 홈에 팀 1개 부팅 보고 · MACHINES 표 「반영됨 <machine> <sha>」 행 |
| **B7 상태가 pane 안에만** | `tmm h` = pane 텍스트 스캔 · 세션 29 · 세션 ≠ 에이전트 생존(nano#1 사례) | 좌석 N → 오빠 순회 N(가설: 체감 = 멍청한짓 원장 「보고 공백」 ×44) | B1·B2 가 파일이라 pane 밖(폰·다른 머신)에서 읽힘 |
| B8 멈춤 감지 = 사람 | 1-7: tick 0 로드 · 「크론도 정지」 · harness·issues·planner 는 tick plist 자체 없음(좌석 턴 의존 · F3) | 규칙 선언: **정체 = 마지막 보고 시각이 팀 보고 주기 ×3 을 넘고, 명부 상태가 «의도된 대기»(stop-ready·HIL 대기)가 아닌 경우** — 장기 작업·의도 idle 과 구분은 이 상태 열로 | 명부 «마지막 보고·상태» 열 · 틱은 보고 주기만 |

왜 pane 인터뷰는 잘 되나(오빠 질문): ①**동기** — 질문이 그 프로세스를 멈추고 값이 같은 프로세스로 들어간다(해석 0) ②**선택지**가 번호로 고정 ③오빠가 `tmm` 으로 바로 붙는다. 어디서 막히나: ①질문이 «pane 안»에만 있어 **좌석 수 > 1** 이면 순회(B7) ②하위 좌석은 인터뷰 금지라 3홉 경유(B2) — 경유 좌석이 stop-ready 면 멈춤 ③기록이 pane 텍스트뿐이라 승계·재시작에 남지 않음(H2) ④오빠 부재(자는 동안·원격) 시 «질문만 모인 자리»가 없다. **병목은 인터뷰 «방식»이 아니라 질문이 «어디에 있느냐»다.** Slack 은 이걸 «게시»로 풀려던 것이고, 이번 기획은 «파일 원장»으로 푼다(게시는 후속 층).

## 3. 목표 구성 (층 · 소유 · 흐름) — DA r1 발견 3·4 반영

### 3-1. 정본 3개 — 소유·출처·복구
| 정본 | 무엇 | 쓰기 소유 | 출처(파생이면 조인 대상) | 복구 |
|---|---|---|---|---|
| **GitHub Issue** | 일 1건 = Issue 1건 · 상태 라벨 5 · **소유 표시 = `team:<x>` 라벨 + 코멘트 1줄 「소유 오케=<세션명>」**(assignee 는 쓰지 않는다 — 전건 `yoonhwan` 단일 계정·assignees 0/121 · FACTS F4) · 완료 5항 = 코멘트 | 등록 = 누구나(오빠·좌석) · **접수 검사·라벨 전이·배분·색인 = issue-manager** · **해결·진행 코멘트·완료 5항 코멘트·close(랜딩 PR Closes)·reopen 집행 = 그 Issue 를 받은 메인 오케**(오빠 Q1) · issue-manager 는 close 뒤 5항 «대조»만 하고 미비면 메인 오케에 1통 | GitHub | GitHub 가 보관 |
| **좌석 실재** `.fable-team/state/seats.live.json` | 세션 × {팀·역할·모델·에이전트 pid·Issue #·마지막 보고 ts·열린 질문 수·상태} | **생성기 `ft-seat-status.sh` 만**(손편집 0) | 세션·pid = tmux · 팀·역할·모델·계보 접두 = **팀 설정 파일** `seats-<x>.json` 설정 행(소유 Q5) · Issue # = 좌석 spawn 인자 · 마지막 보고 = mbox 로그 · 열린 질문 = 질문 원장 | 재생성(멱등). 회원 판정 = 설정 파일의 계보 접두와 일치하는 세션만(동거 프로젝트 제외) |
| **열린 질문 원장** `.fable-team/state/questions.jsonl` (머신당 1) | 행 = {`qid`=`<machine>:<seq>` · 묻는 좌석 · 계보 · Issue # · 선택지 · asked · answered(값·누가) · applied(좌석 ack)} | **append = 묻는 좌석 · answer = 최상위 오케(AskUserQuestion 1곳) · applied = 묻는 좌석** | — (정본 자체) | 좌석 교체: 후계(같은 계보 #N+1) 부팅 시 `applied=null` 행을 자기 것으로 인수(계보 키) · 종료 좌석 drain 은 **질문 행을 지우지 않고** 후계 또는 planner 로 재지정 · 답은 `answered` 에 남아 적용 전까지 유실 0 |

- 답의 정본 = **묻는 좌석이 있는 머신의 원장 행**. 다른 머신에서 답한 경우 그 값은 Issue 코멘트(`hil:answer qid 값`)로 들어오고, 원장 소유 머신의 최상위 오케가 그 코멘트를 **자기 Issue 동기화 때**(좌석 보고 이벤트 · 타이머 0) 원장에 옮겨 적는다 → 그때부터 로컬과 같은 경로. 1단계(머신 1대)에서는 이 경로를 쓰지 않는다.
- mbox 는 **전송**만(상태 아님). 좌석 종료 = 수신함 drain 이 닫는 사건(B3 · 종료 수신자만).

### 3-2. 층과 소유
```
오빠(HIL)        — 질문 원장에 «답»만 · pane·tmm·폰 어디서든 같은 목록 · 파괴·판정 게이트 그대로
최상위 오케(planner) — 질문 원장 answer 집행(AskUserQuestion 1곳 · 기존 HIL 규칙 유지) · 팀 추가·예외 · 큐 절 소유 · 랜딩 순번·통지 · Issue 는 읽기만
issue-manager    — Issue 등록 검사·라벨 전이·배분 1건·close 뒤 5항 대조·LOOP-LEDGER 색인 · «Issue 가 0 이 되게» 루프 소유(close/reopen 집행은 메인 오케)
메인 하네스(v65·cfo·…) / 위성(ccu·kk) — ★**Issue # 의 소유자**(오빠 Q1)★: Issue 1건을 받아 해결·완료(close 까지)하는 단위 · 나노를 카드 단위로 spawn(기존 FT_NANO_FEAT 브랜치 규약 그대로 · 나노는 Issue 번호를 몰라도 됨) · 랜딩 PR 「Closes #N」·진행 코멘트·완료 5항 = 메인 오케 책임 · 동시 진행 = 메인 하네스당 Issue 1(issue-manager 규칙)
harness-ops      — 키트(공용 bin·env·설치)·명부 생성기·질문 원장 도구의 «버전»과 «머신 반영» · REQUEST-LEDGER = team:shared-harness Issue 의 «인덱스»(독립 상태 0 · 접수 = Issue 생성)
좌석(arch·da·nano·tester) — 작업 워커(카드 단위 · spawn 게이트 없음) · [HIL] 은 원장 append 만 · 인터뷰 0 · 상시 역할 좌석은 팀 설정 행에 등록
기계(머신)        — 팀 ↔ 머신 배분표(tracked) · 머신 안 통신 = mbox · 머신 간 = Issue 코멘트만(공유 파일 0)
```

### 3-3. 흐름 — 「자는 사이 이슈는 완성돼 사라지고」
```
①등록  오빠/좌석 → Issue(type·team·재현 스텝) ──issue-manager 접수 검사── needs-triage → ready (라벨 비면 반려 코멘트(좌석 등록 한정 · 사람이 GitHub 폼으로 올린 Issue 는 매니저가 라벨을 대신 채움 · 반려 0) · 전이는 매니저만)
②배분  issue-manager → 팀 오케 mbox 1통 「Issue #N · 골좌표 · 닫는 증거」 → in-progress + 팀 라벨 (`type:bug`+`from:member` 는 재현 뒤 team 전이)
③집행  팀 오케(Issue 소유) → 카드로 쪼개 나노 spawn(기존 규약) → 오케가 Issue 에 진행 코멘트 1줄/단위(나노 보고를 오케가 옮김)
④판정  좌석 [HIL] → 원장 append(선택지) → tmm h / planner pane → 오빠 값 → answer → 묻는 좌석 mbox 1통 → applied
⑤검증  오케의 랜딩 PR 「Closes #N」 + DA/tester 코멘트 → review → 머지 = GitHub close
⑥종료  메인 오케가 5항(닫는 사건·PR·재현 PASS·정리·카드) 코멘트를 달고 랜딩 PR 머지로 close → issue-manager 는 close 이벤트를 받아 5항 «대조» + LOOP-LEDGER 색인 → 통과 = done 라벨 · **미비 = 메인 오케에 1통 → 메인 오케가 reopen + `status:review` + 사유 코멘트 집행**(소유 = 메인 오케 · 오빠 Q1)
⑦정리  나노 close(워크트리·좌석·수신함 drain) → 명부에서 사라짐(파생) → 다음 Issue
```
오빠 손이 닿는 곳 = ①(원할 때) 와 ④ 뿐. ④는 원장이 파일이라 자는 동안 쌓이고 깨서 한 번에 답한다. 「머지 = close」는 유지하되 ⑥이 완료 계약을 지킨다(DA 발견 4).

### 3-4. 멀티 머신 — 「메인 하네스를 머신에 독립 배분」
| 항목 | 지금 | 목표 | 선행 |
|---|---|---|---|
| 키트 정본 | FT_BIN = v65 워크트리 gitignored 사본 · v65 리터럴 21/39 | `scripts/harness-install/fable-team/{bin,templates,install.sh}` = main 추적본 1:1 (#816 ⓪ 채택 먼저) · 리터럴 21개는 FT_* 로 치환(폴백 0 · 미설정 = raise) · **`mbox.py` 는 추적본에서 비추적 경로(`.claude/fable-team/`)로 «설치 복사»** — 심링크 dangling 금지 주석(F6) 그대로 | #816/#818 |
| 설치 | 손복사 | `install.sh --team <x> --machine <m>` → `~/.fable-team/<x>/` env + bin 심링크 + tick plist · 드리프트 검사 1줄 | 키트 정본 |
| 배분표 | 없음 | `design/harness/MACHINES.md` 행 = 팀 · 머신 · sha · 반영 시각(RELEASE 「반영됨」 행의 정본) · «독립» = 팀별 홈·명부·mbox·원장 분리(머신 공유 가능 여부 = Q4) | — |
| 통신 | mbox = 머신 로컬 | 머신 안 mbox 그대로 · 머신 간 = Issue 코멘트(+ 후속 층 Slack) · 공유 파일시스템 0 | 3-1 |
| 오빠 접속 | tmm = 로컬 tmux | tmm 에 머신 열(ssh 프로파일) · 질문 원장은 머신별 파일 → Issue `hil:needed` 코멘트로 모음 | 질문 원장 |

### 3-5. 하지 않는 것
- Slack(미러·역방향·보드) — 후속 층. 원장이 생기면 Slack 은 «원장을 읽어 게시하는 어댑터».
- 점수·게이트·면제 목록 · **실행 타이머 0**(경과는 읽을 때 계산해 «표시»만 · 상위화는 이벤트(보고 도착) 때 사람 규칙으로).
- seats-*.json 일괄 삭제 — 설정 행(역할·모델·계보 접두)만 남기고 상태 열은 파생 파일로(구조 커밋 1 · Q5).

### 3-6. 순서(단위 = 커밋 1 · 각 단위 닫는 증거)
1. **질문 원장**(B2·B7): `ft-hil-ask.sh`/`ft-hil-answer.sh` + `tmm h` 가 원장을 읽음 — 닫는 증거: 하위 좌석 질문 1건이 planner pane 과 tmm h 에 동시에 보이고 답이 좌석 seq 로 도달 + applied.
2. **명부 생성기**(B1·B3·B8): `ft-seat-status.sh` → seats.live.json(계보 접두 회원 판정) · 종료 좌석 drain — 닫는 증거: 행 수 = 접두 세션 수 · 종료 수신자 미소비 0.
3. **Issue 전이표 5 + 메인 오케 Closes 규약 + ⑥ reopen**(B4·B5): 라벨 축소 · 메인 오케 랜딩 PR 템플릿에 「Closes #N」 · close 이벤트 5항 검사 — 닫는 증거: 메인 오케가 받은 Issue 의 Closes 연결률 ≥ 80% · reopen 사례 1건 기록. (spawn 게이트 없음 — 오빠 Q1)
4. **키트 정본 + 설치 + 배분표**(B6): #816 ⓪→⑤ — 닫는 증거: 빈 홈(또는 jarvis)에 install.sh 1회로 팀 1개 부팅 보고 + MACHINES 행.

## 4. 오빠 값 (확정 · `VALUES-harness-composition-20261005.md` 8a51bd2f95 · ft-harness-ops#1 인터뷰)

| # | 질문 | 선택지(r2) | 추천 | **오빠 값** |
|---|---|---|---|---|
| Q1 | **Issue 필수 범위** | ①나노·PR 전부 ②메인 하네스 단위만 ③지금처럼 선택 | ① | **③ + 「메인 오케가 이슈번호를 갖고 나노는 작업워커다. 이슈를 해결하고 완료하는 단위는 오케스트 메인이 한다」** → §3-2·§3-3·§3-6 3 반영(spawn 게이트 삭제) |
| Q2 | **오빠가 답하는 자리** | ①planner pane 1곳 + `tmm hil <qid> <번호>`(같은 원장) ②planner pane 만 ③팀 오케 pane 각각 | ① | **①** 확정 |
| Q3 | **대기 가시화** | ①경과 표시만 ②표시 + 이벤트 기반 상위화(타이머 0) ③금지 | ② | **②** 확정(집행 타이머 아님) |
| Q4 | **「독립 배분」의 단위** | ①팀별 독립 홈, 머신 공유 가능 ②팀 1 = 머신 1 ③1대 · 키트·배분표 먼저 | ③→① | **③** 확정(당분간 1대 · 설치 키트 먼저) |
| Q5 | **명부 교체와 설정 소유** | ①바꾼다 · 설정 소유 harness-ops ②바꾼다 · 소유 팀 오케 ③보류 | ① | **①** 확정(구조 커밋 1) |

열린 질문 0. r4 오빠 수락(2026-10-05 · ops#2 #56943). 구현 발주는 보류 — 재개 시 §3-6 순서 1(질문 원장)부터, 발주 주체 = ft-harness-ops.
