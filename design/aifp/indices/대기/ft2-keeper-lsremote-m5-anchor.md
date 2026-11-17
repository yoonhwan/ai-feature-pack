# 인덱스: ft2-keeper-lsremote-m5-anchor — 끝: test_pi_keeper_lsremote_once_r1963b.py 의 사례 ⑥(c6)이 지금 keeper.py 에서 통과하고 · 변이 M5 · M6 이 그 사례를 «변이 때문에» 실패시킨다(닻만 맞추는 것으로는 이 끝에 못 간다)
<!-- ledger: feature-pack/fable-team/legacy/1.x/harness/design/harness/GOAL-harness.md -->
- Issue: 없음(초안) — 나노 훑기 aifp 6025 [새 카드 필요 1줄](완성/ft2-keeper-endings-m9-anchor 구현 범위 3) · 팀장 aifp-ft-master-pi#24 발주 aifp 6039
- 제안서: 없음 — 시험 1파일 복구 · 설계 = 이 카드 «계약»
- 근거: 읽기·시험 실행 2026-11-17 14:50(aifp-ft-arch-pi#24 · 팩 origin/main b9553142 · 제품·시험 파일 손 0 · 임시 시험 사본 1개는 지움) — 아래 «읽은 것» 절
- 원인 1줄: keeper 60초 카드(PR #1397 · d261be1a)가 나노 가지 모으기 줄을 `self.nano_s = self.now() - at` 에서 `self.nano, self.nano_s, self.nano_dl = (…), time.monotonic() - at, None` 으로 바꿨다 · ① M5 는 옛 줄을 닻으로 찾아 0곳에서 떨어진다 ② 나노 초를 재는 시계가 주입 시계(`self.now`)에서 `time.monotonic` 으로 바뀌어, 주입 시계만 움직이는 사례 ⑥ 이 기준판에서 실패한다(nano 칸 없음 · s=4) ③ 그래서 M6 은 지금 «사례가 원래 실패하니 통과» 하는 빈 통과다 · 그 PR 은 이 시험 파일을 고치지 않았다
- 앞 카드: 진행/ft2-keeper-round-60s(PR #1397) · r1963b(ls-remote 리포당 1회 · 나노 모으기 = fetch 시계 밖 · M1~M6) · 완성/ft2-keeper-endings-m9-anchor(PR #1516 · 같은 부류 선례)
- 상태: 대기
- 설치: 없음 — 시험 파일만 바뀐다(keeper 동작 변화 0 · 판 올림을 따로 하지 않는다)
- 선행: 없음(팩 origin/main b9553142)
- 시험 입력: 그 시험 파일이 이미 쓰는 것 그대로(임시 루트 · r1812 대역 World · 실제 git · tmp bare 원격 · 주입 시계 · 실 runtime 0 · 네트워크 0 · sleep 0)
- 기준값: `python3.11 -m pytest tests/test_pi_keeper_lsremote_once_r1963b.py` = 2 failed 12 passed 17.4초(`test_case[c6]` · `test_mutant[M5]`) → 목표 = 14 passed · M5 · M6 이 변이판에서 ⑥ 의 단언을 깬 원문
- 규칙: 없음 — 상시 로드 변경 0
- 규칙 상세: 하드 룰 22
- 대상: 팩 feature-pack/fable-team/ft2/tests/test_pi_keeper_lsremote_once_r1963b.py(사례 c6 · 변이 M5 · 변이 틀)
- 정본 영향 없음: aifp 정본 변경 0 · 팩 ft2 계약 문서 변경 0 · 제품 코드 변경 0
- 크기: 시험 1파일(c6 대역 · M5 2곳 · 변이 틀 대조 1줄) · PR 1개
- 배정: 대기(DA · 2026-11-17T14:52)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
6 — 하네스 운영 정리. 하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」. 골의 축: 6(변이 시험이 지금 코드에 걸려 있어야 회귀를 잡는다). 이 카드의 증거 = 착지 sha + 그 파일 rc0 + M5 · M6 이 변이판에서 ⑥ 을 실패시킨 원문 + 원본에서 ⑥ PASS.

## 배경 (한 단락)
r1963b 시험의 변이 M1~M6 은 keeper.py 사본에서 글자 한 줄을 찾아 바꾼 뒤, 지정한 사례가 실패하는지 본다. M5 는 «나노 가지 모으기 초를 fetch 칸에 넣는» 회귀를, M6 은 «나노 초를 합계에서 빼는» 회귀를 잡는다. 둘 다 사례 ⑥(주입 시계로 나노 모으기 3초 · fetch 4초 → ROUND fetch=4 · nano=3 · s=7)에 걸린다. keeper 60초 카드 뒤 M5 는 찾는 글자를 잃었다. 팀장 발주는 «닻만 맞춰도 M5 뜻이 서는가» 를 물었다. 재 보니 서지 않는다. 사례 ⑥ 자체가 기준판에서 실패하기 때문이다. 변이 틀은 «변이판에서 사례가 실패하는가» 만 보므로, 사례가 원래 실패하면 닻을 맞춘 M5 도, 지금의 M6 도 아무것도 잡지 않고 통과한다. 이 카드는 사례 ⑥ 을 지금 코드에서 다시 서게 하고, 그 위에서 M5 닻을 맞춘다. 제품 코드는 고치지 않는다.

## 읽은 것 (2026-11-17 14:50 · 팩 origin/main b9553142 · 제품·시험 파일 손 0)
| # | 무엇 | 원문 |
|---|---|---|
| 가 | 시험 112행 M5 | `"M5": ("        self.nano_s = self.now() - at\n", '        self.spent["fetch"] += self.now() - at; self.nano_s = 0.0\n', c6),   # 나노 모으기를 fetch 시계 안에` |
| 나 | 시험 113행 M6 | `"M6": ("        s += self.nano_s", "        s += 0", c6)}   # 나노 초를 s 에 안 넣음` |
| 다 | 지금 keeper.py :470~477 | `at, got, nano_cut = time.monotonic(), {}, False` → `self.nano_dl = at + NANO_S` → `for team in ([] if self.table else self.teams()): got.update(kf.nanos(self, [team]))` → `self.nano, self.nano_s, self.nano_dl = ({} if self.table else got), time.monotonic() - at, None` · 옛 줄 `self.nano_s = self.now() - at` 는 0곳 · `s += self.nano_s` 는 1곳(:532) |
| 라 | PR #1397 의 그 줄 diff | `-        self.nano_s = self.now() - at` · `+        self.nano, self.nano_s, self.nano_dl = ({} if self.table else got), time.monotonic() - at, None` · 그 PR 이 바꾼 파일에 이 시험 파일 없음 |
| 마 | 사례 ⑥(시험 87~96행) | `kf_of(k).nanos` 를 «주입 시계 +3 뒤 원래 함수» 로 · `k.git` 을 «fetch 면 주입 시계 +4» 로 바꾸고 `assert (cell["fetch"], cell.get("nano"), cell["s"]) == ("4", "3", "7"), row` · 주입 시계 = World 의 `now=lambda: s.t`(keeper `self.now`) |
| 바 | 기준판 실행(파일 전체) | `2 failed, 12 passed in 17.37s` = `test_case[c6]` · `test_mutant[M5]` |
| 사 | 기준판 ⑥ 실패 원문 | `AssertionError: ROUND s=4 fetch=4 b1=0 b2c=0 b2f=0 b3=0 stall=0 fetch_root=0 fetch_pack=4 wall=4 other=0 items=2/2 cut=- slow=-` · `assert ('4', None, '4') == ('4', '3', '7')` |
| 아 | 기준판 M5 실패 원문 | `AssertionError: ('M5', '        self.nano_s = self.now() - at\n')` · `assert 0 == 1` |
| 자 | 변이 틀(121~131행) | `assert text.count(old) == 1, (name, old)` → 바꾼 사본에서 `with pytest.raises(AssertionError): case(World(…, tree))` · 원본에서 그 사례가 통과하는지는 보지 않는다(`test_case` 가 따로 본다) |
| 차 | keeper 의 시계 2개 | `self.now`(주입 · `timed()` 의 칸 초 `self.spent[…]`) · `time.monotonic`(7곳 · 바퀴 예산 · 나노 모으기 초 · wall) · 60초 카드 시험은 keeper 모듈의 `time` 을 통째로 주입 시계로 바꾼다(test_keeper_round_60s.py :43 `g["time"] = types.SimpleNamespace(monotonic=s.clock, time=s.clock)`) |
| 카 | 닻만 맞춘 꼴을 임시 사본으로 재 봄(M5 닻·바꿀 글자를 튜플 줄로 · ⑥ 에 keeper 모듈 `time` 주입 1줄) | `3 failed, 13 passed in 20.88s` · ⑥ 은 여전히 `('4', None, '4')` · M5 변이판도 `fetch=4`(fetch_root 만 0 → 4) = 나노 모으기 3초가 어느 시계에도 안 들어갔다 · [확인 필요: 까닭 — `kf.nanos` 가 지금은 팀마다 불리는데(`self.teams()`) ⑥ 의 World 에 대상 팀이 0 이라 바꿔 둔 `nanos` 가 한 번도 안 불리는지 · 나노 구현 때 먼저 잰다] |

## 계약
- L1 사례 ⑥ 이 지금 keeper.py 원본에서 통과한다 · 기대값 `("4", "3", "7")` 과 둘째 단언(모으기 0초 → ` nano=` 칸 없음)은 그대로 둔다 · 고치는 것은 ⑥ 의 대역뿐이다: ⓐ 나노 모으기 3초가 keeper 가 실제로 재는 시계(`time.monotonic`)에 들어가게 한다(60초 카드 시험의 주입 꼴을 따른다 · 그 World 한 개 안에서만 · 다른 사례로 새지 않는다) ⓑ 바꿔 둔 `nanos` 가 실제로 1회 이상 불리게 한다(읽은 것 카 의 까닭을 먼저 재고, 대상 팀이 0 이어서라면 ⑥ 에 팀 1개를 세운다)
- L2 M5 의 닻 2곳을 지금 줄에 맞춘다 · 찾는 글자 = `        self.nano, self.nano_s, self.nano_dl = ({} if self.table else got), time.monotonic() - at, None\n` · 바꿀 글자 = 같은 자리에서 그 초를 `self.spent["fetch"]` 에 더하고 `self.nano_s` 를 0.0 으로 두는 한 줄(`self.nano` · `self.nano_dl` 대입은 원본과 같게) · 변이의 뜻(나노 모으기를 fetch 시계 안에)은 그대로다
- L3 M6 의 글자는 손 0 이다(닻 `        s += self.nano_s` 는 지금도 1곳) · L1 이 서면 M6 은 빈 통과가 아니게 된다
- L4 빈 통과 막기: M5 · M6 이 변이판에서 ⑥ 을 실패시킬 때 그 실패가 «변이가 만든 값» 임을 PR 본문에 원문으로 보인다(M5 = fetch 7 · nano 없음 / M6 = s 4) · 변이 틀에 «원본에서 그 사례 PASS» 대조를 넣을지는 나노가 걸린 초를 재서 정한다(파일 전체가 70초 안이면 넣는다 · 넘으면 넣지 않고 그 까닭 1줄)
- L5 제품 코드 손 0(keeper.py 의 나노 초를 `self.now` 로 되돌리지 않는다 · 나노 모으기 7초 문 `nano_dl` 이 바퀴 예산과 같은 시계를 쓰는 것이 60초 카드 R6 계약이다) · 다른 사례 c1~c5b · c7 · 변이 M1~M4 손 0
- L6 L1 ⓐⓑ 를 시험 파일만으로 못 세우면(제품 코드를 고쳐야만 ⑥ 이 선다) 고치지 않고 팀장에 1줄 = 그때는 제품 1줄 카드로 다시 짠다(사람 판단)

## 반례 표
| # | 입력 | 기대 | 지금 |
|---|---|---|---|
| 51가 | `test_case[c6]` | 1 passed · ROUND 줄에 fetch=4 · nano=3 · s=7 | 1 failed · `('4', None, '4')`(읽은 것 사) |
| 51나 | `test_mutant[M5]` | 1 passed = 변이판에서 ⑥ 이 AssertionError(fetch=7 · nano 칸 없음) | 1 failed · 닻 0곳(읽은 것 아) |
| 51다 | `test_mutant[M6]` | 1 passed = 변이판에서 ⑥ 이 AssertionError(s=4 · 원본은 7) | 1 passed 이지만 빈 통과(원본에서도 ⑥ 실패) |
| 51라 | 그 파일 전체 | 14 passed · rc 0 · 70초 안 | 2 failed 12 passed 17.4초 |
| 51마 | 닻만 맞추고 ⑥ 을 안 고친 꼴(잘못 고친 꼴) | 착지 못 함 = 51가 가 실패로 남는다 · M5 가 통과해도 완료 조건 3 의 «변이가 만든 값» 원문을 못 낸다 | — |
| 51바 | M5 의 바꿀 글자에서 `self.spent["fetch"] +=` 를 빼먹음(변이판 = 원본과 같은 초 배분) | L1 이 선 뒤에는 변이 틀의 `pytest.raises(AssertionError)` 가 실패한다(DID NOT RAISE) | — |

## 구현 범위 (나노 1 · 팩 base origin/main 최신 · DA 설계 승인 뒤)
1. 먼저 잰다(고침 0): 읽은 것 카 의 까닭 = ⑥ 에서 바꿔 둔 `nanos` 가 불린 횟수 · `self.teams()` 값 · 결과 1줄을 PR 본문에
2. 커밋 1 [test] — 그 시험 파일 L1 · L2 · L4 · 기준판 FAIL 원문(51가 · 51나)을 PR 본문에 붙인다
3. 변이판 원문 2줄(M5 · M6 의 ROUND 줄 = L4)을 PR 본문에 붙인다
4. 실행 = `python3.11 -m pytest`(ft-test-slot) · 착지 = PR 1개(팀장 집행) · git stash 쓰지 않는다(기준판 비교는 sha 로 · 나노 aifp 6025 사고)

## 범위 밖
- keeper.py · keeper_fetch.py · 계약 문서(제품 코드 손 0 · L6 이면 새 카드).
- 같은 훑기에서 나온 다른 rc1 파일(launch_failed_end M11·M12·M16·M30·M31 · fetch_narrow_r1937 M2 · r1812 M5) = 깨진 닻이 아니다 · 따로 본다(팀장 판단).
- 60초 카드 회귀 목록에 이 파일을 더하는 일 = 팀장 판단.

## 완료 조건
1. [ ] 나노: 구현 범위 1 의 잰 값 1줄(nanos 불린 횟수 · teams 값)
2. [ ] 나노: 기준판 FAIL 원문(51가 · 51나)
3. [ ] 나노: 그 파일 전체 14 passed rc0 · 걸린 초(51라) · 변이판 원문 2줄(M5 fetch 7 · M6 s 4 = L4)
4. [ ] 나노: 바뀐 파일 1개(제품 코드 손 0) · L6 에 걸리면 고치지 않고 팀장 1줄
5. [ ] 팀장: PR 착지 sha

## 계약↔시험 대응표
| 계약 | 시험 |
|---|---|
| L1 사례 ⑥ 복구 | 51가 · 51마 |
| L2 M5 닻 | 51나 · 51바 |
| L3 M6 손 0 · L4 빈 통과 막기 | 51다 · 변이판 원문 2줄 |
| L5 제품 코드 손 0 | PR 바뀐 파일 1개 |

## 상태
- 2026-11-17 14:52 · 대기 — aifp-ft-arch-pi#24 초안(팀장 aifp 6039 · 나노 훑기 aifp 6025 · 읽기 + 시험 실행 4회 3·17·22·2초 · 임시 시험 사본은 지움 · 제품·시험 파일 손 0) · 판단 = 닻만 맞춰서는 M5 뜻이 서지 않는다(사례 ⑥ 이 기준판에서 실패 · M6 은 지금 빈 통과) → 범위 = 시험 1파일에서 ⑥ 대역 + M5 닻 · 다음 = 팀장 PR merge → DA 설계 → Issue → 나노 1석
