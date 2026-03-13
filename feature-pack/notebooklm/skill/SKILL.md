---
name: notebooklm
description: Google NotebookLM CLI (nlm) 을 사용하여 소스 기반 Q&A, 노트북 관리, 리서치, 오디오/리포트/퀴즈 생성을 수행합니다. 할루시네이션 없는 문서 기반 답변을 제공합니다.
---

# NotebookLM CLI Skill

`nlm` CLI를 통해 Google NotebookLM과 상호작용하는 스킬.

## When to Use This Skill

트리거 조건:
- 사용자가 "NotebookLM", "노트북", "nlm" 언급
- NotebookLM URL 공유 (`https://notebooklm.google.com/...`)
- "내 문서에서 찾아봐", "소스 기반으로 답변해줘"
- 리서치, 팟캐스트, 리포트 생성 요청

## CLI Binary

```
~/.local/bin/nlm
```

설치 방법: `uv tool install notebooklm-mcp-cli`
업데이트: `uv tool upgrade notebooklm-mcp-cli`

## ⚠️ CRITICAL: 인증 (세션 ~20분)

**모든 작업 전 인증 상태 확인:**
```bash
nlm auth status
```

실패 시:
```bash
nlm login
# Chrome 열림 → 사용자에게 "브라우저에서 Google 로그인해주세요" 안내
```

자동 복구 내장 (CSRF/토큰/Headless) → 대부분 자동 처리됨.
"Cookies have expired" 또는 "authentication may have expired" → `nlm login` 재실행.

## Command Style

두 가지 스타일 모두 동일하게 동작:

| Noun-First (리소스 중심) | Verb-First (액션 중심) |
|---|---|
| `nlm notebook list` | `nlm list notebooks` |
| `nlm notebook create "제목"` | `nlm create notebook "제목"` |
| `nlm source add <id> --url <url>` | `nlm add url <id> <url>` |

어느 스타일이든 사용 가능. 이 문서는 Noun-First 기준.

## Core Workflows

### 1. 노트북 관리

```bash
# 목록
nlm notebook list
nlm notebook list --json          # JSON 출력 (파싱용)
nlm notebook list --quiet         # ID만 출력

# 생성
nlm notebook create "프로젝트 이름"

# 상세 / AI 요약
nlm notebook get <id>
nlm notebook describe <id>

# 이름 변경 / 삭제
nlm notebook rename <id> "새 이름"
nlm notebook delete <id> --confirm   # ⚠️ 삭제 전 사용자 확인 필수!
```

### 2. 소스 관리

```bash
# 소스 추가 (3가지 방식)
nlm source add <notebook_id> --url "https://..."            # URL
nlm source add <notebook_id> --file "/path/to/file.md"      # 로컬 파일
nlm source add <notebook_id> --text "내용" --title "제목"    # 텍스트

# 소스 추가 후 처리 대기 (쿼리 전 권장)
nlm source add <notebook_id> --url "..." --wait

# 소스 목록 / 상세
nlm source list <notebook_id>
nlm source describe <notebook_id> <source_id>

# 소스 원문
nlm source content <notebook_id> <source_id>

# Drive 소스 동기화
nlm source stale <notebook_id>    # 업데이트 필요한 소스 확인
nlm sync sources <notebook_id>     # 동기화 실행
```

### 3. Q&A (핵심 기능)

```bash
# 기본 쿼리
nlm query notebook <notebook_id> "질문"

# JSON 출력
nlm query notebook <notebook_id> "질문" --json

# 특정 소스만 대상으로 쿼리
nlm query notebook <notebook_id> "질문" --source-ids <id1,id2>

# 대화 이어가기
nlm query notebook <notebook_id> "후속 질문" --conversation-id <cid>
```

> **중요**: `nlm chat start` (REPL 모드)는 사용하지 마세요. 에이전트가 제어할 수 없습니다.
> 항상 `nlm query notebook`으로 one-shot 쿼리를 사용하세요.

### 4. 콘텐츠 생성

```bash
# 오디오 팟캐스트
nlm audio create <notebook_id> --confirm

# 비디오 오버뷰
nlm video create <notebook_id> --confirm

# 리포트
nlm report create <notebook_id> --confirm

# 퀴즈 / 플래시카드
nlm quiz create <notebook_id> --confirm
nlm flashcards create <notebook_id> --confirm

# 마인드맵 / 슬라이드 / 인포그래픽
nlm mindmap create <notebook_id> --confirm
nlm slides create <notebook_id> --confirm
nlm infographic create <notebook_id> --confirm

# 생성 상태 확인 (오디오/비디오: 1~5분 소요)
nlm studio status <notebook_id>
nlm studio status <notebook_id> --full

# 다운로드
nlm download audio <notebook_id> <artifact_id> -o output.mp3
nlm download video <notebook_id> <artifact_id> -o output.mp4
nlm download report <notebook_id> <artifact_id> -o report.txt
```

### 5. 리서치

```bash
# 딥 리서치 시작
nlm research start <notebook_id> "연구 주제" --mode deep

# 상태 확인 (완료까지 대기)
nlm research status <notebook_id> --max-wait 300

# 결과 소스로 임포트
nlm research import <notebook_id> <task_id>
```

### 6. 별칭 (UUID 단축)

```bash
nlm alias list                      # 전체 별칭
nlm alias set myproject <uuid>      # 별칭 설정 (이후 모든 명령에서 사용 가능)
nlm alias get myproject             # UUID 확인
nlm alias delete myproject          # 별칭 삭제

# 별칭 사용 예:
nlm notebook get myproject
nlm query notebook myproject "질문"
nlm audio create myproject --confirm
```

### 7. 공유 / 내보내기

```bash
# 공유 상태
nlm share status <notebook_id>

# 공개 설정
nlm share public <notebook_id>
nlm share private <notebook_id>

# 초대
nlm share invite <notebook_id> --email user@example.com --role reader

# Google Docs/Sheets로 내보내기
nlm export to-docs <notebook_id> <artifact_id>
nlm export to-sheets <notebook_id> <artifact_id>
```

## Output Formats

| 플래그 | 설명 | 사용처 |
|--------|------|--------|
| (없음) | 사람용 테이블 | 기본값 |
| `--json` | JSON 출력 (파싱용) | 스크립트 |
| `--quiet` | ID만 출력 | 파이프 |
| `--full` | 전체 컬럼 | 상세 확인 |

**자동 감지**: stdout이 TTY가 아니면 (파이프 시) 자동 JSON 출력.

## Decision Flow

```
사용자가 NotebookLM 관련 요청
    ↓
nlm auth status → 실패 시 nlm login (사용자에게 브라우저 로그인 안내)
    ↓
nlm alias list → 별칭 확인 (자주 쓰는 노트북)
    ↓
목적에 따라 분기:
├── Q&A → nlm query notebook <id> "질문"
├── 소스 추가 → nlm source add <id> --url/--file/--text
├── 생성 → nlm audio/report/quiz create <id> --confirm
├── 리서치 → nlm research start <id> "주제" --mode deep
└── 관리 → nlm notebook list/create/delete
    ↓
결과 정리 → 사용자에게 응답
```

## Troubleshooting

| 문제 | 해결 |
|------|------|
| `nlm: command not found` | `export PATH="$HOME/.local/bin:$PATH"` |
| "Cookies have expired" | `nlm login` |
| Rate limit | 자동 재시도 3회 (1s/2s/4s 백오프) |
| 노트북 못 찾음 | `nlm notebook list`로 ID 확인 |
| 리서치 이미 진행 중 | `--force` 사용 또는 기존 결과 import 먼저 |
| 생성 시간 오래 걸림 | 오디오/비디오 1~5분 정상, `nlm studio status`로 확인 |

## Best Practices

1. **인증 먼저** — 모든 작업 전 `nlm auth status`
2. **별칭 활용** — UUID 대신 기억하기 쉬운 이름
3. **--confirm 필수** — 생성/삭제 명령에 항상 추가 (프롬프트 방지)
4. **--wait 활용** — 소스 추가 후 바로 쿼리하려면 `--wait`
5. **REPL 금지** — `nlm chat start` 사용 금지, `nlm query notebook` 사용
6. **삭제 전 확인** — 삭제는 복구 불가, 사용자에게 반드시 확인
7. **별칭 중복 확인** — 새 별칭 설정 전 `nlm alias list`로 기존 확인
