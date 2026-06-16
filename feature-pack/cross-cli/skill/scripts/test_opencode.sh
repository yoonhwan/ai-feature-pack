#!/usr/bin/env bash
# test_opencode.sh — opencode 단독 비대화·자율·resume 점검 (모델 자동탐색)
# Usage: bash test_opencode.sh [provider/model]
#   인자 생략 시: $OPENCODE_MODEL → 없으면 `opencode models`에서 claude/sonnet 우선 자동선택.
# 로그: <skill>/logs/opencode.r1 / .r2 / .err
set -uo pipefail
exec </dev/null

command -v opencode >/dev/null 2>&1 || { echo "ERROR: opencode 없음 (PATH)"; exit 127; }

TIMEOUT_S="${CROSS_CLI_TIMEOUT:-120}"
run_to(){ perl -e '
  my $t=shift @ARGV; my $pid=fork();
  if(!defined $pid){ exit 127 }
  if($pid==0){ setpgrp(0,0); exec @ARGV or exit 127 }
  local $SIG{ALRM}=sub{ kill("KILL", -$pid); }; alarm $t;
  waitpid($pid,0); my $rc=$?; alarm 0; exit($rc==0?0:($rc>>8||142));
' "$TIMEOUT_S" "$@"; }

# ── 모델 결정 ──
MODEL="${1:-${OPENCODE_MODEL:-}}"
if [ -z "$MODEL" ]; then
  echo "[info] 모델 자동탐색: opencode models ..."
  LIST=$(run_to opencode models 2>/dev/null)
  MODEL=$(printf '%s\n' "$LIST" | grep -iE 'claude.*sonnet' | head -1)
  [ -z "$MODEL" ] && MODEL=$(printf '%s\n' "$LIST" | grep -iE 'claude' | head -1)
  [ -z "$MODEL" ] && MODEL=$(printf '%s\n' "$LIST" | grep -E '.+/.+' | head -1)
fi
MODEL=$(printf '%s' "$MODEL" | tr -d '[:space:]')
[ -z "$MODEL" ] && { echo "ERROR: 모델 미결정. 'opencode models'로 확인 후 인자로 전달하세요."; exit 2; }
echo "[info] 사용 모델: $MODEL  (timeout ${TIMEOUT_S}s)"

SDIR="$(cd "$(dirname "$0")/.." && pwd)"
LOGDIR="${CROSS_CLI_LOGDIR:-$SDIR/logs}"; mkdir -p "$LOGDIR"
TOKEN="BANANA-7"
R1="Remember this codeword: ${TOKEN}. Reply with exactly: OK ${TOKEN}"
R2="What was the codeword I gave you earlier? Reply with ONLY the codeword, nothing else."

echo "── R1 (비대화 + 자율) ──"
o1=$(run_to opencode run -m "$MODEL" "$R1" 2>"$LOGDIR/opencode.err"); printf '%s\n' "$o1" | tee "$LOGDIR/opencode.r1"
echo "── R2 (resume -c) ──"
o2=$(run_to opencode run -c -m "$MODEL" "$R2" 2>>"$LOGDIR/opencode.err"); printf '%s\n' "$o2" | tee "$LOGDIR/opencode.r2"

r1="✅"; grep -q "$TOKEN" <<<"$o1" || r1="❌ R1불일치"
r2="✅"; grep -q "$TOKEN" <<<"$o2" || r2="❌ 미회상"
echo
echo "결과: R1=$r1 / R2(resume)=$r2   모델=$MODEL"
if [ "$r1" = "✅" ] && [ "$r2" = "✅" ]; then
  echo "🎉 opencode 정상 — 비대화 + 자율 + resume 통과"
else
  echo "실패 — 아래 opencode.err 마지막 부분:"; tail -c 700 "$LOGDIR/opencode.err"
fi
