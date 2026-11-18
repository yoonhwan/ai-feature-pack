# 인덱스: ft2-keeper-nano-cut-blank-cell — 끝: 나노 가지 모으기가 7초에 끊겨도 ROUND 의 cut 칸에 빈 자리 이름(`-:-:-`)이 찍히지 않는다 · cut 칸은 업무 구획이 실제로 끊긴 자리만 말한다
<!-- ledger: feature-pack/fable-team/legacy/1.x/harness/design/harness/GOAL-harness.md -->
- Issue: 없음(초안) — 설치 뒤 실측 aifp 6067(진행/ft2-keeper-round-60s 조건 7 [ ]) · 팀장 aifp-ft-master-pi#24 발주 aifp 6068 ㉡ · 앞 인계서 «볼 것» 8(11-16 09:15:47 `-:-:-` 1줄)
- 제안서: 없음 — keeper 1곳 고침 · 설계 = 이 카드 «계약»
- 근거: 실측 2026-11-18 12:55(aifp-ft-arch-pi#24 · BYZ .fable-team/state/ft2-keeper/2026111[78].jsonl · 11-17 14:50:06 ~ 11-18 12:55:39 ROUND 1012줄 · 읽기만 · 셈 = .fable-team/state/team-main/aifp-ft/A24-keeper-measure/) + 코드 읽기(팩 origin/main 14d7677f · feature-pack/fable-team/ft2/adapters/pi/keeper.py) — 아래 «읽은 것» 절
- 원인 1줄: 나노 가지 모으기(keeper.py :471~478) 동안에는 `left()` 가 나노 7초 끝(`nano_dl`)까지만 남은 몫으로 준다(:203~204) · 그 몫이 다하면 `call` 이 :126 · :130 에서 `raise self.cut_at()` 을 던지고, `cut_at`(:208~213)은 던지기 앞에 `self.cut_pos` 와 `self.cut` 을 쓴다 · 이때는 팀 밖이라 `self.at` = None · `at_work` = `-` · 칸 = `-` → `self.cut = "-:-:-"` · :476 `except Cut:` 은 `nano_cut = True` 만 하고 그 두 값을 되돌리지 않는다 → 업무 구획이 끝까지 돌아도 ROUND 는 `cut=-:-:-` 이고 :522 `if self.cut == "-"` 가 거짓이라 cursor 도 지워지지 않는다
- 앞 카드: 진행/ft2-keeper-round-60s(PR #1397 · R3·R4 끊긴 자리 · R6 나노 7초 · R10 ROUND cut 칸)
- 상태: 대기
- 설치: 있음 — ft2 판 올림 1회 · 되돌림 = 앞 판으로 판 전환(상태 파일·설정 변화 0)
- 선행: 없음(팩 origin/main 14d7677f) · 대기/ft2-keeper-ungraded-team-rest 와 같은 파일의 다른 줄(순서 무관 · 뒤에 착지하는 쪽이 rebase)
- 시험 입력: 60초 카드 시험 대역 그대로(임시 루트 · 주입 시계 · 가짜 subprocess.run · 실 runtime 0 · 네트워크 0 · sleep 0 · 사례 1개 70초 안)
- 기준값: 22시간 ROUND 1012줄 가운데 `cut=-:-:-` 37줄 · 37줄 모두 그 바퀴에 «판정 불가 나노 가지 모으기 7초 넘음 — 모은 것만» 이 있고 ROUND-CAP 줄은 0 · 같은 값 3바퀴 연속 3번(11-18 11:23 ~ 12:23) → 목표 = `cut=-:-:-` 0줄
- 규칙: 없음 — 상시 로드 변경 0
- 규칙 상세: 하드 룰 20 · 22
- 대상: 팩 feature-pack/fable-team/ft2/adapters/pi/keeper.py(:476 `except Cut:` 갈래 1곳) · feature-pack/fable-team/ft2/tests/test_keeper_round_60s.py 또는 새 시험 1파일 · CASES.md 1줄
- 정본 영향 없음: aifp 정본 변경 0 · ft2 CONTRACT.md 변경 0(R10 «cut = 끊긴 자리» 글에 코드를 맞춘다)
- 크기: 코드 1파일 1~2줄 · 시험 1파일 · PR 1개
- 배정: 대기(DA · 2026-11-18T13:01)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
6 — 하네스 운영 정리. 하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」. 골의 축: 6(keeper ROUND 줄이 거짓 끊김을 말하지 않아야 굶음을 그 줄로 읽을 수 있다). 이 카드의 증거 = 착지 sha + 시험 rc0 + 설치 뒤 keeper 로그 `cut=-:-:-` 0줄.

## 배경 (한 단락)
keeper ROUND 줄의 cut 칸은 «예산이 다해 업무 구획이 끊긴 자리(팀:work:칸)» 를 적는다. 60초 카드 조건 7 은 이 칸에서 같은 자리가 3바퀴 연속 나오면 굶음으로 읽는다. 그런데 바퀴 맨 앞의 나노 가지 모으기가 7초에 끊길 때도 같은 변수에 값이 쓰이고, 그 뒤 아무도 지우지 않는다. 팀 밖에서 난 일이라 자리 이름이 전부 빈 값(`-:-:-`)이다. 원격이 느린 시간대에는 이 값이 바퀴마다 찍혀 «같은 자리 3바퀴 연속» 으로 보인다. 실제 굶음과 가릴 수 없다. cursor 도 지워지지 않아 옛 자리가 남는다.

## 읽은 것 (2026-11-18 · 읽기만)
| # | 무엇 | 원문 |
|---|---|---|
| 가 | keeper.py :199~206 `left` | `end = self.start + self.sect` / `if self.nano_dl is not None:` / `end = min(end, self.nano_dl)` / `return end - time.monotonic()` |
| 나 | :123~130 `call` 문 | `left = None if self.in_fetch else self.left()` / `if left < MIN_S:` / `raise self.cut_at()` … `elif left < timeout or (…):   # R2 쓰기 = 시작 0` / `raise self.cut_at()` |
| 다 | :208~213 `cut_at` | `stage = "report" if self.sect != WORK_S else self.cursor_stage if self.cursor_stage != "-" else (self.stage or "-")` / `self.cut_pos = (self.at or "-", self.at_work or "-", stage)` / `self.cut = ":".join(self.cut_pos)` / `return Cut(self.cut)` |
| 라 | :471~480 나노 모으기 | `self.nano_dl = at + NANO_S` / `try:` / `for team in ([] if self.table else self.teams()):` / `got.update(kf.nanos(self, [team]))` / `except Cut:` / `nano_cut = True` / `self.nano, self.nano_s, self.nano_dl = (…), time.monotonic() - at, None` / `if nano_cut or self.nano_s >= NANO_S:` / `self.log("판정 불가", text="나노 가지 모으기 7초 넘음 — 모은 것만")` |
| 마 | :522~523 · :541 | `if self.cut == "-":` / `self.state.pop("cursor", None)` · `cells += " wall=%g other=%g items=%d/%d cut=%s" % (…, self.cut)` |
| 바 | 셈(22시간 ROUND 1012줄) | `cut=-:-:-` 37줄 = 그 바퀴에 «나노 가지 모으기 7초 넘음» 있음 37 · 없음 0 · 그 37바퀴의 ROUND-CAP 줄 0 · «나노 가지 모으기 7초 넘음» 이 있는데 `cut=-:-:-` 가 아닌 바퀴 15(끊김 없이 7초를 채운 꼴 `self.nano_s >= NANO_S`) |
| 사 | 로그 원문 | `15:04:23 판정 불가 나노 가지 모으기 7초 넘음 — 모은 것만` → … → `ROUND … nano=6.2 wall=32 other=1.9 items=2/2 cut=-:-:- slow=-` · 3바퀴 연속 = `11:23:08 … items=2/2 cut=-:-:- slow=- OVER` · `11:24:51 … items=2/2 cut=-:-:- slow=-` · `11:26:09 … items=4/4 cut=-:-:- slow=v65:b2f:1.7 unknown=1` |

## 계약
- N1 나노 가지 모으기에서 난 `Cut` 은 ROUND cut 칸 · cursor 에 흔적을 남기지 않는다 = :476 갈래를 나올 때 `self.cut` 은 `-`(`cut_pos` 는 계약·시험 대상이 아니다 = 읽는 곳이 `mark_cut` 하나이고 그 앞에서 늘 새로 쓰인다 · None 으로 같이 돌려도 된다)
- N2 «판정 불가 나노 가지 모으기 7초 넘음 — 모은 것만» 1줄 · ROUND `nano=` 칸 · 모은 것만 쓰는 동작(부분 손실 0)은 그대로다
- N3 나노가 끊긴 바퀴에서 그 뒤 업무 구획이 실제로 끊기면 cut 칸 · ROUND-CAP · cursor 는 그 실제 자리다(나노 흔적이 덮지도 섞이지도 않는다)
- N4 나노가 끊긴 바퀴가 업무 구획을 끝까지 돌면 :522 가 cursor 를 지운다(앞 바퀴 cursor 가 있었으면 지금 규칙대로 그 자리부터 돌고 끝까지 갔을 때 지운다)
- N5 손 0: `cut_at` 의 자리 셈 · `mark_cut` · report 구획 · fetch 구간 · keeper_fetch.py · NANO_S 값

## 반례 표 (주입 시계 · 가짜 subprocess)
| # | 입력 | 기대 | 지금 |
|---|---|---|---|
| 53가 | 나노 모으기 중 남은 몫이 다함(팀 2개 · 첫 팀 판독 뒤 주입 시계 +7) · 업무 구획은 끝까지 돎 | 판정 불가 1줄(나노) · ROUND `cut=-` · ROUND-CAP 0줄 · state 에 cursor 없음 | `cut=-:-:-` · cursor 가 있었으면 남음 |
| 53나 | 53가 를 3바퀴 연속 | 세 줄 모두 `cut=-` | `cut=-:-:-` 3바퀴 연속 |
| 53다 | 53가 + 업무 구획에서 팀 b 의 b2f 가 예산 끊김 | `cut=b:-:b2f` · ROUND-CAP 1줄(b) · cursor = b 자리 | 같은 값(뒤 끊김이 덮는다) = 고친 뒤에도 같아야 한다 |
| 53라 | 앞 바퀴 cursor = (b, w1, b1) · 이번 바퀴 나노 끊김 · 업무 구획은 b 부터 끝까지 돎 | cursor 지워짐 · `cut=-` | cursor 남음 · `cut=-:-:-` |
| 53마 | 나노가 끊김 없이 7초를 채움(`nano_s >= NANO_S`) | 지금 그대로 = 판정 불가 1줄 · `cut=-` | 같음 |
| 53바 | 나노 끊김 없음 | ROUND 줄 · 판정 줄이 고치기 앞 판과 바이트 같음 | 같음 |

변이: M133 :476 갈래에서 되돌리지 않음(지금 판) → 53가·53나·53라 / M134 되돌림을 :476 갈래가 아니라 ROUND 줄(:541) 바로 앞에서만 함 → 53라(:522 가 먼저 돌아 cursor 가 남는다) / M135 업무 구획 끝에서 `cut` 을 무조건 `-` 로 → 53다 / M136 나노 판정 불가 줄을 지움 → 53가(N2)

## 구현 범위 (나노 1 · 팩 base origin/main 최신 · DA 설계 승인 뒤)
1. 커밋 1 [test] — 53가~바 · 변이 M133~M136 · 기준판 FAIL 원문(53가 · 53나 · 53라)
2. 커밋 2 [fix] — keeper.py N1 · CASES.md 1줄
3. 회귀 = test_keeper_round_60s.py · test_keeper_round_cells.py · test_pi_keeper_lsremote_once_r1963b.py(파일별 초) · 실행 = `python3.11 -m pytest`(ft-test-slot) · git stash 쓰지 않는다 · 착지 = 카드 docs PR(세트 줄) 먼저 → 코드 PR(팀장 집행)

## 범위 밖
- 나노 가지 모으기가 왜 7초를 넘는지 · 11-18 11시대 fetch_root 18초 바퀴(원격이 느린 까닭) = 따로 본다.
- 팀 자리 git 7초 넘음에서 뒤 팀이 빠지는 것 = 대기/ft2-keeper-ungraded-team-rest.
- 60초 넘은 바퀴 1줄 · other 5초 넘음 = 진행/ft2-keeper-round-60s 조건 6 에 남는다.

## 완료 조건
1. [ ] 나노: 기준판 FAIL 원문(53가 · 53나 · 53라)
2. [ ] 나노: 새 시험 전체 rc0 · 걸린 초 · 변이 M133~M136 지정 반례 FAIL
3. [ ] 나노: 회귀 rc0(파일별 초)
4. [ ] 팀장: PR 착지 sha · 설치 판
5. [ ] arch: 설치 뒤 읽기 실측 = BYZ keeper 로그 ROUND 200줄 이상(양 끝 시각)에서 `cut=-:-:-` 0줄 · 그 구간의 «나노 가지 모으기 7초 넘음» 줄 수(0 이면 줄 수가 찰 때까지 [~] = 끊긴 바퀴가 있어야 본 것이다)와 그 바퀴 ROUND 원문 2줄
6. [ ] arch: 다시 재는 순서 = 이 카드와 대기/ft2-keeper-ungraded-team-rest 가 모두 설치된 뒤 ROUND 200줄에서 진행/ft2-keeper-round-60s 조건 7(같은 자리 3바퀴 연속 0 · 예산 2회 넘음 줄 · items p50)을 다시 잰다 · 조건 6(other 5초 · 60초 넘음)은 두 카드로 줄지 않으므로 같은 구간 값만 나란히 적는다

## 계약↔시험 대응표
| 계약 | 시험 |
|---|---|
| N1 흔적 0 | 53가 · 53나 · M133 · M134 |
| N2 나노 줄 그대로 | 53가 · 53마 · M136 |
| N3 실제 끊김 그대로 | 53다 · M135 |
| N4 cursor | 53라 |
| N5 그대로 | 53바 |

## 상태
- 2026-11-18 13:01 · 대기 — aifp-ft-arch-pi#24 초안(팀장 aifp 6068 ㉡ · 실측 aifp 6067 · 읽기만 · 시험·코드 손 0) · 원인 = 나노 모으기 Cut 이 cut_at 으로 `self.cut` 을 쓰고 :476 이 되돌리지 않음(37줄 전부 나노 7초 바퀴) · 다음 = 팀장 PR merge → DA 설계 → Issue → 나노 1석
- 2026-11-18 13:42 · 대기 — aifp-ft-arch-pi#25 보정(DA 설계 B HOLD 1/3 aifp 6075 · 팀장 발주 aifp 6080) · N1 = «:476 갈래를 나올 때 self.cut = -» 로 줄임(cut_pos 는 계약·시험 대상 아님) · M134 = «되돌림을 ROUND 줄 바로 앞에서만» 으로 바꿈 · 다른 칸 손 0 · 다음 = 팀장 DA 설계 2/3
