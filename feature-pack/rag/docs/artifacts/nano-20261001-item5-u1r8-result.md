model: claude-sonnet-5-5[1m]
provider: claude-code session (ft-airag-nano-r1#1, effort=high)

# AIRAG U1 r8 — DA r14 잔여 minor R14-m1 (생성기 동명 클래스 생성자 전역 덮어쓰기) 결과

골 원문: 최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
골의 어느 축인가: A03 · A02 5순위 U1(C12·C07) — DA r14 잔여 minor R14-m1 (HELM #1943: 안 막힌 마지막 후속). 발주 #1944.

## 결과
consumer 전체 pytest 마지막 줄: `347 passed in 301.95s (0:05:01)` (기준선 341 + 신규 6). **`src/` 변경 0**(`git diff --stat -- src` 빈 출력) · **`reason_codes.py` frozen 528 diff 0**: `python tests/_regen_reason_codes.py` 재생성 후 파일 불변, `current().registry == REASON_CODES`·`render(registry) ==` 파일 문자열 일치, 미분류 0·수기 모순 0, 출현 분포 불변(declaration 866 · data 77 · structural 53 · compare 6 — 수기 검토 항목 추가 0). push 없음. 디스크 여유 191Gi(5%, 대용량 산출물 없음).

| 변경 | 커밋 |
|---|---|
| 생성기 | `b465b4a` [fix] |
| 회귀 테스트 | `aa94c5d` [test] |

## 원인
`build_bindings` 가 `classes: dict[str, ClassDef]` 에 `classes[node.name] = node` 로 이름만 키로 덮어써서, 같은 클래스명이 두 파일에 있으면 마지막 ClassDef 만 남았다. 각 모듈의 클래스에 `class_binding(node.name)` 을 부를 때 이미 «마지막 모듈의 정의»를 쓰므로 두 모듈 모두에 같은(잘못된) binding 이 들어가 R11-m3 의 `lookup` 불일치 검사에 도달하지 못했다. 결과가 파일 입력 순서에 좌우됐다(data→reason 순서에서 `Choice("PATH")` 가 reason 으로 허용 — DA 합성 재현).

## 변경 (`tests/_regen_reason_codes.py`, 도구만)
- `classes` 를 `dict[str, list[ClassDef]]` 로 — 같은 이름의 모든 정의를 보관(덮어쓰기 제거).
- `class_bindings(node)`: **그 클래스 노드 자신**의 `__init__`/dataclass 필드에서 constructor binding 을 구한다. 상속은 같은 이름의 베이스가 여러 정의면 각 후보의 binding 집합(여럿이면 불일치로 `Bindings.lookup` 이 모호 → `structural` 수기 검토). 예외 상속 판정(`is_exception`)도 노드 기반으로 바꿔 동명 베이스 후보 중 하나라도 예외면 예외로 본다. 정의 위치별 등록(`local[path]`·`anywhere`)은 R11-m3 구조 그대로, 클래스 정의마다 각자의 binding 을 등록한다.
- builtin 예외 기본(메시지=코드)은 같은 이름의 패키지 클래스가 있으면 추가하지 않는다(이전 동작 보존).

## 테스트 (`tests/test_reason_codes.py`)
- `test_same_named_classes_keep_their_own_constructor_binding_in_any_file_order`(2 순서 파라미터): data.py `Choice.__init__(field)` + `Choice("PATH")` vs reason.py `Choice.__init__(code)` + `Choice("VALID_CODE")` — `VALID_CODE` 선언·`PATH` 비선언·레지스트리에 `PATH` 없음.
- `test_class_collision_result_does_not_depend_on_file_order`: 입력 dict 순서를 뒤집어도 `(경로, 값)→kind` 가 동일, import 한 이름은 모호 → `structural`.
- `test_a_subclass_of_a_base_name_defined_twice_is_ambiguous_in_any_order`(2 순서): 같은 이름 `Base` 가 a.py(code)·b.py(field) 에 있을 때 `Child(Base)` 의 literal 은 `structural`.
- `test_an_exception_subclass_of_a_package_base_still_reports_its_message_as_the_code`: 예외 상속 보존.

## Red 요약
수정 전 4건 실패: 같은 이름 클래스 순서별 2건(data→reason 에서 `PATH` 가 선언 — 반대 순서에서는 `VALID_CODE` 가 `structural` 로 올라가 단언 위반) · 입력 순서 독립 1건 · 동명 베이스 서브클래스 1건(순서 하나). 나머지 2건(순서 반대 서브클래스·예외 상속 보존)은 통과. 중간에 1회: 클래스 정의별 binding 을 `positional/keywords` 가 있는 것만 등록해 동명 베이스 불일치가 사라지는 실수를 테스트가 즉시 잡아 정의마다 등록하도록 수정했다.

## 범위·금지 확인
테스트·도구 변경만(`tests/_regen_reason_codes.py`, `tests/test_reason_codes.py`). `runtime.json`·launchd·운영 경로·실제 op 접촉 없음. 신규 *.md 는 이 파일 하나.
