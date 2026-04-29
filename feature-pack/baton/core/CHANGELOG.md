# baton Changelog

이 파일은 사용자가 직접 편집 가능합니다. 글로벌 설치본(`~/.baton/versions/{ver}/`)의 변경 이력을 추적하세요.

## [1.2.2] — 2026-04-30 (Codex/OMX runtime-aware baton)

### Improved
- **Runtime-aware handoff defaults** — `BATON_AGENT` 미설정 시 Codex/OMX 환경(`CODEX_THREAD_ID`, `CODEX_CI`, `CODEX_MANAGED_BY_NPM`, `OMX_SESSION_ID`)을 감지해 handoff agent를 `codex`로 기록.
- **OMX/Codex 하네스 안내** — baton 안내·JOURNAL 템플릿·SPEC·README·Codex 어댑터가 Claude/OMC 전용 슬래시 대신 `$autopilot`, `$team`, `$ralplan`, `$ultraqa`, `$code-review` 등 OMX 스킬을 런타임별로 안내.
- **`preferred_execution: runtime:auto`** — 프로젝트 기본 실행 하네스를 특정 벤더 슬래시가 아닌 현재 런타임 선택으로 전환.
- **Codex adapter install** — 설치 시 `~/.codex/baton/INSTRUCTIONS.md`에 Codex/OMX 어댑터 가이드 복사.

---

## [1.2.1] — 2026-04-28 (모바일 SSH 자동 안내)

### Added
- **모바일 SSH 안내 자동 표시** — Tailscale 설치 시 `wt-create` / `plan` / `save` / `resume` / `finish` 출력에 한 줄 자동:
  ```
  📱 모바일 SSH: ssh yoonhwan@100.x.x.x  → tmux a -t baton-byz-agents-X
  ```
  Tailscale 미설치 시 silent skip.
- `lib/tmux.sh` `baton_tmux_mobile_ssh_hint` 함수 — `tailscale ip -4` + `$USER` 동적 조합.
- README / standard_workflow.md에 모바일 attach 시나리오 + macOS 사전 준비 + 추천 앱 (Termius/Blink/JuiceSSH).

### Why
멀티 에이전트 + tmux 영속의 진짜 가치는 **노트북이 작업하는 동안 어디서든 attach**. Tailscale은 그 인프라. baton이 안내까지 자동화해서 사용자가 모바일 SSH 명령 따로 외울 필요 없음.

---

## [1.2.0] — 2026-04-27 (tmux 표준화 + archive=baton 통찰)

### Changed (Breaking)
- **tmux는 default 표준** — `BATON_TMUX_ENABLE=true` 환경변수 불필요. tmux 설치되어 있으면 자동 사용.
  - opt-out: `export BATON_TMUX_DISABLE=true` (강제 비활성)
  - legacy: `BATON_TMUX_ENABLE=false` 도 같은 효과 (호환 유지)
- 모든 가이드(README/SPEC/standard_workflow)에 tmux를 default 표준으로 반영.

### Added
- **archive = baton 통찰** — README/standard_workflow hero에 명시:
  > 워크트리는 baton 만드는 공장. archive는 인계 가능한 baton 그 자체.
  > 다음 사람·에이전트에게 "이 archive id 받아서 이어 가" 한 줄로 모든 결정·이력·코드 변경을 통째로 인계.
- `/baton:archive search` / `extract` = **바통 받기**의 의미적 정의 강조.
- 엑스클로우 크루 워크플로우: archive git-tracked + push → 다른 크루 `git pull` + `archive search`로 즉시 인계.

### Improved
- `baton status` tmux 메시지: "BATON_TMUX_ENABLE=true" → "default — v1.2 표준"

---

## [1.1.0] — 2026-04-27 (tmux 통합 + Hermes adapter 실 구현)

### Added
- **tmux 통합** — `BATON_TMUX_ENABLE=true` 환경변수로 활성화. `wt-create` 시 자동 tmux 세션(`baton-{project}-{phase-id}`) 생성 + cd + ready 배너 (status + NEXT.md 자동 출력). 세션 끊김 방지 + 프로세스 영속.
- **status에 tmux 세션 정보** — 활성 워크트리마다 `(tmux: session-name — attach: tmux a -t ...)` 표시.
- **wt-clean 시 tmux 세션 묻기** — y/N prompt. 사용자가 보존 결정 가능.
- **Hermes 어댑터 실 Python script** — `adapters/hermes/baton.py`. `~/.hermes/plugins/baton.py` 로 복사해 사용. `on_session_start` / `on_session_end` / `journal` / `harness` / `keyword` / `set-status` CLI 서브커맨드 + 키워드 트리거.
- **Hermes 설치 가이드** — `adapters/hermes/INSTALL.md`. shell_hooks 연동 + 수동 사용법 + tmux 시나리오 + 트러블슈팅.
- **Codex CLI 어댑터 가이드** — `adapters/codex/INSTRUCTIONS.md`. sandbox 우회 패턴 + NEXT.md 주입 + 멀티 에이전트 시나리오.
- **Gemini CLI 어댑터 가이드** — `adapters/gemini/INSTRUCTIONS.md`. `--approval-mode yolo` 패턴 + tmux 통합 + settings.json 연동.
- **OpenCode 어댑터 가이드** — `adapters/opencode/INSTRUCTIONS.md`. slash commands + AGENTS.md 통합 + 멀티 에이전트 시나리오.
- **lib/tmux.sh** — `baton_tmux_enabled` / `baton_tmux_session_name` / `baton_tmux_create_session` / `baton_tmux_kill_session` / `baton_tmux_kill_by_phase` / `baton_tmux_status_suffix` / `baton_tmux_list_sessions` 함수.

### Improved
- **멀티 에이전트 시나리오 강화** — 워크트리 N개를 각기 다른 에이전트(claude-code/codex/gemini/opencode/hermes)가 동시 작업 → archive 한 곳에 누적 → `git push` 로 크루 간 자동 sync.

---

## [1.0.1] — 2026-04-27 (사용성 테스트 픽스)

### Fixed
- **archive_dir linked worktree 미지원** — `git rev-parse --show-superproject-working-tree` 는 submodule 전용. linked worktree에서 `git worktree list --porcelain` 첫 entry로 main worktree 결정. (lib/archive.sh)
- **post-tool-use.sh `tac` macOS 미존재** — single-pass awk로 교체 (tac/tail -r 의존 제거). (claude-code/hooks/post-tool-use.sh)
- **`wt-clean <name>` 인자 정규화 부재** — 절대경로 아니면 `$root/.worktrees/<name>/` 자동 매핑. (lib/core.sh `baton_cmd_wt_clean`)
- **wt-clean cwd 무효화** — 진입 시 `cd "$root"` 강제 + `$PWD == $wt_path*` 안전장치. (lib/core.sh)
- **wt-clean exit code=1 silent functional success** — `if/fi` 블록 + 명시적 `return 0`. (lib/archive.sh `baton_archive_prune`)
- **archive extract `$TMPDIR` 사용으로 macOS 도움말 불일치** — 고정 `/tmp/baton-extracted/<id>/` 경로. SSOT 일관성. (lib/archive.sh `baton_archive_extract`/`baton_archive_close`)
- **`baton_project_root` linked worktree 미지원** — 워크트리 안에서 호출 시 워크트리 자체를 root로 반환 → `cd .worktrees/X && /baton:wt-clean` 후 cwd 무효 → `archive_prune .last_prune` write 실패. fix: `git worktree list --porcelain` 첫 entry = main worktree 우선 반환. (lib/core.sh `baton_project_root`)

### Improved
- **`/baton:plan` UX** — phase.json 충돌 시 거부 → "그대로 사용" 통과. PLAN.md 상태별 분기(stub/실제) 안내. (lib/core.sh `baton_cmd_plan`)
- **B+C 호출 패턴** — `/baton:plan` 출력에 호출 명령 + PLAN.md 저장 지시 통째로 포함. 사용자/Claude가 그대로 복붙해서 외부 하네스 호출 → PLAN.md 자동 누적. (lib/harnesses.sh `baton_plan_recommend`)
- **최신 슬래시만 추천** — deprecated(`superpowers:write-plan`/`execute-plan`/`brainstorm`) 사용 금지 경고. README/SKILL/JOURNAL.md.template 일관 적용.
- **HARNESS 필드 룰 명시** — JOURNAL.md.template 헤더에 외부 하네스만 기록(baton 자체 명령/Bash/Read 제외) 룰 명시.

### Removed
- **harnesses/ yaml 카탈로그 8 파일** — 표준 instruction 동적 주입(lib/harnesses.sh 상수 + 이름 매칭 분류)으로 대체. da 권고 SIMPLIFY 적용. (모든 yaml 7 + _index.md)

### Verified
- BYZ 자율 풀 사이클 테스트 통과 (test-baton-feature → test2 → test3, archive 3건 누적, archive search/extract/close 정상)
- `bash test/verify.sh`: 43 passed / 0 failed
- 사용자 보호 워크트리(lecture-quality / loom-phase7 / migration-phase-b / v5-pr-a3-*) 손대지 않음, main commit 0건

---

## [1.0.0] — 2026-04-27

### Added
- 핵심 라이프사이클 8 명령: `plan`, `wt-create`, `save`, `resume`, `finish`, `wt-clean`, `status`, `help`
- Archive 6 명령: `archive [list|search|show|extract|close|prune]`
- 메타 3 명령: `install`, `doctor`, `upgrade`
- 4-템플릿 메모리: `PLAN.md` / `JOURNAL.md` / `CURRENT.md` / `NEXT.md`
- 8 플로우 케이스: A(plan-first), B(wt-first), C(wt-finish), D(branch-pivot), E(abandoned), F(hotfix-mode), G(orphan-recovery), H(handoff-rollback)
- 7 하네스 어댑터: superpowers(brainstorm/writing-plans/executing-plans), OMC(deep-interview/autopilot/team), claude-mem
- 5 Claude Code 훅: SessionStart / UserPromptSubmit / PostToolUse / PreCompact / SessionEnd
- 옵션 B (main/root strict): main 브랜치에서 baton 거부, hotfix-mode 별도
- Archive 위치: 프로젝트 내부 `.baton/archive/` + git-tracked (자동 sync)
- multi-version 글로벌 설치: `~/.baton/versions/{ver}/`
- Interop SPEC v1 (4룰): handoff 포맷 / phase.json 스키마 / 워크트리 위치 / 포트 룰
