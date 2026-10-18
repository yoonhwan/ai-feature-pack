# PLAN — R14 팀 feature 설치 (arch#6 안 · 2026-10-07 · 미커밋)

## 골 원문 (GOAL-harness.md 복붙)
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

골의 축: 6-b(planner#5 #59383 · 오빠 결정 10-07 19:3x 「신설 · 종합안 그대로 · #856 이관」) · 원문 7(쪼개 동시에).

## 결론
승인(수정 2). 설정 파일 3 + 골 줄 파일 1 로 «설치·master 개설» 은 코드 변경 0 이 맞다. ★단 «코드 변경 0» 은 나노 spawn 까지만 참★ — 첫 feature 나노를 «닫는» 순간 ft-nano-close.sh 251행 v65- 하드코딩에 걸린다(kk 팀 4석 못 닫은 같은 결함). 사유 1줄(planner 회신용): 「설치·개설은 코드 0 · 나노 닫기는 251행 접두 하드코딩 1줄 수정 필요(kk 와 같은 결함) — 첫 나노 닫기 전에 카드 1장」.

## 실측 (전제 — 바이트로 확인)
1. 팀 env 자동 로드(PR 846 · 5663d3f9ce · origin/main): ft-nano-spawn.sh 21~24행이 카드 경로 design/<팀>/indices/ 에서 팀 이름을 뽑아 .fable-team/bin-<팀>/<팀>-env.sh 를 찾는다 · ft-nano-close.sh 30~32행은 좌석명 byz-<팀>-nano- 로 같은 파일. 팀 목록 하드코딩 0 → feature 는 새 코드 0.
2. ★ft-nano-close.sh 251행★ `[[ "$rel" =~ ^v65-${_KEY}(-r[0-9]+)?$ ]]` — 워크트리 접두가 v65- 로 고정(FT_NANO_WT_PREFIX 무시). feature 나노 워크트리(feature-<키>)는 후보에서 빠진다.
3. ★ft-role-spawn.sh 27~29행★ seats.json · design/v65/indices/inbox · SEATBELT-README 가 v65 고정 → feature master·arch 를 이걸로 열면 v65 seats.json 에 행이 들어간다. ★쓰지 않는다★ — harness 팀처럼 tmuxc open 직접 + seats-feature.json 손 등록.
4. ft-tick-install.sh 12행 LABEL=com.byz.ft-tick 고정 · 템플릿에 팀 env 없음 → feature plist 는 이 스크립트로 못 만든다. kk 는 bin-cfo/ft-tick-cfo.plist 를 손으로 포크했다(지금 com.byz.ft-tick-kk.plist.disabled · 로드 0).
5. 라이브 FT_BIN(.worktrees/v6-realtime-live/.fable-team/bin)의 ft-nano-spawn.sh 에는 자동 로드 줄이 0(추적본 1) — 모든 팀 env 가 같은 FT_BIN 을 가리킨다. 그래서 feature 도 «env 파일을 먼저 source» 하는 지금 방식 그대로 써야 한다(FT_NANO_PREFIX 가 이미 있으면 자동 로드는 건너뛴다 — 결과 같음).
6. ★골 파일이 main 에 없다★: design/feature/GOAL-feature.md 는 98ce0131c8(feat/v6-realtime-live)에만 있다 · origin/main·harness-ops 0. feature 워크트리 base = 최신 main 이면 카드 lint 의 ledger 파일이 없다.
7. ★골 절이 한 단락(2문장)★ — 카드 lint 는 골 3줄을 요구(FT_GOAL_LINES_FILE 3행).
8. seats-*.json 은 ft-seat-live·ft-seat-request 가 glob 으로 읽음(목록 0) · team:feature 라벨은 별칭 없이 그대로 feature.
9. 곁가지(별건): seats-harness.json 의 _master=#8 · _arch=#5 가 승계 뒤에도 옛 이름(현역 #9·#6) — 이 칸을 읽는 도구가 옛 좌석으로 보낸다(BOOT 13 실측 사례와 같은 종류).

## ① 설치할 파일·값 표
| 경로 | 값 | 되돌림 |
|---|---|---|
| R/.fable-team/seats-feature.json | _name Seatbelt-FEATURE · _version 1.0.0 · _doc(팀·카드·env 경로 · 「틱 = com.byz.ft-tick-feature」) · _master byz-feature-master-claude#0 · _arch (arch 개설 뒤 기입) · _hil_route byz-planner-master-claude#5(harness·issues 와 같음 — 승계 시 현역 확인) · 행: master#0 {role master · agent claude · model claude-sonnet-5-5[1m] · tick ft-master-tick · index design/feature/indices/} | 파일 삭제(rm = HIL 경로) 또는 _doc 에 CLOSED |
| R/.fable-team/bin-feature/feature-env.sh | harness-env.sh 포크: FT_SEATS_JSON=…/seats-feature.json · FT_NANO_PREFIX=byz-feature-nano- · FT_NANO_WT_PREFIX=feature- · FT_ACTIVE_TAG=@zc_feature_active · FT_NANO_LEDGER_WT=R/.worktrees/feature-main(아래) · FT_NANO_LEDGER=design/feature/NANO-LEDGER-feature.md · FT_GOAL_LEDGER=design/feature/GOAL-feature.md · FT_GOAL_LINES_FILE=R/.fable-team/bin-feature/goal-lines-feature.txt · FT_IMPL_MODEL='claude-sonnet-5-5[1m]' · FT_SEND_FROM='byz-feature-master-claude#0' · FT_BIN=(다른 팀과 같은 값) · FT_NANO_FEAT=(feature 워크트리 브랜치) | 파일 삭제 |
| R/.fable-team/bin-feature/goal-lines-feature.txt | 3행 — 아래 ⓖ | 파일 삭제 |
| R/.fable-team/bin-feature/{ft-tick.sh · ft-seat-status.sh} | bin-cfo 의 같은 이름 파일 cp+cmp(라이브로 돌고 있는 판) · ft-goal-tick-feature.sh = kk 처럼 exit 0 스텁(골 대조 자동화 없음 · 주석 1줄) | 파일 삭제 |
| ~/Library/LaunchAgents/com.byz.ft-tick-feature.plist (+ 사본 bin-feature/ft-tick-feature.plist) | bin-kk/ft-tick-kk.plist 포크 — kk→feature 치환(Label · FT_TICK_SEATS · GOAL_TICK · SEAT_STATUS · PIDFILE /tmp/ft-tick-feature.pid · STAMP_PREFIX · 로그 /tmp/ft-tick-feature.log · MASTER_MSG/PM_MSG 의 팀 이름) · 간격 kk 값 그대로 · plutil -lint → launchctl bootstrap gui/$UID | launchctl bootout gui/$UID/com.byz.ft-tick-feature + 파일을 .disabled 로(kk 와 같은 처리) |
| 워크트리 R/.worktrees/feature-main · 브랜치 feat/feature-main ← 최신 origin/main | baton wt-create 또는 git worktree add + .venv·venv·.env 심링크 + .worktree-info.json | git worktree remove 는 HIL(브랜치 보존) |
| 그 워크트리 design/feature/{GOAL-feature.md · NANO-LEDGER-feature.md · indices/{대기,진행,완성}/} | GOAL = 98ce0131c8 판 바이트 그대로(git show 로 꺼냄) · 원장은 머리줄만 | git revert |
- ★launchd 는 오빠 승인 범위 안★: 오빠 결정 「종합안 그대로」 의 6번에 「설정 파일 3(seats·env·plist)」 가 명시돼 있다 → plist 설치 = 오빠 값. bootstrap 은 비파괴·bootout 으로 되돌림. 막히면(승인 창·훅) §7 경로.
- ★골 파일을 main 에 먼저★(실측 6): GOAL-feature.md 를 main 에 docs 커밋으로 올린 뒤 feature 워크트리를 딴다(planner 커밋 98ce0131c8 의 이 파일만 · BOARD·STRUCTURE 는 planner 몫이라 손대지 않음). 아니면 lint 의 ledger 가 없다.

## ⓖ 골 3줄 (goal-lines-feature.txt · 카드 「골 원문」 절 · ★planner 확인 1회 필요★)
GOAL-feature.md 「## 골」 은 2문장 한 단락이다. 줄을 «나누기만» 하고 3행째는 같은 파일의 오빠 원문 줄을 쓴다 — 새 문장 0:
1. 중형 이상의 신규 개발 피처를 v65(실시간 정합)·CFO(과금·운영툴)와 분리해 «설계 → 구현 → PR» 까지 끝내는 팀.
2. 제품 발행 경로·상태 머신은 건드리지 않는다.
3. 「856 이슈같은 중형이상의 개발 피처를 처리할 메인팀 하나 만드는거 어떤지」
골 파일은 불변이라 고치지 않는다 — 이 3줄 분할이 오빠 값을 벗어나는지만 planner 가 1회 확인(벗어나면 planner 가 골 파일 3줄 절을 오빠께 받는다).

## ② 「코드 변경 0」 전제 판정
- 설치·master 개설: 참(위 표 = 설정·문서만).
- 나노 spawn: 참(PR 846 자동 로드 · env source 방식이면 라이브 FT_BIN 에서도 동작).
- 나노 close: ★거짓★ — 251행 v65- 고정. 카드 1장(feature 첫 나노 닫기 «전»): 251행을 `${FT_NANO_WT_PREFIX:-v65-}` 로 · 시험 = test_nano_team_env.sh 에 feature-<키> 워크트리 사례. ★같은 파일을 진행 중인 나노 nano-close-named-wt 가 고치고 있다★ → 그 랜딩 뒤 base 로 따로(진행 중 카드에 범위 추가 0).
- role-spawn: 쓰지 않음(실측 3) — arch·DA 좌석도 tmuxc open + seats-feature.json 손 등록. 나중에 팀 일반화가 필요하면 별건(FT_SEATS_JSON·inbox 를 env 로).
- tick install 스크립트: 쓰지 않음(실측 4 · 손 포크).

## ③ master 첫 부팅 발주문 초안 (master#9 가 보냄 · 본문 그대로)
```
[byz-harness-master-claude#9->byz-feature-master-claude#0] 신설 팀 feature 오케 부팅 발주
★골 원문 (design/feature/GOAL-feature.md 「골」 · 읽기 전엔 착수 금지)★
> 중형 이상의 신규 개발 피처를 v65(실시간 정합)·CFO(과금·운영툴)와 분리해 «설계 → 구현 → PR» 까지 끝내는 팀.
> 제품 발행 경로·상태 머신은 건드리지 않는다.
> 「856 이슈같은 중형이상의 개발 피처를 처리할 메인팀 하나 만드는거 어떤지」
1. 먼저 읽을 것: ~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md(16조항 · 전문 COMM-GUIDE.md 는 열지 않는다) → 골 파일 전체(진입 기준·경계·로스터·접수 경로) → ~/.claude/skills/fable-team/references/main-team-governance.md §1·§2·§6·§7.
2. 첫 일: 부팅 보고(세션명 byz-feature-master-claude#0 / 모델·창 / Serena 가부 + i-have-adhd / 골 대조 1줄 / cron=<job id>)를 byz-planner-master-claude#5(현역 확인: ft-harness-info.sh seats) 에 mbox — 보고 전 착수 0.
3. ★체크 크론★: 부팅 보고 그 턴에 CronCreate 10분 틱(mbox recv + 하위 pane 실측 + 오빠 3줄) — 없으면 착수 0(BOOT 16).
4. 자리: seats = R/.fable-team/seats-feature.json · env = R/.fable-team/bin-feature/feature-env.sh(나노·도구 실행 전 source) · 카드 = R/.worktrees/feature-main/design/feature/indices/ · 나노 접두 byz-feature-nano- · 나노 ≤3(claude-sonnet-5-5[1m]) · DA = v65 DA 계보 공유(새 DA 좌석 열기 전 planner 에 확인).
5. 경계: 오디오 press 0(단위 시험·화면 캡처만 · 필요하면 v65 press 순번 요청) · v65 코드 겹치면 PR 까지만(v65 가 랜딩 주체) · 그 외 main 랜딩은 Tank PR + 로컬 verify · CFO 영역 0.
6. 첫 단위: Issue #856 — 배정은 planner 가 보낸다(받기 전 착수 0 · 이슈 진입로 ③ 컨펌 게이트).
7. 주의: ft-role-spawn.sh 는 v65 전용(seats.json·v65 inbox 고정) — arch 좌석은 master#9 에 개설 요청. 나노 닫기는 ft-nano-close 251행 수정 카드 랜딩 «뒤» 부터.
```

## 집행 순서 (master)
①GOAL-feature.md main docs 커밋 → ②feature-main 워크트리 → ③bin-feature 4 파일 + goal-lines(planner 확인 뒤) + seats-feature.json → ④plist bootstrap + launchctl print 로 state=running 확인 → ⑤tmuxc open byz-feature-master-claude#0(--model claude-sonnet-5-5[1m] --effort high --ctx 1m) → ⑥③ 발주문 send → ⑦부팅 보고 recv(cron= 칸 실재)를 planner 가 받았는지 확인 → ⑧planner 에 좌석명 + 사유 1줄 회신. 카드: ft-nano-close 251행(nano-close-named-wt 랜딩 뒤).
