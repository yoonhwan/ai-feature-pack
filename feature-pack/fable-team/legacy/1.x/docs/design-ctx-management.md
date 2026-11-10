# Design: fable-team 컨텍스트 관리 — 상태 외재화 + compact/clear/재시작 정책

- 대상: `feature-pack/fable-team/skill/` (SKILL.md + references/ 신규 문서 `context-management.md` 1건, monitoring-loop.md §4 개정 1건)
- 전제(실측): ① Agent 워커는 세션 종속(세션 사망=워커 사망) ② Workflow는 무상태 일회성(resumeFromRunId는 같은 세션 한정) ③ 디스크 파일은 세션을 넘어 생존 ④ **agent-cli 브레인 세션(codex/cursor 등)은 디스크-백드로 session-id resume이 가능해 오케스트레이터 세션 사망을 넘어 생존** — 윈도우를 유지하는 유일한 연산-보유 세션(resume 채택, §3). 에이전트 .md 반영은 세션 재시작 경계.

> 개정: 라운드 카운터·복원 분기 산술은 `design-round-integrity.md`로 개정됨 — 정본은 `skill/references/context-management.md`.

## 원인 분석

fable-team의 유일한 파이프라인 진행 기록인 상태 원장(monitoring-loop.md §4)이 오케스트레이터 컨텍스트 **안에만** 존재한다. 그런데 이 컨텍스트는 세 가지 경로로 예고 없이 소실된다: ① 자동 컴팩션(요약 과정에서 원장 세부·라운드 카운터가 뭉개짐), ② 세션 재시작(에이전트 정의 설치가 이미 재시작을 **필수 경계**로 요구하므로 회피 불가능한 정상 플로우), ③ ctx 임계 도달 시 증류(사용자 표준 70/80%). 원장이 사라지면 "지금 stage 몇인지, DA 라운드 몇 회째인지, 어느 워커가 살아있는지"를 아무도 모른다 — 라운드 한도(§5)는 무의미해지고(무한 루프 방어 붕괴), 완료된 checker/architect 단계를 통째로 재실행하며(토큰 낭비), 최악의 경우 CHANGES_REQUESTED 상태를 잊고 미승인 구현을 종결 보고한다(게이트 우회). 단계 간 전달이 이미 파일 경유인 아키텍처에서 **진행 포인터만 휘발성**인 것이 이 설계 구멍의 본질이다.

## 해결 설계

핵심 원칙 한 줄: **컨텍스트는 캐시, 디스크가 SSOT.** 오케스트레이터 컨텍스트가 어느 시점에 증발해도 `.fable-team/state/`만으로 파이프라인이 복원돼야 한다.

### 1. 상태 외재화 원칙 — 핸드오프 파일 스펙

**디렉토리 구조** (기존 `.fable-team/features/`에 `state/` 추가):

```
<project>/.fable-team/
  features/<slug>.md            # 피처 파일 (기존 — 파이프라인 형상 포함)
  features/design-<slug>-v<N>.md # 설계 파일 (재기획마다 v+1 새 파일 — 경로를 이 위치로 명문화)
  state/ACTIVE                  # 활성 피처 slug 한 줄 (없으면 유휴 상태)
  state/<slug>.state.md         # 핸드오프 SSOT (아래 스펙)
  state/<slug>/                 # 워커 산출물 보관함
    checker-<NN>.json           # checker 보고 (JSON 한 줄 그대로)
    impl-round<N>.md            # implementer 완료 보고 (IMPLEMENTED + 변경 파일 목록 — stage 3 실재 증거. <N> = 대응 설계 버전, 축약 형상은 1)
    da-round<N>.md              # DA 판정 + 증거 (라운드별 — 첫 줄에 `reviewed: v<M>`, M=디스패치 시점 설계 버전)
    tester-round<N>.json        # tester 결과
```

**`state/<slug>.state.md` 형식** — YAML frontmatter(기계 판독) + 본문(사람/LLM 판독):

```markdown
---
slug: <slug>
pipeline: standard  # standard | abbrev(확인→구현→테스트) | check-only — feature-interview 확정 형상
da: loop2           # loop2(stage 5 게이트) | review(stage 4 1회 판정만 — 게이트 아님) | none — DA 강도 (형상의 일부)
stage: 3            # 0킥오프|1수집|2기획|3구현|4검증|5게이트|6종결 (형상에 없는 단계는 건너뜀)
status: running     # running | blocked(에스컬레이션 대기) | done
da_round: 0         # 게이트 라운드 — DA 디스패치 시점에 +1 (한도 2. 예시는 stage 3 = 게이트 전이라 0)
architect_rounds: 1   # 기획 라운드 — architect 디스패치 시점에 +1 (한도 2)
respawns: {impl: 0, tester: 0, da: 0, checker: 0}   # failure 사유 재스폰만 카운트(한도 각 2) — 윈도우 압박 등 계획적 재스폰은 한도 비소모
design: features/design-<slug>-v1.md   # 최신 설계 파일 (DESIGN_WRITTEN 수신 시에만 갱신)
brain_sessions: {da: none}   # agent-cli 브레인 session-id (디스크-백드 resume 자산 — 세션 넘어 유효)
updated: 2026-07-02T14:30
---
## 원장
| 워커 | 경로 | 상태 | 마지막 신호 | 조치 |
|------|------|------|-------------|------|
| impl-02 | Agent | 🟢 작업중 | 14:28 중간보고 | — |

## 이벤트 로그 (최신 위, append-only)
- 14:30 stage 2→3 전이. design v1 → impl-02 스폰
- 14:24 architect DESIGN_WRITTEN features/design-<slug>-v1.md
```

**갱신 시점 (write-through 규율)** — monitoring-loop.md §4의 "보고 때마다 갱신"을 "다음 4개 이벤트마다 **디스크 갱신**"으로 개정:

1. **단계 전이 시** (stage N 완료 → N+1 진입 직전) — 필수, 예외 없음. **stage 0 킥오프의 `state/ACTIVE`+state.md 생성, stage 6 종결의 `status: done` 기록+ACTIVE 제거도 이 이벤트에 포함**(ACTIVE는 복원의 유일한 진입점).
2. **게이트/검증 디스패치·판정 수신 시** — 카운터(da_round/architect_rounds)는 **디스패치 시점에 +1 기록**, 판정(DA APPROVED·CHANGES_REQUESTED, tester ALL_PASS·FAIL) 원문은 `state/<slug>/` 산하 파일로, state.md에는 결과 한 줄.
3. **워커 상태 변화 시** (스폰·완료·실패·재스폰·해산 + 중간보고 수신·STOP 교정·재기획 근거 접수 + agent-cli 브레인 session-id 발급·resume·fork) — 원장 행 갱신과 동시.
4. **에스컬레이션/블록 시** (status: blocked + 사유 이벤트 로그).

**쓰기 순서 불변식**: 산출물 파일을 먼저 완전히 기록한 뒤에만 stage 포인터·이벤트 로그를 전진시킨다 — "포인터가 가리키는 단계까지의 산출물은 반드시 실재"가 복원의 전제.

**워커 산출물 외재화**: 워커 보고 "JSON 한 줄"은 수신 즉시 `state/<slug>/`에 파일로 낙수(오케스트레이터가 Write). DA 판정+증거처럼 긴 것은 워커(드라이버)가 직접 `state/<slug>/da-round<N>.md`에 Write하고 경로만 보고 — architect 재기획 입력도 이 경로를 릴레이하므로 오케스트레이터 컨텍스트에 증거 본문이 실리지 않는다(컨텍스트 최소화 수칙과 합치).

**항상 디스크에 있어야 하는 상태의 완결 목록**: **ACTIVE 포인터**, 피처 파일, **파이프라인 형상(pipeline/da)**, 설계 파일(버전별), stage 포인터, 3종 카운터(da_round/architect_rounds/respawns), **브레인 세션 id(brain_sessions)**, 원장, 워커 산출물(판정·증거·구현 보고), 블록 사유. 이 목록 밖의 것(워커 transcript, Workflow runId)은 복원에 **불필요**해야 한다 — runId는 이벤트 로그에 참고로 기록하되 복원 시 신뢰하지 않는다(같은 세션 한정이므로).

### 2. 오케스트레이터 컨텍스트 임계 정책

ctx %는 선제 측정 API가 없다(리스크 절) — 아래 %수치는 **참고 기준(정성 판단 눈금)**이고, 실측 가능한 실행 트리거는 ① **자동 컴팩션 경고·발생 감지** ② **매 단계 전이 시점의 자가점검** 두 가지다.

| 수단 | 트리거 | 부작용 | 사전·사후 조치 |
|------|--------|--------|----------------|
| **/compact** | 압박 징후(참고 ~70%) && 파이프라인 진행 중 → **다음 단계 경계**에서 실행 | 요약 손실(원장 세부 뭉개짐). Agent 열린 워커는 생존 | 사전: write-through 최신 확인. 사후: **첫 행동 = state.md re-Read로 원장 재적재** |
| **/clear** | 피처 **종결(stage 6) 후** 다음 피처 시작 전, 같은 세션 계속 && 에이전트 정의 변경 없음 | 대화 전체 소실. 열린 워커 생존 미보장 | 사전: status=done 기록 + 열린 워커 전원 해산. 사후: 신규 피처 인터뷰부터 |
| **세션 재시작(증류)** | ① 압박 심각(참고 ~80%) ② compact를 이미 1회 한 뒤 재차 압박(요약의 요약 금지) ③ 에이전트 .md 설치/수정 필요 ④ 세션 오염(400 반복 등) | Agent 워커 전멸, resumeFromRunId 무효, 대화 소멸. 디스크는 유지 | 사전: state.md 최신화 + ACTIVE 확인 + 사용자에게 "재시작 후 fable-team 재트리거" 안내. 사후: §4 복원 절차 |

**단계 경계 규칙**: compact/clear/재시작은 **반드시 단계 경계에서** — 단계 중간엔 워커 통지(idle/task-notification) 대기가 걸려 있어 유실 위험. ctx 확인 시점은 매 단계 전이 시(write-through와 같은 타이밍). 안전 경계의 우선순위: **stage 2→3(설계 파일 확정 직후)** > stage 5→6(게이트 통과 직후) > 기타 경계. stage 3(구현) 진행 중 압박 심각(참고 ~80%)이면: implementer에게 SendMessage로 현 시점 커밋/중간 산출 마무리를 지시 → 원장에 "구현 중단·재개 필요" 기록 → 재시작(복원 시 §4-4의 단계 재실행 규칙이 흡수).

**자동 컴팩션 방어**: 자동 컴팩션은 예고 없이 온다 — write-through 규율이 유일한 방어선이므로 §1의 갱신 시점 4개는 "가능하면"이 아니라 **의무**다. 컴팩션 발생을 인지한 순간(요약 시스템 메시지 감지) state.md re-Read.

### 3. 워커 컨텍스트 관리

**대원칙: 열린 워커는 최적화이지 필수 경로가 아니다.** 파일 릴레이 덕에 모든 워커는 무상태 재스폰 가능해야 하며, 열린 워커에만 있는 상태(파일에 없는 결정·맥락)를 만드는 것을 금지한다.

**워커 자기 윈도우 정책**: 워커 자신의 ctx %도 오케스트레이터가 폴링할 수 없다 — 장수명 워커(implementer, da 드라이버) 계약(템플릿)에 self-checkpoint를 넣는다: 자기 윈도우 압박을 자각하면 진행분을 파일로 flush하고 team-lead에 `WINDOW_PRESSURE` 1줄 보고 후 지시 대기 → 오케스트레이터가 flush 확인 후 해산·재스폰(계획적 재스폰 — respawns 한도 비소모). 일회성 워커(checker/architect/tester)는 누적이 없어 해당 없음.

**agent-cli 브레인 세션 — 4번째 버킷(resume 채택)**: codex 등 agent-cli 브레인은 디스크-백드 세션이라 session-id로 resume 가능하고 오케스트레이터 세션 사망을 넘어 생존한다. ① DA approve loop 라운드 2+는 one-shot 재인라인 대신 **resume 체인**(`codex exec resume <session-id>`)으로 재개 — 라운드 1 지적 기억(적대검증 강화) + 토큰 절약. ② session-id는 발급 즉시 `brain_sessions`에 write-through(세션을 넘는 복원 자산). ③ 브레인 윈도우 압박 시 요약-후-fork(요약을 새 세션에 인계, id 교체).

**수명 정책 (역할별)**:

| 워커 | 열어두는 구간 | 닫는 시점 |
|------|--------------|-----------|
| checker | 열지 않음 | 보고 수신 즉시 (후속 확인은 재스폰이 더 싸고 안전) |
| implementer | stage 3 ~ 게이트 종료 (approve loop 재라운드용) | **APPROVED 시점** 또는 다음 라운드까지 15분+ 지연 예상 시(재기획 장기화) 조기 해산, `WINDOW_PRESSURE` 보고 시 flush 확인 후 해산·재스폰(한도 비소모) |
| da (Agent 경로) | approve loop 동안 | APPROVED / 라운드 한도 초과 시 / `WINDOW_PRESSURE`(브레인 세션은 resume/fork 승계 — 드라이버만 교체) |
| architect/tester (Workflow) | 해당 없음 (일회성) | — |

공통: **stage 5→6 전이 = 전원 해산 지점.** 에스컬레이션(status=blocked)으로 사용자 대기 진입 시에도 전원 해산 — 대기 중 열린 워커는 낭비이자 세션 리스크.

**approve loop 라운드 간 상태 보존**: 라운드 상태는 전부 파일에 있다 — `da_round` 카운터(state.md) + `state/<slug>/da-round<N>.md`(판정·증거) + `features/design-<slug>-v<N>.md`(재기획 시 architect가 **v+1 새 파일**로 Write, frontmatter `design:` 갱신 — v1/v2가 파일 존재로 구분). implementer가 살아있으면 SendMessage "설계 파일이 갱신됨(v2 경로 전달). 재Read 후 차이만 구현" — 빠른 경로. 죽었으면 재스폰 — 같은 계약이므로 결과 동일.

**재스폰 규약 (번호 절차)**:

1. 원장에서 사망/해산 확인 → state.md `respawns` 카운터 +1 (**failure 사유만** — WINDOW_PRESSURE 등 계획적 재스폰은 한도 비소모), **한도 2** 초과 시 재스폰 대신 에스컬레이션.
2. 같은 역할 **새 이름** (`impl-02` → `impl-03`) — 에이전트 타입 캐시 함정 회피 겸 원장 추적성.
3. 스폰 프롬프트 = 표준 계약(파일 경로 + 보고 형식)**만**. 이전 대화 요약 전달 금지 — 파일이 SSOT이고, 요약 전달은 열린-워커-의존 설계로의 퇴행이다.
4. implementer 재스폰 계약 문구: "구현 SSOT를 Read하고 **현재 코드와의 차이를** 구현" — 구현 SSOT는 표준 형상 = 설계 파일, 축약 형상(설계 단계 없음) = 피처 파일. 부분 구현 상태에서 재개해도 멱등(SSOT = 목표 상태 선언).
5. Workflow 워커: 완료 판정은 runId 캐시가 아니라 **산출물 파일 존재**로만 (design-<slug>-v<N>.md 존재 = 해당 기획 라운드 완료).

### 4. 세션 재시작 복원 절차

새 세션에서 fable-team 트리거 시, 피처 인터뷰 **이전에** 다음을 수행:

1. `<project>/.fable-team/state/ACTIVE` 존재 확인. 없으면 → 신규 플로우(기존 절차 그대로).
2. 있으면 slug 획득 → `state/<slug>.state.md` Read → frontmatter(**pipeline/da 형상** + stage/status/카운터) + 원장 적재. `status: done`이면 ACTIVE 제거 후 신규 플로우. **이후 4~6의 검증·분기는 전부 형상 기준** — 형상에 없는 단계(abbrev의 기획, `da: none`의 게이트 전부, `da: review`의 stage 5 게이트)는 검증·재실행 대상에서 제외(사용자가 opt-out한 워커를 복원이 되살리면 실패). 형상 필드가 없거나 피처 파일과 불일치하면 피처 파일을 신뢰하고 state를 교정.
3. `status: blocked`면 이벤트 로그의 블록 사유를 사용자에게 제시하고 결정부터 받는다 (자동 재개 금지).
4. **산출물 실재 검증** (state는 선언, 파일이 증거): stage 포인터 이하 완료 단계 중 **형상에 포함된 단계만** 산출물 존재를 확인 — 피처 파일(stage 0), checker JSON(1), `design-<slug>-v<architect_rounds>.md`(2), `impl-round<architect_rounds>.md`(3 — 현재 설계 버전 대응만 유효, 이전 라운드는 stale), tester/da 라운드 파일(4-5). **불일치 시 산출물이 실재하는 마지막 단계로 stage 롤백** (예: state=3인데 설계 파일 없음 → stage 2부터).
5. 재개 단계 결정: 검증된 stage의 **진행 중이던 단계를 처음부터 재실행** (단계 원자성 — implementer 계약이 멱등이므로 안전). stage 5 도중이었다면 **파일 존재로 분기**: 마지막 `da-round<N>.md`가 CHANGES_REQUESTED일 때 그 파일의 `reviewed: v<M>` 기준으로 `design-<slug>-v<M+1>.md` **없음** → stage 2 재진입(재기획 전), **있음** → stage 3(수정 설계 완료). da_round로 설계 버전을 산술하지 않는다(mid-impl 재기획이 lockstep을 깨므로 — 파일 기록이 증거).
6. **필요한 워커만 재스폰**: 재개 단계의 워커만. 완료 단계 워커(checker 등)는 산출물이 파일에 있으므로 재스폰하지 않는다. 카운터는 state.md 값을 **승계**한다 (da_round=1이었으면 라운드 2부터 — 한도가 세션을 넘어 유효). 단 **산출물 없는 "열린 라운드"**(디스패치로 +1 기록됐으나 대응 `design-v<n>`/`da-round<n>` 부재)는 복원 재디스패치 시 **재증가 없이 같은 번호로 재개**(이중 과금 = 크래시만으로 오탐 에스컬레이션). `brain_sessions`에 유효 session-id가 있으면 브레인은 재스폰이 아니라 **resume으로 재개**(라운드 기억 승계).
7. 사용자에게 1회 재개 보고: 복원된 원장 + "stage N부터 재개, 사유: <이벤트 로그 마지막 줄>" → 파이프라인 속행.

### 5. baton 선택 연동

계층 분리: **baton = 세션 간 내비게이션 레이어, fable-team state = 파이프라인 상태 레이어.** 상태를 중복 저장하지 않고 포인터만 연결한다.

- **감지**: `baton:save`/`baton:resume` 스킬 가용 여부 (또는 `~/.baton/current/` 존재).
- **있으면**: §2의 재시작(증류)·피처 종결 시점에 `baton:save`를 추가 호출하되, NEXT.md에는 상태 본문이 아니라 **한 줄 포인터만**: `fable-team 파이프라인 진행 중 — .fable-team/state/ACTIVE 참조, 재트리거 시 자동 복원`. baton:resume가 이 줄을 노출하면 사용자가 fable-team 재트리거 → §4 절차가 실제 복원을 수행.
- **없으면**: 기능 저하 없음 — §4 복원 절차는 state 파일만 의존하며 baton을 참조하지 않는다. baton이 제공하는 것은 "다음 세션이 fable-team 진행 중임을 알게 되는 발견 편의"뿐이고, 이는 §4-1의 ACTIVE 감지가 자체적으로 대체한다.
- worktree 정합: baton은 `{worktree}/.baton/handoff/` 기준, fable-team은 `<project 루트>/.fable-team/` 기준 — worktree 안에서 돌면 둘 다 그 worktree 루트에 생기므로 자연 정합, 별도 처리 불요.

## 검증 기준 (시나리오 5개)

1. **강제 재시작 복원**: stage 3(구현) 진행 중 세션 강제 종료 → 새 세션 fable-team 트리거 → 기대: ACTIVE 감지 → state Read → 산출물 검증 통과 → implementer**만** 재스폰(재개 보고에 복원 원장 포함), stage 0-2 재실행 **0회**, 최종 산출물이 무중단 실행과 동등.
2. **compact 후 원장 정합**: stage 2→3 경계에서 /compact(또는 자동 컴팩션 발생 시뮬) → 기대: 오케스트레이터 첫 행동이 state.md re-Read, compact 전후 원장·카운터 diff 없음, 이후 파이프라인 정상 속행.
3. **세션을 넘는 approve loop 한도**: 라운드 1 CHANGES_REQUESTED → 재기획 → 재시작 증류(implementer 사망) → 새 세션 복원으로 stage 3 재스폰 → 라운드 2 다시 CHANGES_REQUESTED → 기대: da_round가 세션을 넘어 2로 승계돼 **한도 초과 → 자동 진행 금지 + 에스컬레이션** 발동(라운드 3 자동 진입하면 실패).
4. **축약 형상 복원**: 파이프라인 축약(확인→구현→테스트) + `da: none` 피처가 stage 3 진행 중 사망 → 새 세션 복원 → 기대: 형상 게이팅에 따라 architect 스폰·da-round 대기 **없이** checker JSON 확인 → 구현 재실행(구현 SSOT = 피처 파일)으로 직행.
5. **브레인 세션 resume 승계**: DA 라운드 1 CHANGES_REQUESTED 후 세션 재시작 → 복원 → 기대: 라운드 2 재판정이 `brain_sessions` id의 resume 체인으로 수행돼 라운드 1 지적 맥락 유지(resume 실패 시에만 one-shot 폴백 + 이벤트 로그 기록).

## 리스크·미결

- **/clear 후 in-process teammate 생존 여부 미실측** — 설계는 보수적으로 "clear 전 전원 해산"을 강제. 생존이 실측 확인되면 완화 가능(단 완화 이득이 작아 우선순위 낮음).
- **자동 컴팩션이 워커 통지 대기 중 발생 시 통지 유실 가능성** — write-through + re-Read + 기존 Monitor 폴링(jsonl 직접 감시)이 이중 방어이나, 통지 채널 자체의 컴팩션 내성은 미검증. 검증 시나리오 2에 통지 대기 중 케이스 추가 여지.
- **ctx % 자동 측정 수단 부재** — 오케스트레이터가 자기 컨텍스트 %를 프로그래밍적으로 얻는 표준 API가 없어, §2가 %수치를 참고 기준으로 두고 자동 컴팩션 감지 + 단계 경계 자가점검을 실행 트리거로 규정. 자동화는 미결.
- **다중 피처 병렬 미지원** — ACTIVE는 단일 포인터(단일 오케스트레이터 전제라 락도 없음). 병렬 피처가 필요해지면 ACTIVE를 목록화하는 확장이 필요하나 현 스킬 스코프(피처 인터뷰가 직렬) 밖.
- **stage 3 중단 시 부분 구현 잔재** — 멱등 계약("SSOT와 현재 코드의 차이 구현")으로 흡수하지만, 설계 밖 임시 파일이 남을 수 있음 → implementer 계약(템플릿)에 "중단 지시 수신 시 임시 산출물 정리 후 종료" 반영됨.
