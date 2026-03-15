---
name: memory-system
description: OpenClaw 에이전트 메모리 시스템 관리 — 장기기억, 데일리 노트, Obsidian 볼트 연동, NotebookLM CLI 조합
---

# Memory System 스킬

에이전트의 3층 기억 시스템을 운영합니다.

## 구조

```
[Layer 1] OC 워크스페이스 메모리
  ├── MEMORY.md     — 장기기억 (큐레이션)
  └── memory/*.md   — 데일리 노트 (원본 로그)

[Layer 2] Obsidian 볼트 (세컨드브레인)
  ├── Daily/memory/ — 데일리 미러
  ├── News-Links/   — 링크 → 노트
  ├── Meetings/     — 대화 기록
  └── People/       — 인물 프로필

[Layer 3] NotebookLM (선택)
  └── nlm CLI       — 소스 기반 Q&A
```

## 매 세션 시작

1. `exec("ls memory/")` → 파일 목록 확인
2. `read("memory/YYYY-MM-DD.md")` — 오늘 + 어제
3. 메인 세션이면 `MEMORY.md`도 읽기

## 기록 규칙

### 데일리 노트 (memory/YYYY-MM-DD.md)
- 시간순 활동 로그
- 결정, 이슈, 교훈 기록
- 없으면 새로 생성

### 장기기억 (MEMORY.md)
- 데일리에서 중요한 내용 큐레이션
- 프로젝트 마일스톤, 핵심 결정, 반복 교훈
- 세션 간 유지할 핵심 컨텍스트

### Obsidian 볼트 연동
- 링크 공유 → News-Links/ 노트 생성
- 대화 기록 → Meetings/ + People/ 양방향 링크
- 직접 편집: `obsidian-cli` 또는 `read`/`write`/`edit`

### NotebookLM 활용 (nlm CLI)
- 문서 묶어서 노트북 생성: `nlm notebook create "이름"`
- 소스 추가: `nlm source add <id> --file <path>`
- 소스 기반 Q&A: `nlm chat query <id> "질문"`

## ⚠️ 금지 사항

- `read("memory")` 절대 금지 → EISDIR 에러
- 데일리 노트에 개인정보/API키 기록 금지
- MEMORY.md를 그룹 채팅에서 로드 금지 (프라이버시)
