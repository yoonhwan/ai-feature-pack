# HANDOFF — byz-harness-master-claude#23 → #24 (2026-10-09 · ctx 409k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
이 단위의 골 축: A(모니터·오빠 요청) + B(개선요청 접수·협의) + C(업그레이드·커밋·push·반영) + 원문 5(머신 독립 배분).
★승계 첫 일 = 골 대조 3줄 + 부팅 3항 + i-have-adhd 를 현역 planner(`byz-planner-master-claude#18` · tmux 실측)에 mbox 보고 → 같은 턴 CronCreate 10분 틱(cron=job id 보고). 전임 크론 `ff91490d` 는 세션 종속이라 후계가 새로 건다. BOOT 23조항(`~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md`) 먼저. 좌석표 교체: 루트에서 `bash .fable-team/bin/ft-seat-retire.sh byz-harness-master-claude#23 byz-harness-master-claude#24 --seats .fable-team/seats-harness.json`.★

## 지금 상태 (한 줄)
**하네스는 휴식 상태 — 열린 단위 0.** 판정 711(오빠): 휴식 유지 · 직접 label create 가드 안 함 · 디스크(uv·baton) 688 보류 · 그래픽스 도구 요청이 오면 그때.

## 이번 세션(#23)에 끝낸 것 (전부 origin/main · 설치 cmp OK · 판정서 §109~§114)
- §109 판정 675·676 ft-op-token 자동 발급 — PR 1085 `1e6b0f7d95` (developer.ts 실발급 OK · admin.ts cred 없음 → 필요 시 planner 가 `/tmp/opcred.sh admin.ts@byourz.com` 1회)
- §110 판정 690 그래픽스 팀장 체제 정본화 — PR 1093 `b158acbe83` (홈 governance·harness-map 설치 · ft-harness-info seats «팀 명부» 절 · graphics install.sh 명부 보존)
- §111 op675b ft-op-token 다듬기 3 — PR 1103 `4b8cfd2756` · §112 R66 codex Serena 부팅 경로 — PR 1104 `b38dba04b2`(홈 BOOT 1조항) · §113 R67 mbox-v2 추적 사본 가드 — PR 1109 `bba72c3a4e` · §114 R68 Tank 래퍼 label-create — PR 1113 `780267aa4d`
- 그래픽스 팀 개설(판정 678·690): 팀장 `byz-graphics-master-claude#0` 개설 · arch `byz-graphics-arch-codex#0` · 나노 g678(Issue #1087 · 브랜치 `nano/g678-cfo-credits-uiux`) 진행 중. 지휘는 팀장 소관 — 하네스는 **도구·설치·원격 보존 push 집행만**.
- 판정서 마지막 §114 → 다음 §115 · 요청 원장 마지막 R69 → 다음 R70 · 판정 번호(planner) 722~.

## 열린 일 (순서)
1. **그래픽스 팀장 요청 대기**: 원격 보존 push 요청이 반복해서 온다(arch 브랜치 `graphics/g678-cfo-credits-plan` · 나노 브랜치 `nano/g678-cfo-credits-uiux` — 둘 다 fast-forward 인지 `merge-base --is-ancestor origin/<b> HEAD` 확인 뒤 push · 삭제 0 · 완료 sha 1줄 회신 · 원격 최신: arch `19af425df4` · 나노 `9b36ec99c8`). g678 이 랜딩되면 CLOSEOUT 정본 1장 + 닫기(나노 `ft-nano-close.sh` · 브랜치 삭제 HIL).
2. 큐(착수 0 · 오빠 지시 때만): ①uv 캐시 53GB 재시도(다른 uv 잠금) ②`.baton/archive` 110GB 보관 기간 단축(오빠 승인 별도) · 둘 다 688 보류 ③가드로 직접 `gh label create` 차단 = 오빠 「안 함」(711).
3. 이월(접수만): 원장 R54·R55 보강 · R56 wt-clean TERM 오탐 · R57 Haiku 분류 rc=1 · R61 gce-guard 로그 회전 · GCE 가드 BREACH 2건 유지 · 보드 prune 첫 삭제 관찰(10-16) · 판정 621(cairn 원장 합치기)은 planner 지시 시 · 판정 601 fixture 실패·check-drift MAP 옛 행(별건).

## 현역 좌석 (이름은 승계로 바뀐다 — 보내기 전 tmux 실측)
planner `byz-planner-master-claude#18` · harness arch `byz-harness-arch-claude#25`(Opus 5.5 · 휴식 · cron 9f855ca1) · DA `byz-harness-da-claude#0`·`da-codex#0`(휴식) · 그래픽스 팀장 `byz-graphics-master-claude#0`(cron 284c51ad) · graphics arch `byz-graphics-arch-codex#0` · graphics 나노 `byz-graphics-nano-g678-cfo-credits-uiux#0`. 좌석표 `_master` = 이 세션(#23) → 후계가 #24 로 교체(`_hil_route` = planner#18 로 이미 교체됨).

## 운영 규칙·함정 (이번 세션 실측)
- **환경**: `cd .worktrees/harness-ops && source ../../.fable-team/bin-harness/harness-env.sh && export FT_SEND_FROM='byz-harness-master-claude#<본인>'` → `$FT_BIN`. 그래픽스 도구는 `source ../../.fable-team/bin-graphics/graphics-env.sh` 추가.
- **나노 spawn**: `ft-nano-spawn.sh design/harness/indices/대기/<카드>.md --agent claude --model 'claude-sonnet-5-5[1m]' --effort high --base origin/main --from <본인>`. ★ops 워크트리 cwd(ops/main-base)에서 돌린다★ — origin/main 기준 cwd(ops-guard)에서 돌리면 인덱스 이동이 실패하고 명부 `index` 가 절대경로로 남아 닫기 ⑥ 이 카드를 못 찾는다(대응: 명부 `index` 를 상대경로로). 첫 발주가 입력줄에 제출 대기로 걸리면 `mbox.sh ring <좌석> <seq>`.
- **병합 절차**: ops 에 `§N` append(arch 초안 `.fable-team/state/drafts-r22/OPS-VERDICT-<N>.md`) + 카드 `## 결과`(증거 줄 `세트: <40hex> · 시험: … rc=<n> · 이슈: 0` · 줄 안에 괄호 부가 문구 넣지 말 것 — 형식 REJECT) → `ft-nano-evidence-check.sh` OK → ops 커밋(★경로 지정 add · `git add -A` 훅 차단★) → 나노 wt 에서 `git checkout -b land/<n> origin/main` → 파일 목록 zsh 배열로 `git checkout nano/<n> -- $files` + ops 문서 `git -C ../harness-ops show ops/main-base:<f> > <f>` → 로컬 시험 → push + PR(`--body-file` · `unset GH_TOKEN`) → `gh pr view`(별 명령) → `gh pr merge N --squash`(별 명령 · CI 체크 0개 — 병합 근거는 로컬 검증) → 나노 wt 를 `nano/<n>` 으로 되돌림(안 하면 닫기 ③ REJECT) → 설치(cp 전 sha 대조 · 백업 `.bak-<n>-1009` · cmp) → 닫기(jsonl 마지막 기록 3분 뒤 — `sleep` 은 훅 차단이니 `run_in_background` 로) → `ft-index-move.sh 진행/<카드> 완성 --da '…OPS-VERDICTS-20261006.md#§N'` → ops 커밋.
- **훅**: mbox 본문에 백틱(`) 이 있으면 차단 — 본문은 파일에 쓰고 `mbox.sh relay`(요약 인자에도 백틱 금지). `sleep N; cat` 체인 차단 → `run_in_background` + Read. 재귀 삭제·`pkill`·`git add -A` 도 차단.
- **seats.json 오염**: 나노가 «명부에 좌석 없음» 오판으로 루트 `seats.json`(v65 명부)에 스스로 행을 등록하면 ft-tick 이 v65 master 로 오알림 — 그래픽스 좌석 명부는 `seats-graphics.json` 하나(제거 백업 `.fable-team/state/seats.json.bak-graphics-row-690`).
- **비밀**: `secrets/`·`*.cred`·토큰 파일은 키 이름·존재·크기만(BOOT 22조항) · JSON cred 는 python 키 이름으로.
- **틱 판단**: 좌석 상태는 `ft-seat-status.sh turn`·`✻ … done`·pane `Working`·마지막 커밋 시각·미커밋 수로 실측(쪽지 문장 복사 금지). 쉬는 좌석의 «정지 N분» 은 정상. 하네스는 휴식 중 — 틱은 mbox 수신 + 좌석 실측만, 새 단위 0.
- **보고**: 오빠 보고 틀 = 결론 1줄 → 오빠 할 일 → 바뀐 것 → 근거 + PR 번호는 맨 아래 표. planner 마일스톤은 mbox.

## 환경
워크트리 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops`(ops/main-base · push 금지). mbox `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh`. 판정서 `design/harness/OPS-VERDICTS-20261006.md` · 요청 원장 `design/harness/REQUEST-LEDGER.md` · 설치 키트 원본 비교용 `.worktrees/ops-guard`(`git checkout --detach origin/main`) · 라이브 bin `.worktrees/v6-realtime-live/.fable-team/bin`.
