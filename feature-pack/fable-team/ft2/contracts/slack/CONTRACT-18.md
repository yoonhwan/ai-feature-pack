# Slack 연결 계약 18줄 ↔ 사례 대응표 (ft 2.0 · PR③ 검증 표)

- 정본 계약: `design/harness/research/ft-2.0/slack.html` §「연결 계약 18줄 (보정판 · 줄마다 근거 번호)」 @ BYZ `e50b743978c3b2287296acc3cf99d89eff2549f5`
- 사례 원자료: `design/harness/research/ft-2.0/slack/checker-r1501/raw/case-json/*.json` @ 같은 sha · 독립 checker 1석 판정문 `checker-r1501/VERDICT-r1501-slack-checker.md`
- **사례 수 재계수 = 21** (원자료 파일 21 = 표 행 21). 정본 `core.html` 의 «24사례·변이14» 는 같은 실험의 뒤 회차(`exp-r1500/results-v2/` 01~24)를 센 값이다. **차이 3** = 22 `t6` · 23 `r1` · 24 `r2`(r1501 1차 원자료 뒤 재검에서 추가). 이 표는 재계수 21 만 담는다.
- 사례 표 칸 = `id` · 출처(경로@sha) · given(Slack 사건 · 키 3종 workspace·channel·ts) · expect(계약 낱말 + 원자료 결과 칸 그대로). 파일 = `cases/NN-<id>.json`
- 검사기 = `replay_check.py` — ⓐ 사례 수 · ⓑ 이 표 ↔ 정본 원문/사례 대응 · ⓒ expect ↔ 원자료 결과 · ⓓ 키 3종·계약 낱말 · ⓔ 비밀값 0
- 실행 = `python3 replay_check.py --byz <BYZ 리포>` (원자료를 못 읽으면 rc3 · 조용한 통과 0) · 시험 = `python3.11 -m pytest feature-pack/fable-team/ft2/tests/test_contract_slack_replay.py`
- 상태: 사례 21 중 **계약 줄을 덮는 사례 = 17** · 계약 밖 사례 4(`f1`·`f2`·`f3` 서식·파일 · `f4` 는 계약 10 이 덮음) → 계약 밖 = 3

## 대응표

| 줄 | 원문 (정본 복붙) | 덮는 사례 |
|---|---|---|
| 1 | 수신 = Socket Mode 이벤트(전용 app · 운영 gateway 연결 공유 0) · 주기 폴링 0 [S1·S13] | 미시험 |
| 2 | 거름 → 메시지 키 → 기록 → Slack 확인 → 입구 전달 · 확인 ≠ 업무 접수 [②③] | c1, c2, c3 |
| 3 | 키 3종: 메시지 (workspace, channel, ts) · 전송 힌트 event_id·client_msg_id · 답 (thread 연결, 요청 번호) [S14] | c1, c2, d1 |
| 4 | 넘김 완료 = 팀 도구 입구 영수 기록(현행 비교값은 mbox seq). 영수가 없으면 같은 전달 의도로 대조·복구하며, 재기동마다 시도 예산을 새로 만들지 않음 [S15·공통 운영 계약] | c1, c3, d2 |
| 5 | 재송 머리에 메시지 키 표식 · 좌석은 같은 표식 2번째부터 안 읽음 · 행 수 상한 약속 0 [S15] | d2 |
| 6 | 입구 가득이면 영수 0 · 접수 아님 · 기록 보존 + 알림 [S4] | t4 |
| 7 | 보충 회차 = 재시작·재연결 사건 때만 · 허용 채널·활성 thread의 커서 이후를 제한된 묶음으로 · 페이지가 남으면 위치 보존 후 재개 · 커서는 연속된 처리 영수까지만 · 실패/gap은 미완 기록 [S16] | d3 |
| 8 | 좌석·thread별 커서 · 창 전체 다시 읽기 0 [⑧] | c8 |
| 9 | thread 1 = 주제 1 = 논리 컨텍스트 1 · 파일 분리 ≠ 모델 입력 격리 [⑤·S5] | c5 |
| 10 | 답 = 그 thread 1곳 · 요청 번호 = 팀 도구 번호 그대로 [①·S19] | c1, f4 |
| 11 | 답 응답 불명 = UNCERTAIN · 표식 조회 3값(있음·없음 확인·판정 불가) · 판정 불가는 보존·사람 · 자동 재송 0 [S18] | t3 |
| 12 | 담당 승계 사슬 · 옛 세대 답 거절 [⑦] | c7, t2 |
| 13 | 429 = Retry-After · 재시도 1 · 넘으면 보이는 오류 [④] | c4 |
| 14 | 임시 채널은 사람이 만듦 · 닫히면 담당 없음 · 새 글 = 재개 필요 · 답 거절 [⑥·S17] | c6, d4 |
| 15 | 결정·완료 정본 = 팀 도구 · 미인가·bot·다른 채널은 확인만 하고 버림 [①·S7] | c1, t1 |
| 16 | 유휴·중복·무변화 사건은 도구 안에서 끝 · 모델 호출·좌석 깨움·틱 상태 메시지 0 [②·⑧·T5] | c2, c8, t5 |
| 17 | 목적지는 binding·상태로(모델 분류기 0) · 좌석에는 그 thread 변경분과 필요 근거만 · 전체 대화 재로드 0 [⑤·⑧·S23] | c5, c8, t5 |
| 18 | 기록 파일은 용도별 유한 cap·회전(스크립트 · LLM 0) · 열린·미확정 기록은 안 지움 · 넘치면 명시적 포화 · cap 숫자는 arch 검토 중 [S6·S24] | 미시험 |

## 사례 21 (원자료 순)

| id | 파일 | 계약 줄 | 원자료 판정 |
|---|---|---|---|
| c1 | 01-c1_roundtrip.json | 2, 3, 4, 10, 15 | PASS |
| c2 | 02-c2_reconnect.json | 2, 3, 16 | PASS |
| c3 | 03-c3_crash.json | 2, 4 | PASS |
| c4 | 04-c4_ratelimit.json | 13 | PASS |
| c5 | 05-c5_threads.json | 9, 17 | PASS |
| c6 | 06-c6_close.json | 14 | PASS |
| c7 | 07-c7_owner.json | 12 | PASS |
| c8 | 08-c8_full.json | 8, 16, 17 | PASS |
| d1 | 09-d1_channel_key.json | 3 | PASS |
| d2 | 10-d2_crash_before_receipt.json | 4, 5 | PASS |
| d3 | 11-d3_backfill_pages.json | 7 | PASS |
| d4 | 12-d4_closed_binding.json | 14 | PASS |
| t1 | 13-t1_bot_echo.json | 15 | PASS |
| t2 | 14-t2_two_owners.json | 12 | PASS |
| t3 | 15-t3_uncertain.json | 11 | PASS |
| t4 | 16-t4_entrance_full.json | 6 | PASS |
| t5 | 21-t5_model_zero.json | 16, 17 | PASS |
| f1 | 17-f1_render.json | 계약 밖 | PASS |
| f2 | 18-f2_split.json | 계약 밖 | PASS |
| f3 | 19-f3_file_guard.json | 계약 밖 | PASS |
| f4 | 20-f4_interview.json | 10 | PASS |

## 미시험 · 계약 밖 (지우지 않는다)

| 줄 | 왜 미시험인가 | 어디서 닫나 |
|---|---|---|
| 1 | 21 사례 전부 가짜 Slack(`fake_slack.py`) 경유다. Socket Mode 실 연결·운영 gateway 공유 0 은 어느 사례도 안 본다 | PR③ 실 수신기 + 실채널 회차 |
| 18 | r1501 결함 D3 «유한 cap·회전 미구현·미시험». 사례 0 · cap 숫자는 arch 검토 중 | r1504/r1505(카드 기준값 §범위 밖) |

| 사례 | 계약 밖 사유 | 닫는 자리 |
|---|---|---|
| f1 | 계약 18줄이 답 서식(mrkdwn 렌더)을 안 덮는다 | PR③ 답 서식 계약 또는 별 카드 |
| f2 | 계약 18줄이 긴 답 나눔(코드 블록 경계·순서)을 안 덮는다 | 같음 |
| f3 | 계약 18줄이 파일 첨부 검사(팩 file_guard 재사용)를 안 덮는다 | PR③ + 팩 file_guard |

## 알려진 한계

- 사례는 r1501 1차 원자료 21 이다. 재검 회차의 `t6`(같은 intent_id 재회신 거절 · 계약 3) · `r1`·`r2`(재기동 경계) 는 이 표 범위 밖이라 계약 3 의 멱등 부분은 «사례 0» 이다.
- 원자료는 모형(`evidence_kind=모형`)이다. 실 Slack 호출 0 · 실 토큰 0. 실채널 왕복·사람 화면 판정은 정본대로 미시험으로 남는다.
- `given` 의 channel·ts 는 원자료에 값이 있으면 그 값, 없으면 모형 생성기 기본값이다(`given.basis` 에 어느 쪽인지 적었다). 사건 자체는 사례 원문(`title`)과 같다.
