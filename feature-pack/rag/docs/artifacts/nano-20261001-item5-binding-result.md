model: claude-sonnet-5-5[1m]
provider: claude-code session (ft-airag-nano-r1#1, effort=high)

# AIRAG 재부팅 st_dev 변경 binding 불일치 — 권고 A(내용 연속성) 구현 결과

골 원문: 최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
골의 어느 축인가: A03 · A02 5순위 U1(C12·C07) — 재부팅으로 st_dev 가 바뀌어 수집기가 같은 파일을 거부(exit 40 `COLLECTOR_SOURCE_BINDING_MISMATCH`)하는 구조 결함. 설계 `arch-20261001-item5-binding-design.md` ⑤ B0~B6 · 사용자 명시 답 «① 내용 연속성 수용»(HELM #2000). 발주 #2001.

## 결과
consumer 전체 pytest 마지막 줄: `364 passed in 249.47s (0:04:09)` (기준선 347 → B1 후 348 → +16). `reason_codes.py` 528 diff 0(재생성 불변) · `tick.py`·`runtime.py` 무변경 · push 없음. 디스크 여유 시작 195Gi → 종료 193Gi.

| 단계 | 커밋 | 접두 |
|---|---|---|
| B1 | `9c7a51d` | [refactor] — `_incarnation` 헬퍼 추출(동작 불변)·골든 패리티·review 줄 키 443→444 |
| B2+B3 | `9a18980` | [fix] — 비교 규칙 변경 + drift 테스트(Red 3건 포함; Red 단독 커밋은 빌드를 깨므로 같은 커밋) · review 줄 키 444→451 |
| B4 | `e2226ec` | [test] — 보존·경계·의도 수용 |

변경 파일: `feature-pack/rag-consumer/src/airag_consumer/collector.py` · `tests/test_collector.py` · `tests/reason_code_review.py`(collector.py 줄 키 2건만). **계약 문구의 `feature-pack/rag/src/airag/…collector.py` 는 오기 — 실제 collector 는 consumer 패키지에 있다.** core(`feature-pack/rag`) 는 이 변경이 닿지 않아 실행하지 않았다(변경 파일이 consumer 3개뿐).

## 코드 변경 (`collector._load_or_create_source`)
- 행 없음: 지금과 동일(device·inode·incarnation 저장, 스키마·값 불변).
- 행 있음: 일치 요구 = `source_path`·`real_path`·`inode`·`expected_session_id`·`tenant`·`project`·`normalized_source_id`. **device 는 비교하지 않는다.** 저장 incarnation 은 `_incarnation(real_path, session, 저장 device, 저장 inode)` 와 같아야 한다(저장 행 자기 일관성). 통과하면 저장 incarnation 을 그대로 사용(재계산·갱신 없음). DB 쓰기 추가 없음.

## B1~B6 «닫는 테스트» (`tests/test_collector.py`)
| 불변식 | 닫는 테스트 |
|---|---|
| B1 첫 수집·헬퍼 동작 불변 | `test_incarnation_matches_the_golden_value_and_the_stored_row`(골든 문자열은 B1 이전 인라인 공식으로 계산·실제 수집 행과 일치) · 기존 수집 테스트 전부 |
| B2 일치해야 하는 필드 | `test_every_identity_field_other_than_the_device_is_still_enforced`(path 별칭 하드링크·session·tenant·project·저장 `normalized_source_id` UPDATE 5종, 같은 source_id) · `test_a_replacement_file_is_still_rejected_even_when_the_device_also_changed` · 기존 `test_detects_file_replacement_even_when_bytes_match` |
| B3 device 불요 | `test_a_changed_device_number_does_not_stop_collection_of_the_same_file`(새 이벤트 수집·두 이벤트 `producer_epoch` 동일·저장 device/inode/incarnation 불변) · `test_repeated_device_changes_keep_collecting_with_a_monotonic_chain`(shift 1·2·5 연속, offset 단조·이벤트 4) |
| B4 incarnation 자기 일관성·불변 사용 | `test_a_tampered_stored_row_is_rejected_by_its_own_consistency_check`(incarnation·device·inode 각각 변조) · 위 epoch 불변 단언 · `test_a_pending_plan_replays_after_a_device_change_without_touching_the_epoch`(lost-ack 뒤 재시작 직전 device shift: plan finalized·`first_seen_at`·`normalized_sha256`·events·source 행 불변) |
| B5 prefix·절단 검사 유지 | `test_a_changed_device_does_not_bypass_the_prefix_and_truncation_checks`(`SOURCE_PREFIX_REWRITTEN`·`SOURCE_TRUNCATED`) |
| B6 새 DB 쓰기 없음 | 위 B3 테스트의 «저장 행 불변» 단언 |
| zero-prefix (설계 3.2) | `test_a_row_with_nothing_consumed_yet_survives_a_device_change`(정상 `captured_byte_limit=0` · 첫 레코드 전 예외 중단 2종 — 성공·epoch 불변) |
| 의도 수용 | `test_cross_volume_clone_with_the_same_prefix_is_accepted_by_design`(docstring 에 계약 명시) |
| review 줄 키 | `tests/test_reason_codes.py` 통과 + `reason_codes.py` 재생성 diff 0 |

선택 T-tick-drift-integration 은 구현하지 않았다 — device shift 가 같은 프로세스의 `collector.os` 대체라 틱의 자식 프로세스 경계를 넘지 못한다(별도 합성 수단이 필요해 이번 범위 밖).

## Red 요약 · 규칙 과완화 점검
수정 전 drift 3건 실패(전부 `COLLECTOR_SOURCE_BINDING_MISMATCH` — prefix 테스트는 그 때문에 `SOURCE_PREFIX_REWRITTEN` 단언이 못 닿음). B4 의 보존·거부 계열은 수정 직후 처음부터 통과. **뮤테이션 점검(되돌림 확인)**: 자기 일관성 검사를 빼면 변조 테스트 2건이, inode 비교를 저장값으로 바꾸면 교체 2건 + 변조 3건이 실패 — 테스트가 과완화를 잡는다. 작성 중 1건 정정: `CollectorResult.accepted_count` 가 누적값이라 «+1» 단언을 `committed_native_offset == 파일 크기` 로 교체.

## 3.2 계약 인용 (유지/비유지 범위)
개정 «같은 소스» = `(real_path, inode 번호, session id, tenant, project)` 일치 + **이미 소비한 prefix 의 sha256 일치** + 행의 incarnation 이 저장 값으로 자기 일관적. `st_dev` 는 재부팅·마운트 순서에 따라 바뀌는 값이라 신원이 아니다.

| 사건 | 현재 | 개정 |
|---|---|---|
| device 만 바뀜 | 거부(결함) | **수용** |
| 새 inode(같은 바이트) | 거부 | **거부** |
| 경로·세션·tenant·project 변경 | 거부 | **거부** |
| 소비 prefix 재작성 / 절단 | `SOURCE_PREFIX_REWRITTEN` / `SOURCE_TRUNCATED` | **동일** |
| 다른 볼륨 동일 inode 번호 + 같은 경로·세션 + 소비 prefix 복제 + 다른 suffix | 거부 | **수용**(기존 incarnation·producer_epoch) |
| 저장 행 자체 변조 | 거부 | **거부** |

**의도된 비보장: 물리 볼륨 동일성은 보장하지 않는다.** 같은 prefix 를 가진 파일은 같은 소스의 이어받기로 취급하므로 다른 볼륨에서 prefix 를 복제해 다른 내용으로 이어 쓴 «분기된 사본»의 suffix 를 기존 epoch 로 수용한다(사용자 명시 수용 ①). «다른 볼륨의 파일 교체 일반까지 거부한다»는 확장 해석은 무효다. zero-prefix 행(`captured_byte_limit=0`·첫 레코드 전 중단)은 소비한 바이트가 없어 B2 필드만이 증거이며 «과거 내용 검증»의 의미를 부여하지 않는다. B4 는 unkeyed hash 의 자기 일관성 검산일 뿐 인증이 아니다. 백업 복원 후 재방문도 같은 정책이다.

## 잔여 (설계 ⑥ 인용)
«device 단독 원인»은 우선 가설(운영 DB 미열람) — 사후 확인은 수정 뒤 수동 1회 exit 0 · 진단 한계(불일치 필드명 미기록)는 후속 제안 · 수정 뒤 첫 패스는 큰 증분(소스 ~46MB)이 여러 틱으로 소화됨 · 투어 도구 `first_collection.py` 의 plan device 비교는 별개 경로 · 운영 DB·runtime.json·launchd·실제 rollout 파일·op 접촉 없음.
