# HANDOFF — byz-harness-master-claude#19 → #20 (2026-10-09 01:1x · ctx 400k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
이 단위의 골 축: A(모니터·오빠 요청) + 6-b(개선요청 접수·협의) + C(업그레이드·커밋·push·반영) + 원문 5(머신 독립 배분).
★승계 첫 일 = 골 대조 3줄 + 부팅 3항 + i-have-adhd 를 현역 planner(`byz-planner-master-claude#14` · 이름은 `tmux list-sessions` 로 실측)에 mbox 보고 → 같은 턴 CronCreate 10분 틱(cron=job id 보고). 전임 크론 `f30454f7` 는 후계 부팅 보고 뒤 내가 삭제.★ BOOT 20조항(19 + 신규 20 측정 조작 금지) 먼저. 오빠 지침 판정 514·532(골 끝내면 `[완료·휴식]`)·511(상태=실측) 유지.

## 지금 상태 (한 줄)
오늘(10-08 밤~10-09 새벽) 판정서 §83~§88 랜딩 · 원장 R54~R63 접수 · 진행 단위 = v423c 반송 수정(나노 작업 중) + R63 발주 템플릿(나노 RESULT 도착 → arch#20 재현 대기) + 가드 2층 카드(arch#20 작성 중). 오빠 할 일 0.

## 이번 세션(#19)에 끝낸 것 (전부 origin/main · 라이브 cp+cmp OK)
v423a 보드 발행(PR 1014 · §83) · v423b 보고 훅 2종(PR 1023 · §84) · R58 press-gate 다른 줄기(PR 1027 · §85) · R59 Tank comment-edit(PR 1028 · §86) · v558 inbox waive(PR 1031 · §87 · waive 79건 집행 · 훅 2종 planner 로컬 등록 = `v6-realtime-live/.claude/settings.local.json` + `~/.claude/hooks/`) · v555 보드 5분 틱(PR 1034 · §88 · launchd `com.byz.ft-board-publish` + WorkingDirectory 복구) · CLAUDE.md 측정 조작 금지 1줄(PR 1041). 오빠 절대지침 「임의 Redis·말풍선 DOM 주입 금지」 = 전역 CLAUDE.md 하드 룰 11 + CLAUDE_MASTER_SYNC 3곳 + BOOT 20 + governance §10 + 전 팀 방송(판정 588 접수). GCE 가드 = `.worktrees/ops-guard`(detached origin/main) + plist `GCE_GUARD_OUT`(판정 580 안1) — ★랜딩마다 `git -C .worktrees/ops-guard checkout --detach origin/main`★. 판정서 마지막 §88 → 다음 §89 · 원장 마지막 R63 → 다음 R64.

## 열린 일 (순서)
1. **v423c 미러 요약기·mbox 알림**: 나노 `byz-harness-nano-v423c-mirror-mbox-notify#0` 가 DA r1 HOLD 반송(`.fable-team/state/drafts-r21/REJECT-v423c-mirror-mbox-notify-r1.md` · 쪽지 66484 로 전달) 수정 중 → RESULT 오면 arch#20 재현 → DA r2(bounded) → §89 → 병합(★새 브랜치 land/<이름> 을 origin/main 에서 만들어 새 파일만 재구성 · 나노 브랜치는 ops 줄기 base 라 병합 충돌★) → 라이브 comm(mbox 2파일)·slack-mirror cp+cmp · 미러 launchd 재시작 · doorbell 1일 관찰.
2. **R63 발주 템플릿**: 나노 `byz-harness-nano-r63-spawn-body-no-injection#0` `[완료·휴식]` 세트 `0bc7d3b6a94b0515a327e41a84b7cb5cdddde9af`(시험 rc=0) → arch#20 에 재현 요청 → §89/§90 번호 → 병합 → 라이브 FT_BIN `ft-role-spawn.sh`·`ft-nano-spawn.sh` cp+cmp.
3. **가드 2층 카드(판정 589)**: arch#20 이 ㉡증거 검사(차단 없음) → ㉠block-destructive 3번째 블록 카드 작성 중 → spawn → ㉠조건: 원본 백업·셔뱅 그대로 시험·오탐 0(격리 픽스처·DEL/FLUSHDB/GET·기존 러너·일반 curl)·위반 차단·적용 뒤 첫 도구 호출 실측·오탐 1건이면 즉시 원복.
4. **R60+R62 묶음 카드**(arch#20 작성 예정): R60 plist 템플릿 WorkingDirectory · R62 보드 발행 정규화 누락(정지 N분·턴 끝 시각이 매 틱 변해 «변화 없음» 0회 → 스냅샷 ~109MB/일).
5. **원장 접수만**: R54·R55 보강 · R56 wt-clean TERM 오탐 · R57 Haiku 분류 rc=1(미상 쪽지) · R61 gce-guard 로그 회전 ROOT 기준. 착수 0.
6. **v555 첫 1시간 관찰 결과 1줄**을 planner 에 아직 안 올림(12틱 완주 시점 이후 · 현재 6회 성공·변화 없음 0 → R62 와 묶어 보고).
7. **GCE 가드 정시 회차 실측 1회**(01:52 이후 `launchctl print … runs` 증가 + last.log mtime + BREACH.md 2건 유지) → planner 보고 1줄.
8. **정리**: 옛 tmux(master#15·#17·#18 · arch#16~#19)는 keep-last-2 안에서 · 닫은 나노 워크트리 다수 `skipped:cwd` → 다음 `ft-wt-sweep.sh`.

## 현역 좌석 (이름은 승계로 자주 바뀐다 — 보내기 전 tmux 실측)
planner `#14` · cfo `#64` · feature `#6` · issues `#6` · loom `#4` · ops `#4` · v65 `#151` · harness arch `byz-harness-arch-claude#20`(Opus 5.5 · cron 811be559) · DA `byz-harness-da-codex#0` · 나노 v423c#0 · r63#0.

## 운영 규칙·함정 (이번 세션 실측)
- **환경**: `cd .worktrees/harness-ops && source ../../.fable-team/bin-harness/harness-env.sh && export FT_SEND_FROM='byz-harness-master-claude#<본인>'` → `$FT_BIN`(= v6-realtime-live/.fable-team/bin). 나노 spawn: `ft-nano-spawn.sh <대기/카드> --agent claude --model 'claude-sonnet-5-5[1m]' --effort high --base origin/main --from <본인>` (★--base origin/main 필수 · 아니면 나노 base 가 ops 줄기라 코드 파일이 없다 · 카드는 ops 줄기에 있고 나노는 카드 미접촉).
- **병합 절차(CI 판정 521 해제 후 = push 전 로컬 1회 + 머지 직전 라벨 ci 1회 · 재실행 0)**: ①arch 재현+§N 초안(drafts-r21/OPS-VERDICT-N.md) → ②ops 에 §N append + 카드 증거 줄(`세트: <나노 HEAD 40hex> · 시험: … rc=0 · 이슈: 0` + 정본 영향 없음 줄) → `ft-nano-evidence-check.sh <카드> --repo <나노 wt>` OK → ops 커밋 → ③나노 wt 에서 `git checkout -b land/<n> origin/main` → `git checkout nano/<n> -- <코드 파일들>` + ops 의 판정서·원장·NANO-LEDGER·진행 카드 `git show ops/main-base:<f> > <f>` → 로컬 시험+ruff+kit_sync → 커밋 → push + PR(`gh pr create --body-file` · unset GH_TOKEN · 일시 GraphQL 오류는 재시도) → `gh pr merge N --squash` → 나노 wt 를 `git checkout nano/<n>` 으로 되돌림 → ④라이브 cp+cmp(`git archive origin/main …` scratchpad 새 폴더 · 백업 `*.bak-…`) → ⑤`ft-nano-close.sh <좌석> --result <진행카드> --recv <RESULT seq> --cherry-override "PR N squash <sha> blob 동일 (…)"` → ⑥`ft-index-move.sh 진행/<카드> 완성 --da '…OPS-VERDICTS-20261006.md#§N'` → ops 커밋.
- **훅 차단**: `rm -rf` 글자·`git add -A`/`.`·긴 `sleep` 은 차단 → 경로 지정 add · 대기는 Monitor until-loop. mbox 속도 제한 5건/60초 · 같은 본문 fan-out 은 BLOCKED(팀별 문구).
- **보고**: 오빠 보고 틀 = 결론 1줄→오빠 할 일→바뀐 것→근거 + PR/Issue 번호는 맨 아래 표. 마일스톤 1줄은 planner 로. 틱 = 하위 좌석 pane done 줄·jsonl 실측 + `ft-board.py stalled --min 3`. 정지 3분 넘으면 그 턴에 처리(오빠 10-09 지적: 쪽지는 틱 사이에도 즉시 처리).
- **DA 규칙**: HOLD 2회 = 리뷰 종료(3회째 없음 · arch 가 보강 설계 + 독립 재현·서명). 구현 DA 소환 여부는 카드 계약(v423c = 있음 · R59·v555 = 없음).

## 환경
워크트리 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops`(ops/main-base · push 대상 아님). mbox `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh`. 판정서 `design/harness/OPS-VERDICTS-20261006.md` · 요청 원장 `design/harness/REQUEST-LEDGER.md` · 조사 `design/harness/INVEST-root-checkout-align-20261009.md` · `SURVEY-r63-injection-guard-hook-20261009.md`. 백업(scratchpad `…/b7f954e3-…/scratchpad/` · `$TMPDIR`): COMM-GUIDE-BOOT.md.bak-redis-1009 · bak-r63/(CLAUDE.md·AGENTS·SOUL·governance) · seats-harness.bak-arch20 · gce-guard-check.plist.bak-1009.
