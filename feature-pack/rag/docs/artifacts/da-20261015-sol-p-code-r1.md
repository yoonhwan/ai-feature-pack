골 원문: 최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
골의 어느 축인가: A03 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 권한 팝업 해결의 P 단계 = 오빠 HIL 1회 실행용 증거 수집 프로브의 구현 DA다.
작업 디렉터리: /Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant (브랜치 feature/rag-transplant · push 금지 — PUBLIC 리포 · Serena 미사용). 답변 한국어.

판정: **REJECT — blocker 1 / major 4 / minor 2**

검토: ft-airag-da-codex#1 · 2026-10-15 · 발주 #2495 · 기준 HEAD `38bb103857a16b05a701d6eed12f87faef6cb882`.
대상 구현은 `05c6bb8`·`a0f2cff`·`ee3682f` 중 P 관련 네 파일이다. 아래 `sh:N`은 `feature-pack/rag-consumer/ops/probe-opa/probe.sh`, `py:N`은 같은 폴더의 `probe.py`, `시험:N`은 `feature-pack/rag-consumer/tests/test_probe_opa.py`, `가짜LC:N`은 같은 tests 폴더의 `_probe_fake_launchctl.py`, `설계:N`은 `feature-pack/rag/docs/artifacts/arch-20261015-opa-popup-design-r4.md`의 행 번호다.

기존 합성 시험은 **31 passed in 46.11s**다. 별도의 합성 반례에서 외부 호출 마감·전체 마감·충돌 라벨 소유·TCC 관측·운영 모드 구분의 결함을 재현해 **현재 프로브의 HIL 실행 진입은 반송**한다. 값 비출력의 정상 경로와 기존 31개 시험을 통과한 사실은 유지한다.

실제 op·운영 launchctl·네트워크·운영 토큰/자격 파일·DB는 호출하거나 열람하지 않았다. 모든 반례는 합성 자식, 가짜 launchctl/log, 임시 HOME/토큰 파일만 사용했다. 이 좌석이 만든 직접 자식만 종료했고 공유 프로세스/데몬은 종료하지 않았다. 제품 코드는 수정하지 않았다.

## 1. 정본과 구현의 대조

| 범위 | 대조 결과 |
|---|---|
| §4.2 단계/검증기 | P4→P0→P2→P1→P1b, 버전/계정 별도 판정, 계정 JSON type 미일치 unsupported는 구현됨. 시도 마감은 B1 |
| §4.3 전이표 | timeout/seen_* 중지, 완료 오류 중지, P1b의 세 단계 success+none_logged_ok 조건은 구현되고 시험됨 |
| §4.4 결과 스키마 | 9종 상태·유한 결론/불리언·필드 허용목록·원자 기록·불완전 결과 unknown이 구현됨. 이 판정은 임의 문서의 의미적 일관성까지 모두 검증했다는 뜻은 아님 |
| §4.5 값 경계 | 토큰은 파일→부모 메모리→필요한 op env로 전달, P0에는 없음. 직접 저장하는 argv/plist/결과/원문 스트림의 정상 경로에서 누출 없음. 원문 traceback 대신 유한 클래스. op 내부 캐시/데몬의 실제 동작은 합성 시험으로 입증할 수 없음 |
| §4.6 종료/정리 | 직접 자식 kill·유한 wait/파이프 회수·PID/시작 시각 비교·합성 a–m은 구현됨. 셸 전체 마감과 충돌 라벨 처리는 M1/M2 |
| §7 사람 고지 | 토큰 읽기·공유 op 상태 접촉·복수 팝업·disabled 유지 고지는 유지할 수 있음. **최대 75초와 자기 작업만 정리한다는 약속은 현행 코드로 충족하지 않음** |

## B1 — 실제 외부 호출 수명을 시도당 7초로 제한하지 못한다 (blocker)

근거: py:101–108,127–131,154–165,329–345 · 설계:53,83,155.

CLI는 Popen으로 이미 실행시킨 뒤 `book.after()`에서 `ps_line()`과 원자 파일 기록을 수행하고, 그 **뒤에 새 7초**를 communicate에 준다. ps는 자체 최대 3초이고 이 시간에도 op는 살아서 원격 호출할 수 있다. 프로세스 기동을 포함한 하나의 7초 마감이 아니다.

합성 재현: 시도 상수 100ms, Popen 뒤 PID 기록 지연 250ms를 주자 직접 자식은 **354ms** 뒤 timeout/종료됐다. 자식은 단순 sleep이며 실제 op가 아니다. 기록 지연을 시도 예산에서 차감하지 않는 구조가 확인된다.

P4도 `socket.create_connection(timeout=…)`만으로 DNS를 제한하지 못한다. 표준 create_connection의 getaddrinfo는 소켓 timeout의 바깥이다. getaddrinfo를 200ms 뒤 오류 내는 합성 함수로 바꾸면 시도 예산 50ms인데 **203ms**, network_error로 반환한다. 실제 DNS/접속은 없었다. 마감이 이미 지난 뒤에도 `max(0.01, remaining)`으로 다음 소켓/TLS 동작을 시작할 여지도 있다.

필수 수정: Popen 직전 고정한 시도 deadline에서 PID 기록 등 경과를 차감해 communicate에 **남은 시간만** 전달하고 소진 시 즉시 직접 자식 종료/유한 회수로 이동한다. DNS·접속·TLS도 하나의 취소 가능한 7초 마감 안에 넣고, 소진 후 다음 네트워크 동작을 시작하지 않는다. PID 기록 지연과 DNS 지연 반례를 회귀 시험에 넣는다. 기동비/정리비를 외부 호출 상한에 임의 가산하지 않는다.

## M1 — 셸의 최대 75초는 실행 경로에 강제되지 않는다 (major)

근거: sh:36–43,48,72,79–96,143–175,180–198 · 설계:160–162,213.

초기/정리 `launchctl print`, bootstrap, bootout은 timeout 없이 동기 호출된다. 결과 대기 시계는 **bootstrap이 돌아온 뒤** T0에서 시작한다. CLEAN_DEADLINE은 TERM 대기 일부만 제한하고 label 조회/bootout·PID 조회 helper·마지막 KILL 재확인 루프·report 전체를 제한하지 않는다. 따라서 결과/정리 상수의 합이 전체 상한이 아니다.

합성 재현: 가짜 bootstrap만 4초 대기 후 실패하게 했고 start/result/clean 예산을 각각 1초로 설정했다. 어떤 job도 시작하지 않았는데도 전체가 **4.356초** 걸렸다. 세 예산을 중복 합산한 느슨한 3초 상한조차 넘는다. 무한히 반환하지 않는 launchctl이면 현재 wrapper도 계속 대기한다.

필수 수정: bootstrap 전 초기화부터 report까지 하나의 전체 deadline을 두고 모든 helper/launchctl 호출과 재확인에 남은 시간을 전달한다. 정리는 별도 남은 15초 한도 안에서 끝내고 소진/조회 불가를 «잔존 확인 필요»로 닫는다. 명령은 자동 반복하지 않는다. bootstrap hang·cleanup 조회/bootout hang·여러 PID 정리의 예산 소진을 합성 검증해야 한다.

## M2 — 라벨 충돌로 시작을 거부한 EXIT 정리가 기존 라벨을 bootout한다 (major)

근거: sh:75–95,104,141–147 · 설계:141,145–149.

LABEL을 설정한 뒤 preflight가 loaded/unknown이면 시작을 거부하지만, EXIT trap의 cleanup은 그 LABEL을 다시 조회해 bootout한다. **이 실행이 bootstrap한 적 없는 라벨도 정리 대상**이 된다. «라벨이 같다»는 사실만으로 자기 job 소유를 입증할 수 없다.

합성 재현: 가짜 launchctl이 preflight부터 기존 loaded 라벨이라고 응답하도록 했다. 기록은 **bootstrap 0회, bootout 1회**였다. 실제 기존 job을 만들거나 종료하지 않고 요청만 기록했다. 충돌 확인은 시작 중단 이유이면서 동시에 기존 job을 내리는 원인이 된다.

필수 수정: 충돌/소유 미확인 job에는 bootout하지 않는다. bootstrap 직후 중단도 처리하려면 단순 성공 플래그뿐 아니라 **자기 PROBE_DIR/ProgramArguments/plist와 실제 loaded job의 일치**를 확인하는 소유 계약을 둔다. preflight loaded/unknown·동명 job의 인자 불일치·자기 bootstrap 직후 중단을 구분해서 시험한다. 다른 job을 내리는 권한은 이 프로브 HIL 범위에 없다.

## M3 — TCC 결과가 AppData 사건/약속한 시간창을 신뢰성 있게 나타내지 않는다 (major)

근거: py:81–83,137–142,264–290,351–368,418–435 · 시험:84–98 · 설계:99,107–114.

관측기는 1password/팀 ID/**AppData 중 아무 문자열**이 있으면 관련 요청으로 분류한다. AppData가 아닌 사건도 포함된다. 합성 compact 로그의 `kTCCServiceCamera com.1password.op pid=321` 한 줄은 **seen_attributed**가 됐다. AppData 요청이 없는데 연쇄가 중지되고 해당 원인 후보를 지지한다.

또 종료+2초까지의 창을 명령 인자로 주지만 그 시각이 올 때까지 기다리거나 지연 이벤트를 재확인하지 않는다. 즉시 log show를 실행하면 미래의 요청은 아직 없다. 다른 TCC 줄을 양성 대조로 보고 none_logged_ok를 낸 뒤 다음 단계로 넘어갈 수 있다. `--info --debug`도 없고 실제 TCC 서비스/귀속 필드 대신 임의 pid 부분문자열을 검사한다. 현재 fake log는 호출 인자/시각/레벨을 검증하지 않고 미리 만든 한 줄을 즉시 내므로 이 차이를 잡지 못한다.

LOCAL_BUDGET_S도 로컬 호출 시간 합계가 아니라 execute 시작 후 **모든 벽시계 경과**를 센다. P4/op의 정상 대기가 15초를 소진하면 TCC를 더 조회하지 않는다. 합성 재현에서 로컬 예산 50ms를 만든 뒤 외부 작업을 대신하는 80ms만 기다렸는데, log를 한 번도 부르지 않고 unknown_log_unavailable가 됐다. 관측 불가가 실제 로그 상태보다 예산 오산에서 만들어질 수 있다.

필수 수정: AppData 요청과 그 요청의 귀속 필드를 식별/연결하고 다른 서비스는 제외한다. 요구한 관측 창을 실제로 확보할 수 없으면 unknown으로 기록한다. 필요한 로그 레벨을 포함하고 실제 compact 형식을 반영한 비밀 제거 fixture로 검증한다. 외부 호출 예산과 로컬 관측 예산을 분리해 차감하며, 전체 75초 안에서 관측 창을 확보하지 못하면 P1b/후보 판단을 보류한다. 값을 출력할 필요는 없다.

## M4 — 운영 wrapper의 환경 검사만으로 worker의 selftest를 금지할 수 없다 (major)

근거: sh:106–119,158–169 · py:31–43,203,273–275,332–334,438 · 가짜LC:60–62 · 시험:418–423.

shell은 자기 환경의 PROBE_/FAKE_를 거부하지만, worker는 **자기 환경의 PROBE_SELFTEST=1만으로** 모든 오버라이드를 허용한다. 운영 plist에는 production 모드를 고정하는 인자/검증이 없다. wrapper와 launchd job의 환경은 별개이며 launchd 영역의 상속 환경은 wrapper 검사로 확인할 수 없다. 기존 가짜LC는 plist 환경만 전달하므로 이 경계를 모델링하지 않는다.

합성 재현: 일반 wrapper를 **--selftest 없이**, PROBE_/FAKE_ 키 0개인 환경으로 시작했다. 가짜 launchd만 worker에 PROBE_SELFTEST와 fake op/token/log/P4 변수를 추가했다. worker는 이를 수용해 **합성 op 4회, no_repro_twice, rc=0**을 만들었다. 실제 launchd 환경에 현재 그런 변수가 있다는 주장은 아니며, **일반 모드가 환경만으로 시험 모드로 바뀔 수 있는 계약 반례**다. 실제 op/운영 토큰/네트워크는 사용하지 않았다.

필수 수정: worker 모드를 wrapper가 받은 명시적 실행 인자로 전달하고, production worker는 주변 환경의 selftest 스위치/오버라이드로 전환되지 않게 한다. launchd 상속 환경을 가짜LC에도 모델링해, normal wrapper+주변 selftest 변수에서도 production이거나 실행 거부임을 시험한다. 결과의 mode를 유한 값으로 명시하면 증거 구분에도 도움이 되지만, 표시만 추가해서 실행 모드 강제를 대신해서는 안 된다.

## m1 — 기본 interpreter가 consumer의 책임 프로세스와 일치하도록 고정되지 않았다 (minor)

근거: sh:18–22,110,123,158–160 · py:2–5.

--python을 생략하면 호출 셸 PATH의 python3를 택한다. 이 검토 환경의 기본 경로는 `/opt/homebrew/bin/python3`이고, consumer의 설치 Python 3.13 런타임을 선택한다는 보장이 없다. plist 인자에 -I도 없다. 책임 프로세스/실행 정체성이 문제의 핵심인 만큼 다른 Python으로 실행하면 비교 조건이 달라진다. selftest는 PROBE_PYTHON으로 항상 시험 Python을 고정해 이 차이를 드러내지 않는다.

운영 HIL 계획에는 검증한 consumer interpreter의 절대경로를 명시하고 같은 격리 옵션을 사용한다. 기본값을 허용한다면 동일성/안전한 경로 검증을 추가한다. 이 DA는 설치 interpreter나 운영 plist를 변경하지 않았다.

## m2 — op 자식 env 허용목록을 없애는 변이가 31개 시험을 모두 통과한다 (minor)

근거: py:74,192–199 · 시험:71–80,185–212.

현재 구현은 필요한 이름만 복사해 올바르게 제한한다. 그러나 이를 `env = dict(os.environ)`으로 직접 바꾼 복사본에서 **31 passed in 48.82s**였다. 기존 stub은 TOK의 존재와 HOME/CFG만 기록하고 다른 환경 이름은 확인하지 않는다.

보강: 합성 부모 환경에 허용되지 않은 키를 넣고 op_environment/실제 자식이 받는 **키 이름만** 검사하는 시험을 추가한다. 값은 출력하지 않는다. 이 변이가 실패하는지 확인한다. 현행 코드 자체의 누출로 분류하지는 않는다.

## 2. Nano가 보고한 세 편차

| 편차 | 판단 |
|---|---|
| P2 HOME을 `<HOME>/.local/share/airag/op-home`으로 사용 | §4.2가 §5.1 전용 경로를 참조하므로 수용 가능. 경로는 격리 장벽이 아니고 생성/CLI 캐시 쓰기가 생길 수 있다. HIL의 공유 상태 접촉 고지에 포함하며 «운영 경로 접촉 0»으로 설명하지 않는다 |
| 완료 오류 뒤 남은 단계에 skipped_not_applicable 사용 | 실행을 늘리지 않고 종료 이유를 유한 상태로 표현하므로 수용 가능. unresolved와 구분하는 의미를 문서/소비자에 일치시키면 됨 |
| 최상위 conclusion/tcc_unknown 추가 | 둘 다 유한 값/불리언이고 전이표의 결론과 관측 불가 보존에 필요하므로 수용. 자유 텍스트/원문 출력 필드를 추가하지 않음 |

이 세 편차 자체가 이번 REJECT의 원인은 아니다. 원래 정본이 허용한 **토큰 파일 읽기·공유 op 상태 접촉**과 **운영 DB/consumer 파일/토큰 쓰기 금지**를 구분한다. 실제 토큰을 전혀 읽지 않는 프로브라는 설명은 사용하면 안 된다. 본 DA에서는 실제 토큰 파일을 열지 않았다.

## 3. 합성 시험과 직접 뮤테이션 증거

원본 시험: `feature-pack/rag/.venv/bin/python -B -m pytest tests/test_probe_opa.py -q -p no:cacheprovider`, **31 passed in 46.11s, rc=0**. 합성 반례 실행기도 모든 재현 단언을 만족해 **rc=0**이다. 제품 파일을 수정하지 않고 임시 디렉터리에 네 파일을 텍스트로 복사해 소스 문장을 직접 치환했다. 변이별 실패 단언도 확인했다.

| 직접 변이 | 실행 시험 | 결과 |
|---|---|---|
| P0에도 토큰 주입 | 정상 a | 1 failed — P0 TOK 없음 단언 |
| P1b에서 TCC 조건 제거 | l의 4조합 | 3 failed, 1 passed — unknown인데 P1b 실행 |
| TCC 0줄을 none_logged_ok로 처리 | l의 4조합 | 3 failed, 1 passed — 같은 보류 단언 |
| 아홉 번째 상태 삭제 | m | 1 failed — 9종 목록 단언 |
| timeout 뒤 파이프 회수를 무제한 communicate로 변경 | k | 1 failed — p0 6.231초로 유한 상한 초과 |
| 합성 토큰을 probe 디렉터리 leak.txt에 저장 | e | 1 failed — 합성 TOKEN이 tree_text에 없다는 단언 |
| 자식 env에 부모 전체 복사 | **전체 31개** | **31 passed**, 생존 — m2 |

따라서 직접 변이 **7종 중 6탐지/1생존**이다. 실제 launchctl/op를 호출할 위험이 있는 모드 거부 guard 제거 변이는 실행하지 않았다. 대신 M4처럼 모든 하위 명령이 합성으로 고정된 별도 모형을 사용했다.

재현 실행기: `/tmp/airag-p-da-code-r1-checks.py`.
반례 상세: `/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-p-da-checks-99lixg08/evidence.json`.
변이 실행기: `/tmp/airag-p-da-code-r1-mutations.py`.
변이 상세: `/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-p-da-mutations-ieca1dd_/summary.json` 및 변이별 result.txt.

## 4. 재심과 실행 경계

B1과 M1~M4를 수정한 프로브 및 해당 반례의 회귀 시험이 재심 입력이다. m1/m2도 운영 계획/시험에 반영할 수 있다. 기존 정상 31건과 a–m의 폐쇄는 유지해 확인한다. Master의 clean HEAD 전체 회귀 결과는 이 좌석이 아직 수신하지 않아 별도 통과로 기록하지 않는다.

실제 op/운영 launchctl 실행은 이 판정의 일부가 아니다. 현재 상태의 HIL 실행 준비 완료로 보고하지 않는다. 수정 뒤 구현 DA와 구체 HIL 계획 검토를 거쳐야 하며, consumer disabled·서버 18712/18703 복구 통보·HELM 재개·별도 S2 승인 경계는 유지된다. 이번 산출 외 제품 파일 수정·설치·커밋·push는 0이다.
