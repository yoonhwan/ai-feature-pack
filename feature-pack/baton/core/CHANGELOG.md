# baton Changelog

이 파일은 사용자가 직접 편집 가능합니다. 글로벌 설치본(`~/.baton/versions/{ver}/`)의 변경 이력을 추적하세요.

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
