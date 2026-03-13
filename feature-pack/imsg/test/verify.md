# 설치 검증

## 1. CLI 동작 확인

```bash
# 버전/도움말
imsg --help
# → "imsg 0.4.0" + 명령어 목록 출력 ✅

# 대화 목록 (Full Disk Access 검증)
imsg chats --limit 3 --json
# → JSON 대화 목록 출력 ✅
```

## 2. 메시지 전송 테스트

```bash
# 본인에게 테스트 전송 (Automation 권한 검증)
imsg send --to "{{USER_PHONE}}" --text "🔔 imsg 설치 테스트 완료! $(date '+%Y-%m-%d %H:%M')"
# → Messages.app에서 수신 확인 ✅
```

## 3. 히스토리 조회 테스트

```bash
# chat-id 확인
CHAT_ID=$(imsg chats --limit 1 --json | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['chat_id'])" 2>/dev/null)
echo "첫 번째 대화 ID: $CHAT_ID"

# 히스토리 조회
imsg history --chat-id "$CHAT_ID" --limit 5 --json
# → 메시지 히스토리 출력 ✅
```

## 4. 검증 체크리스트

- [ ] `imsg --help` → 정상 출력
- [ ] `imsg chats --limit 3 --json` → 대화 목록 표시
- [ ] `imsg send` → 테스트 메시지 수신 확인
- [ ] `imsg history` → 히스토리 조회 성공
- [ ] 스킬 파일 존재: `ls {{OPENCLAW_WORKSPACE}}/skills/imsg/SKILL.md`
- [ ] TOOLS.md에 iMessage 섹션 추가됨
- [ ] Full Disk Access 권한 설정됨
- [ ] Automation 권한 허용됨

## 5. 실패 시 대응

| 단계 | 실패 증상 | 대응 |
|------|----------|------|
| CLI | `command not found` | `brew install steipete/tap/imsg` |
| chats | `permission denied` | 시스템 설정 → Full Disk Access → 터미널 추가 |
| send | Automation 팝업 | "허용" 클릭 |
| send | "Messages is not running" | Messages.app 실행 |
| send | 전송 실패 | `--service sms` 시도 |
