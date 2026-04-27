# D: branch-pivot

## 시나리오

메인 작업(phase A)이 진행 중인데 급히 다른 브랜치에서 별도 작업이 필요해지는 상황이다. 예를 들어 feature 구현 도중 팀에서 hotfix 요청이 오거나, 실험적인 접근법을 병렬로 검증해야 할 때 발생한다. 두 워크트리가 동시에 존재하게 되며, 각각 독립된 포트와 handoff 메모리를 가진다.

옵션 B 가드 덕분에 두 phase 모두 워크트리 내부에서만 존재하므로 main 브랜치는 오염되지 않는다. 각 워크트리를 순서대로 또는 병렬로 완료하면 된다.

## 트리거

- 사용자가 "이거 하면서 저것도 봐야 해", "다른 브랜치 하나 더 파자", "병렬로 진행" 등의 신호를 줄 때
- 기존 phase 진행 중 예상치 못한 hotfix 요청이 올 때 (hotfix가 며칠 작업이면 이 케이스, 긴급 소규모면 F: hotfix-mode)
- 실험적 A/B 접근법을 두 워크트리에서 동시에 검증할 때

## 단계별 시퀀스

```
사용자                    baton                      git/하네스
  │                         │                           │
  │ (phase A 작업 중)        │                           │
  │ /baton:save              │                           │
  ├────────────────────────▶│                           │
  │                         │ CURRENT.md status:paused │
  │                         │ NEXT.md 갱신              │
  │                         │                           │
  │ [main으로 돌아가서]       │                           │
  │ /baton:wt-create hotfix-b│                          │
  ├────────────────────────▶│                           │
  │                         │ .worktrees/hotfix-b/ 생성 │
  │                         │ 별도 포트 할당            │
  │                         │ 새 phase.json stub        │
  │                         │ CURRENT.md status:active  │
  │                         │                           │
  │ cd .worktrees/hotfix-b  │                           │
  ├────────────────────────▶│                           │
  │                         │                           │
  │ (hotfix-b 작업)          │                           │
  ├─────────────────────────────────────────────────────▶│
  │                         │                           │ 작업
  │ /baton:finish            │                           │
  ├────────────────────────▶│                           │
  │                         │ hotfix-b phase.json done  │
  │ /baton:wt-clean          │                           │
  ├────────────────────────▶│                           │
  │                         │ hotfix-b archive + 삭제   │
  │                         │                           │
  │ [phase A 워크트리로 복귀] │                           │
  │ cd .worktrees/v5-pr-a3  │                           │
  ├────────────────────────▶│                           │
  │                         │                           │
  │ /baton:resume            │                           │
  ├────────────────────────▶│                           │
  │                         │ NEXT.md 출력              │
  │                         │ CURRENT.md status:active  │
  │                         │                           │
  │ (phase A 재개)           │                           │
  ├─────────────────────────────────────────────────────▶│
  │                         │                           │ 작업 재개
  │ /baton:finish            │                           │
  ├────────────────────────▶│                           │
  │ /baton:wt-clean          │                           │
  ├────────────────────────▶│                           │
  │                         │ phase A archive + 삭제    │
```

## 명령 시퀀스

```bash
# [phase A 워크트리에서 — 일시 정지]
cd .worktrees/v5-pr-a3
/baton:save
# → CURRENT.md status:paused, NEXT.md 갱신

# [main으로 돌아가서 새 워크트리 생성]
cd /path/to/project/root
/baton:wt-create hotfix-b
# → 별도 포트(예: 8090) 자동 할당

# [새 워크트리에서 작업]
cd .worktrees/hotfix-b
/baton:plan hotfix-b          # 필요시 plan 추가
/oh-my-claudecode:autopilot "hotfix-b 구현"
/baton:finish
/baton:wt-clean

# [phase A 워크트리로 복귀]
cd .worktrees/v5-pr-a3
/baton:resume                 # 또는 "이어서"
# → NEXT.md 기반으로 컨텍스트 복원
/oh-my-claudecode:autopilot "이어서 진행"
/baton:finish
/baton:wt-clean

# 전체 상태 확인 (두 워크트리가 동시에 있을 때)
/baton:status
```

## 메모리 흐름

- **PLAN.md** ← 각 워크트리가 독립적으로 보유. phase A의 PLAN.md는 `save` 시점에 보존되고, hotfix-b는 별도 PLAN.md를 가짐.
- **JOURNAL.md** ← 각 워크트리 독립. phase A가 paused 상태인 동안 hotfix-b의 JOURNAL만 갱신됨.
- **CURRENT.md** ← phase A는 `save` 시 `status: paused`로 변경. `resume` 시 `status: active`로 복원. hotfix-b는 별도 active 상태.
- **NEXT.md** ← phase A의 `save` 시 다음 재개 지시로 채워짐. `resume` 시 에이전트가 이를 읽어 컨텍스트 복원.

두 워크트리의 archive 독립 보관:
```
.baton/archive/
├── INDEX.jsonl                          ← 두 phase 모두 기록
├── v5-pr-a3_20260427_1430.tar.gz        ← phase A archive
└── hotfix-b_20260427_1600.tar.gz        ← hotfix-b archive
```

## 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| 두 워크트리가 같은 포트 충돌 | `.worktree-info.json.index` 중복 | `/baton:status`로 포트 목록 확인 후 수동 조정 |
| `resume` 시 CURRENT.md가 active로 안 바뀜 | `save` 없이 이탈 | CURRENT.md 직접 편집 또는 `resume` 재실행 |
| `baton:status`에 phase A가 안 보임 | paused 상태 필터 | `status --all`로 paused 포함 확인 |
| hotfix-b 완료 후 phase A 컨텍스트 소실 | NEXT.md가 없음 | JOURNAL.md 마지막 Turn에서 수동으로 NEXT.md 재작성 |

## 다음 케이스 연계

- 각 브랜치 완료 → **C: wt-finish** (순서대로)
- 한 쪽 포기 → **E: abandoned**
- hotfix-b가 긴급 소규모 수정 → **F: hotfix-mode**로 대신 처리 고려
