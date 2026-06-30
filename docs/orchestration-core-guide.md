# 오케스트레이션 코어 운용 가이드 — cairn · tmuxc · baton

> **대상**: 이 문서를 읽는 AI 에이전트(Hermes / Aina).
> **목적**: 한 에이전트가 세 모듈을 엮어 **프로젝트 관리 + 세션 모니터링 + 무중단 인계**를 수행하기 위한 단일 컨텍스트.
> **이식**: 이 문서는 `ai-feature-pack` repo의 SSOT다. 각 머신(개인 = Hermes, BYZ 회사 = Aina)은 `git pull`로 동일 사본을 받아 **독립 운영**한다. 원장은 머신 간 공유되지 않는다.

---

## 0. TL;DR

세 모듈은 **하나의 작업을 세 측면에서** 다룬다.

| 측면 | 모듈 | 한 줄 |
|------|------|-------|
| **계획** | `cairn` | 무엇을 할지·어디까지 됐는지·어디로 복귀할지 (SSOT 원장 `.cairn/plan.yaml`) |
| **실행** | `tmuxc` | 지금 어느 세션이 살아 무엇을 하는 중인지 (live tmux 세션 런처/제어) |
| **기억** | `baton` | 세션이 끊겨도 다음이 그대로 이어받게 (핸드오프 그릇 `.baton/handoff/`) |

핵심: **세 모듈은 `session_ref` / `execution_ref`로 한 원장에서 만난다**(§2). 그래서 "프로젝트 관리"와 "세션 모니터링"은 따로 짠 두 기능이 아니라 cairn 한 축의 두 면이다.

---

## 1. 3모듈 분업 + 책임 경계

```
        cairn (계획·SSOT)
       /  무엇을/언제/복귀점  \
      / session_ref     execution_ref \
 tmuxc (실행)            baton (기억)
 live 세션 관제          워크트리·핸드오프·아카이브
```

- **cairn = 계획 앵커 + 복구 그래프.** 자체 쓰기는 `.cairn/plan.yaml`(계획) + 복구 메타뿐. tmuxc·baton·git을 **read-only join**한다. 단일 직렬 writer(flock + atomic + validate + git commit) — 매 명령이 곧 커밋.
- **tmuxc = 실행 표면.** 프로젝트/워크트리에 에이전트 세션을 열고(`open`/`wt`), 세션 간 메시지·상태를 표준화(`ask`/`send`/`msg`). cairn·baton의 상태를 **바꾸지 않는다** — 살아있는 세션만 소유.
- **baton = 기억·인계 표준.** 워크트리 생성/정리, 핸드오프 dump/resume, 아카이브를 `.baton/`에 누적. 그릇 포맷은 `core/SPEC.md` 4룰로 표준화 → 어느 도구(Claude/Codex/Gemini/Hermes)든 그릇만 읽으면 이어받음.

**경계 한 줄**: cairn은 *논리*(계획·계보)를, baton은 *물리*(워크트리·파일 기억)를, tmuxc는 *라이브*(지금 도는 세션)를 소유한다. 셋은 서로의 영역을 직접 쓰지 않고 **참조(ref)로 연결**한다.

---

## 2. 통합 축 — `session_ref` / `execution_ref` 조인 (★핵심)

cairn 노드는 분기(`spawn`) 시 두 ref를 갖는다:

```bash
cairn spawn "토큰정책 구현" --from t1 --return-to t1 \
      --worktree .worktrees/token   `# → execution_ref (baton 워크트리/git 브랜치)` \
      --session  sess-token          `# → session_ref  (tmuxc 라이브 세션)`
cairn link t4 --execution-ref feat/token --session-ref sess-token
```

이 두 ref가 세 모듈을 한 줄에 꿴다:

```
cairn 노드 t4 ──session_ref: sess-token──▶ tmuxc 세션 (tmuxc ask sess-token → 라이브 진행)
            └──execution_ref: feat/token─▶ baton 워크트리 (.worktrees/token, .baton/handoff)
```

**그래서 "세션 모니터링"이 cairn 위에서 공짜로 나온다:**
`cairn map`이 "어느 노드가 무슨 작업"을 알고, 그 노드의 `session_ref`로 `tmuxc ask`하면 "그 세션이 지금 뭘 하는 중"이 붙는다. 둘을 조인 = **프로젝트 노드별 실시간 진행 관제**.

복귀도 한 줄: `cairn return --to t1`은 재앵커하면서 **baton resume에 연결**(NEXT.md 안내)한다 — 계획 복귀와 기억 복원이 한 동작.

---

## 3. 파일 트리 인덱스 (핵심 큐레이션)

> 전역 1회 설치형. 설치본은 `~/.cairn/` · `~/.baton/` · `~/.tmuxc/`. 실행 cwd 프로젝트의 `.cairn/`·`.baton/` 원장을 대상으로 동작.

```
ai-feature-pack/feature-pack/
├── cairn/                         # 계획·복구 원장
│   ├── core/cairn.py              # ★단일 파일 CLI — 모든 명령(§4)
│   ├── claude-code/
│   │   ├── skills/cairn/SKILL.md  # ★발동 트리거 + 명령 매핑 (에이전트 진입점)
│   │   ├── commands/cairn/*.md    # 명령별 상세 문서
│   │   └── hooks/cairn-auto-progress  # BTS evidence pass → 완료 후보 자동 캡처
│   ├── docs/cairn-design.md       # 설계 철학·데이터모델 (왜 이렇게 동작하나)
│   └── README.md / INSTALL.md
│   └── ◇ 원장: .cairn/plan.yaml(SSOT) · .cairn/views/plan.md+html(간트) · /tmp/cairn/<hash>/recovery.md(복구맵)
│
├── tmuxc/                         # 실행·라이브 세션
│   ├── core/bin/tmuxc            # ★CLI (전역: ~/.local/bin/tmuxc)
│   ├── claude-code/skills/tmuxc/SKILL.md
│   └── README.md / INSTALL.md
│
└── baton/                        # 기억·인계
    ├── core/bin/baton           # ★CLI (전역: ~/.baton/current/bin/baton)
    ├── core/SPEC.md             # ★핸드오프 그릇 포맷 4룰 (표준)
    ├── flows/*.md               # 워크플로우: plan-first, wt-first, wt-finish,
    │                            #   orphan-recovery, hotfix-mode, branch-pivot, ...
    ├── claude-code/skills/baton/SKILL.md
    ├── docs/MULTI_AGENT_SCENARIOS.md
    └── ◇ 그릇: .baton/handoff/NEXT.md · .baton/archive/*.tar.gz · phase.json
```

**에이전트가 먼저 읽을 3파일**: 각 모듈 `SKILL.md`(트리거+명령). 그 다음 필요 시 cairn `core/cairn.py`, baton `core/SPEC.md`.

---

## 4. 명령 레퍼런스 (자연어 트리거 → CLI)

### cairn — 계획·복구
| 분류 | 명령 |
|------|------|
| 부트스트랩 | `cairn init` · `new-project <p>` · `add-milestone <p> <name>` · `add-task <p> <ms> <name> [--days N]` |
| 조회·간트 | `cairn status` · `show <p>` · `overdue [--today]` · `render`(간트 HTML 기본 생성+표시, `--no-open`으로 억제) |
| 변경 | `cairn set-status` · `set-date` · `set-priority` · `depends <p> <t> --on <t>` |
| **복구 fan-out/in** | `cairn spawn <name> --from <parent> [--return-to] [--worktree] [--session]` · `complete <task> [--force]` · `return --to <node>` · `map [--focus] [--show-merged] [--html]` · `link <node> --execution-ref/--session-ref/--merge-back-to` · `reconcile` |
| 백로그 | `cairn add-todo` · `todos` · `link-todo <td> --by <node>` |
| 무결성 | `cairn validate` · `self-test` · `revert` |

### tmuxc — 실행·세션
```bash
tmuxc open <path> --name NAME --agent claude|codex|omx --role worker|orchestrator|designer
tmuxc wt <worktree-path> --name NAME --prompt "NEXT.md 읽고 시작"   # 워크트리에 세션
tmuxc list                       # 살아있는 세션 일람
tmuxc ask <name> [lines]         # 세션 최근 화면 캡처(read) — ★모니터링
tmuxc send <name> "msg" / msg <name> "msg"   # verified send
tmuxc kill <name> / clean        # 종료 / 정리
```

### baton — 기억·인계 (트리거 키워드: "이어서/진행/go/continue/next" → resume)
```bash
baton plan <id> [title]          # phase.json + 4템플릿 생성
baton wt-create <name>           # 워크트리 생성 + 포트 할당
baton save                       # 핸드오프 dump (status=paused)
baton resume                     # .baton/handoff/NEXT.md 출력 (세션 재개)
baton finish                     # 페이즈 완료 (status=done)
baton wt-clean [path] [--merged] # archive 보관 후 워크트리 삭제
baton status                     # 활성 phase + 워크트리 목록
baton archive list|search <q>|show <id>|extract <id>|prune
baton digest <topic>             # (에이전트 전용) 다중 세션 컨텍스트 → SSOT 1파일 압축
```

---

## 5. 운용 시나리오 (자연어 → 3모듈 흐름)

### ① 프로젝트 진행 조회 — "webapp 어디까지 됐어?"
```bash
cairn status                 # 전 프로젝트 진행률
cairn show webapp            # 마일스톤·태스크 트리
cairn overdue --today        # 오늘 기준 지연
cairn render                 # 전사 간트 → plan.html (브라우저 표시)
```

### ② 세션 관제 — "지금 뭐 돌고 있어?" (★통합 축 활용)
```bash
tmuxc list                                   # 살아있는 세션
# cairn 노드 ↔ session_ref 조인:
cairn map --show-merged                       # 노드별 session_ref/execution_ref가 박힌 복구맵
tmuxc ask <session_ref> 40                     # 해당 노드 세션의 라이브 진행 화면
# → "노드 t4(토큰정책)가 sess-token 세션에서 진행 중, 최근 로그 …" 식으로 합성 보고
```

### ③ 작업 이어받기 — "그거 이어서" (무중단 인계)
```bash
baton resume                                  # .baton/handoff/NEXT.md 출력(다음 할 일)
tmuxc wt .worktrees/token --name sess-token --prompt "NEXT.md 읽고 시작"
cairn show webapp                             # 계보(spawned_from/return_to) 재확인
```

### ④ fan-out → 수렴 복구 (분기 작업 마무리)
```bash
cairn spawn "토큰정책 구현" --from t1 --return-to t1 \
      --worktree .worktrees/token --session sess-token
baton wt-create token                         # (물리 워크트리 + 포트)
cairn link t4 --execution-ref feat/token --session-ref sess-token
# … 작업 …
cairn complete t4                             # return_to 보유 → --force 불요
cairn link t4 --merge-back-to t1
baton wt-clean .worktrees/token --merged      # archive 보관 후 워크트리 삭제
cairn return --to t1                          # 재앵커 + baton resume 연결
```

---

## 6. 머신 독립 + 슬랙 운용 맥락

- **두 에이전트, 두 머신, 완전 독립**: Hermes(개인 머신) / Aina(BYZ 회사 머신)는 각자 로컬 `.cairn`·`.baton`·tmuxc 세션을 본다. **원장은 서로 보이지 않으며 섞이지 않는다.** 회사 일은 Aina, 개인 일은 Hermes가 각자 자기 머신을 관장.
- **슬랙 = 공통 허브**: `cliproxyapi`가 제공하는 Slack 게이트웨이 위에서 두 에이전트가 같은 채널에 붙는다. 멘션/채널로 "어느 머신을 향하는 명령인지" 라우팅한다.
- **자연어 → 명령**: 슬랙 메시지를 받은 각 에이전트는 §4 트리거 표로 자연어를 3모듈 명령에 매핑하고, §5 시나리오 흐름으로 실행한 뒤 결과를 채널에 보고한다.
- **읽기와 쓰기 분리**: 조회·모니터링(`status`/`map`/`tmuxc ask`/`baton status`)은 자유롭게, 상태 변경(`complete`/`spawn`/`wt-clean`)은 신중히 — 특히 `wt-clean`·`kill` 등 비가역 동작은 사람 확인 후.

---

*SSOT: `ai-feature-pack/docs/orchestration-core-guide.md` · 각 모듈 상세는 해당 `SKILL.md` / `README.md` 참조.*
