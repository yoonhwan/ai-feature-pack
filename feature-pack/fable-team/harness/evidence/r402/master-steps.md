# r402 — master 단계 (나노 산출 · 실행 0)

1. 팩 PR: 브랜치 `nano/r402-old-team-path-new-file-deny` push → PR (나노 push 금지).
2. 착지 뒤 harness-live ff → `bash <팩>/feature-pack/fable-team/harness/install.sh --apply --project <BYZ 루트>`
   → 출력 `HOOKS copied=1 same=1`(freeze 가드는 홈과 이미 같음) · `cmp <키트>/hooks/old-team-path-new-file-gate.sh ~/.claude/hooks/old-team-path-new-file-gate.sh` = 0.
   manifest 1.1.7 — 다른 카드가 먼저 1.1.7 을 착지하면 번호를 다음으로(CHANGES 머리·manifest 둘 다).
3. 훅 등록 1줄 (PreToolUse 배열에 1항):
   `{"matcher": "Write|Edit|Bash", "hooks": [{"type": "command", "command": "$HOME/.claude/hooks/old-team-path-new-file-gate.sh"}]}`
   ★실측: 이웃 `harness-freeze-gate.sh`·`tracked-bin-call-gate.sh` 는 BYZ `.claude/settings.json` 이 아니라 홈 `~/.claude/settings.json` PreToolUse(Bash)에 등록돼 있다 — 카드는 «BYZ settings» 라 적었으니 어느 쪽에 걸지 master 가 정한다.★
4. 실사건: 등록 뒤 꼴2 리포 워크트리에서 Write `design/v65/<새 이름>.md` 시도 → deny 원문 1건(나노 프로브 원문은 아래).

## 관측 (실행→나온 것)
- 이 워크트리(BYZ `harness-r402-…`, TEAMS.md 꼴2)에 훅 직접 호출: Write `design/v65/zz-r402-probe.md` → deny «바른 경로: design/teams/v65/zz-r402-probe.md» · Bash `echo x > design/planner/zz-probe.md` → deny «design/teams/planner/zz-probe.md».
- BYZ 루트 체크아웃(main): `design/TEAMS.md` 없음 → 허용 + WARN 1줄(fail-open).
- `.worktrees/harness-ops`(카드 워크트리): TEAMS.md 가 아직 꼴1(`design/v65/`·`design/planner/`) → 그 워크트리 안 옛 경로 쓰기는 통과(명단은 «그 루트» 의 것 · ft_team_in 과 같은 원칙). harness-ops 가 main 의 꼴2 명단을 받으면 그때부터 막힌다.
