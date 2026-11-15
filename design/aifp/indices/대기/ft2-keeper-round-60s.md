# 인덱스: ft2-keeper-round-60s — 끝: ft2 keeper 한 바퀴가 60초 안에 끝난다 · 남은 예산이 없으면 새 항목을 시작하지 않고 다음 바퀴로 넘긴다 · ROUND 줄이 벽시계 초와 재지 못한 초를 함께 보인다
<!-- ledger: feature-pack/fable-team/legacy/1.x/harness/design/harness/GOAL-harness.md -->
- Issue: 없음(초안) — 요청 planner#327 aifp 5702 · 팀장 aifp-ft-master-pi#21 발주 aifp 5704 · 문제 원문 «keeper 한 바퀴 78초 / 상한 60초 ★크리티컬★ → 느린 단계 쪼개기»(BYZ design/planner/PROBLEMS-desk175-20261116.md 40줄 · 근거 BYZ #309391 · #309397 = 발주 인용 · 이 좌석은 그 파일을 로컬에서 못 찾아 원문 대조 안 함)
- 제안서: 없음 — 기존 상한(바퀴 60초)을 지키게 하는 결함 복구 · 설계 1쪽은 DA 설계 단계에서 쓴다(이 카드 «설계에서 고를 것» 4개)
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
- 대상: 팩 feature-pack/fable-team/ft2/adapters/pi/keeper.py(바퀴·상한·ROUND 줄) + 설계가 고르는 느린 칸의 파일(keeper_close.py · keeper_next.py · keeper_stall.py · keeper_report.py · keeper_fetch.py 중) · 새 시험 feature-pack/fable-team/ft2/tests/test_keeper_round_60s.py · 문서 ft2/contracts/keeper-settle/CONTRACT.md
- 정본 영향 없음: aifp 정본(docs/architect · docs/rules · design 팀 GUIDE·README) 변경 0 — 바뀌는 것은 팩 ft2 계약 문서(contracts/keeper-settle/CONTRACT.md «바퀴 예산» 절 1개 · CASES.md 행)뿐이고 같은 PR(나노)에 넣는다
- 크기: 코드 2~4파일 · 새 시험 1파일 · 문서 2파일 · PR 1개(설계가 2개로 쪼개면 카드도 쪼갠다)
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

## 계약 (무엇을 · 어떻게는 설계 1쪽)
- R1 예산 시계 1개 = 바퀴 시작부터 60초(지금의 `start` · ROUND_S) · 팀 고리 머리뿐 아니라 «새 항목을 시작하기 전» 마다 본다
- R2 항목 = ①팀 고리 앞 단계(fetch · 나노 가지 모으기) ②팀의 work 1개의 칸 1개(b1 · b2c · stall) ③팀의 fill 1회(b2f) ④팀 고리 뒤 단계(b3 고아 · b3 옛 좌석 · report) · 남은 예산이 «항목 최소 몫» 보다 작으면 그 항목과 뒤 항목을 시작하지 않는다
- R3 넘긴 것은 잃지 않는다 = 넘긴 팀부터 다음 바퀴가 돈다(지금의 cap_next 그대로) · 팀 고리 뒤 단계를 넘겼으면 다음 바퀴가 그 단계를 먼저 돈다 · 넘김은 `ROUND-CAP <넘긴 항목> — 다음 바퀴` 1줄
- R4 시작한 항목은 끝낸다(중간에 끊지 않는다 = 닫기·열기·쪽지가 반쯤 된 상태 0) · 그래서 항목 1개가 낼 수 있는 가장 긴 초를 계약에 숫자로 적는다 · 바퀴 끝 = 60초 안(예산 − 항목 최소 몫 + 항목 가장 긴 초 ≤ 60)
- R5 바깥 호출 1회 = 7초 상한(하드 룰 12) · 바퀴 안 로컬 git(merge-base · grep · ls-tree · rev-parse)도 같다 · 넘으면 그 항목 = `판정 불가 <팀> <항목> git 7초 넘음 — 다음 바퀴` 1줄(성공으로도 실패로도 읽지 않는다 · 하드 룰 20)
- R6 쪽지 send 가 한 바퀴에서 시간 초과(rc None) 2회면 그 바퀴 남은 쪽지는 보내지 않고 미룬다 = 지문·횟수 미소비 · `NOTIFY-DEFER` 줄(완성/ft2-keeper-notify-recipient 의 미룸 길 그대로)
- R7 드러냄 = ROUND 줄에 `wall=<벽시계 초>` · `other=<wall − 칸 합계>` 2칸을 더한다 · `OVER` 는 wall 로 판정한다 · 옛 칸·순서 그대로(뒤에 붙임)
- R8 그대로: 판정 규칙(착지·끝·settle) · 쪽지 글·받는 곳 · fetch 규칙(r1963·r1975) · gates() · ALL_STOP · PENALTY_STOP · NEW_CARD_HOLD · 잠금 · SLOW-CALL·SLOW-CELL 줄 꼴

## 설계에서 고를 것 (DA 설계 단계 · 카드는 고르지 않는다)
1. 항목 최소 몫과 항목 가장 긴 초의 숫자(R2·R4) — 열기(LAUNCHING) 1회가 실제로 몇 초인지 먼저 잰다(기준값 «나»·«다» 는 칸 합계만 있다)
2. 열기를 바퀴 안에서 기다리는가(지금) · 던지고 다음 바퀴가 잇는가(LAUNCH-WAIT · fill_open 이어 열기 길이 이미 있다) — «느린 단계 쪼개기» 의 본체
3. 짧은 호출 148회(기준값 «다»)를 줄이는가(바퀴 캐시) · 예산 시계로 끊기만 하는가
4. R5 로 git 상한을 25 → 7초로 내리면 load 가 높은 시간대에 «판정 불가» 가 얼마나 느는가(오늘 7초 넘은 로컬 git = 11줄) · 굶는 카드가 생기지 않는 근거

## 반례 표 (후보 · 설계가 확정)
| # | 입력 | 기대 | 지금 |
|---|---|---|---|
| ㊳가 | 팀 3 · 첫 팀의 b2c 1항목이 50초(가짜 시계) | 첫 팀 남은 항목·둘째 팀부터 시작 0 · ROUND-CAP 1줄 · cap_next = 넘긴 팀 · wall ≤ 60 | 첫 팀을 끝까지 돌고 둘째 팀 머리에서야 컷 |
| ㊳나 | 한 팀의 work 5개 · 각 b1 14초 | 예산 안 항목만 돌고 나머지 work 는 다음 바퀴 · 넘긴 work 의 판정·쪽지 0 | 5개 모두(70초) |
| ㊳다 | 팀 고리 앞 fetch 14초 + 나노 모으기 30초 | 나노 모으기가 몫을 넘기 전에 멈추거나 넘긴다 · 팀 고리 예산이 남는다 | 44초 쓰고 팀 고리 시작 |
| ㊳라 | 팀 고리가 58초에 끝남 · b3 25초짜리 | b3 시작 0 · ROUND-CAP 1줄 · 다음 바퀴가 b3 먼저 | b3 를 돌아 83초 |
| ㊳마 | send 가 rc None 2회 뒤 보낼 쪽지 4통 | 남은 4통 send 0 · NOTIFY-DEFER · 지문 미소비 · 다음 바퀴 보냄 | 통마다 7초 × 2 |
| ㊳바 | merge-base 가 8초 걸림 | 7초에 끊김 · `판정 불가 … git 7초 넘음` 1줄 · complete·닫기 0 · 다음 바퀴 다시 봄 | 25초까지 기다림 |
| ㊳사 | 넘긴 팀이 매 바퀴 같은 팀 | cap_next 가 돌아 뒤 팀이 굶지 않는다(3바퀴 안에 모든 팀 1회 이상) | — |
| ㊳아 | 닫기 항목 도중 예산 0 | 그 닫기는 끝낸다(영수 1 · 세션 닫힘) · 다음 항목 시작 0 | — |
| ㊳자 | 모두 빠름(합 10초) | 줄·순서·동작 지금과 같음 + ROUND 줄 끝에 wall= other= | — |
| ㊳차 | 칸 사이·report 에 20초(재지 않는 초) | ROUND other=20 · wall 이 60 넘으면 OVER | s 에 안 보임 |
| ㊳카 | ALL_STOP 정지 중 | 지금과 같음(판정·«예정» 줄만) · 예산 시계가 실행을 새로 만들지 않는다 | — |

범위 밖 입력(하드 룰 18·19·20): 줄바꿈·탭 든 파일 이름 · 권한 바꾼 상태 파일 · 주입한 git·tmux 실패의 꼴 맞추기.

## 구현 범위 (나노 1 · 팩 base origin/main 최신 · DA 설계 승인 뒤)
1. 커밋 1 [test] — 새 시험 feature-pack/fable-team/ft2/tests/test_keeper_round_60s.py(㊳가~카 · 변이 M72~) · 기준판 FAIL 원문을 PR 본문에 붙인다
2. 커밋 2 [fix] — R1~R7 = feature-pack/fable-team/ft2/adapters/pi/keeper.py(`_round` · `team_round` · `call` · ROUND 줄) + 설계가 정한 파일 · 판정 규칙 손 0
3. 커밋 3 [docs] — CONTRACT.md «바퀴 예산» 절 · CASES.md ㊳ 행 · 설계 1쪽을 feature-pack/fable-team/design/ 로
4. 회귀 rc0(파일별 · 각 70초 상한): test_pi_keeper_slow_call_r1992 · test_pi_keeper_b3_one_list_r1898 · test_pi_keeper_b2_split_cache_r1969 · test_pi_keeper_r1817 · test_keeper_notify_recipient · test_pi_keeper_next_card_r1871 · test_settle_one_path_r2055
5. 실행 = `python3.11 -m pytest` · 착지 = PR 1개(팀장 집행)

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
6. [ ] arch: 설치 뒤 읽기 실측 = BYZ keeper 로그 ROUND 줄 200줄 이상에서 wall 60초 넘음 0 · 단계별 초 표(p50 · p90 · 가장 긴 값)를 기준값 표와 나란히 · ROUND-CAP·판정 불가(git 7초)·NOTIFY-DEFER 줄 수 · 60초를 넘은 줄이 1개라도 있으면 원문과 함께 [ ] 로 둔다(빼고 통과 0)
7. [ ] arch: 굶음 0 = 같은 구간에서 팀마다 판정 줄이 3바퀴 안에 1회 이상(㊳사의 실 runtime 판)

## 계약↔시험 대응표
| 계약 | 시험 |
|---|---|
| R1·R2 항목 앞 예산 검사 | ㊳가 · ㊳나 · ㊳다 · ㊳라 |
| R3 넘김·차례 | ㊳가 · ㊳라 · ㊳사 |
| R4 시작한 항목은 끝냄 | ㊳아 |
| R5 git 7초 | ㊳바 |
| R6 쪽지 미룸 | ㊳마 |
| R7 wall·other | ㊳자 · ㊳차 |
| R8 그대로 | ㊳자 · ㊳카 |

## 상태
- base_sha: a065424f23ae6235b78ae657f647360abd61b2f8
- 2026-11-16 05:06 · 대기 — aifp-ft-arch-pi#20 초안(팀장 aifp 5704 · 실측 = BYZ keeper 로그 ROUND 210줄 · 구현 0) · 다음 = 팀장 PR → DA 설계 → Issue → 나노 1석
