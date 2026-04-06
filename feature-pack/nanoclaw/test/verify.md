# NanoClaw 설치 검증

## 자동 검증 스크립트

```bash
#!/bin/bash
echo "=== NanoClaw 설치 검증 ==="

# 1. 빌드 확인
echo -n "1. dist/index.js: "
[ -f dist/index.js ] && echo "OK" || echo "FAIL"

# 2. Docker 이미지
echo -n "2. nanoclaw-agent image: "
docker images -q nanoclaw-agent:latest | grep -q . && echo "OK" || echo "FAIL"

# 3. OneCLI
echo -n "3. OneCLI gateway: "
docker ps --format '{{.Names}}' | grep -q onecli && echo "OK" || echo "FAIL (run /setup first)"

# 4. .env
echo -n "4. .env file: "
[ -f .env ] && echo "OK" || echo "FAIL"

# 5. Slack 토큰
echo -n "5. SLACK_BOT_TOKEN: "
grep -q "SLACK_BOT_TOKEN=xoxb-" .env 2>/dev/null && echo "OK" || echo "FAIL (set in .env)"

# 6. groups/
echo -n "6. groups/ directory: "
[ -d groups ] && echo "OK ($(ls -d groups/*/ 2>/dev/null | wc -l | tr -d ' ') groups)" || echo "FAIL"

# 7. SQLite
echo -n "7. messages.db: "
[ -f store/messages.db ] && echo "OK" || echo "PENDING (created on first message)"

echo "=== 검증 완료 ==="
```

## 수동 검증

1. `node dist/index.js` → 에러 없이 시작
2. Slack에서 메시지 전송 → 응답 수신
3. `docker ps` → nanoclaw-agent 컨테이너 스폰 확인
4. 두 번째 메시지 전송 → 이전 대화 기억 확인 (세션 영속)
