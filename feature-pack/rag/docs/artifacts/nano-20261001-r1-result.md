# Nano r1 결과 — DA r1 결함 4건 수정

- 세션: `ft-airag-nano-r1#0` · 모델: claude-sonnet-5-5[1m]
- 골의 어느 축인가: A03 — A02 트리 2순위 C09 (DA r1 REJECT 결함 수정 → 회귀 재실행 → DA 재검토)
- 대상: `feature-pack/rag-consumer` 만 변경. core(`feature-pack/rag`) 무변경. 커밋·push 안 함.
- 최종 pytest (`feature-pack/rag-consumer`, `../rag/.venv/bin/python -m pytest tests -q -p no:cacheprovider`): `210 passed in 7.08s` (기준선 206 + 신규 4)

## B1 — 아카이브 2묶음부터 백업·일일 실행 실패
- 실제 원인(DA 설명과 일치): `runtime.py` `_backup` 이 모든 아카이브 묶음을 `DatabaseSource(..., self.keys["archive"])` 로 넘겼다. `operations._validate_sources`(`operations.py:146-147`) 가 database 컴포넌트 키의 중복을 거부하므로 묶음이 2개가 되는 순간 `STORE_KEYS_MUST_BE_DISTINCT`. `operations.create_backup_set` 은 이미 «소유자가 암호화한 파일»용 `ArchiveSource`(키 불요, 원본 바이트 복사)를 제공하고 있었는데 runtime 이 `[]` 로 비워 두고 있었다.
- 수정: 아카이브를 `ArchiveSource` 로 `create_backup_set` 의 archives 인자에 전달 (근원 수정, 키 검사 완화·플래그 없음). `runtime.py:35`(import), `runtime.py:965-972`(`_backup`).
- 테스트: `test_runtime.py::test_backup_and_daily_run_succeed_with_two_archive_bundles` (강제 백업 성공·archive 컴포넌트 2개·검증 True·다음 날 `run_once()` 백업 성공).
- Red: `OperationsError: STORE_KEYS_MUST_BE_DISTINCT` (`runtime.py:968` → `operations.py:147`).

## M1 — 과거 백업 재검증이 현재 아카이브 증가로 실패
- 실제 원인(DA 설명과 일치): `verify_backup` 이 «현재 원장»의 `_confirmed_archives()` 로 기대 컴포넌트 집합을 만들어 링크 체크에 넘겼다. 백업 이후 생긴 묶음이 기대 집합에 들어가 복원 집합과 불일치 → `RESTORED_COMPONENT_SET_MISMATCH`.
- 수정: 링크 체크가 «복원된 원장(백업 시점)» 에서 `_confirmed_archives(restored_ledger)` 로 기대 집합을 직접 구한다. `_restore_link_check` 의 인자 제거, `verify_backup`·`_backup` 호출부 정리. `runtime.py:903-905`(시그니처), `runtime.py:918-922`(복원 원장 기준 집합 비교), `runtime.py:1263-1270`(`verify_backup`). 아카이브 컴포넌트는 `kind=archive` 라 `verify_backup_set` 의 database_keys 에서 아카이브 키 항목을 뺐다.
- 테스트: `test_runtime.py::test_past_backup_reverifies_after_new_archive_bundle_is_added`.
- Red: `RuntimeError: RESTORED_COMPONENT_SET_MISMATCH` (`runtime.py:908`).
- 비고: B1 수정 이전 코드로 만든 «아카이브 1개 포함 백업» 은 manifest 에 해당 컴포넌트가 `kind=database` 로 남아 있어 새 `verify_backup` 에서 키 매핑이 없으면 `MISSING_DATABASE_KEY` 가능. 운영에 그런 백업이 이미 있는지는 확인하지 않았다(운영 DB·백업 접근 금지). 필요하면 master 판정.

## M2 — 등록 소스 일부 미수집인데 coverage_complete=True
- 실제 원인(DA 설명과 일치): `status()` 의 `coverage_complete` 가 이미 상태 행이 있는 collector 소스만 대상으로 `all()` 을 계산했다. session_meta 검증 단계에서 거부된 소스는 상태 행이 아예 없어 집계에서 빠졌다.
- 수정: 상태 행의 source_id 집합이 등록 소스 전체와 같을 때만 완료 가능. `runtime.py:1097-1099`. `collector_sources` 목록 모양·필드는 그대로.
- 테스트: `test_runtime.py::test_coverage_is_incomplete_while_an_enrolled_source_has_no_collector_state`.
- Red: `assert True is False` (`coverage_complete`).

## M3 — 첫 미검증 해결책 배치가 뒤 배치의 verifier 기회를 가림
- 실제 원인(DA 설명과 일치): `_unverified_batch` 가 항상 ordinal 최소의 미검증 배치만 골랐다. 그 배치가 계속 미검증이면 매 호출이 같은 배치만 재평가.
- 수정: 라운드로빈. lineage 별 마지막 방문 배치 ordinal 을 새 테이블 `airag_memory_verification_cursor` 에 기록하고, 다음 선택은 그 ordinal 보다 큰 배치를 먼저(없으면 처음으로 순환). 시계 값에 의존하지 않는다(고정 Clock 에서도 순환). 기존 테이블(`airag_memory_extractions` 15열 등)은 건드리지 않았다(`CREATE TABLE IF NOT EXISTS` 라 기존 DB 마이그레이션 불요). `memory.py:478-480`(스키마), `memory.py:721-735`(`_unverified_batch`).
- 테스트: `test_memory.py::test_unverified_batches_take_turns_when_verifier_returns_later` (DA 재현 블록 그대로: 배치 3개·마지막만 verifier True → 방문 집합 3개 전부·materialized 1).
- Red: 방문 `['solution-0']` 뿐, 나머지 2개 미방문 (`assert ['solution-0'] == [...3개]`).

## 변경 파일
- `feature-pack/rag-consumer/src/airag_consumer/runtime.py` (B1·M1·M2)
- `feature-pack/rag-consumer/src/airag_consumer/memory.py` (M3)
- `feature-pack/rag-consumer/tests/test_runtime.py` (신규 3 테스트 + 헬퍼 2)
- `feature-pack/rag-consumer/tests/test_memory.py` (신규 1 테스트)
