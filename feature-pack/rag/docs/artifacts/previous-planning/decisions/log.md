# 결정 이력

날짜순 내림차순. 각 항목은 확정 결정과, 있다면 그것이 대체한 이전 가정을 함께 적는다.

### 2026-09-09 — 정본 기획 문서 구조 승인

사용자가 `feature-pack/rag/docs/` 아래 정본화된 문서 구조(README/scope/architecture/
contracts/delivery/research/decisions/visuals/archive) 도입을 승인했다. 기존
`docs/design-rag-transplant.md`는 이 트리로의 리다이렉트 문서로 교체하고, 원문은
`archive/2026-09-09-initial-rag-transplant.md`에 역사적 기록으로 보존한다.

### 2026-09-09 — 외부 배선 책임 경계 (원본 설계의 내장 워처 계획을 대체)

사용자 정정: "CLI는 입출력 생성을 관리한다. 소비자가 새 데이터/재수입 트리거를
제공한다. 원본 파일 변경/삭제 확인은 외부 배선이며, 소비자가 CLI에 갱신/삭제를
알린다. 신규 등록도 동일하다."

승인된 책임 경계:
- 소비 프로젝트(BYZ, KakaoBot, 다른 앱)가 감지, 파일시스템 워처/폴링, 스케줄,
  디바운스, 신규/변경/삭제 파일 판단, 재시도/재수입 시점 결정, 외부 원본 읽기
  권한, CLI 호출을 담당한다.
- AI RAG core/CLI는 일반 처리기다. add/update/delete/search/expand/fetch/manage
  요청만 받아 표준화(MD+구조화 provenance), 청킹, 임베딩/색인 갱신, 불변 원본/이력
  관리를 수행하고 표준화된 결과/근거를 반환한다.
- core 패키지 안에 내장 디렉터리 워처, 루트 인벤토리 폴링, 자동 폴더 탐색, 상주
  데몬, 소스 감시 루프를 두지 않는다.
- 요청 정확성(안정적 collection+source_key/ID, 호출자 idempotency key, 예상
  리비전/충돌 처리, 원자적 발행/tombstone, 모델 공간 격리, 일관된 조회 스냅숏)은
  core 안에 그대로 남는다. 외부 트리거 타이밍이 DB 정확성을 좌우하지 않는다.
- delete 이벤트는 원본 경로가 사라진 뒤에도 등록된 소스를 식별하며, CLI는 이를
  실시간 검색에서 논리적으로 제외하고 관리 원본/이력을 이전 삭제 계약대로 보존한다
  — 외부 파일 자체를 지우지 않는다.
- 재수입 처리는 요청 시 core의 작업으로 남고, 재수입 필요/시점 판단은 소비자
  몫이다. provider/profile 기반 재색인도 자율이 아니라 명시적 요청이다.
- 소비자 측 워치 연동은 나중에 예시/어댑터로 제공될 수 있으나 지금은
  구현/패키징하지 않는다.

**대체됨**: 최초 사용자 요청과 원본 설계 문서(archive)의 §3 다이어그램, §7.2
파일 워처(2초 폴링), §10의 `watch` 명령, `watch_roots`/`watch_entries` 테이블,
§13의 "watcher add/change/delete" 시나리오. 이 항목들은 core에 내장 감시 루프가
있다고 전제했으며 위 결정으로 대체됐다.

**정식 문서 정합성 참고**: `docs/design-rag-transplant.md`(현재는 archive로 대체된
원문)와 그 시점의 §12/§13 순서는 워처 소유권에 대해 부분적으로 낡았다 — 이번
정본화 작업으로 `delivery/roadmap-and-gates.md`가 갱신된 순서를 반영한다.

### 2026-09-09 — 시각 매거진 리뷰 사이클 (기획용 인터랙티브 자료)

아키텍트가 승격 전 초안(현재 [`../visuals/2026-09-09-rag-visual-atlas.html`](../visuals/2026-09-09-rag-visual-atlas.html))을 다단계로 리뷰:
1. 표준 MD/구조 앵커 라벨링, PDF 디지털/스캔 선택, 구성 지도의 HWP 별도 어댑터
   표기, 확장 단계의 깊이/최대 조각 분리 — 4건 보완.
2. 이미지 OCR 결과 placeholder 문구, 엑셀 표 미리보기 부재/앵커 불일치 — 2건 보완.
3. 확장→반환 데이터 흐름 버그(선택한 조각 수가 다음 장면에 전달 안 됨), 재수입
   리비전이 봉투/MD/원본에 일관되지 않게 반영되는 버그 — 단일 파생 데이터 모델
   도입으로 근본 수정.
4. 사용자 승인 후 외부 배선 경계 반영 — 구성 지도에 "사용하는 프로젝트"/"AI RAG
   CLI" 경계와 add/update/delete/result 라벨 화살표 추가; delete와 update를
   별도 노드로 분리; 반환 결과가 경계 밖 소비자로 나가는 화살표 추가.

최종 검증: Playwright 58/58, 콘솔 에러 0. 요약 근거:
[`../delivery/evidence/visual-atlas-qa-summary.json`](../delivery/evidence/visual-atlas-qa-summary.json).
**이 58건은 HTML 매거진 검사이며 RAG 엔진 검증이 아니다** — [`../delivery/roadmap-and-gates.md`](../delivery/roadmap-and-gates.md)
참고.

### 2026-09-09 — 초기 설계 승인 (archive 원문)

사용자가 §1~§11의 범용 엔진 책임 경계, SQLCipher+sqlite-vec, 원본 스냅숏 보존,
유형별 어댑터, 청크 연결과 제한된 확장, 상위 에이전트용 근거 반환을 승인했고,
§12 순서로 구현·검증·운영을 진행하기로 했다. 원문 전체는
[`../archive/2026-09-09-initial-rag-transplant.md`](../archive/2026-09-09-initial-rag-transplant.md)에
보존되어 있다. **이후 결정(위 항목들)이 워처 소유권 부분을 대체했다** — 원문의 해당
절을 단독으로 현재 진실로 읽지 않는다.

## 관련 문서

- 경계의 최신 계약 형태: [`../contracts/consumer-integration.md`](../contracts/consumer-integration.md)
- 구현 순서와 현재 상태: [`../delivery/roadmap-and-gates.md`](../delivery/roadmap-and-gates.md)
