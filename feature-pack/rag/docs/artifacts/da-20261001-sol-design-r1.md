model: gpt-6.1-sol
provider: headroom

# AIRAG U1 설계 DA r1/3 — REJECT (blocker 0, major 3, minor 2)

**판정: REJECT — blocker 0, major 3, minor 2.** 발주 #1772의 PASS 기준은 설계 major 0이다. 컴포넌트 프로세스 분리는 R10 native stdio 문제를 닫는 방향이며 합성 실험도 이를 지지한다. 다만 IPC 크기 제한·descendant fd 수명·레지스트리 생성 규칙이 현재 계약대로 구현되면 주요 보장과 테스트를 만족하지 못한다.

- 세션: `ft-airag-da-sol#1`, effort=high. 실행 헤더 model/provider는 위 두 줄. `[1m]` 여부는 미노출이다.
- 검토 파일: `.fable-team/state/airag-arch-claude/arch-20261001-item5-u1-design.md`.
- 설계 SHA-256: `18fbc4598bc681c9c07fd22d20595653b0c41330cb45dc307e56d727bc1953a2`.
- 코드 구현·source/test 수정은 하지 않았다. 기존 클래스/함수 시그니처는 Serena로 대조했고, 설계의 OS/IPC 계약만 독립 합성 스텁·임시 파일로 확인했다. 실제 op·운영 경로·키·DB·launchd·외부 endpoint는 미접촉이다.

## Major

### D1 — 8MiB 검사가 전체 수신 뒤여서 부모 메모리 상한을 보장하지 않는다

- 심각도: **major**.
- 위치: 설계 `:104-112`의 부모 subprocess.run/길이 검사; ⑤-7의 부모 payload 최대 8MiB 주장; T-oversize-result.
- 원인: subprocess.run(stdout=PIPE)는 communicate로 전체 stdout을 메모리에 모아 반환한다. 그 뒤 len(stdout)>8MiB를 검사하는 것은 이미 발생한 할당을 제한하지 않는다.
- 실험: 설계와 같은 run/PIPE/post-length-check로 유한 9MiB 합성 출력 자식을 실행했다. 부모가 받은 buffer는 **9,437,184바이트**였다. raw 내용은 출력하지 않았다.
- 영향: 큰/지속적인 프로토콜 출력에서 부모까지 메모리 고갈에 노출된다. 초과 후 RUNTIME_OUTPUT_INVALID가 나오는 테스트만으로 bounded 수신을 증명할 수 없다.
- 필요한 계약: byte 단위로 **수신 도중** 상한을 적용하는 framing/streaming과 초과 후 drain/종료/락 정리 정책을 정한다. 최대 capture 크기와 부모 peak 사용량을 확인하는 테스트를 추가한다. 자식 자신의 결과 생성 메모리 한계도 부모 상한과 구분한다.

### D2 — 비상속 fd도 fork에는 복제되어 결과 EOF·락 해제가 패스 종료와 어긋난다

- 심각도: **major**.
- 위치: 설계 `:92`, 자식 step 3/6, `:145`의 lock 상속·손자 close_fds 근거; 분류표 6·7·8.
- 원인: non-inheritable/CLOEXEC는 exec 시 닫는 속성이고 **fork 자체의 fd 복제를 막지 않는다**. 컴포넌트가 fork 후 exec하지 않는 손자를 만들면 result_fd와 lock_fd가 모두 남는다. subprocess 기본 close_fds=True만으로 네이티브 fork/daemon 경계를 통제할 수 없다. pass_fds로 받은 lock을 다시 non-inheritable로 바꾸는 것만으로도 이 fork 문제는 닫히지 않는다.
- 실험: 임시 flock을 worker에 전달했다. worker는 lock을 non-inheritable로 설정하고 비상속 result fd를 만들었다. fork 손자는 새 session에서 1초만 기다린 뒤 정상 종료했다. worker는 정상 결과를 쓰고 exit 0, 부모도 자기 lock fd를 닫았다. **손자가 살아 있는 동안 새 nonblocking flock은 실패했고, worker가 exit한 뒤에도 result EOF는 지연**됐다. 손자가 정상 종료한 뒤 둘 다 해제됐다. 무한 대기/kill/운영 프로세스는 사용하지 않았다.
- 영향: 패스가 완료됐어도 부모 run()이 EOF를 기다리거나 다음 틱이 계속 skipped가 될 수 있다. 명시적으로 인정한 고아의 존재와 별개로, 그 고아가 제어 채널/락의 수명까지 연장한다. launchd 그룹 밖으로 daemon화하는 경우는 기존 그룹 정리로 해결되지 않는다.
- 필요한 계약: 결과 수신 완료를 descendant의 EOF와 분리하고, 패스 락을 누가 어느 시점까지 보유하는지 정한다. 컴포넌트에 제어 fd를 주지 않는 감독 경계 또는 명확한 fork/descendant 지원 제한을 검토한다. parent 종료·worker 완료·fork-no-exec daemon·close_fds=False exec의 테스트가 필요하다.

### D3 — 첫 위치 인자 생성 규칙이 실제 이유 코드 인자 위치와 맞지 않는다

- 심각도: **major**.
- 위치: 설계 `:156`의 3.5-2 생성 규칙·수기 callee 검증, 3.5-3/4 닫힌 세계/드리프트 테스트.
- 실제 시그니처: `TickError(exit_code, code, kind='')`, `_id(value, code)`, `_absolute(value, code)`, `_identifier(..., code)`, `_regular(..., code)`는 이유 코드가 첫 인자가 아니다. `VerificationDecision(verified, reason_code)`도 두 번째 인자이며 keyword도 code가 아닌 reason_code다.
- 현재 source AST에서 확인한 코드 literal 위치(occurrence 수): TickError 첫 위치 0/뒤 위치 16, _id 0/8, _identifier 0/14, _absolute 0/6, _regular 0/6, VerificationDecision 0/4. 설계 규칙으로 이 **54개 occurrence**를 선언된 이유 코드로 잡을 수 없다. distinct 코드 개수라는 뜻은 아니다.
- 추가 불일치: VerificationDecision은 Exception subclass도 예외를 raise하는 helper도 아닌 dataclass다. _id/_absolute는 본문에서 직접 exception constructor를 raise/return하지 않고 _error(code)를 호출한다. 제안한 수기 helper의 직접 raise/return 검증과도 맞지 않는다.
- 영향: frozen 목록이 실제 선언을 빠뜨리거나 closed-world 테스트가 구현 시작부터 미분류로 실패한다. 이를 광범위 NON_REASON_CONTEXTS에 넣어 통과시키면 진짜 코드가 데이터로 분류되는 문제가 남는다.
- 필요한 계약: callee마다 **실제 signature의 code/reason_code 파라미터**를 positional/keyword 호출에 매핑하고 helper의 간접 raise 및 도메인 결정의 reason 필드를 구분한다. 분류 단위(값/각 literal occurrence), 우선순위, registry 자체 파일의 제외/분류도 명시한다. 두 번째 positional·reason_code keyword·간접 helper 테스트가 필요하다.

## Minor · 보장 표현 보정

### D4 — 부모가 sqlcipher를 import하지 않는다는 변경 계획과 현재 의존성이 맞지 않는다

- 심각도: **minor**.
- 위치: 설계 `:129`, I2/분류표 10의 근거, 3.3 import 변경 목록.
- 현재 tick은 `from .operations import KEY_NAMES`를 유지하며 operations는 top-level에서 sqlcipher3를 import한다. 새 프로세스에서 tick만 import해도 sqlcipher3가 sys.modules에 있었다.
- 보정: 부모의 경량 데이터/상수 경계를 변경 목록에 포함하거나, 주장 범위를 실제로 실행하지 않는 consumer pass까지로 한정한다. 이번 실험은 import 의존성을 확인한 것이며 실제 import가 값을 출력했다고 주장하지 않는다.

### D5 — 사설 fd의 불가시성과 모든 프로세스 env의 키 부재는 과대한 주장이다

- 심각도: **minor**.
- 위치: 설계 `:37`의 분류표 8, `:165`의 I3 및 후보 B의 불변식 설명.
- result_fd는 같은 worker 주소공간의 컴포넌트에 원리적으로 알 수 없는 자원이 아니다. fd 열거/상태 조회가 가능하며 non-inheritable은 접근 제어가 아니다. schema 검사로 malformed frame은 거부할 수 있지만 **valid-schema 위조까지 인증하는 것은 아니다**. trusted component의 예상 밖 standard-stream 출력을 막는 범위와 악의적 컴포넌트 격리를 구분해야 한다.
- 기존 env 키 우선 동작을 유지하면 부모의 기존 os.environ에 NAMES가 있을 수 있다. 자식 env에서 지우고 stdin으로 전달하는 것은 **새 자식에 key를 env/argv로 넣지 않는 보장**이며, 모든 기존 프로세스의 env에 없다는 I3는 아니다.
- 보정: 분류표 8은 사설 채널의 비밀성 대신 검증 범위·writer 신뢰 가정을 적는다. I3는 기존 env 예외와 wrapper가 새로 추가하는 노출의 범위를 명시한다.

## 분류표 11행과 테스트 판단

1. **1~5:** worker의 fd 1·2가 컴포넌트 import/실행 전부터 종료까지 /dev/null이고 부모의 stdout fd를 넘기지 않는다면 R10의 Python/C/native/direct-write 경계를 닫는 방향이다. bootstrap 순서를 필수 계약으로 고정해야 한다.
2. **6~8:** descendant의 standard stream이 /dev/null이라는 것과 제어 fd/락이 descendant에 남지 않는다는 것은 다른 문제다(D2). 분류표 8은 malformed-frame fail-closed에 한정하고 D1의 bounded 수신을 추가해야 한다.
3. **9:** 파일/소켓/syslog/os_log/tty를 범위 밖으로 명시한 것은 적절하다. 프로세스 분리를 hostile code sandbox로 표현해서는 안 된다.
4. **10~11:** 부모의 metadata whitelist 방향은 유지할 수 있지만 import 의존성(D4)·type의 신뢰 가정·초기 bootstrap/프로토콜 실패의 출력 경계를 구분한다. 기존 수준이라는 표현은 모든 BaseException을 부모가 정제한다는 뜻이 아니다.
5. **R10 테스트:** native-normal/native-exception을 별도 전체 틱 프로세스 단위로 보고 명시적 fflush 없이 정상 종료까지 포함하는 명세는 원래 재현을 닫는 데 맞다. 같은 프로세스 capfd만 쓰는 것으로 대체하면 안 된다. 여기에 bounded read, fork/EOF/락, signature별 registry 테스트가 추가돼야 design major 0을 판단할 수 있다.

## 합성 OS 실험 결과

```text
POST_CAPTURE_LIMIT_BUFFER_BYTES 9437184
POST_CAPTURE_LIMIT_ALREADY_OVER_8MIB True
FORK_WORKER_EXITED True
FORK_DESCENDANT_RETAINS_LOCK_AFTER_WORKER_EXIT True
FORK_NONINHERITABLE_RESULT_EOF_DELAYED True
FORK_RESULT_FRAME_VALID True
FORK_DESCENDANT_NORMAL_EXIT_RELEASED_LOCK True
CURRENT_TICK_IMPORTS_SQLCIPHER True
ISOLATED_WORKER_NORMAL_EXIT True
ISOLATED_WORKER_RESULT_VALID True
ISOLATED_WORKER_ALL_MARKERS_HIDDEN True
ISOLATED_WORKER_NO_MANUAL_NATIVE_FLUSH True
```

긍정 실험에서는 stdin의 합성 입력·비상속 result fd·영구 /dev/null stdout/stderr를 사용하는 독립 toy worker가 Python print·직접 fd write·libc printf marker를 숨기고 결과 frame만 전달했다. 이는 **출력 격리 방향만** 검증한 것이며, 아직 구현되지 않은 CLI/키/registry 통합 전체를 통과 판정한 것은 아니다. fd 수명 실험의 fork 손자는 유한 1초 후 정상 종료했으며 모든 락·pipe는 회수됐다. 소스 대조는 read-only였다.

**최종: REJECT (blocker 0, major 3, minor 2).** 설계 r2에서 D1 수신/초과 정책, D2 제어 fd/락 수명, D3 이유 코드 파라미터 모델을 확정하면 나머지 보장 표현과 테스트를 함께 재점검할 수 있다.
