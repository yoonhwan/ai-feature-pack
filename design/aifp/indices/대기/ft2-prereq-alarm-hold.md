# 인덱스: ft2-prereq-alarm-hold — 끝: 전팀 정지 · 팀 PAUSED · NEW_CARD_HOLD 중에는 [다음 막힘] 선행 줄 쪽지가 0통이다 · 풀린 첫 바퀴에 팀마다 1통이 가고 그 글에 전체 목록(3장을 넘으면 목록 파일 경로 1줄)이 있다 · 팀장이 없는 팀은 harness [긴급] 으로 넘기지 않고 팀장이 설 때까지 보류한다
<!-- ledger: feature-pack/fable-team/legacy/1.x/harness/design/harness/GOAL-harness.md -->
- Issue: 없음(초안) — 넘김 byz-harness-master-pi#292 aifp 5744(planner 결정 BYZ 311721 · arch#385 판단 BYZ 311752) · 팀장 aifp-ft-master-pi#21 발주 aifp 5746 · 후보 본문 BYZ .fable-team/state/team-main/harness/a385/card-candidate-prereq-alarm-hold.md
- 제안서: 없음 — 앞 카드가 만든 쪽지 1곳에 보낼 조건을 더하는 결함 복구 · 설계 = 이 카드 «계약»·«반례 표»
- 근거: 실측 2026-11-16 05:39(aifp-ft-arch-pi#21 · BYZ .fable-team/state/ft2-keeper/launchd.log · 20261115.jsonl · 20261116.jsonl · state.json · 읽기만) — 아래 «기준값» 절
- 원인 1줄: keeper_next.prereq_tell 은 보낼지를 묶음 지문(I8)만으로 정한다 · 정지·보류는 choose 를 부르는 쪽(fill · 닫기 뒤 고르기)의 앞 조건에만 걸려 있어 쪽지 자리에서는 보이지 않는다 · 본문에는 앞 3장만 실린다 · 팀장이 없으면 notify 가 대신 받는 곳 묶음(harness [긴급])에 넣는다
- 앞 카드: 진행/ft2-prereq-unreadable-once(I1~I9 · 착지 b70abbf6 · 설치 ft2 2.0.69 · 조건 7 [~]) · 진행/ft2-new-card-hold(H1~H8 · 착지 eb4c9ea0) · 완성/ft2-keeper-notify-recipient(E1~E8 받는 곳·묶음) · 완성/ft2-penalty-team-no-new-pick
- 앞 카드와의 관계: ft2-prereq-unreadable-once 가 만든 쪽지 1곳(prereq_tell)에 «보내지 않는 조건 2개» 와 «본문 칸 1개» 를 더한다 · 앞 카드의 조건 7(설치 뒤 줄 수 실측)은 이 카드와 따로 닫는다 · 같은 파일을 고치므로 나노 base 는 앞 카드 착지(b70abbf6) 뒤 main 이다
- 상태: 대기
- 설치: 있음 — ft2 판 올림 1회 · 되돌림 = 앞 판으로 판 전환(상태 파일 새 키 1개는 옛 판이 읽지 않음 · 목록 파일은 남아도 읽는 곳 0)
- 선행: 없음
- 시험 입력: 임시 루트(tmp_path) · 시험 안에서 만든 카드 루트·카드·keeper 상태 파일·명부 · 가짜 mbox(rc 를 사례가 정함) · 가짜 clock · sleep 0 · 네트워크 0 · 실 runtime 읽기·쓰기 0 · 사례 1개 70초 안
- 기준값: 2.0.69 설치(05:13:27) 뒤 [다음 막힘] 선행 줄 쪽지 6통(팀마다 1통) 중 1통이 팀장 없는 chatbot 몫으로 harness master [긴급] 묶음에 실림 · harness 18장 쪽지에 이름 3개만 실림 → 목표 = 정지·보류 중 0통 · 팀장 없는 팀 [긴급] 0통 · 3장 넘는 묶음은 전체 목록 경로 1줄
- 규칙: 없음 — 상시 로드 변경 0
- 규칙 상세: 하드 룰 19(우리 도구가 만드는 파일은 일반 파일) · 하드 룰 20 · 하드 룰 22
- 대상: 팩 feature-pack/fable-team/ft2/adapters/pi/keeper_next.py(prereq_tell 1곳) · 새 시험 feature-pack/fable-team/ft2/tests/test_prereq_alarm_hold.py · 문서 ft2/contracts/keeper-settle/CONTRACT.md · CASES.md
- 정본 영향 없음: aifp 정본(docs/architect · docs/rules · design 팀 GUIDE·README) 변경 0 — 바뀌는 것은 팩 ft2 계약 문서(CONTRACT.md «선행불명 로그·쪽지» 절에 줄 더함 · CASES.md 행)뿐이고 같은 PR(나노)에 넣는다
- 크기: 코드 1파일 · 새 시험 1파일 · 문서 2파일 · PR 1개
- 배정: 대기(DA · 2026-11-16T05:39)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
6 — 하네스 운영 정리. 하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」. 골의 축: 6(멈춰 둔 팀과 팀장이 없는 팀에 고치라는 쪽지가 가지 않고, 풀리면 한 번에 전체 목록이 간다). 이 카드의 증거 = 착지 sha + 시험 rc0 + 설치 뒤 keeper 로그의 PREREQ-WAIT 줄·[다음 막힘] 본문 원문 + harness master 우편함의 [긴급] 묶음에 선행 줄 글 0.

## 배경 (한 단락)
앞 카드(2.0.69)는 못 읽는 «- 선행:» 줄을 팀장에게 [다음 막힘] 1통으로 알린다. 설치 직후 여섯 팀에 1통씩 나갔다. 그중 chatbot 은 팀장이 없어서 harness master 에게 [긴급] 묶음으로 갔다. harness 는 18장인데 쪽지에는 이름 3개만 실렸다. planner 는 네 팀을 «지금 손대지 않는다» 고 정했는데, keeper 는 그 결정을 볼 길이 없었다. 그 시각 BYZ 에는 ALL_STOP · PAUSED · NEW_CARD_HOLD.json 이 하나도 없었다. 그래서 이 카드는 세 가지를 한다. 정지·보류 표식이 있으면 쪽지를 보내지 않는다. 풀리면 전체 목록을 한 번에 준다. 팀장이 없는 팀 몫은 harness 로 넘기지 않는다.

## 기준값 (실측 원문 · 2026-11-16 05:39)
| 재는 것 | 값 |
|---|---|
| launchd.log «선행 줄 판독 불가» 전체 | 1319줄 |
| 그중 2.0.69 앞 꼴(«— 건너뜀» 으로 끝 · 까닭 없음) | 1281줄 = cfo 1162(카드 4장) · harness 119(카드 3장) |
| 그중 2.0.69 꼴(까닭 + «고칠 꼴») | 38줄 = harness 18 · v65 7 · cfo 4 · chatbot 4 · knowledge 4 · ops 1 = 카드 38장에 1줄씩 |
| 시각으로 가른 값(jsonl) | 11-15 = cfo 864 · harness 49 / 11-16 설치 05:13:27 앞 = cfo 298 · harness 70 / 설치 뒤 = 38줄(05:13~05:18:36) · 그 뒤 0줄 |
| cfo 1166줄 / 8장 | 설치 앞 1162줄(4장 · 바퀴마다 되풀이) + 설치 뒤 4줄(4장 · 1줄씩) = 되풀이는 모두 설치 앞이다 · 앞 좌석 5737 의 «설치 뒤 38줄» 과 같다 |
| 설치 뒤 [다음 막힘] 선행 줄 쪽지 | 6통(05:14:06 cfo · 05:14:14 knowledge · 05:14:19 ops · 05:16:06 v65 · 05:16:08 chatbot = harness master [긴급] 묶음 · 05:18:43 harness 18장 · 이름 3개) |
| 그 시각의 정지·보류 표식 | state/ALL_STOP 없음 · state/<팀>-tick/PAUSED 0개 · state/NEW_CARD_HOLD.json 없음 · state.json new_card_hold_seen = {} |
| PENALTY_STOP | 있음 · 재개 전 6팀(ccu · graphics · issues · kk · lecture · room)에는 판독 불가 줄 0 · 쪽지 0 / 쪽지를 받은 6팀은 재개된 팀과 harness 다 |

읽은 뜻: 설치 뒤 줄 수는 앞 카드 계약대로다(카드당 1줄 · 팀당 1통). 쪽지를 받은 팀은 keeper 가 볼 수 있는 표식으로는 모두 열린 팀이었다. 팀 PAUSED · NEW_CARD_HOLD · PENALTY 재개 전인 팀은 지금도 choose 를 부르지 않아 쪽지가 0통이다(keeper_next.py 260 · 302~304줄). 지금 코드에서 실제로 새는 곳은 세 곳이다: 전팀 정지 중 닫기 뒤 고르기 길(keeper_close.py 141줄 → keeper_next.close 가 halt 를 보지 않는다) · 본문 이름 3개 · 팀장 없는 팀의 [긴급] 묶음.

## 계약
- P1 묵음 = 전팀 정지(k.halt) · 팀 PAUSED(state/<팀>-tick/PAUSED) · NEW_CARD_HOLD(깨짐 포함 = 보류로 본다) 중 하나라도 참이면 그 바퀴 그 팀의 [다음 막힘] 선행 줄 쪽지는 0통이다 · 판정 자리 = prereq_tell 안 1곳(부르는 쪽 앞 조건에 기대지 않는다) · prereq_told 는 바꾸지 않는다 · prereq_now(지문·전이 번호)는 지금처럼 바퀴마다 고친다
- P2 풀림 = 셋 다 거짓인 첫 바퀴에 지금 묶음이 비어 있지 않고 prereq_told 와 다르면 1통(I8 그대로) · 보류 중 묶음이 X → Y 로 바뀌었으면 Y 만 1통 · 보류 중 묶음이 비었으면 0통
- P3 본문 = 카드 3장까지는 지금 글 그대로 · 3장을 넘으면 `[다음 막힘] <팀> 선행 줄을 못 읽는 카드 <n>장: <앞 3장 이름> · 전체 목록 <경로> · 고칠 꼴 «- 선행: 없음» 또는 «- 선행: r<번호>»`
- P4 목록 파일 = <root>/.fable-team/state/ft2-keeper/prereq-<팀>.txt · 줄마다 `<카드>\t<선행 값>\t<까닭>`(이름순) · 묶음 지문이 바뀔 때 원자 쓰기(보류 중에도 쓴다) · 묶음이 비면 지운다 · 3장 이하도 쓴다(쪽지에는 경로를 싣지 않을 뿐) · 일반 파일
- P5 팀장 없음 = 그 팀 명부의 _master 칸이 비어 받는 곳이 대신 받는 곳(_desk · harness master)이거나 없으면 선행 줄 쪽지는 보류한다 · notify 를 부르지 않는다(묶음 [긴급] 에 쌓이지 않는다) · prereq_told 그대로 · `PREREQ-WAIT <팀> 팀장 없음 — 선행 줄 쪽지 보류 <n>장 · 목록 <경로>` 1줄(묶음 지문이 바뀔 때만 · 기억 = state["prereq_wait"][<팀>] = 지문) · 팀장 칸이 채워진 바퀴에 P2 로 1통 + 기억 지움
- P6 판정 순서 = 묶음 빔(I7) → P1 묵음 → P5 팀장 없음 → I8 보냄 · P1 중에는 PREREQ-WAIT 줄도 0
- P7 그대로: I1~I4(판정 불가 로그는 값·까닭이 바뀔 때만 · 기억 치우기) · I6·I7·I9(지문 · 전이 번호 · 상태 파일 기억) · I8 의 열쇠와 성공 때만 told · I10 · H1~H8(새 카드 보류는 고르기 두 곳만 막는다 · NEW-CARD-HOLD 줄) · E1~E8(다른 쪽지의 받는 곳·묶음) · [다음 없음] 쪽지 · 고르기 순서 · 막는 판정
- P8 I5 는 바뀐다 = 3장을 넘을 때 본문에 «전체 목록 <경로>» 칸이 붙는다(앞 카드 시험 ㉟아의 기대 = 수 5 · 이름 3개는 그대로 통과해야 한다)

## 반례 표 (가짜 mbox · 가짜 clock)
| # | 입력 | 기대 | 지금 |
|---|---|---|---|
| ㊵가 | NEW_CARD_HOLD.json 있음 · 선행불명 2장 · 두 바퀴 | 쪽지 0통 · prereq_told 없음 · NEW-CARD-HOLD 줄은 지금처럼 | 같음(choose 를 안 부름) = 회귀 고정 |
| ㊵나 | 팀 PAUSED 있음 · 선행불명 2장 | 쪽지 0통 | 같음 = 회귀 고정 |
| ㊵다 | ALL_STOP 중 · 닫기 뒤 고르기 길로 choose 가 불림(세션 없음) · 선행불명 2장 | 쪽지 0통 · prereq_told 없음 | 나노가 기준판에서 잰다(1통이면 Red) |
| ㊵라 | prereq_tell 을 직접 부름 · 세 표식을 하나씩 켬(3칸) | 칸마다 쪽지 0통 · prereq_now 는 고쳐짐 | 3칸 모두 1통 |
| ㊵마 | ㊵가 뒤 파일을 지움 | 그 바퀴 1통 · 다음 바퀴 0통 | 1통 |
| ㊵바 | 보류 중 묶음 X → Y | 보류 중 0통 · 풀리면 Y 1통(X 글 0통) | — |
| ㊵사 | 보류 중 카드를 모두 고침(묶음 빔) | 풀려도 0통 · 목록 파일 없음 | — |
| ㊵아 | 열림 · 선행불명 5장 | 1통 · 수 5 · 이름 3개 · 전체 목록 경로 1개 · 파일 5줄(이름순 · 값 · 까닭) | 경로 0 · 파일 0 |
| ㊵자 | 열림 · 선행불명 3장 | 지금 글 그대로(경로 칸 0) · 파일 3줄 | 파일 0 |
| ㊵차 | _master 빈칸 · harness master 있음 · 선행불명 4장 · 두 바퀴 | 쪽지 0통 · state undelivered 에 그 글 0 · PREREQ-WAIT 1줄(둘째 바퀴 0줄) · prereq_told 없음 | harness [긴급] 묶음에 실림 |
| ㊵카 | ㊵차 뒤 _master 칸을 채움 | 그 바퀴 팀장에게 1통 · prereq_wait 지움 · 다음 바퀴 0통 | — |
| ㊵타 | ㊵차 뒤 카드 1장 더(묶음 바뀜) | PREREQ-WAIT 1줄 다시(5장) · 쪽지 0통 | — |
| ㊵파 | _master 빈칸 · _desk 있음 | ㊵차와 같음(대신 받는 곳 = 보류) | desk 묶음 |
| ㊵하 | NEW_CARD_HOLD 깨짐(빈 파일) · 선행불명 2장 · prereq_tell 직접 | 쪽지 0통 | 1통 |
| ㊵거 | 보류 중 keeper 를 다시 만듦(상태 파일 그대로) → 풀림 | 1통(재기동이 0통이나 2통을 만들지 않는다) | — |
| ㊵너 | 팀장 없음 + NEW_CARD_HOLD | 쪽지 0통 · PREREQ-WAIT 0줄(P6) | — |
| ㊵더 | 세 표식 0 · 팀장 있음 | 앞 카드 시험 파일 전부 rc0(㉟가~거) | — |

범위 밖 입력(하드 룰 18·19·20): 줄바꿈·탭 든 카드 이름 · 권한을 바꾼 목록 파일·표식 파일 · 주입한 mbox 실패의 꼴 맞추기.

## 구현 범위 (나노 1 · 팩 base origin/main 최신 · DA 설계 승인 뒤)
1. 커밋 1 [test] — 새 시험 feature-pack/fable-team/ft2/tests/test_prereq_alarm_hold.py(㊵가~더 · 변이 M85~M90) · 기준판 FAIL 원문(㊵라 · ㊵아 · ㊵차 · ㊵하)을 PR 본문에 붙인다 · ㊵다는 기준판 결과(통과든 실패든)를 원문으로 적는다
2. 커밋 2 [fix] — P1~P6 = feature-pack/fable-team/ft2/adapters/pi/keeper_next.py 의 prereq_tell 1곳(묵음 판정 · 팀장 판독 = k.recipients · 목록 파일 · 본문 칸) · choose·fill·close·new_card_hold·gates 손 0 · 다른 파일 손 0
3. 커밋 3 [docs] — CONTRACT.md «선행불명 로그·쪽지» 절에 P1~P6 · 상태 키 prereq_wait · 목록 파일 꼴 · CASES.md ㊵·변이 행
4. 회귀 rc0(파일별 · 각 70초 상한): test_prereq_unreadable_once · test_new_card_hold · test_penalty_team_no_new_pick · test_keeper_next_prereq_line_r2027 · test_keeper_notify_recipient · test_pi_keeper_next_card_r1871
5. 실행 = `python3.11 -m pytest` · 착지 = PR 1개(팀장 집행)

변이: M85 전팀 정지 조건 빼기 → ㊵다·㊵라 / M86 보류 중에 prereq_told 를 씀 → ㊵마·㊵바 / M87 경로 칸 빼기 → ㊵아 / M88 팀장 없음에도 notify → ㊵차·㊵파 / M89 PREREQ-WAIT 를 바퀴마다 → ㊵차 / M90 묶음이 비어도 목록 파일을 안 지움 → ㊵사

## 범위 밖
- planner 가 말로 정한 «손 0» 을 keeper 가 아는 것 — keeper 는 표식 파일만 본다 · 멈추려면 NEW_CARD_HOLD.json 이나 PAUSED 를 둔다(운영 절차 · planner master)
- 전팀 정지 중 닫기 뒤 고르기 길이 submit 까지 가는지 — ㊵다에서 submit 이 보이면 팀장에게 1줄로 알리고 새 카드로 낸다(이 카드는 쪽지만 막는다)
- harness 카드 18장 · 다른 팀 카드의 «- 선행:» 줄 고치기(그 팀 팀장 · harness docs PR)
- PENALTY 재개 전 팀 · 나노 정원 꽉 참 팀(지금도 choose 를 부르지 않아 0통 · 손 0)
- [다음 없음] 쪽지와 다른 keeper 쪽지의 팀장 없음 묶음(E2 그대로)

## 완료 조건
1. [ ] 나노: 커밋 1 기준판 FAIL 원문(㊵라 · ㊵아 · ㊵차 · ㊵하 + ㊵다 결과)
2. [ ] 나노: 새 시험 전체 rc0 · 걸린 초
3. [ ] 나노: 변이별 지정 반례 FAIL(M85~M90 전부)
4. [ ] 나노: 회귀 rc0(파일별 초)
5. [ ] 팀장: PR 착지 sha · 설치 판
6. [ ] arch: 설치 뒤 읽기 실측 = BYZ keeper 로그에서 팀장 없는 팀의 PREREQ-WAIT 줄 원문(값이 그대로면 1줄뿐) · 설치 뒤 harness master 가 받은 [긴급] 묶음에 «선행 줄을 못 읽는» 글 0 · state/ft2-keeper/prereq-<팀>.txt 줄 수 = state.json prereq_seen 의 그 팀 칸 수
7. [ ] arch: 실사건 = NEW_CARD_HOLD.json 또는 PAUSED 가 놓인 동안 그 팀 [다음 막힘] 선행 줄 쪽지 0통 · 풀린 뒤 1통(본문 원문) · 사건이 없으면 [~] 로 둔다

## 계약↔시험 대응표
| 계약 | 시험 |
|---|---|
| P1 묵음 | ㊵가 · ㊵나 · ㊵다 · ㊵라 · ㊵하 · M85 |
| P2 풀림 | ㊵마 · ㊵바 · ㊵사 · ㊵거 · M86 |
| P3 본문 | ㊵아 · ㊵자 · M87 |
| P4 목록 파일 | ㊵아 · ㊵자 · ㊵사 · M90 |
| P5 팀장 없음 | ㊵차 · ㊵카 · ㊵타 · ㊵파 · M88 · M89 |
| P6 순서 | ㊵너 |
| P7 그대로 · P8 | ㊵더 · ㊵자 |

## 상태
- base_sha: 18428688fd1cf98c875d8d955b42ec97da871f03
- 2026-11-16 05:39 · 대기 — aifp-ft-arch-pi#21 초안(팀장 aifp 5746 · 넘김 harness#292 aifp 5744 · 실측 = BYZ launchd.log 1319줄 · jsonl 2일 · state.json · 구현 0) · 다음 = 팀장 PR → DA 설계 → Issue → 나노 1석
