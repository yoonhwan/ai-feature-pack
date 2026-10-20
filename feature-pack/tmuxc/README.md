# tmuxc — tmux session launcher for Claude, Codex, OMX, Pi

`tmuxc`는 프로젝트 폴더나 git worktree에 Claude Code, Codex CLI, OMX, OpenCode, Command Code, Pi 세션을 빠르게 열고, 세션 간 메시지·상태 확인·verified send/capture를 표준화하는 운영용 CLI입니다.

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
tmuxc open <path> --name NAME --agent claude|codex|omx|opencode|cmd|pi --role worker|orchestrator|designer
tmuxc wt <worktree-path> --name NAME --prompt "NEXT.md 읽고 시작"
tmuxc list
tmuxc ask <name> [lines]
tmuxc send <name> "message"
tmuxc msg <name> "message"
tmuxc kill <name>
tmuxc clean
tmuxc save [--keep N]                 # 종료 전 전역 세션 스냅샷 ([1m]/effort/session_id 보존)
tmuxc restore [--from latest] [--go]  # 재부팅 후 복원 (스냅샷 우선, --scan 으로 로그 스캔 강제)
tmuxc fork <path> --name NEW (--from LIVE_SESSION | --source ID --agent claude|codex|opencode|cmd|pi) [--model ID] [--ctx 1m] [--effort E] [--prompt TEXT]
                                      # 네이티브 conversation fork — 부모 대화 불변, 자식은 새 세션ID로 분기
```

### tmuxc fork (네이티브 분기)

부모 세션을 건드리지 않고 새 conversation id로 분기한다 — 모델/effort만 바꿔 이어가거나
실험 브랜치를 딸 때 쓴다. 4엔진 각각의 네이티브 플래그를 쓴다:

| 엔진 | argv | 비고 |
|---|---|---|
| claude | `--resume <ID> --fork-session` | headroom 래퍼 경유, `[1m]`/effort 승계 |
| codex | `codex fork <ID>` | `-c model=`/`-c model_reasoning_effort=` 통과 |
| opencode | `--session <ID> --fork` | 모델 = 세션 env `OPENCODE_CONFIG_CONTENT` (아래) |
| cmd | `--resume <ID> --fork-session` | `--model`/`--effort` |
| pi | `--fork <ID> --session-id <NEW>` | `--model`/`--thinking` |

- `--from <라이브세션>`: 엔진·모델·conversation id를 라이브 프로세스/트랜스크립트에서 해석. **교차엔진 불가**(같은 엔진만).
- `--source <ID> --agent <엔진>`: id 직접 지정. 엔진 저장소 실재 여부를 best-effort 확인.
- `omx`는 네이티브 fork가 없어 대상에서 제외.

### pi 좌석 (2026-10-20)

```bash
tmuxc open . --name PI_WORKER --agent pi --role worker --model opengateway/deepseek/deepseek-v4.1-flash-ultrafast
tmuxc open . --name PI_REVIEW --agent pi --role orchestrator --effort high
```

- tmuxc가 `--session-id <uuid>`를 발급하고 세션 env(`TMUXC_PI_SESSION_ID`, `TMUXC_PI_MODEL`, `TMUXC_PI_THINKING`)에 심는다. process.title이 argv를 숨겨도 `probe`/`model`/`save`/`restore`가 exact session으로 복구된다.
- `worker`/`implementer` = `read,bash,edit,write,grep,find,ls`; `orchestrator`/`planner`/`analysis` = read-only.
- `--effort`는 Pi `--thinking`으로 매핑된다.
- `--like <pi-session>`으로 live pi의 model/thinking을 상속할 수 있다.
- Pi 자체 스킬은 `~/.agents/skills/pi-ops` 및 `/skill:pi-ops` 참고.

### Pi + Serena (0.4.3)

```bash
tmuxc open .worktrees/my-task --name PI_IMPL --agent pi --serena --role worker
```

- `--serena`는 **`--agent pi` 전용**. 그 워크트리의 `.pi/mcp.json`에 serena를 **stdio · `--project <그 경로>`**로 적고, pi 명령에 `--approve`(이번 실행만 프로젝트 신뢰 · `trust.json` 저장 0)를 붙인다.
- `--context codex`를 쓴다: pi도 codex처럼 자체 파일·셸 도구를 갖고 있어, serena의 `read_file`·`create_text_file`·`execute_shell_command` 같은 중복 도구를 빼고 심볼 도구만 남기는 context가 맞다.
- 노출은 화이트리스트(`exposure:"hidden"` + `toolExposure`)뿐 — `activate_project`·`find_symbol`·`find_referencing_symbols`·`get_symbols_overview`·`find_implementations`·`onboarding`·`list_memories`·`read_memory`·`write_memory`만 direct. 나머지는 등록되지만 호출 불가.
- 기동 때 활성 프로젝트가 이미 지정되므로 **첫 `find_symbol`에 `activate_project` 선행 호출이 필요 없다**. 온보딩은 `list_memories`에 온보딩 기억이 없으면 `onboarding` 1회.
- 워크트리의 `.pi/`·`.serena/`를 `.git/info/exclude`에 넣는다(커밋 금지 · 좌석 로컬).
- 공유 HTTP serena를 쓰지 않는 이유: serena 1개는 **활성 프로젝트 1개**만 갖는다 — 여러 좌석이 공유하면 서로 `activate`를 밀어낸다. stdio는 pi 세션이 끝날 때 프로세스 그룹째 회수된다.
- `--dry-run`은 **파일을 쓰지 않는다** — `mcp=`(경로)와 `mcp_json=`(쓸 내용)만 출력한다.
- 플래그가 없으면 이전과 동작 차이 0. 다른 에이전트에 `--serena`를 주면 거부한다.

### opencode 좌석 모델 (0.4.1 · r476)

opencode 2.0.x TUI 최상위에는 `--model` 이 없다(`opencode run` 전용 → `Unrecognized flag: --model` 기동 실패).
`open`/`fork --agent opencode --model <ID>` 는 모델을 플래그 대신 **세션 생성 때 env**
`OPENCODE_CONFIG_CONTENT={"model":"<ID>"}` 로 그 tmux 세션에만 심는다(`--dry-run` 의 `env=` 줄).
글로벌 `~/.config/opencode/opencode.json`·워크트리 파일은 건드리지 않는다. 모델 미지정이면 env 0(opencode 기본값).

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
