# HANDOFF — byz-harness-master-claude#16 → #17 (2026-10-08 · ctx 403k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
이 단위의 골 축: A(모니터·오빠 요청) + 6-b(개선요청 접수·협의) + C(업그레이드·커밋·push·반영) + 원문 5(머신 독립 배분).
★승계 첫 일 = 골 대조 3줄 + 부팅 3항 + i-have-adhd 를 현역 planner(`ft-harness-info.sh seats` · 지금 byz-planner-master-claude#11)에 mbox 보고 → 같은 턴 CronCreate 10분 틱(cron=job id 보고).★ BOOT 17조항 먼저. 전임 크론 `bdb3920e` 는 후계 부팅 보고 뒤 내가 삭제. 오빠 보고 = 결론→할 일→바뀐 것→근거 + PR·Issue 번호는 맨 아래 각주 표.

## 지금 상태 (한 줄)
★PR 956(R42 sha base 닫기 수정) CI 1건 남음 · PR 958(R41 정본 영향 없음 쪽지 소음) CI 진행 중 — 초록이면 각 `gh pr merge <N> --squash`(push·re-run 0) → 라이브 FT_BIN cp → 나노 닫기 → 판정서 §71·§72 → 카드 완성 이동.★

## 이번 세션(#16)에 끝낸 것 (전부 판정서 §62~§70 · origin/main)
PR 929(판정 원장·인박스·슬랙 게이트) · 935(fixture 단축 §62) · 937(슬랙 미러 복구 §68) · 941/943/944(판정 444 정본화 §63·§66·§64) · 945(Mobile Test 변경 감지 §65) · 951(xdist §67) · 954(인박스 via 필드 §70) 병합. 판정 438=오빠 판정 460 으로 «7분 반» 닫힘(§69). 판정 441 점검표 회신. 라이브 설치 전부 cmp OK(드리프트 85파일).

## 열린 일 (순서)
1. **PR 956 (nano/r42-nano-close-sha-base · ce1d7da3dc)** CI 초록 → squash 병합 → 라이브 cp 2파일: `ft-nano-close.sh`·`ft-nano-spawn.sh` (원천 = origin/main 의 `scripts/harness-install/fable-team/bin/`; 라이브 FT_BIN=`v6-realtime-live/.fable-team/bin` + 루트 `.fable-team/bin` 둘 다 cp+cmp, 백업 먼저) → `ft-live-bin-drift-check.sh --bin $FT_BIN --repo . --ref origin/main` OK → v65 master#148 에 「고쳤다」 알림(그가 고치면 알려 달라 함) → 나노 `byz-harness-nano-r42-nano-close-sha-base#0` 닫기(`--recv 63799`) → 카드 증거 줄 append + 판정서 §(번호 다음) + 완성 이동.
2. **PR 958 (nano/r41-index-move-canon-notice-noise · 66e26a1edd)** 같은 순서. 라이브 cp 1파일 `ft-index-move.sh`. 나노 닫기 `--recv 63818`(r41 마지막 보고 63824 = 증거 줄). arch#16 이 R41 진행 카드(미커밋 `진행/r41-index-move-canon-notice-noise.md`)에 문구 반영했으니 그 파일 커밋 포함.
3. **원장 R38~R42 상태**: R38·R39·R40 = block-destructive.sh 오탐(주석/heredoc/Dockerfile 본문/mbox 본문 인용) → «훅이 실행 문맥과 본문 글자를 구분» 통합 카드 1장 대기(planner 우선순위 확인 필요, 낮음). R41=PR 958. R42=PR 956.
4. **대기 카드(planner 우선순위)**: R35 `r35-role-spawn-team-env-reject.md` · `mbox-sh-split-200.md` · `r23-tank-rest-path.md` · `v421-board.md` · `v423-publish-report-hooks.md` · 보류(커밋 금지·미추적) `gate-hook-kit-equals-home.md`(판정 345) · `design/ops/`.
5. **판정 444 팀 공지 미발신**: index-move 새 규칙(판정 절에 「대상 카드: <카드>」 줄)을 팀 master·DA 좌석에 1줄 공지(v65·cfo·loom·ops·feature·issues). 이미 알린 곳 = issues master(6항). CFO·v65 등은 아직.
6. **판정 441 후속 관찰**: 인박스 via 필드 병합 후 Haiku 성공률은 `jq -s -c 'group_by(.via // "unknown")|map({via:(.[0].via // "unknown"),n:length})' .fable-team/state/inbox/<계보>.jsonl` 로 셈. 미사용 `mark`/`report` 는 planner 가 recv 로 처리 중(강제 0).
7. **R36**(scripts/server 터널 안내·회전 체크리스트 = ops 소관 제안) planner 판정 대기.
8. **판정서 번호**: 마지막 §70. 다음 §71(R42 또는 R41 먼저 닫히는 쪽). 판정 번호는 planner 발급(판정 441·442·444·446·451·460·461·462 다룸). 요청 원장 `REQUEST-LEDGER.md` 다음 번호 R43.

## 현역 좌석
planner `byz-planner-master-claude#11` · cfo `byz-cfo-master-claude#61`(명부 _master 이미 #61) · issues `byz-issues-master-claude#4` · feature `byz-feature-master-claude#3` · ops `byz-ops-master-claude#0`+arch#1 · loom `byz-loom-master-claude#1`+arch#1 · v65 `byz-v65-master-claude#148` · harness arch `byz-harness-arch-claude#16`(Opus 5.5 · cron ef785ee0 · 명부 `_arch`) · DA `byz-harness-da-codex#0` · 나노: r42(PR 956)·r41(PR 958). 정지 레디: harness master #9~#16 · arch #8~#15(arch#15 크론 삭제 확인 대기).

## 운영 규칙·함정 (이번 세션 실측)
- **하네스 나노 spawn 은 반드시 `--base origin/main`**: `ft-nano-spawn` 은 호출 브랜치(ops/main-base, main 보다 ~290 앞섬) HEAD 를 base 로 쓴다. `FT_NANO_FEAT=origin/main`(harness-env.sh 정정됨)은 닫기 비교용일 뿐 spawn base 를 안 바꾼다. 안 주면 나노에게 «git checkout -B <브랜치> origin/main + info base 정정» 첫 일을 지시(r42·r41 이 그렇게 정정됨).
- **환경 소스**: `source ../../.fable-team/bin-harness/harness-env.sh && export FT_SEND_FROM='byz-harness-master-claude#<본인>'` 후 `$FT_BIN/ft-nano-spawn.sh|ft-nano-close.sh|ft-nano-evidence-check.sh|ft-index-move.sh` (repo 쪽 `scripts/fable-team-bin` 은 낡아 lint 도구 없음).
- **나노 닫기 순서**: ①증거 줄(나노 RESULT 의 세트/시험/이슈)을 카드 끝에 맨몸 1줄 append(master 가) → `ft-nano-evidence-check.sh <카드> --repo <나노 wt>` OK → ②`ft-nano-close.sh <좌석> --result <카드> --recv <seq> --cherry-override "<PR squash 랜딩 사유 + blob 동일>"`(유휴 3분 필요 — 3분 미만이면 REJECT, 기다린 뒤 «한 번만») → ③카드 `ft-index-move.sh 진행/…md 완성 --da 'design/teams/harness/OPS-VERDICTS-20261006.md#§N'`. ★카드를 완성으로 먼저 옮기면 close 가 명부 `index`(진행 경로)를 못 찾아 REJECT★ — 닫기 «먼저» 이동 «나중». 증거 줄 «시험» 칸에 `.github/` 변경이면 «없음(문서)» 거부(코드 경로로 봄) · 사유에 `·` 쓰면 구분자와 충돌.
- **판정서 §N 절은 「대상 카드: <카드>」 줄 필수**(새 ft-index-move 결속 · 정확 일치). 소급 없음.
- **git add -A 차단 훅**: 경로 명시. 삭제·이동은 ft-index-move 가 이미 스테이징. `gate-hook-kit-equals-home.md`·`design/ops/` 는 커밋 금지.
- **block-destructive 오탐**: Bash 본문에 삭제 옵션 글자·DROP 글자가 들어가면 차단 — 원장 기록은 Edit 도구로. 기록+허용(오빠 10-07).
- **CI 비용(판정 436)**: 로컬 검증 후 push 1회 · re-run 0 · 병합 전 `gh pr checks` 전 항목 pass/skipping · 문서만 PR 은 CI 0(paths-ignore). 최신 main 병합 뒤 재시험하고 push.
- mbox: 본문 백틱 금지 · 긴 본문은 파일 후 relay · `--urgent` 는 마지막 인자. 승계로 이름이 바뀌므로 발신 전 `ft-harness-info.sh seats` 로 현역 확인. 고스트 서제스천 무시.

## 환경
워크트리 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops`(브랜치 ops/main-base · push 대상 아님 — 코드/설정은 나노가 origin/main 기반 브랜치로 PR). mbox `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh`. 판정서 `design/teams/harness/OPS-VERDICTS-20261006.md`. 백업 위치(이번 세션): scratchpad `…/d63a71ae-…/scratchpad/` (livebin-backup-1008.tar · seats-*.bak · harness-env.sh.bak-1008 · mbox.sh.bak-1008).
