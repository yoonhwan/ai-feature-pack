# Nano r2 결과 — DA r2 잔존 major 2건 수정

- 세션: `ft-airag-nano-r1#0` · 모델: claude-sonnet-5-5[1m]
- 골의 어느 축인가: A03 — A02 트리 2순위 C09 (DA r2 잔존 major 2건 → DA r3 PASS·major 0 목표). 백업 복구 경계 = 골 «운영 가능» 직결.
- 대상: `feature-pack/rag-consumer` 만 변경. core 무변경. 커밋·push 안 함. 실운영 백업·키 사용 복원은 건드리지 않았다.
- 최종 pytest (`feature-pack/rag-consumer`, `../rag/.venv/bin/python -m pytest tests -q -p no:cacheprovider`): `212 passed in 7.78s` (기준선 210 + 신규 2)

## R2-M2 — 격리 복원 검증이 원본 archive 파일 존재에 의존
- 실제 원인(DA 설명과 일치): `_restore_link_check` 가 복원된 원장의 receipt 를 `_confirmed_archives()` 로 해석했는데, 그 함수가 receipt 의 «원래 절대경로가 현재 archive_root 아래 + is_file()» 을 요구해 복원 전용 검증이 운영 파일에 묶였다. 복원 검증이 실제로 쓰는 것은 receipt 의 bundle_id·scope·records 와 «복원된 임시 archive 파일» 뿐이다.
- 수정: receipt 해석(`_archive_receipts`, 경로 검사 없음)과 운영 경로 신뢰 검사(`_confirmed_archives` = `_archive_receipts` + 기존 경로 검사)를 분리. 복원 검증은 `_archive_receipts(restored_ledger)` 사용. 운영 경로(백업 생성·archive-search)는 기존 신뢰 검사 그대로. 복원된 archive 자체의 `verify_archive`(키·scope·bundle_id·records) 검증은 그대로 유지. `runtime.py:822`(`_archive_receipts`), `runtime.py:850`(`_confirmed_archives`), `runtime.py:925`.
- 테스트: `test_runtime.py::test_backup_verifies_without_the_original_archive_files` (새 백업 생성 → 원본 archive 파일 2개를 `.preserved-offline` 로 이동 → verify True → finally 복구).
- Red: `RuntimeError: UNTRUSTED_ARCHIVE_RECEIPT_PATH` (`runtime.py:846` ← `check` 919).

## R2-M1 — 구버전 형식 백업(archive 가 kind='database') verify 거부
- 실제 원인(DA 설명과 일치): 구버전은 archive 컴포넌트를 `kind='database'` 로 manifest 에 기록했다. 현재 `verify_backup` 은 consumer/projection 키만 넘겨 `verify_backup_set` 이 `MISSING_DATABASE_KEY`.
- 수정: `verify_backup` 이 검증된 manifest 를 읽어, `kind='database'` 이면서 이름이 `archive_` 로 시작하는 컴포넌트에 archive 키를 매핑한다. 이후 operations 가 그 컴포넌트에도 `_integrity`(키로 열어 integrity_check)를 그대로 수행하므로 검증 강도 약화 없음(키 없이 열지 않음). 신규 형식(`kind='archive'`)은 매핑 대상 아님. manifest 읽기용으로 `operations.read_backup_manifest`(기존 `_manifest` 검증 래퍼) 추가. `operations.py:314`, `runtime.py:42`(import), `runtime.py:1274-1279`.
- 테스트: `test_runtime.py::test_legacy_manifest_with_archive_as_database_component_still_verifies` (구버전 형식 manifest 를 `create_backup_set` 으로 생산·`kind=database` 확인 → 현재 verify True → 새 백업 생성·verify True).
- 구버전 manifest 충실도: 테스트는 git 이력 의존(shallow clone 취약)을 피해 공개 API 로 구버전 형식을 합성한다. 합성이 실제 구버전과 같은 형식임은 별도로 확인했다 — 임시 스크립트(미커밋)로 `git show 2938a36:.../runtime.py` 의 실제 구버전 런타임이 만든 백업은 manifest 가 `archive_*=database, consumer=database, projection=database` 이고, 현재 `verify_backup` 이 그 백업에 `True` (출력 `REAL_LEGACY_VERIFY_BY_CURRENT True`).
- Red: `OperationsError: MISSING_DATABASE_KEY`.

## 변경 파일
- `feature-pack/rag-consumer/src/airag_consumer/runtime.py` (R2-M1·R2-M2)
- `feature-pack/rag-consumer/src/airag_consumer/operations.py` (`read_backup_manifest` 추가)
- `feature-pack/rag-consumer/tests/test_runtime.py` (신규 2 테스트, `DatabaseSource`·`create_backup_set` import 추가)
