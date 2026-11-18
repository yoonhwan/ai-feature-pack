# 인덱스: ft2-keeper-round-cells-b1-items — 끝: ft2 keeper ROUND 줄의 `b1=` 칸이 착지 판정(landing)에 쓴 초를 다시 담는다 · `other=` 는 칸 밖 초만 보인다 · `items=` 의 분모는 그 바퀴에 돌 수 있는 자리 수다(끊기지 않은 바퀴는 N/N · 이미 처리한 work 를 세지 않는다)
<!-- ledger: feature-pack/fable-team/legacy/1.x/harness/design/harness/GOAL-harness.md -->
- Issue: #8676 (byz-agents · 등록 aifp-ft-master-pi#23 BYZ 313531 · DA APPROVE-DESIGN 313472) — 팀장 aifp-ft-master-pi#23 발주 aifp 5919(진행/ft2-keeper-round-60s 조건 6·7 1차 읽기 aifp 5918 의 후속 조사)
- 제안서: 없음 — 결함 복구(ROUND 줄 칸 2개의 셈) · 설계 = 이 카드 «계약»·«반례 표»
- 근거: 읽기 조사 2026-11-16 09:16(aifp-ft-arch-pi#23 · 설치본 ft2 2.0.76 · BYZ .fable-team/state/ft2-keeper/20261116.jsonl · 팩 origin/main e95184f0 · 읽기만) — 아래 «조사 결과» 절
- 원인 1줄: keeper 60초 카드(PR #1397 · d261be1a)가 바퀴 고리를 `team_round` → `one_work` 로 옮기면서 `self.landing(team, work)` 를 `self.timed("b1", …)` 밖에서 부르게 됐다(앞 판은 `self.timed("b1", self.landing, team, work)`) → 착지 판정의 git 초가 `b1=` 에서 빠져 `other=` 로 간다 · `items=` 분모는 `positions()` 가 journal 의 모든 dispatch work 를 세는데 고리는 처리 끝난 work(`handled` · 반환 · 쉼)를 자리 진입 없이 건너뛴다
- 앞 카드: 진행/ft2-keeper-round-60s(R10 ROUND 칸 · 가정 A1 · 완료 조건 6·7) · r1817(단계별 초) · r1969(slow 칸)
- 상태: 대기
- 착지: cf2a00ec(팩 main · PR #1513 · squash · 승인 head 4ca226e14922d58e580f490b1b7e0e27f4fbfc1b · 팀장 재실행 round_cells+round_60s 64 passed 11.2s)
- DA 판정: APPROVE-IMPL 3/3 BYZ 326406(aifp 6035 · 앞 HOLD 1/3 326273 · 2/3 326352 · 사본 .fable-team/state/team-main/aifp-ft/DA-round-cells-impl-approve-326406/verdict.md · 알려진 한계 = b2_split_cache_r1969 ② main 같은 1 failed)
- 설치: 있음 — ft2 판 올림 1회 · 되돌림 = 앞 판으로 판 전환(상태 파일·설정 변화 0)
- 선행: 없음(팩 origin/main e95184f0)
- 시험 입력: 임시 루트(tmp_path) · 시험 안에서 만든 journal·카드 · 가짜 tmux·가짜 mbox·가짜 git(걸린 초를 가짜 시계로 더함) · 주입 시계 · sleep 0 · 네트워크 0 · 실 runtime 0 · test_keeper_round_60s.py 의 Rig 을 그대로 쓴다 · 사례 1개 70초 안
- 기준값: 설치 뒤 ROUND 4줄(09:10:56~09:15:47) 모두 `b1=0` · `other=` 7 · 10 · 16.2 · 10.3초 · `items=` 55/1197 · 56/1201 · 33/1201 · 24/1213 → 목표 = 착지 판정이 돈 바퀴의 `b1=` 이 0 이 아님 · 끊기지 않은 바퀴의 `items=` 가 N/N
- 규칙: 없음 — 상시 로드 변경 0
- 규칙 상세: 하드 룰 22
- 대상: 팩 feature-pack/fable-team/ft2/adapters/pi/keeper.py(`one_work` 의 landing 호출 1줄 · 분모 셈 2줄) · 새 시험 feature-pack/fable-team/ft2/tests/test_keeper_round_cells.py
- 정본 영향 없음: aifp 정본 변경 0 · 팩 ft2 계약 문서도 변경 0 — CONTRACT.md §13 R10 은 이미 `items=<돈 자리>/<돈 수 있는 자리>` 라고 적혀 있다(구현이 그 글과 다르다) · «옛 칸·순서 그대로» 도 60초 카드 R10 글 그대로다
- 크기: 코드 1파일(5줄 안팎) · 새 시험 1파일 · PR 1개
- 배정: 좌석 aifp-ft-nano-ft2-keeper-round-cells-b1-items#0

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
6 — 하네스 운영 정리. 하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」. 골의 축: 6(keeper 한 바퀴가 어디에 초를 썼는지 ROUND 줄이 바르게 보인다). 이 카드의 증거 = 착지 sha + 시험 rc0 + 설치 뒤 ROUND 줄의 `b1=` · `other=` · `items=` 원문.

## 배경 (한 단락)
keeper 60초 카드는 «`other=` 의 가장 긴 값이 5초를 넘으면 가정 A1(프로세스 안 초는 문이 끊지 못한다)이 깨진 것» 으로 읽기로 했다. 설치 뒤 첫 4바퀴의 `other=` 는 7~16초였다. 조사해 보니 그 초는 프로세스 안 초가 아니다. 착지 판정(카드 본문 `git show` · 조상 확인)이 쓰는 바깥 호출 초다. 그 호출은 지금도 호출 문(`Keeper.call`)을 지나고 예산 시계에 잡힌다. 다만 `b1=` 칸에 더해지지 않아 `other=` 로 보인다. 그래서 지금의 `other=` 로는 A1 을 판정할 수 없다. `items=` 분모도 같은 PR 에서 계약 글(돈 수 있는 자리)과 다르게 구현됐다. 이 카드는 그 두 셈만 바로잡는다. 판정·예산·끊김 규칙은 건드리지 않는다.

## 조사 결과 (2026-11-16 09:16 · 읽기만)
| # | 무엇 | 원문 |
|---|---|---|
| 가 | 지금 판(팩 main e95184f0 = 설치본 2.0.76) keeper.py | :540 `landed = self.landing(team, work)`(timed 밖) · :543 `if self.timed("b1", self.complete, team, work, attempt, landed):` · :461 `wall = max(time.monotonic() - self.start, s)` · :468 `other=%g` = `max(wall - s, 0.0)` · `s` = `sum(self.spent.values()) + self.nano_s` |
| 나 | 앞 판(d261be1a^) keeper.py | :310 `landed = self.timed("b1", self.landing, team, work)` · :313 `if row.get("done") or self.timed("b1", self.complete, team, work, attempt, landed):` |
| 다 | 설치 앞 판 ROUND 끝 100줄(06:45:32~09:09:42) | `b1=` p50 6.9초 · p90 12.0초 · 가장 긴 값 26.0초 |
| 라 | 설치 뒤 ROUND 4줄 | `09:10:56 … b1=0 … wall=13.8 other=7 items=55/1197 cut=-` · `09:12:16 … b1=0 … wall=19.5 other=10 items=56/1201 cut=-` · `09:14:05 … b1=0 … wall=44 other=16.2 items=33/1201 cut=harness:r2093-keeper-skip-shell-card-hold:stall` · `09:15:47 … b1=0 … wall=41 other=10.3 items=24/1213 cut=-:-:-` |
| 마 | 분모 셈 | keeper.py :193 `positions()` = 팀마다 `works_of(team)`(journal 의 dispatch work 전부) × (b1 · b2c · stall) + 팀 수(b2f) + 2(b3o · b3r) · :431 · :467 `self.total = len(self.positions()) - len(self.unused)` · 고리 :506 은 `handled` · 반환 · 쉼인 work 를 `continue` 로 건너뛴다(`at_pos` 0 · `unused` 에도 안 넣음) |
| 바 | BYZ journal 셈(설치본 2.0.76 의 projection 으로 읽기 · 0.12초 · journal 5597줄) | 팀 14 · dispatch work 399(harness 342) → 자리 = 3 × 399 + 14 + 2 = 1213 · 고리가 건너뛰지 않는 work = 23(harness 18 · room 2 · chatbot 1 · lecture 1 · planner 1) |

읽은 뜻:
- `other=` 7~16초의 이름 = `one_work` 의 `self.landing(team, work)`(keeper_land.py 착지 판정 · 바깥 호출은 git). 앞 판 `b1=` p50 6.9초와 새 판 `b1=0` · `other=` 7~10초가 맞물린다. 프로세스 안 초의 한 예인 journal 전부 읽기는 0.12초다.
- `items=` 분모 1197~1213 = 처리 끝난 work 376개의 자리 1128개가 든 수다. 굶음이 아니다. 끊기지 않은 두 바퀴의 분자 55 · 56 은 건너뛰지 않는 work 23개(work 마다 1~2자리 = b1 과 stall, 또는 b2c)에 팀 14 · b3 2 를 더한 크기다. 건너뛰지 않는 work 도 세 자리(b1 · b2c · stall)를 다 가지 않으므로, 처리 끝난 work 만 빼서는 N/N 이 되지 않는다(23 × 3 + 16 = 85).
- `other=` 에는 landing 말고도 칸 밖 초가 더 있다(팀마다 `project` · `land_ready` · `endings.ending` · `report()` · 소켓 확인 · fetch 대상 읽기). 그 몫은 이 카드 착지 뒤 `other=` 를 다시 재야 보인다.
- 볼 것 1개(이 카드 범위 밖 · 원문만): 09:15:47 줄의 `cut=-:-:-` 는 자리 이름이 빈 끊김이다. CONTRACT §13 은 report 끊김을 `<팀> <work>` 자리로 적게 했다.

## 계약
- H1 `b1=` = 착지 판정 초 + complete 초 = 앞 판과 같다 · `one_work` 가 `self.timed("b1", self.landing, team, work)` 로 부른다 · landing 의 반환·예외(Cut · Ungraded)·호출 순서는 그대로다(`timed` 는 `try … finally` 로 초만 더한다)
- H2 `items=` 분모 = 그 바퀴에 돌 수 있는 자리 · 끊기지 않은 바퀴(`cut=-`)는 분모 = 분자 = `items=N/N`(다 돌았다는 뜻 그대로) · 끊긴 바퀴는 분모 = 분자 + 끊긴 자리 뒤에 남은 자리 수 · 남은 자리 = `positions()` 에서 끊긴 자리 뒤의 것 가운데 고리가 건너뛰는 work(`handled` 에 있는 최신 attempt · 반환 · 쉼 = :506 의 조건과 같은 식)의 자리와 `unused` 를 뺀 것 · 아직 가지 않은 work 는 b1 · b2c · stall 세 자리로 센다(어느 자리로 갈지는 가 봐야 안다 = 끊긴 바퀴의 분모는 위쪽 어림이다)
- 알려진 한계(DA APPROVE-DESIGN 313472): 맨 끝 자리(b3r)에서 끊기면 뒤에 남은 자리가 0 이라 `items=5/5` 처럼 N/N 이 나온다(`cut=-:-:b3r`) = «끊긴 바퀴는 분자 < 분모» 는 맨 끝 자리에서 성립하지 않는다 · 다 돌았는지는 `cut=-` 와 함께 읽는다 · H1 뒤 landing 의 SLOW-CALL 단계 이름·SLOW-CELL 값은 b1 로 붙는다(H3 의 «그대로» 는 줄 꼴·호출 판단·예산 동작이다) · keeper 60초 카드 조건 6 의 other 5초 문구는 완화 0 = 이 카드 설치 뒤 ROUND 50줄 이상에서 다시 재서 그 기준 그대로 본다
- H3 그대로: `positions()` 의 반환값과 순서 · `key` · `before` · `cursor_key` · `next_pos`(끊김 자리·이어받기는 모든 자리 목록으로 센다) · 예산 시계 · 호출 문 · 끊김 · `wall=` · `cut=` · SLOW-CALL · SLOW-CELL · 판정 규칙 · report · 다른 keeper_*.py
- H4 `other=` 의 식은 그대로다(`wall − 칸 합계`) · H1 뒤에는 landing 초가 칸 합계에 들어가므로 그만큼 준다 · 이 카드는 `other=` 에 상한을 두지 않는다

## 반례 표 (가짜 시계 · Rig)
| # | 입력 | 기대 | 지금 |
|---|---|---|---|
| ㊻가 | work 1개 · 착지 판정의 git 호출이 6초(가짜 시계) · complete 0초 | ROUND `b1=6` · `other=0` · `wall=` 그대로 | `b1=0` · `other=6` |
| ㊻나 | work 3개 가운데 2개는 `handled` · 1개는 진행(닫지 않음) · 끊김 없음 | `items=N/N`(N = 돈 자리 수) · `cut=-` | 분모에 `handled` work 2개의 자리 6개와 진행 work 의 b2c 자리 1개가 더 들어감 |
| ㊻다 | work 2개 · 최신 attempt 가 반환 1 · 쉼 1(열기 실패 쉼 아님) · 끊김 없음 | `items=N/N` | 분모가 6 큼 |
| ㊻라 | 열기 실패 쉼(`LAUNCH_FAILED`)인 work 1개가 끊긴 자리 뒤에 있음 | 그 work 는 건너뛰지 않는다 = 남은 자리에 3개로 든다(지금 고리 규칙 그대로) | — |
| ㊻마 | 진행 work 2개 + `handled` work 1개 · 첫 진행 work 의 b1 에서 예산이 다해 끊김 | `cut=<팀>:<work>:b1` · `items=1/N` · N = 1 + 그 work 의 b2c · stall 2 + 둘째 진행 work 3 + 팀 b2f 1 + b3 2 = 9(`handled` work 의 자리 3개는 없다) · state 의 cursor 와 다음 바퀴 이어받기는 지금과 같다 | 분모 12 |
| ㊻아 | 진행 work 1개가 투영 done(b1 없이 닫기 자리로) · 끊김 없음 | `items=N/N` · `b1=0` | 분모에 그 work 의 b1 자리가 남음 |
| ㊻바 | landing 안에서 Cut 이 남(㊳가 꼴) | Cut 이 그대로 올라가고 그때까지의 초가 `b1=` 에 든다 · cursor 자리 = b1 | `b1=0` |
| ㊻사 | landing 이 Ungraded(git 7초 넘음 · ㊳바 꼴) | 그 자리 남은 판정 0 · 다음 자리 · «판정 불가» 줄 그대로 · 그 초가 `b1=` 에 든다 | `b1=0` |

범위 밖 입력(하드 룰 18·19·20): 줄바꿈·탭 든 work 이름 · 권한 바꾼 journal · 주입한 git 실패의 꼴 맞추기.

## 구현 범위 (나노 1 · 팩 base origin/main 최신 · DA 설계 승인 뒤)
1. 커밋 1 [test] — 새 시험 feature-pack/fable-team/ft2/tests/test_keeper_round_cells.py(㊻가~아 · 변이 M109~M112) · 기준판 FAIL 원문(㊻가 · ㊻나 · ㊻다 · ㊻마 · ㊻바 · ㊻사 · ㊻아)을 PR 본문에 붙인다
2. 커밋 2 [fix] — H1 · H2 = feature-pack/fable-team/ft2/adapters/pi/keeper.py(`one_work` 의 landing 호출 1줄 · 분모 셈 :431 · :467) · 다른 파일 손 0 · 문서 손 0
3. 회귀 rc0(파일별 · 각 70초 상한): test_keeper_round_60s · test_pi_keeper_r1817 · test_pi_keeper_slow_call_r1992 · test_pi_keeper_b2_split_cache_r1969 · test_pi_keeper_b3_one_list_r1898 · test_settle_one_path_r2055
4. 실행 = `python3.11 -m pytest` · 착지 = PR 1개(팀장 집행)

변이: M109 landing 을 `timed` 밖에서 부름(지금 판) → ㊻가·㊻바·㊻사 / M110 분모에서 건너뛰는 work 를 빼지 않음(지금 판) → ㊻나·㊻다 / M111 열기 실패 쉼도 분모에서 뺌 → ㊻라 / M112 끊기지 않은 바퀴의 분모를 자리 목록으로 셈(가지 않은 b2c · b1 이 남음) → ㊻나·㊻아

## 범위 밖
- `other=` 의 나머지 몫(project · land_ready · endings.ending · report · 소켓 확인)에 칸을 주는 일 = 이 카드 착지 뒤 `other=` 를 다시 재고 정한다.
- keeper 60초 카드 가정 A1 의 후속(동사에도 문을 두기) = 지금 실측으로는 A1 이 깨졌는지 판정할 수 없다. 이 카드 착지 뒤 값으로 다시 본다.
- keeper 60초 카드 완료 조건 6 의 `other=` 5초 문구를 닫힘 판정에 어떻게 쓸지 = 팀장·DA 몫.
- `cut=-:-:-` 꼴(조사 결과 볼 것) = 원인 조사 0. 새 카드 감.

## 완료 조건
1. [ ] 나노: 커밋 1 기준판 FAIL 원문(㊻가 · ㊻나 · ㊻다 · ㊻마 · ㊻바 · ㊻사 · ㊻아)
2. [ ] 나노: 새 시험 전체 rc0 · 걸린 초
3. [ ] 나노: 변이 M109~M112 지정 반례 FAIL
4. [ ] 나노: 회귀 rc0(파일별 초)
5. [ ] 팀장: PR 착지 sha · 설치 판
6. [ ] arch: 설치 뒤 읽기 실측 = BYZ keeper 로그 ROUND 50줄 이상(양 끝 시각)에서 `b1=` 이 0 이 아닌 줄 수와 p50 · `other=` 의 p50·가장 긴 값을 기준값(7 · 10 · 16.2 · 10.3초)과 나란히 · 끊기지 않은 줄(`cut=-`)의 `items=` 가 모두 N/N · 아닌 줄이 있으면 원문과 함께 [ ] 로 둔다 · ★설치 뒤 실측(읽기만 · aifp-ft-arch-pi#24 2026-11-18 12:57 · 팀장 aifp 6041 · 6066 · BYZ .fable-team/state/ft2-keeper/2026111[78].jsonl · 셈 스크립트·출력 = .fable-team/state/team-main/aifp-ft/A24-keeper-measure/) = [ ] 그대로: 끊기지 않은 줄(cut=-) 가운데 items 가 N/N 이 아닌 줄이 있다 · 창1 = 11-17 14:50:06(2.0.102 설치) ~ 17:22:03(2.0.103 설치 전) ROUND 114줄(14:51:11 ~ 17:21:10): b1 0 아님 108/114줄 · b1 p50 3.2초 · other p50 1.1 · 가장 긴 값 12.3초(기준값 7 · 10 · 16.2 · 10.3) · cut=- 107줄 가운데 N/N 103 · 아닌 줄 4 · 창2 = 11-17 14:50:06 ~ 11-18 12:55:39(판 2.0.102 ~ 2.0.116) ROUND 1012줄(14:51:11 ~ 12:55:04): b1 0 아님 954/1012줄 · b1 p50 1.6(0 아닌 것 1.8) · other p50 1.4 · 가장 긴 값 26.9초 · cut=- 910줄 가운데 N/N 886 · 아닌 줄 24 · 아닌 24줄은 모두 그 바퀴 안에 «판정 불가 <팀> - git 7초 넘음» 줄이 있다(팀 고리가 git 7초에 끊겼는데 cut 칸은 `-`) · 원문은 상태 절★

## 계약↔시험 대응표
| 계약 | 시험 |
|---|---|
| H1 b1 칸 | ㊻가 · ㊻바 · ㊻사 · M109 |
| H2 items 분모 | ㊻나 · ㊻다 · ㊻라 · ㊻마 · ㊻아 · M110 · M111 · M112 |
| H3 그대로 | ㊻마(cursor · 이어받기) · ㊻바 · ㊻사 · 회귀 6파일 |
| H4 other 식 | ㊻가 |

## 상태
- base_sha: 34f538264bdf1dd9f77ccb42b361e577b004f560 (spawn 2026-11-17)
- 2026-11-16 09:17 · 대기 — aifp-ft-arch-pi#23 초안(팀장 aifp 5919 · 읽기 조사 3회 · 구현 0) · 다음 = 팀장 PR merge → DA 설계 → Issue → 나노 1석
- 2026-11-16 09:26 · 대기 — aifp-ft-arch-pi#23 머리 줄(팀장 aifp 5923) · Issue #8676 · DA 판정: APPROVE-DESIGN 313472(승인 sha f7b0614e28a8ca4e8806b56d4e145dd45f94692f · 사본 .fable-team/state/team-main/aifp-ft/DA-round-cells-design-approve-313472/verdict.md · 수용 동작 반례 0 · 알려진 한계 1줄 계약에 보탬) · 배정 줄 꼴 고침(대기 · 정지 = BYZ 전팀 정지 판정 4244 ② · 팀장 aifp 5924) · 그 밖 손 0 · 다음 = 팀장 착지 → 인터뷰 뒤 나노 spawn
- 2026-11-17 14:13 — 대기→진행 · 좌석 aifp-ft-nano-ft2-keeper-round-cells-b1-items#0
- [배정 불명] 불명(scope 표 없음 opengateway/deepseek/deepseek-v4.1-flash-ultrafast)
- 2026-11-18 12:57 · 진행 — 조건 6 설치 뒤 실측 = [ ](aifp-ft-arch-pi#24 · 읽기만) · b1 · other 는 기준값보다 나아졌다(other p50 7~10 → 1.1~1.4) · 남은 것 = git 7초에 끊긴 바퀴가 cut=- 인 채 items 가 N/N 이 아님(창1 4줄 · 창2 24줄)
  원문 2줄: `16:01:45 판정 불가 harness - git 7초 넘음` → `ROUND s=27.6 fetch=3.5 b1=4.8 b2c=0 b2f=13.3 b3=0 stall=0.3 fetch_root=3.5 fetch_pack=0.7 nano=5.6 wall=31.2 other=3.6 items=11/39 cut=- slow=harness:b2f:11.5 unknown=6` · `16:09:43 판정 불가 harness - git 7초 넘음` → `ROUND s=23.3 fetch=3.8 b1=0 b2c=0 b2f=16.8 b3=0 stall=0.1 fetch_root=3.8 fetch_pack=0.8 nano=2.6 wall=24.1 other=0.7 items=1/29 cut=- slow=harness:b2f:16.8`
  아닌 줄 시각 분포(창2): 11-17 16시 4 · 19시 1 · 21시 3 · 22시 3 · 23시 5 · 11-18 05시 2 · 06시 1 · 12시 3
- 세트: 4ca226e14922d58e580f490b1b7e0e27f4fbfc1b · 시험: python3.11 -m pytest feature-pack/fable-team/ft2/tests/test_keeper_round_cells.py (15 passed · 2.6초 · 변이 M109~M112 4/4) rc=0 · 이슈: 0
