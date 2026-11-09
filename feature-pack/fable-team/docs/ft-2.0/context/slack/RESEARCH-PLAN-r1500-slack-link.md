# RESEARCH-PLAN r1500 — ft 2.0 Slack 양방향 연결: 조사 1차 + 격리 실험 1회 + 평가·보완

- 카드: `design/harness/indices/진행/r1500-ft20-slack-bidirectional-link-research-isolated-exp.md` · Issue #8098
- 실행: nanoworker(NW) `byz-harness-nano-r1500-ft20-slack-bidirectional-link-rese#0` · 엔진 기록 = pi + `cliproxy-anthropic/claude-opus-5-5`(세션 jsonl `"provider":"cliproxy-anthropic"` `"model":"claude-opus-5-5"` · PI_SESSION_ID 01e26350)
- 입력 고정: gajae-code `b4127889c4a849133f868cbf8f4d5a65126baec4`(INPUT/gajae-code.HEAD) · ai-feature-pack `53a6a1911b7bc5768d02d4c1d47f1f9559e29263`(INPUT/ai-feature-pack.HEAD) · AUDIT 정정 `fb2be8b65b`
- 범위: 기획·실험만. 제품 구현 0 · 배포 0 · 운영 채널 발행 0 · 채널 생성 0. 실채널은 사람이 만든 `#byz-dev-test`(C0CGUDJ9NTS)만.
- 증거 종류 표기: **[실측]** 실제 Slack·실제 모델 호출 또는 실제 파일 stat · **[모형]** 가짜 Slack·재배달 모형 · **[계산]** 실측값×횟수 · **[코드]** 파일:줄 읽기(실행 보장 아님).

## §1 현행 ft ↔ gajae-code 차이표

현행 ft 경로 = 팩 `feature-pack/fable-team/harness/kit/slack-mirror/`(아래 `kit/`). gajae 경로 = `packages/coding-agent/src/sdk/bus/`(아래 `bus/` · r1489 §4 인용 · 이번에 줄 재확인).

| 행 | 현행 ft (파일:줄) | gajae (파일:줄) | 차이 1줄 |
|---|---|---|---|
| 수신 | 폴링. `kit/byz_slack_mbox_inbound.py:61` history(oldest=now−7일 `:26`, limit 200) 매 pass · `:193` sleep(기본 10초) | 이벤트. `bus/slack-live-provider.ts:184` apps.connections.open · `bus/slack-daemon.ts:497` handleEnvelope | ft 는 «창을 읽어 찾는다», gajae 는 «도착을 받는다» |
| 접수 | 메시지별 영속 원장(계획→attempt→send→done) `kit/byz_slack_mbox_inbound.py:2-3`·`:149`·`:85-129` | claim(영속) → transport ACK → dispatch `bus/slack-daemon.ts:517`→`:528`→`:538` | **카드 기준값 정정**: ft 에도 접수 원장은 있다. 없는 것은 Slack 쪽 ACK(폴링이라 개념 없음) |
| 중복 | 원장 키 = 메시지 ts · mbox 꼬리 토큰 `slack:<ts>:<수신자>` 검색 `kit/mirror_inbound.py:141` · «최악 1회» 계약 `:3` | event_id·client_msg_id·retry key dedupe(`bus/slack-conversation.ts:50-53` · `bus/conversation-store.ts:7` 128개) | ft = ts 1키, gajae = 이벤트 id 계열 다키 · 둘 다 «정확히 1회» 아님(AUDIT fb2be8b65b §2) |
| 증분 컨텍스트 | thread 마다 `latest_reply` 가 같으면 replies 생략 `:68` · 바뀌면 `oldest=floor`(창 시작)부터 그 thread 전체 재조회 `:70` · 좌석에는 새 글 본문만 mbox 로 | thread 단위 세션에 새 user turn 주입(`bus/slack-daemon.ts:538` dispatch) | ft 는 «읽기» 가 창 전체, «좌석 입력» 은 증분 · thread 문맥은 좌석에 안 감 |
| 양방향 응답 | 좌석→Slack = mbox 미러(`kit/byz_mbox_slack_mirror.py:86` pass 마다 `:32-46` 우편함 사본 전문 read) + haiku 요약(`kit/mirror_summary.py:19`) | thread 댓글 1곳(`bus/slack-daemon.ts:1007`·`:1197`) | ft 응답은 «미러»(좌석이 직접 그 thread 에 답하는 경로 아님) |
| 팀/임시 채널 | 채널 1개(`--channel` 고정) · thread 장부 키 `<팀>/<카드>`(`kit/thread_ledger.py:3`) | 채널 1개 · 팀 묶음 0(r1489 §4 «팀·세션 라우팅») | 둘 다 «팀/NW 임시 채널» 개념 없음 |
| thread 격리 | 장부가 카드 1 = thread 1 · 좌석 쪽 문맥 분리 없음 | 키 (team, channel, rootTs) = 세션 1 `bus/slack-conversation.ts:59` | gajae 는 세션=thread, ft 는 thread 를 좌석 문맥에 묶는 장치 없음 |
| 승계 | 수신자 = 명부 `_master`/`--to-key` 현역 + tmux 생존 매번 재조회(`kit/mirror_inbound.py:79-84` · `kit/mirror_share.py:81`) | 세대·incarnation(r1489 §3 관리 행) · thread→owner 승계 키는 Slack 어댑터에 없음 | ft 는 «역할 키 → 현역» 이 있다. thread 별 owner 와 구 owner 차단은 둘 다 없음 |
| 재시작 | 미완료 원장 항목 독립 재개 `kit/byz_slack_mbox_inbound.py:143-145` · 첫 실행 baseline(과거 글 버림) `:135` | journal 재생 `bus/chat-effect-journal.ts:118` · `bus/slack-daemon.ts:2188` | ft: 데몬이 7일(+③ 14일 `kit/mirror_threads.py:20`) 넘게 꺼지면 그 사이 글은 창 밖 = 조용한 누락 가능 |
| rate limit | `kit/mirror_lib.py:60-78` 429 를 구분하지 않음(GET 은 재시도 1 · Retry-After 미사용) · ③ 순환은 호출 예산(`kit/mirror_threads.py:21-23`) | `bus/slack-live-provider.ts:89` Retry-After 해석 · `:511` 상한 뒤 rate_limited 오류 · lane 큐 `bus/rate-limit-pool.ts:26` | ft 는 429 를 일반 실패로 raise → launchd 재기동(대기 없음) |
| 권한 | 허용 사용자 목록 `kit/mirror_humans.py:18` · bot·subtype 거름 `kit/mirror_inbound.py:29` | 단일 authorizedUserId + bot/self/subtype 거름 `bus/slack-daemon.ts:500-514` | 비슷함 · gajae 는 거른 envelope 도 ACK(재배달 방지) |

## §2 Slack 공식 제약 (출처 = docs.slack.dev · 2026-11-09 13:2x 내려받아 확인)

| 항목 | 내용 | 출처 |
|---|---|---|
| Socket Mode ACK | envelope 마다 `envelope_id` 로 ACK 해야 Slack 이 재시도 여부를 안다 · 연결은 몇 시간마다 갱신(약 10초 전 `disconnect` 경고) · 동시 연결 10개까지, 각 payload 는 «아무 연결에나» 간다 | https://docs.slack.dev/apis/events-api/using-socket-mode |
| Events API(HTTP) 재시도 | 3초 안에 200 이 없으면 재시도 3회(즉시·1분·5분) · `x-slack-retry-num`·`x-slack-retry-reason` · `event_id` 는 전역 고유 | https://docs.slack.dev/apis/events-api/ |
| rate tier | Tier1 1+/분 · Tier2 20+/분 · Tier3 50+/분 · «메서드 × workspace × app» 단위 · 초과 = HTTP 429 + `Retry-After`(초) · websocket URL 발급은 분당 1회 근처 | https://docs.slack.dev/apis/web-api/rate-limits |
| history/replies | 둘 다 Tier 3(50+/분). 2025-05-29 변경: Marketplace 밖 «상업 배포» 앱의 신규 설치는 분당 1회·limit 15 · **내부(customer-built) 앱은 영향 없음** | https://docs.slack.dev/reference/methods/conversations.history · https://docs.slack.dev/changelog/2025/05/29/rate-limit-changes-for-non-marketplace-apps |
| postMessage | 채널당 대략 초당 1개 · text 4,000자 권장 · 40,000자 넘으면 잘림 · `thread_ts` = 답글 · `reply_broadcast` = 채널에도 노출(기본 false) | https://docs.slack.dev/reference/methods/chat.postMessage |
| 채널 생성 | `conversations.create` = bot scope `channels:manage`(Tier 2) | https://docs.slack.dev/reference/methods/conversations.create |
| 이 workspace 실측 | team `T0AC5HC4ENR` · ft bot scope 19개, `channels:history`·`chat:write` 있음, `channels:manage` 없음, app-level(xapp) 토큰 없음 **[실측]** | `exp-r1500/raw/auth-test.json` · `raw/channel-check.json` |

공식 문서에서 확인한 «scope 보유» 는 «호출 허용» 과 같지 않다. 실채널 호출 결과는 §5 실채널 표에 따로 적는다.

## §3 최소 연결 계약 (보정판 15줄 · DA HOLD #275618 R1~R4 · 메인 대조 #275615 6항 · arch #275625 A1~A3 반영)

각 줄 끝 [ ] = 그 줄을 닫는 시험 사례 번호 또는 SPEC_INCOMPLETE S번호. 사례 번호가 있어도 그 사례가 줄 전체를 닫는다는 뜻은 아니다(아래 §4 «기존 모형이 닫는 범위»).

1. 수신 = Socket Mode 이벤트(전용 app · 운영 gateway xapp 공유 0). 주기 폴링 작업은 두지 않는다. [S1 · S13]
2. 순서 = 거름 → 메시지 키 확인 → claim 기록(append+fsync) → transport ACK → 팀 도구 입구 전달. transport ACK 는 «Slack 이 보냈다» 확인이고 업무 접수가 아니다. [②③]
3. 키 3종을 나눈다. 메시지 키 = `(workspace, channel, ts)`(Slack ts 는 대화 안에서만 고유). 전송 중복 힌트 = `event_id`·`client_msg_id`(같은 메시지 키로만 묶는다). 회신 키 = (binding, intent id). [S14]
4. dispatched = 팀 도구 입구가 돌려준 영수 1개를 journal 에 적은 것이다. 현행 입구 mbox 의 영수 = `QUEUED seq=N`. 영수 없이 재시작하면 같은 본문을 다시 보낸다(재시작 1번에 재송 최대 1번). [S15]
5. 재송 본문 머리에는 메시지 키 표식 1개를 싣는다(`event_id` 가 있으면 함께). 수신 좌석은 같은 표식 2번째부터 읽지 않는다(소비자 멱등). crash 가 반복되면 입구 행은 늘 수 있다. 모듈은 행 수 상한을 약속하지 않는다(«최악 1회 중복» 주장 철회). [S15]
6. 입구가 가득(현행 수신자 큐 RING · 2.0 입구 FULL)이면 영수가 없다. 업무 접수로 적지 않고 claim 을 남기며 보이는 알림을 낸다. [S4]
7. 보충 회차 = 재시작·재연결 사건마다 1번이다. 요청마다 `next_cursor` 가 빌 때까지 이어 받는다. 커서는 «끊김 없이 영수가 적힌 마지막 ts» 까지만 옮긴다. 중간 실패면 커서를 두고 회차를 `미완` 으로 적고 보이는 오류를 낸다(§3-1). [S16]
8. 증분 커서 = (좌석, thread) 별 위치. 창 전량 재조회 0. [⑧]
9. thread 1 = 주제 1 = 논리 컨텍스트 1. 키 = `team:channel:root_ts`. 파일 분리는 모델 입력 격리의 증거가 아니다. [⑤ · S5]
10. 회신 = 그 thread 1곳(`thread_ts=root`) · `reply_broadcast` 0. intent id = 팀 도구 쪽 요청 식별자(mbox seq 또는 카드 줄 id) 그대로. 모듈은 id 를 새로 만들지 않는다. [① · S19]
11. 미확정 송신 = post 응답을 못 받으면 `UNCERTAIN`. thread 표식 조회는 3값이다. 있음 → `posted`. 없음 확인(전 페이지 조회 성공·표식 없음) → 같은 intent id 로 1회 재송. 판정 불가(조회 실패·권한·잘린 페이지·반영 지연) → 보존하고 담당·확인 시한·보고처를 붙인다. 자동 성공·자동 재송 0(§3-3). [S18]
12. owner = binding(thread → 주제·owner 역할 키·세대). 승계 = `_replaced_by` 사슬. 구 세대 회신은 거절하고 오류로 남긴다. [⑦]
13. rate limit = `Retry-After` 를 따른다. 재시도 1회(하드 룰 12). 넘으면 오류 기록 + 보이는 오류(조용한 폐기 0). [④]
14. 임시 채널은 사람이 만든다(채널 생성 API 0). 종료 = binding `open=false`. 닫힌 binding 의 owner 는 없다. 닫힌 thread 의 새 글은 팀 도구에 «재개 필요» 로 넘긴다. 회신은 모두 거절하고, 재개(새 세대 owner) 뒤에만 한다(§3-2). [⑥ · S17]
15. 결정·미결정·완료의 정본 = 팀 도구. 모듈은 판정하지 않고 팀 도구 id 만 참조한다. 미인가·bot·다른 채널 envelope 은 ACK 하고 버린다(로그 1줄). r1498(팀 종료 1명령)과는 14행 «종료 = binding 닫기» 1줄로만 만난다. [① · S7]

### §3-1 보충 회차의 끝 조건 (R3)

- 회차 = 재시작 1번 또는 재연결 1번에 따른 보충 1번이다. «1회» 는 요청 수가 아니다. `limit` 은 페이지 크기일 뿐 상한이 아니다.
- 범위 = 모듈이 맡은 channel 의 `conversations.history(oldest=채널 커서)` + 열린 binding 의 `conversations.replies(oldest=thread 커서)`.
- 각 요청은 `response_metadata.next_cursor` 가 빌 때까지 이어 받는다. 모은 글은 ts 오름차순으로 입구에 넘긴다.
- 커서는 «끊김 없이 영수가 적힌 마지막 ts» 까지만 옮긴다. 중간 실패(오류·429 상한)면 커서는 그 자리에 남는다. 회차는 `미완` 으로 적고 보이는 오류를 낸다. 다음 회차가 그 커서에서 이어 받는다.
- 새 root 는 채널 커서 뒤의 history 에서만 찾는다. 커서가 없는 채널(처음 맡음)은 맡은 시각을 커서로 둔다(과거 글 쏟기 0 · 현행 `kit/byz_slack_mbox_inbound.py:135` 와 같은 꼴).
- 회차 중 Socket 으로 같은 글이 오면 메시지 키로 합친다. 끝 = 모든 범위 요청의 next_cursor 가 비고, 모은 글의 영수가 모두 적힘.

### §3-2 닫힌 binding (R4)

- `close` 뒤 owner 조회는 «없음» 이다. inbound 는 팀 도구에 «닫힌 주제의 새 글 = 재개 필요» 로 넘긴다(SIM v1 §6 «이미 closed 면 새 pending 이 팀 재개 필요 상태»).
- outbound 는 닫힌 binding 에서 모두 거절한다(옛 owner 포함). 팀 도구가 재개하면 binding 은 새 세대 owner 로 다시 열린다.

### §3-3 미확정 송신 (메인 대조 1항 · arch A2)

- post 응답이 끊기면 intent 는 `UNCERTAIN` 이다. intent id 는 팀 도구 요청 식별자이고, thread 표식도 그 id 로 찾는다.
- 조회 결과 3값: 있음 → `posted` · 없음 확인 → 같은 id 로 1회 재송 · 판정 불가 → `UNCERTAIN` 유지 + 담당·확인 시한·보고처(SIM v1 §2). 시한이 지나도 자동 성공·자동 재송 0.

## §4 반례 ↔ 시험 사례

| 반례 | 무엇이 깨지나 | 막는 계약 줄 | 사례 |
|---|---|---|---|
| R1 재연결 | 끊김 직전 ACK 유실 · 끊긴 사이 도착 | 2·4·7 | ②③ · S16 |
| R2 재전송 | Slack 재배달(retry_attempt) · 같은 client_msg_id 두 번 | 3·5 | ② |
| R3 포화 | 429 · 입구 가득 | 6·13 | ④ · S4 |
| R4 권한 | 미인가 사용자·bot 글이 좌석에 감 · 운영 xapp 공유로 이벤트 탈취 | 1·15 | ① 의 미인가 분기 · xapp 공유는 금지로만 |
| R5 순서 | 재배달된 옛 글이 새 글 뒤에 좌석 문맥에 붙음 | 8 | S3 |
| R6 thread 누출 | thread A 글이 B 문맥에 들어감 | 9 | ⑤(파일 분리까지) · S5 |

DA HOLD #275618 의 정적 반례 4건(번호 D1~D4 · 위 R 번호와 다름). 기존 모형 8 PASS 는 이 4건을 시험하지 않았다. 기대 결과는 §3 보정판 기준이다. 실험은 §7-4 순서를 따른다.

| DA | 입력 1줄 | 기대 결과(보정판) | 막는 줄 | 기존 모형 |
|---|---|---|---|---|
| D1(R1) | 같은 workspace 에서 (C1, t, E1, M1) 접수 뒤 (C2, t, E2, M2) | 둘 다 접수 · 메시지 키가 다름 | 3 | 미시험 → S14 |
| D2(R2) | claim → 입구 전달 → 영수 기록 전 crash 를 2번 반복 | 입구 행 3 가능 · 좌석은 표식으로 1회만 읽음 · 모듈은 행 수 상한 약속 0 | 4·5 | 미시험(③ 은 after_claim·after_ack 만) → S15 |
| D3(R3) | 커서 뒤 미수신 16개 · limit 15 · 1쪽 뒤 next_cursor 있음 | 2쪽까지 이어 받아 16 전달 · 2쪽 실패면 커서 = 15번째 · 회차 `미완` | 7 · §3-1 | 미시험 → S16 |
| D4(R4) | bind(C,R,owner#1) → close(C) → owner_of(C,R) · 새 글 · owner#1 회신 | owner 없음 · 새 글 = «재개 필요» · 회신 거절 | 14 · §3-2 | 미시험(⑥ 은 pending·open 만) → S17 |

참고: `exp-r1500/contract_ref.py`(adedcacc) 는 보정 전 계약을 따른다. 키 구성(D1)·재전달(D2)·`owner_of`(D4)가 보정판과 다르다. 실험 단계에서 보정판에 맞춘다(이번 보정은 문서만 · 실행 0).

사례 8: ①정상 왕복 ②재접속 누락0·중복0 ③ACK 전/후 crash ④429 retry-after·상한 뒤 오류 ⑤같은 좌석 복수 thread 파일 분리 ⑥임시 채널 종료 뒤 미결정 보존 ⑦구 owner 응답 차단 ⑧재독 비교(포화 시험 아님).

## §5 측정 결과

### 5-1 모형 사례 8 **[모형 · 구현자 시험 범위 · 독립 checker(r1501) 판정 전 · DA D1~D4 미포함]** — `exp-r1500/results/case-0N.json` · 실행 로그 `raw/cases-run.txt`

| 사례 | 판정 | 핵심 관측 | 모형 호출 | 모형 재독 bytes | 실제 Slack 호출 |
|---|---|---|---|---|---|
| ① 정상 왕복 | PASS | dispatch 1 · ctx 1줄 · 답글 thread_ts=root · 미인가 글 = ignored+ACK | 3 | 73 | 0 |
| ② 재접속 | PASS | 재배달 2 → duplicate 1·dispatched 1 · 이미 ACK 된 글 재배달 → duplicate · mbox 5행 중복 0 누락 0 | 8 | 0 | 0 |
| ③ crash | PASS | 실 자식 프로세스 os._exit(9) · crash 지점 = after_claim·after_ack 만(입구 전달 뒤·영수 기록 전 = D2 미시험) · ACK 전 crash → Slack 재배달 → 재시작 recover 1회 · ACK 후 crash → 재배달 없음 → journal 재생 1회 · 두 경우 모두 mbox 1행 | 4 | 0 | 0 |
| ④ 429 | PASS | Retry-After 3초 요청 기록(가상 시계 · 실제 대기 0) 뒤 성공 · 연속 429 → 재시도 1 뒤 raise + errors.jsonl 1행 | 4 | 0 | 0 |
| ⑤ thread 파일 분리 | PASS | 같은 좌석·thread 2 → 각 4줄 · 교차 0(ts 집합 비교) · 모델 입력 격리 아님 | 8 | 522 | 0 |
| ⑥ 채널 종료 | PASS | binding open=false · 새 프로세스(다음 좌석)가 미결정 1건 읽음 · 종료 뒤 재입력·회신은 미시험(D4) | 0 | 0 | 0 |
| ⑦ 구 owner | PASS | seat#1→#2 승계 뒤 #1 답 거절(errors 1행) · #2 답 1건만 게시 | 1 | 0 | 0 |
| ⑧ 재독 비교 | PASS | 아래 5-2 · 포화(FULL) 시험 아님 | 19 | 137,238 | 0 |

시험: `timeout 70 pytest -q test_r1500_cases.py` = 10 passed(사례 8 + 변이 2: 중복 기억 제거 → ② FAIL 확인 · 승계 사슬 제거 → ⑦ FAIL 확인). 모형 호출 수는 비용 증거로 합산하지 않는다.

### 5-2 ⑧ 재독 비교 — 현행 열은 «팩 실코드» 를 가짜 Slack 에 붙여 잼 **[모형]**

30 thread × 9 글 창 · pass 10 회(홀수 pass 에 새 답 1개, 짝수 pass 는 새 글 없음). 현행 = `Inbound._candidates`(`kit/byz_slack_mbox_inbound.py:53-76`) 그대로 · ③ 순환은 끔(호출이 더 적은 쪽으로 보수적).

| 구간 | 현행 ft | 계약 참조 구현 |
|---|---|---|
| 첫 pass | 31 호출 · 119,977 B | (기동 시 journal 1회 읽기) |
| 새 글 있는 pass | 2 호출 · 16,815 B(창 루트 목록 전체 + 그 thread 전체) | envelope 1 · 증분 ~131 B |
| 새 글 없는 pass | 1 호출 · 13,127 B(창 루트 목록 전체) | 0 |
| pass 2~10 합 | 14 호출 · 136,583 B | 5 envelope · 655 B |

[가정 계산] 유휴 pass 13,127 B × 하루 8,640 pass(10초) = 약 113 MB/일 논리 재독(모형 창 30 thread 기준 · 실제 운영 측정 아님).

### 5-3 실제 토큰·캐시 **[실측 usage · 입력은 합성 prompt · 현행 ft 운영 절감 실측 아님]** — `raw/token-probe.json` · cliproxy :8317 · claude-haiku-5-5 · 4회

| 입력 | input | cache write | cache read |
|---|---|---|---|
| A 창 전체 재주입(23,329자) | 2 | 21,199 | 0 |
| B 증분 1줄만 | 201 | 0 | 0 |
| C1 창 전체(cache_control) 같은 꼴 다시 | 2 | 0 | 21,199 |
| C2 창 전체 + 새 줄 바뀜 | 2 | 21,206 | 0 |

관측: 프록시가 cache_control 이 없는 A 에도 1시간 캐시를 붙였다(실측). 새 줄이 바뀌면 C2 처럼 캐시를 다시 쓴다.

해석 한계: cache write 와 input 은 가격이 달라 같은 절감률로 비교하지 않는다. 현행 ft 도 좌석 입력은 새 글 본문만이다(§1 증분 컨텍스트 행). 그래서 이 표는 «창 전체를 다시 넣는 설계를 피해야 하는 이유» 의 크기만 보인다. 현행 운영에서 줄어드는 양의 증거가 아니다.

### 5-4 현행 미러(좌석→Slack) 재독 **[실측 파일 크기 · 실행 0]** — `raw/mailbox-size.json`

[코드] `kit/byz_mbox_slack_mirror.py:32-46` 는 pass 마다 `mailbox.log.jsonl`+`.1` 전문을 읽는다(5초). [실측] 지금 두 파일 = 8,597,236 B. [가정 계산] 켜져 있다면 하루 약 148 GB 논리 재독(실제 디스크 IO 아님 · OS 캐시 미반영). 미러는 11-02 부터 꺼져 있어 실행 측정은 0 이다(r624 의 3.3MB 재파싱 CPU 11.5% 와 같은 꼴).

### 5-5 실채널 #byz-dev-test **[실측]** — Web API 증분 조회 시험(이벤트 수신 실증 아님 · 최종 수신 구조로 채택 0)

준비 확인: ft bot 멤버 · 공개·미보관 · gateway bot 비멤버(가로채기 0) · xapp 없음 → Socket Mode 실측 불가.

<!-- REAL-CHANNEL-TABLE -->
보류 — #275604(오빠 «실험은 기획 완성되면 해도된다») 로 순서가 바뀌었다. 실채널 호출은 auth.test·conversations.info·conversations.members(읽기 3종)뿐이고 발행 0 이다. `exp-r1500/real_channel.py` 는 미실행이다. §7 기획 → arch/DA 고정 검토 뒤 실행한다.

## §6 보완 / 미측정

- 미측정(실채널 이벤트 수신): 시험 app 의 xapp 토큰이 없다. 운영 gateway xapp 공유는 Socket Mode 가 아무 연결에나 배달하므로 운영 이벤트를 빼앗는다 → 공유 0. 필요한 것 = 시험 전용 Slack app 1개(Socket Mode on · `connections:write` xapp · bot `channels:history`·`chat:write`) — 사람 승인 항목.
- 미측정(실 429): 실 한도를 일부러 소진하지 않는다. 모형 ④ 만 있다.
- 미검증(R5 순서): 재배달된 옛 글의 문맥 내 순서 규칙(ts 정렬 vs 도착순)을 정하지 않았다.
- 미검증(모델 입력 격리 · S5): ⑤ 는 «파일로 나뉜 논리 컨텍스트» 까지다. thread 마다 실제 대화 이력·모델 요청 입력이 나뉘었는지 확인해야 한다. 파일 2개를 같은 누적 대화에 넣는 방식은 격리 근거가 아니다.
- 1.x 대안(2.0 채택 0 · 비교용): 현행 ft 에 계약 1·2·7 만 덧대는 길(원장·역할 키 재조회·mbox 꼬리 토큰은 이미 있다). 2.0 방향(#275603 · 기존 도구 격리 · 코드 참고만 · 신규 구성)에서 현행 추천은 §7 B 다(arch A3).
- 순서(#275604): 모형 사례 8·실토큰 4회는 근거로 유지한다. 새 실채널·추가 모형 실행은 §7 검토 뒤로 미룬다.
- 정정: 카드 기준값 «현행 ack 0 · journal 0» → 현행에는 메시지별 영속 원장이 있다(Slack ACK 만 없다). «pass 마다 replies 재조회» → `latest_reply` 가 바뀐 thread 만 재조회한다. 재독의 본체는 «창 루트 목록 전체» 와 «바뀐 thread 전체» 다.

## §7 사용자 신규안 검토 — Slack 공통 모듈 + 연결 풀 (#275604·#275605 · 검토이지 자동 채택 아님)

원칙(오빠): «슬랙은 슬랙대로 일반화와 작지만 강력한 시스템». Slack 모듈은 연결·binding·입출력 전달·복구만 맡는다. 골·배정·진척·완료는 공통 팀 도구 정본을 참조하고 복제하지 않는다. 팀/NW 별 봇·스크립트·크론 0. 메시지마다 모델 중계 0.

### 7-1 기존 gateway 실재 확인 **[실측 · 읽기만 · 설정 변경 0 · xapp 접속 0]** — `exp-r1500/raw/hermes-local.json` · `raw/hermes-byzmini.json` · `INPUT/hermes-agent.HEAD`

| 항목 | 로컬 Hermes(MacBook-Pro) | byz-mini 아이나 |
|---|---|---|
| 프로세스 | launchd `ai.hermes.gateway` → `hermes_cli/main.py gateway run --external-supervisor`(gateway_state.json) · 별도 `ai.hermes.gateway-zion` 1개 더 | launchd `ai.hermes.gateway`(같은 명령) |
| 코드 | hermes-agent 906227f1 v0.22.4 | 5894e750 v0.22.5 |
| Slack workspace / bot | T0AC5HC4ENR(ft bot 과 같은 workspace) / bot `hermes` | **T08C94A3CHM(다른 workspace)** / bot `aina` |
| 수신 방식 | Socket Mode(xapp 보유) · slack_bolt `AsyncSocketModeHandler`(`plugins/platforms/slack/adapter.py:1272`) | 같음(:1252) |
| 다른 입력 | webhook 플랫폼 127.0.0.1:8644(config `platforms.webhook`) | telegram·feishu |
| 저장소 | `~/.hermes/` 세션 DB·kanban.db·gateway_state.json | `~/.hermes/`(cron.db·kanban.db) |
| 권한 | scope 22 · `channels:manage` 있음 · 허용 사용자 3 · bot 글은 mention 때만 | scope 16 · `channels:manage` 있음 · 전체 사용자 허용 |
| 외부 event hook | `~/.hermes/hooks/` 비어 있음 · hook 은 agent:start 등 «관찰» 지점뿐(`gateway/hooks.py:1-9` · 오류가 흐름을 막지 않음) | 비어 있음 |

코드 경로 **[코드 · 로컬 906227f1]**:
- 수신 메시지는 거름(무시 채널 `adapter.py:4526` · bot `:4529`) 뒤 `handle_message`(`:4723` → `gateway/platforms/base.py:3990`)로 LLM agent 세션에 들어간다. 모델을 거치지 않는 «접수만» 하는 입구는 없다.
- 중복 제거는 메모리 `MessageDeduplicator`(`gateway/platforms/helpers.py:20` · 기본 2000개·TTL) 이고 키는 workspace+ts(`adapter.py:4523`)다. 재시작하면 잊는다. 영속 claim 은 없다.
- ACK 는 slack_bolt 기본값이 정한다. Hermes 는 `process_before_response` 를 설정하지 않는다(adapter.py 검색 0). bolt 기본값은 False 다(`venv/.../slack_bolt/app/async_app.py:116`). 그래서 ACK 가 listener 처리보다 먼저 나간다. 처리 전에 crash 하면 Slack 은 다시 보내지 않는다(실행 확인 0 · 코드·기본값 근거).
- 송신은 모델 없이도 된다: webhook route `deliver_only`(`gateway/platforms/webhook.py:568`)가 렌더한 글을 agent 없이 그 gateway 의 Slack 연결로 보낸다(멱등 delivery_id `:235` · chat_id·thread_id 는 `webhook_delivery.py:43`). 로컬에만 webhook 이 켜져 있고 route 는 0개다(쓰려면 설정 추가 = 관문 뒤).

### 7-2 후보안 3

| | A 기존 gateway 재사용 | B Slack 공통 모듈(별도 수신) | C 혼합(수신 B · 송신 A) |
|---|---|---|---|
| 수신 | Hermes·아이나 Socket Mode 를 그대로 쓰고 «비모델 접수» 입구를 Hermes 안에 새로 만든다 | 공통 모듈 1 프로세스가 workspace 별 시험/제품 app 연결을 풀로 든다(설정 1행 = workspace 1) | B 와 같음 |
| 송신 | 같은 gateway | 같은 모듈 · thread 1곳 | Hermes `deliver_only`(로컬 workspace 만) |
| 모델 호출 | 지금 구조로는 메시지마다 agent → 위반. Hermes 코드 변경이 있어야 0 | 0(모듈) · 모델은 팀 도구가 배정한 좌석의 자기 턴에서만 | 0 |
| 영속 claim·재시작 | 없음(메모리 dedupe · ACK 먼저) → Hermes 변경 필요 | 계약 2·4(§3) | 수신 B · 송신 쪽 미확정 상태는 Hermes 응답만 봄 |
| 바꾸는 것 | 외부 프로젝트(Hermes) 코드 2곳 · 두 머신 | 새 Slack app(사람 1회 · workspace 마다) · 모듈 1 | B + Hermes route 설정 |
| bot 정체 | hermes / aina | 모듈 app bot 1개(workspace 마다) | 수신 app ≠ 송신 hermes → 답이 다른 bot 이름 · echo 거름 2중 |
| 경쟁 접속 | 없음(같은 연결) | 없음(다른 app) | 없음 |

**추천(제안 · 2.0 현행 추천 · 자동 채택 아님)**: B. B 의 모듈은 2.0 신규 트리의 파일로 두고, 현행 `kit/` 는 참고 코드로만 인용한다(arch A3). 이유 3줄. ① A 는 «메시지마다 모델 0» 과 «영속 claim» 을 Hermes 코드 변경으로만 얻는다(우리가 소유하지 않는 코드 · 두 머신 버전도 다르다). ② 아이나는 다른 workspace 라, 어느 안이든 «workspace 별 연결 설정» 이 필요하다. B 는 그것을 설정 1행으로 둔다. ③ C 는 bot 정체가 둘로 갈려 echo 거름과 미확정 송신 판정이 두 곳이 된다. Hermes 는 그대로 두고, 사람이 Hermes 와 대화하는 기존 채널과 공통 모듈 채널을 겹치지 않게 나눈다(같은 채널에 두 bot 이 있으면 둘 다 반응한다).

### 7-3 B 의 최소 구조 (파일·프로세스·상태 종류·모델 호출 지점)

```
[Slack workspace W1..Wn]
   │ Socket Mode (app 마다 연결 1 · 설정 slack.yaml 의 행)
   ▼
(프로세스 1) slack-link ── 거름 → 메시지 키 → claim → ACK → 입구 전달 ──▶ 팀 도구 입구(mbox send / 카드 inbox)  ← 모델 0
   │                                       ◀── 영수(mbox seq) = dispatched
   │   상태 파일: journal.jsonl(claim·dispatched(영수)·intent·posted·uncertain) · binding.json · cursors.json
   ▲
   │  outbound 요청(팀 도구 요청 id = intent id)                                        ← 모델 0
팀 도구 정본(골·배정·진척·완료 · seats/카드/mbox)  ──▶  배정된 좌석의 자기 턴   ← 모델 호출은 여기 1곳
```

| 종류 | 이름 | 내용 | 정본 여부 |
|---|---|---|---|
| 설정 | slack.yaml | workspace → app 토큰 «파일 경로»·bot 토큰 «파일 경로»·허용 사용자 · channel → 팀 | 설정 정본 |
| 상태 | binding.json | `team:channel:root_ts` → 팀·골 id·topic·논리 컨텍스트 id·owner 역할 키·세대 | Slack 연결 정본(골 내용은 참조 id 만) |
| 상태 | journal.jsonl | inbound claim/dispatched(입구 영수) · outbound intent(팀 도구 id)/posted/uncertain | 전달·복구 정본 |
| 상태 | ctx/<binding>.jsonl · cursors.json | thread 별 논리 컨텍스트 · 좌석별 커서 | 전달 사본(골 정본 아님) |
| 정본 참조 | 팀 도구 | 골·배정·진척·완료·미결정 | 팀 도구 정본(복제 0) |

풀 = «연결과 binding 의 표» 다. 컨텍스트 공유가 아니다. 좌석은 자기 binding 의 ctx 만 읽는다.

키 분리(§3 3·4·5·10·11행):
- 메시지 키 = (workspace, channel, ts). 전송 중복 힌트 = `event_id`·`client_msg_id`. 회신 키 = (binding, intent id). intent id = 팀 도구 요청 식별자 그대로.
- inbound dispatched = 입구 영수(mbox seq). 영수 없이 재시작하면 재송 1번 + 메시지 키 표식 · 좌석이 표식으로 2번째부터 읽지 않는다.
- 회신은 «intent 를 먼저 적고 → post → posted ts 기록» 순서다. 응답이 끊기면 `UNCERTAIN` 이고, 표식 조회 3값(있음·없음 확인·판정 불가)으로만 다음을 정한다(§3-3). 참고 코드: 현행 `kit/mirror_lib.py:67` 의 «표식 채택 재실행».

조건별 처리:

| 조건 | 처리 | 시험(실험 단계) |
|---|---|---|
| bot echo | 자기 bot_id·다른 bot 글은 접수 0(ACK 만) · 허용은 설정의 bot 목록만 | T1 새 사례 |
| 같은 thread 복수 owner | binding owner 는 1 · 두 번째 claim 은 거절+오류 → 팀 도구 판정 | T2 새 사례 |
| 세대 교체 | owner 역할 키 + `_replaced_by` 사슬 · 구 세대 회신 거절 | ⑦ 재사용 |
| 미확정 송신 | intent→UNCERTAIN→표식 조회 3값 · 판정 불가 = 보존·담당·시한 · 자동 재송 0 | T3 새 사례 · S18 |
| 재접속 | Socket 재배달 + 영속 claim + 보충 회차 끝 조건 | ②③ 재사용 · D3 |
| 포화 | 429 Retry-After · 입구 가득 = 영수 0 · claim 보존 + 알림 | ④ + T4 새 사례 · S4 |
| 주제 누출 | binding 별 ctx · 좌석 입력은 그 ctx 커서 뒤만 · 모델 입력 격리는 따로 확인 | ⑤ 재사용 · S5 |
| 메시지마다 모델 0 | 모듈 프로세스의 모델 호출 수 = 0 을 세어 확인 | T5 새 사례(호출 계수) |

### 7-3a 업무 입구 라우팅 (#275636 · 정본 = `design/teams/planner/GUIDE-planner.md@eb2d525a90` §협업 ③)

- 신규 업무 = planner 가 사용자 논의·분류 결정·팀 배정을 한다. issues 는 접수·분류 안·등록·추적·배분 코멘트·닫기를 맡는다.
- 모든 입력을 planner 로 직행하지 않는다. 모든 메시지를 issues 모델로 중계하지도 않는다.
- 기존 thread 의 답글을 owner 좌석으로 바로 보내는 것은 2.0 설계 후보다(현재 정본 미확인). harness 직접 개선 접수는 기존 골을 유지한다.
- HTML(`slack-operation.html`) 기본 화면은 이 라우팅을 «사람 → Slack 공통 도구 → 업무 입구 → 팀 도구/NW → 기록 → 같은 thread 답» 시퀀스 하나와 상황 3개(신규 업무·기존 thread 답·중단 복구)로 보인다. 9상황 근거·계약·비교·숫자는 접힌 영역에 둔다.

### 7-4 최소 시험 계약(실험 단계 진입 조건)

1. 기존 모형 ②③④⑤⑦ 을 B 구조 이름으로 다시 돌린다(내용 같음).
2. 새 모형 T1~T5 와 DA D1~D4 를 더한다. 기대 결과는 §4 표 그대로다(실험 작성자가 임의로 정하지 않는다). 각 사례 = 결과 JSON + 실제/모형 열 분리.
3. 실채널은 #byz-dev-test 1개만 쓴다. 시험 전용 app(xapp) 이 생기기 전에는 «Web API 증분 조회» 만 하고, 그것을 최종 수신 구조로 쓰지 않는다.
4. Hermes·아이나는 읽기만 한다. xapp 경쟁 접속 0. 설정 변경 0.
5. 진입 순서 = 이 보정판 → arch 재확인 1회 → 오빠 확인 → 실험 → r1501 checker. 시험 app 생성·권한은 구체 항목(§6 첫 줄)으로 정리해 오빠께 1회 여쭌다.
