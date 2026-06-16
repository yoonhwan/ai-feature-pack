# agent-cli 설치 검증

다음을 순서대로 실행:

```bash
# 1. SKILL.md 존재 + 이름
test -f ~/.claude/skills/agent-cli/SKILL.md && grep -q 'name: agent-cli' ~/.claude/skills/agent-cli/SKILL.md && echo "✅ SKILL.md" || echo "❌ SKILL.md missing"

# 2. references
test -f ~/.claude/skills/agent-cli/references/per-cli.md && echo "✅ per-cli.md" || echo "❌ per-cli.md"
test -f ~/.claude/skills/agent-cli/references/personas.md && echo "✅ personas.md" || echo "❌ personas.md"

# 3. scripts (실행권한 포함)
for s in detect-env selftest test_opencode resume_chain; do
  f=~/.claude/skills/agent-cli/scripts/$s.sh
  test -x "$f" && echo "✅ $s.sh (x)" || echo "❌ $s.sh missing or not executable"
done

# 4. 문법 검사
for s in detect-env selftest test_opencode resume_chain; do
  bash -n ~/.claude/skills/agent-cli/scripts/$s.sh && echo "✅ $s.sh syntax" || echo "❌ $s.sh syntax error"
done

# 5. 의존성
command -v perl >/dev/null && echo "✅ perl" || echo "❌ perl"
command -v python3 >/dev/null && echo "✅ python3" || echo "❌ python3"

# 6. 에이전트 CLI 최소 1개 존재
n=0; for c in claude codex gemini opencode cursor-agent; do command -v "$c" >/dev/null 2>&1 && { echo "  · $c ✅"; n=$((n+1)); }; done
[ "$n" -ge 1 ] && echo "✅ 에이전트 CLI ${n}개 감지" || echo "❌ 에이전트 CLI 0개 — 최소 1개 필요"

# 7. perl 강제 타임아웃 동작(2초 제한으로 5초 sleep 종료)
t0=$(date +%s); perl -e 'my $t=shift@ARGV;my $p=fork();if($p==0){setpgrp(0,0);exec @ARGV or exit 127}local $SIG{ALRM}=sub{kill("KILL",-$p)};alarm $t;waitpid($p,0);exit($?>>8||142)' 2 sleep 5 >/dev/null 2>&1; t1=$(date +%s)
[ $((t1-t0)) -le 3 ] && echo "✅ 타임아웃 동작(${t1}-${t0}s)" || echo "❌ 타임아웃 미동작"
```

기대: 1~5·7 모두 ✅ + 6에서 최소 1개 CLI ✅.

## 실동작(end-to-end) 검증 — 인증된 환경에서

```bash
# 설치된 CLI만 비대화·자율·resume 일괄 점검 (격리/신뢰 폴더에서)
bash ~/.claude/skills/agent-cli/scripts/selftest.sh
# → logs/selftest.log 요약표에서 각 CLI R1 ✅ / R2(resume) ✅ 확인
```

미인증/미설치 CLI는 SKIP 또는 ⚠️/❌로 표시되며, 이는 스크립트 결함이 아니라 해당 CLI 환경 상태다(`logs/<cli>.err` 참조).
