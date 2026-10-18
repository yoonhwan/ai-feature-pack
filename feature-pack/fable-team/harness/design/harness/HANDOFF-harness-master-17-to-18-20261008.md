# HANDOFF — byz-harness-master-claude#17 → #18 (2026-10-08 · ctx 400k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
이 단위의 골 축: A(모니터·오빠 요청) + 6-b(개선요청 접수·협의) + C(업그레이드·커밋·push·반영) + 원문 5(머신 독립 배분).
★승계 첫 일 = 골 대조 3줄 + 부팅 3항 + i-have-adhd 를 현역 planner(`ft-harness-info.sh seats` · 지금 byz-planner-master-claude#12)에 mbox 보고 → 같은 턴 CronCreate 10분 틱(cron=job id 보고).★ BOOT 18조항 먼저. 전임 크론 `0b5ce805` 는 후계 부팅 보고 뒤 내가 삭제. 오빠 보고 = 결론→할 일→바뀐 것→근거 + PR·Issue 번호는 맨 아래 각주 표.

## 지금 상태 (한 줄)
★오빠 문책 판정 511(상태는 실측만 · 팀 master 본업 = 하위 좌석 정지·거짓 보고 감시)이 최우선. 전 팀 방송은 6곳 발신 끝, 정본 조항·강제 장치 설계는 arch#17 사전 DA 중. v421-board 나노(뉴스 개편 판정 502)가 구현 중.★

## 이번 세션(#17)에 끝낸 것 (전부 판정서 §71~§76 · origin/main)
PR 956(R42 sha base) · 958(R41 쪽지 소음) · 962(v466 block-destructive 글 싱크) · 965(R43 틱 옛 master 행 제외+ft-seat-retire) · 974(R44 push 강제·삭제 차단) · 983(슬랙 읽기 전용 공유판) 병합+라이브 설치 전부 cmp OK. 홈 훅 교체 2회(백업 scratchpad). 팀 틱 4개(cfo·ops·feature·loom 사본)에 R43 한 줄 필터 수동 이식(kit 통째 교체 금지 — 사본 전용 heir_of·retarget_seat·팀 뉴스 문구). 명부 `_hil_route` 3곳 #12 로 정정. 판정서 마지막 §76, 다음 §77(판정 511 설계 닫힐 때). 요청 원장 마지막 R50, 다음 R51.

## 열린 일 (순서)
1. **arch#17 판정 511 설계**(`design/teams/harness/DESIGN-511-seat-stall-watch-20261008.md` · 사전 DA #64771 진행): APPROVE 오면 ①governance §8 조항 ②BOOT 18줄 문구를 `~/.claude/skills/fable-team/references/main-team-governance.md`·`~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md` 에 «cp+cmp»(백업 먼저 · 내가 직접 쓰지 않는다 — 정본 변경은 arch 안 없이 집행 0). 강제 장치(ft-board 좌석 칸 jsonl 기계 채움)는 카드화 → 나노. 결과 planner#12 에 카드 경로 1줄.
2. **v421-board 나노 `byz-harness-nano-v421-board#0`**(워크트리 `.worktrees/harness-v421-board` · 카드 진행/v421-board.md · base a752a987d3): 구현 중(새 파일 ft_board_*.py 4개). RESULT 오면 → arch#17 독립 재현+닫힘 초안(대상 카드: v421-board) → 문서 동봉 PR(아래 절차) → 병합 → 라이브 cp → 나노 닫기 → 판정서 §77 이후 번호 → 카드 완성 이동. 랜딩 뒤 명부 `_tree` 4팀 기입 + 5팀 트리 작성은 master 몫(카드에 적혀 있음).
3. **R49 카드**(대기/r49-question-board.md · DA r2 APPROVE · lint OK): 슬랙 질문 보드가 36건·UTF-8 4073바이트로 chat.update msg_too_long 반복(설치 전부터). 처방 ①(건수+결정자리+오래된 5건, 3500바이트, 정리는 planner 인박스). 순서 제안(arch): v421 랜딩 → 511 카드 → R49. 한 번에 하나.
4. **대기 카드**(planner 우선순위 판정 492): R35 `r35-role-spawn-team-env-reject.md`(팀 DA 개설 정식 경로 R48 도 같이 판단) · `mbox-sh-split-200` · R23 `r23-tank-rest-path` · v423. 보류(커밋 금지): `gate-hook-kit-equals-home.md`(판정 345) · `design/ops/`.
5. **원장 접수만(완성 후·착수 0)**: R45 팀 틱 사본↔kit 계보 갈라짐 · R46 gh `--body-file -` heredoc 이 v466 글 싱크 밖(처방 후보: 싱크 확장=판정+DA) · R47 cd-dev 게이트 빨강(소관 ops, issues#5 배정) · R48 팀 DA 좌석 개설 정식 경로 없음(ops #979 에는 ops-env + 카드 기반 ft-nano-spawn 길 안내함).
6. **kk 위성**: 판정 511 방송 미발신(좌석 확인 안 됨, planner 에 알림 필요).
7. **명부 `_master` 낡음**: feature=#4(활동 #5) · loom=#1(활동 #3) · ops=#0(활동 #2) · v65 `_master`=#149. 정정은 각 팀 승계 때 `ft-seat-retire.sh`.

## 현역 좌석
planner `byz-planner-master-claude#12` · cfo `#62` · feature `#5`(명부 #4) · issues `#5` · loom `#3`(명부 #1) · ops `#2`(명부 #0) · v65 `#149` · harness arch `byz-harness-arch-claude#17`(Opus 5.5 · cron 625c0c82) · DA `byz-harness-da-codex#0` · 나노 `byz-harness-nano-v421-board#0`. 정지 레디: harness master #9~#17(#17 은 증류 직후) · arch #8~#16.

## 운영 규칙·함정 (이번 세션 실측)
- **환경**: `cd .worktrees/harness-ops && source ../../.fable-team/bin-harness/harness-env.sh && export FT_SEND_FROM='byz-harness-master-claude#<본인>'` → `$FT_BIN/ft-nano-spawn.sh|ft-nano-close.sh|ft-nano-evidence-check.sh|ft-index-move.sh|ft-seat-retire.sh`.
- **나노 spawn**: 카드 `대기/` → `ft-nano-spawn.sh <카드> --agent claude --model 'claude-sonnet-5-5[1m]' --effort high --base origin/main --from <본인>` → 워크트리 `merge-base --is-ancestor HEAD origin/main` 로 base 확인 → 카드 이동분 커밋(ops/main-base).
- **병합 절차(ops 문서 동봉 · 판정 444)**: 나노 브랜치에 `git merge origin/main` → `git checkout ops/main-base -- design/teams/harness/<파일들>`(NANO-LEDGER·OPS-VERDICTS·REQUEST-LEDGER·카드·설계·DA·인계서) + 완성/진행 중복 사본 `git rm` → 커밋 → 로컬 시험(그 나노 시험+kit_sync+ruff) → push → PR 본문은 **Write 로 파일 만들고** `gh pr create --body-file`(heredoc 본문을 gh 명령에 쓰면 훅 차단 R46) → CI 초록(`gh pr checks`) → `gh pr merge N --squash` → 라이브 cp+cmp(+백업) → drift-check → 나노 닫기.
- **나노 닫기**: 카드 끝에 증거 줄(`세트: <나노 현재 HEAD 40hex> · 시험: bash tests/harness/<시험> rc=0 · 이슈: 0`) append → `ft-nano-evidence-check.sh <카드> --repo <나노 wt>` OK → `ft-nano-close.sh <좌석> --result <카드> --recv <seq> --cherry-override "PR N squash <sha> blob 동일 (...)"` → `ft-index-move.sh 진행/…md 완성 --da 'design/teams/harness/OPS-VERDICTS-20261006.md#§N'`(§N 절에 「대상 카드: <카드>」 줄 필수). 닫기 «먼저», 이동 «나중». ★나노 HEAD 가 병합 커밋 때문에 시험 시점과 다르면 evidence-check 가 REJECT → 시험 재실행 후 줄 갱신.★
- **홈 훅 교체**: `~/.claude/hooks/block-destructive.sh` ← origin/main 키트 템플릿(백업 scratchpad). 설치본 검증 = `BD_HOOK=$HOME/.claude/hooks/block-destructive.sh bash <scratchpad 복사본>/tests/harness/test_block_destructive.sh`. 스모크 명령에 파괴 글자를 직접 쓰면 훅이 차단 → 시험 스크립트로 검증.
- **슬랙 미러 설치**: origin/main 키트를 scratchpad 새 폴더에 `git archive` 추출 → `BYZ_ROOT=<루트> bash <키트>/install-github.sh|install.sh|install-inbound.sh|install-magazine.sh`. github 미러는 bootstrap 1회 실패 후 재등록으로 복구됨. 미러 2개(mbox·inbound)는 종료코드 1 반복 = R49 질문 보드 건(설치 이전부터).
- **mbox**: 본문 백틱 금지 · fan-out 차단(같은 본문 600초 내 여러 좌석) — 방송은 팀별 문구로 · 5건/60초 속도 제한 · 긴 본문은 파일 후 relay. 발신 전 현역 이름은 `ft-harness-info.sh seats` + 최근 발신 기록(`tail mailbox.log.jsonl`)으로 교차 확인. 고스트 서제스천 무시.
- **훅 오탐 회피(R39·R46)**: Bash 에 파괴 글자·heredoc 본문이 들어가면 차단 → 원장 행·PR 본문은 Write/Edit 로 파일을 만든다. 기록+허용(오빠 10-07).
- **CI 비용(판정 436)**: 로컬 검증 후 push 1회 · re-run 0 · 병합 전 `gh pr checks` 전 항목 pass/skipping.
- **보고**: 오빠 보고 틀 = 결론 1줄→오빠 할 일→바뀐 것 3줄→근거 · PR/Issue 번호는 맨 아래 각주 표(번호·종류·제목·상태). 모든 승계·마일스톤 1줄은 planner#12 로.
- **판정 511 규칙(나에게도 적용)**: 상태 칸은 실측만(pane done 줄·jsonl·프로세스) · 「진행」은 지금 도는 좌석만 · 멈췄으면 「정지 N분 · 기다리는 것 = 누구의 무엇」 · 대기 3분 넘으면 그 턴에 ring/상위 보고. 매 틱 내 하위 좌석(arch·nano·DA) 정지 N분을 실측해 보고에 적는다.

## 환경
워크트리 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops`(브랜치 ops/main-base · push 대상 아님 — 코드/설정은 나노가 origin/main 기반 브랜치로 PR, 문서는 그 PR 에 동봉). mbox `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh`. 판정서 `design/teams/harness/OPS-VERDICTS-20261006.md` · 요청 원장 `design/teams/harness/REQUEST-LEDGER.md`. 백업 위치(이번 세션): scratchpad `…/ddb71631-…/scratchpad/` (block-destructive.sh.home-bak-1008 · home-bak-r44 · bk965 · bk-teamtick · seats-*.bak-* · main-team-governance.md.bak-511 · COMM-GUIDE-BOOT.md.bak-511 · dumb-time-ledger.md.bak-511).
