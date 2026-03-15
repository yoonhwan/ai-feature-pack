# Memory System 설치 검증

## 체크리스트

### 1. OC 워크스페이스 메모리
- [ ] `{{OC_WORKSPACE}}/MEMORY.md` 존재
- [ ] `{{OC_WORKSPACE}}/memory/` 폴더 존재
- [ ] AGENTS.md에 Memory 섹션 추가됨
- [ ] TOOLS.md에 Obsidian 섹션 추가됨

### 2. Obsidian 볼트
- [ ] 볼트 폴더 구조 생성 (Daily, News-Links, Meetings, People, Projects, Reference, Ideas, Archive)
- [ ] `HOME.md` 생성됨
- [ ] `Meetings/_INDEX.md` 생성됨
- [ ] `People/_INDEX.md` 생성됨
- [ ] `obsidian-cli set-default` 완료
- [ ] `obsidian-cli list` 정상 출력

### 3. 메모리 검색 통합
- [ ] `openclaw.json`에 `memorySearch.extraPaths` 설정됨
- [ ] `watch: true` 설정됨
- [ ] OpenAI API Key 설정됨
- [ ] `openclaw gateway restart` 실행
- [ ] 에이전트에게 볼트 내 노트 검색 테스트 → 성공

### 4. 미러링
- [ ] `memory/` → `Daily/memory/` 링크 또는 복사 설정
- [ ] `MEMORY.md` → `Daily/MEMORY.md` 링크 또는 복사 설정

### 5. NotebookLM (선택)
- [ ] `nlm --version` 정상 출력
- [ ] `nlm notebook list` 정상 출력
- [ ] 볼트 문서를 소스로 추가 테스트
