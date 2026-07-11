# 오케스트레이터 동적 배치 — 배치 패턴 카탈로그

> SSOT: 이 파일이 패턴 분류·투입 조합·킥오프 템플릿의 원본. 지침 재배포 없이 이 파일만 수정하면 운용 반영.

## 분류 신호

문제 텍스트의 성격으로 유형을 분류한다:
- 재현 절차/에러 로그 첨부 → **P-BUG**
- "추가/만들어" → **P-FEAT**
- "정리/구조" → **P-REFAC**
- "왜/확인/조사" → **P-ANLZ**
- "지금 당장/프로덕션" → **P-HOT**
- "돌려봐/검증" → **P-VRFY**
- *.md·설정·오타 (코드 2파일 이내) → **P-DOC**
- 모호하면 스텝3 추천에 2안 병기 후 사용자 선택.

## 패턴 카탈로그 (7종)

| # | 패턴 | 트리거 신호 | 투입 워커 (스폰 순서) | 파이프라인 형상 | DA 강도 |
|---|------|------------|----------------------|----------------|---------|
| P-BUG | 버그 수정 | 에러 로그·재현 절차·회귀 보고 | checker(로그·재현 경로 수집, 병렬 가능) → analyst(3자대조 진단) → [DIAGNOSIS만으로 수정 자명하면 planner 생략] → implementer → tester(repro→PASS) → da | 표준 | approve loop |
| P-FEAT | 피처 구현 | "추가·구현·만들어" + 스펙/한 줄 요구 | planner(설계 파일) → implementer → tester → da (+ checker는 자산 서치 필요 시만 선행) | 표준 | approve loop |
| P-REFAC | 리팩토링 | "정리·구조 개선·중복 제거" (행위 불변) | checker(영향 범위·참조 수집) → planner → implementer → tester(**회귀 전후 동일성**) → da | 표준 | approve loop |
| P-ANLZ | 분석·조사 | "왜·원인·확인·조사·아키텍처 파악" (변경 없음) | checker ×N(병렬 서치) → analyst(종합 진단) — implementer/tester/da **미스폰** | 보고 종결 | 없음 (선택: da review 1회) |
| P-HOT | 긴급 수정 | "지금·프로덕션·장애" + 원인 기지(旣知) | implementer + tester 직행(동시 스폰) → **da review 후행 1회**(비게이트 — 랜딩 차단 안 함, 판정만 기록) | 축약 | review (후행) |
| P-VRFY | 검증 전용 | "돌려봐·확인해줘·PASS 여부" (구현 완료물) | tester(+tester2 병렬 가능) → da review | 축약 | review |
| P-DOC | 문서·설정 | *.md·설정·오타 (코드 2파일 이내) | **워커 미스폰** — 오케 직접 처리 (orchestration-gate 허용 범위) | 없음 | 없음 |

> **v3 스폰 표기**: 위 "투입 워커"는 전부 **tmuxc 세션**(`.fable-team/bin/ft-tmux-spawn.sh --agent claude|codex --role <role>`)으로 스폰된다 — 완료는 파일 센티널(`ft-tmux-poll.sh` 판독), 오케 증류·재시작에도 생존(SKILL.md 「v3 스폰」). checker는 단명(done→`ft-tmux-kill.sh`), 그 외는 approve loop/재라운드 동안 상주하다 kill 또는 `#N+1` distill 승계.

### PM(ft-pm-memory) 개설 — 패턴별

| 패턴 | PM 개설 | 근거 |
|------|---------|------|
| P-BUG · P-FEAT · P-REFAC · P-HOT | **개설(상시)** | 코드 변경 형상 — 흐름 기억·cairn 대행·증류 브리핑 필요 |
| P-VRFY | 조건부 | 구현 완료물 검증 — 다회전·증류 예상 시만 |
| P-ANLZ (보고 종결) | 미개설 | check-only 성격 — 파이프라인 상태 원장 불요 |
| P-DOC | 미개설 | 오케 직접 처리 — 워커·PM 미스폰 |

PM은 **프로젝트당 1개**(피처 공유) — 이미 열린 `ft-pm-<proj>#0`가 생존하면 재사용(KICKOFF만 송신). 킥오프 훅에서 확보(integrations.md §1 스텝4).

## 운영 규칙 (4개)

### 1. 필요 워커만 스폰

패턴에 없는 워커는 대기 스폰조차 하지 않는다. 카탈로그가 곧 스폰 목록.

### 2. 실행 중 증원 (에스컬레이션 신호 — 자동 스폰 트리거)

- analyst 보고 `ESCALATE_TO_PLANNER: yes` → planner 투입 (P-BUG가 P-FEAT급 설계로 승격)
- tester `FAIL` 동일 케이스 2회 반복 → analyst 투입 (P-HOT/P-VRFY가 P-BUG로 승격)
- da `CHANGES_REQUESTED`에 설계 결함 명시 → planner 재회전
- 증원은 **같은 세션 선택 브레인**을 쓴다(재질문 금지). 증원 사실은 state.md에 1줄 기록.

### 3. 해산

Workflow 일회성 워커는 완료 즉시 자연 종료(해산 개념 없음). Agent 경로 장수명(드라이버·approve loop 대기)만 파이프라인 종결 시 오케가 명시 종료 — GC 훅은 ft-* 보호라 자동 수거 안 됨(네이밍 규약과 정합, 의도된 동작).

### 4. 패턴 이탈 허용

스텝3에서 사용자가 "da2도 붙여줘" 식 조정 가능 — 조정 결과를 그 피처의 형상으로 state.md에 기록. 카탈로그는 추천 기본값이지 락이 아니다.

---

## 킥오프 질문 템플릿 (7종)

> 오케가 분류 직후 AskUserQuestion 1개를 발사한다. `<>` 부분만 문제 텍스트로 채운다.
> 공통: `multiSelect: false`, `header: "배치"` (영문 세션이면 `"Crew"`).

### AskUserQuestion 스펙 준수 규칙

| 항목 | 규칙 |
|------|------|
| options 수 | **2~4개**. 패턴 고유 옵션 최대 3개 + 마지막 슬롯 `직접 조합` — 단 도구가 자유 입력(Other)을 기본 제공하는 하네스면 `직접 조합` 옵션을 생략하고 고유 옵션에 슬롯을 쓴다(install.json `ask_other_builtin`) |
| 첫 옵션 | label 끝에 ` (Recommended)` 접미 — 오직 첫 옵션에만 |
| multiSelect | **false 고정** — 배치는 단일 선택 |
| header | **"배치"** (2자). 영문 세션이면 "Crew" |
| label | 30자 이내 — 형상 요약은 description에 |
| description | 크루 체인(→ 표기) + DA 강도 + 발동 조건 한 줄 |
| question | 압축 보드 4줄 고정: `문제: <한 줄>` / `유형: <P-XXX> (<이유 한 구>)` / `산출: .fable-team/features/<slug>.md` / `연동: <워크트리·cairn 1줄 또는 "없음">` |

**모호 분류(2안 병기)**: ①=1순위 패턴 기본(Recommended), ②=2순위 패턴 기본을 옵션으로 병치. 유형 확정과 배치 선택이 질문 1개로 동시 해결.

**엔터 킥오프**: 첫 옵션이 기본 하이라이트이므로 엔터만 치면 ① 선택 = 즉시 킥오프. 어떤 옵션을 골라도 재확인 없이 즉시 킥오프 — 조정은 옵션에 내장. `직접 조합` 경로에서만 형상 1줄 재확인 1회 → 킥오프.

### P-BUG (버그 수정)

```yaml
question: |
  문제: <한 줄>
  유형: P-BUG (에러 로그/재현 절차 감지)
  산출: .fable-team/features/<slug>.md
  연동: <1줄>
options:
  - label: "P-BUG 기본 (Recommended)"
    description: "checker→analyst→implementer→tester→da approve loop(≤3R). planner는 analyst ESCALATE 시 자동 투입"
  - label: "+ planner 선투입"
    description: "다층 원인·아키 변경이 예상될 때 — planner 설계 파일부터 시작"
  - label: "축약: impl→tester"
    description: "원인 자명(수정 지점 특정됨) — checker/analyst 생략, da는 review 후행 1회"
  - label: "직접 조합"
    description: "워커·순서·DA 강도를 자유 입력 (1회 재확인 후 킥오프)"
```

### P-FEAT (피처 구현)

```yaml
question: |
  문제: <한 줄>
  유형: P-FEAT (피처 구현 요청)
  산출: .fable-team/features/<slug>.md
  연동: <1줄>
options:
  - label: "P-FEAT 기본 (Recommended)"
    description: "planner→implementer→tester→da approve loop(≤3R)"
  - label: "+ checker 자산 서치 선행"
    description: "기존 코드·유사 구현·재사용 자산 조사가 설계 품질을 좌우할 때"
  - label: "+ da2 이중 판정"
    description: "고위험·광범위 피처 — da/da2 이종 브레인 교차 검증"
  - label: "직접 조합"
    description: "자유 입력 (1회 재확인 후 킥오프)"
```

### P-REFAC (리팩토링)

```yaml
question: |
  문제: <한 줄>
  유형: P-REFAC (리팩토링 — 행위 불변)
  산출: .fable-team/features/<slug>.md
  연동: <1줄>
options:
  - label: "P-REFAC 기본 (Recommended)"
    description: "checker(영향 범위)→planner→implementer→tester(회귀 전후 동일성)→da"
  - label: "축약: checker→impl→tester"
    description: "기계적 변환(rename·이동 등) — 설계 불요, da review 후행"
  - label: "+ tester2 병렬"
    description: "회귀 표면이 넓을 때 — 테스트 이분할 병렬"
  - label: "직접 조합"
    description: "자유 입력 (1회 재확인 후 킥오프)"
```

### P-ANLZ (분석·조사)

```yaml
question: |
  문제: <한 줄>
  유형: P-ANLZ (분석·조사 — 변경 없음)
  산출: .fable-team/features/<slug>.md
  연동: <1줄>
options:
  - label: "P-ANLZ 기본 (Recommended)"
    description: "checker×N 병렬 서치→analyst 종합 진단. impl/tester/da 미스폰, 보고로 종결"
  - label: "+ da review 1회"
    description: "진단 결론을 이종 브레인으로 교차 검증하고 싶을 때"
  - label: "analyst 단독"
    description: "범위가 좁고 대상 파일이 특정됨 — 서치 생략"
  - label: "직접 조합"
    description: "자유 입력 (1회 재확인 후 킥오프)"
```

### P-HOT (긴급 수정)

```yaml
question: |
  문제: <한 줄>
  유형: P-HOT (긴급 — 원인 기지)
  산출: .fable-team/features/<slug>.md
  연동: <1줄>
options:
  - label: "P-HOT 기본 (Recommended)"
    description: "implementer+tester 동시 스폰 직행. da review 후행 1회(비게이트 — 랜딩 차단 없음)"
  - label: "+ analyst 초고속 진단 선행"
    description: "긴급하지만 원인 불확실 — analyst 1패스 후 impl 투입"
  - label: "impl 단독"
    description: "1~2파일 자명 수정, 검증은 오케·사용자 수동 확인 (tester·da 생략)"
  - label: "직접 조합"
    description: "자유 입력 (1회 재확인 후 킥오프)"
```

### P-VRFY (검증 전용)

```yaml
question: |
  문제: <한 줄>
  유형: P-VRFY (검증 전용 — 구현 완료물)
  산출: .fable-team/features/<slug>.md
  연동: <1줄>
options:
  - label: "P-VRFY 기본 (Recommended)"
    description: "tester→da review. 구현 완료물의 PASS/FAIL 판정 + 이종 교차 확인"
  - label: "tester+tester2 병렬"
    description: "케이스가 많을 때 — 이분할 병렬 실행"
  - label: "tester 단독"
    description: "빠른 PASS 확인만 — da 생략"
  - label: "직접 조합"
    description: "자유 입력 (1회 재확인 후 킥오프)"
```

### P-DOC (문서·설정)

```yaml
question: |
  문제: <한 줄>
  유형: P-DOC (문서·설정 — 코드 ≤2파일)
  산출: 직접 처리 (features 파일 없음)
  연동: 없음
options:
  - label: "오케 직접 처리 (Recommended)"
    description: "워커 미스폰 — orchestration-gate 허용 범위(코드 ≤2파일·문서·설정) 내 즉시 처리"
  - label: "implementer 위임"
    description: "코드 3파일+ 이거나 게이트 차단이 예상될 때"
  - label: "P-FEAT로 승격"
    description: "실은 동작 변경을 수반 — planner부터 표준 파이프라인"
```

(P-DOC은 고유 옵션 3개로 충분 — `직접 조합` 생략 가능한 유일 패턴. `ask_other_builtin: false`인 하네스면 4번째로 추가.)
