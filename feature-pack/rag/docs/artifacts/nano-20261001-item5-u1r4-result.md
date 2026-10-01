model: claude-sonnet-5-5[1m]
provider: claude-code session (ft-airag-nano-r1#1, effort=high; 선임 ft-airag-nano-r1#0 이 S1~S3 일부 수행 후 컨텍스트 게이트로 승계)

# AIRAG A02 5순위 U1 r4 — 컴포넌트 프로세스 격리 구현 결과

골 원문: 최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
골의 어느 축인가: A03 닫는 증거 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — A02 5순위 U1(C12·C07), DA r10 R10-M1(libc stdio 가 틱 stdout 으로 새는 결함)·R10-m1(환경변수명이 이유 코드로 통과) 의 «설계 구현». 정본 설계 `arch-20261001-item5-u1-design.md` ⑥ S0~S7.

## 결과 한 줄
설계 ⑥ S0~S7 전부 구현. consumer 전체 pytest **288 passed**(기준선 239 → +49) · `plutil -lint` 템플릿 OK(변경 없음) · push·launchctl·운영 경로·실제 op 접촉 없음.
마지막 줄: `288 passed in 168.13s (0:02:48)` (`cd feature-pack/rag-consumer && ../rag/.venv/bin/python -m pytest tests -q -p no:cacheprovider`)

## 커밋 (feature/rag-transplant, 미 push)
| 단계 | sha | 접두 | 내용 |
|---|---|---|---|
| S1 | 0a0cb76 | [test] | R10-M1 Red — libc stdio 가 틱 stdout 으로 나오는 재현 |
| S1b | 93a49f3 | [refactor] | summarize·error_fields → `_result.py`, 잠정 `reason_codes.py`(동작 불변) |
| S1b | f14fda8 | [feat] | `build_frame`·`validate_frame`·`RESULT_MAX_BYTES` + T-frame-validate |
| S2 | bcefd7c | [feat] | `_pass_child.py`·`tests/_tick_component.py`·T-child-protocol-unit |
| S3 | b792659 | [feat] | `_run_component`·`component` 시임, `_discard_component_output`·`hooks` 삭제, 테스트 전환·S1 Red→T-native-* Green |
| S3a | 6443644 | [refactor] | `NAMES` 상수화(부모의 `operations`·sqlcipher3 import 제거) + T-names-match·T-parent-imports |
| S4 | 30b5162 | [test] | 격리 테스트 일괄 + `_tick_component.py` 모드 확장 |
| S5 | f433ba4 | [feat] | R10-m1 — 레지스트리를 AST 선언 규칙으로 재생성 + 규칙·닫힌 세계 테스트 |

변경 파일(`git diff --stat 05a2acc..HEAD`): `tick.py` · `_pass_child.py` · `_result.py` · `reason_codes.py` · `tests/test_tick.py` · `tests/_tick_component.py` · `tests/_regen_reason_codes.py` · `tests/reason_code_review.py` · **`tests/test_reason_codes.py`(신규 — S6 목록에 없던 파일; 레지스트리 테스트를 test_tick 과 분리)**. plist 템플릿·`runtime.json`·`cli.py` 변경 없음.

## 설계 ① 분류표 1~11 — «닫는 테스트» 매핑 (`tests/test_tick.py` 기준, 파일명 생략)
| # | 출력 종류 | 닫는 테스트 | 보장 |
|---|---|---|---|
| 1 | Python print·`sys.std*`·logging | `test_python_and_direct_fd_output_never_reach_the_tick`(mode chatty) · `test_native_libc_output_does_not_reach_the_tick_streams` | 보장 |
| 2 | libc stdio (R10-M1) | `test_native_libc_output_does_not_reach_the_tick_streams`(정상) · `test_native_output_before_an_exception_is_dropped_too`(예외) — 별도 자식 Python 으로 인터프리터 종료 flush 까지 관찰 | 보장 |
| 3 | 그 밖의 네이티브 버퍼 | 구조로 닫힘: `test_cli_is_imported_only_after_fds_1_and_2_are_devnull`(자식 fd 1·2 = /dev/null 이 `cli` import 전) + `test_tick_fds_are_untouched_on_every_path` | 보장 |
| 4 | 직접 fd write | `test_python_and_direct_fd_output_never_reach_the_tick`(`os.write(1\|2)`) | 보장 |
| 5 | 패스 전 dup 한 틱 fd | `test_tick_fds_are_untouched_on_every_path`(정상·native-raise·없는 component) · `test_keys_reach_the_child_on_stdin_only`(`close_fds=True`·`pass_fds` 없음) | 보장 |
| 6 | 컴포넌트의 자식 프로세스 | `test_keys_are_not_in_the_component_or_its_grandchild_environment` · `test_descendant_stream_output_does_not_reach_the_tick` | 보장 |
| 7 | 패스 뒤 존속 손자·스레드 | `test_a_forked_descendant_neither_delays_the_tick_nor_holds_the_lock` · `test_a_descendant_holding_the_result_file_sees_only_a_value_free_frame` · `test_descendant_stream_output_does_not_reach_the_tick` | 표준 스트림 비노출 보장(존속 자체는 ⑤ 2) — 아래 편차 4 참조 |
| 8 | 결과 채널 형식 오염 | `test_protocol_violations_are_static_codes_only`(bad-protocol·bad-protocol-large·oversize-frame·forged-frame·forged-extra-key·crash) · `test_an_oversized_result_is_rejected_without_reading_it`(결과 파일 `read` 0회) · `test_child_exits_3_and_writes_nothing_when_its_frame_would_be_oversized` · `test_parent_rejects_a_forged_frame_even_when_the_schema_fits` · `test_raw_component_output_is_never_persisted_in_the_result_file`(keylike·short·chatty·huge-raw·body-in-output·normal) · `test_frame_validation_accepts_only_the_closed_schema` · `test_frame_building_keeps_only_whitelisted_numbers_and_reason_codes` | 형식 오류 fail-closed 한정 |
| 9 | 컴포넌트의 파일·소켓·syslog·tty | 테스트 없음 — 범위 밖 | 보장 안 함(⑤ 1) |
| 10 | 틱 자신의 출력 | `test_tick_parent_never_imports_the_component_stack`(신선한 인터프리터, `cli`·`runtime`·`bridge`·`operations`·sqlcipher3 없음) · `test_tick_key_names_match_the_operations_registry` · 기존 `test_normal_tick_…leaks_nothing`·`test_key_shaped_error_text_never_reaches_output_or_log`·`test_short_error_value_is_not_trusted_as_a_reason_code` | 보장(whitelist 범위) |
| 11 | 틱 자신의 예외·bootstrap 실패 | `test_unavailable_component_is_a_static_code_and_releases_the_lock` · `test_child_import_failure_is_a_static_code_without_a_traceback` · `test_held_lock_skips_before_any_component_is_started` · `test_default_command_runs_the_pass_child_module` · 기존 `test_runtime_failure_is_reported_by_code_only` | 기존 수준 유지 |

R10-m1: `test_registry_matches_the_values_the_sources_declare`(드리프트) · `test_every_literal_occurrence_is_classified_and_review_entries_are_sound`(닫힌 세계) · `test_reference_baseline_does_not_widen_the_registry` · `test_compare_references_never_create_a_registry_value` · `test_code_parameters_bind_by_name_not_by_position` · `test_environment_names_and_data_are_not_reason_codes` · `test_codes_are_reported_without_reading_any_source` · `test_an_environment_variable_name_is_not_reported_as_a_code`(`OP_SERVICE_ACCOUNT_TOKEN` → `RUNTIME_FAILED`) · `test_a_declared_reason_code_is_kept`. 키 비노출(I3): `test_keys_reach_the_child_on_stdin_only` · `test_keys_are_not_in_the_component_or_its_grandchild_environment`.

## 편차 · 관찰 (설계와 어긋난 지점 — 임의 변경 없이 기록)
1. **native-raise 단언 완화(S3):** 설계는 `RUNTIME_FAILED` + `RuntimeError`. 실측은 `INTERNAL_ERROR` + `RuntimeError` — `cli.main`(`cli.py:146-152`)이 메시지(`"inside"`)가 코드 형식이 아니면 `INTERNAL_ERROR` 로 바꾸고 그 코드가 레지스트리에 들어 있다. 단언을 `{RUNTIME_FAILED, INTERNAL_ERROR}` 로 허용했다(보호 대상인 «값 비노출»은 불변).
2. **`_pass_child` 의 `from .tick import NAMES`(S2):** 설계는 «stdlib + `_result`». S3a 로 `tick` 이 `operations`·sqlcipher3 를 더는 끌어오지 않아 자식 쪽 import 도 가벼워졌다 — 해소 가능한 편차이나 코드는 바꾸지 않았다(NAMES 를 `_result` 로 옮기려면 설계 변경이라 Master 판단).
3. **S2 의 Red 단계:** 선임이 S2 를 Red 커밋 없이 구현+테스트 한 커밋(bcefd7c)으로 냈다. S1 Red(0a0cb76)는 있었다.
4. **fork 손자와 «프로젝트 락»(관찰 — 설계 문구는 충족):** 패스 «도중» fork 한 손자는 틱 락(부모만 보유)은 쥐지 않지만, runtime 이 패스 동안 쥐는 `.airag-runtime.lock`(`runtime.py:_lock`, flock)의 open file description 을 상속해 쥔다. 그 사이 다음 틱은 `PREVIOUS_TICK_RUNNING(10)` 이 아니라 `PROJECT_BUSY`(exit 40)로 끝난다(손자 종료 후 해소). 설계 I6·T-fork-descendant-no-delay 는 «skipped 가 아님»까지만 요구해 테스트 단언을 `!= EXIT_SKIPPED` 로 두었다(첫 시도에서 `== EXIT_OK` 를 단언해 이 현상을 발견). ⑤ 2 의 «손자 존속 자체는 못 막음» 범위의 연장이나 설계에 명시되지 않았으므로 **architect/Master 가 ⑤ 에 한 줄 추가할지 판단**하길 권한다.
5. **레지스트리 변화(S5):** 잠정 스냅샷 574 → 규칙 생성 528. 빠진 값 = 환경변수명(`OP_SERVICE_ACCOUNT_TOKEN`·`PATH`·`HOME`·`AIRAG_*_KEY_HEX` 등)·SQL 토큰(`BEGIN`·`COMMIT`·`NULL`…)·이미지 포맷(`PNG`·`RGB`…)·dict `"reason"` 키/`reason=` 키워드로만 쓰는 도메인 상태(`EXCLUDED_*`·`SOURCE_CHANGED_*`·`USER_REJECTED`·`INTERRUPTED_REQUEST_RECOVERED` — 설계 3.5 규칙상 `code`/`reason_code` 가 아닌 키라 데이터). 더해진 값 = `COMPONENT_PROCESS_FAILED`·`COMPONENT_PROCESS_UNAVAILABLE`. 빠진 도메인 상태 코드는 `cli.main` 이 에러 코드로 내보내지 않는 값이라(코드 = `str(exc)`) 틱 출력 변화 없음. 설계 ⑤ 4(동적 코드군 `INVALID_{FIELD}`·`CORE_*_FAILED:{code}` 는 레지스트리 밖)와 동일하게 `RUNTIME_FAILED`+type 으로 대체.
6. **수기 검토 파일은 줄 번호 키:** `tests/reason_code_review.py` 53 출현(40 값)이 `(경로, 줄, 값)` 키라 `tick.py`·`_result.py` 등을 편집하면 키가 어긋난다 — 어긋나면 닫힌 세계 테스트가 줄 번호와 함께 실패하고 `python tests/_regen_reason_codes.py` 가 같은 목록을 출력한다(설계 3.5 그대로).
7. **테스트 안정화:** 패스 자체가 sqlcipher KDF 로 수 초(부하 시 10 s 이상) 걸려 fork 손자의 sleep 을 5 s 로 하고 마커 대기를 폴링(최대 20 s)으로 했다.

## ⑤ 보장하지 않는 것 — 인용(과대 보장 없음)
1 컴포넌트의 비-표준-스트림 출구(파일·소켓·syslog·os_log·/dev/tty) 미차단 · 2 고아·손자 존속과 «부모만 보유하는 틱 락»(위 편차 4 연장 포함) · 3 타임아웃 없음 · 4 동적 이유 코드군 진단 손실 · 5 레지스트리 신선도(테스트 없이 소스만 바꾸면 구 레지스트리 — 안전 방향) · 6 `type`(예외 클래스명)은 값이 아니라는 가정 · 7 결과 파일은 정제 frame 만·디스크 한도·fd 가 마지막 close 될 때 회수 · 7a 같은 주소공간 컴포넌트의 frame 위조는 막지 않음(위협 모델 = 신뢰하는 컴포넌트의 우발 출력) · 8 로그 디렉터리·락 파일 보호의 기존 범위 · 9 launchd 환경 상속·U2 등록 전 `op` 동작 확인은 Master 몫 · 10 설치 가정 `[sys.executable, "-m", "airag_consumer._pass_child"]`.

## 환경
디스크 여유: 시작 251Gi(루트 4%) → 종료 264Gi(4%). 새 대용량 산출물 없음(테스트 임시 파일은 pytest tmp).
