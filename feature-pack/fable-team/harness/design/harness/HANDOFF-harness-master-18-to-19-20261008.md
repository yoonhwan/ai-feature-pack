# HANDOFF — byz-harness-master-claude#18 → #19 (2026-10-08 22:5x · ctx 401k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
이 단위의 골 축: A(모니터·오빠 요청) + 6-b(개선요청 접수·협의) + C(업그레이드·커밋·push·반영) + 원문 5(머신 독립 배분).
★승계 첫 일 = 골 대조 3줄 + 부팅 3항 + i-have-adhd 를 현역 planner(`ft-harness-info.sh seats` · 지금 byz-planner-master-claude#13)에 mbox 보고 → 같은 턴 CronCreate 10분 틱(cron=job id 보고).★ BOOT 19조항 먼저. 전임 크론 `55ce2e0c` 는 후계 부팅 보고 뒤 내가 삭제.
★오빠 지침 판정 514·532(최상위): 골을 끝낸 좌석은 `[완료·휴식]` 1통 보내고 쉬는 것이 정답. 끝난 단위 끌기·옛 데이터 승계·끝없는 루프·스스로 다음 일 만들기 금지(정본 governance §9 · BOOT 19 설치됨).★

## 지금 상태 (한 줄)
오늘(10-08 밤) 상태판 도구 3종·루트 지침·R49·R52·R53 전부 랜딩·설치 끝. 지금 진행 단위 = v423a(보드 발행) 나노 RESULT 도착 → arch#18 재현 대기. 오빠 할 일 0.

## 이번 세션(#18)에 끝낸 것 (전부 판정서 §77~§82 · origin/main · 라이브 cmp OK)
PR 989·991(상태판 ft-board + 카드 제목 H1, R52) · 997(루트 지침 514·532 문서 + 정본 설치 governance sha c5d73fff80291434 · BOOT 01cddacdb2b070d8 + 전 팀 방송 7곳 seq 65230~65249) · 1002(상태판 좌석 칸 실측 + stalled, 판정 511) · 1004(R49 슬랙 질문 보드 msg_too_long + 27건 일괄 닫기 판정 538) · 1009(R53 ft-nano-close ③ jsonl 마지막 timestamp). 슬랙 새 스레드 발행(판정 542): 채널 C0C6MJGRR89 root_ts 1791467135.131769 · 카드 `완성/update-tools-20261008.md`. 명부 9개에 `_cards`·`_cards_wt`·`_label`(+`_tree` 4팀) 기입(백업 scratchpad `*.bak-board-keys`). 판정서 마지막 §82 → 다음 §83. 요청 원장 마지막 R56 → 다음 R57.

## 열린 일 (순서 · planner 판정 545)
1. **v423a 보드 발행**(★반송 r1 진행 중: arch#18 재현 7종 PASS · 사유 1 = 실제 루트 render --slack 37,482B(R49 거부선 3.9KB 10배) → 슬랙 뿌리 = 머리+⓪+④+끝줄·3500B 상한 새 파일·시험 5 · 반송서 `.fable-team/state/drafts-r21/REJECT-v423a-board-publish-r1.md` 를 나노 byz-harness-nano-v423a-board-publish#0 에 전달함(seq 위 방금) · 슬랙 뿌리에서 ①②③ 빠지는 표시 범위 변경은 랜딩 뒤 planner 1줄 통보★ · `design/harness/indices/진행/v423a-board-publish.md` · 나노 `byz-harness-nano-v423a-board-publish#0` `[완료·휴식]` 3acc64f9bc2257e9e19bdfb140a3d18edd1e0a1a): arch#18 에 재현+§83 닫힘 초안 요청함(seq 65588). 오면 → 병합 절차(아래) → v423b spawn.
2. **v423b 보고 훅**(`대기/v423b-report-hooks.md`) → **v423c 미러·mbox 알림**(`대기/v423c-mirror-mbox-notify.md` · mbox-sh-split-200 보다 먼저). 한 번에 한 단위.
3. **②gate-hook-kit-equals-home**(오빠 343 · `대기/` 가 untracked — 커밋 대상 아님·planner 순서 ②) → ③r35-role-spawn-team-env-reject → ④mbox-sh-split-200(v423 랜딩 뒤). r23 보류 유지.
4. **원장 접수만(착수 0)**: R54 evidence-check 가 카드 전체의 마지막 «세트:» 줄을 읽음 · R55 RED 재현 LOCATE 나노 vs rc=0 강제 · R56 wt-clean TERM rc=143 오탐(+ 쪽지 65603 추가 사례: 대형 워크트리 삭제 도중 TERM → 반삭제 feature-f-multilingual-linebreak-measure-th-font 54 D, 같은 이름 재spawn 나노의 옛 wt-clean .sh 잔존). 접수 회신은 v65 master#150 에 #19 이름으로(65603 건은 아직 회신 0).
5. **정리 못 한 것**: 닫은 나노 워크트리 다수 `skipped:cwd 보유 프로세스`(세션은 닫힘 · 브랜치 보존) — 다음 `ft-wt-sweep.sh` 로 · 옛 tmux: master#15·#17 · arch#16·#17(#16부터 keep-last-2 안에서 정리 가능).
6. **상태판 첫 실측 잔여**: feature master#4·loom master#1·ops master#0 옛 행(명부 `_replaced_by` 없음) — 각 팀 승계 정리 몫(planner 에 통보 끝) · v65#149 완료 선언 미처리.

## 현역 좌석
planner `byz-planner-master-claude#13` · cfo `#62` · feature `#5` · issues `#5` · loom `#3` · ops `#3` · v65 `#150`(마지막 쪽지 발신자 — 명부 `_master` 는 #149 로 낡음) · kk·ccu 현역 세션 없음 · harness arch `byz-harness-arch-claude#18`(Opus 5.5 · cron 28433abc) · DA `byz-harness-da-codex#0` · 나노 `byz-harness-nano-v423a-board-publish#0`.

## 운영 규칙·함정 (이번 세션 실측)
- **환경**: `cd .worktrees/harness-ops && source ../../.fable-team/bin-harness/harness-env.sh && export FT_SEND_FROM='byz-harness-master-claude#<본인>'` → `$FT_BIN/ft-nano-spawn.sh|ft-nano-close.sh|ft-nano-evidence-check.sh|ft-index-move.sh|ft-seat-retire.sh` (FT_BIN = v6-realtime-live 의 `.fable-team/bin`). 나노 spawn 모델 `claude-sonnet-5-5[1m]` high · arch Opus 5.5 · 설계 좌석 Fable 5.1 high(판정 514 때만) · DA sol high(판정 514 때만 · 기본 low).
- **병합 절차(CI 꺼짐 · 판정 521 — CI 기다림·재실행 0)**: ①arch 재현 + §N 초안(`.fable-team/state/drafts-r21/OPS-VERDICT-N.md`) → ②ops 에 §N append(`printf '\n'; cat`) + 카드 증거 줄 append(`세트: <나노 HEAD 40hex> · 시험: bash tests/harness/<시험> rc=0 · 이슈: 0` + 정본 영향 없음 줄) → `ft-nano-evidence-check.sh <카드> --repo <나노 wt>` OK → ops 커밋 → ③나노 wt: `git merge origin/main` → `git checkout ops/main-base -- OPS-VERDICTS·REQUEST-LEDGER·NANO-LEDGER·진행 카드` + `대기/` 중복 `git rm` → 커밋 → 로컬 시험 + kit_sync + ruff → ④push + PR(본문 = Write 로 파일 `gh pr create --body-file` · 로컬 검증 줄 필수 · heredoc 금지 R46) → `gh pr merge N --squash` → ⑤라이브 cp+cmp(`git archive origin/main scripts/fable-team-bin` 을 scratchpad 새 폴더에 · 백업 · 실행 비트) + `ft-live-bin-drift-check.sh` → ⑥`ft-nano-close.sh <좌석> --result <진행카드> --recv <RESULT seq> --cherry-override "PR N squash <sha> blob 동일 (...)"`(증거 줄 HEAD 가 달라지면 새 HEAD 로 줄 append 후 재시도) → ⑦`ft-index-move.sh 진행/<카드> 완성 --da '...OPS-VERDICTS-20261006.md#§N'`(카드에 「정본 영향 없음: 이유」 줄 필수) → ops 커밋.
- **훅 차단**: `rm -rf` 글자 포함·`git add -A`/`.` 는 차단 → 새 폴더 생성·경로 지정 add. 오탐 회피 = 우회 말고 명령 자체를 단순화.
- **슬랙 발행**: `~/.hermes/scripts/byz_thread_post.py start --card <절대경로> --team harness --issue 없음 --seat <좌석> --canon <절대경로> --next 없음 --resume-script $FT_BIN/ft-resume-cmd.sh --text "$(cat <파일>)"` — 장부 `~/.hermes/state/byz_threads.json` 은 이미 --init 됨 · 한 번 올리면 회수 불가라 범위 확인 먼저(판정 542 사례).
- **mbox**: 본문 백틱 금지 · 5건/60초 속도 제한(방송 시 대기 후 재시도) · fan-out 은 팀별 문구 · 긴 본문은 relay · 고스트 서제스천 무시 · planner pane 에 질문 창(AskUserQuestion)이 떠 있으면 ring 금지.
- **보고**: 오빠 보고 틀 = 결론 1줄→오빠 할 일→바뀐 것→근거 + PR/Issue 번호는 맨 아래 표. 마일스톤 1줄은 planner#13 로. 틱 = 하위 좌석 pane done 줄·jsonl 실측(`ft-seat-status.sh turn --json`) + `ft-board.py stalled --min 3`.
- **판정 511·514 규칙(나에게도)**: 상태 칸은 실측만 · 끝난 좌석은 깨우지 않는다(`[완료·휴식]` = 닫기 또는 다음 카드) · 다음 일은 planner 판정(스스로 만들지 않음).

## 환경
워크트리 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops`(ops/main-base · push 대상 아님). mbox `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh`. 판정서 `design/harness/OPS-VERDICTS-20261006.md` · 요청 원장 `design/harness/REQUEST-LEDGER.md`. 백업(scratchpad `…/31dfe316-…/scratchpad/`): main-team-governance.md.bak-514 · COMM-GUIDE-BOOT.md.bak-514 · ft-nano-close.sh.bak-r53 · seats-*.json.bak-board-keys · byz_slack_questions.bak-r49 · *.bak-v421/-r52/-v511.
