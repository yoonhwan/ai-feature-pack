# HANDOFF — 슬랙·세션·GitHub 홀 정리 → harness-ops (planner byz-planner-arch#3 · 2026-10-04 21:0x)

> 골 원문(GOAL-planner.md 원문 13·14 · 오빠 2026-10-04 18:3x~18:5x):
> 「브로드캐스트 채널 스레드로 작업 분리 잘됐는데 뭔가 아직 부족해 — 양방향 통신도 안되고 질의도 안되고 테스트 환경 문제있다는데 내가 피드백해도 응답 없음」
> 「tmm tmux 에 인터뷰는 직관적이고 멈춰있는데 슬랙은 이 부분이 가장 취약하네 이거부터 개선 최우선」
> 「깃헙 이슈 업데이트면 링크를 메시지에 담아줘야 내가 열지」
>
> 골의 축 = 원문 14 「슬랙 인터뷰 왕복 = P0(#820)」 / 닫는 증거 = 오빠 답 → 좌석 mbox seq → 집행 1줄 · 미답 보드 0 · 오빠 「이제 보인다」 1줄.

## 0. 오빠 지시(21:0x 원문) — 이 문서의 발주
> 「이건 harness ops 가서 할일이네 지금 정리내용과 나와 대화내용 전달. 거기서 da랑 나노워커들 셋팅해서 내가 확인 개선하고 돌아올께」

- 집행 주체 = **ft-harness-ops#1** (현역 · 하위 DA 1 + 나노 N 을 네 팀 안에서 개설 · DA = codex gpt-6.1-sol low · 나노 = claude-sonnet-5-5[1m])
- ★오빠가 harness-ops pane 에 직접 와서 확인·개선한다★ → 이 단위 동안 harness-ops#1 의 AskUserQuestion 은 **허용**(오빠 지시 · 평시 「하위 좌석 인터뷰 금지」 예외 · 끝나면 원복)
- 다른 좌석(v65·issue-manager·CCU)은 정지 레디 유지 · 재개 = 오빠 → planner
- 슬랙 launchd 3 은 bootout 상태(plist 보존) — 수정판 설치 때 bootstrap

## 1. 지금 구조(실측 · 21:0x) — 세 층의 차이
```
[오빠]
 ├─ tmux pane(planner) ── AskUserQuestion ──▶ 값이 같은 프로세스에 «직접» (동기 · 멈춰서 기다림)
 └─ Slack #byz-planner  ── 글 ──▶ 폴링 데몬 10초 → mbox 파일 (비동기 · 데몬 생존 의존)
[좌석 = tmux 안 Claude]  유일한 일하는 주체 · 통신 = mbox.sh(파일 큐 mailbox.jsonl + 도어벨 「[발주 #seq] recv …」)
[hermes 봇 U0B04VB3WSC] 역할 파일 C0C6MJGRR89.md 「읽기 전용 · 응답 0」 → 이 채널에서 아무것도 안 함(planner 손 게시 3건만 이 이름)
[데몬 3 · launchd · ~/.hermes/scripts/byz_*.py · state ~/.hermes/state/]
 ① mbox→Slack  byz_mbox_slack_mirror.py : mailbox.log.jsonl tail · 필터 to=^byz-planner-arch#N$ ★planner 수신분만★
      요약 = claude haiku CLI(mirror_summary.PROMPT 「todo = 오빠가 할 일 한 문장 · HIL 이면 질문 반드시」)
      키 = 본문 첫 「#N」 → byz_slack_threads.C0C6MJGRR89.json → reply / 없으면 루트 「#N 시작」 · 게시 봇 = xclaw-yoonhwan U0AS5HN14P6
 ② GitHub→Slack byz_github_slack_mirror.py : gh 목록 상태 차이 → 4종(열림·닫힘·머지·hil:needed) → 같은 thread map 루트 + URL
 ③ Slack→mbox  byz_slack_mbox_inbound.py : history+replies 폴링 · 사람 U0AC2JF0M7D 1명 · thread_ts → 소유 좌석(--seats seats-harness.json ★한 파일★) + planner 사본
      원장 = byz_slack_mbox_inbound.C0C6MJGRR89.json · 열린 질문 보드 = byz_slack_questions.C0C6MJGRR89.json
```
GitHub↔세션 수락 흐름: Issue(issue-manager gh) → ③출범 mbox → 작업 → PR → 좌석이 planner 에 「머지 판정 요청」 → planner 가 gh 재측 → **tmux AskUserQuestion(오빠)** → mbox GO → 좌석 gh pr merge → main sha → GitHub 미러 「merged」. ★②③은 tmux 안이라 슬랙엔 요청과 결과만 보임★.

## 2. 슬랙 홀 S1~S11 (채널 전체 덤프 · 루트 34 · 봇 2 · 사람 1)
| # | 홀 | 실측 | 원인 위치 |
|---|---|---|---|
| **S2 ★** | 「할 일」 줄이 지어낸 요청 — 좌석→planner 내부 보고가 전부 «오빠에게 요청»으로 | #56808 「언론 공개 후」(press) · #56693 「새 에이전트 종료 시점을 정해」 · #56873 「기반 작업 완료 후 자동 진행 예정」 · #56796 「다음 버전에서 개선하실지」 · #56877 「심사 승인하고 이슈 처리 마쳐」 · #823 「캐시 서버」(redis) · #825 「조회 전용」(observe) → 오빠 화면 = 「판단해 주세요」 30여 개 · 실제 오빠 몫 5 | mirror_summary.PROMPT todo 강제 · 수신자(planner) 무시 · 용어 사전 0 |
| **S3 ★** | 결정이 슬랙에 0 — planner→좌석 값(~15통) · 오빠 인터뷰 값 9 · 전부 미게시 | 스레드마다 질문만 쌓임 | ① 필터 to=planner 만 |
| **S4** | 작업 1 = 스레드 1 깨짐 | PR #824 일이 3곳(「#824 시작」·#820 스레드 Q56769·「ft-harness-ops 시작」) · #56707/#56710/#56715(#819 처리) → #820 스레드 · #56737/#56823 → 「#136 시작」 가짜 루트 · CCU 10건 → 「#817」1 뒤 「FB_CCU 시작」 · #56808(URL 4) → 「ft-issue-manager 시작」 | 키 = 본문 첫 #N 만 · 좌석명 #N 오인(수정 뒤에도 17:22 「#136」) |
| S5 | 계보 루트 6개가 「시작 —」 꼴 → 작업처럼 보임 | 「#0」·「ft-harness-ops」·「#136」·「FB_CCU」·「ft-issue-manager」·「ft-v65-master-claude 시작」 | 키 없는 보고 → 계보 루트 설계 |
| S6 | 루트 1줄 = 첫 reply 1줄 복제(전 스레드) | 노이즈 ×2 | format_row |
| S7 | 봇 2개(U0AS5HN14P6 좌석 보고 / hermes U0B04VB3WSC planner 손 게시) | 공식 구분 불가 | 토큰 분리 |
| S8 | relay 전문 미게시 → 17:30 「전문 / >」 인용으로 수정됨 ✅ | 체크리스트 본문은 planner 손 게시 | — |
| S9 | 「답을 기다리는 질문 N건」 보드 루트가 핀 아님 → 밀려 올라감 · 「0건」인데 S2 때문에 요청 30개 | 17:39 루트 | pins:write scope 0 |
| **S10 ★** | 자유문 답(「머르 체크하라고」) → 번호 매핑 0 → planner 해석 「1」로 머지 조건 집행(오빠 확인 0) | 17:46 seq 56773 | 자유문 규칙 1줄(설계 반영됨 · 미구현) |
| S11 | 메아리 2중(「slack-oppa 시작」 + 「누군가 스레드가 왜 새로 열렸는지 물었어요」) → 17:52 차단 ✅ | 1791103622.287519 | from=slack-oppa 미제외(수정됨) |
| S1 | 구 포맷 루트 11개(16:43~16:51 · 160자 잘림 · 「/ 내용:」 조각) 채널 머리에 잔존 | — | 단계 1 D1 사본 |
| 후보 | inbound 좌석 조회 = seats-harness.json 1개 → v65/issue-manager/CCU 질문의 오빠 답은 좌석 미도달 가능(미검증) | — | --seats 인자 |

## 3. 세션·GitHub 홀 H1~H19 (요지)
- H1 닫힌 좌석 5 생존(planner#1·#2 · v65 #135 · harness-ops#0 · FB_CCU#11) — 종료 집행 = 오빠 규칙
- H2 좌석 교체 시 미처리 mbox 이관 규칙 0(harness-ops #0→#1 때 planner 재기재로 보정)
- H3 pid 보고 ≠ 실측(36636/31826 보고 → 40221/34025) · 재시작 통지 0
- H4 역방향 전 오빠 피드백 좌석 도달 0(17:10 「체크 리스트」) · H5 relay 본문 미게시 · H6 좌석명 키 오인 · H7=S10 · H8=S11 · H9=S5 · H10 미답 보드 0건 스냅 · H11=S7
- H12 PR 3건(#814·#822·#823) 전부 「main 자체 빨강 2잡 면제」 머지 — CI 게이트 실질 0(#823 뒤 1197→107 · PR #824 는 기준선 차이로 미머지)
- H13 Issue 전부 status:needs-triage 고정 — 전이 규칙 0 · H14 Issue close 0(생성 9)
- H15 재기동마다 kill·prune 승인 왕복 ≈10분 · H16 issue-manager 가 Slack/미러 state 접근 0 · H17 DA HOLD → 같은 턴 수정·라이브(재DA 사후) · H18 GPU 과금(→ ORDERS 85 TERMINATED ✅) · H19 planner 가 Slack 직접 게시·폴링 크론(경계 밖)

## 4. 오빠와의 대화 요지(시간순 · 원문)
- 18:3x 「양방향 통신도 안되고 질의도 안되고 … 피드백해도 응답 없음」 → 원문 13
- 18:4x 「어디가서 피드백하는데? 답은 tmm 열어?」 → planner: 지금은 pane 또는 슬랙(손 중계) · #820 뒤 자동
- 18:5x 「tmm tmux 에 인터뷰는 직관적이고 멈춰있는데 슬랙은 이 부분이 가장 취약 — 이거부터 개선 최우선」 · 「깃헙 이슈 업데이트면 링크를 메시지에 담아줘야 내가 열지」 → 원문 14 · #820 P0
- 17:46(슬랙) 「머르 체크하라고」 · 17:47 「먼데 왜 스레드 새로파는데」
- 20:3x 「작업 모두 정지 레디」 · 20:4x 「지금 실제 작업으로 동작한 것 … 각 시점에 관측 내용과 실제 동작성 확인 정리 · 트리 · 어디가 홀인지 하나씩 상세 · 완성한 뒤에 다시 작업 · 절대 작업 수행 이어가게 하지 말고 내 판단 이후에 재개」
- 20:5x 「모두 정지했으면 슬랙부터 상세 트리. 뭔가 많이 이상한데 지금」 · 「크론도 정지 시켜 다들. 정지. 구현 시작하면 그때 재개」
- 21:0x 「hermes 봇이 있고 세션 tmux 가 있고 슬랙 메시지를 폴링하고 전송하는 구조 차이부터 설명 … github 과 세션 메시지를 어떻게 이어서 진행하고 수락받는지」 → §1
- 21:0x 「이건 harness ops 가서 할일이네 … da 랑 나노워커들 셋팅해서 내가 확인 개선하고 돌아올께」 → 이 문서

## 5. planner 권고 순서(값 아님 · 오빠가 harness-ops pane 에서 확정)
S2(요약 todo — 수신자가 planner 면 todo 0 · HIL 라벨만 질문 · 용어 사전) → S3(결정 방향도 게시: planner→좌석 값 · 오빠 인터뷰 값 1줄) → S4(키 = 「Issue/PR #N」 명시 + 발주서 키 · 좌석명 제외 · 다중 URL 보고는 각 스레드) → S10(번호 외 답 = 소유 좌석이 되묻기 · 해석 집행 0) → S5~S7·S9 → S1 · inbound --seats 전 팀 파일.
닫는 증거(원문 14): 오빠 답 1건 → 좌석 mbox seq → 집행 1줄 · 미답 보드 0 · 재스냅에서 가짜 루트 0 · 오빠 「이제 보인다」.

## 6. 재개 시(이 단위 끝 · 오빠 신호 → planner)
harness-ops#1: PR #824 main 병합→CI→머지 · v65 #136: DA#24 #721 판정→#732 arch OK→close · issue-manager: #825·#826·#827 ③ 출범 · CCU: ORDERS 85 뒤 재개 신청.
