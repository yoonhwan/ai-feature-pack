# tmuxc — tmux session launcher for Claude, Codex, and OMX

`tmuxc`는 프로젝트 폴더나 git worktree에 Claude Code, Codex CLI, OMX 세션을 빠르게 열고, 세션 간 메시지·상태 확인·verified send/capture를 표준화하는 운영용 CLI입니다.

BYZ식 운영에서는 다음 3개를 한 세트로 둡니다.

| 도구 | 역할 |
| --- | --- |
| `baton` | worktree, handoff, archive, memory |
| `cairn` | milestone/task schedule ledger, session lineage |
| `tmuxc` | live tmux agent session launcher/control |

## 설치 결과

- CLI: `~/.tmuxc/current/core/bin/tmuxc`
- PATH 링크: `~/.local/bin/tmuxc`
- Claude Code skill: `~/.claude/skills/tmuxc`

## 주요 명령

```bash
tmuxc open <path> --name NAME --agent claude|codex|omx --role worker|orchestrator|designer
tmuxc wt <worktree-path> --name NAME --prompt "NEXT.md 읽고 시작"
tmuxc list
tmuxc ask <name> [lines]
tmuxc send <name> "message"
tmuxc msg <name> "message"
tmuxc kill <name>
tmuxc clean
```

## BYZ 권장 패턴

```bash
# 1) baton handoff가 있는 worktree에서 세션을 연다.
tmuxc open /path/to/project/.worktrees/my-task   --name MY_TASK_ORCH   --agent codex   --role orchestrator   --prompt "AGENTS.md, .baton/handoff/CURRENT.md, .baton/handoff/NEXT.md 읽고 시작"

# 2) cairn task/session ref를 남긴다. 필요 시 프로젝트에서 실행.
cairn link t7 --session-ref MY_TASK_ORCH --execution-ref "tmuxc:MY_TASK_ORCH"

# 3) 진행 중 상태는 tmuxc ask/list로 확인한다.
tmuxc list
tmuxc ask MY_TASK_ORCH 80
```

## 설치

에이전트에게 다음을 요청하세요.

```text
feature-pack/tmuxc/INSTALL.md 읽고 설치해줘
```

또는 수동으로 실행합니다.

```bash
bash feature-pack/tmuxc/install.sh
tmuxc --help
```

Codex 기반 설치 검증:

```bash
tmuxc open "$PWD" --name TMUXC_SMOKE --agent codex --role worker --dry-run
```

Claude Code 연결 확인:

```bash
test -e "$HOME/.claude/skills/tmuxc/SKILL.md"
test -e "$HOME/.claude/skills/tmuxc/COMM-GUIDE.md"
```

## 제거

```bash
bash feature-pack/tmuxc/uninstall.sh
```
