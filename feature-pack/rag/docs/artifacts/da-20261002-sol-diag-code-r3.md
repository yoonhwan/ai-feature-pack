model: gpt-6.1-sol
provider: headroom

# U2 tally assertion — small code DA r3

판정: **PASS — blocker 0 / major 0 / minor 0**. 코드 DA r2의 잔여 항상 참 tally 단언 minor 닫힘.

발주 #2145, 대상 `7f72839` [test]. 검토 시 HEAD `bd06533`; 대상 커밋 이후 consumer src 및 `tests/test_tick.py` diff 0을 확인했다. 세션 `ft-airag-da-codex#0`; Serena 프로젝트 활성화 및 `_publish_summary` 참조 확인. 요청 allocation low fast; 창 크기/실제 서비스 tier는 확인하지 못했다.

## 단언의 의미

`feature-pack/rag-consumer/tests/test_tick.py:911`은 세 슬롯의 코드 배열 전체를 다음 기대값과 직접 비교한다.

```python
["PROVIDER_TIMEOUT", "PROVIDER_UNREACHABLE", "CORE_NOT_SEARCHABLE"]
```

입력의 TIMEOUT/UNREACHABLE count는 각각 2, MODEL_MISMATCH/CORE_NOT_SEARCHABLE/CORE_PUBLICATION_FAILED는 각각 1이다. 따라서 `(-count, code)` 기준에서 count 2의 두 항목이 먼저 오고 그 동률은 코드 오름차순이다. count 1 후보의 첫 코드 `CORE_NOT_SEARCHABLE`이 3위를 차지한다. 이어지는 count `[2,2,1]` 및 합계/other 단언과 함께, 이 fixture의 정확한 순위와 cutoff 선택을 검사한다. 기존 `[:0] or True`와 달리 잘못된 3위도 직접 실패한다.

## 독립 실행

Python 3.13.12 임시 venv에서 `test_tally_top3_with_other_and_tie_order` 및 `test_tally_boundaries_and_order_independence`: **2 passed / 141 deselected, 1.81s**. Master의 `test_tick.py` 143 passed는 별도 peer 증거이며 이 좌석의 전체 실행으로 주장하지 않는다.

제품 `_publish_summary`의 정렬키에 아래 두 뮤테이션을 임시 consumer 사본에서 직접 대입했다. 각 실행은 대상 top-3 테스트 하나만 사용했다.

1. count 우선순위는 유지하고 동률에서 MODEL_MISMATCH를 먼저 선택: `(-pair[1], pair[0] != "MODEL_MISMATCH", pair[0])`. **1 failed, 2.67s**. 새 `:911` 배열 단언에서 index 2의 MODEL_MISMATCH 대 CORE_NOT_SEARCHABLE 차이로 실패.
2. count 내림차순은 유지하고 코드 동률을 내림차순으로 변경: `(-pair[1], tuple(-ord(c) for c in pair[0]))`. **1 failed, 1.75s**. 같은 새 단언에서 index 0의 PROVIDER_UNREACHABLE 대 PROVIDER_TIMEOUT 차이로 실패.

둘 다 제품 producer의 동률 동작을 바꿨으며 테스트 기대값은 바꾸지 않았다. 새 단언이 cutoff의 잘못된 동률 선택과 상위 동률 역순을 실제로 잡는다. 임의의 모든 정렬 결함을 증명한다고 확대하지 않는다.

## 잔존 검색 및 변경 범위

`test_tick.py` 전체를 grep으로 `or\s+True`, `[:0]`(공백 변형 포함), `assert True` 패턴 검색: **0건**. `assert`와 `True`를 함께 포함하는 넓은 검색 결과도 확인했으며 `is True`, JSON expected bool, 문자열 marker 등 유효한 단언이었다. 이 검색은 동치인 모든 논리 tautology에 대한 형식 증명은 아니다.

`git show --name-only 7f72839`: **test_tick.py 1파일**, 1 insertion / 2 deletions. `git diff 7f72839^ 7f72839 -- feature-pack/rag-consumer/src`: **diff 0**. 후속 HEAD와 대상 커밋 사이에서도 해당 source/test diff 0. src/runtime/bridge/core 변경 없음.

증거: `/private/tmp/da2145-baseline.log`, `da2145-mutation-model_first.log`, `da2145-mutation-tie_reverse.log`, `da2145_mutate.py`. `/private/tmp/da2145-*` 사본의 `_result.py`는 실행 후 원본과 byte 동일하게 복구했다. 원본 소스/테스트 변경, 운영 DB/op/live endpoint 접근, commit/push 없음. 기존 untracked `.claude/`, `CLAUDE.md` 보존. 본 판정 파일만 추가한다.
