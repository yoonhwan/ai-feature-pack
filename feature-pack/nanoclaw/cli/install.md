# NanoClaw CLI 설치

## 요구사항

- Node.js 20+
- npm
- Docker (Colima 또는 Docker Desktop)
- Git

## 설치 명령

```bash
# 클론
git clone https://github.com/qwibitai/nanoclaw.git
cd nanoclaw

# 의존성 + 빌드
npm install
npm run build

# 에이전트 이미지 빌드
cd container && docker build -t nanoclaw-agent:latest . && cd ..

# 첫 실행 + /setup
node dist/index.js
```

## 검증

```bash
# 빌드 확인
ls dist/index.js

# Docker 이미지 확인
docker images | grep nanoclaw-agent

# OneCLI 확인
docker ps | grep onecli
```
