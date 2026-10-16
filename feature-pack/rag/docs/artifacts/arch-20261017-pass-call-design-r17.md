최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰 + 6순위 C13(KakaoBot 통합 보고서) published 칸 채움.
골의 어느 축인가: A03 — C12. 재개 2회차 tick2 의 pass 단계 16분 무종료(판정 2067) → 원인 단위 설계 r17(판정 2068) + 추가 요구 Q6(판정 2071, DB 3종 PRAGMA quick_check). 작성 ft-airag-arch-claude#3 · 2026-10-17 · 코드 수정 0·시험 실행 0·op 0·운영 파일 접촉 0(코드·추적 문서·틱 로그 수치만 읽음).

# 0. 답 요약 (후보 단계 — 원인 확정 아님, 확정은 계측 뒤)

- **Q1** pass 의 외부 호출은 ①기억 추출 chat(18703, pass당 1건) ②윈도우 발행 core `add/retry`(윈도우마다 순차: 서버 토큰 계산·의미 묶음 chat·번역/요약 chat·임베딩 배치 POST) ③HF 토크나이저 로드(네트워크 가능, 프로세스당 1회) 세 부류. 상한은 전부 30/60/120초(urllib 소켓 단위)이고 **호출 내부 재시도 없음 · pass 전체 마감 없음**(`tick.py:400-403` `subprocess.run` 에 timeout 인자 없음). 규칙 12 와 어긋나는 곳 = 상한 값 3종, 총 마감 부재, 출력 기준량 초과 호출(§2 표).
- **Q2** 후보 6개(§3). 이번 16분은 «호출 1건 정지» 단독으로는 «연결 교체(01:46 포트 64929 → 01:48 포트 50338)»와 맞추기 어렵고, «윈도우 14개 × 호출 여러 개의 느린 누적»·«서버 생성 지연»과 어긋나는 사실이 없다 — 단 호출별 소요 미계측이라 가르지 못한다.
- **Q3** 호출 1건당 한 줄을 **`pass-trace.jsonl` 에 즉시 추가 기록**(시작 줄·끝 줄 분리 → 멈춘 호출이 «시작만 있고 끝 없음»으로 남는다). 틱 로그 probe 와 같은 닫힌 스키마·크기 상한·실패 불변 방식 재사용(§4). 부모 로그 줄은 pass 가 끝나야 써지므로 부모 probe 에 얹으면 이번 같은 중도 종료를 못 남긴다.
- **Q4** 규칙 12 목표 값(§5): 기억 추출 시도당 56초(출력 예약 환산 8단위)·임베딩 배치는 쪼갠 뒤 상한·토큰 계산 7초·묶음/번역 chat 56초·**호출마다 총 마감 = 시작+상한(read 루프에서 확인)**·pass 는 «윈도우 경계에서만 새 일 시작 금지» 마감. **값은 계측 뒤에 확정**(수치 환산은 가정 표시).
- **Q5** 다음 한 걸음 = **계측 먼저(행위 불변) + DB 점검 게이트(읽기 전용)**, 규칙 12 상한 변경은 이번 재개에서 제외. 재개 3회차 조건 R-1~R-6 개정은 §7, 오빠 결정 지금 0건·다음 1건(=3회차 재개 승인, 관찰 상한 수용 포함).
- **Q6** quick_check 는 `_pass_child` 안(키는 이미 자식 stdin 에만 있음)에서 **consumer·projection 2종 1회**. profile-source 는 4번째 키(`PROFILE_SOURCE_KEY_ENV`)가 필요해 tick 의 키 3개 계약·op 읽기 횟수를 바꾸므로 이번 단위 제외 권고(§6, 두 안 병기). 결과 = ok/not_ok·DB 이름만, 실패면 pass 시작 안 함.
- **DA 소환 권고: 예** — 설계 r17 전체 1회(§9 중점 4개).

# 1. 사실 칸 (판정 없음 · 근거 표기)

| # | 사실 | 근거 |
|---|---|---|
| F1 | pass 는 자식 프로세스 `_pass_child` 한 번에 `run --once`. 부모 대기는 `subprocess.run(argv, input=keys, …, check=False)` — **timeout 인자 없음** | `tick.py:399-403`, `_pass_child.py:75-84` |
| F2 | `run_once` 순서: 수집 → refresh → **윈도우 발행(대기 중 전부, 순차)** → **기억 추출(1배치)** → refresh → 보관 → 백업. 전체 마감 코드 없음 | `runtime.py:1002-1012`, `bridge.py:368-393` |
| F3 | 윈도우 발행 호출은 `for window_id in state["pending_publication_ids"]` 순차. 윈도우 1개 처리 = core `add`(또는 `retry`) | `bridge.py:252,303,308,387-393` |
| F4 | 기억 추출은 `concurrency=1` → `extract_memories` → **pass당 chat 1건**. 입력 ≤4,096B·메시지 ≤4개, `max_tokens=2048`, `timeout_s` 기본 120.0(운영 경로가 지정 안 함) | `runtime.py:58-59,722-725,1008`, `memory.py:189-190,389-391,1274-1310` |
| F5 | 모든 HTTP 는 `urllib.request.urlopen(..., timeout=…)` 직접 호출 — SDK 기본값(600/300) 경로 없음. 호출 내부 재시도 없음(실패는 윈도우·배치 단위로 다음 pass 가 재시도) | `memory.py:391`, `llm_enrichment.py:200`, `embeddings.py:305`; 재시도 grep 결과 호출 내부 루프 0 |
| F6 | 윈도우 1개(= 4 단위 묶음마다) 호출: 서버 토큰 계산 `/tokenize`(chat 직전마다 1회) + 의미 묶음 chat 1건 + 번역·요약 chat(v3 프로필이면 줄 단위 호출 반복 + 조립본 1건) + 임베딩 POST(배치 64) | `llm_enrichment.py:222-244,374,431-512,550`, `processing.py compute`, `profiles.py:35`, `embeddings.py:437-470`, `pipeline.py:65-72,184` |
| F7 | 시도당 상한 기본값: 임베딩 30.0·LLM(토큰 계산·chat) 60.0·기억 120.0. 프로필이 캡처한 실제 값은 암호화 DB 안이라 **미확인** | `embeddings.py:54`, `llm_enrichment.py:67,128`, `memory.py:189` |
| F8 | urllib 의 timeout 은 소켓 연산(연결·수신 1회)당이며 **총 마감 코드는 이 코드에 없음**. 호출마다 새 연결(포트 교체가 호출 경계일 수 있음 — 일반 동작에서의 추정) | 코드 grep(총 마감 로직 0) · 포트 교체는 Master 실측 |
| F9 | HF 토크나이저: `from_pretrained` 는 첫 사용 시 네트워크 가능, `lru_cache` 는 프로세스 수명 → **pass 자식이 새로 뜰 때마다 1회** | `chunking.py:55-71` |
| F10 | 틱 로그(10-02·11·12·13·16, 수치 필드만): pass 줄의 `published_attempted` 는 10~14, **`published_succeeded > 0` 인 줄 0건**(필드가 있는 줄 기준). 실패 pass 소요 13.45~32.16s(10-13 21줄), 10-12 에 **566.02s 1줄**, 10-02 ok 줄 20.4~128.5s. `memory_attempts` 는 pass마다 +1(provider 호출 기록 True) | 로그 직접 집계(값 비출력) |
| F11 | tick2 (01:32:02 시작) 종료 82초·36초 전까지 `consumer.db`(01:47:10)·`projection.db-wal`(01:47:56) 쓰기 → 진행 중이었다는 파일 시각 사실. 틱 로그 줄 0(중도 종료) | checker-integrity-facts.json q1·q3 |
| F12 | Master 실측: pass 자식 16분·CPU 0%·sleep, 열린 연결은 18703 ESTABLISHED + cloudfront https 1(CLOSE_WAIT)뿐, 18703 연결의 로컬 포트 64929(01:46) → 50338(01:48), 서버 `/v1/models` 200(0.42s·0.63s), load1 72.9(tick1)→~37 | 브리프 |
| F13 | 시스템 키 3개는 `AIRAG_CONSUMER/PROJECTION/ARCHIVE_KEY_HEX`, profile-source DB 키는 별도 `PROFILE_SOURCE_KEY_ENV`(다른 키여야 함) | `tick.py:32`, `runtime.py:433-446` |

# 2. Q1 — pass 외부 호출 전수와 하드 룰 12 대조

| 호출 | 대상 | 시도당 상한 | 재시도 | 총 마감 | 스트림 | 규칙 12 와의 거리 |
|---|---|---|---|---|---|---|
| 기억 추출 chat `memory.py:389-391` | 18703 `byz-llm`(`deployment_setup.py:154`) | 120.0 (`memory.py:189`) | 없음 | 없음 | 비스트림 | 상한 120>70 천장. 출력 예약 `max_tokens=2048`(≈기준 출력 300자의 약 8단위 환산, 가정) → 쪼개기 선행 대상이나 **쪼개면 lineage id 가 바뀌어 기억 재처리**(`memory.py:1313-1318`)이므로 이번 단위에서 쪼개지 않음 |
| 서버 토큰 계산 `/tokenize` `llm_enrichment.py:222-233` | 18703 | 60.0 | 없음 | 없음 | 비스트림 | 1단위(짧은 요청)인데 상한 60 → 7초가 기본 |
| 의미 묶음 chat `llm_enrichment.py:550` | 18703 | 60.0 | 없음 | 없음 | 비스트림 | 4 단위 묶음 입력 + 출력 예약 최대 2,048 토큰(`DEFAULT_MAX_TOKENS`) → 입력 ≥1~2단위, 출력 다단위 추정 |
| 번역·요약 chat `llm_enrichment.py:374` (v3: 줄 단위 반복 `:431-512`) | 18703 | 60.0 | 없음 | 없음 | 비스트림 | v3 이면 한 묶음 안 호출 수가 줄 수에 비례(상한 `MAX_UNITS_PER_CALL` 로만 제한) |
| 임베딩 POST `embeddings.py:305` | 18712 `byz-embed` | 30.0 | 없음 | 없음 | 비스트림 | 배치 64×텍스트당 ≤`max_tokens` → 입력 환산 수~십수 단위 가능(프로필 값 미확인). `max_batch`·`timeout_s` 는 프로필 지문에서 제외된 운영 노브(`embeddings.py:120-125`)지만 **프로필 저장 방식 확인 전 변경 금지** |
| 임베딩 문서 로컬 토큰 계산 `embeddings.py:457-458` | 로컬 HF 토크나이저 | (네트워크 아님) | - | - | - | 외부 호출 아님 |
| HF 토크나이저 로드 `chunking.py:71` | HF 허브 계열(cloudfront 후보) | **코드에 상한 없음**(라이브러리 기본, 값 미확인) | 미확인 | 없음 | - | pass 자식마다 1회 → 후보 중 하나(H5) |
| 문서 정규화(vision) `pipeline.py:150` | 18703(이미지 문서일 때만) | 60.0 | 없음 | 없음 | 비스트림 | 이 윈도우들이 텍스트인지 **미확인** |
| 전체 pass | — | **없음** | — | **없음** | — | `tick.py:400-403`; launchd 간격 300초 동안 뒤 틱은 flock 으로 `PREVIOUS_TICK_RUNNING` |

**어긋남 3종**: ⓐ 상한 값이 7초 기본·크기 비례 공식·70초 천장 어디에도 맞지 않음(30/60/120) ⓑ 호출·윈도우·pass 어느 단위에도 총 마감 없음(소켓 단위 timeout 뿐) ⓒ 출력 기준량을 크게 넘는 chat 을 쪼개지 않고 호출. 600/300 값은 **이 경로에서는 보이지 않음**(F5).

# 3. Q2 — 이번 16분의 가설 후보표 (단정 없음)

| 후보 | 지지하는 사실 | 어긋나는/모자란 사실 |
|---|---|---|
| 호출 1건이 길게 대기 | 상한이 30~120초로 길고 총 마감 없음(F5·F7·F8) | 16분(990초)은 120초 상한 단일 호출로는 설명되지 않음 — 바이트가 계속 흘러들면 소켓 timeout 이 안 걸리므로 불가능하지는 않음(미확인). 연결 교체(F12)는 단일 호출 정지만으로는 설명이 어려움 |
| 호출 개수가 많아 느리게 누적 | pass당 윈도우 14개가 순차(F3·F10), 윈도우당 최소 /tokenize 2 + chat 2 + 임베딩 1 이상(F6) ⇒ **최소 약 70회**, 연결 교체 = 새 호출 시작(F8·F12), 파일 쓰기가 종료 36~82초 전까지 이어짐(F11) | 호출별 소요·윈도우별 진행 미계측. **로그 5일치에서 발행 성공 0건**이라 «성공 경로의 처리량»은 이번이 첫 관측(F10) — 윈도우당 평균 약 70초면 990초(산수일 뿐 관측 아님) |
| 서버 처리 지연(생성 길이·큐) | `/v1/models` 200 은 목록 조회라 생성 부하 상태를 보여주지 않음(F12), 출력 예약 2,048 토큰 | 지연 호출의 서버 쪽 시각 없음 |
| 호스트 부하 | tick1 load1 72.9, 이후 ~37 (F12). 자식 CPU 0% 는 «서버 응답 대기» 와도 모순 아님 | tick2 구간 부하 값 없음(내 스냅샷 23.7/14코어는 다른 시각) |
| HF 토크나이저 로드(cloudfront) | pass 자식마다 로드(F9), cloudfront CLOSE_WAIT 1개 | CLOSE_WAIT = 상대가 이미 닫은 연결 → 현재 대기 원인이라는 근거 아님. 로드는 pass 시작에 한 번인데 포트 교체는 16분 뒤에도 발생 |
| DB 쓰기 대기(sqlite busy 5초·flock) | 파일 쓰기 흔적(F11) | 대기 소켓은 18703 ESTABLISHED — DB 대기는 지연의 일부일 수는 있어도 소켓 상태와 어긋남 |

가르는 데 필요한 자료 = 호출별 시작·끝 오프셋과 윈도우 경계(§4). 원인은 계측 뒤 확정.

# 4. Q3 — 계측 최소안 (행위 불변)

**기록 장소 = `pass-trace.jsonl`(틱 로그 디렉터리, 모드 0600), 자식(`_pass_child`)이 호출 시작·끝마다 즉시 한 줄 추가.** 이유: 이번 사건은 pass 가 끝나지 않아 부모가 로그 줄을 못 쓰는 경우라, pass 끝에 모아 쓰는 방식(probe 부모 경로)으로는 기록이 0이다(F11).

- **전달 경로**: 부모가 `--trace-file <log_dir>/pass-trace.jsonl` 을 자식 argv 에 추가(경로 검증은 부모의 안전한 log_dir 재사용: 심볼릭 링크·비정규 파일 거부). 자식은 `os.open(O_WRONLY|O_APPEND|O_CREAT, 0o600)` 로 열고 줄 하나를 `os.write` 한 번으로 씀(fsync 없음 — 프로세스가 죽어도 커널 버퍼로 남음, 호스트 정전은 대상 아님). pass 시작 때 기존 파일을 `pass-trace.jsonl.prev` 로 `os.replace` 해 중도 종료된 직전 pass 의 흔적을 한 세대 보존.
- **후킹 위치(행위 불변 최소)**: `urllib.request.OpenerDirector.open` 한 곳을 감싸 시작·끝 기록 후 **같은 반환값·같은 예외**를 그대로 통과(기억·임베딩·LLM 모두 `urlopen` → `OpenerDirector.open` 경유, `memory.py:314` 기본 인자 바인딩 시점과 무관). 윈도우 경계는 `bridge._publish_window` 진입·종료 한 쌍(소비자 소유 함수). 응답 `read()` 구간은 비스트림이라 헤더 도착이 생성 완료 뒤이므로 이번 단위에서 감싸지 않음(응답 객체 래핑은 행위 위험).
- **닫힌 스키마(줄당 ≤192B, 객체당 추가 키 거부)**:

| 필드 | 형 | 조건 |
|---|---|---|
| `v` | int | ==1, 필수 |
| `n` | int | 호출 일련번호 0~99,999, 호출 줄만 |
| `ph` | str | `b`(호출 시작)·`e`(호출 끝)·`wb`·`we`(윈도우 시작·끝) 중 하나 |
| `i` | int | 윈도우 순번 0~9,999, `wb`·`we` 줄만 |
| `name` | str | `llm`·`embed`·`other` **3종**(경로가 chat·tokenize→llm, embeddings→embed, 그 외→other; URL·포트 값은 기록하지 않음) |
| `tok` | bool | `/tokenize` 호출이면 true, `b`·`e` 줄 |
| `t` | float | pass 시작 기준 오프셋 초, 0~86,400, 소수 3자리 |
| `out` | str | `e` 줄만: `ok`·`timeout`·`http_error`·`unreachable`·`error` |

  줄 수 상한 2,048(초과분은 쓰지 않고 메모리에 `dropped` 개수만 증가, 파일 총 ≤384KiB). 바이트 수·본문·프롬프트·URL·키·참조 값 기록 0.
- **복구 사슬(probe 와 같은 방식)**: ①정상 기록 → ②스키마 검증 실패면 그 줄 건너뜀(최소 줄도 불가면 추적 비활성화·카운터만) → ③쓰기 `OSError` 면 추적 전체 비활성화. **어떤 경우에도 호출 결과·예외·반환 코드·summary 는 바뀌지 않음.** 추적 코드의 예외는 전부 삼키되 `BaseException`(중단 신호)은 그대로 통과.
- **멈춘 호출 판별**: 파일에 `b` 만 있고 짝 `e` 가 없는 `n` = 중도 절단 호출. «느림 vs 멈춤»은 마지막 `b` 이후 경과와 이후 줄 유무로 읽는다 — 이 가름은 계측 결과가 말하는 것이지 설계 시점의 판정이 아님.
- **한계(미포함 표기)**: HF 토크나이저 로드는 urllib 가 아니라 H5 판별 불가 → 보완으로 «첫 호출 시작 오프셋 `t`» 가 pass 시작 이후 몇 초인지를 보면 로드 구간 크기를 간접으로 알 수 있음(별도 훅 없음). `urlopen` 밖 DB 대기는 미포함.
- **시험 설계(실행 보류)**: 가짜 opener 로 정상·timeout·HTTPError·URLError 반환/예외 동일성, 기록 실패 주입(디렉터리 쓰기 불가·줄 상한 초과)에서 호출 결과·종료 코드 동일, 줄 스키마 위반 거부, 최종 로그·stdout 에서 추적 영향 0, 줄당 바이트·총 파일 크기 상한.

# 5. Q4 — 규칙 12 적용 설계 (값은 계측 뒤 확정, 환산은 가정)

**순서 원칙**: 상한을 늘리기 전에 쪼개기 → 쪼갤 수 없는 크기 아는 배치만 `시도당 = min(고정비 + 7초 × ceil(요청량/기준량), 70초)`. 로컬 HTTP 는 CLI 가 아니므로 고정비 0(규칙의 3.5s 는 CLI 서브프로세스 몫).

| 호출 | 1단위인가 | 쪼갤 수 있나 | 목표 시도당 상한(가정) | 재시도 |
|---|---|---|---|---|
| `/tokenize` | 1단위 | - | 7.0 | 없음(규칙은 «첫 출력 전 실패만 1회» 허용, 호출 내부 재시도는 이번 단위에서 도입하지 않음) |
| 의미 묶음 chat | 입력 1~2단위·출력 예약 최대 약 8단위 환산 | 4단위 묶음 크기·출력 예약은 프로필 값(캡처, 변경 범위 미확인) | min(7×8, 70)=56.0 | 없음 |
| 번역·요약 chat | 위와 같음(v3 는 줄 단위 호출 = 이미 쪼개진 형태, 호출당 1~2단위) | v3 줄 단위가 쪼개기 | 호출 크기 비례(1~2단위: 7~14) | 없음 |
| 임베딩 POST | 배치 64×토큰: 입력 수~십수 단위 가능 | **배치 크기(`max_batch`)를 줄여 쪼갬** — 프로필 지문에서 제외된 노브지만 저장 위치·재등록 필요 여부 미확인 | 쪼갠 뒤 배치당 7~14, 쪼개기 불가면 min(7×단위, 70) | 없음 |
| 기억 추출 chat | 출력 예약 최대 약 8단위 환산 | 쪼개면 lineage 변경 = 기억 재처리(§2) → **이번 단위 제외** | min(7×8, 70)=56.0 | 없음(다음 pass 가 재시도) |
| HF 로드 | 파일 수 개 소형 | 미확인 | 라이브러리 값 확인 필요 | - |

- **호출 총 마감**: 시작 시각 + 상한(소켓 timeout 은 연산당이므로 **응답 read 루프에서 단조시계로 마감 확인**). 마감 초과 = `timeout` 취급, 기존 오류 코드·재시도 가능 표시 그대로.
- **pass 마감(윈도우 경계에서만 새 일 금지)**: pass 시작 시각 기준 `PASS_NEW_WORK_BUDGET`(잠정 120초, launchd 간격 300초 안에서 끝나게 한 임의값 — 계측 전 확정 안 함, 호출 상한 70초 천장과는 별개의 «새 윈도우 시작 금지 시계»)을 지나면 **다음 윈도우를 시작하지 않고** 기억 추출은 건너뛰고(다음 pass 로) 정상 종료. 진행 중 호출은 위 호출 총 마감(≤70)까지만 → pass 최악 ≈ 120+70 = 190초 < 300.
- **중도 종료(마감 정지가 아니라 kill) 때의 부분 쓰기 안전성 — 읽은 사실**:
  - 윈도우 단위 쓰기는 `BEGIN IMMEDIATE…COMMIT`(checker 정합 사실 write_units), 발행 claim 은 «processing claims are retryable after crashes»(`lifecycle.py:910-936`), core job 이 `running` 이면 `reclaim_stale_job`(리스 만료 뒤, 리스 ≥ max(5분, 호출 상한+30초): `store.py:119`, `pipeline.py:132-134`) 경로로 이어짐 → **윈도우 경계에서 멈추면 안전, 호출 중 kill 은 리스 만료까지(최소 5분) 같은 윈도우가 재개 안 됨**(코드 읽기 근거, 실행 검증 0).
  - **기억 추출은 다르다**: 호출 중 kill 되면 추출 상태가 `pending` 으로 남고, 다음 pass 는 «이미 pending 이라 재호출 안 함(`should_call=created`)» 으로 `provider_called=False·continuation_required=True` 만 반환(`memory.py:1196-1234`). 복구 함수 `recover_interrupted_memory_batches`(`memory.py:1457-1498`)는 **소비자 코드 어디서도 호출되지 않음**(grep 결과 정의 1건뿐). → 기억 쪽이 멈춘 채 쌓일 수 있는 상태가 **이번 단위의 미확인 위험**(운영 DB 의 `pending` 배치 수는 키 없이 확인 불가). 재개 전 확인 조건으로 §7 에 올림.
  - SIGTERM 핸들러·atexit 코드 0(checker grep). kill 시 SQLite/SQLCipher 롤백·WAL 복구 동작은 코드 밖(미확인) → 그래서 Q6 점검이 있다.

# 6. Q6 — DB quick_check 1회 게이트 (판정 2071)

**결론**: `_pass_child` 안에서 **consumer·projection 2종**을 PRAGMA quick_check 1회. profile-source 는 제외 권고(근거 아래), 두 안 병기 — 지시는 3종이었으므로 변경 사유를 명시한다.

| 항목 | 설계 |
|---|---|
| 어느 프로세스 | `_pass_child`: fd 1·2 를 `/dev/null` 로 돌린 뒤 `cli_main` 호출 **이전**(`_pass_child.py:75-84` 사이). 키는 이미 자식 stdin 에만 있고(`tick.py:386` 문서) 부모는 sqlcipher 를 import 하지 않으므로 새 키 노출 경로·import 를 만들지 않음. 설정 경로는 자식이 이미 읽는 `--config`(`RuntimeConfig.load`) |
| 몇 종 | **안 A(권고)**: consumer·projection 2종 — 이미 가진 키 `consumer_ledger`·`projection_db`(`runtime.py:433-434`)로 열림. **안 B**: profile-source 포함 3종 — 4번째 키 `PROFILE_SOURCE_KEY_ENV` 필요(`runtime.py:433-446`, 다른 키여야 함) → 틱 `NAMES` 3개 계약·`_pass_child` 프로토콜(`set(keys)==set(NAMES)`, `_pass_child.py:35`)·키 읽기 3→4(r16 의 키당 21.0 예산·팝업 영향) 변경 = 이번 단위에 변인 추가라 **비추천**. profile-source.db 는 196,608B·09-28 이후 불변(checker)·정상 pass 는 열지 않는 경로가 있음(`runtime.py:596-609`, 분기 조건 전문은 미확인). archive 폴더는 비어 있음(checker) → 점검 대상 파일 0 |
| 여는 방식 | `rag/db/connect.py` 의 `open_readonly`(`?mode=ro`, 키 적용) — 소비자 `open_ledger`(`ledger.py:307-325`)는 `journal_mode=DELETE` 설정·스키마 확인을 하므로 **쓰기 가능 경로이고 projection 을 rw 로 열고 닫으면 WAL 체크포인트가 본체를 바꿈** → 점검이 증거를 바꾸지 않도록 두 DB 모두 읽기 전용. 이전에 `diagnostics.py:181` 가 같은 `PRAGMA quick_check` 를 쓰는 선례(코드 `DATABASE_INTEGRITY_FAILED`·`DATABASE_INTEGRITY_UNREADABLE`) |
| 결과 취급 | 반환 행은 `== [("ok",)]` 비교만 하고 어떤 행도 출력·저장하지 않음 |
| 1회 규칙 | `log_dir/integrity-ok.json`(닫힌 스키마 `{"v":1,"ok":["consumer","projection"]}`, ≤128B, 0600)이 **없을 때만** 점검. 모두 ok 일 때 자식이 기록, 기록 실패는 다음 틱 재점검일 뿐 동작 불변. 다음 재개에서 다시 점검하려면 Master 가 마커를 옮김(재개 절차에 한 줄) |
| 결과 enum | DB 이름 `consumer`·`projection`(·`profile_source`) × 결과 `ok`·`not_ok`·`deadline`·`open_error` |
| 실패 시 | 하나라도 ok 가 아니면 **`cli_main` 호출 안 함 = pass 시작 0**. 프레임 `exit=1`, code: `not_ok`→`DATABASE_INTEGRITY_FAILED`, `deadline`·`open_error`→`DATABASE_INTEGRITY_UNAVAILABLE`(둘 다 `FRAME_CODES` 허용 목록에 추가 필요, `_result.py`), type 칸 = DB 이름 토큰. 부모는 기존 경로로 exit 40 `runtime_error` 줄을 씀. 이후 틱은 마커가 없으니 다시 점검(비용은 아래 «시간» 칸, 최악 21초) — R-5 의 «연속 3틱 즉시 중단 보고»에 그대로 포함 |
| 시간(규칙 12 적용 여부) | 로컬 파일 스캔이라 **규칙 12 의 «외부 호출»에 해당하지 않음 — 7초 룰 직접 적용 대상 아님**. 단 «무기한 대기 금지·크기 비례» 원칙은 적용: DB별 마감 `min(70, 7 × ceil(크기MiB / 16))`(크기 = 본체+WAL 바이트, `os.stat`) → consumer 10,473,472B → 7초, projection 13,221,888+4,054,112B ≈ 16.5MiB → 14초, 합계 최악 21초. 기준 16MiB 와 소요 모두 **실측 전 임의 가정** — quick_check 소요 실측 0. 첫 점검 소요(`ms`)를 기록해 값을 개정. 마감은 진행 핸들러(`set_progress_handler`) 또는 `interrupt()` — sqlcipher3 에서의 동작 미확인(구현 DA 항목) |
| 로그 | 부모 줄에 선택 최상위 필드 `integrity`(probe 와 별개 — probe `v:1` 스키마 불변): `{"v":1,"dbs":[{"db":이름,"out":결과,"ms":float 0~120,000}]}` ≤3항목, ≤512B. 자식→부모 전달은 프레임에 선택 키 `integrity`(`FRAME_KEYS` 확장, 부모가 같은 검증기로 재검증·실패 시 필드만 삭제 = probe 복구 사슬 ①정상→②검증→③크기→④최소→⑤필드 없는 기준 줄). 기존 필드·반환 코드·summary 불변. 합성 시험: 최종 줄에서 `integrity` 제거 후 기준 실행과 동일 |
| 점검이 보지 못하는 것 | 업무 상태(윈도우 `processing` 잔여, 기억 `pending` 배치, core job 리스) — quick_check 는 페이지·인덱스 구조 점검뿐. WAL 의 유효 프레임 수 미확인 |
| 실패 위험(과잉 정지) | WAL DB 를 읽기 전용으로 열 때 `-shm` 복구가 필요하면 `open_error` 가 날 수 있음(SQLite 버전·SQLCipher 동작 미확인) → 이 경우 이 틱은 정지(fail-closed), Master 가 읽기 전용 재확인 후 판단 |

# 7. Q5 — 다음 한 걸음과 재개 3회차 조건

**추천 = 계측(§4) + DB 점검 게이트(§6) 먼저. 규칙 12 상한 변경(§5)은 이번 재개에서 하지 않는다.**
근거: ①지금 모르는 것(느린가·멈췄나·몇 개째·어느 윈도우)을 §4 가 호출 단위로 기록하고, 상한부터 바꾸면 값 근거(실측 소요)가 없어 R-6(변인 하나)과 어긋남 ②§6 은 pass 시작 전 읽기 전용 게이트라 pass 시간 변인과 독립(서로 간섭 경로: 점검 소요 ≤21초가 틱 총 시간에 더해짐뿐) ③읽기 전용 추가 실측은 키·DB 열기가 필요해 op 호출·운영 DB 접촉이라 이 팀 규칙으로는 불가 → 같은 목적을 §6 이 재개 첫 틱에서 대신함.
**변인 정리**: 계측은 행위 불변, 게이트는 새 정지 경로(+최대 21초). 상한·pass 마감·쪼개기는 계측 자료를 본 뒤 별도 단위.

**R-1~R-5 는 r16 정오표 문구 그대로 유지하고, 아래만 추가·개정(Master 가 원문에 맞춰 정리)**:
- R-2 개정: 설치 대상 = tick.py·`_pass_child.py`·`_result.py`·`bridge.py` 의 계측/게이트 커밋 둘, 직전 설치본 백업·해시 검증 유지, 위임 범위(판정 2022) 안인지 설치 직전 1줄 기록.
- **재개 전 확인(신규)**: 기억 추출 `pending` 배치 수·윈도우 `processing` 잔여 — 운영 DB 열기가 필요하므로 이번엔 읽지 않고, **«미확인 위험 수용»을 R-3 위험 고지 한 줄에 포함**.
- R-4 개정: 고지에 ⓐ첫 pass 가 길어질 수 있음 ⓑ첫 틱에 DB 점검 최대 21초가 먼저 돎 ⓒ팝업: tick1 에서 오빠가 허용한 python3.13 접근이 3회차에도 유지되는지 **미확인**(재발 시 키 읽기 3키 중 일부 timeout 후보).
- R-5 개정: «연속 3틱» 계수에 **로그 줄이 안 남는 중도 종료 틱도 1틱으로 센다** + **관찰 상한 T**(잠정: pass 시작 5분 시 `pass-trace.jsonl` 마지막 줄 읽기로 진행 확인 보고, 15분 초과 시 정지 보고 — T 는 Master 대리 확정 가능) .
- **R-6 신설**: 한 번의 재개에서 계측·게이트 외 행위 변경 금지. 정지 시 읽기 전용으로 trace·점검 결과만 채집.
- 오빠 결정 지금 **0건**(자율 ON — T 값·마커 절차·2종/3종은 근거와 함께 대리). 다음 올라갈 건 **3회차 재개 승인 1건**(위험 수용 한 줄 포함).

# 8. 미확인 (유지)

운영 DB 안 프로필 값(타임아웃·max_tokens·max_batch)·윈도우당 실제 단위 수·v3 줄 호출 수·기억 `pending` 잔여·tick2 구간 부하·HF 로드 소요/타임아웃·`quick_check` 소요·sqlcipher3 의 진행 핸들러/ro WAL 복구 동작·`OpenerDirector.open` 래핑이 모든 호출 경로를 덮는지(요청 라이브러리 직접 사용 호출이 있는지)·SIGTERM 시 자식 최종 상태·`ps`/trace 의 호스트 부하 영향.

# 9. DA 소환 권고 — 예 (1회, 설계 r17 전체)

중점 4: ①계측이 정말 행위 불변인가(`OpenerDirector.open` 래핑·윈도우 훅·추적 실패 삼킴 범위) ②quick_check 게이트의 fail-closed 과잉 여부와 2종 vs 3종 판단 ③§5 환산(8단위·56초·120초 pass 시계)이 «가정»으로 정직하게 표기됐는지, 규칙 12 독해 ④기억 `pending` 고착 위험 서술이 코드 근거에 맞는지. 금지: 코드 수정·설치·재개 승인 판단은 이 심사 범위 밖.
