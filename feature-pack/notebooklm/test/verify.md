# NotebookLM Feature Pack 설치 검증

## 자동 검증 명령어

아래 명령어를 순서대로 실행하여 설치를 검증합니다.

### 1. CLI 설치 확인
```bash
nlm --version
# 예상: nlm version 0.x.x
```

### 2. 인증 상태
```bash
nlm auth status
# 예상: ✓ Authenticated (노트북 수 표시)
```

### 3. 노트북 접근
```bash
nlm notebook list
# 예상: 기존 노트북 목록 또는 빈 목록
```

### 4. 스킬 파일 확인
```bash
ls ~/.openclaw/workspace/skills/notebooklm/SKILL.md
# 예상: 파일 존재
```

### 5. TOOLS.md 설정 확인
```bash
grep -c "NotebookLM" ~/.openclaw/workspace/TOOLS.md
# 예상: 1 이상
```

### 6. 통합 테스트 (노트북 생성 → 소스 → 쿼리 → 삭제)
```bash
# 생성
NB_ID=$(nlm notebook create "Feature Pack Test" --json | jq -r '.id // .notebook_id')
echo "Created: $NB_ID"

# 소스 추가
nlm source add "$NB_ID" --text "The quick brown fox jumps over the lazy dog. This is a test document for verifying NotebookLM feature pack installation." --title "Test Source" --wait

# 쿼리
nlm query notebook "$NB_ID" "What animal jumps?"
# 예상: fox 관련 답변

# 정리
nlm notebook delete "$NB_ID" --confirm
echo "Test complete!"
```

## 체크리스트

- [ ] `nlm --version` → 버전 출력
- [ ] `nlm auth status` → Authenticated
- [ ] `nlm notebook list` → 정상 출력
- [ ] 스킬 SKILL.md 존재
- [ ] TOOLS.md에 NotebookLM 섹션 존재
- [ ] 통합 테스트 통과
