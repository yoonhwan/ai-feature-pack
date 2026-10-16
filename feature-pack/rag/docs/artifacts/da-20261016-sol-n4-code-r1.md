골 원문(GOAL-LEDGER-airag.md 복붙):
최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰 + 6순위 C13(KakaoBot 통합 보고서) published 칸 채움.

판정: **PASS — blocker 0 / major 0 / minor 3 / note 1**

검토: `ft-airag-da-codex#1` · 2026-10-16 · 발주 #2606. 기준 HEAD `b61e327b38aa56f415be0150f188470bc867973c`. 대상은 `83763c4`, `40f4a4b`, `e6eaecd`, `1f9bdd9`, `b61e327`의 N4 구현·합성 시험이다. 정본은 `arch-20261016-opa-popup-design-r10.md` §4와 `da-20261016-sol-opa-design-r10.md`의 구현 인수 조건 3건이다.

**구현 검토 PASS이며 실제 N4 실행·consumer 재개·운영 plist 변경 승인은 아니다.** 실제 op·운영 launchctl·네트워크·DB·운영 토큰 접근 없이 합성 stub만 사용했다. 제품 코드·기존 시험은 수정하지 않았다. Serena 정의·참조 조회와 전체 변경 diff, 합성 실행을 대조했다. 아래 minor는 현재 정상 생성 경로에서의 재현 결함이 아니라 비정상 입력 방어·시험·명세 경계 보완이며 PASS를 막지 않는다. 기존 P/E1/chain/S2의 종결 판정은 재개방하지 않는다.

이하 P=`feature-pack/rag-consumer/ops/probe-opa/probe.py`, PSH=`probe.sh`, C=`chain.py`, T=`feature-pack/rag-consumer/tests/test_n4_opa.py`. 줄 번호는 위 SHA 기준 1-based다.

## 핵심 계약 대조

| 계약 | 독립 확인 및 판정 |
|---|---|
| 토큰 비접촉 | P:662–665에서 `read_token()`보다 먼저 p0only로 분기·return. P:700–722는 P4 뒤 P0 한 번, P2/P1/P1b는 skipped. P0는 `op_environment(None)`으로 실행한다. success/timeout 양쪽의 read_token 금지·센티넬·계정 호출 0 시험 통과. read_token 삽입 독립 변이는 양쪽에서 assertion으로 탐지 |
| 기본 full 보존 | `83763c4^`의 실제 probe.py/probe.sh를 임시 디렉터리에 추출해 현 소스와 같은 fake launchctl/log/op로 실행. 실행별 경로·PID·시간만 정규화해 **plist 전체**, stdout 보고, result 키·각 단계의 이름/상태/키 일치. stderr 양쪽 빈 값. 신규 골든은 plist 앞부분만 보지만 이 DA는 전체를 대조 |
| v1·기존 판독 보존 | 변경 전/후 AST에서 `validate_result`, `read_result`, `report`, `conclude`, `write_json_atomic` 동일. 새 메타데이터는 profile.json에만 저장. S2/compare import의 full 기본값 시험 통과 |
| worker 인자·소유 | PSH:201–205에서 WORKER_ARGS 한 번 구성. :112 소유 대조와 :223 plist 직렬화가 같은 배열 사용. 기존 plist 경로 일치 조건도 유지. 다른 프로필 drop_p0/flip_pt/add_p0는 bootout 0·잔존 안내, 자기 unset job은 정상 bootout. 인자/불리언 변이도 탐지 |
| 프로필·완료 순서 | P:718–722의 atomic 0600 profile 저장이 정상 `save(complete=True)` 앞. sidecar 정확한 5키·형·유한 부하·null 조건 확인. 독립 write 관찰기로 정상 complete 게시 시 이미 유효한 profile이 있음을 확인. profile 쓰기 OSError를 주입하면 기존 예외 경로의 observation_unknown/aborted_class=OSError로 종료, G4는 probe_incomplete로 거부 |
| G4 | C:232–256: 기존 G1의 종료 미확인·불완전·단계 오류를 먼저 거부, P0 success/회수된 timeout만 허용, 세 계정 단계 skipped/null 확인, 닫힌 profile와 단계 기대값·독립 plist 구조를 삼자 대조. A는 값이 정확히 Background, B는 키 없음. 변형·symlink·잘림·크기 초과 시험 통과. 비정상 단계 배열의 추가 방어는 minor 1 |
| 발견·표 판독 | N4 세 단계 모두 N1의 새 probe 디렉터리 유일 발견 규칙 재사용. 0/복수/E1 패턴/잘림/과대/도구 비정상 rc는 후속 미실행. C:492의 code==0 AND 세 단계 관측 존재 조건이 마지막 실패 후 표 판독을 막음. 이 조건 삭제 변이 탐지 |
| 시간·신호·잔존 | N4는 기존 240초 전체·83초 시작 조건·77초 도구 초과·TERM 1회/3초 유예를 재사용하고 상수를 늘리지 않음. fake clock 64조합·초과·SIGINT 전달·저장 종료코드 전파 시험 통과. 시작 조건 삭제 변이는 12조합에서 탐지. 기존 종료/정리 규칙을 새 절대 wall-clock 보장으로 확대 해석하지 않음 |
| 값 비출력·해석 한계 | 결과·profile·plist 원문값을 보고에 반사하지 않고 고정 enum/수치만 사용. selftest 센티넬 비노출·그룹 신호 금지 시험 통과. 세 표 행과 나머지 hold, 인과/운영 변경 금지·A-B-A 한계 문구 유지 |

설계 DA의 인수 조건 3건은 충족한다. ① P4 success/P0 success → cause_unconfirmed, success/timeout → p0_blocked, **network_error/timeout → network_reachability**, spawn_error/timeout → G4 probe_step_error 중단. 기존 conclude는 수정하지 않았다. P4가 success가 아닌 허용 관측이면 표는 hold다. ② plistlib로 최상위 키와 값을 읽어 A=Background/B=키 없음 확인. ③ 정상 profile 완성 뒤 complete 게시를 코드와 독립 write 관찰로 확인했다.

## Minor 3건

**minor 1 — G4가 단계 배열의 유일성·P4 존재를 추가 검증하지 않는다.** C:238의 dict 변환은 중복 step을 마지막 항목으로 덮고, 기존 v1 validator는 단계별 닫힌 키/열거형을 검사하지만 단계 집합의 완전성·유일성까지 요구하지 않는다. 독립 합성 결과에서 (a) P4 삭제, (b) 정상 skipped P2 앞에 success/account_type_confirmed=true P2를 하나 추가한 문서가 모두 validate_result=true, gate_n4=None이었다. (b)는 계정 단계 비실행을 검증한다는 G4의 방어 의미가 약해지는 경우다. 현재 producer는 STEPS 순서의 done dict에서 한 번씩만 생성하므로 정상 구현 경로로는 만들어지지 않는다. (a)도 최종 P4=not_run으로 hold하여 연관 판독은 하지 않는다. **보완:** 기존 공용 v1 계약을 바꾸지 않고 N4 게이트에서 정확한 P4/P0/P2/P1/P1b 집합과 유일성을 확인하고 malformed 배열을 거부하는 합성 시험을 추가할 수 있다. 정상 생산 경로 결함으로 승격하지 않는다.

**minor 2 — 완료 순서 시험에 짧은 경쟁 구간을 놓치는 변이가 있다.** T:222의 시험은 20ms 폴링이며 현재 지연 훅은 profile 쓰기 전에 있다. `write_json_atomic(profile.json, …)` 바로 앞에 `save(complete=True)`를 삽입한 독립 변이는 **통과**했다. profile 저장 직전의 짧은 잘못된 완료 게시를 폴링이 놓칠 수 있다. 같은 게시를 지연 훅 앞으로 옮겨 잘못된 구간을 1.5초로 만든 변이는 실패했다. 현재 제품 코드는 올바른 순서이고 DA의 별도 write 관찰도 통과했다. **보완:** sleep/폴링에만 의존하지 말고 write_json_atomic 호출을 감싸 정상 complete=true 게시 순간 profile이 이미 존재·유효한지 검증하는 결정적 시험을 추가한다. Nano의 45종 생존 0 보고를 이 독립 변이까지 포함한 보증으로 확장하지 않는다.

**minor 3 — `--bounded` 뒤 child argv의 신규 플래그는 worker 검증을 거치지 않는다.** r10 §4.2-4는 bounded와의 결합을 종료 2·실행 0으로 적었지만 P:864–865의 기존 bounded 조기 반환이 신규 플래그 검증보다 앞이다. `probe.py --bounded 1 -- <합성 Python child> --p0-only --process-type-set true`는 rc=0이고 child marker가 생성되었다. wrapper가 생성하는 정상 N4 worker argv에는 bounded가 없으며, `--` 뒤는 원래 child argv인 범용 bounded 계약과도 겹치는 경계다. **보완:** 신규 worker 플래그와 bounded의 금지 조합을 child 인자까지 금지한다는 뜻인지 명세에서 명확히 하고 그 해석의 합성 시험을 추가한다. 단순 검증 순서 이동은 기존 bounded child 인자 계약을 바꿀 수 있으므로 full 호환성을 함께 확인한다. 실제 토큰 접근·운영 실행 우회로 판정하지 않는다.

## Nano가 정한 5건의 처분

| 선택 | 처분 |
|---|---|
| p0_not_tabulable / profile_violation / profile_missing / profile_schema / profile_mismatch | **수용.** 값 없는 고정 중단 사유이며 기존 gate_probe 사유 우선순위를 보존. spawn_error/unsupported/observation_unknown이 먼저 probe_step_error가 되는 것은 기존 게이트 재사용에 부합 |
| N4-A1 / N4-B / N4-A2 이름 | **수용.** 계획 순서·기대값 매핑이 명시적이고 기존 full/N1~N3와 분리 |
| profile 쓰기 실패를 기존 예외 경로로 처리 | **수용.** 완성되지 않은 profile을 정상 관측으로 통과시키지 않음. 합성 OSError에서 G4 probe_incomplete 재확인 |
| probe.sh 끝 p0only 안내 한 줄 | **수용.** 명시적 p0only에서만 출력, Background/미지정(Standard·가벼운 제한 있음) 구분. 기본 full 골든 유지. 실제 실행 시에는 r10 §4.8의 P4 네트워크·팝업·CLI 내부 접촉 미확인 고지를 함께 적용 |
| PROBE_P0_PROFILE_DELAY | **수용.** override_seconds의 selftest 전용 훅이며 운영 환경 override 거부 계약 유지. 제품 기능 아님. 지연 시험은 유용하나 minor 2의 결정적 검증을 대체하지 않음 |

## 검증 증거

- 기준 소스에서 `../rag/.venv/bin/python -B -m pytest tests/test_n4_opa.py -q -p no:cacheprovider` → **218 passed in 65.84s, rc=0**. cwd=`feature-pack/rag-consumer`. 이 DA에서 기존 전체 회귀를 별도로 재실행하지 않았으며 Master의 동시 전체 회귀 결과를 독립 실행인 것처럼 합산하지 않았다.
- 독립 소스 변이: 임시 복사본 15종·제품 파일 변경 0. **14종 assertion 실패로 탐지 / 1종 생존 / 수집·setup 오류 0**. 토큰 읽기, worker bool, 소유 argv, B plist 키, profile 추가 키, bool 부하, A의 잘못된 값, 자기보고 불일치, 계정 단계, 마지막 실패 표 판독, 시작 예산, P4 실패 표 판독, full 오염, 지연된 조기 완료 게시가 탐지됐다. 짧은 조기 완료 게시만 생존(minor 2).
- 독립 합성 검사: P4 누락·중복 P2·bounded 경계 재현, 실제 pre-N4 소스와 full 골든, profile 쓰기 실패, write 호출 시점의 완료 순서 관찰. 정상 계약 검사와 경계 재현을 구분해 기록했다. 최종 스크립트 rc=0, summary는 `/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-n4-da-r1-independent-b7wcdcdu/summary.json`.
- 재현 스크립트: `/tmp/airag-n4-da-r1-mutations.py`, `/tmp/airag-n4-da-r1-independent.py`. 변이별 결과와 summary는 `/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-n4-da-r1-mutations-2jpl_pqf/`. 임시 증거는 영구 보관을 보증하지 않으며 주요 결과는 이 판정에 고정했다.

**note 1 — 실행·관측 경계 유지.** 합성 통과는 실제 macOS launchd의 팝업/타임아웃 재현·ProcessType 효과·consumer 복구 증거가 아니다. 실제 N4는 별도 고지와 HIL 뒤에만 가능하다. 이번 PASS로 운영 plist 변경·S2 실행·consumer 재개·C12 회복 관찰 완료를 선언할 수 없다.
