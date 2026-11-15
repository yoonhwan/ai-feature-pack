# 설계 · 카드 초안 — 문제 ② launch-failed 가 PARKED 로 조용히 남음 (aifp-ft-arch-pi#16 · 2026-11-16)

- 발주: 팀장 #17 aifp 5310 ② · 사실 줄 5314(r2058 닫힘 = `ft2 complete --attempt a1` rc0 rev 2864 · BYZ #309621 · 집행 = harness arch#377) · 발주 전문 `orders/ORDER-arch16-three-problems-20261116.md`
- 상태: 설계 p3(팀장 #18 aifp 5364 · planner 5363 실사건 = v65 자동 배정이 나노 불가 카드 K4 를 a2 로 다시 띄움 · BYZ 309915) · 앞 판 = r1 DA 대행 APPROVE-DESIGN(5339) → p2 명부 찾기 1줄(sha256 53a003d6…) · p3 에서 바뀐 곳 = §1.1 실측 · §2 원인 4 · §3 규칙 6 · 7 · 시험 ㉘아~카 · 변이 M30 · M31 · p3 덧은 DA 전 · 카드 번호 = 팀장 부여 · 구현 = 나노 1석
- 기준판: 팩 origin/main 1757addf · 계약 `ft2/contracts/keeper-settle/CONTRACT.md` §3 · 설계 정본 `design/DESIGN-r2055-seat-settle-one-path.md` §4.2(62 · 94 · 104 · 135줄)

## 1. 실측 — r2058 (harness journal · keeper 로그 · launch intent 원문 · 읽기만)

| 시각 | 줄 |
|---|---|
| 11-15 19:45 | `HELD-ORPHAN … nano-r2058…#0 자동 개설 근거 없음`(손으로 연 나노가 그 카드를 이미 하고 있었다) |
| 11-16 00:05:00 | journal 2852 accept `keeper-next-r2058-…` → 2853 dispatch a1 → 2854 deliver(keeper fill) |
| 00:05:05 | intent `state: failed · step: git add · reason: …worktrees/r2058-…@a1 이(가) 이미 있습니다` |
| 00:06:34 | `UNKNOWN harness r2058-… 남은 범위 줄 없음`(착지는 봤지만 카드에 «- 남은 범위:» 줄이 없어 complete 0) |
| 00:06:35 | `판정 불가 harness 쪽지 3 — [긴급] UNKNOWN … 착지했지만 complete 0`([긴급] 전송 실패) |
| 00:06:36 | `PARKED harness r2058-… launch-failed` · journal 2855 parked a1 |
| 00:06:37 | `HELD-NEXT harness fill:r2058-… launch 실패` → fill_hold(같은 카드 자동 재시도 0) |
| 00:44:25 | journal 2863 complete a1 · 2864 reassess(harness arch#377 손 집행) |

00:06:37 부터 00:44:25 까지 keeper 는 이 work 에 줄을 하나도 내지 않았다.

### 1.1 실측 — v65 K4 다시 띄움 (p3 · 읽기만)

| 본 것 | 값 |
|---|---|
| keeper 로그 | 11-16 01:15:56 `LAUNCHING v65 byz-v65-nano-K4-lst-on-long3m-003-joint-read-after-sp#0 열기 …@a2.log` → 01:17:17 `NEXT v65 fill:K4-…`(a1 = 11-14 12:36 열기 멈춤 · intent opening) |
| 카드 | BYZ `origin/ops/main-base:design/v65/indices/대기/K4-lst-on-long3m-003-joint-read-after-split-landing.md` 머리에 `- 배정:` · `- 선행:` 줄 없음(나노 불가를 말하는 줄 0) |
| 배정 원장 | 그 뒤 v65 팀장이 손으로 막음: `.fable-team/state/card-assign/K4-….json` = `{"reason": "정지", "state": "waiting", …}`(4건 · rc0 · planner 5363) |
| 명부 | 다시 뜬 좌석이 유휴인데 명부 행이 없어 `ft-seat-close` 를 못 씀(도구가 `seats-v65.json` 을 찾음 · v65 명부 = `seats.json`) |
| keeper 가 지금 보는 막힘 근거 | `keeper_next.choose` 139줄: 배정 원장 `state == seat` · owner 있음 · 원장 `reason ∈ BLOCK`(`정지` · `석` · `선행` · `DA` · `사람` · 10줄) · 카드 줄은 `- 배정: 대기(선행` 과 `- 선행:` 만(`prereq` 14~26줄) |

## 2. 원인 (세 겹 + p3 한 겹)

1. **쉼 줄이 그 work 를 바퀴에서 뺀다.** `keeper.team_round` 는 최신 attempt 에 `parked` 줄이 있으면 `continue` 한다(302 · 305줄). 착지 판독 · complete · 판정 · [긴급] 이 모두 건너뛰어진다. idle-done 에는 맞는 동작이다(끝났고 안전). launch-failed 에는 틀리다(일이 시작도 못 했거나, r2058 처럼 다른 손이 끝낸 상태).
2. **다시 여는 길이 막혀 있다.** r2055 설계는 «launch-failed = fill 이 새 attempt 로 다시» 라고 적었다(94 · 135줄). 실제 fill 은 launch 실패 카드를 `fill_hold` 에 넣고 «원장을 손보면 다시 시도» 로 둔다(r1913 · r1939). 두 규칙이 만나 자동 재시도 0 · 판정 0 이 된다.
3. **fill 이 이미 착지한 카드를 골랐다.** 카드가 `대기/` 에 남아 있으면 `choose()` 는 착지 여부를 보지 않는다. r2058 은 착지가 끝난 카드였다.

4. **(p3) 나노가 하면 안 되는 카드를 말하는 추적되는 자리가 없다.** 막는 길은 배정 원장(`state/card-assign/<카드>.json` · 리포 밖 · 손 조치)뿐이다. 카드 머리의 `- 배정: 대기(<사유> …)` 는 `선행` 만 읽는다. 그래서 원장에 손을 대기 전까지 keeper 는 그 카드를 계속 후보로 본다. a1 이 막혀도(열기 멈춤 · 열기 실패 · 반환) owner 가 풀리는 순간 a2 로 다시 띄운다.

## 3. 고침 — launch-failed + 세션 0 의 정해진 끝

원칙: 자원은 푼다(지금처럼 core `park`). 판정 낱말은 `PARKED` 가 아니다. 매 바퀴 다시 본다.

| # | 자리 | 규칙 |
|---|---|---|
| 1 | `keeper.team_round` 건너뜀 조건 | 최신 attempt 의 쉼 사유가 `launch-failed` 이면 건너뛰지 않는다(`idle-done` 쉼 · `returned` 는 지금처럼 건너뜀) |
| 2 | 그 work 의 바퀴 순서 | 착지 판독 → 착지면 complete(LANDED 길 · 세션이 없으니 닫기 0) → 카드 끝 표식이면 close 길 → 둘 다 아니면 3번 |
| 3 | `keeper_settle.settle_nano` | intent failed·closed ∧ 세션 부재 = core `park`(reason launch-failed · 자원 해제 · 1회 멱등)는 그대로 하고, 판정 줄은 `UNKNOWN <팀> <work> <좌석> launch-failed · <intent step · reason 앞 80자>` + [긴급] 1통(지문 하루 1회 · 다음 수 = «원인 고친 뒤 원장 갱신 → fill 재시도 · 필요 없으면 return 또는 카드 끝 표식») |
| 4 | 3번 뒤 | 그 work 에 stall 깨움 · 재배정 · hold 검사 0(깨울 좌석이 없다) |
| 5 | `keeper_next.choose` | 착지 판독이 참인 카드는 고르지 않는다 · `NEXT-SKIP <팀> <카드> 이미 착지 — 카드 정리 필요` 1줄(값이 바뀔 때만) |

| 6 | `keeper_next.prereq`(카드 줄) | **나노 불가 표식 = 카드 머리 `- 배정: 대기(<사유> · <시각>)` 의 사유가 `사람` · `정지` · `DA` · `lint` · `면제대기` · `선행` 중 하나.** 이 줄이 있는 카드는 fill · 닫기 뒤 pick 둘 다 고르지 않는다(지금은 `선행` 만 읽음). 새 칸을 만들지 않는다: `ft-index-lint` 가 이미 허용하는 `- 배정:` 값 꼴 그대로다. `- 배정: 좌석 <이름>` · `- 배정: 없음` · 줄 없음은 막지 않는다 |
| 7 | 판정 근거 칸 두 곳의 순서 | 한 함수에서 본다: ① 배정 원장 `state == seat` 또는 owner 있음 = `배정됨` ② 배정 원장 `reason ∈ BLOCK` = 그 사유 ③ 카드 `- 배정: 대기(<사유>` = 그 사유 ④ 카드 `- 선행:` 판독. 원장(②) 또는 카드(③) 중 하나만 막아도 막힌다. 원장이 `없음` 이어도 카드 줄이 막으면 막힌다(원장은 리포 밖이라 지워질 수 있다 · 카드 줄이 추적되는 정본) |

- 6 · 7 로 «재발주 0» 이 된다: 막힌 카드는 owner 가 풀려도(쉼 · 반환 · 열기 실패) 다시 후보가 되지 않는다. 풀기 = 카드 줄을 `- 배정: 없음` 으로 고치고(추적 커밋) 원장을 `없음` 으로.
- [다음 없음] 쪽지의 «막힌 사유별» 셈에 그 사유가 그대로 들어간다(`사람 1 정지 4` 꼴 · 새 문구 0).
- v65 가 손으로 둔 원장 `정지` 4건은 그대로 유효하다(② 가 이미 읽는다). 이 규칙은 같은 뜻을 카드에 적을 수 있게 한다.
- K4 가 a2 로 다시 뜬 직접 길(a1 owner 가 언제 풀렸는지)은 안 봤다 [확인 필요: v65 journal 의 K4 a1 뒤 줄(returned · parked · reassess 중 무엇) — v65 팀장 또는 나노가 시험 입력으로 대조].
- 명부: 다시 뜬 나노의 명부 행은 행 E 의 명부 찾기 한 함수가 `launch_roster.py` 에 들어가면 `seats.json` 에 적힌다(v65). 이 카드는 그 함수를 쓰기만 한다 → 선행 = 행 E 착지.
- 끝은 둘 중 하나다: (가) 착지 근거가 있으면 keeper 가 complete 로 닫는다 (나) 없으면 사람 판정 1줄이 매일 다시 뜬다. 조용한 PARKED 는 없다.
- r2058 꼴(착지 봄 · «남은 범위» 줄 없음)은 이미 있는 `UNKNOWN 남은 범위 줄 없음` [긴급] 이 매 바퀴 판정에 다시 잡힌다(1번 덕분). 카드에 줄을 넣으면 다음 바퀴에 complete 된다.
- **경계(팀장 개설은 대상이 아니다 · 팀장 5334 · 5340)**: 이 규칙이 보는 것은 keeper 가 dispatch 한 work 의 launch intent(`teams/<팀>/runtime/launch/<work>@<attempt>.intent`)뿐이다. 팀장 · arch · desk 개설(`ft-successor-open.sh` · 팀장 열기 길)은 journal dispatch 도 launch intent 도 만들지 않으므로 판정 · park · [긴급] 대상이 아니다. 5번(fill 의 착지 카드 제외)도 keeper 의 카드 pick 만 바꾼다.
- core `park` · `capacity` · `remaining` 손 0. 용량에서는 지금처럼 빠진다(launch-failed 가 칸을 쥐지 않는다).
- [긴급] 전송 실패(00:06:35 «쪽지 3»)는 지문을 쓰지 않으므로 다음 바퀴에 다시 보낸다(지금 규칙 그대로 · 1번이 있어야 그 다음 바퀴가 온다).

- **명부 찾기(planner 5353 덧 · 행 F)**: 이 규칙이 내는 [긴급] 의 받는 곳은 행 E 설계의 명부 찾기 한 함수를 쓴다(`seats-<팀>.json` → 없고 v65 면 `seats.json`). 이 카드에서 명부 경로를 새로 만들지 않는다. v65 6장의 판정은 행 E 착지 뒤 v65 팀장(byz-v65-master-pi#294)에게 간다.

### 계약 · 설계 문서 고침(같은 PR)

- `CONTRACT.md` §3: `PARKED launch-failed` 행을 `UNKNOWN launch-failed`(park 는 실행 · 판정은 UNKNOWN · 매 바퀴 재판독)로 옮긴다.
- `CASES.md` ③ · ⑫ 기대값: «park 1회 · 용량 −1» 그대로 + 판정 낱말 `UNKNOWN launch-failed` · «fill 이 새 attempt 로 다시» 문구를 «원장 갱신 뒤 fill 재시도(fill_hold 규칙)» 로 고친다.
- `DESIGN-r2055` 는 이관 원문이라 고치지 않는다. 계약 머리 표에 이 카드를 «설계 뒤 고침» 1줄로 적는다.

### 고르지 않은 길

| 길 | 버린 까닭 |
|---|---|
| launch-failed 면 keeper 가 새 attempt 로 자동 재시도 | r2058 꼴(워크트리가 이미 있음)은 몇 번을 해도 실패한다. 재시도 폭주 · r1913 «자동 재시도 0» 과 충돌 |
| park 를 하지 않음 | owner · 예약 · 용량 칸이 남는다(r1968 · r1973 반쪽이 다시 생김) |
| launch-failed 면 바로 complete | 일을 하지 않았는데 완료가 된다 |

## 4. 시험 (나노 · 새 파일 1개 · 가짜 journal · 임시 루트)

| # | 사례 | 기대 |
|---|---|---|
| ㉘가 | intent failed · 세션 부재 · owner 있음 · 착지 0 | park 1줄 · `UNKNOWN … launch-failed` 1줄 · [긴급] 1 · `PARKED` 줄 0 |
| ㉘나 | ㉘가 다음 바퀴(쉼 줄 있음) | 건너뛰지 않음 · park 다시 0(멱등) · 판정 줄 반복 0 · stall 깨움 0 |
| ㉘다 | ㉘가 뒤 카드에 착지 줄 + «남은 범위: 없음» 이 생김 | 다음 바퀴에 complete 1 · 닫기 호출 0 · 그 뒤 바퀴 줄 0 |
| ㉘라 | r2058 꼴: 착지 봄 · «남은 범위» 줄 없음 · launch-failed 쉼 | 매 바퀴 판정 대상 · `UNKNOWN 남은 범위 줄 없음` 유지 · 카드 고치면 complete |
| ㉘마 | idle-done 쉼 | 지금처럼 건너뜀(줄 0) |
| ㉘바 | fill 후보가 이미 착지한 카드 1 + 안 한 카드 1 | 안 한 카드만 submit · `NEXT-SKIP` 1줄 |
| ㉘사 | 팀장 좌석(`byz-<팀>-master-…`)이 세션 0 · launch intent 없음 | 그 좌석에 판정 줄 0 · park 0 · [긴급] 0(지금과 같음) |
| ㉘아 | 대기 카드 2장 · 한 장 머리에 `- 배정: 대기(사람 · 2026-11-16T01:00)` · 빈 나노 칸 | 그 카드 submit 0 · 다른 카드만 submit · [다음 없음] 셈에 `사람 1` 없음(다른 카드가 있어 쪽지 0) |
| ㉘자 | ㉘아 카드 1장뿐 | submit 0 · [다음 없음] 1통 · 막힌 사유별 `사람 1` |
| ㉘차 | 나노 불가 표식 카드 · a1 이 launch-failed 쉼(owner 풀림) · 원장 `없음` | 다음 바퀴 a2 dispatch 0 · LAUNCHING 0(재발주 0) |
| ㉘카 | 카드 줄 없음 · 원장 `{"reason": "정지", "state": "waiting"}` | submit 0(지금과 같음) / 카드 `- 배정: 좌석 <이름>` · 원장 없음 → 막지 않음 / 카드 `- 배정: 없음` → 막지 않음 |
| M11 | 1번(건너뜀 예외)을 뺌 | ㉘나 · ㉘다 · ㉘라 FAIL |
| M12 | 3번 판정을 PARKED 로 되돌림 | ㉘가 FAIL |
| M13 | 5번을 뺌 | ㉘바 FAIL |
| M30 | 6번을 뺌(카드 줄은 `선행` 만 읽음) | ㉘아 · ㉘자 · ㉘차 FAIL |
| M31 | 7번에서 원장 `없음` 이 카드 줄을 이기게 함 | ㉘차 FAIL |

회귀: `test_settle_one_path_r2055.py`(③ · ⑫ 기대값을 이 설계로 고침 · PR 본문에 적음) · `test_core_park_capacity_r2055.py` · r1913 · r1939 fill 시험.

## 5. 닫는 증거

1. 규칙 커밋(팩 main 착지 sha).
2. 시험 사례 ㉘가~바 통과 줄.
3. harness 몫 사실 줄(받아 적음): r2058 = `ft2 complete --attempt a1` rc0 rev 2864 · BYZ #309621.

## 6. DA 에게 묻는 것

- Q1. park 는 하고 판정만 UNKNOWN 으로 내는 것이 계약 §1 «판정 4개 · 바퀴당 1개» 와 맞는가(PARKED 행동 + UNKNOWN 낱말).
- Q2. 5번(착지한 카드 fill 제외)을 이 카드에 둘지 문제 ① 카드로 옮길지.
- Q4(p3). 나노 불가 표식을 새 칸 없이 `- 배정: 대기(<사유>` 로 읽는 것이 맞는가 · `대기(석 · …)` 은 «나노 좌석을 기다림» 이라 막지 않는 쪽에 뒀다(막으면 fill 이 영영 못 고름).
- Q5(p3). 원장과 카드가 다를 때 «하나라도 막으면 막힘» 이 맞는가.
- Q3. 5번의 착지 판독을 fill 후보마다 부르면 바퀴 시간이 늘어난다. 바퀴 캐시(`once`)로 충분한가.
