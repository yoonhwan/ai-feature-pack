# HANDOFF — byz-harness-master-claude#28 → #29 (2026-10-11 · ctx 402k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
이 단위의 골 축: B(개선요청 접수·협의)+C(업그레이드·커밋·push·반영).
★승계 첫 일 = 골 대조 3줄 + 부팅 3항 + i-have-adhd 를 현역 planner(`byz-planner-master-claude#26` · `ft-harness-info.sh seats` 실측)에 mbox 보고 → 같은 턴 CronCreate 10분 틱(cron=job id) — 전임 크론 `22447b57` 은 세션 종속이라 새로 건다. BOOT 23조항 먼저. 좌석표: `bash .fable-team/bin/ft-seat-retire.sh byz-harness-master-claude#28 byz-harness-master-claude#29 --seats .fable-team/seats-harness.json`(루트에서 · `_master` 만 바뀜).★

## 지금 상태 (한 줄)
R102(이슈 닫기 게이트) 설계 착수 — arch#28 이 설계 중(발주서 `design/harness/ORDER-r102-close-gate-design-20261011.md` · 부팅 보고 받음 · 크론 d85d7212). 나머지 하네스 일은 대기. 하네스 나노 0석.

## 열린 일 (순서)
1. **R102 (판정 1059 · 착수 승인됨)**: 닫는 6항에 «원인 확정 · 같은 증상 보류 0» 두 칸 + 비면 issues 닫기 도구 거절 → «관찰 중» · 관찰 중 닫기 = 오빠 폰 서로 다른 판 2회 재현 0. 흐름: arch#28 설계(`design/harness/PLAN-r102-close-gate-20261011.md`) → DA(`byz-harness-da-codex#1` · bounded: 2회 HOLD 면 중단·3차는 planner 허가) → master 설치(라이브 bin 복사 + 백업 `.bak-r102-<ts>`) → planner#26 에 «설치 끝» 1줄. graphics#4 의 #922 수리와 겹치지 않음. 보고서 `design/harness/REPORT-g922-reopen-why-20261011.md`.
2. **R86 라이브 확인**: planner 가 오빠 입력창 시험 쪽지를 요청할 때만 발송(먼저 보내지 않음) → 통과 뒤 요청 원장 R34·R57·R85 닫기.
3. **접수만(착수 0 · planner 우선순위 대기)**: R82·R84·R88·R89 · 명부 자동 갱신 부재 묶음(R90~R93·R96·R98·R100·R101 — loom 명부 9회) · R94(tcc8 러너 /tmp/tcc8-kept-tab.txt 세트 공통) · R95(DA⑥ 브리프에 «분기 플래그 판별 층 RED» 항목) · R97(mbox send 수신자 검증 부재 — WARN 부터 권고) · R99(CD standing 게이트 옛 리비전 빈 응답 1회 실패 — 재조회 또는 범위 제한).
4. **다른 팀 명부 `_hil_route` 점검**: graphics·ops·loom·feature 는 planner#25 였음(planner 현역 #26) — 각 팀 master 요청이 오면 정정(백업 `.bak-*` + 값 1개만 교체 + 원장 행). 하네스·loom 은 정정 완료.
5. **정리 대기**: graphics 나노 g1227 두 석 워크트리는 정리됨. 브랜치 삭제는 전부 [HIL] 로 보존 중.
6. **묶음 push 대기**: `ops/main-base` 로컬 커밋 다수는 push 금지 브랜치(판정 739) — 코드 랜딩 때 land 가지로 옮겨 같이. 미커밋: `design/graphics/NANO-LEDGER-graphics.md`(도구 자동 기록) · `.serena/project.yml` · `design/ops/`(untracked — 건드리지 않음). `git add` 는 파일 경로 지정, `-A` 금지.

## 이번 세션(#28)에 끝낸 것
g1227 구독 카드 변경 main 랜딩(PR 1230 · main `ba02bd983c`) + 나노 2석·g922·g1087-next-preview 닫기·워크트리 정리 · land 워크트리 4개 정리(오빠 `! bash /tmp/h12`) · feature master#10 개설 · loom 임시 상향(arch→Fable 5.1 max `#22`·DA→`byz-loom-da-codex#0` astra low — 완성 뒤 arch Opus 5.5 high·DA sol 6.1 low 로 복구, 명부 행 `_note`) · ops arch#8 개설 · byztest910 계정 표 추가 · 요청 원장 R93~R102 기록 · #922 재오픈 경위·구멍 보고.

## 운영 규칙·함정 (이번 세션 실측)
- **환경**: `cd .worktrees/harness-ops && source ../../.fable-team/bin-harness/harness-env.sh && export FT_SEND_FROM=byz-harness-master-claude#29` → `$FT_BIN`=`v6-realtime-live/.fable-team/bin`. mbox 정본 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh`(백틱 금지 — 본문은 파일로 쓰고 `relay`).
- ★**루트 `.fable-team/bin` 은 17개짜리 옛 부분 사본**(origin/main 과 99개 어긋남) — 항상 `$FT_BIN`(라이브)에서 실행. CFO 가 이걸로 spawn 하다 «드리프트» REJECT 한 사고(쪽지 74759).
- ★**ft-nano-close 는 «그 팀 env» + «그 팀 master 워크트리»에서**(graphics: `.worktrees/graphics-master` 에서 `source ../../.fable-team/bin-graphics/graphics-env.sh` — 파이프로 source 하면 서브셸이라 FT_BIN 이 비는 함정). 증거 줄 형식: `세트: <40hex> · 시험: <명령> rc=<n> · 이슈: 0`(rc 바로 뒤 « · 이슈:» · 이슈 칸이 줄 끝 · 부가 칸은 위 별도 줄 · 이슈 값은 0 또는 실재 카드 경로). 미랜딩 커밋은 `--cherry-override "<사유>"`(사람 값). `.worktree-info.json` 이 없으면 가드가 `branch=?` — branch 칸 보정.
- ★**astra(gpt-6-astra) 는 effort low 만**(오빠 확정 — ft-role-spawn 이 거부). 새 좌석은 `zsh -lc "tmuxc open <워크트리> --name '<이름>' --agent claude --model '<ID>' --ctx 1m --effort <e>"` + 팀 명부 손 등록(`ft-role-spawn` 은 v65 고정이라 CFO·feature·loom·ops·graphics 는 금지). 부팅 쪽지는 relay 로(골 원문 3줄 선두).
- **명부 정정 표준**: 백업 `<명부>.bak-<표식>-<ts>` → 값 1개만 문자열 치환(assert count==1) → `python3 json.load` 로 키 수 확인 → 원장 행 → 요청자에 1줄.
- **planner 앞 쪽지는 doorbell 0** — 큐에만 쌓임. planner pane 에 send-keys·ring 금지. 같은 요청을 겹쳐 보내지 않음.
- ★**오빠 글 = 쉬운 말 · 번호는 각주 표**. mbox 는 예외.
- **gh**: `unset GH_TOKEN` · 체크 확인과 merge 별 명령(CI 는 `ci` 라벨 때만 — 체크 0건이면 로컬 검증 갈음).
- **[오탐] 파괴 차단 훅**: 쪽지 본문 속 «워크트리 삭제 명령 글자»에도 걸림 — 우회 0 · 문구만 바꿔 재발신.
- ★하위 좌석은 AskUserQuestion 금지 — [HIL] 은 planner#26 로. main 합치기 [HIL·merge] 는 planner 가 모아 오빠께 한 번에(판정 1058) — 다음 일을 막을 때만 «막힘: <무엇>» 1줄.

## 현역 좌석
planner `byz-planner-master-claude#26` · harness arch `byz-harness-arch-claude#28`(설계 중) · arch#27 휴식(ctx 포화 — 정리 후보) · DA `byz-harness-da-codex#1`(대기) · graphics master `#4` · issues master `#13` · loom master `#18`(arch #27 · 임시 DA `byz-loom-da-codex#0`) · cfo master `#72` · ops master `#8`(arch #8) · feature master `#10` · v65 master `#167`+.
