# cairn — 일정관리 + 멀티에이전트 복구 원장

결정적 단일 직렬 writer 원장(`.cairn/plan.yaml`)으로 두 가지를 관리한다:

1. **일정**: 프로젝트 / 마일스톤(start·end) / 태스크(start·due) + overdue + 전사 간트(mermaid)
2. **복구**: 멀티에이전트 fan-out 작업의 계보(`spawned_from` / `return_to` / `merge_back_to` / `fanout_depth`) — 세션 증류·워크트리 정리 후에도 복귀점 보존

baton(기억)·tmuxc(실행)·git을 read-only join하고, 자체 쓰기는 계획 + 복구 메타뿐. 단일 직렬 writer(flock + atomic + validate + git commit).

## 설치

```bash
bash install.sh          # ~/.cairn 전역 설치 + Claude Code 슬래시/스킬 등록
cairn self-test          # 검증
```

전역 1회 설치 후, **어느 프로젝트 cwd에서 실행하든** 그 프로젝트의 `.cairn/` 원장을 대상으로 동작한다.

## 일정 명령

| 명령 | 동작 |
|------|------|
| `cairn new-project <name>` / `add-milestone <p> <name>` / `add-task <p> <ms> <name> [--days N]` | 생성 |
| `cairn status` / `show <p>` / `overdue [--today]` / `render` | 조회·간트 |
| `cairn set-status` / `set-date` / `set-priority` | 변경 |

## 복구 명령 (fan-out / fan-in)

| 명령 | 동작 |
|------|------|
| `cairn spawn <name> --from <parent>` | **분기**(fan-out) — spawned_from/return_to/fanout_depth 자동 |
| `cairn complete <task> [--force]` | 완료 + return_to 노출 (누락 시 차단) |
| `cairn return --to <node>` | **복귀**(fan-in) — 재앵커 + baton resume 연결 |
| `cairn map [--focus] [--render]` | 복구 그래프(recovery-map) mermaid → termaid |
| `cairn link <node> --execution-ref/--session-ref/--merge-back-to` | 훅 호출용 메타 기록 |
| `cairn reconcile` | 활성 worktree ↔ 노드 orphan 탐지 |

## 무결성

- task id는 **전역 유니크**(복구 메타 전역 참조). `cairn validate`가 끊긴 복구 엣지 0을 보장.
- 모든 쓰기는 transaction(lock + atomic write + validate + git commit). 더티 가드.

## 라이선스

MIT
