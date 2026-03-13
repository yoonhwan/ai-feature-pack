# TOOLS.md 추가 섹션: Obsidian CLI

아래 내용을 `TOOLS.md`에 추가하세요.

---

### 📝 Obsidian CLI (obsidian-cli)

**바이너리**: `/opt/homebrew/bin/obsidian-cli` (brew 설치)
**설치**: `brew install yakitrak/yakitrak/obsidian-cli`
**기본 볼트**: `{{VAULT_NAME}}` (`{{VAULT_PATH}}`)

**핵심 명령어:**
```bash
# 조회
obsidian-cli list                          # 볼트 루트 파일/폴더 목록
obsidian-cli list "폴더명"                  # 특정 폴더 내 목록
obsidian-cli print "경로/파일명"            # 노트 내용 읽기
obsidian-cli print-default                 # 기본 볼트 확인

# 검색
obsidian-cli search "검색어"               # 노트 이름 퍼지 검색
obsidian-cli search-content "검색어"        # 노트 내용 검색

# 생성
obsidian-cli create "경로/노트명" --content "내용"
obsidian-cli daily                         # 데일리 노트

# 수정
obsidian-cli create "경로/노트명" --content "새내용" --overwrite    # 덮어쓰기
obsidian-cli create "경로/노트명" --content "추가" --append         # 추가
obsidian-cli frontmatter "경로/노트명" --edit --key "k" --value "v" # frontmatter

# 이동/삭제
obsidian-cli move "old/path" "new/path"    # 이동 (위키링크 자동 업데이트)
obsidian-cli delete "경로/노트명"           # 삭제
```

**직접 파일 편집**: 볼트는 일반 폴더 → `read`/`write`/`edit` 도구로 `.md` 직접 수정 가능
**참고**: `create`/`open`은 Obsidian URI handler 필요 (Obsidian 앱 실행 중)
