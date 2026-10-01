model: gpt-6.1-sol
provider: headroom

# AIRAG U1 설계 DA r3/3 — PASS (blocker 0, major 0, minor 3)

**판정: PASS — blocker 0, major 0, minor 3.** 발주 #1785의 승인 기준인 설계 major 0을 충족한다. r1의 수신 상한·fork/락·코드 인자 모델과 r2의 결과 파일 raw 값 저장·선언/참조 충돌·익명 파일 수명 지적이 r3 계약에서 닫혔다. 아래 minor는 구현 착수 때 테스트 명세와 단계 순서를 보정할 항목이며, 새로운 설계 라운드를 요구하는 보호 경계 결함은 아니다.

- 세션: `ft-airag-da-codex#0`, effort=high. model/provider는 현 세션 rollout metadata로 확인했다. 창 크기와 `[1m]` 여부는 미노출이다.
- 검토 설계: `.fable-team/state/airag-arch-claude/arch-20261001-item5-u1-design.md`, 맨 위 개정 r3. SHA-256: `dffb7fe1a56e9739d413073871b341e3219b617384ac6f3810a24d500b3c62b5`.
- 검토 HEAD: `fa9407672c7a4763285190bb4c1888730d561b8e`.
- 이전 판정: `da-20261001-sol-design-r1.md`, `da-20261001-sol-design-r2.md`; 원 재현: `da-20261001-sol-r10.md`; U1 키 저장 계약: `ops-design-vs-reality-20261001.md:31`.
- Serena initial instructions·워크트리 활성화·ready 상태를 확인하고 심볼 본문/참조를 대조했다. `.fable-team/state`는 Serena의 ignored-path 제한으로 셸에서 읽었다. source/test/설계 원문은 수정하지 않았다.

## 이전 결함의 폐쇄 대조

| 이전 지적 | r3 계약 및 확인 | 판단 |
|---|---|---|
| r1 D1: PIPE 전체 capture 후 상한 검사 | `:94-96,119-128`: 익명 파일, 직접 자식 종료 후 fstat, 64 KiB 초과 시 read 0회, 나머지도 read(size) 한 번. 유한 1 MiB 합성 파일의 read 0회를 확인했다. | 닫힘 |
| r1 D2: fork 손자의 result EOF·락 연장 | `:95,104,166-168`: 완료는 직접 자식 wait, wrapper 락은 부모만 보유, close_fds=True/pass_fds 없음. 손자가 result fd를 보유해도 부모가 반환하고 다음 flock을 획득했다. 부모 강제 종료 후 고아 겹침은 명시된 비보장이다. | 닫힘 |
| r1 D3: 첫 인자와 실제 code 인자 위치 불일치 | `:172-181`: code/reason_code 파라미터 바인딩·상속 init·dataclass 필드, 간접 helper의 호출 인자까지 포함. 실제 TickError·VerificationDecision·helper 시그니처와 맞다. 한 글자 예시 문제는 R3-m1이다. | 닫힘 |
| r1 D4: 부모 operations→sqlcipher import | `:140,150,195,252-253`: NAMES 상수화 및 순수 _result/reason_codes만 부모 import 그래프에 포함. fresh interpreter 검사와 NAMES 일치 검사가 명시됐다. 현 package __init__도 eager component import를 하지 않는다. | 닫힘(구현 검증 필요) |
| r1 D5: 사설 fd 비밀성·모든 env 키 부재 과대 주장 | `:92,196,284,286`: trusted/noisy 모델, valid-frame 위조 비보장, 기존 부모 env 예외와 새 자식 argv/env 보장 구분. type의 클래스명 신뢰 가정도 명시됐다. | 닫힘 |
| r2 R2-M1: raw stderr의 저장소 키를 파일에 기록 | `:97,113-114,127,133,198`: 자식 메모리에서 쓰기 전 정제, 파일에는 정확히 exit/summary/code/type frame만 기록, 부모 재검증. 키-like 오류·본문/경로·5 MiB raw 합성 입력의 파일에 금지 문자열이 없었다. | 닫힘 |
| r2 R2-M2: 선언 값의 Compare/Dict를 data로 처리해 충돌 | `:175-189`: 출현 기준 선언/참조/데이터, code/reason_code dict 값은 선언, 이미 선언된 값의 Compare는 참조, 값의 다중 역할 허용. 기존 충돌 9곳을 AST로 재확인했다(아래). | 닫힘 |
| r2 R2-m1: 부모 close 시 익명 파일 회수 주장 | `:98,250,285`: 마지막 보유 fd close가 회수 시점. 부모 close 후 fork 손자의 파일이 nlink=0 상태로 생존하는 것을 확인했다. 파일 수명과 완료/락 수명은 구분된다. | 닫힘 |

## Minor

### R3-m1 — 레지스트리 테스트의 한 글자 X가 코드 형태 규칙과 맞지 않는다

- 심각도: **minor**. 위치: 설계 `:264-265`의 T-registry-reference-no-widen / T-registry-binding, `:175,179`의 선언 규칙.
- 현 `_CODE`는 `[A-Z][A-Z0-9_]{1,100}`이다. 따라서 `fullmatch("X")`는 False, `fullmatch("XX")`는 True다. 명세는 `{"code": "X"}`, `TickError(40, "X")`, `_id(v, "X")`, `VerificationDecision(..., reason_code="X")`를 선언으로 기대한다.
- 조치: 선언 추출 테스트의 예시를 `DECLARED_CODE` 또는 `XX`로 바꾼다. 순수 parameter-binding 단계만 시험한다면 그 단계와 최종 `_CODE` 형태 필터의 기대를 분리한다. 런타임 코드 형태를 넓힐 필요는 없다.
- 영향: 보호 정책은 안전 방향이나, 글자 그대로 작성한 테스트가 올바른 구현을 실패시킬 수 있다.

### R3-m2 — Red 선행 테스트의 단언 방향이 단계 표와 반대다

- 심각도: **minor**. 위치: 설계 `:232`의 T-R10M1-native-red, `:299`의 S1.
- 본문은 현 코드에서 `MARKER_NATIVE in proc.stdout`를 단언하도록 쓰여 있다. 기존 누출이 재현되면 이 단언은 통과하지만, S1 표는 marker 검출 때문에 단일 테스트가 실패하는 Red를 요구한다.
- 조치: Red 테스트는 목표 동작인 `MARKER_NATIVE not in proc.stdout`를 단언해 현 코드에서 실패하게 한다. 관찰용 재현 probe의 `marker present=True`는 별도 증거로 남길 수 있다.
- 영향: 네이티브 버퍼 원인·격리 설계의 결함은 아니며, Red→Green의 검증 의미를 맞추는 보정이다.

### R3-m3 — 자식 모듈을 시험하는 S2보다 필수 import 의존성 작성 단계가 늦다

- 심각도: **minor**. 위치: 설계 `:141,146,300-306`의 import 계약 및 S2/S3b/S5 순서.
- `_pass_child.py`는 모듈 최상단에서 `._result`를 import하고 `_result.py`는 `reason_codes`를 import한다. 그런데 단계 표는 S2에서 자식 단위 테스트 통과를 요구하면서 `_result.py`를 S3b, `reason_codes.py`를 S5에서 만든다. HEAD에는 두 모듈 모두 없다.
- 조치: S2의 자식 테스트보다 앞서 필수 순수 모듈/레지스트리 의존성을 마련하거나, 자식 배선·시험 단계를 해당 의존성 이후로 옮긴다. S5는 선언 생성/드리프트 규칙의 확정 및 레지스트리 교체 단계로 유지할 수 있다. 신규 `_result.py`도 S6 변경 파일 목록에 포함한다.
- 영향: 최종 구조의 보안 결함은 아니지만, 현재 순서 그대로는 단계별 통과·실행 가능한 커밋을 만들 수 없다.

## 요청한 5축 판단

1. **설계 major 0:** 승인 가능하다. 파일 쓰기 전 정제와 부모 재검증이 분리되고, fd/락/파일의 서로 다른 수명이 계약으로 고정됐다. 남은 3건은 테스트·실행 순서 보정이다.
2. **보장표:** 1~7은 컴포넌트 import 전부터 정상 종료/네이티브 flush까지 자식 fd 1·2가 영구 /dev/null이라는 근거다. 8은 bounded read·형식 검증에 한정되며 valid-schema 위조 방지는 주장하지 않는다. 9의 파일/소켓/syslog/tty는 범위 밖, 10은 순수 부모 import 및 whitelist, 11은 부모 BaseException의 기존 수준이다. 부모 강제 종료·손자 존속·type 신뢰 가정·파일 물리 크기 상한 없음은 승인으로 사라지지 않는다.
3. **자식 프로토콜:** exact NAMES·64hex·distinct bytes·입력 한도, 부분 write 반복/0 반환 실패, 종료코드 0/3/기타 구분, 정확한 frame 키·int/bool 구분·summary whitelist·코드/type 재검증이 명시됐다. 큰 raw 메모리와 결과 파일/부모 수신 상한도 구분됐다. 악의적 writer·모든 BaseException 비노출·디스크 용량 제한으로 확대하지 않는다.
4. **테스트 명세:** T-native-normal/exception의 별도 전체 tick 프로세스·수동 fflush 없는 종료가 R10-M1 원 재현을 겨냥한다. T-raw-output-not-persisted는 console뿐 아니라 결과 파일을 검사하고, T-parent-revalidates는 자식 우회 frame도 거부한다. 초과 read 0회·fork 완료/락/파일 수명·bootstrap/import·기존 r8~r10 회귀가 각각 대응된다. R3-m1/m2를 보정한 뒤 구현된 전체 tick에서 통과해야 한다.
5. **레지스트리:** runtime frozen 데이터와 테스트 시 AST 생성의 분리, 선언/참조/데이터의 출현 분류, 수기 reason만 허용값에 기여, 참조의 no-widen 및 registry/tests 스캔 제외가 타당하다. 구조 문맥 수기 분류·실제 생성기의 이름/인자 바인딩은 Nano가 구현 후 closed-world로 검증해야 하며, 이 설계 승인은 아직 없는 생성기를 실행한 통과 판정이 아니다.

## 독립 합성 확인

임시 toy worker에 r3의 stdin·stdout=익명 결과 파일·stderr=DEVNULL·close_fds·dup 후 영구 /dev/null·쓰기 전 frame 정제 경계를 구성했다. 정제 함수는 현 tick.py의 `_counts`, `_safe_code`, `_error_fields` 및 정규식 AST를 읽기 전용으로 추출했고, 허용 코드 집합은 독립 합성 목록을 주입했다. **새 `_pass_child`/`_result`/레지스트리의 구현이나 실제 tick 통합 검증은 아니다.** raw 내용은 출력하지 않고 boolean·크기·종료코드만 관찰했다.

```text
NORMAL_EXIT 0
NORMAL_RESULT_SAFE true
KEYLIKE_FILTERED_BEFORE_FILE true
HUGE_RAW_SMALL_INVALID_FRAME true
NATIVE_NORMAL_EXIT_NO_MANUAL_FLUSH true
NATIVE_RESULT_SAFE true
FORK_NEXT_TICK_LOCK_AVAILABLE true
FORK_PARENT_RETURNED_WITHOUT_DESCENDANT_EOF true
FORK_ANONYMOUS_FILE_LIVE_AFTER_PARENT_CLOSE true
FORK_DESCENDANT_ENV_KEYS_ABSENT true
OVERSIZE_FILE_BYTES 1048576
OVERSIZE_PARENT_READ_CALLS 0
REGISTRY_EXAMPLE_X_MATCHES_CODE false
REGISTRY_EXAMPLE_XX_MATCHES_CODE true
R2_DECLARED_VALUES_IN_COMPARE_DICT_OCCURRENCES 9
R10_ENV_NAMES_DECLARED false
```

정상·키-like 오류·5 MiB raw·native·fork의 결과 파일에서 합성 키 3개(대/소문자), MARKER_, 합성 경로가 없었고 정확한 frame 키와 64 KiB 이하 크기를 확인했다. native worker는 Python 출력·직접 fd write·libc printf 후 정상 종료했으며 수동 fflush를 쓰지 않았다. fork 손자는 부모 파일 close를 기다리는 유한 probe를 수행했다. 초과 파일은 정제 자식을 우회한 별도 합성 모드이고, 부모가 read를 호출하지 않았다.

현재 source의 기존 충돌 9곳은 다음처럼 닫힌다. `bridge.py:164 NOT_FOUND`, `collector.py:753 STALE_COLLECTOR_CURSOR`는 Compare 참조이고, core `api.py:61 KEY_OR_DB_VERIFICATION_FAILED`, `:63 UNSUPPORTED_SCHEMA_VERSION`, `:65 DATABASE_ALREADY_EXISTS`, `:87 VALIDATION_ERROR`, `:89 IO_ERROR`, `:687 VALIDATION_ERROR`, `:692 PAYLOAD_TOO_LARGE`는 code dict 선언이다. 각 출현을 구조적으로 대조했으며, 최종 frozen 값 개수나 전체 수기 분류 완료를 주장하지 않는다.

## 검토 범위·snapshot

| 파일 | SHA-256 |
|---|---|
| `feature-pack/rag-consumer/src/airag_consumer/tick.py` | `f4188bb96ed5bee89922ad6f6387c8ee3dced596ca9770c55b2511784f72da48` |
| `feature-pack/rag-consumer/tests/test_tick.py` | `0cac63db06e6524502347d678fa8b6a1fbc4b434695a873b78a9108b502cee4f` |

두 hash는 원 R10 판정과 같다. source/test/설계 수정이 없고 신규 구현도 없으므로 기존 239개 consumer 회귀를 반복하지 않았다. 이번 증거는 설계 계약 대조·현 source AST·유한 합성 OS 실험이다. 실제 op·1Password·운영 경로/키/DB·launchd·외부 endpoint에는 접근하지 않았다. commit·push·branch 삭제·다른 프로세스 종료도 수행하지 않았다. 산출물은 이 판정서 하나다.

**최종: PASS (blocker 0, major 0, minor 3).** Architect는 승인된 r3 구조를 Nano에 넘기되 R3-m1/m2/m3를 구현 명세에 반영한다. 실제 구현의 값 비노출·레지스트리·회귀 통과와 운영 승인/관찰은 별도 후속 게이트다.
