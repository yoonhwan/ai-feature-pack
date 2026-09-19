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
tmuxc save [--keep N]                 # 종료 전 전역 세션 스냅샷 ([1m]/effort/session_id 보존)
tmuxc restore [--from latest] [--go]  # 재부팅 후 복원 (스냅샷 우선, --scan 으로 로그 스캔 강제)
tmuxc fork <path> --name NEW (--from LIVE_SESSION | --source ID --agent claude|codex|opencode|cmd) [--model ID] [--ctx 1m] [--effort E] [--prompt TEXT]
                                      # 네이티브 conversation fork — 부모 대화 불변, 자식은 새 세션ID로 분기
```

### tmuxc fork (네이티브 분기)

부모 세션을 건드리지 않고 새 conversation id로 분기한다 — 모델/effort만 바꿔 이어가거나
실험 브랜치를 딸 때 쓴다. 4엔진 각각의 네이티브 플래그를 쓴다:

| 엔진 | argv | 비고 |
|---|---|---|
| claude | `--resume <ID> --fork-session` | headroom 래퍼 경유, `[1m]`/effort 승계 |
| codex | `codex fork <ID>` | `-c model=`/`-c model_reasoning_effort=` 통과 |
| opencode | `--session <ID> --fork` | `--model` 그대로 |
| cmd | `--resume <ID> --fork-session` | `--model`/`--effort` |

- `--from <라이브세션>`: 엔진·모델·conversation id를 라이브 프로세스/트랜스크립트에서 해석. **교차엔진 불가**(같은 엔진만).
- `--source <ID> --agent <엔진>`: id 직접 지정. 엔진 저장소 실재 여부를 best-effort 확인.
- `omx`는 네이티브 fork가 없어 대상에서 제외.

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
