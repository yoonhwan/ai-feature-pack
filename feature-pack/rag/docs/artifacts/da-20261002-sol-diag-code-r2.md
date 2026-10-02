model: gpt-6.1-sol
provider: headroom

# U2 publication diagnostics — code DA r2

판정: **PASS — blocker 0 / major 0 / minor 1**. r1의 **M1 및 m1 닫힘**. 남은 minor는 기존 항상 참인 tally 단언이며, 부분 실패 상태 검증의 닫힘을 방해하지 않는다.

발주 #2125. 검토 HEAD `63ed629`, 대상 `f28e936` [test] / `63ed629` [fix]. 기준은 승인 설계 r2 (`8fb8c98`) 및 `da-20261002-sol-diag-code-r1.md`. 세션 `ft-airag-da-codex#0`; Serena 활성화 및 `_publish_group_ok` → `validate_frame` 참조 확인. 요청 allocation low fast; 실제 창 크기/서비스 tier는 확인하지 못했다.

## M1 닫힘 — 코드값 유일성 검사가 독립적으로 추가됨

`feature-pack/rag-consumer/src/airag_consumer/_result.py:145`의 `len({code for _, code in tally}) != k`는 정렬과 별도로 코드값 중복을 거부한다. 슬롯 번호 집합만으로 중복을 검증하던 r1의 빈틈을 직접 닫는다. 정상 Counter producer와 양립하며 새 예외/값 출력 경로를 추가하지 않는다.

r1 독립 반례(동일 `PROVIDER_TIMEOUT`, count 2/1, attempted=failed=3, succeeded=other=0)를 동일 임시 probe로 재실행했다.

- 직접 `validate_frame` 결과: **None**, 이전의 수용 결과에서 거부로 변경.
- 실제 부모 `_run_component` → `main` 경로: **exit 40 / status runtime_error / code RUNTIME_OUTPUT_INVALID**. 합성 subprocess가 익명 결과 파일에 위조 JSON을 쓰고 실제 부모 validator가 처리했다.
- 정상 producer 조합 **3,072개**(등록 코드 5종의 count 0..3 × 성공 count 0..2): `build_frame` → `validate_frame` 모두 수용. 이 범위에서 거짓 거부 없음.
- 기존 독립 malformed 그룹 9개, malformed published/집계 반례 5개 및 fallback/privacy 9개도 재실행해 기대대로 거부/치환됨.

새 직접 회귀는 `tests/test_tick.py:1009` 부근에 count가 서로 다른 중복과 비인접 중복을 포함한다. 새 부모 회귀 `:1067–1071`은 단순 validator 호출이 아니라 합성 component의 위조 응답을 실제 tick으로 처리해 exit/runtime_error/code를 단언한다.

unique 검사 무력화 mutant를 임시 사본에서 직접 실행: **3 failed / 19 passed / 121 deselected, 2.78s**. 실패는 직접 중복 그룹 2건 및 부모 회귀 1건이다. 정상 HEAD 회귀에서는 모두 통과했다. Nano 보고와 별도로 독립 검증했다.

## m1 닫힘 — 부분 실패를 실제 tick 출력에서 검증함

새 `tests/test_tick.py:1074–1081`은 `publish:mixed` component를 실행하고 다음을 확인한다.

- 실제 tick 반환값 **EXIT_OK**.
- 실제 summary의 succeeded와 failed가 각각 1 이상.
- 실제 stdout JSON의 **status degraded / exit 0**.
- 로그 마지막 JSON의 **status degraded**.

`tick_line` (`:531`)은 `everything_written`에서 stdout와 기록 파일을 모아 첫 JSON을 반환한다. 따라서 새 테스트는 테스트 내부의 가상 상태 계산에 의존하지 않는다. fixture의 `mixed`는 성공 항목과 실패 항목이 함께 있는 list를 반환하고 runtime이 이를 집계한다.

r1과 동일한 any-fail → all-fail 변경(`failed > 0 and succeeded == 0`)을 임시 사본의 실제 `tick.py`에 대입했다. 결과 **1 failed / 2 passed / 140 deselected, 8.91s**. 새 partial 테스트가 실제 status `ok` 대 기대 `degraded`로 실패했다(`:1080`). all-failed 및 기존 summary-only partial 테스트는 통과했다. 이전 생존 mutant가 새 실제 tick 테스트로 잡혔으므로 r1 m1은 닫혔다.

독립 부모 probe도 정상 HEAD에서 부분 실패 **exit 0/degraded**, no-group legacy **exit 0/ok**, malformed published **exit 40/runtime_error**를 확인했다. 사용자 확정 any-fail degraded / 정상 발행 실패 exit 0 / 값 비노출 결정을 유지한다.

## 남은 minor — tally의 항상 참인 단언

`tests/test_tick.py:910–911`의 `... == [...] [:0] or True`는 여전히 항상 참이다. 이 문장으로 top-3 코드값의 정확한 선택을 검증한다고 주장할 수 없다. 뒤쪽 count/부분 tie 정렬/합계 및 다른 경계 테스트는 유효하지만 이 단언을 대체하지는 않는다.

이는 tally 코드값 테스트의 기존 약점이며 새 partial tick 테스트/unique 검증과 독립적이다. 위 두 실제 mutant가 모두 실패하므로 **M1/m1 닫힘에 영향 없음**. 범위 밖 수정을 하지 않았으며 이 minor를 보존해 기록한다. 기존 summary-only partial 테스트 (`:1084`) 역시 단독으로 제품 상태 회귀를 잡지 못하지만 새 테스트가 그 책임을 충족한다.

## 독립 회귀 및 registry

- Python 3.13.12 임시 venv; core만 editable 설치하고 consumer는 source PYTHONPATH로 읽었다. 실제 op/1Password, 운영 DB/rollout, live endpoint/서비스는 사용하지 않았다.
- file-scoped U2/registry 선택: **63 passed / 98 deselected, 13.74s**. tally, fallback, malformed published, 관계 불변식, 정상/all-failed/partial/위조 부모, registry/manual reference 검증 포함.
- 독립 AST 분류: **registry 528**, frozen 집합 일치, 메모리 재생성 `render`와 tracked `reason_codes.py` **diff 0**, **unclassified 0 / contradictions 0**. 원본 registry는 쓰지 않았다.
- 두 대상 커밋은 `_result.py`, `test_tick.py`, `_tick_component.py`만 변경. runtime/bridge/core 및 tick 제품 상태 조건 자체는 무변경. 범위 전체 git diff에는 앞선 판정/인계 문서 커밋도 있으므로 그것을 두 대상 구현 커밋의 변경으로 세지 않았다.
- Master의 **422 passed / 305s**는 peer 증거다. 이번 좌석은 요청된 scoped/반례/뮤테이션 검증을 독립 수행했고 full-suite 수치를 자체 실행으로 주장하지 않는다.

증거: `/private/tmp/da2125-scoped.log`, `da2125-mutation-partial.log`, `da2125-mutation-unique.log`, `da2125_mutate.py`; r1 probe `da2104_probe.py`, `da2104_parent.py`는 최신 HEAD로 재실행했다. 뮤테이션은 `/private/tmp/da2125-*` 사본에서 수행하고 원문으로 복구했다. 원본 source/test diff 없음, commit/push 없음. unrelated untracked `.claude/`, `CLAUDE.md` 보존. 본 판정 파일만 추가한다.
