model: claude-sonnet-5-5[1m]
provider: claude-code session (ft-airag-nano-r1#1, effort=high)

# AIRAG U1 r5 — DA r11 minor R11-m1·R11-m2 소형 패치 결과

골 원문: 최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
골의 어느 축인가: A03 · A02 5순위 U1(C12·C07) — DA r11 PASS 의 minor R11-m1·m2 (HELM #1828, 발주 #1829).

## 결과
커밋 `4dd56b7` ([fix], 미 push) · consumer 전체 pytest 마지막 줄: `302 passed in 204.63s (0:03:24)` (기준선 288 + 신규 14). 구조 변경 없음 — 행위 수정 2곳 + 테스트.

| ID | 원인 | 수정 위치 | 테스트 | Red 요약 |
|---|---|---|---|---|
| R11-m1 | `validate_frame` 이 code 타입 검사 전에 frozenset membership 수행 → list/dict 는 TypeError → 부모 exit 50 | `_result.py` validate_frame 의 code 검사: `isinstance(code, str)` 아니면 None | `test_a_non_string_code_is_a_rejected_frame_not_an_internal_error[list/dict/null/int]`(실제 tick → exit 40·`RUNTIME_OUTPUT_INVALID`·`MARKER_CODE` 비노출) · `test_validate_frame_rejects_a_non_string_code`(list·dict·None·7·True·bytes) · 컴포넌트 모드 `forged-code-*` | list·dict 실제 tick 2건 + 단위 2건 실패(`TypeError: unhashable type`); null·int·True·bytes 는 기존에도 거부 |
| R11-m2 | `bytes.fromhex` 가 공백을 허용 → 길이 64 + 공백 2개 = 31바이트 키 수락 | `_pass_child.py` _read_keys: `_KEY = [0-9a-fA-F]{64}` fullmatch 후 fromhex(→ 항상 32바이트) | `test_child_rejects_bad_stdin_without_any_result` 에 4 케이스 추가(후미 공백 2·`\t\n`·앞뒤 공백·내부 공백; 각각 64자·31바이트 decode) | 4건 모두 종료코드 0 으로 수락(기대 2·빈 결과) |

범위 밖(후속): m3·m4. 금지 사항(push·launchctl·kill·운영 경로·실제 op·`runtime.json`) 접촉 없음. 신규 *.md 는 이 파일 하나.
