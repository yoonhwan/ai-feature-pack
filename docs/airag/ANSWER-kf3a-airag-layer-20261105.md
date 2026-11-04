# K-F3a × airag 협의 답 — 물을 것 3에 대한 airag 입장

골좌표: 1 — 슈퍼브레인 도메인 테넌트 시스템 운영 런타임
골의 어느 축: 운영자가 md·csv·pdf 를 올리면 사람 손 없이 검색 재료가 된다. 그 형식 추출을 airag 의 기존 레이어와 맞추는 협의다(판정 4081 «우리 레이어 다있는데 airag 팀 열어서 협의»).
쓴 좌석: aifp-airag-master-claude#10 · 2026-11-05 · 발주 #3523 (byz-planner-master-claude#230) · 사람 «1-1 팀복구 증류해서 진행»(11-05 08:15) · 문서만(코드 0 · BYZ 리포 쓰기 0 · DA 0 · 새 나노 0)
질문 원본: BYZ origin/main `design/teams/knowledge/CONSULT-kf3a-airag-layer-20261105.md` §3
airag 코드 기준: ai-feature-pack `feature/rag-transplant` @ 677264a6fe (remote 0 · 로컬 가지에만 있음) · 패키지 `feature-pack/rag` · 아래 줄 번호는 이 sha 기준(`ci outline`·`rg` 로 찾음)

## 0. 결론 3줄

1. 판은 **ⓑ 추출 모듈만 옮겨 심기**를 추천한다. 패키지 의존(ⓐ)은 Python 3.13 고정과 sqlcipher3 의존 때문에 BYZ 에 설치가 안 된다. 서비스(ⓒ)는 airag 에 서버 모드가 없어 새 배포가 생긴다.
2. 형식 추출의 고침 주인은 airag 이고, BYZ 는 csv·415 입구·이어 하기·revision 칸을 맡는다는 나눔에 동의한다. 청크는 **BYZ 600자 규칙을 유지**하고, airag 에서는 추출 텍스트와 쪽·영역 위치만 받는 것을 추천한다.
3. 모델은 **Job 이미지에 구워 넣는다**(airag 는 실행 중 다운로드를 막아 둠). PDF 필요 모델은 약 506MB, tesseract 언어 데이터는 15.5MB 이다. 시험 표본 4개가 로컬에서 15초에 끝나 70초 상한 안에 든다.

## 1. 재사용 계약 · 판

### 답

| 안 | airag 판단 | 근거 |
|---|---|---|
| ⓐ `ai-feature-rag` 패키지 의존 | 안 됨(지금) | `feature-pack/rag/pyproject.toml` `requires-python = ">=3.13,<3.14"` 라서 BYZ 3.11 에 설치 자체가 거부된다. 필수 의존에 `sqlcipher3==0.6.2`·`sqlite-vec` 가 있어 추출만 쓰려 해도 암호 DB 의존이 따라온다. 가지가 remote 에 없어 고정할 판(tag)도 없다. |
| ⓑ 추출 모듈만 옮겨 심기 | **추천** | 추출 경로는 docling 계열만 쓴다. `normalize.py:45` 는 `docling_core` 만, `document_adapters.py:183-219` 는 `docling` 만 import 한다. docling 2.126.0·docling-core 2.95.0 의 Requires-Python 은 `>=3.10,<4.0` 이다(설치본 metadata 실측). 즉 3.13 고정은 airag 패키지 전체의 선택이고 추출 코드의 제약이 아니다. |
| ⓒ airag 서비스 호출 | 안 함 | airag 는 로컬 암호 DB 위의 라이브러리·CLI 다(`pyproject.toml` `[project.scripts] ai-rag`). 추출만 내주는 서버 입구가 없다. 새로 만들면 배포·인증·운영 주인이 하나 더 생긴다. |

### 옮겨 심을 범위 (출처 sha 677264a6fe 고정)

| 파일 | 줄 | 옮길 때 끊을 의존 |
|---|---|---|
| `src/airag/normalize.py` | `:259-268` `build_document`, `:131` `_build_markdown`, `:97` `_build_plain_text` | `airag._json.strict_json_loads`(conversation 형식에만 씀) |
| `src/airag/document_adapters.py` | `:31-38` 형식·기본값, `:52` `canonical_config`, `:183-219` `_converter`, `:222-303` `_office_pdf`, `:498-514` `build_document` | `:23` `from airag import store` 는 `store.ApiError`(오류 꼴)와 `store.MAX_CONTENT_BYTES`(`store.py:109` · 50MB) 두 개만 쓴다. BYZ 오류 class 와 상수로 바꾸면 끊긴다. |
| `src/airag/image_adapters.py` | `:99` `build_image` | `:12` `llm_enrichment`(vision 추론 · LLM 호출). OCR 만 쓰면 `image_mode='ocr'` 로 이 길을 안 탄다. image 는 `대기/loom-file-formats-ocr` 카드에서 따로 본다. |

hwp·hwpx(`:402` `_hwpx`, `:472` `_hwp`)는 JVM bridge(`HwpBridge.java`·`hwp_classpath`·`hwp_sha256`)가 필요하다. 이미지에 JVM 이 하나 더 실리므로 `대기/loom-file-formats-office` 카드에서 따로 정하기를 추천한다.

### Python 3.13 ↔ BYZ 3.11

- 옮길 세 파일은 모두 `from __future__ import annotations` 를 쓴다. 3.12+ 전용 문법(PEP 695 `type X =`·`def f[T]`)은 `src/airag` 전체에 0건이다(`rg` 실측).
- [확인 필요: 3.11 인터프리터로 위 세 파일 import·시험 실행 0회] — 옮겨 심는 나노가 첫 시험으로 확인한다.

### pdf 쪽 단위 호출(이어 하기 cursor)

- Docling 은 쪽 범위를 받는다. `DocumentConverter.convert(..., page_range=(start, end))` 이다(설치본 signature 실측).
- airag 는 지금 그 값을 넘기지 않는다. `_office_pdf:255-258` 은 `max_num_pages` 만 넘기고, `:232` 는 전체 쪽 수가 `max_pages`(200)를 넘으면 거절한다.
- 그래서 cursor 는 옮겨 심은 쪽에서 `page_range` 인자 하나를 더하면 열린다. 이 고침은 airag 원본에도 같은 꼴로 받는다(역수입 · 고침 주인 airag).
- 주의: 쪽을 1장씩 자르면 쪽을 넘는 표·heading 맥락이 끊긴다. 단위는 «쪽 N장 묶음»으로 두고 N 은 시간 상한(airag 기본 `timeout_s 120` · `document_adapters.py:37`)에 맞춰 정하기를 권한다.

## 2. 소유 · 청크

### 소유 나눔

| 일 | 주인 | 근거·메모 |
|---|---|---|
| pdf·docx·xlsx·hwp·hwpx·image 형식 추출 로직 | airag(원본) | `document_adapters.py:31` `SUPPORTED`. BYZ 사본의 고침은 airag 원본에 먼저 넣고 sha 를 올려 다시 옮긴다. |
| md·평문 | airag 레이어 재사용 권장 | `normalize.py:131` `_build_markdown` 이 ATX heading·fenced code 를 이미 처리한다. WIP `_markdown_unit` 과 뜻이 같다. |
| csv | BYZ | airag 에 csv 0(xlsx 만 Docling). |
| 업로드 입구 형식 문(415) | BYZ | airag 는 Docling 이 판별한 형식과 선언 형식이 다르면 `MEDIA_TYPE_MISMATCH` 로 거절한다(`document_adapters.py:261-263`). 이건 변환 «뒤» 검사다. 원본 저장 «전» 서명 대조는 BYZ 몫이 맞다. |
| 이어 하기 cursor · lease | BYZ | §1 의 `page_range` 인자만 airag 쪽 고침이다. |
| revision 추출 칸 | BYZ | S3 `loom_revisions` 이름을 따른다. |

### 청크: BYZ 600자 유지를 추천

- airag 청커는 token 기준이다. `chunking.py:83-84` `HybridChunker(tokenizer=HuggingFaceTokenizer…)` 이고, tokenizer 는 고정 revision 으로 HF 에서 받는다(`chunking.py:55-71`). 임베딩 모델 tokenizer 에 맞춘 설계라서 BYZ 임베딩 정체성(`chunk=max600`)과 다르다.
- 바꾸면 전 묶음 재임베딩 1회가 든다. 그 판단은 이미 `대기/loom-file-chunking-by-format` 카드 몫이다. 이 협의에서 함께 정하지 않기를 권한다.
- 받을 것: `NormalizedDocument`(`document_adapters.py:303`) 의 DoclingDocument 텍스트와 anchor. anchor 에는 쪽 번호가 든 `provenance` 와 `text_origin`(extracted·ocr·extracted_or_ocr) 이 있다(`:280-292`). BYZ 600자 조각에 쪽 번호를 붙이는 데 충분하다.
- heading 맥락은 DoclingDocument heading 으로 `[A › B]` 접두를 만들면 WIP 와 같은 뜻이 된다. airag 의 `contextualize()` 는 쓰지 않는다.

## 3. 시험 자리 · Job 이미지

### 모델·데이터 크기 (로컬 `.venv/share/docling-models` · 11-05 `du` 실측)

| 묶음 | 크기 | PDF + tesseract 경로에 필요 |
|---|---|---|
| `docling-project--docling-models`(표 구조) | 342MB | 필요 |
| `docling-project--docling-layout-heron`(layout) | 164MB | 필요 |
| `docling-project--docling-layout-heron-onnx` | 163MB | 불필요(같은 layout 의 onnx 판) |
| `EasyOcr` | 109MB | 불필요(`ocr_engine='tesseract'` 기본 · `:34`) |
| `RapidOcr` | 61MB | 불필요 |
| tesseract `kor`·`eng`·`osd` traineddata | 1.6 + 3.9 + 10MB = 15.5MB | 필요(`:104-110` 이 파일 지문을 잡음) |

- 필요 합계는 약 506MB + 15.5MB 이다. [확인 필요: 변환 1회 중 실제로 연 파일 목록 측정 0 — 표 안 판정은 디렉터리 이름 기준]
- docling 은 torch 를 끌고 온다(로컬 torch 2.14.0 · `.venv` 전체 2.0GB · macOS arm64). [확인 필요: linux CPU 판 이미지 크기·Job 기동 시간 측정 0]

### 이미지에 싣는 법: 구워 넣기 추천

- airag 는 실행 중 모델 다운로드를 막는다. `_converter:204-210` 은 `artifacts_path` 가 실재하는 디렉터리가 아니면 거절하고, `enable_remote_services=False`·`allow_external_plugins=False` 로 고정한다. `pdf_artifacts_path` 가 없으면 `PDF_MODELS_REQUIRED` 다(`:225-226`).
- 그래서 Job 이미지 빌드 때 모델을 고정 경로에 넣고, 그 경로를 config 로 넘긴다. 실행 시 GCS 에서 받는 방식은 위 계약과 맞지 않는다.
- 모델 지문은 `canonical_config` 가 잡는다(`:103-110` · `model_fingerprints`). 이미지를 바꿔 모델이 바뀌면 `DOCUMENT_PROFILE_MISMATCH` 로 드러난다(`:96-97`).

### 시험 자리

- ai-feature-pack 에는 CI 가 없다. `.github/workflows` 가 origin/main·HEAD 둘 다 0 파일이다(`git ls-tree` 실측). airag 시험은 지금 로컬에서만 돈다.
- 그래서 옮겨 심은 추출 시험은 **BYZ CI** 에서 돌리기를 추천한다. airag 시험(`tests/test_document_adapters.py`)은 원본 고침 때 airag 로컬에서 돈다.
- 모델이 없으면 airag 시험은 skip 한다(`tests/test_document_adapters.py:81-84` `AIRAG_DOCLING_MODELS`). BYZ CI 는 skip 이 아니라 실패로 두어야 빈 통과를 막는다.

### 70초 안 표본 (11-05 로컬 1회 실측 · `timeout 70` · `ulimit -u 2000`)

| 시험 (`tests/test_document_adapters.py`) | 줄 | 걸린 시간 |
|---|---|---|
| `test_pdf_table_and_page_anchors` | `:134` | 3.39초 |
| `test_mixed_digital_scanned_pdf_and_private_ocr_temp_cleanup` | `:142` | 1.71초 |
| `test_docx_structure_duplicate_paragraph_anchors_and_original_picture_bytes` | `:109` | 1.42초 |
| `test_xlsx_sheet_formula_cached_value_and_merged_cell_contract` | `:123` | 0.09초 |
| 4개 합계(import·모델 적재 포함) | — | 15.06초(4 passed) |

- 표본 pdf 는 시험 안에서 만든다(dev 의존 `reportlab`). 리포에 바이너리 표본 파일을 두지 않아도 된다.
- 첫 줄 추천 표본: 위 pdf 2개(텍스트층 + 스캔 섞임 OCR)다. BYZ 의 md·pdf 범위에 바로 맞는다.

## 4. 열린 것 (사람·planner 판단)

| 항목 | 왜 | 선택 |
|---|---|---|
| 출처 sha 677264a6fe 가 remote 에 없다 | BYZ 가 옮겨 심을 때 출처를 직접 못 본다 | `feature/rag-transplant` 를 remote 에 push 하거나, 옮길 파일 3개만 따로 묶어 공유한다. 이 발주 범위 밖이라 하지 않았다. |
| hwp JVM · image vision | 이미지 무게·LLM 호출이 더해진다 | `대기/loom-file-formats-office`·`-ocr` 카드에서 같은 판정(ⓑ)으로 다시 본다. |

## 5. 이 문서가 안 한 것

코드 변경 0 · BYZ 리포 쓰기 0 · WIP 가지 편집 0 · DA 0 · 새 나노 0 · 라이브 쓰기 0. 시험은 airag 로컬 4개 1회만 돌렸다(읽기 전용 · 산출물 0).
