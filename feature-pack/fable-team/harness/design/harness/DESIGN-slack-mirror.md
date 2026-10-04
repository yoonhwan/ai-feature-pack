# DESIGN — mbox → Slack 읽기 미러 (`byz_mbox_slack_mirror.py`) · 코드 0 · 준비만

골 원문(GOAL-harness.md 복붙): 「내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.」
골 좌표: 축 C 「배포 발행(슬랙)」의 슬랙 면 — 닫는 증거(복붙): 「RELEASE-<ver>.md 1장 + 머신별 『반영됨 <machine> <sha>』 행 전부」. 이 설계는 그 «발행 채널»을 소유하는 준비이고, 단계 1(읽기 미러)은 그 채널이 «말을 할 수 있게» 하는 최소 조각이다.
근거 문서: 정본 PROPOSAL-slack-driven-ops §13·§14 (v6-realtime-live/design/planner/) · 역할 파일 템플릿 `design/planner/templates/slack-channel-role-planner.md` · xClaw 라우터 `~/Project/xclaw-v2/scripts/xclaw-stream-router.py`.
> 발주문은 템플릿 sha edaadee2f4 라고 했으나 현재 파일의 마지막 커밋은 e5ceaa32e4(원문 10 정정 반영본)다. 아래는 e5ceaa32e4 판을 읽었다.

## 1. ★먼저 풀어야 할 구조 문제 — 입력 소스 (D1)

발주는 「입력 = mailbox.jsonl tail」인데, mbox 는 **consume-on-read** 다(`tools/comm-canonical/mbox.py` 헤더 「LIFO·per-to ring·consume-on-read」). planner 가 recv 하면 그 행은 mailbox.jsonl 에서 사라진다. 전문 파일 `comm/bodies/<seq>.txt` 는 소비 뒤에도 14일 남지만 **긴 본문(700자 초과)만** 쓴다(실측: bodies 1912개 · seq 범위 21062~56600).
⇒ **짧은 보고(3줄)가 미러가 읽기 전에 planner 에게 소비되면 슬랙에 영영 안 뜬다.** 미러의 존재 이유(폰에서 읽기)가 정확히 짧은 보고라서 이건 설계 결함 수준이다.

| 안 | 내용 | 유실 | 비용·위험 |
|---|---|---|---|
| A | mailbox.jsonl 을 N초 폴링 | planner 가 폴링 사이에 recv 하면 유실 — **0 보장 불가** | 코드 변경 0 |
| **B (추천)** | mbox.py send 경로에 «추가 전용» 사본 1줄 — `comm/mailbox.sent.jsonl` 에 {seq, ts, from, to, body[:700]} append | 0 (send 가 끝났다는 건 사본이 있다는 뜻) | **공유 하네스(mbox.py) 수정 1곳** — 전 좌석 통신 경로. DA·롤백 계획 필요. 파일 증가는 일 단위 회전 |
| C | bodies 를 모든 send 에 쓰도록 변경 | 0 | B 와 같은 수정 범위인데 파일 수만 폭증 → 기각 |

추천 B. 단 mbox.py 는 전 좌석이 쓰는 통신 정본이라 «하네스 업그레이드» 절차(Issue → 시험 → PR → RELEASE)를 그대로 밟고, 오빠 판정 후 착수한다. A 로 먼저 띄우는 길도 있으나 유실 가능을 알고 쓰는 것이어야 한다.

## 2. 인터페이스

`python3 ~/.hermes/scripts/byz_mbox_slack_mirror.py --project byz --mailbox <경로> --seat <regex> --channel <ID> [--state-dir <경로>] [--dry-run]`
- `--project` = 라벨(게시문 머리말·상태 파일 이름) — 프로젝트 무관 스크립트(xClaw 범용 층 자산).
- `--seat` = **정규식** `^byz-planner-arch#\d+$` — planner 좌석이 #1→#2 로 교체돼도 같은 설정이 산다(seat 이름 고정 시 교체마다 설정 변경 = 사고).
- `--channel` = Slack 채널 ID(오빠 생성 뒤 planner 가 1통 — 지금은 미정이라 `--dry-run` 만 가능).
- 입력 = D1 의 안(B 면 `mailbox.sent.jsonl` · A 면 `mailbox.jsonl`) — 같은 파서, 경로만 다르다.

## 3. exactly-once (「같은 seq 두 번 게시 0」)

상태 파일 `<state-dir>/byz_mbox_slack_mirror.<project>.json` = `{last_seq, pending}`. 순서:
1. 새 seq(> last_seq · 필터 통과) 선택 → `pending={seq, ts}` 기록(fsync).
2. 게시. `ok:true` 면 `last_seq=seq`, `pending=null` 기록.
3. **재시작 시 pending 이 있으면**: 게시 전에 채널 최근 50건(`conversations.history`)에서 본문 머리말 `#<seq>` 를 찾는다 — 있으면 이미 게시된 것(마커만 기록) · 없으면 게시. **조회 자체가 실패하면 게시하지 않고 raise**(중복보다 지연이 낫다 · 사람이 `.err` 로 본다).
- xClaw 라우터는 «시도 전 NX 가 아니라 성공 뒤에만 sent marker»를 교훈으로 남겼다(`:1244-1275` BLOCKER 수정). 같은 원칙이되, 게시와 마커 사이에서 죽는 창은 위 3번으로 닫는다 — Slack 에 멱등 키가 없어서 «조회 후 게시» 가 유일한 방법이다.

## 4. 게시 — 재사용과 «재사용하면 안 되는 것»

| xClaw 자산 | 판정 | 이유 |
|---|---|---|
| `_slack_post` HTTP 형태(`:1222-1243` · urllib · chat.postMessage · 의존 0) | ✅ 요청 모양만 | **실패를 삼킨다**(`return False` · 「라우팅 비차단」) — BYZ #0 RULE(실패 = raise)과 충돌. 복사 후 `ok!=true` 면 raise 로 바꾼다 |
| `_esc`(`:1102-1109` `&<>` 중화) | ✅ 필수 | mailbox 본문은 **다른 에이전트가 쓴 미검증 입력**이다. 중화 없이 게시하면 본문의 `<!channel>`·`<@U…>` 가 전 채널 알림이 된다 |
| `_load_yoonhwan_bot_token`(`:1080`) | ✗ | 환경변수 → 죽을 NanoClaw 크루 `.env` 폴백 체인(조용한 폴백). 미러는 단일 출처만 읽고 없으면 raise |
| 포맷 | ✅ | 한국어 mrkdwn · 표 0 · 4~5줄 `[보고\|HIL\|BLOCK] <from> #<seq> — <제목>` / 내용 3줄 / 전문 경로 |

토큰 출처(D2): launchd plist 에 토큰을 쓰지 않는다. `~/.hermes/secrets/yoonhwan_bot.env`(chmod 600, `YOONHWAN_BOT_TOKEN=`)를 스크립트가 읽는다. 토큰·채널 설정의 «지속 관리»는 harness-ops 몫(오빠 16:3x)이라 이 파일의 권한·회전도 harness-ops 가 본다. 로그에 토큰 0(`***` 마스킹 테스트 포함).

## 5. [HIL] — 스레드 1 + 핀

- 태그 판별: 본문 첫 줄 `[HIL]` → HIL, `[BLOCK]` → BLOCK, 그 외 보고.
- HIL 게시 = 채널 본문 1건(= 스레드 루트) · 이후 같은 질문의 후속은 `thread_ts` 로 그 스레드에. 오빠 멘션은 **설정 파일의 고정 사용자 ID 1개만**(D4) — 본문에서 온 멘션 토큰은 전부 중화.
- **핀은 지금 불가능**: 읽어 본 yoonhwan 봇 manifest(`~/Project/xclaw-v2/docs/xclaw-yoonhwan-slack-manifest.json`)의 scope 에 `pins:write` 가 없다(user: chat:write·channels:history 등 20개 / bot: 8개). 핀하려면 scope 추가 + 앱 재설치 = **오빠 몫**(D3). 그 전까지 `--pin` 은 꺼 두고, 켠 상태에서 scope 가 없으면 raise(게시·마커는 이미 끝난 뒤라 중복은 없다).

## 6. 침묵 · 실패

- 새 seq 없음 → 게시 0 · 하트비트 0 · 「정상」 게시 0(템플릿 §1-6 그대로).
- 필터: `to` 가 `--seat` 정규식에 맞는 것만. 도어벨·ring 알림 같은 기계 메시지는 `from` 허용 목록이 아니라 **본문 첫 줄에 `[` 로 시작하는 태그가 없는 것**도 일단 «보고»로 게시(조용히 버리는 필터를 만들지 않는다 — 버려지는 걸 아무도 못 본다). 소음이 실측되면 그때 규칙을 추가.
- 실패 = raise · 재시도 0 · exit 비0. stderr → `~/.hermes/logs/byz_mbox_slack_mirror.err`. launchd `KeepAlive` + `ThrottleInterval 30` — 죽으면 launchd 가 다시 띄우고, 다시 뜬 뒤에도 같은 실패면 `.err` 가 계속 쌓여 보인다(조용히 멈추지 않는다).
- **seq 공백 가드(오빠 조건 1 · 구현됨)**: mbox.py 가 사본 기록에 실패하면 stderr WARN 만 남고 그 seq 는 사본에서 빠진다 — 미러가 행 사이 seq 공백(`BLOCKED` 는 seq 를 소모하지 않으므로 공백 = 기록 누락)을 감지해 `[BLOCK] mirror #GAP-<a>-<b>` 1건을 채널에 올린다(공백 알림도 exactly-once). 유실이 조용하지 않다.
- 모니터 연결: `harness-monitor.sh`(#806)에 «미러 마지막 게시 seq vs sent 마지막 seq 격차» 검사 1줄 추가 — 격차가 크면 WARN.

## 7. 배치

- 실행본: `~/.hermes/scripts/byz_mbox_slack_mirror.py` · plist `~/Library/LaunchAgents/com.hermes.byz-mbox-slack-mirror.plist`(launchd 1개 · 공유 하네스 밖 · 메인 엔진(mbox)에는 읽기 접근만).
- 버전 관리: 소스·plist 템플릿·설치 스크립트를 레포 `scripts/harness-install/slack-mirror/` 에 두고 설치 스크립트가 `~/.hermes` 로 복사(RELEASE 1장에 머신별 반영 행) — 머신이 늘면(jarvis 등) 같은 키트가 간다.
- 역할 파일 `~/.hermes/channel_roles/slack/<ID>.md` + `config.yaml` `slack.channel_prompts.<ID>` 1항: 템플릿 §4 그대로 — 채널 ID 가 나온 뒤 설치(집행 = harness-ops).

## 8. 구현 때의 시험 계획 (지금은 안 한다)

fixture mailbox 로 ①같은 seq 2회 입력 → 게시 1 ②게시 직후 강제 종료 → 재시작 → 중복 0 ③잘못된 토큰 → raise·exit≠0 ④본문 `<!channel>` 주입 → 중화 확인 ⑤HIL 스레드 1·후속은 thread ⑥침묵 ⑦`--dry-run` 출력 대조. 실 Slack 호출은 오빠가 채널을 만든 뒤 테스트 채널 1회.

## 9. 결정 요청 (planner #2 → 오빠)

| # | 질문 | 추천 |
|---|---|---|
| D1 | 입력 소스: B(mbox.py send 에 추가 전용 사본 1줄 — 유실 0 · 공유 하네스 수정) vs A(폴링 — 유실 가능) | B |
| D2 | 토큰 출처: `~/.hermes/secrets/yoonhwan_bot.env`(chmod 600) | 이 안 |
| D3 | yoonhwan 봇에 `pins:write` 추가 + 재설치(오빠) — 핀을 단계 1 에 넣을지, 단계 2 로 미룰지 | 단계 2 로 미룸 |
| D4 | [HIL] 에서 멘션할 Slack 사용자 ID(오빠) | 오빠가 ID 1개 알려줌 |
