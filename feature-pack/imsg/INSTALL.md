# Feature Pack: iMessage (imsg)

> 이 문서는 OpenClaw 에이전트가 읽고 자율적으로 설치를 진행하는 프롬프트입니다.
> `{{PLACEHOLDER}}` 항목은 반드시 사용자에게 인터뷰한 뒤 대치하세요.

---

## 개요

**imsg** — macOS Messages.app을 터미널에서 제어하는 CLI.
대화 조회, 메시지 전송, 실시간 수신 감시, 에이전트 알림 채널로 활용.

**설치 후 할 수 있는 것:**
- iMessage/SMS 대화 목록 + 히스토리 조회
- 텍스트 + 첨부파일 메시지 전송
- 실시간 새 메시지 스트림 (watch)
- 🔔 에이전트/크론/CI에서 iMessage 알림 전송

---

## Prerequisites (사전 요구사항)

### 필수
- **macOS** (Apple Silicon 또는 Intel)
- **Messages.app** — iCloud 계정으로 로그인된 상태
- **Homebrew** — `brew --version`으로 확인

### macOS 권한 설정 (중요!)

imsg는 Messages.app의 SQLite DB를 직접 읽고, AppleScript로 메시지를 전송합니다.
**두 가지 권한이 필요합니다:**

1. **Full Disk Access** — 터미널(Terminal.app / iTerm2 등)에 부여
   - 시스템 설정 → 개인정보 보호 및 보안 → Full Disk Access → 터미널 앱 추가
   - `chat.db` 파일 읽기에 필요

2. **Automation 권한** — 메시지 전송 시 자동 팝업
   - 첫 `imsg send` 실행 시 "Terminal이 Messages를 제어하도록 허용" 팝업 → 허용
   - 시스템 설정 → 개인정보 보호 및 보안 → 자동화 → Terminal → Messages 체크

> ⚠️ **사용자에게 안내**: "터미널에 Full Disk Access 권한이 필요합니다. 시스템 설정에서 설정해주세요."

---

## Step 1: CLI 설치

### 1-1. imsg 설치

```bash
brew install steipete/tap/imsg
```

### 1-2. 설치 확인

```bash
imsg --help
# "imsg 0.4.0" + 명령어 목록 출력되면 성공
```

---

## Step 2: 권한 설정 및 인증 테스트

### 2-1. 대화 목록 테스트 (Full Disk Access 검증)

```bash
imsg chats --limit 3 --json
```

- **성공**: JSON 형태 대화 목록 출력
- **실패** (`permission denied` 등): Full Disk Access 미설정 → 사용자에게 안내

### 2-2. 메시지 전송 테스트 (Automation 권한 검증)

```bash
imsg send --to "{{USER_PHONE}}" --text "✅ imsg 설치 테스트 완료!"
```

> **{{USER_PHONE}}** — 사용자 본인 전화번호 (테스트용 자기한테 전송).
> "+82 형식 포함 전체 번호를 알려주세요. (예: +821012345678)"

- **성공**: Messages.app에서 본인에게 메시지 수신 확인
- **팝업 발생**: "Terminal이 Messages를 제어하도록 허용" → 허용 클릭 안내

---

## Step 3: 스킬 설치

### 3-1. 스킬 폴더 복사

```bash
SKILL_DIR="{{OPENCLAW_WORKSPACE}}/skills/imsg"
cp -r skill/ "$SKILL_DIR"
```

> **{{OPENCLAW_WORKSPACE}}** — OpenClaw 워크스페이스 경로 (기본: `~/.openclaw/workspace`)

### 3-2. 스킬 확인

```bash
ls "$SKILL_DIR/SKILL.md"
```

---

## Step 4: OpenClaw 설정

### 4-1. TOOLS.md에 추가

`{{OPENCLAW_WORKSPACE}}/TOOLS.md`에 아래 섹션 추가:

```markdown
### 📨 iMessage CLI (imsg)

**바이너리**: `/opt/homebrew/bin/imsg`
**버전**: 0.4.0
**출처**: `brew install steipete/tap/imsg`

**핵심 명령어:**
\```bash
# 대화 목록
imsg chats --limit 10 --json

# 메시지 히스토리
imsg history --chat-id <ID> --limit 20 --json
imsg history --chat-id <ID> --start 2026-01-01T00:00:00Z --json

# 메시지 전송
imsg send --to "+821012345678" --text "메시지 내용"
imsg send --to "+821012345678" --text "첨부 포함" --file /path/to/file.jpg

# 실시간 수신 감시
imsg watch --chat-id <ID> --json

# 🔔 에이전트 알림 전송 (원라이너)
imsg send --to "{{NOTIFY_PHONE}}" --text "알림 내용"
\```

**알림 채널 설정:**
- 기본 알림 수신자: `{{NOTIFY_PHONE}}`
- 다른 에이전트/스크립트에서 `imsg send` 호출로 iMessage 알림 가능
```

---

## Step 5: 알림 채널 설정 (핵심 기능)

### 5-1. 알림 수신 번호 설정

다른 에이전트, 코딩 도구, 크론에서 iMessage 알림을 받을 전화번호를 설정합니다.

> **{{NOTIFY_PHONE}}** — 알림 수신 전화번호.
> "iMessage 알림을 받을 전화번호를 알려주세요. (예: +821050046707)"

### 5-2. 알림 활용 예시

```bash
# 빌드 완료 알림
imsg send --to "{{NOTIFY_PHONE}}" --text "✅ 빌드 완료: $(date '+%H:%M')"

# 에러 알림
imsg send --to "{{NOTIFY_PHONE}}" --text "🔴 에러 발생: $ERROR_MSG"

# 크론 결과 알림
imsg send --to "{{NOTIFY_PHONE}}" --text "📊 일일 리포트 생성 완료" --file ~/reports/daily.pdf

# CI/CD 파이프라인
imsg send --to "{{NOTIFY_PHONE}}" --text "🟢 PR #$PR_NUM 머지 완료"

# 스크립트 완료 알림 (범용 패턴)
long_running_task && imsg send --to "{{NOTIFY_PHONE}}" --text "✅ 작업 완료" \
                  || imsg send --to "{{NOTIFY_PHONE}}" --text "🔴 작업 실패"
```

### 5-3. Claude Code / Codex 연동

Claude Code나 Codex 세션 완료 시 알림:
```bash
# 작업 완료 후 알림
claude --print "작업 내용" && imsg send --to "{{NOTIFY_PHONE}}" --text "Claude Code 작업 완료"
```

### 5-4. 셸 함수 등록 (선택)

자주 쓴다면 `.zshrc`에 헬퍼 함수 등록:

```bash
# ~/.zshrc에 추가
notify() {
  imsg send --to "{{NOTIFY_PHONE}}" --text "$*"
}

# 사용: notify "빌드 완료!"
```

---

## Step 6: 설치 검증

### 6-1. CLI 동작 확인

```bash
imsg --help
# → 명령어 목록 출력

imsg chats --limit 3 --json
# → JSON 대화 목록 출력
```

### 6-2. 전송 테스트

```bash
imsg send --to "{{USER_PHONE}}" --text "🔔 imsg Feature Pack 설치 완료! $(date '+%Y-%m-%d %H:%M')"
```

### 6-3. 검증 체크리스트

- [ ] `imsg --help` → 정상 출력
- [ ] `imsg chats --limit 3 --json` → 대화 목록 표시
- [ ] `imsg send` → 테스트 메시지 수신 확인
- [ ] 스킬 파일 존재: `ls {{OPENCLAW_WORKSPACE}}/skills/imsg/SKILL.md`
- [ ] TOOLS.md에 iMessage 섹션 추가됨
- [ ] Full Disk Access 권한 설정됨
- [ ] Automation 권한 허용됨

---

## Troubleshooting

| 문제 | 원인 | 해결 |
|------|------|------|
| `imsg: command not found` | brew 설치 안됨 | `brew install steipete/tap/imsg` |
| `permission denied` (chats) | Full Disk Access 없음 | 시스템 설정 → 개인정보 보호 → Full Disk Access → 터미널 추가 |
| 전송 실패 | Automation 미허용 | 시스템 설정 → 자동화 → Terminal → Messages 체크 |
| "Messages is not running" | Messages.app 미실행 | Messages.app 실행 후 재시도 |
| 수신자 iMessage 미지원 | SMS fallback 필요 | `--service sms` 옵션 추가 |
| chat-id 모름 | 대화 ID 미확인 | `imsg chats --json`으로 ID 확인 |

---

## Placeholder 정리

| Placeholder | 설명 | 기본값 |
|-------------|------|--------|
| `{{OPENCLAW_WORKSPACE}}` | OpenClaw 워크스페이스 경로 | `~/.openclaw/workspace` |
| `{{USER_PHONE}}` | 사용자 본인 전화번호 (테스트용) | — |
| `{{NOTIFY_PHONE}}` | 알림 수신 전화번호 | — |

---

## 설치 완료 후

1. `imsg chats --json`으로 대화 목록 확인
2. `imsg send --to "번호" --text "내용"`으로 메시지 전송
3. 스크립트/크론에서 `imsg send`로 알림 채널 활용
4. `notify "메시지"` 셸 함수로 빠른 알림 (선택 설정 시)
