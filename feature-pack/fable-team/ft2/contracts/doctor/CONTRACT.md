# ft2 doctor 입출력 계약 (r1550 · PR④ 앞 계약 고정)

doctor 는 각 설치 환경에서 비모델로 진단하고, 국소 복구와 재검증까지 잇는다.
이 문서는 그 입출력을 **파일로 고정**한 계약이다. 구현·어댑터는 PR④ 몫이다.

## 정본 문면 (복붙)

> 새로 분리한 doctor 작업의 독립 입력은 증상key·설치sha·상태revision·근거·관측/판정불가·허용복구·재검증·미해결 owner다. 계약 문면은 지금 작성하고 r1506/r1507 결과와의 대조만 후행한다. 이 분리는 제품 구현을 허가하지 않는다.

즉 **r1506/r1507 결과와의 대조는 후행 · 제품 구현 허가 아님**이다. 이 계약으로 doctor 동작을 판정하지 않는다.

## 8 독립 입력 — 의미 이름 대응표

필드 더하기·빼기 0. 이름만 영문 snake 로 옮겼다.

| # | 정본 의미 | 필드 | 형 | 제약 |
|---|---|---|---|---|
| 1 | 증상key | `symptom_key` | string | `^[a-z0-9][a-z0-9._-]*$` |
| 2 | 설치sha | `install_sha` | string | 40자 소문자 hex |
| 3 | 상태revision | `state_revision` | integer | ≥ 0 |
| 4 | 근거 | `evidence[]` | array | 1건 이상 · 각 `{source, ref}` |
| 5 | 관측/판정불가 | `observation` | object | `verdict` enum 2값 · 판정불가면 `reason` 필수 |
| 6 | 허용복구 | `allowed_recovery[]` | array | 복구 종류 문자열(0개 허용 = 자동 복구 없음) |
| 7 | 재검증 | `reverified` | object | `done` 필수 · `evidence_ref` 선택 |
| 8 | 미해결 owner | `unresolved` | object | `open` 필수 · `open=true` 면 `owner` 필수 |

### enum 2값 (5번)

| verdict | 뜻 | 조건 |
|---|---|---|
| `observed` | 관측이 성립했다 | 없음 |
| `undetermined` | 판정 불가다 | `reason` 필수 — 판정불가를 숨기지 않는다 |

### 조건 2개 (schema 의 `if`/`then`)

1. `observation.verdict == "undetermined"` → `observation.reason` 필수.
2. `unresolved.open == true` → `unresolved.owner` 필수.

## 예시 fixture

| 파일 | 기대 | 무엇을 보이는가 |
|---|---|---|
| `examples/ok-01-observed.json` | 통과 | 관측 성립 · 복구 1종 예정 · 미해결 0 |
| `examples/ok-02-undetermined.json` | 통과 | 판정불가 + 사유 · 미해결 owner 있음 |
| `examples/ok-03-recovered-reverified.json` | 통과 | 복구 2종 실행 · 재검증 true + 근거 |
| `examples/bad-01-missing-field.json` | 거절 | `evidence` 필드 1개 빠짐 |
| `examples/bad-02-undetermined-no-reason.json` | 거절 | 판정불가인데 사유 없음 |
| `examples/bad-03-unresolved-no-owner.json` | 거절 | 미해결(open)인데 owner 없음 |

## 검사기

`schema_check.py` — 표준 라이브러리만 쓴다(jsonschema 의존 0). 손검사는 3종이다: 필수(`required`) · enum · 조건(`if`/`then`).

```
python3 feature-pack/fable-team/ft2/contracts/doctor/schema_check.py            # examples/ 전부
python3 .../schema_check.py examples/bad-03-unresolved-no-owner.json            # 1건만
```

| rc | 뜻 |
|---|---|
| 0 | 준 예시 전부 schema 통과 |
| 1 | 위반 있음(어느 파일의 어느 경로인지 출력) |
| 3 | schema/예시를 못 읽음 — 0 으로 조용히 통과하지 않는다 |

## 계약 ↔ 시험 대응

| 계약 | 시험(`ft2/tests/test_contract_doctor_schema.py`) |
|---|---|
| 정본 8개 필드 그대로 | ⓐ + 변이 M2 |
| 판정불가는 사유와 함께 | ⓑ · ⓒ |
| 미해결엔 owner | ⓒ + 변이 M1 |
| 구현 허가 아님 문구 | ⓓ |

## 미시험 / 범위 밖

- **미시험**: doctor 실행 동작 · 복구 집행 · 재검증 결과 판정 — PR④ 와 게이지 20 에서 본다.
- 범위 밖: enum 확장 · 어댑터 · r1506/r1507 결과 대조(후행) · 실 설치본 진단.
- 이 계약은 자료다. 설치 동작·정본 3파일은 바꾸지 않는다.
