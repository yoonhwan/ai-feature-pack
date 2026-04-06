# NanoClaw 관리 스킬

> NanoClaw 에이전트 플랫폼의 그룹·컨테이너·상태를 관리하는 스킬

## 사용 가능 명령

### 그룹 관리
```bash
# 그룹 목록
ls groups/

# 그룹 생성 (페르소나 정의)
mkdir -p groups/{name}/memory
# → groups/{name}/CLAUDE.md 작성

# 메모리 확인
cat groups/{name}/memory/directives.md
cat groups/{name}/memory/mistakes.md
cat groups/{name}/memory/achievements.md
```

### 상태 확인
```bash
# 실행 중인 컨테이너
docker ps --filter "name=nanoclaw"

# OneCLI 상태
docker ps --filter "name=onecli"

# launchd 서비스
launchctl list | grep nanoclaw

# SQLite 대화 이력
sqlite3 store/messages.db "SELECT COUNT(*) FROM messages;"
```

### 스킬 관리
```bash
# 내장 스킬 목록
ls .claude/skills/

# 커스텀 스킬 추가
mkdir -p groups/{name}/skills/{skill-name}
# → SKILL.md 작성
```
