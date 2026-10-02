model: gpt-6.1-sol
provider: headroom

# U2 publication diagnostics — code DA r1

판정: **REJECT — blocker 0 / major 1 / minor 1**.

대상: `99d432c` test + `85aa26e` fix, 검토 HEAD `85aa26e`. 기준: `arch-20261002-published-diag-design.md` r2 (`8fb8c98`) 및 설계 DA r2. 발주 #2104. 세션 `ft-airag-da-codex#0`; Serena 연결/프로젝트 활성화 및 `_publish_group_ok` 참조 확인 완료. 요청 allocation은 low fast; 실제 창 크기/서비스 tier는 확인하지 못했다.

## M1 — 서로 다른 count의 중복 코드가 부모 검증을 통과한다

앵커: `feature-pack/rag-consumer/src/airag_consumer/_result.py:128`, `:141`, `:143`, `:185`; 부모 `tick.py:192` 부근.

`codes` 집합은 코드 값이 아니라 slot 번호다. 정렬 키 `(-count, code)`의 strict ordering은 같은 count의 중복만 막는다. 서로 다른 count이면 같은 코드라도 서로 다른 키이므로 통과한다. 승인 설계의 “unique registry codes” 불변식과 불일치한다.

독립 반례:

```json
{"exit":0,"summary":{"published_attempted":3,"published_succeeded":0,"published_failed":3,"published_failed_other":0,"published_failed_code_1":"PROVIDER_TIMEOUT","published_failed_count_1":2,"published_failed_code_2":"PROVIDER_TIMEOUT","published_failed_count_2":1},"code":"","type":""}
```

현재 `validate_frame(frame) == frame`. 임시 config/log와 합성 subprocess 응답으로 실제 `_run_component` → `main` 경로까지 실행해도 **exit 0 / status degraded**로 기록된다. 기대는 부모의 **exit 40 / RUNTIME_OUTPUT_INVALID**다. 정상 Counter producer는 이 프레임을 만들지 않으므로 정상 출력 오류로 확대 해석하지 않는다. 그러나 부모의 위조 프레임 검증 계약이 깨졌다.

수정 요구: 코드 값의 유일성을 별도로 검사하고, 다른 count의 중복을 직접 validator 및 부모 경로에서 거부하는 회귀를 추가한다. 기존 `test_tick.py:1008` 중복 예시는 count 2/2이므로 정렬 검사만으로 거부되어 이 결함을 잡지 못한다. DA 좌석은 소스/테스트를 수정하지 않았다.

## m1 — 부분 실패 상태 테스트가 실제 tick 상태를 검증하지 않는다

앵커: `tests/test_tick.py:1063–1069`, `src/airag_consumer/tick.py:252`.

부분 실패 테스트는 테스트 내부에서 `status = "degraded" if ...`를 다시 계산한다. `tick.main`의 JSON/로그 상태를 확인하지 않아 제품 조건의 회귀를 놓친다. 임시 사본에서 실제 조건을 `failed > 0 and succeeded == 0`으로 바꿨을 때 U2 선택 **54 passed / 85 deselected**였다. 별도 부모 실행으로 이 mutant가 부분 실패에 **exit 0 / status ok**를 출력함을 확인했다. 원본 구현은 부분 실패를 올바르게 degraded로 출력한다.

부분 성공/실패가 섞인 합성 component 결과를 실제 tick에서 실행하고 stdout와 로그의 degraded/exit 0을 확인하도록 보완해야 한다. `test_tick.py:910–911`의 `... or True` 단언도 항상 참이다; tie 선택 코드 검증에는 사용될 수 없다. 동일 테스트의 뒤쪽 count/부분 정렬/합계 검사는 유효하지만 이를 전체 코드 순위 단언으로 간주하지 않는다.

## 독립 실행과 설계 대조

- Python 3.13.12, 격리 임시 venv. `test_tick.py` + `test_reason_codes.py`: **156 passed / 1 failed, 170.29s**. 한 실패는 검증 환경에 consumer를 editable 설치해 import 실패를 기대하는 기존 테스트의 전제가 달라진 것이다. consumer 설치를 제거하고 해당 테스트만 재실행: **1 passed, 2.85s**. 따라서 157개 고유 테스트가 통과했으나 단일 clean-run 157 PASS라고 보고하지 않는다. Master의 418 passed는 별도 peer 증거다.
- 합성 producer: 등록 코드 5종 각각 count 0..3, 성공 count 0..2의 **3,072개** 일관 조합을 `build_frame` → `validate_frame`으로 실행, 모두 수용. 정상 producer 거짓 거부는 이 범위에서 발견하지 못했다.
- 독립 malformed 그룹 **9개**: code/count 짝 없음, bool count/attempted, 음수, 초과합, failed 산식 불일치, non-string code, 0 count, other 합 불일치 모두 거부. rank hole/순서/4-key 부분 그룹 등 추가 케이스는 기존 file-scoped 회귀에서 통과. 예외는 M1이다.
- present published None/list/string와 설계 r1의 집계 반례 2개, 총 **5개** 모두 `build_frame`의 `{exit:0,summary:{},code:RUNTIME_OUTPUT_INVALID,type:""}`. 부모 실행에서 malformed published는 **exit 40 / runtime_error**로 변환.
- unknown/code-shaped secret/path/message/list/dict/bool/int/None 등 **9개** 코드 입력은 `CORE_PUBLICATION_FAILED`로 치환. `_result.py:95`에서 문자열 검사 → regex → registry 순서. 프레임에 합성 message marker 미포함. `_pass_child.py:91`에서 sanitize 후 serialize/write하므로 값 경계는 익명 결과 파일보다 앞이다. 익명 파일/로그의 unknown 및 message 비노출은 기존 spy 회귀도 통과.
- 실제 부모 실행: 부분 실패 **exit 0/degraded**, no-group legacy **exit 0/ok**, malformed published **exit 40/runtime_error**. all-failed/unknown/정상/crash/재수동 및 reference key 변형은 scoped tick 회귀에 포함된다. 사용자 확정 any-fail degraded / 정상 발행 실패 exit 0 / 값 비노출 결정을 유지한다.
- 설계 minor T7: `test_tick.py:993–997`이 4=2+1+1의 가능한 완성 그룹으로 대체한다. present None/list/string은 `:954`에 명시. T13 `:963`은 publication 그룹 자체가 없는 legacy만 허용한다. attempted/succeeded만 있는 구형 publication 그룹의 호환성을 주장하지 않는다.
- runtime `AIRAGRuntime._publish` (`runtime.py:673–688`)는 bridge list로부터 attempted/정확한 `ok is True` succeeded/items를 함께 구성한다. 변경된 fixture 역시 list 반환. runtime/bridge/core 변경 없음; 두 구현 커밋의 변경은 지정된 5파일뿐이다.
- registry 독립 AST 분류: **528**, 현 frozen 집합 동일, `render(current.registry)`와 tracked `reason_codes.py` 텍스트 **diff 0**, **unclassified 0 / contradictions 0**. 재생성은 메모리에서 비교해 원본을 쓰지 않았다. moved manual line/reference도 이 분류로 검증했다.

## 뮤테이션과 보존

두 뮤테이션은 `/private/tmp/da2104-*`의 consumer 사본에서 실행하고 원문으로 복구했다. 운영 소스에 mutation을 대입하지 않았다.

1. `_publish_failure_code`의 registry membership 제거: fallback 선택 **2 failed / 8 passed / 129 deselected, 2.18s**. 테스트가 unknown/hex-shaped 코드 통과를 잡았다.
2. tick의 any-fail 조건을 all-fail로 변경: U2 **54 passed / 85 deselected, 6.68s**. 생존 mutant이며 m1의 실제 partial wrong-ok를 별도 실행으로 확인했다.

증거: `/private/tmp/da2104_probe.py`, `da2104_parent.py`, `da2104_mutate.py`, `da2104_partial_confirm.py`; 로그 `da2104-baseline-fixed.log`, `da2104-import-recheck.log`, `da2104-mutation-registry.log`, `da2104-mutation-partial.log`. `test_runtime.py -k publish`는 50 deselected로 실행 케이스가 없었으며 검증 수에 포함하지 않았다.

실제 op/1Password, 운영 DB/rollout, live endpoint, 서비스/launchd는 사용하지 않았다. 검토 전 unrelated untracked `.claude/`, `CLAUDE.md` 보존. 원본 source/test diff 없음, commit/push 없음. 본 판정 파일만 추가한다. M1 수정과 직접 회귀 후 재검토가 필요하다.
