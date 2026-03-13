# CLI Installation Guide

## imsg (iMessage/SMS CLI)

**패키지**: `steipete/tap/imsg`
**설치**: `brew install steipete/tap/imsg`
**바이너리**: `/opt/homebrew/bin/imsg`
**버전 확인**: `imsg --help` (첫 줄에 버전 표시)

### Prerequisites
- macOS + Messages.app (iCloud 로그인)
- Homebrew

### 권한 설정 (필수)

| 권한 | 용도 | 설정 경로 |
|------|------|----------|
| Full Disk Access | `chat.db` 읽기 | 시스템 설정 → 개인정보 보호 → Full Disk Access → 터미널 |
| Automation | 메시지 전송 | 첫 send 시 자동 팝업 → 허용 |

### 주요 명령어

```bash
# 대화 목록
imsg chats --limit 10 --json

# 히스토리
imsg history --chat-id <ID> --limit 20 --json

# 전송
imsg send --to "+821012345678" --text "메시지"
imsg send --to "+821012345678" --text "첨부" --file ~/pic.jpg

# 실시간 감시
imsg watch --json
imsg watch --chat-id <ID> --attachments --debounce 250ms
```

### 검증

```bash
imsg --help && echo "✅ imsg OK"
imsg chats --limit 1 --json && echo "✅ Full Disk Access OK"
```
