# baton Interop Contract — SPEC v1

> 다른 에이전트(Claude Code / Codex / Gemini / OpenCode / OpenClaw / Hermes / nanoclaw / 신규)가 baton과 호환하려면 이 4룰만 따르면 됩니다. 그러면 어디서 시작한 phase든 무중단 인계 가능합니다.

**Spec version**: 1
**Compatible baton versions**: `>=1.0.0 <2.0.0`

---

## Rule 1 — 4-template 핸드오프 파일 포맷

위치: `{worktree}/.baton/handoff/`. 인코딩: UTF-8 (BOM 없음).

### CURRENT.md (frontmatter + 본문)
```markdown
---
session_id: <YYYY-MM-DD_HHMM>
phase: <phase-id>
branch: <git-branch-name>
worktree: <relative-path>
agent: <agent-id>          # claude-code | codex | gemini | opencode | openclaw | hermes | <other>
status: <active|paused|done|abandoned>
started_at: <ISO8601>
last_updated: <ISO8601>
last_harness: <harness-name|null>   # 가장 최근 사용한 외부 하네스
---

## ⚠️ 블로커
<자유 텍스트 또는 "없음">

## 📌 핵심 결정
- <항목>

## 🔗 핵심 파일
- <path:line>
```

### PLAN.md (외부 하네스 결과 누적, append-only)
```markdown
# Plan — <phase-id>

## 2026-04-27 14:30 — Plan v1 (by superpowers:writing-plans)
<plan 내용>

## 2026-04-27 16:00 — Plan v2 (revised by superpowers:brainstorm)
<수정 내용>
```

### JOURNAL.md (시간순 단일 메모리, append-only)
INTENTS + HISTORY + TODO 섹션을 한 파일에서 시간순 관리.
```markdown
# Journal — <phase-id>

## 2026-04-27 14:30 — Turn 1
**INTENT**: 사용자 원문 입력
**HARNESS**: 사용한 외부 하네스 (있으면)
**ACTIONS**: 한 일 요약
**TODO**: 추가/완료된 할 일

## 2026-04-27 14:42 — Turn 2
...
```

### NEXT.md (다음 세션 1페이지, 자유 형식)
- 길이 ≤ 1KB
- 다음 세션 첫 입력 자연어 지시

---

## Rule 2 — phase.json 스키마

위치: `{worktree}/.baton/phase.json`. **commit O** (팀 합의 산물).

```json
{
  "schema_version": "1",
  "phase_id": "string (slug)",
  "title": "string",
  "branch": "string",
  "worktree": "string (relative)",
  "ports": { "<service>": <integer> },
  "started_at": "ISO8601",
  "target_pr": "string|null",
  "sessions": [
    {
      "id": "string",
      "agent": "string",
      "duration_min": "integer",
      "status": "active|paused|done|abandoned",
      "harnesses_used": ["string"]
    }
  ],
  "completion_criteria": ["string"],
  "next_phases": ["string"]
}
```

**필수**: `schema_version`, `phase_id`, `branch`, `worktree`, `started_at`, `sessions`.

---

## Rule 3 — 워크트리 위치 + 옵션 B (main/root strict)

```
{project}/.worktrees/{branch-name-flat}/
```

**옵션 B 강제 룰**:
- main / master 브랜치 root에서 `baton plan` / `baton wt-create` 외 명령 거부
- 단, `baton hotfix-mode` 는 main에서도 작동 (lite mode)
- `baton plan` 호출 시 phase는 워크트리 내부에만 생성. root에 phase.json 잔존 금지.

워크트리 내부 표준 파일:
```
.baton/
├── config.json     # commit O (프로젝트 설정)
├── version.lock    # commit O
├── phase.json      # commit O
├── handoff/        # gitignore (개인 상태)
│   ├── PLAN.md
│   ├── JOURNAL.md
│   ├── CURRENT.md
│   └── NEXT.md
├── archive/        # commit O (자동 sync)
│   ├── INDEX.jsonl
│   └── *.tar.gz
└── session.lock    # gitignore
```

심볼릭 링크 (`config.json.shared_links`): `.env`, `.venv`, `.claude`, `.omc` 등.

---

## Rule 4 — 포트 할당

```
worktree_port = base_port + (offset × index)
```

- `base_port`: `config.json.base_ports.<service>`
- `offset`: `config.json.worktree_port_offset` (기본 10)
- `index`: `.worktree-info.json.index` (max(existing) + 1로 deterministic 할당)

`config.json` 예:
```json
{
  "schema_version": "1",
  "project_name": "byz-agents",
  "base_ports": { "gateway": 8080, "web": 3001, "mobile": 3002 },
  "worktree_port_offset": 10,
  "shared_links": [".env", ".venv", ".claude", ".omc"],
  "scripts_dir": ["scripts/server", "scripts/client"],
  "verify_command": "make test && ruff check",
  "archive": {
    "retention_days": 30,
    "auto_prune": {
      "on_wt_clean": true,
      "lazy_check_interval_days": 7
    }
  },
  "harnesses": {
    "preferred_plan": "superpowers:writing-plans",
    "preferred_execution": "runtime:auto"
  }
}
```

### Runtime-aware execution harness

`preferred_execution: "runtime:auto"` means baton keeps the project default neutral and lets the active agent runtime choose its native execution surface:

- Codex + OMX: `$autopilot`, `$ralph`, `$team`, `$ultraqa`, `$code-review`, or `codex exec`
- Claude + OMC: `/oh-my-claudecode:autopilot`, `/oh-my-claudecode:team`, `/oh-my-claudecode:plan`
- Other agents: their adapter-specific execution command

When creating a handoff, baton records `BATON_AGENT` if it is set. If unset, it detects Codex from `CODEX_THREAD_ID`, `CODEX_CI`, `CODEX_MANAGED_BY_NPM`, or `OMX_SESSION_ID`; otherwise it falls back to `claude-code` for backwards compatibility.


---

## 어댑터 호환 체크리스트

새 에이전트 어댑터 추가 시:

- [ ] 17개 슬래시 명령 인식 (또는 동등 매핑)
- [ ] 키워드 트리거: "이어서/진행/go/continue/next" → `resume`
- [ ] **PostToolUse 동등 훅** (필수 — 하네스 사용 추출 + JOURNAL.md 자동 append)
- [ ] SessionStart 동등 훅 (paused 알림 + 환경 검증 + lazy prune)
- [ ] 사용자 입력 직전 훅 (UserPromptSubmit 등) — INTENT 캡처
- [ ] CURRENT.md `agent` 필드를 그 에이전트 ID로 기록
- [ ] 옵션 B 가드: main/master 브랜치에서 plan/wt-create 외 거부
- [ ] verification 검증 (PostToolUse가 하네스 결과 파일 검사 — `min_lines`, `required_sections`)
- [ ] 모든 슬래시 명령은 `~/.baton/versions/{ver}/lib/*.sh` 함수로 종착

---

## 버저닝 룰

| 변경 종류 | 버전 증가 | 영향 |
|-----------|-----------|------|
| 신규 명령 | minor | 호환 유지 |
| 옵셔널 인자 | patch | 호환 유지 |
| 옵셔널 필드 | minor | 호환 유지 |
| **필수 필드 변경/제거** | major | SPEC v2 |
| **Rule 1~4 의미 변경** | major | SPEC v2 |

`{worktree}/.baton/version.lock`에 호환 범위:
```json
{
  "baton_version": "1.0.0",
  "compat_range": ">=1.0.0 <2.0.0",
  "spec_version": "1",
  "locked_at": "ISO8601"
}
```

---

## 멀티 버전 글로벌 설치

```
~/.baton/
├── versions/
│   ├── 1.0.0/        ← 활성 워크트리들이 호환
│   └── 1.1.0/        ← 신규 설치 (마이그레이션 안전망)
├── current → versions/1.0.0/
└── archives -> (deprecated, 프로젝트 내부 .baton/archive/로 이전)
```

`baton upgrade`는 새 버전을 versions/에 추가하고 current 심링 변경. 이전 버전은 보관(7일 후 자동 삭제 또는 수동).

---

## 옵션 B (main/root strict) — 가드 정책

### 차단되는 동작 (main/master 브랜치 root에서)
- `baton plan` (phase는 워크트리에만)
- `baton wt-create` 후 cd 안 한 상태에서 다른 명령
- `baton save`, `baton resume`, `baton finish` (워크트리 전용)

### 허용되는 동작 (main/master 브랜치 root에서)
- `baton wt-create <name>` (워크트리 생성만)
- `baton hotfix-mode` (lite, baton 메모리 비활성)
- `baton archive list/search/show/extract` (조회)
- `baton status` (전역 phase 목록 표시 — 활성 워크트리 모음)
- `baton doctor`, `baton upgrade`

### hotfix-mode 동작
- main에서 직접 작업 허용
- baton의 phase/handoff 비활성
- 종료 시 archive에 `tag: hotfix` 만 남김 (메모리 dump 없음)
- `/baton:hotfix-mode finish` 로 명시적 종료
