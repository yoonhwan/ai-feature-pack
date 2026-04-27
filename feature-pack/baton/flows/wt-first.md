# B: wt-first

## 시나리오

계획 없이 바로 워크트리를 만들고 작업에 뛰어드는 경량 플로우다. 요구사항이 명확하고 작업 범위가 좁으며, 30분~2시간 안에 끝날 것 같을 때 적합하다. `plan` 단계를 생략하므로 `phase.json`은 빈 stub 상태로 생성되고, PLAN.md도 처음에는 비어있다.

작업이 커지면 언제든 `deep-interview` 하네스를 호출해 PLAN.md를 채울 수 있다. 처음부터 완벽한 계획이 필요하지 않다는 것이 이 플로우의 핵심이다.

## 트리거

- 사용자가 "바로 만들어줘", "빠르게 시작", "워크트리만 만들어줘" 등의 신호를 줄 때
- 작업 예상 시간이 2시간 이하이거나 단일 PR 범위일 때
- 버그 수정, 간단한 설정 변경, 소규모 리팩터링 등 범위가 명확할 때
- `config.json`의 `harnesses.preferred_plan`이 미설정인 경우 baton 기본 제안

## 단계별 시퀀스

```
사용자                    baton                      git/하네스
  │                         │                           │
  │ /baton:wt-create fix-typo│                          │
  ├────────────────────────▶│                           │
  │                         │ 옵션 B 가드 확인           │
  │                         │ (main이면 허용 — wt-create│
  │                         │  는 main에서도 OK)         │
  │                         │                           │
  │                         │ .worktrees/fix-typo/ 생성 │
  │                         │ 포트 할당 + 심볼릭 링크   │
  │                         │ phase.json 빈 stub 생성   │
  │                         │ handoff/ 초기화           │
  │                         │ CURRENT.md status:active │
  │                         │                           │
  │ cd .worktrees/fix-typo  │                           │
  ├────────────────────────▶│                           │
  │                         │                           │
  │ (작업 직접 수행 or 하네스)│                           │
  ├─────────────────────────────────────────────────────▶│
  │                         │                           │ 코드 수정
  │                         │ PostToolUse: JOURNAL.md  │
  │                         │ ACTIONS 섹션 append       │◀─┤
  │                         │                           │
  │ /baton:finish            │                           │
  ├────────────────────────▶│                           │
  │                         │ phase.json status:done   │
  │                         │ CURRENT.md status:done   │
  │                         │ wt-clean 제안             │
  │                         │                           │
  │ /baton:wt-clean          │                           │
  ├────────────────────────▶│                           │
  │                         │ handoff/ → archive 압축  │
  │                         │ 워크트리 삭제             │
  │                         │ INDEX.jsonl 갱신          │
```

## 명령 시퀀스

```bash
# [main/master root에서] 워크트리 즉시 생성
/baton:wt-create fix-typo
# phase.json은 빈 stub으로 생성됨 (plan 없이)

# [워크트리 진입]
cd .worktrees/fix-typo

# 작업 수행 (직접 또는 하네스)
# 직접 수행 예시:
# 파일 수정 → 커밋

# 하네스 사용 예시:
/oh-my-claudecode:autopilot "오타 수정 및 커밋"

# 작업이 생각보다 커졌을 때 plan 추가 (선택)
/baton:plan fix-typo
# → writing-plans 또는 deep-interview 하네스 호출
# → PLAN.md가 채워짐

# phase 완료
/baton:finish

# 워크트리 정리 + archive 보관
/baton:wt-clean
```

## 메모리 흐름

- **PLAN.md** ← 처음에는 비어있음. 작업이 커질 경우 `/baton:plan`을 뒤늦게 호출해 채울 수 있음. 하네스 결과가 append-only로 누적됨.
- **JOURNAL.md** ← `UserPromptSubmit` 훅이 매 사용자 입력을 INTENT로, `PostToolUse` 훅이 도구 사용 결과를 ACTIONS/HARNESS로 자동 append. plan 없이 시작했으므로 INTENT가 첫 기록.
- **CURRENT.md** ← `wt-create` 시 `status: active`로 초기화, `agent` 필드에 현재 에이전트 ID 기록. `finish` 시 `status: done`.
- **NEXT.md** ← `save` 또는 `PreCompact`/`SessionEnd` 훅 시 갱신. 짧은 작업이므로 대부분 "완료" 또는 비어있게 됨.

## plan-first(A)와의 차이

| 항목 | A: plan-first | B: wt-first |
|------|---------------|-------------|
| 시작 명령 | `wt-create` → `plan` | `wt-create` 바로 |
| PLAN.md | plan 직후 채워짐 | 처음엔 빈 stub |
| 적합 작업 | 수 시간 이상, 복잡 | 2시간 이하, 단순 |
| 하네스 의존 | 높음 (plan 필수) | 낮음 (선택) |
| 세션 인계 품질 | 높음 (PLAN.md 충실) | 보통 (JOURNAL.md 의존) |

## 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| `wt-create` 후 포트가 이미 사용 중 | 이전 워크트리 잔존 | `/baton:status`로 확인 후 불필요한 워크트리 `wt-clean` |
| phase.json이 비어서 팀원이 혼란 | plan 생략 | 작업 완료 후라도 `/baton:plan`으로 메타데이터 보강 |
| JOURNAL.md에 아무것도 안 쌓임 | PostToolUse 훅 미등록 | `/baton:doctor`로 훅 등록 상태 확인 |

## 다음 케이스 연계

- 작업 완료 → **C: wt-finish** (PR 머지 + 정리)
- 작업이 커져서 plan이 필요해짐 → 이 케이스 내에서 `/baton:plan` 추가 호출
- 작업 중 다른 브랜치 분기 → **D: branch-pivot**
- phase 포기 → **E: abandoned**
