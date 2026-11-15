# 설계 · 카드 초안 — 문제 ③ Slack 접수(dict-work)가 접수 칸을 영구 점유 (aifp-ft-arch-pi#16 · 2026-11-16)

- 발주: 팀장 #17 aifp 5310 ③ · 덧붙임 5313(오빠 00:43 «또 다시» · issues «용량 부족» 13회) · 발주 전문 `orders/ORDER-arch16-three-problems-20261116.md`
- 상태: 설계 r2(DA 대행 byz-harness-da-codex#11 HOLD-DESIGN 1/3 반영 · aifp 5328 · 5331 · 판정 전문 `/private/tmp/da-aifp-p3-309656/verdict.md` · r1 sha256 b08b94f1…7829) · 카드 = `design/aifp/indices/대기/ft2-slack-accept-capacity.md` · 구현 = 나노 1석
- r2 에서 바뀐 곳: §3-2 재접수 칸 셈(R1) · §3-4 드러냄 1줄을 뺌(Q2 · 후속 카드) · §5 ㉖가 사후 remaining 9 · ㉖나 기준판·제안판 값 · ㉖마 보강 · 회귀 fixture 기대(R2 · Q3) · §3 머리에 «dict = 글 영수» 계약 문장(Q1)
- 옮김: 2026-11-16 · aifp-ft-nano-ft2-slack-accept-capacity#0 이 구현하며 `.fable-team/state/team-main/aifp-ft/orders/DESIGN-p3-slack-accept-capacity-20261116.md`(r2)를 이 자리로 옮겼다(내용 손 0 · §3 계약 문장에 r2089 낱말만 붙임)
- 기준판: 팩 origin/main 1757addf · 대상 폴더 git log 확인(core 최신 d88ef381 r2055 · 77511fcc 보정 3 · ccad300d r1881 · 421637c1 r1824)

## 1. 실측 (읽기만 · 팩 1757addf core 로 BYZ 데이터 루트를 셈 · journal 쓰기 0)

| 팀 | remaining | capacity | 내용 |
|---|---|---|---|
| planner | 4 | 4 | 4개 전부 `slack:T0AC5HC4ENR:C0C9GRFHJE5:<ts>` · work = dict(`route`·`slack`) · 그 command 의 dispatch·complete 0 · 접수 11-15 11:23 · 12:53 · 13:35 · 16:31 |
| issues | 8 | 8 | 팀장 실측(5313): cmd 단위 7 = work dict(`{"slack": {"team": …}}`) · 마지막 11-14T18:25 |
| harness | 8 | 3 | str-work 만 · parked 6 이 용량에서 빠짐(r2055 정상 동작) |

planner 4건의 글: «상홤 프로그레스 …» · «최종 2.0 닫기 까지 통합 프로그레스 …» · «3.1 4.ok» · «상태공유». route kind = 새 업무 2 · 재개 필요 2. `slack/receive.jsonl` 은 4건 모두 `dispatched`(제출 영수)에서 끝난다.

## 2. 원인

1. 셈하는 곳: `core/record.py` `capacity()` 는 work 가 str 이 아닌 command 를 `"cmd:" + command` 1칸으로 센다(r2055 §4.1 «work 없는 command = 1칸»).
2. 비우는 곳은 str-work 만 본다.
   - `keeper_settle.accept_only` = `isinstance(work, str)` 가 아니면 건너뜀(보정 3 · 77511fcc ㉕). 판정 줄 0.
   - core `park` · `parked` 접기 = work 문자열 키. dict-work 는 대상이 못 된다.
   - `close_next._pick_next` = dict-work 제외(r1881).
3. dict-work 접수의 끝은 하나뿐이다: 같은 thread 에 탱크 봇 답글이 달릴 때 `reply_done.settle` 이 `Dispatch.complete` 를 부른다(r1872 · r1927).
   - 답을 채널 최상위 메시지로 올리면(오빠 11-15 «상태 공유는 메시지로 · thread 는 집중 논의만») 그 끝이 오지 않는다. planner 4건이 이 꼴이다.
   - issues 팀 접수(`wiring.record_issue`)는 기록만 한다(깨움 0 · 답글 0). 끝이 설계에 없다.
4. 결과: dict-work 접수는 칸을 쥐고 놓는 길이 없다. 8개가 차면 그 팀의 모든 접수(Slack 글 · keeper fill)가 «용량 부족» 이 된다.

보정 3 과의 관계: 같은 줄기다. 보정 3 은 dict-work 때문에 keeper 가 죽는 것(TypeError)만 막았고 «대상 밖» 으로 뒀다. 셈하는 쪽은 그대로 1칸으로 세서 틈이 남았다.

## 3. 고침 (한 기준: 용량 칸 = 카드 단위 = str-work 접수)

계약 문장(Q1): accept 줄의 work 가 dict 이면 그 줄은 «글 영수» 다. 용량 단위가 아니다. work 가 str 인 줄 · work 가 None 인 줄 · parked 의 동작은 지금 그대로다.

Slack 접수(dict-work)는 «글 영수» 다. 카드가 아니다. 그 글에서 나온 일은 따로 str-work 접수(keeper-next-… · 카드)로 들어와 칸을 쥔다. 그래서 dict-work 는 용량 셈에서 뺀다. 의무 장부는 그대로 둔다.

| # | 자리 | 바꿈 | 안 바꿈 |
|---|---|---|---|
| 1 | `core/record.py` `capacity()` | accept 줄의 work 가 dict 인 command 는 용량 단위를 만들지 않는다 | `remaining()` 손 0(마감 · 재개 · reopen 은 지금 값 그대로) · work 가 None 인 command(pending 만 남은 것 · work 없이 낸 접수)는 지금처럼 1칸 |
| 2 | `adapters/slack/reply_done.py` `_requeue` | 빈 칸을 처음 한 번 세고 성공마다 1씩 빼는 셈(`room − 1`)을 버린다. FULL 글마다 그때의 실제 용량(`capacity − len(record.capacity(다시 읽은 state · records))`)과 재접수 입구(`_recover`)의 영수로 판단한다. 영수가 «용량 부족» 이면 그 뒤 미요청 글은 건너뛴다(지금 r1938 규칙과 같은 뜻). dict-work 재접수는 용량을 쓰지 않으므로 용량 때문에 남는 글이 없다 | 재접수 순서(ts 오래된 순) · 멱등(같은 command 재부여 0) · settle 대조(desk 처리 요청은 칸 0 이어도 settled) 손 0 |
| 3 | `adapters/pi/full_alert.py` `remaining()` | 알림 판정 값이 `proj["remaining"]` 이다. intake 와 같은 `proj["capacity"]` 로 맞춘다(없으면 `remaining` · `keeper_next.intake_open` 과 같은 읽기) | 문구 · 서명 · 중복 억제 · 풀림 규칙 손 0 |

1~3 으로 발주 기준(영구 점유 0)이 닫힌다. r1 의 4번(keeper 드러냄 1줄 `ACCEPT-ONLY-SLACK`)은 이 카드에서 뺐다(DA Q2). 후속 카드로 따로 낸다. 넣을 때는 값이 바뀌는 지문을 «건수 · command 집합 · 최초 시각» 으로 잡는다(매 분 늘어나는 나이는 지문에 넣지 않는다). 답 없는 Slack 접수는 의무 장부(remaining)와 투영 `remaining` 칸에 그대로 보인다.

### 고르지 않은 길

| 길 | 버린 까닭 |
|---|---|
| dict-work 도 `PARK_IDLE` 뒤 park | park 는 str work 키 · owner · 세션 닫기와 묶여 있다. core 3곳(park · 접기 · capacity)을 넓혀야 한다. 60분 안에 글 8개가 오면 여전히 FULL 이다(harness 가 5314 에서 본 «60분 유휴 전까지 칸을 쥠» 과 같은 틈) |
| 채널 최상위 봇 글이 그 채널의 앞 접수를 complete | 답이 아닌 공지가 관계없는 요청을 닫는다. 오판 비용이 크다 |
| journal 손으로 complete | HIL · 다음 글에서 다시 쌓인다 |

## 4. 알려진 남는 것 (이 카드 밖 · 숨기지 않음)

- keeper 드러냄 1줄(`ACCEPT-ONLY-SLACK`)은 후속 카드다(DA Q2).
- 답 없는 Slack 접수는 의무 장부(remaining)에 남는다. 팀 마감 판정은 지금처럼 그 글 때문에 «남은 일 있음» 으로 본다. 최상위 답글로 답한 글을 무엇으로 닫을지는 따로 정해야 한다(오빠 · planner 판단).
- Slack 글 폭주의 상한은 journal 총량 한계(`admits_submit`)만 남는다.
- work None 접수는 1칸을 쥐고 keeper 가 보지 않는다. 지금 실측 0건이라 손대지 않는다.

## 5. 시험 (나노 · 새 파일 1개 · 임시 루트 · 시험 안에서 만든 journal · 실 runtime 쓰기 0 · 1개 70초 안)

| # | 사례 | 기준판(origin/main) | 고친 판 |
|---|---|---|---|
| ㉖가 | planner 꼴 dict-work accept 8(`{"route": {...}, "slack": {...}}`) → 9번째 Slack 접수 submit | `용량 부족` | `접수 성공` · 접수 전 capacity 0 · remaining 8 → 접수 뒤 capacity 0 · remaining 9 |
| ㉖나 | issues 꼴 dict-work accept 8(`{"slack": {"team": "planner"}}`) → str-work 접수 1 | capacity 8 · remaining 8 · `용량 부족` | 접수 전 capacity 0 · remaining 8 → `접수 성공` → capacity 1 · remaining 9 · 손 complete 0 |
| ㉖다 | dict-work 8 + str-work accept 8 → 다음 str-work 접수 | `용량 부족` | `용량 부족` · 문구의 남은 일 8 |
| ㉖라 | work None 접수 8 → 다음 접수 | `용량 부족` | `용량 부족`(r2055 §4.1 그대로) |
| ㉖마 | str-work 8 로 꽉 찬 팀에 Slack 글 9건이 와서 receive `full` 9(같은 thread 에 먼저 접수된 dict-work 1건 있음) → str-work 1건 complete(여유 1칸) → 그 thread 봇 답글 settle 1회 | 1건만 재접수 · `full` 8 남음 | 9건 전부 재접수(`requeued` 9 · ts 오래된 순 · 여유 1칸보다 많음) · receive `full` 0 · capacity 7 그대로 · 같은 settle 한 번 더 = 재접수 0(멱등) |
| ㉖바 | dict-work accept 8 인 팀 · `full_alert.remaining()` 1회 → str-work 8 접수 뒤 1회 → str-work 1 complete 뒤 1회 | 첫 호출에 꽉 참 알림 | 첫 호출 알림 0(0/8) → 둘째 꽉 참 1통(8/8) → 셋째 풀림 1통 · 같은 값 다시 호출 = 0통 |
| M7 | capacity 의 dict 제외를 뺌 | — | ㉖가 · ㉖나 · ㉖마 FAIL |
| M8 | `_requeue` 를 «처음 센 칸 − 성공 수» 로 되돌림 | — | ㉖마 FAIL(1건만 재접수 · full 8 남음 · DA R1 관측과 같은 꼴) |
| M9 | `full_alert` 값을 remaining 으로 되돌림 | — | ㉖바 FAIL |

회귀(기대값을 이 계약으로 고치는 곳 · 삭제 0 · PR 본문에 사례 이름을 적는다):

| 파일 | 고칠 전제 | 지킬 기대 |
|---|---|---|
| `test_slack_reply_completes_r1872.py` test_7 · test_8 · thread_full | dict-work 8건으로 FULL 을 만드는 fixture → str-work 포화 또는 기준판에서 만든 FULL 영수(receive `full` 줄)로 바꾼다 | 답글 범위(같은 thread · 답글 ts 이하) · 멱등 · 오래된 순서 · 복구 보호 |
| `test_core_remaining_dict_work_r1824.py` case5 | dict-work 가 용량 칸을 쥔다는 기대가 있으면 remaining 기준으로 고친다 | remaining 대조 규칙 |
| r1886 꽉 참 알림 시험 test_c1_c2_c3 | dict-work 가 다시 칸을 채운다는 기대 → str-work 재포화로 바꾼다 | 서명 · 중복 억제 · 풀림 · 재포화 |
| `test_core_park_capacity_r2055.py` · `test_settle_one_path_r2055.py`(㉕가·나·다) · `test_core_close_next_dict_work_r1881.py` | 없음 | 그대로 rc0 |

실행 = `python3.11 -m pytest`.

문서: `ft2/contracts/keeper-settle/CONTRACT.md` 용량 절에 계약 문장 1줄 · `CASES.md` ㉖ · M7 · M8 · M9 행(같은 PR).

## 6. 닫는 증거

구현 = r2089(나노 좌석) · 시험 = `feature-pack/fable-team/ft2/tests/test_slack_accept_capacity.py`(㉖가~바 · 변이 M7·M8·M9).

1. 고친 커밋(팩 main 착지 sha).
2. 설치 뒤 읽기 실측: planner capacity 0 · issues capacity = str-work 수(지금 1).
3. 오빠 다음 Slack 글에서 issues · planner «용량 부족» 0(listen.log · wire.jsonl 원문 줄).

## 7. DA 판정 기록

| 회 | 판정 | 반영 |
|---|---|---|
| 1/3 | HOLD-DESIGN(byz-harness-da-codex#11 대행 · aifp 5328) | R1 → §3-2 · ㉖마 · M8 / R2 → ㉖가 사후 remaining 9 · 회귀 fixture 표 / 필수 ㉖나 → 기준판 · 고친 판 두 칸 / Q1 동의 → 계약 문장 / Q2 → 드러냄 1줄 분리 / Q3 → ㉖바 · M9 · r1886 기대 |

보정 3 이 통과한 까닭(DA 첫 줄): Slack 접수 길 시험이 0 이었다. 셈(`record.capacity`)과 비우기(`accept_only`)를 따로 검증했다. dict TypeError 만 승인했고 용량 점유는 보지 않았다.
