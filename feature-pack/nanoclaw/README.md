# NanoClaw — AI 멀티 에이전트 플랫폼

> OpenClaw 대체. Claude Agent SDK 기반. Docker 컨테이너 격리.

## 뭐가 다른가?

| 항목 | OpenClaw | NanoClaw |
|------|----------|----------|
| Brain | 내장 LLM 라우팅 | Claude Agent SDK ($0, 구독 포함) |
| 실행 환경 | 호스트 프로세스 | Docker 컨테이너 (격리) |
| 확장 | 스킬 + 플러그인 | groups/ + skills/ (Configure-Don't-Code) |
| 멀티 에이전트 | 단일 인스턴스 | 1 NanoClaw = 1 크루원 (멀티 인스턴스) |
| 영속성 | 내부 DB | SQLite + memory/ 파일 + Redis 미러 |
| 통신 | HTTP API + Slack | Slack 네이티브 + Redis Stream |

## 설치

에이전트에게: `INSTALL.md 읽고 설치해줘`

수동: [INSTALL.md](INSTALL.md) 참조 (~15분)

## 구조

```
nanoclaw/
├── dist/              # 빌드된 TypeScript → JS
├── groups/            # 에이전트 페르소나 (CLAUDE.md + memory/)
├── container/         # Docker 이미지 소스
├── store/             # SQLite (messages.db)
├── data/              # IPC, sessions, certs
├── logs/              # stdout/stderr
└── .env               # Slack 토큰 + 설정
```

## 핵심 개념

- **Group**: 에이전트의 페르소나 단위. `groups/{name}/CLAUDE.md`로 정의
- **Container**: 매 태스크마다 Docker 컨테이너 스폰 → 작업 → 종료
- **Skill**: `.claude/skills/` 에 SKILL.md 파일로 정의
- **Memory**: `groups/{name}/memory/`에 실수·성과·지침 영속
- **OneCLI**: Claude API 키 프록시 (컨테이너에 자동 주입)
