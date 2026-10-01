model: gpt-6.1-sol
provider: headroom

# AIRAG reference 키 지연 검사 설계 DA r1 — PASS (blocker 0, major 0, minor 2)

**판정: PASS — blocker 0, major 0, minor 2.** 발주 #1844의 major 0 기준을 충족한다. 권고 C는 reference 키를 자동 생성하거나 다른 키로 폴백하는 변경이 아니다. 저장소 3키·초기 profile 키 검사를 유지하고, reference 검색의 필수 키 검사를 해당 사용 경로의 부작용 전에 수행하는 설계다. None/빈 문자열만 지연 허용하며, 제공된 잘못된 키의 형식·distinct 거부는 유지한다. 아래 minor는 테스트 보강과 R6의 보장 범위 보정이다.

- 세션: `ft-airag-da-codex#0`, model/provider 및 effort=low는 현재 rollout으로 확인. 발주 표기는 `gpt-6.1-sol low fast`; fast 서비스 등급·창 크기·`[1m]` 여부는 runtime metadata 미노출.
- 검토 HEAD: `67e16b58623d035ed1796e35b3492ab03793a70e`.
- 설계: `arch-20261001-item5-refkey-design.md`, SHA-256 `458c96fe687391e9e07ab066ff19cf36d9534543dca727cdd50cafe1cfe7da68`.
- source snapshot: `runtime.py` SHA-256 `e0ec0bc768fa7f32a0ca82e4aed4fbfc63e29deeacffd362aca06069a7e84e47`; `tests/test_runtime.py` SHA-256 `0a33d5a17c70b6ec813f1fd10c10ef49d5c7d87349dffd6a3719724359eb4a79`.
- Serena 심볼·필드 참조·텍스트 검색으로 source/spec를 대조했다. class constructor 참조의 빈 결과와 ignored tour 스크립트는 consumer src 및 `.fable-team/bin/tour`의 exhaustive rg/읽기로 보완했다. 실제 tour 도구는 실행하지 않았다.

## 요청한 5축

### 1. fail-closed 및 우회 경로

현재 생성자는 `load_store_keys`를 locks/directories/database보다 먼저 호출하고 저장소 3키를 필수·64hex·상호 distinct로 검증한다. profile 키도 초기 저장소가 없으면 필수이며 `_install_profile`은 profile 키가 None일 때 원본을 열기 전에 거부한다. C는 이 두 경계를 변경하지 않는다.

`reference_source_key`의 실제 사용은 `AIRAGRuntime.search → search_tour_reference`다. C의 조기 guard는 기존 검색 인자 검증 직후, `_lock/_open_ledger` 전에 놓여야 한다. 기존 후기 guard도 유지하면 내부 상태가 바뀌는 경우의 이중 방어가 남는다. 직접 `search_tour_reference(..., source_key=None, ...)` 호출도 `_validate_key`에서 INVALID_SOURCE_KEY로 거부되며 `_safe_paths/_digest` 호출 0회였다. None을 다른 키로 대체하는 로직은 없다.

`run_once/status/backup/verify/memory-*`는 reference source key를 소비하지 않는다. `status`가 reference snapshot 디렉터리의 파일 이름을 나열하고 `init`이 snapshot 디렉터리를 만들 수 있다는 점은 원본 reference DB의 복호화나 snapshot DB 생성과 구분한다. profile bootstrap의 별도 키·경로 역할은 아래 D2처럼 R6에 명시해야 한다.

### 2. DECISIONS.md의 키 미제공 거부와의 관계

DECISIONS.md:447-452의 “키 미제공/형식 오류는 저장소 생성·열기 전 거부, 자동 키 생성·폴백 없음”은 **접근할 저장소에 유효한 키 없이 접근하지 않는 경계**로 유지된다. 사용하지 않는 reference 키 때문에 다른 키로 보호된 소비자 저장소의 객체 생성까지 금지해야 한다는 별도 명시 계약은 찾지 못했다.

스토어 키는 여전히 필수이고, reference 검색은 reference 키가 없으면 저장소 작업 전에 거부한다. profile 설치가 필요하면 profile 키가 여전히 필수다. 기존 “reference 설정이면 생성자에서 필수” 테스트는 실제 변경되는 동작 계약이므로 숨기지 말고 교체해야 한다. 후기의 None 방어 분기가 있다는 사실만으로 과거 작성자의 의도를 증명할 수는 없지만, C의 안전성은 그 의도 추정에 의존하지 않는다.

### 3. None·빈 문자열·공백·잘못된 타입

없음과 명시 None, 정확히 빈 문자열 `""`만 absence로 취급한다. 공백을 strip해 absence로 바꾸거나 truthiness로 분기하면 안 된다. 공백·64문자 중 공백 포함·63/65자 hex·비hex·0·False는 invalid로 거부한다. 유효 hex는 bytes로 비교해 대소문자 차이에 의한 distinct 우회를 막는다. distinct 집합에는 스토어 3키와 제공된 profile 키가 들어가야 한다.

이 행렬을 메모리 안의 후보 C 생성자로 확인했다. 모든 absence는 reference_source_key=None으로 생성됐고, invalid는 MISSING_OR_INVALID_REFERENCE_SOURCE_KEY, 재사용은 REFERENCE_SOURCE_KEY_MUST_BE_DISTINCT였다. 유효한 별도 키는 기존처럼 수락됐다.

### 4. CLI·tour·bridge 호출자 영향

- **CLI:** 모든 서브커맨드가 생성자를 통과한다. C 뒤에는 reference 키 없는 non-search 명령이 실행 가능하고, search는 메서드 시작 시 같은 정적 오류로 끝난다. 제공된 invalid reference 키는 non-search 명령에서도 생성자가 거부한다는 정책이 유지된다.
- **tick/_pass_child:** stdin·NAMES는 스토어 3키 그대로다. 없던 reference 키를 주입하거나 새 보관 위치를 만들지 않는다. 기존 env에 reference 값이 이미 있으면 자식의 기존 env 상속을 통해 생성자 검사를 받는 것도 그대로다.
- **tour:** deployment_setup.initialize/status와 first_collection.runtime은 환경 mapping에 명시 reference 키를 제공한다. 유효한 키가 있으면 동작이 유지된다. 초기 profile bootstrap은 기존에도 reference 절을 제외한 설정과 profile 키를 쓴다. verify_14_isolated의 synthetic caller는 테스트 환경을 제공한다.
- **bridge/직접 helper:** consumer bridge의 일반 검색은 자기 projection을 사용하고 reference 호출은 runtime.search가 조합한다. 직접 reference helper는 자체 32바이트 키 검증을 유지한다. 기존 호출자에서 이 생성자 오류를 catch해 다른 키로 여는 fallback은 확인되지 않았다.

### 5. 테스트·레지스트리

명세는 핵심 직접 증상인 reference-config tick exit 40→0, search의 락/원장 이전 거부, malformed 키 유지, 정상 reference 검색 회귀를 포함한다. D1의 경계값을 추가하면 None/빈값 허용이 과도한 truthiness 완화로 구현되는 것을 잡을 수 있다.

최소 삽입 후보 source를 **문자열/AST 분석용 메모리에서만** 구성해 registry를 대조했다. 값 집합 변화 없음, 미분류 0·수기 모순 0이었다. 이번 삽입 위치보다 앞에 있는 runtime 수기 검토 항목의 줄은 변하지 않는다. 따라서 reason_codes.py를 변경하지 않는 명세는 이 최소 변경에서는 성립한다. 실제 구현 후 drift/closed-world 전체 회귀는 필요하다.

## Minor

### D1 — 경계값과 보존해야 할 다른 키 경계의 테스트가 부족하다

- 심각도: **minor**. 위치: 설계 ④ T-ref-empty/invalid/distinct 및 R2/R3/R4.
- 현재 invalid 예시는 비hex·63/65자 문자열뿐이며, missing/빈값과 공백의 차이, 명시 None, falsey non-str(0/False/빈 bytes 등)를 명시적으로 시험하지 않는다. distinct는 projection 값 한 개만 고정한다. 저장소 키의 필수 거부가 그대로 남는지도 이번 변화와 함께 검증하는 편이 좋다.
- 보정: absent/None/`""` 수락, `" "`·공백 포함 64문자·0/False/비-str 거부, 스토어 3키 각각과 제공된 profile 키 재사용 거부를 parameterize한다. 스토어 키를 하나씩 제거한 생성자 거부와 초기 profile 키 없는 bootstrap 거부도 보존 회귀로 묶는다. invalid query의 오류 우선순위는 search 인자 검증→reference guard 순서 그대로다.
- 설계 자체의 조건은 명확하므로 major로 세지 않는다. 후보 실험은 이 기대대로 동작했다.

### D2 — “reference 키 없으면 투어 DB를 열지 않음”은 reference 경로로 한정해야 한다

- 심각도: **minor**, 보장 표현의 범위. 위치: 설계 R6·② 권고 보안 설명·④ no-side-effect 단언.
- RuntimeConfig는 `profile_source_db == reference.source_db`를 금지하지 않는다. 후보 C에서 이 둘을 같은 **합성** 파일로 지정하고 reference 키는 제거하되 유효한 **profile 키**를 명시 제공하면 `init → _install_profile → open_readonly(profile_source_db, profile_source_key)`가 그 파일을 읽는다. 관찰: reference_source_key는 None이지만 aliased reference 경로의 readonly open 1회, init 성공이었다.
- 이것은 키 없이 DB를 연 것이 아니며 자동 fallback도 아니다. 별도의 명시 profile 키와 profile 설치 경로가 사용됐다. 기존에도 reference 절 없는 profile bootstrap으로 가능한 동작이고, C가 복호화 키를 만들거나 타 저장소 키로 대체하지 않는다. 실제 tour 설정은 profile seed와 reference source를 별도 경로로 둔다.
- 보정: R6을 **“reference 키 없으면 reference 검색/helper/그 경로의 source DB open·snapshot DB 생성은 없다”**로 쓰고, profile bootstrap은 별도의 profile 키로 보호됨을 명시한다. 절대적인 모든 DB 파일 open 금지나 경로 alias 금지를 새로 도입하는 것은 이번 surgical 변경의 요구가 아니다. alias 사례를 합성 테스트로 기록하면 보장 범위가 분명해진다.

## 독립 합성 증거와 한계

실제 저장된 source는 수정하지 않고, inspect/AST로 현재 __init__/search를 읽어 C의 조건·조기 guard만 넣은 함수를 **별도 Python 프로세스의 메모리**에서 실행했다. 기존 test_runtime의 합성 project/bridge와 resolved 임시 경로를 사용했다. search의 side effect를 spy로 차단했고 실제 reference bytes와 snapshot 파일 수를 대조했다.

```text
CURRENT_MISSING_REFERENCE_CONSTRUCTOR MISSING_OR_INVALID_REFERENCE_SOURCE_KEY
C_MATRIX missing/explicit_none/empty allowed_none
C_MATRIX space/whitespace64/short/long/badhex/integer/boolean MISSING_OR_INVALID_REFERENCE_SOURCE_KEY
C_MATRIX valid allowed_key
C_MATRIX store_consumer/store_projection/store_archive/profile_reuse REFERENCE_SOURCE_KEY_MUST_BE_DISTINCT
C_MISSING_SEARCH_ERROR MISSING_OR_INVALID_REFERENCE_SOURCE_KEY
C_MISSING_SEARCH_SIDE_EFFECT_CALLS 0
C_MISSING_STORE_STILL_REJECTED [각 3키] MISSING_OR_INVALID_STORE_KEY
C_MISSING_INIT_SUCCESS true
C_MISSING_RUN_ONCE_SUCCESS true
C_MISSING_STATUS_REFERENCE_CONFIGURED true
C_REFERENCE_SEARCH_CALLS 0
C_REFERENCE_SOURCE_BYTES_UNCHANGED true
C_REFERENCE_SNAPSHOT_FILES 0
DIRECT_REFERENCE_NONE_KEY_ERROR INVALID_SOURCE_KEY
DIRECT_REFERENCE_NONE_FILE_CALLS 0
SURGICAL_C_REGISTRY_UNCHANGED true
SURGICAL_C_REGISTRY_UNCLASSIFIED 0
SURGICAL_C_REGISTRY_CONTRADICTIONS 0
C_PROFILE_REFERENCE_PATH_ALIAS_ALLOWED true
C_MISSING_REFERENCE_WITH_EXPLICIT_PROFILE_KEY_INIT true
C_PROFILE_BOOTSTRAP_OPENS_ALIASED_REFERENCE_PATH 1
C_REFERENCE_KEY_STILL_NONE true
```

첫 registry 탐색에서 AST.unparse로 파일 전체를 재배치하면 수기 줄 번호 항목 2개가 stale해졌다. 이는 C의 최소 삽입 효과가 아니므로 결함 증거로 사용하지 않았다. 원래 source 행을 유지하는 최소 후보로 위의 변화 없음/모순 0을 확인했다. 직접 helper probe의 초기 import 경로 오류는 driver에서 수정했으며 source key 검사가 파일 작업 이전이라는 결과를 완료했다.

아직 repo 구현이 없으므로 전체 consumer 회귀나 후보의 실제 tick subprocess 통합을 통과 판정하지 않는다. 후속 Nano가 명세의 Red→Green 및 코드 DA에서 검증해야 한다. 호출 시점 운영 env의 실제 변수 존재 여부도 재조사하지 않았으며, 키 없음·형식 오류·재사용 모두 동일 장애와 연결될 수 있어 생성자 사용 시점의 불일치와 운영 관찰은 구분한다.

이 검토에서는 실제 op·1Password·운영 경로/키/DB·launchd·외부 endpoint를 접촉하지 않았다. source/test/설계 원문·환경 설정을 수정하지 않았고 commit/push/프로세스 종료도 하지 않았다. 신규 산출물은 이 판정서 하나다.

**최종: PASS (blocker 0, major 0, minor 2).** C의 사용처 이전 검사와 기존 저장소/profile 키 경계를 유지하고, D1 테스트와 D2 보장 문구를 구현 명세에 반영한다.
