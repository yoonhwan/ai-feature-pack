#!/bin/bash
# PreToolUse(Bash) hook — 키 변경·삭제 게이트 (R277 · 오빠 급 · desk#7 #99701)
# gcloud api-keys·secrets versions·Cloud Run 키 env 변경은 byz-keys 장부 «사용처 표» 없으면 막고, 옛 키 삭제·비활성은 «전환 확인» 줄 없으면 막는다.
# 판정 = 같은 폴더 key_change_judge.py --hook (deny → permissionDecision deny JSON · 통과 → 출력 없음). 오빠가 `!` 로 직접 치는 명령은 훅 밖(의도).
# 판정기 실패(파이썬 오류·동봉 모듈 없음) 후퇴 순서: ①토큰 분석(key_change_cmd.py --scan — 실행되는 키 변경 명령이면 deny · 글자로만 든 명령은 통과) ②그것도 실패하면 글자 검사 — 키 변경 모양이 글자로 보이면 deny(#0 RULE) · 아니면 통과(fail-open — 다른 작업 마비 0).
# 되돌림: settings.json 의 이 훅 줄 삭제 + 이 파일·key_change_judge.py·key_change_cmd.py·key_change_ledger.py 삭제.
JUDGE="${KEY_GATE_JUDGE:-$(dirname "${BASH_SOURCE[0]}")/key_change_judge.py}"
INPUT=$(cat)
case "$INPUT" in *gcloud*) ;; *) exit 0 ;; esac   # gcloud 글자가 없으면 판정기를 부르지 않는다(비용 ≈0)

OUT=$(printf '%s' "$INPUT" | python3 "$JUDGE" --hook 2>/dev/null)
RC=$?
if [ "$RC" = 0 ]; then
  [ -z "$OUT" ] || printf '%s\n' "$OUT"
  exit 0
fi
DENY='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"REJECT 키 변경 게이트 — 판정기가 실패해 키 변경 명령을 통과시키지 않음. 오빠에게 [HIL] 로 올리거나 판정기 복구(key_change_judge.py) 뒤 다시"}}'
# 후퇴 1: 장부 없이 토큰 분석만(key_change_cmd.py --scan) — echo·commit -m·heredoc·grep 글자는 «실행되는 명령»이 아니라 통과 (DA H1)
SCAN=$(printf '%s' "$INPUT" | python3 "$(dirname "${BASH_SOURCE[0]}")/key_change_cmd.py" --scan 2>/dev/null)
if [ $? = 0 ]; then
  if [ "$SCAN" = hit ]; then
    echo "key-change-gate: 판정기 실패(rc=$RC) + 키 변경 명령 — 막는다(#0 RULE) · 사용처 표: keys-usage.sh <ENV>" >&2
    printf '%s\n' "$DENY"
  else
    echo "key-change-gate: 판정기 실패(rc=$RC) — 키 변경 명령이 아니라 통과(fail-open)" >&2
  fi
  exit 0
fi
# 후퇴 2(마지막): 토큰 분석까지 실패 — 글자 검사. 키 변경 모양이 «글자로» 보이면 deny · 아니면 통과
if printf '%s' "$INPUT" | grep -qE 'gcloud[^|;&]*(secrets[ \\"]+versions[ \\"]+(add|disable|destroy)|secrets[ \\"]+delete|api-keys[ \\"]+(create|update|delete)|run[ \\"]+services[ \\"]+update)'; then
  echo "key-change-gate: 판정기·토큰 분석 실패(rc=$RC) + 키 변경 모양 — 막는다(#0 RULE)" >&2
  printf '%s\n' "$DENY"
  exit 0
fi
echo "key-change-gate: 판정기 실패(rc=$RC) — 키 변경 모양이 아니라 통과(fail-open)" >&2
exit 0
