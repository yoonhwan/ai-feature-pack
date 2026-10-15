골 원문: 최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
골의 어느 축인가: A03 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 권한 팝업 해결 P 프로브의 구현 재심이다.
작업 디렉터리: /Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant (브랜치 feature/rag-transplant · push 금지 — PUBLIC 리포 · Serena 미사용). 답변 한국어.

판정: **REJECT — blocker 1 / major 3 / minor 1**

검토: ft-airag-da-codex#1 · 2026-10-15 · 발주 #2505 · 대상 `6b696e7`·`3faa8ea` · 기준 HEAD `3faa8eaf5026aedd513533e86a73dc4b824312e3`.
아래 `sh:N`은 `feature-pack/rag-consumer/ops/probe-opa/probe.sh`, `py:N`은 같은 폴더의 `probe.py`, `시험:N`은 `feature-pack/rag-consumer/tests/test_probe_opa.py`의 행 번호다. 정본은 `arch-20261015-opa-popup-design-r4.md`, 이전 판정은 `da-20261015-sol-p-code-r1.md`다.

원본 합성 시험은 **53 passed in 147.50s, rc=0**이다. r1 반례를 API/모드 변경에 맞춰 재실행했고 직접 소스 변이 **12종 모두** 관련 시험이 탐지했다. 그러나 PID 기록 중 시한 미집행, 셸 ps의 무제한 대기, 외부 job 경로의 부분 일치, 연결되지 않은 AppData 요청의 누락이 남는다. 새 입력 거부 경로의 원문 출력도 확인해 현재 HIL 실행 진입은 반송한다.

실제 op·운영 launchctl·외부 DNS/접속·운영 토큰/자격 파일·DB는 호출하거나 열람하지 않았다. 합성 명령·임시 HOME/토큰·로컬 자식만 사용했다. 직접 만든 자식만 종료했고 공유 프로세스/데몬은 종료하지 않았다. 제품 소스/시험 수정·설치·커밋·push는 0이다.

## 1. r1 일곱 항목 폐쇄 대조

| r1 | r2 수정과 재실행 | 판정 |
|---|---|---|
| B1 외부 시도 마감 | py:185–206의 고정 deadline/남은 시간 차감은 맞음. 100ms 시도를 PID 기록이 넘긴 뒤 새 100ms communicate 없이 50ms 이하 drain만 확인. P4 DNS는 별도 자식으로 303ms에 종료/재수거 | **부분 반영**. 기록 중 직접 자식 생존은 아래 B1 |
| M1 전체 75초 | sh:43–58,174–208의 helper 상한·시작 시계 개선. 기존 4초 bootstrap 반례는 축소 예산에서 **630ms**에 중단 | **부분 반영**. 셸 ps는 아래 M1 |
| M2 소유 확인 | preflight loaded 반례는 **bootstrap 0/bootout 0**. bootstrap 시도 전에는 정리하지 않고 외부 인자 불일치 시험 추가 | **부분 반영**. 경로 부분 일치는 아래 M2 |
| M3 TCC/관측 예산 | Camera를 none_logged_ok로 구분, msgID별 연결, info/debug, 종료 후 tail 대기, charge 방식으로 외부 대기 제외 | **주요 수정 수용**, 연결 불가 AppData의 false negative는 아래 M3 |
| M4 환경 기반 모드 전환 | 명시적 --mode, production의 주변 PROBE_/FAKE_ 거부. 기존 완전 합성 상속 반례는 mode=production/AmbientOverrideRefused, op 0회 | **종결** |
| m1 interpreter | production 기본 설치 runtime 경로, 절대경로/실행 가능 파일 검사, plist에 -I | **종결** |
| m2 자식 env 시험 공백 | 새 unit/실제 합성 자식 이름 검사. 이전 생존 변이가 두 시험 모두 실패 | **종결** |

종결은 이 코드 범위에 대한 것이다. 실제 운영 계정·TCC 상태·서비스 회복을 시험했다는 뜻은 아니다. r1의 원래 반례가 닫힌 부분과 아래 남은/새 결함을 구분한다.

## B1 — PID 기록이 한도를 넘으면 실제 자식 종료는 그 기록이 돌아올 때까지 지연된다 (blocker)

근거: py:138–149,185–206 · 시험:545–583.

새 7초를 다시 주는 문제는 고쳤다. 하지만 Popen 뒤 `book.after()`는 동기로 실행되고, deadline 확인과 kill은 **그 함수가 반환한 뒤**에만 수행된다. ps 조회·원자 파일 기록이 지연되는 동안 독립적인 시한 집행이 없다. 기록 후 remaining<=0을 검사해 추가 communicate를 생략하는 것은 이미 지연된 종료 시점을 되돌리지 못한다. 기존 새 시험도 «추가 wait가 짧다»를 검사하며 실제 첫 kill 시각은 검사하지 않는다.

**기본 상수 재현:** ATTEMPT_S=7.0을 바꾸지 않고 post-spawn PID 기록을 7.4초 지연시키자 첫 kill이 **7,405ms**에 호출됐다. 자식은 합성 Python sleep이며 실제 op가 아니다. 직접 자식은 정상 재수거했다. 이는 SIGKILL 이후 회수 오버헤드가 아니라 **첫 종료 신호 전**의 초과다. 생산 환경에서 현재 디스크/ps가 그만큼 느리다는 주장은 아니며 기록 지연 시 계약을 검증한 반례다.

필수 수정: 기록이 늦어져도 직접 자식의 실행 시한은 별도로 집행되게 하거나, 기록 작업이 실행 시한을 막지 않는 구조로 바꾼다. 기록/준비가 시한을 다 썼다면 새 자식을 시작하지 않는다. 시작 시점→**첫 종료 신호 시점**을 기본 상수와 축소 상수에서 단언하고, 값 비노출·직접 자식만 종료·재수거·기록의 부분 실패 계약도 유지한다. 시도 상수를 늘려 해결하지 않는다.

## M1 — pid_matches의 제한 없는 ps 때문에 정리 시한과 전체 상한이 여전히 깨진다 (major)

근거: sh:61–64,72–95,102,130,233–236.

launchctl과 Python helper는 bounded로 감쌌지만 **셸의 ps는 그대로 무제한**이다. 정리 시간이 이미 소진된 분기에서도 잔존 확인을 위해 pid_matches를 다시 호출한다. 한 PID의 조회가 지연되면 이후 PID마다 다시 그 지연을 지불하고, 상한에 도달해도 빠져나오지 못한다.

합성 재현: PID 기록 중에는 정상 ps를 사용하고, 가짜 bootout 시점부터 ps만 3초 대기하도록 바꿨다. run/clean 예산은 **6+5=11초**인데 wrapper는 **19.126초**, rc=0으로 반환했다. 대상은 이 실행의 이미 끝난 합성 PID들이고 실제 job/공유 프로세스는 없었다. 따라서 정리 오버런이 실패 상태로도 표시되지 않았다.

필수 수정: PID 조회도 남은 정리 시한 안의 유한 호출로 만들고, 소진 뒤에는 추가 조회를 시작하지 않는다. 미확인 PID는 조회를 기다리는 대신 «잔존 확인 필요»로 기록하고 종료한다. bounded helper/close/report를 포함한 **전체 반환 시각**을 여러 PID·느린 ps·소진 후 조회 반례에서 검증한다.

## M2 — PROBE_DIR 부분문자열은 자기 job 소유를 입증하지 못한다 (major)

근거: sh:103–108 · 시험:687–706.

cleanup은 launchctl print 출력 **어디에든** PROBE_DIR 문자열이 있으면 자기 job으로 인정한다. 기존 새 시험의 `/other/place/not-ours`는 걸러지지만, 실제 argv가 `<우리 PROBE_DIR>-foreign`이면 같은 grep에 일치한다. 환경/설명 필드에 경로가 있는 경우도 구분하지 않는다.

합성 재현: 같은 라벨의 loaded 출력에 `/other/python --run <우리 디렉터리>-foreign`, 다른 plist 경로를 주었다. 결과는 **bootout 1회, rc=0**이었다. 가짜 launchctl의 요청만 관찰했고 실제 외부 job을 종료하지 않았다.

필수 수정: loaded job의 plist 경로/ProgramArguments를 구조적으로 읽어 예상한 **정확한 인자와 경로**에 대조하고, 부분/부가 필드 일치로 소유를 인정하지 않는다. 모호하거나 파싱할 수 없으면 bootout하지 않고 잔존 확인 필요로 닫는다. 접두사/접미사·다른 인자·환경 필드만 같은 경로·예상 자기 job을 함께 시험한다. bootstrap 직후 중단 회복은 유지한다.

## M3 — msgID가 없거나 지원 형식으로 연결되지 않은 AppData 요청을 미관측으로 바꾼다 (major)

근거: py:92–97,302–323 · 시험:86–123,710–732.

Camera를 제외하고 msgID로 속성을 연결하는 수정은 적절하다. 그러나 시간 형식이 맞는 줄은 total에 세면서, msgID를 파싱하지 못한 줄은 그룹에서 버린다. AppData 요청이 분명히 적힌 줄도 그룹에 없으면 appdata=[]가 되어 **none_logged_ok**다. 지원하지 않는 귀속 형식을 성공적인 음성 관측으로 처리하는 셈이다.

합성 compact 입력 `AUTHREQ_CTX: service=kTCCServiceSystemPolicyAppData, pid=321`(msgID 없음)은 **none_logged_ok**로 반환됐다. 실제 이 Mac에서 현재 해당 형식이 출력됐다는 주장은 아니다. 식별 가능한 AppData 사건이 미지원/누락된 msgID 때문에 false negative가 되는 파서 경계 시험이다.

필수 수정: 명시적인 AppData 요청은 연결 실패 시 최소 seen_unattributed 또는 observation unknown으로 남기고, none_logged_ok로 낮추지 않는다. 지원하지 않는 ID 형식도 보수적으로 처리한다. 연결 가능한 자기 요청·다른 서비스·다른 요청의 PID·msgID 부재/미지원/부분 수집을 fixture에 넣는다. 이미 고친 tail 대기·info/debug·외부 시간 미차감은 유지한다.

## m1 — 운영 모드 거부 전에 잘못된 시험용 시간 값을 원문으로 출력한다 (minor, 신규)

근거: sh:126–145.

PROBE_T_CLEAN을 읽고 `[ "$T_CLEAN" -gt 5 ]`로 비교하는 시점이 production의 PROBE_/FAKE_ 거부보다 앞이다. 값이 숫자가 아니면 Bash가 그 문자열을 stderr에 그대로 내보낸다. 합성 canary를 넣은 일반 모드 호출에서 **rc=2로 거부되면서 canary도 stderr에 출력**됐고 폴더 생성/op/launchctl 호출은 없었다.

실제 서비스 토큰 파일의 값이 이 변수로 흘렀다는 증거는 아니므로 그 흐름의 누출로 주장하지 않는다. 다만 거부 대상 입력을 먼저 해석해 자유 텍스트를 출력하는 경계 결함이다. production은 시험 변수의 값을 읽기 전에 이름만 검사해 거부하고, selftest의 숫자 검증도 원문 없는 고정 오류를 사용한다. canary 비출력 회귀 시험을 추가한다. r1 m1(interpreter)은 위 표대로 종결했으며 이 항목은 새 입력 처리 결함이다.

## 2. 새 P4 worker와 모드 경계의 별도 확인

P4는 이제 부모 run_child가 별도 Python `--p4-worker`의 PID를 기록·제한·재수거한다(py:425–452). 합성 DNS sleep 4초에서 부모 시도 예산 0.3초로 **303ms**, timeout/child_exited/reaped를 확인했다. child env를 관찰해 부모의 합성 OP_SERVICE_ACCOUNT_TOKEN이 전달되지 않음을 확인했고 argv에는 고정 host/port/시간만 있다. 결과는 exit code→유한 상태로 바뀌며 원문 stdout/stderr는 결과에 들어가지 않는다. P4의 TCC 관측은 생략된다. 이 경계에서 별도 값/후손 종료 결함은 발견하지 않았다. 공통 PID 기록 시한 문제 B1은 P4에도 적용된다.

모드는 wrapper가 production/selftest를 명시하고 worker는 주변 PROBE_/FAKE_를 production에서 거부한다. 기존 완전 합성 상속 반례는 **production/AmbientOverrideRefused/steps=[]/op 0회**였다. 추가 모드 인자 5경우도 rc=0인 검증기로 확인했다: mode 생략/production/미지원 값에서 주변 selftest 변수는 승격되지 않고, 중복 mode 인자는 usage 오류로 실제 execute 전에 거부됐다. 미지원 값은 production 기본으로 해석되므로 유효한 두 값만 받아들이는 엄격한 문법과 같다고 주장하지 않는다. 현재 wrapper가 만드는 한 개의 고정 mode 인자에서 환경에 의한 위조 경로는 닫혔다. 명시적 selftest 인자를 사용한 정상 시험 경로 자체는 허용 계약이다.

## 3. 재실행과 직접 소스 변이 증거

원본: `feature-pack/rag/.venv/bin/python -B -m pytest tests/test_probe_opa.py -q -p no:cacheprovider` → **53 passed in 147.50s (0:02:27), rc=0**. 이전 반례 실행기의 케이스를 r2 API/명시적 모드에 맞춰 재사용했으며, «기존 결함 재현» 단언을 «폐쇄 확인» 단언으로 바꾼 부분과 새로운 잔여 반례를 함께 기록했다. 모든 반례 검증기는 기대한 결과를 확인해 rc=0이다.

변이는 r1과 같이 임시 복사본에 문장을 직접 대입했다. 관련 원래 시험을 실행하고 실패 단언이 해당 변경을 잡는지 확인했다. 제품 파일은 변경하지 않았다.

| 직접 변이 | 결과 |
|---|---|
| P0 토큰 주입 | 정상 a에서 TOK 없음 단언 실패 |
| P1b TCC 조건 제거 | l의 4조합 중 3실패/1통과 |
| TCC 0줄을 none으로 처리 | l의 4조합 중 3실패/1통과 |
| 9번째 상태 삭제 | m 목록 단언 실패 |
| 무제한 파이프 drain | k 시간 상한 단언 실패 |
| 합성 토큰을 leak.txt에 저장 | e의 토큰 비출력 단언 실패 |
| 부모 env 전체 전달 (이전 생존 변이) | 새 실제 자식/함수 시험 **2 failed** |
| 기록 후 남은 시간 대신 새 시도 상한 | 새 B1 시험 **2 failed** |
| P4 부모 communicate 제한 제거 | DNS 6초를 기다려 2.5초 상한 단언 실패 |
| launchctl 제한 제거(stdout/stderr 합치기는 유지) | 14초 bootstrap을 기다린 뒤 timeout 거부 단언 실패, 전체 **17.451초** |
| job 소유 확인 무시 | 외부 job 시험의 bootout 없음 단언 실패 |
| 주변 PROBE_SELFTEST가 mode보다 우선 | mode=production 단언 실패 |

총 **12종 모두 탐지**. 모드 승격 변이는 production guard를 일부러 깨므로 시험용 주변 환경에 fake launchctl/state/HOME/TMPDIR를 추가로 고정한 뒤 실행했다. 기존 판정 단언은 바꾸지 않았고 실제 op/운영 launchctl/토큰/네트워크로 빠지는 경로를 만들지 않았다. 이 안전 고정을 생략한 변이는 실행하지 않았다.

반례 실행기: `/tmp/airag-p-da-code-r2-checks.py` (r1 실행기의 사례 재사용).
반례 결과: `/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-p-da-r2-checks-r083y229/evidence.json`.
변이 실행기: `/tmp/airag-p-da-code-r2-mutations.py`.
변이 결과: `/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-p-da-r2-mutations-dg9v9gvq/summary.json` 및 변이별 result.txt. bootstrap 변이는 stderr 병합을 보존해 preflight 형식 변경으로 먼저 거부되는 오탐을 제거한 뒤 재실행했다.

## 4. 재심 범위와 실행 경계

재심은 B1의 **기록 중 실제 종료 시한**, M1의 **느린 ps/예산 소진 후 조회**, M2의 **정확한 job 소유**, M3의 **연결 불가 AppData 사건**, 새 m1의 **거부 입력 비출력**이다. 이미 닫힌 환경 모드 전환·interpreter·env 허용목록 시험과 새 P4 정상 회수는 유지한다.

Master의 clean HEAD 전체 회귀 결과는 작성 시점까지 수신하지 않아 여기서 별도 PASS로 기록하지 않는다. 실제 프로브 HIL·실제 op·운영 launchctl·설치·S2·consumer 재개를 승인한 판정이 아니다. 수정 재심 뒤 기존 HIL과 서버 18712/18703 복구 통보·HELM 재개·disabled 유지 경계를 따른다.
