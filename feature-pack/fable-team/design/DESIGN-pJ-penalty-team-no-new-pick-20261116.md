# 설계 — 행 J keeper 가 전 세션 정지(PENALTY_STOP) 재개 전 팀에 새 카드를 넣는다 (aifp-ft-arch-pi#18 · 2026-11-16)

- 발주: 팀장 #19 aifp 5461 (나) · 5464(Issue #8650) · 범위 판단 5455 → 회신 5459 «새 카드» · 결함 원문 = planner 5446(room#48 BYZ 310510)
- 상태: 설계 r1 · DA 판정 전 · 카드 = 팩 `design/aifp/indices/대기/ft2-penalty-team-no-new-pick.md` · 구현 = 나노 1석 · 코드 0(이 문서는 읽기 실측만)
- 기준판: 팩 origin/main 592cb9fd · `feature-pack/fable-team/ft2/adapters/pi/keeper_next.py`(244줄 · 마지막 고침 d88ef381 r2055 · 설치본 2.0.63 과 바이트 같음)
- 시험 번호 ㊲ · 변이 M62~M66

## 1. 실측과 근거 (읽기만 · 11-16 02:27~02:30)

| 본 것 | 값 |
|---|---|
| BYZ `.fable-team/state/PENALTY_STOP` | 있음(336바이트 · 고친 때 11-16 01:11) · `order` 11팀에 room · `resumed` = feature · cfo · knowledge · ops · v65 · chatbot · room 없음 |
| 1.x 판정기 `ft-penalty.sh check room`(FT_ROOT = BYZ 루트) | `REJECT penalty 전 세션 정지 중 — 팀=room 은 아직 재개 전 …` rc 3 |
| 같은 명령 `check cfo` | 출력 0 · rc 0 |
| BYZ keeper 로그 `state/ft2-keeper/20261116.jsonl` | 02:19:31 `LAUNCHING room byz-room-nano-R-room-runner-home-ws-origin-check#0 열기 …@a2.log` → 02:20:54 `WORKING … cpu-busy · 착지 줄 없음` → 02:20:56 `NEXT room fill:R-room-runner-home-ws-origin-check -> …` |
| `keeper_next.gates()`(50~66줄) | 보는 것 = 팀 `CLOSE-NEXT.enabled` · 팀 `PAUSED` · `SPAWN_HOLD` · `ACCT_PAUSE` · 나노 상한. `PENALTY_STOP` 0 |
| ft2 `adapters/pi/*.py` | `ft-penalty` · `ft-nano-spawn` 을 부르는 곳 0(문자열 검색) |
| 1.x `ft-nano-spawn.sh` 275~279줄 | `PENALTY_STOP` 이 있으면 `ft-penalty.sh check <팀>` 을 부르고 rc 3 이면 열지 않는다. 판정기가 없으면 REJECT |
| `ft_penalty.py check`(96~101줄) | 파일 없음 = 통과 · 팀이 `EXEMPT`(harness · planner) 또는 `resumed` 안 = 통과 · 아니면 rc 3 |
| `gates()` 를 부르는 곳 | 3곳 = 닫기 뒤 다음 카드 pick(157줄) · fill pick(197줄) · 복구 launch 직전 가드(226줄 · `reconcile`) |

- 사건의 a2 는 fill 이 새로 넣은 것이다(로그 `NEXT room fill:…`). 닫기 뒤 pick 길은 이 사건에서 타지 않았다.
- 그 카드는 «착지 줄 없음» 이었다. 열기 실패 카드(ft2-launch-failed-end)의 L5(착지 카드 제외)로는 막히지 않는다.

## 2. 원인

1. 전 세션 정지는 1.x 의 나노 열기 도구(`ft-nano-spawn.sh`)에서만 막는다. ft2 keeper 는 그 도구를 거치지 않고 스스로 submit · assign · deliver 한다.
2. keeper 의 팀 문(`gates()`)에는 `PENALTY_STOP` 판독이 없다. 그래서 재개 전 팀에도 빈 칸이 있으면 카드를 넣는다.

## 3. 고침

| # | 자리 | 규칙 |
|---|---|---|
| 1 | 새 함수 `penalty_open(k, team)`(keeper_next.py) | 참 = 새 카드를 넣어도 됨. `<루트>/.fable-team/state/PENALTY_STOP` 이 없으면 참이고 판정기 호출 0 이다. 있으면 `ft-penalty.sh check <팀>` 을 부른다(FT_ROOT = `k.root`). rc 0 = 참 · rc 3 = 거짓 · 그 밖(rc 1 · 2 · 도구 없음 · 시간 초과) = 거짓 + `판정 불가` |
| 2 | 판정기 자리 | env `FT2_PENALTY_BIN` → 없으면 `dirname(k.close_bin)/ft-penalty.sh`(`SPAWN_HOLD` · `ACCT_PAUSE` 판정기와 같은 폴더 규칙 · 56줄). 호출은 바퀴 캐시 `once(k, "penalty|<팀>", …)` 로 팀당 바퀴 1회 |
| 3 | 막는 곳 | 새 pick 두 곳뿐이다: `fill()` 의 pick(197줄) · `close()` 의 닫기 뒤 다음 카드 pick(157줄). 꼴 = `gates(k, team) and penalty_open(k, team)` |
| 4 | 닫기 뒤 길 | 닫기 영수(`k.receipt`)는 지금처럼 쓴다. 다음 카드만 «없음» 길로 간다(`stem` 없음) |
| 5 | 안 막는 것 | 이미 연 열기 잇기(`fill_open` · `reconcile`) · 복구 launch 가드(226줄 · `gates()` 본문 그대로) · settle · 착지 complete · 닫기 · 깨움 · 사람 손 `ft2 submit/assign/deliver` · 팀장 개설 · 승계 |
| 6 | 드러냄 | 막힘 = `NEXT-HOLD <팀> PENALTY_STOP 재개 전 — 다음 카드 0` 1줄. 판정 불가 = `판정 불가 <팀> PENALTY_STOP 판독 rc <값> — 다음 카드 0` 1줄. 풀림 = `NEXT-OPEN <팀> PENALTY_STOP 풀림` 1줄. 세 줄 모두 값이 바뀔 때만 찍는다 |
| 7 | 기억 | keeper 상태 파일 키 `state["penalty_seen"][<팀>]` = 마지막으로 찍은 값(`hold` · `unsure:<rc>` · 없음 = 열림). `fill_wait`(175~184줄)와 같은 방식이다. 메모리에만 두지 않는다 |
| 8 | 그대로 | `gates()` 본문 · `choose()` · `intake_open()` · `fill_hold` · ALL_STOP · 팀 PAUSED · 1.x `ft_penalty.py`(판정 규칙 · EXEMPT · resume) |

- 판정은 한 곳에서 한다. keeper 가 JSON 을 직접 읽지 않고 1.x 판정기를 부른다. 재개 규칙과 면제 팀 목록(harness · planner)이 `ft_penalty.py` 한 곳에만 있기 때문이다. 나노 열기 도구와 keeper 가 같은 답을 낸다.
- 파일이 없으면 판정기를 부르지 않는다. 평소 바퀴 비용은 `lexists` 1회다.
- `gates()` 본문에 넣지 않는 까닭: 226줄 복구 launch 가드가 `gates()` 를 같이 쓴다. 본문에 넣으면 이미 dispatch 한 열기의 복구까지 막힌다. 발주 범위는 «새 pick 두 곳만 · 이미 연 열기 · reconcile 은 그대로» 다. 새 카드 보류(ft2-new-card-hold)의 H8 도 `gates()` 본문 손 0 이다.
- 판정 불가를 막힘으로 두는 까닭: 1.x 도구도 파일이 있는데 판정기가 없으면 REJECT 다(조용한 통과 0 · 하드 룰 20).
- 순서: `gates()` 가 거짓이면 `penalty_open` 을 부르지 않는다(이미 닫힌 문에 줄을 더 찍지 않는다).

### 새 카드 보류(ft2-new-card-hold)와의 관계

두 카드는 같은 두 자리에 조건을 하나씩 붙인다. 뒤에 착지하는 카드가 앞 카드의 조건 뒤에 `and` 로 잇는다. 뜻은 다르다: 새 카드 보류는 전 팀 설정 파일 1개이고 이 카드는 팀별 재개 여부다. 합치지 않는다.

### 고르지 않은 길

| 길 | 버린 까닭 |
|---|---|
| `gates()` 본문에 판독을 넣음 | 복구 launch 가드까지 막힌다(위 · M65 가 가른다) |
| keeper 가 `PENALTY_STOP` JSON 을 직접 읽음 | 면제 팀 · 재개 규칙이 두 곳에 생긴다. 1.x 가 규칙을 바꾸면 어긋난다 |
| `choose()` 에서 카드마다 거름 | 팀 단위 조건이다. 카드 단위 함수에 넣으면 카드 수만큼 판정한다 |
| 열기 실패 카드(D+F)에 덧붙임 | 함수 · 계약 행이 다르다(5459 판단). D+F 는 `team_round` · `settle_nano` · `choose` 의 카드 단위 제외다 |

## 4. 시험 (나노 · 새 파일 `tests/test_penalty_team_no_new_pick.py` · 임시 루트 · 가짜 판정기 스크립트(rc 를 사례가 정함 · 호출 수 기록) · 가짜 tmux · 가짜 mbox · sleep 0 · 네트워크 0)

| # | 사례 | 기대 |
|---|---|---|
| ㊲가 | `PENALTY_STOP` 있음 · 판정기 rc 3 · 빈 나노 칸 · 대기 카드 1 · 두 바퀴 | fill submit 0 · journal 줄 수 그대로 · `NEXT-HOLD <팀> PENALTY_STOP 재개 전` 1줄 · 둘째 바퀴 0줄 |
| ㊲나 | 파일 있음 · 판정기 rc 0(재개된 팀) | fill 1장(지금 동작) · NEXT-HOLD 0줄 |
| ㊲다 | 파일 없음 | fill 1장 · 판정기 호출 0 |
| ㊲라 | 닫기 뒤 pick: 파일 있음 · rc 3 · 나노 닫기 1 | 닫기 영수 1 · 다음 카드 배정 0 · submit 0 |
| ㊲마 | 파일 있음 · rc 3 · `fill_open` 에 잇는 열기 1 | `reconcile` 그대로 진행(파일 없을 때와 같은 호출 · 결과) |
| ㊲바 | 파일 있음 · rc 3 · 복구 launch 가드 길(`reconcile` 의 pick 없음) | 파일 없을 때와 같은 결과 · 판정기 호출 0 |
| ㊲사 | 판정기 rc 1 · 도구 파일 없음 · 시간 초과(세 갈래) | 셋 다 fill 0 · `판정 불가 <팀> PENALTY_STOP 판독 rc …` 1줄 |
| ㊲아 | rc 3 → rc 0 으로 바뀜 → 다시 rc 3 | `NEXT-OPEN` 1줄 + fill 1장 → `NEXT-HOLD` 1줄 다시 |
| ㊲자 | rc 3 로 1줄 찍은 뒤 keeper 다시 만듦(상태 파일 그대로) | 0줄 |
| ㊲차 | 두 팀 한 바퀴: 한 팀 rc 0 · 한 팀 rc 3 | rc 0 팀만 fill 1장 · 판정기 호출 팀당 1회 |
| ㊲카 | `gates()` 가 거짓(팀 PAUSED) · 파일 있음 | 판정기 호출 0 · PENALTY 줄 0 |
| M62 | fill 자리의 `penalty_open` 을 뺌 | ㊲가 FAIL |
| M63 | 닫기 뒤 자리의 `penalty_open` 을 뺌 | ㊲라 FAIL |
| M64 | 판정 불가를 참으로 바꿈 | ㊲사 FAIL |
| M65 | 판독을 `gates()` 본문으로 옮김 | ㊲바 FAIL |
| M66 | `penalty_seen` 기억을 뺌(바퀴마다 찍음 · 또는 메모리에만 둠) | ㊲가 둘째 바퀴 FAIL · ㊲자 FAIL |

회귀: `test_keeper_fill_empty_slot_r1913.py` · `test_keeper_fill_intake_full_r1939.py` · `test_pi_keeper_next_card_r1871.py` · `test_settle_one_path_r2055.py`. 실행 = `python3.11 -m pytest`.

## 5. 닫는 증거

1. 고친 커밋(팩 main 착지 sha) + 설치 판.
2. 설치 뒤 BYZ keeper 로그에서 재개 전 팀의 `NEXT-HOLD <팀> PENALTY_STOP 재개 전` 줄 원문.
3. 그 시각 뒤 재개 전 팀 journal 의 새 `accept keeper-next-…` 줄 0(`PENALTY_STOP` 이 그때도 있고 그 팀이 재개 전일 때만 잰다. 그 사이 풀렸으면 «잴 대상 없음» 1줄).

## 6. DA 에게 묻는 것

- Q1. 막는 범위를 새 pick 두 곳으로만 두는 것. 이미 dispatch 한 열기의 복구 launch(226줄)는 재개 전 팀에서도 그대로 간다. 대안 = 복구 launch 도 막는다(1.x 도구는 재개 전 팀의 나노 열기를 모두 막는다).
- Q2. keeper 가 1.x 판정기(`ft-penalty.sh check`)를 부르는 것. 대안 = ft2 가 JSON 을 직접 읽는다(1.x 의존 0 · 규칙 두 곳).
- Q3. 판정 불가(도구 없음 · rc 1 · 시간 초과)를 막힘으로 두는 것. 판정기가 오래 깨져 있으면 그 팀 fill 이 멈춘다. 드러내는 줄은 값이 바뀔 때 1줄뿐이다(팀장 쪽지 0).

## 7. 다른 행과 겹침 · 운영 손

- `keeper_next.py` 를 만지는 카드: ft2-launch-failed-end(D+F · `choose` · `prereq`) · ft2-new-card-hold(C · 같은 두 pick 자리) · ft2-prereq-unreadable-once(I · `prereq` · `choose`). 이 카드는 D+F 뒤에 시작하고 C 와 앞뒤로 잇는다.
- 운영 줄(범위 밖): room 팀을 재개할지(`ft-penalty.sh resume room`)와 지금 돌고 있는 room 나노 a2 를 어떻게 할지는 room 팀장 · planner 판단이다. 이 카드는 손대지 않는다.
- 알려진 한계: 사람이 손으로 넣는 `ft2 submit/assign/deliver` 는 재개 전 팀에서도 통과한다. keeper 의 자동 pick 만 막는다.
