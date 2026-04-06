# TOOLS.md 추가 섹션 — NanoClaw

## NanoClaw (AI 멀티 에이전트)

NanoClaw는 Docker 컨테이너 기반 AI 에이전트 플랫폼입니다.

### 실행
```bash
# 시작
node dist/index.js

# launchd 서비스로 실행 중이면
launchctl list | grep nanoclaw
```

### 주요 명령 (Slack 또는 대화에서)
- `/setup` — 초기 설정 (OneCLI + 에이전트 등록)
- `/add-slack` — Slack 채널 추가
- `/status` — 에이전트 상태 확인
- `/customize` — 그룹 설정 커스터마이징

### 그룹 관리
```bash
# 그룹 목록
ls groups/

# 새 그룹 생성
mkdir -p groups/{name}/memory
cp groups/global/CLAUDE.md groups/{name}/CLAUDE.md
```

### 트러블슈팅
```bash
# 로그 확인
tail -f logs/stderr.log

# 컨테이너 상태
docker ps | grep nanoclaw

# OneCLI 상태
docker ps | grep onecli

# 서비스 재시작
launchctl kickstart -k gui/$(id -u)/com.nanoclaw-main
```
