# HANDOFF — byz-harness-master-claude#27 → #28 (2026-10-11 · ctx 406k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
이 단위의 골 축: B(개선요청 접수·협의)+C(업그레이드·커밋·push·반영).
★승계 첫 일 = 골 대조 3줄 + 부팅 3항 + i-have-adhd 를 현역 planner(`byz-planner-master-claude#24` · `ft-harness-info.sh seats` 실측)에 mbox 보고 → 같은 턴 CronCreate 10분 틱(cron=job id). 전임 크론 `3db4e097` 은 세션 종속이라 새로 건다. BOOT 23조항 먼저. 좌석표 교체: 루트에서 `bash .fable-team/bin/ft-seat-retire.sh byz-harness-master-claude#27 byz-harness-master-claude#28 --seats .fable-team/seats-harness.json`(`_master` 만 바뀜).★

## 지금 상태 (한 줄)
R87(LOOM 터널 launchd)·g1087 시안·g1087 FE 전부 main 랜딩·라이브 반영·나노 닫음. 하네스 나노 0석 · arch#27 휴식(ctx 422k+ · 크론 삭제 차단으로 틱 1줄만) · da#1 대기. 열린 건 아래.

## 열린 일 (순서)
1. **g1227 구독 카드 변경 묶음 push 승인 대기(쪽지 #73988 → planner#24)**: land 가지 `land/g1227-card-change-fe2` `96c8729f68`(origin/main `8f9e92f761` 위 · squash 1커밋 · 103파일 나노 `nano/g1227-card-change-fe` HEAD `5d7df0ad9e` 와 동일 · tsc 0 · ESLint 오류 0 · Jest credit 433건 전체 병렬 3회 통과) · 워크트리 `.worktrees/harness-land-g1227fe2` · 원격 push 0. 값 오면: `unset GH_TOKEN` → `git fetch` main 이동 확인(`merge-tree --write-tree`) → push → `gh pr create --body-file`(Refs #1227) → `gh pr checks` 별 명령(Actions 미실행이면 0건 — 로컬 검증으로 갈음) → `gh pr merge --squash` 별 명령 → 파일별 대조 → graphics#3 에 랜딩 sha 회신(연동 나노 base) → 그 뒤 graphics#3 이 나노 2석(`byz-graphics-nano-g1227-card-change-preview#0`·`…-fe#0`) 닫기 요청. 닫기는 graphics 환경(`source .fable-team/bin-graphics/graphics-env.sh`)에서 `$FT_BIN/ft-nano-close.sh … --result <graphics-master 의 진행/ 카드 절대경로> --recv <seq> --cherry-override "…"`(카드 증거 줄 = `세트: <나노 HEAD 40hex> · 시험: <명령> rc=0 · 이슈: 0`, 나노 워크트리 3분 내 편집이면 정지 3분 뒤 재시도).
2. **R86 라이브 확인**: planner 가 오빠가 입력창에 칠 때 «시험 쪽지 1통 보내 달라» 고 알리면 발송(그 전엔 먼저 보내지 않음) → 입력창 글자 그대로·세션 안 알림 1건 확인 → 통과 뒤 요청 원장 R34·R57·R85 닫기 + BOOT·governance 에 1줄.
3. **접수만 된 요청(착수 0 · planner 우선순위 대기)**: R82(게이트 ft-proposal-gate.sh:138) · R84(팀 명부에 역할 행 없으면 ft-role-spawn 이 다른 팀 명부로 떨어지지 말고 REJECT) · R88(ft-index-lint.sh ⑥ base ref 기준 경로 확인 — cfo master#69) · R89(install.sh watchdog tmo1: 부모가 먼저 끝나면 TERM 무시 자식이 고아로 남음 — 이미 끝난 라이브 설치엔 영향 0) · R90·R91·R92(승계 때 팀 명부 `_master`·`_arch`·`_hil_route` 자동 갱신 부재 — 같은 줄기 반복 4회, 재발 방지 후보 1건으로 묶음).
4. **R87 카드**: `design/teams/harness/indices/진행/r87-loom-tunnel-launchd.md` 진행/ 유지 — 완성 이동은 DA 판정문 §N 닫힘이 필요(DA 는 2회 HOLD 로 중단 · planner 판정 942 = R87 완료로 마감 · 카드 이동은 필요하면 planner 판단).
5. **정리 대기(삭제 = [HIL] · 훅이 워크트리 삭제 명령 차단)**: land 워크트리 4개 `harness-land-g1087fe`(PR 1225 머지) · `harness-land-g1227`(폐기 a4ec34010a) · `harness-land-g1227fe`(폐기 2def89fb54) · 그리고 위 1번 처리 뒤 `g1227fe2`. 방법: 짧은 계획 파일을 만들고 `bash $FT_BIN/ft-hil.sh --add <파일>` → `! bash /tmp/h<N>` 1줄을 planner 경유 오빠께(10-11 선례: 13개 정리 /tmp/h10 · 판정 941·946). 가지는 보존. 또 나노 워크트리 3개(g1087-next-preview·g1087-orders-fe 등)는 ft-wt-sweep 이 재시도.
6. **묶음 push 대기(판정 739)**: `ops/main-base` 로컬 커밋 약 680개는 push 금지 브랜치 — 코드 랜딩 때 land 가지로 옮겨 같이 올린다(R80~R87 선례). 미커밋: `NANO-LEDGER-harness.md` · `NANO-LEDGER-graphics.md`(도구 자동 기록 — 다음 land 때 같이 · 커밋 시 `git add` 는 파일 경로 지정, `-A` 는 훅이 차단).

## 이번 세션(#27)에 끝낸 것
g1087 시안 PR 1205 main `744af6211c` + 나노 닫기 · R87 LOOM 터널 launchd(제안 #1213 · 오빠 판정 913·934 · 나노 r1·r2 · DA 2회 HOLD→bounded 중단 · PR 1221 main `edda18c4a1` · 실머신 설치 16:29 — launchd=loaded · 옛 세션 터널 pid 85243 넘겨받음 · 이후 ssh 1회 끊김 → launchd 자동 재연결 pid 7157 · gateway PoolTimeout 0 · 내 초기 보고 «이관 뒤 PoolTimeout 0» 은 16:30:54 경고 6건이 있어 정정함) · g1087 FE PR 1225 main `aeae2b7d9b`(CFO 인수 시험 PASS) + 나노 닫기 · land 워크트리 13개 정리(오빠 `! bash /tmp/h10`) · 요청 원장 R87~R92 기록 · loom 명부 값 정정 3회(#13·#14·#20) · harness 명부 `_hil_route` → planner#24. 다음 번호: 요청 원장 R93 · 판정서 §117+(미확인) · 라이브 bin 백업 `.bak-r81/r83/r86-<ts>`.

## 운영 규칙·함정 (이번 세션 실측)
- **환경**: `cd .worktrees/harness-ops && source ../../.fable-team/bin-harness/harness-env.sh && export FT_SEND_FROM=byz-harness-master-claude#28` → `$FT_BIN`=`v6-realtime-live/.fable-team/bin`. mbox 정본 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh`.
- ★**ft-nano-close 는 «그 팀 env»에서**: 루트 `.fable-team/bin/ft-nano-close.sh` 는 10-08 옛 부분 사본(드리프트 REJECT) — 항상 `$FT_BIN`(라이브). harness env 에서는 `byz-harness-nano-*` 만 닫는다 → graphics 나노는 `graphics-env.sh`, 카드는 graphics-master 워크트리(`.worktrees/graphics-master`, untracked)에서 찾는다.
- ★**planner 앞 쪽지는 doorbell 0** — 큐에만 쌓이고 planner 는 Monitor·틱으로 읽음. planner pane 에 send-keys·ring 금지(오빠 입력 절단). planner 무응답이 길어도 같은 요청을 겹쳐 보내지 않는다.
- ★**오빠 글 = 쉬운 말 · 번호는 각주 표**(번호·R·r1 본문 0). mbox 는 예외.
- **[오탐] 파괴 차단 훅**: 쪽지·heredoc 본문 속 «워크트리 삭제 명령 글자»에도 걸림 — 우회 0 · 문구만 바꿔 재발신 + 쪽지에 오탐 알림 1줄. 실제 삭제는 사람 `!`.
- **land 가지 준비 표준**: `git worktree add .worktrees/harness-land-<x> -b land/<x> origin/main` → `git merge --squash <나노>` → 파일별 `git diff --quiet <나노>:<f> :<f>` 로 동일 확인 → 웹이면 `clients/web/node_modules` 심링크(`c-level-planning` 의 것) 후 tsc·eslint·jest(credit 범위 — 전체 `tests/` 금지) → 심링크 제거 → `git add <경로들>` → 커밋(본문 Why/What/Verify/Impact) → planner `[HIL·push]`. 워크트리에 `.venv`·`.env` 심링크가 없으면 `loom-tunnel/install.sh status` 의 select1 이 fail 로 나온다(터널 문제 아님).
- **gh**: `unset GH_TOKEN` · 체크 확인과 merge 별 명령(Actions 쿼터로 체크 0건일 수 있음 — mergeable CLEAN 이면 로컬 검증 갈음) · squash 뒤 «우리 파일» 대조.
- **터널 상태 확인**: 아무 워크트리에서 `bash <그 워크트리>/scripts/harness-install/loom-tunnel/install.sh status` → `launchd=loaded listen=<pid> select1=ok`. 38309 는 launchd 소유 — 세션에서 열고 닫지 않음 · 일회성 DB 터널은 38301~38399 빈 포트.
- ★하위 좌석은 AskUserQuestion 금지 — [HIL] 은 planner#24 로. DA 3회 HOLD 규칙: bounded, 2회 HOLD 면 중단·3차는 planner 허가.
- **zsh**: `$B:path` 수정자 · `$F` 단어 분리 안 됨 → 파이프+xargs.

## 현역 좌석
planner `byz-planner-master-claude#24` · harness arch `byz-harness-arch-claude#27`(Opus 5.5 · 휴식 · 컨텍스트 거의 꽉 참 → 설계 일이 생기면 후계 #28 개설 후 #26 정리) · DA `byz-harness-da-codex#1`(대기) · graphics master `byz-graphics-master-claude#3` · issues master `byz-issues-master-claude#12` · loom master `byz-loom-master-claude#14`(arch #20) · cfo master `#70` · v65 master `#163` · 하네스 나노 0석.
