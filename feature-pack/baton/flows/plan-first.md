# A: plan-first

## 시나리오

호흡이 긴 작업(PR 여러 개, 며칠~수 주 예상)을 시작할 때 따르는 정석 플로우다. 구현에 앞서 `deep-interview` 또는 `superpowers:writing-plans` 하네스로 phase를 충분히 설계한 뒤, 워크트리를 생성하고 외부 하네스에 실행을 위임한다.

계획이 먼저 있어야 중간에 에이전트가 교체되거나 세션이 끊겨도 PLAN.md를 기반으로 무중단 인계가 가능하다. 불확실한 요구사항, 여러 팀원이 관여하는 phase, 복잡한 아키텍처 결정이 수반되는 작업에 적합하다.

## 트리거

- 사용자가 "plan부터 시작하자", "설계 먼저", "긴 작업이니까 계획이 필요해" 등의 신호를 줄 때
- 예상 작업 시간이 2시간 이상이거나 PR이 2개 이상 예상될 때
- `config.json`의 `harnesses.preferred_plan`이 설정되어 있을 때 자동 제안
- 이전 NEXT.md에 "다음 phase: plan부터" 지시가 있을 때

## 단계별 시퀀스

```
사용자                    baton                      git/하네스
  │                         │                           │
  │ /baton:wt-create v5-pr-a3│                          │
  ├────────────────────────▶│                           │
  │                         │ .worktrees/v5-pr-a3/ 생성│
  │                         │ 포트 할당                 │
  │                         │ 심볼릭 링크 설정          │
  │                         │ phase.json 빈 stub 생성   │
  │                         │ CURRENT.md status:active │
  │                         │                           │
  │ cd .worktrees/v5-pr-a3  │                           │
  ├────────────────────────▶│                           │
  │                         │                           │
  │ /baton:plan v5-pr-a3    │                           │
  ├────────────────────────▶│                           │
  │                         │ 옵션 B 가드 확인           │
  │                         │ (main이면 거부 — 워크트리  │
  │                         │  안에서만 허용)            │
  │                         │                           │
  │                         │ handoff/ 초기화           │
  │                         │ 하네스 후보 출력 (3개)     │
  │ 하네스 선택              │                           │
  ├────────────────────────▶│                           │
  │                         │                           │
  │                         │ ──▶ deep-interview 호출  │
  │                         │     또는                  │
  │                         │ ──▶ writing-plans 호출   │
  │                         │                           │
  │                         │     결과 → PLAN.md append│
  │                         │                           │
  │ /oh-my-claudecode:autopilot "..."                   │
  ├─────────────────────────────────────────────────────▶│
  │                         │                           │ 작업 실행
  │                         │ PostToolUse: JOURNAL.md  │
  │                         │ HARNESS 섹션 append       │◀─┤
  │                         │                           │
  │ /baton:save (중간 저장)  │                           │
  ├────────────────────────▶│                           │
  │                         │ CURRENT.md 갱신           │
  │                         │ NEXT.md 갱신              │
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
# [main/master root에서] 워크트리 생성
/baton:wt-create v5-pr-a3

# [워크트리 진입]
cd .worktrees/v5-pr-a3

# plan 기획 (하네스 선택 프롬프트 출력)
/baton:plan v5-pr-a3
# → deep-interview 선택: /oh-my-claudecode:deep-interview
# → writing-plans 선택: /superpowers:writing-plans
# 결과는 .baton/handoff/PLAN.md에 자동 누적

# 외부 하네스로 실행 위임
/oh-my-claudecode:autopilot "PLAN.md 기반으로 v5-pr-a3 구현"
# 또는
/superpowers:executing-plans

# 세션 중 중간 저장 (선택, PreCompact/SessionEnd 훅이 자동 처리)
/baton:save

# phase 완료
/baton:finish

# 워크트리 정리 + archive 보관
/baton:wt-clean
```

다음 세션에서 이어받기:
```bash
cd .worktrees/v5-pr-a3
# 어떤 에이전트에서든
/baton:resume
# 또는 키워드만 입력
이어서
```

## 메모리 흐름

- **PLAN.md** ← `deep-interview` 또는 `writing-plans` 하네스 결과가 타임스탬프 헤더와 함께 append. 여러 번 수정할 경우 "Plan v2 (revised by ...)" 형식으로 누적.
- **JOURNAL.md** ← `UserPromptSubmit` 훅이 매 사용자 입력을 INTENT 섹션으로, `PostToolUse` 훅이 하네스 invocation 결과를 HARNESS 섹션으로 자동 append. Turn 단위로 시간순 누적.
- **CURRENT.md** ← `wt-create` 시 `status: active`로 초기화. `save` 시 `last_updated` + 블로커 + 핵심 결정 갱신. `finish` 시 `status: done`.
- **NEXT.md** ← `save` 및 `PreCompact`/`SessionEnd` 훅 시 다음 세션 지시로 갱신. 길이 1KB 이내 유지.

## 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| `baton plan` 이 main에서 거부됨 | 옵션 B 가드 | 먼저 `wt-create`로 워크트리 생성 후 `cd`하고 `plan` 실행 |
| 하네스 후보가 출력 안 됨 | `config.json.harnesses` 미설정 | `config.json`에 `preferred_plan` 키 추가 또는 `/baton:doctor` 실행 |
| PLAN.md가 비어있음 | 하네스 PostToolUse 훅 미등록 | `install.sh` 재실행 또는 `settings.json` hooks 수동 확인 |
| `wt-create` 후 포트 충돌 | 기존 워크트리와 index 겹침 | `/baton:status`로 활성 워크트리 목록 확인, `.worktree-info.json.index` 수동 조정 |
| `resume` 시 NEXT.md가 없음 | 이전 세션에서 save 안 됨 | `PreCompact`/`SessionEnd` 훅 등록 확인. JOURNAL.md에서 마지막 Turn 수동 확인 |

## 다음 케이스 연계

- 작업 완료 → **C: wt-finish** (PR 머지 + 정리)
- 작업 중 다른 브랜치가 필요해짐 → **D: branch-pivot**
- phase를 포기해야 함 → **E: abandoned**
- `.baton/` 구조 손상 발생 → **G: orphan-recovery**
