# fable-team 컨텍스트 관리 — 상태 외재화 + compact/clear/재시작 정책

핵심 원칙 한 줄: **컨텍스트는 캐시, 디스크가 SSOT.** 오케스트레이터 컨텍스트가 어느 시점에 증발해도 `.fable-team/state/`만으로 파이프라인이 복원돼야 한다.

## 왜 필요한가 (배경)

파이프라인 진행 기록(원장·라운드 카운터·워커 생존)이 오케스트레이터 컨텍스트 **안에만** 있으면 ① 자동 컴팩션 ② 세션 재시작(에이전트 정의 설치가 이미 필수 경계로 요구) ③ ctx 임계 증류로 예고 없이 소실된다. 소실되면 라운드 한도(monitoring-loop §5)가 무의미해지고, 완료 단계를 재실행하며, 최악의 경우 CHANGES_REQUESTED를 잊고 미승인 구현을 종결 보고한다(게이트 우회). 단계 간 전달이 이미 파일 경유인데 **진행 포인터만 휘발성**인 것이 구멍이다.

## 1. 상태 외재화 — 디렉토리 + 핸드오프 스펙

```
<project>/.fable-team/
  features/<slug>.md            # 피처 파일 (feature-interview 산출 — 파이프라인 형상 포함)
  features/design-<slug>-v<N>.md # 설계 파일 (planner 산출, 재기획마다 v+1 새 파일 — 경로를 이 위치로 명문화)
  state/ACTIVE                  # 활성 피처 slug 한 줄 (없으면 유휴)
  state/<slug>.state.md         # 핸드오프 SSOT (아래)
  state/<slug>/                 # 워커 산출물 보관함
    checker-<NN>.json           # checker 보고 (JSON 한 줄 그대로)
    impl-round<N>.md            # implementer 완료 보고 (IMPLEMENTED + 변경 파일 목록 — stage 3 실재 증거. <N> = 대응 설계 버전(구현 시점 planner_rounds), 축약 형상은 1)
    da-round<N>.md              # DA 판정 + 증거 (라운드별 — 첫머리에 검토한 설계 버전 `reviewed: v<M>` 명기, §4-5 복원 분기의 키)
    tester-round<N>.json        # tester 결과 (<N> = impl-round<N>과 동일 규칙 — 대응 설계 버전, 축약 형상은 1)
```

**`state/<slug>.state.md`** — YAML frontmatter(기계 판독) + 본문(사람/LLM 판독):

```markdown
---
slug: <slug>
pipeline: standard  # standard | abbrev(확인→구현→테스트) | check-only — feature-interview 확정 형상 (features/<slug>.md와 일치)
da: loop2           # loop2(stage 5 게이트) | review(stage 4 1회 판정만 — 게이트 아님, playbook 참조) | none — DA 강도 (형상의 일부)
stage: 3            # 0킥오프|1수집|2기획|3구현|4검증|5게이트|6종결 (형상에 없는 단계는 건너뜀)
status: running     # running | blocked(에스컬레이션 대기) | done
da_round: 0         # 게이트 라운드 — 라운드 디스패치 규칙(§1)로 증감 (한도 2. 예시=stage 3 게이트 미진입이라 0)
planner_rounds: 1   # 기획 라운드 — 동일 규칙 (한도 2)
respawns: {impl: 0, tester: 0, da: 0, checker: 0}   # failure 사유 재스폰만 카운트(한도 각 2) — 윈도우 압박 등 계획적 재스폰은 한도 비소모(이벤트 로그로 추적)
design: features/design-<slug>-v1.md   # 최신 설계 파일 (DESIGN_WRITTEN 수신 시에만 갱신)
brain_sessions: {da: none}   # agent-cli 브레인 session-id (디스크-백드 resume 자산 — 세션 넘어 유효)
cairn_task: none    # cairn 노드 전체 주소 <project>/<milestone>/<tid> (integrations on/required 시 — 롤백·complete 인자의 출처, integrations.md §1)
updated: 2026-07-02T14:30
---
## 원장
| 워커 | 경로 | 상태 | 마지막 신호 | 조치 |
|------|------|------|-------------|------|
| impl-02 | Agent | 🟢 작업중 | 14:28 중간보고 | — |

## 이벤트 로그 (최신 위, append-only)
- 14:30 stage 2→3 전이. design v1 → impl-02 스폰
- 14:24 planner DESIGN_WRITTEN features/design-<slug>-v1.md
```

**write-through 규율 — 다음 4개 이벤트마다 디스크 갱신(의무, "가능하면" 아님)**:

1. **단계 전이** (stage N 완료 → N+1 진입 직전) — 예외 없음. **stage 0 킥오프의 `state/ACTIVE`+state.md 생성, stage 6 종결의 `status: done` 기록+ACTIVE 제거도 이 이벤트에 포함** — ACTIVE는 복원의 유일한 진입점(§4-1)이라 생성·제거가 누락되면 §4 전체가 무의미하다.
2. **게이트/검증 디스패치·판정 수신** — 카운터(da_round/planner_rounds)는 디스패치 직전 갱신하되 **파일 실재로 열림/닫힘을 판정**한다(**라운드 디스패치 규칙**): **N≥1이고 현재 카운터 값 N의 산출물(planner: `design-<slug>-v<N>.md`, DA: `da-round<N>.md`)이 부재하면 열린 라운드 → 재증가 없이 번호 N을 재사용해 디스패치**(크래시·재시작 후의 재디스패치가 여기 해당 — 같은 논리 라운드 이중 과금 금지); **그 외(N=0 또는 산출물 실재=닫힌 라운드)는 +1 후 디스패치**. +1이 디스패치 전에 기록되므로 판정 대기 중 사망해도 라운드 소모는 승계된다. 판정(DA APPROVED·CHANGES_REQUESTED, tester ALL_PASS·FAIL) 원문은 `state/<slug>/` 파일로, state.md엔 결과 한 줄.
3. **워커 상태 변화** (스폰·완료·실패·재스폰·해산 + 중간보고 수신·STOP 교정·재기획 근거 접수 + agent-cli 브레인 session-id 발급·resume·fork) — 원장 행 갱신과 동시.
4. **에스컬레이션/블록** (status: blocked + 사유 이벤트 로그).

**쓰기 순서 불변식**: 산출물 파일을 먼저 완전히 기록한 뒤에만 stage 포인터·이벤트 로그를 전진시킨다 — 어느 시점에 죽어도 "포인터가 가리키는 단계까지의 산출물은 반드시 실재"가 §4 복원의 전제다.

이 4개가 monitoring-loop §4의 "보고 때마다 갱신"을 대체한다(컨텍스트 원장 → 디스크 원장).

**워커 산출물 외재화**: 워커의 "JSON 한 줄" 보고는 수신 즉시 `state/<slug>/`에 파일로 낙수(오케스트레이터가 Write) — implementer의 IMPLEMENTED 완료 보고(변경 파일 목록 포함)도 `impl-round<N>.md`로 동일하게 낙수(stage 3의 실재 증거). DA 판정+증거처럼 긴 것은 드라이버가 직접 `state/<slug>/da-round<N>.md`에 Write하고 경로만 보고 — planner 재기획 입력도 이 경로를 릴레이하므로 증거 본문이 오케스트레이터 컨텍스트에 실리지 않는다(컨텍스트 최소화 수칙과 합치).

**항상 디스크에 있어야 하는 상태(완결 목록)**: **ACTIVE 포인터**, 피처 파일, **파이프라인 형상(pipeline/da)**, 설계 파일(버전별), stage 포인터, 3종 카운터(da_round/planner_rounds/respawns), **브레인 세션 id(brain_sessions)**, **cairn_task 포인터(연동 on 시)**, 원장, 워커 산출물(판정·증거·구현 보고), 블록 사유. 이 밖의 것(워커 transcript, Workflow runId)은 복원에 **불필요**해야 한다 — runId는 이벤트 로그에 참고로만 기록하고 복원 시 신뢰하지 않는다(같은 세션 한정).

## 2. 오케스트레이터 컨텍스트 임계 정책

실측 트리거 우선순위: ① **HUD/statusline ctx%**(OMC HUD 등이 표시하면 1순위 실측값 — 매 단계 전이 시 확인 의무) ② **누적 토큰 절대 눈금**(아래 — HUD 부재 시에도 적용) ③ 자동 컴팩션 경고·발생 감지 + 단계 전이 자가점검(압박 징후).

**절대 토큰 눈금 (하드 룰 — 대형 모델(fable-5 등) 세션일수록 엄격 적용)**:
- **300k 토큰 = 경계 시작**: 다음 단계 경계에서 /compact 또는 증류를 **예약**하고 사용자에게 고지.
- **500k 토큰 = 강제**: 신규 단계 진입 금지 — 현 단계 마무리 즉시 증류·재시작.
- **HUD ctx 80% = 재시작·증류 준비**(다음 경계에서 실행), **90%+ = CRITICAL**: 단계 경계를 기다리지 않는다 — 진행 중단, write-through 최신화 후 **즉시 증류**. 90%에서 경계를 기다리다 자동 컴팩션에 강제당한 실사례(2026-07-03, ctx 92% 무증류) 재발 금지.

**컨텍스트 하이진 스캔 (300k 경계 도달 시 시작 + 증류 전 의무)**: 비대 파일은 ctx의 숨은 폭탄이다 — 실수로 Read/Grep 한 번에 수십 k 토큰이 증발하고, 다음 세션 부팅이 그대로 밟는다(실사례 2026-07-03: 러너 로그 17개 = 17GB). 절차:
1. **스캔**: 작업 경로에서 대용량 후보 실측 — `find <작업경로> -type f -size +50M -mtime -7`(로그·jsonl·출력 낙수·evidence·`state/<slug>/` 산출물 위주) + `du -sh` 상위.
2. **활성 판별**: mtime·`lsof`로 활성 쓰기 확인 — **활성 파일은 건드리지 않는다**.
3. **사용자 인터뷰(의무)**: 발견 목록(경로·크기·최근 접근)을 제시하고 AskUserQuestion — [무손실 압축(gzip — `zcat` 열람 유지, 로그류 90%+ 절감)] / 아카이브 이동 / 보존 / 항목별 선택. **삭제는 선택지에 올리지 않는다**(사용자가 명시 요구할 때만). 압축은 백그라운드 가능 — 완료 시 최종 용량 보고.
4. **증류 전 강화**: 다음 세션이 열리기 전 정리 완료가 원칙. headless(인터뷰 불가)면 조치 없이 목록만 이벤트 로그/핸드오프에 기록하고 다음 대화형 세션에 위임.

| 수단 | 트리거 | 부작용 | 사전·사후 조치 |
|------|--------|--------|----------------|
| **/compact** | **300k 토큰 또는 HUD ~70%** && 진행 중 → **다음 단계 경계**에서 | 요약 손실(원장 세부 뭉개짐). Agent 열린 워커는 생존 | 사전: write-through 최신 확인. 사후: **첫 행동 = state.md re-Read로 원장 재적재** |
| **/clear** | 피처 **종결(stage 6) 후** 다음 피처 전, 같은 세션 && 에이전트 정의 변경 없음 | 대화 전체 소실. 열린 워커 생존 미보장 | 사전: status=done + 열린 워커 전원 해산. 사후: 신규 피처 인터뷰부터 |
| **세션 재시작(증류)** | ① **500k 토큰 또는 HUD 80%**(90%+는 경계 대기 없이 즉시) ② compact 1회 후 재차 압박(요약의 요약 금지) ③ 에이전트 .md 설치/수정 ④ 세션 오염(400 반복) | Agent 워커 전멸, resumeFromRunId 무효, 대화 소멸. 디스크 유지 | 사전: state.md 최신화 + ACTIVE 확인 + **(integrations on/required && 워크트리 파이프라인) `baton save` — NEXT.md 한 줄 포인터(integrations.md §2 규칙. baton은 워크트리 phase 안에서만 save 가능 — main root 메타 작업은 해당 없음, 실측 2026-07-03)** + "재시작 후 fable-team 재트리거" 안내. 사후: §4 복원 |

**단계 경계 규칙**: compact/clear/재시작은 **반드시 단계 경계에서** — 단계 중간엔 워커 통지 대기가 걸려 유실 위험. ctx 확인 시점은 매 단계 전이 시(write-through와 같은 타이밍). 안전 경계 우선순위: **stage 2→3(설계 확정 직후)** > stage 5→6(게이트 통과 직후) > 기타. stage 3 진행 중 500k/HUD 80% 도달 시: implementer에 SendMessage로 현 시점 마무리 지시 → 원장에 "구현 중단·재개 필요" 기록 → 재시작(복원은 §4-5 단계 재실행이 흡수).

**자동 컴팩션 방어**: 자동 컴팩션은 예고 없이 온다 — write-through가 유일한 방어선이라 §1의 4개 갱신 시점이 의무다. 컴팩션 인지 순간(요약 시스템 메시지 감지) 즉시 state.md re-Read.

## 3. 워커 컨텍스트 관리

**대원칙: 열린 워커는 최적화이지 필수 경로가 아니다.** 파일 릴레이 덕에 모든 워커는 무상태 재스폰 가능해야 하며, 열린 워커에만 있는 상태(파일에 없는 결정·맥락) 생성을 금지한다.

**워커 자기 윈도우 정책**: 워커 자신의 ctx %도 오케스트레이터가 폴링할 수 없다(오케스트레이터 ctx와 동형) — 따라서 장수명 워커(implementer, da 드라이버)의 계약(템플릿)에 self-checkpoint를 넣는다: **자기 윈도우 압박을 자각하면 진행분을 파일로 flush하고 team-lead에 `WINDOW_PRESSURE` 1줄 보고 후 지시 대기.** 오케스트레이터는 flush 확인 후 해산·재스폰한다(계획적 재스폰 — respawns 한도 비소모). 일회성 워커(checker/planner/tester)와 fresh 프로세스는 누적이 없어 해당 없음.

**agent-cli 브레인 세션 — 4번째 버킷(resume 채택)**: codex 등 agent-cli 브레인(크루 드라이버가 구동하는 세션형 하네스 포함 — omx 등, `crew/crew-support.md`)은 Agent(세션 종속)·Workflow(무상태 일회성)와 달리 **디스크-백드 세션**이라 session-id로 resume 가능하고, 오케스트레이터 세션 사망을 넘어 생존하는 유일한 연산-보유 세션이다. 운용 규칙: ① DA approve loop 라운드 2+는 새 one-shot 재인라인 대신 **resume 체인**(예: `codex exec resume <session-id>`)으로 재개 — 라운드 1 지적을 기억해 적대검증이 강해지고 재인라인 토큰이 절약된다. ② session-id는 발급 즉시 state.md `brain_sessions`에 write-through(세션을 넘는 복원 자산). ③ 브레인 윈도우 압박 시 **요약-후-fork**: 현 세션 요약을 새 세션 첫 프롬프트로 인계하고 brain_sessions id 교체.

| 워커 | 열어두는 구간 | 닫는 시점 |
|------|--------------|-----------|
| checker | 열지 않음 | 보고 수신 즉시 (후속은 재스폰이 더 싸고 안전) |
| implementer | stage 3 ~ 게이트 종료 (approve loop 재라운드용) | **APPROVED** 또는 다음 라운드 장기 지연 예상 시(참고 ~15분 — 판단 가이드, 측정 규범 아님) 조기 해산, `WINDOW_PRESSURE` 보고 시 flush 확인 후 해산·재스폰(한도 비소모) |
| da (Agent 경로) | approve loop 동안 | APPROVED / 라운드 한도 초과 / `WINDOW_PRESSURE`(브레인 세션은 resume/fork로 승계되므로 드라이버만 교체) |
| planner/tester (Workflow) | 해당 없음 (일회성) | — |

공통: **stage 5→6 전이 = 전원 해산 지점.** 에스컬레이션(status=blocked) 진입 시에도 전원 해산 — 대기 중 열린 워커는 낭비이자 세션 리스크.

**approve loop 라운드 간 상태 보존**: 라운드 상태는 전부 파일에 있다 — `da_round`(state.md) + `state/<slug>/da-round<N>.md`(판정·증거) + `features/design-<slug>-v<N>.md`(재기획 시 planner가 **v+1 새 파일**로 Write, frontmatter `design:` 갱신 — v1/v2가 파일 존재로 구분된다). implementer가 살아있으면 SendMessage "설계 파일 갱신됨(v2 경로 전달). 재Read 후 차이만 구현" — 빠른 경로. 죽었으면 재스폰(같은 계약이라 결과 동일).

**재스폰 규약(번호 절차)**:

1. 원장에서 사망/해산 확인 → `respawns` +1 (**failure 사유만** — WINDOW_PRESSURE 등 계획적 재스폰은 한도 비소모, 이벤트 로그로만 추적), **한도 2** 초과 시 재스폰 대신 에스컬레이션.
2. 같은 역할 **새 이름**(`impl-02`→`impl-03`) — 에이전트 타입 캐시 함정 회피 겸 추적성.
3. 스폰 프롬프트 = 표준 계약(파일 경로 + 보고 형식)**만**. 이전 대화 요약 전달 금지(파일이 SSOT, 요약 전달은 열린-워커-의존 설계로의 퇴행).
4. implementer 재스폰 계약 문구: "구현 SSOT를 Read하고 **현재 코드와의 차이를** 구현" — 구현 SSOT는 표준 형상에선 설계 파일, **축약 형상(설계 단계 없음)에선 피처 파일(features/<slug>.md — 성공 기준 포함)**. 부분 구현에서 재개해도 멱등(SSOT = 목표 상태 선언).
5. Workflow 워커: 완료 판정은 runId 캐시가 아니라 **산출물 파일 존재**로만(design-<slug>-v<N>.md 존재 = 해당 기획 라운드 완료).

## 4. 세션 재시작 복원 절차

새 세션에서 fable-team 트리거 시, 피처 인터뷰 **이전에** 수행:

1. `<project>/.fable-team/state/ACTIVE` 확인. 없으면 — integrations on/required && main 워크트리 내부면 **discovery 선행**(baton status + `.worktrees/*` glob — SKILL.md 부팅 시퀀스 1·integrations.md §3), 그래도 없으면 → 신규 플로우.
2. 있으면 slug 획득 → `state/<slug>.state.md` Read → frontmatter(**pipeline/da 형상** + stage/status/카운터) + 원장 적재. `status: done`이면 ACTIVE 제거 후 신규 플로우. **이후 4~6의 검증·분기는 전부 형상 기준** — 형상에 없는 단계(abbrev의 기획, `da: none`의 게이트 전부, `da: review`의 stage 5 게이트 — review 판정 파일은 stage 4 산출물)는 산출물 검증·재실행 대상에서 제외한다(사용자가 opt-out한 워커를 복원이 되살리면 실패). 형상 필드가 없거나 `features/<slug>.md`와 불일치하면 피처 파일 쪽을 신뢰하고 state를 교정.
3. `status: blocked`면 이벤트 로그의 블록 사유를 사용자에게 제시하고 결정부터 받는다(자동 재개 금지).
4. **산출물 실재 검증**(state는 선언, 파일이 증거): stage 이하 완료 단계 중 **형상에 포함된 단계만** 산출물 존재 확인 — 피처 파일(0), checker JSON(1), `design-<slug>-v<M>.md`(2 — **M = 실재하는 최대 설계 버전**, 카운터가 아니라 파일이 증거), `impl-round<M>.md`(3 — 현재 최대 설계 버전 M 대응만 유효, 이전 버전 파일은 stale로 무시. 축약 형상은 impl-round1), `tester-round<M>`/da 라운드 파일(4-5). **불일치 시 산출물이 실재하는 마지막 단계로 stage 롤백**(예: state=3인데 설계 파일 없음 → stage 2부터. 단 abbrev 형상이면 설계 파일은 검증 대상이 아니므로 checker JSON까지만 확인하고 3부터).
5. 재개 단계 결정: 검증된 **진행 중이던 단계를 처음부터 재실행**(단계 원자성 — implementer 계약이 멱등이라 안전). stage 5 도중이면 **파일 존재로 분기**: 마지막 `da-round<K>.md`의 판정과 그 파일 첫머리의 **검토 설계 버전 `reviewed: v<M>`**(필드 부재 시 실재하는 마지막 `impl-round<M>`의 M으로 도출)을 읽어 — CHANGES_REQUESTED && `design-<slug>-v<M+1>.md` **없음** → stage 2 재진입(재기획 전), **있음** → stage 3(수정 설계 완료). **DA 라운드 번호 K와 설계 버전 M은 독립 축**(mid-impl 재기획은 K를 움직이지 않고 M만 올린다) — K 기반 `v<K+1>` 산술 금지.
6. **필요한 워커만 재스폰**: 재개 단계 워커만. 완료 단계 워커(checker 등)는 산출물이 파일에 있으므로 재스폰하지 않는다. 카운터는 state.md 값을 **승계**(da_round=1이었으면 라운드 2부터 — 한도가 세션을 넘어 유효). 단 **산출물 없는 "열린 라운드"**(디스패치로 +1 기록됐으나 대응 `design-v<n>`/`da-round<n>` 부재)는 §1 라운드 디스패치 규칙에 따라 복원 재디스패치 시 **재증가 없이 같은 번호로 재개**한다(같은 논리 라운드를 이중 과금하면 크래시만으로 오탐 에스컬레이션). 복원에 따른 워커 재스폰은 계획적 재스폰(세션 사망 ≠ 워커 failure)으로 respawns 한도 비소모 — 이벤트 로그로만 추적. **`brain_sessions`에 유효 session-id가 있으면 agent-cli 브레인은 재스폰이 아니라 resume으로 재개**(라운드 기억 승계 — 드라이버 워커만 새로 스폰).
7. 사용자에게 1회 재개 보고: 복원된 원장 + "stage N부터 재개, 사유: <이벤트 로그 마지막 줄>" → 파이프라인 속행.

## 5. baton·cairn 연동 — `references/integrations.md` 참조 (프로파일 게이팅)

계층 분리(불변): **baton = 워크트리·세션 간 내비게이션, cairn = 프로젝트 작업 원장, fable-team state = 파이프라인 상태(유일 SSOT).** 상태 중복 저장 없이 포인터만 연결 — cairn에서 FT 피처는 "열림→닫힘" 2상태만 가진다.

- 연동 레벨(off/on/required)·훅 절차(킥오프/종결/재시작/블록·언블록)·CWD 규칙·버저닝 절연은 전부 `integrations.md`가 SSOT.
- **off/미설치**: 기능 저하 없음 — §4는 state 파일만 의존, ACTIVE 감지(§4-1)가 발견 편의를 자체 대체.
- NEXT.md 원칙 유지: 상태 본문이 아니라 **한 줄 포인터만**("fable-team 파이프라인 — .fable-team/state/ACTIVE 참조") — 발견 채널은 복원 재료가 될 수 없다(이중 복원 구조적 방지).
- **worktree 정합**: baton은 `{worktree}/.baton/`, fable-team은 그 worktree 루트 `.fable-team/` — 자연 정합. 단 **cairn 원장은 프로젝트 전역**(`$MAIN_ROOT/.cairn`)이라 cairn 명령은 반드시 루트 고정 서브셸로(integrations.md §공통 — 위반 시 원장 파편화).

## 검증 시나리오

1. **강제 재시작 복원**: stage 3 진행 중 세션 강제 종료 → 새 세션 트리거 → ACTIVE 감지 → state Read → 산출물 검증 통과 → implementer**만** 재스폰, stage 0-2 재실행 **0회**, 최종 산출물이 무중단 실행과 동등.
2. **compact 후 원장 정합**: stage 2→3 경계에서 /compact → 첫 행동이 state.md re-Read, compact 전후 원장·카운터 diff 없음, 정상 속행.
3. **세션 넘는 approve loop 한도**: 라운드 1 CHANGES_REQUESTED → 재기획 → 재시작(implementer 사망) → 새 세션 복원 stage 3 재스폰 → 라운드 2 다시 CHANGES_REQUESTED → da_round가 세션 넘어 2로 승계 → **한도 초과 → 자동 진행 금지 + 에스컬레이션**(라운드 3 자동 진입하면 실패).
4. **축약 형상 복원**: 파이프라인 축약(확인→구현→테스트) + `da: none` 피처가 stage 3 진행 중 사망 → 새 세션 복원. 복원이 planner를 스폰하거나 `da-round<N>.md`를 기다리면 **실패** — 형상 게이팅(§4-2)에 따라 checker JSON 확인 → 구현 재실행(구현 SSOT = 피처 파일)으로 직행해야 통과.
5. **브레인 세션 resume 승계**: DA 라운드 1 CHANGES_REQUESTED 후 세션 재시작 → 복원 → 라운드 2 재판정이 `brain_sessions`의 id로 **resume 체인**으로 수행돼 라운드 1 지적 맥락을 기억(새 one-shot으로 전체 재인라인하면 실패는 아니나 비최적 — resume 실패 시에만 one-shot 폴백 + 이벤트 로그 기록).
6. **크래시-중-디스패치 이중 과금 방지**: stage 2 최초 planner 디스패치 직후(planner_rounds=1 기록, DESIGN_WRITTEN 전) 세션 사망 → 복원 → 재디스패치. design-v1 부재 = 열린 라운드 → planner_rounds **1 유지**로 v1 산출, 이후 실 재기획 1회에 2로 정상 진행 — 복원 재디스패치가 2를 만들거나 실 재기획 1회 만에 한도 초과 에스컬레이션이 뜨면 **실패**(stage 5 디스패치 직후 사망의 da_round 동형 케이스 포함).
7. **mid-impl 재기획 크로스오버 복원**: v1 구현 중 "설계 틀림" 근거 → 재기획 v2(planner_rounds=2, da_round=0 유지) → v2 구현 → DA 라운드 1이 v2 검토, CHANGES_REQUESTED(`da-round1.md`에 `reviewed: v2`) → 재기획 디스패치 전 사망 → 복원. 분기가 M=2를 읽어 design-v3 부재 → **stage 2** 선택해야 통과 — design-v2 존재를 이유로 stage 3(거부된 v2 재구현)으로 가면 **실패**(게이트 우회).

## 리스크·미결

- **/clear 후 in-process teammate 생존 미실측** — 보수적으로 "clear 전 전원 해산" 강제. 생존 실측 시 완화 가능(이득 작아 우선순위 낮음).
- **자동 컴팩션이 워커 통지 대기 중 발생 시 통지 유실 가능성** — write-through + re-Read + Monitor 폴링(jsonl 직접 감시)이 이중 방어이나 통지 채널의 컴팩션 내성은 미검증.
- **ctx % 프로그래밍적 측정 API 부재** — 단 HUD/statusline(OMC HUD 등)이 있으면 ctx%·토큰이 실측 가능하고, §2가 이를 1순위 트리거 + 절대 토큰 눈금(300k/500k)으로 규범화. HUD 부재 환경은 토큰 눈금 + 자가점검으로 커버.
- **WINDOW_PRESSURE 자가탐지는 best-effort** — 워커가 압박을 자각 못 하고 죽을 수 있음. 그 경우 failure 재스폰 경로(파일 SSOT + 멱등 계약)가 안전망 — 자가탐지는 최적화이지 유일 방어선이 아니다.
- **다중 피처 병렬 미지원** — ACTIVE 단일 포인터(단일 오케스트레이터 전제). 병렬 필요 시 ACTIVE 목록화 확장이 필요하나 현 스코프(피처 인터뷰 직렬) 밖.
- **stage 3 중단 시 부분 구현 잔재** — 멱등 계약으로 흡수하나 설계 밖 임시 파일이 남을 수 있음 → implementer 계약(템플릿)에 "중단 지시 수신 시 임시 산출물 정리 후 종료" 반영됨.
