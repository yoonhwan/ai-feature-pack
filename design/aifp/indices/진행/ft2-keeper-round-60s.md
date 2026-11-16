# 인덱스: ft2-keeper-round-60s — 끝: ft2 keeper 한 바퀴가 벽시계 60초 안에 끝난다 · 예산이 다하면 그 자리(팀·work·칸)에서 끊고 다음 바퀴가 거기서 잇는다 · ROUND 줄이 벽시계 초·재지 못한 초·끊긴 자리를 보인다
<!-- ledger: feature-pack/fable-team/legacy/1.x/harness/design/harness/GOAL-harness.md -->
- Issue: #8661 (byz-agents · 팀장 aifp-ft-master-pi#22 등록 BYZ 312613 · 오빠 결정 ① · 동결 반례 F1~F7) — 요청 planner#327 aifp 5702 · 팀장 aifp-ft-master-pi#21 발주 aifp 5704 · 문제 원문 «keeper 한 바퀴 78초 / 상한 60초 ★크리티컬★ → 느린 단계 쪼개기»(BYZ design/planner/PROBLEMS-desk175-20261116.md 40줄 · 근거 BYZ #309391 · #309397 = 발주 인용 · 이 좌석은 그 파일을 로컬에서 못 찾아 원문 대조 안 함)
- 제안서: 없음 — 기존 상한(바퀴 60초)을 지키게 하는 결함 복구 · 설계 = 이 카드 «계약»·«바깥 호출 전수»·«설계 확정»·«반례 표»(DA HOLD-DESIGN 1/3 BYZ 311663 반영 r2 · 2/3 BYZ 311745 반영 r3 · 3/3 BYZ 311870 뒤 오빠 결정 ① 수신자 순환 반영 r4 · 반례 동결 .fable-team/state/team-main/aifp-ft/keeper-round-60s-decision/FROZEN.md · 4번째 설계 DA 0 = 하드 룰 14)
- 근거: 실측 2026-11-16 05:05(aifp-ft-arch-pi#20 · BYZ .fable-team/state/ft2-keeper/20261116.jsonl 읽기만 · 설치 ft2 2.0.65~2.0.68 구간) — 아래 «기준값» 절
- 원인 1줄: 바퀴 상한 검사는 팀 고리 머리 1곳뿐이다(adapters/pi/keeper.py `_round` 의 `if time.monotonic() - start > ROUND_S`) · 한 팀의 한 칸이 혼자 60초를 넘어도 끊지 못하고 · 팀 고리 앞(fetch · 나노 가지 모으기)과 뒤(b3 · report)는 상한 밖이다
- 앞 카드: r1817(단계별 초) · r1898(cap_next = 컷에 걸린 팀부터) · r1969(slow 칸) · r1992(SLOW-CALL · SLOW-CELL) · r1963·r1975(fetch) · 완성/ft2-keeper-notify-recipient(쪽지 받는 곳·바퀴 3통)
- 착지: d261be1a1e504d5ecc649473510a7efab3e28a6d(팩 main · PR #1397 squash · head 9fc8b9ab · DA 대행 byz-harness-da-codex#11 APPROVE-IMPL BYZ 313228 · 세트 9fc8b9ab = PR head · 뺄 커밋 0)
- 상태: 대기
- 설치: 있음 — ft2 판 올림 1회 · 되돌림 = 앞 판으로 판 전환(상태 파일 새 키는 옛 판이 읽지 않음)
- 선행: 없음(팩 origin/main a065424f)
- 시험 입력: 임시 루트(tmp_path) · 시험 안에서 만든 journal·카드 · 가짜 tmux·가짜 mbox·가짜 git(걸린 초를 가짜 시계로 더함) · 주입 시계(self.now · monotonic 주입점) · sleep 0 · 네트워크 0 · 실 runtime 읽기·쓰기 0 · 사례 1개 70초 안
- 기준값: 오늘 00:00:54~05:04:32 ROUND 210줄 = 60초 넘음 14줄 · 가장 긴 바퀴 152.5초 · p50 15.8초 · p90 52.5초 → 목표 = 60초 넘음 0줄
- 규칙: 없음 — 상시 로드 변경 0
- 규칙 상세: 하드 룰 12(외부 호출 7초 · 런타임 7초 절대) · 하드 룰 20(외부 명령 실패 = 판정 불가 1줄) · 하드 룰 22
- 대상: 팩 feature-pack/fable-team/ft2/adapters/pi/keeper.py(예산 시계 · 호출 문 · cursor · 바퀴 · ROUND 줄 · git 상한 · 꽉 참 알림 넣는 곳) · feature-pack/fable-team/ft2/adapters/pi/keeper_report.py(쪽지 미룸 · report 구획 · 꽉 참 알림 보내기) · feature-pack/fable-team/ft2/adapters/pi/full_alert.py(보내는 손 주입 1칸 · r3) · 새 시험 feature-pack/fable-team/ft2/tests/test_keeper_round_60s.py · 문서 ft2/contracts/keeper-settle/CONTRACT.md · CASES.md
- 정본 영향 없음: aifp 정본(docs/architect · docs/rules · design 팀 GUIDE·README) 변경 0 — 바뀌는 것은 팩 ft2 계약 문서(contracts/keeper-settle/CONTRACT.md «바퀴 예산» 절 1개 · CASES.md 행)뿐이고 같은 PR(나노)에 넣는다
- 크기: 코드 3파일(r3 · full_alert.py 더함 = 3개를 넘지 않아 선행 카드로 쪼개지 않는다) · 새 시험 1파일 · 문서 2파일 · PR 1개 · 끊김 수렴 시험(㊳파)에서 원자 구간이 21초를 넘는 순서가 나오면 그 순서는 새 카드로 쪼갠다(코드 4파일을 넘기지 않는다)
- 배정: 좌석 aifp-ft-nano-ft2-keeper-round-60s#0

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

새 실측 1줄(r4 · 2026-11-16 07:15 · ft2 2.0.72 · BYZ 읽기만): 꽉 참 알림 BYZ 312444 `★크리티컬★ 꽉 참 keeper 바퀴 keeper 89/60 · 막힌 것 남은 팀 issues · 풀기 = keeper 로그 단계별 초에서 느린 단계 쪼개기`(07:15:13 · ft2-full-alert → harness master) · 같은 바퀴 `07:15:15 ROUND s=85 fetch=5 b1=26 b2c=17.1 b2f=20.4 b3=0.2 stall=1.2 fetch_root=4.7 fetch_pack=1.9 nano=15.1 slow=harness:b2c:17.1 OVER unknown=15` = 벽시계 89초 / 상한 60초 · 칸 합계 85초(차 4초가 칸 밖) · 가장 느린 칸 harness b2c 17.1초

## 바깥 호출 전수 (r3 · 실측 2026-11-16 05:36 · aifp-ft-arch-pi#21 · 팩 origin/main 14c2f051 · 읽기만)
잰 법: ft2 의 시험 밖 .py 전부를 AST 로 훑어 subprocess.run·Popen·call·check_output · os.system·popen · urlopen 호출 줄을 셈(19줄) + grep 으로 time.sleep · flock · wait · communicate · 별칭(subprocess 낱말이 든 줄 전부) 대조. r2 는 keeper*.py 의 속성 이름만 보아 full_alert.py 를 놓쳤다.

| # | 자리 | keeper 바퀴에서 닿는 길 | 문(Keeper.call) | r3 처리 |
|---|---|---|---|---|
| 전1 | adapters/pi/keeper.py:74 subprocess.run | 문 자체 · 문을 부르는 자리 = 13파일 75줄(grep 셈 · 정의 줄 포함) | — | R2 |
| 전2 | adapters/pi/full_alert.py:15 subprocess.run(7초 · 2회 · 받는 곳 최대 2 = 최악 28초) | keeper.py:262·267(keeper 바퀴) · keeper_next.py:84(나노 정원) · keeper_next.py:263·313(남은 일) · keeper_land.py:212(journal) = 6곳 | ★밖★ | R12 = 바퀴 안에서는 보내지 않고 넣어 두었다가 report 구획에서 문을 지나 보낸다 |
| 전3 | adapters/pi/keeper_launch.py:43 subprocess.Popen | keeper_next.reconcile → launching → spawn | 밖 · 대기 0(wait·communicate 0줄) | 그대로 · R13 에 «대기 없는 띄우기» 로 이름을 적는다 |
| 전4 | adapters/pi/keeper_fetch.py:74 subprocess.Popen | keeper.py main 이 run_once 뒤에 부름(바퀴·잠금 밖) | 밖 · 대기 0 | 그대로 · R13 |
| 전5~전8 | adapters/pi/launch.py:89 · launch_cleanup.py:15 · launch_plan.py:163·216 | 닿지 않음 = 따로 뜬 launch.py 프로세스만(keeper 는 pid_state 에 문을 꽂아 부른다 = keeper_launch.py:18·21) | — | 손 0 |
| 전9 | adapters/pi/card_stage.py:31 | 닿지 않음(ft2 시험 밖에서 부르는 줄 0 · 단독 명령) | — | 손 0 |
| 전10~전12 | adapters/slack/wiring.py:89·221 · socket.py:59(urlopen) | 닿지 않음 = Slack 수신기 프로세스 | — | 손 0 |
| 전13~전19 | doctor/recover.py:45 · tools/install.py:58 · contracts 의 검사 5파일 | 닿지 않음 = 단독 명령 | — | 손 0 |

전수 목록 = 19줄 · keeper 바퀴에서 닿는 우회 = 3줄(전2 · 전3 · 전4) · 그중 기다리는 것 = 1줄(전2).

문은 지나지만 r2 의 «쓰기 = 7초» 전제를 깨는 자리(자기 상한 25초인 쓰기 3줄): keeper_stall.py:233(재배정 launch.py · LAUNCH_S 25) · keeper_close.py:310(닫기 도구 · GIT_S 25) · keeper_next.py:348(배정 원장 record · GIT_S 25). 정지 그물에 없는 쓰기 2줄: keeper_report.py:98(mbox send) · keeper_settle.py:511(clean 도구). → R2 를 고친다.

프로세스 안에서 기다릴 수 있는 것: time.sleep 0줄(adapters/pi · core) · 막고 기다리는 flock 1줄(launch_roster.py:73 = launch.py 만 부른다) · core 의 flock 은 모두 LOCK_NB · cli.run 9줄(keeper_next 262·280·311 · keeper_land 211 · keeper_settle 332·472 · keeper_stall 224·230 · core 에 subprocess·urlopen 0줄 = 파일 읽기·쓰기뿐).

전2 의 기준값(BYZ .fable-team/state/ft2-full-alert.jsonl · 실패 줄만 남는 장부 · 91줄): rc 3 = 82줄 · TimeoutExpired = 9줄(받는 곳 1곳마다 7초 2회 = 126초가 SLOW-CALL 에도 ROUND 칸에도 보이지 않았다) · 오늘 우편함에 간 꽉 참 알림 48통(mailbox.log.jsonl from=ft2-full-alert). 긴 쓰기 3줄의 오늘 값: REASSIGNED 0줄 · CLOSED-SEAT 0줄 · SLOW-CALL 74줄 중 launch·닫기 도구·record 0줄.

## 계약 (r4 · DA 311663 · 311745 반례 반영 · R12 보내기 = 오빠 결정 ① 수신자 순환)
- R1 예산 시계 1개 = 바퀴 시작부터의 벽시계 초 · 구획 3개: 업무 0~45초(fetch · 나노 가지 모으기 · 팀 항목 · b3) · report 45~55초 · 마무리 55~60초(state.json 원자 쓰기 · ROUND 줄 · 관측 기록 = 바깥 호출 0)
- R2 호출 문 1곳(`Keeper.call`) — 바깥 호출을 시작하기 전마다 남은 몫(= 지금 구획 끝 − 벽시계)을 본다
  - 판독 호출 = 문 안의 판독 목록 1개에 든 것만(git 의 rev-parse · merge-base · grep · ls-tree · ls-remote · fetch · log · show · cat-file · cherry · rev-list · status · config --get = 지금 문을 지나는 git 동사 13개 전부 · tmux 의 has-session · display · display-message · capture-pane · list-sessions · gh pr list · ps · mbox peek · 벌점 판정기 check): 상한 = min(자기 상한, 남은 몫) · 남은 몫 1초 미만 = 시작 0 · 끊김 · 남은 몫으로 줄인 상한에 걸려 끝난 것도 끊김(느린 것이 아니라 예산이 다한 것 = `판정 불가` 로 적지 않는다)
  - 쓰기 호출 = 판독 목록 밖 전부(r3 · 모르는 호출은 쓰기로 본다 = kill-session · send-keys · python 실행 · 닫기 도구 · mbox send · 배정 원장 record · clean 도구): 원자 단위 = 호출 1개 · 몫 = 그 호출의 자기 상한(7초 · 긴 쓰기 3줄은 25초) · 남은 몫이 자기 상한보다 작으면 시작 0 · 끊김 · 시작한 쓰기는 자기 상한 그대로(줄이지 않는다) · 재시도 0 그대로
  - 긴 쓰기 3줄(25초)은 벽시계 20초 뒤로는 시작하지 않는다 → 그 자리는 끊기고 R5 가 맡는다 · 상한을 7초로 줄이지 않는다(오늘 5초 넘은 적 0 이지만 줄이면 도는 도중에 죽는다) · 굶는지는 완료 조건 7 로 본다
  - 프로세스 안 동사(cli.run 9줄)는 문을 지나지 않는다 · 걸린 초는 0 이 아니다 → 가정 A1 로 따로 적는다(아래) · ROUND `other=` 에 보인다
- R3 끊김 = 그 바퀴 업무 구획의 끝 · 뒤 항목 시작 0 → report 구획 → 마무리 · 끊김은 예외 1종으로 올린다(`except Exception` 에 먹히지 않는 종류) · 올라가는 길에 상태 쓰기 0
- R4 cursor = state.json 의 `cursor` 1칸 `{team, work, stage, cuts}` + report 구획용 `rep_cursor` 1칸 `{seat}`(r3 · 손 닫기 후보 probe 가 55초에 끊기면 그 좌석 이름 · 다음 바퀴 report 는 그 좌석부터 이름순으로 돈다 · 다 돌면 지운다 · 업무 cursor 와 따로 둔다 = 한 바퀴에 둘 다 끊길 수 있다) · stage = b1 · b2c · stall · b2f(팀의 fill) · b3o(고아) · b3r(옛 좌석) · 순서 = 팀(이름순) → work(이름순) → 칸(지금 순서) → 팀 고리 뒤 b3o → b3r 의 고정 순환 · 다음 바퀴는 cursor 자리부터 돈다 · 끊김 없이 한 바퀴를 다 돌면 cursor 를 지운다 · 지금의 `cap_next` 는 cursor 로 바뀐다(옛 키는 읽어서 팀 자리로 옮긴다)
- R5 굶김 0 = 같은 자리가 연속 2바퀴 끊기면 `판정 불가 <팀> <work> <칸> 예산 2회 넘음 — 건너뜀` 1줄 + cursor 를 다음 자리로 · git 7초 실패(R7)는 끊김이 아니다 = 판정 불가 1줄 + 그 자리의 남은 판정 0 + 다음 자리로 간다
- R6 앞 단계 몫 = fetch 는 지금 규칙 그대로(ls-remote 7초 + fetch 7초 + 재시도 1 = 최대 21초 · 두 리포 동시) · 나노 가지 모으기 = 합 7초(판독 호출을 R2 로 줄임) · 넘으면 `판정 불가 나노 가지 모으기 7초 넘음 — 모은 것만` 1줄 + 모은 것으로 진행 · 모으는 순서도 cursor 팀부터
- R7 로컬 git 상한 25 → 7초(merge-base · grep · ls-tree · rev-parse · 하드 룰 12) · 자기 상한에 걸리면 `판정 불가 <팀> <work> git 7초 넘음` 1줄 · 성공으로도 실패로도 읽지 않는다 · 상태 쓰기 0
- R8 쪽지 = 한 바퀴에서 send 시간 초과(rc None) 2회면 그 바퀴 남은 쪽지는 보내지 않는다 · 미룬 쪽지 = 지문·횟수 미소비 + NOTIFY-DEFER 줄 · 그 전에 간 쪽지의 지문·횟수는 그대로 · report 구획(45~55초)의 쓰기도 R2 를 지난다
- R9 끊김 수렴 = 어느 호출 앞에서 끊겨도 뒤 바퀴들이 «끊기지 않은 실행» 과 같은 끝에 닿는다(journal 의 work 별 끝 줄 종류 같음 · 쪽지 중복 0 · 닫힌 세션 같음) · 수렴하지 않는 순서가 시험에서 나오면 그 순서만 «원자 구간» 으로 선언한다(쓰기 호출 n개 · 몫 n×7 ≤ 21초 · 첫 쓰기 전에 몫을 예약 · 구간 표를 CONTRACT 에 적는다) · 21초를 넘으면 이 카드에서 고치지 않고 쪼갠다
- R10 드러냄 = ROUND 줄 끝에 `wall=<초> other=<wall − 칸 합계> items=<돈 자리>/<전체 자리> cut=<팀:work:칸 또는 ->` · `OVER` 는 wall 로 판정 · 끊김 1줄 = `ROUND-CAP <팀> <work> <칸> — 다음 바퀴 여기부터` · 옛 칸·순서 그대로
- R11 그대로: 판정 규칙(착지·끝·settle) · 쪽지 글·받는 곳 · fetch 규칙(r1963·r1975) · gates() · ALL_STOP · PENALTY_STOP · NEW_CARD_HOLD · 잠금 · SLOW-CALL·SLOW-CELL 줄 꼴 · 열기(아래 «설계 확정» 2) · 꽉 참 알림의 글·받는 곳(팀 master + harness master)·서명 규칙
- R12 꽉 참 알림(r3 · 전2 · 보내기 줄은 r4) = keeper 바퀴 안에서는 보내지 않는다
  - full_alert.py 의 observe · remaining · journal 에 «보내는 손» 인자 1칸을 더한다 · 기본값 = 지금의 `_send`(Slack 수신기 쪽 부르는 곳 2줄 = receive.py:201 · wiring.py:307 은 동작 그대로)
  - keeper 는 자기 손을 꽂는다(keeper.py 의 `fa` 1곳 · keeper_next.py · keeper_land.py 의 부르는 줄 손 0) · 그 손은 바깥 호출 0 = state.json 의 `alert_out` 목록에 `{to, body, sig, tries, mark}` 1줄을 더할 뿐이다(r4 · `mark` = 확인 못 한 시도의 우편함 장부 seq 경계 · 처음엔 빈 값)
  - 서명 저장은 지금 순서 그대로(먼저 저장 = 재알림 폭주 0) · 알림 글은 `alert_out` 에 남아 있어 끊겨도 잃지 않는다(영수 경계 = 보낸 것이 확인된 줄만 목록에서 지운다)
  - 보내기(r4 · 오빠 결정 ① 수신자 순환 · 앞 판 «시간 초과 = 목록 그대로 · tries 미소비» 는 버린다) = report 구획 머리에서 `alert_out` 을 앞에서부터 · 한 바퀴에서 한 줄은 한 번만 시도한다 · 통마다 문을 지나는 쓰기 1개(7초 · 재시도 0)
    - 성공 = rc 0 또는 E7 도착 확인(시도 바로 뒤 우편함 장부 판독 · 지금 notify 와 같은 함수) → 목록에서 지움 + `FULL-ALERT <받는 곳> <글 머리>` 1줄(도착 확인이면 `(도착 확인 · rc <값>)` 붙임)
    - 실제 시도했는데 미완료(시간 초과 rc None · rc≠0 · 도착 확인 안 됨) = tries +1 · 그 시도의 seq 경계를 `mark` 에 적음 · 그 받는 곳의 줄 전부를(서로 순서 그대로) 목록 맨 뒤로 옮긴다 = 다음 시도는 다른 받는 곳부터다(끊긴 사람은 다음 사람 뒤)
    - `mark` 가 있는 줄을 다시 시도하기 앞 = 그 경계로 E7 도착 확인을 먼저 한 번(장부 읽기 · 바깥 호출 0) · 도착이면 성공 처리 · 다시 보내기 0(늦게 닿은 알림을 두 번 보내지 않는다)
    - 시작하지 않은 예산 미룸(문에서 남은 몫 < 7초로 시작 0 · R8 미룸) = tries 그대로 · 순서 그대로 · 그 바퀴 보내기는 거기서 끝 · 다음 바퀴가 그 줄부터 잇는다
    - tries 3 = 목록에서 지우고 `판정 불가 꽉 참 알림 3회 실패 <받는 곳>` 1줄 + 지금과 같은 꼴로 ft2-full-alert.jsonl 1줄(조용한 유실 0) · 이때 FULL-ALERT 줄은 쓰지 않는다(확인 못 한 것을 지웠다고 전달 성공으로 적지 않는다)
    - 순서·tries·`mark` 는 `alert_out` 줄 그대로 state.json 에 남는다 = 목록 순서가 곧 순환 자리다(따로 cursor 칸 0) · keeper 가 다시 떠도 그대로 잇는다
    - 끝이 있다 = 줄마다 실제 시도 3회가 상한이고, 모든 받는 곳이 시간 초과여도 한 바퀴에 시작되는 7초 시도는 report 구획 10초 안 1개뿐이라 wall ≤ 60 이다
  - R8 의 «시간 초과 2회 = 남은 쪽지 미룸» 은 이 목록에도 같이 센다 · 바퀴 3통 상한(E5)은 세지 않는다(꽉 참 알림이 일반 쪽지 뒤로 밀리지 않게 먼저 보낸다)
  - «keeper 바퀴» 관측 = 마무리 구획에서 1회 · 값 = wall(R10) · 한계 60 · 끊김(ROUND-CAP)만으로는 꽉 참이 아니다(지금은 ROUND-CAP 마다 꽉 참 = 실패 장부에만 «keeper 바퀴» 글 33줄) · 그 알림은 다음 바퀴 report 구획에서 나간다
- R13 문 밖 바깥 호출 0 = adapters/pi 의 keeper 바퀴에서 닿는 파일에서 기다리는 바깥 호출(subprocess.run·call·check_output · urlopen · os.system)은 keeper.py 의 문 1줄뿐 · 예외 = «대기 없는 띄우기» 2줄(전3 · 전4 = Popen 뒤 wait·communicate 0) · 시험이 AST 로 센다(새 우회가 생기면 FAIL)
- 가정 A1(증명 밖 · 실측으로 본다) = 프로세스 안 초(cli.run 동사 · 파일 읽기 · 파이썬)는 문이 끊지 못한다 · 문은 다음 호출 앞에서 그 초를 남은 몫에 반영할 뿐이다 · 마지막 문 뒤에 몰린 초는 막지 못한다 → 마무리 5초가 그 몫이다 · `other=` 의 가장 긴 값이 5초를 넘으면 완료 조건 6 을 [ ] 로 두고 동사에도 문을 두는 후속 카드를 낸다

벽시계 60초가 나오는 셈(r3): 기다리는 바깥 호출은 문 1곳만 지난다(R13). 판독은 구획 끝에서 끊긴다. 쓰기는 구획 끝에서 자기 상한만큼 앞까지만 시작하고 자기 상한 안에 끝난다. 그래서 바깥 대기는 업무 45초, report 55초를 넘지 않는다. 꽉 참 알림은 report 구획의 쓰기다(R12). 마무리는 바깥 호출이 없다. 이 셈이 보장하는 것은 바깥 대기까지다. 프로세스 안 초는 가정 A1 이고 `other=` 로 재서 완료 조건 6 에서 본다(«other 를 재니까 60초가 보장된다» 고 하지 않는다).

DA 311745 반례(업무 34초 · fill 의 남은 일 꽉 참 알림 4호출 = 62초)에 댄 답: fill 은 알림 글을 `alert_out` 에 넣기만 한다(0초). 그 2통은 report 구획에서 문을 지나 나간다. 45초에 시작해 7초씩이면 둘째 통은 52초에 끝난다. 첫 통이 시간 초과면 둘째 통은 남은 몫 3초라 시작하지 않고 다음 바퀴로 간다.

DA 반례(fill 1항목 안 7초 호출 10개 = 70초)에 댄 답: 그 10개는 호출마다 문을 지난다. 판독이면 45초에 끊기고, 쓰기면 38초 뒤로는 시작하지 않는다. fill 은 끊긴 자리(cursor)에서 다음 바퀴가 잇는다.

## 설계 확정 (DA 311663 권고 4개에 댄 답 · 오빠 결정 1개 = 5번)
1. 몫의 숫자 = 업무 45 · report 10 · 마무리 5초 · 원자 단위 = 쓰기 호출 1개 7초(DA 권고 «원자 항목 최대 7초») · 앞 판의 «최소 몫» 은 버린다(시작 전에 보는 것은 호출 1개의 최대 몫이다) · 이 숫자는 실측값이 아니라 상한에서 거꾸로 센 값이다. 업무 45초로 줄면 끊기는 바퀴가 는다(오늘 칸 합계 p90 = 52.5초). 그 값은 완료 조건 6 의 `items=`·`cut=` 로 본다.
2. 열기는 지금도 기다리지 않는다(정정) = keeper_launch.py 의 spawn 은 Popen(start_new_session) 으로 던지고, 다음 바퀴가 LAUNCH-WAIT·fill_open 이어 열기로 잇는다 · 이 카드는 열기에 손대지 않는다 · 기준값 «나»·«다» 의 긴 칸은 열기 앞뒤의 동기 일(카드 고르기 · project · submit · assign · deliver)과 닫기 판독이다 · 그 일은 R2 의 호출 문과 `other=` 로 갈라 본다
3. 정확성은 호출 문과 cursor 가 맡는다 · 바퀴 캐시를 더 늘리지 않는다(명부·판정 결과의 낡은 캐시 0) · 짧은 호출 148회는 줄이지 않고 끊는다
4. git 7초 실패 = 판정 불가 + 다음 자리(R5·R7) · 느린 팀이 앞자리를 계속 차지하지 않는다 · 상한을 늘리거나 성공으로 치지 않는다 · 오늘 7초 넘은 로컬 git = 11줄(210바퀴) = 판정 불가가 그만큼 는다
5. 오빠 결정(r4 · 2026-11-16 · Slack thread ts 1794775311.637929 · 답 ts 1794781929.270889 «1» · desk#180 BYZ 312567 · planner#329 aifp 5851) = DA HOLD-DESIGN 3/3(BYZ 311870 · 사본 .fable-team/state/team-main/aifp-ft/DA-round-design-hold3-311870/verdict.md)의 «선택지 1» 수신자 순환 · 끊긴 사람은 다음 사람 뒤로 · 시간 초과도 3회 상한에 센다 · E7 도착 = 성공 · 예산 미룸만 0회 · 반례 F1~F7 동결(FROZEN.md) · 이 뒤 설계 DA 0 · 구현 DA 는 동결 반례의 동작만 본다(하드 룰 14·21) · 고르지 않은 안 = 2 별도 실행기(outbox) · 3 FIFO 3회 상한

## 반례 표 (r4 · DA 보완 반영 · 동결 반례 F1~F7 · 가짜 시계)
시간 입력의 뜻(r3): 가짜 호출은 «요청받은 상한» 과 «자기 소요» 중 작은 값만큼 가짜 시계를 올린다. 7초를 넘는 값은 호출 1개가 아니라 호출 여러 개의 합이다(㊳가 = 판독 8개 × 7초 · ㊳나 = work 마다 판독 2개 × 7초 · ㊳다 = ls-remote 7 + fetch 7 · 나노 판독 6개 × 5초 · ㊳라 = 판독 4개 × 7초에서 앞 3개 뒤 끊김). 호출 1개가 자기 상한보다 길면 상한에서 끊긴 것(rc None)으로 돌려준다(㊳바).

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
| ㊳너 | report 구획: 손 닫기 후보 probe 10개 · 각 2초 | 55초에 끊김 · `rep_cursor` = 여섯째 좌석 · 다음 바퀴 report 는 여섯째부터 · 남은 쪽지는 다음 바퀴 · 마무리(state 저장·ROUND 줄)는 한다 | 끝까지 |
| ㊴가 | DA 311745: 업무 34초 · fill submit 이 남은 일 꽉 참 전이 · 받는 곳 2(팀 master ≠ harness master) · send 는 모두 시간 초과 | 바퀴 안 full_alert 바깥 호출 0 · `alert_out` 2줄 · report 구획에서 문을 지나 1통 시도(7초) · 둘째는 시작 0 · wall ≤ 60 · 서명 1개 · 첫째 줄 tries 1 로 목록 뒤 · 다음 바퀴는 둘째 받는 곳부터 1통 시도(r4 · 앞 판 «다음 바퀴에 2통 다시 시도» 를 고침) | 62초 · 문 0회 |
| ㊴나 | `alert_out` 3줄 · 첫 통 rc 0 · 둘째 rc 1 · 셋째 rc 0 | 첫·셋째 줄 지움 + FULL-ALERT 2줄 · 둘째 tries 1 로 남음 · 다음 두 바퀴도 rc 1 이면 지움 + `판정 불가 꽉 참 알림 3회 실패` 1줄 + ft2-full-alert.jsonl 1줄 | 그 자리에서 2회 뒤 jsonl 1줄 |
| ㊴다 | 꽉 참 알림을 넣은 바퀴가 업무 구획에서 끊김 | 끊김이 올라가도 `alert_out` 은 마무리의 state 저장에 들어 있다 · 다음 바퀴 report 에서 나감 · 같은 서명 알림 중복 0 | — |
| ㊴라 | 긴 쓰기(재배정 launch.py · 자기 상한 25초) 직전 남은 몫 24초 | 시작 0 · 끊김 · launch 호출 0 / 남은 몫 26초면 시작한다 · 가짜 소요 25초여도 wall ≤ 45 | 시작해서 59초 |
| ㊴마 | 판독 목록에 없는 새 호출(bash 어떤-도구 · 자기 상한 7초) 직전 남은 몫 5초 | 쓰기로 본다 = 시작 0 · 끊김(판독처럼 5초로 줄여 돌리지 않는다) | — |
| ㊴바 | adapters/pi 의 keeper 바퀴에서 닿는 파일을 AST 로 훑음 | 기다리는 바깥 호출 = keeper.py 문 1줄 · Popen = 2줄(keeper_launch.py · keeper_fetch.py) · 그 밖 0 | full_alert.py 1줄 더 |
| ㊴사 | 끊김 3바퀴(wall 50초 안) 뒤 정상 1바퀴 | «keeper 바퀴» 꽉 참 알림 0통 · wall 61초인 바퀴 1개를 넣으면 꽉 참 1통 · 다음 정상 바퀴에 풀림 1통 | ROUND-CAP 마다 꽉 참 |
| ㊴아 | Slack 수신기 쪽에서 full_alert.remaining 을 «보내는 손» 없이 부름 | 지금과 같음(`_send` 7초 2회 · 실패 = jsonl 1줄) | — |
| ㊷가 = F1 | 동결 F1(DA 311870): `alert_out` = [A, B] · A 는 매번 7초 시간 초과 · B 는 바로 rc 0 | 1바퀴 = A 시도 1(tries 1 · 목록 [B, A]) · B 시작 0 / 2바퀴 = B 발신 1 + FULL-ALERT 1줄 · 이어 A 시도(tries 2) / 3바퀴 = A tries 3 → 지움 + `판정 불가 꽉 참 알림 3회 실패` 1줄 + jsonl 1줄 · B 발신이 0 인 채 도는 일 0 · 바퀴마다 wall ≤ 60 | r3 계약 = 네 바퀴 모두 A 만 시도 · B 영구 발신 0 |
| ㊷나 = F2 | 동결 F2: A 가 7초 시간 초과(rc None) · 그 글은 우편함 장부에 경계보다 큰 seq 로 닿아 있음 / 갈래 2 = 시도 바로 뒤에는 없고 다음 바퀴 앞에 닿아 있음 | 갈래 1 = 그 자리에서 성공 처리(지움 + `FULL-ALERT … (도착 확인 · rc None)`) · tries 0 / 갈래 2 = 1바퀴 tries 1 + `mark` · 2바퀴 다시 시도하기 앞 도착 확인 → 성공 처리 · mbox send 호출 수 = 1(다시 보내기 0) | — |
| ㊷다 = F3 | 동결 F3: report 구획 머리에서 남은 몫 5초(문이 쓰기 7초를 시작 0) · `alert_out` 2줄 | mbox send 호출 0 · 두 줄 tries 0 그대로 · 순서 그대로 · `mark` 빈 값 · 다음 바퀴(남은 몫 10초)에 첫 줄부터 시도 | — |
| ㊷라 = F4 | 동결 F4: ㊷가의 1바퀴 뒤(목록 [B, A] · A tries 1 · `mark` 있음) state.json 을 저장하고 keeper 객체를 새로 만듦 | 새 keeper 의 첫 바퀴 = B 부터 시도 · A tries 1 · `mark` 그대로(0 으로 돌아가지 않는다 · 순서가 [A, B] 로 돌아가지 않는다) | — |
| ㊷마 = F5 | 동결 F5: `alert_out` = [A, B, C] · 받는 곳 셋 모두 매번 7초 시간 초과 · 도착 확인 0 | 바퀴마다 시도 1개 · wall ≤ 60 · 9바퀴 안에 세 줄 모두 tries 3 → `판정 불가 꽉 참 알림 3회 실패` 3줄 + jsonl 3줄 · FULL-ALERT 0줄 · 그 뒤 `alert_out` 빈 목록 · mbox send 호출 합 = 9 | — |

동결 반례와 칸의 대응(r4 · FROZEN.md): F1~F5 = ㊷가~마(새 5칸) · F6(DA HOLD 1/3 BYZ 311663 반례) = ㊳가~너 가운데 r2 가 고친 칸 그대로 유지 · F7(DA HOLD 2/3 BYZ 311745 반례) = ㊴가(wall 62초 · 문 0회) 유지 — 기대의 끝 구절 1곳만 ①안에 맞춰 고쳤다(wall ≤ 60 · 바퀴 안 full_alert 바깥 호출 0 은 그대로).

범위 밖 입력(하드 룰 18·19·20): 줄바꿈·탭 든 파일 이름 · 권한 바꾼 상태 파일 · 주입한 git·tmux 실패의 꼴 맞추기 · 쓰기 호출이 자기 상한 7초를 넘겨 죽지 않는 경우(subprocess 상한 밖).

## 구현 범위 (나노 1 · 팩 base origin/main 최신 · r4 = 오빠 결정 뒤 · 설계 DA 0 · 구현 DA 는 동결 반례로만)
1. 커밋 1 [test] — 새 시험 feature-pack/fable-team/ft2/tests/test_keeper_round_60s.py(㊳가~너 · ㊴가~아 · ㊷가~마 · 변이 M72~M84 · M94~M97) · 기준판 FAIL 원문을 PR 본문에 붙인다 · 사례 1개 70초 안 · ㊳파는 순서마다 사례를 나눈다
2. 커밋 2 [fix] — R1~R13 = feature-pack/fable-team/ft2/adapters/pi/keeper.py(`call` 호출 문 · 판독 목록 · 예산 시계 · 끊김 예외 · cursor · `_round`·`team_round` 순환 · `git` 상한 · ROUND 줄 · `fa` 에 자기 손 · «keeper 바퀴» 관측 자리) + feature-pack/fable-team/ft2/adapters/pi/keeper_report.py(R8 · report 구획 · `rep_cursor` · `alert_out` 보내기 = 수신자 순환·tries·`mark`) + feature-pack/fable-team/ft2/adapters/pi/full_alert.py(«보내는 손» 인자 1칸 · 기본값 = 지금 동작) · 판정 규칙 손 0 · 다른 keeper_*.py 손 0 · adapters/slack 손 0
3. 커밋 3 [docs] — CONTRACT.md «바퀴 예산» 절(구획 숫자 · 호출 문 · cursor · 원자 구간 표) · CASES.md ㊳ 행
4. 회귀 rc0(파일별 · 각 70초 상한): test_full_critical_alert_r1886 · test_pi_keeper_slow_call_r1992 · test_pi_keeper_b3_one_list_r1898 · test_pi_keeper_b2_split_cache_r1969 · test_pi_keeper_r1817 · test_keeper_notify_recipient · test_pi_keeper_next_card_r1871 · test_settle_one_path_r2055 · test_penalty_team_no_new_pick · test_new_card_hold · test_pi_keeper_fetch_fresh_r1963 · ★더한 3묶음(팀장 aifp 5866 · 이 카드가 keeper.py 를 고쳐 앞 카드 시험이 같이 닿는다): test_prereq_unreadable_once · test_prereq_alarm_hold 4파일(본 · _mutants · _compat · _compat_b) · test_done_seat_short_idle 3파일(본 · _mutants · _mutants_b)★
5. 실행 = `python3.11 -m pytest` · 착지 = PR 1개(팀장 집행)

변이: M72 판독 호출 상한을 남은 몫으로 줄이지 않음 → ㊳가·㊳타 / M73 쓰기 문(남은 몫 7초) 빼기 → ㊳아 / M74 cursor 를 팀만 기억 → ㊳나·㊳사 / M75 2회 끊김 건너뜀 빼기 → ㊳하 / M76 git 상한 25 그대로 → ㊳바 / M77 send 미룸 빼기 → ㊳마 / M78 끊김을 Exception 으로 → ㊳거 / M79 report 를 구획 밖에서 → ㊳너 / M80 keeper 의 `fa` 를 옛 `_send` 로 되돌림 → ㊴가·㊴바 / M81 `alert_out` 을 결과와 무관하게 지움 → ㊴나·㊴다 / M82 쓰기 몫을 7초 고정으로 → ㊴라 / M83 판독 목록 밖을 판독으로 → ㊴마 / M84 «keeper 바퀴» 관측을 ROUND-CAP 자리에 그대로 → ㊴사 / M94(r4) 미완료 줄을 목록 뒤로 옮기지 않음 → ㊷가·㊷라 / M95 시간 초과를 tries 에 세지 않음 → ㊷가·㊷마 / M96 시작 0 인 예산 미룸에 tries +1 → ㊷다 / M97 `mark` 도착 확인 없이 다시 보냄 → ㊷나

## 범위 밖
- mbox.sh send 가 7초에 끊기는 까닭(우편함 잠금·가드) — 다른 도구 · 새 카드 감
- 긴 쓰기 3줄의 상한 25초 줄이기 · 재배정 launch 를 기다리지 않게 바꾸기 — 이 카드는 문에서 시작 조건만 건다 · 새 카드 감
- Slack 수신기 쪽 full_alert 호출(wiring.py · receive.py) — 다른 프로세스 · 동작 그대로
- keeper 가 바퀴 도중 죽어 state.json 을 못 쓴 경우의 `alert_out`(그 바퀴의 다른 지문·영수도 같이 잃는 지금 경계 그대로)
- gh pr list · git fetch 의 네트워크 속도 · 리포 크기 줄이기
- launchd 주기(60초) 바꾸기 · keeper 를 팀마다 따로 돌리기
- 판정 규칙·쪽지 글

## 완료 조건
1. [x] 나노: 커밋 1 기준판 FAIL 원문 — 기준판(98b561f1) 새 시험 48 failed(나노 aifp 5861 · PR #1397 본문 «기준판 48 failed») = 수는 있다 · ★FAILED 줄·단언 원문은 PR 본문에도 쪽지에도 없다 = 나노가 닫기 앞에 원문 몇 줄을 보태면 [x]★ · DA 는 기준판 대조를 r1886 c7 한 칸만 했다(baseline-c7.log) · ★보탬(나노 aifp 5901 · 2026-11-16 · 아래 «조건 1 원문» 절) = 기준판 98b561f1 에서 새 시험 49 failed in 3.74s · FAILED 줄 원문 10 → [x]★
2. [x] 나노: 새 시험 전체 rc0 · 걸린 초 — head 9fc8b9ab · test_keeper_round_60s.py 49 passed rc 0(지정 31 + 환경 격리 1 + 변이 17) · 나노 = 깨끗한 셸 4.27초 · 팀장과 같은 셸 4.28초(aifp 5890 · 3번 더 돌려 같음) · DA 재실행 49 passed 5.10초(.fable-team/state/team-main/aifp-ft/DA-round-60s-impl-approve-313228/specified.log · 판정문 «지정 49개 6.112초») · ★앞 head ec5409dc 의 48 passed 3.71초는 나노의 미커밋 수정이 든 실행이었다 = 9fc8b9ab 가 그 수정(cursor 칸 이어받기)을 커밋하고 test_env_isolated 1칸을 더했다★
3. [x] 나노: 변이별 지정 반례 FAIL(설계가 정한 M72~ 전부) — M72~M84 · M94~M97 17개 모두 검출(나노 aifp 5861 17/17 · DA .fable-team/state/team-main/aifp-ft/DA-round-60s-impl-approve-313228/mutation-audit.json 17줄 = AssertionError 13 · DID NOT RAISE 3 · KeyError 1(M80 = alert_out 없음) · 판정문 «syntax/import 오류 때문에 거짓 통과한 사례 0»)
4. [x] 나노: 회귀 rc0(파일별 초) — 나노 실행(aifp 5890 · head 9fc8b9ab): r1817 22(32.7초) · r1992 10(5.3) · r1898 10(6.9) · r1969 9(15.2) · notify 25(18.2) · next_card 17 + 9(40.4 + 38.3 · 통째 86초라 둘로 나눠 돎) · settle 29(51.0) · penalty 16(30.2) · hold 9(19.3) · fetch 19(31.6) · 더한 3묶음 = prereq_unreadable_once 15 + 6(43.6 + 29.7 · 70초를 넘어 둘로 나눠 돎) · prereq_alarm_hold 18(36.0) · _mutants 7(15.9) · _compat 1(33.6) · _compat_b 1(10.9) · done_seat_short_idle 27(56.2) · _mutants 5(23.7) · _mutants_b 5(31.9) · DA 재실행(.fable-team/state/team-main/aifp-ft/DA-round-60s-impl-approve-313228/regressions.json · targeted.json): r1992 10 passed 14.566초 · r1969 9 passed 20.891초 · r1898 10 passed 14.95초 · done_seat ㉙도 1 passed · settle ⑦·㉕다 2 passed · r1817 2 passed · ★알려진 한계: test_full_critical_alert_r1886 은 4 passed 뒤 c7(test_c7_journal_refused_then_release) 1 failed = rc 1 · 기준판 98b561f1 에서도 같은 단언으로 Red(baseline-c7.log) = DA «신규 회귀로 세지 않는다» · 이 카드 범위 밖 후속 감 · DA 는 «기존 회귀 전체 통과» 를 주장하지 않았다(직접 돌린 범위만)★ · 기존 시험 7파일 보정 = DA «기존 의미 단언을 삭제하여 통과시킨 변경은 찾지 못했다»
5. [~] 팀장: PR 착지 sha · 설치 판 — 착지 = PR #1397 squash d261be1a1e504d5ecc649473510a7efab3e28a6d(head 9fc8b9ab91a4e3ce565d12ebe075ac6dbdef489d · gh pr view 로 대조 · MERGED 2026-11-15T23:58:37Z = 08:58:37 KST · 커밋 4 = ff10f3bc 시험 · 27062d69 고침 · ec5409dc 문서 · 9fc8b9ab ㊳파 고침 · 바뀐 파일 13 = keeper.py · keeper_report.py · full_alert.py · CONTRACT.md · CASES.md · 새 시험 1 · 기존 시험 7) · 설치 = 아직(지금 ft2 CURRENT 2.0.75 = install-log 08:37:38 KST 로 착지보다 앞 판 · harness 설치 요청 BYZ 313289 회신 뒤 이 칸에 판·시각 1줄)
6. [ ] arch: 설치 뒤 읽기 실측 = BYZ keeper 로그 ROUND 줄 200줄 이상에서 wall 60초 넘음 0 · `other=` 의 p50·가장 긴 값(5초 넘으면 [ ] = 가정 A1 깨짐) · FULL-ALERT 줄 수와 `alert_out` 에 2바퀴 넘게 남은 줄 0 · 단계별 초 표(p50 · p90 · 가장 긴 값)를 기준값 표와 나란히 · ROUND-CAP·판정 불가(git 7초)·NOTIFY-DEFER 줄 수 · 60초를 넘은 줄이 1개라도 있으면 원문과 함께 [ ] 로 둔다(빼고 통과 0) · ★r4 성립 여부: «`alert_out` 에 2바퀴 넘게 남은 줄 0» 은 받는 곳이 2곳인 꼴(F1)과 실패 없는 날에는 ①안으로 그대로 성립한다(끊긴 줄이 뒤로 가서 다른 받는 곳이 다음 바퀴에 나간다) · 끊기는 받는 곳이 있으면 그 줄은 실제 시도 3회까지 남고, 받는 곳이 n곳이면 tries 0 줄의 첫 시도가 n바퀴까지 밀릴 수 있다 → 실측은 «넣은 뒤 첫 시도까지 그때 목록의 받는 곳 수 바퀴 안» + «tries ≥ 1 줄은 `판정 불가 꽉 참 알림 3회 실패` 줄로 끝남(줄 수·원문)» 으로 읽는다(2바퀴 숫자를 늘린 것이 아니라 끊긴 줄을 따로 센다)★ — 대기(설치 뒤 잰다 · aifp-ft-arch-pi#23 2026-11-16 09:01)
7. [ ] arch: 굶음 0 = 같은 구간의 ROUND `cut=` 칸에서 같은 자리가 3바퀴 연속 나온 적 0 · `예산 2회 넘음` 줄 수와 그 자리 원문 · `items=` 의 p50(㊳사·㊳하의 실 runtime 판) — 대기(설치 뒤 잰다)
8. [x] 나노: ㊳파 끊김 수렴 표 = 순서 5개 × 끊은 자리 수 · 수렴 못 한 순서 이름(없으면 «없음») · 원자 구간으로 선언한 것의 쓰기 호출 수 — 순서 5개(닫기 probe → kill-session → receipt · 깨움 capture-pane → send-keys · 재배정 launch → record · 쉼 park → released · fill pick → submit → assign) × 끊은 자리 3 + 2 + 2 + 2 + 3 = 12칸이 모두 통과했다(c_pa1~5 · DA 49 passed 안) = 칸마다 «같은 일 집합 · 뒤 바퀴 4번 안 · ft2-keeper 쪽지 1통» 단언 · 수렴 못 한 순서 = 없음 · ★칸별 바퀴 수 표와 «원자 구간으로 선언한 것의 쓰기 호출 수» 는 어디에도 적히지 않았다(시험이 표를 만들지만 찍지 않는다) = 나노가 닫기 앞에 표 1개를 보태면 [x]★ · ★보탬(나노 aifp 5901 · 아래 «조건 8 원문» 절) = 칸별 바퀴 수 12칸 모두 2바퀴 · 수렴 못 한 순서 = 없음 · 원자 구간으로 선언한 것 0개(쓰기 호출 수 0) = 조건 문구의 세 항목(순서 5개 × 끊은 자리 수 · 수렴 못 한 순서 이름 · 원자 구간 쓰기 호출 수)이 모두 있다 → [x]★
9. [x] 나노: ㊴바 AST 셈 원문(기다리는 바깥 호출 1줄 · Popen 2줄) + 문 안 판독 목록 원문 — 시험 c_s6 통과(DA 49 passed 안) · AST 셈 원문(aifp-ft-arch-pi#23 읽기 · 팩 main f88a39f6 · 같은 걷기): 기다리는 바깥 호출 = `{"full_alert.py": [15], "keeper.py": [128]}`(keeper.py 문 1줄 · full_alert.py 는 Slack 수신기 기본 손) · Popen = `{"keeper_fetch.py": [74], "keeper_launch.py": [43]}` 2줄 · 판독 목록 원문(keeper.py :28~29 · `reading` :84): `READ_GIT = ("rev-parse", "merge-base", "grep", "ls-tree", "ls-remote", "fetch", "log", "show", "cat-file", "cherry", "rev-list", "status")` + `config --get` = git 13 · `READ_TMUX = ("has-session", "display", "display-message", "capture-pane", "list-sessions")` 5 · gh pr list · ps · mbox peek · 벌점 판정기 check

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
| R11 그대로 | ㊳자 · ㊳카 · ㊴아 |
| R2 쓰기 몫 = 자기 상한 · 판독 목록 | ㊴라 · ㊴마 · M82 · M83 |
| R4 `rep_cursor` | ㊳너 |
| R12 꽉 참 알림 | ㊴가 · ㊴나 · ㊴다 · ㊴사 · M80 · M81 · M84 |
| R12 보내기 = 수신자 순환(r4 · F1~F5) | ㊷가 · ㊷나 · ㊷다 · ㊷라 · ㊷마 · M94 · M95 · M96 · M97 |
| R13 문 밖 바깥 호출 0 | ㊴바 · M80 |

## 상태
- base_sha: a065424f23ae6235b78ae657f647360abd61b2f8
- 2026-11-16 05:06 · 대기 — aifp-ft-arch-pi#20 초안(팀장 aifp 5704 · 실측 = BYZ keeper 로그 ROUND 210줄 · 구현 0) · 다음 = 팀장 PR → DA 설계 → Issue → 나노 1석
- 2026-11-16 05:22 · aifp-ft-arch-pi#20 r2(팀장 aifp 5726 · DA HOLD-DESIGN 1/3 BYZ 311663 · 사본 .fable-team/state/team-main/aifp-ft/DA-round-design-hold-311663/verdict.md) — 고친 것: 호출마다 남은 몫을 보는 호출 문(R2) · 구획 숫자 45·10·5(R1) · 팀·work·칸 cursor(R4) · 2회 끊김 건너뜀(R5) · 끊김 수렴과 원자 구간(R9) · «열기를 기다린다» 전제 정정(설계 확정 2) · «모든 팀 3바퀴» 를 2N 바퀴 순환으로(㊳사) · 반례 11 → 16 · 오빠 결정 0
- 2026-11-16 05:38 · aifp-ft-arch-pi#21 r3(팀장 aifp 5743 · DA HOLD-DESIGN 2/3 BYZ 311745 · 사본 .fable-team/state/team-main/aifp-ft/DA-round-design-hold2-311745/verdict.md) — 고친 것: 바깥 호출 전수 19줄(우회 3줄 · 기다리는 것 1줄 = full_alert) · 꽉 참 알림을 넣어 두었다가 report 구획에서 문으로(R12) · 문 밖 바깥 호출 0 을 AST 시험으로(R13) · 쓰기 = 판독 목록 밖 전부 · 몫 = 자기 상한(긴 쓰기 25초 3줄) · report 의 `rep_cursor` · 프로세스 안 초는 가정 A1 로 내림 · 시간 입력을 복합 호출로 정의 · 반례 16 → 24 · 변이 8 → 13 · 코드 2 → 3파일 · 오빠 결정 0
- 2026-11-16 07:36 · aifp-ft-arch-pi#22 r4(팀장 aifp 5852 · DA HOLD-DESIGN 3/3 BYZ 311870 뒤 오빠 결정 «1» = 수신자 순환 · 동결 .fable-team/state/team-main/aifp-ft/keeper-round-60s-decision/FROZEN.md) — 고친 것: R12 보내기 줄(미완료 줄은 그 받는 곳째 목록 뒤 · 시간 초과도 tries · E7 도착 = 성공 · `mark` 로 다시 보내기 앞 도착 확인 · 예산 미룸만 0회 · 3회 뒤 판정 불가) · 반례 표에 F1~F5 = ㊷가~마 · ㊴가 기대 끝 구절 1곳 · 변이 M94~M97 · 완료 조건 6 성립 여부 1줄 · 기준값에 89/60초(BYZ 312444) 1줄 · 설계 확정 5 · 반례 24 → 29 · 변이 13 → 17 · 그 밖 계약(R1~R11 · R13) 손 0 · 새 설계 범위 0
- 2026-11-16 07:41 — 대기→진행 · 좌석 aifp-ft-nano-ft2-keeper-round-60s#0
- [배정 불명] 불명(scope 표 없음 opengateway/deepseek/deepseek-v4.1-flash-ultrafast)
- 2026-11-16 · 나노 구현 r1(aifp-ft-nano-ft2-keeper-round-60s#0 · 브랜치 nano/ft2-keeper-round-60s · push 안 함 · 커밋 3개 ff10f3bc [test] → 27062d69 [fix] → ec5409dc [docs]) — R1~R13 구현(구획 45·55·60초 · Keeper.call 문 · cursor/rep_cursor · 나노 7초 · git 7초 · 쪽지 미룸 · ROUND wall/other/items/cut · 꽉 참 손 = alert_out + report 머리 1줄 1회 수신자 순환) · 새 시험 48 사례(㊳가~너 · ㊳파 5순서 수렴 · ㊴가~바 · ㊷가~마 · 변이 M72~M84·M94~M97) 기준판 48 failed → rc0 · 계약 §13·CASES 행 · 회귀 11파일 rc0(단 r1886 c7 은 앞 판에서도 Red = cache 없이 followup.gate 판정 불가 · 이 카드 범위 밖)
  - 세트: ec5409dc3c7b88df2db8928b86c1efa7ebd1dedd · 시험: python3.11 -m pytest tests/test_keeper_round_60s.py (48 passed in 3.71s) rc=0 · 이슈: 0
- 2026-11-16 · 나노 ㊳파 고침(aifp 5890) — 커밋 9fc8b9ab 1개 더(force 0) · 원인 = 기준판 FAIL 을 보려고 adapters 를 98b561f1 로 checkout 했다가 되돌리면서 커밋 안 한 one_work 수정(cursor 칸 이어받기)이 지워졌다 · 고침 = R4 이어받기 복원 + 쪽지 몫(notify_used · send_fails · send_stop)은 바퀴 끝에서 되돌림 + 새 사례 test_env_isolated · 기존 시험 보정 1건 더 = done_seat_short_idle ㉙도(keeper 꽉 참 알림이 자기 mbox 로 실제 나감)
- 2026-11-16 09:01 · aifp-ft-arch-pi#23 착지 줄 씀(팀장 aifp 5896) · 조건 2·3·4·9 [x] · 조건 1·8 [~] = 나노 원문·표 보탬 대기 · 조건 5 [~] = 착지 sha 있음 · 설치 회신 대기(BYZ 313289) · 조건 6·7 = 설치 뒤 · 구현 범위 4 에 회귀 3묶음 더함(팀장 aifp 5866) · 나노가 루트에 썼던 증거 줄 2개를 위에 옮김(.fable-team/state/team-main/aifp-ft/handover-tmp/ft2-keeper-round-60s-nano-evidence.diff) · 코드 변경 0
- DA 판정: APPROVE-IMPL 313228(승인 sha 9fc8b9ab91a4e3ce565d12ebe075ac6dbdef489d · 사본 .fable-team/state/team-main/aifp-ft/DA-round-60s-impl-approve-313228/verdict.md · 동결 FROZEN.md F1~F7 로만 검토 · 설계 재론 0 · 동결 범위 신규 동작 반례 0 · 지정 31 + 환경 격리 1 + 변이 17 = 49 PASS · r1992 10 · r1969 9 · r1898 10 PASS · r1886 c7 은 기준판 98b561f1 과 같은 실패 · 검증 경계 = 주입 시계·가짜 subprocess · 실 tmux·실 발신·실 설치 0 = 설치 뒤 실제 wall ≤ 60초 증거를 대신하지 않는다) · 설계 = HOLD-DESIGN 3/3 BYZ 311870 뒤 오빠 결정 ① 로 동결
- 2026-11-16 09:05 · aifp-ft-arch-pi#23 조건 1·8 [~] → [x](팀장 aifp 5904) · 나노 보탬 원문(aifp 5901 · .fable-team/comm/bodies/5901.txt)을 아래에 글자 그대로 옮김(요약·고침 0) · 조건 5·6·7 그대로(설치 = harness#296 aifp 5902 · 2.0.76 precheck ABORT → DA 판정 대기) · 코드 변경 0
  - 조건 1 원문(나노 aifp 5901 ①):
    ```
    ① 조건 1 = 기준판 98b561f1 에서 새 시험 49 failed in 3.74s (git worktree add --detach /tmp/kr60base 98b561f1 → 지금 가지의 시험 파일만 그 worktree 로 복사 → pytest · 쓰고 worktree prune 으로 걷음 · 지금 가지 파일 덮어쓰기 0) FAILED 줄 원문 10:
    FAILED tests/test_keeper_round_60s.py::test_case[㊳가] - FileNotFoundError
    FAILED tests/test_keeper_round_60s.py::test_case[㊳나] - FileNotFoundError
    FAILED tests/test_keeper_round_60s.py::test_case[㊳다] - AssertionError
    FAILED tests/test_keeper_round_60s.py::test_case[㊳라] - FileNotFoundError
    FAILED tests/test_keeper_round_60s.py::test_case[㊳마] - AttributeError
    FAILED tests/test_keeper_round_60s.py::test_case[㊳바] - Failed: DID NOT RAISE
    FAILED tests/test_keeper_round_60s.py::test_case[㊳사] - FileNotFoundError
    FAILED tests/test_keeper_round_60s.py::test_case[㊳타] - FileNotFoundError
    FAILED tests/test_keeper_round_60s.py::test_case[㊳파-닫기]
    FAILED tests/test_keeper_round_60s.py::test_case[㊴가] - AttributeError
    (49 전부 FAILED · 위는 앞 10줄 · 뒤에는 ㊳하·거·너 · ㊴나·다·라·마·바·사 · ㊷가~마 · 변이 M72~M84·M94~M97)
    ```
  - 조건 8 원문(나노 aifp 5901 ②):
    ```
    ② 조건 8 = ㊳파 12칸(순서 5 × 끊은 자리) 칸별 바퀴 수 — 시험 모듈의 converge() 가 만든 값을 그대로 찍었다(시험 파일 수정 0 · 70초 안 1.2초):
    닫기(probe·kill-session·receipt) 3칸 = cut0 2바퀴 / cut1 2바퀴 / cut2 2바퀴
    깨움(capture-pane·send-keys) 2칸 = cut0 2바퀴 / cut1 2바퀴
    재배정(launch·record) 2칸 = cut0 2바퀴 / cut1 2바퀴
    쉼(park·released) 2칸 = cut0 2바퀴 / cut1 2바퀴
    fill(pick·submit·assign) 3칸 = cut0 2바퀴 / cut1 2바퀴 / cut2 2바퀴
    합 12칸 · 수렴 못 한 순서 = 없음 · 원자 구간으로 선언한 것 = 0개(쓰기 호출 수 0) — 어느 호출 앞에서 끊겨도 «끊긴 바퀴 1 + 이어서 끝내는 바퀴 1» 로 같은 끝(같은 일 집합 · 쪽지 1통)에 닿는다
    ```
- 세트 정정(나노 aifp 5890 · 팀장 aifp 5896): 위 세트 줄의 ec5409dc 는 ㊳파 고침 앞 head 다 · PR #1397 head 와 DA 승인 sha 는 9fc8b9ab 이다(뒤 커밋 1개 = 9fc8b9ab 고침) · 닫기 도구가 읽는 세트 = 맨 끝 줄
- 세트: 9fc8b9ab91a4e3ce565d12ebe075ac6dbdef489d · 시험: python3.11 -m pytest feature-pack/fable-team/ft2/tests/test_keeper_round_60s.py (49 passed 5.10초) rc=0 · 이슈: 0
