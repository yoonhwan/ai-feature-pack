골 원문(GOAL-LEDGER-airag.md 복붙):
최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰 + 6순위 C13(KakaoBot 통합 보고서) published 칸 채움.

판정: **REJECT — blocker 0 / major 2 / minor 2 / note 2**

검토: ft-airag-da-codex#1 · 2026-10-16 · 발주 #2575. 대상 `8160e0c`·`c5c20f6`, 시험 보강 포함 기준 HEAD `6d2b2fae63bd78af12c803b525fd9b91884e46f6`.
작업 디렉터리: `/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant`. Serena **가용 yes**: activate 성공, manual 읽기 완료, 정의 및 read_call/run_attempt/run_round/evaluate의 참조를 조회했다. 동적 시험 import 경로는 텍스트/실행으로 추가 대조했다.
이하 `py:N`은 `feature-pack/rag-consumer/ops/probe-opa/s2.py`, `sh:N`은 같은 폴더 `s2.sh`, `시험:N`은 `feature-pack/rag-consumer/tests/test_s2_opa.py`, `tick:N`은 `feature-pack/rag-consumer/src/airag_consumer/tick.py`다. 정본은 `arch-20261015-opa-popup-design-r4.md` §3.2·§6.1 및 r8의 실행 보류 계약이다.

**원본 33건 통과와 별개로, 채택 판정/사람에게 주는 해석에 정상 입력 경로의 오류 두 건이 있다.** 빠른 인증 오류가 7초 초과로 보고되고, 소비자가 거부하는 중복 키도 두 경로 모두 기준 충족으로 판정된다. 이 두 항목을 고치고 관련 부정 시험을 추가해야 한다. chain 결과나 실제 op 실행을 기다리지 않고 코드·합성 시험만으로 재심할 수 있다. 기존 probe.py/probe.sh 및 P/E1/chain의 종결 판정은 다시 열지 않는다.

## M1 — 빠른 인증/형식 오류까지 콜드 시작 7초 초과로 보고한다 (major)

근거: py:262–288,483–503 / 시험:255–283,426–434.

`evaluate()`의 `cold_over_limit`은 첫 라운드의 시도가 **success가 아니기만 해도** True다. `report()`는 이 값을 «콜드 시작이 7초 한도를 넘음 → 규칙 예외를 둘지는 오빠 결정»으로 표시한다. 즉 시간 초과와 인증·네트워크·형식·기동 오류가 섞인다.

실제 S2 도구를 합성 op/토큰/설정으로 실행한 빠른 auth_error 사례에서, **최대 시도 216ms**, 세 키의 첫 상태 모두 auth_error, comparison=neither_meets인데도 **cold_over_limit=true 및 위 7초 초과 문구**가 나왔다. 운영 토큰을 읽거나 실제 op를 실행한 것이 아니다. 만료/권한 오류는 지원하는 일반 입력 상태이며, 이 지적은 도달 불가 OS 고장을 가정하지 않는다.

수정: deadline 도달/실제 측정 시간 초과와 그 밖의 실패를 구별한다. 빠른 auth_error·network_error·unsupported·spawn_error만으로 시간 상한 예외를 상신하지 않는다. timeout 자체도 «기한 안 미완료»이며 정상 콜드 실행이 7초 뒤 끝난다는 증거로 확대하지 않는다. 해당 음성 사례와 실제 timeout 양성 대조를 함께 고정한다. **상수 7/14초를 올리는 수정은 해법이 아니다.**

## M2 — 중복 키를 알아도 기준 충족으로 판정하며, hex 대소문자 중복은 표시도 놓친다 (major)

근거: py:145–157,238–251,262–296 / tick:124–130 / 시험:280–283.

S2는 개별 값의 64-hex 형식만 통과하면 시도 success로 기록하고, 라운드의 `keys_distinct`는 문자열 집합으로 비교한다. 그러나 evaluate의 `meets_all`은 이 라운드 필드를 보지 않는다. 실제 소비자는 **bytes.fromhex 이후의 키 바이트**가 세 개 모두 달라야 받아들인다.

같은 구현을 합성 설정으로 끝까지 돌린 결과:

| 입력 | S2의 keys_distinct | S2의 판정 | 실제 소비자 load_keys 함수에 같은 합성 설정을 넣은 결과 |
|---|---|---|---|
| 같은 유효 64-hex 키 3개 | false | 양쪽 meets_all=true, **both_meet** | **STORE_KEYS_MUST_BE_DISTINCT** |
| 같은 키의 소문자/대문자 표현 2개 + 다른 키 1개 | true | 양쪽 meets_all=true, **both_meet** | **STORE_KEYS_MUST_BE_DISTINCT** |

첫 사례 최대 시도 233ms, 둘째 217ms였다. 실패가 느린 호출/재시도/자원 증가 때문인 사례는 아니다. 기존 시험은 동일 문자열에서 flag=false만 확인하여 잘못된 채택 결과를 놓친다. 이것이 timing 측정이라는 설명만으로 소비자가 사용할 수 없는 키 집합을 «전용 경로 후보를 지지하는 기준 충족»으로 올려서는 안 된다.

수정: 원문을 저장하지 않는 메모리 비교는 유지하고, 소비자와 같은 바이트 단위로 중복을 판단한다. `meets_all`에는 모든 라운드의 `keys_distinct is True`를 포함하거나 동등한 무효화 규칙을 둔다. 개별 시도 시간을 지울 필요는 없으며, 같은 두 합성 입력에서 후보 충족 판정이 나오지 않도록 시험한다. 키 값/참조를 보고서나 결과 JSON에 추가할 필요는 없다.

## m1 — 자식 종료 미확인 뒤에도 무출력 timeout 재시도를 시작한다 (minor)

근거: py:137–142,160–195,464–469.

재시도 조건은 timeout·부분 출력 없음·남은 시간만 확인한다. `_end_child()`가 종료를 확인하지 못해 `child_exit_unconfirmed=true/reaped=false`여도 재시도가 가능하다. 자식 실행을 대체한 모형에서 **첫 시도 종료 미확인 → 두 번째 시도 실행 → outcome=success**를 확인했다. 실제 프로세스를 이 상태로 만들거나 운영 op에서 관측한 것은 아니다.

이는 SIGKILL 뒤에도 유한 대기 안에 종료를 확인하지 못하는 조건부 경로다. 실제 기준 충족은 첫 시도 실패/재시도 때문에 이미 거절되므로, M2처럼 정상 값만으로 잘못된 채택을 내는 문제와 구분해 minor로 둔다. 보강 시 종료 미확인 뒤에는 추가 재시도/다음 라운드 진입을 보류하고 불완전으로 남긴다. 공유 데몬/그룹 종료나 이전 core 회수 계약의 재작업은 필요하지 않다.

## m2 — 호출 마감 판정을 무력화한 변이가 원본 33건 전체를 통과한다 (minor)

근거: py:282–295 / 시험:157–182,242–251,472–496.

`calls_within_deadline`을 **항상 True**로 바꾼 격리 사본이 **33 passed in 166.37s**였다. 원본 코드의 해당 비교식이 잘못됐다는 뜻이 아니라, 14초 호출 상한의 독립 부정 단언이 부족하다는 뜻이다.

별도 모형에서 첫 시도는 모두 정상 100ms지만 call_total_ms=15000인 여섯 라운드를 주면, **원본은 calls_within_deadline=false/meets_all=false**, 변이는 **true/true**였다. 실제로 15초짜리 외부 호출을 수행한 것은 아니다. 현재 f 시험은 두 번째 시도와 합계 시간만 직접 단언하고, criteria의 호출 상한 flag/채택 거부를 별도로 검증하지 않는다. 이 독립 부정 사례를 추가하면 변이가 탐지된다.

## note 1 — B1의 병렬/직렬/단일 비교까지 구현된 도구는 아니다

정본 r4의 B1 표(행 42)는 «3 병렬 vs 직렬 vs 단일 반복의 실패율 차이»를 S2 관측으로 적지만, 같은 문서 §6.1(행 199–203)은 라운드를 키 3개 병렬로 고정한다. 구현 py:238–251,434–471과 sh의 인자는 **기본/전용 경로 × 각 6라운드의 병렬 읽기만** 제공한다. 직렬·단일 모드/그 비교 통계는 없다.

이번 구현은 구체적인 §6.1의 경로 비교 계약을 따른 것으로 보며, 모호한 B1 표를 근거로 DA가 새 기능을 임의 요구하지 않는다. 다만 이 결과만으로 B1 동시성 원인 구분을 완료했다고 보고할 수는 없다. Master/architect가 B1 후속 범위와 이번 S2의 경계를 정본에서 정리하면 된다.

## note 2 — 시험은 합성 경로에 고정됐지만 selftest 자체가 실제 op 차단 경계는 아니다

현재 시험은 합성 credentials/token 파일의 `op`를 가짜 실행 파일에 고정하고, launchctl·pgrep·P4도 합성 도구로 묶는다. 이번 모든 검증에서 실제 op/운영 launchctl/네트워크 호출은 0이었다. 하지만 `--selftest`는 재정의를 허용하는 모드이며, `load_settings()`는 selftest에서도 전달한 credentials의 op/토큰 경로를 그대로 사용한다. **실제 설정 파일을 넘겨도 가짜 도구로 강제 치환하거나 거부하는 기능은 없다.**

따라서 «기존 시험은 실제 op를 실행하지 않는다»는 확인과 «어떤 selftest 인자도 운영 접촉을 못 한다»는 보장을 구분한다. 합성 실행에서는 지금처럼 설정/토큰/실행 파일을 모두 fixture에 고정해야 한다. 이 경계를 강화하는 별도 요구가 있다면 계약으로 정해야 하며, 기존 도구의 selftest 계약까지 이번 DA가 임의 변경하지 않는다.

## 검증·안전 범위

| 검증 | 결과 |
|---|---|
| 기준 HEAD의 원본 S2 시험 | **33 passed in 163.43s (2:43)** |
| 독립 직접 변이 17종 | 선택한 기존 시험이 **16종 탐지**, 호출 상한 criteria 무력화 1종 생존. 그 1종은 전체 33건 재실행에서도 통과 |
| 실제 도구/합성 입력의 반례 | 빠른 인증 오류의 잘못된 시간 초과 보고, 동일 키/대소문자 동치 키의 both_meet, 소비자 함수의 두 입력 거부 확인 |
| foreground PTY Ctrl-C | 전용 경로 첫 라운드의 병렬 읽기 중 `0x03` → **130 / 임시 job 0 / 측정 직접 자식 생존 0**. op-home 폴더는 보존됨 |
| 7초 룰·간격·형식·privacy | 운영 기본값 7.0/14.0, 한 번 재시도 및 첫 출력 뒤 재시도 금지 확인. 각 조건 콜드 1+웜 5/웜 간격 60초. 결과는 닫힌 스키마, 합성 키·토큰·참조·stderr 센티넬 비출력 시험 통과 |
| 원본 보존 | probe.py/probe.sh는 S2 구현 커밋에서 diff 0. s2.py/s2.sh는 c5c20f6→기준 HEAD diff 0. 최근 변경은 시험 시간 상수/실패 설명 보강. core.bare=false |

변이는 부분 출력 무시·재시도 제거·두 번째 시도 제한 해제·형식 검사 약화·키 인덱스/콜드 라벨 손실·웜 간격 제거·전용 환경 제거/환경 전체 상속·프로세스/디스크 증가 무시·재시도/시도/호출 criteria 무력화·스키마 extra key 허용·stderr 저장·느슨한 전용 디렉터리 허용이다. 탐지 실패/성공은 실제 선택 시험 결과로 셌고, 전체 33건을 모든 변이에 돌렸다고 주장하지 않는다.

원본 명령은 `feature-pack/rag/.venv/bin/python -B -m pytest tests/test_s2_opa.py -q -p no:cacheprovider`(cwd `feature-pack/rag-consumer`)다. 발주에 적힌 전체 회귀 695건은 송신자의 보고이며, 이 DA가 다시 전체 실행한 건수로 합산하지 않았다. selftest의 8/16초·긴 wrapper 정리 예산은 합성 부하 내성용이며 운영 상수 7/14초가 바뀐 것이 아니다. wrapper 900초는 다중 측정과 최소 600초의 웜 간격을 포함한 집계 상한으로, 단일 외부 호출 제한이 아니다.

op-home은 0700으로 생성되고 결과 디렉터리와 함께 남는다. 이 폴더를 자동 삭제했다거나 새 공유 데몬을 정리했다고 보고하지 않는다. 디스크 증가 허용 오차 **0바이트**는 r4가 구현 DA에 맡긴 값으로 명시되어 있다. 실제 op 내부 캐시/데몬 생성 여부는 이번 합성 검증으로 확인하지 않았으며, 실행 고지에는 설정 경로 접촉·보존 가능성·팝업·36 논리 읽기/최대 72 CLI 시도와 총 실행 시간을 포함해야 한다. 실제 서비스 API 요청 수는 여전히 미확인이고 r4의 문서 확인 선행 조건도 남는다.

## 재현 위치와 다음 단계

- 반례·PTY·미확인 재시도: `/tmp/airag-s2-da-code-r1-checks.py`; 결과 `/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-s2-da-r1-checks-kn8o2kpu/evidence.json`. 소비자 함수 거부 기록은 같은 폴더의 `tick-check.json`.
- 변이 실행기: `/tmp/airag-s2-da-code-r1-mutations.py`; 요약 `/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-s2-da-r1-mutations-fx59_y5r/summary.json`.
- 생존 변이 전체 시험/원본 대비 판정: 위 폴더의 `call_deadline_criterion_ignored/full-suite-check.json`·`criterion-witness.json`.

실제 op·운영 DB·runtime.json·운영 plist·운영 토큰/자격 파일은 호출/열람/변경하지 않았다. 파일 내용 읽기는 소스·설계·합성 설정/결과에 한정했다. 신호/정리는 이 세션이 시작한 시험 프로세스에만 수행했다. 제품 소스/시험 수정·설치·커밋·push는 0이며 쓰기는 이 판정서 및 임시 합성 검증물이다. 서브에이전트는 사용하지 않았다.

재심은 **M1/M2의 S2 코드·합성 시험 수정**에 한정한다. 실제 키 읽기 승인·chain 결과·운영 재개가 이번 코드 수정의 전제는 아니다. 실제 S2 실행은 별도 chain 결과 판단과 사람 HIL 뒤라는 계약을 유지한다.
