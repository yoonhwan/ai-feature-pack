# WIP — 군집 관제 기획 리서치 노트 (ft-harness-arch#0 · 2026-10-04 · 정지 레디 시점 스냅)

> 골 원문(GOAL-harness.md 복붙):
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
>
> 골의 축: 축 A(모니터·오빠 요청) + 축 B(오케 개선요청 접수·협의). 발주 = `BRIEF-swarm-control-arch-20261004.md` §1단계 산출물 3(웹리서치).
> 상태: **정지 레디(오빠 지시 · mbox #56912)**. 산출물 2·4·5·설계 1장은 미착수. nano 사실표 미수신. DA 발주 0.

## 1. 읽은 정본 (구조 분석 입력)
- `design/harness/HANDOFF-slack-holes-20261004.md` — S1~S11 · H1~H19 · 3층 구조(pane 동기 / Slack 비동기 폴링 10초 / 좌석=mbox).
- `design/harness/DESIGN-slack-inbound-820.md` — 역방향 원장·열린 질문 보드·자유문 규칙·exactly-once 계약(중복 최악 1회).
- `design/harness/DESIGN-slack-mirror.md` — D1 consume-on-read 문제 → 사본 로그 B 채택.
- `design/planner/PROPOSAL-slack-driven-ops.md` — 3층 유지(슬랙=사람 창구 · planner=원장 · tmux=실행) · jarvis/hermes C안 · Issue 1=행 1 · 프로파일 레지스트리.
- `tmm --help` — `tmm h`(HUMAN/BLOCK/STUCK 만) · `tmm s`(도달확인 송신) · `tmm ss` 전 좌석 스캔 · `tmm dead/restore-all` · fork. ★오빠 「이미 잘 되고 있는 것」의 실체 = 이 TUI(SSH 터미널 필요).

## 2. 웹리서치 (3/4 완료 · 4번째는 rate-limit 으로 미실행)

### 2-1. LangGraph `interrupt()` / `Command(resume)` — «멈춤 = 저장된 상태 + 재개 키»
- 핵심: interrupt 는 (체크포인터 · thread_id · JSON payload) 셋이 전제. 멈춘 지점은 «상태 파일» 이고 재개는 같은 thread_id 로 `Command(resume=값)`.
- ★재실행 함정: 재개 시 그 노드가 «처음부터» 다시 돈다 → interrupt 앞의 부작용은 멱등이어야 함. 우리 대응물 = 좌석이 [HIL] 보낸 뒤 답이 오면 «그 턴을 다시 시작» — 답 도착 전에 한 일(커밋·게시)은 멱등 키 필요(#820 exactly-once 와 같은 문제).
- 우리 구조 매핑: thread_id = 질문번호 `Q<seq>` · 체크포인터 = `byz_slack_questions.<채널>.json` + 좌석 트랜스크립트(tmm idx) · resume = mbox `[HIL-ANSWER]`.
- 출처: https://docs.langchain.com/oss/python/langgraph/interrupts · https://docs.langchain.com/oss/python/langgraph/graph-api · https://docs.langchain.com/oss/python/langchain/human-in-the-loop

### 2-2. Temporal Approval Pattern — «대기에는 반드시 타임아웃 + 에스컬레이션 경로»
- 공식 패턴: wait_condition(timeout) → 시그널(승인 데이터: 누가·왜·언제) 또는 타임아웃 → 거절/에스컬레이션. 다단계 승인·에스컬레이션 변형 있음.
- ★프로덕션 함정 1위: «타임아웃·에스컬레이션 없는 HIL 대기» — 알림 미전달·버그·부재 시 영원히 멈춤 · 복구 경로 0. 우리 H1~H19 의 「좌석이 기다리는데 아무도 모름」 과 같은 꼴.
- 권고 4: ①핸드오프 지점에 타이머(SLA 뒤 정의된 행동: 에스컬레이션/보조 승인자 알림) ②상태 어휘 5(submitted·acknowledged·approved·rejected·timed_out — pending/done 이분 금지) ③시그널 핸들러 멱등(버튼 2번 클릭) ④멈춘 승인의 가시성 = 검색 속성 + 알림(사람이 눈치챌 때 조회 금지).
- ★우리 규칙과 충돌 1: 글로벌 「No timers」(feedback_no_timer…)는 «집행 타이머» 금지이지 «대기 가시화·에스컬레이션 알림» 까지 금지인지 오빠 판정 필요 → 질문 후보.
- 출처: https://docs.temporal.io/design-patterns/approval · https://temporal.io/blog/human-in-the-loop-approvals · https://www.xgrid.co/resources/temporal-ai-agent-orchestration-failure-patterns/

### 2-3. Slack 승인 봇 — Block Kit 버튼 · Socket Mode vs HTTP (★폴링 모델은 Slack 에 없다)
- 상호작용 수신 경로는 2개뿐: HTTP Request URL(공개 HTTPS · 3초 내 200) / Socket Mode(xapp 토큰 · 아웃바운드 WSS · 공개 포트 0 · 내부앱 권장 · 동시 연결 10 · 컨테이너 재활용으로 간헐 끊김). 지금 우리 inbound 는 `conversations.history` 폴링 = 버튼 불가 · 텍스트 답만.
- 버튼을 쓰려면: Interactivity 켜기(Socket Mode 만으론 block_actions 미전달 — 실패 사례) · 클릭 멱등·클릭자 기록 · 라이브 상태 대조(first-wins) · 승인 카드는 봇 소유 별도 메시지 · stale 카드 만료 · 결정 뒤 `chat.update`.
- 우리 적용 판정: 오빠 폰 답 = 번호 텍스트(지금) vs 버튼(Socket Mode 데몬 1개 추가 + 앱 설정 변경 = 오빠 손). 단일 인스턴스 내부앱이라 Socket Mode 가 맞음 — 단 끊김 시 폴링 폴백이 아니라 «끊김 = .err + 재접속» 으로.
- 출처: https://docs.slack.dev/apis/events-api/comparing-http-socket-mode/ · https://docs.slack.dev/apis/events-api/using-socket-mode/ · https://api.slack.com/automation/interactive-messages · https://github.com/stabrea/Branch-Agent/pull/693

### 2-4. (미실행) 코딩 에이전트 군집 관제·Issue 배정 사례 — 재개 시 1회 검색.

## 3. 재개 시 다음 한 수
1. nano 사실표 수신(mbox) → ft-harness-da#0 에 검증 발주.
2. 산출물 2 「Slack 이 왜 필요한가」 — 표 1개: 상황(원격·폰·자는 동안·여러 사람·여러 머신) × pane/tmm 가능 여부 × Slack 필요 여부. 「하지 않는다」 결론 허용.
3. 산출물 4 분해(S/H 홀을 «쌓인 문제» 단위로 · 증거·빈도·체감·닫는 증거) → 설계 1장 `DESIGN-swarm-control-20261004.md` + 오빠 질문 ≤5 → ft-harness-ops#1.
