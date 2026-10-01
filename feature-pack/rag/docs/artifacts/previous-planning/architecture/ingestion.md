# 수집: 형식 → 추출/OCR → 정규화 번들 → 청크/색인

**상태: 확정(전체 방향) · 미구현** (`feature-pack/rag/src/`에 어댑터 코드 없음 — [`../delivery/roadmap-and-gates.md`](../delivery/roadmap-and-gates.md) 참고). 형식/OCR 지원 사실은 문헌확인 — 근거는 [`../research/findings-and-open-questions.md`](../research/findings-and-open-questions.md).

## 파이프라인

```
원본 바이트 --[형식별 경로]--> 정규화 번들 --[청커]--> 청크 --> 색인
```

1. **원본 바이트**는 경로와 무관하게 불변으로(`original_ref`) 보존한다.
2. **추출/OCR/어댑터**가 원본을 구조화 표현으로 바꾼다. 어떤 경로를 타는지 자체가
   형식별 설계 결정이다(아래 표) — 모든 형식이 같은 엔진을 거치지 않는다.
3. **정규화 번들** = 보존되는 실제 **표준 마크다운 산출물**(사람이 읽는 뷰, 자체
   해시/버전) + 구조화 문서 표현·provenance/앵커 메타데이터. 이 둘은 서로 연결되지만
   별개의 산출물이다.
4. **청킹**은 **구조화 표현**을 입력으로 받는다 — 내보낸 마크다운 문자열을 재파싱하지
   않는다. Docling의 `HybridChunker.chunk(dl_doc: DoclingDocument, **kwargs)`는
   `DoclingDocument`를 직접 받는다(문헌확인) — 마크다운 재파싱 API인 것처럼 문서화하지 않는다.
5. **색인 발행**(FTS + 벡터)은 리비전 단위로 원자적이다 — 상세는 [`data-and-storage.md`](data-and-storage.md).

## 형식별 라우팅

**상태: 문헌확인**(개별 셀 표기, 확정 채택 여부는 별개)

| 형식 | 경로 | 앵커 세밀도 | 근거 |
|---|---|---|---|
| PDF | Docling(네이티브) | page / bbox / charspan(`ProvenanceItem`) | Docling 공식 `DoclingDocument`/`ProvenanceItem` 스키마 문서에서 PDF 계열에 대해 확인. |
| DOCX·XLSX·PPTX·HTML 등 Docling 공식 지원 목록 | Docling(네이티브) | 형식 의존적 — PDF 계열 밖에서는 물리 page/bbox를 보장하지 않음 | 지원 형식 목록은 확인됨; PDF 외 앵커 세밀도는 개별 확인되지 않아 DOCX에 좌표를 발명하지 않는다. |
| XLSX(개별) | Docling(네이티브) | 시트당 `TableItem` 개수·시트 경계 보존은 현재 버전 미검증 | 공식 지원 형식임은 확인됨. 시트별 유지 여부와 `export_to_markdown()`의 다중 시트 평탄화는 둘 다 GitHub 이슈 #1292의 과거 보고이며 현재 backend 코드로 재검증하지 않았다. 수식 보존/재계산·병합 셀 처리도 **검증되지 않음** — 무손실 수식 변환을 약속하지 않는다. |
| HWP | 비-Docling 어댑터(후보: `hwplib`) | 문단 수준 추정, 미확정 | Docling 공식 지원 형식 레지스트리(홈페이지가 아니라 직접 확인)에 네이티브 HWP/HWPX 핸들러 없음. `hwplib`(Apache-2.0, JVM) README는 텍스트 추출만 확인 — 표/이미지 추출·암호화 파일·PDF/이미지 렌더링 불가. 현재 **검증 예정**으로 표기(실동작 검증되면 갱신), "동작함"이라 표기하지 않는다. |
| HWPX | 비-Docling 어댑터(후보: `hwpxlib`) | 문단 수준 추정, 미확정 | 동일 레지스트리 부재 확인. `hwpxlib`(Apache-2.0, JVM) README는 `TextExtractor` 기능 확인; 표/이미지 추출은 명시적으로 확인되지 않음. 동일하게 "검증 예정". |
| 이미지(스캔/사진) | Docling + OCR 백엔드 | OCR 인식 영역 | OCR(가시 텍스트 인식)·비전 설명(모델의 해석 캡션 — 사실이 아닌 해석)·임베딩(검색 벡터)은 서로 다른 층이며 하나로 합치지 않는다. |
| 구조화된 대화 | 경량 입력 어댑터(Docling 왕복 없음) | 메시지 ID | 이미 구조화된 텍스트는 문서 변환 엔진이 필요 없다. |

혼합 페이지(디지털+스캔이 한 PDF 안에 공존)는 페이지/영역 단위 처리가 필요할 수 있다.
Docling의 정확한 기본 자동판별(디지털 vs 스캔) 알고리즘은 이번 조사에서 **검증되지
않았다** — 특정 알고리즘을 확정 사실로 제시하지 않는다.

## OCR 백엔드(한국어 지원)

**상태: 문헌확인**

EasyOCR(CJK+러시아어 5개 언어 다국어 모델, `iso:ko`)과 Tesseract(`kor` traineddata) 모두
Docling 공식 문서에서 한국어 지원이 **문서로 확인**된다. 둘 사이 **정확도 우열은
검증되지 않았다** — Tesseract 한국어가 영어보다 약하다는 저신뢰 2차 자료만 있을 뿐이다.
"한국어 최적" 배지를 붙이지 않는다 — 실제 문서로 두 후보를 벤치마크해야 한다.

## 청킹

**상태: 제안**

기본 detail 청크 크기는 KakaoBot 선례를 출발점으로 계승한다(추정 800~1,200 토큰,
10~15% overlap)하되 실제 임베딩 제공자의 입력 한도를 우선한다. overlap은 중복된
사실이 아니라 연속된 문맥을 위한 것이며, 근거 묶음을 만들 때 겹치는 원문 범위를
합쳐 중복 전달을 줄인다.

## 관련 문서

- 수집이 기록하는 저장 정체성(소스/리비전/산출물): [`data-and-storage.md`](data-and-storage.md)
- 청크가 검색되고 근거로 반환되는 방식: [`retrieval-and-evidence.md`](retrieval-and-evidence.md)
- 전체 출처 목록과 항목별 신뢰도: [`../research/findings-and-open-questions.md`](../research/findings-and-open-questions.md)
- 소비 프로젝트가 실제로 무엇을 보내 수집을 트리거하는지: [`../contracts/consumer-integration.md`](../contracts/consumer-integration.md)
