# FACTS — Slack #byz-planner 현황 사실표 (nano 전수 조사 · 2026-10-04)

작성: ft-harness-nano#0 (opencode · openrouter/deepseek-flash-latest, 읽기 전용) · 발주: ft-harness-ops#1
브리프: `design/harness/BRIEF-swarm-control-arch-20261004.md` §1단계 산출물 1번 «현황 사실표»
조사 시각: 2026-10-04 20:45~20:5x (KST) · 채널 **C0C6MJGRR89 = #byz-planner**
조사 방법(재현): Slack `conversations.history`(limit 200, next_cursor 끝까지) + 각 루트 `conversations.replies`(끝까지) 전수 덤프 → 아래 집계. 대조 = `~/.hermes/logs/byz_*.err`, `.fable-team/comm/mailbox.log.jsonl`(보낸 사본), `mailbox.jsonl`(큐), `~/.hermes/state/byz_*.json`, `launchctl list`.
경계: 코드·설정·launchd·Slack 게시 **수정 0**. 모든 수치는 위 시각 스냅샷. 값·추측 구분 표기.

---

## §A. 층 구성 실측 (브리프 §1 검증)

| 층 | 실측 | 근거 |
|---|---|---|
| 채널 | #byz-planner · C0C6MJGRR89 · 이름 `byz-planner` | `conversations.info` |
| 봇 1 (좌석 보고) | **U0AS5HN14P6** · bot_id B0ARZTTV1GE · 게시 86건 | 전 메시지 86/95 |
| 봇 2 (planner 손 게시) | **U0B04VB3WSC** · bot_id B0AUJA7KQ1H · 게시 3건 | 머리 3건 |
| 사람 | **U0AC2JF0M7D** · 게시 3건 | 아래 §D |
| 채널 참여 이벤트 | U0AC2JF0M7D / U0AS5HN14P6 / U0B04VB3WSC 각 1 (16:4x) | subtype `channel_join` |
| 데몬 3 (launchd) | **현재 전부 미기동** — `launchctl list` 에 byz mirror 항목 0 | plist 3개는 `~/Library/LaunchAgents/com.hermes.byz-{mbox-slack-mirror,github-slack-mirror,slack-mbox-inbound}.plist` 에 존재 |

- `launchctl list` 에 남은 byz 항목 = `com.byz.gce-guard-check`, `dev.byz.*` 뿐. mirror 3종은 bootout 상태(브리프 §27 «planner bootout» 과 일치).
- 채널 총 메시지 = **95** (루트 34 + 스레드 reply 61). 봇1 86 · 참여 3 · 사람 3 · 봇2 3.

## §B. 채널 전수 집계

| 분류 | 건수 | 비고 |
|---|---|---|
| 루트 전체 | 34 | history 34 |
| ├ 참여 이벤트 | 3 | channel_join |
| ├ 「… 시작 —」 스레드 루트 | 20 | 질문 카드/보고가 붙는 정상 루트 |
| ├ 구 포맷 `[보고] …` 루트 | 10 | 16:4x · 요약 3줄 이전 원문 꼴 (S1) |
| └ 보드 | 1 | ts `1791103146.899609` 「답을 기다리는 질문 0건」 |
| 3줄 포맷 report 행 | 48 | `(좌석 · #seq)` 꼬리 있는 것 |
| GitHub 이벤트 reply | 5 | `(github #N opened/merged)` |
| 사람 글 | 3 | 전부 reply(루트 사람 글 0) |
| 봇2(hermes) 손 게시 | 3 | 체크리스트 2 + meta 진단 1 |

## §C. 루트 20 + 계보 키 (thread map 실측)

`~/.hermes/state/byz_slack_threads.C0C6MJGRR89.json` 키 20: `#814 #732 #815 #817 #816 #721 #819 #0 #820 ft-harness-ops #136 FB_CCU #824 slack-oppa #823 #825 ft-issue-manager #826 #827 ft-v65-master-claude`

- **Issue URL 줄이 있는 루트 = 5** (`#823 #824 #825 #826 #827`) — 17:5x 링크 규칙(§3b) 배포 뒤 생성분만. 그 이전 15개 시작 루트엔 URL 없음(`#814 #815 #816 #817 #819 #820 #721 #732 …`).
- 비(非)번호 계보 키 6 = `ft-harness-ops` · `#0` · `#136` · `FB_CCU` · `ft-issue-manager` · `ft-v65-master-claude` · `slack-oppa`. 이 중 `#0`·`#136` 은 Issue 가 아닌 «좌석명이 #N 으로 오인» 된 키(S4/S5).

## §D. 봇별 게시 · 사람 글 (ts 포함)

**사람 U0AC2JF0M7D (3건, 전부 스레드 reply):**
1. `1791101433.264569` 「체크 리스트」 — #819 스레드(notice: 요약/전문 없이 원문만)
2. `1791103568.347679` 「머르 체크하라고」 — #820 스레드 = 열린 질문 Q56769 의 답
3. `1791103658.099929` 「먼데 왜 스레드 새로파는데」 — slack-oppa(메아리) 스레드

**hermes 봇 U0B04VB3WSC (planner 손 게시 3건):**
1. `1791101758.130079` #819 체크리스트 전문(미러가 본문 미게시 → planner 직접)
2. `1791101893.713359` 체크리스트 GitHub 정본 링크
3. `1791103724.879319` 「결함이에요 — 오빠 답이 mbox 로 들어간 뒤 미러가 그걸 다시 슬랙에 '새 작업'으로 올렸어요(메아리)…— planner」 (meta 설명)

**GitHub 미러 이벤트 reply (5):** `#823 merged`(1791104304.181209) · `#824 opened`(1791102518.976759) · `#825 opened`(1791104347.414689) · `#826 opened`(1791104362.105689) · `#827 opened`(1791104375.733909).

## §E. 요약 품질 (S2) — «오빠 할 일» 지어냄

3줄 포맷 48행 중 **todo 줄에 판단·요청 어휘(주세요/판단/승인/결정/알려/정해/확인…)가 있는 행 = 31**. 그중 **실제 HIL 멘션(`<@U0AC2JF0M7D>`)이 붙은 행은 3건뿐**(Q56769 `1791103147.378619` · `1791100911.952059` · `1791101057.268349`). 나머지 **약 28건은 좌석→planner 내부 보고인데 «오빠에게 판단 요청»으로 표시**(= S2 재현).

대표 예(좌석 → 슬랙 todo 원문 → 실제 수신자는 planner):
| seq | seat | 슬랙에 뜬 «오빠 할 일» | ts |
|---|---|---|---|
| #56808 | ft-issue-manager#0 | 「언론 공개 후 다음 단계를 진행해도 될지 알려 주세요」 | 1791104355.867699 |
| #56693 | ft-harness-ops#0 | 「새 에이전트의 작업 상황을 고려해 종료 시점을 정해 주세요.」 | 1791101494.807509 |
| #56873 | ft-issue-manager#0 | 「기반 작업이 완료된 후 자동으로 진행될 예정이에요.」 | 1791105472.570139 |
| #56796 | FB_CCU#12 | 「다음 버전에서 이 부분을 개선하실지 판단해주세요.」 | 1791104031.170829 |
| #56877 | ft-v65-master-claude#136 | 「심사를 승인하고 기록을 정리한 뒤 이슈 처리를 마쳐 주세요」 | 1791105583.301659 |
| #56754 | FB_CCU#12 | 「최악의 상황에 대비해 자원 할당을 다시 검토해주세요.」 | 1791102576.988969 |

→ 채널에 «판단해 주세요» 류가 30건 내외로 깔리는데 실제 오빠 몫은 소수. 원인 후보(추측): `mirror_summary.PROMPT` 「todo = 오빠가 할 일 한 문장」 강제 + 수신자(to) 무시. (근거: `byz_mbox_slack_mirror.err` 에 요약 실패 1건 `seq=56689` → 원문 첫 문장 대체 로그).

## §F. 가짜 루트 · 계보 (S4·S5)

- **작업 1 ≠ 스레드 1**: `#824` 일이 3곳 — `#824 시작`(1791102518.646299) + #820 스레드 + `ft-harness-ops 시작`(1791102060.440779).
- **좌석명이 루트로**: `ft-v65-master-claude 시작`(1791105494.394029) · `FB_CCU 시작`(1791102221.306569) · `ft-issue-manager 시작`(1791104355.523259) · `ft-harness-ops 시작`(1791102060.440779).
- **`#136 시작`**(1791102142.252429) = 이슈 136 이 아니라 좌석 `ft-v65-master-claude#136` 의 #56737/#56823(#819 처리)이 잘못 키된 루트.
- **`#0 시작`**(1791101438.745559) = 승계 좌석 라벨 `#0->#1`.
- **루트 1줄이 첫 reply 복제**(S6): `#814 시작`(1791100419.405409) ↔ 첫 reply(1791100419.882639) 등 시작 루트 전부.
- **구 포맷 잔존**(S1): 16:4x `[보고] …` 원문 10개가 채널 머리에 그대로(160자 잘림·`/ 내용:` 조각 꼴).

## §G. 결정 미게시 (S3) — planner→좌석 값이 슬랙에 0

- `mailbox.log.jsonl` 에 **planner-arch#N → 좌석 = 53행** (ft-issue-manager#0 15 · ft-harness-ops#1 12 · ft-v65-master-claude#136 9 · ft-harness-ops#0 7 · FB_CCU#12 6 · planner 내부 4). 이 중 슬랙 게시 = **0건**.
- 원인: 미러 필터 `--seat ^byz-planner-arch#\d+$` = **planner «수신» 행만** 게시(코드 `byz_mbox_slack_mirror.py:125`). planner «발신» 행은 구조적으로 안 올라감.
- 오빠 인터뷰 값도 미게시: 사람 글 3건 중 mbox 반영은 1건(56773). #820 스레드에 «planner 해석» 결정 1줄 없음.

## §H. 역방향 · 보드 (S9·S10·S11)

- **보드**: `byz_slack_questions.C0C6MJGRR89.json` = `open {}` · `resolved {56769: 1791103936}` · `board_ts 1791103146.899609` · 문구 「답을 기다리는 질문 0건」. 핀 아님(루트로 밀림).
- 보드가 «0건» 인데 같은 시각 HIL 멘션 글 3건이 스레드에 존재 → 보드↔실제 불일치(S9).
- **자유문 답(S10)**: 오빠 「머르 체크하라고」(1791103568.347679) → 번호 매핑 0 → 원문 그대로 좌석 전달(seq 56773). 이후 planner 해석은 슬랙에 미게시.
- **메아리 2중(S11)**: `slack-oppa 시작`(1791103622.287519) 루트 = from=slack-oppa 행이 다시 게시된 것. 차단 커밋 뒤 seq 56790(17:52)서 해소. 현재 미러 코드 `byz_mbox_slack_mirror.py:125` 에 `from=="slack-oppa"` 제외 반영.
- **inbound 원장(실측)**: `byz_slack_mbox_inbound.C0C6MJGRR89.json` ledger 2건 — `1791103568.347679`(Q56769 → ft-harness-ops#1 + planner, done) · `1791103658.099929`(질문 없음 «추정» → planner only). baseline `1791103104.165305`.

## §I. 정방향 미러 정지 실측

- `byz_mbox_slack_mirror.byz.json`: `last_seq = 56881` · 파일 mtime 18:31 · `pending null`. mirror 가능 행(seq>56634, to=planner, from≠slack-oppa) = **64행**, 그중 seq≤56881 = 58행 게시, **seq 56882~56908 = 6행 미게시**(56893·56894·56900·56901·56906·56907).
- `mailbox.log.jsonl` 은 seq 56632~**56908**(277행)까지 쌓였는데 미러는 56881 에서 멈춤 = 데몬 bootout 시점과 일치. «보낸 것 ≠ 올라간 것».
- `mailbox.jsonl`(큐) 436행 · seq 8~56885. 오빠 답 seq 56773 은 큐에 없음(소비 완료) → 원장/로그에만.

## §J. 로그 대조 요약

| 축 | 수 | 출처 |
|---|---|---|
| 보낸 것(전체 mbox 사본) | 277행 (seq 56632~56908) | mailbox.log.jsonl |
| 그중 to=planner-arch#N | 68행 (from=slack-oppa 2 포함) | mailbox.log.jsonl |
| 미러 게시 대상(필터 통과) | 64행 → 58행 게시 | state last_seq·Slack |
| Slack 봇1 게시 | 86건(루트·reply·보드·github) | conversations.* |
| `byz_*.err` | `byz_mbox_slack_mirror.err`: baseline 56634 + 요약실패 1(seq 56689) · `byz_github_slack_mirror.err`: baseline open=95 since 08:27:22Z · `byz_slack_mbox_inbound.err`: baseline 만 | 로그 3종 |
| `.out` | 3종 모두 0 byte | 로그 3종 |

## §K. «0» 의 축 명시

- planner→좌석 결정 슬랙 게시 **0** (축: 미러 필터).
- 실제 오빠 판정 필요 글이 보드에 표시된 수 **0** (축: questions.open) — 실제 HIL 멘션 3건과 불일치.
- 루트 사람 글 **0** (축: history, 사람은 전부 reply).
- 미러 데몬 기동 **0** (축: launchctl list).

## §L. 미확인 · 한계 (추측과 사실 구분)

- **추측**: S2 원인(=요약 프롬프트 강제)은 코드·프롬프트 문면 기반 추정이며 프롬프트 실행 로그로 «직접» 확인하진 않음.
- **미확인**: ①`#819` 체크리스트가 미러로 안 올라간 정확한 실패 지점(미러 .err 엔 미기록, planner 손 게시로 대체된 것만 확인) ②Slack ts→KST 정밀 매핑(epoch 초 근사) ③대화별 `reply_count` 와 실측 reply 수의 미세 차이 ④inbound 7일 창 밖 reply 미조회.
- **한계**: 위 집계는 20:5x 스냅샷. Slack 은 데몬 정지 상태라 이후 신규 글 0. `conversations.replies` 20쪽 초과 없음(최대 스레드 #819 rc=10).

---
sha256(이 문서) = 아래 mbox 보고에 첨부.
