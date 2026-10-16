최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰 + 6순위 C13(KakaoBot 통합 보고서) published 칸 채움.
골의 어느 축인가: A03 — C12. 설계 r17 정정 정오표 DA 재심 REJECT 0/4/3/4(da-20261017-sol-pass-design-r17-r2.md) 2차 정정. 원문 `arch-20261017-pass-call-design-r17.md`·1차 정오표 `…-r17-errata.md` 의 해당 문장을 **명시 대체**한다. 코드 수정 0·시험 실행 0·op 0·운영 파일 접촉 0. 수치는 계획 예산/계산 예시이며 보장 상한이 아니다.

수용 유지(다시 열지 않음): B1 핵심(consumer 연결·식별)·M3·M6·m1·N 항목 · 1차 정오표 §2 의 «어댑터 함수 전체 래핑»·§3 의 «파일·예외 기본 계약»·§4~§7 의 나머지.

# 1. major 1 (M1) — `_post_json` 인자 위치 (1차 정오표 §2 표 첫 행 대체)

`_post_json(cfg, path, body_obj, …)`(`llm_enrichment.py:193`)에서 `path` 는 **두 번째 위치 인자**이다(첫 인자는 `cfg`). 호출 예: `_post_json(cfg, "/tokenize", …)`(`:226`). 대체 문장:

- `tok` 는 래퍼가 **바인딩된 `path` 값**으로 정한다: 위치 인자로 받았든(현재 호출 형태 = 두 번째) 키워드 `path=` 로 받았든, 원함수 서명에 따라 `path` 에 묶인 값이 `"/tokenize"` 와 같으면 true. 구현은 `inspect.signature(원함수).bind(*a, **k)` 로 `path` 를 얻고, 바인딩 실패(서명 변경 포함) 시 **추적 비활성화**(예외 아님, 업무는 그대로). `cfg`·본문 값은 읽지 않는다.
- 시험 설계(실행 보류): 위치 호출·키워드 호출 모두에서 `tok` 가 맞고, `cfg` 가 우연히 문자열 `"/tokenize"` 와 같은 합성 입력에서도 `path` 만 비교됨을 확인.

# 2. major 2 (M2) — trace 최초 생성 경로 (1차 정오표 §3 «초기화·회전» 행 대체)

«lstat 포함 어느 하나라도 실패하면 비활성화»를 아래로 바꾼다. 원본 부재는 정상이다.

| 단계 | 결과 | 처리 |
|---|---|---|
| `lstat(trace)` | **`FileNotFoundError`(ENOENT)** | **정상적인 최초 생성**: 회전 단계 건너뜀, `O_CREAT` 열기로 진행(추적 활성) |
| `lstat(trace)` | 그 밖의 `OSError` | 추적 비활성(업무 진행) |
| `lstat(trace)` 성공 | 심볼릭 링크이거나 정규 파일이 아님 | 추적 비활성(`replace` 하지 않음) |
| `lstat(trace)` 성공·정규 파일 | — | `os.replace(trace, trace.prev)`; 실패하면 추적 비활성. `.prev` 가 디렉터리 등으로 교체 불가한 경우도 여기 포함 |
| 열기 | `O_WRONLY\|O_APPEND\|O_CREAT\|O_NOFOLLOW\|O_NONBLOCK` + `fstat` 정규 파일·소유자·`st_nlink==1`·권한(1차 정오표 §3 그대로) | 실패하면 추적 비활성 |

- `lstat` 와 열기 사이의 경합은 열기의 `O_NOFOLLOW`·`fstat` 검사가 닫는다(경합으로 바뀐 경우 열기 단계 실패 = 비활성).
- **어떤 경우에도 업무 호출은 그대로 진행**(1차 정오표 그대로). 시험 설계(실행 보류): trace 없음 → 최초 배포에서 활성·`.prev` 없이 시작, trace 있음 → 회전, trace 가 링크·디렉터리 → 비활성, 업무 결과 동일.

# 3. major 3 (M4) — `running` 기록 실패에도 우회 불가한 계약 (1차 정오표 §5 «점검 여부»·«기록 시점»·«기록 방식» 행 대체)

반례(DA): 유효한 `clean` 을 읽어 점검 생략 → `running` 기록 실패 → pass 진행 → 강제 종료 → `clean` 이 남아 다음 틱도 생략. 대체 계약 = **안전한 `running` 기록 없이는 pass 를 시작하지 않는다.**

순서(자식 `_pass_child` 안, 점검 스레드 결정 이후):

1. `pass-state.json` 판독 → `clean`(스키마·`proj`·권한·크기·소유자 유효)이면 점검 생략, 아니면 점검 실행(결과가 ok 가 아니면 pass 시작 안 함 — 기존 계약).
2. **`running` 기록**: 같은 디렉터리에 임시 파일 작성(0600) → `os.replace(임시, pass-state.json)`. 성공 여부는 `replace` 반환으로 확인한다.
3. **2 가 어느 단계든 실패하면 pass(`cli_main`)를 시작하지 않는다**: 프레임 `exit=1`, code `PASS_STATE_UNAVAILABLE`(허용 코드 목록에 추가), type `pass_state`. 오래된 `clean` 이 남아 있어도 이 경로는 우회가 아니다 — 시작이 막히므로 «`running` 없이 실행되는 pass» 가 존재하지 않는다. 임시 파일 정리 실패는 무시.
4. `cli_main` 이 정상 반환·예외 종료한 직후 `clean` 기록(같은 방식). **`clean` 기록 실패 = 파일이 `running` 으로 남음 → 다음 틱 점검**(안전 방향).
5. 강제 종료·정전: `running` 이 남아 다음 틱이 점검한다.

- 정리: 기록 실패 시 «다음 틱도 점검» 문구를 삭제하고 «pass 시작 거부, 다음 틱에서 같은 순서로 재시도»로 바꾼다. 거부 틱도 R-5 의 «연속 3틱 즉시 중단 보고» 계수에 센다(로그에는 exit 40 줄이 남음).
- 위험 표기: 로그 디렉터리 쓰기 불능(디스크 가득 등)에서는 pass 가 시작되지 않는다 — 같은 디렉터리의 `tick.lock` 열기(`tick.py` `LOCK_FILE_UNSAFE`)와 틱 로그 쓰기도 영향을 받는 환경이라 추가 가용성 손실은 «임시 파일 작성 단계 하나» 범위로 본다(실측 0).
- 시험 설계(실행 보류): 유효 `clean` + 임시 파일 작성 실패 주입 / `replace` 실패 주입 → pass 미시작·코드 `PASS_STATE_UNAVAILABLE`, `clean` 기록 실패 주입 → 다음 틱 점검 실행, `running` 상태에서 강제 종료한 뒤 다음 틱 점검 실행.

# 4. major 4 (M5) — 호출 총마감 보장 범위 한정 (1차 정오표 §6 첫 항목 대체)

«시작부터 `D` 안에 반환 또는 `timeout` 예외»를 삭제한다(소켓 밖 대기와 충돌). 대체:

- **보장 범위 = 소켓 I/O 구간**: 연결·요청 송신·헤더 수신·본문 수신의 **각 블로킹 소켓 연산**에 `timeout = D − 현재 단조시계`(0 이하면 즉시 `timeout` 처리)를 다시 설정한다. 이 구간들의 합이 시작 시각 기준 `D` 를 넘지 않음(스케줄 지연 제외)을 구현·시험 인수 조건으로 한다.
- **호출 전체의 `D` 내 반환은 «미확정»**: 이름 조회·소켓 생성 전 처리·응답 파싱·검증·로컬 처리·인터프리터 스케줄 대기는 `D` 에 포함되지 않으며 이 계약이 제한하지 않는다. 연결 소켓이 생기기 전의 이름 조회 지연은 소켓 timeout·소켓 닫기로 끊을 수 없다.
- **조건부 메모**: 설정된 엔드포인트가 숫자 주소(예: 배포 템플릿 `127.0.0.1` 형태)이면 이름 조회 대기가 생기지 않을 가능성이 있으나, **운영 설정 값은 미확인**이므로 보장 근거로 쓰지 않는다. 후속 구현에서 «엔드포인트 호스트가 숫자 주소임»을 설정 검증으로 확인하면 이 한정을 줄일 수 있다는 후보만 적는다(이번 단위 적용 없음).
- 나머지(pass 최악 시간 미확정·120초 시계는 보장 아님·`120+70=190` 철회)는 1차 정오표 §6 그대로.

# 5. minor 1 (B1) — projection 예외 분류를 «단계»로 확정 (1차 정오표 §1 projection 행 대체)

core `open_readonly` 는 읽기 검증 실패(`connect.py:79` `_verify_readable`)와 engine 불일치(`:208`)에 **같은 `WrongKeyOrForeignDatabase`** 를 던지므로(`UnsupportedSchemaVersion` 은 별개 예외) 예외 종류·메시지로는 `open_error`/`identity_error` 를 구분할 수 없고, **원문 예외 메시지는 읽거나 출력하지 않는다.** 대체: projection 도 점검 모듈에서 **`open_readonly` 와 같은 순서의 단계로 직접 연결**하고 결과 enum 을 «어느 단계에서 실패했는가»로 정한다.

| 단계 | 내용(= `connect.py:197-209` 와 같은 순서) | 실패 시 enum |
|---|---|---|
| A. 연결·열기 | `sqlcipher3.connect(<uri>?mode=ro, uri=True, isolation_level=None)`·키 형식 검증·`PRAGMA key`·`temp_store=MEMORY`·`query_only=ON`·`busy_timeout`(§4 점검용 1,000ms)·`SELECT count(*) FROM sqlite_master`(읽기 검증)·`PRAGMA cipher_version` 비어 있지 않음 | `open_error` |
| B. 식별 | `SELECT value FROM db_meta WHERE key='engine'` 가 `connect.ENGINE_TAG` 와 같음 · `read_schema_version(con) == SCHEMA_VERSION` | `identity_error`(테이블 없음·행 없음·불일치·버전 불일치 전부) |
| C. 스캔 | `PRAGMA quick_check` 반환이 `[("ok",)]` | `not_ok` |

- consumer 도 같은 틀: A = 1차 정오표 §1 의 연결·읽기 검증, B = `meta.engine`·`user_version==4`, C = 스캔.
- 분류는 **단계 번호만** 사용한다(예외 클래스·메시지 비교·출력 0). 단계 안에서 마감(§4 점검 스레드)이 만료되면 `deadline`.
- 이 변경으로 projection 에 core `open_readonly` 를 호출하지 않는다 — 1차 정오표 §1 의 «함수 내부 검사» 칸은 위 단계 표로 대체. 상수(`ENGINE_TAG`·`SCHEMA_VERSION`·`read_schema_version`)는 core 모듈의 공개 이름을 읽기만 한다(`connect.py:42,206-209`; `ENGINE_TAG` 가 `__all__` 에 없다는 점은 구현 DA 확인 항목).
- 시험 설계(실행 보류): 잘못된 키 → `open_error`, 평문 파일 → `open_error`, 다른 engine 값 → `identity_error`, 스키마 버전 불일치 → `identity_error`, 정상 → `ok`; 모든 경우 출력에 예외 메시지 0.

# 6. minor 2 (M2) — 중단 표지 `x` 의 예산과 부분 쓰기 뒤 줄 경계 (1차 정오표 §3 «부분 쓰기»·«누락 표지»·«줄 크기» 행 보강)

- **중단 표지 예약 예산**: 일반 이벤트(`b`·`e`·`wb`·`we`)는 **줄 2,040개·파일 총 383KiB 까지만** 쓴다. 나머지(8줄·1KiB)는 `x` 전용 예약분이며 `x` 줄은 이 예약 안에서만 쓴다. `x` 는 줄당 ≤96바이트(필드: `v`·`t`·`rsn` 뿐)이고 pass 당 최대 4회까지 시도한다. 일반 이벤트가 예약 경계에 닿는 순간 `x`(`cap_lines`/`cap_bytes`)를 한 번 쓰고 이후 일반 이벤트는 쓰지 않는다(총량 384KiB·2,048줄 상한은 그대로).
- **부분 쓰기 뒤 줄 경계**: `os.write` 가 짧게 끝나거나 `OSError` 를 내면 파일 끝에 개행 없는 조각이 남을 수 있다. 이후 `x` 는 **항상 선행 개행 한 글자를 붙여 한 번의 `os.write`** 로 쓴다(`"\n" + x줄 + "\n"`) — 조각은 그 개행으로 끝나 독립 줄이 되고 `x` 줄은 온전히 남는다. 빈 줄·조각 줄은 판독 규약대로 버린다(개행 선행 바이트는 `x` 예약 크기 안에 포함).
- **표지를 남기지 못하는 경우의 판독 규약**: `x` 줄이 없다는 사실은 «완전한 기록»을 뜻하지 않는다. 다음이 하나라도 있으면 파일을 **«계측 누락 가능 — 원인 미확정»** 으로 읽는다: ①파일이 개행으로 끝나지 않음 ②스키마 불일치로 버려진 줄이 있음 ③`d` 필드 존재 ④`x` 줄 존재 ⑤파일 상한 근처(≥383KiB 또는 ≥2,040줄)에서 끝남. 모두 해당 없고 마지막 유효 줄이 짝 없는 `b` 일 때만 «종료 시점 진행 중 후보»(후보 단계, 확정 아님).
- 이 계약은 부분 줄 폐기·«짝 없는 `b` = 후보»(DA 수용)를 확대하지 않으며 **원인을 정하지 않는다.**

# 7. minor 3 (M7/F9) — HF 토크나이저 캐시 표현 (1차 정오표 §8 표 F9 행 대체)

`chunking.py:55` 는 `lru_cache(maxsize=8)` 이며 키는 `(model, revision, max_tokens)` 이다. 대체 문장: **«프로세스 안에서 캐시에 유지된 조합은 재사용되고, 캐시 miss 또는 eviction 이 있으면 같은 조합도 다시 로드될 수 있다.»** 입력 chunker(`pipeline.py:161`)와 번역 출력 chunker(`:68`)의 한도가 다르면 조합이 달라질 수 있다. 조합 수·eviction 발생 여부는 **미확인**이며 운영에서 eviction 을 관측했다는 주장은 하지 않는다. «조합별 최대 1회»·«pass 자식마다 조합별 최대 1회» 문장을 삭제한다.

# 8. 정정 위치 요약

| DA 지적 | 정정 |
|---|---|
| major 1 | §1 바인딩된 `path` 값만 비교(두 번째 인자), `inspect.signature` 바인딩 |
| major 2 | §2 ENOENT = 정상 최초 생성, 그 밖의 `lstat`·회전·열기 실패와 구분 |
| major 3 | §3 `running` 기록 실패 = pass 시작 거부(`PASS_STATE_UNAVAILABLE`), 기존 `clean` 우회 불가 |
| major 4 | §4 보장 범위 = 소켓 I/O, 호출 전체 `D` 내 반환 «미확정» |
| minor 1 | §5 projection 도 단계 A/B/C 직접 연결, 예외 종류·메시지 사용 0 |
| minor 2 | §6 `x` 예약 예산·선행 개행·판독 규약 |
| minor 3 | §7 `lru_cache(maxsize=8)` 한정 표현 |

DA 재심은 이 정정 범위(major 1~4·minor 1~3)로 한정해 달라고 권고한다. 미확인(유지): 운영 설정의 엔드포인트 형태·`ENGINE_TAG` 공개 여부·sqlcipher3 의 `interrupt`·진행 핸들러 동작·점검 결정 지연·로그 디렉터리 쓰기 불능 빈도.
