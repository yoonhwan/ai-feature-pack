# ft2 병렬 배정·실행권 계약 사례표 (r1549)

ft 2.0 PR② 구현이 통과해야 닫히는 **입력 사건 → 기대 결과** 표다. 사례는 r1507 배정 실험과
r1509 독립 checker 관측(`design/harness/research/ft-2.0/parallel-dispatch/`)에서 옮겼고,
실험 코드는 실행하지 않는다(원자료 `git show` 읽기만 · 측정 조작 0).

## 원자료 재계수 (2026-11-10 · BYZ origin/main `db18c453c77868355ffeb813d3b4c49f2047806a`)

| 항목 | 값 | 근거 |
|---|---|---|
| 사례 함수 | **8** | `cases_e1e2.py` 4(`e1_normal`·`e1_variant`·`e2_normal`·`e2_variant`) · `cases_e3e4.py` 4(`e3_normal`·`e3_variant`·`e4_normal`·`e4_variant`) — `grep '^def '` |
| 사례표 파일 | **8** | `cases/*.json` |
| PLAN «8칸» 대조 | **일치** | PLAN §병렬 배정 «기존 8칸 내 정상 7 · 의도 변이 FAIL 1» — 사례 함수 8 = 정상 4 + 변이 1 + 주입 3 |
| compare 대조 칸 | **56** | `checker-r1509/compare.json` — pair 8 × 7수(dispatch·owner·reserved·delivery·reassess·release·uncertain_release) · `mismatch: []` |
| checker 관측 키 | **15** | `counts.json` 사례 13 + 접두 스냅숏 2(`E1n_mid`·`E1n_after_all`) — 판1·보정 판 모두 같은 15키 |
| 의도 변이 | **1** | `E1v-teamclose-gate` 판정 FAIL(계약 극성 검사만 실패) — 표에서 극성 `변이` |
| 보정 판 차이 | 1행 | `raw2/counts2.json`(`e42a005e`·D7) 의 `E4v-evidenceonly` = 재평가·반환·owner 복구 **W3 만**(판1 은 W2 포함) |

## 판정 낱말 (정본 문면 · 새 낱말 0)

`expect.판정` 은 `PASS`/`FAIL` 두 낱말만 쓴다. 극성 `변이` 사례의 FAIL 은 **계약 위반 재현**이지
구현 결함이 아니다(1판 `raw2/cases.json` 의 `intentional_fail`·`unintended_fail` 구분과 같은 뜻).
`정상`·`주입` 사례는 PASS 여야 한다 — 아니면 표가 틀렸거나 관측이 갈라진 것이다.

## 사례표 8행

| id | 축 | 극성 | 사건(요약) | 판정 | 관측 키(갈래) |
|---|---|---|---|---|---|
| case_01_e1n_normal_allof | E1 | 정상 | A 대기 중 독립 W3 배정 1 · B 완료 1 · D 미충족 배정 0 · 충족 사건 뒤 D 배정 1 | PASS | E1nn(정본) · E1n_mid(중간) · E1n-after(충족 뒤) · E1n_after_all(같은 폴더 재기록) |
| case_02_e1v_teamclose_gate | E1 | 변이 | 팀 마감 «잔여 0» 을 배정 증거로 재사용 → 미완 선행 W1 대기인데 W4 배정 1 | FAIL(의도) | E1vv(변이 arm) · E1v-ctrl(대조 arm) |
| case_03_e2n_single_claim | E2 | 정상 | claim 1회 → owner 1 · 예약 1 · 배정 1 | PASS | E2nn(정본) |
| case_04_e2v_race_two_claimants | E2 | 주입 | 두 claimant 동시 · 공유 자원 1 — 원자 경계 vs 스냅숏 경합 | PASS | E2v-atomic(원자) · E2v-stale(스냅숏 = 변이 검출) |
| case_05_e3n_claim_deliver | E3 | 정상 | claim + 전달 → 전달 1 · 수신 업무 실행 1 | PASS | E3nn(정본) |
| case_06_e3v_crash_before_delivery | E3 | 주입 | claim 쓰기 뒤 · 전달 쓰기 전 crash → 의도 복구 + 같은 attempt 재전달 | PASS | E3v-contract(정본) · E3v-nointent(의도 미기록 = 변이 검출) |
| case_07_e4n_complete_reassess | E4 | 정상 | 완료 → 재평가 1 · 반환 1 · owner 복구 1 | PASS | E4nn(정본) |
| case_08_e4v_crash_before_reassess | E4 | 주입 | 완료 쓰기 뒤 · 재평가 표식 전 crash → 표식 복구 재평가·반환·owner 복구 | PASS | E4v-contract(정본) · E4v-evidenceonly(판1 관측 · 보정 판 D7) |

각 사례 파일 칸 = `id` · `사례 이름` · `축` · `극성` · `출처`(정본 경로·sha·함수·줄 + `비교 키`·`관측 키`) ·
`given`(배정·완료·재전달 사건 열 + attempt id) · `expect`(판정 · 계약 문면 · 관측).

`expect.관측` 행은 `키`(원자료 키) · `갈래` · `원자료`(`판1`=`counts.json` · `보정`=`raw2/counts2.json`) ·
`값`(checker 필드 이름 그대로, 값을 바꾸지 않고 옮김) 이다. 7수는 counts 필드에서 그대로 온다:
`dispatch`=`dispatch_journal`(=`dispatch_state` 와 같아야 함) · `owner` · `reserved` · `delivery` ·
`reassess`=`reassess_journal` · `release`=`release_journal` · `uncertain_release`.

같은 attempt 억제는 수가 아니라 **실행/억제 쌍**으로 적는다 — `run`(수신 업무 실행 수) ·
`suppressed`(`execute-suppressed` 줄 수) · `deliver_attempts`. E3 주입 사례 = 전달 2 · 실행 1 · 억제 1.

## 필수 관측 집합 (DA R1 · 2026-11-10)

`replay_check.py` 는 «선언된 칸만» 비교하지 않는다. arm 행(원자료 `cases` 키)은 7수 + `run` ·
`suppressed` · `deliver_attempts` 를 **반드시** 선언해야 하고, 하나라도 빠지면 rc=1 이다
(DA R1 반증: E3v 에서 세 필드를 지운 표가 rc=0 으로 통과하던 결함 → 지금은 rc=1).
접두 스냅숏 행(`E1n_mid`)만 `dispatch_journal` · `deliver_by_task` 로 줄인다.

## 구현 계약 사례 (r1616 · 재생 원자료 아님)

이 표는 위 8행(실험 재생)과 달리 **제품 구현**에 붙은 계약 사례다. `replay_check.py` 는 `cases/*.json` 만 보므로
이 행은 재생 대조에 들어가지 않는다(사례 수 8 불변).

| 사례 | 사건 | 판정 | 계약 문면 | 시험 |
|---|---|---|---|---|
| 접수 없는 배정 | 같은 work 의 `kind=accept` 영수가 없는데 `assign` | **접수 거부** · `written=false` · journal·state 바이트 불변 | 「접수한 일만 배정한다」 — 영수는 `intake.submit(command, body, work)` 가 남긴다 | `tests/test_core_assign_requires_accepted.py` ⓑ · M1 |

## 미시험 (이 표가 닫지 않는다)

실 분산 잠금(다중 호스트·네트워크 분할)과 실제 역할 통합(planner/구현/checker 실좌석 사슬)은 관측이
없어 사례 0 이다 — 표에 올리지 않는다. 재전달 상한·UNCERTAIN 반환 허용 변이·제품 구현 채택 판정도 미시험.
