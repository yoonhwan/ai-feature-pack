# baton 플로우 케이스 인덱스

> 어떤 상황에서 어떤 플로우를 따를지 한눈에 확인하는 매트릭스.

---

## 케이스 매트릭스

| 케이스 | 제목 | 진입점 | 종료점 | 시나리오 1줄 |
|--------|------|--------|--------|--------------|
| **A** | [plan-first](plan-first.md) | `/baton:wt-create` (plan은 워크트리 안에서) | `/baton:wt-clean` | 호흡 긴 작업, wt-create 후 plan |
| **B** | [wt-first](wt-first.md) | `/baton:wt-create` | `/baton:wt-clean` | 가벼운 작업 즉시 (plan 생략) |
| **C** | [wt-finish](wt-finish.md) | `/baton:finish` | `/baton:wt-clean` | 단일 종료 정석 |
| **D** | [branch-pivot](branch-pivot.md) | `/baton:wt-create` (추가) | `/baton:wt-clean` (다중) | 작업 중 새 브랜치 분기 |
| **E** | [abandoned](abandoned.md) | (수동 status 변경) | `/baton:wt-clean --tag abandoned` | phase 포기 |
| **F** | [hotfix-mode](hotfix-mode.md) | `/baton:hotfix-mode start` | `/baton:hotfix-mode finish` | main 직접 hotfix |
| **G** | [orphan-recovery](orphan-recovery.md) | `/baton:doctor` | (자동 + 수동) | .baton 손상 복구 |
| **H** | [handoff-rollback](handoff-rollback.md) | `/baton:archive list` | `/baton:archive close` | handoff 복원 |

---

## 결정 트리

```
[새 작업 시작]
      │
      ▼
 /baton:wt-create <name>   ← 항상 가장 먼저
      │
      ▼
 cd .worktrees/<name>
      │
      ▼
 호흡이 긴가? (PR 여러 개, 며칠 이상 예상)
      ├─ Y ──▶ A: plan-first  → /baton:plan (워크트리 안에서)
      └─ N ──▶ B: wt-first    → 바로 작업

[작업 진행 중]
      │
      ▼
 중간에 다른 브랜치가 필요해졌나?
      ├─ Y ──▶ D: branch-pivot
      └─ N ──▶ 계속 진행

 이 phase를 포기해야 하나?
      ├─ Y ──▶ E: abandoned
      └─ N ──▶ 계속 진행

 main에서 즉각 수정이 필요한가?
      └─ Y ──▶ F: hotfix-mode

[작업 완료]
      │
      ▼
 단일 워크트리인가?
      └─ Y ──▶ C: wt-finish

[문제 발생]
      │
      ▼
 .baton/ 구조 자체가 깨졌나?
      ├─ Y ──▶ G: orphan-recovery
      └─ N ──▶
           handoff/ 파일이 손상됐나?
                └─ Y ──▶ H: handoff-rollback
```

---

## 케이스 간 연계 맵

```
A (plan-first)
  └─▶ C (완료 시 wt-finish)
  └─▶ D (분기 발생 시 branch-pivot)
  └─▶ E (포기 시 abandoned)

B (wt-first)
  └─▶ C (완료 시 wt-finish)
  └─▶ D (분기 발생 시 branch-pivot)
  └─▶ E (포기 시 abandoned)

C (wt-finish)
  └─▶ A 또는 B (다음 phase 시작)

D (branch-pivot)
  └─▶ C (각 브랜치 완료 시)

F (hotfix-mode)
  └─▶ C와 독립 (lite mode, archive에 tag:hotfix만)

G (orphan-recovery)
  └─▶ B 또는 A (복구 후 재시작)

H (handoff-rollback)
  └─▶ 기존 케이스 재개 (복원 후 resume)
```

---

## 메모리 파일 역할 요약

| 파일 | 위치 | gitignore | 역할 |
|------|------|-----------|------|
| `PLAN.md` | `.baton/handoff/` | O | 외부 하네스 결과 누적 (append-only) |
| `JOURNAL.md` | `.baton/handoff/` | O | 시간순 작업 메모리 (INTENT/HARNESS/ACTIONS/TODO) |
| `CURRENT.md` | `.baton/handoff/` | O | 현재 세션 상태 (frontmatter + 블로커 + 핵심 결정) |
| `NEXT.md` | `.baton/handoff/` | O | 다음 세션 1페이지 지시 (≤1KB) |
| `phase.json` | `.baton/` | X (commit) | phase 메타데이터 (팀 합의) |
| `archive/` | `.baton/` | X (commit) | 완료·포기 phase 압축 보관 |

---

## 옵션 B 가드 요약

> **핵심**: `/baton:wt-create`는 항상 가장 먼저. `/baton:plan`은 워크트리 안에서만.

| 위치 | 허용 | 거부 |
|------|------|------|
| main/master root | `wt-create`, `hotfix-mode`, `archive *`, `status`, `doctor`, `upgrade` | `plan`, `save`, `resume`, `finish` |
| 워크트리 내부 | 모든 명령 | — |
