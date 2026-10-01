# 구현 로드맵과 현재 상태

## 먼저 읽을 것 — 서로 다른 두 종류의 "통과"

**인터랙티브 시각 매거진에 대한 58/58 검사 통과는 HTML+JS 기획 데모의 브라우저/UI
테스트다. RAG 엔진 테스트가 아니다.** 매거진에는 실제 DB, 실제 파일, 임베딩, 어댑터가
없다 — 설계를 가르치기 위한 예시 데이터다. 요약 근거:
[`evidence/visual-atlas-qa-summary.json`](evidence/visual-atlas-qa-summary.json)
(검사 결과·일자·HTML 해시만 담은 사본; 상세 로그는 이 패키지에 포함되지 않는다).
이 문서 세트 어디에서도 58건 검사를 엔진 검증으로 인용하지 않는다.

## 오늘 실제로 구현된 것 (`feature-pack/rag/src/` 코드로 확인)

**상태: 스캐폴드**

| 영역 | 상태 |
|---|---|
| 패키지/CLI 스캐폴드 | `ai-rag`/`krb-rag` 콘솔 스크립트 등록됨; JSON envelope 계약 적용됨. |
| `init` | 새 암호화 DB 생성; 비어 있지 않은 기존 파일은 거부. |
| `manage doctor` | SQLCipher/FTS5/vec0 probe 결과와 키 제공자 상태 보고. |
| `manage verify` | 주어진 키로 기존 암호화 DB를 열어 검증. |
| 키 처리 | `--key-fd` 동작; macOS Keychain 제공자는 항상 미가용을 보고하는 스텁. |
| 그 외 전부(add/update/search/expand/delete/manage retry-reindex/restore/backup, 어댑터, 청킹, 임베딩, FTS/vec 발행, 소비자 요청 기반 재수입 처리) | **미구현.** 이 워크트리에 해당 코드가 전혀 없다. |

현재 스캐폴드에는 워처 코드가 없다 — 승인된 외부 배선 경계와 이미 일치하므로
제거할 것이 없다.

## 구현 순서 (원본 설계 §12를 워처 단계만 대체해 계승)

**상태: 확정(순서) · 각 단계 미구현**(1단계 일부 스캐폴드 제외)

1. **설치·암호화 검증** — 패키지/CLI 진입점, SQLCipher/FTS5/vec0 probe, 키 처리,
   잘못된 키 거부, 평문 폴백 없음. *(위 표 기준 일부 완료.)*
2. **저장·입력 계약** — 원본 스냅숏/리비전/collection/job 원장·마이그레이션,
   텍스트/구조화 대화 어댑터, public API.
3. **실제 임베딩·검색** — embedding space 등록, chunk/FTS/vec 발행, RRF, 실제
   로컬 모델로 검색/fetch/manifest 재조회.
4. **문서·이미지 어댑터** — Docling 경유 PDF/DOCX/XLSX, 별도 어댑터 경유
   HWP/HWPX, 이미지 OCR/비전 표현, 원본 반환.
5. **청크 연결·확장** — 구조 관계 생성, reference 해석, 예산 있는 확장, provenance/중복 제거.
6. **소비자 요청 처리** — `add`/`update`/`delete` 처리, durable 재시도, restore,
   reindex, doctor, 암호화 백업. (원본 설계의 "파일 워처" 단계를 대체 —
   소비자가 이벤트를 보내고 core가 처리한다. [`../contracts/consumer-integration.md`](../contracts/consumer-integration.md) 참고.)
7. **시뮬레이션** — 아래 시나리오를 실제 CLI·실제 암호화 DB로 실행하고 결과를
   이 워크트리에 보존.
8. **사용자 투어** — 등록→수정→검색→원본→확장→삭제→복구를 사용자와 실제
   혼합 자료로 직접 확인.
9. **완성 판정·통합 자료 준비** — 승인된 요구와 검증 결과를 대조하고, 패키지 경로·
   사용 계약·제한을 담은 통합 자료(소비 프로젝트가 참고할 문서)를 준비한다. 이
   패키지가 다른 프로젝트에 자동으로 보고하거나 배포를 트리거하지 않는다 —
   소비 프로젝트 쪽에서 이 자료를 가져다 쓴다.

1~6단계는 원본 설계의 워처 중심 6단계를 소비자 요청 처리로 대체하며, 나머지
시뮬레이션/투어/판정 단계는 원본 설계와 순서가 같다.

## 시뮬레이션 시나리오 (계획됨, 아직 실행 안 함)

**상태: 제안**

암호화 DB 개폐/오키 거부, 신규 문서 등록과 해시 일치 fetch, 중복 재등록은 no-op,
갱신 시 새 리비전 생성하되 기존 manifest는 구 내용을 그대로 반환, 빈/긴/한글 텍스트
처리, 구조화 대화의 스레드 보존, PDF/DOCX 앵커·원본 충실도, OCR 처리된/안 된 이미지,
소비자가 보낸 add/update/delete가 올바르게 반영(원본 설계의 "watcher add/change/delete"를
대체 — 결과는 같고 트리거가 워처 대신 소비자), 삭제 후 복구, 접근 불가와 삭제의
구분, 모델 실패/차원 불일치 처리, 공간 혼합 없는 모델 리비전 마이그레이션, 동시
add/reindex에서 중복 발행 없음, 순환·예산이 보장된 구조/의미 확장, 선택적 원본 포함,
편집/삭제 이후에도 재현되는 manifest, 백업/복원, CLI/API 계약 일관성, BYZ/KakaoBot
내부를 import하지 않는 별도 샘플 프로젝트에서의 클린 설치·소비 테스트.

성능 목표(아직 측정 안 함): warm query vector로 1만 청크·384차원 깊이 1 구조 확장
p95 ≤ 500ms; core RSS ≤ 300MiB. 검증할 목표값이지 현재 측정값이 아니다.

## 관련 문서

- "완성"의 정의와 코드 존재 ≠ 완성인 이유: [`../scope.md`](../scope.md)
- 위 형식/어댑터 주장의 1차 출처: [`../research/findings-and-open-questions.md`](../research/findings-and-open-questions.md)
- 결정 이력: [`../decisions/log.md`](../decisions/log.md)
