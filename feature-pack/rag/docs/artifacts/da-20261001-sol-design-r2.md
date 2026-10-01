model: gpt-6.1-sol
provider: headroom

# AIRAG U1 설계 DA r2/3 — REJECT (blocker 0, major 2, minor 1)

**판정: REJECT — blocker 0, major 2, minor 1.** 발주 #1776의 PASS 기준은 설계 major 0이다. r1의 파이프 수신 상한·fork EOF/락·인자 위치·부모 import·과대 보장 지적은 개정됐다. 새 익명 결과 파일의 민감 값 저장과 closed-world의 코드 참조 분류를 고쳐야 설계 major 0으로 닫을 수 있다.

- 세션: `ft-airag-da-sol#1`, effort=high. 실행 헤더 model/provider는 위 두 줄. `[1m]` 여부는 미노출이다.
- 검토 파일: `.fable-team/state/airag-arch-claude/arch-20261001-item5-u1-design.md`, r2.
- 설계 SHA-256: `e573a76971077ca4619617b481610e3fda5cbff6d713e47b859899d5c42bdb86`.
- 코드·테스트·설계 원문은 수정하지 않았다. source AST/기존 실제 합성 CLI와 임시 OS 자원만 사용했다. 실제 op·1Password·운영 경로/키/DB·launchd·외부 endpoint는 미접촉이다.

## r1 지적의 반영

| 항목 | r2 대조 |
|---|---|
| D1: PIPE 전체 capture 후 상한 검사 | 익명 파일의 fstat 후 read(size)로 교체. size 초과 시 읽지 않으며 read(size)도 상한 내다. 5MiB 합성 파일에서 read 0회를 확인했다. 자식 자신의 생성 메모리·파일의 물리적 크기는 부모 읽기 상한과 구분됐다. |
| D2: fork 손자에 남는 result EOF/락 | pipe EOF 대신 직접 자식 wait를 완료 신호로 사용하고 wrapper 락을 부모만 보유한다. fork 손자가 result fd를 갖고 있어도 부모 run이 먼저 반환하는 실험을 확인했다. 부모 강제 종료 시 고아 패스 겹침은 이번엔 보장 밖으로 명시됐다. |
| D3: 첫 인자 선언 규칙 | code/reason_code parameter binding, constructor 상속·dataclass field를 사용하도록 교체했고 두 번째 positional/keyword 테스트가 추가됐다. 이전 인자 위치 모순은 닫혔다. 정의와 참조의 별도 분류는 R2-M2로 남는다. |
| D4: 부모의 SQLCipher import | NAMES를 경량 상수로 두고 operations import 제거를 변경 목록에 명시했다. fresh interpreter import-graph 테스트도 추가됐다. |
| D5: 사설 fd 불가시성·모든 env 키 부재 | trusted/noisy component 모델, valid-frame 위조 비보장, 기존 부모 env 예외를 명시했다. I3가 새 자식 argv/env에 추가되는 노출로 한정됐다. |

## Major

### R2-M1 — 원시 CLI stderr를 익명 결과 파일에 쓰면 저장소 키가 파일에 남는다

- 심각도: **major**.
- 위치: 설계 `:93-96` 결과 파일, 3.2 자식 step 6/7의 `{exit,stdout,stderr}` payload, `:265`의 ⑤-7 저장 설명.
- 기존 U1 계약: `ops-design-vs-reality-20261001.md:31`은 **키를 파일·로그·plist에 쓰지 않는다**고 정의한다. 프로세스 격리로 바뀌어도 저장소 키의 새 파일 저장을 승인한 계약은 아니다.
- 원인: worker는 CLI stdout/stderr 원문을 result 파일에 쓰고, **부모가 파일을 읽은 뒤** _error_fields/_counts로 정제한다. 실제 CLI는 code 형태인 예외 메시지를 그대로 error.code에 넣을 수 있다. R8~R10의 64hex 재현 값도 그 원시 stderr 안에 있다.
- 실험: 기존 합성 runtime을 유효한 대문자 hex 저장소 키로 초기화하고 bridge만 그 합성 키를 RuntimeError 메시지로 던지게 했다. 실제 CLI는 exit 2로 그 값을 stderr JSON에 넣었다. 제안된 payload 형태를 실제 TemporaryFile에 기록했다. 파일은 regular/0600이었고 **합성 저장소 키 바이트를 포함**했다. 이후 parent 필터라면 RUNTIME_FAILED로 바뀐다는 것도 확인했다.
- 의미: 정상 tick stdout/log가 안전해도 새로운 결과 파일에는 정제 전 비밀이 기록된다. anonymous/0600은 접근성과 이름을 제한할 뿐 값 저장을 없애는 것은 아니다. ⑤-7이 설명한 숫자 중심 stdout·경로만의 변화보다 범위가 크며 stderr의 키/본문 가능성도 포함한다.
- 필요한 계약: 파일에 쓰기 **전에** worker가 code/type/숫자 whitelist로 정제한 결과만 전송하거나, 원시 결과가 파일에 기록되지 않는 bounded IPC로 설계한다. parent는 받은 정제 schema를 재검증한다. 키-like 예외 테스트는 console뿐 아니라 결과 저장 채널에도 키·본문 값이 없음을 확인해야 한다.
- 한계: 실제 키나 운영 파일을 읽거나 쓴 것은 아니다. 파일 내용을 판정서/콘솔에 출력하지 않고 존재 여부만 보고했다.

### R2-M2 — 이유 코드의 참조를 자동 data로 분류하면 현재 코드에서 reason/data 충돌이 발생한다

- 심각도: **major**.
- 위치: 설계 `:176-177` closed-world 규칙, T-registry-closed-world.
- 원인: 규칙 ①은 생성자/코드 parameter에 전달된 literal을 reason으로 선언한다. 규칙 ②는 Compare·Dict 등의 literal을 자동 non-reason으로 분류한다. 이어 **같은 값이 reason/data 양쪽이면 테스트 실패**로 정한다. 하지만 실제 코드의 비교/응답 딕셔너리는 이유 코드의 정상 참조일 수 있다.
- source AST 대조: 선언된 이유 코드와 같은 값이 Compare/Dict에 있는 **9개 occurrence**를 확인했다. 예: bridge.py:164 NOT_FOUND 비교, collector.py:753 STALE_COLLECTOR_CURSOR 비교, airag/api.py:61 KEY_OR_DB_VERIFICATION_FAILED 응답 dict, :63 UNSUPPORTED_SCHEMA_VERSION, :65 DATABASE_ALREADY_EXISTS, :87 VALIDATION_ERROR.
- 영향: 이들은 새 모호한 데이터 literal이 아니라 코드의 정상 참조다. r2 규칙대로면 현재 baseline에서 충돌 실패가 생긴다. 수기 reason/data 파일은 Tuple/List/Assign 등의 구조 문맥에 한정돼 있어 자동 data인 Compare/Dict를 어떻게 정정하는지 계약이 없다.
- 필요한 계약: **선언 / 이유 코드 참조 / 일반 데이터**를 구분한다. 명시 error.code/reason_code 응답 필드·코드 비교와 같은 참조 문맥을 검증하거나 검토 가능한 override를 정의한다. 참조는 이미 선언된 값을 확인하되 새 허용값을 넓히지 않도록 한다. 값의 reason/data 공존 자체를 무조건 실패시키지 말고 occurrence의 의미/충돌 정책을 정한다. 현재 9개 참조 및 같은 public literal의 합법적 data 사용을 baseline 테스트로 추가한다.

## Minor

### R2-m1 — 부모가 close하면 익명 파일이 회수된다는 수명 주장은 fork 손자와 맞지 않는다

- 심각도: **minor**.
- 위치: 설계 `:96`, 3.4 종료 순서, ⑤-7의 짧은 파일 수명 설명.
- 실험: worker가 익명 result fd를 fork 손자에 남긴 뒤 정상 종료했다. 부모 run은 손자를 기다리지 않고 반환했고 부모도 자기 TemporaryFile을 닫았다. 유한 0.6초 후 손자가 fstat으로 확인한 파일은 **여전히 regular file이고 nlink=0**이었다. 손자는 정상 종료했다.
- 의미: 익명 파일 회수는 부모 close가 아니라 **마지막 보유 fd의 close** 시점이다. r2가 손자 존속을 허용하므로 파일의 수명/디스크 사용이 패스·부모보다 길 수 있다. 부모 완료 판정·메모리 상한은 이로 인해 다시 실패한 것은 아니다.
- 보정: 수명 보장을 정정하고 descendant가 result fd를 보유하는 경우를 잔여/테스트에 포함한다. R2-M1의 원시 민감 값 저장과 함께 검토해야 한다.

## 나머지 5축 판단

1. **보장표:** 영구 /dev/null worker는 native/Python/fd 출력을 console에서 분리하는 방향이며 r1의 긍정 실험을 유지한다. bootstrap 전에 컴포넌트를 import하지 않는 명세와 fresh parent import 테스트도 타당하다. 결과 파일 저장은 console 비노출과 별도 보호 채널이다.
2. **프로토콜:** fstat 후 read(size)로 부모의 byte 수신 상한은 명확하다. descendant가 파일을 키워도 이미 정한 read 크기는 늘지 않는다. parent-only 락의 강제 종료 잔여는 솔직하게 명시됐다. 자식 입력은 exact NAMES/64hex/distinct 검사와 exit의 정확한 int 타입(bool 제외)을 구현 시 고정하는 편이 프로토콜 테스트를 명확하게 한다.
3. **R10 테스트:** 별도 전체 tick 프로세스·수동 fflush 없는 native 정상/예외 테스트는 원래 누출 시나리오를 닫는 명세다. rejected log-dir·partial write·op env 기존 회귀를 유지하는 것도 적절하다. 결과 저장 채널의 raw key 검사와 파일 수명 검사가 추가돼야 한다.
4. **레지스트리:** positional/keyword parameter binding과 dataclass reason_code, 간접 helper 처리는 r1보다 맞다. 동적 코드군의 RUNTIME_FAILED/type fallback·frozen 파일 제외·drift 검사는 유지할 수 있다. 실제 source의 이유 코드 참조 분류를 해결해야 한다.
5. **운영 제약:** op proxy/CA 허용목록·상위 log-dir symlink·기존 권한·타임아웃 없음은 의도된 잔여로 구분됐다. 실제 운영 의존성은 금지 범위여서 판단하지 않는다. 부모 강제 종료의 overlap은 core 프로젝트 락/launchd 그룹 정리와 wrapper 락을 구분해 운영 단계에서 판단해야 한다.

## 합성 확인 결과

```text
RAW_RESULT_CLI_FAILURE_EXIT 2
RAW_RESULT_IS_REGULAR_FILE True
RAW_RESULT_PRIVATE_MODE 0o600
RAW_RESULT_FILE_CONTAINS_SYNTHETIC_STORE_KEY True
RAW_RESULT_PARENT_WOULD_FILTER_KEY True
DECLARED_REASON_ALSO_IN_NON_REASON_CONTEXT_OCCURRENCES 9
R2_OVERSIZE_BYTES 5242880
R2_OVERSIZE_PARENT_READ_CALLS 0
R2_FORK_WORKER_NORMAL_EXIT True
R2_FORK_PARENT_RETURN_BEFORE_DESCENDANT True
R2_ANONYMOUS_FILE_LIVE_AFTER_PARENT_CLOSE True
R2_ANONYMOUS_FILE_HAS_NO_NAME True
R2_DESCENDANT_FINITE_COMPLETION True
```

첫 파일 수명 probe는 마커 파일이 생성 중인 순간 JSON을 읽어 driver의 JSONDecodeError가 났다. 마커를 temp 작성 후 rename으로 게시하도록 수정해 위 결과를 완료했다. 설계 결함으로 세지 않았다. 새 구현이 없는 설계 검토이므로 전체 consumer 회귀를 반복하지 않았다. 코드·테스트·원 설계는 수정하지 않고 이 판정 파일만 작성했다. commit·push·프로세스 kill·운영/외부 접근은 수행하지 않았으며 실제 키·본문은 미접촉이다.

**최종: REJECT (blocker 0, major 2, minor 1).** r3에서 결과 파일의 쓰기 전 정제와 reason-reference 분류/충돌 정책을 확정하면 major 0 여부를 재점검할 수 있다.
