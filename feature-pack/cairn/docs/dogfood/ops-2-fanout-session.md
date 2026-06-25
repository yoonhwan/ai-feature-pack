# ops#2 fan-out-in-fan-out + 세션 핸드오프 운영 노트

## 목적

- **팬아웃 안의 팬아웃**: 서브태스크가 또 서브태스크를 spawn(depth2 재분기)할 때 복구 그래프가 깊이를 식별 가능하게 표현하는지 검증한다.
- **tmuxc 세션 핸드오프**: 한 작업이 컨텍스트 한계로 세션 #1→#2→#3으로 이어질 때 `session_chain`이 연속성을 보존하는지 검증한다.
- 그래프(`map`)가 depth1/depth2를 시각 구분하고, stale 손자 노드가 누락되지 않으며, 머지/return/스테일 표기가 동시에 성립하는지 확인한다.

## 태스크 원장

| 태스크 | 역할 | depth | execution_ref | return_to | merge/stale | 비고 |
|---|---|---:|---|---|---|---|
| `t1` | ops#2 코디네이터(parent) | 0 | 없음(main) | 없음 | merge root | 그래프 루트 |
| `t2` | depth1: stale 스캔 | 1 | `worktree/ops2-stale-scan` | `t1` | `t1`로 merge | done·병합 |
| `t3` | depth1: nested 확장(재팬아웃 owner) | 1 | `worktree/ops2-nested-owner` | `t1` | 미병합, doing | depth2 자식 보유 |
| `t4` | depth1: tmuxc 핸드오프 | 1 | `worktree/ops2-tmuxc-handoff` | `t1` | `t1`로 merge | 세션 #1→#2→#3 |
| `t5` | depth2: spec 증가 A | 2 | `worktree/ops2-nested-a` | `t3` | **stale**(done·미병합) | 빨강 점선 |
| `t6` | depth2: spec 증가 B | 2 | `worktree/ops2-nested-b` | `t3` | `t3`로 merge | done·병합 |

## 운영 타임라인 (실측 CLI)

| 순서 | 단계 | 명령 | 기대 원장 상태 | 확인 포인트 |
|---:|---|---|---|---|
| 1 | 부모 생성 | `cairn add-task ops2 ms1 "parent: fan-out 복구 통합"` | `t1 fanout_depth=0` | 루트로 보인다 |
| 2 | depth1 spawn ×3 | `cairn spawn "..." --from t1 --worktree worktree/ops2-*` | `t2/t3/t4 return_to=t1 fanout_depth=1` | 세 자식이 t1 아래 같은 depth |
| 3 | depth2 재팬아웃 ×2 | `cairn spawn "..." --from t3 --worktree worktree/ops2-nested-*` | `t5/t6 return_to=t3 fanout_depth=2` | t3의 손자로 한 층 더 깊다 |
| 4 | 세션 핸드오프 | `cairn link t4 --add-session session-t4-2` → `... session-t4-3` | `t4.session_chain=[#1,#2,#3]`, `session_ref=#3` | 노드 `sess`가 `t4-1→t4-3 (3)` |
| 5 | 머지 | `cairn link t2 --merge-back-to t1` (t4→t1, t6→t3) | `merge_back_to` 기록 | 기본 map에서 숨김 처리 |
| 6 | 상태 | `cairn set-status ops2 task ms1 t5 done` (등) | t2/t4/t5/t6 done, t3 doing | t5는 done+미병합 |
| 7 | 검증 | `cairn validate` | `valid` | 어떤 순서에도 원장 무결 |
| 8 | 렌더 | `cairn map` / `render_recovery_map(show_merged=True)` | depth 음영 + stale 빨강 | 아래 판정 |

## 운영자 체크포인트

- depth2 spawn은 반드시 depth1 자식(`t3`)을 `--from`으로 지정한다. `fanout_depth`는 부모+1로 자동 계산되지만, **그래프 음영은 `spawned_from` 체인 홉 수로 파생**되므로 필드를 손으로 안 채워도 일관하게 구분된다.
- 세션 핸드오프는 `--add-session`으로만 누적한다. 직접 `session_ref`만 갈아끼우면 #1/#2 이력이 사라진다.
- `t5`는 작업 완료(done)하되 merge_back하지 않아 stale 손자로 남긴다 — focus가 손자까지 포함하는지 검증하는 핵심 노드.

## 완료 판정

| 항목 | 기대값 | 판정 |
|---|---|---|
| depth2 재팬아웃 | `t5/t6`가 `t3`의 손자(fanout_depth=2) | 통과 |
| depth 시각 구분 | depth1(t2,t3,t4) vs depth2(t5,t6) 다른 음영 | 통과 |
| 세션 체인 | `t4` 노드 `sess t4-1→t4-3 (3)` | 통과 |
| stale 손자 | `t5` 빨강 점선, depth2 음영 위에 우선 | 통과 |
| focus 손자 포함 | `map --focus t1`에 `t5` 포함 | 통과 |
| 원장 무결 | `validate` = valid | 통과 |

## 도그푸드로 드러난 갭과 처리

- **[해소] depth 시각 구분 부재**(Ops#2 bug#1): depth별 점증 음영 추가(`_node_depth`, classDef depth1/2/3). → `cairn-design.md` §9.2.
- **[기구현] focus 손자 누락**(bug#2)·**세션 체인**(spec#1): 이전 라운드에서 이미 구현(`_focused` 상향 추적, `session_chain`).
- **[보류·YAGNI] handoff_from/to/reason, active_session_ref/session_refs 분리**(spec#2,#3): `session_chain` 하나로 대부분 포섭 → v0 제외, 역추적 수요 발생 시 재평가. → `cairn-design.md` §6.
