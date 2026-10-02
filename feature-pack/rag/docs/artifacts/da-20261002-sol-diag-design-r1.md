model: gpt-6.1-sol
provider: headroom

# AIRAG U2 published 진단 설계 DA r1 — REJECT (blocker 0, major 2, minor 2)

**판정: REJECT — blocker 0, major 2, minor 2.** 발주 #2085의 major 0 기준을 충족하지 못한다. 확정된 **any-fail→degraded / exit 0 유지 / 값 비노출**는 재론하지 않는다. 정적 코드 슬롯과 registry 게이트 방향은 타당하지만, 설계가 허용한 총계/items 불일치 처리와 proposed validator의 관계 검증이 서로 맞지 않는다. 이 반례를 테스트 명세에 반영해야 한다.

- 세션: `ft-airag-da-codex#0`, 발주/직전 확인 gpt-6.1-sol low, provider=headroom. 창 크기·fast 서비스 등급은 미노출.
- HEAD: `90352c2a2a0935dc07fb0c65004938729f34a697`.
- 설계: `arch-20261002-published-diag-design.md`, SHA-256 `edd731fe3dc2353f21447c7326dfe3cfcf046c41890c79918e6ec8c9d253ee28`.
- Serena로 `_result.summarize/validate_frame`, `runtime.AIRAGRuntime._publish`, bridge·SyntheticBridge를 대조했다. 설계의 알고리즘/추가 분기만 별도 Python 메모리에서 구성해 합성 입력으로 공격했다. source/test/운영 DB는 변경하지 않았다.

## 공격 ① — 문자열 코드 게이트

설계 §3.1(2)의 `str → _CODE.fullmatch → REASON_CODES membership → fallback` 순서는 안전한 방향이다. list/dict/None/int/bool·메시지·key-like 64hex·경로를 합성으로 넣었을 때 CORE_PUBLICATION_FAILED로 치환됐다. 공개 코드명만 통과하고 메시지는 담지 않는다. 부모의 string 검사도 membership보다 먼저 있어 non-hashable 값이 TypeError로 가는 경로를 막는다.

현재 frozen 528개에는 설계의 주요 코드와 CORE_PUBLICATION_FAILED가 모두 있고 pure 64hex 코드 literal은 없다. 이 검토에서 등록된 코드명 자체를 secret 값 누출로 분류하지 않는다. malicious valid-frame 위조 방지로 확대할 수는 없으며 기존 trusted/noisy component 범위를 유지한다.

## Major D1 — attempted/succeeded 우선 정책이 any-fail·합계 불변식과 충돌한다

- 앵커: 설계 §3.1(3), 현재 `_result.py:summarize`의 published 블록, `tick.py:main`의 status 결정 지점.
- 명세는 failed 총계를 max(0, attempted−succeeded)로 우선하고 코드 count는 failed_items에서 독립 계산한다. 마지막 `other=max(0,total−top3sum)`는 top3sum이 total보다 큰 것을 고치지 못한다.
- 문서대로 구성한 합성 결과:

| 입력 | failed items | published_failed | rank count 합+other | status |
|---|---|---|---|---|
| attempted=1, succeeded=1, 실패 item 1개 | 1 | 0 | 0 | **ok** |
| attempted=1, succeeded=0, 동일 코드 실패 item 5개 | 5 | 1 | **5** | degraded |
| attempted=3, succeeded=0, items=[] | 0 | 3 | 3(other) | degraded |

첫 경우는 실패 item이 존재하는데 0건으로 요약해 false-ok를 다시 만든다. 둘째는 `top3sum+other==failed` 불변식이 깨진다. 이 불일치 입력들을 proposed validator도 수락했다. 음수/성공 수 초과도 `max(0, ...)`가 가려줄 수 있다.

**정상 runtime과 구분:** 현재 `_publish`는 bridge의 반환을 list로 요구하고 attempted=len(result), succeeded=`ok is True` 개수, items=result를 같은 list에서 만든다. 현재 정상 producer 출력에서 이 모순이 관찰됐다고 주장하지 않는다. major는 설계가 직접 허용·설명한 malformed/inconsistent 입력 정책의 모순과 false-ok 가능성이다.

보정: 정상 aggregate/items 계약과 어긋난 데이터의 처리를 명시한다. 정합 검증으로 기존 protocol-invalid 경로에 넘길지, 숫자/항목을 일관되게 조정해 실패 신호를 보존할지 하나의 정책을 정해야 한다. legitimate 발행 실패의 exit 0/degraded 계약은 유지한다. 실패 신호를 사라지게 하거나 집계 합이 total을 초과하는 조정은 허용하지 않는다. T1/T2/T3의 정상 입력 외에 위 불일치·성공 수 초과·음수·bool 총계를 별도 공격 테스트로 추가한다.

## Major D2 — validate_frame은 타입만 검사하고 top-3 구조를 검증하지 않는다

- 앵커: 설계 §3.1(4) 및 T7, 현재 `_result.py:104-120 validate_frame`.
- 제시된 변경은 SUMMARY_CODE_KEYS의 known str 분기만 추가한다. code/count pairing, 연속된 순위, 중복 코드, 양수 count, 정렬, failed/other 관계를 검사하는 계약이 없다. `FRAME_KEYS`가 닫혀 있어도 summary 진단 그룹의 관계는 닫히지 않는다.
- 그 한 분기와 기존 검증을 그대로 구성하면 아래는 **모두 valid**다:

```text
unpaired: code_1=PROVIDER_TIMEOUT (failed/count/other 없음)
rank_hole: failed=1, code_3=PROVIDER_TIMEOUT,count_3=1,other=0
zero_with_rank: failed=0,code_1=PROVIDER_TIMEOUT,count_1=1,other=0
negative: failed=-1,other=-1
sum_mismatch: failed=1,code_1=PROVIDER_TIMEOUT,count_1=5,other=0
rank_unsorted: failed=3, rank1 count1=1, rank2 count2=2,other=0
```

이들은 문자열 registry 게이트를 통과하면서 진단 의미를 깨뜨린다. 원 값 노출을 재현한 것은 아니지만, closed top-3 protocol과 parent 재검증이 목표대로 작동한다고 판정할 수 없다.

보정: 진단 그룹 전체가 없으면 기존 summary를 허용하되 새 그룹이 있을 때 요구 필드와 관계를 정의한다. ranks는 1..k의 code/count 쌍, count는 정확한 양수 int, code는 중복 없이 registry 안, 순서는 count 내림차순/code 오름차순, failed/other는 정확한 비음수 int, sum(counts)+other==failed를 검증한다. total 0의 rank 부재와 total>0/items 부재의 other 처리도 D1 정책과 맞춘다.

**T7의 positive도 바꿔야 한다.** 현재 “known code 하나만 있는 summary면 통과”는 pairing/required-group 검증과 충돌한다. 완전한 정상 그룹으로 바꾸고, 위 구조 반례를 parent forged-frame 경로까지 검사한다. 임의의 외부 데이터를 인증하는 검증으로 확대하지 않는다.

## Minor

### m1 — frozen 값 불변과 literal 출현/수기 줄키 불변은 다르다

- 앵커: 설계 §3.3/⑥의 “새 코드 리터럴 없음·재생성 불필요”, `tests/_regen_reason_codes.py:_kind`, `tests/reason_code_review.py`.
- 새 helper가 `return "CORE_PUBLICATION_FAILED"`를 쓰면 기존 registry의 **값**이지만 새 literal **출현**이다. pure AST probe는 이 Return을 structural로 분류했고 검토 항목 없이 unclassified 1개였다.
- 기존 `_result.py`의 RUNTIME_FAILED Return·FRAME_CODES 집합도 59/66/83행 수기 reference 키로 관리된다. summarize 확장/helper 추가로 이 위치가 이동할 수 있다. tick.py의 수기 키도 확인해야 한다.
- 보정: reason_code_review.py의 새 reference/이동 키 갱신을 허용하고 값 집합·렌더의 frozen 528 불변과 미분류/모순 0을 각각 확인한다. generator의 전역 규칙을 넓힐 필요는 없다.

### m2 — 테스트 caller 형태와 확정 입력을 문서에 정합시킨다

- 앵커: §⑤ SyntheticBridge 설명, §④/⑩ 사용자 조건 확인.
- `runtime._publish`는 bridge.publish_pending_windows의 반환이 **list**여야 한다. 실패 dict 하나를 직접 반환하는 fixture는 INVALID_BRIDGE_RESULT로 끝나 exit 0/degraded 경로를 시험하지 않는다. `[failure_item,...]`를 반환하거나 별도 synthetic CLI data를 쓰되 시험 경로를 구분한다.
- 최신 발주의 any-fail·exit 0은 이미 확정이다. §④/⑩의 any-fail vs 전부-실패 사용자 재확인 문구를 없애고 확정 입력으로 고정한다. 설계의 high 권고도 사용자의 low/fast 유지 지시를 바꾸는 근거로 쓰지 않았다.

## T1~T10의 mutation 관점

- T1/T3/T4는 all-fail-only status mutation 및 failed=0/positive 분기 오류를 잡는 적절한 정상 사례다.
- T2는 coherent 입력의 sorting/truncation/other 계산 오류는 잡지만 D1의 overflow·false-ok는 입력에 없다. 모든 정상 예제가 aggregate/items 일치 상태면 잘못된 max clamp가 계속 통과한다.
- T5/T6/T7/T8은 registry/type 게이트의 누락을 겨냥한다. T5의 “어디에도 값 없음”은 로그뿐 아니라 **쓰기 전 정제 결과 파일**도 관찰해야 한다. 부모가 뒤늦게 잘못된 코드를 거부해도 raw key-like 값이 child 파일에 쓰였다면 비노출 계약을 충족하지 못한다.
- T7/T8의 현재 입력만으로 D2의 pairing/rank/산술 검증 omission을 잡지 못한다. 특히 T7의 known-code-only positive가 그 약화를 고정한다.
- T9/T10의 기존 오류 status·pure import 보존 방향은 맞다. 아직 새 구현/테스트가 없으므로 위는 실제 새 테스트를 실행한 PASS가 아니라 명세의 검증력 분석이다.

## 독립 증거·범위

설계 알고리즘만 메모리 prototype으로 구성해 합성 입력을 넣었다. published source는 실제 DB/서비스를 호출하지 않았다. 알려진 코드 게이트의 합성 값은 모두 fallback이었고, D1/D2의 counterexample은 그대로 통과했다.

현재 기준선의 pure frame/registry 관련 선택 실행:

```text
../rag/.venv/bin/python -m pytest tests/test_tick.py tests/test_reason_codes.py -q -p no:cacheprovider \
  -k 'frame_validation or frame_building or registry or code_parameters or reference_baseline or compare_references or environment_names or codes_are_reported'
9 passed, 94 deselected in 5.52s
exit 0
```

```text
CURRENT_REGISTRY_COUNT 528
CURRENT_REGISTRY_VALUES_MATCH true
CURRENT_REGISTRY_RENDER_MATCH true
CURRENT_REGISTRY_UNCLASSIFIED 0
CURRENT_REGISTRY_CONTRADICTIONS 0
DESIGN_CODES_ALL_ALREADY_FROZEN true
FROZEN_RAW_HEX64_LITERAL_PRESENT false
NEW_FALLBACK_LITERAL_KIND structural
NEW_FALLBACK_LITERAL_UNCLASSIFIED 1
```

현재 source와 baseline 통과를 새 설계의 구현 완료로 표현하지 않는다. `source/test/설계 원문/registry/운영 DB` 수정, 실제 op·endpoint·서버 기동·commit/push/일반 프로세스 종료는 수행하지 않았다. 신규 산출물은 이 판정서 하나다.

**최종: REJECT (blocker 0, major 2, minor 2).** 총계/items 정합 정책과 top-3 관계 검증을 먼저 닫고, 새 reference 출현·fixture 반환 형태·확정 입력을 명세에 반영하면 major 0 여부를 재검토할 수 있다.
