# 설계 · 카드 초안 — 문제 ① 2.0 완료 전 keeper 가 새 카드를 투입 (aifp-ft-arch-pi#16 · 2026-11-16)

- 발주: 팀장 #17 aifp 5310 ① · 덤 사실 5314 · 발주 전문 `orders/ORDER-arch16-three-problems-20261116.md`
- 상태: 설계 r1(+ 경계 1줄 · 시험 ㉗사 = 팀장 5334 · planner 5333 · 오빠 00:54 «병렬로 전팀 팀장 투입») · DA 반박 전 · 카드 번호 = 팀장 부여 · 구현 = 나노 1석
- 기준판: 팩 origin/main 1757addf · `adapters/pi/keeper_next.py` git log 확인(최신 d88ef381 r2055 · r1939 fill 꽉 참 · r1913 fill 원본)

## 1. 실측 (BYZ `.fable-team/state/ft2-keeper/` 로그 원문 · 읽기만)

- 전 팀 정지(ALL_STOP)가 11-15 23:44 에 풀렸다. 그 뒤 keeper fill 이 harness 에 새 카드 3장을 넣었다.
  - `NEXT harness fill:r2057-silent-wait-to-critical-one-path` (a1 launch 실패 → a2 성공)
  - `LAUNCHING … r2058-oppa-thread-goal-news-on-change@a1` 00:05:03 → `PARKED … launch-failed` 00:06:36
  - `NEXT harness fill:r2064-status-head-stale-day-cannot`
- journal: harness seq 2852 accept `keeper-next-r2058-…` 00:05:00 → 2853 dispatch → 2854 deliver.
- 지금 막는 손 조치 = harness `state/harness-tick/PAUSED`(팀별 파일 · 임시).

## 2. 원인

`keeper_next.gates()` 가 보는 것은 팀별 `CLOSE-NEXT.enabled` · 팀별 `PAUSED` · `SPAWN_HOLD` · `ACCT_PAUSE` · 나노 상한뿐이다. «지금은 새 카드를 넣지 않는 기간» 을 말하는 전 팀 설정이 없다. 그래서 ALL_STOP 이 풀리면 fill 이 `대기/` 카드를 바로 넣는다. 막으려면 팀마다 PAUSED 를 손으로 둬야 한다(PAUSED 는 그 팀 틱 전체를 멈추는 다른 뜻의 파일이다).

## 3. 고침 — 새 카드 투입 보류 설정 1곳

| 항목 | 값 |
|---|---|
| 설정 자리 | `<데이터 루트>/.fable-team/state/NEW_CARD_HOLD.json` 1개(전 팀 공통) |
| 꼴 | `{"reason": "<10자 이상>", "by": "<좌석>", "at": "<시각>", "until": "<사람이 읽는 조건 · 예: ft 2.0 완료>"}` |
| 판독 | keeper 가 바퀴당 1회(ALL_STOP 판독과 같은 꼴). 없음 = 열림 · 있음 = 보류 · 깨짐 = 보류 + `판정 불가` 1줄 |
| 막는 것 | keeper 가 스스로 새 카드를 고르는 두 곳: `fill()` 의 새 pick(`keeper_next.py` 197줄) · 닫기 뒤 다음 카드 pick(`close()` 157줄) |
| 안 막는 것 | 이미 연 열기 잇기(`fill_open` reconcile) · settle · 착지 complete · 닫기 · 깨움 · 사람 손 `ft2 submit/assign/deliver`(팀장 발주) |
| 드러냄 | 팀마다 `NEW-CARD-HOLD <팀> <reason> · until <until>` 1줄(값이 바뀔 때만) · 풀리면 `NEW-CARD-OPEN <팀>` 1줄 |
| 풀기 | 파일을 `NEW_CARD_HOLD.released-<시각>` 으로 이름 바꿈(ALL_STOP 과 같은 손 · 2.0 완료 선언 때 planner master 집행) |

- **경계(팀장 개설은 막지 않는다)**: 이 파일을 읽는 곳은 keeper 의 카드 pick 두 곳뿐이다. 좌석을 여는 도구(`ft-successor-open.sh` · 팀장 열기 길 · `ft-nano-spawn.sh` · `tmuxc open`)는 이 파일을 읽지 않는다. 보류 중에도 팀장 개설 · 승계 · 사람 손 나노 개설은 지금과 같다. 구현은 `ft2/adapters/pi/keeper_next.py`(판독 함수 자리 포함) 밖에서 이 파일 이름을 참조하지 않는다.
- «2.0 완료» 는 기계가 판정하지 않는다. 사람이 둔 파일 1개가 기준이다(추측 0).
- 닫기 뒤 영수(`close_receipt`)는 지금처럼 쓴다. 다음 카드만 `[다음 없음]` 과 같은 길(next 없음)로 간다.
- 팀별 `PAUSED` 는 이 설정이 들어간 뒤 harness 에서 치운다(집행 = harness 팀장 · 이 카드 밖).

### 고르지 않은 길

| 길 | 버린 까닭 |
|---|---|
| `thresholds.env` 에 키 추가 | env > 루트 > 홈 > 샘플 4곳을 읽는다. «1곳» 이 아니다. launchd env 가 조용히 이긴다 |
| `gates()` 안에 넣기 | `gates()` 는 복구 launch 가드(226줄)도 쓴다. 이미 배정된 일의 이어 열기까지 막는다 |
| ALL_STOP 다시 켜기 | 닫기 · settle · 깨움까지 멈춘다(발주 제약 «전체 정지 0») |

## 4. 시험 (나노 · 새 파일 1개 · 가짜 journal · 임시 루트)

| # | 사례 | 기대 |
|---|---|---|
| ㉗가 | HOLD 파일 있음 · 빈 나노 칸 · 대기 카드 1 | fill submit 0 · journal 줄 수 그대로 · `NEW-CARD-HOLD` 1줄(둘째 바퀴 0줄) |
| ㉗나 | HOLD 파일 있음 · 나노 닫기 1 | 닫기 영수 1 · 다음 카드 배정 0 |
| ㉗다 | HOLD 파일 있음 · `fill_open` 에 잇는 열기 1 | reconcile 그대로 진행 |
| ㉗라 | HOLD 파일 깨짐(빈 파일 · JSON 아님) | fill 0 · `판정 불가` 1줄 |
| ㉗마 | 파일 없음 | 지금 동작과 같음(fill 1장) |
| ㉗바 | 두 팀 · 파일 1개 | 두 팀 모두 fill 0 |
| ㉗사 | HOLD 파일 있음 · 팀장 개설 1회(`ft-successor-open.sh` · tmux · 쪽지 대역) | 파일이 없을 때와 같은 rc · 같은 출력(막힘 줄 0) + 팩 `feature-pack/fable-team/` 에서 `NEW_CARD_HOLD` 를 참조하는 실행 파일 = keeper 쪽뿐(문자열 검색 1회) |
| M14 | fill 의 HOLD 검사를 뺌 | ㉗가 · ㉗바 FAIL |
| M15 | close 의 HOLD 검사를 뺌 | ㉗나 FAIL |

회귀: `test_pi_keeper_next_card_r1871.py` · r1913 · r1939 fill 시험 · `test_settle_one_path_r2055.py`.

## 5. 닫는 증거

1. 고친 커밋(팩 main 착지 sha) + 설치 판.
2. 설정 파일을 둔 뒤 keeper 로그의 팀별 `NEW-CARD-HOLD` 줄.
3. 그 시각 뒤 전 팀 journal 에 새 `accept keeper-next-*` 줄 0(팀별 원문 셈 1줄씩).

## 6. DA 에게 묻는 것

- Q1. 닫기 뒤 다음 카드 pick 까지 막는 범위가 맞는가(발주 낱말은 fill).
- Q2. 깨진 파일 = 보류로 보는 방향이 맞는가(ALL_STOP 과 같은 쪽).
