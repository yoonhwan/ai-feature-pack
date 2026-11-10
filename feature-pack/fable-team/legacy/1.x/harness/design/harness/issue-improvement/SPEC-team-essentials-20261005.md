# SPEC — 팀 구성 필수 요소: 시험 묶음 1개 = tester+checker 역할 + bts·poller 사용 (r7 · ft-harness-arch#2 · 2026-10-05 · 조각 P7)

> MERGED 반영 r+1 (C11 · 2026-10-06): §1-C 묶음 보고에 증거 등급 2값 칸(충돌 ⑦) · §3 명부 행 `test_bundle.mode` 5값(충돌 ⑫).

> **건드리는 정본**: P2 `SPEC-main-orch-tree` §3 트리(팀별 시험 묶음 자리) · P3 `SPEC-roles-mission-flow` §3-B P3-3(시험 lane · 보고 수신) · P5 `SPEC-planner-issue-queue` §2-B ④⑤(차분/최종 게이트) · `ft-role-spawn.sh:15`(역할 목록) · 팀 `seats-<x>.json`(시험 묶음 선언 칸). **문서 수정은 합치기 때 — 지금은 정정 후보 표 + 해소안만.**
> **전제 조각**: P2(37e19724b5) · P3(8fae5ab751 r4) · P5(8fae5ab751 r5) · P6(a2b5523a05 · 역할 예약어 10 에 `tester`·`checker` 포함).
> **핵심 한 줄 기여**(GOAL-harness 원문 7): 쪼개서 동시에 돌린 결과는 **press 가 필요한 작업·플랜마다 시험 묶음 1개**가 같은 세트에서 돌리고(tester) · 4축 사실을 모아(checker 역할) · 3자 대조(bts)·화면 관측(poller)으로 닫아 **architect 에게 바로 올린다** — 묶음을 «하나»로 두는 이유가 바로 «빠르게 수집→보고»다(오빠 10-05). 묶음은 상시 좌석이 아니라 **메인 하네스(팀 오케)가 press 필요 사건에 열고 끝나면 닫는다** — 동시 처리 폭을 좌석 수가 아니라 «열고 닫는 사건» 으로 낸다.
>
> 골 원문(GOAL-harness.md 복붙):
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
> 정말 많은 양의 이슈와 테스트, 그리고 큰 병렬적인 메인 플랜(메인 기획)을 얼마나 잘 수행해내느냐에 핵심이 달려 있는 거예요. 지금 이 골(Goal)들은 그 세부 항목들을 다 잘 처리해서, 결국엔 그 루트인 큰일을 얼마나 별개로 쪼개서 동시에 아주 잘 해결하느냐에 달려 있는 거죠. 이게 기획에 반영되어야 해요.
>
> 골의 축: 표 A(모니터) · 원문 7 핵심 한 줄(쪼갠 작업을 동시에 시험하는 폭). 오빠 지시(10-05): 「tester, checker, bts, poller 놓치면 안 된다 팀 구성에」 → 「tester+checker(bts,poller) 하나의 구성으로 v65 에서 단순화하고 빠르게 수집 보고 아키텍트에게 올린 이게 유효함. press test 가 필요한 작업이나 플랜에」 → 「필요하면 메인 하네스가 필요시 배분」. 발주 = ops#2 #57013 → ORDER-essentials-bundle(#57036). 닫는 증거 = DA APPROVE + 오빠 「맞다」.
> r6→r7(DA r3 `DA-team-essentials-r3.md` HOLD 2 → 직렬 DA 종료 · 문서 정정만): ①**논리 완료 ≠ 물리 닫기** — 묶음 `close_event` 는 논리 완료(결과 분류 + ack)이고 좌석 세션은 keep-last-2·HIL 아래 **`closed-retained`** 로 남을 수 있다(남은 세션 = 누수 아님 · 물리 수명 소유 = master) ②**결과 분류**: PASS 수락 → 완료 · FAIL/미측정 → 같은 묶음 **`reopen`**(카드당 묶음 1 · 멱등) · ack 누락 → `pending` + P5 Q-4 10분 상위화 · 좌석 소실 → `pending`(오케 복구) ③tester#13 「유휴 22h」 = mbox 마지막 행 기준 **추론**(프로세스 증거 아님).
> r5→r6(오빠 정정 · nano `FACTS-team-essentials-r6` G1~G4 사실 83%): ①넷 따로 → **시험 묶음 1개**(tester 좌석 1 이 checker 역할 겸임 · bts·poller 는 묶음이 쓰는 스킬·도구) ②배분 주체 = **메인 하네스(팀 오케)** · 배분 사건 = press 필요 표기 카드/플랜 출범 · 닫는 사건 = press 창 종료 + 좌석 닫음 ③적용 범위 = press 필요 작업·플랜만(비-press 팀 = 기존 대체 축 + 사유) ④보고 수신 = **architect**(현행 tester→master 는 정정 후보) · §1·§3·§4 재작성 · Q1·Q2 를 묶음 단위로.
> r4→r5: poller 러너 실체 = `tcc8_completion_press.py` · mbox 「BTS」 0행. r3→r4(ops #57025): 「측정된 관측」 정의 · 주기 실행기 별도 이름 · 프로필 차분/최종 · Q1 = 합칠 때 오빠 질문. r2→r3(DA r2 HOLD 2 → 직렬 DA 종료): poller 증거 = 그 회차 세트의 press 구간 표본 · 비-press 최종 게이트도 같은 프로필. r1→r2(DA r1 HOLD 3): checker 명부 행 0 · poller env 기록 · 4축은 press 팀에만.
> 실측 = arch#1 15:5x(E) + nano#1 15:56(E1~E3) · 16:53(G1~G4). [사실]/[제안]/[추측].

## 1. 시험 묶음 1개 — 정체·구성원·배분 [사실 + 제안]
### 1-A 구성원 (좌석 수는 사실대로 = **좌석 1**)
| 구성원 | 정체 | 묶음 안의 자리 | 근거 |
|---|---|---|---|
| **tester** | **좌석 1**(세션) — press 러너를 쥐는 손 · 시험 설계·실행·재현 · 구현 수정 0 | 묶음의 **유일한 좌석** · press 를 돌리고 4축을 모으고 보고를 쓴다 | `~/.claude/agents/ft-tester.md` · `ft-role-spawn.sh:15 tester` · v65 `seats.json` role=tester 12행 전부 `ft-v65-tester-claude#N`(sonnet-5-5[1m]) [사실] |
| **checker 역할** | **역할**(좌석 아님) — 4축 사실 확인 · 「checker 4축 = FE 콘솔·poller/DOM·worker 로그·저장소」 | **tester 좌석이 겸임** — v65 실측: 최근 press 2회차(`evid-tester9`·`evid-tester10`) 4축 파일 발신 = tester 단독 · 별도 checker 발신 0 · 명부 role=checker 0 · 겸임 전례 좌석명 `ft-v65-tester-checker-ds#19/#20` | `FACTS-…-r6` G1·G2 [사실] · 겸임 해석 [추측] |
| **bts** | **스킬**(좌석 아님) — 로그·아키텍처·코드 3자 대조 + N-회차 나선 · 루프 소유 = architect | 묶음이 **쓰는** 스킬 — 4축 사실표가 어긋나면 architect 가 bts 루프를 열고 묶음이 회차 사실을 공급 | `.claude/skills/bts/SKILL.md` · `design/BTS-N-ROUND-LOOP-STANDARD.md` · mbox 「BTS」 0행 [사실] |
| **poller** | **도구**(러너 안) — press 중 DOM 변화를 시간축으로 기록(`poller_dom.jsonl`) · 「발행했다 ≠ 화면이 움직였다」의 유일한 축 | 묶음이 **켜는** 도구 — tcc8 러너가 기동(`★poller_dom★ 기동 pid=… → …/poller_dom.jsonl` · `pump start (poller live capture)`) · 스냅샷 훅 `_append_ptt_dom_snapshot` 은 env `BYZ_BTS_DOM_JSONL` · 유효 관측 = 그 회차 세트의 press 구간 표본 ≥1 + 소비자(`m1_round_timeline`·press-gate 축) 호환 | `tests/e2e/tcc8_completion_press.py:144` · `realtime_multi_e2e.py:1757~1760` · `runner-seq.log` 머리 [사실] |

### 1-B 배분 — 누가 · 어느 사건에 열고 · 어느 사건에 닫나 [제안 · 오빠 「필요하면 메인 하네스가 필요시 배분」]
| 항목 | 규칙 | 지금(v65 실측) |
|---|---|---|
| **배분 주체** | **메인 하네스 = 그 팀 오케**(master) 가 묶음을 연다 — architect 는 「press 필요」를 설계에 표기할 뿐 좌석을 열지 않는다(Master 금지 셋·arch 소환 금지 그대로) | 열린 계기 = master#136 → tester#13 「Seatbelt 역할 교체」(seq 56728 · 10-04 17:20) · 「tester 열어」 발주 0 [사실] |
| **배분 사건(열기)** | ①카드/플랜에 **「press 필요」 표기**(architect 설계 or P5 큐 행 종류) ②그 카드가 **활성** 이 되는 순간(P3 P1-2 배분 쌍 · P5 Q-1 `활성`) ③오케가 `ft-role-spawn.sh tester` 로 묶음 좌석 1 을 열고 명부 선언 칸(§3)을 채운다 — **press 필요 표기가 없는 카드에는 묶음을 열지 않는다** | 명부 `created` 필드 0 · 세션 시각으로만 [사실] |
| **닫는 사건(논리 완료)** | 묶음 식별 = **카드/플랜 1개당 묶음 1개**(같은 카드가 활성인 동안 다시 열지 않는다 · 멱등). 최종 게이트 보고가 architect 에 도착하면 **결과를 분류**한다: ⓐ **PASS 수락**(러너 종료 + P3 P2-3 press 허가 해제 뒤) → `close_event` = architect 수락 회신 seq → 오케가 「press 창 종료」 와 같은 턴에 명부 `state=closed` 기록 ⓑ **FAIL / 미측정** → architect 가 bts 루프 → 나노 수정 → **같은 묶음 `state=reopen`** → ④ 재진입(새 묶음 열지 않음 · 재배분 소유 = 오케) ⓒ **ack 누락**(architect 또는 오케 회신 없음) → `state=pending` · P5 Q-4 「10분 무응답 = 상위화」 그대로 · Issue 클리어 금지 ⓓ **좌석 소실·취소** → `state=pending` · 오케 복구(완료로 간주 0) | 닫힌 계기 = 「press 창 종료(tester#13 70 완료)」(seq 56818) · 「tester 닫음」 문구 0 [사실] · tester#13 마지막 mbox 행 56899(10-04 18:36) 뒤 발신 0 → 유휴 ≈ 22h 는 **추론**(프로세스 증거 아님) |
| **물리 닫기(좌석 세션)** | 논리 완료와 **분리** — `state=closed` 뒤 좌석은 **`closed-retained`**(활성 작업에서 제외 · 재사용은 오케가 새 카드 `open_event` 로 명시) 로 남을 수 있다 · 세션 kill 은 **master 소유** · keep-last-2 하한·HIL 그대로(묶음 좌석이 1개뿐이면 kill 하지 않는다) · architect 수락은 좌석을 죽이지 않고 **집행 요청 1건**을 오케에 보낼 뿐 | 역할 좌석 kill 규칙 = 글로벌 HIL 「keep-last-2」 [사실] — 남은 tester 세션 자체는 누수가 아니다(DA r3 ①) |
| **적용 범위** | **press test 가 필요한 작업·플랜에만** · 비-press 팀(cfo·ccu·issues·harness)은 묶음을 열지 않고 **기존 「대체 축 + 사유」**(§2) 그대로 | cfo·ccu 묶음 0 · 대체 축 = API 응답·PG 행 / SSE 수신 시각 [사실] |
| **보고 수신** | **architect**(루프 소유) 가 받는다 — 묶음 → arch 직접 · master 에는 집행 요청(좌석·커밋·push)·사람 판정만(COMM-GUIDE 「master 로는 두 가지만」) | **현행은 tester → master**(최근 11행 전부 master · tester→arch 19행은 옛 seq ≤14851) [사실] → 오빠 원문과 다름 · §3 정정 후보 |

### 1-C 묶음이 올리는 보고 형식 [사실 · v65 정본 복붙]
`READ-tester11-s5-3bubble-press.md:18-24` 「## 3. 4자 표 (시간 열 + 분모)」 — 열 = `축 | 사실 | 시간` · 행 = `아키텍처 문서 | 코드 | 로그(worker) | 화면(poller)`. 4축 파일 대응 = FE 콘솔 `runner-seq.log(★FE-CONSOLE★)` · poller/DOM `poller_capture_end.json`+`final_dom.png` · worker `worker_log_span.txt` · **저장소(Redis) 전용 파일 없음**(로그 안 durable 라인) [사실]. 묶음 보고 1건 = 이 4자 표 + 분모(유효 회차 n/m) + 회차 세트(후보 sha·러너 시작 시각) 1줄 + 증거 등급 1칸(**2값**: `E2E 통과` / `contract guard only` — byz-e2e Hard Rule #0-1·#2 현행 그대로 · 오빠 값 P9 Q1 · MERGED ⑦) · 「관측 0」은 「정상」이라 쓰지 않는다(r3 그대로).

## 2. 팀별 지금 상태 [사실]
| 팀 | 시험 묶음(tester 좌석) | checker 역할 | bts | poller |
|---|---|---|---|---|
| v65 | `ft-v65-tester-claude#13` 살아 있음(마지막 mbox 행 10-04 18:36 · 논리 닫는 사건 기록 0) | tester 가 겸임(4축 파일 발신 tester 단독) | 스킬 · arch 루프 소유 | tcc8 러너가 기동 · 산출 `evid-tester*/` |
| cfo | **묶음 0**(오디오 press 없음) | 0 | 스킬 | **해당 없음** → 대체 축 API 응답·PG 행 |
| ccu | 0(명부 없음) | 0 | 스킬 | **대체** = SSE 수신 시각(DESIGN-ccu-stress-infra:63 · FE 없음) |
| harness·issues·planner | 0 · issues 는 `repro-e2e#0`(main HEAD 재현 · tester 성격) | 0 | 스킬 | 해당 없음(문서·Issue 팀) |
[사실] 묶음은 v65 만 · 보고는 master 로 · 닫는 사건은 어느 팀에도 0.

## 3. 정정 후보 표 (묶음 단위 · 문서 수정은 합치기 때)
| 조각·자리 | 지금 적힌 것 | 빠진 것 | 정정 후보 [제안] |
|---|---|---|---|
| P2 §3 트리 | v65 아래 tester ★ · 「da·checker 는 필요할 때」 | 묶음 «자리»·열림/닫힘 상태 | 각 팀 아래 **1줄** `시험묶음: <tester 좌석명 · 열린 카드#> \| 닫힘(마지막 닫는 사건 seq) \| 해당 없음(대체 축 <이름>)` — checker 줄 삭제(역할이지 좌석 아님) · bts·poller 는 묶음 줄 안 괄호 |
| P2 표 1 (오케 리스트) | 팀 열 7 | 「시험 묶음」 열 | 열 1 추가 「시험 묶음(열림/닫힘 · 좌석)」 — 생성기(P1)가 명부 선언 칸으로 채움 |
| P3 §3-B P3-3 | press 석 = tester 또는 오케 | 오케가 press 하는 길 · 보고 수신 | ①press 는 **묶음 tester 좌석만**(오케·나노 press 금지) ②묶음은 오케가 press 필요 카드 활성에 열고(1-B) ③**보고 수신 = architect**(tester→arch 직접 · master 에는 집행만) ④4자 표(#8 RULE)는 press 회차마다 · 쓰는 손 = 묶음 tester(checker 역할 겸임) |
| P3 §4-B 클리어 ③ | repro PASS 코멘트(type:bug) | 누가 PASS 를 찍나 | press 필요 카드 = 그 팀 묶음 tester · 비-press = issues `repro-e2e#0` 또는 그 팀 대체 축 손(오케·나노 아님 — 작성 lane 과 검토 lane 분리) |
| P5 §2-B ④⑤ | 차분 게이트 · 최종 게이트 = tester · DA | checker 자리 · bts 시점 · 보고 수신 | ④ 차분 = **묶음** 실행 + 4축 사실표(press 팀) / 대체 축 표(비-press) → **architect 수신** · 어긋남이면 architect 가 bts 루프(N 회차) → 나노 수정 → ④ 재진입 · ⑤ 최종 = 같은 프로필: press 팀 = 묶음 전체 세트 + 3버블(poller 유효 관측) + DA · 비-press = 전체 세트 + 대체 축 증거 + DA · **⑤ 결과를 architect 가 분류(PASS 수락 → 묶음 논리 완료 · FAIL/미측정 → `reopen` · ack 누락 → `pending`)**(1-B) — 수락은 P3/P5 소유 오케의 클리어 ①~⑤·후보 sha 게이트를 대체하지 않는다 |
| P5 §2-C 지표 「시험 병렬」 | 차분:전체 비 · 전체 세트 소요 | 묶음 열림/닫힘 · 관측 커버 | 지표 3 추가: ①press 필요 카드 중 묶음이 열린 비율(=1) ②닫는 사건이 기록된 묶음 비율(=1 · 지금 0) ③press 회차 중 유효 `poller_dom.jsonl` + 4자 표 있는 비율(=1) · 비-press 팀 = 대체 축 표 있는 단위 비율 |
| `ft-role-spawn.sh:15` | `master\|da\|pm\|arch\|tester` | — | **그대로**(checker 역할 추가 불필요 — 묶음 = tester 1) · 구현 조각에서 `tester` 호출 시 명부 선언 칸(아래) 자동 기입 |
| 명부 생성기(P1) · 팀 개설(STRUCTURE §2 ①~⑥) | 좌석 1(오케) | 묶음 선언 | 개설 ③ `seats-<x>.json` 에 **선언 1칸** `test_bundle` = `{mode: press-mic\|press-api\|press-inject\|alt\|none, card: <카드#>, seat: <tester 키\|null>, state: open\|reopen\|pending\|closed\|closed-retained, open_event: <seq>, close_event: <seq\|null>, alt_axes: [...], bts_owner: arch}` — `mode` 빈칸 = REJECT(`press-inject` 는 완성 후 예약값 — P9 · MERGED ⑫) · `press-*` 면 `card`·`seat`·`open_event` 셋 다 · 같은 `card` 로 두 번째 open = REJECT(멱등) · `state=open\|reopen` 인데 좌석 세션이 없으면 → `pending` 경보(오케 복구) · `closed-retained` 세션은 경보 아님 |
| 보고 라우팅(글로벌 COMM-GUIDE 4항) | master 로는 집행·사람 판정 두 가지 | tester 보고의 수신 | 묶음 보고 = architect 수신으로 명시(현행 v65 tester→master 11행은 라우팅 어긋남 — 구현 조각에서 tester 부팅 발주 템플릿의 보고 수신처 = arch) |

## 4. 오빠 값이 필요한 질문 (최대 3 · 추천안 첫째 · ops 가 인터뷰)
| # | 질문 | 추천 | 대안 |
|---|---|---|---|
| Q1 | **시험 묶음의 수명** — press 필요 카드가 활성될 때 메인 오케가 열고, PASS 수락이면 그 턴에 논리 닫음(`closed`) · 좌석 세션은 keep-last-2 아래 `closed-retained` 로 남겨 다음 press 카드에 재사용 | **카드 단위로 열고 논리 닫음 · 좌석은 유지·재사용**(1-B) | 팀당 상시 1(항상 `open` · 카드 식별 없음 — 지금 v65 방식) |
| Q2 | **묶음 보고 수신처** — 오빠 원문 「아키텍트에게 올린」 vs 현행 tester→master 11행 | **architect 직접**(master 에는 좌석 열기·닫기·push 집행만) | 현행 유지(tester→master→arch relay) |
| Q3 | **4축 중 저장소(Redis) 축** — v65 4자 표는 문서·코드·worker 로그·화면 4행이고 Redis 전용 파일 없음 | **4자 표 그대로**(저장소 사실은 worker 로그 durable 라인으로 인정 · 별 파일 요구 0) | 저장소 축 파일 1개를 묶음 산출 필수에 추가 |

## 5. DA 기록
- r1 `DA-team-essentials-r1.md` HOLD 3 → r2. r2 `DA-team-essentials-r2.md` HOLD 2 → 직렬 DA 종료 → r3~r5 문서 정정 · ops 수락. r6(오빠 정정 · 묶음 1) → **r3 `DA-team-essentials-r3.md` HOLD 2**(①논리 완료 vs 물리 닫기 미분리 ②보고 도착만으로 닫힘 — 결과 분류·ack 없음) → **HOLD 2 = 직렬 DA 종료 → r7 문서 정정(1-B 분리 · 결과 4분류 · 명부 state) → ops 수락 경로**(ORDER-essentials-bundle). DA 가 수락한 것: 보고 수신 arch = COMM-GUIDE·P3 와 충돌 0 · tester 겸임 = 작성·검토 분리 위반 0. 구현 후보: 명부 `test_bundle` 선언 칸(state 5값) + lint · tester 부팅 템플릿 보고 수신처 = arch · 결과 분류 + 논리 close 기록 · P5 지표 3.
