# 인덱스: ft2-prereq-unreadable-once — 끝: keeper 가 못 읽는 «- 선행:» 줄의 판정 불가 로그는 값이나 까닭이 바뀔 때만 1줄 찍힌다 · 팀장에게 어느 카드를 어떻게 고칠지 [다음 막힘] 1통이 간다 · 막는 판정은 그대로다
<!-- ledger: feature-pack/fable-team/legacy/1.x/harness/design/harness/GOAL-harness.md -->
- Issue: #8645 — 등록 planner#324 aifp 5411(팀장 aifp-ft-master-pi#18 발주 aifp 5410 ③ · 5395 ② · 5382 행 I)
- 제안서: 없음 — 결함 복구(새 흐름 0) · 설계 = .fable-team/state/team-main/aifp-ft/orders/DESIGN-pI-prereq-unreadable-log-once-20261116.md(r2 sha256 bdf62a46…a750 · DA 대행 byz-harness-da-codex#11 APPROVE-DESIGN BYZ 310229 · 전문 .fable-team/state/team-main/aifp-ft/DA-pI-r2-approve-310229.md · 앞 판 r1 REJECT = 재발 쪽지 0 · 까닭 바뀜 로그 0 반례 → 닫힘) · 착지 PR 에서 feature-pack/fable-team/design/ 로 옮긴다
- 근거: 실측 2026-11-16(aifp-ft-arch-pi#17 · BYZ .fable-team/state/ft2-keeper/2026111{5,6}.jsonl·카드 원문 · 읽기만) — «판정 불가 <팀> <카드> 선행 줄 판독 불가 — 건너뜀» 이틀 1132줄 · 카드 7장(cfo 4 · harness 3) · 11-15 cfo 3장이 장마다 288줄 · 그동안 선행 값 변화 0 · 까닭 2갈래 = 번호 참조 없음(cfo sim-source-links «생성기 턴키 기준 main 착지 = 1a80d4c0fc(충족)» · harness r1375 «재자율(…)») / 글 속 r5 가 카드 번호로 읽혀 루트에 없음(cfo atom-it-planner-rate «결정 원문 r5 PR 8503 착지»)
- 원인 1줄: keeper_next.choose 는 선행불명 줄을 바퀴 캐시(once)로만 막아 다음 바퀴에 또 찍는다 · 줄에 까닭과 고칠 꼴이 없다 · 팀장에게는 고를 카드 0 일 때의 [다음 없음] 사유별 수만 가고 카드 이름이 없다
- 앞 카드: r2027(팩 54375271 · 선행 줄로 막힘 · 못 읽는 선행 건너뜀) · r1969(바퀴 캐시) · r1871(다음 카드) · r1913·r1939(fill)
- 상태: 대기
- 착지: b70abbf6821b535077494f2083c1a69626387963(팩 main · PR #1336 squash · #1331 을 main 위로 rebase 한 판 · DA#11 APPROVE-IMPL BYZ 311566 + rebase 재확인 311650 · 세트 093824d7 = PR head · 뺄 커밋 0)
- 설치: 있음 — ft2 판 올림 1회 · 되돌림 = 앞 판으로 판 전환(상태 파일의 새 키 3개는 옛 판이 읽지 않음)
- 선행: 없음 — E ft2-keeper-notify-recipient 착지 ae0c199e(PR #1282) + D+F ft2-launch-failed-end 착지 8ed707c4(PR #1294) + J ft2-penalty-team-no-new-pick 착지 0d72507e(PR #1304 · keeper_next.py 겹침 풀림) 착지 끝 · 팀장 aifp-ft-master-pi#20 이 풂
- 시험 입력: 임시 루트(tmp_path) · 시험 안에서 만든 카드 루트·카드·keeper 상태 파일 · 가짜 mbox(rc 를 사례가 정함) · 가짜 clock(날짜 넘김 포함) · sleep 0 · 네트워크 0 · 실 runtime 쓰기·읽기 0 · 사례 1개 70초 안
- 기준값: 기준판 = 선행불명 카드 1장이 바퀴마다 1줄 · 팀장 쪽지에 카드 이름 0 → 목표 = 값·까닭이 바뀔 때만 1줄 · [다음 막힘] 은 묶음이 마지막으로 전한 것과 다를 때 1통
- 규칙: 없음 — 상시 로드 변경 0
- 규칙 상세: 하드 룰 20 · 하드 룰 22 · r2027 «못 읽는 선행 = 건너뜀»(추측 0) 그대로
- 대상: 팩 feature-pack/fable-team/ft2/adapters/pi/keeper_next.py(prereq 까닭 반환 · choose 로그 기억 · 쪽지 1곳) · 새 시험 feature-pack/fable-team/ft2/tests/test_prereq_unreadable_once.py · 문서 ft2/contracts/keeper-settle/CONTRACT.md·CASES.md
- 정본 영향 있음: CONTRACT.md 에 «선행불명 로그·쪽지» 절 1개(상태 키 3개 · 줄 꼴 · 보낼 조건) · CASES.md ㉟·변이 행 = 같은 PR(나노)
- 크기: 코드 1파일 · 새 시험 1파일 · 문서 2파일 · PR 1개
- 배정: 좌석 aifp-ft-nano-ft2-prereq-unreadable-once#0

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」. 골의 축: 6(하네스 운영 정리 — 막힌 카드가 같은 줄만 되풀이하지 않고 고칠 사람에게 고칠 꼴이 간다). 이 카드의 증거 = 착지 sha + 시험 rc0 + 설치 뒤 1시간 keeper 로그의 «선행 줄 판독 불가» 줄 수 + cfo·harness 팀장 우편함의 [다음 막힘] seq.

## 배경 (한 단락)
keeper 는 대기 카드의 «- 선행:» 줄에서 r<번호> 만 읽는다. 번호가 없거나 그 번호의 카드가 루트에 없으면 고르지 않는다. 그 판정은 맞다. 문제는 같은 «판정 불가» 줄을 바퀴마다 찍는 것이다. cfo 카드 3장은 하루에 장마다 288줄을 냈다. 줄에는 왜 못 읽는지, 어떻게 고치는지가 없다. 팀장은 고를 카드가 하나도 없을 때만 «선행불명 n» 이라는 수를 받는다. 그래서 어느 카드를 고쳐야 하는지 모른 채 남는다.

## 계약
- I1 로그 = 선행불명 줄은 그 카드의 «선행 값 + 까닭» 이 바뀔 때만 1줄 · 기억 = keeper 상태 state["prereq_seen"]["<팀>|<카드>"] = {"val": <선행 값>, "why": <까닭>} · 값은 같고 까닭만 바뀌어도 1줄
- I2 줄 꼴 = `판정 불가 <팀> <카드> 선행 줄 판독 불가(<까닭>) — 건너뜀 · 고칠 꼴 «- 선행: 없음» 또는 «- 선행: r<번호>»` · 까닭 = `번호 참조 없음` 또는 `루트에 없는 번호 r<a> r<b> …`(없는 번호 전부 · 번호 순)
- I3 prereq() 의 판정 값 3개("" · 선행 · 선행불명)와 고르지 않는 판정은 그대로 · 까닭 글만 따로 돌려준다
- I4 기억 치우기 = 그 카드가 선행불명이 아니게 되거나 대기 폴더에서 사라지면 prereq_seen 에서 지운다 · 다시 선행불명이 되면 1줄
- I5 팀장 쪽지 = `[다음 막힘] <팀> 선행 줄을 못 읽는 카드 <n>장: <앞 3장 이름> · 고칠 꼴 «- 선행: 없음» 또는 «- 선행: r<번호>»` · 고를 카드가 있든 없든 간다
- I6 묶음 지문 = 그 팀 선행불명 카드의 (이름·선행 값·까닭) 전부 · 바퀴마다 계산 · 0장이면 빈 묶음
- I7 두 기억 = state["prereq_now"][<팀>](앞 바퀴 묶음 지문 + 전이 번호 · 묶음이 바뀔 때마다 +1) · state["prereq_told"][<팀>](마지막으로 전송에 성공한 묶음 지문) · 지금 묶음이 비면 prereq_told 를 비운다
- I8 보낼지 = 지금 묶음이 비어 있지 않고 prereq_told 와 다르면 보낸다 · 열쇠 = `prereq|<팀>|<묶음 지문>|<전이 번호>` · prereq_told 는 notify 가 성공(rc 0 또는 도착 확인)을 돌려줄 때만 바꾼다 · 실패·바퀴 넘김(defer)은 바꾸지 않는다
- I9 세 기억(prereq_seen·prereq_now·prereq_told)은 모두 keeper 상태 파일의 키다 · 메모리에만 두어 재기동 때 번호가 초기화되면 불합격(DA BYZ 310229)
- I10 그대로: [다음 없음] 쪽지(하루 1통 · 사유별 수) · choose 의 고르기 순서 · 보내기는 k.notify(받는 곳 차례·실패 지문·바퀴 3통 = ft2-keeper-notify-recipient)

## 구현 범위 (나노 1 · 팩 base origin/main 최신 · 선행 두 카드 착지 뒤)
1. 커밋 1 [test] — 새 시험 feature-pack/fable-team/ft2/tests/test_prereq_unreadable_once.py(㉟가~하 14칸 + 인수 칸 ㉟거 · M39·M40·M41·M56·M57·M58) · 기준판 FAIL 원문(㉟가·㉟바·㉟차·㉟타)을 PR 본문에 붙인다
2. 커밋 2 [fix] — I1~I9 = feature-pack/fable-team/ft2/adapters/pi/keeper_next.py(prereq 반환 · choose 의 선행불명 로그 자리 · 쪽지 1곳) · 다른 함수 손 0 · 다른 파일 손 0
3. 커밋 3 [docs] — CONTRACT.md 절 · CASES.md ㉟·변이 행 · 설계 1쪽을 feature-pack/fable-team/design/ 로
4. 회귀 rc0: r2027 선행 시험 · test_pi_keeper_next_card_r1871.py · r1913·r1939 fill 시험 · ft2-launch-failed-end 의 ㉘아~하(L9 가 같은 함수를 만짐)
5. 실행 = `python3.11 -m pytest` · 착지 = PR 1개(팀장 집행)

## 범위 밖
- cfo 4장·harness 2장의 «- 선행:» 을 `없음` 또는 `r<번호>` 로 고치는 일(그 팀 팀장)
- 카드 이름(slug)으로 적은 선행을 읽는 것 · `r5` 처럼 카드가 아닌 r<n> 글을 가리는 것(판정이 바뀌므로 따로 카드)
- 알려진 한계(DA BYZ 310229): ft2-keeper-notify-recipient 의 판독 불가·실패 지문 때문에 [다음 막힘] 이 실제로 닿는 날이 다음 날로 밀릴 수 있다

## 완료 조건
1. [x] 나노: 커밋 1 기준판 FAIL 원문 — 기준판 2b5037d1 에서 4칸 Red(나노 aifp 5679): ㉟가 `AssertionError ['판정 불가 harness r9201-plain 선행 줄 판독 불가 — 건너뜀']`(까닭·고칠 꼴 없음) · ㉟바 `AssertionError []`([다음 막힘] 0통 · 기대 1통) · ㉟차 `AssertionError ([], ['판정 불가 harness r9201-plain 선행 줄 판독 불가 — 건너뜀'])`(쪽지 0통 · 로그 1줄 · 기대 2통·2줄) · ㉟타 `AssertionError ['… 판독 불가 — 건너뜀']`(까닭 없음 · 기대 «루트에 없는 번호 r9100 r9101»)
2. [x] 나노: 새 시험 전체 rc0 · 걸린 초 — 나노 = 21 passed 63초 rc=0(aifp 5679) · rebase 뒤 head 093824d7 에서 21 passed 66.95초 rc=0(aifp 5709 · 70초 상한까지 3초) · DA 직접(311566) = 성공 20칸 뒤 70초 rc124 · M58 판정 불가(«전체 21 PASS/rc0 주장 없음») = 전체 rc0 의 근거는 나노 제출 값이다
3. [x] 나노: 변이 M39 → ㉟가·㉟라 FAIL · M40 → ㉟마 FAIL · M41 → ㉟바 FAIL · M56 → ㉟파 FAIL · M57 → ㉟차·㉟카 FAIL · M58 → ㉟타 FAIL — 나노 «변이 M39·M40·M41·M56·M57·M58 6이 각각 지정 사례를 FAIL 시킴»(aifp 5679) · DA 직접 = M39·M40·M41·M56·M57 검출 · M58 은 70초 상한에 걸려 판정 불가(311566) = M58 의 근거는 나노 제출 값이다 · 변이별 원문 줄은 두 원문에 없다
4. [x] 나노: 회귀 rc0 — 나노(aifp 5679) = r2027 9 passed 20초 · r1871 26 passed 68초 · r1913 14 passed · r1939 9 passed · launch-failed 24 passed · penalty 16 passed · rebase 뒤(aifp 5709) test_new_card_hold 9 passed 19.10초 · r2027 9 passed 17.06초 · DA 직접(311566) = r2027 9 · 다음 카드 26(68.4초) · 빈 칸 14 · 접수 상한 9 · L9 7 passed 모두 rc0 · 정합 변경 1건 = r2027 시험 T3 기대 줄과 변이 M2 글자를 I2 줄 꼴에 맞춤(DA «막는 판정·변이 검출 의도 축소 없음»)
5. [x] arch: DA 인수 칸 원문 확인 = 상태 저장 뒤 keeper 다시 만듦 → 변화 없음 발신 0 → 그 뒤 X 재발 1통(㉟거) · notify 성공·실패·넘김 구분(㉟파) — aifp-ft-arch-pi#20 · 2026-11-16 05:24 · 착지 b70abbf6 의 git archive 사본에서 `python3.11 -m pytest "tests/test_prereq_unreadable_once.py::test_case[㉟거]" "…::test_case[㉟파]" -q` = 2 passed 10.74초 · 읽은 단언: ㉟거 c_geo = 첫 바퀴 [다음 막힘] 1 → 새 keeper(상태 파일 그대로) 바퀴 = 쪽지 1 그대로·로그 1줄 그대로(발신 0) → «선행: 없음» 으로 고친 바퀴 쪽지 1 → 다시 글로 바꾼 바퀴 = 쪽지 2·로그 2줄(재발 1통) / ㉟파 c_pa = X 성공 1통 → Y 가 되고 send rc 3 = 보냄 2(실패 · told 그대로) → 같은 날 다음 바퀴 2 그대로(실패 지문 = 재시도 0) → 날짜 바뀐 바퀴·넘김 갈래 · DA(311566) «㉟거·㉟파 는 상한 전에 통과»
6. [x] 팀장: PR 착지 sha · 설치 판 — PR #1336 squash b70abbf6821b535077494f2083c1a69626387963(head 093824d7 · gh pr view 로 대조) · 설치 = ft2 2.0.69 rc 0(harness#292 · 팀장 aifp 5727) · arch 읽기 확인(aifp-ft-arch-pi#20 · 2026-11-16 05:24): install-log 2026-11-15T20:13:27Z(05:13:27 KST) op install version 2.0.69 prev 2.0.68 rc 0 · CURRENT = 2.0.69 · PACKAGE.json source sha 017fe2cf(b70abbf6 은 그 조상 · rc 0) · 설치본 adapters/pi/keeper_next.py = b70abbf6 판과 cmp 0
7. [~] arch: 설치 뒤 1시간 keeper 로그 실측 1줄(선행 줄 판독 불가 줄 수 ≤ 그때 선행불명 카드 수 · 둘째 바퀴부터 0) + [다음 막힘] BYZ seq — 중간값(aifp-ft-arch-pi#20 · 2026-11-16 05:24 · 설치 뒤 9분 · 바퀴 6 · BYZ 읽기만 · 1시간이 차면 다시 잰다): 설치 앞 오늘 00:00~05:13 «선행 줄 판독 불가» 368줄(같은 카드가 바퀴마다 되풀이) → 설치 뒤 38줄 = 카드 38장 × 1줄(05:14 에 20줄 · 05:18 에 harness 18줄) · 그 뒤 바퀴 0줄 · state.json prereq_seen 38칸(harness 18 · v65 7 · cfo 4 · chatbot 4 · knowledge 4 · ops 1) = 줄 수 ≤ 카드 수 · 줄 꼴 원문 `판정 불가 cfo cfo-2605-s6b-sub-renewal-live 선행 줄 판독 불가(번호 참조 없음) — 건너뜀 · 고칠 꼴 «- 선행: 없음» 또는 «- 선행: r<번호>»` · [다음 막힘] BYZ seq = 311695(cfo 4장) · 311697(knowledge 4장) · 311698(ops 1장) · 311711(v65 7장) · 311726(harness 18장) + chatbot 4장은 팀장이 없어 harness master 앞 «[긴급] chatbot 팀장 없음 · 못 전한 keeper 판정 1건» 묶음 311712 로 감 · prereq_told 6팀 = prereq_now 의 지문과 같음(선행불명 0장인 feature·planner 는 빈 묶음)

## 계약↔시험 대응표
| 계약 | 시험 |
|---|---|
| I1·I2 값·까닭 바뀔 때만 | ㉟가 글뿐인 선행 1장 · 두 바퀴 → 1줄(까닭 번호 참조 없음 · 고칠 꼴) · 둘째 0줄 · submit 0 / ㉟나 글을 바꿈 → 1줄 다시 / ㉟다 `r5 착지` · r5 없음 → 까닭 루트에 없는 번호 r5 / ㉟타 `r100 r101` 둘 다 없음 → 다음 바퀴 r100 생김 → 1줄 다시(까닭 r101) · 쪽지 2통 / M39 · M58 |
| I9 재기동 | ㉟라 keeper 다시 만듦(상태 파일 그대로) → 0줄 / ㉟거 X 쪽지 성공 → keeper 다시 만듦 → 변화 없음 쪽지 0 → 해소 뒤 X 재발 → 1통 |
| I4 기억 치우기 | ㉟마 `없음` 으로 고침 → 고름 → 다시 글 → 1줄 / M40 |
| I5 쪽지 | ㉟바 선행불명 2장 + 고를 카드 1장 → [다음 막힘] 1통 · submit 1 · 둘째 바퀴 0 / ㉟사 1장 더 → 1통 다시 / ㉟아 5장 → 이름 3개 · 수 5 / M41 |
| I3 판정 그대로 | ㉟자 `r100` 이 대기에 있음 → 선행 · 줄 0 / 완성에 있음 → 열림 |
| I6~I8 전이와 전송 성공 분리 | ㉟차 같은 날 X 성공 → 해소 → X → 2통 / ㉟카 X → Y → X 모두 성공 → 3통 / ㉟파 Y send rc 3 → 같은 날 send 1회 · 날짜 바뀐 바퀴 1 / 넘김이면 다음 바퀴 1 / ㉟하 Y 실패 → 다시 X → 쪽지 0 / M56 · M57 |

## 상태
- base_sha: 2b5037d160d118defab9c00b760a625055d33b03 (spawn 2026-11-16)
- 2026-11-16 · aifp-ft-arch-pi#17 씀(aifp 5410 ③ · 5412) · 대기 · 설계 r2 = DA 대행 APPROVE-DESIGN(BYZ 310229) · 선행 = ft2-keeper-notify-recipient · ft2-launch-failed-end 착지
- 2026-11-16 04:35 — 대기→진행 · 좌석 aifp-ft-nano-ft2-prereq-unreadable-once#0
- [배정 불명] 불명(scope 표 없음 opengateway/deepseek/deepseek-v4.1-flash-ultrafast)
- 2026-11-16 05:24 · aifp-ft-arch-pi#20 착지 줄 씀(팀장 aifp 5727) · 조건 1~6 [x] · 조건 7 [~] = 설치 뒤 9분 중간값(1시간 뒤 다시) · rebase: 나노 aifp 5709 = 충돌 1파일 CONTRACT.md(앞 착지 §11 보존 · 이 카드 절 §11 → §12) · 동작 변경 0
- DA 판정: APPROVE-IMPL 311566(승인 sha 42c688cd · 사본 .fable-team/state/team-main/aifp-ft/DA-prereq-once-impl-approve-311566/verdict.md · 수용 반례 0 · 판정값 2016조합 같음 · 신규 20칸 통과 뒤 70초 rc124 · M58 판정 불가) + rebase 재확인 APPROVE-IMPL 311650(승인 sha 093824d7 · 사본 DA-prereq-rebase-impl-approve-311650/verdict.md · 선행불명 함수 AST 같음 · 신규 행위 변경 0 · 시험 반복 안 함) · 알려진 한계 = notify 실패 지문 때문에 같은 실패의 재시도가 다음 날로 밀릴 수 있다
- 세트 정정(나노 aifp 5709 · 팀장 aifp 5727): 아래 세트 줄의 42c688cd 는 rebase 앞 head 다 · PR #1336 head 와 DA 재확인 sha 는 093824d7 이다 · 닫기 도구가 읽는 세트 = 맨 끝 줄
- 세트: 42c688cddf290ea0712c546a307a7a29ae3f1b6e · 시험: python3.11 -m pytest feature-pack/fable-team/ft2/tests/test_prereq_unreadable_once.py -q (21 passed 63초) rc=0 · 이슈: 0
- 완료: aifp-ft-nano-ft2-prereq-unreadable-once#0 · 한 일: ft2 keeper 선행불명 I1~I9 구현 + 새 시험 15칸·변이 6 + 계약 §11·사례 §9·설계 정본(커밋 9a45f2dc fc9f93ae 42c688cd) · 산출: nano/ft2-prereq-unreadable-once@42c688cddf · 병합 상태: 착지 전(push 전) · 남은 일: 없음
- 세트: 093824d79e68fcafc52666300bc105c91705d79c · 시험: python3.11 -m pytest feature-pack/fable-team/ft2/tests/test_prereq_unreadable_once.py -q (21 passed 66.95초) rc=0 · 이슈: 0
