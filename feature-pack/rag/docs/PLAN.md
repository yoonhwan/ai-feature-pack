# AI RAG 완성 계획 · 체크리스트 (PLAN)

결정 근거는 [`DECISIONS.md`](DECISIONS.md)의 D-ID를 참고. 이 문서가 할 일·현재 계획의
유일한 TODO 파일이다. 아래 체크박스를 완료 근거와 함께 갱신한다.

**현재 상태: P-07까지 완료 · P-08 사용자 투어 준비 완료 (2026-09-13).**
P-01/P-02와 P-04/P-05/P-06의 계획된 구현·검증을 완료했다. P03-06 운영 모델 식별도 완료했다.
P-07 품질·규모·독립 설치·장애·전체 형식·최종 실제 모델 회귀 검증을 마쳤다.
[최종 완료 근거와 재현 명령](artifacts/p07-completion-20260913.json)을 확인한다.
[P-05 완료 근거·지원 한계](artifacts/p05-completion.json)를 확인한다.
[카테고리 완료 근거·지원 한계](artifacts/p04-completion.json)를 함께 확인한다.
전체 RAG는 아직 미완성이다. 사용자의 `gcloud auth login` 완료 후 새 로컬 IAP 경로에서
**실제 GPU API·설치 CLI 통합 검증을 완료했다**. API 통합 테스트 1개(20.94초), 별도
디렉터리의 설치 CLI 15개 명령(총 40초 미만), 혼합 문서 의미 그룹/검색(29.517초)이
모두 통과했다. [실행 근거](artifacts/p03-live-gpu-verification.json)에 실제 응답과 시간을
보존했다. 이는 작은 합성 한국어 자료의 동작 검증이며 대규모 품질/성능 판정은 아니다.

현재 구현 경로는 프로필 등록 → 명시적 `--profile-key`로 add/update → 저장된 LLM 설정으로
의미 그룹·태그·요약·영어 번역 → 임베딩 → 원자 발행 → 동일 언어 정책의 검색 →
불변 manifest 재현이다. 원문·번역문·원문 앵커는 구분한다. 실제 모델 가중치 리비전은
아직 자동 증명되지 않았으며 운영자 선언과 런타임 fingerprint를 구분한다.

## 실행 순서

**현재 카테고리: P-08 사용자 투어 직전.**
운영 상태·암호화 백업·소비자 경계 구현과 P-07 종합 검증을 마쳤다.
2026-09-13 사용자 지시로 **P06-05부터 P-07까지 중간 승인 대기 없이 구현·검증을 계속한다**.
P03-06 운영 모델 식별도 이 구간에서 마감한다. 이번 실행 종료 지점은 P-08 사용자 투어 직전이다.
운영 모델 식별(P03-06)의 파일/서빙 경로 근거와 GPU 메모리 attestation 한계는 별도 기록했다.

| 순서 | 묶음 | 현재 상태 | 다음 단계로 넘어갈 조건 |
|---|---|---|---|
| 1 | P-01 설치·암호화 / P-02 저장 계약 | 검증 완료 | 완료 근거를 유지하며 이후 변경의 회귀 확인 |
| 2 | P-03 임베딩·LLM·검색 | 핵심 경로·운영 모델 식별 완료 | 품질·규모 평가는 P-07에서 마감 |
| 3 | P-04 문서·이미지 어댑터 | **완료 · STOP_READY** | 요청된 각 형식의 추출·앵커·검색·원본 반환 검증 |
| 4 | P-05 청크 연결·확장 | **완료 · STOP_READY** | 스냅숏·범위·예산을 지키는 실제 확장 API/CLI 검증 |
| 5 | P-06 운영 보완 | 완료 | 완료 근거 유지 |
| 6 | P-07 종합 시뮬레이션 | 완료 | 완료 근거와 지원 한계를 사용자 투어에 연결 |
| 7 | P-08 사용자 투어 | 미착수 | 사용자가 실제 자료와 동작을 확인하고 피드백 반영 |
| 7A | P-08A 자료·이력·기억 운영 확장 | 대화 첫 경험의 실제 입력 검증 PASS | 고정범위442건·검색창28·기억337·실패/대기0; 감사gap1 명시; 운영 환경키 미설정 |
| 7B | P-08B 프로젝트 코드·문서 RAG + Serena/LSP | v1.2 사용자 요구 반영·구현 미착수 | 저장소/언어/버전 계약 → 증분 색인 → 심볼 연동 → 실제 저장소 시연 |
| 8 | P-09 완성 판정 | 미착수 | 요청 범위 대조, 미완료 확인, 통합 자료와 완료 보고 |
| 9 | P-10 완성 리뷰 매거진 | 미착수 | P-08/P-09 결과를 담은 검증된 리뷰 산출물 전달 |

## 체크 운영 방식

- `[ ]`는 남은 일, `[x]`는 완료 조건을 실행으로 확인한 일이다. 진행 중인 항목도 검증 전에는 `[ ]`로 둔다.
- 완료 시 같은 항목에 날짜와 테스트/산출물 경로를 붙인다. 완료된 줄은 남겨 이력을 확인할 수 있게 한다.
- 막힌 항목에는 막힌 이유와 해소에 필요한 사실/행동을 적고, 독립적으로 가능한 다음 항목을 진행한다.
- 기능 구현만으로 검증·사용자 확인까지 완료 처리하지 않는다. 작은 합성 자료의 성공을 전체 품질/성능 통과로 올리지 않는다.
- 범위를 바꿔야 하면 결정 기록에 반영한다. 실패하거나 어려운 항목을 삭제해서 전체 완료로 만들지 않는다.
- 전체 완료는 P-09의 조건까지 충족했을 때 판정한다. 체크 개수를 개발 진척률로 환산하지 않는다.

## 완료까지의 TODO

### P-01 — 설치·암호화

근거: [D-001](DECISIONS.md#d-001).

- [x] **P01-01** 격리 환경 설치와 `ai-rag`/`krb-rag` 진입점 실행, 실제 SQLCipher·FTS5·vec0 사용 확인. 근거: [설치 검증](artifacts/p01-encrypted-install.json), 2026-09-09.
- [x] **P01-02** 올바른 키 재개방, 오키·키 없음·외부 평문 DB 거부, 키의 argv/로그 비노출 및 암호화 저장 검증. 근거: [설치 검증](artifacts/p01-encrypted-install.json), `tests/test_connect.py`, `test_encryption_opacity.py`, 2026-09-09.

### P-02 — 원본·저장·요청 계약

근거: [D-001](DECISIONS.md#d-001), [D-009](DECISIONS.md#d-009).

- [x] **P02-01** 컬렉션/소스 신원, 원본 바이트·불변 리비전·파생 세대 분리, 스키마 마이그레이션 검증. 근거: [저장 계약](artifacts/p02-storage-contract.json), `tests/test_store.py`, `test_migration.py`, 2026-09-09.
- [x] **P02-02** CAS 토큰·멱등 요청·동시 변경 충돌, stage/publish/fail 경계와 이전 ready 보존 검증. 근거: [저장 계약](artifacts/p02-storage-contract.json), `tests/test_store.py`, 2026-09-09.
- [x] **P02-03** Python API/CLI 공통 envelope, 단건·배치 입력과 원본 조회 검증. 근거: `tests/test_api.py`, `test_cli_p02.py`, [저장 계약](artifacts/p02-storage-contract.json), 2026-09-09.

### P-03 — LLM 전처리·임베딩·검색

근거: [D-010](DECISIONS.md#d-010), [D-011](DECISIONS.md#d-011).

- [x] **P03-01** 텍스트/Markdown/대화를 Docling 구조로 정규화하고 실제 HybridChunker로 청킹; 원문·표준 MD·앵커 유지. 근거: `tests/test_normalize.py`, `test_chunking.py`, 2026-09-10 회귀 검증.
- [x] **P03-02** 불변 처리 프로필과 모델/리비전/차원/전처리별 공간 격리; 잘못된 모델 응답·벡터·입력 크기 거부. 근거: `tests/test_profiles.py`, `test_embeddings.py`, `test_publish.py`, 2026-09-10.
- [x] **P03-03** 실제 GPU LLM의 의미 그룹·태그·요약·영어 번역 → 임베딩 → 원자 발행; 원문과 파생 결과 구분. 근거: [실제 GPU 검증](artifacts/p03-live-gpu-verification.json), 혼합 문서 4개 입력 단위→3개 의미 그룹, 2026-09-10.
- [x] **P03-04** BM25+cosine RRF, 순위 제한 전 범위 필터, 동점 결정성, 검색 중 동시 발행에도 동일 스냅숏 유지. 근거: `tests/test_search.py`, `test_api_processing.py`, 2026-09-10.
- [x] **P03-05** 설치 CLI의 등록/수정/검색/원본·청크·정규화문서 조회와 과거 manifest 재현. 근거: [실제 GPU CLI 15개 명령](artifacts/p03-live-gpu-verification.json), 2026-09-10.
- [x] **P03-06** 운영용 모델 식별 기록을 완성한다. 완료 조건: embedding/LLM의 모델·revision 값·근거와 확인 한계를 기록하고 프로필에 반영; 모델 변경 시 새 공간/프로필로 분리됨을 확인. 현재 probe용 미확인 표기를 운영 핀으로 취급하지 않는다. 직접 가중치 증명이 안 되면 D-010의 명시적 운영자 선언과 그 한계를 남긴다. **완료(2026-09-13)**: 실행 컨테이너 argv·마운트·`/v1/models`·실제 가중치 SHA-256 및 LLM HF cache 리비전을 읽기 전용으로 대조했다. [식별 근거](artifacts/p03-operational-model-identity-20260913.json)와 [운영 프로필](artifacts/operational-profile-20260913.json)에 반영하고 실제 모델 품질 실행에 사용했다. 파일/서빙 경로 식별이며 GPU 메모리의 암호학적 attestation이 아님을 명시했다. `tests/test_profiles.py tests/test_reindex_contract.py` 28 passed(35.40초)로 모델·리비전/프로필 전환 시 공간 분리 검증.

폭넓은 한국어/영어 의미 품질은 **P07-04**, 규모·지연·메모리는 **P07-05**에서 검증한다.
현재 성공한 작은 합성 자료를 이 두 항목의 완료 근거로 사용하지 않는다.

### P-04 — 문서·이미지 어댑터 · 9/9 완료 · STOP_READY

근거: [D-003](DECISIONS.md#d-003), [D-007](DECISIONS.md#d-007), [D-011](DECISIONS.md#d-011), [D-012](DECISIONS.md#d-012).

- [x] **P04-01** 어댑터 공통 계약과 실제 의존성을 확인한다. 완료 조건: 지원 형식별 입력·Docling 구조/표준 MD·원문 앵커·추출 오류·처리 프로필 계약을 정하고, 전체 Docling/별도 HWP·이미지 경로의 설치 및 모델 필요 조건을 확인한다. 문서 어댑터는 Docling 구조를 직접 청커에 전달한다. **완료(2026-09-10)**: `document_adapters.py`의 캡처된 버전/모델 해시·오류/입력 제한 계약, 실제 의존성 설치 및 문서/이미지 어댑터 단위 검증. 세부 결정은 D-012 참고.
- [x] **P04-02** PDF 경로를 구현·검증한다. 완료 조건: 실제 디지털 PDF의 본문/표와 페이지 앵커가 추출·검색되며 원본 바이트를 되돌려 받을 수 있다. 스캔 페이지는 OCR 경로로 명시한다. **완료(2026-09-10)**: 실제 PDF 본문·표·페이지 영역, 디지털/스캔 혼합 PDF와 실제 GPU 검색·원본 바이트 반환 통과. 근거: [P-04 완료 기록](artifacts/p04-completion.json).
- [x] **P04-03** DOCX 경로를 구현·검증한다. 완료 조건: 제목/문단/표 구조와 원본 위치를 보존하고 실제 파일에서 추출→검색→원본 반환이 동작한다. **완료(2026-09-10)**: 실제 DOCX 제목/문단/표·중복 문장의 별도 XML 위치·원본 그림 바이트 보존, GPU/API 및 설치 CLI 통과. 근거: [P-04 완료 기록](artifacts/p04-completion.json).
- [x] **P04-04** XLSX 경로를 구현·검증한다. 완료 조건: 실제 시트·셀/표 경계, 병합 셀, 수식과 값의 보존 범위를 확인하고 검색 근거가 원래 시트를 가리킨다. 수식 보존과 재계산을 구분하고 미지원 동작을 명시한다. **완료(2026-09-10)**: 실제 XLSX 시트/표/병합 셀·일반 수식 문자열·캐시 값 보존 및 GPU 검색 통과. 수식 재계산은 없고 array/data-table 수식은 명시적으로 거부한다. 근거: [P-04 완료 기록](artifacts/p04-completion.json).
- [x] **P04-05** HWP 별도 어댑터를 구현·검증한다. 완료 조건: 선택한 실제 파서로 본문/표/이미지의 지원 범위를 실측하고, 앵커의 정확도와 한계를 기록한 검색·원본 반환 사례가 있다. **완료(2026-09-10)**: hwplib 1.1.11 + JVM으로 실제 HWP 본문/표/그림 추출, 섹션·문단·표 경로, GPU/API·설치 CLI·원본 반환 통과. 보호/배포용 HWP와 렌더링 좌표는 지원하지 않는다. 근거: [P-04 완료 기록](artifacts/p04-completion.json).
- [x] **P04-06** HWPX 별도 어댑터를 구현·검증한다. 완료 조건: 실제 파일의 섹션/문단/표/이미지 추출과 앵커를 검증하고, Docling 기본 지원으로 오표기하지 않는다. **완료(2026-09-10)**: 실제 HWPX spine 순서·문단/표 XML 위치·원본 그림 바이트, GPU 검색·원본 반환 통과. 근거: [P-04 완료 기록](artifacts/p04-completion.json).
- [x] **P04-07** 한국어 OCR과 디지털/스캔 혼합 페이지 처리를 검증한다. 완료 조건: 실제 스캔/이미지 입력에서 OCR 결과와 원문 페이지·영역 연결을 확인하고, OCR 선택/오류/누락을 드러낸다. EasyOCR/Tesseract 품질 비교는 같은 자료로 측정한다. **완료(2026-09-10)**: 한국어 OCR와 혼합 PDF 통과. 같은 3문장 이미지의 공백 제외 CER: Tesseract PSM3 69.44%, PSM6 0%, EasyOCR 13.89%. 공백 포함 오류율도 산출물에 기록했으며 일반 품질 우열로 확대하지 않는다. 근거: [P-04 완료 기록](artifacts/p04-completion.json).
- [x] **P04-08** 글자 없는 이미지의 비전 의미 표현을 연결한다. 완료 조건: 사용 가능한 실제 비전 제공자를 확인하고, 이미지→의미 표현→검색→원본 이미지 반환이 동작한다. 추론 내용은 원문 인용과 구분하고 제공자/프롬프트/모델 근거를 보존한다. **완료(2026-09-10)**: 실제 byz-llm 이미지 입력→관측 설명→임베딩→검색·원본 반환 통과. 검색에 inferred/contains_inference를 노출하고 원문 직접 인용으로 표시하지 않는다. 근거: [P-04 완료 기록](artifacts/p04-completion.json).
- [x] **P04-09** 문서/이미지의 실패·암호화 경계를 검증한다. 완료 조건: 미지원/손상 입력이나 변환·OCR·비전 실패가 가짜 ready를 만들지 않고 이전 검색 가능 세대를 유지한다. 원본·추출물·벡터 저장의 암호화 및 변환 중 임시 파일 처리 범위를 실제 확인한다. **완료(2026-09-10)**: 손상/형식 불일치·ZIP/셀/페이지/픽셀 제한·모델 해시 변경 거부, 실패 갱신의 이전 ready 유지, 암호화 DB 및 0600 OCR 임시 PNG 정리 확인. 강제 프로세스 종료 시 임시 파일 잔존 가능성은 한계로 기록했다. 근거: [P-04 완료 기록](artifacts/p04-completion.json).

### P-05 — 청크 연결·예산 있는 확장 · 5/5 완료 · STOP_READY

근거: [D-001](DECISIONS.md#d-001), [D-010](DECISIONS.md#d-010).

- [x] **P05-01** 확장 계약과 스냅숏 정책을 확정한다. 완료 조건: `search`와 확장이 공유하는 소스/리비전/세대·범위·필터를 정의하고, 별도 `expand(manifest)`에서 오래된 manifest를 어떻게 처리할지 명시한다. 현재 상태를 과거 스냅숏에 조용히 섞지 않는다. **완료(2026-09-10)**: [D-013](DECISIONS.md#d-013)에 inline 동일 스냅숏, standalone stale 거부, historical replay, 소스/MIME 필터와 근거 JSON 예산 계약을 기록했다.
- [x] **P05-02** 구조 연결을 저장한다. 완료 조건: 제목/문단/표/페이지/대화 흐름 등 실제 어댑터가 제공하는 구조 관계로 인접·상하위 청크를 찾고 원문 근거를 유지한다. **완료(2026-09-10)**: v5 세대별 구조 연결·관측 locator 저장, 원자 발행과 기존 v4 backfill 검증. 반복 제목·상하위 섹션·표/페이지/시트/턴 관계를 확인했다. 근거: [P-05 완료 기록](artifacts/p05-completion.json).
- [x] **P05-03** 참조 해석과 의미 연결을 구현한다. 완료 조건: 명시적 문서 참조와 추론된 의미 관계를 구분하고, 해석되지 않은 참조·연결 근거·모델 공간을 표시한다. **완료(2026-09-10)**: 원문 CommonMark/source-key/대화 reply_to/네이티브 DOCX hyperlink, fragment·미해결/모호한 참조와 opt-in exact cosine 연결을 검증했다. 실제 GPU 결과에도 references/similar와 분류·점수를 보존했다. 근거: [P-05 완료 기록](artifacts/p05-completion.json).
- [x] **P05-04** 확장 예산과 범위 제한을 구현한다. 완료 조건: 깊이/청크/토큰 예산, 순환 방지·중복 제거, 매 단계의 컬렉션·필터·스냅숏 검증, 중단/잘림 이유가 실행 테스트로 확인된다. **완료(2026-09-10)**: 시드 포함 청크/깊이/토큰/바이트/연결 예산과 순환·중복 방지, 매 후보의 스냅숏/공간/컬렉션/소스·MIME 필터, 소모량·잘림 사유를 검증했다. 근거: [P-05 완료 기록](artifacts/p05-completion.json).
- [x] **P05-05** 확장 API/CLI와 근거 반환을 연결한다. 완료 조건: 실제 검색 결과에서 확장→원문/출처 조회가 동작하고, 갱신·삭제·과거 manifest 상황에서도 계약을 지킨다. **완료(2026-09-10)**: API 및 search --expand / expand --manifest-id / fetch expansion 연결, 동일 스냅숏 동시 발행, stale 거부·삭제 후 historical replay·원본 조회를 설치 CLI와 실제 GPU로 검증했다. 근거: [P-05 완료 기록](artifacts/p05-completion.json).

### P-06 — 요청 처리·재처리·복구·백업

근거: [D-002](DECISIONS.md#d-002), [D-006](DECISIONS.md#d-006), [D-009](DECISIONS.md#d-009), [D-010](DECISIONS.md#d-010).

- [x] **P06-01** 명시적 add/update/delete/restore, 단건·배치 처리와 삭제/복구 시 검색 가시성 연결. 근거: `tests/test_cli_processing.py`, [실제 GPU CLI 검증](artifacts/p03-live-gpu-verification.json), 2026-09-10.
- [x] **P06-02** 동일 요청의 한 개 처리 claim, IN_PROGRESS, 만료 claim 복구, 완료/실패 응답의 불변 재현과 stale 작업 차단. 근거: `tests/test_api_processing.py`, `test_pipeline.py`, 2026-09-10. 운영 명령을 통한 일반 retry는 다음 항목이다.
- [x] **P06-03** 명시적 retry/기존 pending 입력 처리 명령을 구현한다. 완료 조건: 대상 job/revision/profile을 식별해 재처리하고, 종료된 원래 응답을 바꾸지 않으며 중복 호출/프로세스 재시작에도 작업이 중복 발행되지 않는다. **완료(2026-09-11)**: `api.retry`와 `manage retry --job-id --request-id [--profile-key]`, `manage status`의 `latest_job` 식별 정보 구현. 요청 원장과 claim을 원자 기록하고, 실패한 원 job은 보존한 채 새 job을 생성한다. stale CAS·다른 활성 job·비처리 job·잘못된 입력을 거부하며, 같은 요청의 재생·만료 claim 복구·이전 시도 fencing을 검증했다. 근거: `tests/test_retry_contract.py` 독립 20개 통과(설치 CLI와 모의 HTTP 제공자의 pending/failed 성공·재생 포함), 전체 오프라인 380 passed, 1 skipped, 19 deselected. 실제 GPU 재실행은 이번 검증에 포함하지 않았다.
- [x] **P06-04** reindex/프로필 전환을 구현한다. 완료 조건: 같은 원본의 새 처리 세대를 만들고, 실패 시 이전 색인을 유지하며 완성된 색인으로 원자 전환한다. 이전 리비전·manifest 재현과 모델 공간 격리가 유지된다. **완료(2026-09-11)**: `api.reindex`와 `manage reindex --collection --source-key --expected-revision --profile-key --request-id` 구현. 요청 원장의 재생 판정을 CAS보다 먼저 수행하고, 저장 원본·메타데이터·리비전을 유지한 채 새 job/세대만 생성한다. 처리 중·실패 시 기존 검색을 유지하고, 차원이 다른 모델 공간으로의 전환·과거 manifest/원문 재현·후속 수정 뒤 동일 응답 재생·재시작·동시 수정 충돌을 검증했다. 오래된 pending/running job이 새로운 유효 요청을 막지 않도록 reindex와 retry의 중복 가드를 현재 state_version에 한정했다. 근거: `tests/test_reindex_contract.py` 독립 23개, 기존 retry 20개 통과, 전체 오프라인 403 passed, 1 skipped, 19 deselected. 설치 CLI 성공 경로는 모의 HTTP 제공자로 검증했으며 실제 GPU 재실행은 포함하지 않았다.
- [x] **P06-05** 운영 상태/doctor/verify를 보완한다. 완료 조건: pending/running/failed 작업, profile·provider 구성, FTS/vec/ready 포인터 불일치를 진단하고 키·원문을 로그로 노출하지 않는다. 현재 기본 doctor/verify가 전체 운영 진단인 것처럼 표시하지 않는다. **완료(2026-09-13)**: `diagnostics.py`, 진단 전용 `open_readonly`, API/CLI 운영 상태·verify·doctor 구현. FTS 내용/행·vec 가시성/소속/차원·head/ready 포인터·profile·DB 정합성 검증, caller snapshot 보존, 외부 연결 미검사 명시. 자체·대상 98 passed와 `tests/test_operations_contract.py` 독립 10 passed(13.53초): 손상 검출, 자동수리 없음, 기존 stale-ready 정상 허용, CLI 읽기 전용·민감정보 비노출 확인.
- [x] **P06-06** 암호화 백업·복원을 구현한다. 완료 조건: 별도 새 경로에 일관된 암호화 백업을 만들고 복원한 DB에서 원문·검색·manifest·작업 상태를 재검증한다. 오키/손상 백업 실패를 처리하고 기존 DB를 덮어쓰지 않는 검증 사례가 있다. **완료(2026-09-13)**: SQLCipher snapshot·선택적 키 변경·재개방/원본해시/정합성 검증 후 0600 파일을 원자적 nonoverwrite 공개. `manage backup`/`manage restore-backup`과 API 제공. 실패 staging은 보존하되 최종경로로 공개하지 않는다. 원본·검색·manifest·pending 작업 복구, 동시 쓰기 snapshot, 기존파일/symlink/race 보호와 잘못된키·손상 거부 검증. 자체9+독립8 포함 대상64 passed(25.60초), 독립 `tests/test_backup_contract.py` 8 passed(9.90초).
- [x] **P06-07** 소비자 트리거 경계를 검증한다. 완료 조건: 샘플 소비자가 변경/삭제를 명시 요청하고, 접근 불가·불완전 열거를 삭제로 오인하지 않으며 tombstone은 명시적 restore 없이 복구되지 않는다. core에 워처·폴링·자동 디렉터리 탐색을 추가하지 않는다. **완료(2026-09-13)**: `examples/explicit_consumer.py`와 `tests/test_consumer_contract.py`의 명시 이벤트·안정된 event ID/CAS·관측 무변경·외부파일 보존·tombstone 4경로 비부활/명시restore 검증. core 변경 없이 소비자13개 포함 대상회귀117 passed(47.84초).

### P-07 — 종합 시뮬레이션·품질·규모

근거: [D-001](DECISIONS.md#d-001), [D-003](DECISIONS.md#d-003), [D-010](DECISIONS.md#d-010), [D-011](DECISIONS.md#d-011).

- [x] **P07-01** 작은 합성 한국어 자료로 실제 GPU API·설치 CLI를 실행한다. 근거: [실제 GPU 검증](artifacts/p03-live-gpu-verification.json), API 1개·CLI 15개 명령·혼합 주제 사례, 2026-09-10. 독립 클린 설치/전체 형식 검증은 아래 항목에 남긴다.
- [x] **P07-02** 독립 소비자 설치를 검증한다. 완료 조건: 새 환경에서 패키지를 설치해 저장소 checkout에 의존하지 않고 두 진입점과 Python API로 등록→검색→원본 조회를 실행한다. 네이티브 의존성·버전·설치 명령을 재현 가능하게 남긴다. **완료(2026-09-13)**: 새 `/tmp/airag-independent-KCG7SW/venv`에 wheel과 documents extra 설치, 저장소 밖 cwd에서 site-packages 모듈 사용 확인. 실제 GPU 등록/검색/원본조회/reindex/과거manifest/Python API retry/backup/restore/verify/doctor/status 및 두 CLI 진입점13개 명령 통과. [최종 환경·명령·응답](artifacts/p07-independent-install-final-20260913.json), [설치명령·wheel SHA](artifacts/p07-install-reproduction-20260913.json). 초기 검증기의 가변 현재상태 전체동등 비교 오류는 불변 원본 필드 대조로 수정했으며 초기 실패 보고도 보존했다.
- [x] **P07-03** 전체 형식·상태 시나리오를 실행한다. 완료 조건: P-04의 각 문서/이미지, 빈/긴/한글·영문/대화 입력, 중복 등록·갱신·삭제·복구·확장을 실제 암호화 DB와 CLI로 검증하고 원본·앵커 누락 여부를 대조한다. **완료(2026-09-13)**: `tests/test_acceptance_live.py` 실제 GPU·설치 CLI 12종(PDF/DOCX/XLSX/HWP/HWPX/OCR/비전/빈/긴/한글/영문/대화),154개 CLI 명령 통과(541.44초). 원본 바이트·anchor, 중복등록/동일내용update·확장·삭제시비노출·복원·과거manifest/원응답재생 확인. 실제 변경/동시수정은 reindex/retry/fault 테스트와 결합해 검증. [실행 XML](artifacts/p07-lifecycle-final-20260913.xml), [형식별 retained trace](artifacts/p07-completion-20260913.json).
- [x] **P07-04** 의미 검색·전처리 품질을 평가한다. 완료 조건: 실행 전에 질문/정답 근거·평가 기준을 고정하고, 한국어/영어 검색과 태깅·요약·번역·의미 분리의 누락/오역/잘못된 근거를 측정한다. 실패 사례와 판정 근거를 함께 기록한다. **완료(2026-09-13)**: 사전 고정12문서/24질의에서 실제 모델 top1/top3 모두100%, 원문 anchor12개/정답source24개 정확성 확인. [최종 의미 검토](artifacts/p07-quality-final-review-20260913.json), [실측](artifacts/p07-quality-v3-20260913.json). 초기 v1/v2 그룹요약 오역·언어위반을 보존하고 grouping metadata를 주제 식별 역할로 명확히 한 v3로 재검증했다. v1/v2 저장프로필은 원래 prompt/지문을 유지하고 새 등록만 v3를 기본으로 사용한다. 소규모 합성 코퍼스의 결과이며 일반 품질 보장이나 사용자 투어로 확대하지 않는다.
- [x] **P07-05** 규모·지연·자원 사용을 측정한다. 완료 조건: 목표 자료 규모와 허용 기준을 먼저 정하고, 수집/검색/확장의 지연·메모리·디스크 및 현재 O(N) 검색 비용을 실측한다. 작은 샘플 결과를 대규모 보장으로 확대하지 않는다. **완료(2026-09-13)**: [사전 고정 기준](artifacts/p07-evaluation-plan.json)에 따라100/1000문서·500/5000청크·1024차원·규모별30질의 실행. 1000문서 발행1.30초, 검색p95 0.147초, 확장p95 0.041초, 프로세스 peak562MiB, DB/WAL37.54MiB로 기준 통과. [실측](artifacts/p07-scale-20260913.json). 합성벡터의 로컬 저장/검색/확장 측정이며 외부 모델 지연·대규모 보장과 구분한다. 실제 수집/질의 시간은 품질 보고서에 별도 보존.
- [x] **P07-06** 장애·동시 실행·재시작을 종합 검증한다. 완료 조건: 제공자 실패/잘못된 벡터, 변환 실패, 처리 중 프로세스 종료, 발행 직후 응답 유실, 동시 수정/삭제, 재색인·백업 상황에서 부분 발행·중복·과거 근거 변조가 없다. 장애 주입은 테스트용 프로세스/연결로 수행한다. **완료(2026-09-13)**: `tests/test_fault_recovery.py`/`tests/helpers/fault_child.py`의 실제 child 종료9사례: add/retry/reindex stage 종료, publish commit후 응답유실, publish중 transaction rollback, dualprocess CAS, backup 공개전 종료. 키 pipe 전달, 자신의 test process만 종료, lease 만료 시각만 테스트에서 앞당김. 기존 embeddings/normalize/pipeline/publish/backups와107 passed,1 skipped,3 deselected(32.67초). 원 ready/FTS/vec·과거응답·원본 보존 확인.
- [x] **P07-07** 전체 회귀와 실제 모델 검증을 재현 가능하게 마감한다. 완료 조건: 오프라인 테스트와 실제 모델 테스트를 분리 실행하고, 명령·환경·profile·결과·건너뛴 이유를 저장한다. 아직 실행하지 않은 필수 시나리오가 남아 있으면 P-07을 완료 처리하지 않는다. **완료(2026-09-13)**: 오프라인464 passed/1 skipped(181.62초), 실제 모델19 passed(200.55초), 전체형식12 passed(541.44초). skip은 다른 identity-field 테스트로 대체된 기존 placeholder 한 건이며 필수 시나리오 미실행이 아니다. 실제 v3 다중주제4unit→2group 경계도 확인. [명령·프로필·환경·소스해시·결과](artifacts/p07-completion-20260913.json), [오프라인 XML](artifacts/p07-offline-final-20260913.xml), [실제 모델 XML](artifacts/p07-live-final-20260913.xml). 초기 품질·하네스 오류는 보존하고 최종 통과 근거와 구분했다.

### P-08 — 사용자 투어

근거: [D-001](DECISIONS.md#d-001).

**투어 안내 준비 완료(2026-09-13)**: [풀 투어 가이드](artifacts/full-tour-guide.md).
현재 **T07 내용 갱신·요청 재생 기술 검증 완료, 별도 데이터 생애주기 기획 DA PASS(2026-09-27)**. 한글도서관 샘플만5권14일→7권21일 변경, 원본리비전1→19/처리세대23. 같은request_id 재생응답 동일·외부모델호출0·추가행0, 오래된CAS토큰은 CONFLICT_STALE_REVISION으로 거부. 최신한영검색은 변경내용, 옛원본/manifest1·2·13·14는5권14일 유지, 영어샘플/타소스 무변경·DB정합성확인. `T07-results-20260927.json` 근거를 보존하고 다음투어는T08이다. 현재 사용자는 자료변경트리거·시간순대화/기억/아카이브 순환 기획을 요청했고 나노초안과 Fable5.1 2차 DA검토를 완료했다. 실제 수집/기억 자동화는 아직 구현·실행하지 않았다.
T06 보존 결과: 환불안내→증빙·지원절차 참조연결, inline/standalone3청크동일, 청크/토큰잘림사유·의미추론분리·중복제거 검증. manifest33/expansion1~7과 `T06-results-20260927.json`에 근거보존.
T05 번역 보완 보존: source sample-mixed_pdf 세대21→22, 원본리비전15·앵커·옛job/manifest 보존. 새v3는 구조줄별독립번역을 결합하고 annotation이 번역을 덮어쓰지 않는다. 'The cat sleeps a lot.' 및 표42/17·서울날씨·커피문장 보존, 한영새세대검색통과. 실제의미8사례·오프라인492passed/1placeholder skip·실제모델회귀4passed, Unicode11종/lease갱신/부분발행거부 검증. 기존v1/v2지문/동작유지. `T05-translation-completion-20260927.json`/`T05-translation-repair-20260927.json`에 근거, 사용자확인완료.
T05 출처 대조 근거: 원본리비전18개 해시/길이, 대표9자료의 문자위치·셀·XML·JSON pointer·PDF영역·이미지추론표시, T04 manifest18개재현을 읽기전용으로 확인(`T05-results-20260927.json`). 이 기록에서 발견한 옛세대21의 '고양이→Cows' 오역은 과거기록으로 보존했고 새세대22로 해결했다.
T04 보존 결과: 한영18질의 모두정답근거, 정답1위16/18·2위내18/18. 환불증빙 한영2질의의 상세문서2위(T04-RANK-001), 초기2질의61.01/79.03초 원인미확정 지연(T04-LATENCY-001)을 유지한다. 상세기록 `T04-recheck-20260927.json`, 최초12질의 `T04-results.json`도 보존하며 사용자수락과 구분한다.
T03 보완 근거(2026-09-27): 원래 `long.txt`는 enrichment v2의 명시적 원문사용 응답으로 재색인해10.1초·45회 반복 보존 확인. 기존 v1 프로필/실패job/원본리비전은 유지했다. 혼합PDF는 해당파일 전용 한국어OCR/PSM6으로 재색인해 공백제외 오류율8.33%→0%, 영어표/앵커/옛OCR세대 보존 확인. 오프라인473passed/1기존placeholder skip와 실제모델4passed, `T03c-completion.json`/`T03c-repair-results.json`에 근거 보존. 중단 사이 추가된 `long-real.txt`도 보존했고 대체샘플의 성공만으로 원래 실패를 완료 처리하지 않았다.
T01 로컬 점검: Python3.13.12, SQLCipher4.12.0/SQLite3.51.1, FTS5, vec0 v0.1.9 런타임 정상. 패키지0.1.0과 P07 완료보고 소스해시 전부 일치. 과거 `/tmp` 독립설치·wheel은 현재 없으며 투어 실행 경로는 현존 패키지 `.venv`를 사용한다. 2026-09-21 `developer.ts@byourz.com` 재로그인 후 프로젝트 조회 성공, 두 GPU VM RUNNING 확인. 로컬 IAP18002/18811을 재연결하고 `/v1/models`에서 byz-llm(root google/gemma-4-12B-it-qat-w4a16-ct,24576)와 byz-embed(root /models/qwen3-embed,8192) 응답 확인. 가중치 파일해시는 이번에 재측정하지 않았다. 사용자가 권한 제한 파일 보관을 승인했으며 아래와 같이 키 준비를 마쳤다. 이 점검은 T01 완료 시점의 기록이며 T02 생성 결과는 아래에 있다.
이후 요청마다 현재 단계를 마감하거나 다음 한 단계만 진행하고, 결과·사용자 확인 상태·남은 목록을 출력한 뒤 대기한다.
T02 실행 결과: 투어 디렉터리의 `tour.db`를 새로 생성(schema v5, 권한600), 키는 매 호출 새 raw-byte pipe로 전달. 기본 텍스트/LLM 전처리 프로필 `002e5a81bbf23d75502ded8cb2cfcbb0af5ec79403f5e1f49d5d1d6b79ba9da7`(space1)을 등록했다. DB verify/doctor healthy=true, source0/profile1, 암호화 헤더 및 read-only 재개방 확인. 실행 기록은 같은 디렉터리 `T02-results.json`이며 `tour-session.json`의 다음 단계를 T03으로 갱신했다. 자료 등록은 아직 실행하지 않았다. 문서/이미지별 어댑터 프로필은 T03에서 필요한 설정을 확인해 추가한다.
T01 키 준비 완료: 사용자의 `진행` 승인에 따라 저장소 밖 전용 키 폴더(700)에 UTF-8 hex 키 파일(600)을 생성하고 32바이트 디코딩·재읽기 일치를 확인했다. 키 값은 출력하지 않았다. 투어 ID는 `tour-20260921-191737-df2c2ec3`, 실행 기록은 `/Users/yoonhwan/.local/share/airag-tour/runs/tour-20260921-191737-df2c2ec3/tour-session.json`이다. 키 위치는 이 비밀값 없는 실행 기록에 보존한다. 키 생성 당시에는 DB·자료가 없었으며, 이후 T02에서 DB를 생성했다. 입력 자료는 아직 등록하지 않았다. T02부터 매 명령마다 키를 raw bytes로 새 pipe FD에 전달한다. 진행 원장은 이 PLAN이다.

- [x] **P08-01** 사용자와 확인할 자료·질문·동작 순서를 정한다. 완료 조건: 문서/이미지/대화와 원본 확인·확장·갱신·삭제·복구를 포함한 투어 시나리오가 있다. **완료(2026-09-21)**: 사용자가 기본안을 선택했다. 공개·합성 문서/표/이미지/대화 샘플로 대출 수량·기간, 환불 증빙·연결 절차, 재고 수량의 원본 위치를 확인한다. 가이드 T00~T13 순서로 환경 준비→등록→검색·원본·확장→갱신·재시도·재색인·논리삭제/복원→백업·API·피드백을 한 요청당 한 단계씩 진행한다. 사용자 실제 자료는 현재 지정되지 않았으며 자동 수집하지 않는다. 이후 T02까지 완료했으며 현재 다음 단계는 T03이다.
- [ ] **P08-02** 사용자와 실제 투어를 진행한다. 완료 조건: 사용자가 검색 근거와 원본을 직접 확인하고 연결 확장 및 상태 변화까지 함께 확인한다. 자동 테스트를 사용자 확인으로 대체하지 않는다.
- [ ] **P08-03** 피드백을 반영하고 다시 확인한다. 완료 조건: 투어에서 발견한 결함/미충족 요구를 해결하거나 명시적으로 범위 결정을 기록하고, 필요한 항목을 사용자와 재확인한다.

### P-08A — 자료·이벤트·기억 운영 확장 개발 (대화·검색·기억·운영 통합 검증 중)

근거: [D-014](DECISIONS.md#d-014), [최종 기준안](artifacts/data-lifecycle-plan.md), [Fable 5.1 DA 검토](artifacts/data-lifecycle-da-review.md).
2026-09-27 사용자 추가 요청. 두 축 기획을 기준으로
새 개발 작업을 이 단일 원장에 추적한다. 기존 P01~07 완료를 되돌리지 않고, 기존 P08 투어와
별개 확장 트랙으로 둔다. 구현 위치는 `feature-pack/rag-consumer/`이며 P08A-03 순수 입력 어댑터와 테스트를 생성했다.
core에 워처·폴링·전체 폴더 탐색을 넣지 않는다. 2026-09-27 사용자 “다음으로 진행”에 따라 P08A-01 계약 구체화를 시작했다. 실제 입력 범위는 현재 세션+투어 17개 source로 확정했으며 선택 세션 고정 범위의 수집·검색·기억 검증은 완료했으며 운영 환경키 기반 상시 서비스는 미활성이다.

**P08A-01 진행 근거**: [계약 초안](artifacts/p08a01-contract.json), [합성 JSONL](artifacts/p08a01-synthetic-conversation.jsonl), [접점·남은 정책](artifacts/data-lifecycle-plan.md#13-p08a-01-진행--검토-가능한-계약-초안). 기존 대화 어댑터로 DoclingDocument 생성 및 message ID/원문 pointer 보존을 확인했다. 사용자가 현재 세션+투어 문서를 선택했고 exact path와 17개 source 허용 목록을 고정했다. 원본 메타·DB를 읽기 전용 확인했으며 4차 DA는 PASS이며 운영 정책·인수 시험이 남아 체크박스는 미완료로 유지한다.

- [ ] **P08A-01 — 사건·권한·보존 계약**. 자료/이벤트 envelope, 안정 source/message/session/segment ID, source_version·CAS·멱등성·checkpoint, raw/projection/window/memory 구분을 확정한다. 실제 첫 연결 채널·허용 경로·민감정보·보존·N/토큰 정책을 기록한다. **닫는 증거**: D-014 및 키 보관·교체·복구 정책 확정, 중복/역순/rename/수정삭제/권한철회/비밀마스킹/재시작의 계약 사례와 기대 결과, DA의 개발 착수 검토. **선행**: 기획 DA 필수 지적 반영.
- [ ] **P08A-02 — 자료 변경 consumer**. 문서·이미지 완료 이벤트, wiki 게시 revision, DB committed CDC/snapshot 이벤트를 명시 core 요청으로 연결한다. **닫는 증거**: 출처별 add/update/delete/restore/reindex와 부분 목록 미삭제·CAS 충돌·옛ready 보존, source별 receipt/offset 복구. 실제 wiki/DB 서비스가 미선정이면 fixture 완료와 실제 연결 완료를 분리하고 전체 지원 완료로 표시하지 않는다. **선행**: 01.
- [ ] **P08A-03 — 대화·CS JSONL 기록과 윈도우 문서**. 한 사건 한 JSONL 레코드를 SQLCipher에 암호화 보존하고 안정 ID의 윈도우 문서를 연속 생성한다. 저장 세그먼트와 검색 윈도우는 별도 ID/원본 범위로 연결한다. 합성 로그 후 사용자가 지정한 실제 채널을 연결한다. **닫는 증거**: JSONL round-trip, 부분 줄·중복·순서역전·긴 메시지·tool 관계·재시작 무손실, 원본 내구성 확인, 승인 밖 읽기·비밀 저장 없음. **선행**: 01.
- [ ] **P08A-04 — 기존 RAG 기반 히스토리 검색·N개 활성 창**. JSONL 윈도우의 현재 유효 메시지를 DoclingDocument로 구성해 기존 HybridChunker·전처리·임베딩·검색에 발행한다. 대화·CS 검색은 기억 추출과 무관한 기본 기능이다. **닫는 증거**: 10개 창 중 최근 N=4만 활성 입력에 넣어도 W001 검색·message ID 인용 가능, 창 경계 문맥·중복 제거·토큰 상한·수정삭제·권한철회 반영, stored/index_pending/searchable/failed 표시. 임의 메타 필터·새 JSONL core 지원을 가정하지 않는다. **선행**: 02의 명시 요청 계약·03.
- [ ] **P08A-05 — 검색 기반 기억·트러블슈팅 지원**. 대화·CS 원문 검색 위에 사실/선호·진행/결정·troubleshoot·지침 후보를 anchor/version으로 연결하고 검증 후 memory 예산에 배치한다. **닫는 증거**: 유사 오류의 증상·환경·실패 시도·성공 검증 인용, 제안/시도/성공 구분, 재오픈·삭제·원본편집에 따른 무효화, 중요도 선택 이유·pin overflow, 낡은근거·지침권한승격 거부. AGENTS/SOUL/config 자동 변경이나 상위지침 자동복제는 하지 않는다. **선행**: 01·04.
- [ ] **P08A-06 — 아카이브·퇴거·재참조 순환**. 보존 검증→원자 manifest/checkpoint→활성 참조 퇴거→권한 있는 제한 검색의 순환을 구현한다. **닫는 증거**: archive/요약 실패·디스크부족·전환전후 크래시에도 원본무손실, 전환 재실행 중복없음, 삭제/철회자료 비부활, 메모리/아카이브 파생물 연계무효화. 영구 삭제는 별도 승인·정책 범위다. **선행**: 04·05.
- [ ] **P08A-07 — 통합 장애·권한·성능 검증**. 두 축의 중복/순서/권한/편집/삭제/재시작과 실제 주입 예산, 기억 회수 품질·비용·지연을 사전 고정 자료/기준으로 검증한다. **닫는 증거**: 허용되지 않은 근거 노출0·데이터 유실0·stale 파생물 신규발행0, 정의된 창/토큰 상한과 측정 기준 통과. 합성·실제 연결 결과 및 미지원 경계 분리. **선행**: 02~06.
- [ ] **P08A-08 — 실제 연결·사용자 시연·확장 완료 판정**. 선택한 실제 자료 채널과 에이전트 이력 채널에서 수집→검색→기억선정→archive→재참조→수정삭제 순환을 시연한다. **닫는 증거**: 사용자 확인과 피드백 재검증, 실제 연동한 출처 목록·지원 한계·설치/운영 근거, DA 최종 대조. **선행**: 07. 기존 P08 투어 완료를 대신하지 않는다.

개발 진행의 권장 순서는 `01 → (02,03) → 04 → 05 → 06 → 07 → 08`이다.
- [ ] **P08A-09 — 90일 활성 만료·파일 아카이브·명시 조회**. 최신 사용자 선택으로 영구 삭제 요구를 대체한다. 메시지 작성일부터 90일 뒤 대화와 의존 기억을 일반 검색/컨텍스트에서 제외하고, 별도 항목별 승인 없이 암호화 파일 아카이브로 보존한다. 조회는 별도 요청과 현재 권한 확인을 거치며 자동 재활성화하지 않는다. **닫는 증거**: 가상 시간 만료 경계·파생물/캐시 비노출·아카이브 실패 재시도·보존 검증 전 참조 유지·백업 복원 후 비부활·archive-only 수입·명시 조회. 아카이브 기한/파일 묶음/키 운영은 후속 확정. 원천 파일 삭제·자동 purge는 수행하지 않는다.

- [ ] **P08A-10 — 일일 암호화 백업·복원 검증·30일 순환 보관**. 환경변수 키 주입을 사용하고 운영 계층에서 매일 Asia/Seoul 03:00, 누락 시 다음 실행1회 보충한다. 기본 목적지는 `~/.local/share/airag/backups/<project-id>/`. 소비자 원장·발행 DB·아카이브·manifest/checkpoint를 일관된 세트로 백업하고 격리 임시 복원에서 DB 무결성과 연결을 검증한다. 새 세트 검증 성공 후에만30일 초과 AIRAG 소유 백업을 정리한다. **닫는 증거**: 누락/동시 실행·부분 실패·공간 부족·오키·재시작·복원 검증·보존 경계·주 아카이브 비삭제·최소 검증 백업 보호. 외부 복제·키 보관은 사용자 책임이며 예약은 core 밖에 둔다.

**첫 사용자 완료 기준 확정:** 검색·기억·운영까지. P08A-09/10 정책은01과 함께 구체화하고03~06 기반 뒤 구현한다. 09/10 검증을07에 포함한 뒤08에서 실제 선택 입력의 검색·결정/해결책 기억·아카이브·백업/복원을 시연해야 첫 단계 완료다. 자동 에이전트 주입과 P08B 프로젝트 코드 RAG는 후속 범위로 유지한다. 운영 환경의 상시 수집·예약은 아직 활성화하지 않았다. 별도 임시 키의 테스트 환경에서 실제 수집·검색·기억·암호화 백업과 복원 검증을 완료했다.
**2026-09-28 최종 실측:** 선택 원본의 완성 줄 prefix 28,156,963바이트를 기존 `captured_byte_limit` API로 고정해442건을 수집했다. 검색창28개(활성4·이전검색24), 기억337개, 실패/대기0건, 질의3개 각각5건 회수. 입력 전체 범위 처리는 완료했지만 `AMBIGUOUS_INJECTED_BLOCK` 감사gap1이므로 `coverage_complete=false`를 유지한다. 원문/고정 프로필은 그대로 두고 출력 예산에 맞춘 source-unit 분할로 남은3개 창 복구PASS. 기억106배치 추가 처리 후 `source_complete=true`; 사용자 확인/해결 검증이 필요한 후보는 자동 승인하지 않는다. 새 암호화 백업의 격리 복원 검증·선택 원본prefix 해시 불변PASS. 최종 오프라인691 passed·1 skipped·31 integration deselected, 별도 실제provider6 passed. 임시 테스트 키·고정입력 fixture의 근거이며 운영 배포나 모든 자료/CS 출처 지원 완료를 의미하지 않는다. 실행 근거: `.fable-team/airag/final-integration-result.json`. 실제 통합조회도PASS: 대화5건과 투어17출처/11그룹을 별도 순위로 반환하고 원본DB/사본검증을 확인했다. 백업시각·90일·프로젝트분리의 기대 근거를 회수하는3개 질의 모두 일치했다.

**2026-09-28 실제 입력 검증 중 발견·대응:** 선택 세션 전체 수집은430건·감사gap1까지 완료했으나, 모든 창이 검색 가능했던 것은 아니다. core 번역의 잘못된 JSON·미완결 출력으로8개 창이 실패했고 consumer가 `retryable=false`를 무시해37개 실패 시도가 누적됐다. 자동 반복은 중단하고 bridge는 불변 실패 응답을 재생하도록 수정했다(명시 core retry 복구는 유지). core 보강·그룹 요청에 strict JSON schema를 전달하며 기존 원문 범위·순서·완료 검증은 유지한다. 회귀693 PASS·24 skip; 기본 서버 미기동5건은 실제 endpoint 재검증6 PASS. 수정된 요청으로 실패 창을 명시 복구 중이며, 실제 입력 전체 완료로 판정하지 않는다. 검증 입력은 계속 늘어나는 현 세션이므로 기존 `captured_byte_limit` API를 사용한 고정 prefix fixture로 마감한다. 운영 원본과 환경 키는 변경/저장하지 않는다.

**2026-09-27 최신 통합 근거:** 독립 설치 CLI에서 실제 모델로 공개 대화 8건 수집·검색 창 1개·기억 2배치 처리와 질의 3개(각 4건 회수)를 확인했다. memory v4는 모델이 근거 ID만 선택하고 코드가 원문 인용을 구성한다. 동시 수집의 지연 독자 재현(제외 메타·정상 사건·명시 gap) 3건 통과. 실제 암호화 백업을 89일 시점에 생성하고 91일 시점에 격리 복원하여 대화와 고정 기억의 일반 검색 비부활을 확인했다. 실행 근거: `.fable-team/airag/final-integration-result.json`. 실제 선택 세션 검증은 별도 진행 중이며 임시 테스트 키만 사용한다. 아래 초기 구현 기록은 당시 범위이고, 운영 배포·P08A 전체 완료를 뜻하지 않는다.

**P08A-03 첫 구현 단위 완료(2026-09-27)**: 독립 패키지의 정규 사건 검증·바이트 기준 JSONL 파서·create-only 대화 변환을 구현했다. 신규 44개+기존 정규화 26개 총 70개 테스트 통과. [실행 근거](artifacts/p08a03-input-adapter-verification.json). grant/revoke·correction 적용·redaction·SQLCipher 원장·durable checkpoint·윈도우 관리·실제 rollout 수집·RAG 발행은 미구현이므로 P08A-03 전체 체크는 닫지 않는다. 다음 구현 단위는 암호화 원장과 마스킹/멱등 수신 checkpoint다.
**후속 원장 구현(2026-09-27)**: 위 미구현 중 redaction·SQLCipher 원장·사건/receipt/checkpoint 원자 commit·재수신·명시 거부기록 skip을 구현했다. 코드 DA K1/K2를 수정해 user/assistant 제한·source_ordinal 순서·opaque anchor를 적용했다. [원장 실행 근거](artifacts/p08a03-ledger-verification.json): 소비자96+기존26=122개 통과. 7차 코드 DA PASS(blocker 0)이며 native rollout/file integrity·권한 사건·correction·키 운영·봉인·윈도우·RAG 발행은 남아 있다. 실제 운영 DB는 만들지 않았고 시험용 DB만 pytest 임시 경로에서 사용했다.
v1.1 추가 완료 조건: P08A-07은 JSONL round-trip·기억 추출 없이 이력 검색·최근 N개 밖 검색·원문 인용·임베딩 장애 재시도·재오픈된 해결책 무효화를 필수 검증한다. P08A-08은 실제 승인된 대화/CS 채널에서 같은 검색과 기억·트러블슈팅 순환을 시연한다. CS 채널 미선정 시 CS 실연동 완료로 표시하지 않는다. v1.0 DA PASS와 v1.1 추가 요구의 검증 상태를 구분한다.
기존 투어는 T08~T13을 이어갈 수 있으며, 최종 P09 완성 판정에는 기존 P08과 새 P08A의
완료 근거를 각각 대조한다. P10 매거진은 그 최종 범위를 반영한다.

### P-08B — 프로젝트 문서·소스·테스트·스크립트 지식 (기획 v1.2)

근거: [D-015](DECISIONS.md#d-015), [프로젝트 지식 축](artifacts/data-lifecycle-plan.md#15-c축--프로젝트-문서코드테스트스크립트-rag-v12). 자체 프로젝트·선택한 오픈소스를 AIRAG로 검색하고 Serena/LSP와 연결하는 사용자 추가 요구다. P08A를 대체하지 않으며 이번 범위는 기획 등록이다.

- [ ] **P08B-01 저장소·언어·접근·snapshot 계약**. 첫 자체/OSS 저장소와 언어, root/ignore/비밀 정책, commit/dirty worktree 구분, parser·profile·LSP 버전 일치 기준 확정. **증거**: 파일 선택·분기 전환·symlink·권한·제외 사례와 DA. P08A 공통 ID/권한/원장 계약을 재사용한다.
- [ ] **P08B-02 프로젝트 변경 consumer**. initial manifest·안정 쓰기·git diff/watcher·rename/delete·재시작 대조를 외부 계층에 구현한다. **증거**: 변경분만 발행·누락 복구·실패 시 snapshot 가시성 제어. **선행**: 01, P08A-02/03 공통 기반.
- [ ] **P08B-03 문서·코드 구조 청킹·프로필**. 문서 Docling 재사용, 코드/테스트/스크립트의 원문·AST/심볼·행 범위와 긴 함수 분할을 보존한다. 코드 원문을 번역/재작성하지 않는 프로필을 별도 검증한다. **증거**: 원문 hash·anchor 왕복과 지원 언어/fallback 경계. 필요한 core 변경은 별도 등록·회귀. **선행**: 01·02.
- [ ] **P08B-04 프로젝트 RAG + Serena/LSP 연결**. 질문→문서/구현/테스트 검색→같은 버전의 정의/참조/호출 확인 경로를 제공한다. **증거**: 문서-코드-테스트 질의, stale LSP·LSP 미노출·비지원 언어의 명시적 제한. **선행**: 03.
- [ ] **P08B-05 변경·권한·규모 통합 검증**. rename/edit/delete/branch/dirty 경합·누락 이벤트·재시작·권한·색인비용/지연을 검증한다. **증거**: 과거 코드가 현재 답변에 섞이지 않음·허용 밖 근거 0·지원 범위와 측정치. **선행**: 02~04.
- [ ] **P08B-06 독립 설치·자체/OSS 실제 시연**. 프로젝트 코드·전역 설정 수정 없이 라이브러리/CLI와 선택적 심볼 adapter 연결을 재현한다. **증거**: 선정한 실제 저장소에서 문서/소스/테스트/스크립트 검색 및 변경 반영, 사용자 확인, 라이선스·출처·지원 한계. **선행**: 05.

### P-09 — 완성 판정·통합 자료

근거: [D-001](DECISIONS.md#d-001), [D-002](DECISIONS.md#d-002), [D-005](DECISIONS.md#d-005), [D-008](DECISIONS.md#d-008).

- [ ] **P09-01** 원래 범위(P01~P08), 자료/대화 확장(P08A), 프로젝트 지식 확장(P08B)의 구현·검증 결과를 각각 대조한다. 완료 조건: 승인된 요구마다 대응 코드/명령/실행 근거가 있고 각 범위의 완료 근거·미완료 항목·지원 한계를 별도로 기록한다. fixture 통과와 실제 connector/저장소 운영 완료를 구분하며 확장 지연으로 원 범위의 검증 근거를 가리거나 필수 항목을 조용히 제외하지 않는다.
- [ ] **P09-02** 소비 프로젝트용 통합 자료와 재현 가능한 버전을 준비한다. 완료 조건: 설치·키 전달·모델/profile 구성·요청/오류·재시도·백업 계약과 실행 예제가 현재 검증 버전에서 일치한다. 워처/스케줄 책임이 소비자에게 있음을 명시한다.
- [ ] **P09-03** 사용자 투어·필수 체크·통합 준비 결과로 완성을 판정하고 승인된 최종 완료 보고를 정리한다. 완료 조건: 해결되지 않은 필수 TODO가 없고, 실제 검증과 알려진 한계를 포함한 최종 통합 결과가 준비·전달된다. 지금의 부분 구현을 전체 완성으로 보고하지 않는다.

### P-10 — 완성 리뷰 매거진 발행

2026-09-13 사용자 추가 요청. P-08 사용자 투어와 P-09 완성 판정 뒤 수행한다.

- [ ] **P10-01** 완료 범위·핵심 동작·검증 결과·지원 한계·사용자 투어 피드백을 근거와 함께 정리한다.
- [ ] **P10-02** 완성 리뷰를 시각적 매거진으로 제작하고 읽기 흐름·도표·근거 링크를 검증한다.
- [ ] **P10-03** 검증된 매거진 산출물을 사용자에게 전달한다. 외부 게시 위치가 지정되면 해당 게시 범위에 따라 발행하고 전달 경로를 기록한다.

## 현재 검증 기록과 실행 환경

**P-07 최종 검증(2026-09-13)**: 오프라인 **464 passed, 1 skipped**, 실제 모델 **19 passed**,
전체 형식·상태 **12 passed**(154개 CLI 명령). 한영24질의 top1/top3 **100%**, exact anchor12개 확인,
실제 다중주제4unit→2group 분리 통과. 1000문서/5000청크의 로컬 합성벡터 검색p95 **0.147초**.
[완료 근거](artifacts/p07-completion-20260913.json)에 환경·명령·파일해시·지원 한계를 보존했다.
전체 제품 완성 판정은 아직 하지 않았으며 **P-08 사용자 투어 → P-09 완성 판정 → P-10 리뷰 매거진**이 남았다.

**P06-04 최종 검증(2026-09-11)**: `.venv/bin/python -m pytest tests/ -q --tb=short`
**403 passed, 1 skipped, 19 deselected**(125.98초). `tests/test_reindex_contract.py` 23개는
실제 SQLCipher DB에서 원본·리비전·메타데이터 보존, 처리 중 기존 검색 유지, 차원이 다른
공간으로의 원자 전환, 과거 manifest/원문 재현, 실패 후 retry, 후속 변경 뒤 요청 재생,
만료 claim 복구, 동시 수정, 오래된 job의 비차단을 확인한다. 별도 디렉터리에서 설치 CLI로
프로필 전환·검색·과거 manifest 조회·후속 수정 뒤 요청 재생도 검증했다. 제공자는 모의
HTTP/벡터이며 실제 GPU·모델 품질의 새 검증으로 취급하지 않는다. 스키마는 v5를 유지한다.

**P06-03 최종 검증(2026-09-11)**: `.venv/bin/python -m pytest tests/test_retry_contract.py -q --tb=short`
**20 passed**(16.11초). `.venv/bin/python -m pytest tests/ -q --tb=short`
**380 passed, 1 skipped, 19 deselected**(96.58초). 실제 SQLCipher DB·재개방·별도 연결의
동시 요청·설치 CLI의 별도 프로세스 실행을 확인했다. 제공자 성공 경로는 모의 HTTP
응답으로 검증했으며 실제 GPU·모델 품질의 새 검증으로 취급하지 않는다. 스키마는 v5를
유지한다. `latest_job`은 처리 대상 식별용이며 P06-05 전체 운영 진단의 완료 근거가 아니다.

**P-05 최종 검증(2026-09-10)**: 오프라인 **360 passed, 1 skipped, 19 deselected**
(92.06초). 실제 GPU 설치 CLI 테스트 **1 passed**(70.32초, 내부 12개 명령), synthetic
HTTP 제공자를 쓴 별도 CLI 테스트도 통과했다. 실제 확장은 5개 청크에서 구조/참조/의미
연결을 반환했고 10,757토큰/48,950바이트의 근거 payload를 보존했다. v5 스키마의
원자 발행·이전 데이터 보존/이관·stale 거부·동시 발행 스냅숏·전체 JSON 예산을 검증했다.
[상세 기록](artifacts/p05-completion.json) 및 [실제 응답](artifacts/p05-live-validation.json) 참고.


**P-04 최종 검증(2026-09-10)**: 전체 오프라인 **326 passed, 1 skipped**(59.18초),
실제 GPU **9 passed**(118.56초), 설치 CLI **10개 명령 통과**. 최종 설정 타입 가드도
별도로 재검증했다. 배포 wheel에 Python 문서/이미지 모듈과 HWP Java 소스가 실제로
포함되고 현재 소스와 일치하는지 확인했다. 새 GPU 테스트는
`tests/test_documents_live.py`에 남겼다. 모델·fixture 준비 조건은
[완료 기록](artifacts/p04-completion.json)에 있다.

지원 범위: PDF/DOCX/XLSX, 일반 HWP5/HWPX, PNG/JPEG/BMP/TIFF의 명시적 OCR/비전 모드.
문서에 포함된 그림 리소스는 추출·보존하며 자동으로 별도 비전 처리를 실행하지 않는다.
수식 재계산, array/data-table 수식, 보호/배포용 HWP, DOCX 비트맵 이외 DrawingML의
자동 렌더링은 지원하지 않는다. HWP/HWPX 앵커는 섹션·문단·표 기준이다.

**최종 오프라인 검증(2026-09-10)**: 아키텍트 독립 실행 `294 passed, 1 skipped, 9 deselected`
(23.43초). 실제 SQLCipher/FTS5/vec0, 별도 프로세스 설치 CLI와 모의 HTTP 제공자,
동시 발행 중 검색 스냅숏, 응답 재현, 삭제·복구를 포함한다. 실제 GPU 증거와 구분한다.

**실제 GPU 검증(2026-09-10, 인증 복구 후)**: `tests/test_pipeline_live.py` 통과.
설치 CLI는 등록 재시도 응답 일치, 수정 후 새 리비전, 과거 원본 바이트/manifest 보존,
삭제 후 검색 제외 및 복구 후 새 세대 검색까지 통과했다. 혼합 문서는 실제 LLM이
4개 입력 단위를 고양이/날씨/커피의 3그룹으로 나눴으며 커피 질문의 1위가 커피 원문이었다.
이번 검증에서 런타임 코드 수정은 필요하지 않았다. 기존 오프라인 294개 통과 기록과
구분해 [실측 JSON](artifacts/p03-live-gpu-verification.json)에 보존한다.

**현재 연결**: LLM `http://127.0.0.1:18002/v1`, embedding `http://127.0.0.1:18811/v1`.
기존 8002/18810 리스너는 보존했다. GPU/VM 재시작이나 IAM 변경 없이 로컬 IAP 터널만
두 개 열었다. `AIRAG_EMBED_ENDPOINT`/`AIRAG_LLM_ENDPOINT`로 현재 포트를 지정한다.
테스트의 `integration-probe-unverified-weights-2026-09-10`은 가중치 미확인 표시이며
운영용 모델 revision 핀이나 가중치 해시가 아니다.

**실행 상태(2026-09-13)**: P06-05~07·P03-06·P-07 구현·검증을 완료했다. 사용자 지정 종료 지점인 P-08 직전에서 준비 완료. P-10 완성 리뷰 매거진 발행은 후속 단계로 추가했다.

## 파이프라인 (요약, 근거 [D-001](DECISIONS.md#d-001)~[D-003](DECISIONS.md#d-003))

```
원본 --[Docling 또는 HWP/HWPX 별도 어댑터·경량 대화 어댑터]--> 표준 번들(MD+구조/앵커)
  --[HybridChunker, 구조화 표현 입력]--> 청크 --[임베딩/FTS 발행]--> 색인
  --[BM25+벡터+RRF]--> 검색 --[예산 있는 구조/의미 확장]--> 근거(EvidenceBundle, 원본 반환 포함)
```

외부 트리거(신규/변경/삭제 감지, 스케줄)는 core 밖 소비 프로젝트에 있다([D-002](DECISIONS.md#d-002)) —
core 안에 `watch` 명령이나 폴링 테이블을 두지 않는다. OCR/비전 해석/임베딩은 서로
다른 층으로 구분해 표시한다([D-003](DECISIONS.md#d-003)). 상위 에이전트가 근거를 받아
최종 답변/산출물을 생성한다 — core는 그 생성을 하지 않는다([D-001](DECISIONS.md#d-001)).

## 명령 어휘 (제안, 근거 [D-002](DECISIONS.md#d-002)/[D-006](DECISIONS.md#d-006))

`init`, `add`(신규), `update`(기존 갱신), `delete`, `search`, `expand`,
`fetch source/chunk/original/manifest`, `manage status/list/show/retry/reindex/
restore/backup/doctor/verify`. 하나의 응답 envelope: `{schema_version, request_id,
ok, command, data, error}`. `add`의 입력은 파일/본문/소비자 열거 배치로 한정 —
디렉터리 자동 탐색 없음. `watch`, `manage sync`, `manage pause/resume`은 없음([D-002](DECISIONS.md#d-002)/[D-006](DECISIONS.md#d-006)).
정확한 플래그·스키마 세부값은 동결되지 않은 제안이다.

현재 CLI에는 `manage profile --config`로 불변 프로필 등록, `add/update --profile-key`,
`search --profile-key`, `fetch chunk/source/manifest`가 추가됐다. 프로필을 주지 않은
add/update는 기존처럼 honest stored_pending이며 자동 모델 선택은 없다. 배치의 각
항목은 자체 `profile_key`를 가질 수 있다. `fetch source`는 저장된 정규화 산출물,
`fetch original`은 선택한 리비전의 원본, `fetch manifest`는 historical 표시가 있는
과거 검색 결과다. `expand`와 `fetch expansion`, `manage retry·reindex·backup·restore-backup`과 운영 진단은 구현·검증됐다. 외부 트리거·시간순 로그·메모리/아카이브 운영 계층은 별도 기획 대상이다.

확장 명령은 `search --expand`(같은 읽기 스냅숏), `expand --manifest-id`(현재와 일치하는
검색 스냅숏), `fetch expansion --expansion-id`(과거 결과 재현)다. `--max-depth`,
`--max-chunks`, `--max-tokens`, `--max-bytes`, `--max-edges`와 선택적
`--include-semantic`/`--semantic-neighbors`/`--min-similarity`를 제공한다.
검색의 반복 `--source-key`/`--media-type` 필터는 확장에서도 그대로 유지된다.
`--relation`으로 구조/명시적 참조 종류를 선택할 수 있다. 토큰·바이트 예산은 wrapper를
제외한 `evidence` 전체의 canonical compact JSON이며, 로컬의 캡처된 토크나이저를 쓴다.

검색의 cosine 경로는 현재 정확한 전수 비교(O(N))다. BM25와 벡터의 후보 범위를
순위 제한 전에 적용하고 동점은 chunk ID로 정한다. ANN 성능이나 한국어 lexical 품질을
검증했다고 주장하지 않는다. 영어 전처리 설정에서는 query도 같은 LLM 설정으로 번역한다.

## 완성 검증 범위

아래 범위 중 이미 실행한 항목과 남은 항목은 위 TODO에서 구분한다.

암호화 DB 개폐(오키 거부 포함), 신규 등록·중복 재등록 no-op, 갱신 시 새 리비전과
구 manifest 보존, 빈/긴/한글 텍스트, 대화 스레드 보존, PDF/DOCX 앵커, 글자 있는/없는
이미지, 소비자발 add/update/delete 반영, 삭제 후 복구, 접근 불가와 삭제 구분, 모델
실패/차원 불일치, 모델 리비전 마이그레이션, 동시 실행 시 중복 발행 없음, 구조/의미
확장의 순환·예산 보장, 선택적 원본 포함, manifest 재현, 백업 복원, CLI/API 계약
일관성, 별도 샘플 프로젝트에서의 클린 설치·소비.

**매거진 QA(58/58, [D-004](DECISIONS.md#d-004))는 이 시나리오들의 대체 증거가 아니다**
— HTML 데모 검사일 뿐이다.

## 남은 검증·지원 한계

- **P03-06 완료 범위**: 실행 컨테이너의 제공 경로·실제 가중치 SHA·HF cache revision을 확인했다. GPU 메모리의 암호학적 attestation은 아니며 이전 probe 표기를 운영 revision으로 승격하지 않았다.
- **P07-04/P07-05 완료 범위**: 사전 고정된 합성12문서/한영24질의와 로컬1000문서/5000청크 범위에서 품질·지연·자원을 측정했다. 임의의 사용자 자료나 더 큰 규모에 대한 보장은 아니며 P-08 사용자 투어가 남아 있다.
- P-04는 실제 디지털/스캔 혼합 PDF와 한국어 OCR 비교를 검증했다. 모든 혼합 페이지/복잡한 배치에서의 정확도는 보장하지 않는다.
- XLSX 시트/셀·병합·일반 수식/캐시 범위를 현재 backend로 확인했다. 재계산과 복잡한 수식은 지원 범위 밖이다.
- HWP/HWPX는 실제 본문·표·그림 리소스 추출을 확인했다. 렌더링 좌표를 추측하지 않으며, 지원하지 않는 컨트롤은 경고에 드러낸다.
- 임시 변환 파일과 저장 암호화를 구분한다. Docling Tesseract의 정상/예외 정리와 별개로 강제 종료 잔존 가능성은 [완료 기록](artifacts/p04-completion.json)에 명시했다.

## 관련 산출물

- [P-05 완료·계약·한계](artifacts/p05-completion.json)
- [P-05 실제 GPU CLI 검증](artifacts/p05-live-validation.json)
- [P-05 패키지 구성 확인](artifacts/p05-package-verification.json)

- [P-04 완료·환경·지원 범위](artifacts/p04-completion.json)
- [P-04 실제 GPU 9개 사례](artifacts/p04-live-validation.json)
- [P-04 설치 CLI 검증](artifacts/p04-cli-validation.json)
- [한국어 OCR 비교](artifacts/p04-ocr-comparison.json)
- [배포 wheel 확인](artifacts/p04-package-verification.json)

- [`artifacts/2026-09-09-rag-visual-atlas.html`](artifacts/2026-09-09-rag-visual-atlas.html) — 기획 시각화(예시 데이터, [D-004](DECISIONS.md#d-004))
- [`artifacts/visual-atlas-qa-summary.json`](artifacts/visual-atlas-qa-summary.json) — 매거진 QA 요약(엔진 검증 아님)
- [`artifacts/research-notes.md`](artifacts/research-notes.md) — Docling/HWP/OCR 1차 출처([D-003](DECISIONS.md#d-003)/[D-007](DECISIONS.md#d-007))
- [`artifacts/previous-planning/`](artifacts/previous-planning/) — 이전 세분화 문서 이력([D-008](DECISIONS.md#d-008))

**2026-09-28 사용자 투어 확인:** 사용자가 대화 검색·백업의 CLI 노트북 투어 완료를 확인했다. 이후 투어는 `.fable-team/bin/tour/`에 번호별로 추가하고 `notebook.py`의 설명→실행→결과·해설→다음 셀 방식을 공유한다. 01 대화 투어는 사용자 확인 완료, 02 운영 준비 투어는 정책·환경 키·모델 연결 점검으로 진행한다. 운영 키의 미준비는 보류로 표시하며 운영 서비스 가동과 구분한다.

**2026-09-28 투어02 사용자 확인:** 운영 정책·키 형식/분리·모델 연결 점검 5셀 완료, `configuration_ready` 기록 확인. 키 값은 저장·수신하지 않았다. 다음 투어03은 구성안 검토→키 재입력→지속 경로의 CLI 설치→설정 준비→운영 암호화 저장소 초기화→상태 확인이다. 별도 임시 경로에서 설치·키 누락 차단·초기화·재실행과 원본 보존을 검증했다. 운영 경로 생성은 사용자가 해당 셀을 실행할 때 수행하며 수집은 후속 투어로 분리한다.

**2026-09-28 투어03 사용자 확인:** 전용 실행 환경 설치·운영 설정·암호화 저장소 초기화 6셀 완료, 검색/기억/실패/대기0 및 기존문서17개 연결 확인. 다음 투어04는 기존 승인 세션의 첫 유효대화4개까지만 prefix/hash를 고정해 수집하고 같은 범위의 재실행을 확인한다. 실제 입력 사전검사4개/254203바이트 및 별도 합성 원장4건 저장·재실행0건·변조거부를 검증했다. 모델 호출/검색 색인은05 투어로 분리하며 오류 자동 건너뛰기는 비활성이다.

**2026-09-28 투어04 사용자 확인:** 첫 유효대화4개 범위 수집 및 같은 범위 재실행의 중복 방지 확인 완료. 다음05는 원장의 offset/event count와04 prefix를 대조한 뒤 기존 public bridge로 해당 범위만 색인·검색한다. 추가수집/기억추출/전체투어문서통합조회는 실행하지 않는다. 별도 원장에서 실제 core+fixture 임베딩으로 발행1창·검색1건·재색인0작업·신규수집0 및 범위확대거부를 검증했다. 실제 모델 endpoint 두 개의 모델 목록 정상응답도 확인했다. 운영 색인은 사용자가05 셀을 실행할 때 수행한다.

**2026-09-28 투어05 사용자 확인:** 운영 범위의 첫 색인·질문 검색·재실행 및 상태 확인 완료(`first_index_and_search_verified`). 다음06은 동일 범위에서 기억 후보를 추출하고 자동반영/확인대기/검증대기를 구분한다. 별도 합성 원장에서 결정1 자동반영·선호1 확인대기·해결책1 미검증 및 재실행의 모델호출/추가사건0을 검증했다. 후보 내용이나 수를 미리 보장하지 않으며, 실제 기록에 기억할 내용이 없으면0으로 표시한다. 공통 진행기는 미완료 배치를 같은 셀에서 이어가도록 지원한다. 운영 후보 확인 승인은 이번 투어에 포함하지 않는다.

**2026-09-28 투어06 사용자 확인:** 기억 후보 추출·자동/확인대기/검증대기 분류·중복방지 재실행 완료(`memory_selection_verified`). 사용자 승인으로 1Password 서비스 계정의 AIRAG 키3개를 투어 프로세스 환경에 자동 전달하도록 연결했고, 키 누락 시 다음 셀 진입을 차단한다. 다음07은 운영 백업 생성→격리 복원 검증→별도 프로세스 재열기와 보호 데이터 해시 비교다. 별도 암호화 테스트 원장에서 백업생성/검증/백업바이트불변/보호데이터불변을 확인했다. 운영 DB 덮어쓰기·자동 수집/예약 실행 시작은 포함하지 않는다.

**2026-09-28 투어07 사용자 확인:** 암호화 백업·격리 복원·재열기 및 보호 데이터 보존 확인 완료(`backup_restore_and_reopen_verified`). 다음08은 운영 DB를 읽고 남은 승인 소스의 완성된 줄을 분류/마스킹 사전검사한다. 실제 읽기 전용 검사에서 남은32789671바이트·공개대화후보555·거부1(AMBIGUOUS_INJECTED_BLOCK)을 확인했다. 본문 미출력·partial-tail 분리·기존 prefix 및 source identity/scope 대조를 검증했다. 자동 건너뛰기 승인이나 대량 색인/상시 서비스 시작은 수행하지 않는다.

**2026-09-28 투어08 사용자 확인:** 남은 입력 검사·자동 실행 정책 점검 완료(`operational_preflight_rejection_review`). 기록된 prefix끝33131482바이트와 단일AMBIGUOUS_INJECTED_BLOCK의 위치/해시를 다시 검증했다. 다음09는 사용자가 직접 검토 승인한 snapshot에만 한정한다. 정상 구간은 allow_gaps=false, 승인된 한 줄에만 일시적 true를 사용하고 반환된 gap의 위치/해시/사유를 대조한다. 전역설정은false 유지, 모델호출 없음, 최대8MiB씩 수집한다. 합성 원장에서 승인 없는 실행/승인 불일치 거부·단일허용·이후append 미수집·재실행0을 확인했다. 실제 승인기록/운영수집은 사용자가09 셀에서 실행할 때 수행한다.

**2026-09-28 투어09 사용자 확인:** 승인한 snapshot 수집 완료, 검색가능1/발행대기29/실패0/감사gap1 확인(`reviewed_snapshot_collected`). 다음10은 승인 digest·완료 offset·수집 record count를 대조하고 대기창을 한 개씩 기존 bridge로 발행한다. Enter는 한 창, 전체실행은 실패 전까지 연속 처리하며 15초마다 경과시간을 표시한다. 창별 최대900초 제한과 중단 시 완료 창 보존/재시작 동작은 기존 core claim·atomic publication 경계를 사용한다. 별도 원장에서 단일창발행·검색·재실행0작업·추가수집0 및 UI 연속처리 실패중단/heartbeat/timeout을 검증했다. 실제 운영 발행은 투어 실행 때 시작한다.

**2026-09-28 처리 성능 개선·투어10 중단 후 재개 준비:** 사용자 지시에 따라 기존 실행 중단을 확인했고 완료22창과 중단 작업1건을 보존했다. 동일 프로필에서 독립 semantic window를 최대2개 병렬 계산하고 cache/lease/DB 쓰기는 호출 스레드에 유지한다. 모델리비전·프로필·입력/문맥에 묶인 결과를 projection SQLCipher DB의 비권위 캐시에 보관하며 손상/불일치는 재계산한다. 실제 공개 입력 ABBA 비교에서 순차평균36.035초·병렬18.219초(1.978배), 재사용 시 생성/토큰확인 요청0회. 전체회귀697 PASS 및 추가 processing8/병렬pipeline·API21/독립설치cache5묶음 검증 통과. 새 투어는 실제 구간시간·요청수·결과캐시·서버KV캐시를 표시한다. 원문우선검색/보강선택 프로필 전환은 이번 증분에 포함하지 않았으며 운영 재색인은 사용자 투어 실행 전까지 재개하지 않았다.

**2026-09-28 투어10 사용자 확인·11 준비:** 검색 창30/대기0/실패0·사건573·기억2 확인. 승인 snapshot 기억 추출 투어11은 기존 완료 배치를 재사용하며 배치별 순차 처리·전체실행·오류중단을 제공한다. 격리 합성 원장에서 2배치 처리·재실행 모델호출0·신규사건0·확인/검증대기 유지·승인불일치 거부를 검증했다. 운영 추출은 사용자 셀 실행 시 시작하며 추가 수집·자동 후보승인은 하지 않는다. 기존 감사gap1은 유지한다.

**2026-09-28 투어11 중단 후 기억 처리 개선:** 실제 저장소는 완료142/전체151배치·기억386·검색30·남은9(중단 pending1 포함)로 확인했다. 기존4096바이트/4메시지 배치와 lineage를 유지하고 모델 요청만 최대2개 병렬화하며 SQL/검증/반영은 호출 스레드에 둔다. 명시 복구 셀은 runtime 배타잠금 아래 정확한 pending 집합·미저장 결과만 실패/재시도 상태로 바꾸고 완료분은 보존한다. 기본 단일배치 API의 ambiguous pending 자동재발행 금지는 유지한다. 진행률 및 최근 실측 ETA, timeout 별도 코드를 추가했다. consumer 전체206 PASS·설치 환경 격리 투어(잠금 거부/복구/재실행0호출/추가수집0/보류유지/승인불일치 거부) PASS. 공개 합성 ABBA는 순차5.5345초·병렬3.5805초(1.546배); 긴 실제 대화의 속도 보장은 아니다. 운영 복구/추출은 수정 투어 셀 실행 전까지 하지 않았다. 근거: `.fable-team/airag/memory-optimization-result.json`.

**2026-09-28 투어11 실제 timeout 진단·혼잡 진입 제한:** 142/143배치가120초 timeout. 같은 실패 입력은 서버 idle 상태에서9.494초/5.889초 및 후보4/3 검증 성공(진단용, 운영 기억 미저장). 실패시간대 공유vLLM은 실행4~6/대기최대4·생성약1~4tok/s·prefix hit약66%. GPU는L4 24GB, model_len24576/max_num_seqs128/max_num_batched_tokens2496. 투어에 모델별 실행/대기 메트릭 진입검사를 추가해 혼잡이면 새배치 생성/추론 없이 즉시 중단하며 메트릭 미확인도 거부한다. 설치 환경 합성 busy gate 무변경·재시작/재실행 보존 검증 PASS. 시작 이후 들어오는 다른 클라이언트와의 자원경합까지 보장하지 않으며 공유 서버 설정은 변경하지 않았다.

**2026-09-28 GO 후 사용자 전체실행·투어11 완료:** KST19:16:49.939852~19:17:45.756022에 남은9배치(최대2동시) 전부 성공, 요청구간55.816초·평균6.227/최대10.116초. 응답usage는 입력5495/출력1475/캐시입력1536토큰(누락0). 저장소151/151완료·대기실패0·기억411·검색30이며 완료분 재실행의 신규모델요청0도 확인했다. 이번 재현은 명시적 동시실험에만 혼잡gate를 우회했고 일반투어의 gate는 유지한다. 서버표본 실행0~2/대기0, timeout미재현. master에 요청시각·로그 전달했으며 M6 실제중첩 대조는 아직 미확인으로 공동부하 검증완료를 주장하지 않는다. 근거: `.fable-team/airag/traces/airag-m6-20260928T095627Z.result.json`.

**2026-09-28 투어12 합성 연속 부하(수용 기록 없음):** 공개 합성 대화로 동시2·3분 2회(44/44·183.081초, 44/44·180.834초)와 동시4 1회(77/77·187.361초)를 실행해 모두 실패0·운영 DB 미개방(`operational_db_opened:false`)을 확인했다. 비교 파일 기준 평균지연 8.183초(동시2)/9.443초(동시4), p95 8.361/19.638초. 12-load 투어의 사용자 수용 기록은 없다.

**2026-09-28 투어13 멀티 인스턴스 부하 1단계 중단 → 2026-10-01 사용자 보류:** 1프로세스·최대2요청 단계만 실행(230.778초)해 제출44·성공42·실패0·취소2에서 `REQUEST_LATENCY_EXCEEDED`로 중단됐고 2·4·8프로세스 단계는 실행하지 않았다. 이는 설정한 중단 기준 도달이며 하드웨어 용량 한계의 증명이 아니다(M6 발화 시각과 별도 대조). 2026-10-01 사용자 결정으로 멀티 부하 사다리(1·2·4·8)·§5.3 worker gateway 용량 실험·P08B 코드 RAG는 보류한다.

**2026-10-01 형상 보존·투어11 수용·회귀·독립 DA:** AIRAG 코드·문서를 `feature/rag-transplant`에 최초 커밋(`bd5386a`)했다(push 별도 승인). 투어11 사용자 수용(151/151·창30·기억411·7셀 완료). 09-28 마지막 수정(18:26~18:29) 뒤 전체 회귀가 없어 오프라인 전체 회귀를 다시 실행했다: consumer 206 passed, core 502 passed·1 skipped·31 deselected(integration 31건 deselect, 목록 `artifacts/regression-20261001-deselected.txt`). 09-28 변경분(`processing.py`·`memory.py`·`runtime.py`)의 GPT-6.1 Sol 독립 DA r1은 REJECT(blocker1·major3): 아카이브 2묶음부터 백업·일일 실행 실패(B1), 과거 백업 재검증 실패(M1), 등록 소스 일부 수집 실패인데 coverage 완료 표시(M2), 첫 미검증 해결책이 뒤 배치 검증을 가림(M3). 수정(`3695683`) 뒤 r2는 PASS(blocker0)이나 major2 잔존: 구버전 백업 verify 거부(R2-M1), 격리 복원이 원본 archive 파일에 의존(R2-M2). 수정(`6634a0b`) 뒤 r3 PASS(blocker0·major0·minor0), 한계: 구버전 snapshot 은 receipt 암호문 해시 동일성이 보장되지 않아 manifest 해시와 논리 bundle 검사로 검증한다. clean HEAD `c924d32` 회귀 consumer 212 passed·core 502 passed·1 skipped·31 deselected. 판정·로그: `artifacts/da-20261001-sol-r{1,2,3}.md`·`regression-20261001-*.log`·`nano-20261001-r{1,2}-result.md`.
