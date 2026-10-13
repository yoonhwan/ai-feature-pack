#!/bin/bash
# PreToolUse(Bash) hook — 비밀을 stdout 으로 내는 명령이 화면·파이프로 가면 «실행 전에» 거절 (R135a · 판정 1585 · loom 사고 2026-10-13)
# 판정 = 같은 폴더 ft_secret_judge.py --hook (reject → permissionDecision deny JSON · ok → 출력 없음). 안전한 대안 = ft-secret-lib.sh 의 secret().
# 판정기 실패(파이썬 오류·파일 없음)는 deny 가 아니다 — fail-open: stderr 1줄 + 원장 1줄(명령 본문 0) — 전 세션 마비 방지.
# 되돌림: settings.json 백업(.bak-r135) 복원 + 이 파일·ft_secret_judge.py·ft_secret_lex.py 삭제.
JUDGE="${FT_SECRET_JUDGE:-$(dirname "${BASH_SOURCE[0]}")/ft_secret_judge.py}"
LOG="${FT_SECRET_GUARD_LOG:-$HOME/.fable-team/state/secret-guard-error.log}"

OUT=$(python3 "$JUDGE" --hook 2>/dev/null)
RC=$?
if [ "$RC" = 0 ]; then
  [ -z "$OUT" ] || printf '%s\n' "$OUT"
  exit 0
fi
echo "secret-output-guard: 판정기 실패(rc=$RC) — 검사 없이 통과시킨다(fail-open)" >&2
mkdir -p "$(dirname "$LOG")" 2>/dev/null
printf '%s secret-output-guard 판정기 실패 rc=%s judge=%s\n' "$(date '+%F %T')" "$RC" "$JUDGE" >> "$LOG" 2>/dev/null
exit 0
