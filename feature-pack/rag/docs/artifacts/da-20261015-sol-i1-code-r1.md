골 원문: 최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
골의 어느 축인가: A03 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 권한 팝업/타임아웃 해결의 첫 구현 단계 I-1 = 외부 호출 7초 룰을 tick.py 의 op 호출에 적용(현재 timeout=30). 설계 DA r4 PASS(0/0/0) 로 설계가 닫혔다.
작업 디렉터리: /Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant (브랜치 feature/rag-transplant · push 금지 — PUBLIC 리포 · Serena 미사용). 답변 한국어.

판정: **PASS — blocker 0 / major 0 / minor 0**

맨 앞 3줄은 I-1 구현 브리프 원문이다. 그 안의 «현재 timeout=30»은 구현 전 상태를 가리킨다.

검토: ft-airag-da-codex#1 · 2026-10-15 · 발주 #2486 · 대상 `17d72ec`·`2160294`·`856c0b7` · 기준 HEAD `856c0b76d58f109c1517e3aa070bf8ffecd06f19`.
종결 재확인: 검토 중 추가된 `ee3682f0f9ff46cbd649e3cd40fb6549c6195897`의 stderr 전용 회귀 시험만 델타 검토했다. 중간의 프로브 P 구현 커밋은 이번 검토 대상이 아니다.
범위는 `99f5d92..856c0b7`의 세 파일이다: `feature-pack/rag-consumer/src/airag_consumer/tick.py`, `feature-pack/rag-consumer/tests/test_tick.py`, `feature-pack/rag-consumer/tests/reason_code_review.py`. 아래 `코드:N`, `시험:N`, `검토표:N`은 각각 이 파일의 행 번호다. 정본은 `arch-20261015-opa-popup-design-r4.md` §3.2/§3.3 및 설계 DA r4다.

**구현의 재시도·시간 상한·값 경계는 적합하다.** 856c0b7에서 확인한 stderr 전용 회귀 시험 공백 1건도 후속 ee3682f에서 보강됐고, 양성 시험 및 기존 생존 변이의 실패를 재확인해 종결했다. 전체 회귀는 발주대로 Master의 별도 실행 결과에 맡긴다. 이 판정은 배포·프로브·운영 재개 승인과 구분한다.

## 1. 발주 여덟 항목의 대조

| 항목 | 근거와 검증 | 판정 |
|---|---|---|
| ① 14초 + 유한 정리 상수 안 반환 | 코드:104–120. 기본 7/14초를 바꾸지 않은 합성 op에서 **시도 2회, 14.003초**, 단언 상한 14.5초 이내. 기존 POSIX run의 직접 자식 종료/회수 사용 | 적합 |
| ② 후손 파이프 유지에도 시도 마감 뒤 반환 | 시험:472–480 포함 선택 시험 통과. 설치 Python 3.13.12 POSIX run의 timeout 경로도 소스/합성 실행으로 확인 | 적합 |
| ③ 직접 자식만 종료 | 코드:109–110은 subprocess.run 유지. 설치 Popen.kill은 직접 프로세스에 SIGKILL을 보내는 경로. 별도 합성 실행에서 timeout 반환 시 후손이 살아 있음을 확인했고 후손에는 신호를 보내지 않음 | 적합 |
| ④ 첫 출력 전 TimeoutExpired만 재시도 | 코드:113–119의 isinstance와 stdout/stderr의 truthiness 결합. None/빈 str/빈 bytes/비어 있지 않은 str/bytes의 **25조합** 통과. 원래 부분출력 시험에서 실제 bytes 1바이트 확인 | 적합. stderr 전용 회귀 공백도 후속 시험으로 종결 |
| ⑤ 남은 마감으로 2차 timeout 제한/소진 시 보류 | 코드:104,117–120. 기존 남은 마감·소진 시험 및 직접 분기 검증 통과. 모의 monotonic 100→108에서 실제 전달 timeout **[7.0, 6.0]**, 2차 성공 시 키 반영 확인 | 적합 |
| ⑥ 레지스트리·값 비노출·R8-m2 | 레지스트리 528, 이유 코드 선언/분류 동기 시험 통과. 코드:100–101 허용목록/토큰 주입 불변, 부분 출력/메시지는 로그로 넘기지 않고 클래스만 전달 | 적합 |
| ⑦ 신규 8개 시험의 직접 뮤테이션 탐지 | 소스 문장을 메모리에 직접 치환해 별도 pytest 프로세스로 실행. 최초 10변이 중 9탐지/1생존. 후속 ee3682f 시험이 생존했던 stderr 검사 제거도 검출 | 종결 |
| ⑧ 검토표 238→252의 의미 | 검토표:66. 이전/현재 REVIEW 딕셔너리를 AST로 비교: 단 한 키의 줄 번호만 이동, 값의 reference 분류·설명·다른 항목 모두 동일 | 적합 |

①~③은 확인한 **Python 3.13.12 POSIX 런타임**의 증거다. 다른 플랫폼이나 OS가 종료 불가능한 상태까지 형식적으로 보장했다고 확대하지 않는다. Windows의 후속 communicate 분기는 이번 macOS 경로가 아니다.

## 2. 실제 실행 증거

기준 Python은 `feature-pack/rag/.venv/bin/python` **3.13.12**다. pytest는 `-p no:cacheprovider`로 실행했다. Master가 전체 회귀를 돌리고 있어 중복 전체 실행은 하지 않았다.

| 실행 | 결과 |
|---|---|
| 신규 8개 + 기존 op env 허용목록 1개 + registry/분류/환경변수 제외 3개 | **12 passed in 11.08s, rc=0** |
| 기존 값 비노출/예외 클래스/키 형식 실패 경계 | **8 passed in 15.30s, rc=0**. 정상 키 주입 무누출, 키 모양 오류 텍스트 억제, 4종 op 예외 클래스, 값 모양 클래스 이름 제거, 잘못된 op 응답 경계 |
| 원래 `test_op_timeout_after_partial_output_is_not_retried`에 관찰기만 추가 | **1 passed in 6.58s, rc=0**. text=True, stdout 타입 bytes, 길이 **1**, stderr 길이 **0**, 실제 op 시도 1회 |
| 후속 stderr 전용 회귀 시험 (ee3682f) | **1 passed in 3.19s, rc=0**. 같은 시험에 stderr 무시 변이를 적용하면 시도 2회 대신 1회 단언에서 **예상한 실패 rc=1** |
| stdout 전용/stderr 전용/양쪽 부분 출력의 실제 합성 op | 최종 관찰 검증 **rc=0**. 각 1회만 시도, 출력이 실제 비어 있지 않고 TimeoutExpired로 반환함 확인 |
| stdout/stderr 타입·빈 값 25조합 및 재시도 후 성공 | **rc=0**. 빈 값 조합 9개는 재시도·성공, 비어 있지 않은 출력 포함 16개는 1회 종료 |
| 기본 7.0/14.0초, 합성 op가 exec sleep | **rc=0**, 2시도, **14,003ms**. 직접 자식은 run의 timeout 경로에서 종료/재수거됨 |
| 설치 native run + 후손이 파이프 유지 | **rc=0**. 축소 시도 제한 0.3초, 반환 0.8초 미만, 그때 후손 PID 생존 확인. 후손은 자연 종료 |
| 검토표 딕셔너리/레지스트리 직접 대조 | **rc=0**, 238→252 외 변경 없음, reference 유지, **528** |
| git diff 공백 검사/시험 뒤 공용 Git 상태 | diff check rc=0, `core.bare=false`. 시험에 GIT_DIR 등 Git 재지정 환경변수를 설정하지 않음 |

추가 보조 관찰 중 0.12초로 축소한 부분출력 probe는 한 번 관찰 단언에 실패(rc=1)해 PASS 증거에서 제외했다. 이를 제품 오류나 원인 확정으로 사용하지 않았다. 최종 증거는 원래 시험과 같은 0.3초에서 원래 stub의 실제 1바이트를 직접 확인한 결과 및 분리 재실행해 rc=0을 얻은 25조합 검증이다. 중복인 관찰 시험을 신규 통과 개수에 합산하지 않았다.

## 3. 직접 뮤테이션 결과

작업 트리 파일을 고치지 않고, 원본 소스의 정확한 한 문장을 치환해 독립 pytest 프로세스의 tick 모듈에 compile/exec로 직접 대입했다. 변이마다 관련 원래 시험을 실행했으며, stderr 변이는 **신규 8개 전체**를 실행했다. 신규 8개로 확인한 9변이는 8탐지/1생존이며, 기존 R8-m2 허용목록 시험의 변이 1개가 추가로 탐지됐다.

| 직접 대입한 변이 | 탐지 시험 | 결과 |
|---|---|---|
| OP_ATTEMPT_TIMEOUT_S = 30.0 | 상수 시험 | 1 failed, 탐지 |
| OP_CALL_DEADLINE_S = 30.0 | 상수 시험 | 1 failed, 탐지 |
| 첫 timeout도 항상 즉시 종료 | 무출력 timeout 재시도 | 1 failed, 탐지 |
| 부분 출력 유무 검사 제거 | 부분 stdout timeout | 1 failed, 탐지 |
| OSError까지 silent=True로 간주 | spawn 실패 무재시도 | 1 failed, 탐지 |
| attempt 증가 제거 | 무출력 timeout 재시도 | 1 failed, 탐지 |
| 남은 마감 min 대신 시도 상한만 사용 | 2차 timeout 상한 | 1 failed, 탐지 |
| timeout<=0 중지 조건 제거 | 마감 소진 무재시도 | 1 failed, 탐지 |
| stdout만 검사하고 stderr 검사 제거 | 신규 8개 전체 → 후속 stderr 전용 시험 | 최초 **8 passed, 생존**. ee3682f 시험에서는 **1 failed, 탐지** |
| child 허용목록 대신 부모 environment 전달(서비스 토큰 주입은 보존) | 기존 op child allowlist | 1 failed, 금지 env 이름 단언에서 탐지 |

뮤테이션 실행기: `/tmp/airag-i1-da-code-r1-mutations.py`.
로컬 상세/요약: `/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-i1-da-mutations-h5r3fqfb/summary.json` 및 같은 디렉터리의 변이별 txt. 실행기는 종료 시 실제 tick.py 내용이 원본과 같은지도 단언했다. 임시 플러그인/시험은 합성 값만 사용했다.

## 4. stderr 전용 회귀 공백 종결 (ee3682f)

근거: 코드:116 · 시험:404–411,390–480.

현행 코드는 `not (error.stdout or error.stderr)`로 올바르게 검사한다. 그러나 부분출력 stub은 stdout에만 `printf x`를 한다. `not error.stdout`으로 직접 변이시켜 stderr 검사를 없애도 신규 **8개가 모두 통과**했다. 따라서 stderr 경계를 깨는 후속 변경을 저장소의 신규 시험이 놓칠 수 있다.

검토 중 다른 좌석이 ee3682f에서 `test_op_timeout_after_stderr_only_output_is_not_retried`를 추가했다(후속 시험:414–421). `printf x >&2` 후 sleep하는 경우 시도 1회와 OP_READ_UNAVAILABLE/type을 단언한다. 이 시험은 **1 passed in 3.19s**이며, 같은 stderr 무시 변이를 적용하면 실제 시도가 2회가 되어 기대 1회 단언에서 실패한다. 따라서 이전 생존 변이를 이제 잡는다. 별도의 실제 stderr 부분출력 관찰과 25조합에서도 현재 구현이 올바르게 동작함을 확인했다. 공백은 **종결**이며 최종 minor는 0이다. 이 좌석은 제품 소스/시험을 직접 수정하지 않았다. 추가 증거는 같은 임시 디렉터리의 `stderr_closure.json`, `ignore_stderr_new_regression.txt`다.

## 5. 범위와 잔여 게이트

이번 PASS는 지정 세 커밋의 **I-1 구현 적합성**과 후속 ee3682f의 stderr 회귀 보강 종결이다. Master의 clean HEAD 전체 회귀 결과는 작성 시점까지 이 좌석이 수신하지 않아 여기서 통과로 기록하지 않는다. 최종 회귀/집행 판정은 Master가 해당 실행 증거와 합쳐야 한다.

프로브 P 전체 구현, 실제 op, 토큰 원문 열람, 설치·launchd·DB 변경은 이번에 하지 않았다. S2는 별도 HIL이며 consumer disabled·서버 18712/18703 복구 통보·HELM 재개 게이트가 유지된다. 검토 중 다른 좌석이 만든 untracked 프로브 시험 파일은 이번 커밋 범위 밖이어서 수정하지 않았다. 본 판정 외 작업 트리 변경·커밋·push는 0이다.
