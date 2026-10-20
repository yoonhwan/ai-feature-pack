# r610 — tmuxc 비 claude 좌석 git 비대화 3종 (0.4.4)

사건: pi 나노가 `git rebase --continue` 에서 화면 없는 `vi` 를 열어 54분 정지 → 발주 5통 미처리 → r599 착지 막힘 (arch 113 실측 2026-10-21 06:1x).

## 변경
- `feature-pack/tmuxc/core/bin/tmuxc` — `open`(672~)·`fork`(857~) 의 `seat_env` 에 `agent != claude` 일 때
  `GIT_EDITOR=true` · `GIT_SEQUENCE_EDITOR=true` · `GIT_TERMINAL_PROMPT=0` 추가.
- `core/VERSION` · `manifest.json` 0.4.3 → 0.4.4 · `README.md` 절 추가(「비 claude 좌석의 git 비대화」).
- 시험 칸: `test/test_tmuxc_agent_seat_git_editor.sh`(신규) · `test/verify.sh` ㉙ · `test/test_tmuxc_opencode_model.sh` 2줄(OPENCODE env 0 → «OPENCODE env 0» 로 의도 유지).

## base(c920b0f/origin-main) 대조 — `tmuxc open --dry-run` env 줄 원문
| agent | base | after |
|---|---|---|
| pi | TMUXC_PI_SESSION_ID·TMUXC_PI_MODEL·TMUXC_PI_THINKING (3) | + GIT_EDITOR · GIT_SEQUENCE_EDITOR · GIT_TERMINAL_PROMPT (6) |
| codex | (0) | GIT_EDITOR · GIT_SEQUENCE_EDITOR · GIT_TERMINAL_PROMPT (3) |
| opencode | (0) | 위 3줄 (모델 지정 시 OPENCODE_CONFIG_CONTENT 와 함께) |
| cmd | (0) | 위 3줄 |
| claude | (0) | (0) ← 회귀 0 |

## 시험
- ⓐ FAIL(前): `bash test/test_tmuxc_agent_seat_git_editor.sh` rc=1 — pi env 0/3. PASS(後): rc=0 ALL PASS.
- ⓑ codex·opencode·cmd 3줄 + opencode 모델 env 유지 — PASS.
- ⓒ claude env 0 — PASS.
- ⓓ `test/verify.sh` rc=0 `tmuxc verify OK` · `test/test_tmuxc_opencode_model.sh` rc=0 ALL PASS.
- 실전 경로(가짜 tmux `new-session -e`) 에 3줄 실림 — PASS.

## 남는 일(master)
- 착지 → `feature-pack/tmuxc/install.sh` 설치본 cmp0 → 새 pi 좌석 env 실사건 1(`tmux show-environment -t <좌석>`
  또는 좌석 안 `git var GIT_EDITOR` = true).
- press 필요 없음(이 카드는 라이브 오디오 무관 · 단위·dry-run 만).
