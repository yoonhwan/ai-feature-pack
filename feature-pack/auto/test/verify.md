# AutoResearch v3.0 설치 검증

다음 명령을 순서대로 실행하세요:

```bash
# 1. SKILL.md 존재 + 버전
test -f ~/.claude/skills/auto/SKILL.md && grep -q '3.0.0' ~/.claude/skills/auto/SKILL.md && echo "✅ SKILL.md v3.0" || echo "❌ SKILL.md missing or wrong version"

# 2. git-loop-protocol 존재
test -f ~/.claude/skills/auto/references/git-loop-protocol.md && echo "✅ git-loop-protocol.md" || echo "❌ not found"

# 3. run-experiment-contract 존재
test -f ~/.claude/skills/auto/references/run-experiment-contract.md && echo "✅ run-experiment-contract.md" || echo "❌ not found"

# 4. report-template 존재
test -f ~/.claude/skills/auto/references/report-template.md && echo "✅ report-template.md" || echo "❌ not found"

# 5. Python 3.11+
python3 -c "import sys; v=sys.version_info; assert v>=(3,11); print(f'✅ Python {v.major}.{v.minor}')" 2>/dev/null || echo "❌ Python 3.11+ required"

# 6. git 사용 가능
git --version >/dev/null 2>&1 && echo "✅ git OK" || echo "❌ git not found"

# 7. uv 사용 가능
uv --version >/dev/null 2>&1 && echo "✅ uv OK" || echo "❌ uv not found — install: curl -LsSf https://astral.sh/uv/install.sh | sh"

# 8. SKILL.md 핵심 키워드 확인
grep -q "uv run run_experiment.py" ~/.claude/skills/auto/SKILL.md && echo "✅ uv run pattern present" || echo "❌ uv run pattern missing"

# 9. SKILL.md 원칙 확인
grep -q "에이전트는 코드만 수정" ~/.claude/skills/auto/SKILL.md && echo "✅ core principle present" || echo "❌ core principle missing"

# 10. 템플릿 확인 (선택)
ls config/templates/*.py config/templates/*.toml config/templates/*.md >/dev/null 2>&1 && echo "✅ templates found" || echo "⚠️ templates not in current directory (OK if already copied to project)"
```

기대 결과: 9개 필수 ✅ + 1개 선택 ✅/⚠️
