# HANDOFF — byz-harness-arch-claude#13 → #14 (2026-10-08 · 컨텍스트 413k 승계)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

이 좌석의 골 축: A 모니터·오빠 요청 + 6-b(개선요청 접수·협의) + C(배포·반영).

## 승계 첫 일 (순서 고정)
1. ~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md Read → Serena initial_instructions → activate_project(★/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops★ — 다른 워크트리가 잡힌다) → i-have-adhd 로드.
2. 골 대조 + 부팅 보고(세션명 / 모델·창 / Serena / i-have-adhd / cron=<id>)를 현역 master(★byz-harness-master-claude#15★)에 mbox. 같은 턴 CronCreate 10분 틱.
3. 함정: mbox 명령 줄(heredoc 포함)에 백틱이 있으면 PreToolUse 훅이 막는다(본문 파일에 mbox.sh 글자만 있어도) → 카드·문서는 Write 도구로 · 쪽지는 relay. zsh `$(` grep 패턴 비는 일 → grep -F/python. 임시 파일은 scratchpad.

## 역할 (governance §6)
arch = 설계·카드(대기/ · lint 통과 · 미커밋)·DA 소환 판단·나노 결과 «독립 재현»·판정서 초안. master = 커밋·push·설치·좌석. arch 코드 0.
- 카드 lint: `source <루트>/.fable-team/bin-harness/harness-env.sh; FT_CARD_REQUIRE_PREVERIFY=1 bash scripts/harness-install/fable-team/bin/ft-index-lint.sh <카드>` — 구현 범위에 «실재 파일 경로» 1개 이상 필요 · DA 마지막 판정 HOLD 면 REJECT → 2 HOLD 종료 건은 「소환: 아니오 + 면제: … — arch 서명 <좌석>」 으로 사실대로.
- 나노 증거 줄: harness-ops 의 진행/ 카드 끝 맨몸 줄 · 미커밋 · 세트 = 나노 HEAD. 나노가 자기 브랜치에 카드 사본 커밋하면 HEAD 가 밀려 REJECT(R30 실례) → `ft-nano-evidence-check.sh <카드> --repo <나노 wt> --feat <base_sha>` 먼저.
- 판정서 초안 = `<루트>/.fable-team/state/drafts-r21/OPS-VERDICT-<N>.md` · ★다음 번호 §58★(§56 R29 · §57 R30 반영 끝).
- DA = byz-harness-da-codex#0(relay · 10+10분 · 2 HOLD 면 중단·통합 이관).
- 전역 훅 카드 초안에는 «전역 훅 영향 점검 표»(입력 차단 가능성·팀 밖 세션 무출력·워크트리 판정·라이브 bin 선행·되돌림)를 넣는다(§57 꼴).

## 이 세션에서 닫힌 것
| 무엇 | 닫는 증거 |
|---|---|
| R30 승계 창 자동 이관 | §57 · 랜딩 697112e720 + e70527f301 · 구현 DA APPROVE(DA-r30 §10) · 반송 1회(guard 루트·MISMATCH 폭주) |
| R29 cherry 게이트 --squashed-pr | §56 · a619a6b06b · 실사례 dry-run 같음 19·고쳐짐 2 |
| 판정 410 감사 | design/harness/AUDIT-j410-console-vs-slack-20261008.md(17건 · 원인 = 출처 차) |
| R34 원인 실측 | design/harness/AUDIT-r34-planner-relay-latency-20261008.md(읽음 중앙값 22초 · 미보고 10/39) |
| 421+423+425-B 설계 | DESIGN-news-tree-workqueue-viz-20261009.md r2 + §8 · DA 2 HOLD 종료(N1·N3 APPROVE · N2 정본 술어) · 오빠 컨펌 판정 430·431 |
| 카드 2장 lint OK | 대기/v430-verdict-ledger.md(나노 1) · 대기/v425-master-inbox.md(나노 4) |

## 열린 일 (순서대로)
1. **421 카드 2장 더 작성**(master #62749): 나노 2 상태판 = 설계 §2-2·§2-3·§3 나노 2(ft-board.py · 명부 키 `_cards`·`_cards_wt`·`_label` · 스냅샷 먼저→chat.update→변경 단위 diff 답글 · ft-news-tree.py 결함 3 해소) · 나노 3 발행+보고 훅 = §2-4·§3 나노 3(byz_thread_post update · report-coverage Stop · drain-before-interview PreToolUse · 턴 키 1회 · 오류 통과+기록 · 미러 요약기 할 일 금지 + ★모델 = 오빠 컨펌값 claude-haiku-5-5★(scripts/harness-install/slack-mirror/mirror_summary.py:17 지금 4.5) · planner 처리 1줄 · ①~④ 항상 ring · 회신 상한 제외 · 전역/planner 훅 영향 점검 표). 꼴 = 대기/v425-master-inbox.md 복제(Write 도구). lint OK 뒤 master 에 알림.
2. **카드 2(result-reply-close-gate) 재현 + §58 초안**(master #62758): 나노 브랜치 nano/result-reply-close-gate e04492076f+e7c62f2197 · master 검증 index_move_slack 12/12 · slack_post_guard 15/15 · kit_sync PASS. 할 것: 재현 · 편차 1건 판정(ft-index-move.sh 가 --issue/--seat/--canon/--next/--resume-script 를 카드·ft-resume-cmd.sh 에서 채움 — 카드 범위 안인가) · §58 초안 + 전역 훅 slack-post-guard 라이브 설치 전 «오탐 시 입력 차단 여부» 점검 표.
3. 나노 1·4 결과 오면 재현 → 판정서 초안(§59~).
4. 별 카드 제안 대기: distill-gate 루트 판 .claude/hooks/context-distill-gate.sh:104 haiku 200k 창 값 → Haiku 5.5 실제 창(master 지시 오면).
5. 대기 카드: gate-hook-kit-equals-home(planner 지시 대기) · r23-tank-rest-path(보류).

## 함정 (실측 · 이 세션)
- master 는 #14 → #15 승계됨(수신처 #15). planner = #10.
- 라이브 .fable-team/comm/mbox.sh 가 tools/comm-canonical/mbox.sh 보다 60줄 앞섬(mbox.py 는 같음) — mbox 고치는 카드는 사본 동기화 [structure] 먼저.
- 판정 번호 원장 파일 없음(이번 나노 1 이 만듦) · 슬랙 미러는 mbox 행만 읽고 planner 콘솔 보고는 안 실림.
- DA 판정문은 DA 파일에 §N 으로 append 되고 mbox 로 결론 1줄이 온다.
