# 리서치: 확인한 사실, 1차 출처, 남은 검증 항목

**상태: 문헌확인**(출처가 명시된 항목) 또는 **미검증**(명시적으로 표시된 항목). 아래
항목은 아키텍트가 재검증한 리서치 결과를 요약·정리한 것이며, 모든 원문 인용을 옮기지는
않는다.

## Docling — 확인된 사실

- IBM Research 원 프로젝트, MIT 라이선스, `github.com/docling-project/docling`
  (DS4SD/docling에서 개명). 문서 변환 엔진으로 `DoclingDocument`라는 구조화 표현을
  만든다 — Markdown/HTML/JSON/DocTags는 그 구조화 표현에서 **파생된 export 뷰**이지
  기반이 아니다.
- 공식 지원 형식(홈페이지가 아니라 형식 레지스트리 페이지에서 확인): PDF, DOCX,
  PPTX, XLSX, HTML, EPUB, Apple Pages, WAV/MP3, WebVTT, Box Notes, EML/MSG, 이미지,
  LaTeX, DocTags, 일반 텍스트, ODF, 비디오, XBRL, Markdown 계열.
- `HybridChunker.chunk(self, dl_doc: DoclingDocument, **kwargs)` — `DoclingDocument`를
  직접 입력으로 받는다. `chunk.meta.doc_items`는 문서로의 back-reference,
  `chunk.meta.headings`는 섹션 경로다. **재파싱한 마크다운 문자열을 받지 않는다** —
  이전 초안이 틀렸던 지점이며, [`../PLAN.md`](../PLAN.md)의
  핵심 정정 사항이다.
- `ProvenanceItem` 필드: `page_no`, `bbox`, `charspan` — TextItem/TableItem/
  SectionHeaderItem/PictureItem/KeyValueItem에 `prov: list[ProvenanceItem]`로 붙는다.
  **PDF 계열 콘텐츠에서는 실제 제공이 확인됐다.** 다른 형식(DOCX/XLSX 등)에서 이
  필드가 어느 범위까지 채워지는지는 형식별로 개별 검증하지 않았다 — "PDF만 가능"이
  아니라 "PDF 외 형식의 제공 범위가 미검증"이며, 검증 전까지 HWP/Word/XLSX에 좌표를
  발명하지 않는다.
- OCR 백엔드: EasyOCR, Tesseract(tesserocr/TesseractCli), RapidOCR, OcrMac(macOS
  Vision), Nemotron-OCR, 원격 KServe-V2, `OcrAutoOptions` 모드; `iso:` 언어 코드
  정규화 계층; 미지원 언어는 명시적 예외를 던지며 조용히 폴백하지 않는다.
  `OcrMode` enum: `DEFAULT`, `FULL_PAGE`, `LAYOUT_REGIONS`, `PDF_AWARE_LAYOUT_REGIONS`.
- 한국어 OCR: EasyOCR(iso:ko)와 Tesseract(`kor` traineddata) 모두 Docling 공식
  문서에서 한국어 지원이 확인된다. **정확도 우열에 대한 검증된 근거는 없다** —
  Tesseract 한국어가 영어보다 약하다는 저신뢰 2차 자료뿐이며, "한국어 최적" 배지는
  붙이지 않는다.
- 페이지 단위 디지털/스캔 자동판별의 정확한 기본 규칙: 옵션 이름은 존재하나
  docstring 본문까지 확인하지 못해 **미검증**.
- XLSX는 **공식 지원 형식**이다(위 지원 형식 목록으로 확인됨). 그 이상의 세부
  동작은 확실성 수준을 섞지 않는다:
  - 시트당 `TableItem` 개수, 시트 경계 보존 여부는 **현재 버전 기준 미검증**이다 —
    이 주장의 원 출처도 아래 GitHub 이슈 #1292이며, 현재 backend 소스코드로
    재검증하지 않았다. "시트별 TableItem이 유지된다"를 확인된 사실로 제시하지 않는다.
  - `export_to_markdown()`이 여러 시트를 하나의 MD로 평탄화한다는 것은 GitHub 이슈
    #1292의 **과거 보고**다 — 그 시점의 이슈 보고이지 현재 코드로 재검증한 사실이
    아니며, 지금도 그렇다고 단정하지 않는다.
  - 수식 보존/재계산은 어떤 1차 출처에서도 확인되지 않았다 — 무손실 수식 변환이나
    정확한 셀 앵커를 확정 동작으로 제시하지 않는다.

## HWP/HWPX — 확인된 사실

Docling의 전용 형식 레지스트리 페이지(`docling-project.github.io/docling/usage/supported_formats/`)에
HWP/HWPX가 **없음을 확인**했다 — 홈페이지만 본 것이 아니다. 별도의, Docling이 아닌
어댑터가 필요하다.

| 후보 라이브러리 | 라이선스 | 확인 근거 | 확인된 기능 | 명시적으로 안 되는 것 |
|---|---|---|---|---|
| `hwplib` (neolord0) | Apache-2.0 | README 직접 fetch | 텍스트 추출, 표 컨트롤, 이미지/하이퍼링크 삽입 | 암호화 파일 읽기, PDF/이미지 렌더링 |
| `hwpxlib` (neolord0) | Apache-2.0 | README 직접 fetch | `TextExtractor` | 표/이미지 추출은 README에 명시적 확인 없음 |
| `pyhwp` | AGPLv3 | 검색요약 수준 | HWP5 전용, 유지보수 여부 불명 | — |
| `hwp-hwpx-parser`, `hwpkit`, `rhwp-python` | 불명 | 검색요약 수준만 | — | 채택 의존성으로 취급하지 않음, 명시적 미검증 |

두 후보 모두 JVM 요구. HWP/HWPX 어댑터는 **현재** 검증 예정 상태로 라벨링한다 — 실제
동작 검증이 이뤄지면 이 상태 표시를 갱신한다("영구히 검증 예정"이 아니라 지금 시점의
상태다). 좌표 수준(page/bbox) 앵커는 약속하지 않는다 — 최선의 경우 문단/섹션 수준이다.

## 사전 리서치 메모

2026-08-26에 스크랩한 개인 메모 1건이 Docling/Unstructured.io를 이미 언급했다(엔터프라이즈
RAG는 원본을 바로 벡터화하지 말고 구조화 파서를 거쳐야 한다는 요지). 이 메모는 사전
리서치 전체를 대표하지 않으며, 이 문서의 근거는 아래 출처를 새로 확인한 결과다.

## 1차 출처

**직접 근거로 사용**(위 사실 서술에 인용됨):

| 출처 | 확인 내용 |
|---|---|
| [Docling 지원 형식 레지스트리](https://docling-project.github.io/docling/usage/supported_formats/) | 공식 지원 형식 목록, HWP/HWPX 부재 |
| [Docling Chunking 개념](https://docling-project.github.io/docling/concepts/chunking/) | `HybridChunker.chunk(dl_doc: DoclingDocument, ...)` 시그니처 |
| [Docling OCR 개념](https://docling-project.github.io/docling/concepts/OCR/) | OCR 백엔드 목록, 한국어 지원, `OcrMode` |
| [Docling `DoclingDocument` 레퍼런스](https://docling-project.github.io/docling/reference/docling_document/) | `ProvenanceItem` 스키마 |
| [IBM Research 블로그](https://research.ibm.com/blog/docling-generative-AI) | Docling 프로젝트 배경 |
| [hwplib README](https://raw.githubusercontent.com/neolord0/hwplib/main/README.md) | 라이선스, 텍스트/표/이미지 기능 범위 |
| [hwpxlib README](https://raw.githubusercontent.com/neolord0/hwpxlib/main/README.md) | 라이선스, `TextExtractor` 기능 범위 |
| [GitHub 이슈 #1292](https://github.com/docling-project/docling/issues/1292) | XLSX MD 평탄화 이슈 보고(역사적 증거로만 사용) |

**배경/참고**(검색요약 수준이거나 채택 의존성으로 취급하지 않음):

[docling-project/docling](https://github.com/docling-project/docling) ·
[Docling 문서 홈](https://docling-project.github.io/docling/) ·
[Pipeline Options 레퍼런스](https://docling-project.github.io/docling/reference/pipeline_options/) ·
[Full-page OCR 예제](https://docling-project.github.io/docling/_generated/examples/full_page_ocr/) ·
[Docling About](https://docling.org/about/) ·
[pyhwp](https://github.com/mete0r/pyhwp) ·
[hwplib GitHub](https://github.com/neolord0/hwplib) ·
[hwpxlib GitHub](https://github.com/neolord0/hwpxlib) ·
[hwp-hwpx-parser](https://github.com/KimDaehyeon6873/hwp-hwpx-parser) ·
[hwpkit](https://pypi.org/project/hwpkit) ·
[rhwp-python](https://github.com/DanMeon/rhwp-python)

## 남은 검증 항목 (미검증, 확정으로 승격 금지)

- 혼합 페이지(디지털+스캔)의 정확한 기본 자동판별 알고리즘.
- EasyOCR vs Tesseract 한국어 정확도의 정량 비교(실제 문서 벤치마크 필요).
- PDF 외 형식에서 `ProvenanceItem`이 실제로 채워지는 범위.
- XLSX 시트당 `TableItem` 개수·시트 경계 보존, 수식 보존/재계산, 병합 셀 처리,
  `export_to_markdown()` 평탄화의 **현재** 코드 동작(전부 #1292 이후 재검증 안 됨).
- `hwplib`/`hwpxlib`의 표/이미지 추출 세부 정확도, HWPX 앵커(문단/섹션 이상) 세밀도.
- SQLCipher+sqlite-vec의 이전 벤치 기록(합성 벡터, 원본 환경) — 새 설치 환경·실제
  텍스트/이미지 임베딩·연결 확장까지 검증한 것은 아님을 이어서 확인해야 함.

## 관련 문서

- 이 사실들이 적용되는 형식 라우팅: [`../PLAN.md`](../PLAN.md)
- 이 리서치를 기반으로 한 결정 기록: [`../DECISIONS.md`](../DECISIONS.md)
