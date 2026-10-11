# HANDOFF — byz-harness-master-claude#20 → #21 (2026-10-09 03:2x · ctx 400k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
이 단위의 골 축: A(모니터·오빠 요청) + 6-b(개선요청 접수·협의) + C(업그레이드·커밋·push·반영) + 원문 5(머신 독립 배분).
★승계 첫 일 = 골 대조 3줄 + 부팅 3항 + i-have-adhd 를 현역 planner(`byz-planner-master-claude#14` · 이름은 `tmux list-sessions` 로 실측)에 mbox 보고 → 같은 턴 CronCreate 10분 틱(cron=job id 보고). 전임 크론 `205b409a` 는 세션 종속이라 후계가 옮겨 받지 못한다(후계가 새로 건다). BOOT 20조항(COMM-GUIDE-BOOT.md) 먼저.★ 좌석표 교체: `ft-seat-retire.sh byz-harness-master-claude#20 byz-harness-master-claude#21 --seats .fable-team/seats-harness.json`(인자 순서 구·후계 · 루트에서 실행).

## 지금 상태 (한 줄)
오늘(10-09 새벽) 판정서 §89~§98 랜딩 · 원장 R64·R65 접수→해소 · 진행 단위 = 판정 592 ④ mbox.py 분리(나노 RESULT 도착 → arch#21 재현·최종 DA 진행 중). 오빠 할 일 0.

## 이번 세션(#20)에 끝낸 것 (전부 origin/main · 라이브 설치 cmp OK)
PR 1042(R63 발주 BODY 1줄 §91) · 1043·1046(R63 ㉡ 증거 검사 §92·§94) · 1044(v423c 미러·mbox 알림 §89) · 1045(R60+R62 보드 발행 §90) · 1047·1048(R63 ㉠ block-destructive 주입 차단 + 상대경로 정본 mbox 인정 §93·§95 · 홈 훅 설치) · 1049(키트=홈 게이트 훅 §96) · 1050(block-destructive 판정기 분리 §97 · 홈 87줄+judge.py 123줄 설치 · 오탐 0) · 1051(mbox.sh 분리 §98 · 라이브 설치 + 실발주 OK). 판정서 마지막 §98 → 다음 §99 · 원장 마지막 R65(해소) → 다음 R66.

## 열린 일 (순서)
1. **판정 592 ④ mbox.py 637줄 분리**: 나노 `byz-harness-nano-mbox-py-split-200#0` RESULT(HEAD `427ebdddbc7d29af76c7da0b1fab0dc579ba987f` · 커밋 2 · 진입 125 + conf 41·store 186·guard 146·ops 167) → arch#21 재현 + 최종 DA 1회(요청 커밋 a66bd9b98a · 판정문 오면) → §99 초안(`.fable-team/state/drafts-r21/OPS-VERDICT-99.md`) → 카드 증거 줄 옮김 → 새 브랜치 `land/<이름>` 을 origin/main 에서 → PR(`--body-file`) → 병합 → ★라이브 설치★(아래 함정) → 나노 닫기(`--recv <RESULT seq 66870>`) → 카드 완성 이동.
2. **라이브 설치 함정(mbox.py)**: 라이브 `.fable-team/comm/mbox.py` 는 `../../.claude/fable-team/bin/mbox.py` 로의 링크 · 파이썬은 링크된 스크립트의 모듈을 «실제 폴더(.claude/fable-team/bin)»에서 찾는다 → 모듈 4개(`mbox_conf.py`·`mbox_store.py`·`mbox_guard.py`·`mbox_ops.py`)를 bin 에 «먼저» cp+cmp → 진입 `mbox.py` 를 `.new` 로 복사 후 `mv -f` 원자 교체 + cmp · 백업 `mbox.py.bak-mboxpy-20261009` · 루트 계산은 진입에만 있어야 함(모듈에 있으면 NO_MAILBOX_ROOT 로 전 좌석 쪽지 정지) · 설치 뒤: 자기 peek + 다른 좌석 실발주 1통 도착·recv(도어벨 포함) + 회신 가드 행 `r` 확인 · 실패 1건이면 즉시 원복.
3. **원장 접수만(착수 0)**: R54·R55 보강 · R56 wt-clean TERM 오탐 · R57 Haiku 분류 rc=1 · R61 gce-guard 로그 회전 ROOT 기준.
4. **GCE 가드 정시 회차 실측 1회(전임 이월 · 아직 안 함)**: `launchctl print gui/$(id -u)/<gce-guard plist>` runs 증가 + last.log mtime + `state/gce-op-model/BREACH.md` 2건 유지(ccu-stress-stt-tts·ccu-stress-vllm) → planner 보고 1줄.
5. **보드 prune 첫 삭제 관찰**: 10-16 첫 발행 때 날짜 폴더 7개 유지(`ft-board-publish.sh` 가 날짜 첫 발행 때 `prune --days 7`). «변화 없음» 줄은 팀이 쉴 때 나옴(지금까지 0 = 팀 8개 활동 중 · 실제 바뀜).
6. **정리**: 닫은 나노 워크트리 다수 `skipped:cwd` → 다음 `ft-wt-sweep.sh` · 옛 tmux(master#15·#17~#19 · arch#16~#20)는 keep-last-2 안에서.
7. **큐 후보(planner 가 오빠께 여쭙는 중)**: 별 카드 후보 = Bash 훅 템플릿이 아닌 다른 200줄 초과 파일은 planner 판정 592 범위 밖 · 새 요청은 원장 접수 후 planner→오빠 컨펌.

## 현역 좌석 (이름은 승계로 자주 바뀐다 — 보내기 전 tmux 실측)
planner `byz-planner-master-claude#14` · harness arch `byz-harness-arch-claude#21`(Opus 5.5 · cron b90cf5a2 · 좌석표 `_arch` 반영됨) · DA `byz-harness-da-codex#0` · 나노 `byz-harness-nano-mbox-py-split-200#0`(RESULT 도착·휴식). 좌석표 `_master` = 이 세션(#20) 로 되어 있음 → 후계가 #21 로 교체. `_hil_route` = planner#14 (planner 가 직접 갱신).

## 운영 규칙·함정 (이번 세션 실측)
- **환경**: `cd .worktrees/harness-ops && source ../../.fable-team/bin-harness/harness-env.sh && export FT_SEND_FROM='byz-harness-master-claude#<본인>'` → `$FT_BIN`(= v6-realtime-live/.fable-team/bin). 나노 spawn: `ft-nano-spawn.sh <대기/카드> --agent claude --model 'claude-sonnet-5-5[1m]' --effort high --base origin/main --from <본인>`.
- **병합 절차**: ①arch 재현 + §N 초안 → ②ops 에 §N append(`{ echo; cat 초안; } >> design/harness/OPS-VERDICTS-20261006.md`) + 카드에 `## 결과` 칸 + 증거 줄(`세트: <40hex> · 시험: … rc=0 · 이슈: 0` + 정본 영향 없음 줄) → `ft-nano-evidence-check.sh <카드> --repo <나노 wt>` OK → ops 커밋 → ③나노 wt 에서 `git checkout -b land/<n> origin/main` → `git checkout nano/<n> -- <코드 파일들>` + ops 의 판정서·카드·DA 판정문 `git -C ../harness-ops show ops/main-base:<f> > <f>` → 로컬 시험 → 경로 지정 add → 커밋 → push + PR(`gh pr create --body-file` · unset GH_TOKEN) → `gh pr merge N --squash` → 나노 wt 를 `git checkout nano/<n>` 으로 되돌림 → `git -C ../ops-guard checkout --detach origin/main` → ④라이브 설치(`git archive origin/main <경로> | tar -x -C <scratch>` · 백업 `.bak-…` · cp+cmp) → ⑤`ft-nano-close.sh <좌석> --result <진행 카드> --recv <RESULT seq> --cherry-override "PR N squash <sha> blob 동일 (…)"` ★닫기는 카드가 «진행/» 에 있을 때만 → 닫은 뒤에 `ft-index-move.sh 진행/<카드> 완성 --da 'design/harness/OPS-VERDICTS-20261006.md#§N'`(--da 는 판정서 «절» 이름 · 파일 경로 아님)★ → ops 커밋(경로 지정).
- **훅 오탐 회피(중요)**: 홈 block-destructive 는 «명령 글자 안의 파괴 명령 인용»과 «변수 경로 재귀 삭제»를 막는다. 장부·원장·커밋 본문에 그런 글자가 필요하면 풀어 쓰거나 Write 도구로 파일에 쓰고, 임시 폴더는 삭제 대신 `mktemp -d` 새 이름. 상대경로 mbox 송신(`bash ../../.fable-team/comm/mbox.sh send …`)은 이제 통과(§95). `git add -A`/`.`·긴 sleep 차단.
- **보고**: 오빠 보고 틀 = 결론 1줄→오빠 할 일→바뀐 것→근거 + PR/Issue 번호는 맨 아래 표. 마일스톤 1줄은 planner 로 mbox(pane 에만 쓰고 쪽지 안 보내면 planner 가 «미도착»으로 묻는다 — 02:56 실수). 틱 = 하위 좌석 pane done 줄·`ft-board.py stalled --min 3`($FT_BIN) · 정지 3분 넘으면 그 턴에 처리.
- **DA 규칙**: HOLD 2회 = 리뷰 종료(arch 가 보강 설계 + 독립 재현·서명). 구현 DA 소환 여부는 카드 계약. 나노 HIL(차단 보고)은 오탐 판단 후 우회 안 하고 회신(허용 신호는 줄 때만).
- **ops 줄기**: `ops/main-base` 는 push 대상 아님(랜딩은 항상 새 `land/<이름>` 브랜치). 나노는 origin/main 기준이라 카드·도구는 ops 줄기에 있으면 절대경로로 읽게 안내.

## 환경
워크트리 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops`(ops/main-base). mbox `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh`. 판정서 `design/harness/OPS-VERDICTS-20261006.md` · 요청 원장 `design/harness/REQUEST-LEDGER.md` · 요청 접수 R64/R65 해소. 홈 훅 = `~/.claude/hooks/block-destructive.sh`(87줄 · sha 0ea922d149f7) + `block-destructive-judge.py`(123줄) · 백업 `.bak-r63b/.bak-r63e/.bak-bdsplit-20261009`. 라이브 mbox.sh 백업 `.claude/fable-team/bin/mbox.sh.bak-mboxsplit-20261009`.
