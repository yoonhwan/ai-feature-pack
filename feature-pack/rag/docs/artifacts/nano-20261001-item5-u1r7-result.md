model: claude-sonnet-5-5[1m]
provider: claude-code session (ft-airag-nano-r1#1, effort=high)

# AIRAG U1 r7 — DA 후속 minor R11-m3 · R11-m4 · R12-m1 결과

골 원문: 최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
골의 어느 축인가: A03 · A02 5순위 U1(C12·C07) — DA 후속 목록 소형 라운드(HELM #1930, launchd 등록을 막지 않음). 발주 #1932.

## 결과
consumer 전체 pytest 마지막 줄: `341 passed in 214.35s (0:03:34)` (기준선 330 + 신규 11: m3 5 · m4 2 · R12-m1 4). **`src/` 변경 0**(`git diff --stat -- src` 빈 출력) · **`reason_codes.py` 528개 diff 0**(`python tests/_regen_reason_codes.py` 재생성 후 diff 없음, `current().registry == REASON_CODES`). push 없음. 디스크 여유 194Gi(5%; 시작 때 245Gi — 다른 세션 사용분, 이 작업의 대용량 산출물 없음).

| ID | 커밋 | 접두 |
|---|---|---|
| R11-m3 | `0de1c4c` | [fix] (생성기 + 회귀 테스트) |
| R11-m4 · R12-m1 | `98fa128` | [test] |

## R11-m3 — 생성기가 동명 함수 바인딩을 합침
- 원인: `_regen_reason_codes.build_bindings` 가 callee 를 짧은 이름으로만 보고 같은 이름의 code 파라미터 위치를 union(`events._identifier(value, field)` vs `lifecycle._identifier(value, code)` 등).
- 변경(`tests/_regen_reason_codes.py`): `Bindings`(정의 위치별 `local[path][name]` + 전체 `anywhere[name]`). 조회 규칙 — 일반 이름 호출·`self`/`cls` 수신자는 **호출 모듈 자신의 정의 우선**, 그 외 수신자·타 모듈 정의는 **모든 정의의 binding 이 일치할 때만** 바인딩하고, 불일치(같은 이름·다른 signature)는 모호함 → `structural`(수기 검토로 올림, 조용한 union 없음).
- 테스트(`tests/test_reason_codes.py`): `test_a_same_named_function_with_a_field_parameter_does_not_declare_its_literal`(`PATH` 가 선언·레지스트리에 안 들어감) · `test_a_local_definition_wins_for_a_plain_call` · `test_an_imported_name_with_conflicting_definitions_is_ambiguous_not_guessed` · `test_a_method_call_on_another_receiver_with_conflicting_definitions_is_ambiguous` · `test_an_unambiguous_name_defined_in_another_module_still_binds`.
- Red: 합성 두 모듈(`reason.py`: `_identifier(value, code)`, `data.py`: `_identifier(value, field)` + `_identifier(v, "PATH")`)에서 수정 전 생성기가 `PATH` 를 declaration 으로 분류 — 위 3건 실패(필드 파라미터·import 충돌·수신자 충돌), 2건은 보존 확인으로 통과.
- 실제 소스: 새 모호함으로 올라온 미분류 0, 수기 검토 항목 추가 0, 레지스트리 528 불변(분류 분포는 declaration 866(+1 = 직전 refkey 수정의 `_error` 호출) · data 77 · structural 53 · compare 6).

## R11-m4 — huge-raw 가 정제 대상 StringIO 를 키우지 않음
- 변경: `tests/_tick_component.py` 에 모드 `huge-cli-stdout`·`huge-cli-stderr` 추가 — 합성 `airag_consumer.cli` 모듈로 `child_main` 이 실제로 넘기는 stdout/stderr StringIO 에 ~5 MiB 비-JSON(`MARKER_HUGE_CLI`)을 쓴다. 기존 `huge-raw`(표준 스트림 부하)는 유지.
- 테스트: `test_megabytes_of_raw_cli_output_shrink_to_a_tiny_frame`(2 파라미터) — 결과 파일 < 512 바이트·`validate_frame` 통과·stdout 건: exit 40 + `RUNTIME_OUTPUT_INVALID`(exit 0 이지만 JSON 아님), stderr 건: `RUNTIME_FAILED` · `MARKER_` 가 결과 파일·틱 출력·로그에 없음.
- Red: 해당 없음 — src 는 올바르고 빠진 것은 테스트 대상이라 신규 테스트가 처음부터 통과(DA 독립 probe: 6,000,000바이트 입력 → 65바이트 파일과 일치하는 방향).

## R12-m1 — reference-config 틱 회귀의 키 공급 변형
- 변경(`tests/test_tick.py`): `test_a_reference_config_ticks_in_every_key_supply_variant` — {스토어 3키를 env 로 | credentials/`stub_op` 로 op 호출} × {profile 키 남김 | 설치 후 3키 전용(profile·reference 키 모두 없음)} 4 변형. 각 변형: exit 0·`MISSING_OR_INVALID` 없음 · op 변형은 합성 op 3회 호출(레퍼런스 3개) · 자식 stdin = 스토어 3키 그대로 · 자식 env 에 reference·스토어 키 없음 · profile 키 존재 여부가 변형과 일치. 기존 key-loaded 변형(`test_a_reference_config_ticks_without_any_reference_key`)은 유지.
- Red: 해당 없음 — DA 가 같은 경로를 실행해 현재 동작이 정상임을 확인한 «회귀 고정» 이라 처음부터 통과.

## 범위·금지 확인
테스트·테스트 도구만 변경(`tests/_regen_reason_codes.py`·`tests/test_reason_codes.py`·`tests/_tick_component.py`·`tests/test_tick.py`). 설계 ⑤2 문구·`runtime.json`·launchd·운영 경로·실제 op 접촉 없음. 신규 *.md 는 이 파일 하나.
