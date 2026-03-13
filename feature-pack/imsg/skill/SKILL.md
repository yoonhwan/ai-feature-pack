---
name: "imsg"
description: "iMessage/SMS CLI — 대화 조회, 메시지 전송, 실시간 수신 감시 + 에이전트 알림 채널. 어떤 도구에서든 imsg send로 iMessage 알림 가능."
version: "1.0.0"
status: active
---

# imsg Skill

macOS Messages.app을 터미널에서 제어. 대화 조회, 메시지 전송, 실시간 수신 감시.
**에이전트/크론/스크립트에서 iMessage 알림 채널로 활용 가능.**

## When to Use

✅ **USE:**
- 사용자가 iMessage/SMS 전송 요청
- 대화 목록 또는 히스토리 조회
- 실시간 메시지 수신 감시 (watch)
- 에이전트/크론 작업 완료 알림 전송
- 다른 코딩 도구(Claude Code, Codex 등) 결과 알림

❌ **DON'T USE:**
- Telegram → `message` 도구 (`channel:telegram`)
- Slack → `slack` 스킬
- Discord → `message` 도구 (`channel:discord`)
- Signal → Signal 채널
- 그룹 멤버 관리 (미지원)
- 대량 발송 (반드시 사용자 확인 필요)

## Requirements

- macOS + Messages.app (iCloud 로그인)
- 터미널 Full Disk Access 권한
- Messages.app Automation 권한

## Decision Flow

```
메시지 요청 수신
  ├─ iMessage/SMS? → YES → imsg 사용
  │                → NO  → 해당 채널 도구 사용
  ↓
수신자 확인
  ├─ 전화번호/이메일 있음? → imsg send --to
  ├─ chat-id 있음? → imsg send --chat-id
  └─ 이름만 있음? → imsg chats --json → 검색 → 확인 후 전송
  ↓
전송 전 확인
  ├─ 사용자 직접 요청? → 수신자+내용 확인 후 전송
  └─ 에이전트 알림? → 사전 설정된 번호로 즉시 전송
```

## CLI Reference

### chats — 대화 목록

```bash
imsg chats [options]

Options:
  --limit <N>       표시할 대화 수
  --json, -j        JSON 출력
  --db <path>       chat.db 경로 (기본: ~/Library/Messages/chat.db)
  -v, --verbose     상세 로깅

Examples:
  imsg chats --limit 10 --json
  imsg chats --limit 5
```

**JSON 출력 필드:** `chat_id`, `displayName`, `lastMessage`, `lastMessageDate`, `service`, `participants`

### history — 메시지 히스토리

```bash
imsg history [options]

Options:
  --chat-id <ID>    대화 ID (chats에서 확인)
  --limit <N>       메시지 수
  --start <ISO8601> 시작 시간 (inclusive)
  --end <ISO8601>   종료 시간 (exclusive)
  --participants <handles>  참여자 필터
  --attachments     첨부파일 메타데이터 포함
  --json, -j        JSON 출력

Examples:
  imsg history --chat-id 1 --limit 20 --json
  imsg history --chat-id 1 --start 2026-03-01T00:00:00Z --attachments --json
  imsg history --chat-id 1 --limit 50 --participants "+821012345678"
```

### send — 메시지 전송

```bash
imsg send [options]

Options:
  --to <phone/email>      수신자 (전화번호 또는 이메일)
  --chat-id <ID>          대화 ID로 전송
  --chat-identifier <str> 대화 식별자
  --chat-guid <str>       대화 GUID
  --text <message>        메시지 본문
  --file <path>           첨부파일 경로
  --service <type>        imessage | sms | auto (기본: auto)
  --region <code>         전화번호 정규화 지역
  --json, -j              JSON 출력

Examples:
  # 텍스트 전송
  imsg send --to "+821012345678" --text "안녕하세요!"

  # 첨부파일 포함
  imsg send --to "+821012345678" --text "보고서입니다" --file ~/reports/daily.pdf

  # chat-id로 전송
  imsg send --chat-id 42 --text "답장합니다"

  # iMessage 강제
  imsg send --to "+821012345678" --text "iMessage로" --service imessage

  # SMS 강제
  imsg send --to "+821012345678" --text "SMS로" --service sms
```

### watch — 실시간 수신 감시

```bash
imsg watch [options]

Options:
  --chat-id <ID>          특정 대화만 감시
  --participants <handles> 참여자 필터
  --since-rowid <ID>      이 rowid 이후부터
  --debounce <duration>   이벤트 디바운스 (예: 250ms)
  --start <ISO8601>       시작 시간
  --end <ISO8601>         종료 시간
  --attachments           첨부파일 메타데이터 포함
  --json, -j              JSON 출력

Examples:
  imsg watch --json
  imsg watch --chat-id 1 --attachments --debounce 250ms
  imsg watch --participants "+821012345678" --json
```

### rpc — JSON-RPC 모드

```bash
imsg rpc [options]

# stdin/stdout JSON-RPC 프로토콜 (MCP 서버 등 연동용)
```

## 🔔 에이전트 알림 채널 가이드

### 기본 원라이너

```bash
# 성공 알림
imsg send --to "{{NOTIFY_PHONE}}" --text "✅ 작업 완료: 설명"

# 에러 알림
imsg send --to "{{NOTIFY_PHONE}}" --text "🔴 에러: 설명"

# 파일 첨부 알림
imsg send --to "{{NOTIFY_PHONE}}" --text "📊 리포트" --file /path/to/report.pdf
```

### 스크립트 패턴

```bash
# 성공/실패 분기
some_command \
  && imsg send --to "{{NOTIFY_PHONE}}" --text "✅ 완료" \
  || imsg send --to "{{NOTIFY_PHONE}}" --text "🔴 실패"

# 크론 결과 알림
0 9 * * * /path/to/script.sh && imsg send --to "{{NOTIFY_PHONE}}" --text "📋 크론 완료 $(date)"
```

### 코딩 에이전트 연동

```bash
# Claude Code 완료 알림
claude --print "작업 내용" && imsg send --to "{{NOTIFY_PHONE}}" --text "Claude Code 완료"

# Codex 완료 알림
codex "작업 내용" && imsg send --to "{{NOTIFY_PHONE}}" --text "Codex 완료"
```

### 셸 헬퍼 함수

```bash
# ~/.zshrc에 추가
notify() { imsg send --to "{{NOTIFY_PHONE}}" --text "$*"; }
notify-file() { imsg send --to "{{NOTIFY_PHONE}}" --text "$1" --file "$2"; }

# 사용
notify "빌드 완료!"
notify-file "리포트 첨부" ~/report.pdf
```

## Safety Rules

1. **사용자 직접 요청 시**: 수신자 + 메시지 내용 반드시 확인 후 전송
2. **에이전트 알림 시**: 사전 설정된 `{{NOTIFY_PHONE}}`으로만 전송 (다른 번호 금지)
3. **대량 발송 금지**: 반복 전송 시 반드시 사용자 확인
4. **첨부파일**: 파일 존재 확인 후 전송
5. **모르는 번호**: 사용자 명시적 승인 없이 전송 금지

## Troubleshooting

| 문제 | 원인 | 해결 |
|------|------|------|
| `command not found` | 미설치 | `brew install steipete/tap/imsg` |
| `permission denied` | Full Disk Access 없음 | 시스템 설정 → Full Disk Access → 터미널 추가 |
| 전송 실패 | Automation 미허용 | 시스템 설정 → 자동화 → Terminal → Messages 체크 |
| Messages 미실행 | Messages.app 꺼짐 | Messages.app 실행 후 재시도 |
| iMessage 미지원 수신자 | 상대방 iMessage 없음 | `--service sms` 옵션 |
| chat-id 모름 | ID 미확인 | `imsg chats --json`으로 확인 |

## Best Practices

- **알림 번호 고정**: `{{NOTIFY_PHONE}}`을 TOOLS.md에 기록하여 모든 에이전트가 참조
- **이모지 프리픽스**: ✅ 성공, 🔴 에러, 📊 리포트, ⚠️ 경고 — 한눈에 구분
- **짧은 메시지**: iMessage 알림은 1~2줄로 핵심만 (상세는 파일 첨부)
- **JSON 출력 활용**: `--json` 옵션으로 스크립트에서 파싱 가능
- **watch 디바운스**: 실시간 감시 시 `--debounce 250ms`로 중복 이벤트 방지
