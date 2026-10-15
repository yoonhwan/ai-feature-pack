골 원문: 최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
골의 어느 축인가: A03 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 권한 팝업 해결 P 프로브의 구현 r3 재심이다.
작업 디렉터리: /Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant (브랜치 feature/rag-transplant · push 금지 — PUBLIC 리포 · Serena 미사용). 답변 한국어.

판정: **REJECT — blocker 1 / major 1 / minor 0**

검토: ft-airag-da-codex#1 · 2026-10-15 · 발주 #2509 · 대상 `7c40233`·`2cad91c` · 기준 HEAD `2cad91cef73419107e8c8216f8f7d987e40a33c8`.
아래 `py:N`은 `feature-pack/rag-consumer/ops/probe-opa/probe.py`, `sh:N`은 같은 폴더의 `probe.sh`, `시험:N`은 `feature-pack/rag-consumer/tests/test_probe_opa.py`의 행 번호다. 정본은 `arch-20261015-opa-popup-design-r4.md`, 이전 판정은 `da-20261015-sol-p-code-r2.md`다.

원본 합성 시험은 **75 passed in 180.43s, rc=0**다. r2의 다섯 반례는 모두 폐쇄됐다. 새 Timer의 **시작/기록 예외에서 자식이 제한 없이 남는 경로**와 **주 스레드 회수 후에도 콜백의 신호 요청이 남을 수 있는 수명 경쟁**이 확인되어 HIL 실행 진입은 반송한다. 재심은 이 두 새 경계로 좁힐 수 있다.

실제 op·운영 launchctl·외부 DNS/접속·운영 토큰/자격 파일·DB는 호출하거나 열람하지 않았다. 모든 프로세스/신호 실험은 직접 만든 합성 자식에 한정했다. PID 재사용을 실제로 만들거나 재사용된/외부 PID에 신호를 보내지 않았다. 교차 실행 모형의 지연 신호는 기록만 했고 전송하지 않았다. 제품 소스/시험 수정·설치·커밋·push는 0이다.

## 1. r2 다섯 항목의 폐쇄 대조

| r2 항목 | 재실행/코드 근거 | 판단 |
|---|---|---|
| B1 기록 중 시한 미집행 | py:199–225의 사전 소진 거부·Timer. 기존 기본 7초/기록 7.4초 반례에서 **첫 kill 7,008ms**, 직접 자식 재수거. 사전 준비 소진 시 자식 시작 없음 시험도 통과 | **기존 반례 종결**. 새 Timer 예외 경로는 아래 B1 |
| M1 셸 ps 무제한 | sh의 pid_state가 남은 phase 안에서 bounded ps를 호출하고 소진/조회 지연은 unknown으로 보고. 6+5초 축소 예산 반례는 **4.100초, rc=4**, 19초 대기 없이 미확인 PID 보고 | **종결** |
| M2 경로 부분 일치 | owns_loaded_job의 정확한 전체 argv/plist 경로 대조. 이전 접두사 foreign 모형에서 **bootout 0, rc=4**. suffix/extra_arg/env_only/path_suffix/prefix_dir 시험과 bootstrap 직후 중단도 통과 | **종결** |
| M3 연결 불가 AppData | msgID 없는 명시적 AppData가 **seen_unattributed**, 미지원 ID/부분 귀속은 보수적 상태로 유지. 기존 Camera·로그 창·로컬 예산 수정도 유지 | **종결** |
| m1 거부 입력 원문 출력 | production은 시간 값 해석 전 이름으로 거부. 이전 canary 반례에서 **rc=2, canary 출력 없음, 폴더/op/launchctl 없음**. selftest의 잘못된 숫자도 고정 오류 | **종결** |

기존 preflight 충돌도 bootstrap/bootout 없이 거부되고, bootstrap 지연은 축소 예산에서 1.513초로 제한됐다. P4 합성 DNS 자식은 304ms에 종료/재수거됐으며 토큰 env 제외가 유지됐다. 환경 기반 mode 승격·interpreter·자식 env 경계의 이전 폐쇄도 유지한다.

## B1 — Timer 시작/기록 예외가 발생하면 자식을 남겨 두고 시한 집행을 없앤다 (blocker, 새 경로)

근거: py:204–227,240–246 · 시험:840–891에는 정상 지연/사전 소진만 있고 해당 예외 경계가 없음.

Popen 성공 뒤 `timer.start()`가 try 바깥에 있다. 스레드 자원 부족 등으로 start가 RuntimeError를 내면 직접 자식은 이미 시작했지만 타이머도 정리도 없다. start가 성공해도 `book.after()`가 OSError 등으로 실패하면 finally는 **timer.cancel()만** 실행하고, 그 아래 kill/wait/스트림 닫기로 내려가지 않는다. 살아 있는 자식을 남긴 채 유일한 독립 시한 집행을 취소한다. 기록 실패라면 PID book에도 자식이 저장되지 않았을 수 있어 뒤의 wrapper 정리에만 의존할 수 없다.

**두 경로 각각 합성 재현:** ATTEMPT_S=100ms, 직접 자식은 `/bin/sleep 10`으로 두고 (a) book.after가 즉시 OSError, (b) Timer.start가 RuntimeError를 내게 했다. 두 경우 모두 함수의 예외를 받은 뒤 **300ms 시점에도 자식이 살아 있었다**. 원문 값/실제 op는 사용하지 않았고, 관찰 후 이 시험이 만든 자식을 직접 종료·재수거했다. 이는 원래의 «느린 기록 중 정상 Timer» 반례와 별개다.

필수 수정: **Popen 성공 즉시 모든 이후 경로를 자원 소유/정리 보호 구간에 넣는다.** Timer 시작 실패, 기록/통신 예외, 중단을 포함해 직접 자식이 살아 있으면 즉시 자기 자식만 종료하고 유한 재수거/파이프 닫기 또는 미확인 상태 보고를 수행한다. 자식이 남아 있는데 단순 cancel로 시한을 제거하지 않는다. start 실패와 기록의 부분 성공/실패 시험에서 시한 뒤 생존 없음·재수거·값 비출력·스레드 종료를 확인해야 한다. 이 경계는 op와 같은 run_child를 쓰는 P4 worker에도 적용된다.

## M1 — Timer 콜백과 주 스레드의 kill/reap 수명이 동기화되지 않는다 (major, 신규)

근거: py:215–244,246–264. 설치 Python 3.13.12의 `subprocess.Popen.send_signal`/`_internal_poll`, `threading.Timer.cancel`/`run`도 대조했다.

Timer는 poll→fired→kill을 수행하고 주 스레드는 communicate/wait와 별도의 kill을 수행한다. finally의 cancel은 **이미 실행 중인 콜백을 멈추거나 종료를 기다리지 않는다**. 따라서 함수가 자식을 회수하고 반환한 뒤에도 콜백이 신호 경계에 남을 수 있다. `proc.poll()`과 native kill의 추가 poll은 보통의 정상 종료를 보호하지만, kill 결정과 다른 스레드의 wait/reap 전체를 하나로 직렬화하지 않는다.

설치 CPython의 send_signal 소스도 returncode 검사와 kill 사이에서 재사용 PID 경쟁이 여전히 가능하다고 명시한다. `_waitpid_lock`은 wait끼리 보호하며 이 구현이 추가한 Timer와 주 스레드 사이의 전체 kill/reap 소유 계약을 대신하지 않는다.

**통제된 교차 실행 모형:** 실제 Timer/Popen을 사용하고, Timer가 native send_signal의 검사 뒤 os.kill 경계에 도달한 시점에서 그 신호만 기록기로 보류했다. 주 스레드는 자기 직접 자식을 종료·wait하고 함수에서 반환했다. 이때 **callback_alive_at_return=true**였고, 보류를 풀자 **target_already_reaped=true**인 지연 신호 요청이 남았다. **그 지연 신호는 실제 전송하지 않았고, 실제 PID 재사용/외부 프로세스 신호도 없었다.** 재사용이 발생할 수 있는 틈과 수명 분리의 부재를 검증한 모형이지, 외부 프로세스가 실제 종료됐다는 주장이 아니다.

대조로 빠른 정상 종료 3회에서는 success/reaped와 **실제 신호 0회**를 확인했다. 일반 경로의 보호는 작동하지만 위 교차 실행이 닫혔다는 증거는 아니다.

필수 수정: Timer의 종료 결정/신호와 주 스레드의 회수를 **하나의 명시적 소유 프로토콜**로 만든다. 이미 실행 중인 콜백이 없는 것을 확인하기 전에 Popen을 회수·반환하지 않으며 스레드도 유한 시간에 종료/미확인 보고한다. 단순히 현재 finally 끝에 join을 붙이면 communicate가 그 전에 회수했을 수 있어 충분하지 않다. 예를 들어 Timer를 기록 구간에만 활성화하고 cancel/유한 종료 확인 뒤, 남은 deadline으로 주 스레드의 communicate/wait를 시작하는 방식은 검토할 수 있다. 기록 중 독립 7초 집행을 보존해야 한다. 정상 종료·만료 동시 경계·실행 중 콜백 취소·기록 예외·Timer 시작 실패를 같은 계약으로 시험한다.

설치 런타임 근거 경로:

- `/Users/yoonhwan/.local/share/uv/python/cpython-3.13.12-macos-aarch64-none/lib/python3.13/subprocess.py:2218` — send_signal의 재사용 PID 경쟁 설명과 guard.
- 같은 파일 `:2006` — _internal_poll의 wait lock.
- 같은 런타임의 `lib/python3.13/threading.py:1338` 및 `:1342` — cancel과 Timer.run; 진행 중 콜백의 종료 대기는 없음.

## 2. 실행 증거와 변이 해석

| 검증 | 결과 |
|---|---|
| 원본 `tests/test_probe_opa.py` | **75 passed in 180.43s, rc=0** |
| 이전 반례 재실행 | 기존 다섯 항목의 폐쇄 단언 **rc=0**. 위 표의 실제 수치로 확인 |
| Timer 예외 경계 2종 | 각각 3배 시도 시간 뒤 합성 자식 생존을 재현, 관찰 후 직접 정리. 검증기 **rc=0** |
| 콜백/회수 교차 실행 | 반환 때 콜백 생존·회수 후 지연 신호 요청 재현, 지연 신호는 미전송. 검증기 **rc=0** |
| 빠른 정상 자식 | 3회 success/reaped, 실제 신호 0회 |
| 직접 소스 변이 | **16종 중 15탐지/1생존**, 실패 단언도 항목별 확인 |

변이는 이전 r2 실행기의 12종을 r3 문자열/소유 함수에 맞춰 재사용하고, Timer 비활성화·소진 후 자식 시작·연결 불가 AppData 무시·모드 거부 전 숫자 해석 4종을 추가했다. 원래 P0 토큰·P1b·상태 목록·원문 누출·env·소유·모드 변이도 유지했다. 제품 파일은 수정하지 않고 임시 복사본에서 실행했다.

탐지된 15종은 관련 원래 시험의 해당 단언에서 실패했다. 남은 1종은 P4의 communicate timeout을 없앤 변이로, **선택한 정상 Timer DNS 시험에서는 Timer가 대신 시한을 집행해 1 passed**였다. 이 생존을 무조건 시험 공백으로 세지 않는다. 모든 실패 조건에서의 완전 동등성을 증명한 것도 아니다. Timer 자체를 비활성화하면 새 첫-kill 시각 시험 2개가 모두 실패한다. 타이머의 시작/기록 예외와 교차 실행은 별도 검증기에서 발견했으며 기존 75개가 이를 보호한다고 주장하지 않는다.

mode 승격 변이는 이전과 같이 fake launchctl/state/HOME/TMPDIR를 추가 고정한 환경에서만 실행했다. 신호를 외부 PID/실제 운영 명령으로 보낼 수 있는 위험한 변이는 실행하지 않았다. 임시 변이 실행기의 문자열 구문 오류 1회는 실행 전 수정했고, 최종 변이 실행기는 rc=0으로 완료했다.

## 3. 재현 위치와 다음 재심 범위

이전 반례 재실행기: `/tmp/airag-p-da-code-r3-checks.py`.
재실행 결과: `/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-p-da-r3-checks-q9r79knj/evidence.json`.
새 Timer 검증기: `/tmp/airag-p-da-code-r3-timer-checks.py`.
Timer 결과: `/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-p-da-r3-timer-checks-kkw10qdw/evidence.json`.
변이 실행기: `/tmp/airag-p-da-code-r3-mutations.py`.
변이 결과: `/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-p-da-r3-mutations-kowwcdyo/summary.json` 및 변이별 result.txt.

다음 재심은 **B1 예외 경로의 자식 소유/정리와 M1 콜백·회수 동기화/스레드 종료** 두 건으로 제한할 수 있다. 이미 닫힌 셸 ps·정확한 job 소유·TCC·거부 입력 경계는 유지해 확인한다. 새 운영 관측/토큰 사용은 이 수정에 필요하지 않다.

Master의 clean HEAD 전체 회귀 결과는 작성 시점까지 수신하지 않아 여기서 통과로 기록하지 않는다. 이 판정은 실제 프로브 HIL·실제 op/launchctl·설치·S2·consumer 재개 승인이 아니다. 수정 재심 뒤 기존 HIL과 서버 18712/18703 복구 통보·HELM 재개·disabled 유지 경계를 따른다.
