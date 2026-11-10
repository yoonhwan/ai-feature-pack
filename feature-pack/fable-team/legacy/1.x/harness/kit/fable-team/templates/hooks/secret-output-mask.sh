#!/bin/bash
# PostToolUse(*) hook — 도구 출력 속 비밀 «모양»을 *** 로 바꿔 Claude 에 넘긴다 (R135b · 판정 1585 · 제안서 §3-②)
# 판정 = 같은 폴더 ft_secret_shapes.py --hook (바뀐 것 있음 → hookSpecificOutput.updatedToolOutput JSON · 없음 → 출력 0).
# 원장 = ~/.claude/state/secret-leak.log (시각·세션 id·도구·종류 · 값 0).
# 실패(파이썬 오류·JSON 깨짐·파일 없음)는 원본 통과 — fail-open: stderr 1줄 + hook-falsepos.log 1줄(본문 0) — 전 세션 마비 방지.
# 시험 끄기 = env FT_SECRET_GUARD_TEST_OFF (시험 하네스에서만 — 좌석이 스스로 끄는 경로 없음).
# 되돌림: settings.json 백업(.bak-r135b) 복원 + 이 파일·ft_secret_shapes.py 삭제.
SHAPES="${FT_SECRET_SHAPES:-$(dirname "${BASH_SOURCE[0]}")/ft_secret_shapes.py}"
LOG="${FT_SECRET_FALSEPOS_LOG:-$HOME/.claude/state/hook-falsepos.log}"

OUT=$(python3 "$SHAPES" --hook 2>/dev/null)
RC=$?
if [ "$RC" = 0 ]; then
  [ -z "$OUT" ] || printf '%s\n' "$OUT"
  exit 0
fi
echo "secret-output-mask: 가림 모듈 실패(rc=$RC) — 원본을 그대로 통과시킨다(fail-open)" >&2
mkdir -p "$(dirname "$LOG")" 2>/dev/null
printf '%s secret-output-mask 가림 모듈 실패 rc=%s shapes=%s\n' "$(date '+%F %T')" "$RC" "$SHAPES" >> "$LOG" 2>/dev/null
exit 0
