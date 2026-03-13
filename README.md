# 🏞️ AI Feature Pack

**신규 OpenClaw 에이전트를 위한 피처별 자동 설치 패키지**

## 사용법

1. 원하는 feature-pack 폴더를 다운로드 (또는 repo 전체 clone)
2. OpenClaw 에이전트에게 `INSTALL.md`를 전달
3. 에이전트가 자율적으로 설치 완료

```bash
# 예시: notebooklm 설치
git clone https://github.com/yoonhwan/ai-feature-pack.git
# OpenClaw 에이전트에게:
# "feature-pack/notebooklm/INSTALL.md 읽고 설치해줘"
```

## 피처 목록

| Feature Pack | 설명 | CLI | OS |
|-------------|------|-----|----|
| [notebooklm](feature-pack/notebooklm/) | Google NotebookLM CLI + 스킬 | `nlm` | macOS |

## 구조

각 Feature Pack은 동일한 구조:

```
feature-pack/{name}/
├── INSTALL.md       ← 에이전트용 설치 프롬프트 (핵심!)
├── README.md        ← 사람용 개요
├── manifest.json    ← 메타데이터
├── skill/           ← OpenClaw 스킬 폴더
├── cli/             ← CLI 설치 가이드
├── config/          ← AGENTS.md / TOOLS.md 설정 조각
├── obsidian/        ← Obsidian 연동 (해당 시)
└── test/            ← 설치 검증
```

## 라이선스

MIT
