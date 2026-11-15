# 인덱스: ft2-slack-accept-capacity — 끝: Slack 글 접수(work 가 dict 인 accept)가 접수 칸을 쥐지 않는다 · 용량 셈·재접수 칸 셈·꽉 참 알림이 같은 값(record.capacity)을 본다 · 오빠 다음 Slack 글에서 «용량 부족» 0
<!-- ledger: feature-pack/fable-team/legacy/1.x/harness/design/harness/GOAL-harness.md -->
- Issue: #8631 — 등록 planner#323 aifp 5348(팀장 aifp-ft-master-pi#17 발주 aifp 5310 ③ · 덧붙임 5313 · 카드 지시 5324 · planner#323 aifp 5308 · 오빠 Slack 11-16 00:42 «페이블이 해결 · 끝까지 책임» · 00:43 «또 다시»)
- 제안서: 없음 — 결함 복구(새 안 0) · 설계 1쪽 = .fable-team/state/team-main/aifp-ft/orders/DESIGN-p3-slack-accept-capacity-20261116.md(r2 · 고침 3곳 · 버린 길 3 · 시험 ㉖가~바 · 변이 M7·M8·M9 · DA 대행 1/3 HOLD-DESIGN 반영) · 착지 PR 에서 feature-pack/fable-team/design/DESIGN-ft2-slack-accept-capacity.md 로 옮긴다
- 근거: 실측 2026-11-16 00:5x(aifp-ft-arch-pi#16 · 팩 origin/main 1757addf core 를 import 해 BYZ 데이터 루트를 읽기만 함 · 쓰기 0) — planner remaining 4 · capacity 4 · 4건 전부 command `slack:T0AC5HC4ENR:C0C9GRFHJE5:<ts>` · work = dict(route·slack) · dispatch·complete 0 · 접수 11-15 11:23·12:53·13:35·16:31 · issues remaining 8 · capacity 8 중 dict-work 7(팀장 실측 5313 · 뒤에 정식 동사 complete 7회로 비움 5318 · rev 91) · 오빠 Slack 글마다 issues «용량 부족» 13회(5313)
- 원인 1줄: core/record.py capacity() 는 work 가 str 아닌 command 를 «cmd:<command>» 1칸으로 세는데, 비우는 길(keeper_settle.accept_only · core park · close_next)은 str-work 만 본다 · dict-work 접수의 끝은 같은 thread 봇 답글(reply_done.settle · r1872·r1927)뿐이라 답을 채널 최상위로 올리거나(planner) 기록만 하는 팀(issues)은 칸이 영영 안 빈다
- 앞 카드: 보정 3(팩 77511fcc · PR 1249 · accept_only work=dict TypeError)과 같은 줄기 — 보정 3 은 keeper 죽음만 막고 dict-work 를 «대상 밖» 으로 뒀다 · r1881(ccad300d close_next dict 제외) · r1824(421637c1 remaining dict 대조) · r2055(d88ef381 capacity 새 함수)
- 상태: 대기
- 설치: 있음 — ft2 판 올림 1회(팩 착지 뒤 팀장·harness 설치 묶음 · 라이브 = ~/.claude/fable-team/live/<판>/) · 되돌림 = 앞 판으로 판 전환
- 선행: DA APPROVE-DESIGN(harness DA codex#11 대행 · planner 5321 · BYZ 309656 · 1/3 HOLD-DESIGN aifp 5328 → 설계 r2 재판정 2/3) — 판정 전 나노 개설 0
- 시험 입력: 임시 루트(tmp_path) · 시험 안에서 만든 journal(실 runtime 쓰기·읽기 0) · planner 꼴 work `{"route": {"channel": "C1", "id": null, "kind": "새 업무", "thread": "<ts>"}, "slack": {"workspace": "T1", "channel": "C1", "ts": "<ts>"}}` · issues 꼴 work `{"slack": {"team": "planner"}}` · 가짜 clock · sleep 0 · 네트워크 0 · 사례 1개 70초 안
- 기준값: 기준판(origin/main) = dict-work accept 8개 뒤 capacity 8 · remaining 8 · 다음 접수 «용량 부족» → 목표 = 접수 전 capacity 0 · remaining 8 · 다음 접수 «접수 성공»(DA 대행 실측: issues 꼴 8건 뒤 str-work 접수 = 성공 · 사후 capacity 1 · remaining 9)
- 규칙: 없음 — 상시 로드 변경 0
- 규칙 상세: 하드 룰 20(외부 실패 한 함수) · 하드 룰 22(시험 70초 · 1회차 7분) · r2055 계약 ft2/contracts/keeper-settle/CONTRACT.md
- 대상: 팩 feature-pack/fable-team/ft2/core/record.py(capacity) · adapters/slack/reply_done.py(_requeue) · adapters/pi/full_alert.py(remaining 알림 값) · 새 시험 feature-pack/fable-team/ft2/tests/test_slack_accept_capacity.py · 문서 ft2/contracts/keeper-settle/CONTRACT.md·CASES.md
- 정본 영향 있음: ft2/contracts/keeper-settle/CONTRACT.md 용량 절 1줄 · CASES.md ㉖·M7·M8·M9 행 = 같은 PR(나노)
- 크기: 코드 3파일 · 새 시험 1파일 · 회귀 fixture 고침 3파일 · 문서 3파일 · PR 1개
- 배정: 좌석 aifp-ft-nano-ft2-slack-accept-capacity#0

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」. 골의 축: 6(하네스 운영 정리 — 오빠 Slack 글이 접수 칸 때문에 막히지 않는다). 이 카드의 증거 = 착지 sha + 시험 rc0 + 설치 뒤 planner capacity 0 실측 줄 + 오빠 다음 Slack 글 «용량 부족» 0 원문.

## 배경 (한 단락)
오빠가 Slack 에 글을 쓰면 수신 팀과 issues 팀 접수 장부에 accept 1줄이 남는다. 이 줄의 work 는 문자열이 아니라 dict 다. r2055 가 만든 용량 셈은 이런 줄을 1칸으로 센다. 칸을 비우는 길은 같은 thread 에 봇 답글이 달릴 때뿐이다. 답을 채널 최상위 글로 올리는 지금 방식에서는 그 끝이 오지 않는다. 8칸이 차면 그 팀의 모든 접수가 «용량 부족» 이 된다. Slack 글 접수는 카드가 아니라 글 영수다. 그 글에서 나온 일은 문자열 work 로 따로 접수되어 칸을 쥔다. 그래서 dict-work 는 용량 셈에서 빼고 의무 장부(remaining)에는 그대로 둔다.

## 계약
- S0 accept 줄의 work 가 dict 이면 그 줄은 «글 영수» 다 · 용량 단위가 아니다 · work 가 str·None 인 줄과 parked 의 동작은 그대로
- S1 `record.capacity()` 는 accept 줄의 work 가 dict 인 command 로 용량 단위를 만들지 않는다 · work 가 None 인 command 는 지금처럼 1칸 · parked 제외 그대로
- S2 `record.remaining()` 손 0 — 마감·재개·reopen 이 보는 값은 그대로(dict-work 접수는 의무 장부에 남는다)
- S3 `reply_done._requeue` 는 «처음 센 칸 − 성공 수» 셈을 버린다 · FULL 글마다 그때의 실제 용량(`capacity − len(record.capacity(다시 읽은 state·records))`)과 재접수 입구 `_recover` 의 영수로 판단한다 · 영수 «용량 부족» = 그 뒤 미요청 글 건너뜀 · 재접수 순서(ts 오래된 순)·멱등·settle 대조 손 0
- S4 `full_alert.remaining()` 의 알림 값 = 투영 `capacity` 칸(없으면 `remaining` · keeper_next.intake_open 과 같은 읽기) · 문구·서명·중복 억제·풀림 규칙 손 0
- S5 그대로: intake 접수 순서·문구 꼴 · close_next dict 제외(r1881) · 보정 3 가드(㉕가·나·다) · keeper_settle.accept_only · journal 총량 한계

## 구현 범위 (나노 1 · 팩 base origin/main 최신 · 9180664e 이후)
1. 커밋 1 [test] — 새 시험 feature-pack/fable-team/ft2/tests/test_slack_accept_capacity.py(㉖가~바 · M7 · M8 · M9) · 기준판에서 ㉖가·㉖나·㉖마·㉖바 FAIL 원문을 PR 본문에 붙인다
2. 커밋 2 [fix] — S1·S3·S4 = feature-pack/fable-team/ft2/core/record.py(capacity) · feature-pack/fable-team/ft2/adapters/slack/reply_done.py(_requeue) · feature-pack/fable-team/ft2/adapters/pi/full_alert.py(remaining) · 다른 함수 손 0
3. 커밋 2 에 같이 — 회귀 fixture 고침(삭제 0 · PR 본문에 사례 이름): feature-pack/fable-team/ft2/tests/test_slack_reply_completes_r1872.py 의 test_7·test_8·thread_full = dict 8건 FULL 전제를 str-work 포화 또는 기준판 FULL 영수(receive full 줄)로 바꾸고 답글 범위·멱등·오래된 순서·복구 보호 기대는 지킨다 · feature-pack/fable-team/ft2/tests/test_core_remaining_dict_work_r1824.py case5 = dict-work 칸 점유 기대가 있으면 remaining 기준으로 · r1886 꽉 참 알림 시험 test_c1_c2_c3 = dict 재포화 기대를 str-work 재포화로
4. 커밋 3 [docs] — CONTRACT.md 용량 절에 S0 1줄 · CASES.md ㉖·M7·M8·M9 행 · 설계 1쪽을 feature-pack/fable-team/design/ 로 옮김
5. 회귀 rc0: test_core_park_capacity_r2055.py · test_settle_one_path_r2055.py · test_core_close_next_dict_work_r1881.py(기대값 손 0) + 3번의 세 파일
6. 실행 = `python3.11 -m pytest` · 착지 = PR 1개(팀장 집행)

## 범위 밖
- 답 없는 Slack 접수를 keeper 가 팀당 1줄로 드러내는 일(후속 카드 · DA Q2 · 지문 = 건수·command 집합·최초 시각)
- 답 없는 Slack 접수를 무엇으로 닫을지(채널 최상위 답글과 접수를 잇는 규칙) — 오빠·planner 판단
- work None 접수의 끝(실측 0건)
- 실 runtime journal 손 쓰기(HIL) · 설치 집행(팀장·harness)

## 완료 조건
1. [ ] 나노: 커밋 1 기준판 FAIL 원문(㉖가·㉖나·㉖마·㉖바)
2. [ ] 나노: 새 시험 전체 rc0 · 걸린 초
3. [ ] 나노: 변이 M7 → ㉖가·㉖나·㉖마 FAIL · M8 → ㉖마 FAIL · M9 → ㉖바 FAIL
4. [ ] 나노: 회귀 6파일 rc0 · 고친 fixture·기대값 사례 이름 목록
5. [ ] 팀장: PR 착지 sha · 설치 판
6. [ ] arch: 설치 뒤 읽기 실측 1줄(planner capacity 0 · issues capacity = str-work 수)
7. [ ] 팀장: 오빠 다음 Slack 글에서 issues·planner «용량 부족» 0 원문 줄

## 계약↔시험 대응표
| 계약 | 시험 |
|---|---|
| S0·S1 dict-work 는 용량 0칸 | ㉖가 planner 꼴 accept 8 → 9번째 Slack 접수 = 접수 성공(기준판 용량 부족) · 접수 뒤 capacity 0 · remaining 9 / ㉖나 issues 꼴 accept 8 → str-work 접수 1 = 접수 성공(기준판 capacity 8 · 용량 부족) · 접수 뒤 capacity 1 · remaining 9 · 손 complete 0 / M7 |
| S1 str-work · None 은 그대로 | ㉖다 dict 8 + str-work accept 8 → 다음 str-work 접수 = 용량 부족 · 문구의 남은 일 8 / ㉖라 work None 접수 8 → 다음 접수 = 용량 부족 |
| S2 의무 장부 그대로 | ㉖가·㉖나 remaining 8 → 9 |
| S3 재접수 = 실제 용량 + 입구 영수 | ㉖마 str-work 8 포화 중 Slack 글 9건 = receive full 9(같은 thread 에 먼저 접수된 dict-work 1) → str-work 1 complete(여유 1칸) → thread 답글 settle 1회 = 9건 전부 재접수(ts 오래된 순 · 기준판 1건만) · full 0 · capacity 7 · settle 한 번 더 = 재접수 0 / M8 |
| S4 알림 값 = capacity | ㉖바 dict-work 8 인 팀 full_alert.remaining 1회 = 알림 0(기준판 꽉 참) → str-work 8 접수 뒤 = 꽉 참 1통 → str-work 1 complete 뒤 = 풀림 1통 · 같은 값 다시 = 0통 / M9 |
| S5 보정 3·r1872 그대로 | 회귀 test_settle_one_path_r2055.py ㉕가·나·다 · test_slack_reply_completes_r1872.py(fixture 만 고침) |

## 상태
- base_sha: 731bc23623c10cd68cc18210d47c7d1793f20e4c (spawn 2026-11-16)
- 2026-11-16 · aifp-ft-arch-pi#16 초안(aifp 5324) · 대기 · DA 판정 전
- 2026-11-16 · aifp-ft-arch-pi#16 r2(aifp 5331 · DA 대행 1/3 HOLD-DESIGN R1·R2·Q1~Q3 반영 · 드러냄 1줄 분리) · 대기 · DA 재판정 전
- 2026-11-16 02:02 — 대기→진행 · 좌석 aifp-ft-nano-ft2-slack-accept-capacity#0
- [배정 불명] 불명(scope 표 없음 opengateway/deepseek/deepseek-v4.1-flash-ultrafast)
- 세트: dc85096f87cce258b7fedc3db3deb56e30021c8b · 시험: python3.11 -m pytest feature-pack/fable-team/ft2/tests/test_slack_accept_capacity.py rc=0 · 이슈: 0
- 완료: aifp-ft-nano-ft2-slack-accept-capacity#0 · 한 일: dict-work(글 영수) 용량 0칸 · 재접수는 그때의 실제 용량 · 꽉 참 알림 값 = capacity + 새 시험·계약·사례표 · 산출: nano/ft2-slack-accept-capacity-r2@dc85096f87 · 병합 상태: 착지 전(push 전) · 남은 일: 없음
