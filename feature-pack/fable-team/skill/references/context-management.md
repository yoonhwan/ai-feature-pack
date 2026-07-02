# fable-team 컨텍스트 관리 — 상태 외재화 + compact/clear/재시작 정책

핵심 원칙 한 줄: **컨텍스트는 캐시, 디스크가 SSOT.** 오케스트레이터 컨텍스트가 어느 시점에 증발해도 `.fable-team/state/`만으로 파이프라인이 복원돼야 한다.

## 왜 필요한가 (배경)

파이프라인 진행 기록(원장·라운드 카운터·워커 생존)이 오케스트레이터 컨텍스트 **안에만** 있으면 ① 자동 컴팩션 ② 세션 재시작(에이전트 정의 설치가 이미 필수 경계로 요구) ③ ctx 임계 증류로 예고 없이 소실된다. 소실되면 라운드 한도(monitoring-loop §5)가 무의미해지고, 완료 단계를 재실행하며, 최악의 경우 CHANGES_REQUESTED를 잊고 미승인 구현을 종결 보고한다(게이트 우회). 단계 간 전달이 이미 파일 경유인데 **진행 포인터만 휘발성**인 것이 구멍이다.

## 1. 상태 외재화 — 디렉토리 + 핸드오프 스펙

```
<project>/.fable-team/
  features/<slug>.md            # 피처 파일 (feature-interview 산출)
  features/design-<slug>.md     # 설계 파일 (planner 산출 — 경로를 이 위치로 명문화)
  state/ACTIVE                  # 활성 피처 slug 한 줄 (없으면 유휴)
  state/<slug>.state.md         # 핸드오프 SSOT (아래)
  state/<slug>/                 # 워커 산출물 보관함
    checker-<NN>.json           # checker 보고 (JSON 한 줄 그대로)
    da-round<N>.md              # DA 판정 + 증거 (라운드별)
    tester-round<N>.json        # tester 결과
```

**`state/<slug>.state.md`** — YAML frontmatter(기계 판독) + 본문(사람/LLM 판독):

```markdown
---
slug: <slug>
stage: 3            # 0킥오프|1수집|2기획|3구현|4검증|5게이트|6종결
status: running     # running | blocked(에스컬레이션 대기) | done
da_round: 1         # 게이트 라운드 (한도 2)
planner_rounds: 1   # 재기획 횟수 (한도 2)
respawns: {impl: 0, tester: 0}   # 워커별 재스폰 횟수 (한도 각 2)
design: features/design-<slug>.md
updated: 2026-07-02T14:30
---
## 원장
| 워커 | 경로 | 상태 | 마지막 신호 | 조치 |
|------|------|------|-------------|------|
| impl-02 | Agent | 🟢 작업중 | 14:28 중간보고 | — |

## 이벤트 로그 (최신 위, append-only)
- 14:30 stage 2→3 전이. design v1 → impl-02 스폰
- 14:24 planner DESIGN_WRITTEN features/design-<slug>.md
```

**write-through 규율 — 다음 4개 이벤트마다 디스크 갱신(의무, "가능하면" 아님)**:

1. **단계 전이** (stage N 완료 → N+1 진입 직전) — 예외 없음.
2. **게이트/검증 판정 수신** (DA APPROVED·CHANGES_REQUESTED, tester ALL_PASS·FAIL) — 판정 원문은 `state/<slug>/` 파일로, state.md엔 결과 한 줄 + 카운터.
3. **워커 상태 변화** (스폰·완료·실패·재스폰·해산) — 원장 행 갱신과 동시.
4. **에스컬레이션/블록** (status: blocked + 사유 이벤트 로그).

이 4개가 monitoring-loop §4의 "보고 때마다 갱신"을 대체한다(컨텍스트 원장 → 디스크 원장).

**워커 산출물 외재화**: 워커의 "JSON 한 줄" 보고는 수신 즉시 `state/<slug>/`에 파일로 낙수(오케스트레이터가 Write). DA 판정+증거처럼 긴 것은 드라이버가 직접 `state/<slug>/da-round<N>.md`에 Write하고 경로만 보고 — planner 재기획 입력도 이 경로를 릴레이하므로 증거 본문이 오케스트레이터 컨텍스트에 실리지 않는다(컨텍스트 최소화 수칙과 합치).

**항상 디스크에 있어야 하는 상태(완결 목록)**: 피처 파일, 설계 파일(버전 갱신 포함), stage 포인터, 3종 카운터(da_round/planner_rounds/respawns), 원장, 워커 산출물(판정·증거), 블록 사유. 이 밖의 것(워커 transcript, Workflow runId)은 복원에 **불필요**해야 한다 — runId는 이벤트 로그에 참고로만 기록하고 복원 시 신뢰하지 않는다(같은 세션 한정).

## 2. 오케스트레이터 컨텍스트 임계 정책

| 수단 | 트리거 | 부작용 | 사전·사후 조치 |
|------|--------|--------|----------------|
| **/compact** | ctx **70%** && 진행 중 → **다음 단계 경계**에서 | 요약 손실(원장 세부 뭉개짐). Agent 열린 워커는 생존 | 사전: write-through 최신 확인. 사후: **첫 행동 = state.md re-Read로 원장 재적재** |
| **/clear** | 피처 **종결(stage 6) 후** 다음 피처 전, 같은 세션 && 에이전트 정의 변경 없음 | 대화 전체 소실. 열린 워커 생존 미보장 | 사전: status=done + 열린 워커 전원 해산. 사후: 신규 피처 인터뷰부터 |
| **세션 재시작(증류)** | ① ctx **80%**(하드) ② compact 1회 후 재차 70% ③ 에이전트 .md 설치/수정 ④ 세션 오염(400 반복) | Agent 워커 전멸, resumeFromRunId 무효, 대화 소멸. 디스크 유지 | 사전: state.md 최신화 + ACTIVE 확인 + "재시작 후 fable-team 재트리거" 안내. 사후: §4 복원 |

**단계 경계 규칙**: compact/clear/재시작은 **반드시 단계 경계에서** — 단계 중간엔 워커 통지 대기가 걸려 유실 위험. ctx 확인 시점은 매 단계 전이 시(write-through와 같은 타이밍). 안전 경계 우선순위: **stage 2→3(설계 확정 직후)** > stage 5→6(게이트 통과 직후) > 기타. stage 3 진행 중 80% 도달 시: implementer에 SendMessage로 현 시점 마무리 지시 → 원장에 "구현 중단·재개 필요" 기록 → 재시작(복원은 §4-5 단계 재실행이 흡수).

**자동 컴팩션 방어**: 자동 컴팩션은 예고 없이 온다 — write-through가 유일한 방어선이라 §1의 4개 갱신 시점이 의무다. 컴팩션 인지 순간(요약 시스템 메시지 감지) 즉시 state.md re-Read.

## 3. 워커 컨텍스트 관리

**대원칙: 열린 워커는 최적화이지 필수 경로가 아니다.** 파일 릴레이 덕에 모든 워커는 무상태 재스폰 가능해야 하며, 열린 워커에만 있는 상태(파일에 없는 결정·맥락) 생성을 금지한다.

| 워커 | 열어두는 구간 | 닫는 시점 |
|------|--------------|-----------|
| checker | 열지 않음 | 보고 수신 즉시 (후속은 재스폰이 더 싸고 안전) |
| implementer | stage 3 ~ 게이트 종료 (approve loop 재라운드용) | **APPROVED** 또는 다음 라운드 15분+ 지연 예상 시 조기 해산 |
| da (Agent 경로) | approve loop 동안 | APPROVED / 라운드 한도 초과 |
| planner/tester (Workflow) | 해당 없음 (일회성) | — |

공통: **stage 5→6 전이 = 전원 해산 지점.** 에스컬레이션(status=blocked) 진입 시에도 전원 해산 — 대기 중 열린 워커는 낭비이자 세션 리스크.

**approve loop 라운드 간 상태 보존**: 라운드 상태는 전부 파일에 있다 — `da_round`(state.md) + `state/<slug>/da-round<N>.md`(판정·증거) + `features/design-<slug>.md`(재기획 시 planner 갱신, 이벤트 로그에 "design v2"). implementer가 살아있으면 SendMessage "설계 파일 갱신됨(v2). 재Read 후 차이만 구현" — 빠른 경로. 죽었으면 재스폰(같은 계약이라 결과 동일).

**재스폰 규약(번호 절차)**:

1. 원장에서 사망/해산 확인 → `respawns` +1, **한도 2** 초과 시 재스폰 대신 에스컬레이션.
2. 같은 역할 **새 이름**(`impl-02`→`impl-03`) — 에이전트 타입 캐시 함정 회피 겸 추적성.
3. 스폰 프롬프트 = 표준 계약(파일 경로 + 보고 형식)**만**. 이전 대화 요약 전달 금지(파일이 SSOT, 요약 전달은 열린-워커-의존 설계로의 퇴행).
4. implementer 재스폰 계약 문구: "설계 파일을 Read하고 **현재 코드와의 차이를** 구현" — 부분 구현에서 재개해도 멱등(설계 = 목표 상태 선언).
5. Workflow 워커: 완료 판정은 runId 캐시가 아니라 **산출물 파일 존재**로만(design-<slug>.md 존재 = stage 2 완료).

## 4. 세션 재시작 복원 절차

새 세션에서 fable-team 트리거 시, 피처 인터뷰 **이전에** 수행:

1. `<project>/.fable-team/state/ACTIVE` 확인. 없으면 → 신규 플로우.
2. 있으면 slug 획득 → `state/<slug>.state.md` Read → frontmatter(stage/status/카운터) + 원장 적재. `status: done`이면 ACTIVE 제거 후 신규 플로우.
3. `status: blocked`면 이벤트 로그의 블록 사유를 사용자에게 제시하고 결정부터 받는다(자동 재개 금지).
4. **산출물 실재 검증**(state는 선언, 파일이 증거): stage 이하 완료 단계 산출물 존재 확인 — 피처 파일(0), checker JSON(1), 설계 파일(2), 구현 diff/IMPLEMENTED 이벤트(3), tester/da 라운드 파일(4-5). **불일치 시 산출물이 실재하는 마지막 단계로 stage 롤백**(예: state=3인데 설계 파일 없음 → stage 2부터).
5. 재개 단계 결정: 검증된 **진행 중이던 단계를 처음부터 재실행**(단계 원자성 — implementer 계약이 멱등이라 안전). stage 5 도중이면 마지막 `da-round<N>.md` 판정으로 분기: CHANGES_REQUESTED 후 재기획 전 → stage 2 재진입, 수정 설계 완료 후 → stage 3.
6. **필요한 워커만 재스폰**: 재개 단계 워커만. 완료 단계 워커(checker 등)는 산출물이 파일에 있으므로 재스폰하지 않는다. 카운터는 state.md 값을 **승계**(da_round=1이었으면 라운드 2부터 — 한도가 세션을 넘어 유효).
7. 사용자에게 1회 재개 보고: 복원된 원장 + "stage N부터 재개, 사유: <이벤트 로그 마지막 줄>" → 파이프라인 속행.

## 5. baton 선택 연동

계층 분리: **baton = 세션 간 내비게이션 레이어, fable-team state = 파이프라인 상태 레이어.** 상태 중복 저장 없이 포인터만 연결.

- **감지**: `baton:save`/`baton:resume` 가용 여부(또는 `~/.baton/current/` 존재).
- **있으면**: §2 재시작·피처 종결 시점에 `baton:save` 추가 호출하되 NEXT.md엔 상태 본문이 아니라 **한 줄 포인터만**: `fable-team 파이프라인 진행 중 — .fable-team/state/ACTIVE 참조, 재트리거 시 자동 복원`. baton:resume가 이 줄을 노출 → 사용자가 fable-team 재트리거 → §4가 실제 복원.
- **없으면**: 기능 저하 없음 — §4는 state 파일만 의존. ACTIVE 감지(§4-1)가 발견 편의를 자체 대체.
- **worktree 정합**: baton은 `{worktree}/.baton/handoff/`, fable-team은 `<project 루트>/.fable-team/` 기준 — worktree 안에서 돌면 둘 다 그 worktree 루트에 생겨 자연 정합, 별도 처리 불요.

## 검증 시나리오

1. **강제 재시작 복원**: stage 3 진행 중 세션 강제 종료 → 새 세션 트리거 → ACTIVE 감지 → state Read → 산출물 검증 통과 → implementer**만** 재스폰, stage 0-2 재실행 **0회**, 최종 산출물이 무중단 실행과 동등.
2. **compact 후 원장 정합**: stage 2→3 경계에서 /compact → 첫 행동이 state.md re-Read, compact 전후 원장·카운터 diff 없음, 정상 속행.
3. **세션 넘는 approve loop 한도**: 라운드 1 CHANGES_REQUESTED → 재기획 → 재시작(implementer 사망) → 새 세션 복원 stage 3 재스폰 → 라운드 2 다시 CHANGES_REQUESTED → da_round가 세션 넘어 2로 승계 → **한도 초과 → 자동 진행 금지 + 에스컬레이션**(라운드 3 자동 진입하면 실패).

## 리스크·미결

- **/clear 후 in-process teammate 생존 미실측** — 보수적으로 "clear 전 전원 해산" 강제. 생존 실측 시 완화 가능(이득 작아 우선순위 낮음).
- **자동 컴팩션이 워커 통지 대기 중 발생 시 통지 유실 가능성** — write-through + re-Read + Monitor 폴링(jsonl 직접 감시)이 이중 방어이나 통지 채널의 컴팩션 내성은 미검증.
- **ctx % 자동 측정 수단 부재** — 표준 API 없음. 단계 경계 확인 규율(+시스템 경고 의존)로 커버, 자동화 미결.
- **다중 피처 병렬 미지원** — ACTIVE 단일 포인터(단일 오케스트레이터 전제). 병렬 필요 시 ACTIVE 목록화 확장이 필요하나 현 스코프(피처 인터뷰 직렬) 밖.
- **stage 3 중단 시 부분 구현 잔재** — 멱등 계약으로 흡수하나 설계 밖 임시 파일이 남을 수 있음 → implementer 계약에 "중단 지시 수신 시 임시 산출물 정리 후 종료" 1줄 추가 권장.
