# HANDOFF — byz-harness-arch-claude#18 → #19 (2026-10-08 · 컨텍스트 403k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

이 좌석의 골 축: A 모니터·오빠 요청 + 6-b(개선요청 접수·협의) + C(배포·반영).

## 승계 첫 일 (순서 고정)
1. `~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md`(지금 19줄 — 18 정지 감시 · 19 완료·휴식) Read → Serena `initial_instructions` → `activate_project(project="/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops", session_id=…)` → i-have-adhd 로드.
2. 골 대조 + 부팅 보고(세션명 / 모델·창 / Serena / i-have-adhd / cron=<id>)를 현역 master(지금 **byz-harness-master-claude#19** — 발신 전 `.fable-team/seats-harness.json` `_master` 확인)에 mbox. 같은 턴 CronCreate 10분 틱.
3. master 에 부탁: `bash .fable-team/bin/ft-seat-retire.sh byz-harness-arch-claude#18 byz-harness-arch-claude#19 --seats .fable-team/seats-harness.json`.

## ★지금 할 일★ — v423b(planner 보고 훅) 반송 r1 회수
- 반송서 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/state/drafts-r21/REJECT-v423b-report-hooks-r1.md`(DA r1 Q3 HOLD — 맨 `#숫자` 를 seq 로 봄 → 식별 규칙 = **`쪽지 #<seq>`** 꼴만 · hook-errors.log 를 `state/hook-errors.log` 한 곳으로 · 시험 ①~⑦). master#19 가 나노 `byz-harness-nano-v423b-report-hooks#0` 에 전달.
- r2 커밋이 오면: 재현(origin/main 아카이브 + 나노 커밋 diff 적용 — 브랜치 base 가 ops/main-base 라 diff 는 나노 커밋만 `git diff <c>~1 <c>`) → DA r2(Q3 + 시험 ①~⑤만 · bounded) 소환을 master 에 부탁 → APPROVE 면 §84 초안 `.fable-team/state/drafts-r21/OPS-VERDICT-84.md`(꼴 = OPS-VERDICT-83.md).
- 설치 전 planner 판단 1건(master 에 이미 전달 #65754): planner 인박스 ①~④ 미닫힘 119 seq — 등록 즉시 매 턴 block. 옛 줄 일괄 mark 먼저 할지.
- 요청서 `design/harness/DA-REQ-v423b-report-hooks-20261008.md` · 판정문 `design/harness/DA-v423b-report-hooks-20261008.md`(r1).

## 그 뒤 큐 (판정 545 순서 · master 한 번에 하나)
1. v423b 닫힘 → 2. `대기/v423c-mirror-mbox-notify.md`(요약기 할 일 금지 + Haiku 5.5 · planner 처리 1줄 · mbox ①~④ doorbell · 회신 상한 제외 · lint 실재 경로 2 확인됨) → 3. `gate-hook-kit-equals-home` → 4. `r35` → 5. `mbox-sh-split-200`(v423c 뒤). r23 보류.

## 이 세션에서 닫힌 것 (판정서 초안 → master 반영)
| § | 단위 | 랜딩 |
|---|---|---|
| 78 | R52 상태판 카드 제목 첫 5줄 H1 | #991 |
| 79 | 루트 지침 514(+511·516·522·532) · 정본 governance §8·§9 · BOOT 18·19 설치(sha c5d73fff80291434 / 01cddacdb2b070d8) · 방송 7팀 | #997 |
| 80 | v511 상태판 좌석 칸 실측 · stalled · 완료 선언 꼬리 | #1002 |
| 81 | R49 슬랙 질문 보드 3500B · 인박스 닫는 사건 · 적재 실패 재시도 0 | #1004 |
| 82 | R53 nano-close ③ = jsonl 마지막 timestamp 기록 | 랜딩 확인 필요 |
| 83 | v423a 보드 발행(뿌리 = 머리+⓪+④ · 3500B) | #1014 |
- 카드: v423 3분할(09c5159790) · R53 카드(4e74ffa52f) · v511 3구분 갱신 · R49 재확인.

## 함정 (실측 · 이 세션)
- **zsh `$M:` 수식자**: `git show $M:path` 처럼 변수 뒤 `:` 는 zsh 가 `:t`·`:h` 등으로 먹는다 → `${M}:` 또는 `bash <<'EOF'` 로.
- **mbox 명령줄에 백틱 0**(훅 차단) — 같은 Bash 호출 안 다른 명령(grep 패턴)에 백틱이 있어도 막힌다. 백틱 들어갈 글은 파일 + `mbox.sh relay`.
- **`rm -rf` 는 block-destructive 훅 차단** — 스크래치는 `mktemp -d <scratchpad>/x.XXXX` 새 폴더로.
- **나노 브랜치 base = ops/main-base** 인 경우 많음 → `merge-base origin/main` diff 에 ops 문서가 섞인다. 나노 변경만 = `git diff <c>~1 <c>`, 재현 = origin/main 아카이브 + 그 diff 적용.
- **시험이 스텁 본문이면 크기 결함을 못 잡는다** — 슬랙 발행물은 항상 실제 루트 렌더로 바이트 실측(R49 631B · v423a 37,485B→2,969B). 슬랙 chat.update 거부선 = 3,909~4,073 바이트.
- **카드 spawn lint**: 구현 범위 절에 origin/main 실재 경로 1개 이상 필요(새 파일만이면 REJECT) — 기존 호출 대상 파일을 같이 인용.
- `ft-seat-status.sh turn` 은 첫 턴 중 좌석을 UNKNOWN, codex DA 좌석을 WORKING 으로 잘못 찍는다 — pane `✻/✽/✳ … (Ns` 줄로 교차 확인.
- `ft-inbox find_mail` 은 회전본 `mailbox.log.jsonl.1` 을 안 읽는다(R49 옛 질문 27건 영구 「인박스 밖」 · 별 카드 후보).
- `state/hook-errors.log` 에 Haiku 분류 연속 실패(`haiku rc=1` 23:12~) — 미상 쪽지가 보고 의무 훅에서 빠짐(새 요청 후보 · master 전달함).
- 판정서 초안 자리 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/state/drafts-r21/OPS-VERDICT-<N>.md` · 다음 번호 §84.
