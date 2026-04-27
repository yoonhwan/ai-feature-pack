# E: abandoned

## 시나리오

진행 중이던 phase를 완료 없이 포기해야 하는 플로우다. 우선순위 변경, 방향 전환, 기술적 막힘 등의 이유로 작업을 중단할 때 사용한다. 단순히 워크트리를 삭제하는 것이 아니라 handoff/ 파일을 `tag: abandoned`로 archive에 보관하여 나중에 부분 재활용이 가능하도록 한다.

포기한 작업의 컨텍스트(PLAN.md, JOURNAL.md)는 archive에 남아 있으므로, 나중에 동일 주제로 재시작할 때 `archive search`로 찾아 참고할 수 있다.

## 신호 (이 케이스 식별 방법)

- 사용자가 "이거 그냥 포기하자", "방향 틀자", "나중에 다시 하자" 신호를 줄 때
- phase가 기술적 blocker로 인해 더 이상 진행 불가능할 때
- 다른 phase가 이 phase보다 훨씬 높은 우선순위가 되어 자원을 비워야 할 때
- CURRENT.md `blockers` 항목이 해소 불가능 상태로 판단됐을 때

## 단계

1. **마지막 상태 기록** — `/baton:save` (선택이지만 권장)
   - 동작: CURRENT.md `last_updated` 갱신, NEXT.md에 포기 사유와 재시작 조건 기록
   - 산출물: NEXT.md에 "포기 사유: ..., 재시작 조건: ..." 기록

2. **phase 포기 선언** — `/baton:abandon` 또는 `/baton:finish --tag abandoned`
   - 동작: `phase.json`의 `status`를 `abandoned`로 갱신, CURRENT.md `status: abandoned`로 갱신
   - 산출물: phase.json (status=abandoned)

3. **워크트리 정리** — `/baton:wt-clean --tag abandoned`
   - 동작: handoff/ 파일을 `tag: abandoned`로 archive 압축, INDEX.jsonl에 abandoned 태그 기록, 워크트리 삭제
   - 산출물: `.baton/archive/<phase-id>_abandoned_<ts>.tar.gz`, INDEX.jsonl 갱신

## 단계별 시퀀스

```
사용자                    baton                      git/하네스
  │                         │                           │
  │ "이거 포기하자"           │                           │
  │                         │                           │
  │ /baton:save              │                           │
  ├────────────────────────▶│                           │
  │                         │ CURRENT.md last_updated  │
  │                         │ 갱신, NEXT.md에 포기 사유 │
  │                         │ + 재시작 조건 기록        │
  │                         │                           │
  │ /baton:abandon           │                           │
  │ (또는 /baton:finish      │                           │
  │    --tag abandoned)      │                           │
  ├────────────────────────▶│                           │
  │                         │ phase.json                │
  │                         │   status: abandoned       │
  │                         │ CURRENT.md                │
  │                         │   status: abandoned       │
  │                         │                           │
  │ /baton:wt-clean          │                           │
  │   --tag abandoned        │                           │
  ├────────────────────────▶│                           │
  │                         │ handoff/ 4파일 읽기       │
  │                         │ ↓                         │
  │                         │ archive tar.gz 생성       │
  │                         │ INDEX.jsonl append:       │
  │                         │   tags: ["abandoned"]     │
  │                         │   status: abandoned       │
  │                         │                           │
  │                         │ git worktree remove       │
  │                         │ .worktrees/{name}/ 삭제   │
  │                         │                           │
  │          "✓ abandoned. archive ID: xxx" 출력        │
```

## 명령 시퀀스

```bash
# [워크트리 내부에서]
# 포기 전 상태 저장 (권장)
/baton:save

# phase 포기 선언 (두 방법 중 하나)
/baton:abandon
# 또는
/baton:finish --tag abandoned

# 워크트리 정리 (abandoned 태그 포함)
/baton:wt-clean --tag abandoned

# 나중에 검색하려면
/baton:archive list --tag abandoned
/baton:archive show <archive-id>
```

## 핵심 결정 포인트

- **포기 사유를 기록해야 하는가**: 강력 권장. NEXT.md에 "왜 포기했는가, 재시작하려면 무엇이 필요한가"를 남겨두면 나중에 archive를 꺼낼 때 판단이 쉬워진다.
- **코드 변경사항을 남겨야 하는가**: 브랜치는 삭제하지 않는 것이 기본. `wt-clean --tag abandoned`는 워크트리만 삭제하고 원격 브랜치는 그대로 둔다. 명시적으로 `--delete-branch` 플래그를 줘야만 삭제된다.

## 다음 케이스로 전이

- 보통 → 새 작업 시작 (A 또는 B)
- 나중에 같은 주제 재시작 → `archive search <keyword>` → **H: handoff-rollback**으로 PLAN.md 복원 후 A 또는 B 재시작
- 포기 중 워크트리 손상 → **G: orphan-recovery**

## Don't

- 포기 시 워크트리를 그냥 `rm -rf`로 삭제하지 말 것 — archive도 INDEX도 남지 않음
- `finish` 없이 `wt-clean`만 하면 phase.json이 `active`로 archive됨 — `abandon` 또는 `finish --tag abandoned` 먼저
- 포기 사유를 기록하지 않으면 나중에 archive를 꺼냈을 때 재활용 여부 판단이 어려움
