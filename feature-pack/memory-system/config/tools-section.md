# TOOLS.md 추가 섹션 — Memory System

아래 내용을 TOOLS.md에 추가하세요.

---

```markdown
### Obsidian

- Default vault: `{{VAULT_NAME}}`
- Path: `{{VAULT_PATH}}`

### Obsidian CLI (obsidian-cli)

**바이너리**: `obsidian-cli` (brew 설치)
**설치**: `brew install yakitrak/yakitrak/obsidian-cli`

핵심 명령어:
- `obsidian-cli list` — 볼트 루트 목록
- `obsidian-cli list "폴더명"` — 폴더 내 목록
- `obsidian-cli print "경로/파일명"` — 노트 읽기
- `obsidian-cli search "검색어"` — 노트 이름 검색
- `obsidian-cli search-content "검색어"` — 노트 내용 검색
- `obsidian-cli create "경로/노트명" --content "내용"` — 노트 생성
- `obsidian-cli move "old" "new"` — 이동 (위키링크 자동 업데이트)
- `obsidian-cli daily` — 데일리 노트 생성/열기

직접 파일 편집도 가능: 볼트는 일반 폴더이므로 read/write/edit 도구로 .md 직접 수정 → Obsidian 자동 감지
```
