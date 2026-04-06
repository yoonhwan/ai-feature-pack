# Feature Pack: NanoClaw

> 에이전트 자율 설치 프롬프트 — 이 문서를 AI 에이전트에게 전달하면 자동 설치됩니다.
> **OpenClaw를 대체**하는 AI 멀티 에이전트 플랫폼입니다.

## 개요

NanoClaw는 Claude Agent SDK 기반 AI 에이전트 플랫폼입니다. Docker 컨테이너 안에서 에이전트가 실행되며, Slack으로 통신하고, 독립 SQLite로 대화 이력을 영속합니다.

**OpenClaw → NanoClaw 전환 이유:**
- Claude Agent SDK 내장 ($0 Brain, 구독 포함)
- Docker 컨테이너 격리 (크래시 안전)
- 멀티 인스턴스 지원 (1 NanoClaw = 1 크루원)
- groups/ + skills/ 기반 Configure-Don't-Code 확장

**할 수 있는 것:**
- Slack 채널에서 대화형 AI 에이전트 운영
- Docker 컨테이너 안에서 코딩 에이전트 실행 (Bash, Read, Write, Edit 등)
- 멀티 그룹 운영 (groups/ 디렉토리로 페르소나 분리)
- 세션 영속성 (SQLite + memory/ 파일)
- 스킬 시스템 (~31개 내장 + 커스텀 추가)

## Prerequisites

- macOS (Apple Silicon 권장, M1+)
- Node.js 20+ (`node --version`)
- npm (`npm --version`)
- Docker Desktop 또는 Colima (`docker --version`)
- Git (`git --version`)
- Claude Pro/Max 구독 (API 비용 $0)

### Docker 환경 (Colima 권장)

```bash
# Colima 미설치 시
brew install colima docker

# Colima 시작 (CPU 4, RAM 8GB, Disk 100GB)
colima start --cpu 4 --memory 8 --disk 100

# Docker 확인
docker info
```

## Step 1: NanoClaw 클론 + 빌드

```bash
# 1-1. 클론 (upstream: qwibitai/nanoclaw)
cd {{WORKSPACE_PATH}}
git clone https://github.com/qwibitai/nanoclaw.git
cd nanoclaw

# 1-2. 의존성 설치
npm install

# 1-3. 빌드
npm run build

# 1-4. 확인
ls dist/index.js  # 존재해야 함
```

| Placeholder | 설명 | 기본값 |
|-------------|------|--------|
| `{{WORKSPACE_PATH}}` | NanoClaw 설치 경로 | `~/Project/xclaw` 또는 원하는 프로젝트 |

## Step 2: OneCLI 설정 (Claude API 프록시)

NanoClaw는 OneCLI를 통해 Claude API 키를 컨테이너에 자동 주입합니다.

```bash
# 2-1. OneCLI 에이전트 볼트 초기화
# NanoClaw 디렉토리에서 실행
node dist/index.js

# 2-2. 첫 실행 시 /setup 명령으로 초기 설정
# 대화창에서: /setup
# → OneCLI 설치 + 에이전트 등록 자동 진행

# 2-3. OneCLI 확인
docker ps | grep onecli  # onecli-gateway + onecli-postgres 컨테이너
```

> **참고**: OneCLI는 localhost:10254에서 API 프록시를 운영합니다. 컨테이너가 이 프록시를 통해 Claude API에 접근합니다.

## Step 3: Slack 앱 연동

```bash
# 3-1. Slack 앱 생성
# https://api.slack.com/apps → Create New App → From Manifest

# 3-2. 필요한 Bot Token Scopes:
#   - channels:history, channels:read, channels:join
#   - chat:write, chat:write.customize
#   - groups:history, groups:read
#   - im:history, im:read, im:write
#   - users:read

# 3-3. Event Subscriptions 활성화:
#   - message.channels, message.groups, message.im
#   - Socket Mode 활성화 → App-Level Token 생성

# 3-4. .env 파일 설정
cat > .env << 'EOF'
SLACK_BOT_TOKEN=xoxb-your-bot-token
SLACK_APP_TOKEN=xapp-your-app-token
ASSISTANT_NAME={{AGENT_NAME}}
EOF
```

| Placeholder | 설명 | 기본값 |
|-------------|------|--------|
| `{{AGENT_NAME}}` | Slack에서 표시되는 에이전트 이름 | `NanoClaw` |

## Step 4: 그룹 설정 (페르소나)

```bash
# 4-1. 기본 그룹 확인
ls groups/
# → global/ (기본 템플릿), 기타 기존 그룹

# 4-2. 새 그룹 생성 (예: main 오케스트레이터)
mkdir -p groups/main
cp groups/global/CLAUDE.md groups/main/CLAUDE.md

# 4-3. CLAUDE.md 편집 — 에이전트 페르소나 정의
# groups/main/CLAUDE.md에 역할·스킬·규칙 작성

# 4-4. memory 디렉토리 생성
mkdir -p groups/main/memory
touch groups/main/memory/{directives,mistakes,achievements}.md
```

## Step 5: 컨테이너 에이전트 이미지 빌드

```bash
# 5-1. 에이전트 Docker 이미지 빌드
cd container
docker build -t nanoclaw-agent:latest .

# 5-2. 이미지 확인
docker images | grep nanoclaw-agent
```

## Step 6: 실행 + 검증

```bash
# 6-1. NanoClaw 시작
cd {{WORKSPACE_PATH}}/nanoclaw
node dist/index.js

# 6-2. Slack에서 에이전트에게 메시지 전송
# → 응답 확인

# 6-3. 컨테이너 동작 확인
docker ps  # nanoclaw-agent 컨테이너가 메시지 처리 시 스폰
```

## Step 7: OpenClaw → NanoClaw 마이그레이션 (선택)

기존 OpenClaw 사용자가 NanoClaw로 전환할 때:

```bash
# 7-1. OpenClaw 스킬 이전
# OpenClaw 스킬 → NanoClaw groups/{name}/skills/ 로 복사
cp -r ~/.openclaw/workspace/skills/my-skill groups/main/skills/

# 7-2. OpenClaw cron → NanoClaw scheduled task
# openclaw.json의 cron 설정 → NanoClaw task-scheduler 형식으로 변환

# 7-3. OpenClaw 중지 (선택)
# NanoClaw가 안정적으로 동작 확인 후
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/ai.openclaw.gateway.plist
```

> **공존 가능**: OpenClaw과 NanoClaw는 동시 운영 가능합니다. 같은 Slack 워크스페이스에서 다른 봇 토큰을 사용하면 됩니다.

## Step 8: launchd 자동 시작 (선택)

```bash
# 8-1. plist 생성
cat > ~/Library/LaunchAgents/com.nanoclaw-main.plist << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.nanoclaw-main</string>
  <key>WorkingDirectory</key>
  <string>{{WORKSPACE_PATH}}/nanoclaw</string>
  <key>ProgramArguments</key>
  <array>
    <string>/opt/homebrew/bin/node</string>
    <string>dist/index.js</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
  </dict>
  <key>KeepAlive</key>
  <true/>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>{{WORKSPACE_PATH}}/nanoclaw/logs/stdout.log</string>
  <key>StandardErrorPath</key>
  <string>{{WORKSPACE_PATH}}/nanoclaw/logs/stderr.log</string>
</dict>
</plist>
PLIST

# 8-2. 서비스 등록 + 시작
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.nanoclaw-main.plist

# 8-3. 확인
launchctl list | grep nanoclaw
```

## Placeholder 요약

| Placeholder | 설명 | 질문 |
|-------------|------|------|
| `{{WORKSPACE_PATH}}` | NanoClaw 설치 경로 | "NanoClaw를 어디에 설치할까요?" |
| `{{AGENT_NAME}}` | Slack 에이전트 이름 | "에이전트 이름을 뭘로 할까요?" |

## 검증 체크리스트

- [ ] `node dist/index.js` 실행 시 에러 없음
- [ ] `docker ps | grep onecli` → onecli-gateway 실행 중
- [ ] Slack에서 에이전트에게 메시지 → 응답 수신
- [ ] `docker ps` → 메시지 처리 시 nanoclaw-agent 컨테이너 스폰
- [ ] `groups/main/CLAUDE.md` 존재 + 페르소나 정의됨
- [ ] `ls store/messages.db` → SQLite 대화 이력 영속

## 트러블슈팅

| 문제 | 해결 |
|------|------|
| `docker: command not found` | `brew install docker` + `colima start` |
| OneCLI 컨테이너 미기동 | `/setup` 재실행 또는 `docker restart onecli-gateway` |
| Slack 메시지 미수신 | `.env`의 SLACK_BOT_TOKEN/APP_TOKEN 확인 + Socket Mode 활성화 확인 |
| 컨테이너 스폰 실패 | `docker images | grep nanoclaw-agent` 확인 → 없으면 Step 5 재실행 |
| launchd 서비스 사망 | `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.nanoclaw-main.plist` |
| Rate limit | Claude Pro → Max 업그레이드 또는 MAX_CONCURRENT_CONTAINERS 줄이기 |
