# r286 master 집행 순서 (나노 산출 · 착지·설치·실사건은 master 손)

## 실측 정정 (나노 · 2026-10-19)
- 카드 경로(`scripts/fable-team-bin/…` · `scripts/harness-install/…` · `tests/harness/…`)는 r386(BYZ 하네스 사본 삭제) 전 꼴 — 지금 정본은 팩 `feature-pack/fable-team/harness/` → 팩 가지 `nano/r286-roster-opencode-nano-close`(base origin/main b75e62f7). BYZ 가지 `nano/r286-roster-opencode-nano-close` 는 변경 0.
- 훅 위치 = 키트 `kit/hooks/opencode-reap-check.sh`(카드는 `templates/hooks/`) — LIVE-MAP `hooks/*` = cmp `~/.claude/hooks` 라 `ft-live-install-check` 가 설치를 대조한다(`fable-team/templates/*` 는 skip = 설치 확인 0).
- BOOT 조항 번호 = **41**(카드 «39» 는 10-16 기준 — 지금 39·40 이 이미 있음).
- 선행 HIL(kill 예외)은 이미 확정 — 전역 `~/.claude/CLAUDE.md` 하드 룰 2 «opencode 정리 kill 표준승인 (2026-10-17 · 판정 2035 · R286)».
- ★실측: 지금 머신의 `opencode serve --service`(pid 52898 · 18:56 시작)는 **ppid 1 · cwd = $HOME** 으로 뜬다 — 공유 서비스일 수 있다. 그래서 «스폰 뒤 새로 뜬 부모 잃은 serve»(via=new) 는 기록하되, 닫을 때 다른 opencode 가 살아 있으면 `oc-skip`(공유 의심 · kill 0)으로 남긴다. 좌석 나무(①)·좌석 워크트리 cwd(③)·기록(같은 lstart)은 그대로 회수.
- 홈 로스터의 architect·DA 행은 카드 표와 글자가 다르다(홈 arch = «sonnet-5 기본…» · 카드 = «Opus 5.5» / 홈 DA = «codex-5.6-sol 또는 grok-4.6» · 카드 = «gpt-6.1-sol low+fast»). 카드가 두 행 모두 «변경 0» 이라 staged 사본은 홈 글자 그대로 — 고칠지는 planner 판정.
- 전역 `~/.claude/CLAUDE.md` «오케스트레이션» 절의 모델 줄(opus-4-8 등)도 stale 이지만 카드 범위(홈 rules 로스터만) 밖 — 손대지 않음.

## 순서
1. 착지: 팩 `nano/r286-roster-opencode-nano-close` → main(버전·CHANGES 머리는 착지 순서대로 — 문안 아래).
2. 설치(되돌림 = `.bak-r286`):
   - 하네스: `bash <하네스>/install.sh --apply` → LIVE_BIN `ft-opencode-reap.sh`(새)·`ft-nano-spawn.sh`·`ft-nano-close.sh` 키트와 cmp 0.
   - 홈 훅: `cp -p <키트>/hooks/opencode-reap-check.sh ~/.claude/hooks/` → cmp 0 · `~/.claude/settings.json` 의 `PostToolUse` 배열에 1줄: `{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash /Users/yoonhwan/.claude/hooks/opencode-reap-check.sh", "timeout": 10}]}`(훅 안 외부 호출 = ps 1회 7 s 상한) → `ft-settings-lint.py ~/.claude/settings.json` OK.
   - 홈 정본 2: `cp ~/.claude/rules/orchestration.md{,.bak-r286}` → `design/harness/staged-r286/orchestration.md` cp · `cp ~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md{,.bak-r286}` → `design/harness/staged-r286/COMM-GUIDE-BOOT.md` cp(41항 추가만 · 삭제 줄 0). 사본 기준 홈 sha256 앞16 = orchestration ec3f6ba83bed8fbf · BOOT c2aa97171b0719d5 — 홈이 그새 바뀌었으면 사본을 다시 뜬다.
   - `ft-live-install-check.sh --range <병합 전 main>..<착지 sha>` OK.
3. 실사건 1: `ft-nano-spawn.sh <짧은 서치 카드> --tier search` → 짧은 서치 1건 → `ft-nano-close.sh` → 출력 `OC-REAPED <좌석> reap left=0 rc=0` + 닫힌 뒤 `ps -axww -o pid=,ppid=,command= | grep -i '[o]pencode'` 에 그 좌석 opencode 0(공유 serve 가 `oc-skip` 으로 남았으면 그 pid 를 카드에 적는다) → 카드 `- 실사건:` 줄.
4. desk#8 1줄(master 경유): 로드 줄 = BOOT 41 + 홈 orchestration.md 로스터 아래 · 도구 = ft-opencode-reap.sh · 시험 rc.

## CHANGES 문안
- r286 opencode 나노 = 읽고 모으기 · 쓰면 매번 닫기 — `ft-opencode-reap.sh`(좌석 나무·부모 잃은 serve·pid 기록 회수 · left=0 · 남의 opencode 0 · 공유 serve oc-skip) · `ft-nano-close` 가 opencode 좌석을 kill 뒤 회수(left≠0 = CLOSE-FAIL) · `ft-nano-spawn --tier search`(opencode/deepseek-v4.1-flash-free) · 나노·checker·tester 기본 모델 claude-sonnet-5-5[1m] · 홈 훅 `opencode-reap-check.sh`(PostToolUse Bash · 알림만).

press 필요: 없음(프로세스·tmux 단위 시험으로 닫힘 · 오디오 경로 무관).
