# 인덱스: ft2-penalty-team-no-new-pick — 끝: 전 세션 정지(PENALTY_STOP) 중에 재개 전인 팀에는 keeper 가 새 카드를 넣지 않는다 · 이미 연 열기·settle·닫기·사람 손 발주는 그대로다 · 판정은 1.x 나노 열기 도구와 같은 판정기 한 곳이 한다
<!-- ledger: feature-pack/fable-team/legacy/1.x/harness/design/harness/GOAL-harness.md -->
- Issue: #8650 — 등록 planner(팀장 aifp-ft-master-pi#19 aifp 5464 · 발주 5461 (나) · 범위 판단 5455 → 5459 · 결함 전달 planner 5446 = room#48 BYZ 310510)
- 제안서: 없음 — 결함 복구(새 흐름 0) · 설계 = .fable-team/state/team-main/aifp-ft/orders/DESIGN-pJ-penalty-team-no-new-pick-20261116.md(r1 sha256 c50fb568…d8b3 · DA 판정 전) · 착지 PR 에서 feature-pack/fable-team/design/ 로 옮긴다
- 근거: 실측 2026-11-16 02:27~02:30(aifp-ft-arch-pi#18 · BYZ 읽기만) — .fable-team/state/PENALTY_STOP 있음(order 에 room · resumed = feature·cfo·knowledge·ops·v65·chatbot · room 없음) · 1.x 판정기 «ft-penalty.sh check room» rc 3 «REJECT penalty 전 세션 정지 중 — 팀=room 은 아직 재개 전» · «check cfo» rc 0 · keeper 로그 state/ft2-keeper/20261116.jsonl 02:19:31 «LAUNCHING room byz-room-nano-R-room-runner-home-ws-origin-check#0 열기 …@a2.log» → 02:20:54 «WORKING … 착지 줄 없음» → 02:20:56 «NEXT room fill:R-room-runner-home-ws-origin-check» = fill 이 재개 전 팀에 새로 넣음
- 원인 1줄: 전 세션 정지는 1.x ft-nano-spawn.sh 에서만 막는데 ft2 keeper 는 그 도구를 거치지 않는다 · keeper_next.gates() 가 보는 것은 CLOSE-NEXT.enabled·팀 PAUSED·SPAWN_HOLD·ACCT_PAUSE·나노 상한뿐이고 PENALTY_STOP 판독이 없다
- 앞 카드: r1913(fill) · r1939(fill 꽉 참) · r1871(닫기 뒤 다음 카드) · r2055(팩 d88ef381 · settle 한 길) · 1.x R320b(전 세션 정지 · 오빠 판정 2170)
- 상태: 대기
- 설치: 있음 — ft2 판 올림 1회 · 되돌림 = 앞 판으로 판 전환(상태 파일의 새 키 1개는 옛 판이 읽지 않음)
- 선행: ft2-launch-failed-end 착지(keeper_next.py 를 같이 만짐 · 그 위에서 시작) · ft2-new-card-hold 와 앞뒤로 이어 붙임(같은 두 pick 자리 · 뒤에 착지하는 카드가 앞 조건에 and 로 잇는다) — 이 줄은 카드 이름 글이라 keeper 가 읽지 못한다(선행불명) · keeper 가 읽는 막힘은 아래 배정 줄 «대기(선행» 이다 · 앞 카드가 착지하면 팀장이 이 줄을 «- 선행: 없음» 으로, 배정 줄을 «- 배정: 없음» 으로 고친다
- 시험 입력: 임시 루트(tmp_path) · 시험 안에서 만든 journal·카드·PENALTY_STOP 파일 · 가짜 판정기 스크립트(rc 를 사례가 정함 · 호출 수 기록) · 가짜 tmux·가짜 mbox · sleep 0 · 네트워크 0 · 실 runtime 쓰기·읽기 0 · 사례 1개 70초 안
- 기준값: 기준판 = PENALTY_STOP 재개 전 팀에도 fill submit 1 → 목표 = submit 0 · journal 줄 수 그대로 · NEXT-HOLD 1줄(값이 바뀔 때만)
- 규칙: 없음 — 상시 로드 변경 0
- 규칙 상세: 하드 룰 20(판정기 실패 = 판정 불가 1줄 · 조용한 통과 0) · 하드 룰 22 · 하드 룰 12(판정기 호출 7초)
- 대상: 팩 feature-pack/fable-team/ft2/adapters/pi/keeper_next.py(새 함수 penalty_open · fill pick 앞 · 닫기 뒤 pick 앞) · 새 시험 feature-pack/fable-team/ft2/tests/test_penalty_team_no_new_pick.py · 문서 ft2/contracts/keeper-settle/CONTRACT.md·CASES.md
- 정본 영향 있음: CONTRACT.md 에 «전 세션 정지 재개 전 팀» 절 1개(판정기 자리·막는 것·안 막는 것·줄 꼴·상태 키) · CASES.md ㊲·변이 행 = 같은 PR(나노)
- 크기: 코드 1파일 · 새 시험 1파일 · 문서 2파일 · PR 1개
- 배정: 대기(선행 · 2026-11-16T02:31)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」. 골의 축: 6(하네스 운영 정리 — 전 세션 정지가 keeper 의 자동 카드 넣기에도 똑같이 걸린다). 이 카드의 증거 = 착지 sha + 시험 rc0 + 설치 뒤 keeper 로그의 재개 전 팀 NEXT-HOLD PENALTY_STOP 줄 + 그 시각 뒤 그 팀 journal 의 새 accept keeper-next 줄 0.

## 배경 (한 단락)
전 세션 정지(PENALTY_STOP)는 한 세션이라도 멈추면 전 팀의 새 나노를 막고 팀을 하나씩 재개하는 장치다. 1.x 에서는 나노 열기 도구가 판정기(ft-penalty.sh check)를 불러 재개 전 팀을 막는다. ft2 keeper 는 그 도구를 거치지 않고 스스로 카드를 넣는다. keeper 의 팀 문에는 이 판독이 없다. 그래서 room 팀은 재개 전인데도 02:19 에 fill 이 나노를 새로 열었다. keeper 의 새 카드 고르기 두 곳에 같은 판정기를 붙인다. 이미 연 열기와 닫기, 사람 손 발주는 건드리지 않는다.

## 계약
- P1 새 함수 `penalty_open(k, team)` — 참 = 새 카드를 넣어도 됨 · `<루트>/.fable-team/state/PENALTY_STOP` 이 없으면 참이고 판정기 호출 0 · 있으면 판정기 `ft-penalty.sh check <팀>`(FT_ROOT = k.root)의 rc 로 정한다: rc 0 = 참 · rc 3 = 거짓 · 그 밖(rc 1·2 · 도구 없음 · 시간 초과) = 거짓 + 판정 불가
- P2 판정기 자리 = env `FT2_PENALTY_BIN` → 없으면 `dirname(k.close_bin)/ft-penalty.sh`(SPAWN_HOLD·ACCT_PAUSE 판정기와 같은 폴더 규칙) · 호출은 바퀴 캐시 once 로 팀당 바퀴 1회 · keeper 는 PENALTY_STOP JSON 을 직접 풀지 않는다(재개 규칙·면제 팀은 1.x ft_penalty.py 한 곳)
- P3 막는 곳 = `fill()` 의 새 pick · `close()` 의 닫기 뒤 다음 카드 pick 두 곳뿐 · 꼴 = `gates(k, team) and penalty_open(k, team)` · gates 가 거짓이면 판정기를 부르지 않는다
- P4 닫기 뒤 길 = 닫기 영수(close_receipt)는 지금처럼 쓰고 다음 카드만 «다음 없음» 길
- P5 안 막는 것 = 이미 연 열기 잇기(fill_open · reconcile) · 복구 launch 직전 가드(gates 본문 그대로) · settle · 착지 complete · 닫기 · 깨움 · 사람 손 ft2 submit/assign/deliver · 팀장 개설·승계
- P6 드러냄(값이 바뀔 때만 1줄) = `NEXT-HOLD <팀> PENALTY_STOP 재개 전 — 다음 카드 0` · `판정 불가 <팀> PENALTY_STOP 판독 rc <값> — 다음 카드 0` · 풀리면 `NEXT-OPEN <팀> PENALTY_STOP 풀림`
- P7 기억 = keeper 상태 파일 키 state["penalty_seen"][<팀>](마지막으로 찍은 값 · 열림이면 키 없음) · 메모리에만 두어 재기동 때 같은 줄을 다시 찍으면 불합격
- P8 그대로: gates() 본문 · choose() · intake_open() · fill_hold · ALL_STOP · 팀별 PAUSED · 1.x ft_penalty.py(판정 규칙·EXEMPT·resume)

## 구현 범위 (나노 1 · 팩 base origin/main 최신 · ft2-launch-failed-end 착지 뒤)
1. 커밋 1 [test] — 새 시험 feature-pack/fable-team/ft2/tests/test_penalty_team_no_new_pick.py(㊲가~카 11칸 · M62~M66) · 기준판 FAIL 원문(㊲가·㊲라·㊲사)을 PR 본문에 붙인다
2. 커밋 2 [fix] — P1~P7 = feature-pack/fable-team/ft2/adapters/pi/keeper_next.py(함수 1 · fill pick 앞 · 닫기 뒤 pick 앞) · gates() 본문 손 0 · 다른 파일 손 0
3. 커밋 3 [docs] — CONTRACT.md 절 · CASES.md ㊲·변이 행 · 설계 1쪽을 feature-pack/fable-team/design/ 로
4. 회귀 rc0: test_keeper_fill_empty_slot_r1913.py · test_keeper_fill_intake_full_r1939.py · test_pi_keeper_next_card_r1871.py · test_settle_one_path_r2055.py
5. ft2-new-card-hold 가 먼저 착지했으면 그 조건 뒤에 and 로 잇고 두 카드의 시험을 함께 돌린다(test_new_card_hold.py rc0)
6. 실행 = `python3.11 -m pytest` · 착지 = PR 1개(팀장 집행)

## 범위 밖
- room 팀을 재개할지(ft-penalty.sh resume room) · 지금 도는 room 나노 a2 를 어떻게 할지(room 팀장·planner 판단)
- 복구 launch(이미 dispatch 한 열기)까지 막는 일 — 설계 Q1 로 DA 에 묻는다 · 판정이 «막는다» 면 이 카드의 계약 P5 를 고친다
- 사람 손 ft2 submit/assign/deliver 를 재개 전 팀에서 막는 일(알려진 한계 · keeper 의 자동 pick 만 막는다)
- 1.x ft_penalty.py 의 재개 규칙·면제 팀 목록 고침
- 판정 불가가 오래 이어질 때 팀장에게 쪽지를 보내는 일(지금은 로그 1줄 · 설계 Q3)

## 완료 조건
1. [ ] 나노: 커밋 1 기준판 FAIL 원문
2. [ ] 나노: 새 시험 전체 rc0 · 걸린 초
3. [ ] 나노: 변이 M62 → ㊲가 FAIL · M63 → ㊲라 FAIL · M64 → ㊲사 FAIL · M65 → ㊲바 FAIL · M66 → ㊲가 둘째 바퀴·㊲자 FAIL
4. [ ] 나노: 회귀 rc0
5. [ ] 팀장: PR 착지 sha · 설치 판
6. [ ] arch: 설치 뒤 읽기 실측 = BYZ keeper 로그의 재개 전 팀 NEXT-HOLD PENALTY_STOP 줄 원문 + 그 시각 뒤 그 팀 journal 새 accept keeper-next 줄 0(그 사이 정지가 풀렸으면 «잴 대상 없음» 1줄)

## 계약↔시험 대응표
| 계약 | 시험 |
|---|---|
| P1·P3 fill 을 막는다 | ㊲가 파일 있음 · 판정기 rc 3 · 빈 나노 칸 · 대기 카드 1 · 두 바퀴 → fill submit 0 · journal 줄 수 그대로 · NEXT-HOLD 1줄 · 둘째 바퀴 0줄 / M62 |
| P1 재개된 팀·파일 없음 = 열림 | ㊲나 파일 있음 · rc 0 → fill 1장 · NEXT-HOLD 0줄 / ㊲다 파일 없음 → fill 1장 · 판정기 호출 0 |
| P3·P4 닫기 뒤 pick 을 막는다 | ㊲라 파일 있음 · rc 3 · 나노 닫기 1 → 닫기 영수 1 · 다음 카드 배정 0 · submit 0 / M63 |
| P5 이어 열기·복구 가드는 그대로 | ㊲마 rc 3 · fill_open 에 잇는 열기 1 → reconcile 그대로 / ㊲바 rc 3 · 복구 launch 가드 길 → 파일 없을 때와 같은 결과 · 판정기 호출 0 / M65 |
| P1 판정 불가 = 막힘 | ㊲사 판정기 rc 1 · 도구 파일 없음 · 시간 초과 → 셋 다 fill 0 · 판정 불가 1줄 / M64 |
| P6·P7 값이 바뀔 때만 · 재기동 | ㊲아 rc 3 → rc 0 → rc 3 = NEXT-OPEN 1줄 + fill 1장 → NEXT-HOLD 1줄 다시 / ㊲자 1줄 찍은 뒤 keeper 다시 만듦(상태 파일 그대로) → 0줄 / M66 |
| P2 팀당 바퀴 1회 | ㊲차 두 팀 한 바퀴(rc 0 · rc 3) → rc 0 팀만 fill 1장 · 판정기 호출 팀당 1회 |
| P3 gates 가 먼저 | ㊲카 팀 PAUSED · 파일 있음 → 판정기 호출 0 · PENALTY 줄 0 |

## 상태
- 2026-11-16 · aifp-ft-arch-pi#18 씀(aifp 5461 (나) · 5464) · 대기 · 설계 r1 = DA 판정 전 · 선행 = ft2-launch-failed-end 착지 · Issue #8650
