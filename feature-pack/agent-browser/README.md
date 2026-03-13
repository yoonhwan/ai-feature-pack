# Agent Browser Feature Pack

AI 에이전트용 브라우저 자동화 CLI — 웹 스크래핑, 스크린샷, 폼 입력, 비디오 녹화, 디버그, 스타일드 카드 생성.

## What You Get

- **agent-browser CLI** (v0.16.3+) — Playwright + Rust CDP 기반 headless/headed 브라우저 자동화
- **OpenClaw Skill** — 에이전트가 브라우저 작업을 자동 트리거
- **TOOLS.md section** — 환경별 설정, 속도 비교, 팁

## Key Features

| Feature | Description |
|---------|-------------|
| Web scraping | 동적 SPA/React 페이지 포함 콘텐츠 추출 |
| Screenshots | 전체/부분 스크린샷 + 2× 레티나 카드 생성 |
| Form automation | 로그인, 회원가입, 폼 자동 입력 |
| Video recording | WebM 녹화 → GIF 변환 |
| Debug | 콘솔 로그, 에러, 네트워크 모킹 |
| Cookie persistence | 로그인 세션 저장/복원 |
| Native CDP | Rust daemon 직접 Chrome 연결 (확장 프로그램 지원) |

## Requirements

- macOS (arm64/x86_64)
- Node.js 18+
- Python 3 + Pillow (스크린샷 카드용)

## Install

INSTALL.md를 에이전트에게 전달하면 자율 설치됩니다.
