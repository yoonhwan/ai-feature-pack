# Nano item5 U1 결과 — launchd 5분 틱용 키 주입 래퍼 + plist 템플릿

- 세션: `ft-airag-nano-r1#0` · 모델: claude-sonnet-5-5[1m]
- 골의 어느 축인가: A03 — A02 트리 5순위(C12·C07) — 상시 서비스를 launchd 로 돌리기 위한 설계 빈칸(저장소 키 주입 래퍼) 구현. 등록·기동은 범위 밖.
- 커밋·push 안 함. launchd 등록·`launchctl`·`~/Library/LaunchAgents`·`~/.local/share/airag`(logs 포함) 쓰기·실제 `op`·운영 DB·운영 키·`runtime.json` 접촉 없음(테스트는 tmp 경로의 합성 키·가짜 `op` 스텁). 키 값 미출력.
- pytest (`feature-pack/rag-consumer`): `227 passed in 10.88s` (기준선 218 + 신규 9)

## 설계 선택
### 위치 — 이유
- 래퍼: `feature-pack/rag-consumer/src/airag_consumer/tick.py` (`python -m airag_consumer.tick`). 이유: ①설치되는 런타임 wheel 에 같이 실려 launchd 가 «설치된 런타임의 파이썬» 한 줄로 실행 가능 ②기존 `pythonpath=["src"]` 로 합성 fixture(`tests/test_runtime.py`)와 함께 바로 테스트 ③`cli.main` 을 같은 프로세스에서 호출해 키가 자식 argv 에 노출되지 않음.
- plist 템플릿: `feature-pack/rag-consumer/ops/com.airag.consumer.plist.template` (템플릿만. 설치·등록 안 함).
- 개인 설정 분리: 볼트·아이템 이름·토큰 경로는 저장소에 없다. `--credentials <로컬 설정 JSON>`(`token_file`·`references{키이름: op://…}`·선택 `op` 실행파일 경로)에서만 읽는다. 형식은 기존 `.fable-team/bin/tour/credentials.py` 와 호환(코드 대조) — 단 볼트 접두어 `op://develop/` 하드코딩은 가져오지 않고 `op://` 만 요구(설정 파일은 로컬 신뢰 파일).

### 동작
1. 인자: `--config`(필수)·`--credentials`·`--log-dir`(기본 `~/.local/share/airag/logs`).
2. 설정 파일 확인 → 로그 디렉터리 생성 → `tick.lock` 에 **비차단 flock** (겹침이면 키 로딩·런타임을 건드리지 않고 skipped).
3. 키 로딩: 환경에 이미 있는 키 우선(형식 검증, 있는 것은 `op` 호출 생략), 없는 것만 `op read <ref>` 를 3개 병렬로(자식 환경에는 기존 `AIRAG_*_KEY_HEX`·`OP_*` 제거 후 서비스 계정 토큰만 주입; 토큰·키는 argv 에 없음). 3개가 서로 달라야 함. 키는 `os.environ` 이 아니라 이 호출의 환경 복사본 dict 에만 채워 `cli.main(environ=…)` 로 전달.
4. 같은 프로세스에서 `cli.main(["--config", …, "run", "--once"])` — stdout/stderr 는 메모리 버퍼로 받아 **화이트리스트 수치만** 요약(소스 수·accepted·gap·coverage_complete·발행 attempted/succeeded·기억 개수/provider_called·아카이브 수·백업 due/created). 원문·기억 본문·경로·예외 메시지는 요약에 들어가지 않는다. 런타임 오류는 CLI 가 이미 정제한 `error.code` 만 전달.
5. stdout 에 JSON 1줄 + 날짜별 로그에 같은 줄. 자체 반복·sleep 없음(launchd 의 다음 간격이 재시도).

### 종료 코드표
| 코드 | status | 의미 |
|---|---|---|
| 0 | ok | 1패스 정상 |
| 10 | skipped | 이전 틱 실행 중(`PREVIOUS_TICK_RUNNING`) — 아무것도 하지 않음 |
| 20 | config_error | 인자·config 파일 없음(`CONFIG_FILE_UNAVAILABLE`)·credentials 설정 없음/손상(`CREDENTIAL_SETTINGS_UNAVAILABLE`/`_INVALID`) |
| 30 | key_error | `op` 없음/토큰 없음/읽기·형식 실패/기존 키 형식 오류/키 중복 |
| 40 | runtime_error | `run --once` 실패(코드만 기록: 예 `DATABASE_OPEN_OR_KEY_FAILED`) |
| 50 | internal_error | 예상 밖 예외(타입 이름만) |

### 로그 정책
`<log-dir>/tick-YYYYMMDD.log`(UTC 날짜) 에 틱당 JSON 1줄. 파일이 1,000,000바이트를 넘으면 `.log.1` 로 교체(하루 최대 2파일 = 크기 상한), 14일 지난 날짜 파일은 삭제. 로그 쓰기 실패는 틱 결과를 바꾸지 않고 stderr 에 `tick log_write_failed`. launchd 의 stdout/stderr 는 plist 가 `launchd.out.log`/`launchd.err.log` 로 보낸다(요약 1줄뿐).

### plist 템플릿
Label `com.airag.consumer` · `StartInterval 300` · `RunAtLoad` · `ProcessType Background` · PATH 에 homebrew 포함 · `KeepAlive` 없음 · 자리표시 `__PYTHON__`·`__CONFIG__`·`__CREDENTIALS__`·`__LOG_DIR__` 만. 키·op 참조 문자열 없음.

## 변경 파일:라인
- 신규 `feature-pack/rag-consumer/src/airag_consumer/tick.py` — `load_keys`·`append_log`·`_counts`·`main`·종료 코드 상수
- 신규 `feature-pack/rag-consumer/ops/com.airag.consumer.plist.template`
- 신규 `feature-pack/rag-consumer/tests/test_tick.py` (9 테스트)

## 테스트·Red
- `test_normal_tick_fills_keys_runs_once_and_leaks_nothing` (정상 1틱·op 3 호출·stdout/stderr/로그/토큰에 키 없음·실제 `os.environ` 무변경)
- `test_existing_environment_keys_win_and_op_is_not_called` · `test_only_missing_keys_are_read_from_op` (기존 env 우선·부족한 키만 조회)
- `test_overlapping_tick_skips_without_touching_keys_or_runtime` (flock 보유 중 → 10, op 미호출)
- `test_key_loading_failure_has_its_own_exit_code_and_leaks_nothing` (스텁이 stderr 로 키를 흘려도 30 + 출력에 없음)
- `test_missing_credentials_or_config_is_a_configuration_error` (설정 부재 → 20, 코드 확인)
- `test_runtime_failure_is_reported_by_code_only` (잘못된 키 → 40, 키 미노출)
- `test_log_rotation_caps_size_and_prunes_old_days`
- `test_plist_template_is_a_placeholder_only_five_minute_job` (placeholder 4개만·plistlib 파싱·300초·RunAtLoad·키/op 문자열 없음)
- Red: 구현 전 `ImportError: cannot import name 'tick'`(파일 수집 단계). 구현 후 plist 테스트가 템플릿의 XML 주석 안 `--once`(주석에 `--` 금지)를 `ExpatError: not well-formed` 로 잡아 주석 문구를 고침 → 전부 통과, `plutil -lint` 도 OK.
- 한계: 실제 `op`·실제 1Password·launchd 로드는 실행하지 않았다(합성 스텁 한정). 스텁이 `op read` 호출 규약(`$1=read`, `$2=ref`, 서비스 계정 토큰 환경변수)을 확인한다.

## 사용자 수동 1회 실행 방법 (사용자 터미널, 한 줄)
```
~/.local/share/airag/runtime/bin/python -m airag_consumer.tick --config ~/.local/share/airag/projects/ai-feature-pack/runtime.json --credentials <로컬 credentials 설정 JSON 경로> --log-dir ~/.local/share/airag/logs; echo "exit=$?"
```
- 출력은 JSON 1줄(`status`·`exit`·`summary`)과 `exit=` 값. `credentials` 설정은 기존 투어 설정 파일과 같은 형식(`token_file`·`references`)이면 그대로 쓸 수 있다(내용은 읽지 않았다).
- **선행조건**: 설치 런타임(`~/.local/share/airag/runtime`)은 비 editable 복사본이므로 `tick.py`(와 r1~r6 이후 코어)가 들어가도록 재설치가 먼저 필요하다. 이 1회 실행은 `runtime.json` 의 소스를 실제로 수집하고 `memory_enabled` 이면 `127.0.0.1:18703` 로 기억 추출 요청을 보내며(U4), 백업 시각이 되었으면 백업을 만들 수 있다. 로그 디렉터리·락 파일이 처음 생성된다(U6).

## 보강 (#1737) — 요약에 U4 관찰값 추가
- 코드로 확인한 사실: `provider_requests`·`elapsed_s` 는 병렬 경로(`memory.extract_memory_batches`, 투어용)에만 있다. 상시 틱이 쓰는 `run_once` 는 직렬 `extract_memories`(`runtime.py:1006` `_extract_memory(lifecycle)`, concurrency=1)이고 그 결과(`ExtractionResult.to_dict`)에는 그 두 키가 없다. 실제 키: `attempts`·`candidate_count`·`materialized_count`·`awaiting_confirmation_count`·`unverified_count`·`conflict_count`·`rejected_count`·`batch_message_count`·`provider_called`(bool) 등.
- 추가한 숫자 필드(화이트리스트, 값 없음): 수집 `committed_native_offset_total`·`pending_bytes_total`(소스별 합) / 기억 `memory_attempts`·`memory_candidate_count`·`memory_conflict_count`·`memory_rejected_count`·`memory_batch_message_count`(기존 `memory_materialized_count`·`memory_awaiting_confirmation_count`·`memory_unverified_count`·`memory_provider_called` 유지) / `pass_elapsed_s` = 틱이 `run --once` 전체를 직접 잰 시간(모델 요청 시간이 포함된 1패스 소요, 모델 단독 시간은 `run_once` 결과에 없어 분리하지 못함).
- 테스트: `test_first_pass_summary_carries_collection_progress_and_memory_observations` — 합성 프로젝트(기억 ON·합성 추출기)의 실제 `run_once` 출력 기준: 오프셋 합 = 소스 파일 크기, pending 0, 후보 2·시도 1·배치 메시지 1, 기억 본문·키가 출력에 없음. Red: `KeyError: 'committed_native_offset_total'`(기존 9개 테스트는 그대로 통과).
- pytest: `228 passed in 14.96s` (227 + 신규 1). 변경: `src/airag_consumer/tick.py`(`_counts`·`main`)·`tests/test_tick.py`. 커밋·push 없음.
