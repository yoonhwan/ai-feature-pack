# Feature Pack: Memory System

> 이 문서는 OpenClaw 에이전트가 읽고 자율적으로 설치를 진행하는 프롬프트입니다.
> `{{PLACEHOLDER}}`를 발견하면 **반드시 사용자에게 인터뷰**하고, 답변으로 대치한 뒤 진행하세요.

---

## 개요

OpenClaw 에이전트의 **3층 기억 시스템**을 구축합니다:

1. **OC 워크스페이스 메모리** — 에이전트 장기기억 + 데일리 노트
2. **Obsidian 볼트 (세컨드브레인)** — 구조화된 지식 저장소
3. **메모리 검색 통합** — 볼트 전체를 에이전트 메모리 검색 범위에 포함
4. **NotebookLM CLI** — 문서 기반 Q&A (선택)

**설치 후 할 수 있는 것:**
- 에이전트가 대화/결정/교훈을 장기기억으로 축적
- 데일리 노트로 일별 활동 자동 기록
- Obsidian 볼트의 모든 노트를 에이전트 메모리로 검색
- 뉴스 링크 → 노트 변환, 대화 기록 → 인물 프로필 축적
- NotebookLM으로 문서 묶어서 소스 기반 Q&A

---

## Prerequisites (사전 요구사항)

### 필수
- **macOS** (Apple Silicon 또는 Intel)
- **OpenClaw** 설치 + 실행 중
- **Obsidian** 앱 설치 (https://obsidian.md)
- **OpenAI API Key** — 임베딩(text-embedding-3-small)용

### 선택
- **nlm CLI** — NotebookLM 연동 (별도 `notebooklm` 피처팩 참조)
- **Google 계정** — NotebookLM 사용 시

---

## Step 1: OC 워크스페이스 메모리 구조

### 1-1. 워크스페이스 경로 확인

```bash
# OpenClaw 워크스페이스 위치 확인
# 기본값: ~/.openclaw/workspace
ls ~/.openclaw/workspace/
```

### 1-2. 메모리 파일 생성

워크스페이스에 아래 파일들을 생성합니다.

#### MEMORY.md (장기기억)

```bash
cat > {{OC_WORKSPACE}}/MEMORY.md << 'EOF'
# MEMORY.md - 장기 기억

_에이전트의 핵심 기억. 세션을 넘어 유지되는 중요한 정보._

---

## 시작

- 첫 부트스트랩 완료 (날짜 기록)
- 역할과 목적 정리

---

_주기적으로 daily notes에서 중요한 내용을 여기로 정리한다._
EOF
```

> `{{OC_WORKSPACE}}` — OpenClaw 워크스페이스 경로 (기본: `~/.openclaw/workspace`)

#### memory/ 폴더 (데일리 노트)

```bash
mkdir -p {{OC_WORKSPACE}}/memory
```

데일리 노트는 에이전트가 자동 생성합니다:
- 파일명: `memory/YYYY-MM-DD.md`
- 내용: 그날의 활동, 결정, 교훈을 시간순 기록
- 중요한 내용은 주기적으로 MEMORY.md로 큐레이션

### 1-3. AGENTS.md에 메모리 규칙 추가

AGENTS.md에 아래 섹션을 추가하세요:

```markdown
## Memory

You wake up fresh each session. These files are your continuity:

- **Daily notes:** `memory/YYYY-MM-DD.md` (create `memory/` if needed) — raw logs of what happened
- **Long-term:** `MEMORY.md` — your curated memories, like a human's long-term memory

Capture what matters. Decisions, context, things to remember.

### 매 세션 시작 시
1. `memory/YYYY-MM-DD.md` (오늘 + 어제) 읽기
2. 메인 세션이면 `MEMORY.md`도 읽기

### 메모리 파일 읽기 규칙 (EISDIR 방지)
- ❌ `read("memory")` → EISDIR 에러!
- ✅ `exec("ls memory/")` → 파일 목록 확인
- ✅ `read("memory/2026-02-05.md")` → 개별 파일 읽기

### 기록 원칙
- "Mental notes" 금지 — 파일에 써야 기억이 남는다
- "remember this" 요청 → memory/ 또는 MEMORY.md 업데이트
- 교훈 → AGENTS.md 또는 관련 파일에 기록
```

---

## Step 2: Obsidian 볼트 구조

### 2-1. 볼트 생성

Obsidian 앱에서 새 볼트를 생성하거나 기존 볼트를 사용합니다.

```bash
# 볼트 경로 확인 (사용자에게 질문)
# {{VAULT_PATH}} — Obsidian 볼트 전체 경로
# 예: ~/Library/Mobile Documents/iCloud~md~obsidian/Documents/my-vault
# 예: ~/Documents/my-vault
```

> `{{VAULT_PATH}}` — Obsidian 볼트의 절대 경로
> `{{VAULT_NAME}}` — Obsidian 볼트 이름 (폴더명)

### 2-2. 폴더 구조 생성

```bash
VAULT="{{VAULT_PATH}}"

# 핵심 폴더 생성
mkdir -p "$VAULT/Daily/memory"     # 데일리 노트 + OC 메모리 미러
mkdir -p "$VAULT/News-Links"       # 뉴스/링크 → 노트 변환
mkdir -p "$VAULT/Meetings"         # 대화/통화 기록
mkdir -p "$VAULT/People"           # 인물 프로필 (진화형)
mkdir -p "$VAULT/Projects"         # 프로젝트별 노트 (빈 폴더)
mkdir -p "$VAULT/Reference"        # 참조 문서
mkdir -p "$VAULT/Ideas"            # 아이디어
mkdir -p "$VAULT/Trading"          # 투자/트레이딩 (선택)
mkdir -p "$VAULT/Archive"          # 아카이브
mkdir -p "$VAULT/Tools"            # 도구/CLI 가이드
```

### 2-3. 볼트 홈 노트

```bash
cat > "$VAULT/HOME.md" << 'EOF'
# 🏠 Home

내 세컨드브레인의 시작점.

## 📂 구조

| 폴더 | 용도 |
|------|------|
| [[Daily/]] | 데일리 노트 + 에이전트 메모리 |
| [[News-Links/]] | 뉴스/링크 자동 변환 노트 |
| [[Meetings/]] | 대화/통화 기록 |
| [[People/]] | 인물 프로필 |
| [[Projects/]] | 프로젝트별 노트 |
| [[Reference/]] | 참조 문서 |
| [[Ideas/]] | 아이디어 |
| [[Archive/]] | 아카이브 |

## 최근 활동
- ...
EOF
```

### 2-4. 인덱스 파일 생성

```bash
# Meetings 인덱스
cat > "$VAULT/Meetings/_INDEX.md" << 'EOF'
# Meetings Index

대화/통화 기록 목록. 새 기록 추가 시 여기에도 링크 추가.

## 최근 기록
- (자동으로 채워집니다)
EOF

# People 인덱스
cat > "$VAULT/People/_INDEX.md" << 'EOF'
# People Index

인물 프로필 목록. 대화마다 인사이트가 누적됩니다.

## 등록된 인물
- (자동으로 채워집니다)
EOF
```

### 2-5. obsidian-cli 설치 + 기본 볼트 설정

```bash
# obsidian-cli 설치
brew install yakitrak/yakitrak/obsidian-cli

# 기본 볼트 설정
obsidian-cli set-default "{{VAULT_NAME}}"

# 확인
obsidian-cli print-default
```

---

## Step 3: 메모리 검색 통합 (핵심!)

Obsidian 볼트 전체를 에이전트 메모리 검색 범위에 포함시킵니다.

### 3-1. OpenClaw 설정

`openclaw.json`에 아래 설정을 추가합니다:

```json
{
  "agents": {
    "defaults": {
      "memorySearch": {
        "enabled": true,
        "sources": ["memory", "sessions"],
        "extraPaths": [
          "{{VAULT_PATH}}"
        ],
        "provider": "openai",
        "model": "text-embedding-3-small",
        "sync": {
          "watch": true,
          "watchDebounceMs": 1500
        },
        "query": {
          "hybrid": {
            "enabled": true,
            "vectorWeight": 0.7,
            "textWeight": 0.3,
            "candidateMultiplier": 4
          }
        }
      }
    }
  }
}
```

> **OpenAI API Key** 필요: `text-embedding-3-small` 임베딩 모델 사용
> OpenClaw 환경변수 또는 설정에 `OPENAI_API_KEY` 등록 필요

### 3-2. 설정 적용

```bash
# OpenClaw 재시작으로 설정 반영
openclaw gateway restart
```

### 3-3. 동작 확인

설정 적용 후:
- `watch: true` → 볼트 파일 변경 시 자동 인덱싱
- `memory_search` 도구로 볼트 내 노트 검색 가능
- 에이전트가 대화 중 관련 볼트 문서를 자동 참조

---

## Step 4: TOOLS.md에 Obsidian 설정 추가

```markdown
### Obsidian

- Default vault: `{{VAULT_NAME}}`
- Path: `{{VAULT_PATH}}`
```

별도의 config 파일 `config/tools-section.md` 참조.

---

## Step 5: 데일리 메모리 미러 (OC ↔ 볼트)

에이전트의 `memory/YYYY-MM-DD.md` 데일리 노트를 볼트 `Daily/memory/`에도 미러합니다.

### 방법 A: 심볼릭 링크 (추천)

```bash
# OC 메모리 → 볼트 Daily/memory/ 심볼릭 링크
ln -s {{OC_WORKSPACE}}/memory/* {{VAULT_PATH}}/Daily/memory/

# 또는 폴더 자체를 링크
rm -rf {{VAULT_PATH}}/Daily/memory
ln -s {{OC_WORKSPACE}}/memory {{VAULT_PATH}}/Daily/memory
```

### 방법 B: 크론으로 복사

```bash
# 매시간 동기화 (rsync)
# openclaw cron으로 등록하거나 시스템 crontab 사용
rsync -a {{OC_WORKSPACE}}/memory/ {{VAULT_PATH}}/Daily/memory/
```

### MEMORY.md 미러

```bash
ln -s {{OC_WORKSPACE}}/MEMORY.md {{VAULT_PATH}}/Daily/MEMORY.md
```

---

## Step 6: NotebookLM CLI 연동 (선택)

> 이 단계는 `notebooklm` 피처팩이 필요합니다. 미설치 시 건너뛰세요.

### 6-1. nlm CLI 확인

```bash
nlm --version
# 출력: nlm version 0.x.x
```

### 6-2. 볼트 문서를 NotebookLM 소스로 추가

```bash
NLM={{NLM_PATH:-$(which nlm)}}

# 프로젝트용 노트북 생성
$NLM notebook create "{{VAULT_NAME}} Knowledge Base"

# 볼트 문서를 소스로 추가 (예시)
NOTEBOOK_ID="<위 명령 출력의 notebook_id>"
$NLM source add $NOTEBOOK_ID --file "{{VAULT_PATH}}/HOME.md"
$NLM source add $NOTEBOOK_ID --file "{{VAULT_PATH}}/Reference/중요문서.md"

# 소스 기반 Q&A
$NLM chat query $NOTEBOOK_ID "이 프로젝트에서 가장 중요한 결정은?"
```

### 6-3. TOOLS.md에 추가

```markdown
### NotebookLM CLI (nlm)

- 바이너리: $(which nlm)
- 설치: `uv tool install notebooklm-mcp-cli`
- 인증: Google 계정 연동 완료

핵심 명령어:
- `nlm notebook list` — 노트북 목록
- `nlm chat query <id> "질문"` — 소스 기반 Q&A
- `nlm source add <id> --file <path>` — 소스 추가
```

---

## Step 7: 설치 검증

### 7-1. 워크스페이스 메모리 확인

```bash
# MEMORY.md 존재
ls {{OC_WORKSPACE}}/MEMORY.md

# memory/ 폴더 존재
ls {{OC_WORKSPACE}}/memory/

# 에이전트에게 "오늘 뭐 했어?" → 데일리 노트 생성 확인
```

### 7-2. Obsidian 볼트 확인

```bash
# 폴더 구조 확인
ls {{VAULT_PATH}}/
# 기대: Daily/ News-Links/ Meetings/ People/ Projects/ Reference/ Ideas/ Archive/ HOME.md

# obsidian-cli 동작
obsidian-cli list
obsidian-cli search "HOME"
```

### 7-3. 메모리 검색 통합 확인

```bash
# OpenClaw 재시작 후
openclaw gateway restart

# 에이전트에게 질문: "볼트에서 XX 관련 노트 찾아줘"
# → memory_search가 볼트 파일을 검색하면 성공
```

### 7-4. NotebookLM 확인 (선택)

```bash
nlm notebook list
# 노트북 목록이 출력되면 성공
```

---

## Troubleshooting

### memory_search에서 볼트 파일이 안 나와요
- `openclaw.json`의 `extraPaths`에 볼트 절대 경로가 정확한지 확인
- `openclaw gateway restart` 실행
- OpenAI API Key가 설정되어 있는지 확인
- `watch: true`가 설정되어 있는지 확인
- 인덱싱에 시간이 걸릴 수 있음 (볼트 크기에 따라 수분~수십분)

### EISDIR 에러
- `read("memory")` 절대 금지 → `read("memory/YYYY-MM-DD.md")`로 개별 파일 읽기
- `exec("ls memory/")` 로 파일 목록 먼저 확인

### obsidian-cli가 볼트를 못 찾아요
- `obsidian-cli set-default "볼트이름"` 재실행
- Obsidian 앱이 한 번 이상 해당 볼트를 열었는지 확인
- `~/Library/Application Support/obsidian/obsidian.json` 에 볼트 등록 확인

### 심볼릭 링크가 Obsidian에서 안 보여요
- Obsidian은 심볼릭 링크를 지원합니다 (macOS)
- iCloud 볼트의 경우 심볼릭 링크가 동기화되지 않을 수 있음 → 방법 B(크론 복사) 사용

### NotebookLM 인증 실패
- `notebooklm` 피처팩의 인증 단계 참조
- Chrome 브라우저가 설치되어 있어야 함
