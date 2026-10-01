model: claude-sonnet-5-5[1m]
provider: claude-code session (ft-airag-nano-r1#1, effort=high)

# AIRAG 상시 틱 exit 40 `MISSING_OR_INVALID_REFERENCE_SOURCE_KEY` — 권고 C 구현 결과

골 원문: 최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
골의 어느 축인가: A03 · A02 5순위 U1(C12·C07) — 사용자 수동 1회 exit 40 의 설계 구현(reference 키 검사를 사용처 `search` 로 지연). 설계 `arch-20261001-item5-refkey-design.md` ⑤ R0~R5 + DA minor D1·D2.

## 결과
커밋 `6b34a70` ([fix], 미 push) · consumer 전체 pytest 마지막 줄: `330 passed in 202.43s (0:03:22)` (기준선 302 + 신규 28). 변경 3파일: `src/airag_consumer/runtime.py` · `tests/test_runtime.py` · `tests/test_tick.py`. `tick.py`·`_pass_child.py`·`_result.py`·`reason_codes.py` 무변경(레지스트리 드리프트·닫힌 세계 테스트 통과 = 값 변화 0). R0 호출자 grep: 코드·테스트 쪽 사용처는 `runtime.py` 두 곳·레지스트리·`test_runtime.py` 한 곳뿐(예외를 잡아 처리하는 곳 없음). 디스크 여유 245Gi(4%).

## 코드 변경 (runtime.py, 행위 변경만)
1. 생성자: reference 절이 있어도 변수가 None/`""` 이면 `reference_source_key = None` 으로 통과. 비어 있지 않으면 기존 그대로(str·64hex fullmatch → 아니면 `MISSING_OR_INVALID_REFERENCE_SOURCE_KEY`, 스토어 3키·profile 키와 같으면 `REFERENCE_SOURCE_KEY_MUST_BE_DISTINCT`). 프로필 키 처리(None/"" 허용)와 같은 모양.
2. `search`: `INVALID_SEARCH_REQUEST` 검증 직후, `with self._lock()` 앞에서 reference 절이 있고 키가 None 이면 같은 코드로 거부. 기존 후속 방어 분기는 유지(이중 방어).

## R1~R6 «닫는 테스트»
| 불변식 | 닫는 테스트 |
|---|---|
| R1 reference 절 없음 = 불변 | `test_a_config_without_reference_is_unchanged_by_the_reference_key` |
| R2 None·`""` → 생성 통과 | `test_reference_key_may_be_absent_empty_or_none_at_construction`(absent·""·None 3종) · 통합 `test_a_reference_config_ticks_without_any_reference_key`(틱 exit 0, 자식 env 에 reference 키 없음·stdin 은 스토어 3키 그대로) |
| R3 비어 있지 않은 부정 값 → 생성자 거부 | `test_a_present_but_malformed_reference_key_is_still_refused_at_construction`(`" "`·`zz`·64 z·63/65자·공백 포함 64자(후미 공백·`\t\n`)·0·False·`b""`·bytes 11종) · 통합 `test_a_garbage_reference_key_still_stops_the_tick_without_echoing_it`(exit 40·값 비노출) |
| R4 distinct | `test_a_reference_key_equal_to_any_other_key_is_refused`(스토어 3키 각각 + profile 키 4종) |
| R5 search 는 락·원장 이전에 거부 | `test_search_without_the_reference_key_is_refused_before_any_lock_ledger_or_search`(`_lock`·`_open_ledger`·`_open_projection`·bridge `search_history` spy 호출 0회 · 인자 검증 `INVALID_SEARCH_REQUEST` 가 guard 보다 먼저 — 공백 질의·limit 0) |
| R6 키 없으면 reference 검색·투어 DB open·snapshot 없음 | 위 R5 테스트(`reference-snapshots` 디렉터리 미생성) · `test_run_once_and_status_never_need_the_reference_key`(키 없이 init→run --once --save→status 성공, `reference-*.db` 0개, 원본 투어 DB 바이트 불변) |
| 보존 회귀(D1) | `test_a_missing_store_key_is_still_refused_without_a_reference_key`(스토어 3키 하나씩 제거) · `test_initial_bootstrap_still_requires_the_profile_key_without_a_reference_key` · 기존 `test_reference_config_requires_exact_allowlist_and_separate_source_key`(distinct·allowlist; 키 없음 단언은 새 계약 테스트로 이전) · 기존 combined search 테스트(키 있음 → 통과, 회귀 0) |

D2 보장 문구: **reference 키가 없으면 reference 검색/helper·그 경로의 source DB open·snapshot DB 생성이 없다**(R5·R6 테스트). profile bootstrap 은 별도 profile 키로 보호된다 — `test_a_reference_source_that_is_also_the_profile_source_is_read_with_the_profile_key_only` 가 `reference.source_db` 를 profile source 와 같은 합성 파일로 두고 reference 키 없이 `init` 이 명시 profile 키로 읽혀 성공하며 snapshot 이 생기지 않음을 기록한다.

## Red 요약
수정 전 7건 실패(전부 생성자의 `MISSING_OR_INVALID_REFERENCE_SOURCE_KEY` 거부): 생성 통과 3종 · run_once/status · search 조기 거부 · profile-source 동일 파일 init · 틱 통합(exit 40). 부정 값·distinct·스토어 키·profile bootstrap 보존 테스트는 수정 전에도 통과(현재 동작 보존). 작성 중 테스트 헬퍼 오류 1건(garbage 환경값을 곧바로 pop)을 고쳤다 — 코드 문제 아님.

## 잔여(설계 ⑥ 인용)
상시 서비스 안의 reference 병합 검색 경로는 만들지 않았다(필요 시 키 주입은 별도 사용자 결정) · 수동 `search` 의 reference 키 운영 주입 방법 문서 없음 · 생성자 계약 변경(키 없이 생성 허용)은 코드 구조로 추론한 의도 · 이 수정은 DA 코드 게이트 대조용이다. runtime.json·launchd·운영 경로·실제 op 접촉 없음, push 없음.
