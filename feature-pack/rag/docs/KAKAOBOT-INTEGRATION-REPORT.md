# AIRAG × KakaoBot 통합 보고서 (초안 · 절 A·B·C·D)

- 수신: KakaoBot 개발자
- 상태: **작성 중(DRAFT)** — 절 A·B 작성, 절 C·D 는 서버 복구와 무관한 부분만 초안(published 수치 칸은 비워 둠). 이 문서는 완료 판정을 하지 않는다(판정은 사용자·DA).
- 기준 버전: git `fd708cf` 위(feature/rag-transplant), 패키지 `ai-feature-rag 0.1.0` · `ai-feature-rag-consumer 0.1.0`, Python `>=3.13,<3.14`.
- 표기 규칙: **[실행]** = 이 문서 작성 중 현재 HEAD 에서 실제로 돌려 확인한 것 · **[인용]** = PLAN.md·artifacts 에 기록된 과거 실행 근거를 그대로 옮긴 것(이번에 재실행하지 않음) · **미확인** = 근거를 찾지 못했거나 이번에 확인하지 못한 것.
- 값·키는 이 문서에 적지 않는다. 키는 항상 «전달 방법»만 적는다.

---

## 절 A. KakaoBot 사용법

### A.0 구성 한눈에
| 조각 | 패키지·진입점 | 역할 |
|---|---|---|
| core | `ai-feature-rag` → `ai-rag`·`krb-rag`(같은 진입점) | 암호화 SQLite(SQLCipher)에 문서를 넣고 검색·확장·원본 조회·백업. **명시적 요청만 처리**한다. 파일 감지·워처·폴링·스케줄은 없다. |
| consumer | `ai-feature-rag-consumer` → `ai-rag-consumer` | 대화(Codex rollout JSONL)를 수집해 윈도우·기억·아카이브·일일 백업까지 운영하는 외부 계층. 한 번 실행 = 한 패스(`run --once`). |
| tick | `python -m airag_consumer.tick` | launchd 가 5분마다 부르는 래퍼. 키를 채우고 consumer 패스를 자식 프로세스로 1회 실행한다. |

**책임 경계(P09-02 요구):** 파일 변경 감지·워처·주기 실행(스케줄)은 **소비 프로젝트(KakaoBot)의 책임**이다. core 는 호출받은 것만 처리한다. 백업 복제·키의 외부 보관/복구도 사용자 책임이다(백업에는 키가 들어가지 않는다 — DECISIONS.md 「백업 담당 확정」).

### A.1 설치
core (재현 근거 [인용]: `artifacts/p07-install-reproduction-20260913.json`):
```bash
uv build --wheel --out-dir <wheel-dir>                      # feature-pack/rag 에서
uv venv --python 3.13 <venv>
uv pip install --python <venv>/bin/python '<wheel-dir>/ai_feature_rag-0.1.0-py3-none-any.whl[documents]'
```
- `[documents]` extra(docling·easyocr)는 PDF/DOCX/XLSX/HWP 계열·OCR 입력에 필요하다. 텍스트·대화만 쓰면 extra 없이 `ai_feature_rag-0.1.0-...whl` 만 설치한다(이 조합의 별도 설치 검증은 **미확인**).
- 네이티브 의존성: `sqlcipher3==0.6.2`, `sqlite-vec>=0.1.9`(`pyproject.toml`). 독립 설치 후 두 진입점 13개 명령을 통과한 기록 [인용]: `artifacts/p07-independent-install-final-20260913.json`.
- 현재 HEAD 의 `feature-pack/rag/.venv` 에는 `ai-rag`·`krb-rag` 가 있고 `ai-rag-consumer` 진입점은 **없다**[실행: `ls .venv/bin`]. consumer 는 `PYTHONPATH=feature-pack/rag-consumer/src` 로 실행해 확인했다.
- consumer wheel 의 독립 설치·재현 명령 기록: **미확인**(consumer 는 `ai-feature-rag==0.1.0` 에 의존; tick/launchd 는 설치된 consumer 런타임의 python 을 요구 — `ops/com.airag.consumer.plist.template` 주석).

### A.2 키 전달
| 대상 | 방법 | 비고 |
|---|---|---|
| core CLI | `--key-fd N` — 이미 열린 fd 에서 **정확히 32 raw bytes** 를 읽는다. argv·환경·로그에 키를 두지 않는다. | `keys.py`. macOS Keychain 제공자는 구현되어 있지 않다(`KeychainUnavailable`). 틀린 키 = `KEY_OR_DB_VERIFICATION_FAILED`, 종료코드 4 [실행]. |
| consumer / tick | 환경변수 3개 `AIRAG_CONSUMER_KEY_HEX`·`AIRAG_PROJECTION_KEY_HEX`·`AIRAG_ARCHIVE_KEY_HEX` (각 64 hex, **서로 달라야 함**) | 하나라도 없거나 형식이 틀리면 저장소를 만들거나 열기 전에 거부한다. 자동 생성·폴백 없음. |
| tick 의 키 채우기 | 환경에 이미 있으면 그대로 사용, 없는 것만 `--credentials` 설정 파일의 `op://` 참조로 1Password `op read` 에서 가져온다 | 설정 파일 필드: `token_file`(서비스 계정 토큰 파일)·`references`(변수명→`op://…`)·선택 `op`. 키는 자식 프로세스에 **stdin 으로만** 전달되고 argv·자식 env 에는 없다(`tick.py`·`_pass_child.py`). |
| 최초 부트스트랩 | `AIRAG_PROFILE_SOURCE_KEY_HEX` (프로필 원본 DB 키) | projection/consumer DB 가 이미 있으면 필요 없다(`runtime.py`). |
| reference 검색 | runtime.json `reference.source_key_env` 가 가리키는 변수 | **`search` 에서만** 필요하다. 변수가 없거나 비어 있으면 객체 생성은 되고 `search` 가 `MISSING_OR_INVALID_REFERENCE_SOURCE_KEY` 로 거부한다(상시 틱에는 불필요). 값이 있는데 형식이 틀리거나 다른 키와 같으면 생성 단계에서 거부. |

### A.3 모델·profile 구성
`ai-rag manage profile --db <db> --config <profile.json>` 는 임베딩(필수)·LLM(선택)·normalizer(선택) 설정 JSON 을 받아 **불변 처리 프로필**을 등록하고 `profile_key`·`space_id` 를 돌려준다[실행 — 네트워크 없이 등록 성공 확인].
- 형태(`artifacts/operational-profile-20260913.json` 의 키 구조): `embedding{provider, endpoint, model, revision, dimension, tokenizer_revision, max_tokens, timeout_s}` · `llm{provider, endpoint, model, weights_revision, context_length, timeout_s}`.
- add/update/search/reindex/retry 는 **명시적 `--profile-key`** 를 받는다. 모델·리비전·차원·전처리가 바뀌면 새 프로필 = 새 공간으로 분리된다(P03-06·`test_profiles.py` [인용]).
- 등록은 외부 서버 접속 없이 성공하지만 add/search 는 임베딩 서버가 필요하다 — 현재 임베딩 서버(`127.0.0.1:18712` 계열) 도달 상태는 절 C 에서 다룬다.

### A.4 호출 지점 (core CLI)
모든 명령은 `--db <path> --key-fd N` 을 받고 JSON 한 개를 stdout 에 쓴다. `ai-rag --help` [실행]: `init, manage, add, update, delete, fetch, search, expand`.

| 목적 | 명령 (요지) |
|---|---|
| DB 생성 | `ai-rag init <db> --key-fd N` (schema_version 5) |
| 프로필 등록 | `ai-rag manage profile --db <db> --config <json>` |
| 추가 | `ai-rag add --db <db> --collection C --source-key K --profile-key P (--text T \| --content-file F \| --batch J) [--request-id R]` |
| 갱신 | `ai-rag update … --expected-revision <revision_token> [--force-reprocess]` |
| 삭제(논리) / 복구 | `ai-rag delete --db … --request-id R --collection C --source-key K --expected-revision T` / `ai-rag manage restore …(같은 인자)` |
| 검색 | `ai-rag search --db … --collection C --query Q --profile-key P [--top-k N] [--expand …]` |
| 확장 | `ai-rag expand --db … --manifest-id M [--max-depth/--max-chunks/--max-tokens/--max-bytes/--max-edges …]` |
| 조회 | `ai-rag fetch {original,chunk,source,manifest,expansion} …` (원본은 `--include-bytes`) |
| 운영 | `ai-rag manage {doctor,verify,status,list,show,profile,retry,reindex,backup,restore-backup,restore}` |

consumer(`ai-rag-consumer --config <runtime.json> <command>`): `init`·`run [--once] [--task-completed] [--save] [--allow-gaps]`·`status`·`search <q> [--limit]`·`archive-search <q>`·`backup`·`verify <backup_id>`·`memory-candidates --state S`·`memory-confirm|reject|verify <candidate_id>` [실행: `--help` 대조].
- **호출 책임:** 새 대화/문서가 생겼을 때 호출하는 쪽은 KakaoBot 이다. consumer 는 runtime.json 에 **명시 등록된** 소스 파일(`path`·`session_id`·`source_id`)만 읽는다. 자동 디렉터리 탐색은 없다.

### A.5 오류·재시도 계약
응답 envelope [실행 확인]: `{"schema_version":1,"request_id":…,"ok":true|false,"command":…,"data":…,"error":null|{"code","message","retryable"}}`.
- 멱등: 같은 `request_id` 로 다시 보내면 **저장된 응답을 그대로 재생**한다(외부 모델 호출 0·추가 행 0 — T07 근거 [인용] PLAN.md P-08 서두). 새 요청이면 새 `request_id` 를 쓴다.
- 갱신 충돌: 오래된 revision 토큰은 `CONFLICT_STALE_REVISION`(`retryable:true`). 현재 `revision_token` 을 다시 읽은 뒤 새 요청으로 재시도한다.
- `retryable:true` 로 선언된 코드(소스 확인): `CONFLICT_STALE_REVISION` · `LEASE_NOT_EXPIRED`(이전 시도의 lease 가 아직 유효 — 만료 후 재시도) · `IN_PROGRESS`(같은 소스의 다른 job 이 활성 — 그 job 이 끝난 뒤 재시도) · `DB_BUSY`(락 경합). 그 밖의 `ApiError`(`NOT_FOUND`·`VALIDATION_ERROR`·`ALREADY_DELETED`·`INVALID_JOB_STATE`·`STALE_CLAIM_FENCED`·`BACKUP_*`·`DESTINATION_EXISTS`·`INVALID_BACKUP_PATH`)는 소스에서 `retryable:false` 로 선언돼 있다(`PROCESSING_FAILED` 의 retryable 값은 호출 지점마다 달라 **미확인** — 응답의 `error.retryable` 을 따를 것).
- job 재처리: 실패/대기 job 은 `ai-rag manage retry --db … --job-id J --request-id R [--profile-key P]`. 원래 실패 응답은 바뀌지 않고 새 job 이 생긴다(P06-03 [인용]). 프로필 전환 재색인은 `manage reindex`.
- 종료코드 표: 틀린 키 = 4 [실행]. 그 밖 코드 → **미확인**(코드 번호표는 문서화돼 있지 않음 — `error.code` 를 기준으로 분기할 것).
- consumer 틱 종료코드(소스 `tick.py`): `0` ok · `10` skipped(이전 틱 실행 중) · `20` config 오류 · `30` 키 오류 · `40` runtime 오류 · `50` 내부 오류. 출력은 값 없는 JSON 한 줄(`status`·`exit`·`code`·`type`·`summary`)이고 같은 줄이 `--log-dir/tick-YYYYMMDD.log` 에 남는다. 재시도는 launchd 의 다음 주기가 한다(틱은 루프·sleep 이 없다).

### A.6 백업 계약
- core: `ai-rag manage backup --db <db> --output <new-path> [--destination-key-fd N]` — 일관된 SQLCipher 스냅샷을 **새 경로에** 0600 으로 공개한다(기존 파일 덮어쓰기·symlink 거부). `manage restore-backup --db <new-db> --backup <path>` 로 새 DB 에 복원, `manage verify <db>` 로 재검증. [실행: init→profile→backup→restore-backup→verify 모두 ok=true, 틀린 키는 거부]
- consumer 일일 백업(DECISIONS.md·`operations.py`): 매일 **Asia/Seoul 03:00** 슬롯, 놓치면 다음 패스에 현재 상태 1회 보충. 기본 목적지 `~/.local/share/airag/backups/<project-id>/`. 소비자 원장·발행 DB·아카이브를 세트로 만들고 격리 임시 복원으로 DB 무결성·연결을 검증한다. 새 세트 검증 성공 뒤에만 30일 초과 AIRAG 소유 백업을 정리한다. 키는 백업에 포함되지 않는다. `ai-rag-consumer backup` 은 강제 1회, `verify <backup_id>` 는 검증.
- **일일 슬롯이 실제 launchd 환경에서 자동으로 만들어졌는지**는 아직 관찰 전이다(절 C).
- 외부 복제·키 보관은 소비자(사용자) 책임.

### A.7 실행 예제
**현재 HEAD 에서 실제로 실행해 확인한 예제** (임시 디렉터리·임의 키; 네트워크 불필요):
```bash
AI=feature-pack/rag/.venv/bin/ai-rag
# 키 32바이트를 파일에서 fd 3 으로 전달 (argv·env 에 키 없음)
bash -c "$AI init db.sqlite --key-fd 3" 3< key.bin                                   # → ok:true, schema_version:5
bash -c "$AI manage profile --db db.sqlite --config profile.json --key-fd 3" 3< key.bin   # → data.profile_key
bash -c "$AI manage status --db db.sqlite --key-fd 3" 3< key.bin                      # → healthy:true, provider_connectivity:not_checked
bash -c "$AI manage doctor --db db.sqlite --key-fd 3" 3< key.bin
bash -c "$AI manage verify db.sqlite --key-fd 3" 3< key.bin
bash -c "$AI manage backup --db db.sqlite --output backup1.sqlite --key-fd 3" 3< key.bin
bash -c "$AI manage restore-backup --db restored.sqlite --backup backup1.sqlite --key-fd 3" 3< key.bin
bash -c "$AI manage verify restored.sqlite --key-fd 3" 3< key.bin
```
**add/search 예제** — 형태는 `scripts/verify_installed_consumer.py`(독립 설치 검증기)에서 가져왔다:
```bash
ai-rag add    --db D --collection installed --source-key library --text "…" --profile-key P --request-id add-library --key-fd N
ai-rag search --db D --collection installed --query "…" --profile-key P --key-fd N        # 결과: data.results[].source_key, manifest_id
ai-rag fetch original --db D --collection installed --source-key library --include-bytes --key-fd N
ai-rag manage reindex --db D --collection installed --source-key library --expected-revision <revision_token> --profile-key P --request-id reindex-library --key-fd N
```
이 add/search/fetch/reindex 예제는 임베딩·LLM 서버가 필요해 **이번 HEAD 에서는 실행하지 못했다**(미확인). 과거 통과 기록 [인용]: `artifacts/p07-independent-install-final-20260913.json`(2026-09-13, 13개 CLI 명령).

consumer 최소 `runtime.json`(필수 키, `runtime.py`): `schema_version:1`, `project_root`, `owner_id`, `tenant_id`, `project_id`, `consumer_db`, `projection_db`, `archive_root`, `backup_root`, `profile_source_db`, `profile_key`, `collection`, `sources:[{path, session_id, source_id}]`. 선택: `token_mode`·`allow_gaps`·`memory_enabled`·`memory_endpoint`·`memory_model`·`poll_seconds`·`reference{source_db, source_key_env, source_allowlist, snapshot_root, …}`. 모든 경로는 절대 경로이고 출력 경로는 project_root 안(백업 루트는 관리 경로 허용)이어야 하며 서로 겹치면 거부된다.
launchd: `feature-pack/rag-consumer/ops/com.airag.consumer.plist.template` — `__PYTHON__ -m airag_consumer.tick --config __CONFIG__ --credentials __CREDENTIALS__ --log-dir __LOG_DIR__`, `StartInterval 300`, `RunAtLoad`. 플레이스홀더를 채워 `~/Library/LaunchAgents/` 에 두고 직접 로드한다(저장소는 템플릿만 보관).

---

## 절 B. 승인 요구 ↔ 증거 추적표

읽는 법: «기록»은 PLAN.md 체크박스 상태(체크는 PLAN.md 가 적은 상태일 뿐 이 문서의 판정이 아님). «근거»는 [인용]한 산출물 또는 [실행] 한 것. fixture·합성 자료 통과와 실제 운영 완료는 열을 나눠 적었다. 이 문서는 P01~P07 을 **재실행하지 않았다**(core 회귀·실제 모델 회귀는 이번에 돌리지 않음) — 아래 [실행] 은 절 A 의 core CLI 스모크와 consumer 회귀뿐이다.

consumer 회귀 [실행, 이 브랜치 작업 중 마지막 전체 실행]: `364 passed`(`feature-pack/rag-consumer`, `../rag/.venv/bin/python -m pytest tests -q -p no:cacheprovider`).

### B.1 원래 범위 P01~P08

| 요구 | 기록 | 대응 코드·명령 | 근거 | 미완·한계 |
|---|---|---|---|---|
| P01-01 설치·SQLCipher/FTS5/vec0 | [x] 2026-09-09 | `connect.py`·`ai-rag init` | [인용] `p01-encrypted-install.json` · [실행] init/verify ok | — |
| P01-02 키 재개방·오키 거부·키 비노출 | [x] 2026-09-09 | `keys.py`·`--key-fd` | [인용] `test_connect.py`·`test_encryption_opacity.py` · [실행] 틀린 키 거부(종료 4) | Keychain 제공자 미구현 |
| P02-01 소스 신원·불변 리비전·마이그레이션 | [x] | `store.py` | [인용] `p02-storage-contract.json`·`test_store.py`·`test_migration.py` | — |
| P02-02 CAS·멱등·stage/publish/fail | [x] | `store.py`·`pipeline.py` | [인용] 같은 파일 | — |
| P02-03 공통 envelope·단건/배치·원본 조회 | [x] | `api.py`·`cli/main.py` | [인용] `test_api.py`·`test_cli_p02.py` · [실행] envelope 형태 확인 | — |
| P03-01 정규화·청킹 | [x] 2026-09-10 | `normalize.py`·`chunking.py` | [인용] `test_normalize.py`·`test_chunking.py` | — |
| P03-02 불변 프로필·공간 격리 | [x] | `profiles.py`·`embeddings.py` | [인용] `test_profiles.py` 등 · [실행] profile 등록 ok | — |
| P03-03 실제 GPU LLM 전처리→발행 | [x] | `llm_enrichment.py`·`pipeline.py` | [인용] `p03-live-gpu-verification.json`(작은 합성 한국어 자료) | 대규모 품질 판정 아님 |
| P03-04 BM25+cosine RRF·동일 스냅숏 | [x] | `search.py` | [인용] `test_search.py` | — |
| P03-05 CLI 등록/수정/검색/조회/manifest 재현 | [x] | `cli/main.py` | [인용] 실제 GPU CLI 15개 명령 | — |
| P03-06 운영 모델 식별 | [x] 2026-09-13 | profile 에 revision 기록 | [인용] `p03-operational-model-identity-20260913.json` | GPU 메모리 attestation 아님(파일/서빙 경로 식별) |
| P04-01~09 문서·이미지 어댑터 | [x] 전부 2026-09-10 | `document_adapters.py`·`image_adapters.py`·`HwpBridge.java` | [인용] `p04-completion.json` | 보호/배포용 HWP·렌더 좌표 미지원, 수식 재계산 없음, 강제 종료 시 임시 파일 잔존 가능 |
| P05-01~05 청크 연결·확장 | [x] 2026-09-10 | `relations.py`·`expansion.py`·`search --expand`·`expand` | [인용] `p05-completion.json` | — |
| P06-01~02 add/update/delete/restore·claim 복구 | [x] | `processing.py`·`api.py` | [인용] `test_cli_processing.py`·`test_api_processing.py` | — |
| P06-03 retry | [x] 2026-09-11 | `manage retry` | [인용] `test_retry_contract.py` | 실제 GPU 재실행은 그 검증에 불포함 |
| P06-04 reindex | [x] 2026-09-11 | `manage reindex` | [인용] `test_reindex_contract.py` | — |
| P06-05 doctor/verify | [x] 2026-09-13 | `diagnostics.py`·`manage doctor/verify/status` | [인용] `test_operations_contract.py` · [실행] doctor·verify·status ok | 외부 연결은 검사하지 않음(`provider_connectivity: not_checked`) |
| P06-06 암호화 백업·복원 | [x] 2026-09-13 | `backups.py`·`manage backup/restore-backup` | [인용] `test_backup_contract.py` · [실행] 백업→복원→verify ok | — |
| P06-07 소비자 트리거 경계 | [x] 2026-09-13 | `examples/explicit_consumer.py` | [인용] `test_consumer_contract.py` | core 에 워처·폴링 없음(의도) |
| P07-01~03 합성 실행·독립 설치·전체 형식 | [x] 2026-09-10~13 | `scripts/verify_installed_consumer.py` | [인용] `p07-independent-install-final-20260913.json`·`p07-lifecycle-final-20260913.xml` | 작은 합성 자료·실제 모델은 당시 시점 |
| P07-04 의미 품질 | [x] 2026-09-13 | `scripts/evaluate_acceptance.py` | [인용] `p07-quality-final-review-20260913.json`(12문서·24질의) | 소규모 합성 코퍼스 — 일반 품질 보장 아님 |
| P07-05 규모·지연 | [x] 2026-09-13 | — | [인용] `p07-scale-20260913.json`(1000문서·5000청크) | 합성 벡터 로컬 측정 — 외부 모델 지연·대규모 보장 아님 |
| P07-06 장애·재시작 | [x] 2026-09-13 | `tests/test_fault_recovery.py` | [인용] 9사례 | — |
| P07-07 회귀 재현 | [x] 2026-09-13 | — | [인용] `p07-completion-20260913.json` | 이후 변경(2026-09-27~10-02)은 별도 회귀 로그 `artifacts/regression-20261001-*.log` |
| P08-01 투어 시나리오 | [x] 2026-09-21 | `artifacts/full-tour-guide.md` | [인용] PLAN.md | — |
| P08-02 사용자와 실제 투어 | [ ] | — | 투어 카탈로그 12건 사용자 수용 · 투어 14 수용(2026-10-01) [인용: `.fable-team/bin/tour/catalog.json`·A02 작업 트리] | **투어 3건 미수용**(11-load-repro·12-load·13-multi-load) · 확인대기 51·검증대기 25 사용자 보류 — 사용자 범위 결정(HELM #2063) 기록 대상 |
| P08-03 피드백 반영·재확인 | [ ] | — | 위와 같음 | 범위 결정은 사용자가 기록했으나 PLAN.md 체크는 미갱신 |

### B.2 자료·대화 확장 P08A (구현 위치 `feature-pack/rag-consumer/`)

| 요구 | 기록 | 대응 코드·명령 | fixture·합성 근거 | 실제 운영 근거 | 미완·한계 |
|---|---|---|---|---|---|
| P08A-01 사건·권한·보존 계약 | [ ] | `events.py`·`redaction.py`·D-014 | [인용] `p08a01-contract.json`·DA PASS | 허용 경로 17개 source+현재 세션 고정(사용자 선택) | 운영 정책·인수 시험 남음(PLAN 문구) |
| P08A-02 자료 변경 consumer(wiki/DB/문서 이벤트) | [ ] | — | 해당 구현 증거 **미확인** | 없음 | 실제 wiki/DB 서비스 미선정이면 fixture 와 실연동을 분리 표기해야 함(PLAN 문구) |
| P08A-03 대화 JSONL·윈도우 문서 | [ ] | `jsonl.py`·`ledger.py`·`collector.py`·`lifecycle.py` | [인용] `p08a03-input-adapter-verification.json`·`p08a03-ledger-verification.json`(122 passed) · [실행] consumer 회귀 364 passed | 실제 Codex rollout 수집: 선택 세션 고정 prefix 28,156,963B 로 442건 수집(2026-09-28) · 운영 launchd 틱 수집(2026-10-02) | `AMBIGUOUS_INJECTED_BLOCK` 감사 gap 1건 → `coverage_complete=false` · 소스는 계속 자라는 세션 |
| P08A-04 히스토리 검색·N개 활성 창 | [ ] | `bridge.py`·`runtime.search` | [인용] `final-integration-result.json`(검색창 28·활성 4) | 실제 통합 질의: 대화 5건+투어 17출처/11그룹 별도 순위 [인용] | 운영 환경 published(발행) 결과는 **절 C 에서 갱신 예정** |
| P08A-05 기억·트러블슈팅 | [ ] | `memory.py` | [인용] 기억 337개·118 추출 완료 | memory 서버(18703) 도달 여부 **미확인** | 사용자 확인·해결 검증 필요 후보는 자동 승인하지 않음 |
| P08A-06 아카이브·퇴거·재참조 | [ ] | `archive.py` | [인용] `restore_c15`(89일 백업→91일 복원, 비부활) | 운영 `archives/` 비어 있음(90일 미만) | 영구 삭제·자동 purge 없음 |
| P08A-07 통합 장애·권한·성능 | [ ] | `tests/` | [인용] 오프라인 691 passed·1 skipped(2026-09-28) | 성능·규모 보장 아님(`limits`) | — |
| P08A-08 실제 연결·사용자 시연 | [ ] | — | — | 투어 14 수용 · 운영 launchd 틱 3회 exit 0 | 사용자 확인·DA 최종 대조 남음 |
| P08A-09 90일 만료·파일 아카이브 | [ ] | `run_once`(`_archive_pending`) | [인용] 가상 시간 89/91일 시험 | 운영 만료 대상 0 | — |
| P08A-10 일일 백업·30일 보관 | [ ] | `operations.py`·`runtime._backup` | [인용] DA r1~r3 보강 PASS(2026-10-01) | 운영 백업 2세트(투어 07·14) · 03:00 슬롯 자동 생성 **관찰 전** | 외부 복제·키 보관은 사용자 책임 |

### B.3 프로젝트 지식 확장 P08B

| 요구 | 기록 | 근거 |
|---|---|---|
| P08B-01~06 (저장소 계약·변경 consumer·구조 청킹·Serena/LSP·통합 검증·독립 설치/실제 시연) | 전부 [ ] — 착수 증거 **미확인** | PLAN.md 「P-08B … 이번 범위는 기획 등록」 · 후속 범위로 유지됨 |

### B.4 phase 8·9 요구(acceptance-gates)와 이 표의 대응
- phase 8 `tour`: mixed_source_demo·inspect_originals·expand_connections·live_update·delete_restore·user_review — 항목별 «달성» 기록과 투어 단계의 **매핑표는 없다**(B.1 의 P08-02·03 행이 가장 가까운 기록).
- phase 9 `completion`: approved_requirements_traceability(이 절 B) · no_unreported_incomplete_capabilities(절 D, 작성 예정) · user_tour_done · final_kakaobot_integration_report(이 문서).

### B.5 이 절에서 확인하지 못한 것
- PLAN.md 가 적은 «[x] 완료»의 재실행: 이번에 하지 않음(core 회귀·실제 모델 회귀 미실행).
- P08A-02 구현 증거, memory 서버 도달 상태, consumer wheel 독립 설치 재현, core 종료코드 번호표.

---

## 절 C. 운영 상태

> 표기: 시각은 KST. 틱 로그(`~/.local/share/airag/logs/tick-YYYYMMDD.log`)는 UTC 로 기록되므로 +9h 로 옮겼다. **[실행]** = 이 절 작성 중 로컬에서 읽어 확인 · **[인용]** = 지시 원장·인계 문서의 기록 · **근거 미확인** = 파일 근거를 찾지 못함. 이 절은 상태 기록이며 완료·판정 문구를 쓰지 않는다. 값·키는 적지 않는다.

### C.1 launchd 등록 — `com.airag.consumer`
- 등록: 2026-10-02 15:23 KST. plist 수정 시각 15:22:54 · `StartInterval` 300초(5분) **[실행]**. 자격 파일 `~/.config/airag/credential-source.json` 은 권한 600 **[실행]** · «0600 복사» 경위는 **[인용]**(인계 문서).
- 현재 상태: 15:54 KST 에 HELM 이 bootout 함 → 지금 launchd 에 서비스 없음(`launchctl print` 가 «Could not find service») **[실행]**.

### C.2 틱 결과 (등록 이후)
| 시각(KST) | 상태·exit | pass 소요 | accepted | published 시도/성공 |
|---|---|---|---|---|
| 15:23 (첫 틱) | ok · 0 | 122.1s | 818 | 14 / **서버 복구 뒤 기록** |
| 15:30 | ok · 0 | 42.8s | 818 | 14 / **서버 복구 뒤 기록** |
| 15:36 | ok · 0 | 49.8s | 818 | 14 / **서버 복구 뒤 기록** |
| 15:42 | key_error · 30 (`OP_READ_UNAVAILABLE`) | — | — | — |
| 15:47 | ok · 0 | 24.6s | 818 | 14 / **서버 복구 뒤 기록** |
| 15:53 | ok · 0 | 20.4s | 818 | 14 / **서버 복구 뒤 기록** |

- 위 표는 로그 줄 그대로다 **[실행]**. 등록 이후 줄은 6개이고 그중 1개(15:42)가 exit 30 `OP_READ_UNAVAILABLE` 이다. 앞서 Master 가 3틱까지만 관찰하고 보고했고(정지 신호 해당 없음 판정), «6틱 exit 0» 이라는 인계 문서 문구는 로그와 다르다 — **Master 확인: 로그가 맞다**(2026-10-02 20:1x 로그 직접 재독). exit 30 은 한 번이었고 다음 틱(15:47)은 ok 로 회복했다. 원인은 이 문서에서 판정하지 않는다.
- 첫 틱: 소스 46,457,618 B 전량 소화 **[인용]**. `launchd.err.log` 0 B **[실행]**. 로그 줄에 64자리 16진 문자열 0건 **[인용]**(이 절에서 재확인하지 않음).
- 등록 이전 시각(15:12)에 ok 틱 줄이 1개(accepted 746 · `backup_created` true · 128.5s) 있다 **[실행]**. 인계 문서의 «재수동 3회(HELM 대행)» 와 같은 것으로 보이나 로그만으로는 호출 주체 **근거 미확인**.

### C.3 15:54 bootout 경위 [인용]
- published 가 성공하지 못한 원인으로 확정된 것은 임베딩 서버(127.0.0.1:18712) 도달 불가: 실패 창 14개가 `PROVIDER_UNREACHABLE`, 재시도 대기 작업 52, 다른 코드 0(architect 판정 `18d72ec`, 발주 #2061).
- 사용자가 서버를 직접 기동하기로 했고, 그 사이 서비스를 내렸다. published 수치는 해결 뒤 보고한다는 사용자 결정에 따라 위 표의 칸을 비워 두었다.

### C.4 백업과 재설치
- 런타임 백업 디렉터리: `runtime.bak-20261002-1522` · `runtime.bak-20261002-1755` (그 전 `runtime.bak-20261001-1416` 도 존재) **[실행]**.
- 설정 파일 백업: `runtime.json.bak-pre-u2-20261002-1522` · `runtime.json.bak-pre-reinstall-20261002-1755` (그 전 `runtime.json.bak-20261001-184932` 도 존재) **[실행]**.
- 17:55 재설치: 소스 HEAD `87a1225` 기준. 설치된 모듈(`airag_consumer` 19 + `airag` 27 = 46개 `.py`)이 HEAD 소스와 바이트 단위로 같음을 `diff -rq` 로 확인 **[실행]**. HEAD `87a1225` 는 문서 커밋이라 소스는 `63ed629` 와 같다 **[실행]**.
- 재설치(HEAD 87a1225 clean 사본 빌드, 2026-10-02 17:55) 휠 sha256 — consumer `c99bcea3141576623171073f6ce6895a4e1aa8f23bf199f6e9b6e25f8580b0d1`(94,584B) · core `d909cb584f612db6db9ab0f10f7842f1ed4dd28f447f8704b2e36ca3b3ef1a35`(129,721B, 이전 설치 휠과 동일 해시) **[인용: Master 설치 보고 #2131, 빌드 직후 shasum]**. 설치 모듈 46개의 HEAD 소스 일치는 Nano `diff -rq` 와 Master sha256 대조 두 번 확인.

### C.5 진단 가시성 추가 (코드 DA 라운드 기록)
- 틱 요약에 `published_failed` · 실패 코드 상위 3개(코드 이름과 건수만, 메시지 없음) 추가. 실패가 있는 틱은 status `degraded`, exit 코드는 0 유지.
- 코드 DA r1 은 REJECT(major 1: 동일 코드 중복 순위가 통과 / minor 1: 부분 실패 상태 단언 부재), r2 는 PASS(minor 1: 기존 tally 단언 약함 → 이후 교체). 판정: `artifacts/da-20261002-sol-diag-code-r{1,2}.md`.

### C.6 03:00 백업 슬롯
- `backup_created` 는 03:00 슬롯에서의 동작을 **관찰 전**이다. 위 로그의 `backup_created` true 는 15:12 줄 1건뿐이다 **[실행]**.

### C.7 published 현황
- **서버 복구 뒤 기록.**

## 절 D. 알려진 한계/미완

> 이 절은 «알려진 것»의 목록이며 완료·판정 문구를 쓰지 않는다. 근거 문서를 항목마다 적는다.

1. **내용 연속성 계약(binding)** — 같은 realpath·inode 번호·session id·소비 prefix 를 가진 «다른 볼륨의 복제 파일»은 같은 소스의 이어받기로 수용한다. 사용자가 수용한 계약이다. 근거: `artifacts/arch-20261001-item5-binding-design.md` §3.2 · 코드 DA r16·r17.
2. **R15-m1 (생성기 도구)** — 이유 코드 레지스트리 생성기(tests 도구, 런타임 아님)는 동명 베이스 클래스가 `Exception` 파생과 일반 클래스로 섞이면 일반 후보를 «메시지가 코드»로 오인한다. 현재 소스·528개 `reason_codes.py` 에는 영향 없음. 사용자 승인 하에 후속 패치 없이 기록만 한다. 근거: PLAN.md 2026-10-01 «U1 틱 래퍼 알려진 한계» · `artifacts/da-20261001-sol-r{14,15}.md`.
3. **fork 손자와 프로젝트 락(`PROJECT_BUSY`)** — 패스 도중 fork 한 손자가 runtime 의 프로젝트 락 fd 를 상속해 쥐면, 손자가 사는 동안 다음 틱의 패스가 `PROJECT_BUSY`(exit 40)로 끝난다(손자 종료 뒤 해소). 운영 컴포넌트에서 실제로 발생한다고 확인된 것은 없다. 근거: `artifacts/nano-20261001-item5-u1r4-result.md` 항목 4 · `artifacts/da-20261001-sol-r11.md`.
4. **투어 미수용 3건** — `11-load-repro` · `12-load` · `13-multi-load` 는 사용자 수용 기록이 없다. 사용자 범위 결정으로 기록한다. 근거: PLAN.md 2026-09-28 투어11·12 절.
5. **보류 76건** — 확인대기 51 · 검증대기 25 는 사용자가 보류했다(사용자 범위 결정). 근거: `artifacts/phase89-report-draft-20261002.md` 표 · 지시 원장.
6. **memory 서버(18703) 도달 불가** — 이 문서 작성 시점의 로컬 상태로, 서버 기동은 사용자 몫이다. 복구 전후 상태는 서버 복구 뒤 기록. 근거: 인계 문서 #3.
7. **미확인 항목** — 절 B.5 에 적은 것을 그대로 가리킨다(PLAN.md «[x]» 재실행, P08A-02 구현 증거, memory 서버 도달 상태, consumer 휠 독립 설치 재현, core 종료코드 번호표). 지시 원장 재료는 «8건» 이라 했으나 B.5 본문에서 센 항목은 5개여서 숫자는 적지 않는다.
8. **테스트 minor** — 코드 DA r2 의 minor(tally 코드값 단언이 항상 참)는 실제 값 비교 단언으로 교체했다(같은 세션의 별도 `[test]` 커밋). 기록만 남긴다. 근거: `artifacts/da-20261002-sol-diag-code-r2.md`.
9. **`final-integration-result.json` 의 limits (인용)** — ①운영 환경 키 미공급·운영 서비스 미활성(당시 기록) ②악성 주입 블록 gap 1건 인정, `coverage_complete=false` ③`captured_byte_limit` API 로 고정한 유한 스냅샷 — 이후 소스 추가분의 커버리지 아님 ④독립 해결책 검증·선호/지침 확인은 계속 필요 ⑤초기 전량 수집 지연이 큼 — 처리량·규모 보장 아님 ⑥최신 코드 변경은 본 테스트·실제 실행으로만 확인, 새 독립 DA 라운드 아님. 근거: `.fable-team/airag/final-integration-result.json`(09-28 기록). 이 목록은 당시 시점의 것이며 현재 상태와 다를 수 있다.
10. **«Claude 좌석 수집 불가»** — HELM 이 언급한 항목이나 이 문서 작성 중 근거 문서(`final-integration-result.json` limits · PLAN.md · artifacts · `.fable-team/state/airag`)에서 해당 문구를 찾지 못했다 — **근거 미확인**. 근거가 확인되면 채운다.
