골 원문(GOAL-LEDGER-airag.md 복붙):
최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰 + 6순위 C13(KakaoBot 통합 보고서) published 칸 채움.

판정: **PASS — blocker 0 / major 0 / minor 2 / note 1**

검토: ft-airag-da-codex#1 · 2026-10-16 · 발주 #2598. 대상 `arch-20261016-opa-popup-design-r10.md`, 기준 HEAD `375d160535e263abaaaad230cb7481173686dbca`.
이하 `r10:N`은 위 설계, `P:N`은 `feature-pack/rag-consumer/ops/probe-opa/probe.py`, `PSH:N`은 `probe.sh`, `CHAIN:N`은 `chain.py`다. 이전 판정은 `da-20261016-sol-opa-design-r9.md`다. Serena 정의·참조 조회와 정적 파일·메모리 계약 모형으로 대조했다.

**r9 지적은 설계 수준에서 종결한다.** 새 blocker/major는 발견하지 않았다. 기존 v1 결과를 보존하는 sidecar 전략과 명시적인 worker 인자/단계 게이트는 이전 충돌을 해소할 수 있는 설계다. 아래 두 경미 보완과 완료 게시 순서의 인수 조건을 남긴다. 이 PASS는 **설계 재심**이며 N4 구현·실행 승인이 아니다. 기존 구현·관측 라벨·L7 가설의 수용 상태를 다시 열지 않는다.

## 1. r9 항목 폐쇄

| r9 항목 | r10 정정과 평가 | 판정 |
|---|---|---|
| M1 S2 실행 구조 오기 | r10:9,15,126. 이미 launchd Background인 S2 도구와 실제 토큰 사용/측정 부담·승인/해석 한계를 분리. 새 컨텍스트 변형 구현이 필요하다는 설명 철회 | 종결 |
| M2 P0 위치·키 생략·호출 축소 해석 | r10:28–32,89–97. 내부 접촉 순서 미확인, Background 대 미지정/Standard 대조, 호출 3→1 미검증. all-timeout은 이번 키 제거에서 재현이 남았다는 관측에 제한 | 종결 |
| M3 새 인터페이스·기존 계약 충돌 | r10:53–84. result.json v1 불변·profile.json 분리, worker까지 전달/토큰 읽기 앞 분기, WORKER_ARGS 단일 출처, N4 전용 결과 발견/G4·오류 우선 중단·240초·합성 검수 요건 명시 | 종결. 아래 세부 인수 보완 |
| minor 1 마지막 timeout 시각 혼동 | r10:34–36. 10:00은 최장 연속 구간 끝, 10:05는 성공 비율 전환 관측, 10:32/10:49 추가 timeout 구분 | 종결 |
| minor 2 유실 없음 보장 과장 | r10:38–41. 해당 틱의 업무 pass 미시작까지만 확인, 후속 재수집 전제는 기존 복구 계약으로 별도 확인 | 종결 |
| note 1 R-5 관찰·승인 경계 | r10:134–149. 24틱 전체 창과 3틱 조기 확인/6연속 실패 후보를 구분, 횟수와 시간 구분, 중단 집행도 기존 HIL 경로에서 다시 판정. 이 문서의 재개 승인 없음 명시 | 종결 |

R-5의 «확정»은 이 문서의 설계안으로 읽으며, 숫자 3·6·24의 집행은 r10:149처럼 별도 구현/DA/사람 판정을 거치는 것으로 해석한다. R-2·R-3·R-4 미충족 및 consumer disabled 상태는 유지한다.

## 2. 새 프로필 계약 대조

- `--p0-only`/`--process-type-set`를 worker까지 전달하고 read_token 앞에서 분기하는 요건은 P:625–678의 실제 호출 순서와 맞는다. 명시한 모드/인자 오류를 실행 전에 거절하고, S2/compare import에는 기본값만 적용한다는 원칙도 기존 인터페이스와 양립한다. 실제 구현의 parser와 부작용 0은 향후 합성 검수 항목이다.
- 동일 WORKER_ARGS 배열을 plist 생성과 자기 job 대조에 사용하는 설계는 PSH:101–106,202–221의 정확한 argv 소유 조건을 유지할 수 있다. 다른 프로필/인자 job을 내리지 않는 시험도 포함됐다.
- p0only의 남은 세 단계를 기존 skipped_not_applicable로 표현하면 v1의 새 필드/상태가 필요 없다. 합성 v1 문서에서 P0 success와 timeout 모두 현 validate_result를 통과했고, 옆에 profile.json을 두어도 기존 read_result 결과가 바뀌지 않았다.
- N4 세 단계에 프로브 디렉터리 발견/G4를 쓰고, 기존 N2/N3의 E1 검색을 적용하지 않는 명세가 생겼다. 기존 N1~N3 흐름을 보존하면서 원칙을 재사용할 수 있으며, 새 진입 구현은 별도 검수가 필요하다.
- 7초/재시도 0, 기본 full 보존, p0 성공/timeout 양쪽 토큰 비접촉 sentinel, 닫힌 profile 스키마·유한 수치/null 처리·소유/중단 요건은 수용한다. A-B-A/부하 참고값을 원인 통제로 읽지 않는 한계와 좁혀진 HIL 고지도 유지한다.

## minor 1 — P4 예외와 기존 conclusion의 범위를 문서 안에서 맞춘다

근거: r10:56,77,82,107 / P:593–617 / CHAIN:137–150.

두 작은 불일치가 있다.

| 유효한 p0only v1 모형 | 현 conclude | 현 gate_probe |
|---|---|---|
| P4 success / P0 success | cause_unconfirmed | 통과 |
| P4 success / P0 timeout | p0_blocked | 통과 |
| **P4 network_error / P0 timeout** | **network_reachability** | 통과 |
| P4 spawn_error / P0 timeout | p0_blocked | **probe_step_error로 중단** |

따라서 r10:56의 conclusion 두 값은 전체 목록이 아니라 정상 P4의 예로 적거나 network_reachability도 포함해야 한다. 기존 conclude를 수정할 필요는 없다. r10:82의 «P4가 success가 아니면 진행»은 **기존 gate_probe를 통과하는 network_error 관측**에 한정하고, spawn_error/unsupported/observation_unknown·회수 미확인은 기존 중단이 우선이라고 맞춘다. 실제 G4의 공통 검사와 합성 시험 7의 의도는 이미 안전한 쪽이므로 비차단 계약 문구 보강이다.

## minor 2 — plist 대조는 키 존재뿐 아니라 A의 값도 확인한다

근거: r10:61,69,81,102.

profile bool·단계 기대값·텍스트의 키 존재가 모두 true여도 plist 값이 Standard/Interactive이면 같은 검사에 통과한다. 그러나 A의 관측 라벨은 Background다. 메모리 모형에서 세 값 모두 존재 검사에는 통과하고 Background 값 대조만 나머지를 구분했다.

의도된 writer는 기존 Background 상수를 쓰므로 정상 산출물이 임의의 다른 값을 만드는 사례를 관측한 것은 아니다. 비차단 검증 보강으로, plist를 구조적으로 읽어 **A는 ProcessType==Background, B는 키 없음**을 확인하고 A의 다른 값/잘못된 plist 사례를 추가하면 된다. 원문/환경 값을 출력할 필요는 없다. 이 검사가 실제 실행 중인 프로세스의 정책까지 증명하는 것은 아니다.

## note 1 — profile을 완성한 뒤 result의 완료 표식을 게시한다

새 sidecar의 구현 인수 조건이다. 기존 wrapper는 result.json의 complete=true를 보면 즉시 자기 job 정리를 시작한다(PSH:240–251). 따라서 p0only의 최종 profile.json을 원자적으로 완성한 **뒤에** result.json의 완료를 게시해야 한다. 반대로 쓰면 wrapper가 worker를 정리하면서 profile 생성/갱신이 끊겨, G4가 profile_missing/불완전으로 중단할 수 있다.

구현 전 명세의 쓰기 순서를 보완하고 최종 profile 쓰기 지연을 둔 합성 사례로 인계 순서를 확인하면 된다. profile 실패 때 G4가 후속을 막는 정책은 유지한다. 현재 코드의 경합을 재현한 주장이나 기존 wrapper 정리 계약을 다시 바꾸라는 요구는 아니다.

## 3. 검증 범위·다음 단계

정적 계약 실행기 `/tmp/airag-opa-da-r10-checks.py`, 결과 `/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-opa-da-r10-checks-zmwlze63/evidence.json`에 v1 모형 4종·sidecar 호환·plist 값 대조를 보존했다. 새 N4 구현이나 profile 검증기를 시험 통과했다고 주장하지 않는다. 변경이 설계 문서 한 개뿐인 범위에서, 닫힌 제품 시험을 전체 재실행하지 않았다.

이번 쓰기는 판정서 및 임시 합성 검증물이다. 실제 op·운영 launchctl·운영 DB·HTTP·운영 설정·제품 코드/시험 수정·설치·커밋·push·서브에이전트는 0이다. 새 운영 로그/자격 파일 조회도 하지 않았으며 기존 수용 사실을 재측정하지 않았다. core.bare=false다.

minor/인수 조건은 N4 구현 명세와 시험에 반영할 수 있다. 이후 별도 Master 발주·합성 시험·구체적 구현 DA·정확한 상한/전체 고지·사람 HIL 순서를 유지한다. 이 PASS로 N4/S2 실행이나 consumer 재개를 집행하지 않는다.
