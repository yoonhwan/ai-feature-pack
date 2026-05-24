# baton Changelog

이 파일은 사용자가 직접 편집 가능합니다. 글로벌 설치본(`~/.baton/versions/{ver}/`)의 변경 이력을 추적하세요.

## [1.2.7] — 2026-05-25 (RESUME_MSG.md 풀 컨텍스트 + resume 통합)

### Changed — RESUME_MSG.md 압축 제거 + resume 통합
- **`baton_resume_msg_build` 단순화** — NEXT.md 전문 + footer로 구성. 500B 캡/마커 추출/단계적 trim 로직 전부 제거. 호출 세션이 작성한 NEXT.md 내용을 그대로 보존.
- **`baton_handoff_resume` RESUME_MSG.md 우선 읽기** — resume 시 RESUME_MSG.md가 있으면 우선 사용 (NEXT.md + worktree/branch/commit footer 포함). 없으면 NEXT.md fallback.

### Fixed
- RESUME_MSG.md가 500B로 압축되어 구체적 컨텍스트(명령어, 파일경로, 실험계획)가 잘리던 문제 해결
- `/baton:resume`가 RESUME_MSG.md를 읽지 않아 새 세션에서 footer 컨텍스트(worktree/branch/commit) 누락되던 문제 해결

## [1.2.6] — 2026-05-24 (NEXT.md 호출 세션 직접 작성)

### Changed — NEXT.md/RESUME_MSG.md 생성 책임 이전
- **NEXT.md는 호출 세션이 직접 작성** — 헤드리스 에이전트는 `.events.jsonl`(intent + harness 이벤트만)만 볼 수 있어 파일경로, 명령어, 실험결과, 성능수치 등 구체적 컨텍스트를 담지 못했음. 풀 컨텍스트를 보유한 호출 세션이 NEXT.md를 직접 작성하도록 변경.
- **save-prompt.md.template에서 NEXT.md/RESUME_MSG.md 태스크 제거** — 헤드리스 에이전트 책임을 JOURNAL.md append + CURRENT.md frontmatter 갱신으로 축소. `SCOPE` 절로 명시적 경계 선언.
- **save.md 2-step 흐름** — Step 1: 세션이 NEXT.md Write → Step 2: `bash save` 실행. `allowed-tools`에 `Write, Read` 추가.
- **post-spawn RESUME_MSG.md 로직 단순화** — LLM 작성 여부 분기 제거, 항상 `baton_resume_msg_build` (NEXT.md 마커에서 자동 추출).

### Fixed
- NEXT.md가 2-3줄 빈약한 요약만 생성되던 문제 해결 (근본 원인: 헤드리스 컨텍스트 부족)
- RESUME_MSG.md에 구체적 컨텍스트(명령어, 파일경로, 실험계획, 성능 수치) 누락 문제 해결

### Unchanged
- `session-end.sh`, `pre-compact.sh`, `baton_cmd_finish`, `baton_cmd_wt_clean` 내부 save 호출 — 기존 bash-only 경로 유지 (NEXT.md가 이미 작성된 상태이므로 정상 동작).
- `baton_resume_msg_build`, `baton_resume_msg_footer_append` 함수 — handoff.sh에 보존 (외부 호출 호환).

## [1.2.5] — 2026-05-22 (RESUME_MSG.md 자동 생성 + /baton:resume 4분류 가드)

### Added — 매 세션 종료 시 카피용 시작 메시지 자동 생성
- **CURRENT.md frontmatter `last_commit` 필드 신규** — resume 가드 mismatch 비교용. `baton_init_handoff` 가 워크트리 생성 시 채우고, `baton_cmd_save` 마지막에 자동 갱신.
- **`.baton/handoff/RESUME_MSG.md` 자동 생성 (≤500B hard cap)** — 다음 세션 첫 입력으로 그대로 복붙할 카피용 메시지. `baton_resume_msg_build` (bash-only) + `baton_resume_msg_footer_append` (LLM 본문 후 footer append) + `baton_resume_msg_print` (박스 출력).
  - **bash-only 경로**: `--skip-spawn` / events=0 / SessionEnd / spawn 실패. 형식 고정 fill-in.
  - **LLM 경로**: `/baton:save` 정상 spawn에서 LLM이 본문만 작성, bash가 footer(`worktree:`/`branch:`/`commit:`) append.
  - **사이즈 cap**: 초과 시 INTENT → 오늘 끝내기 → 즉시 이어서 순으로 trim.
- **save-prompt.md.template Step 7** — RESUME_MSG.md 본문 생성 instruction. 자유 작문 금지, fill-in 템플릿 강제.

### Added — /baton:resume 가드 강화 (4분류)
- **archive extract hard abort** — `$PWD`가 `/tmp/baton-extracted/*` (macOS는 `/private/tmp/...`)면 즉시 거부. `--force`로도 우회 불가. 데이터 손실 위험 차단.
- **워크트리/commit mismatch 4분류**:
  - `match` — 일치 → 그대로 진행
  - `commit_only` — 해시만 다름 (main 머지 등) → INFO + 1초 wait + 자동 진행
  - `worktree_only` / `both` — TTY는 `[y/N]` 확인, non-TTY는 `[baton-resume-mismatch] kind=...` 한 줄 stdout + NEXT.md 출력 (LLM이 사용자 확인)
- **realpath 정규화** — 저장값/현재 양쪽 `pwd -P` + basename 이중 체크. macOS `/tmp` ↔ `/private/tmp` 흡수.
- **legacy 빈 값 silent 백필** — v1.2.4 이하 워크트리에 `last_commit` 없으면 첫 resume 시 자동 채움.
- **`--force` flag** — `match` 외 분류 우회 (archive extract 제외).

### Added — SessionEnd 훅 폴리싱
- status 무관하게 `RESUME_MSG.md` 갱신 (bash-only — Claude는 RESUME_MSG.md를 Read/Edit 안 함, race 안전).
- events_count ≥ 1 시 `commit:` 라인에 인라인 `(stale, events=N)` 마킹.
- 출력 메시지에 `RESUME_MSG.md` 위치 안내.

### Migration
- `/baton:migrate` 가 legacy CURRENT.md에 `last_commit` 자동 백필 추가 (v1.2.4 워크트리 호환).
- 기존 워크트리는 첫 `/baton:resume` 시 silent 자동 백필. 명시적 `/baton:migrate` 권장.

### Adapters
- codex / gemini / opencode `INSTRUCTIONS.md` 에 `/baton:resume` 4분류 가드 + `--force` + `[baton-resume-mismatch]` non-TTY 처리 명시 추가.

---

## [1.2.4] — 2026-05-01 (race-free pipeline 강화 + 마이그레이션)

### Fixed (codex 리뷰 — HIGH 3)
- **H1: spawn 후 rotate race** — spawn 진행 중 새 hook event가 append되어도 그게 함께 processed로 사라지던 문제. **선 rotate snapshot** 패턴으로 해결: save 시작 시 `.events.jsonl` → `.events.snapshot-{ts}_{pid}_{rnd}.jsonl` 로 atomic 회전 후 spawn에 snapshot 경로 입력. 새 hook은 새 `.events.jsonl`에 적재되어 다음 save에서 처리.
- **H2: 동시 save lock 부재** — 두 개의 `/baton:save`가 동시 실행되면 중복 Turn / rotate race. `mkdir .save.lock` atomic lock 추가 (`baton_save_lock_acquire/release`). 최대 30s 대기 (`BATON_SAVE_LOCK_TIMEOUT`), 10분 이상 stale lock 자동 해제. SIGINT/TERM에서도 trap으로 lock 해제.
- **H3: rotate target 충돌** — 같은 초에 두 번 rotate 시 `.events.processed-{ts}.jsonl` 덮어쓰기 가능. **unique suffix** (`{ts}_{pid}_{rnd}`)로 충돌 회피 + `noclobber` 보장 루프.

### Fixed (codex 리뷰 — MEDIUM 4)
- **M4: fallback 실패 정책** — fallback dump가 실패해도 `.events.processed-*` 로 회전하던 문제. 이제 **fallback 성공 → processed**, **fallback 실패 → `.events.failed-*`** 분기. 실패 시 raw events 보존 + 명시 경고. atomic write (mktemp + mv) 적용.
- **M5: BATON_SKIP_HOOKS 한계 문서화** — baton hook만 차단함을 save-prompt 템플릿과 save.md에 명시. 다른 사용자 hook(omc/gas-town 등)이 핸드오프 파일을 mutate하면 race 재발 가능 → spawn 에이전트에게 Edit 실패 시 retry/abort 패턴 지시.
- **M6: 하네스 instruction 정합성** — `core/lib/harnesses.sh`의 `BATON_EXECUTION_INSTRUCTION`이 v1.2.2 시절 "JOURNAL 직접 편집" 지시 유지하던 문제. sidecar 패턴에 맞게 "JOURNAL/CURRENT/NEXT 직접 편집 금지, /baton:save 가 자동 정리"로 갱신.
- **M7: command 문서 sync** — `save.md`, `finish.md`가 v1.2.2 동작 그대로 기술하던 문제. v1.2.4 race-free pipeline + 자동 save 호출 + lock 동작으로 갱신.

### Fixed (codex 리뷰 — LOW 2)
- **L8: hook schema 통일** — `user-prompt-submit.sh`가 `lib/handoff.sh`의 `baton_events_append`를 사용하도록 통합. `post-tool-use.sh`는 tool 메타까지 보존해야 해서 inline jq 유지(주석 명시).
- **L9: rotate 실패 명시** — `mv` 실패 시 stderr에 "rotate 실패" 경고. caller가 명시적 처리 가능.

### Added
- **`/baton:migrate` 명령** — v1.2.2 이하 워크트리를 v1.2.4 sidecar 패턴으로 비파괴 마이그레이션
  - `--dry-run` 모드
  - 특정 워크트리 path 지정 가능
  - `JOURNAL.md.pre-1.2.4.bak` 자동 백업
  - `.baton/version.lock` 갱신 (`migrated_from`, `migrated_at` 기록)
  - 이미 v1.2.4 이상이면 skip
- `lib/handoff.sh`:
  - `baton_events_snapshot_for_save` — save 전 사전 회전
  - `baton_events_processed_finalize` — snapshot → processed/failed 최종 회전
  - `baton_save_lock_acquire/release` — mkdir 기반 atomic lock
- `lib/core.sh`:
  - `baton_cmd_migrate` — 마이그레이션 명령
  - `baton_cmd_save` — race-free pipeline 재구조 (lock → snapshot → spawn → finalize)
- `templates/save-prompt.md.template` — snapshot 입력 명시 + 다른 hook 영향 가능성 경고 + Edit retry 정책

### Migration
- 자동 호환 유지 — 기존 `.baton/handoff/JOURNAL.md` 그대로 사용
- 신규 워크트리: 별도 작업 불필요
- 기존 워크트리: `/baton:migrate` 권장 (선택 사항)

---

## [1.2.3] — 2026-05-01 (Sidecar 분리 + 헤드리스 정리 — race 종결)

### Fixed (Critical)
- **Hook race condition 종결** — 매 `UserPromptSubmit` / `PostToolUse` / `SessionEnd` 마다 hook이 `JOURNAL.md` / `CURRENT.md` / `phase.json` 을 직접 mutate하던 구조를 폐기. Claude Edit tool이 mtime 기반 optimistic concurrency check를 하기 때문에 hook이 같은 파일을 건드리면 "File has been modified since read" 에러로 agent가 멈추던 문제 해결.

### Changed (Breaking 아님 — 동작 호환)
- **Sidecar 패턴 도입** — Hook은 `.baton/handoff/.events.jsonl` (append-only JSONL)에만 기록.
  - `user-prompt-submit.sh`: 사용자 발화를 `{type:"intent",ts,text}` 한 줄 append. JOURNAL.md/CURRENT.md 손대지 않음.
  - `post-tool-use.sh`: Skill/Agent/Task 도구 사용을 `{type:"harness",ts,name,tool}` 한 줄 append. JOURNAL.md/CURRENT.md/phase.json 손대지 않음.
  - `session-end.sh`: status frontmatter mutation 제거. 미정리 이벤트 카운트만 안내.
  - `pre-compact.sh`: 안내만 출력 (변경 없음).
  - `session-start.sh`: read-only.
- **`/baton:save` 재정의** — frontmatter 한 줄 갱신 + 사용자에게 직접 편집 지시 → 헤드리스 에이전트(claude `--bare` / codex `exec --ephemeral` / gemini `-p --yolo` / opencode `run --pure`) spawn 후 sidecar를 JOURNAL/CURRENT/NEXT로 일괄 정리. spawn된 에이전트는 자기만의 read→edit 사이클이라 race 없음.
- **`/baton:finish` save 자동 호출** — finish가 워크트리 종료의 가장 적합한 정리 지점. sidecar에 미처리 이벤트 있으면 `baton_cmd_save` 자동 호출.
- **`/baton:wt-clean` save 자동 호출** — finish 안 거친 워크트리 대비 archive 직전 save 호출. `--skip-save` 또는 `BATON_WT_CLEAN_SKIP_SAVE=1` 로 회피 가능.

### Added
- `templates/save-prompt.md.template` — 헤드리스 에이전트에게 전달할 정리 instruction. tool_use 잡음 컷·intent/harness 보존·LLM 추측 금지 강제.
- `lib/handoff.sh`:
  - `baton_events_append <handoff_dir> <type> <payload>` — sidecar 한 줄 append (intent/harness 자동 직렬화)
  - `baton_events_rotate <handoff_dir>` — 처리 완료 sidecar `.events.processed-{ts}.jsonl` 회전
  - `baton_events_count <handoff_dir>` — 미처리 이벤트 수 카운트
- `lib/core.sh`:
  - `baton_save_detect_agent` — 환경 자동 감지 (Claude Code → claude, Codex/OMX → codex, fallback opencode/gemini)
  - `baton_save_spawn_agent` — 헤드리스 spawn (각 에이전트별 hook-skip 옵션 적용)
  - `baton_save_fallback_dump` — spawn 실패 시 jq raw dump (LLM 없이 데이터 보존)
- **`BATON_SKIP_HOOKS=1` 가드** — 모든 hook 스크립트 첫 줄에 추가. 헤드리스 spawn 시 baton hook이 자기 자신을 호출하는 무한 루프 방지.
- **`BATON_SAVE_AGENT` 환경변수** — `claude|codex|gemini|opencode` 중 강제 지정 가능. 미지정 시 자동 감지.

### Why
- Hook이 매 prompt/tool마다 파일을 재작성하면 mtime이 갱신됨 → Claude의 Edit tool이 stale-read로 거부 → agent 멈춤 → 사용자가 재시도해도 다음 hook이 또 mtime 갱신 → 무한 실패.
- Anthropic 공식 권장: "hooks가 Claude가 읽고 편집할 파일을 직접 수정하지 말 것." 이번 버전에서 이 패턴을 따름.
- Sidecar 분리 + LLM spawn 정리는 자동 컨텍스트 압축 효과까지 부수적으로 제공 (turns가 누적되어도 JOURNAL은 정돈된 상태로 유지).

### Migration
- 자동 호환 — 기존 `.baton/handoff/JOURNAL.md` / `CURRENT.md` 그대로 사용. 새 sidecar는 `.baton/handoff/.events.jsonl` 으로 추가됨.
- 1.2.2 이전에서 누적된 JOURNAL.md는 그대로 유지. 새 Turn이 1.2.3부터 sidecar→spawn으로 정리됨.

---

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
