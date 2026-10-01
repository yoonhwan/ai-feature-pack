model: claude-sonnet-5-5[1m]
provider: claude-code session (ft-airag-arch-claude#0, effort=high)

# AIRAG A02 5순위 U1 — 틱 래퍼 «값 비노출 경계» 설계 (R10-M1 · R10-m1 · 재발 방지)

골 원문: 최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
골의 어느 축인가: A03 닫는 증거 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — A02 트리 5순위 U1(C12·C07). DA r8→r9→r10 이 같은 값 비노출 경계에서 3연속 구멍 → HELM 규칙 #1752 로 architect 상향.

검토 대상: `feature-pack/rag-consumer/src/airag_consumer/tick.py` (HEAD fa94076, 345행) · `tests/test_tick.py` (436행). 이 설계에서 코드·테스트는 수정하지 않았다.
개정: r3+DA PASS 보정(R3-m1·m2·m3: 합성 코드 `XX_CODE`·Red 는 `not in` 단언·`_result`/잠정 `reason_codes` 를 S2 앞 S1b 로) · 개정: r3 — DA 설계 r2(`da-20261001-sol-design-r2.md`, REJECT major 2·minor 1) 반영: **R2-M1** 결과 파일에는 raw stdout/stderr 를 쓰지 않고 자식이 쓰기 «전» 에 순수 필터(`_result.py`)로 정제한 frame 만 기록·부모가 엄격 재검증(I7, 64 KiB 상한) · **R2-M2** 이유 코드 출현을 선언/참조/데이터 세 칸으로 분류하고 값의 다중 역할 공존은 허용·`code` 키 dict 항목은 선언·Compare 는 선언 집합 값만 참조 · **R2-m1** 익명 파일 수명 정정(마지막 fd close). 변경 절: 3.2·3.3·3.4·3.5·3.6·④·⑤7·⑥.
개정: r2 — DA 설계 r1(`da-20261001-sol-design-r1.md`, REJECT major 3·minor 2: D1 수신 상한·D2 fork 손자 fd/락·D3 이유 코드 파라미터 모델·D4 부모 import·D5 과대 주장) 반영. 변경 절: ①표 6~8·10·11 · ②B · ③3.2~3.6 전부 · ④ 테스트 추가 · ⑤ 2·3·7·11 · ⑥ 단계.
저장 위치 주석: 계약 경로 `feature-pack/rag/docs/artifacts/…` 는 architect 역할 가드(`ft-worker-guard.sh`, 허용 `designs/`·`state/`)가 거부해 이 경로에 둔다. Master 가 계약 경로로 복사한다.

---
## ① 문제 정의 · 보호 대상 출력 분류표

### 한 줄 진단
r8·r9·r10 은 서로 다른 구멍이 아니라 **같은 구조 결함의 세 얼굴**이다. 틱은 «컴포넌트(consumer 1패스)»를 **자기 프로세스 안에서** 실행하고, 그 컴포넌트가 만들 수 있는 모든 출력 경로(Python 객체 → libc FILE → fd → 자식)를 **틱 자신의 fd 1·2 를 잠깐 /dev/null 로 바꿔치기하는 방식**으로 막는다. 이 방식은
- 출력 계층이 하나 늘 때마다(r8: print·직접 fd → r9: 캐시된 Python stream → r10: libc stdio) «그 계층의 버퍼를 복원 전에 비우는 코드»를 하나씩 추가해야 하고,
- 비울 수 없는 계층(Rust·C++ 비동기화 stdio 등 다른 네이티브 런타임 자체 버퍼, 복원 전에 `dup` 해 둔 fd, 패스 뒤에도 도는 네이티브 스레드)은 원리적으로 닫을 수 없다.

«틱의 fd 를 바꿨다 되돌린다» 는 **부정(deny) 방식**이라 새 계층이 나올 때마다 구멍이 생긴다. 경계 방향을 **«컴포넌트에게 틱의 fd 를 처음부터 주지 않는다» 는 긍정(allow) 방식 = 프로세스 격리** 로 뒤집는 것이 권고다.

### R10-M1 원인 (코드 읽기 ↔ DA 실측 일치)
`tick.py:244-267` — 보관·flush 하는 것은 `sys.stdout/sys.stderr` **Python 객체** 둘뿐이다. libc `stdout` FILE 버퍼는 별개이고 `os.dup2(fd, 1)` 복원 «뒤» `fflush(NULL)`·프로세스 종료(`exit()` 의 libc 정리)에서 fd 1 로 나온다. `redirect_stdout(io.StringIO())` 는 Python 레벨 `sys.stdout` 만 바꾸므로 libc 와 무관하다.

### 보호 대상 출력 분류표
보호 목적: 컴포넌트(consumer 1패스 + bridge·memory·provider 호출)가 만들 수 있는 **값·본문·인용·키 후보** 가 **launchd 가 연결한 틱의 stdout/stderr(`launchd.out.log`·`launchd.err.log`)** 또는 틱 로그 파일로 새는 것을 막는다.

| # | 출력 종류 | 수명(어디에 머물다 언제 나오나) | 현 경계(in-process fd 바꿔치기) | 권고안(프로세스 격리) | 보장 |
|---|---|---|---|---|---|
| 1 | Python 객체 출력(`print`·`sys.std*.write`·`logging` StreamHandler) | Python 버퍼 → flush 시 그 프로세스 fd 1/2 | 부분(캐시된 stream 은 r9 에서 닫힘) | 컴포넌트 프로세스 fd 1·2 = /dev/null → 언제 flush 돼도 /dev/null | **보장** |
| 2 | libc stdio(`printf`·`fwrite`·`puts`, C 확장) | libc FILE 버퍼 → `fflush`/`exit()` 시 fd 1/2 | **구멍(R10-M1)** | fd 1/2 = /dev/null. 자식이 정상 종료하며 flush 해도 /dev/null | **보장** |
| 3 | 그 밖의 네이티브 런타임 버퍼(Rust·C++ `sync_with_stdio(false)`·Go 등) | 라이브러리 자체 버퍼 → fd 1/2 | **닫을 수 없음**(flush 호출 대상 없음) | 어떤 버퍼도 틱의 fd 에 닿지 못함 | **보장** |
| 4 | 직접 fd write(`os.write(1\|2)`·C `write`) | 즉시 | 부분(패스 동안 /dev/null) | fd 1/2 = /dev/null | **보장** |
| 5 | 패스 전에 `dup` 해 둔 틱 fd 에 쓰는 코드 | 즉시 | **구멍** | 컴포넌트는 틱의 fd 를 **상속받지 않음**(`close_fds`) | **보장** |
| 6 | 컴포넌트의 자식 프로세스(bridge 가 `subprocess`) | 컴포넌트의 fd 1/2 상속 | 부분 | 컴포넌트의 fd 1/2 = /dev/null 을 상속. 틱의 fd 는 없음 | **보장**(패스 종료 뒤 존속은 ⑤ 2번) |
| 7 | 패스 종료 «뒤» 에도 도는 네이티브 스레드·데몬·fork 손자 | 임의 시점 | **구멍** | 컴포넌트 프로세스와 함께 종료. 남은 손자는 fd 1/2 = /dev/null 만 쥠. **부모 완료 판정은 프로세스 종료(`wait`)** 라 손자의 fd 사본(result 파일·fork 복제 fd)이 완료·락을 지연시키지 않음(I6) | **표준 스트림 비노출 보장**(손자 존속 자체는 ⑤ 2번) |
| 8 | 결과 채널의 형식 오염(JSON 위 쓰레기·과대) | 부모가 만든 익명 임시 파일 | 해당 없음 | 크기를 먼저 보고(> 64 KiB 면 읽지 않음) 스키마 검증 실패 → `RUNTIME_OUTPUT_INVALID`(fail-closed, 값 에코 없음). **채널의 비밀성·위조 방지는 주장하지 않음**(같은 주소공간 컴포넌트는 fd 를 열거·위조할 수 있다 — 신뢰하는 컴포넌트의 우발 출력 범위, ③ 3.2 위협 모델) | **형식 오류 fail-closed 한정** |
| 9 | 컴포넌트의 파일·소켓·syslog·os_log·`/dev/tty` 쓰기 | 각자의 대상 | 범위 밖 | 범위 밖(프로세스 분리는 샌드박스가 아니다) | **보장 안 함**(⑤ 1번) |
| 10 | 틱 자신의 출력(JSON 한 줄·`log_unavailable`·`log_write_failed`·로그 파일) | `main` 이 직접 | whitelist | 동일 + **컴포넌트 코드가 틱 프로세스에서 실행되지 않음**(부모 import 그래프에 `cli`·`runtime`·`bridge`·`operations`·sqlcipher3 없음 — D4 로 `NAMES` 상수화) | **보장**(whitelist 범위 안) |
| 11 | 틱 프로세스 자신의 예외 traceback(`BaseException`)·초기 bootstrap 실패 | 인터프리터 | `except Exception` → type 만 | 동일. 컴포넌트·자식 프로토콜 실패는 정적 코드로만 보고(자식 stderr 는 DEVNULL). 부모의 `BaseException` traceback 은 «모든 BaseException 을 정제한다» 는 뜻이 아니라 컴포넌트 값을 담지 않는다는 기존 수준 | 기존 수준 유지 |

### 격리 전/후
- 전: 값 비노출이 «틱 프로세스가 컴포넌트를 자기 주소공간에서 돌리며 fd 를 임시로 비틀기» 에 의존 → 계층마다 패치.
- 후: **프로세스 경계 한 장** 에 의존. 컴포넌트가 틱의 fd·버퍼·메모리에 닿을 방법이 없다. 틱의 출구는 `main` 의 JSON 한 줄과 로그 파일뿐이고 그 내용은 `summarize` whitelist + 정적 이유 코드 레지스트리를 «자식이 쓰기 전에» 통과하고 부모가 재검증한 것만이다.

---
## ② 후보 비교

### 후보 A — 최소 패치: `libc fflush(NULL)` 추가 (현 구조 유지)
- 변경: `_discard_component_output` `finally` 에서 fd 복원 «전» `ctypes.CDLL(None).fflush(None)`(진입 직전 1회 포함). 8~10행.
- 장점: 변경 최소, 현재 DA 재현은 닫힘.
- 단점/리스크: 분류표 3·5·7번은 원리적으로 못 닫음 → **r11 에서 같은 부류의 새 구멍 가능성이 높음**. `ctypes.CDLL(None)` 이식성 주의, 호출 실패를 삼키면 조용히 무보호(silent fallback — DA 반박 엣지). 유지보수 모델이 여전히 «계층 추가 = 코드 추가».
- 판정: 요구 3(재발 방지) 미충족. 구조 변경이 불가할 때의 «최소 대안» 으로만 남긴다(⑤ 끝).

### 후보 B — 프로세스 격리 (권고)
컴포넌트 1패스를 **별도 자식 프로세스** 로 실행. 부모(틱)는 ① 자식 stdin 으로 **키 3개만** 전달(자식 env·argv 에 두지 않음) ② 자식 stdout = **부모가 만든 익명 임시 파일**(pipe 아님 — 크기를 읽기 전에 알고 완료는 프로세스 종료로 판정), stderr = **DEVNULL** ③ 자식은 컴포넌트 import 전에 자기 fd 1·2 를 /dev/null 로 돌리고 원래 stdout 을 복제해 «결과 JSON 한 덩어리» 만 거기에 씀 ④ 부모는 크기 확인 후 한 번 읽어 기존 `_counts`·`_error_fields` whitelist 로 JSON 한 줄·로그를 냄. 락은 부모만 보유. 위협 모델 = 신뢰하되 우발 출력이 많은 컴포넌트(샌드박스 아님).
- 장점: 분류표 1~8번을 **구조로** 닫음. `dup2` 바꿔치기·복원 순서·예외 경로·fd 누수 정리가 통째로 사라짐(`_discard_component_output` 30행 + `redirect_*` 제거). 복원할 fd 가 없어 «복원 순서» 문제 소멸.
- 단점/리스크: 틱마다 인터프리터 1회 추가 기동(5분 주기라 무시 가능; 부모는 `cli`·`runtime` 을 import 하지 않아 오히려 가벼움). 테스트의 `hooks=` in-process 시임이 프로세스 경계를 못 넘어 헬퍼 전환 필요(⑥ S3, 호출부 12~15곳). 새 실패 모드(자식 비정상 종료·프로토콜 위반·결과 과대·fork 손자·부모 강제 종료 시 고아 자식)를 설계로 처리하거나 ⑤ 에 한계로 명시(③). 키가 자식에게 가는 경로가 생기므로 stdin 전달로 «이 래퍼가 새로 만드는 자식의 env·argv 에 키가 없음» 을 유지(I3 — 기존 env 우선 정책으로 부모 env 에 이미 있는 키는 범위 밖).
- r2 변경(DA r1): pipe+`run()` 은 읽은 뒤 크기 검사(D1)·fork 손자의 fd 사본이 EOF·락을 지연(D2)시켜 **임시 파일 + 프로세스 종료 판정 + 부모 단독 락** 으로 교체.

### 후보 C — 출력 단일 출구 + 허용 필드 통과 (부분 구조)
`main` 의 출구만 JSON whitelist 로 제한(이미 대부분 구현). 컴포넌트 **스스로의** 출력 경로(분류표 1~7)는 그대로라 R10-M1 을 못 닫는다 → 후보 B 의 부분집합(10번 행)이므로 B 에 흡수.

### 비교 요약
| 기준 | A fflush | B 프로세스 격리 | C 단일 출구 |
|---|---|---|---|
| R10-M1 | 닫음 | 닫음 | 못 닫음 |
| 분류표 3·5·7 | 못 닫음 | 닫음 | 못 닫음 |
| 새 계층 출현 시 | 코드 추가 | 변경 불필요 | 해당 없음 |
| 규모 | 소(10행) | 중(+80행 −45행·테스트 헬퍼 전환) | 소 |
| 과대 보장 위험 | 높음 | 낮음(⑤ 로 한계 명시) | — |

**권고: 후보 B.** 근거 한 줄 — 값 비노출 보장의 근거가 «프로세스 경계 1장» 이어야 DA 가 계층을 새로 찾아도 설명이 바뀌지 않는다.

---
## ③ 권고안 — 프로세스 격리 (변경 위치·순서·예외 경로)

### 3.1 구성 요소
| 구성 요소 | 위치 | 책임 |
|---|---|---|
| 틱(부모) | `tick.py` (`main`·`_run_component` 신규) | 락·키 로딩(기존)·자식 기동·결과 검증·whitelist 출력·로그 |
| 패스 자식 | **신규** `src/airag_consumer/_pass_child.py` (`python -m airag_consumer._pass_child --config <path>`) | stdin 키 수령 → fd 1·2 /dev/null → `cli.main(["--config", cfg, "run", "--once"], …)` in-process → 결과 JSON 을 사설 fd 로 1회 write → 종료 |
| 이유 코드 레지스트리 | **신규** `src/airag_consumer/reason_codes.py` (frozen 데이터) | R10-m1 — 3.5 |
| 테스트용 자식 | **신규** `tests/_tick_component.py` (`_` 접두 = 수집 제외) | 합성 모드별 hooks 를 짜 `_pass_child.child_main` 호출 |

plist 주석상 `__PYTHON__` 는 «installed consumer runtime» 이라 `airag_consumer` 를 import 할 수 있다 → 기본 자식 명령 `[sys.executable, "-m", "airag_consumer._pass_child"]` 는 추가 설치 요구가 없다. **plist 변경 없음.**

### 3.2 자식 프로토콜 (r2 확정값 — D1·D2·D5 반영)

**위협 모델(D5):** 컴포넌트는 «신뢰하지만 예상 밖으로 말이 많은 코드»다(버그·라이브러리 print·네이티브 stdio). **악의적 코드를 가두는 샌드박스가 아니다.** 같은 주소공간의 컴포넌트는 fd 를 열거하거나 결과 frame 을 위조할 수 있다 — 이 설계는 그것을 막는다고 주장하지 않는다. 보장 범위 = «우발적 표준 스트림 출력이 틱의 launchd 로그로 새지 않음 + 형식이 틀린 결과는 fail-closed».

**결과 채널 = 부모가 만든 익명 임시 파일(pipe 아님):** `tempfile.TemporaryFile(dir=log_dir)`(검증된 0700 디렉터리 안·생성 즉시 unlink 되는 이름 없는 파일).
- **완료 신호 = 자식 프로세스 종료(`wait`)** 이지 pipe EOF 가 아니다 → fork 후 exec 하지 않은 손자가 result fd 사본을 쥐고 있어도 부모는 지연되지 않는다(D2).
- **부모는 읽기 전에 크기를 안다** — `fstat().st_size` 가 상한(`RESULT_MAX_BYTES = 64 KiB`; 정제된 frame 은 수백 바이트)을 넘으면 **한 바이트도 읽지 않고** `RUNTIME_OUTPUT_INVALID`. 읽을 때도 `read(size)` 한 번(≤ 상한). 수신 도중 상한(D1)이 구조적으로 보장되고 «이미 할당한 뒤 검사» 가 존재하지 않는다. 파일이라 초과 후 drain 도 필요 없다(자식이 막히지 않음).
- **R2-M1 — 결과 파일에는 «정제된 frame» 만 기록한다(원문 stdout/stderr 는 파일에 쓰지 않는다):** 컴포넌트의 raw CLI stdout/stderr 는 자식 **메모리(StringIO)에만** 존재하고, 자식이 파일에 쓰기 «전» 에 순수 필터(`_result.py`)로 `{exit, summary, code, type}` — 숫자·불리언·레지스트리 코드·type 만 — 로 정제한다. 따라서 U1 계약(«키를 파일·로그·plist 에 쓰지 않는다»)대로 **저장소 키·본문·경로 후보가 파일에 한 바이트도 기록되지 않는다**(익명·0600 은 부가 방어일 뿐 근거가 아니다). 부모는 받은 frame 을 같은 모듈의 `validate_frame` 으로 **재검증**한다(자식 결과를 신뢰하지 않음).
- 결과 파일 수명(R2-m1 정정): 이름 없는 파일은 **마지막 보유 fd 가 닫힐 때** 회수된다 — 부모 close 시점이 아니다. fork 손자가 result fd 를 쥐면 파일이 패스·부모보다 오래 살 수 있다. 내용이 값 없는 정제 frame 이므로 노출 위험은 없고 디스크 사용만 잔여다(⑤ 7).

**부모 → 자식**
- argv: `[*component_command, "--config", str(config)]` (경로만)
- env: 부모 `environment` 에서 `NAMES`(스토어 키 3개)를 **제거한** 사본(launchd 환경 `HTTPS_PROXY` 등은 기존 in-process 와 같은 범위로 상속). HELM #1764 의 `op` 자식 `OP_ENV_ALLOWLIST` 결정은 `op` 전용이라 무관·비충돌.
- stdin: `input=json.dumps({name: environment[name] for name in NAMES})`(< 1 KiB).
- stdout = 위 임시 파일 객체 · stderr = `DEVNULL` · `close_fds=True` · **`pass_fds` 없음**(락은 부모만 보유 — 3.4).
- 타임아웃 없음(기존 in-process 와 동일 정책, ⑤ 3번).

**자식 `child_main(argv=None, *, hooks=None) -> int`** — **bootstrap 순서는 필수 계약**(컴포넌트 import·실행 전에 fd 1·2 가 /dev/null 이어야 한다; `airag_consumer.cli` 는 3번 «이후» 에 import):
1. argv: `--config` 만(그 외 → 종료코드 2·무출력).
2. `sys.stdin.buffer.read(65_536 + 1)` — 한도 초과·JSON 아님·키 이름 집합이 **정확히 `NAMES`**(3개 전부·그 외 없음)가 아님·값이 `str` 아니거나 64자 hex(`_KEY` fullmatch) 아님·`bytes.fromhex` 기준 3개 값이 서로 다르지 않음 → 종료코드 2.
3. **fd 정리(한 번뿐·복원 없음):** `result_fd = os.dup(1)` → `null = os.open(os.devnull, O_WRONLY)` → `os.dup2(null, 1)`, `os.dup2(null, 2)` → `os.close(null)`. 이후 자식의 fd 1·2 는 영구 /dev/null. 실패 시 종료코드 2·무출력.
4. `from .cli import main as cli_main` (여기서 처음 import — sqlcipher·runtime·bridge 의 import-시점 출력도 이미 /dev/null).
5. `environ = {**os.environ, **keys}` — `cli.main(environ=…)` 에만 전달, `os.environ` 불변(컴포넌트의 손자는 키를 상속하지 않음).
6. `stdout_buffer, stderr_buffer = io.StringIO(), io.StringIO()`; `code = cli_main(["--config", cfg, "run", "--once"], environ=environ, hooks=hooks, stdout=…, stderr=…)`. `SystemExit`·`BaseException` 은 자식이 잡아 `code=2`, `stderr = {"ok":false,"error":{"code":"RUNTIME_FAILED","type":"<ClassName>"}}`(메시지 없음)로 대체.
7. **쓰기 전 정제(R2-M1):** `frame = _result.build_frame(code, stdout_buffer.getvalue(), stderr_buffer.getvalue())` — raw 문자열은 이 호출 안에서만 읽히고 frame 에는 담기지 않는다. frame = `{"exit": int, "summary": {허용 키: int|bool}, "code": 정적 코드 또는 "", "type": 정규식 통과 클래스명 또는 ""}`. `code`/`exit` 규칙: `cli_main` 이 0 이고 stdout 이 `{"data": dict}` 를 담은 JSON 이면 `exit=0` + `summary=summarize(data)`; 0 이 아니면 `exit=<값>` + `error_fields(stderr)`(레지스트리 통과 코드 or `RUNTIME_FAILED`, type); stdout 이 형식 위반이면 `exit=0` 대신 `code="RUNTIME_OUTPUT_INVALID"`. `json.dumps(frame)` UTF-8 바이트 길이가 `RESULT_MAX_BYTES` 를 넘으면(스키마상 불가능하지만 방어) **쓰지 않고 종료코드 3**. 아니면 `result_fd` 에 **부분 write 를 완료까지 반복**(0 반환 = 실패) → `os.close(result_fd)` → `return 0`. `os._exit` 는 쓰지 않는다(인터프리터 정리·sqlite finalizer 가 돌고 네이티브 flush 는 /dev/null 로). 이후 자식 메모리의 raw 버퍼는 프로세스와 함께 사라진다.
8. 종료코드: 0 = «프로토콜 전달 완료»(패스 성공 여부는 frame `exit`), 3 = 결과 과대, 그 외 = 프로토콜 실패.

**부모 `_run_component(config, environment, log_dir, command)`**
```
with tempfile.TemporaryFile(dir=log_dir) as result:
    subprocess.run(cmd, input=keys_json, env=child_env, stdout=result, stderr=DEVNULL,
                   close_fds=True, check=False)           # 완료 = 자식 프로세스 종료
    OSError (임시 파일 생성·기동)       → TickError(EXIT_RUNTIME, "COMPONENT_PROCESS_UNAVAILABLE")
    returncode == 3                     → TickError(EXIT_RUNTIME, "RUNTIME_OUTPUT_INVALID")
    returncode != 0                     → TickError(EXIT_RUNTIME, "COMPONENT_PROCESS_FAILED")
    fstat(result).st_size > RESULT_MAX  → TickError(EXIT_RUNTIME, "RUNTIME_OUTPUT_INVALID")   # 읽지 않음
    result.seek(0); data = result.read(size)
    frame = _result.validate_frame(json.loads(data))   # 엄격 스키마 재검증(R2-M1)
    파싱 실패 · validate_frame 실패(None)  → TickError(EXIT_RUNTIME, "RUNTIME_OUTPUT_INVALID")   # 에코 없음
frame["exit"] != 0                  → TickError(EXIT_RUNTIME, frame["code"], frame["type"])   # 둘 다 이미 정제·재검증됨
frame["code"] == "RUNTIME_OUTPUT_INVALID" (exit 0 이지만 형식 위반 표시) → 같은 TickError
frame["exit"] == 0                  → summary = frame["summary"]; summary["pass_elapsed_s"] = (기존)
```
`validate_frame`(순수): 키 집합이 정확히 `{exit, summary, code, type}`; `exit` 는 정확한 `int`(bool 제외); `summary` 키는 `SUMMARY_INT_KEYS`·`SUMMARY_BOOL_KEYS`(아래 3.3) 안이고 값은 각각 정확한 `int`/`bool`; `code` 는 `""` 이거나 `REASON_CODES` ∪ `{"RUNTIME_FAILED","RUNTIME_OUTPUT_INVALID"}`; `type` 은 `""` 이거나 `_TYPE` 정규식 통과·16자 hex 없음. 하나라도 어긋나면 `None`.
이후 `main` 의 JSON 한 줄·`append_log` 는 **기존 코드 그대로**(분류표 10번). 신규 정적 코드 2개(`COMPONENT_PROCESS_UNAVAILABLE`·`COMPONENT_PROCESS_FAILED`)는 `TickError` 의 `code` 파라미터 리터럴이라 3.5 선언 규칙에 자동 포함된다.

### 3.3 변경 위치 (HEAD fa94076 기준 `파일:라인`)
| 위치 | 변경 |
|---|---|
| `tick.py:11-27` import | `contextmanager, redirect_stderr, redirect_stdout`·미사용이 된 `io`·`lru_cache` 정리(`re`·`subprocess` 는 다른 곳이 쓰면 유지). 신규 `tempfile` |
| `tick.py:29-31` `from .operations import KEY_NAMES` / `NAMES` | **삭제 후 상수 대체(D4):** `NAMES = ("AIRAG_CONSUMER_KEY_HEX", "AIRAG_PROJECTION_KEY_HEX", "AIRAG_ARCHIVE_KEY_HEX")` 를 tick 에 직접 선언(현 `tuple(KEY_NAMES.values())` 와 같은 순서·값). `operations` 가 top-level 로 sqlcipher3 를 import 하므로 이 import 를 없애야 부모가 컴포넌트 의존성을 로드하지 않는다. 드리프트 방지 테스트 `T-names-match`(`tick.NAMES == tuple(operations.KEY_NAMES.values())`) |
| `tick.py:163-197` `_counts`, `tick.py:200-234` `_known_codes`·`_safe_code`·`_error_fields` | **구조 이동(별도 커밋 — Tidy First) + 교체:** 순수 신규 모듈 `_result.py` 로 옮긴다 — `summarize`(= `_counts`, 동작 불변), `error_fields`(= `_error_fields`+`_safe_code`; `_safe_code` 는 `_CODE` 정규식 + `value in REASON_CODES`, `rglob` 스캔·`import airag` 제거), `build_frame`(자식용), `validate_frame`(부모용), 상수 `SUMMARY_INT_KEYS`·`SUMMARY_BOOL_KEYS`(`summarize` 가 만들 수 있는 키의 닫힌 집합: int = `sources`·`accepted`·`gaps`·`committed_native_offset_total`·`pending_bytes_total`·`published_attempted`·`published_succeeded`·`memory_{attempts,candidate_count,materialized_count,awaiting_confirmation_count,unverified_count,conflict_count,rejected_count,batch_message_count}`·`archived`; bool = `coverage_complete`·`memory_enabled`·`memory_provider_called`·`backup_due`·`backup_created`; 부모가 더하는 `pass_elapsed_s` 는 frame 밖). `_result.py` 의 import = stdlib + `reason_codes` 뿐. `tick.py` 는 `_result` 를 import 해 쓴다 |
| `tick.py:237-267` `_discard_component_output` | **삭제** |
| `tick.py:270-274` `main` 시그니처 | `hooks` **삭제**, `component: Sequence[str] \| None = None` 추가(테스트 시임; 기본 `None` → `[sys.executable, "-m", "airag_consumer._pass_child"]`) |
| `tick.py:303-321` | `from .cli import main`·`stdout_buffer`·`with _discard_component_output(): …` 블록과 이어지는 `_error_fields`·`json.loads(stdout…)`·`_counts` 호출을 `frame = _run_component(config, environment, log_dir, component)` 한 번으로 교체(정제·재검증된 frame 만 받음) |
| `tick.py` 신규 `_run_component` | 3.2 부모(약 40행) |
| 신규 `_pass_child.py` | 3.2 자식(약 50행). 모듈 최상단 import 는 stdlib + `._result`; (4번 단계에서) `.cli` |
| 신규 `_result.py` | 위 행 — 순수(필터·frame) |
| 신규 `reason_codes.py` | 3.5 (순수 데이터 — import 없음) |

결과: 부모(`python -m airag_consumer.tick`)의 import 그래프 = stdlib + `tick` + `_result` + `reason_codes`. `cli`·`runtime`·`bridge`·`operations`·sqlcipher3 를 로드하지 않는다(`T-parent-imports` 로 검증) — 분류표 10번 근거.

### 3.4 순서 · 예외 경로 · 락 · 종료 순서
**정상 경로** (틱의 fd 1·2 는 한 번도 바뀌지 않는다):
`parse → log_dir 검증 → config 확인 → tick.lock flock → load_keys(op, 기존) → _run_component(임시 파일 생성 → 자식 기동 → bootstrap(stdin 키·fd 정리) → 패스 → 결과 1회 write → 자식 종료) → returncode·크기·frame 재검증 → JSON 한 줄(summary 는 frame 의 값 없는 숫자만) → append_log → lock_fd close`.

| 상황 | 틱 동작 | exit | 출력 |
|---|---|---|---|
| 임시 파일 생성·자식 기동 실패(`OSError`) | `COMPONENT_PROCESS_UNAVAILABLE` | 40 | 코드만 |
| 자식 비정상 종료(시그널·import 실패·종료코드 ≠ 0,3) | `COMPONENT_PROCESS_FAILED` | 40 | 코드만(자식 stderr DEVNULL) |
| 결과 과대(자식 종료코드 3 또는 파일 크기 > 상한)·형식 위반 | `RUNTIME_OUTPUT_INVALID` | 40 | 코드만 |
| 컴포넌트 예외(`cli.main` 이 2) | 자식이 `error_fields` 로 정제(레지스트리 통과 코드 or `RUNTIME_FAILED` + type)해 frame 에 기록, 부모가 재검증 | 40 | 코드·type |
| 컴포넌트 `BaseException`/`SystemExit` | 자식이 `RUNTIME_FAILED` + type 으로 대체해 전달 | 40 | `RUNTIME_FAILED`·type |
| 부모 내부 예외(`Exception`) | 기존 `except Exception` → type 만 | 50 | type 만 |
| 부모 `BaseException`(KeyboardInterrupt 등)·시그널 | 기존 수준 유지(부모는 컴포넌트 값을 보유하지 않음). launchd 가 job 을 멈추면 기본 `AbandonProcessGroup=false` 로 자식 정리 | — | — |

**락 소유(D2 재결정):** 락(`tick.lock` flock)은 **부모만** 보유하고 `pass_fds` 로 자식에 넘기지 않는다. 근거: 비상속(CLOEXEC) fd 도 `fork`(exec 없음)에는 복제되므로 자식 상속 방식은 «패스는 끝났는데 fork 손자가 락을 쥐어 이후 틱이 계속 skipped» 를 만든다(DA 실측). 부모는 `run()` 이 **자식 프로세스 종료까지** 블록하므로 락은 «패스 시작 전 ~ 자식 종료 후» 를 정확히 덮는다. 부모가 강제 종료(SIGKILL)되는 경우(launchd 정상 중지는 프로세스 그룹을 정리하므로 해당 없음 — 손 실행 한정)에는 자식이 락 없이 끝까지 돌 수 있다 — ⑤ 2번 잔여로 명시하며 «락이 고아 패스를 막는다» 는 주장을 하지 않는다.

**종료 순서:** 자식이 결과 write·close 후 정상 종료 → 부모 `run()` 반환(pipe EOF 를 기다리지 않음) → 크기 확인·읽기 → 임시 파일 close(회수). 네이티브 버퍼의 종료 시 flush 는 자식 fd 1·2 = /dev/null 로 간다. 복원할 fd 가 없어 «복원 순서» 문제가 존재하지 않는다. fork 손자가 패스 종료 뒤 남아도 부모 완료·락 해제는 지연되지 않는다(그 손자의 fd 1·2 도 /dev/null).

### 3.5 R10-m1 — 이유 코드 정의 vs 데이터 리터럴 (frozen 레지스트리 + 파라미터-이름 기반 선언 규칙 + 닫힌 세계 테스트) — D3 반영

**정정(DA D3):** r1 의 «첫 위치 인자» 규칙은 틀렸다. 실제 시그니처: `TickError(exit_code, code, kind)`·`_id(value, code)`·`_absolute(value, code)`·`_identifier(…, code)`·`_regular(…, code)` 는 `code` 가 두 번째 이후 위치이고, `VerificationDecision(verified, reason_code)` 는 dataclass 필드 `reason_code` 다. 따라서 **«인자 위치» 가 아니라 «파라미터 이름» 으로 선언을 정의한다.**

1. `reason_codes.py`: `REASON_CODES: frozenset[str]` — 정렬된 str 리터럴로 생성한 frozen 순수 데이터. 런타임은 이것만 본다(소스 읽기·`rglob`·`import airag` 없음).
2. **선언 규칙(분류 단위 = 리터럴 «출현»(occurrence), 레지스트리 단위 = 값):** 두 패키지(consumer·core) 소스를 AST 로 읽어 패키지 내 모든 `def`/`class` 의 **«코드 파라미터 바인딩 표»** 를 만든다.
   - 함수·메서드: 시그니처 파라미터 중 이름이 `code` 또는 `reason_code` 인 것 → (위치 인덱스, 키워드명).
   - 클래스: `__init__` 시그니처(상속 사슬에서 첫 정의), dataclass 는 필드 선언 순서에서 같은 이름 규칙.
   - **`Exception` 파생 클래스가 `code`/`reason_code` 파라미터를 가진 `__init__` 를 정의·상속하지 않으면** 첫 위치 인자(메시지)를 코드로 간주(`EventError("XX_CODE")` 관례 — 메시지가 코드라는 계약).
   `_CODE` 형태 str 리터럴 출현이 호출의 positional(위치 인덱스) 또는 keyword(키워드명)로 위 표의 코드 파라미터에 바인딩되면 «선언된 이유 코드 출현». 간접 helper(`_id`→`_error(code)`)는 `_id` 자체가 `code` 파라미터를 가지므로 호출부 리터럴이 바로 바인딩된다 — helper 본문의 raise 검증은 필요 없다. 도메인 결정 dataclass(`VerificationDecision.reason_code`)는 이름 규칙으로 포함한다(실제 이유 코드로 보고되는 값).
   **추가 선언 문맥(R2-M2):** dict 리터럴의 항목 중 **키가 `"code"` 또는 `"reason_code"`** 인 str 리터럴 값(`{"code": "VALIDATION_ERROR", …}` 형태의 응답 — 예: `airag/api.py:61·63·65·87`)도 «선언된 이유 코드 출현» 이다(이 값들은 오류 응답으로 실제 보고되는 코드다).
   **한계:** `*args`·`**kwargs` 전개·변수 전달(리터럴 아님)·`functools.partial` 호출은 바인딩하지 못한다 → 선언 출현으로 세지 않는다(과소 포함 = 안전 방향).
3. **닫힌 세계 테스트 — 출현 분류 «세 칸»(R2-M2: 선언 / 참조 / 데이터):** 두 패키지 소스의 **모든** `_CODE` 형태 리터럴 출현은 정확히 하나로 분류돼야 한다.
   - **선언(declaration)** — 위 2번 규칙(파라미터 바인딩·`code`/`reason_code` 키 dict 항목).
   - **참조(reference)** — **Compare**(`==`·`!=`·`in`) 피연산자 리터럴 중 값이 이미 «선언» 집합에 있는 것(예: `error.get("code") == "NOT_FOUND"` `bridge.py:164`·`collector.py:753 STALE_COLLECTOR_CURSOR`). 참조는 **이미 선언된 값만 가리킬 수 있고 새 허용값을 만들지 않는다**(레지스트리 불변). 선언 집합에 없는 값의 Compare 리터럴은 참조가 아니라 **데이터**(예: 환경변수명 비교)로 분류한다.
   - **데이터(data)** — Dict 의 `code`/`reason_code` 이외 키·값, Subscript, `code`/`reason_code` 가 아닌 keyword 인자, **이름이 열거된** 비-에러 호출(`getattr`/`get`/`startswith`/`execute`/`convert`/`normalize`/`new` 등), 선언 집합에 없는 Compare 리터럴.
   - **구조 문맥**(Tuple·List·Assign·IfExp·Return·BoolOp·JoinedStr)의 출현은 자동 분류하지 않고 수기 검토 파일 `tests/reason_code_review.py` 의 `(상대경로, 줄, 값) → "reason"|"reference"|"data"` 항목으로만 분류 가능(항목마다 한 줄 근거). 약 40 출현을 Nano 가 한 번 분류한다.
   - 어디에도 없으면 **테스트 실패**(미분류).
   **충돌 정책:** 같은 «값» 이 선언·참조·데이터 여러 역할로 공존하는 것은 **실패가 아니다**(공개 literal 의 합법적 data 사용 허용). 판정 단위는 «값» 이 아니라 **출현의 문맥** 이다. 실패 조건은 ① 미분류 ② 수기 파일 항목이 선언 규칙과 모순(예: 수기 `data` 로 적은 출현이 규칙상 «선언») ③ 수기 `reference` 의 값이 선언 집합에 없음. 레지스트리에 값이 들어가는 길은 **선언 출현 또는 수기 `reason`** 두 가지뿐이다.
4. **드리프트 테스트:** `REASON_CODES == { 선언 출현의 값 } ∪ { 수기 reason 값 }`(참조·데이터는 기여하지 않음). 어긋나면 재생성 명령이 담긴 메시지로 실패(생성 로직은 테스트 헬퍼 한 곳 `tests/_regen_reason_codes.py`, `__main__` 으로 재생성). **스캔 제외:** `reason_codes.py` 자체(전부 리터럴이라 자기 자신을 오염)와 `tests/`.
5. **범위·한계(박제):** 레지스트리 = «소스가 **상수 문자열로 코드 파라미터에 바인딩한** 이유 코드 + 수기 검토 reason». 동적 코드군(`INVALID_{FIELD}`·`CORE_*_FAILED:{code}`)은 레지스트리 밖 → 틱 출력에서 `RUNTIME_FAILED` + type 으로 대체(진단 손실이지 비밀 노출 아님, 안전 방향 과차단). 환경변수명·일반 대문자 상수는 구조적으로 제외된다(R10-m1 재현 `OP_SERVICE_ACCOUNT_TOKEN`·`PATH` 거부).
6. 거부한 대안: ⒜ 런타임 AST(매 틱 소스 파싱·읽기 실패 시 목록 축소) ⒝ 예외 클래스 type 만으로 신뢰(`JsonlError(str(exc), …)`·`WrongKeyOrForeignDatabase(f"…{path}…")` 는 앱 클래스인데 메시지에 데이터) ⒞ 코드 에코 폐지(진단성 손실 과대) ⒟ r1 의 «첫 위치 인자» 규칙(DA D3 — 실제 시그니처 불일치로 폐기).

### 3.6 설계 불변식 (DA 가 시험할 항목 — r2 범위 정정)
- I1: 틱 프로세스의 fd 1·2 는 `main` 진입부터 종료까지 **어떤 `dup2` 도 받지 않는다**(전후 `os.fstat(1/2)`·열린 fd 개수 동일).
- I2: 틱(부모) 프로세스는 `cli`·`runtime`·`bridge`·`operations`·sqlcipher3 를 import 하지 않는다 — **컴포넌트 코드가 틱 프로세스에서 실행되지 않는다**(D4: `NAMES` 상수화로 성립, 신선한 인터프리터에서 `sys.modules` 로 검증).
- I3: **이 래퍼가 새로 만드는 자식 프로세스의 argv·env 에는 스토어 키가 없다**(env 에서 제거·stdin 전달). 범위 한정: «기존 env 키 우선» 정책으로 부모 `os.environ` 에 이미 있는 키는 부모 env 에 그대로 존재하며 이 래퍼가 그것을 지우거나 새로 노출하지 않는다. 컴포넌트의 손자(`os.environ` 불변)도 키를 상속하지 않는다. `op` 자식 env 는 기존 `OP_ENV_ALLOWLIST` 그대로.
- I4: 자식 프로토콜 위반·비정상 종료·결과 과대는 **정적 코드** 로만 보고되고 자식 출력은 한 글자도 에코되지 않는다. 부모는 결과 파일을 **상한 이하로만** 읽고 frame 을 엄격 스키마로 재검증한다.
- I7 (R2-M1): **결과 파일에는 컴포넌트의 raw stdout/stderr 가 한 바이트도 기록되지 않는다.** 파일 내용은 `{exit, summary(int|bool), code(정적), type(정규식 통과)}` 뿐이다. 이것이 U1 계약(«키를 파일·로그·plist 에 쓰지 않는다»)이 프로세스 격리 뒤에도 유지되는 근거다.
- I5: 틱이 낼 수 있는 값은 `summarize` whitelist(`SUMMARY_INT_KEYS`·`SUMMARY_BOOL_KEYS`) + `REASON_CODES` + type(`_TYPE` 정규식, 16-hex 거부) + 숫자/플래그뿐이다. `type` 은 컴포넌트가 던진 클래스명이며 «데이터를 담지 않는다» 는 신뢰 가정이다(⑤ 6번).
- I6: 패스의 **완료 판정은 자식 프로세스 종료** 이며 result fd 의 descendant 상속과 무관하다(fork 손자가 남아도 부모는 지연되지 않고 락도 손자가 쥐지 않으므로 다음 틱이 skipped 되지 않는다).

---
## ④ 테스트 명세 (Nano Red→Green)

**공통 금지:** 실제 `op`·1Password·`~/.local/share/airag`·launchd·운영 경로·외부 endpoint 접촉 금지. 값은 합성 fixture·`tmp_path` 에만. 합성 marker 는 `MARKER_` 접두. 테스트는 값 대신 boolean·수·종료코드만 단언한다.

### 4.0 테스트 지원 파일 (신규)
`tests/_tick_component.py` — 자식 스크립트. 사용 `[sys.executable, <이 파일>, <mode>]`; 부모가 뒤에 `--config <path>` 를 붙인다. 구현: `sys.path` 에 `src`·`tests` 추가 → `from airag_consumer._pass_child import child_main` · `from test_runtime import SyntheticBridge, DecisionExtractor` → `child_main(sys.argv[2:], hooks=<mode 별 RuntimeHooks>)`.

| mode | 동작 |
|---|---|
| `normal` | `SyntheticBridge` (기존 정상 합성) |
| `memory` | `SyntheticBridge` + `DecisionExtractor` (기존 `memory=True`) |
| `chatty` | 기존 `ChattyBridge`(print·`sys.stderr.write`·`os.write(1\|2)`) 후 정상 진행 |
| `native` | libc `printf`(합성 marker, **`fflush` 호출 안 함**) + Python print + `os.write` 후 정상 진행 — `ctypes.CDLL(None)` |
| `native-raise` | 위 native 출력 후 `RuntimeError("inside")` |
| `keylike` | 기존 `RaisingBridge`(`RuntimeError(KEYLIKE)`) |
| `short` | 기존 `ShortValueBridge` |
| `envname` | `RuntimeError("OP_SERVICE_ACCOUNT_TOKEN")` (R10-m1 재현) |
| `declared` | 선언된 이유 코드 예외(`REASON_CODES` 의 코드 하나를 앱 예외로) |
| `bad-protocol` | `child_main` 호출 없이 stdout(=결과 파일)에 비-JSON 쓰고 종료코드 0 |
| `bad-protocol-large` | stdout(=결과 파일)에 `RESULT_MAX_BYTES`(64 KiB)보다 큰 **유한** 바이트(예: 1 MiB)를 쓰고 종료코드 0 |
| `huge-raw` | 정상 컴포넌트가 5 MiB 의 비-JSON raw stdout 을 만든다(정제 frame 은 작아야 함 — raw 크기가 결과 파일에 영향 없음) |
| `body-in-output` | 합성 «본문·인용·경로» 문자열(`MARKER_BODY`·`MARKER_QUOTE`·`/synthetic/path`)을 `data` 의 문자열 필드로 담아 정상 종료하는 bridge(raw stdout JSON 에는 존재, whitelist 에는 없음) |
| `crash` | 자기 프로세스에 SIGKILL 시그널 전송 |
| `fork-descendant` | 결과를 정상 기록·정상 종료하기 «전» 에 `os.fork()`(exec 없음)로 손자를 만들고, 손자는 **유한 3초** sleep 후 `tmp` 마커 파일을 쓰고 종료한다(손자는 부모의 result·stdin 등 fd 사본을 보유). 손자가 자기 fd 1·2 로 `MARKER_DESC` 를 쓰는 변형 `fork-descendant-chatty` 포함 |
| `env-probe` | `NAMES` 가 `os.environ` 에 있는지, 손자(`subprocess.run([sys.executable,"-c",…])`)의 env 에 있는지를 임시 파일에 boolean 으로 기록 후 정상 진행 |

테스트 환경 헬퍼: `base_environment()` 에 `PYTHONPATH=<src>:<tests>` 를 더해 자식이 `airag_consumer` 를 import 하게 한다(패키지는 venv 에 설치돼 있지 않고 pytest `pythonpath=["src"]` 에만 있음 — 자식에는 env 로 전달 필요; 코어 `airag` 는 venv 의 editable `.pth` 로 이미 import 가능). 키 3개는 `base_environment()` 에 없고 기존 `credentials()`+`stub_op` 경로로 채워진다.

### 4.1 Red 선행 재현 (현 코드에서 실패해야 함 — S1)
**T-R10M1-native-red** (실제 `tick.main` 자식 프로세스): 부모 테스트가 `[sys.executable, "-c", <코드>]` 를 `subprocess.run(capture_output=True)` 로 실행. 자식 코드는 `tick.main(args, environ=…, clock=…, hooks=RuntimeHooks(bridge=NativeBridge()))` 를 호출, `NativeBridge.publish_pending_windows` 안에서 `ctypes.CDLL(None).printf(b"MARKER_NATIVE\n")` 후 원래 작업 계속(명시적 `fflush` 없음 — 종료 시 libc 정리에 맡김). 단언(목표 동작): 자식 exit 0 이고 **`b"MARKER_NATIVE" not in proc.stdout`** — 현 코드에서는 marker 가 나와 이 단언이 **실패**한다(= Red). «marker present=True» 관찰은 별도 증거로 로그에만 남긴다. S3 에서 `hooks` 가 사라지므로 이 테스트는 4.2 의 T-native-* 로 **교체**된다.

### 4.2 Green 후 상시 테스트
| ID | 대상 | 방법 | 단언 |
|---|---|---|---|
| T-native-normal | R10-M1 정상 경로 | 부모 테스트가 **별도 자식 Python** 으로 `tick.main(…, component=[py, _tick_component, "native"])` 실행·capture | 자식 exit 0 · stdout 정확히 1줄(틱 JSON, status ok) · stdout/stderr 전체에 `MARKER_` 없음 |
| T-native-exception | R10-M1 예외 경로 | 같은 방식, mode `native-raise` | exit 40 · `RUNTIME_FAILED` + `RuntimeError` · `MARKER_` 없음 |
| T-direct-and-py | r8 회귀 | `capfd`, mode `chatty` | `MARKER_` 없음 · 틱 JSON ok |
| T-parent-fds-untouched | I1 | `main` 전후 `os.fstat(1/2)` 의 `(st_dev, st_ino)` + `len(os.listdir("/dev/fd"))` 비교 — 정상·예외(`native-raise`)·기동 실패(없는 `component`) 3경로 | 모두 동일(R9-m1 fd 누수 테스트 대체) |
| T-keys-not-in-env-or-argv | I3 | `subprocess.run` spy(`monkeypatch`)로 **컴포넌트 호출만** 가로채 kwargs 기록 후 실제 호출 | `env` 에 `NAMES` 없음 · argv 에 키 값 부분문자열 없음 · `input` JSON 에 `NAMES` 3개 · **`pass_fds` 미사용**(또는 빈 값) · `stdout` 은 임시 파일 객체(pipe 아님)·`stderr=DEVNULL`·`close_fds=True` |
| T-keys-not-in-grandchild | I3 | mode `env-probe` + 기록 파일 | 자식 `os.environ`·손자 env 모두 `NAMES` 없음 |
| T-protocol-violation | I4 | mode `bad-protocol` | exit 40 · `RUNTIME_OUTPUT_INVALID` · 쓰레기 문자열 출력·로그에 없음 |
| T-oversize-result-bounded-read | I4·D1 | mode `bad-protocol-large`(1 MiB > 64 KiB) — 결과 파일 객체의 `read` 를 감싼 spy(또는 `tempfile.TemporaryFile` 대체 래퍼)로 호출 인자 기록 | `RUNTIME_OUTPUT_INVALID` · **결과 파일에 대한 `read` 호출 0회**(크기 확인 단계에서 거부) · 부모 `ru_maxrss` 비교는 불안정하므로 쓰지 않는다 |
| T-child-oversize-frame-exit3 | I4·D1 | 단위: `_result.RESULT_MAX_BYTES` 를 작게 `monkeypatch` 한 `child_main`(별도 자식 Python) | 종료코드 3 · 결과 fd 에 아무것도 쓰지 않음 · 틱 쪽 매핑은 `RUNTIME_OUTPUT_INVALID` |
| T-raw-output-not-persisted | **R2-M1·I7** | `subprocess.run` spy 가 **컴포넌트 호출이 끝난 직후** `kwargs["stdout"]`(결과 파일) 의 전체 바이트를 `os.pread` 로 캡처(부모가 닫기 전). 모드 `keylike`(`RuntimeError(KEYLIKE)` — raw stderr 에 키 형태 값), `short`, `chatty`, `huge-raw`, `body-in-output`, `normal` 각각 | 캡처 바이트에 ① 합성 저장소 키 3개 hex(대·소문자) ② `KEYLIKE` ③ `MARKER_`(`MARKER_BODY`·`MARKER_QUOTE` 포함) ④ `/synthetic/path` 가 **없음** · `json.loads` 가 `validate_frame` 통과 · 키 집합이 정확히 `{exit,summary,code,type}` · 크기 ≤ 64 KiB |
| T-frame-validate | R2-M1 | `_result.validate_frame` 단위 | 거부: 추가 키·`exit=True`(bool)·모르는 summary 키·summary 값이 str/`True` 가 int 키에·`code` 가 레지스트리 밖·`type` 에 16자 hex·비-dict. 수락: 정상 frame(성공·실패 각 1) |
| T-parent-revalidates | R2-M1 | mode `forged-frame`(스키마는 맞지만 `code="OP_SERVICE_ACCOUNT_TOKEN"` 같은 레지스트리 밖 코드, 또는 추가 키)를 결과 파일에 직접 쓰고 정상 종료 | exit 40 · `RUNTIME_OUTPUT_INVALID` · 해당 문자열 출력·로그에 없음 |
| T-fork-descendant-no-delay | D2·I6 | mode `fork-descendant`; 부모 `tick.main` 호출 직후(손자의 3초 sleep 만료 전) | 틱 exit 0 · **마커 파일이 아직 없음**(= 손자 종료를 기다리지 않음) · 이어서 같은 log-dir 로 `tick.main` 재호출이 `PREVIOUS_TICK_RUNNING`(10)이 **아님**(락을 손자가 쥐지 않음) · 3초 후 마커 존재(손자가 유한 종료)로 정리 확인 |
| T-fork-descendant-holds-result | R2-m1 | mode `fork-descendant`(손자가 결과 파일 fd 사본을 쥔 채 3초 유지; 손자가 부모 close 후 `fstat(fd)` 로 `st_nlink == 0`·regular 인지와 **파일 내용이 값 없는 frame(스키마·금지 문자열 부재)** 인지를 확인해 마커 파일에 boolean 기록) | 마커의 «파일 생존(nlink 0)» True·«내용 값 없음» True — 수명 주장은 «마지막 fd close» 로 정정됐고 내용은 안전함을 고정 |
| T-fork-descendant-streams | 분류 6·7 | mode `fork-descendant-chatty`; 별도 자식 Python 으로 `tick.main` 실행·capture | 자식 stdout/stderr 에 `MARKER_DESC` 없음(손자 fd 1·2 = /dev/null) |
| T-parent-imports | I2·D4 | 신선한 인터프리터에서 `import airag_consumer.tick` 후 `sys.modules` 검사(PYTHONPATH 환경) | `airag_consumer.cli`·`runtime`·`bridge`·`operations`·`sqlcipher3` 모두 없음 |
| T-names-match | D4 | 일반 테스트 프로세스에서 비교 | `tick.NAMES == tuple(operations.KEY_NAMES.values())` |
| T-child-bootstrap-order | 자식 계약 | `_pass_child` 모듈 안의 `cli` import 직전 지점을 `monkeypatch`/주입 훅(테스트 전용 모드 `import-probe`: import 직전 콜백이 fd 1·2 가 /dev/null 인지 `os.fstat` 의 `(st_dev, st_ino)` 를 `os.devnull` 과 비교해 임시 파일에 boolean 기록) | `cli` import 시점에 fd 1·2 == /dev/null |
| T-child-crash | I4 | mode `crash` | exit 40 · `COMPONENT_PROCESS_FAILED` |
| T-child-unavailable | I4 | `component=["/nonexistent/python"]` | exit 40 · `COMPONENT_PROCESS_UNAVAILABLE` · 락 해제(다른 fd 로 `flock(NB)` 성공) |
| T-child-import-failure | I4 | 기본 명령 + `PYTHONPATH` 비움 | exit 40 · `COMPONENT_PROCESS_FAILED` · `capfd` 에 traceback 없음 |
| T-lock-held | 락 | 같은 log-dir `tick.lock` 보유 상태 호출 | exit 10 · 컴포넌트 `subprocess.run` 호출 0회(spy) |
| T-default-command | 기본 명령 배선 | `component=None` 일 때 spy 가 받은 argv 앞 3개 == `[sys.executable, "-m", "airag_consumer._pass_child"]` + `subprocess.run([py,"-c","import airag_consumer._pass_child"], env={PYTHONPATH:…})` 성공 | — |
| T-child-protocol-unit | 자식 단위 | `_pass_child.child_main` 을 별도 자식 Python 으로 실행(stdin 에 합성 키 JSON, stdout=임시 파일) | 결과 파일이 정확히 1개 JSON frame(`exit`·`summary`·`code`·`type`) · stdin 입력 검증 거부(종료코드 2·결과 비어 있음): 키 집합이 `NAMES` 와 정확히 같지 않음(누락·초과)·값이 비-str·64hex 아님·3개 값 중 중복·입력 > 64 KiB |
| T-registry-drift | R10-m1 | 테스트 헬퍼가 소스를 AST 로 읽어 3.5-2 «파라미터 이름 바인딩» 규칙 적용(스캔 제외: `reason_codes.py`·`tests/`) | `REASON_CODES == 선언 출현 값 ∪ 수기 reason 값` |
| T-registry-closed-world | R10-m1·D3 | 모든 `_CODE` 리터럴 «출현» 을 선언 / 참조 / 데이터 / 수기 검토 중 하나로 분류 | 미분류 0 · 수기 항목이 규칙과 모순(선언을 data 로 적음·선언 집합에 없는 값을 reference 로 적음) 0 · **값의 다중 역할 공존은 실패 아님** |
| T-registry-reference-baseline | **R2-M2** | 현재 소스 baseline: DA r2 가 확인한 «선언 값 = Compare/Dict 내 출현» 9곳(`bridge.py:164 NOT_FOUND`·`collector.py:753 STALE_COLLECTOR_CURSOR`·`airag/api.py:61 KEY_OR_DB_VERIFICATION_FAILED`·`:63 UNSUPPORTED_SCHEMA_VERSION`·`:65 DATABASE_ALREADY_EXISTS`·`:87 VALIDATION_ERROR` 외 3곳) + 같은 public literal 의 합법적 data 사용 | 모두 실패 없이 분류됨(dict `"code"` 키 항목 = 선언, Compare = 참조) · 이들이 `REASON_CODES` 를 넓히지 않음(참조 제거 후 레지스트리 동일) |
| T-registry-reference-no-widen | R2-M2 | 합성 소스: ① 선언 없는 값 `OP_SERVICE_ACCOUNT_TOKEN` 의 Compare ② 선언된 값의 Compare ③ `{"code": "XX_CODE"}` dict 항목 | ① data(레지스트리 밖) ② reference(레지스트리 불변) ③ 선언 |
| T-registry-binding | D3 | 합성 소스 조각(AST 입력 문자열)으로 규칙 단위 검증 | **두 번째 positional**(`TickError(40, "XX_CODE")`·`_id(v, "XX_CODE")`) 선언됨 · **`reason_code` 키워드/필드**(`VerificationDecision(True, reason_code="XX_CODE")`) 선언됨 · 간접 helper(`def _id(value, code): raise _error(code)`) 호출부 리터럴 선언됨 · `code` 파라미터 없는 `Exception` 파생의 첫 positional 선언됨 · `getattr(x, "ABC")`·dict 키·Compare 는 선언 아님 · `*args`/변수 전달은 선언 아님 |  ※ 합성 예시 값은 `_CODE` 형태(`[A-Z][A-Z0-9_]{1,100}`)를 만족하는 2자 이상(`XX_CODE`)만 쓴다 — 한 글자(`X`)는 최종 형태 필터에서 탈락한다(R3-m1).
| T-registry-excludes-data | R10-m1 | `OP_SERVICE_ACCOUNT_TOKEN`·`PATH`·`HOME`·`AIRAG_CONSUMER_KEY_HEX`·`BMP` | `REASON_CODES` 에 없음 |
| T-envname-code-rejected | R10-m1 재현 | mode `envname` | exit 40 · `RUNTIME_FAILED` · `RuntimeError` · 환경변수명 출력·로그 없음 |
| T-declared-code-kept | 과차단 방지 | mode `declared` | 선언 코드 그대로 보존 |
| T-registry-no-source-read | 읽기 실패 무관 | `Path.read_text`·`Path.rglob` 을 예외화한 뒤 `_result.error_fields` 로 선언 코드 처리 | 코드 보존 |
| T-short-and-keylike | r8/r9 회귀 | mode `keylike`·`short` | `RUNTIME_FAILED` · 값 비노출(기존 단언 그대로) |
| T-existing-suite | 기존 r8~r10 회귀 | `run_tick(…, hooks=…)` → `run_tick(…, mode=…)` 헬퍼 전환(S3) | 전부 통과 |

### 4.3 native 재현 구현 힌트
`ctypes.CDLL(None).printf(b"MARKER_NATIVE\n")` 는 stdout 이 pipe 일 때 **전체 버퍼링** 이라 `fflush` 전엔 fd 로 나가지 않는다 — DA 재현의 전제와 동일. 인터프리터 종료의 libc 정리까지 포함하려면 **자식 프로세스 단위** 로 확인해야 한다(`capfd` 는 같은 프로세스라 부족). 그래서 T-native-* 는 «부모 테스트 → 별도 자식 Python 이 실제 `tick.main` 실행 → 자식의 raw stdout/stderr 를 부모가 메모리에서 boolean 검사» 구조다.

---
## ⑤ 보장하지 않는 것 (잔여 위험 — 과대 보장 금지)

1. **컴포넌트의 비-표준-스트림 출구**(분류표 9): 컴포넌트가 스스로 여는 파일·소켓·syslog·`os_log`·`/dev/tty` 쓰기는 막지 않는다. `/dev/stdout`·`/dev/fd/1` 재열기는 자식의 fd 1 = /dev/null 을 가리켜 안전하다.
2. **고아·손자 프로세스 존속과 락:** 컴포넌트가 손자를 데몬화하거나 fork 하면 패스 종료 뒤에도 살 수 있다(그 fd 1·2 는 /dev/null 이라 launchd 로그로는 안 가고, 부모 완료·락 해제는 지연되지 않는다 — I6) 하지만 **존재 자체는 못 막는다.** 또한 **락은 부모만 보유**하므로 부모가 강제 종료되면(launchd 정상 중지는 기본 `AbandonProcessGroup=false` 로 그룹을 정리하므로 해당 없음 — 손 실행 한정) 자식 패스가 락 없이 끝까지 돌 수 있고 그동안 다음 틱이 겹칠 수 있다. 이 설계는 «락이 고아 패스를 막는다» 를 주장하지 않는다(자식 락 상속은 fork 손자가 락을 쥐는 더 나쁜 결과를 내 철회 — D2).
3. **타임아웃 없음:** 기존 in-process 와 동일하게 패스 시간 상한이 없다(정책 변경 아님). 자식이 멈추면 부모가 `run()` 에서 블록하고 부모가 락을 보유하므로 이후 틱은 `PREVIOUS_TICK_RUNNING` 으로 건너뛴다 — 정지 감지·kill 은 운영 정책이며 이 설계 범위 밖(kill 은 HIL).
4. **동적 이유 코드군 진단 손실:** `INVALID_{FIELD}`·`CORE_*_FAILED:{code}` 등은 레지스트리 밖 → `RUNTIME_FAILED` + type 만 남는다(안전 방향 과차단). 진단성이 필요하면 해당 생성자를 정적 코드로 바꾸는 별도 작업(인접 리팩터 — 제안만).
5. **레지스트리 신선도:** 드리프트·닫힌 세계 테스트로 소스와의 일치가 강제되지만, 테스트 없이 소스만 바꾸면 틱은 구 레지스트리로 동작(안전 방향: 신규 코드는 `RUNTIME_FAILED`).
6. **`type`(예외 클래스명) 필드:** 클래스명은 값이 아니라고 가정(`_TYPE` 정규식·16자 hex 거부 유지). 클래스명에 데이터를 넣는 코드는 상정하지 않는다.
7. **결과 파일과 한도:** 결과 파일은 부모가 만든 **이름 없는 임시 파일(0600, `log_dir` 안)** 이며 **정제된 frame(숫자·불리언·정적 코드·type)만** 담는다 — raw stdout/stderr·저장소 키·본문·경로는 기록되지 않는다(I7, R2-M1). 부모는 `RESULT_MAX_BYTES`(64 KiB) 이하일 때만 읽으므로 부모 메모리 상한이 구조적으로 보장되지만, **결과 파일이 얼마나 커지는지**(컴포넌트·fork 손자가 임의로 쓰는 경우)는 디스크 용량이 한계다 — 파일 크기 rlimit 는 패스의 SQLite 쓰기에도 걸려 쓰지 않는다. **파일 수명:** 익명 파일은 «마지막 보유 fd close» 시 회수된다(부모 close 가 아님) — fork 손자가 fd 를 쥐면 패스보다 오래 살 수 있으나 내용이 값 없는 frame 이라 노출은 없다(R2-m1). 자식이 raw 버퍼를 **메모리(StringIO)** 로 들고 있는 것은 기존 `cli.main` 의 StringIO 와 같은 부류다.
7a. **결과 채널 위조:** 같은 주소공간의 컴포넌트는 결과 파일에 유효한 스키마의 위조 frame 을 쓸 수 있다 — 위협 모델이 신뢰 컴포넌트의 우발 출력이므로 막지 않는다. 위조되어도 부모가 내는 값은 whitelist·레지스트리를 통과한 숫자·코드뿐이다(I5).
8. **로그 디렉터리·락 파일 보호의 알려진 범위**(r9: 상위 ancestor symlink 미검사·기존 권한 보정 없음)는 이 설계가 바꾸지 않는다.
9. **환경 의존:** 자식은 launchd 환경(`HTTPS_PROXY`·`SSL_CERT_*` 포함)을 그대로 상속한다(기존 in-process 와 동일). HELM #1764 의 `op` 자식 허용목록 결정은 유지되며 이 설계와 **충돌하지 않는다.** «U2 등록 전 launchd 환경 `op` 동작 확인» 은 Master 몫 그대로.
10. **설치 가정:** `[sys.executable, "-m", "airag_consumer._pass_child"]` 가 `__PYTHON__` 에서 성공해야 한다(plist 주석상 성립; 아니면 `COMPONENT_PROCESS_FAILED` 로 즉시 드러남 — 침묵 실패 아님).

### 후보 A 로 후퇴할 때의 «최소 대안» 과 한계
구조 변경이 불가하면: `_discard_component_output` `finally` 에서 fd 복원 전 `ctypes.CDLL(None).fflush(None)` + 진입 직전 1회, 실패는 **삼키지 않고** `TickError(EXIT_INTERNAL, "NATIVE_FLUSH_UNAVAILABLE")`. R10-M1 재현만 닫고 분류표 3·5·7번은 ⑤ 에 «보장 안 함» 으로 명시해야 한다. 권고하지 않는다(재발 방지 요구 3 미충족).

---
## ⑥ Nano 구현 단계 목록 (Red→Green · 구조/행위 커밋 분리)

| 단계 | 내용 | verify |
|---|---|---|
| S0 | 기준선: `../rag/.venv/bin/python -m pytest tests -q -p no:cacheprovider` (consumer 디렉터리) | 239 passed 기록 |
| S1 (Red) | 4.1 T-R10M1-native-red 추가 | 단일 테스트 실패(`not in` 단언 위반) + 이유 = marker 검출 |
| S1b (구조·의존성 선행, R3-m3) | **Tidy First:** `tick.py` 의 `_counts`·`_known_codes`·`_safe_code`·`_error_fields` 를 순수 `_result.py` 로 «동작 불변» 이동(`summarize`·`error_fields`) + **잠정 `reason_codes.py`**(현 `_known_codes` 574 값의 스냅샷 — 동작 불변, `_result` 가 처음부터 이것을 import; 규칙 기반 생성으로의 교체는 S5) + `SUMMARY_INT_KEYS`·`SUMMARY_BOOL_KEYS` 상수 + `build_frame`·`validate_frame` + T-frame-validate | 기존 239 불변 + 신규 단위 통과 |
| S2 | 신규 `_pass_child.py` + `tests/_tick_component.py`(`normal` 모드) + T-child-protocol-unit | 자식 단위 통과 · 기존 239 불변 |
| S3 | `tick.py`: `_run_component` 도입·`_discard_component_output`·`hooks` 삭제·`component` 시임 추가. 같은 커밋에서 `tests/test_tick.py` 의 `run_tick`·직접 `tick.main` 호출부 전환(`hooks=` 12~15곳 → mode; `ChattyBridge`·`RaisingBridge`·`ShortValueBridge` 는 모드로 이전). 한시적 이중 시임 유지 금지 | 전환본 기존 테스트 전부 통과 + 4.1 을 4.2 T-native-* 로 교체해 Green |
| S3a | **D4 선행:** `tick.py` 의 `NAMES` 를 상수로 대체(`from .operations import KEY_NAMES` 제거) + T-names-match·T-parent-imports | 통과(이 시점엔 `cli` 가 아직 지연 import 라 `operations` 만 문제 — 단독 구조 변경 커밋) |
| S4 | 4.2 의 격리 테스트 전부(T-native-*·T-parent-fds-untouched·T-keys-*·T-protocol-violation·T-oversize-*·**T-raw-output-not-persisted·T-parent-revalidates**·T-fork-descendant-*·T-child-*·T-child-bootstrap-order·T-lock-held·T-default-command) | 전부 통과 |
| S5 (R10-m1) | `reason_codes.py` 를 잠정 스냅샷→규칙 생성값으로 교체 + 규칙 헬퍼(`tests/_regen_reason_codes.py`) + `tests/reason_code_review.py`(구조 문맥 약 40 출현 수기 분류) + 레지스트리 테스트(T-registry-drift·closed-world·binding·excludes-data·no-source-read)·T-envname/declared → `_safe_code` 교체·`_known_codes` 삭제 | 통과 |
| S6 | 전체 회귀 + `plutil -lint` 템플릿 불변 + `git diff --stat` 로 변경 파일 확인(`tick.py`·`_pass_child.py`·`reason_codes.py`·`tests/test_tick.py`·`_result.py`·`tests/_tick_component.py`·`tests/_regen_reason_codes.py`·`tests/reason_code_review.py`) | N passed · exit 0 |
| S7 | `docs/artifacts/nano-…-result.md` 에 분류표 1~11 각 행의 «닫는 테스트» 매핑 + ⑤ 잔여 인용 | DA 대조용 |

**제거되는 테스트 3개(대체):** `test_component_output_is_discarded_at_process_level` → T-direct-and-py · `test_buffered_component_output_is_flushed_into_the_discard_window` → T-native-normal/exception · `test_discard_setup_failure_does_not_leak_duplicated_fds` → T-parent-fds-untouched. r8~r10 의 나머지 회귀(심볼릭 링크·로그 회전·op env 허용목록·거부 log-dir·부분 쓰기 등)는 **그대로 유지**.

**운영 사실 대조(요구 4):** `OP_ENV_ALLOWLIST`(`HTTPS_PROXY`·`SSL_CERT_*` 제외)는 **변경 없음** — 설계 충돌 없음. 컴포넌트 자식에는 launchd env 가 그대로 간다.
