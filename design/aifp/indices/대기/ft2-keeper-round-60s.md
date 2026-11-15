# 인덱스: ft2-keeper-round-60s — 끝: ft2 keeper 한 바퀴가 벽시계 60초 안에 끝난다 · 예산이 다하면 그 자리(팀·work·칸)에서 끊고 다음 바퀴가 거기서 잇는다 · ROUND 줄이 벽시계 초·재지 못한 초·끊긴 자리를 보인다
<!-- ledger: feature-pack/fable-team/legacy/1.x/harness/design/harness/GOAL-harness.md -->
- Issue: 없음(초안) — 요청 planner#327 aifp 5702 · 팀장 aifp-ft-master-pi#21 발주 aifp 5704 · 문제 원문 «keeper 한 바퀴 78초 / 상한 60초 ★크리티컬★ → 느린 단계 쪼개기»(BYZ design/planner/PROBLEMS-desk175-20261116.md 40줄 · 근거 BYZ #309391 · #309397 = 발주 인용 · 이 좌석은 그 파일을 로컬에서 못 찾아 원문 대조 안 함)
- 제안서: 없음 — 기존 상한(바퀴 60초)을 지키게 하는 결함 복구 · 설계 = 이 카드 «계약»·«설계 확정»·«반례 표»(DA HOLD-DESIGN 1/3 BYZ 311663 반영 r2)
- 근거: 실측 2026-11-16 05:05(aifp-ft-arch-pi#20 · BYZ .fable-team/state/ft2-keeper/20261116.jsonl 읽기만 · 설치 ft2 2.0.65~2.0.68 구간) — 아래 «기준값» 절
- 원인 1줄: 바퀴 상한 검사는 팀 고리 머리 1곳뿐이다(adapters/pi/keeper.py `_round` 의 `if time.monotonic() - start > ROUND_S`) · 한 팀의 한 칸이 혼자 60초를 넘어도 끊지 못하고 · 팀 고리 앞(fetch · 나노 가지 모으기)과 뒤(b3 · report)는 상한 밖이다
- 앞 카드: r1817(단계별 초) · r1898(cap_next = 컷에 걸린 팀부터) · r1969(slow 칸) · r1992(SLOW-CALL · SLOW-CELL) · r1963·r1975(fetch) · 완성/ft2-keeper-notify-recipient(쪽지 받는 곳·바퀴 3통)
- 상태: 대기
- 설치: 있음 — ft2 판 올림 1회 · 되돌림 = 앞 판으로 판 전환(상태 파일 새 키는 옛 판이 읽지 않음)
- 선행: 없음(팩 origin/main a065424f)
- 시험 입력: 임시 루트(tmp_path) · 시험 안에서 만든 journal·카드 · 가짜 tmux·가짜 mbox·가짜 git(걸린 초를 가짜 시계로 더함) · 주입 시계(self.now · monotonic 주입점) · sleep 0 · 네트워크 0 · 실 runtime 읽기·쓰기 0 · 사례 1개 70초 안
- 기준값: 오늘 00:00:54~05:04:32 ROUND 210줄 = 60초 넘음 14줄 · 가장 긴 바퀴 152.5초 · p50 15.8초 · p90 52.5초 → 목표 = 60초 넘음 0줄
- 규칙: 없음 — 상시 로드 변경 0
- 규칙 상세: 하드 룰 12(외부 호출 7초 · 런타임 7초 절대) · 하드 룰 20(외부 명령 실패 = 판정 불가 1줄) · 하드 룰 22
- 대상: 팩 feature-pack/fable-team/ft2/adapters/pi/keeper.py(예산 시계 · 호출 문 · cursor · 바퀴 · ROUND 줄 · git 상한) · feature-pack/fable-team/ft2/adapters/pi/keeper_report.py(쪽지 미룸 · report 구획) · 새 시험 feature-pack/fable-team/ft2/tests/test_keeper_round_60s.py · 문서 ft2/contracts/keeper-settle/CONTRACT.md · CASES.md
- 정본 영향 없음: aifp 정본(docs/architect · docs/rules · design 팀 GUIDE·README) 변경 0 — 바뀌는 것은 팩 ft2 계약 문서(contracts/keeper-settle/CONTRACT.md «바퀴 예산» 절 1개 · CASES.md 행)뿐이고 같은 PR(나노)에 넣는다
- 크기: 코드 2파일 · 새 시험 1파일 · 문서 2파일 · PR 1개 · 끊김 수렴 시험(㊳파)에서 원자 구간이 21초를 넘는 순서가 나오면 그 순서는 새 카드로 쪼갠다(코드 4파일을 넘기지 않는다)
- 배정: 대기(DA · 2026-11-16T05:06)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
6 — 하네스 운영 정리. 하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」. 골의 축: 6(끝난 좌석 닫기·다음 카드·깨움을 맡은 keeper 가 정한 주기 안에 돈다). 이 카드의 증거 = 착지 sha + 시험 rc0 + 설치 뒤 keeper 로그 ROUND 줄 60초 넘음 0(단계별 초 원문).

## 배경 (한 단락)
keeper 는 launchd 가 60초마다 띄운다(plist StartInterval 60). 한 바퀴 상한도 60초다. 그런데 오늘 5시간 동안 210바퀴 중 14바퀴가 60초를 넘었고 가장 긴 것은 152.5초였다. 바퀴가 길어지면 뒤쪽 팀의 닫기·깨움·다음 카드가 늦는다. 상한 검사는 팀 고리 머리 1곳뿐이라, 넘은 14바퀴 중 12바퀴는 ROUND-CAP 줄을 찍고도 60초를 넘겼다(나머지 2바퀴 = 00:58 은 팀 고리를 돌지 않았고 · 01:14 는 컷 줄 없이 한 칸이 92.6초였다). 느린 까닭은 한 가지가 아니다. 그래서 «예산 시계 1개» 를 먼저 세우고, 느린 항목을 그 시계 아래에 둔다.

## 기준값 (실측 원문 · 2026-11-16 00:00:54~05:04:32 · ROUND 210줄)
단계별 초(ROUND 줄의 칸):

| 칸 | 뜻 | p50 | p90 | 가장 긴 값 |
|---|---|---|---|---|
| s | 칸 합계 + nano | 15.8 | 52.5 | 152.5 |
| fetch | 두 리포 ls-remote·fetch | 3.4 | 6.1 | 19.7 |
| nano | 나노 가지 모으기(팀 고리 앞) | 0.9 | 9.6 | 30.4 |
| b1 | 착지 판정·complete | 6.2 | 11.0 | 30.3 |
| b2c | 닫기(+ 닫기 뒤 다음 카드·열기) | 0.3 | 4.7 | 92.6 |
| b2f | 빈 칸 채우기(fill·열기) | 1.1 | 9.4 | 57.7 |
| stall | settle·깨움·HOLD | 0.8 | 5.1 | 44.7 |
| b3 | 고아·옛 좌석(팀 고리 뒤) | 0.2 | 1.4 | 25.0 |

60초 넘은 14바퀴에서 본 까닭(원문 줄):

| # | 까닭 | 원문 |
|---|---|---|
| 가 | 쪽지 send 가 7초에 끊기고 같은 자리에서 한 번 더 7초 | 01:08:37 `ROUND s=112.8 … stall=44.7 … slow=chatbot:stall:43.7 OVER` · `SLOW-CELL chatbot stall s=43.7 n=9 slow_call=41.3` · 그 칸 `SLOW-CALL chatbot stall bash mbox.sh send` 6줄(5.2~8.1초 · rc=None 4) |
| 나 | 한 팀 한 칸이 혼자 60초를 넘음 · 5초 넘는 호출은 일부뿐 | 01:14:25 `ROUND s=152.5 … b2c=92.6 … slow=harness:b2c:92.6 OVER` · `SLOW-CELL harness b2c s=92.6 n=16 slow_call=16.1`(같은 바퀴에 COMPLETED · CLOSED-SESSION · NEXT · LAUNCHING) |
| 다 | 짧은 호출이 많이 쌓임 | 04:12:04 `ROUND s=94.5 … b2f=57.7 … slow=harness:b2f:56.4 OVER` · `SLOW-CELL harness b2f s=56.4 n=148 slow_call=0`(같은 바퀴에 LAUNCHING) · 04:23:30 `SLOW-CELL harness b2c s=23.2 n=151 slow_call=0` |
| 라 | 로컬 git 이 7초를 넘음(상한 25초) | 03:22:59 `ROUND s=112.5 … b1=30.3 b2c=37.7 … OVER` · `SLOW-CALL harness b2c git BYZ-Agents merge-base s=25 rc=None` · `… merge-base s=11.5 rc=128` · 03:45:02 `SLOW-CALL harness b2c git . grep s=19.3 rc=0` · 03:21:37 `SLOW-CALL ccu b2f git . ls-tree s=10.9 rc=0` |
| 마 | 팀 고리 앞·뒤가 상한 밖 | 00:58:27 `ROUND s=65.7 fetch=14.9 b1=0 b2c=0 b2f=0 b3=25 stall=0 … nano=25.8 slow=- OVER`(팀 고리 0 · ROUND-CAP 줄 없음) · 02:38:05 `ROUND s=67 … nano=30.4 … OVER` |

5초 넘은 바깥 호출(SLOW-CALL 71줄)의 합: `stall bash mbox.sh send` 17줄 114.0초(rc=None 11) · `b2f bash mbox.sh send` 13줄 87.8초(rc=None 11) · `b2c git merge-base` 3줄 61.5초(가장 긴 값 25) · `b1 gh pr list` 7줄 45.9초(가장 긴 값 7.2) · `fetch git fetch`(BYZ) 6줄 40.7초 · `fetch git ls-remote`(BYZ) 6줄 35.7초 · `b2c git grep` 2줄 35.4초 · `b2f git ls-tree` 3줄 28.8초 · `b1 git merge-base` 3줄 25.9초.

그 밖: ROUND-CAP 15줄(60초 넘은 바퀴 12 + 칸 합계로는 60초 안인 바퀴 3) · 60초 넘은 14바퀴 중 7바퀴에 NEXT 또는 LAUNCHING 줄이 있다(00:03 · 01:10 · 01:14 · 02:38 · 03:45 · 04:07 · 04:12) · ROUND 의 `s` 는 칸 합계라 report 와 칸 사이 초는 들어 있지 않다(벽시계 초는 지금 로그로 알 수 없음).

## 계약 (r2 · DA 311663 반례 반영)
- R1 예산 시계 1개 = 바퀴 시작부터의 벽시계 초 · 구획 3개: 업무 0~45초(fetch · 나노 가지 모으기 · 팀 항목 · b3) · report 45~55초 · 마무리 55~60초(state.json 원자 쓰기 · ROUND 줄 · 관측 기록 = 바깥 호출 0)
- R2 호출 문 1곳(`Keeper.call`) — 바깥 호출을 시작하기 전마다 남은 몫(= 지금 구획 끝 − 벽시계)을 본다
  - 판독 호출(git 읽기 · tmux 읽기 · gh · ls-remote): 상한 = min(자기 상한, 남은 몫) · 남은 몫 1초 미만 = 시작 0 · 끊김 · 남은 몫으로 줄인 상한에 걸려 끝난 것도 끊김(느린 것이 아니라 예산이 다한 것 = `판정 불가` 로 적지 않는다)
  - 쓰기 호출(지금 `call` 머리의 정지 그물이 가르는 것 = kill-session · send-keys · python 실행 · 닫기 도구 + mbox send): 원자 단위 = 호출 1개 · 최대 몫 7초 · 남은 몫 7초 미만 = 시작 0 · 끊김 · 시작한 쓰기는 자기 상한 7초 그대로(줄이지 않는다) · 재시도 0 그대로
  - 프로세스 안 동사(cli.run 의 submit·assign·deliver·park·complete·project)는 문을 지나지 않는다(바깥 대기 0) · 걸린 초는 ROUND `other=` 에 보인다
- R3 끊김 = 그 바퀴 업무 구획의 끝 · 뒤 항목 시작 0 → report 구획 → 마무리 · 끊김은 예외 1종으로 올린다(`except Exception` 에 먹히지 않는 종류) · 올라가는 길에 상태 쓰기 0
- R4 cursor = state.json 의 `cursor` 1칸 `{team, work, stage, cuts}` · stage = b1 · b2c · stall · b2f(팀의 fill) · b3o(고아) · b3r(옛 좌석) · 순서 = 팀(이름순) → work(이름순) → 칸(지금 순서) → 팀 고리 뒤 b3o → b3r 의 고정 순환 · 다음 바퀴는 cursor 자리부터 돈다 · 끊김 없이 한 바퀴를 다 돌면 cursor 를 지운다 · 지금의 `cap_next` 는 cursor 로 바뀐다(옛 키는 읽어서 팀 자리로 옮긴다)
- R5 굶김 0 = 같은 자리가 연속 2바퀴 끊기면 `판정 불가 <팀> <work> <칸> 예산 2회 넘음 — 건너뜀` 1줄 + cursor 를 다음 자리로 · git 7초 실패(R7)는 끊김이 아니다 = 판정 불가 1줄 + 그 자리의 남은 판정 0 + 다음 자리로 간다
- R6 앞 단계 몫 = fetch 는 지금 규칙 그대로(ls-remote 7초 + fetch 7초 + 재시도 1 = 최대 21초 · 두 리포 동시) · 나노 가지 모으기 = 합 7초(판독 호출을 R2 로 줄임) · 넘으면 `판정 불가 나노 가지 모으기 7초 넘음 — 모은 것만` 1줄 + 모은 것으로 진행 · 모으는 순서도 cursor 팀부터
- R7 로컬 git 상한 25 → 7초(merge-base · grep · ls-tree · rev-parse · 하드 룰 12) · 자기 상한에 걸리면 `판정 불가 <팀> <work> git 7초 넘음` 1줄 · 성공으로도 실패로도 읽지 않는다 · 상태 쓰기 0
- R8 쪽지 = 한 바퀴에서 send 시간 초과(rc None) 2회면 그 바퀴 남은 쪽지는 보내지 않는다 · 미룬 쪽지 = 지문·횟수 미소비 + NOTIFY-DEFER 줄 · 그 전에 간 쪽지의 지문·횟수는 그대로 · report 구획(45~55초)의 쓰기도 R2 를 지난다
- R9 끊김 수렴 = 어느 호출 앞에서 끊겨도 뒤 바퀴들이 «끊기지 않은 실행» 과 같은 끝에 닿는다(journal 의 work 별 끝 줄 종류 같음 · 쪽지 중복 0 · 닫힌 세션 같음) · 수렴하지 않는 순서가 시험에서 나오면 그 순서만 «원자 구간» 으로 선언한다(쓰기 호출 n개 · 몫 n×7 ≤ 21초 · 첫 쓰기 전에 몫을 예약 · 구간 표를 CONTRACT 에 적는다) · 21초를 넘으면 이 카드에서 고치지 않고 쪼갠다
- R10 드러냄 = ROUND 줄 끝에 `wall=<초> other=<wall − 칸 합계> items=<돈 자리>/<전체 자리> cut=<팀:work:칸 또는 ->` · `OVER` 는 wall 로 판정 · 끊김 1줄 = `ROUND-CAP <팀> <work> <칸> — 다음 바퀴 여기부터` · 옛 칸·순서 그대로
- R11 그대로: 판정 규칙(착지·끝·settle) · 쪽지 글·받는 곳 · fetch 규칙(r1963·r1975) · gates() · ALL_STOP · PENALTY_STOP · NEW_CARD_HOLD · 잠금 · SLOW-CALL·SLOW-CELL 줄 꼴 · 열기(아래 «설계 확정» 2)

벽시계 60초가 나오는 셈: 판독은 구획 끝에서 끊긴다. 쓰기는 구획 끝 7초 전까지만 시작하고 7초 안에 끝난다. 그래서 업무는 45초, report 는 55초를 넘지 않는다. 마무리는 바깥 호출이 없다. 남는 구멍은 호출 사이의 파이썬 초와 프로세스 안 동사뿐이고, 그 초는 `other=` 로 재서 완료 조건 6 에서 본다.

DA 반례(fill 1항목 안 7초 호출 10개 = 70초)에 댄 답: 그 10개는 호출마다 문을 지난다. 판독이면 45초에 끊기고, 쓰기면 38초 뒤로는 시작하지 않는다. fill 은 끊긴 자리(cursor)에서 다음 바퀴가 잇는다.

## 설계 확정 (DA 311663 권고 4개에 댄 답 · 오빠 결정이 필요한 선택 0)
1. 몫의 숫자 = 업무 45 · report 10 · 마무리 5초 · 원자 단위 = 쓰기 호출 1개 7초(DA 권고 «원자 항목 최대 7초») · 앞 판의 «최소 몫» 은 버린다(시작 전에 보는 것은 호출 1개의 최대 몫이다) · 이 숫자는 실측값이 아니라 상한에서 거꾸로 센 값이다. 업무 45초로 줄면 끊기는 바퀴가 는다(오늘 칸 합계 p90 = 52.5초). 그 값은 완료 조건 6 의 `items=`·`cut=` 로 본다.
2. 열기는 지금도 기다리지 않는다(정정) = keeper_launch.py 의 spawn 은 Popen(start_new_session) 으로 던지고, 다음 바퀴가 LAUNCH-WAIT·fill_open 이어 열기로 잇는다 · 이 카드는 열기에 손대지 않는다 · 기준값 «나»·«다» 의 긴 칸은 열기 앞뒤의 동기 일(카드 고르기 · project · submit · assign · deliver)과 닫기 판독이다 · 그 일은 R2 의 호출 문과 `other=` 로 갈라 본다
3. 정확성은 호출 문과 cursor 가 맡는다 · 바퀴 캐시를 더 늘리지 않는다(명부·판정 결과의 낡은 캐시 0) · 짧은 호출 148회는 줄이지 않고 끊는다
4. git 7초 실패 = 판정 불가 + 다음 자리(R5·R7) · 느린 팀이 앞자리를 계속 차지하지 않는다 · 상한을 늘리거나 성공으로 치지 않는다 · 오늘 7초 넘은 로컬 git = 11줄(210바퀴) = 판정 불가가 그만큼 는다

## 반례 표 (r2 · DA 보완 반영 · 가짜 시계)
| # | 입력 | 기대 | 지금 |
|---|---|---|---|
| ㊳가 | 팀 3 · 첫 팀 work 1 의 b2c 판독 호출이 50초 | 45초에 끊김 · `ROUND-CAP <팀> <work> b2c` 1줄 · cursor = 그 자리 · 뒤 자리 시작 0 · wall ≤ 60 | 첫 팀을 끝까지 돌고 둘째 팀 머리에서 컷 |
| ㊳나 | 한 팀 work 5개 · 각 b1 판독 14초 | 넷째 work 에서 끊김 · cursor = (팀, 넷째 work, b1) · 다음 바퀴는 넷째부터(앞 셋 재판독 0) | 5개 모두(70초) |
| ㊳다 | fetch 14초 + 나노 모으기 30초짜리 | 나노 모으기는 7초에 멈춤 · `판정 불가 나노 가지 모으기 7초 넘음` 1줄 · 모은 가지로 fetch · 팀 고리 시작 | 44초 쓰고 시작 |
| ㊳라 | 팀 고리가 44초에 끝남 · b3 고아 판독 25초짜리 | b3o 는 45초에 끊김 · cursor = b3o · 다음 바퀴가 b3o 부터 · report 구획은 돈다 | b3 를 돌아 69초 |
| ㊳마 | send 가 rc None 2회 · 그 앞에 성공 1통 · 뒤에 4통 | 뒤 4통 send 0 · NOTIFY-DEFER · 4통 지문·횟수 미소비 · 성공 1통 지문 그대로 · 다음 바퀴에 4통 나감 | 통마다 7초 |
| ㊳바 | merge-base 8초 · 남은 몫 30초 | 7초에 끊김 · `판정 불가 … git 7초 넘음` 1줄 · complete·닫기·state 쓰기 0 · 다음 자리로 진행(끊김 아님) · 남은 몫 3초였다면 3초에 끊김 = ROUND-CAP(판정 불가 줄 0) | 25초까지 기다림 |
| ㊳사 | 자리 N개 · 매 바퀴 예산이 자리 1개 몫뿐 | cursor 가 순환한다 · 2N 바퀴 안에 모든 자리가 1회 이상 판정된다(«모든 팀 3바퀴» 는 버림 = 팀 수·자리 비용이 정해지지 않으면 못 지킨다) | 팀 단위만 기억 |
| ㊳아 | 쓰기 호출(kill-session) 직전 남은 몫 6초 | 시작 0 · 끊김 · 세션 살아 있음 · 영수 0 · 다음 바퀴 그 자리에서 닫음 / 남은 몫 8초면 시작해 끝낸다(영수 1) | — |
| ㊳자 | 모두 빠름(합 10초) | 줄·순서·동작 지금과 같음 + ROUND 끝에 `wall= other= items=N/N cut=-` · cursor 없음 | — |
| ㊳차 | 호출 사이 파이썬 20초(가짜 시계) | 다음 호출 문에서 그 20초가 남은 몫에 반영됨 · ROUND `other=20` · wall ≤ 60 | s 에 안 보임 |
| ㊳카 | ALL_STOP · PENALTY_STOP · NEW_CARD_HOLD · 잠금 중 | 지금과 같음(기존 회귀 파일 rc0) · 예산 시계가 실행을 새로 만들지 않는다 | — |
| ㊳타 | fill 1항목 안 호출 10개 · 각 7초(DA 반례) | 45초에 끊김 · wall ≤ 60 · cursor = (팀, -, b2f) · 다음 바퀴가 fill 을 이어 감(fill_open 이어 열기 · submit 중복 0) | 70초 이상 |
| ㊳파 | 끊김 수렴: 닫기 · 깨움 · 재배정 · 쉼(park) · fill 각 순서의 «모든 호출 앞» 에서 1회씩 끊음 | 뒤 바퀴들을 돌리면 끊지 않은 실행과 같은 끝(work 별 journal 끝 줄 종류 · 쪽지 수 · 닫힌 세션) · 다르면 그 순서 이름을 원문으로 적고 원자 구간 선언(R9) | — |
| ㊳하 | 같은 자리가 2바퀴 연속 끊김 | `판정 불가 … 예산 2회 넘음 — 건너뜀` 1줄 · cursor 다음 자리 · 셋째 바퀴는 다음 자리부터 | — |
| ㊳거 | 끊김이 올라가는 길에 `except Exception` 이 있는 함수 | 먹히지 않고 바퀴까지 올라간다 · 그 함수의 실패 줄(판정 불가 등) 0 | — |
| ㊳너 | report 구획: 손 닫기 후보 probe 10개 · 각 2초 | 55초에 끊김 · 남은 probe·쪽지는 다음 바퀴 · 마무리(state 저장·ROUND 줄)는 한다 | 끝까지 |

범위 밖 입력(하드 룰 18·19·20): 줄바꿈·탭 든 파일 이름 · 권한 바꾼 상태 파일 · 주입한 git·tmux 실패의 꼴 맞추기 · 쓰기 호출이 자기 상한 7초를 넘겨 죽지 않는 경우(subprocess 상한 밖).

## 구현 범위 (나노 1 · 팩 base origin/main 최신 · DA 설계 승인 뒤)
1. 커밋 1 [test] — 새 시험 feature-pack/fable-team/ft2/tests/test_keeper_round_60s.py(㊳가~너 · 변이 M72~M79) · 기준판 FAIL 원문을 PR 본문에 붙인다 · 사례 1개 70초 안 · ㊳파는 순서마다 사례를 나눈다
2. 커밋 2 [fix] — R1~R10 = feature-pack/fable-team/ft2/adapters/pi/keeper.py(`call` 호출 문 · 예산 시계 · 끊김 예외 · cursor · `_round`·`team_round` 순환 · `git` 상한 · ROUND 줄) + feature-pack/fable-team/ft2/adapters/pi/keeper_report.py(R8 · report 구획) · 판정 규칙 손 0 · 다른 keeper_*.py 손 0
3. 커밋 3 [docs] — CONTRACT.md «바퀴 예산» 절(구획 숫자 · 호출 문 · cursor · 원자 구간 표) · CASES.md ㊳ 행
4. 회귀 rc0(파일별 · 각 70초 상한): test_pi_keeper_slow_call_r1992 · test_pi_keeper_b3_one_list_r1898 · test_pi_keeper_b2_split_cache_r1969 · test_pi_keeper_r1817 · test_keeper_notify_recipient · test_pi_keeper_next_card_r1871 · test_settle_one_path_r2055 · test_penalty_team_no_new_pick · test_new_card_hold · test_pi_keeper_fetch_fresh_r1963
5. 실행 = `python3.11 -m pytest` · 착지 = PR 1개(팀장 집행)

변이: M72 판독 호출 상한을 남은 몫으로 줄이지 않음 → ㊳가·㊳타 / M73 쓰기 문(남은 몫 7초) 빼기 → ㊳아 / M74 cursor 를 팀만 기억 → ㊳나·㊳사 / M75 2회 끊김 건너뜀 빼기 → ㊳하 / M76 git 상한 25 그대로 → ㊳바 / M77 send 미룸 빼기 → ㊳마 / M78 끊김을 Exception 으로 → ㊳거 / M79 report 를 구획 밖에서 → ㊳너

## 범위 밖
- mbox.sh send 가 7초에 끊기는 까닭(우편함 잠금·가드) — 다른 도구 · 새 카드 감
- gh pr list · git fetch 의 네트워크 속도 · 리포 크기 줄이기
- launchd 주기(60초) 바꾸기 · keeper 를 팀마다 따로 돌리기
- 판정 규칙·쪽지 글

## 완료 조건
1. [ ] 나노: 커밋 1 기준판 FAIL 원문
2. [ ] 나노: 새 시험 전체 rc0 · 걸린 초
3. [ ] 나노: 변이별 지정 반례 FAIL(설계가 정한 M72~ 전부)
4. [ ] 나노: 회귀 rc0(파일별 초)
5. [ ] 팀장: PR 착지 sha · 설치 판
6. [ ] arch: 설치 뒤 읽기 실측 = BYZ keeper 로그 ROUND 줄 200줄 이상에서 wall 60초 넘음 0 · `other=` 의 p50·가장 긴 값 · 단계별 초 표(p50 · p90 · 가장 긴 값)를 기준값 표와 나란히 · ROUND-CAP·판정 불가(git 7초)·NOTIFY-DEFER 줄 수 · 60초를 넘은 줄이 1개라도 있으면 원문과 함께 [ ] 로 둔다(빼고 통과 0)
7. [ ] arch: 굶음 0 = 같은 구간의 ROUND `cut=` 칸에서 같은 자리가 3바퀴 연속 나온 적 0 · `예산 2회 넘음` 줄 수와 그 자리 원문 · `items=` 의 p50(㊳사·㊳하의 실 runtime 판)
8. [ ] 나노: ㊳파 끊김 수렴 표 = 순서 5개 × 끊은 자리 수 · 수렴 못 한 순서 이름(없으면 «없음») · 원자 구간으로 선언한 것의 쓰기 호출 수

## 계약↔시험 대응표
| 계약 | 시험 |
|---|---|
| R1 구획 3개 | ㊳가 · ㊳라 · ㊳너 · ㊳차 |
| R2 호출 문(판독 줄임 · 쓰기 7초) | ㊳가 · ㊳아 · ㊳타 · M72 · M73 |
| R3 끊김 예외 | ㊳거 · M78 |
| R4 cursor | ㊳나 · ㊳라 · ㊳타 · M74 |
| R5 굶김 0 | ㊳사 · ㊳하 · M75 |
| R6 앞 단계 몫 | ㊳다 |
| R7 git 7초 | ㊳바 · M76 |
| R8 쪽지 미룸 · report 구획 | ㊳마 · ㊳너 · M77 · M79 |
| R9 끊김 수렴 | ㊳파 · ㊳아 |
| R10 ROUND 칸 | ㊳자 · ㊳차 |
| R11 그대로 | ㊳자 · ㊳카 |

## 상태
- base_sha: a065424f23ae6235b78ae657f647360abd61b2f8
- 2026-11-16 05:06 · 대기 — aifp-ft-arch-pi#20 초안(팀장 aifp 5704 · 실측 = BYZ keeper 로그 ROUND 210줄 · 구현 0) · 다음 = 팀장 PR → DA 설계 → Issue → 나노 1석
- 2026-11-16 05:22 · aifp-ft-arch-pi#20 r2(팀장 aifp 5726 · DA HOLD-DESIGN 1/3 BYZ 311663 · 사본 .fable-team/state/team-main/aifp-ft/DA-round-design-hold-311663/verdict.md) — 고친 것: 호출마다 남은 몫을 보는 호출 문(R2) · 구획 숫자 45·10·5(R1) · 팀·work·칸 cursor(R4) · 2회 끊김 건너뜀(R5) · 끊김 수렴과 원자 구간(R9) · «열기를 기다린다» 전제 정정(설계 확정 2) · «모든 팀 3바퀴» 를 2N 바퀴 순환으로(㊳사) · 반례 11 → 16 · 오빠 결정 0
