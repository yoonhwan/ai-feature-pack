# 소비 프로젝트 연동: 외부 배선 → 명시적 요청 → 결과

**상태: 확정** (2026-09-09, archive의 원본 설계가 제안한 내장 워처 계획을 대체). 이
문서가 책임 분담의 현재 권한 문서다; [`../decisions/log.md`](../decisions/log.md)에
결정 자체와 무엇을 대체했는지 기록되어 있다.

## 경계를 계약으로 표현하면

```
[소비 프로젝트]                              [airag core]
  감지, 파일시스템 워처/폴링,          --->    명시적 add/update/delete/
  스케줄, 디바운스/재시도 타이밍,              search/expand/fetch/manage
  "지금 재수입해야 하나?"                      요청만
                                       <---    표준화된 결과 + 근거
```

소비 프로젝트가 맡는 것: 감지, 파일시스템 워처/폴링, 스케줄, 디바운스, 신규/변경/삭제
파일 판단, 재시도/재수입 시점 결정, 외부 원본 읽기 권한, CLI/API 호출.

`airag` core가 맡는 것: 명시적 요청 수신, 표준화(마크다운 + 구조화 provenance),
청킹, 임베딩/색인 갱신, 불변 원본/이력 관리, 표준화된 결과/근거 반환. core 안에는
**내장** 디렉터리 워처, 루트 인벤토리 폴링, 자동 폴더 탐색, 상주 데몬, 소스 감시
루프가 **없다**.

## 요청/응답 형태

**정확한 필드와 envelope 형식은 [`cli.md`](cli.md)가 소유한다** — 여기서는 재정의하지
않고 그 예시를 그대로 가리킨다: 소비자는 `op`(`add`/`update`/`delete`),
`source_key`, `request_id`, `expected_revision`을 담아 보내고, 응답은 공통 envelope의
`data` 필드 안에 `revision`/`evidence`를 받는다.

- `request_id`는 호출자의 idempotency key다 — 같은 키·같은 내용으로 재시도하면
  새 리비전이 아니라 no-op이다.
- `expected_revision`으로 소비자가 동시 갱신 충돌을 감지한다 — 불일치 시 조용히
  덮어쓰지 않고 conflict를 반환한다.
- 요청 정확성(idempotency, 충돌 처리, 원자적 발행/tombstone, 일관된 읽기 스냅숏)은
  **외부 트리거 타이밍과 무관하게 core 안에서 보장된다** — 소비자의 워치/폴링
  주기가 DB 정확성을 좌우하지 않는다.

## `delete` 의미

`delete` 요청은 **외부 파일이 이미 사라진 뒤에도** 등록된 `source_key`를 식별한다 —
core가 이를 실시간 검색/확장에서 제외하고 관리 원본/이력을 보존한다. core는 외부
파일 자체를 절대 삭제하지 않는다. 시각 매거진에서 delete를 update(재수입)와 별도
결과로 그리는 이유가 이것이다: update는 표준화/청킹에 다시 들어가지만, delete는
그렇지 않다 — 실시간 검색에 보이는지 여부만 바뀌고 이력은 남는다.

## 재수입

재수입(표준화/청킹/임베딩 재실행)은 **요청 시 core가 수행하는 작업**이다. 소비자가
변경 파일을 감지했든, 스케줄이 발동했든, 사용자가 직접 요청했든 — 재수입이 *필요한지/
언제 필요한지*는 전적으로 소비 프로젝트의 결정이며, core가 스스로 판단하지 않는다.

## 이 문서가 대체하는 것

원본 설계(archive의 원문)는 core 안에서 지속적으로 파일시스템을 폴링하는 내장 워처와
`watch_roots`/`watch_entries` 테이블, `watch` CLI 명령을 제안했다. 그 계획은
**대체됐다**: durable job 기록, 원자적 발행, idempotency 같은 요청 정확성 속성은
여전히 유효한 설계 목표지만, 내부 감시 루프가 아니라 소비자가 보낸 요청으로 트리거된다.
소비자 측 워처는 나중에 별도 예시/어댑터로 제공될 수 있으나 지금은 core에
구현·패키징하지 않는다.

## 관련 문서

- 이 계약이 의존하는 저장 계층 보장: [`../architecture/data-and-storage.md`](../architecture/data-and-storage.md)
- 전체 CLI 어휘와 실제 구현 상태: [`cli.md`](cli.md)
- 결정 기록과 대체 근거: [`../decisions/log.md`](../decisions/log.md)
- 소비자/CLI 경계를 넘나드는 add/update/delete 화살표를 직접 보는 인터랙티브 자료: [`../visuals/2026-09-09-rag-visual-atlas.html`](../visuals/2026-09-09-rag-visual-atlas.html)
