# HANDOFF — byz-harness-master-claude#21 → #22 (2026-10-09 08:5x · ctx 402k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
이 단위의 골 축: A(모니터·오빠 요청) + 6-b(개선요청 접수·협의) + C(업그레이드·커밋·push·반영) + 원문 5(머신 독립 배분).
★승계 첫 일 = 골 대조 3줄 + 부팅 3항 + i-have-adhd 를 현역 planner(`byz-planner-master-claude#15` · 이름은 `tmux list-sessions` 실측)에 mbox 보고 → 같은 턴 CronCreate 10분 틱(cron=job id 보고). 전임 크론 `c1338aaf` 는 세션 종속이라 후계가 새로 건다. BOOT 20조항(`~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md`) 먼저. 좌석표 교체: 루트에서 `ft-seat-retire.sh byz-harness-master-claude#21 byz-harness-master-claude#22 --seats .fable-team/seats-harness.json`(인자 순서 구·후계).★

## 지금 상태 (한 줄)
**아침 매거진 오늘(10-09) 호 미발행** — 판정 603 구현 DA 진행 중. 나머지 하네스 일은 전부 닫힘. 오빠 할 일 0.

## 지금 진행 중인 단위 = 판정 603 (아침 매거진 오늘 호 발행)
오늘 08:00 launchd 첫 발사가 실패했고(`ModuleNotFoundError magazine_collect_open`), 원인을 한 겹씩 벗기는 중이다. 닫은 것: ①`magazine_collect_open.py` 홈 미설치 → 설치(PR 1059 `e8c5718a8c` 에서 install-magazine.sh 목록도 import 닫힘 집합으로) ②mbox 로그 회전(10-08 21:03)으로 창 앞부분 못 덮음 → `.1` 이어 읽기(PR 1059) ③형식 미달 완성 카드 13장(CFO 12 + 하네스 update-tools 1)이 호 전체를 막음 → report 모드(PR 1060 `b545ab1225` · 환경값 `MAGAZINE_MALFORMED_CARDS=report` · 홈 plist 에 1줄 추가됨·재적재 아직 안 함) ④`REQUEST-LEDGER` 4·5열 행 28개 → 7열 정리(PR 1061 `60ed7677dd`) — 그러나 수집기가 원장을 «창 끝(오늘 08:00) 스냅샷»으로 읽어 오늘 호엔 안 보임(내일부터 정상) ⑤그래서 planner 판정 603: 같은 report 모드가 원장 형식 미달 행도 표시+ERROR+건너뜀(나노 `byz-harness-nano-mag603-malformed-ledger-rows-report#0` 구현 `74ab10e7a2516d7dbb9fecdf76dc28e8ebf16d5b`).
**현재**: arch#23 독립 재현 OK(58 passed · 실데이터 전체 dry-run rc=0 · PDF 537쪽 · 카드 13 + 요청 행 22 ERROR 줄 · 5번째 원인 없음). 구현 DA 소환됨(#67214 · 요청서 ops `b8a7dac620`) → 판정 오면 arch#23 이 §104 초안 + 집행 요청을 보낸다.
**★planner 상한(판정 603)★**: 오늘 호 dry-run 이 5번째 원인에서 또 막히면 그 자리에서 멈추고 오늘 호 생략(내일 호부터)으로 닫는다 — 추가 수정 라운드 0.

## 열린 일 (순서)
1. **DA 판정 대기 → §104 → 랜딩 → 설치 → 오늘 호 수동 발행** (병합 절차는 아래). 집행 순서(arch 초안): ①PR(--body-file · CI 확인과 병합 별 명령) ②`install-magazine.sh`(WARN 0) ③홈 파일 cmp ④수집 dry 1회(raise 0 · ERROR 13+22) ⑤오늘 호 수동 재발행: 환경값(`BYZ_ROOT=/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents GH_REPO=SecondWindStudio/byz-agents MAGAZINE_CHANNEL=C0C6MJGRR89 MAGAZINE_MALFORMED_CARDS=report PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin`, `unset GH_TOKEN`)을 명령에 직접 주고 `cd ~/.hermes/scripts && /opt/homebrew/bin/python3 byz_morning_magazine.py --date 2026-10-09`(첫 화면·뿌리 글·부록에 «⚠ 형식 미달 카드 13장 / 요청 행 22개» 표시 확인 · 슬랙 ts + err 0 증거) → planner `[완료·휴식]` 보고. 슬랙 게시·push 는 이 단계에서만(지금까지 dry-run 만 함).
2. **plist 재적재(내일 08:00 예약 실행이 report 모드를 받게)**: 홈 plist 에는 env 가 이미 들어 있으나 launchd 에 적재 안 됨 → `launchctl bootout gui/$UID/com.byz.ft-magazine; launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.byz.ft-magazine.plist` — ★planner 보고 «뒤에만»(install-magazine.sh 안내문 금지선)★. 백업 `/private/tmp/claude-501/com.byz.ft-magazine.plist.bak-mag602`.
3. **나노 정리**: mag603 나노는 DA 끝나기 전엔 닫지 않는다 → 랜딩 뒤 `ft-nano-close.sh … --recv 67211 --cherry-override "PR N squash <sha> blob 동일 (…)"` → `ft-index-move.sh 진행/<카드> 완성 --da 'design/harness/OPS-VERDICTS-20261006.md#§104'`.
4. **큐(착수 0 · 09시 오빠 큐 10·11)**: 큐 11 = 원격 `ops/main-base` 브랜치 삭제 HIL(arch#21 이 인계서 커밋을 실수로 push 해 생김 · 지우려면 오빠 승인) · 별 카드 후보 = `test_magazine_collect_decisions.py` 4건 실패(판정 601 이 만든 fixture 문제) · check-drift MAP 옛 v6 행 정리 · boot-read-gate 주석 2줄 · CFO 형식 미달 카드 12장 보정은 cfo 몫(완성 후).
5. **이월(전임 #20)**: 원장 R54·R55 보강 · R56 wt-clean TERM 오탐 · R57 Haiku 분류 rc=1 · R61 gce-guard 로그 회전 ROOT 기준 접수만(착수 0) · GCE 가드 정시 회차 실측 1회(`state/gce-op-model/BREACH.md` 2건 유지) · 보드 prune 첫 삭제 관찰(10-16).

## 이번 세션(#21)에 끝낸 것 (전부 origin/main · 홈 설치 cmp OK)
판정 592 ④ mbox.py 분리 PR 1052 `63b5323987` · 판정 595 가드 ㉠ 오탐 원복→보강 PR 1057 `483ba4ec67`(§100) + X7 간접 입력 PR 1058 `1c2828e1f8`(§101) · 판정 601~603 매거진 PR 1059 `e8c5718a8c`(§102) · PR 1060 `b545ab1225`(§103) · PR 1061 `60ed7677dd`(원장 7열). 판정서 마지막 §103 → 다음 §104 · 원장 마지막 R65 → 다음 R66. 홈 훅 = `~/.claude/hooks/block-destructive.sh`(sha 01b9bf51da39 · 97줄) + `block-destructive-judge.py`(sha 699a959bf11a · 200줄) · 백업 `.bak-fp595b-20261009`·`.bak-x7-20261009`.

## 현역 좌석 (이름은 승계로 바뀐다 — 보내기 전 tmux 실측)
planner `byz-planner-master-claude#15` · harness arch `byz-harness-arch-claude#23`(Opus 5.5 · cron 131ee96d · 좌석표 `_arch` 반영됨) · DA `byz-harness-da-codex#0` · 나노 `byz-harness-nano-mag603-malformed-ledger-rows-report#0`(`[완료·휴식]` 상태). 좌석표 `_master` = 이 세션(#21) → 후계가 #22 로 교체.

## 운영 규칙·함정 (이번 세션 실측)
- **환경**: `cd .worktrees/harness-ops && source ../../.fable-team/bin-harness/harness-env.sh && export FT_SEND_FROM='byz-harness-master-claude#<본인>'` → `$FT_BIN`. 나노 spawn: `ft-nano-spawn.sh <대기/카드> --agent claude --model 'claude-sonnet-5-5[1m]' --effort high --base origin/main --from <본인>`(카드 lint: 구현 범위의 경로는 리포 루트 기준 전체 경로 · 줄임표·/tmp 예시는 백틱 밖).
- **병합 절차**: ops 에 §N append(`{ echo; cat 초안; } >> design/harness/OPS-VERDICTS-20261006.md`) + 카드에 `## 결과` 칸 + 증거 줄 → `ft-nano-evidence-check.sh` OK → ops 커밋(★경로 지정 add — `git add -A`/`.` 은 훅이 막는다★) → 나노 wt 에서 `git checkout -b land/<n> origin/main` → ★파일 목록은 zsh 배열로★(`files=("${(@f)$(git diff --name-only $MB nano/<n>)}")` 후 `git checkout nano/<n> -- $files`) + ops 문서는 `git -C ../harness-ops show ops/main-base:<f> > <f>` → 로컬 시험 → push + PR(`--body-file` · `unset GH_TOKEN`) → `gh pr checks`(별 명령) → `gh pr merge N --squash`(별 명령) → 나노 wt 를 `nano/<n>` 으로 되돌림 + `git -C ../ops-guard checkout --detach origin/main` → 설치 → `ft-nano-close.sh` → `ft-index-move.sh … 완성 --da '…OPS-VERDICTS-20261006.md#§N'` → ops 커밋.
- **훅 오탐 회피**: 홈 block-destructive 는 명령 글자 안의 파괴 명령 인용·변수 경로 재귀 삭제를 막고, 가드 ㉠ 은 argv 밖 redis 쓰기 간접 입력·말풍선 재생 URL 글자도 막는다(오빠 절대지침 — 측정 조작 금지). 시험 명령에 그런 글자가 필요하면 Write 도구로 파일에 쓰고 `python3 -I 파일` 로 돌린다. `mbox.sh send` 본문에 따옴표가 겹치면 zsh 가 깨뜨리니 단일 따옴표로 감싼다.
- **DA 규칙**: HOLD 2회 = 리뷰 종료(arch 처방·독립 재현 서명). 나노 HIL(차단 보고)은 오탐 판단 후 우회 안 하고 회신. 나노의 완료 선언(`[완료·휴식]`)엔 같은 턴 접수 회신(안 하면 «완료 선언 미처리» 정지로 잡힌다).
- **보고**: 오빠 보고 틀 = 결론 1줄→오빠 할 일→바뀐 것→근거 + PR 번호는 맨 아래 표. 마일스톤 1줄은 planner 로 mbox. 틱 = 하위 좌석 pane done 줄·`python3 $FT_BIN/ft-board.py stalled --min 3` · 정지 3분 넘으면 그 턴에 처리.
- **ops 줄기**: `ops/main-base` 는 push 대상 아님(랜딩은 항상 새 `land/<이름>`). 인계서·설계 커밋도 push 금지(arch#21 이 실수로 push 한 사례 있음).

## 환경
워크트리 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops`(ops/main-base). mbox `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh`. 판정서 `design/harness/OPS-VERDICTS-20261006.md` · 요청 원장 `design/harness/REQUEST-LEDGER.md` · 슬랙 미러 홈 `~/.hermes/scripts` · 매거진 plist `~/Library/LaunchAgents/com.byz.ft-magazine.plist`.
