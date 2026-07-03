#!/bin/bash
# fable-team orchestration-gate — 턴 카운터 리셋 (UserPromptSubmit)
# 매 사용자 입력마다 orchestration-gate의 "한 턴 코드파일" 카운터를 비운다.
# FAIL-OPEN: 어떤 오류도 exit 0.
set +e
INPUT=$(cat 2>/dev/null)
SID=$(printf '%s' "$INPUT" | python3 -c "import json,sys;
try: print(json.load(sys.stdin).get('session_id','nosess'))
except Exception: print('nosess')" 2>/dev/null)
[ -z "$SID" ] && exit 0
KEY=$(printf '%s' "$SID" | python3 -c "import sys,hashlib; print(hashlib.sha1(sys.stdin.read().encode()).hexdigest()[:16])" 2>/dev/null)
# P2-9: 매 턴 무조건 리셋은 사용자/자기 "계속" 분할로 2파일씩 계속 우회 가능 →
#   카운터 파일이 OMC_GATE_WINDOW_SEC(기본 300s) 이상 묵힌 경우에만 리셋(같은 작업 창 내 분할은 누적).
#   과설계(persistent ledger)는 정당 작업 false-deny 리스크 → mtime 절충. 한계는 문서화된 우회 가능성 존재.
#   ${TMPDIR:-/tmp}는 빈 값도 /tmp로 정규화. stat: macOS(-f %m)/Linux(-c %Y) 폴백, 실패 시 0(→리셋=비차단 방향).
WINDOW="${OMC_GATE_WINDOW_SEC:-300}"
FILE="${TMPDIR:-/tmp}/omc-orch-gate/${KEY}.files"
if [ -n "$KEY" ] && [ -f "$FILE" ]; then
  NOW=$(date +%s)
  MT=$(stat -f %m "$FILE" 2>/dev/null || stat -c %Y "$FILE" 2>/dev/null || echo 0)
  AGE=$(( NOW - MT ))
  [ "$AGE" -ge "$WINDOW" ] && rm -f "$FILE" 2>/dev/null
fi
exit 0
