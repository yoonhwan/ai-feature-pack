# TOOLS.md 추가 섹션

아래 내용을 `{{OPENCLAW_WORKSPACE}}/TOOLS.md`에 추가하세요.

---

```markdown
### 📨 iMessage CLI (imsg)

**바이너리**: `/opt/homebrew/bin/imsg`
**버전**: 0.4.0
**출처**: `brew install steipete/tap/imsg`
**권한**: Full Disk Access + Messages Automation

**핵심 명령어:**
\```bash
# 대화 목록
imsg chats --limit 10 --json

# 메시지 히스토리
imsg history --chat-id <ID> --limit 20 --json
imsg history --chat-id <ID> --start 2026-01-01T00:00:00Z --attachments --json

# 메시지 전송
imsg send --to "+821012345678" --text "메시지 내용"
imsg send --to "+821012345678" --text "첨부 포함" --file /path/to/file.jpg
imsg send --to "+821012345678" --text "iMessage로" --service imessage

# 실시간 수신 감시
imsg watch --json
imsg watch --chat-id <ID> --attachments --debounce 250ms

# 🔔 에이전트 알림 (원라이너)
imsg send --to "{{NOTIFY_PHONE}}" --text "알림 내용"
\```

**알림 채널 설정:**
- 기본 알림 수신자: `{{NOTIFY_PHONE}}`
- 다른 에이전트/스크립트/크론에서 `imsg send` 호출로 iMessage 알림 가능
- 셸 헬퍼: `notify() { imsg send --to "{{NOTIFY_PHONE}}" --text "$*"; }`
```
