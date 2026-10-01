# 검색, 확장, 근거 반환 계약

**상태: 확정(방향) · 미구현** (`feature-pack/rag/src/`에 search/expand 코드 없음 —
[`../delivery/roadmap-and-gates.md`](../delivery/roadmap-and-gates.md) 참고). 이 흐름을
직접 눈으로 보는 인터랙티브 자료는 시각 매거진
([`../visuals/2026-09-09-rag-visual-atlas.html`](../visuals/2026-09-09-rag-visual-atlas.html))이며,
그 58건의 브라우저 검사는 이 HTML 데모를 검증한 것이지 이 엔진을 검증한 것이 아니다.

## 검색

**상태: 제안**

1. query, collection, 필터(소스/유형/시간), top-K, 예산을 검증한다.
2. 검색 embedding space에 맞는 query vector를 얻는다(모델 호출은 DB 트랜잭션 밖).
3. 짧은 DB 읽기 스냅숏 하나에서 후보를 얻는다 — BM25와 벡터 모두 같은 활성 리비전/삭제/범위 필터를 적용한다.
4. 채널별 순위를 KakaoBot 선례를 계승한 **RRF, k=60**으로 합친다. 기본 후보 100, 최종 결과 10 — 조정 가능한 초기값.
5. 선택적으로 같은 스냅숏 기준 확장을 수행한다(아래).
6. 정확한 리비전/청크/순서/점수/확장 경로/제공자 profile을 manifest로 기록해 반환한다.

3~5단계는 하나의 명시적 읽기 트랜잭션을 공유한다 — hop별 autocommit 조회나 별도
연결을 쓰지 않는다. 벡터 backend가 필터를 네이티브로 지원하지 않으면, 일정 개수만
잘라 사후 필터하고 "완료"로 부르지 않는다 — 적합한 행 집합에 대한 exact cosine
경로를 쓰거나 한계를 명시적으로 보고한다. 해시/결정적 벡터는 테스트 전용이며 운영
기본 의미 검색으로 쓰지 않는다.

## 제한된 확장

**상태: 제안**

확장은 시드 청크에서 시작해 연결된 청크를 추가하며, **다음 전부**로 경계를 짓는다:
범위/collection, 활성 리비전, visited 집합(순환 방지), 깊이, 개수/토큰 예산 — 깊이 하나만이 아니다.
초기 제안값: 깊이 1, 최대 20청크, 추정 토큰 최대 약 8,000; 호출자는 설정된 상한 내에서 낮출 수 있다.

| 연결 | 생성 근거 | 구조적/추정 |
|---|---|---|
| `next` / `previous` | 같은 리비전의 block/청크 순서 | 구조적(실선) |
| `parent` / `child` | 제목/문단/문서-첨부 구조 | 구조적(실선) |
| `reply_to` | 대화 입력의 원본 메시지 ID | 구조적(실선) |
| `references` | 문서 링크, 명시적 `source_key` 관계 | 구조적(실선) |
| `derived_from` | OCR/비전 표현 → 원본으로 복귀 | 구조적(실선) |
| `similar` | 같은 embedding space의 거리, 옵트인 | 추정(점선) — 동일 사실이나 명시적 인용으로 취급하지 않음 |

구조적 연결은 발행 시점에 저장된다; `similar`는 요청 시 계산한다(모든 청크 쌍을
미리 저장하지 않고 top-N만) — 실제 반환한 경로와 점수는 manifest에 남긴다. 예산에
걸리면 `truncated`, 소모량, 사유, 남은 참조 가능성을 반환한다 — 예산을 넘겨 이웃을
계속 모으지 않으며, 컨텍스트를 줄이려고 임의 요약을 생성하지도 않는다 — 대신 겹치는
원문 범위를 합치고 제한된 청크를 선택한다.

## 근거 계약(`EvidenceBundle`)

**상태: 제안**

| 필드 | 내용 |
|---|---|
| `run` | 검색 ID, query, schema version, snapshot sequence, 실행 mode/profile |
| `hits` | chunk ID, rank, 채널별 rank/score, 내용, representation 유형 |
| `citation` | source ID/key, 정확한 리비전, origin URI, 내부 `original_ref`, 해시, anchor |
| `originals` | 포함된 원본 또는 안전한 조회 참조, MIME, 크기 |
| `expansion` | seed, 경로, 관계, 깊이, 구조적/추정 구분 |
| `completeness` | pending/stale 입력, 부분 실패, 예산 사용량, 잘린 이유 |
| `manifest` | 동일한 근거 묶음을 다시 조회하는 식별자 |

원본 반환은 부가 기능이 아니라 **필수 기능**(`fetch original`)이다 — 작은 텍스트
원본은 요청 시 inline 포함 가능하고, 큰/바이너리 원본은 무제한 base64가 아니라 명시적
fetch 참조/스트림으로 반환한다. manifest는 엔진이 반환한 근거의 정확한 내용을
증명하는 것이지, 상위 에이전트가 실제로 어떤 최종 프롬프트를 썼는지를 증명하지 않는다
— 그건 별개 관심사이며 이 계약의 필수 기능이 아니다.

선택된 소스/리비전/확장 노드 집합은 원본/표준 MD/청크 뷰와 반환된 근거 전체에
**동일하게** 흘러야 한다 — 이 일관성 요구는 위 링크의 시각 매거진 재수입/반환 장면이
인터랙티브로 보여 주는 것과 같은 원칙이며,
[`consumer-integration.md`](../contracts/consumer-integration.md)의 재수입 계약이
기대는 것과도 같다.

## 관련 문서

- 청크가 애초에 색인에 들어간 과정: [`ingestion.md`](ingestion.md)
- 이 질의들이 필터링하는 저장 정체성: [`data-and-storage.md`](data-and-storage.md)
- `search`/`expand`/`fetch`의 제안 CLI 표면: [`../contracts/cli.md`](../contracts/cli.md)
