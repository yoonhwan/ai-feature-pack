# C: wt-finish

## 시나리오

단일 워크트리 작업이 완료되어 PR을 머지하고 워크트리를 정리하는 플로우다. 모든 케이스(A, B, D, F 제외)의 마지막 단계가 이 케이스를 거친다. `finish` → `wt-clean` 두 명령으로 완료되며, 이 과정에서 handoff/ 파일 전체가 archive에 압축 보관된다.

archive 보관 덕분에 나중에 동일 맥락의 작업이 생기면 `archive search`로 과거 PLAN.md, JOURNAL.md를 검색해 재활용할 수 있다.

## 트리거

- 사용자가 "다 됐어", "PR 올렸어", "머지됐어", "정리하자" 등의 신호를 줄 때
- PR이 실제로 머지된 것을 확인했을 때 (baton이 git 상태로 자동 감지 가능)
- `phase.json`의 `completion_criteria`가 모두 충족됐을 때

## 단계별 시퀀스

```
사용자                    baton                      git/하네스
  │                         │                           │
  │ (PR 머지 완료)           │                           │
  │                         │                           │
  │ /baton:finish            │                           │
  ├────────────────────────▶│                           │
  │                         │ completion_criteria 체크  │
  │                         │ phase.json status:done   │
  │                         │ CURRENT.md status:done   │
  │                         │ last_updated 갱신         │
  │                         │                           │
  │                         │ "wt-clean으로 정리할까요?" │
  │                         │ (제안 출력)               │
  │                         │                           │
  │ /baton:wt-clean          │                           │
  ├────────────────────────▶│                           │
  │                         │ handoff/ 4파일 읽기       │
  │                         │ ↓                         │
  │                         │ .baton/archive/           │
  │                         │ {phase_id}_{ts}.tar.gz   │
  │                         │ 생성                      │
  │                         │                           │
  │                         │ INDEX.jsonl에 메타 append │
  │                         │ (phase_id, title, branch, │
  │                         │  status, tags, timestamp) │
  │                         │                           │
  │                         │ git worktree remove       │
  │                         │ .worktrees/{name}/ 삭제   │
  │                         │                           │
  │                         │ 포트 반환                 │
  │                         │ (다음 워크트리가 재사용)   │
  │                         │                           │
  │                         │ lazy prune 체크           │
  │                         │ (retention_days 초과분    │
  │                         │  자동 삭제 — 7일 간격)    │
  │                         │                           │
  │                 "✓ 완료. archive ID: xxx" 출력      │
```

## 명령 시퀀스

```bash
# [워크트리 내부에서]
# PR 머지 후

# phase 완료 선언
/baton:finish
# → phase.json, CURRENT.md 갱신
# → "wt-clean으로 정리하시겠습니까?" 제안

# 워크트리 정리 + archive 보관
/baton:wt-clean
# 또는 PR 머지 확인과 함께
/baton:wt-clean --merged

# [이미 다른 위치에 있을 때 경로 지정]
/baton:wt-clean .worktrees/v5-pr-a3

# archive에서 완료 확인
/baton:archive list
/baton:archive show {archive-id}
```

## 메모리 흐름

- **PLAN.md** ← wt-clean 시 archive에 압축 포함. 이후 `archive extract`로 꺼낼 수 있음.
- **JOURNAL.md** ← 마찬가지로 archive에 압축 포함. 전체 작업 이력 보존.
- **CURRENT.md** ← `finish` 시 `status: done`으로 최종 갱신된 후 archive에 포함.
- **NEXT.md** ← archive에 포함. 다음 phase가 이 phase를 이어받는 경우 `archive extract`로 꺼내 참고.

archive 구조:
```
.baton/archive/
├── INDEX.jsonl         ← 메타(phase_id, branch, status, tags, path) 한 줄씩 append
└── v5-pr-a3_20260427_1430.tar.gz
    └── handoff/
        ├── PLAN.md
        ├── JOURNAL.md
        ├── CURRENT.md
        └── NEXT.md
```

## 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| `wt-clean` 시 "worktree not found" | 이미 수동으로 디렉토리 삭제됨 | `git worktree prune` 후 `/baton:wt-clean --force` |
| archive 파일이 생성 안 됨 | `tar` 미설치 | `command -v tar` 확인, OS에 따라 설치 |
| INDEX.jsonl이 비어있음 | 이전 wt-clean이 중단됨 | `archive list`로 실제 tar.gz 파일 확인 후 수동 INDEX 복구 |
| 포트가 반환되지 않음 | `.worktree-info.json` 잔존 | 해당 파일 수동 삭제 또는 `/baton:doctor` 실행 |
| `finish` 없이 `wt-clean` 호출 | 순서 오류 | baton이 경고 출력 후 진행 여부 확인. `finish` 먼저 실행 권장 |

## 다음 케이스 연계

- 정리 완료 후 새 작업 → **A: plan-first** 또는 **B: wt-first**
- 과거 archive 내용 참조 → `archive search <query>`로 재활용
- wt-clean 중 오류 → **G: orphan-recovery**
