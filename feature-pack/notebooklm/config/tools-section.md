# TOOLS.md 추가 섹션 — NotebookLM

아래 내용을 `TOOLS.md`에 추가하세요.

---

### 📓 NotebookLM CLI (`nlm`)

**바이너리**: `~/.local/bin/nlm`
**출처**: `notebooklm-mcp-cli` (uv tool install)
**인증**: Google 계정 연동 (`nlm login`)

**핵심 명령어:**
```bash
NLM=~/.local/bin/nlm

# 노트북 관리
$NLM notebook list                          # 전체 노트북 목록
$NLM notebook create "이름"                 # 새 노트북 생성
$NLM notebook get <notebook_id>             # 노트북 상세
$NLM notebook describe <notebook_id>        # AI 요약 + 추천 토픽

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
```

**활용 시나리오:**
- 옵시디언 문서 묶어서 NotebookLM 프로젝트 생성 → `notebook create` + `source add --file`
- 프로젝트 지식 Q&A → `query notebook`
- 문서 기반 오디오 요약 생성 → `audio create`
