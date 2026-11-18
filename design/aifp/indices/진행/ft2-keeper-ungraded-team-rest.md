# 인덱스: ft2-keeper-ungraded-team-rest — 끝: 한 팀의 팀 자리(work 밖)에서 git 이 7초를 넘어도 그 바퀴의 뒤 팀이 그대로 돈다 · 끊기지 않은 바퀴(cut=-)의 ROUND items 가 N/N 이다
<!-- ledger: feature-pack/fable-team/legacy/1.x/harness/design/harness/GOAL-harness.md -->
- Issue: #9321 — 설치 뒤 실측 aifp 6067(진행/ft2-keeper-round-cells-b1-items 조건 6 [ ]) · 팀장 aifp-ft-master-pi#24 발주 aifp 6068 ㉠
- 제안서: 없음 — keeper 1곳 고침 · 설계 = 이 카드 «계약»
- 근거: 실측 2026-11-18 12:55(aifp-ft-arch-pi#24 · BYZ .fable-team/state/ft2-keeper/2026111[78].jsonl · 11-17 14:50:06 ~ 11-18 12:55:39 ROUND 1012줄 · 읽기만 · 셈 = .fable-team/state/team-main/aifp-ft/A24-keeper-measure/) + 코드 읽기(팩 origin/main 14d7677f · feature-pack/fable-team/ft2/adapters/pi/keeper.py) — 아래 «읽은 것» 절
- 원인 1줄: keeper.py :147~149 가 로컬 git 7초 넘음에 `Ungraded` 를 던진다 · work 안에서 난 것은 :587 이 받아 «다음 자리» 로 간다 · 팀 자리(`at_work` = `-` · 예: b2f 의 merge-base · ls-tree)에서 난 것은 받는 곳이 팀 고리(:502 `for team in self.order[skip:]`) 밖의 :520 `except Ungraded: pass` 하나뿐이다 → 그 팀의 남은 자리뿐 아니라 뒤 팀 전부와 b3 가 이 바퀴에서 돌지 않는다 · `self.cut` 은 `-` 그대로라 :522 가 cursor 를 지우고 ROUND 는 `cut=-` 인데 items 가 N/N 이 아니다(:520 주석 «그 자리 남은 판정 0 · 다음 자리» 와 동작이 다르다)
- 앞 카드: 진행/ft2-keeper-round-60s(PR #1397 · R7 git 7초 · R10 items) · 진행/ft2-keeper-round-cells-b1-items(PR #1513 · items 분모)
- 상태: 대기
- 착지: 49d6b45a(팩 main · PR #1600 · squash · 세트 6838b985d77df655ece8659a874fc0190eaef81a · 팀장 재실행 25 passed 15.1s)
- DA 판정: APPROVE-IMPL 1/3 aifp 6100(da-pi#20 · 승인 6838b985 · 사본 .fable-team/state/team-main/aifp-ft/DA-ungraded-team-rest-impl-approve/verdict-6100.txt · 메모 = 변이 판정 except BaseException · git_no_lazy_fetch 시험 46~61초)
- DA 판정: APPROVE-DESIGN 2/3 aifp 6084(사본 .fable-team/state/team-main/aifp-ft/DA-ungraded-team-rest-design-approve/verdict-6084.txt) · 승인 sha 6048e40b · 앞 반례 사라짐 · 새 반례 0 · 메모 1개 = 52바 를 무는 변이(M137) 반영(구현 승인 아님)
- 설치: 있음 — ft2 판 올림 1회 · 되돌림 = 앞 판으로 판 전환(상태 파일·설정 변화 0)
- 선행: 없음(팩 origin/main 14d7677f) · 대기/ft2-keeper-nano-cut-blank-cell 과 같은 파일(keeper.py)의 다른 줄(순서 무관 · 뒤에 착지하는 쪽이 rebase)
- 시험 입력: 60초 카드 시험 대역 그대로(임시 루트 · 주입 시계 · 가짜 subprocess.run · 실 runtime 0 · 네트워크 0 · sleep 0 · 사례 1개 70초 안)
- 기준값: 22시간 ROUND 1012줄 가운데 끊기지 않은 줄(cut=-) 910 · 그중 items 가 N/N 이 아닌 줄 24 = 모두 그 바퀴 안에 «판정 불가 <팀> - git 7초 넘음» 이 있다 · 그 꼴의 판정 불가 줄 27(work 이름이 붙은 것 11은 :587 이 받아 문제없음) → 목표 = 그 꼴 바퀴에서도 뒤 팀이 돌고 cut=- 줄의 items 는 N/N
- 규칙: 없음 — 상시 로드 변경 0
- 규칙 상세: 하드 룰 12 · 20 · 22
- 대상: 팩 feature-pack/fable-team/ft2/adapters/pi/keeper.py(바퀴 팀 고리 :502~506 근처 1곳) · feature-pack/fable-team/ft2/tests/test_keeper_round_60s.py 또는 새 시험 1파일 · CASES.md 1줄
- 정본 영향 없음: aifp 정본 변경 0 · ft2 CONTRACT.md 의 R7 글(«그 자리 남은 판정 0 · 다음 자리»)은 그대로 = 코드를 글에 맞춘다
- 크기: 코드 1파일 3줄 안팎 · 시험 1파일 · PR 1개
- 배정: 좌석 aifp-ft-nano-ft2-keeper-ungraded-team-rest#0

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
6 — 하네스 운영 정리. 하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」. 골의 축: 6(keeper 한 바퀴가 한 팀의 느린 git 때문에 뒤 팀을 굶기지 않는다). 이 카드의 증거 = 착지 sha + 시험 rc0 + 설치 뒤 keeper 로그에서 cut=- 줄의 items N/N.

## 배경 (한 단락)
keeper 는 한 바퀴에 팀을 이름순으로 돈다. 로컬 git 호출이 7초를 넘으면 «판정 불가» 1줄을 쓰고 그 자리의 남은 판정만 건너뛰는 것이 60초 카드의 계약(R7)이다. work 안에서는 그렇게 동작한다. 그런데 work 밖 팀 자리(빈 칸 채우기 등)에서 7초를 넘으면 예외를 받는 곳이 팀 고리 밖이라, 이름순으로 뒤에 있는 팀이 그 바퀴에서 전부 빠진다. 끊긴 자리도 남지 않아 다음 바퀴는 처음부터 다시 돈다. 같은 팀의 git 이 계속 느리면 뒤 팀은 계속 밀린다. ROUND 줄은 `cut=-`(끊김 없음)로 찍혀 이 상태가 보이지 않는다.

## 읽은 것 (2026-11-18 · 읽기만)
| # | 무엇 | 원문 |
|---|---|---|
| 가 | keeper.py :147~149 | `raise self.cut_at()   # R2 남은 몫으로 줄인 상한에 걸림 …` · `if over and read and self.git_call(argv) and not self.in_fetch:` · `raise self.ungraded()   # R7 로컬 git 7초 넘음 = 판정 불가 1줄 · 성공으로도 실패로도 읽지 않는다` |
| 나 | :194~197 `ungraded` | `self.log("판정 불가", self.at or "-", "%s git %g초 넘음" % (self.at_work or "-", GIT_S))` → `return Ungraded()` |
| 다 | :585~589 work 갈래 | `close = self.one_work(…)` / `except Ungraded:` / `self.left_over(team, work)   # R7 git 7초 = 그 자리 남은 판정 0 · 다음 자리` / `continue` |
| 라 | :501~521 바퀴 팀 고리 | `try:` / `for team in self.order[skip:]:` … `self.team_round(team)` … b3 … / `except Cut: self.mark_cut()` / `except Ungraded:` / `pass   # R7 판정 불가 = 그 자리 남은 판정 0 · 다음 자리(이미 판정 줄을 썼다)` |
| 마 | :522~523 | `if self.cut == "-":   # R4 — 끊기지 않고 바퀴를 다 돌았으면 cursor 를 지운다` / `self.state.pop("cursor", None)` |
| 바 | 로그 2바퀴 원문 | `16:01:45 SLOW-CALL harness b2f git BYZ-Agents merge-base s=7 rc=None try=1/1` → `16:01:45 판정 불가 harness - git 7초 넘음` → `ROUND s=27.6 fetch=3.5 b1=4.8 b2c=0 b2f=13.3 b3=0 stall=0.3 … wall=31.2 other=3.6 items=11/39 cut=- slow=harness:b2f:11.5 unknown=6` · `15:03:11 SLOW-CALL cfo b2f git . ls-tree s=7 rc=None try=1/1` → `15:03:11 판정 불가 cfo - git 7초 넘음` → `ROUND … items=2/49 cut=-:-:- …` |
| 사 | 셈 | cut=- 910줄 가운데 N/N 아닌 줄 24 · 24줄 모두 그 바퀴에 «git 7초 넘음» · 시각 분포 11-17 16시 4 · 19시 1 · 21시 3 · 22시 3 · 23시 5 · 11-18 05시 2 · 06시 1 · 12시 3 |

## 계약
- T1 팀 자리에서 난 `Ungraded` 는 그 팀의 남은 자리만 끝낸다 · 팀 고리는 다음 팀으로 간다 · b3(고아 · 옛 좌석) 구간도 그대로 돈다
- T2 팀 자리 `Ungraded` 의 원천은 b2f(빈 칸 채우기) 뿐이다(실측 49/49 · b2f 는 그 팀의 마지막 자리이고 `at_pos("b2f")` 가 fill 앞에서 seen 에 넣는다) → 그 팀에 남은 자리 0 · 분모 손 0 · 뒤 팀과 b3 자리는 돌아서 끊기지 않은 바퀴의 items 는 N/N(구현 범위 1 실측에서 b2f 밖 칸이 나오면 그때 «안 돈 자리를 분모에서 뺀다» 계약과 변이 M130 을 되살린다) · «판정 불가 <팀> - git 7초 넘음» 줄은 지금처럼 1줄(더 쓰지 않는다)
- T3 `Cut`(예산 끊김) 갈래 · cursor 규칙(R3~R5) · work 갈래(:587) · fetch 구간 · report 구획은 손 0 · 같은 팀이 다음 바퀴에 또 7초를 넘어도 «예산 2회 넘음» 셈에 넣지 않는다(끊긴 자리가 아니다)
- T4 b3 구간(`self.at` = None): b3o 의 `Ungraded` 는 b3o 만 끝낸다 · b3r 는 돈다 · b3r 의 `Ungraded` = 바퀴 업무 끝(뒤에 자리가 없다) · 실측 = «판정 불가 - - git 7초 넘음» 꼴 0줄(49줄 모두 팀 이름 있음 · DA aifp 6071) → T4 는 시험 1칸만
- T5 손 0: keeper_*.py 다른 모듈 · SLOW-CALL · 판정 불가 줄 꼴 · GIT_S 값

## 반례 표 (주입 시계 · 가짜 subprocess)
| # | 입력 | 기대 | 지금 |
|---|---|---|---|
| 52가 | 팀 3개(a · b · c) · a 의 b2f(빈 칸 채우기) git 판독 1회가 7초 넘음 | 판정 불가 1줄(`a - git 7초 넘음`) · b · c 의 자리가 모두 돈다 · ROUND `cut=-` · items N/N | b · c 0자리 · `cut=-` · items 가 N/N 아님 |
| 52나 | 52가 + 같은 바퀴에서 c 의 work 안 git 도 7초 넘음 | 판정 불가 2줄 · c 의 다음 work 는 돈다(지금 :587 동작 그대로) | a 에서 끝나 c 에 닿지 않음 |
| 52다 | 52가 를 2바퀴 연속 | 두 바퀴 모두 b · c 가 돈다 · «예산 2회 넘음» 0줄 · ROUND-CAP 0줄 · cursor 없음 | 두 바퀴 모두 b · c 0 |
| 52라 | a 의 팀 자리에서 예산 끊김(Cut · 남은 몫 < 1초) | 지금 그대로 = ROUND-CAP 1줄 · `cut=a:-:<칸>` · cursor 남음 · b · c 0 | 같음 |
| 52마 | 7초 넘음 없음 | ROUND 줄 · 판정 줄이 고치기 앞 판과 바이트 같음 | 같음 |
| 52바 | b3o 에서 git 7초 넘음 | b3r 가 돈다(T4) | b3r 0 |

변이(M130 은 뺐다 = b2f 원천에서는 등가 변이 · DA aifp 6071): M129 받는 곳을 팀 고리 밖에 그대로 둠 → 52가·52다 / M131 `Ungraded` 를 `Cut` 처럼 다뤄 cursor 를 남김 → 52다 / M132 `Cut` 까지 삼켜 뒤 팀을 돎 → 52라 / M137 b3o 갈래의 `Ungraded` 를 받는 곳을 뺌(팀 고리만 고침) → 52바

## 구현 범위 (나노 1 · 팩 base origin/main 최신 · DA 설계 승인 뒤)
1. 먼저 잰다(고침 0): BYZ keeper 로그에서 «판정 불가 - - git 7초 넘음» 꼴 줄 수(T4) · 팀 자리 Ungraded 가 난 칸 분포(b2f · stall · b1) 1줄
2. 커밋 1 [test] — 52가~바 · 변이 M129 · M131 · M132 · M137 · 기준판 FAIL 원문(52가 · 52나 · 52다)
3. 커밋 2 [fix] — keeper.py T1 · T2 · CASES.md 1줄
4. 회귀 = test_keeper_round_60s.py · test_keeper_round_cells.py · test_keeper_git_no_lazy_fetch.py(파일별 초) · 실행 = `python3.11 -m pytest`(ft-test-slot) · git stash 쓰지 않는다 · 착지 = 카드 docs PR(세트 줄) 먼저 → 코드 PR(팀장 집행)

## 범위 밖
- `report()` 는 `except Cut` 만 받는다 → report 안에서 난 `Ungraded` 는 `_round` 밖으로 샌다(실측 0줄) = 이 카드에서 고치지 않는다.
- git 이 왜 7초를 넘는지(merge-base · ls-tree 가 느린 까닭) = 따로 본다.
- ROUND `cut=-:-:-` 빈 자리 이름 = 대기/ft2-keeper-nano-cut-blank-cell.
- other 5초 넘음 · 60초 넘은 바퀴 1줄(11-18 11:23:08 · b3 38.2초 · fetch 18.4초) = 이 카드로 줄지 않는다(진행/ft2-keeper-round-60s 조건 6 에 남는다).

## 완료 조건
1. [x] 나노: 구현 범위 1 의 잰 값 1줄
2. [x] 나노: 기준판 FAIL 원문(52가 · 52나 · 52다)
3. [x] 나노: 새 시험 전체 rc0 · 걸린 초(사례 1개 70초 안 · 하드 룰 22) · 변이 M129 · M131 · M132 · M137 지정 반례 FAIL
4. [x] 나노: 회귀 rc0(파일별 초)
5. [ ] 팀장: PR 착지 sha · 설치 판
6. [ ] arch: 설치 뒤 읽기 실측 = BYZ keeper 로그 ROUND 200줄 이상(양 끝 시각)에서 cut=- 줄의 items 가 모두 N/N · «판정 불가 <팀> - git 7초 넘음» 이 있는 바퀴 수와 그 바퀴의 items 원문 2줄 · 아닌 줄이 있으면 원문과 함께 [ ]
7. [ ] arch: 다시 재는 순서 = 이 카드 설치 뒤 ROUND 50줄에서 진행/ft2-keeper-round-cells-b1-items 조건 6 을 다시 잰다(그 카드의 남은 칸은 이것 하나) · 진행/ft2-keeper-round-60s 조건 7 은 대기/ft2-keeper-nano-cut-blank-cell 까지 설치된 뒤 ROUND 200줄에서 다시 잰다

## 계약↔시험 대응표
| 계약 | 시험 |
|---|---|
| T1 뒤 팀이 돈다 | 52가 · 52나 · 52다 · M129 |
| T2 남은 자리 0 · 분모 손 0 | 52가(items N/N) |
| T3 Cut·cursor 그대로 | 52다 · 52라 · 52마 · M131 · M132 |
| T4 b3 | 52바 · M137 |

## 상태
- base_sha: 1ff2c25cc29049e7a942dcd7237b94688d6c3174 (spawn 2026-11-18)
- 2026-11-18 13:01 · 대기 — aifp-ft-arch-pi#24 초안(팀장 aifp 6068 ㉠ · 실측 aifp 6067 · 읽기만 · 시험·코드 손 0) · 원인 = 팀 자리 Ungraded 를 받는 곳이 팀 고리 밖(:520) · 다음 = 팀장 PR merge → DA 설계 → Issue → 나노 1석
- 2026-11-18 13:42 · 대기 — aifp-ft-arch-pi#25 보정(DA 설계 A HOLD 1/3 aifp 6071 · 팀장 발주 aifp 6072 + 덧 6074) · T2 를 «원천 = b2f 뿐 → 남은 자리 0 · 분모 손 0» 으로 줄임 · M130 뺌 · T4 문장 고침 · report() 안 Ungraded = 범위 밖 1줄 · T1 · T3 · M131 · M132 손 0 · 다음 = 팀장 DA 설계 2/3
- 2026-11-18 13:46 · 대기 — aifp-ft-arch-pi#25 머리 줄(팀장 aifp 6085) · Issue #9321 · DA 판정 APPROVE-DESIGN 2/3 aifp 6084 · 배정 = 대기(석) · DA 메모 반영 = M137(b3o 갈래 받는 곳 뺌 → 52바) · 완료 조건 3 에 70초 안 · 선행 줄에 rebase 1줄 · 다음 = 팀장 착지 → 나노 1석
- 2026-11-18 13:47 — 대기→진행 · 좌석 aifp-ft-nano-ft2-keeper-ungraded-team-rest#0
- 2026-11-18 13:52 · 완료(나노) — 잰 값 = BYZ keeper 로그 20261117+20261118 16138줄(2026-11-17T00:00:03 ~ 2026-11-18T13:48:22 · 읽기만) · T4 «판정 불가 - - git 7초 넘음» 0줄 · 팀 자리 Ungraded(`판정 불가 <팀> - git 7초 넘음`) 49줄 = 칸 분포 b2f 49 · stall 0 · b1 0 · 그 바퀴 ROUND 49줄 중 items N/N 0줄(34줄 cut=- 에 items=2/1525 꼴 · 15줄 cut=-:-:-) — b2f 가 팀 마지막 자리라 Ungraded 가 팀 고리 밖(:520)까지 올라가 뒤 팀·b3 를 모두 굶긴다
- 2026-11-18 13:52 · 기준판 FAIL 원문(고치기 앞 keeper.py · 팩 origin/main 14d7677f · 같은 대역) — 52가: 판정 불가 1줄 · ROUND items=3/16 cut=- · b·c land 0 / 52나: 판정 불가 1줄(a 것)뿐이라 c 에 닿지 않음 · items=3/16 cut=- / 52다: 2바퀴 모두 b·c land 0 / 52바: b3r retired 0 · 52라·52마 = 기준판 PASS(그대로 지킨다)
- 2026-11-18 13:52 · 고침 = keeper.py `_round` 팀 고리 안에서 `except Ungraded: continue`(그 팀만 0 · 뒤 팀은 돈다 · Cut 은 BaseException 이라 안 삼킴) · b3o 갈래 `except Ungraded: pass`(b3r 은 돈다) · 범위 밖 손 0 · 변이 M129·M131·M132·M137 을 지정 반례가 잡음
- 2026-11-18 13:52 · 시험 = 새 파일 `test_keeper_ungraded_team_rest.py`(52가~바 6칸 + 변이 4) 10 passed 2초 · 회귀 rc0(60s 49 passed 12초 · cells 15 passed 7초 · git_no_lazy_fetch 26 passed 70초) · 재진입 lint OK rc=0 · ruff 통과
- 세트: 6838b985d77df655ece8659a874fc0190eaef81a · 시험: python3.11 -m pytest feature-pack/fable-team/ft2/tests/test_keeper_ungraded_team_rest.py -q (10 passed) rc=0 · 이슈: 0
