골 원문(GOAL-LEDGER-airag.md 복붙):
최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰 + 6순위 C13(KakaoBot 통합 보고서) published 칸 채움.

# DA 판정 — 설계 r17 (1회성 codex exec · 실행 헤더 인용)
OpenAI Codex v0.159.3
model: gpt-6.1-sol
provider: headroom
reasoning effort: high
session id: 01a145a9-b264-71b2-8297-c3333be88ca6

**최종 REJECT — blocker 1 · major 7 · minor 1 · note 4.**

대상은 커밋 `d977ad8`의 [설계 r17](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/docs/artifacts/arch-20261017-pass-call-design-r17.md:1)이다. r16·정오표·기존 구현 DA는 재심하지 않았다. 소스·checker 사실표·지정 로그를 읽기 전용으로 대조했다. 시험 실행·op·운영 DB 열기·파일 쓰기·launchctl·mbox·서브에이전트는 수행하지 않았다.

**B1 · blocker — 정상 consumer DB도 quick_check 이전에 차단하는 연결 함수 선정.**

근거: 설계 §6 L115는 두 DB 모두 core `open_readonly`로 열도록 한다. 그러나 [connect.py:206](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/src/airag/db/connect.py:206)는 `db_meta`의 engine과 core 스키마 버전을 검사한다. consumer 원장은 [ledger.py:23](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag-consumer/src/airag_consumer/ledger.py:23)의 별도 engine·`meta` 테이블을 사용하며, L314~316에서 `meta.engine`과 `user_version=4`를 검사한다.

수용: 읽기 전용 연결과 fail-closed 원칙. **반박: core 전용 opener의 consumer 재사용.** 설계대로면 정상 consumer 원장도 `open_error`가 되어 pass가 시작되지 않는다.

수정 조건: DB 종류에 맞는 읽기 전용 연결·식별 계약을 구분한다. 기존 [operations.py:156](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag-consumer/src/airag_consumer/operations.py:156)의 범용 SQLCipher 읽기 전용 연결도 참고할 수 있으나, 필요한 DB별 식별 검사를 명시해야 한다.

**M1 · major — `OpenerDirector.open` 종료는 HTTP 호출 완료가 아니다.**

근거: 설계 §4 L67은 “비스트림이라 헤더 도착이 생성 완료 뒤”라고 전제하여 `read()`를 제외한다. 실제 코드는 opener 반환 후 별도로 본문을 읽는다.

- [memory.py:391](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag-consumer/src/airag_consumer/memory.py:391): 다음 줄에서 `response.read(...)`.
- [llm_enrichment.py:200](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/src/airag/llm_enrichment.py:200): 다음 줄에서 `resp.read(...)`.
- [embeddings.py:305](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/src/airag/embeddings.py:305): 다음 줄에서 `resp.read(...)`.

비스트림 응답도 헤더 뒤 본문 수신이 지연되거나 실패할 수 있다. 현재 훅이면 `e/ok` 기록 뒤 실제 호출이 정지하거나 timeout이 발생할 수 있다.

수용: 부모 종료 로그와 분리한 시작·끝 기록, 기본 인자에 바인딩된 `urlopen`도 클래스 메서드 훅을 경유한다는 설명. **반박: 이 훅만으로 호출 전체의 종료·성공·소요를 판정한다는 주장.**

수정 조건: 본문 수신까지 포함하는 호출 경계를 설계하거나, 현재 이벤트를 명시적으로 “open 구간”으로 제한하고 본문 대기 구간을 별도로 관측한다. 응답 객체 래핑만이 유일한 방법은 아니다.

**M2 · major — trace의 파일 안전성·동시 쓰기·누락 판정 계약이 부족하다.**

근거: §4 L66~83의 `O_APPEND|O_CREAT`, 생성 모드 0600, 단일 `os.write`만으로는 다음이 보장되지 않는다.

- 기존 파일의 0600 권한 및 심볼릭 링크·비정규 파일 거부. 안전한 디렉터리라는 사실이 내부 파일까지 보장하지 않는다. 기존 [tick.py:345](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag-consumer/src/airag_consumer/tick.py:345)는 파일 자체에 `O_NOFOLLOW|O_NONBLOCK`과 `fstat` 검사를 적용한다.
- 부분 쓰기 발생 시 JSONL 완전성.
- 호출 번호·줄 수·바이트 예산의 동시 갱신. core에는 [processing.py:129](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/src/airag/processing.py:129)의 다중 worker 경로가 있다.
- 추적 실패와 실제 호출 중단의 구분. `b` 기록 후 추적 비활성화·쓰기 실패·상한 도달로 `e`가 누락될 수도 있다. 따라서 **짝 없는 `b`만으로 “중도 절단 호출”을 확정할 수 없다.**

수용: 고정 enum, 본문·프롬프트·URL·키·토큰 값 비출력, 추적 자체의 `Exception`을 삼키는 원칙. **반박: 현재 설명만으로 닫힌 스키마·크기 상한·실패 불변이 완성됐다는 주장.**

수정 조건: 파일 자체 검증, 기존 권한 처리, 부분 쓰기 처리, 번호·예산 동기화, 줄 크기의 개행 포함 여부, 필드 조합별 필수 조건을 명시한다. 계측 누락은 원인 미확정으로 처리하며, 추적 예외를 삼키는 범위에서 실제 업무 호출의 예외를 제외해야 한다. 회전·초기화 실패에도 업무 호출이 그대로 진행되는 계약이 필요하다.

**M3 · major — quick_check의 “최악 21초”가 아직 보장되지 않는다.**

근거: §6 L120은 진행 핸들러 또는 `interrupt()`를 제시하면서 SQLCipher 동작은 미확인이라고 적는다. 진행 핸들러는 연결·키 적용·읽기 검증·busy 대기·파일 I/O 전체의 마감을 자동으로 보장하지 않는다. 기존 core opener도 진행 핸들러 설치 전에 읽기 검증을 수행하고 `busy_timeout=5000`을 설정한다.

수용: 로컬 DB 스캔에 외부 호출 7초 규칙을 직접 적용하지 않는 해석. 현재 파일 크기에 대한 **7초+14초 산술**과 16MiB 기준이 임의 가정이라는 표시도 수용한다.

**반박: 이를 틱 전체에 더해지는 확정 최악 21초로 사용하는 서술.** 크기가 달라지면 공식의 합계도 달라진다.

수정 조건: 마감의 시작·종료 범위와 연결·잠금 대기·스캔·종료를 어떻게 제한하는지 명시한다. 현재 크기에서의 계획 예산과 보장된 상한을 구분하고, 실측 전 21초를 보장값으로 쓰지 않는다.

**M4 · major — 존재 여부만 보는 integrity 마커는 오래된 성공으로 점검을 우회할 수 있다.**

근거: §6 L117의 마커에는 버전과 DB 이름만 있다. 어떤 프로젝트·DB·재개 회차를 점검했는지 구분하지 못하며, 판독 시 스키마·권한 검증 조건도 없다. 이전 성공 뒤 pass가 다시 중단돼도 마커가 남으면 다음 점검은 생략된다. Master의 수동 이동 절차가 누락되면 fail-closed 게이트가 실행되지 않는다.

수용: 성공할 때만 기록하고, 기록 실패 시 다음 틱에서 재점검하는 원칙. **반박: “파일이 있으면 생략”만으로 재개당 1회 점검을 보장한다는 주장.**

수정 조건: 마커의 유효 범위를 이번 재개와 대상 DB에 결부하고, 잘못되거나 오래된 마커는 재점검으로 처리한다. 판독·기록·권한·실패 계약을 닫아야 한다.

**M5 · major — 호출 총마감과 pass 최악 시간 계산이 성립하지 않는다.**

근거: §5 L100~101의 두 부분이다.

첫째, `read` 루프에서 단조시계를 확인하는 것만으로 현재 블로킹 중인 `read`를 마감 시각에 종료하지 못한다. 연결·헤더 수신 등 read 루프 이전 대기도 포함해야 한다.

둘째, “윈도우 경계에서만 새 일 금지”라면 120초 직전에 시작한 **윈도우 전체**를 완료해야 한다. 그 안에는 여러 `/tokenize`·chat·embedding 호출이 있다. [pipeline.py:71](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/src/airag/pipeline.py:71)는 문서를 여러 semantic window로 나누고, [processing.py:91](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/src/airag/processing.py:91)는 묶음·enrichment 호출을 수행한다. 따라서 잔여 작업을 단일 호출 70초로 놓은 **`120+70=190초`는 최악 상한이 아니다.** 후속 refresh·보관·백업 시간도 빠져 있다.

수용: 120초가 임의 가정이며 70초 호출 천장과 다른 시계라는 표시. **반박: `<300초` 종료 보장.**

수정 조건: 호출 마감은 대기 자체를 남은 시간으로 제한하는 계약까지 포함한다. consumer 윈도우·core semantic window·HTTP 호출을 구분하고, 현재 구조에서 증명되지 않는 pass 최악 시간은 미확정으로 남긴다.

**M6 · major — 가정 표시는 정직하지만 56초 환산을 규칙 12의 적용값으로 확정할 근거가 없다.**

근거: §5는 8단위·56초를 가정이라고 명시한다. 그러나 기준은 **입력 2,000토큰과 출력 300자의 비율 중 큰 값**이다. `max_tokens=2048`만으로 출력 문자 수 8단위가 정해지지 않는다. `/tokenize`도 [llm_enrichment.py:237](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/src/airag/llm_enrichment.py:237)에서 실제 전체 프롬프트를 받으므로 항상 “짧은 1단위”라고 할 수 없다. v3 줄 단위 호출에도 지시문·JSON·출력 예약이 붙는다.

또한 lineage 변경 위험은 확인되지만, 이것만으로 기억 호출이 **쪼갤 수 없는 크기 아는 배치**임이 증명되지는 않는다.

수용: 쪼개기 선행 원칙, 조건부 `min(고정비+7×ceil(요청량/기준량),70)`, 내부 재시도를 이번 단위에 도입하지 않는 선택. **반박: 현재 정보에서 56초가 규칙 준수 목표값으로 도출됐다는 해석.**

수정 조건: 요청량 산정과 분할 불가 근거가 확보될 때까지 56초를 계산 예시로 제한한다. 총마감은 재시도를 포함해 70초 이내이며 재시도는 첫 출력 전으로 제한한다는 문구도 명시한다. 스트림을 도입한다면 무진행 7초 조건을 별도로 유지해야 한다. 600/300초 기본값을 채택하지 않는 방향은 타당하다.

**M7 · major — 일부 사실의 절대 표현이 §3의 호출 수·원인 후보 평가로 확대됐다.**

근거:

- **F4:** `extract_memories`는 pass당 chat **최대 1건**이다. memory 비활성, 처리할 배치 없음, 기존 pending 등에서는 0건이다([runtime.py:698](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag-consumer/src/airag_consumer/runtime.py:698), memory.py:1171·1230·1299).
- **F6:** consumer 발행 윈도우 하나와 core의 4-unit semantic window 하나는 다르다. ready replay·terminal failure·캐시·첫 호출 실패도 있어, 발행 시도 14건에서 **외부 호출 최소 70회**가 도출되지 않는다.
- **F9:** HF 캐시는 프로세스당 단일 1회가 아니라 **`(model, revision, max_tokens)`별 캐시**다([chunking.py:55](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag/src/airag/chunking.py:55)). pipeline의 입력 chunker와 번역 출력 chunker는 서로 다른 한도를 사용할 수 있다.
- **§3:** “연결 교체 = 새 호출 시작”은 가능한 해석이지 등식으로 확정할 사실이 아니다. “성공 경로의 처리량은 이번이 첫 관측”도 tick2 발행 성공·호출 완료가 확인되지 않아 성립하지 않는다.

수용: 원인 미확정 선언과 후보들을 남겨 둔 방향. **반박: 위 표현을 근거로 누적 호출 가설에 확정적인 수량·진행 의미를 부여한 부분.**

수정 조건: 조건부 처리량 예시와 관측 사실을 분리한다. §3에 `약화·배제·판명·우세`라는 단어 자체는 없지만, 위 단정은 남아 있으므로 “금지어 없음”만으로 통과할 수 없다.

**m1 · minor — R-5의 정지 행위와 “재개 전 확인” 표현을 명확히 해야 한다.**

근거: §7 L133은 재개 전 확인을 신설하면서 실제 확인 대신 미확인 위험 수용을 적는다. L135의 “15분 초과 시 정지 보고”도 정지 요청·보고인지 실제 프로세스 종료인지 불명확하다.

수용: 로그 없는 중도 종료 틱도 실패 계수에 포함하고 관찰 상한을 두는 방향. 수정 조건: 수행하지 않은 점검은 “미확인 위험 고지”로 표현한다. 보고와 실제 종료를 구분하고, T의 대리 선정이 운영 종료 권한까지 뜻하지 않도록 한다.

**N1 · note — F1~F12 대조 결과.**

| 사실 | 대조 결과 |
|---|---|
| F1 | 수용. 자식 1회 실행·부모 `subprocess.run` timeout 부재 확인. |
| F2 | 수용. 수집→refresh→발행→기억→refresh→보관→백업 순서 확인. |
| F3 | 순차 순회는 수용. 실제 분기에는 replay·terminal failure도 있음. |
| F4 | 기본 120초·2,048토큰·4,096B·4메시지 확인. “항상 1건”은 M7. |
| F5 | 지정 HTTP 어댑터 3종의 urllib 사용·내부 재시도 부재 수용. HF 간접 통신까지 포함한 “모든 HTTP”로 확장하면 안 됨. |
| F6 | 호출 구조는 확인. 윈도우 단위·호출 개수 단정은 M7. |
| F7 | 기본값 30/60/120초 확인. 운영 captured LLM·embedding 값은 미확인. |
| F8 | 소켓 timeout과 총마감 부재 설명 수용. DNS 등 전체 호출 상한까지 보장하는 값은 아님. |
| F9 | 모델·revision·한도별 프로세스 캐시로 정정 필요. |
| F10 | 지정 로그의 직접 집계는 N2와 일치. |
| F11 | checker의 mtime·종료 전 82/36초와 일치. 변경 시각만으로 성공·특정 호출 진전을 확정할 수 없음. |
| F12 | 제공된 Master 관측 사실로 취급. 이번 읽기 전용 심사에서 과거 소켓·CPU 상태를 독립 재현한 증거는 아님. |

**N2 · note — F10의 지정 로그 집계는 수용.**

원문 로그 값은 출력하지 않고 수치만 집계했다.

| 로그 날짜 | 전체 줄 | pass summary | 발행 시도 | 성공 양수 줄 | pass 소요 |
|---|---:|---:|---:|---:|---:|
| 10-11 | 9 | 3 | 모두 14 | 0 | 17.394~25.037초 |
| 10-12 | 252 | 40 | 모두 14 | 0 | 14.154~566.017초 |
| 10-13 | 34 | 21 | 모두 14 | 0 | 13.449~32.157초 |
| 10-16 | 4 | 0 | 해당 없음 | 해당 없음 | 해당 없음 |

summary 64건 모두 `memory_provider_called=True`, 각 날짜 안의 연속 `memory_attempts` 차이는 +1이다. 10-12의 300초 초과 pass는 566.017초 1건이다. 문서의 반올림 수치와 맞는다. **10-02 로그는 이번 지정 입력 밖이므로 20.4~128.5초 및 5일 전체 범위까지 인증하지 않는다.**

**N3 · note — 기억 pending 고착 위험과 복구 호출처 0 서술은 수용.**

[memory.py:1196](/Users/yoonhwan/Project/ai-feature-pack/.worktrees/rag-transplant/feature-pack/rag-consumer/src/airag_consumer/memory.py:1196)의 `should_call=created`, L1230~1234의 재호출 생략, L1289의 ambiguous pending 비자동 재발행 설명이 일치한다. 복구 함수는 L1457에 정의되어 있고, 소비자 production 소스 검색 및 Serena 참조 조회에서 호출처가 확인되지 않았다.

이는 **pending 지속·해당 lineage의 진전 정지 가능성**을 뒷받침한다. 실제 운영 pending 존재·개수나 이번 16분의 원인이라는 증거는 아니다. quick_check도 이 업무 상태를 검사하지 않는다.

**N4 · note — 2종 점검 권고와 “지금 0건→다음 1건”은 조건부 수용.**

profile-source 키가 별도이고 기존 키와 달라야 한다는 설명은 runtime.py:433~446과 일치한다. `run_once`에는 profile-source를 여는 호출이 없으며, `_install_profile`의 참조는 `init`에서 확인됐다. 따라서 **현재 정상 pass 경로의 consumer·projection 2종 점검**에는 코드 근거가 있다. 제외 근거는 작은 크기·오래된 mtime보다 이 호출 경로를 중심으로 써야 한다. 3종 지시 전체를 완료했다고 표현해서는 안 된다.

T·마커 절차·2종 범위는 대리로 제안하고, 이후 구체적인 설치본·관찰 계획·미확인 위험을 묶어 재개 승인 1건으로 올린다는 구조는 일관적이다. 다만 본 심사는 설계 심사이며 그 승인을 대신하지 않는다.

**최종 판정: REJECT.** 정상 consumer 원장을 차단하는 B1과 M1~M7을 설계에서 해소해야 한다. 계측 우선 방향, 지정 로그 집계, 기억 pending 위험 지적은 수용하지만, r17 현재안은 계측 완전성·게이트 가용성·시간 상한을 충족하지 못한다.
