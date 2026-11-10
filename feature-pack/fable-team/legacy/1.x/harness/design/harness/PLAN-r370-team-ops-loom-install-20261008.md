# PLAN — 판정 370 메인 팀 ops · loom 설치 (byz-harness-arch-claude#11 안 · 2026-10-08)

## 골 원문 (GOAL-harness.md 복붙)
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

골의 축: 6-b(planner#8 → master#13 #61405 · 오빠 결정 판정 370 「확정 — 설치 발주」) · 원문 7(쪼개 동시에). 제안서 = planner `PROPOSAL-team-ops-loom-20261008.md`.

## 결론
설치·master/arch 개설은 **코드 변경 0** 이 맞다(전례 feature = PLAN-r14 · 그 뒤 r14 의 코드 결함 2건은 해소됨 — 아래 실측 2). 팀마다 설정 파일 5 + 골 문서 1 + 워크트리 1. ★한 가지 바꿈★: 나노 워크트리 접두를 `ops-`·`loom-` 가 아니라 `ops-nano-`·`loom-nano-` 로(실측 4 — 기존 워크트리 11개와 이름 공간 겹침).

## 실측 (2026-10-08 · 바이트 확인)
1. 팀 목록 하드코딩 0: 라이브 FT_BIN·scripts/fable-team-bin 에서 팀 이름을 나열하는 곳 없음(feature 단어는 ft-lib 의 «feature slug» 뜻뿐). seats-*.json 은 glob 으로 읽힘.
2. r14 결함 해소: ft-nano-close.sh 62·281행이 `FT_NANO_WT_PREFIX` 를 씀(옛 251행 v65- 고정 사라짐) · ft-nano-spawn.sh 132행도 같은 env. ★ft-role-spawn.sh 는 여전히 v65 고정★(27~29행 seats.json·design/v65/indices/inbox) → 쓰지 않는다(tmuxc open + 손 등록 — feature·harness 와 같음).
3. 이름 검사: `ft-name-lint.sh` → byz-ops-master-claude#0 · byz-loom-arch-claude#0 · byz-ops-nano-x#0 전부 PASS · 라이브 tmux 에 byz-ops-/byz-loom- 세션 0.
4. ★이름 공간 겹침★: 기존 워크트리 `ops-*` 9개(ops-accounts-pr1 · ops-magazine(하네스 매거진) · ops-domain-dynamic-s* …) · `loom-*` 2개(loom-domain-hierarchy · loom-suwon-ye-dental). 접두를 `ops-`/`loom-` 로 두면 나노 slug 가 기존 이름과 같을 때(예: magazine) spawn 이 기존 워크트리 자리에 부딪힌다 → 접두 `ops-nano-`·`loom-nano-`. 팀 메인 워크트리 브랜치는 `feat/ops-main`·`feat/loom-main`(하네스의 `ops/*` 브랜치 이름 공간과 안 겹침 — `ops` 단독 브랜치를 만들지 않는다).
5. feature 틱 plist 의 뉴스 문구에 `mbox recv byz-feature-master-claude#0` 고정 — 지금 feature master 는 #2. 새 두 팀은 문구에 번호를 쓰지 않고 「seats-<팀>.json 의 _master」 로 적는다. (feature plist 자체는 별건 — 아래 곁가지.)
6. FT_CARD_REQUIRE_PREVERIFY=1(R16) · FT_GOAL_LINES_FILE(R20) — feature env 에 둘 다 있음 → 새 두 팀도 처음부터 넣는다(R20 같은 사후 REJECT 방지).

## ① 전례 대조표 (feature → ops · loom)
| 항목 | feature (전례) | ops | loom |
|---|---|---|---|
| 좌석 접두 · 라벨 | byz-feature- · team:feature | byz-ops- · team:ops | byz-loom- · team:loom |
| seats 파일 | .fable-team/seats-feature.json | seats-ops.json | seats-loom.json |
| env | bin-feature/feature-env.sh | bin-ops/ops-env.sh | bin-loom/loom-env.sh |
| 나노 접두 · 워크트리 접두 | byz-feature-nano- · feature- | byz-ops-nano- · ★ops-nano-★ | byz-loom-nano- · ★loom-nano-★ |
| active tag | @zc_feature_active | @zc_ops_active | @zc_loom_active |
| 팀 워크트리 · 브랜치 | .worktrees/feature-main · feat/feature-main | .worktrees/ops-main · feat/ops-main | .worktrees/loom-main · feat/loom-main |
| 골 문서 · 원장 | design/feature/GOAL-feature.md · NANO-LEDGER-feature.md | design/ops/GOAL-ops.md · NANO-LEDGER-ops.md | design/loom/GOAL-loom.md · NANO-LEDGER-loom.md |
| 골 3줄 파일 | bin-feature/goal-lines-feature.txt | bin-ops/goal-lines-ops.txt | bin-loom/goal-lines-loom.txt |
| 틱 plist | com.byz.ft-tick-feature · /tmp/ft-tick-feature.{pid,log} | com.byz.ft-tick-ops | com.byz.ft-tick-loom |
| 로스터 | master Sonnet 5.5 · arch Opus 5.5 · DA 공유 · 나노 ≤3 Sonnet 5.5 | 같음 | 같음 |
| _hil_route | byz-planner-master-claude#8 | 같음(설치 때 현역 확인) | 같음 |
| base | 최신 main | 최신 main | 최신 main |

## ② 파일 목록 (팀마다 · `<t>` = ops | loom · R = 리포 루트)
| 경로 | 값 | 되돌림 |
|---|---|---|
| R/.fable-team/seats-<t>.json | seats-feature.json 포크 · 행은 master#0 하나로 시작 · _name Seatbelt-<T> · _doc(팀 설명 = 제안서 §1 «맡는 것» 원문 · 틱·카드·env·골 경로 · 「ft-role-spawn 쓰지 않음」) · _master byz-<t>-master-claude#0 · _arch(개설 뒤 기입) · _hil_route 현역 planner | _doc 에 CLOSED (삭제는 HIL) |
| R/.fable-team/bin-<t>/<t>-env.sh | feature-env.sh 를 위 표 값으로 치환(FT_SEATS_JSON · FT_NANO_PREFIX · FT_NANO_WT_PREFIX · FT_ACTIVE_TAG · FT_NANO_LEDGER_WT · FT_NANO_LEDGER · FT_GOAL_LEDGER · FT_SEND_FROM=byz-<t>-master-claude#0 · FT_NANO_FEAT=feat/<t>-main · FT_GOAL_LINES_FILE · FT_MBOX_SH · FT_CARD_REQUIRE_PREVERIFY=1 · FT_BIN·FT_IMPL_MODEL 그대로) | 파일 .disabled |
| R/.fable-team/bin-<t>/goal-lines-<t>.txt | 아래 ⓖ 3줄 | 같이 |
| R/.fable-team/bin-<t>/{ft-tick.sh · ft-seat-status.sh} | bin-feature 의 같은 파일 cp+cmp | 같이 |
| R/.fable-team/bin-<t>/ft-goal-tick-<t>.sh | bin-feature/ft-goal-tick-feature.sh 포크(exit 0 스텁) | 같이 |
| ~/Library/LaunchAgents/com.byz.ft-tick-<t>.plist (+ 사본 bin-<t>/ft-tick-<t>.plist) | feature plist 를 sed `feature→<t>` 치환 뒤 뉴스·pm 문구 2개만 손으로: 팀 설명 = 제안서 §1 «맡는 것» 한 줄 · `mbox recv byz-feature-master-claude#0` → 「seats-<t>.json 의 _master 로 mbox recv」(번호 고정 금지 — 실측 5) · `plutil -lint` → `launchctl bootstrap gui/$UID` → `launchctl print` state | `launchctl bootout gui/$UID/com.byz.ft-tick-<t>` + .disabled |
| R/.worktrees/<t>-main (feat/<t>-main ← origin/main) | git worktree add + .venv·venv·.env 심링크 + .worktree-info.json(purpose = 팀 <t> 정본 줄기) | worktree remove 는 HIL(브랜치 보존) |
| 그 워크트리 design/<t>/{GOAL-<t>.md · NANO-LEDGER-<t>.md · indices/{대기,진행,완성}/.gitkeep} | GOAL = GOAL-feature.md 틀(머리 · 오빠 원문 · ## 골 원문 3줄 · 맡는 것/안 맡는 것 = 제안서 §1 표 그 행 원문 · ops↔loom 계약 = 제안서 §1 「ops ↔ loom 계약」 원문 · 순서 = §4 원문 · 로스터 · 접수 경로 진입로 ③) · 원장 머리줄만 | git revert |
- ★골 문서를 main 에 먼저★(r14 실측 6 과 같은 이유 — 카드 lint 의 ledger 파일이 팀 워크트리에 있어야 함): GOAL-ops.md · GOAL-loom.md 를 main 에 docs 커밋 1개로 올린 «뒤» 팀 워크트리를 딴다. 쓰는 손 = planner(골 문서는 planner 소관 · 하네스는 문안 초안만) — planner 가 다르게 정하면 그 값.
- launchd 는 오빠 값 범위 안: 제안서 §3 「틱 plist 1」 명시 · 판정 370 「확정 — 설치 발주」.

## ⓖ 골 3줄 (두 팀 같은 3줄 · 발주 #61405 「골=제안서 오빠 원문 3줄 복붙」 · 새 문장 0)
1. 「사실 이게 연결되려면 운영툴이 우선순위로 loom 관리, rag 관리로 실제 연동연결 완성되고 그후순위인 rag가 완성되어 연결 완성. db에 완전히 loom을 레디스에서 db로 이관 완료 되야 실제 런타임에 연결하고 테스트하는것. 이것을 계획 메인팀 배정 고민하자 cfo에서 분리」
2. 「메인 팀 loom 신설」
3. 「아 운영툴도 메인팀으로해서 구성 다시 정리. 운영툴도 충분히 메인팀이 되어야한다」
- 팀별 차이는 골 줄이 아니라 GOAL 문서의 «맡는 것/안 맡는 것» 절(제안서 §1 행 원문)로 둔다. goal-lines 파일 = 이 3줄 바이트 그대로 · 카드 「골 원문」 절도 같은 3줄.

## ③ 좌석 개설 순서 (master#13 집행 · 팀마다 · ops 먼저 — 순서 ① 이 ops)
1. planner 가 GOAL-ops.md · GOAL-loom.md main 커밋(또는 하네스 초안 승인) → sha 확인.
2. `git worktree add .worktrees/<t>-main -b feat/<t>-main origin/main` + 심링크 3 + .worktree-info.json + design/<t>/ 원장·indices 머리 커밋(팀 브랜치 · push 는 첫 랜딩 때).
3. bin-<t>/ 6파일 + seats-<t>.json 설치(cp+cmp) · `bash -n <t>-env.sh` · `source` 뒤 `bash $FT_BIN/ft-index-lint.sh` 에 골 3줄 든 빈 시험 카드(scratchpad) → OK 확인(R20 재발 방지).
4. plist bootstrap → `launchctl print gui/$UID/com.byz.ft-tick-<t>` state·last exit 확인.
5. `tmuxc open <R>/.worktrees/<t>-main --name byz-<t>-master-claude#0 --agent claude --model 'claude-sonnet-5-5[1m]' --ctx 1m --effort high`(zsh -lc 로 감쌈) → 아래 ④ 발주문 send.
6. 부팅 보고(cron= 칸 실재)가 planner 에 도착했는지 확인 = ★설치 완료★(발주 #61405 정의).
7. arch: master 가 요청하면 `tmuxc open … --name byz-<t>-arch-claude#0 --model 'claude-opus-5-5[1m]' --effort high` + seats-<t>.json _arch·행 손 등록.
8. issues master 에 라벨 team:ops · team:loom 신설 통지(재배정은 issues master 몫) · planner 에 좌석명 2개 회신.

## ④ master 부팅 발주문 초안 (팀마다 · PLAN-r14 ③ 틀에서 바꾼 줄만)
- 머리: `[byz-harness-master-claude#13->byz-<t>-master-claude#0] 신설 메인 팀 <t> 오케 부팅 발주` + ⓖ 3줄 그대로.
- 1 읽을 것: COMM-GUIDE-BOOT.md(17조항) → design/<t>/GOAL-<t>.md 전체 → planner PROPOSAL-team-ops-loom-20261008.md §1·§2·§4 → main-team-governance.md §1·§2·§6·§7.
- 2·3 부팅 보고 + CronCreate 10분 틱 → 현역 planner(ft-harness-info.sh seats).
- 4 자리: seats-<t>.json · bin-<t>/<t>-env.sh(나노·도구 전 source) · 카드 .worktrees/<t>-main/design/<t>/indices/ · 나노 접두 byz-<t>-nano- · 워크트리 <t>-nano-<slug>.
- 5 경계: 제안서 §1 그 팀 행 «안 맡는 것» 원문 · 오디오 press 0 · v65 발행 경로·상태 머신은 PR 까지.
- 6 첫 단위: planner 배정 뒤에만. ops = 순서 ① loom 관리 API 계약 1장은 «loom 이 먼저 씀» → ops 첫 일은 그 계약 대기 동안 #777·#791 · loom = 계약 1장 → ② Redis→DB 이관.
- 7 주의: ft-role-spawn.sh 쓰지 않음(v65 고정) — arch 좌석은 harness master 에 개설 요청.

## 되돌림 (코드 변경 0 → 전부 설정 되돌리기)
plist bootout + .disabled → 좌석 세션 kill(표준승인 범위: tmux kill-session · keep-last-2 는 계보 #0 하나라 해당 없음 — 그래도 오빠 결정 되돌림이면 planner 경유) → seats-<t>.json _doc CLOSED · env .disabled → 라벨 되돌림(issues master) · 워크트리·브랜치 삭제는 HIL.

## 위험·열린 것
- CFO 골 2줄(「고객사마다 운영툴에서 용어집·지식(RAG)을 관리한다 …」)은 이제 ops·loom 영역 — CFO 골 문서는 불변이라 고치지 않는다. 경계는 STRUCTURE §1-1(planner)이 정본 · CFO 카드 lint 는 영향 없음.
- 나노 동시 수: 메인 팀 5 × 나노 ≤3 = 최대 15 — 오디오 press 0 이라 장치 충돌 없음 · 포트는 나노가 서버를 띄울 때만(38301~ 레인지 규칙 그대로).
- 곁가지(별건 · 이 설치 범위 밖): feature 틱 plist 뉴스 문구가 byz-feature-master-claude#0 고정(현역 #2) → 뉴스 틱이 옛 좌석 mbox 를 recv. 요청 원장에 R 한 줄로 올릴지 master 판단.

## ⑤ 판정 372 하네스 몫 2건 (master#13 #61420 · arch#11)
1. **main-team-governance.md 초안** `design/teams/harness/drafts/r372-governance/main-team-governance.md` — 실측: 홈 정본에 «팀 표»가 없다(§1 은 오케 이름 목록 1줄뿐 · 팀 «맡는 것» 표 정본 = 프로젝트 STRUCTURE §1-1 = planner 소관). 그래서 ①머리에 판정 370·372 줄(정본 머리 규칙 «오빠 값 1회») ②§1 오케 이름 목록에 feature·ops·loom 추가(feature 도 빠져 있었음) ③§1-1 «메인 팀 하네스 값» 표 신설(접두·라벨·명부·골·경계 1줄 · ops·loom 2행 + 기존 메인 팀 4행 — ★2행만 넣으면 «팀 표»가 두 팀뿐인 것처럼 읽혀 기존 행을 같이 둠 · 2행만 원하면 다른 행 삭제★). diff = 추가 13줄 + §1 1줄 교체.
2. **ft-harness-info.sh — 코드 0**: `seats` = `tmux ls` 전부 + `ft-name-lint`(팀 목록 없음) → byz-ops-·byz-loom- 좌석은 열리는 즉시 노출(이름 lint PASS 실측) · `rules` 의 MAIN_CANON 은 팀 골 파일을 원래 안 넣음(cfo·feature 도 없음) → 바꿀 것 0 · `map` = harness-map.md 출력이라 팀 줄이 없다 → 홈 초안 `drafts/r372-governance/harness-map.md` 에 1행 추가(메인 팀 목록 → governance §1-1).
- 설치: 홈 2파일 `.bak-1008-r372` → cp → cmp · 설치 PR 은 PLAN-r370 과 같은 PR.
- 곁가지: 라벨 `team:harness-ops`(하네스 팀)와 `team:ops`(운영툴 팀)가 이름이 비슷 — issues master 분류 때 혼동 주의 1줄(라벨 개명은 범위 밖).
