# auto (AutoResearch) 설치 검증

## 체크리스트

```bash
# 1. 스킬 파일 존재
test -f ~/.claude/skills/auto/SKILL.md && echo "✅ SKILL.md found" || echo "❌ SKILL.md not found"

# 2. git-loop-protocol 레퍼런스
test -f ~/.claude/skills/auto/references/git-loop-protocol.md && echo "✅ git-loop-protocol.md found" || echo "❌ not found"

# 3. report-template 레퍼런스
test -f ~/.claude/skills/auto/references/report-template.md && echo "✅ report-template.md found" || echo "❌ not found"

# 4. YAML frontmatter 확인
head -8 ~/.claude/skills/auto/SKILL.md | grep -q 'name: "auto"' && echo "✅ YAML frontmatter OK" || echo "❌ YAML frontmatter invalid"

# 5. git 사용 가능
git --version >/dev/null 2>&1 && echo "✅ git OK" || echo "❌ git not found"

# 6. python3 사용 가능
python3 --version >/dev/null 2>&1 && echo "✅ python3 OK" || echo "❌ python3 not found"

# 7. python3 AST 파싱 가능 (실험 전 문법 검증용)
python3 -c "import ast; print('✅ ast module OK')" 2>/dev/null || echo "❌ ast module not available"
```

## 기대 결과

7개 항목 전부 ✅ → 설치 완료.
