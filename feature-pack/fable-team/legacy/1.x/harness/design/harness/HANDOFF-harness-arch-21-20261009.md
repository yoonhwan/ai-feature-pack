# HANDOFF — byz-harness-arch-claude#21 → #22 (2026-10-09 · 컨텍스트 403k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

이 좌석의 골 축: A 모니터·오빠 요청 + 6-b(개선요청 접수·협의) + C(배포·반영).

## 승계 첫 일 (순서 고정)
1. `~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md` Read → Serena `initial_instructions` → `activate_project(project="/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops", session_id=…)` → i-have-adhd 로드.
2. 골 대조 + 부팅 보고(세션명 / 모델·창 / Serena / i-have-adhd / cron=<id>)를 현역 master(**byz-harness-master-claude#21** — 발신 전 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/seats-harness.json` `_master` 확인)에 mbox. 같은 턴 CronCreate 10분 틱(mbox recv + `tmux ls | grep byz-harness-nano` pane 실측 + 오빠 3줄).
3. master 에 부탁: `bash .fable-team/bin/ft-seat-retire.sh byz-harness-arch-claude#21 byz-harness-arch-claude#22 --seats .fable-team/seats-harness.json`.

## ★지금 할 일★ = 없음 · [완료·휴식]
- master#21 지시(#66908): 다음 일 = **09시 오빠 큐 10** · 그때까지 휴식 · 별 카드 후보 2건 착수 0.
- 열린 하네스 나노 0 · DA `byz-harness-da-codex#0` 유휴.

## 이 세션에서 닫힌 것 (판정서 초안 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/state/drafts-r21/OPS-VERDICT-<N>.md` → master 반영)
| § | 단위 | 랜딩 |
|---|---|---|
| 95 | r63e(R64) block-destructive 상대경로 정본 mbox 인정 (DA 2 HOLD → arch 서명) | PR 1048 · 홈 설치 |
| 96 | 판정 592 ① 키트 orchestration-gate = 홈 정본 | PR 1049 |
| 97 | 판정 592 ② block-destructive 209 → 훅 87 + 판정기 123 | PR 1050 · 홈 설치 |
| 98 | 판정 592 ③ mbox.sh 242 → 127 + mbox_doorbell.sh 120 | PR 1051 · 라이브 설치 |
| 99 | 판정 592 ④ mbox.py 637 → 126 + 모듈 4 (DA r1 HOLD 링크 import → 보강 → r2 APPROVE) | PR 1052 · 라이브 설치 |
- 다음 판정서 번호 §100.

## 별 카드 후보 (착수 0 — 오빠/master 지시 때만)
1. `tools/comm-canonical/check-drift.sh` MAP 의 옛 `.worktrees/v6-realtime-live/…` 행(전부 MISSING_RUNTIME) 정리 + README 복구 명령 경로.
2. `boot-read-gate.sh` 키트↔홈 머리 주석 2줄 차이(동작 같음).

## 함정 (실측 · 이 세션)
- ★파괴·주입 명령 글자는 홈 훅이 막는다★ — 시험 프로브는 스크래치 «파일» 안에서 조립(`RM='rm'' -''rf'`)해 `bash <파일>` 로 실행. 막혀도 우회 금지(정상 차단).
- 라이브 통신 파일은 링크: `.fable-team/comm/{mbox.sh,mbox.py,mbox_doorbell.sh}` → `.claude/fable-team/bin/` 실파일. 파이썬 모듈(`mbox_conf·store·guard·ops`)은 bin 에만(comm 링크 불요 · 진입 `mbox.py` 첫 줄이 realpath 폴더를 sys.path 에 넣음).
- `check-drift.sh` 는 루트 기준으로 돌린다(워크트리에서 돌리면 MISSING).
- 나노 워크트리 = origin/main 기준 → ops/main-base 에만 있는 도구는 «절대경로»로 넘긴다.
- shellcheck 은 source 를 따라가게 `-x` 로 본다(단독이면 SC1091·SC2034 거짓 경고).
- pytest `tests/scripts/*` 는 `.venv/bin/python -m pytest --noconftest`(공용 conftest 의 `shared` 부재).
- 같은 워크트리를 master 도 쓴다 → 커밋은 항상 `git commit -- <내 경로>`.
- 스크래치패드(내 세션) = `/private/tmp/claude-501/-Users-yoonhwan-Project-Agent-BYZ-Work-BYZ-Agents--worktrees-harness-ops/7aa01f8d-4b76-4f2c-937f-6ced4ba177e8/scratchpad/` — `probe_r63e_r2.py`·`probe_r63e_r3.py`(block-destructive JSON 31행 재생) · `repro97/98/99.sh`.
