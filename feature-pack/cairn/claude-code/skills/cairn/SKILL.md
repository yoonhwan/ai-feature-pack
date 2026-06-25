---
name: cairn
description: cairn 일정·복구 원장 CLI. "마일스톤", "태스크", "일정", "지연/overdue", "간트", "복구 그래프", "spawn/complete/return", "fanout/fanin", "세션 증류 후 복귀점" 관련 작업 시 발동. 결정적 단일 직렬 writer 원장(.cairn/plan.yaml) + git 추적. 멀티에이전트 fan-out 작업의 분기→완료→복귀(return_to/merge_back_to) 계보를 1급으로 소유.
---

# cairn — 일정관리 + 멀티에이전트 복구 원장

`cairn`은 두 가지를 한 원장(`.cairn/plan.yaml`)에서 결정적으로 관리한다:
1. **일정**: 프로젝트/마일스톤/태스크 + start/due + overdue + 간트(mermaid)
2. **복구**: 멀티에이전트 fan-out 작업의 `spawned_from`/`return_to`/`merge_back_to`/`fanout_depth` 계보 → 세션 증류·워크트리 정리 후에도 복귀점 보존

설치형: 전역 1회 설치(`~/.cairn/`), 실행 cwd 프로젝트의 `.cairn/` 원장을 대상으로 동작.

## 책임 경계
- cairn = **계획 앵커 + 복구 그래프**. 실행(tmuxc)·기억(baton)·git을 read-only join.
- 자체 쓰기는 `.cairn/plan.yaml`(계획) + 복구 메타뿐. 단일 직렬 writer(flock + atomic + validate + git commit).
- 컨텍스트 재주입은 위임하지 않고 baton resume에 **연결**(`cairn return` → 안내).

## 명령 매핑 (슬래시 → CLI)

| 슬래시 | 동작 |
|--------|------|
| `/cairn:status` | 전체 프로젝트 진행률 |
| `/cairn:show <project>` | 프로젝트 구조 |
| `/cairn:overdue [--today]` | 지연 마일스톤·태스크 |
| `/cairn:render` | 전사 간트 → `.cairn/views/plan.md` |
| `/cairn:add-task <p> <ms> <name> [--days N]` | 태스크(start=오늘, due=start+N) |
| `/cairn:add-milestone <p> <name>` · `/cairn:new-project <name>` | 생성 |
| `/cairn:set-status` · `/cairn:set-date` · `/cairn:set-priority` | 상태/일정/우선순위 |
| `/cairn:spawn <name> --from <parent>` | **복구 분기** (spawned_from/return_to/fanout_depth 자동) |
| `/cairn:complete <task> [--force]` | 완료 + return_to 노출 (누락 시 차단) |
| `/cairn:return --to <node>` | 복구 노드 재앵커 + baton resume 연결 |
| `/cairn:map [--focus] [--render]` | 복구 그래프(recovery-map) mermaid |
| `/cairn:link <node> --execution-ref/--session-ref/--merge-back-to` | 훅 호출용 메타 기록 |
| `/cairn:reconcile` | 활성 worktree ↔ 노드 orphan 탐지 |
| `/cairn:validate` · `/cairn:self-test` · `/cairn:revert` | 무결성·자가검증·되돌리기 |
| `/cairn:remove-task/milestone/project` | 삭제(의존성·비어있음 가드) |

## 복구 메타 정책
- `return_to`만 자동 불가 → **spawn 시 명시**(기본=parent). 누락 시 `complete` 차단(`--force` 우회, forced_complete 표식 기록).
- task id는 **전역 유니크**(복구 메타가 전역 참조).
- 훅 자동캡처(git post-merge/checkout, baton wt-create/clean, tmuxc 세션)가 `execution_ref`/`session_ref`/`merge_back_to`를 `cairn link`로 기록. `cairn reconcile`이 hook 우회·orphan 보정.

## Don't
- `.cairn/plan.yaml` 직접 편집 금지 — 반드시 cairn 명령(transaction 경유).
- 복구 그래프 끊김 금지 — `cairn validate`가 끊긴 엣지 0 보장.
