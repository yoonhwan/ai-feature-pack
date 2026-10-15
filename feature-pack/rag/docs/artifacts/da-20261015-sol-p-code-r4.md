골 원문: 최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
골의 어느 축인가: A03 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 권한 팝업 해결 P 프로브의 구현 r4 재심이다.
작업 디렉터리: /Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant (브랜치 feature/rag-transplant · push 금지 — PUBLIC 리포 · Serena 미사용). 답변 한국어.

판정: **PASS — blocker 0 / major 0 / minor 1**

검토: ft-airag-da-codex#1 · 2026-10-15 · 발주 #2513 · 대상 `d93cac1`·`ec06f2b` · 기준 HEAD `ec06f2b5e34e6b6779b35a158e55695977258a2b`.
아래 `py:N`은 `feature-pack/rag-consumer/ops/probe-opa/probe.py`, `시험:N`은 `feature-pack/rag-consumer/tests/test_probe_opa.py`의 행 번호다. 정본은 `arch-20261015-opa-popup-design-r4.md`, 이전 판정은 `da-20261015-sol-p-code-r3.md`다.

**r3의 B1·M1은 종결했다.** 평가 범위는 발주 #2513의 **단일 프로브 1회·사람 HIL·probe.sh가 launchd worker를 실행하는 경로**다. 기존 83개 시험, 예외 반례, 통제된 교차 실행 모형, 직접 변이를 확인했다. 이 경로에서 새 blocker/major를 발견하지 않았다. 별도 오류 주입/복합 조건이 필요한 예외 보강은 발주의 심각도 기준에 따라 비차단 minor 1건으로 남긴다.

실제 op·운영 launchctl·외부 DNS/접속·운영 토큰/자격 파일·DB는 호출하거나 열람하지 않았다. 실제 PID 재사용이나 외부 PID 신호 전송은 없었다. 교차 실행의 지연 신호는 기록만 했고 전송하지 않았다. 시험 자식만 종료·재수거하거나 유한 sleep 후 자연 종료하게 했다. 제품 소스/시험 수정·설치·커밋·push는 0이다.

## 1. r3 두 항목 폐쇄

| 항목 | r4 근거와 재실행 | 판정 |
|---|---|---|
| B1 Timer 시작/기록 예외의 자식 방치 | py:287–305. Timer.start 실패와 book.after OSError를 다시 주입한 결과 observation_unknown, child_exited=true, reaped=true로 반환. 이전처럼 시도 뒤 자식이 남지 않음. 원본 시험의 기록 중 인터럽트/P4 동일 계약도 통과 | **종결** |
| M1 Timer와 주 스레드 kill/reap 경쟁 | py:193–234,290–318. Timer는 기록 구간만 소유하고 lock 아래 만료를 결정. stop은 같은 lock에서 cancelled를 표시하고 유한 join 후에만 main 소유로 인계. callback 종료 확인 실패는 reaped=false/child_exit_unconfirmed로 보고하고 회수하지 않음 | **종결** |

기존 교차 실행 모형을 두 경우로 다시 실행했다. 콜백을 짧게 보류한 경우 main은 종료 확인 뒤 회수했고, 콜백이 정해진 확인 시간을 넘긴 경우에는 **미확인으로 반환하며 회수하지 않았다**. 두 경우 모두 기록기의 `target_already_reaped=false`였고, 지연 신호는 실제 전송하지 않았다. r3에서 발생했던 정상 처리 경로의 회수 후 지연 신호 창이 제거됐다.

구조적으로도 main의 communicate/wait/kill은 guard.stop 성공 뒤에만 시작하므로, 해당 경로에서는 Timer의 poll/kill과 같은 자식의 회수가 겹치지 않는다. 정상 종료 3회·만료 경계 12회·진행 중 콜백 종료 확인·미확인 반환·P4 자식에 관한 원래 시험도 통과했다. 실제 OS에서 PID를 재사용시켜 시험했다는 뜻은 아니다.

## 2. 실행 증거

| 검증 | 결과 |
|---|---|
| 원본 P 시험 파일 | **83 passed in 178.37s (0:02:58), rc=0** |
| r3의 Timer.start 실패 반례 | observation_unknown + 종료/재수거 확인 |
| r3의 PID 기록 실패 반례 | observation_unknown + 종료/재수거 확인 |
| 진행 중 콜백의 정상 인계 모형 | 콜백 종료 뒤 회수, 회수된 PID를 향한 지연 요청 없음 |
| 종료 확인 시간이 소진된 콜백 모형 | observation_unknown + reaped=false + child_exit_unconfirmed, 인계 없이 미확인 보고 |
| 직접 변이 | **18종 모두 관련 시험이 탐지**. 실패 단언도 확인 |

원본 실행은 `feature-pack/rag/.venv/bin/python -B -m pytest tests/test_probe_opa.py -q -p no:cacheprovider`다. 앞의 오류/교차 실행 검증기도 기대한 폐쇄 상태를 단언해 **rc=0**이었다. 해당 검증기에는 아래 minor를 평가한 별도 조건부 모형도 함께 기록했다.

변이는 이전 r3 실행기의 16종을 r4의 _Deadline/소유 인계에 맞춰 재실행하고, **예외 시 _end_child 생략**과 **guard 인계 생략** 두 종을 추가했다. 각각 새 B1 시험 2개와 M1 시험 2개가 실패했다. 기존의 P0 토큰·P1b·TCC·스키마·원문 누출·env·남은 deadline·셸 제한·job 소유·모드·Timer/사전 소진·거부 입력 변이도 탐지됐다.

r3에서 선택된 DNS 시험을 통과했던 «부모 communicate timeout 제거» 변이도 r4에서는 실패했다. Timer를 기록 구간에서 끝내므로 통신 구간의 남은 timeout이 실제 시한을 집행한다. 이 변화는 의도한 단일 소유 단계 분리와 일치한다.

변이의 mode 승격 경로는 fake launchctl/state/HOME/TMPDIR를 추가 고정한 시험 환경에서만 실행했다. 외부/재사용 PID를 실제로 대상으로 삼는 변이는 실행하지 않았다.

## m1 — 정상 HIL 경로 밖의 예외 처리에는 추가 보호 여지가 있다 (minor, 비차단)

근거: py:296–299,309–315. 심각도는 발주 #2513의 단일 HIL 경로 기준을 적용했다.

첫째, 소유 인계 뒤 communicate는 TimeoutExpired만 처리한다. 별도 OSError를 강제 주입하면 그 호출은 전파되고 _end_child에 도달하지 않는다. 합성 수면 자식은 축소 시도 100ms에서 300ms 뒤에도 살아 있었고 시험이 직접 정리했다. 현재 코드가 만든 익명 PIPE를 main이 단독으로 읽는 정상 경로에서 이 오류를 입력으로 유발한 사례는 없으며, 실제 운영 중 pipe 오류를 관찰한 것도 아니다. 함수의 «Popen 뒤 모든 경로 종료» 문구는 이런 강제 시스템 오류까지 포함하는 전면 보장보다 넓다.

둘째, BaseException 처리에서는 guard.stop의 False를 확인하지 않고 _end_child를 수행한다. **worker의 KeyboardInterrupt와 신호 콜백의 장시간 정체를 동시에 강제**한 모형에서는 회수 후 지연 요청이 다시 만들어졌다. 지연 요청은 기록만 하고 전송하지 않았다. 현재 승인 대상에서 사용자의 Ctrl-C는 foreground wrapper에 전달되고 worker는 launchd 작업이므로, 이 모형은 worker에 별도 인터럽트를 주고 콜백도 인위적으로 정체시켜야 한다. 단일 HIL의 정상 실행/취소에서 이 조건에 도달한 증거는 없다.

따라서 현재 프로필의 PASS를 막지 않고 **예외 보강 1건**으로 묶는다. 향후 worker를 직접 인터랙티브 실행하거나 장기 라이브러리로 재사용한다면, 인계 뒤 통신 예외도 소유한 자식을 정리하고 BaseException에서도 stop 실패 시 회수하지 않는 계약으로 맞출 수 있다. 자원/OS의 모든 고장이 불가능하다고 주장하거나 이 함수의 모든 사용 문맥을 승인한 판정은 아니다. 실제 서비스 토큰의 출력/누출을 관찰한 항목도 아니다.

## 3. 재현 위치

기존 두 반례와 교차 실행·조건부 예외 모형: `/tmp/airag-p-da-code-r4-checks.py`.
결과: `/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-p-da-r4-checks-ftgpwmjo/evidence.json`.
초기 예외 폐쇄 확인 결과: `/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-p-da-r4-errors-8fgl2fw5/evidence.json`.
변이 실행기: `/tmp/airag-p-da-code-r4-mutations.py`.
변이 결과: `/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-p-da-r4-mutations-0ytdulu2/summary.json` 및 변이별 result.txt.

## 4. PASS의 범위

이번 PASS는 지정 커밋의 **단일 HIL용 P 프로브 구현 재심**이다. 기존의 유한 시도/회수, 정확한 job 소유, TCC 보수적 분류, 값 없는 결과, 모드 거부, consumer disabled 경계를 유지한다. 여러 번 실행해도 원인을 완전히 가른다거나 실제 계정/팝업/운영 회복을 검증했다는 뜻은 아니다.

Master의 clean HEAD 전체 회귀 결과는 작성 시점까지 수신하지 않아 여기서 통과로 기록하지 않는다. 구체 실행 계획의 HIL은 별도이며, 이 좌석은 실제 프로브를 실행하지 않았다. 실제 키 읽기 S2, 설치/launchd 재개, 서버 18712/18703 복구 통보·HELM 재개 절차도 이 PASS와 구분한다.
