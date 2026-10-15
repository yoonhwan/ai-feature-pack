골 원문(GOAL-LEDGER-airag.md 복붙):
최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — A02 트리 5순위 C12(U2 launchd com.airag.consumer) 회복 관찰 + 6순위 C13(KakaoBot 통합 보고서) published 칸 채움.

판정: **PASS — blocker 0 / major 0 / minor 2 / note 2(유지)**

검토: ft-airag-da-codex#1 · 2026-10-16 · 발주 #2579. 대상 Red `109258d`·`02a0cec` → fix `d4bf38b`, 기준 HEAD `d4bf38bd09dc5524e4c37cbafcf78a6a98eab10a`.
이하 `py:N`은 `feature-pack/rag-consumer/ops/probe-opa/s2.py`, `시험:N`은 `feature-pack/rag-consumer/tests/test_s2_opa.py`다. 이전 판정은 `da-20261016-sol-s2-code-r1.md`다. Serena 가용 yes: 수정 함수·참조와 새 시험 정의를 조회하고 실제 diff/합성 실행을 대조했다.

**r1의 M1·M2와 호출 마감 시험 공백은 종결한다. 종료 미확인 뒤 재시도/후속 라운드 진입도 차단됐다.** 새 blocker/major는 발견하지 않았다. 마지막 라운드에서의 불완전 귀결과 느린 성공의 보고 문구는 비차단 minor로 남긴다. 아래 세 구현 판단을 각각 명시했다. 이 PASS는 코드 재심이며, 실제 S2 실행/운영 재개 승인을 대신하지 않는다.

## 1. r1 항목 재심

| r1 항목 | 수정 및 독립 대입 | 판정 |
|---|---|---|
| M1 빠른 오류의 콜드 7초 초과 오보고 | py:289–290. timeout 또는 제한을 넘긴 success만 flag. 재대입한 auth_error는 최대 232ms, cold_over_limit=false, neither_meets. 시험:580–608에 빠른 오류 5종·timeout·느린 성공·보고 문구 추가 | 종결 |
| M2 동일/대소문자 동치 키도 both_meet | py:247–248,296–299. bytes.fromhex로 비교하고 모든 라운드 distinct=true를 기준에 포함. 재대입 두 사례 모두 keys_distinct=false·meets_all=false·neither_meets. 최대 시도 각각 238/248ms | 종결 |
| m1 종료 미확인 뒤 재시도/다음 라운드 | py:188–189,469–481. 첫 미확인 시도에서 재시도 없이 1회/timeout으로 종료. 첫 라운드 주입은 같은 라운드 3호출만 끝내고 다음 라운드·전용 조건 미실행, comparison=incomplete/report rc=1 | 핵심 조치 종결. 최종 라운드 귀결은 아래 minor 1 |
| m2 calls_within_deadline 항상 True 변이 생존 | 시험:692–698의 독립 15000ms 호출 부정 사례. 같은 변이를 새 시험에 다시 대입해 단언 실패 확인 | 종결 |

r1의 note 1(B1 병렬/직렬/단일 비교와 §6.1 경로 비교의 범위), note 2(selftest는 합성 실행 강제 장벽이 아님)는 수정 범위 밖이며 상태를 유지한다. 이를 다시 차단 항목으로 올리거나 새 기능을 요구하지 않는다.

## 2. Nano가 추가한 세 판단

| 판단 | 수용/수정 요구 | 이유 |
|---|---|---|
| ① 성공이지만 관측 시간이 7초를 넘은 경우 cold_over_limit 유지 | **수용** | 사전 기준은 각 시도 관측 시간 ≤7초다. 성공 여부와 지연 기준을 구분하며 attempts_within_limit=false/meets_all=false가 맞다. 상수를 올리거나 새 호출을 하는 조치도 아니다. 다만 종료 확인된 성공의 문구는 아래 minor 2에서 구별 |
| ② 미확인 중단의 aborted_class=None, 보고서 줄로 표시 | **수정 요구(최종 귀결), 새 오류 분류는 불필요** | 미확인은 예외를 던진 사건이 아니므로 aborted_class=None 자체는 수용한다. JSON에도 이미 시도별 child_exit_unconfirmed가 있어 문장만 남는 것은 아니다. 하지만 마지막 라운드에도 comparison=incomplete/report 비정상을 보장해야 한다. 아래 minor 1 |
| ③ 같은 라운드에서 이미 제출한 다른 두 병렬 호출은 완료까지 실행 | **수용** | 라운드 단위로 세 호출을 제출한 계약이다. 그 두 호출도 기존 7/14초·유한 회수 계약 안에서 끝내고, 다음 라운드/조건을 막으면 된다. 제출된 호출과 아직 시작하지 않은 다음 라운드를 구분한다. 강제 그룹 종료나 새로 공유 데몬을 건드릴 이유가 없음 |

③은 세 호출을 barrier로 함께 입장시키고 한 호출만 종료 미확인으로 반환하는 모형에서도 admitted/finished가 모두 [0,1,2]임을 확인했다. 실제 op를 실행한 것이 아니다.

## minor 1 — 맨 마지막 라운드의 종료 미확인은 incomplete로 귀결되지 않는다

근거: py:443–449,477–483,517–523 / 시험:671–689.

최종 save는 불완전 여부를 조건 2개·각 6라운드라는 **개수만으로** 판단한다. 마지막 dedicated 6회차에 처음 미확인이 생기면 개수가 모두 채워져 comparison이 incomplete가 되지 않는다. 종료 미확인 경고 문장은 나오지만 report의 종료코드는 0이다.

합성 라운드 반환을 주입한 결과:

| 주입 위치 | 실행 라운드 | comparison | aborted_class | Python report 코드 |
|---|---|---|---|---|
| default 첫 라운드 | 1개·조건 [1] | incomplete | null | 1 |
| dedicated 마지막 라운드 | 12개·조건 [6,6] | **default_only_meets** | null | **0** |

두 경우 모두 경고와 child_exit_unconfirmed 기록은 남고, 마지막 사례에서도 전용 경로 기준 충족은 거절된다. 실제 종료 불가 op를 만든 실험이 아니며 wrapper의 최종 코드는 별도 cleanup 결과에도 좌우된다. r1에서 minor로 둔 회수 미확인 조건의 추가 경계이므로 새 blocker/major로 올리지 않는다.

보강: complete=true는 «측정 절차가 끝남» 의미로 유지해 wrapper 대기를 끝낼 수 있다. 다만 어느 라운드든 종료 미확인이 있으면 최종 comparison=incomplete 및 report 비정상을 보장하고 마지막 라운드 사례를 추가한다. aborted_class나 레지스트리 항목을 새로 만들 필요는 없다.

## minor 2 — 느린 성공에도 종료 시점을 알 수 없다는 문구를 공통 적용한다

근거: py:289–290,514–516 / 시험:588–591,604–608.

success/9000ms 모형은 cold_over_limit=true·meets_all=false로 적절하게 판정하지만, 보고서는 timeout과 동일하게 «끝나는 시점은 알 수 없음»이라고 쓴다. 종료가 확인된 성공과 기한 내 완료가 관측되지 않은 timeout을 구별해야 한다. 성공 뒤의 관측 지연은 프로세스의 실제 종료 순간/캐시 원인까지 증명하지도 않는다.

보강: 느린 성공은 «관측 시도 시간 7초 초과, 종료는 확인됨», timeout은 «기한 내 미완료, 이후 정상 종료 시점은 미확인»으로 설명한다. ①의 boolean 유지 결정을 뒤집거나 측정 상수를 키울 필요는 없다. 현재 두 경우 모두 채택은 막히므로 비차단 문구 보강으로 둔다.

## 3. 실행 증거

| 검증 | 결과 |
|---|---|
| 수정본 원본 S2 시험 | **48 passed in 192.47s (3:12), rc=0** |
| r1 반례 재대입 | 빠른 auth_error 과장 없음, 중복 두 사례 neither_meets, 미확인 뒤 재시도 0(총 시도 1) |
| 직접 변이 재대입 | r1의 17종 + 수정 복구 5종 = **22/22 관련 시험이 탐지**. 이전 생존 호출 마감 변이도 새 독립 부정 시험에서 실패 |
| foreground PTY Ctrl-C | 전용 라운드에서 실제 s2.sh + 가짜 운영 의존성 → **130, job 0, 측정 직접 자식 생존 0**, op-home 보존 |
| 추가 경계 모형 | 첫/마지막 라운드 미확인, 느린 성공 보고, 같은 라운드 세 호출 완료를 별도 확인 |

기본 명령은 `feature-pack/rag/.venv/bin/python -B -m pytest tests/test_s2_opa.py -q -p no:cacheprovider`(cwd `feature-pack/rag-consumer`)다. 한 번의 정상 실행으로 48건이 통과해 부하로 인한 실패/단독 재실행은 없었다. Master의 병행 전체 회귀 결과는 작성 시점 미수신이므로 이 숫자에 합산하지 않았다.

r1 임시 실행기를 새 파일로 복사해 현재 소스에 적용했다. 반례는 동일 입력을 유지했고, PTY 시험의 바깥 관측 대기만 부하에 맞춰 늘렸다. 기존 변이 17종은 수정본의 분기 문자열에 맞췄고, 호출 마감 변이는 새 음성 시험을 선택했다. 빠른 오류 오분류 복구·문자열 중복 복구·distinct 기준 제거·미확인 재시도 허용·후속 라운드 허용의 5종을 추가했다. 변이별 선택 시험을 실행한 것이며 모든 사본에 48건 전체를 돌렸다고 주장하지 않는다.

## 4. 재현 위치·범위

- r1 반례 재대입: `/tmp/airag-s2-da-code-r2-checks.py`; 결과 `/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-s2-da-r2-checks-47bt4bch/evidence.json`.
- 변이: `/tmp/airag-s2-da-code-r2-mutations.py`; 결과 `/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-s2-da-r2-mutations-whjvxvy1/summary.json` 및 개별 result.txt.
- 추가 경계: `/tmp/airag-s2-da-code-r2-boundaries.py`; 결과 `/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T/airag-s2-da-r2-boundaries-ojjv5p9z/evidence.json`.

제품 소스/시험 수정·운영 접촉·설치·커밋·push는 0이며 쓰기는 이 판정서와 임시 합성 검증물뿐이다. 실제 op·운영 launchctl·운영 DB·runtime.json·운영 plist·운영 토큰/자격 파일을 실행/열람/변경하지 않았다. 합성 설정·토큰·가짜 도구만 사용했고, 신호/정리는 이 세션이 시작한 시험 프로세스에 한정했다. 서브에이전트는 사용하지 않았다. d4bf38b는 s2.py만 수정했고, 기존 도구·core 변경은 0이다.

Master는 위 minor 두 건의 비차단 보강을 별도 반영할 수 있다. 실제 S2 실행은 기존 계약대로 chain 결과 판단과 별도 사람 HIL 뒤이며 consumer disabled/S2 실행 보류 상태를 이 판정으로 바꾸지 않는다.
