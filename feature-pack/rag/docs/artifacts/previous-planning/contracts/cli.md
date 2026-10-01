# CLI / Python API 계약

**상태: 확정(아래 "지금 구현된 것") · 스캐폴드** — 응답 envelope 형태와 `init`/
`manage doctor`/`manage verify`는 현재 코드(`feature-pack/rag/src/airag/cli/main.py`)로
확인됨. 그 외 모든 명령은 **제안** 어휘로서 아직 만들어지지 않았고 항목별로
개별 검토되지 않았다 — 아래 표를 "전부 존재한다"로 읽지 않는다.

## 지금 구현된 것 (코드로 확인)

| 명령 | 동작 |
|---|---|
| `ai-rag init <db>` | `<db>`에 새 암호화 SQLCipher DB 생성; 비어 있지 않은 기존 파일은 덮어쓰지 않음. |
| `ai-rag manage doctor` | SQLCipher/FTS5/vec0 가용성과 키 제공자 상태 보고(`key_fd`: 지원, `macos_keychain`: **미구현**, 항상 `false`). |
| `ai-rag manage verify <db>` | 기존 암호화 DB를 열어 키/DB 쌍이 읽을 수 있는지 확인. |

`ai-rag`와 `krb-rag`는 같은 진입점(`airag.cli.main:main`)에 등록된 콘솔 스크립트
별칭이다 — `pyproject.toml`에서 확인됨. 모든 응답은 stdout에 출력되는 JSON envelope다:
`{schema_version, request_id, ok, command, data, error}`; 그 외 어떤 것도 stdout에
찍지 않는다. 이 세 명령의 종료 코드는 성공 `0`, 실패 `4`다(아래의 더 넓은 종료 코드
표는 제안일 뿐 구현되지 않았다).

## 제안된 명령군(미구현)

`add`와 `update`는 사용자가 확정한 별개 어휘다 — 하나의 "등록/갱신" 명령으로
합치지 않는다.

| 명령군 | 책임 |
|---|---|
| `add` | **신규** 소스 등록. 입력은 명시적 파일 하나, 인라인 본문(텍스트), 또는 소비자가 이미 열거한 배치(파일 목록)다 — CLI가 디렉터리를 스스로 순회·탐색하지 않는다(디렉터리 탐색은 소비자 쪽 외부 배선, [`consumer-integration.md`](consumer-integration.md) 참고). 동기 처리 또는 job 반환. |
| `update` | **기존** `source_key`의 콘텐츠 갱신 — 새 `source_revision` 생성. |
| `manage status/list/show` | 소스·리비전·기능·pending/failed/stale·용량 조회. |
| `manage retry/reindex` | 실패 재시도, 추출/임베딩 profile 변경에 따른 재색인. |
| `manage restore` | 삭제 tombstone의 명시적 해제. |
| `manage backup` | 암호화 백업; 복원은 항상 새 경로에서 열어 검증한 뒤 교체. |
| `delete` | 소스를 실시간 검색/확장에서 제외; 외부 파일은 절대 삭제하지 않음. |
| `search` | 키워드 + 벡터 hybrid 검색과 선택적 제한 확장. |
| `expand` | 시드에서 깊이/개수/토큰 예산 내 연결 확장. |
| `fetch source/chunk/original/manifest` | ID/리비전으로 정확한 내용이나 원본 바이트 조회. |

`manage sync`와 `manage pause/resume`은 이전 내장-워처 계획의 잔재로, 소비자 요청
기반 모델에서 필요 근거가 없어 제안 명령군에서 제외한다.

제안된 종료 코드(미구현): `0` 성공, `2` 입력/설정 오류, `3` 미지원 기능/제공자 준비
안 됨, `4` 처리/저장 실패, `5` 버전 충돌. 검색 결과 0건은 성공이지 오류가 아니다.
혼합 입력 배치에 부분 실패가 있으면 전체 성공으로 표시하지 않고 성공/실패 항목을
모두 반환한다.

**이 계약에 `watch` 명령은 없다.** 지속 감지는 [`consumer-integration.md`](consumer-integration.md)에
따라 소비자 쪽에 있다 — 이는 원본 설계가 제안한 `watch` 명령과
`watch_roots`/`watch_entries` 테이블을 대체한다.

## 요청/응답 형태 (제안, `add`/`update`/`delete` 예시)

**명령/응답 형식의 소유 문서는 이 문서 하나다.** 다른 문서(예:
[`consumer-integration.md`](consumer-integration.md))는 이 형식을 재사용하며 별도
형식을 만들지 않는다.

```
요청(Python API/내부 표현): { "op": "add|update|delete", "source_key": "pdf-release-notes",
  "request_id": "<uuid>", "expected_revision": "v1" }

응답(공통 envelope 그대로): { "schema_version": 1, "request_id": "<uuid>", "ok": true,
  "command": "add", "data": { "source_key": "pdf-release-notes", "revision": "v2",
  "evidence": [...] }, "error": null }
```

`request_id`는 호출자의 idempotency key, `expected_revision`은 충돌 감지용이며,
`revision`/`evidence`는 다른 모든 명령과 동일하게 응답의 `data` 필드 안에 담긴다 —
`ok`/`data`/`error` 바깥에 별도 응답 형식을 두지 않는다.

## 관련 문서

- 왜 감시가 CLI 명령이 아닌지: [`consumer-integration.md`](consumer-integration.md)
- `search`/`expand`/`fetch`가 실제로 반환하는 것: [`../architecture/retrieval-and-evidence.md`](../architecture/retrieval-and-evidence.md)
- 구현 순서와 확정/제안 대조: [`../delivery/roadmap-and-gates.md`](../delivery/roadmap-and-gates.md)
