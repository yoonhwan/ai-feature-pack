---
name: baton
description: Universal Standard Workflow — 워크트리 + 아카이브 + 작업 메모리 표준. Triggers on `/baton:*` slash commands AND keywords "이어서", "진행", "go", "continue", "next" (resume). MANDATORY before starting any worktree-related work.
---

# baton — Universal Standard Workflow

## 책임 경계

baton은 3축을 담당합니다:

1. **워크트리** — 브랜치별 격리 환경, 포트 자동 할당, 심볼릭 링크 관리
2. **아카이브** — 워크트리 정리 시 `.baton/archive/` 에 tar.gz 보관 (git-tracked)
3. **작업 메모리** — 4-template 핸드오프 (PLAN/JOURNAL/CURRENT/NEXT) 로 세션 간 컨텍스트 유지

baton은 **LLM 작업 실행을 하지 않습니다**. 계획·실행·검증은 외부 하네스에 위임합니다.

## 진입 트리거

| 트리거 종류 | 조건 | 동작 |
|------------|------|------|
| 슬래시 명령 | `/baton:*` | 해당 명령 즉시 실행 |
| 키워드 (resume) | "이어서" / "진행" / "go" / "continue" / "next" | `/baton:resume` 호출 |
| 워크트리 작업 신호 | "새 기능", "브랜치 만들어", "작업 시작" | `/baton:wt-create` 안내 |
| main 코드 수정 요청 | main/master root에서 코드 변경 요청 | 거부 + wt-create 안내 |

## 17 명령 매핑

| 슬래시 명령 | Bash CLI 호출 | 설명 |
|------------|--------------|------|
| `/baton:plan <id> [title]` | `bash ~/.baton/current/bin/baton plan $ARGUMENTS` | phase.json + 4-template 생성 |
| `/baton:wt-create <name>` | `bash ~/.baton/current/bin/baton wt-create $ARGUMENTS` | 워크트리 생성 + 포트 할당 |
| `/baton:save` | `bash ~/.baton/current/bin/baton save` | 핸드오프 dump (status=paused) |
| `/baton:resume` | `bash ~/.baton/current/bin/baton resume` | NEXT.md 출력 (세션 재개) |
| `/baton:finish` | `bash ~/.baton/current/bin/baton finish` | 페이즈 완료 (status=done) |
| `/baton:wt-clean [path] [--merged]` | `bash ~/.baton/current/bin/baton wt-clean $ARGUMENTS` | archive 보관 + 워크트리 삭제 |
| `/baton:status` | `bash ~/.baton/current/bin/baton status` | 활성 phase + 워크트리 목록 |
| `/baton:help` | `bash ~/.baton/current/bin/baton help` | 명령 일람 (ASCII 시퀀스) |
| `/baton:doctor` | `bash ~/.baton/current/bin/baton doctor` | 환경 진단 |
| `/baton:install` | `bash ~/.baton/current/bin/baton install` | 인터뷰형 설치 |
| `/baton:upgrade` | `bash ~/.baton/current/bin/baton upgrade` | 새 버전 설치 안내 |
| `/baton:hotfix-mode [finish]` | `bash ~/.baton/current/bin/baton hotfix-mode $ARGUMENTS` | main 직접 작업 모드 |
| `/baton:archive list [--days N] [--global]` | `bash ~/.baton/current/bin/baton archive list $ARGUMENTS` | 아카이브 목록 |
| `/baton:archive search <q> [--global]` | `bash ~/.baton/current/bin/baton archive search $ARGUMENTS` | 메타+내용 검색 |
| `/baton:archive show <id>` | `bash ~/.baton/current/bin/baton archive show $ARGUMENTS` | 아카이브 상세 |
| `/baton:archive extract <id>` | `bash ~/.baton/current/bin/baton archive extract $ARGUMENTS` | 압축 해제 (임시) |
| `/baton:archive prune [--dry-run] [--days N]` | `bash ~/.baton/current/bin/baton archive prune $ARGUMENTS` | 오래된 아카이브 정리 |

## 키워드 트리거 동작

사용자가 "이어서", "진행", "go", "continue", "next" 중 하나를 입력하면:

1. `/baton:resume` 호출
2. `.baton/handoff/NEXT.md` 출력
3. 에이전트는 NEXT.md + PLAN.md + JOURNAL.md 를 읽고 작업 재개

## 옵션 B (main strict)

main/master 브랜치 root에서 baton은 phase 작업을 **거부**합니다.

**거부 명령**: `plan`, `save`, `resume`, `finish`

**허용 명령**: `wt-create`, `status`, `archive list/search/show/extract`, `hotfix-mode`, `install`, `doctor`, `upgrade`

main에서 코드 변경이 필요하다면:
- 새 기능 → `/baton:wt-create <name>` 으로 워크트리 생성
- 긴급 수정 → `/baton:hotfix-mode` (baton 메모리 비활성, main 직접 작업)

## 외부 하네스 권장 (5종)

| 하네스 | 용도 | 호출 |
|--------|------|------|
| `superpowers:writing-plans` | 계획 수립, PLAN.md 생성 | `/baton:plan` 이후 |
| `oh-my-claudecode:autopilot` | 코드 실행, 피처 구현 | 계획 확정 후 |
| `oh-my-claudecode:team` | 병렬 다중 에이전트 실행 | 복잡한 구현 |
| `oh-my-claudecode:deep-interview` | 요구사항 심층 인터뷰 | 기획 초기 |
| `superpowers:brainstorm` | 설계 대안 탐색 | 아키텍처 결정 전 |

## 자동 정책 (Claude Code 훅)

| 훅 | 타이밍 | 동작 |
|----|--------|------|
| `SessionStart` | 세션 시작 | paused 알림 + 환경 검증 + lazy prune (7일 간격) |
| `UserPromptSubmit` | 사용자 입력 직전 | INTENT → JOURNAL.md 자동 append |
| `PostToolUse` | 도구 사용 후 | 하네스 사용 추출 + CURRENT.md last_harness 갱신 + verification |
| `PreCompact` | 컨텍스트 압축 전 | JOURNAL/CURRENT/NEXT 백업 dump |
| `SessionEnd` | 세션 종료 | 최종 상태 dump |

## Don't

- `git worktree add` 직접 호출 금지 → `/baton:wt-create` 사용
- `.baton/handoff/*` 수동 편집 금지 → `baton_current_set` / `baton_journal_append_intent` 함수 사용
- main/master root에서 코드 수정 금지 → 워크트리로 이전
- `~/.baton/archives/` 사용 금지 → 프로젝트 내부 `.baton/archive/` 사용 (SPEC v1)
