# Nano item4 r2 결과 — DA r4 REJECT 결함 4건 수정

- 세션: `ft-airag-nano-r1#0` · 모델: claude-sonnet-5-5[1m]
- 골의 어느 축인가: A03 — A02 트리 4순위(C05·C06) DA r4 REJECT(blocker 1·major 3) 수정 → 재검토 PASS.
- 커밋·push 안 함. `~/.local/share/airag`·운영 키·실데이터는 읽지도 쓰지도 않았다(합성 fixture 만). 기억 본문·키 값은 출력·기록하지 않았다.
- 최종 pytest (`feature-pack/rag-consumer`, `../rag/.venv/bin/python -m pytest tests -q -p no:cacheprovider`): `218 passed in 7.48s` (기준선 217 + 신규 1)
- 격리 스크립트: `feature-pack/rag/.venv/bin/python .fable-team/bin/tour/verify_14_isolated.py` → `ALL 19 CHECKS PASSED`

## 대조 — DA 설명은 4건 모두 코드와 일치
- B1: 이전 helper 게이트는 영수증 ID 가 `status()['verified_backup_ids']`(manifest owner/state 표시 집계)에 있으면 통과였다. 실제 복원 검증(`verify_backup`)을 부르지 않았다.
- M1: 영수증의 시각·실행 연결 검사가 없었다.
- M2: `list_candidates` 가 `source_current` 를 표시용 플래그로만 쓰고 본문·인용을 그대로 반환했다.
- M3: core 쓰기를 모두 마친 뒤 로그를 읽고 썼다.

## M2 — 만료·비현재 원문 후보는 메타데이터만 (코어)
- 원인: 위와 같음. proof_messages 만 현재 원문 목록으로 제한되고 text·supporting_quotes 는 무조건 반환.
- 수정: 기존 `source_current` 판정(`_batch_context(...) is not None`)과 같은 근거로, 비현재면 `text=None`·`supporting_quotes=[]`·`proof_messages=[]`. id·종류·상태·사유·`source_current=False` 는 유지. 승인/거절/검증 쓰기 경로는 변경 없음(거절은 비현재 후보도 가능). `memory.py:1628-1646`.
- 테스트: `test_memory.py::test_expired_source_candidates_expose_metadata_only`(:1050) — 90일 초과로 시계 이동 + `refresh` 로 eligible 0 확인 후 두 상태 모두 메타만.
- Red: `AssertionError: assert 'Finish migration first' is None` (만료 후에도 본문 반환).
- 투어 표시: 비현재 후보는 «본문·인용을 숨깁니다(승인·검증 불가, 거절만 가능)» 로 출력(`14-memory-confirmation.py` 후보 출력부).

## B1·M1·M3 — helper (`.fable-team/bin/tour/memory_confirmation.py`, gitignore 영역)
- B1 수정: `decide` 가 이번 호출에서 `app.verify_backup(영수증 ID)` 를 실제로 실행해 `verified is True` 를 요구(`verified_receipt`, :59). 목록 포함 여부는 더 이상 근거가 아니다. 실패는 `BACKUP_VERIFICATION_FAILED`.
- M1 수정: 영수증에 `run`(투어 실행 시작 시 생성한 uuid, 환경변수 `AIRAG_TOUR14_RUN` 로 모든 셀 서브프로세스에 전달)과 `at`(`app.clock()` 기준)을 기록. `decide` 는 `run` 일치(`BACKUP_NOT_FROM_THIS_TOUR_RUN`, run 없음은 `TOUR_RUN_REQUIRED`)와 나이 ≤ 6시간(`BACKUP_RECEIPT_STALE`)을 요구(`receipt_for_run` :46, `MAX_RECEIPT_AGE_S` :14). summary·rollback 도 같은 run 연결을 요구. `backup` 도 run 없으면 거부. 투어 본체는 `14-memory-confirmation.py` 에서 run id 를 생성해 `context['env']` 로 주입.
- M3 수정: 순서를 «게이트 → 기존 로그 읽기 → **의도 기록을 먼저 디스크에 쓰기** → core 쓰기 → 결과로 갱신» 으로 변경(`decide` :81). 로그 읽기/의도 쓰기 실패는 core 쓰기 전에 중단되어 core 무변경. 마지막 갱신 쓰기만 실패하면 core 는 이미 적용됐으므로 예외로 돌려주지 않고 `log_complete: False` 로 결과를 반환하며, 디스크에 남은 의도 항목(`status: pending`)이 사용자의 결정 기록이 된다(투어가 경고 출력, summary 는 `pending` 으로 집계). 로그·영수증에는 id·행동만 저장(본문·인용 없음).
- Red: helper 는 gitignore 영역이라 이전 파일이 보존되지 않아 helper 단계의 «수정 전 재실행» 은 하지 못했다. 수정 전 거동의 증거는 DA r4 가 같은 재현으로 기록한 출력(위조 ID → materialized 1, 이틀 영수증 → materialized, 로그 실패 → 기억 0→1·로그 `[]`)이며, 아래 격리 스크립트가 동일 시나리오를 수정 후 거부로 확인한다.

## 격리 검증 스크립트 `verify_14_isolated.py` 실행 결과 (19/19)
합성 fixture 만 사용, 운영 경로 미접촉. 노트북 셀의 helper 서브프로세스는 합성 런타임으로만 구동.
- B1: 위조 manifest ID 가 status 목록에는 나타나는데도 `decide` 는 `BACKUP_VERIFICATION_FAILED`, core 무변경 ✔
- M1: run 없음 `TOUR_RUN_REQUIRED` · 다른 run `BACKUP_NOT_FROM_THIS_TOUR_RUN` · 이틀 지난 영수증 `BACKUP_RECEIPT_STALE`, core 무변경, 새 영수증은 통과 ✔
- M3: 손상 로그 → 중단·core 무변경 ✔ · 의도 쓰기 OSError → 중단·core 무변경 ✔ · 마무리 쓰기 OSError → 반환 `log_complete=False`·core 적용·디스크에 pending 의도 보존 ✔ · 로그·영수증에 본문·인용 없음 ✔
- 정상 7셀: 종료 0·`[완료]` 7개, 전체실행이 쓰기 셀 앞에서 정지, 범위 밖 번호 재질문, 결과 기억 3·대기 0 ✔

## 변경 파일
- git 추적: `feature-pack/rag-consumer/src/airag_consumer/memory.py` · `tests/test_memory.py`(+1)
- gitignore 영역(`.fable-team/bin/tour/`): `memory_confirmation.py` · `14-memory-confirmation.py` · `verify_14_isolated.py`(신규)
- 이전 결과의 선행조건(설치 런타임 재설치, 투어 파일 gitignore)은 그대로 유효.
