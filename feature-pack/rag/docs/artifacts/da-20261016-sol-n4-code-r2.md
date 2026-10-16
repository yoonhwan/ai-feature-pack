골 원문(GOAL-LEDGER-airag.md 복붙):
최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰 + 6순위 C13(KakaoBot 통합 보고서) published 칸 채움.

판정: **PASS — blocker 0 / major 0 / minor 1 / note 1**

`ft-airag-da-codex#1` · 2026-10-16 · 발주 #2610. 기준 HEAD **`0e6d48b400ac6914716f49c0a9aae9a1d1ce4fd0`**, 대상 Red `85a501d` → fix `0e6d48b`의 보강분만 재심했다. 직전 판정 `da-20261016-sol-n4-code-r1.md`의 **minor 1·2 종결, minor 3·note 1 유지, 신규 지적 0**이다. 이 PASS는 구현 검토이며 실제 N4 실행·consumer 재개 승인이 아니다.

## 종결 판단

| 항목 | 근거 | 처분 |
|---|---|---|
| r1 minor 1: 누락·중복 step이 G4 통과 | `feature-pack/rag-consumer/ops/probe-opa/chain.py:238`에서 step 이름의 정렬 목록을 `probe.STEPS` 정렬 목록과 비교한다. dict 변환 전에 개수와 이름별 중복도를 함께 검사하므로 누락·추가·대체가 숨지 않는다. `gate_probe`는 그대로 먼저 실행해 공용 스키마와 기존 오류 우선순위를 유지한다 | **종결** |
| 정상 결과 오탐 | 독립 검사에서 P4 success/network_error × P0 success/timeout × A/B 8조건 각각의 5! 순열, **960건 모두 G4 통과**. 순서를 강제하지 않고 정확한 집합·중복도만 요구한다. 누락 5종·삽입 중복 30종·동일 길이 치환 20종 × 8조건 = **440건 모두 result_schema로 거부** | 새 결함 없음 |
| r1 minor 2: 짧은 완료 게시 순서 변이 생존 | `feature-pack/rag-consumer/tests/test_n4_opa.py:258`의 write_json_atomic 래퍼가 매 complete=true 게시 직전에 profile의 JSON·키 집합·profile명을 확인한다. :290의 새 시험은 완료 게시가 정확히 한 번이고 true임을 요구한다. sleep/폴링이나 PROBE_P0_PROFILE_DELAY 없이 관찰 | **종결** |
| 이전 생존 변이 재대입 | profile 쓰기 바로 앞에 `save(complete=True)`를 넣는 r1의 동일 변이를 임시 소스에 재대입. 새 결정적 시험이 P0 success·timeout **2건 모두 assertion 실패로 탐지** | 생존 0 |

새 정렬 비교는 N4의 gate_n4에만 들어갔다. 공용 validate_result·gate_probe와 기존 N1~N3·S2·compare의 입력 계약은 바꾸지 않는다. 누락 P0의 기존 시험 기대값이 p0_not_tabulable에서 result_schema로 바뀐 것은 더 이른 배열 검증에 따른 의도된 분류다. 공용 게이트 호환 시험과 정상 A-B-A·실제 probe.sh를 사용하는 합성 3단계 연동도 통과했다. 제품 probe.py/probe.sh의 동작·시간·토큰 경로는 이번 변경에서 수정되지 않았다.

**잔존 minor 1건(r1 minor 3):** bounded의 `--` 뒤 child argv에 신규 플래그가 오는 경계는 기존 한계로 남기는 데 동의한다. 정상 N4 wrapper 인자에 bounded가 없고 이번 변경도 해당 경로를 건드리지 않았다.

## 독립 검증

실제 op·운영 launchctl·네트워크·DB·운영 토큰에 접근하지 않았다. 제품 코드·시험 수정·서브에이전트 사용 0. Serena 정의/참조로 gate_n4 → check_stage의 적용 범위를 확인하고 변경 diff와 합성 실행을 대조했다.

| 검사 | 결과 |
|---|---|
| 관련 pytest 선별 실행 | **38 passed, 195 deselected in 10.74s, rc=0** |
| 정상·비정상 독립 행렬 | 정상 순열 **960 통과**, 누락·중복·치환 **440 거부**, rc=0 |
| 이전 생존 변이 | 새 결정적 게시 시험 **2 failed**, rc=1로 탐지 |
| G4 정렬 검사 제거 변이 | 단계 유일성 시험 **10 failed**, rc=1로 탐지 |
| 정렬 목록 대신 set 비교 변이 | **4 failed, 6 passed**, rc=1로 중복도 검사 누락 탐지 |
| 길이만 비교하는 변이 | **2 failed, 8 passed**, rc=1로 동일 길이 치환 누락 탐지 |

변이 4종 모두 assertion 실패이며 수집/setup 오류는 없다. 임시 복사본에서 실행했고 원본과의 일치도 확인했다. 부하성 실패·재실행은 없었다. Master가 실행하는 전체 회귀는 이 DA의 독립 실행 결과로 합산하지 않는다.

pytest 명령(cwd=`feature-pack/rag-consumer`):

```sh
../rag/.venv/bin/python -B -m pytest tests/test_n4_opa.py -q -p no:cacheprovider -k 'every_complete_publication or g4_demands_exactly or extra_account_step or step_array_that_is_not_exact or shared_validator_and_the_other_gates or four_valid_p0only_models or g4_passes_an_ordinary or g4_stops_on_each_single_change or normal_a_b_a or stop_at_the_last_stage or chain_n4_over_the_real_probe_script'
```

독립 검사 스크립트 `/tmp/airag-n4-da-r2-check.py`. summary와 변이별 assertion 로그는 `/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-n4-da-r2-dnmy543w/`에 있다. 임시 증거의 주요 수치와 판정은 이 파일에 고정했다.

**note 1 유지 — HIL 고지·실행 경계:** 이번 보강으로 r10 §4.8의 토큰 파일 읽기 0·계정 명령 0·CLI 내부 접촉 미확인·팝업 가능성·consumer disabled·관측 라벨 한계와 새로 충돌하는 구현은 발견하지 않았다. HIL 고지의 P4 연결 확인·op --version·임시 작업은 **완주 시 각각 3회, 앞 단계 실패 시 후속 미실행이므로 “최대 3회”**로 표현하면 정확하다. 기존 전체 상한 240초와 정리·잔존 한계를 유지하고 팝업 부재·ProcessType 인과·운영 복구를 보증하지 않는다. 실제 실행 여부는 별도 HIL 판정으로 남긴다.
