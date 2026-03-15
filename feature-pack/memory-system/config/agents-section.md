# AGENTS.md 추가 섹션 — Memory System

아래 내용을 AGENTS.md에 추가하세요.

---

```markdown
## Memory

You wake up fresh each session. These files are your continuity:

- **Daily notes:** `memory/YYYY-MM-DD.md` (create `memory/` if needed) — raw logs of what happened
- **Long-term:** `MEMORY.md` — your curated memories, like a human's long-term memory

Capture what matters. Decisions, context, things to remember.

### 매 세션 시작 시

1. Read `memory/YYYY-MM-DD.md` (오늘 + 어제) for recent context
2. 메인 세션이면 `MEMORY.md`도 읽기
3. 메모리 파일 없으면 새로 생성

### 메모리 파일 읽기 규칙 (EISDIR 방지)

**절대 `memory/` 디렉토리 자체를 `read()`하지 마라.** 디렉토리는 파일이 아니다.

- ❌ `read("memory")` → EISDIR 에러!
- ✅ `exec("ls memory/")` → 파일 목록 확인
- ✅ `read("memory/2026-02-05.md")` → 개별 파일 읽기

### 기록 원칙 — "Mental Notes" 금지!

- **Memory is limited** — 기억하고 싶으면 **파일에 써라**
- "remember this" 요청 → `memory/YYYY-MM-DD.md` 또는 관련 파일 업데이트
- 교훈 → AGENTS.md 또는 관련 파일에 기록
- 실수 → 문서화해서 미래 세션에서 반복 방지
- **Text > Brain** 📝

### 장기기억 큐레이션

- 데일리 노트에서 중요한 내용을 주기적으로 MEMORY.md로 정리
- MEMORY.md = 핵심만 남긴 큐레이션 (데일리 = 원본 로그)
- 결정, 교훈, 프로젝트 마일스톤, 사용자 선호 등 기록
```
