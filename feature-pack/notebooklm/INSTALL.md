# Feature Pack: NotebookLM

> 이 문서는 OpenClaw 에이전트가 읽고 자율적으로 설치를 진행하는 프롬프트입니다.
> 사용자에게 질문이 필요한 항목은 `{{PLACEHOLDER}}` 로 표시되어 있습니다.
> placeholder를 발견하면 **반드시 사용자에게 인터뷰**하고, 답변으로 대치한 뒤 진행하세요.

---

## 개요

**NotebookLM CLI (`nlm`)** — Google NotebookLM을 터미널에서 제어하는 CLI 도구.
노트북 생성/관리, 소스 추가(URL/파일/텍스트), AI Q&A, 리서치, 오디오/비디오/리포트 생성을 지원합니다.

**설치 후 할 수 있는 것:**
- 노트북 생성 & 소스 추가 (URL, 로컬 파일, 텍스트)
- 소스 기반 Q&A (할루시네이션 없는 문서 기반 답변)
- 딥 리서치 (웹 소스 자동 수집)
- 오디오 팟캐스트 / 비디오 / 리포트 / 퀴즈 / 플래시카드 / 마인드맵 / 슬라이드 생성
- Obsidian 볼트 문서를 NotebookLM 소스로 연동

---

## Prerequisites (사전 요구사항)

### 필수
- **macOS** (Apple Silicon 또는 Intel)
- **Python 3.10+** — `python3 --version` 으로 확인
- **Google 계정** — NotebookLM 접근 권한 필요
- **Chrome 브라우저** — 인증에 사용 (설치되어 있어야 함)

### 선택
- **uv** (Python 패키지 매니저) — 없으면 Step 1에서 설치

---

## Step 1: CLI 설치

### 1-1. uv 설치 (이미 있으면 건너뛰기)

```bash
# uv 존재 여부 확인
which uv

# 없으면 설치
curl -LsSf https://astral.sh/uv/install.sh | sh
```

### 1-2. nlm CLI 설치

```bash
uv tool install notebooklm-mcp-cli
```

### 1-3. 설치 확인

```bash
nlm --version
# 출력 예: nlm version 0.4.6
```

> ⚠️ `nlm` 명령을 찾을 수 없으면 PATH에 `~/.local/bin` 추가 필요:
> ```bash
> echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
> source ~/.zshrc
> ```

---

## Step 2: Google 인증

### 2-1. 최초 로그인

```bash
nlm login
```

- Chrome 브라우저가 열리며 Google 로그인 페이지가 표시됩니다
- **사용자에게 안내**: "브라우저에서 Google 계정으로 로그인해주세요"
- 로그인 완료 후 자동으로 쿠키 추출
- 성공 시: `✓ Successfully authenticated!`

### 2-2. 인증 확인

```bash
nlm auth status
```

### 2-3. 인증 관련 참고사항

- 세션은 약 **20분** 유지됩니다
- 세션 만료 시 `nlm login` 재실행 필요
- 자동 복구 (CSRF/토큰 리로드/Headless Auth) 가 내장되어 있어 대부분 자동 처리됩니다

---

## Step 3: 스킬 설치

### 3-1. 스킬 폴더 복사

이 Feature Pack의 `skill/` 폴더를 OpenClaw 워크스페이스 스킬 디렉토리에 복사합니다.

```bash
# OpenClaw 워크스페이스 스킬 경로
SKILL_DIR="{{OPENCLAW_WORKSPACE}}/skills/notebooklm"
# 예: ~/.openclaw/workspace/skills/notebooklm

# 스킬 폴더 복사
cp -r skill/ "$SKILL_DIR"
```

> **{{OPENCLAW_WORKSPACE}}** — OpenClaw 워크스페이스 경로.
> 보통 `~/.openclaw/workspace` 이지만, 사용자에게 확인하세요:
> "OpenClaw 워크스페이스 경로가 어디인가요? (기본: ~/.openclaw/workspace)"

### 3-2. 스킬 확인

스킬이 정상 로드되는지 확인:
```bash
ls "$SKILL_DIR/SKILL.md"
# 파일이 존재해야 함
```

---

## Step 4: OpenClaw 설정

### 4-1. TOOLS.md에 추가

`{{OPENCLAW_WORKSPACE}}/TOOLS.md` 파일에 아래 섹션을 추가합니다.
이미 존재하면 내용을 업데이트합니다.

```markdown
### 📓 NotebookLM CLI (`nlm`)

**바이너리**: `~/.local/bin/nlm`
**출처**: `notebooklm-mcp-cli` (uv tool install)
**인증**: Google 계정 연동 (nlm login)

**핵심 명령어:**
\```bash
NLM=~/.local/bin/nlm

# 노트북 관리
$NLM notebook list                          # 전체 노트북 목록
$NLM notebook create "이름"                 # 새 노트북 생성
$NLM notebook get <notebook_id>             # 노트북 상세
$NLM notebook describe <notebook_id>        # AI 요약

# 소스 관리
$NLM source add <notebook_id> --file <path>   # 로컬 파일 업로드
$NLM source add <notebook_id> --url <url>     # URL 소스 추가
$NLM source add <notebook_id> --text "내용" --title "제목"  # 텍스트 소스

# 쿼리 (핵심!)
$NLM query notebook <notebook_id> "질문"    # 소스 기반 Q&A

# 생성
$NLM audio create <notebook_id> --confirm   # 오디오 팟캐스트
$NLM report create <notebook_id> --confirm  # 리포트
$NLM quiz create <notebook_id> --confirm    # 퀴즈
$NLM mindmap create <notebook_id> --confirm # 마인드맵
$NLM slides create <notebook_id> --confirm  # 슬라이드

# 리서치
$NLM research start <notebook_id> "주제" --mode deep  # 웹 리서치
$NLM research status <notebook_id>                     # 진행 상태

# 다운로드
$NLM download audio <notebook_id> <artifact_id> -o <path>

# 별칭 (UUID 단축)
$NLM alias set myproject <notebook_id>      # 별칭 설정
$NLM alias list                             # 별칭 목록
\```
```

### 4-2. AGENTS.md 수정 (선택사항)

특정 채널에서 NotebookLM을 자주 사용한다면, 해당 채널 규칙에 다음을 추가:

```markdown
### NotebookLM 연동
- 사용자가 "노트북에서 찾아봐", "NotebookLM 확인" 등 요청 시 nlm query 실행
- 노트북 별칭 목록: (nlm alias list로 확인)
```

---

## Step 5: Obsidian 연동 (선택사항)

Obsidian 볼트의 마크다운 문서를 NotebookLM 소스로 활용할 수 있습니다.

### 5-1. Obsidian 볼트 문서 → NotebookLM 소스 추가

```bash
# 1. 노트북 생성
nlm notebook create "{{VAULT_NAME}} Knowledge Base"

# 2. 별칭 설정
nlm alias set vault <생성된_notebook_id>

# 3. 옵시디언 파일을 소스로 추가
nlm source add vault --file "{{OBSIDIAN_VAULT_PATH}}/파일명.md"

# 여러 파일을 한번에 추가하려면:
find "{{OBSIDIAN_VAULT_PATH}}" -name "*.md" -maxdepth 1 | while read f; do
  nlm source add vault --file "$f"
  sleep 1  # 레이트리밋 방지
done
```

> **{{VAULT_NAME}}** — Obsidian 볼트 이름. 사용자에게 물어보세요:
> "Obsidian 볼트 이름이 무엇인가요?"
>
> **{{OBSIDIAN_VAULT_PATH}}** — Obsidian 볼트 경로. 사용자에게 물어보세요:
> "Obsidian 볼트 경로가 어디인가요?"
> macOS 기본: `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/{볼트이름}`

### 5-2. 활용 시나리오

- **프로젝트 지식 Q&A**: 프로젝트 문서를 소스로 → `nlm query`로 검색
- **문서 기반 팟캐스트**: 여러 문서 소스 → `nlm audio create`
- **스터디 자료**: 학습 노트 → `nlm quiz create` + `nlm flashcards create`

### 5-3. Obsidian 플러그인 (선택)

NotebookLM과 직접 연동하는 Obsidian 플러그인은 아직 없습니다.
대안: 위의 CLI 명령을 Obsidian 터미널(또는 Templater 스크립트)에서 실행.

---

## Step 6: 설치 검증

### 6-1. CLI 동작 확인

```bash
# 버전 확인
nlm --version

# 인증 상태
nlm auth status

# 노트북 목록 (인증 성공 시 목록 출력)
nlm notebook list
```

### 6-2. 간단 테스트

```bash
# 테스트 노트북 생성
nlm notebook create "Feature Pack Test"

# 텍스트 소스 추가
nlm source add <notebook_id> --text "OpenClaw is an AI agent framework. It supports skills, CLI tools, and automation." --title "Test Source"

# 쿼리 테스트
nlm query notebook <notebook_id> "What is OpenClaw?"

# 테스트 노트북 삭제 (선택)
nlm notebook delete <notebook_id> --confirm
```

### 6-3. 검증 체크리스트

- [ ] `nlm --version` 정상 출력
- [ ] `nlm auth status` → `✓ Authenticated`
- [ ] `nlm notebook list` → 노트북 목록 표시
- [ ] 스킬 폴더 존재: `ls {{OPENCLAW_WORKSPACE}}/skills/notebooklm/SKILL.md`
- [ ] TOOLS.md에 NotebookLM 섹션 추가됨

---

## Troubleshooting

| 문제 | 원인 | 해결 |
|------|------|------|
| `nlm: command not found` | PATH 미설정 | `export PATH="$HOME/.local/bin:$PATH"` 추가 |
| `uv: command not found` | uv 미설치 | Step 1-1 실행 |
| "Cookies have expired" | 세션 만료 | `nlm login` 재실행 |
| "authentication may have expired" | 세션 만료 | `nlm login` 재실행 |
| Chrome 안 열림 | Chrome 미설치 | `brew install --cask google-chrome` |
| Rate limit 에러 | API 호출 제한 | 자동 재시도 (3회), 계속 실패 시 잠시 대기 |
| 소스 추가 실패 | 파일 크기 초과 | NotebookLM 소스 크기 제한 확인 (500KB~) |

---

## Placeholder 정리

설치 중 사용자에게 인터뷰가 필요한 항목:

| Placeholder | 설명 | 기본값 |
|-------------|------|--------|
| `{{OPENCLAW_WORKSPACE}}` | OpenClaw 워크스페이스 경로 | `~/.openclaw/workspace` |
| `{{VAULT_NAME}}` | Obsidian 볼트 이름 (Obsidian 연동 시) | — |
| `{{OBSIDIAN_VAULT_PATH}}` | Obsidian 볼트 경로 (Obsidian 연동 시) | `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/{볼트이름}` |

---

## 설치 완료 후

1. `nlm notebook list` 로 기존 노트북 확인
2. `nlm alias set` 으로 자주 쓰는 노트북에 별칭 설정
3. `nlm query notebook <id> "질문"` 으로 소스 기반 Q&A 시작
4. `nlm --ai` 로 전체 명령어 AI 가이드 확인 가능

**업데이트:**
```bash
uv tool upgrade notebooklm-mcp-cli
```
