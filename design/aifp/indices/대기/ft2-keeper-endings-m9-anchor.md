# 인덱스: ft2-keeper-endings-m9-anchor — 끝: test_pi_keeper_endings_r1960.py 의 변이 M9 가 지금 keeper.py 에 다시 걸린다 · M9 의 뜻(일이 끝난 자리에서 complete 를 부르면 ③ 이 잡는다)은 그대로다
<!-- ledger: feature-pack/fable-team/legacy/1.x/harness/design/harness/GOAL-harness.md -->
- Issue: #8986 (byz-agents · 등록 aifp-ft-master-pi#23 BYZ 326278 · DA APPROVE-DESIGN 326251) — 알림 harness arch#395 BYZ 313766(aifp 5929 ②) · 팀장 aifp-ft-master-pi#23 발주 aifp 5930
- 제안서: 없음 — 시험 닻 1줄 복구 · 설계 = 이 카드 «계약»
- 근거: 읽기 2026-11-16 09:32(aifp-ft-arch-pi#23 · 팩 origin/main 97b15fdc · 읽기만) + 팀장 재현 «1 failed 0.16초»(aifp 5930) — 아래 «읽은 것» 절
- 원인 1줄: keeper 60초 카드(PR #1397 · d261be1a)가 바퀴 고리를 `one_work` 로 옮기면서 `elif self.sock and endings.ending(self, team, work):` 를 `if self.sock and endings.ending(self, team, work):` 로 바꿨다 · M9 는 옛 글자(`elif …`)를 닻으로 찾아 바꾸는 변이라 `assert text.count(old) == 1` 에서 0 으로 떨어진다 · 그 PR 은 이 시험 파일을 고치지 않았고 카드 회귀 목록에도 이 파일이 없었다
- 앞 카드: 진행/ft2-keeper-round-60s(PR #1397) · r1960(일이 끝난 나노 자리 닫기 · M1~M10) · r2000(M9 = cli complete 를 바로 부르는 꼴)
- 상태: 대기
- 설치: 없음 — 시험 파일만 바뀐다(설치본에 tests 는 실리지만 keeper 동작 변화 0 · 판 올림을 따로 하지 않는다)
- 선행: 없음(팩 origin/main 97b15fdc)
- 시험 입력: 그 시험 파일이 이미 쓰는 것 그대로(임시 루트 · ft2 사본에 글자 바꾸기 · 가짜 tmux·mbox · 실 runtime 0 · 네트워크 0)
- 기준값: `python3.11 -m pytest tests/test_pi_keeper_endings_r1960.py -k "M9"` = 1 failed(닻 0개) → 목표 = 1 passed · 파일 전체는 «새 실패 0»(기준판 같은 실패 2건은 알려진 한계 · 완료 조건 2)
- 규칙: 없음 — 상시 로드 변경 0
- 규칙 상세: 하드 룰 22
- 대상: 팩 feature-pack/fable-team/ft2/tests/test_pi_keeper_endings_r1960.py(162행 M9 의 닻 글자 2곳)
- 정본 영향 없음: aifp 정본 변경 0 · 팩 ft2 계약 문서 변경 0 · 제품 코드 변경 0
- 크기: 시험 1파일 1줄 · PR 1개
- 배정: 대기(석 · 2026-11-17T14:23)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
6 — 하네스 운영 정리. 하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」. 골의 축: 6(변이 시험이 지금 코드에 걸려 있어야 회귀를 잡는다). 이 카드의 증거 = 착지 sha + 그 파일 rc0 + M9 가 변이판에서 ③ 을 실패시킨 원문.

## 배경 (한 단락)
r1960 시험의 변이 M1~M10 은 제품 파일 사본에서 글자 한 줄을 찾아 바꾼 뒤, 지정한 사례가 실패하는지 본다. 찾는 글자가 제품 파일에 정확히 1곳 있어야 한다. keeper 60초 카드가 바퀴 고리를 새 함수로 옮기면서 그 줄의 머리 낱말이 바뀌었고, M9 는 찾는 글자를 잃었다. 변이 시험이 걸리지 않으면 «일이 끝난 자리에서 complete 를 부르는» 회귀를 이 파일이 더는 잡지 못한다. 이 카드는 닻 글자만 지금 코드에 맞춘다.

## 읽은 것 (2026-11-16 09:32 · 팩 origin/main 97b15fdc · 읽기만)
| # | 무엇 | 원문 |
|---|---|---|
| 가 | 시험 162행 | `"M9": (KP, "elif self.sock and endings.ending(self, team, work):", "elif self.sock and endings.ending(self, team, work) and (land.cli.run(['complete', '--root', self.root, '--team', team, '--work', work, '--attempt', attempt]) or True):", c3)}   # r2000 — complete() 는 남은 범위 관문이 먼저 막으므로 cli complete 를 바로 부른다` |
| 나 | 지금 keeper.py :546(`one_work` 안) | `if self.sock and endings.ending(self, team, work):   # r1960 끝(완성후·아카이브·상태 머리) = complete 0 · close 가드 그대로` · 파일 안에서 `if self.sock and endings.ending(self, team, work):` 는 1곳 · `elif …` 꼴은 0곳 |
| 다 | 변이가 쓰는 이름 | keeper.py :48 `land = _load(os.path.join(HERE, "keeper_land.py"), "ft2_keeper_land")`(모듈 이름 그대로 있음) · `one_work(self, team, work, attempt, row, dispatched, rows)` 가 `team` · `work` · `attempt` 를 인자로 받는다 |
| 라 | M9 가 거는 사례 ③(시험 73~76행) | `assert has(lines, "CLOSED-ENDING harness r9603", "superseded") and len(kills) == 1 and w.kinds("complete") == 0, lines` |
| 마 | 변이 시험 틀(167~175행) | `assert text.count(old) == 1, (name, old)` → 바꾼 사본에서 사례가 AssertionError · 원본에서 같은 사례 PASS |
| 바 | PR #1397 이 바꾼 파일 13개 | 이 시험 파일 없음 · 60초 카드 «구현 범위 4» 회귀 목록 11파일 + 더한 3묶음에도 없음 |

## 계약
- J1 M9 의 닻 2곳(찾는 글자 · 바꿀 글자)의 머리 `elif` 를 `if` 로 고친다 · 그 밖 글자는 그대로다 = 찾는 글자 `if self.sock and endings.ending(self, team, work):` · 바꿀 글자 `if self.sock and endings.ending(self, team, work) and (land.cli.run([…]) or True):`
- J2 변이의 뜻은 그대로다(판단 = 닻만 맞춘다) · 까닭: 지금 판에서도 그 줄은 «complete 가 거짓을 낸 뒤 일이 끝난 자리인지 묻는» 같은 갈래이고, 변이가 쓰는 이름(`land` · `team` · `work` · `attempt`)이 그 자리에 모두 있다 → 변이판은 끝난 자리에서 cli complete 를 불러 ③ 의 `w.kinds("complete") == 0` 을 깬다 · 사례 ③ · 변이 틀 · 다른 변이 M1~M8 · M10 은 손 0
- J3 제품 코드 손 0(keeper.py 를 `elif` 로 되돌리지 않는다 · `one_work` 는 갈래마다 return 하는 꼴이라 `if` 가 맞다)

## 반례 표
| # | 입력 | 기대 | 지금 |
|---|---|---|---|
| ㊼가 | `test_mutant[M9]` | 1 passed = 변이판에서 ③ 이 AssertionError(`w.kinds("complete")` 가 0 이 아님) · 원본에서 ③ PASS | 1 failed · `AssertionError: ('M9', 'elif self.sock and endings.ending(self, team, work):')` 꼴(닻 0개) |
| ㊼나 | 그 파일 전체 | M9 PASS + 그 밖 실패 집합이 기준판과 같다(새 실패 0) = 사례 18 PASS · 1 FAIL(c4) · 변이 9 PASS · 1 FAIL(M3) · rc 는 1 이다(rc 0 을 요구하지 않는다) | 기준판 = c4 · M3 · M9 3칸 실패(DA BYZ 326251 baseline) |
| ㊼다 | 닻만 맞추고 바꿀 글자의 `and (land.cli.run(…) or True)` 를 빼먹음(잘못 고친 꼴) | 변이 틀의 `pytest.raises(AssertionError)` 가 실패한다(변이판이 원본과 같아 ③ 이 통과) = 그 꼴은 착지 못 함 | — |

## 구현 범위 (나노 1 · 팩 base origin/main 최신 · DA 설계 승인 뒤)
1. 커밋 1 [test] — feature-pack/fable-team/ft2/tests/test_pi_keeper_endings_r1960.py 162행 J1 · 기준판 FAIL 원문(㊼가)을 PR 본문에 붙인다
2. 변이판에서 ③ 이 실패한 원문 1줄(AssertionError 의 lines 앞머리)을 PR 본문에 붙인다 = J2 가 실제로 선다는 증거
3. 훑기 1회(읽기 · 고침 0): ft2/tests 에서 `adapters/pi/keeper.py` 를 글자 닻으로 쓰는 변이 시험 파일을 찾아, 60초 카드 회귀 목록(11파일 + 3묶음)에 없는 파일 이름과 그 파일의 rc 를 PR 본문에 적는다 · 깨진 닻이 더 나오면 고치지 않고 팀장에 1줄(새 카드)
4. 실행 = `python3.11 -m pytest` · 착지 = PR 1개(팀장 집행)

## 범위 밖
- keeper.py · 다른 keeper_*.py · 계약 문서.
- 구현 범위 3 에서 더 나온 깨진 닻의 고침 = 새 카드.
- 기준판에서 이미 실패하는 c4 · M3(원본 대조 c4) 2건의 고침 = 후속 카드(닻 보정이 만든 실패가 아니다 · DA BYZ 326251 · 카드 등록은 팀장).
- 대기/ft2-keeper-round-cells-b1-items(같은 `one_work` 의 landing 줄을 고친다 · 이 카드의 닻 줄과 다른 줄이라 순서 무관 · 그 카드 회귀 목록에 이 파일을 더할지는 팀장 판단).

## 완료 조건
1. [ ] 나노: 기준판 FAIL 원문(㊼가)
2. [ ] 나노: 그 파일 전체 = M9 PASS + 그 밖 실패 집합이 기준판과 같음(새 실패 0) · 실패한 node id 목록을 기준판과 고친 판 나란히 · 걸린 초(㊼나) — 기준판(팩 main 0536a1fa)에서 같은 이름·같은 단언으로 실패하는 2건 = 사례 c4(다른 holder 의 UNKNOWN intent 없음 기대 · attempt a2) · `test_mutant[M3]`(원본 대조에서 같은 c4) 은 «기준판 같은 실패 = 알려진 한계» 로 센다 · 실패 줄의 단언이 기준판과 다르거나 다른 node 가 실패하면 [ ] · «파일 전체 rc0» 이라고 보고하지 않는다(DA APPROVE-DESIGN BYZ 326251)
3. [ ] 나노: 변이판에서 ③ 이 실패한 원문 1줄(J2)
4. [ ] 나노: 훑기 결과(파일 이름 · rc · 깨진 닻 수)
5. [ ] 팀장: PR 착지 sha

## 계약↔시험 대응표
| 계약 | 시험 |
|---|---|
| J1 닻 2곳 | ㊼가 · ㊼나 |
| J2 변이 뜻 그대로 | ㊼가(변이판 ③ 실패 원문) · ㊼다 |
| J3 제품 코드 손 0 | PR 바뀐 파일 1개 |

## 상태
- 2026-11-16 10:04 · 대기 — aifp-ft-arch-pi#23 초안(팀장 aifp 5930 · 알림 harness arch#395 BYZ 313766 · 읽기 2회 · 구현 0 · 시험 실행 0) · 판단 = 닻만 맞춘다(변이 뜻은 지금 판에서도 선다) · 다음 = 팀장 PR merge → DA 설계(정지 풀린 뒤) → 나노 1석
- 2026-11-17 14:23 · 대기 — DA 설계 APPROVE-DESIGN(BYZ 326251 · aifp 6004 · 고정판 0536a1fa) · Issue #8986 등록(BYZ 326278) · 배정 = 대기(석) · 완료 조건 2 를 «파일 전체 rc0» 에서 «M9 PASS + 새 실패 0» 으로(기준판 같은 실패 c4 · M3 2건 = 알려진 한계 · 후속 카드) · aifp-ft-arch-pi#24(팀장 발주 aifp 6005 · 구현 0) · 다음 = 팀장 착지 → 나노 spawn
