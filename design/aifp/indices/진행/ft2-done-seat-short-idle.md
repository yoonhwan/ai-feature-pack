# 인덱스: ft2-done-seat-short-idle — 끝: 착지한 좌석은 유휴 5분 뒤 keeper 가 닫는다(60분을 기다리지 않는다) · 끝난 좌석 앞에 정해진 마감 쪽지 한 줄만 남았으면 쉼·닫기를 막지 않는다 · 그 밖의 미읽음은 지금처럼 모두 막는다
<!-- ledger: feature-pack/fable-team/legacy/1.x/harness/design/harness/GOAL-harness.md -->
- Issue: #8644 — 등록 planner#324 aifp 5411(팀장 aifp-ft-master-pi#18 발주 aifp 5410 ② · 5397 · 5385 · 5361 · 5326 행 A · 5314 덤 사실 · planner 5360 실사건 r2057)
- 제안서: 없음 — 결함 복구(새 흐름 0) · 설계 = .fable-team/state/team-main/aifp-ft/orders/DESIGN-pA-done-idle-threshold-20261116.md(r4 sha256 700e2174…353f · DA 대행 byz-harness-da-codex#11 APPROVE-DESIGN BYZ 310212 · 전문 .fable-team/state/team-main/aifp-ft/DA-pA-r4-approve-310212.md · 앞 판 r2·r3 REJECT = 자유 글 낱말 조건 반례 → 닫힌 꼴 한 줄로 닫힘) · 착지 PR 에서 feature-pack/fable-team/design/ 로 옮긴다
- 근거: 실측 2026-11-16(aifp-ft-arch-pi#16 · 읽기만) — keeper_settle.py 15줄 PARK_IDLE = 3600 하나뿐 · 착지한 좌석 닫기(land_ready)도 같은 look() 을 써서 jsonl 무활동 60분을 채워야 함 · harness 나노 칸 8/8 중 끝난 나노 5석이 60분 유휴 전까지 칸을 쥠(팀장 5314) · result 줄은 끝남 근거가 아님(5팀 work 187 중 63 이 result 2줄 이상) · r2057 = 마감 답장 미읽음 1통(BYZ 장부 seq 309395 · 00:03:48) 때문에 UNKNOWN mail-pending 이 75분 넘게 안 풀림(BYZ 309902)
- 원인 1줄: 유휴 문턱이 PARK_IDLE 3600 하나라 착지한 좌석도 60분을 기다린다 · keeper_settle.unsafe 는 미읽음이 1통이라도 있으면 뜻을 보지 않고 막는다 · 끝난 나노는 그 쪽지를 읽으려고 다시 깨지 않는다
- 앞 카드: r2055(팩 d88ef381 · settle 한 길) · r1841(착지 없는 닫기) · r1865(판정 닫기) · r1153(peek = recv 와 같은 대상 규칙) · r1116(계보)
- 상태: 대기
- 설치: 있음 — ft2 판 올림 1회 + 1.x comm 도구(mbox peek --rows) 설치 1회(팩 착지 뒤 팀장·harness 설치 묶음) · 되돌림 = 앞 판으로 판 전환(옛 mbox 면 keeper 는 지금처럼 1통이라도 막는다)
- 선행: 없음 — E ft2-keeper-notify-recipient 착지 ae0c199e(PR #1282) + D+F ft2-launch-failed-end 착지 8ed707c4(PR #1294) 착지 끝 · 팀장 aifp-ft-master-pi#19 이 풂
- 시험 입력: 임시 루트(tmp_path) · 가짜 tmux · 가짜 ps · 임시 pi 세션 jsonl · 가짜 clock · 가짜 mbox peek(머리줄 + --rows 줄을 사례가 정함) · 시험 안에서 만든 명부 · sleep 0 · 네트워크 0 · 실 runtime·실 우편함 쓰기·읽기 0 · 사례 1개 70초 안
- 기준값: 기준판 = 착지 좌석 닫기까지 무활동 60분 · 미읽음 1통이면 영영 mail-pending → 목표 = 착지 좌석은 무활동 300초 + stop + CPU idle 이면 닫힘 · 미읽음이 닫힌 꼴 마감 쪽지뿐이면 쉼·닫기
- 규칙: 없음 — 상시 로드 변경 0(팀장이 [마감] 꼴로 답하는 통신 지침 1줄은 이 카드 밖 · harness 몫)
- 규칙 상세: 하드 룰 2(닫기는 keeper 기존 가드 그대로) · 하드 룰 20 · 하드 룰 22 · 모르는 미읽음 = 막음(조용한 제외 0 · 제외는 꼬리 근거 줄)
- 대상: 팩 feature-pack/fable-team/ft2/adapters/pi/keeper_settle.py(look 문턱 인자 · unsafe 미읽음 판독) · feature-pack/fable-team/ft2/adapters/pi/keeper_close.py(land_ready·닫기 길에 DONE_IDLE) · feature-pack/fable-team/legacy/1.x/harness/comm/mbox_ops.py(peek --rows 출력) · 새 시험 feature-pack/fable-team/ft2/tests/test_done_seat_short_idle.py · 문서 ft2/contracts/keeper-settle/CONTRACT.md·CASES.md
- 정본 영향 있음: CONTRACT.md §2 상수 줄 DONE_IDLE 300초 · 약속 «착지한 좌석만 짧은 문턱» · «빼는 미읽음 = 닫힌 꼴 마감 쪽지» 절 · CASES.md ㉙·변이 행 = 같은 PR(나노)
- 크기: 코드 3파일 · 새 시험 1파일 · 문서 2파일 · PR 1개
- 배정: 좌석 aifp-ft-nano-ft2-done-seat-short-idle#0

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」. 골의 축: 6(하네스 운영 정리 — 끝난 좌석이 칸을 쥔 채 남지 않고 정한 순서로 닫힌다). 이 카드의 증거 = 착지 sha + 시험 rc0 + 설치 뒤 «카드 착지 → 닫힘 10분 안» 로그 1줄 + 팀장이 [마감] 꼴로 답한 좌석의 «미읽음 마감 n통 제외» 로그 1줄.

## 배경 (한 단락)
keeper 는 좌석이 유휴인지 볼 때 문턱 하나(60분)를 쓴다. 카드가 이미 착지한 좌석을 닫을 때도 같은 문턱이라, 끝난 나노가 60분 동안 팀의 나노 칸을 쥔다. 또 keeper 는 좌석 앞에 안 읽은 쪽지가 1통이라도 있으면 쉼과 닫기를 막는다. 팀장이 «할 일 0 · 마감하고 대기» 라고 답한 쪽지도 막는다. 끝난 나노는 그 답을 읽으려고 다시 깨지 않으므로 영영 풀리지 않는다. 자유 글에서 낱말로 마감을 가리는 길은 DA 가 두 번 반례를 냈다. 그래서 보낸 이가 정해진 한 줄로 마감을 밝힌 쪽지만 뺀다.

## 계약
- A1 착지 판독이 참인 좌석의 닫기 문턱 = DONE_IDLE 300초 · 조건 = 마지막 pi 턴 stopReason stop ∧ CPU idle 2회 ∧ 막는 미읽음 0 ∧ uncertain·effect 표식 0 · 셸만 남은 pane 도 300초
- A2 구현 자리 = look() 에 문턱 인자 1개(idle_s · 기본 PARK_IDLE) · land_ready 와 keeper_close 의 착지 닫기 길만 DONE_IDLE 을 넘긴다 · park 길(settle_alive)은 PARK_IDLE 3600 그대로
- A3 착지 0 좌석은 지금과 같다(60분) · result 줄은 끝남 근거로 쓰지 않는다
- A4 미읽음 읽기 = 지금 keeper 가 부르는 mbox.sh peek <좌석> 의 대상 집합 그대로 · peek 에 --rows 출력 1개(머리줄 pending=N … + 미읽음마다 JSON 1줄 seq·ts·to·from·body · 집합 = mbox_ops.peek 가 pending 을 세는 그 목록 · 계보·옛 우편함 선택 새로 만들기 0 · mark 0 · recv 0)
- A5 줄 수 ≠ pending · JSON 깨짐 · rc ≠ 0 = mail-unknown · 설치된 mbox 가 --rows 를 모르면 지금처럼 1통이라도 mail-pending
- A6 빼는 미읽음 = 세 조건 모두: ① 닫힌 꼴(골좌표: 로 시작하는 줄과 빈 줄을 뺀 나머지가 정확히 1줄 · 그 줄 전체가 `[마감 #<숫자>] 할 일 0` 또는 `[마감] 할 일 0` · 꼬리는 ` · 착지 <7~40자 hex>` 하나만) ② 보낸 이가 그 좌석 팀 명부 역할 칸(_master·_arch·_desk)에 지금 적힌 좌석(명부 = ft2-keeper-notify-recipient E8 함수 · 못 읽으면 막음) ③ 쪽지 ts 가 그 좌석 유휴 문턱(착지 300초 · 그 밖 3600초)보다 오래됨
- A7 미읽음이 여러 통이면 전부 A6 일 때만 쉼·닫기 · 한 통이라도 아니면 UNKNOWN mail-pending
- A8 근거 줄 = 쉼·닫기 판정 줄 꼬리에 `· 미읽음 마감 <n>통 제외(seq <앞 3개> · 가장 오래된 <분>분)` · 쪽지는 큐에 그대로 둔다
- A9 그대로: 닫기 직전 가드 · clean·push 검사 · mail-unknown 길 · PARK_IDLE 값 · core park·capacity

## 구현 범위 (나노 1 · 팩 base origin/main 최신 · 선행 두 카드 착지 뒤)
1. 커밋 1 [test] — 새 시험 feature-pack/fable-team/ft2/tests/test_done_seat_short_idle.py(㉙가~노 · M20·M21·M22·M44·M45·M51~M55) · 기준판 FAIL 원문(㉙가·㉙아·㉙마·㉙너)을 PR 본문에 붙인다
2. 커밋 2 [fix] — A1~A3 = feature-pack/fable-team/ft2/adapters/pi/keeper_settle.py(look) · feature-pack/fable-team/ft2/adapters/pi/keeper_close.py(land_ready·착지 닫기 길) · A5~A8 = feature-pack/fable-team/ft2/adapters/pi/keeper_settle.py(unsafe) · 다른 함수 손 0
3. 커밋 3 [fix] — A4 = feature-pack/fable-team/legacy/1.x/harness/comm/mbox_ops.py(peek 에 --rows · 머리줄 꼴 그대로 · --rows 없으면 출력 바이트 같음) + 그 폴더의 peek 시험에 사례 1개(줄 수 = pending · 계보 옛 이름 앞 쪽지 포함)
4. 커밋 4 [docs] — CONTRACT.md·CASES.md · 설계 1쪽을 feature-pack/fable-team/design/ 로
5. 회귀 rc0: test_settle_one_path_r2055.py(⑥·⑲⑳ 포함) · test_pi_keeper_noland_close_r1841.py · test_pi_keeper_verdict_close_r1865.py · 1.x mbox peek·lineage 시험
6. 실행 = `python3.11 -m pytest` · 착지 = PR 1개(팀장 집행)

## 범위 밖
- 팀장이 끝난 나노에게 `[마감 #<받은 seq>] 할 일 0` 한 줄로 답하게 하는 통신 지침 1줄(지침 주인 harness 몫 · 이 운영 변경이 있어야 A6 이 쓰인다)
- 알려진 한계(DA BYZ 310212): r2057 의 자유 글 답장(BYZ 장부 seq 309395)은 이 카드 뒤에도 막는다 · 옛 사건의 자동 해소를 주장하지 않는다 · 그런 좌석은 사람 판정이다
- 보낸 이 대조는 우편함 from 칸을 믿는 범위 안이다(발신 인증 추가 0)
- 착지 없이 끝난 좌석을 빨리 닫는 길 · 결과 뒤 세션 0·owner 0 인 일의 칸 풀기 · harness 의 끝난 나노를 지금 손으로 닫는 일

## 완료 조건
1. [x] 나노: 커밋 1 기준판 FAIL 원문 — 커밋 624e37b7 본문(㉙가·㉙아 COMPLETED 줄 0 · ㉙마 UNKNOWN mail-pending · ㉙너 CLOSED-SESSION 0 · ㉙서 mail-pending)
2. [x] 나노: 새 시험 전체 rc0 — 36 passed(사례 26 = 55초 · 변이 10 = 57초)
3. [x] 나노: 변이 M20 → ㉙가·㉙아 FAIL · M21 → ㉙나 FAIL · M22 → ㉙바 FAIL · M44 → ㉙버 FAIL · M45 → ㉙서 FAIL · M51 → ㉙머·㉙허 FAIL · M52 → ㉙러·㉙카 FAIL · M53 → ㉙고 FAIL · M54 → ㉙타·㉙더 FAIL · M55 → ㉙마·㉙너 FAIL (test_mutant 10개 = 잡힘 + 원본 PASS)
4. [x] 나노: 회귀 rc0 — rebase 뒤 test_pi_keeper_r1812(31) + test_settle_one_path_r2055(29) + 1.x test_mbox_peek_self_sent_r1153(4) = 64 passed
5. [ ] arch: DA 인수 칸 원문 확인 = ㉙허·㉙고·㉙노 · 새 일과 섞인 미읽음(㉙파·㉙카) · 옛 계보(㉙버) · M51~M55
6. [ ] 팀장: PR 착지 sha · 설치 판(ft2 + mbox)
7. [ ] arch: 설치 뒤 실사건 로그 2줄(착지 → 닫힘 10분 안 · `미읽음 마감 n통 제외`) + 하루 로그에서 일하는 좌석을 닫은 사건 0

## 계약↔시험 대응표
| 계약 | 시험 |
|---|---|
| A1·A2 착지 좌석 300초 | ㉙가 착지 참 · stop · 무활동 6분 · CPU idle 2회 · 쪽지 0 → complete 1 · 닫기 1 / ㉙나 마지막 줄 toolUse → WORKING landed-wait / ㉙다 무활동 4분 → WORKING / ㉙라 CPU busy → 닫기 0 / ㉙아 셸만 남은 pane 6분 → 닫기 1 / M20 · M21 |
| A3 착지 0 은 60분 | ㉙바 착지 0 · 무활동 6분 → WORKING / ㉙사 61분 → PARKED idle-done / M22 |
| A6·A8 닫힌 꼴 마감만 뺌 | ㉙마 미읽음 `[마감 #N] 할 일 0`(75분 · 보낸 이 _master) → PARKED · 꼬리 미읽음 마감 1통 제외 · 큐 그대로 / ㉙너 착지 참 · `[마감] 할 일 0 · 착지 4ccf2a6` + 골좌표 줄(7분) → 닫기 1 / M55 |
| A6 ① 줄 전체·한 줄 | ㉙허 `[마감 #N] 할 일 0이 아닙니다` → mail-pending / ㉙머 DA 입력 2개(`[답 #N] 수정안 승인합니다. …다시 보고하세요.` · `[답 #N] 할 일 0이 아닙니다. …수정해 주세요.`) → mail-pending / ㉙러 4줄(첫 줄 닫힌 꼴 · 4번째 줄 `[긴급][발주]`) → mail-pending / ㉙카 2줄(닫힌 꼴 + `[발주]`) → mail-pending / ㉙노 r2057 실사건 원문 → mail-pending / ㉙어 · ㉙저 자유 글 답장 → mail-pending / M51 · M52 |
| A6 ② 보낸 이 | ㉙고 보낸 이가 다른 나노 · 명부 못 읽음 → mail-pending / M53 |
| A6 ③ 나이 | ㉙타 10분 전 도착(착지 0) → mail-pending / ㉙더 착지 참 · 2분 전 → 닫기 0 / M54 |
| A7 섞인 미읽음 | ㉙파 `[마감 …]` + `[발주 …]` → mail-pending / ㉙자 `[긴급]` · ㉙차 `[발주]` · ㉙하 머리 없는 글 → mail-pending |
| A4·A5 peek 대상 집합 | ㉙버 현역 seat#1 · 큐 to = seat#0 `[발주]` 1통 → pending 1 = 판독 1통 · mail-pending / ㉙서 줄 수 ≠ pending → mail-unknown · 옛 mbox → mail-pending / ㉙거 큐 못 읽음 → mail-unknown / M44 · M45 |

## 상태
- base_sha: cd0bd9ee1361cf25c215dbbb31fed2890e66df8f (spawn 2026-11-16)
- 2026-11-16 · aifp-ft-arch-pi#17 씀(aifp 5410 ② · 5412) · 대기 · 설계 r4 = DA 대행 APPROVE-DESIGN(BYZ 310212 · 카드당 3번째 판정) · 선행 = ft2-keeper-notify-recipient · ft2-launch-failed-end 착지
- 2026-11-16 03:44 — 대기→진행 · 좌석 aifp-ft-nano-ft2-done-seat-short-idle#0
- [배정 불명] 불명(scope 표 없음 opengateway/deepseek/deepseek-v4.1-flash-ultrafast)
- 세트: 5dd17b1d3839dcf11146ee7156b7db52bd068f22 · 시험: python3.11 -m pytest fable-team/ft2/tests/test_done_seat_short_idle.py rc=0 · 이슈: 0
- 완료: aifp-ft-nano-ft2-done-seat-short-idle#0 · 한 일: A1~A9 구현 — 착지 좌석 DONE_IDLE 300초(land_ready·착지 닫기 길) + 안 닫힌 턴 = WORKING landed-wait + unsafe 의 mail_gate(닫힌 꼴·보낸 이·나이 3조건) + 1.x peek --rows + 계약·사례·설계 문서 · 산출: nano/ft2-done-seat-short-idle@5dd17b1d38 · 병합 상태: 착지 전(push 전) · 남은 일: 없음
- 세트: 4bb2c9d5dda0ecafb5144f29c177e00d908aab93 · 시험: python3.11 -m pytest feature-pack/fable-team/ft2/tests/test_done_seat_short_idle.py (36 passed) rc=0 · 이슈: 0
- 완료: aifp-ft-nano-ft2-done-seat-short-idle#0 · 한 일: A1~A9 구현 + master 반송 반영(rebase 1회 · CASES.md §9 로 번호 이동 · 루트 카드 손 0 · 카드 [x] 1~4 를 가지 커밋 4bb2c9d5 로) · 산출: nano/ft2-done-seat-short-idle@4bb2c9d5dd · 병합 상태: 착지 전(push 전) · 남은 일: 없음
- 세트: 0c8f2373eee4dace85d01b702b4534a682dcc37d · 시험: python3.11 -m pytest feature-pack/fable-team/ft2/tests/test_done_seat_short_idle.py (27 passed 53초) rc=0 · 이슈: 0
- 완료: aifp-ft-nano-ft2-done-seat-short-idle#0 · 한 일: DA HOLD-IMPL 반례 311515 R1 보정 — look() waiting-input 분기를 park 길로 한정(착지 좌석 열린 턴은 15분 뒤에도 WORKING landed-wait) · 시험 ㉙도 추가 · 새 시험 파일 셋으로 쪼갬(파일마다 70초 안) · 산출: nano/ft2-done-seat-short-idle@0c8f2373ee · 병합 상태: 착지 전(push 전) · 남은 일: 없음
- 2026-11-16 · 나노 aifp-ft-nano-ft2-done-seat-short-idle#0 — 커밋1 624e37b7 [test] · 커밋2 e059048b [fix] keeper · 커밋3 18a11218 [fix] 1.x peek --rows · 커밋4 e3e91f00 [docs] · 커밋5 4bb2c9d5 카드 · 커밋6 bdc80ee2 [fix] DA 반례 311515 R1(질문 창 판정은 park 길만)
- 세트: 2ec71d7f5fec24cb21368ad043c70bdd74843762 · 시험: python3.11 -m pytest feature-pack/fable-team/ft2/tests/test_done_seat_short_idle.py (27 passed 53초) + ..._mutants.py (5 passed 37초) + ..._mutants_b.py (5 passed 33초) rc=0 · 이슈: 0
- 회귀(rebase·보정 뒤 · 파일별 70초): test_settle_one_path_r2055(29 passed 42초) · test_pi_keeper_r1812(31 = 25초+35초) · test_pi_keeper_noland_close_r1841(15 passed 19초) · test_pi_keeper_verdict_close_r1865(24 = 23초+21초) · test_pi_keeper_empty_r1972(18 = 20초+20초) · 1.x test_mbox_peek_self_sent_r1153(4 passed) = 전부 rc=0 · lint rc=0
- 변이: M20 ㉙가·㉙아 · M21 ㉙나 · M22 ㉙바 · M44 ㉙버 · M45 ㉙서 · M51 ㉙머·㉙허 · M52 ㉙러·㉙카 · M53 ㉙고 · M54 ㉙타·㉙더 · M55 ㉙마·㉙너 — 전부 잡힘(파일 둘로 쪼개 37초·33초)
- DA 반례 311515 R1 = ㉙도 로 고정(착지 참 · toolUse · 16분 · 미읽음 0 → WORKING landed-wait) · 고침 = look() waiting-input 분기에 idle_s == PARK_IDLE 조건 하나 · 기준판 Red 원문은 커밋 bdc80ee2 본문
- 곁들여 고친 대역: keeper_world_r1812 의 mbox 가 peek --rows 에만 pending=0 을 답한다 · test_settle_one_path_r2055 변이 앵커 2개(M3·M5)를 새 조건에 맞춤(변이 뜻 그대로)
- 남은 것: PR 1개 = 팀장 집행 · 설치 1회(ft2 판 + 1.x mbox peek --rows) = 팀장 · press 필요 없음(단위·대역 시험만 · 라이브 오디오 시험 0)
