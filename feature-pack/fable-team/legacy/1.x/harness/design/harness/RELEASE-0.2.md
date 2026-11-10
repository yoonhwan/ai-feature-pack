# RELEASE 0.2 — Slack 읽기 미러 단계 1 (2026-10-04 · 축 C 의 슬랙 면)

골 좌표: 축 C 「배포 발행(슬랙)」 — 닫는 증거 = 이 1장 + 머신별 「반영됨」 행. 설계 정본 = DESIGN-slack-mirror.md (main 9e50e6750a).
채널 = #byz-planner C0C6MJGRR89 · 발행 주체 = yoonhwan 봇 · 오빠 값 D1 허용 · D2 수락 · D3 핀=단계 2 · D4 멘션 U0AC2JF0M7D.

## 항목 (한 항목 = 한 커밋 · 회신)
| # | 항목 | 상태 | 증거 |
|---|---|---|---|
| ⓐ | 역할 파일 설치 + config.yaml channel_prompts 1항 + gateway kickstart | 완료 16:33 | 아래 |
| ⓑ | D1 — mbox.py send 에 append-only 사본(mailbox.log.jsonl) | 완료 16:38 | PR #812 main db18f53a9a · 아래 |
| ⓒ | 미러 스크립트 + launchd 1 | 완료 16:42 | 키트 75e07a1c42 · 아래 |
| ⓓ | 첫 게시 실측 1건 (ts) | 완료 16:43 | seq 56635 → ts 1791099807.837429 |
| ⓕ | 포맷 정정 — 사람 말 3줄(원문 §1-4) + 작업 1개=스레드 1개(원문 12 · §1-5) | 완료 | 커밋 6c1adc5b51 · 아래 |

## ⓐ 증거 (머신: 로컬 yoonhwan 맥 · hermes gateway = ai.hermes.gateway)
- 역할 파일: ~/.hermes/channel_roles/slack/C0C6MJGRR89.md ← design/planner/templates/slack-channel-role-planner.md @ v6-realtime-live bc55b49f9b
- config: ~/.hermes/config.yaml slack.channel_prompts.C0C6MJGRR89 4줄 추가(diff = 순수 추가 4줄) · 백업 ~/.hermes/config.yaml.bak-20261004-163311 · yaml.safe_load 통과 · 다른 slack 키 6개 그대로
- gateway: launchctl kickstart -k gui/501/ai.hermes.gateway · pid 720 → 11187 · 로그 「✓ slack connected」 16:33:32
- 되돌리기: 백업을 config.yaml 로 복사 + 같은 kickstart · 역할 파일 삭제

## ⓑ 증거
- PR #812 squash main db18f53a9a (커밋: 3e16932549 구조 · 0f8c550428 기능) · 시험 6건(빨강5→초록6) · ruff 신규 0
- 라이브 적용: .claude/fable-team/bin/mbox.py 612ba2cd → 910b7c1a · 16:37:56 · 백업 mbox.py.bak-20261004-d1 · py_compile OK
- 스모크: 회신 seq 56632 가 mailbox.log.jsonl 에 1행. 되돌리기 = 백업을 mbox.py 로 복사(사본 기록만 멈춤)
- 별건: mbox.sh 추적본≠라이브 → Issue #813

## ⓒ 증거
- 키트 scripts/harness-install/slack-mirror/ (byz_mbox_slack_mirror.py · mirror_lib.py · plist 템플릿 · install.sh) · 커밋 75e07a1c42
- 시험: 가짜 Slack 서버 10건 통과(중복 0 · 크래시 복구 · 조회 실패 시 미게시 · 본문 멘션 중화 · seq 공백 [BLOCK] · dry-run · 회전) · 변이 3종(마커 조회·중화·공백 가드 제거)이 각각 의도한 시험에서 잡힘 · ruff 통과
- 토큰: ~/.hermes/secrets/yoonhwan_bot.env (dir 700 · file 600) · auth.test = yoonhwan 봇 유효(값 미출력)
- launchd: com.hermes.byz-mbox-slack-mirror · pid 81977 · KeepAlive · ThrottleInterval 30 · 로그 ~/.hermes/logs/byz_mbox_slack_mirror.{out,err} · state ~/.hermes/state/byz_mbox_slack_mirror.byz.json
- 되돌리기: launchctl bootout gui/501/com.hermes.byz-mbox-slack-mirror · plist 삭제

## ⓓ 증거
- 이 발주 회신 seq 56635(to byz-planner-arch#2)가 #byz-planner C0C6MJGRR89 에 `[보고] ft-harness-ops#0 #56635 — …` 로 게시 · ts 1791099807.837429 (16:43:27) · state last_seq 56634→56635 · .err 에 오류 0
- 조건 1(WARN 시 [BLOCK]): 사본 기록 실패로 생기는 seq 공백을 미러가 감지해 [BLOCK] 1건 게시 — 시험 test_seq_gap_posts_one_block_message

## ⓕ 증거 (오빠 17:2x 「기계적·AI slop」 · 17:3x 원문 12)
- 커밋 6c1adc5b51 (PR #814 갱신) · 시험 22건(미러 16 + 사본 6) · 변이 5종(루트 복구·맵 상한·폴백 로그·5자리 키·꼬리 표시)이 각각 의도한 시험에서 잡힘
- 라이브 재설치: install.sh → launchd pid 73454 · ~/.hermes/scripts 에 mirror_summary.py 추가(백업 .bak-*) · state 에 threads 맵 추가(기존 키 유지)
- 실측: 회신 seq 56662 → #byz-planner 루트 1건 「#814 시작 — …」(ts 1791100419.405409) + 그 스레드 reply 1건(3줄: 무슨 일 / 오빠 할 일 / 소문자 꼬리) · 채널 루트에는 여는 줄만
- 요약기: claude -p --model claude-haiku-4-5 (headless · cwd=tmp · 설정 출처 0) · 메시지당 약 15초 · 실패 시 원문 첫 문장 + 꼬리 「원문 그대로」 + stderr ERROR(조용하지 않음)
- 알려진 모양: 스레드 첫 reply 의 1줄이 루트 문장과 같다(루트=「시작」줄 + reply=3줄 규칙대로). 이전 포맷 게시물(seq 56649~56660)은 채널 루트에 그대로 남아 있다(오빠 지시: 그대로 둠).
