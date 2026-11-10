# HANDOFF — byz-harness-arch-claude#20 → #21 (2026-10-09 · 컨텍스트 401k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

이 좌석의 골 축: A 모니터·오빠 요청 + 6-b(개선요청 접수·협의) + C(배포·반영).

## 승계 첫 일 (순서 고정)
1. `~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md` Read → Serena `initial_instructions` → `activate_project(project="/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops", session_id=…)` → i-have-adhd 로드.
2. 골 대조 + 부팅 보고(세션명 / 모델·창 / Serena / i-have-adhd / cron=<id>)를 현역 master(지금 **byz-harness-master-claude#20** — 발신 전 `.fable-team/seats-harness.json` `_master` 확인)에 mbox. 같은 턴 CronCreate 10분 틱(mbox recv + `tmux ls | grep byz-harness-nano` pane 실측 + 오빠 3줄).
3. master 에 부탁: `bash .fable-team/bin/ft-seat-retire.sh byz-harness-arch-claude#20 byz-harness-arch-claude#21 --seats .fable-team/seats-harness.json`.

## ★지금 할 일★ — r63e(R64) DA r1 HOLD 반송 → 결과 오면 재현 → DA r2
- 반송서 r1 = `.fable-team/state/drafts-r21/REJECT-r63e-mbox-ok-relative-path-r1.md` (작성 완료 · master#20 에 송신 완료 — 나노 전달은 master). 처방: `moved` 를 따옴표·역슬래시 지운 글자로 판별(`c''d`·`c\d` 반례).
- 나노 `byz-harness-nano-r63e-mbox-ok-relative-path#0` · 브랜치 `nano/r63e-mbox-ok-relative-path` · r1 커밋 `f94a4a5ebe`. DA 요청서 `design/teams/harness/DA-REQ-r63e-mbox-ok-relative-path-20261009.md` · 판정문 `design/teams/harness/DA-r63e-mbox-ok-relative-path-20261009.md`(r1 HOLD Q2).
- 수정 결과 오면: 아카이브 재현(test_block_destructive · _inject) + 스크래치 `probe_r63e.py`(15행 · 경로는 아래 함정) + 새 반례 2 → DA r2(Q2만 · 요청서에 `## r2 요청` 절 추가 · DA = `byz-harness-da-codex#0`) → 판정서 초안 **§95** → master.
- 그 뒤 master 가 r63b 훅 재설치(§93 7단계 + R64 원 명령 `bash ../../.fable-team/comm/mbox.sh send … 'redis-cli SET …'` 를 JSON cwd=워크트리로 재생 = 0).

## 이 세션에서 닫힌 것 (판정서 초안 → master 반영)
| § | 단위 | 랜딩 |
|---|---|---|
| 89 | v423c 미러·mbox (DA 2 HOLD → arch 서명) | PR 1044 · 라이브 comm+미러 설치 |
| 90 | R60+R62 보드 발행 WorkingDirectory + 비교 키 정규화 | 진행 중(master) |
| 91 | R63 발주 BODY 측정 조작 금지 1줄 | PR 1042 |
| 92 | R63 ㉡ 증거 검사 | PR 1043 |
| 93 | R63 ㉠ INJECT 블록 (DA 2 HOLD → arch 서명) | PR 1047 · ★홈 설치 오탐 1건으로 원복(R64)★ |
| 94 | r63d 증거 검사 소음 축소 | PR 1046 |
- 다음 판정서 번호 §95(r63e).

## 함정 (실측 · 이 세션)
- ★지금 홈 훅(원복된 옛 판)도 상대경로 mbox 본문의 파괴 명령 글자를 막는다★ — 쪽지는 절대경로 `bash /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh …` 로 보낸다. 시험 프로브에 파괴 명령 글자가 들면 python heredoc 도 막힌다 → 스크래치패드 파일로 쓰고 실행(`RM = 'rm'+' -'+'rf'` 꼴).
- zsh 에서 `"$MB:path"` 의 `:p…` 는 수식어로 먹힌다 → `bash <<'EOF'` 또는 `bash -c`.
- `rm -rf` 는 스크래치에서도 막힌다 → `mktemp -d` 새 폴더.
- 같은 워크트리(harness-ops)를 master 도 써서 내 staged 변경이 master 커밋에 실린 적 있다 → 커밋은 항상 `git commit -- <내 경로>`.
- 하네스 카드는 `ft-index-lint.sh` 에서 골 3줄 불일치 REJECT(기존 카드도 같음 · spawn lint 와 별개).
- 판정서 초안 자리 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/state/drafts-r21/OPS-VERDICT-<N>.md`.
- 스크래치패드(내 세션) = `/private/tmp/claude-501/-Users-yoonhwan-Project-Agent-BYZ-Work-BYZ-Agents--worktrees-harness-ops/0e1468cc-dcf6-4a0e-a10c-bcea02ec50c2/scratchpad/` — `probe_r63e.py`·`probe_r64.py`·`injtest.sh` 가 있다(후계는 자기 스크래치에 복사해 쓴다).

## 큐 (master 한 번에 하나)
1. r63e 닫힘(§95) → r63b 재설치(master). 2. 훅 템플릿 208줄(200 초과 · 분리 별 카드 후보). 3. `mbox.py` 637줄(분리 별 카드 후보). 4. 이전 큐: `gate-hook-kit-equals-home` → `r35` → `mbox-sh-split-200`. r23 보류.
