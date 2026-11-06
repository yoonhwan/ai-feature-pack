#!/usr/bin/env bash
# test_resume_gate.sh — r1426 리줌 상한: 큰 대화는 리줌하지 않고 증류로 이어간다.
#   픽스처 jsonl 만 사용(실 세션·홈·tmux 쓰기 0) · 고정 sleep 0 · 외부 호출 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="$HERE/../kit/fable-team/bin/ft-resume-gate.sh"
RR="$HERE/../kit/fable-team/bin/ft-reboot-restore.sh"
fail=0
ok(){ echo "PASS $1"; }; bad(){ echo "FAIL $1"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mk(){ python3 - "$1" "$2" <<'PY'
import json,sys
p,ctx=sys.argv[1],int(sys.argv[2])
open(p,"w").write(json.dumps({"type":"assistant","message":{"usage":{"input_tokens":ctx,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}})+"\n")
PY
}
/bin/bash -n "$GATE" && ok "gate /bin/bash -n" || bad "gate syntax"
/bin/bash -n "$RR"   && ok "reboot-restore /bin/bash -n" || bad "rr syntax"
mk "$T/small.jsonl" 90000;  "$GATE" "$T/small.jsonl" >"$T/o1" 2>&1; rc=$?
{ [ $rc -eq 0 ] && grep -q 'RESUME_OK' "$T/o1"; } && ok "90k → RESUME_OK rc0" || bad "90k rc=$rc $(cat "$T/o1")"
mk "$T/big.jsonl" 420000;   "$GATE" "$T/big.jsonl" >"$T/o2" 2>&1; rc=$?
{ [ $rc -eq 1 ] && grep -q 'DISTILL' "$T/o2"; } && ok "420k → DISTILL rc1" || bad "420k rc=$rc $(cat "$T/o2")"
"$GATE" "$T/big.jsonl" --max 500000 >"$T/o3" 2>&1; rc=$?
[ $rc -eq 0 ] && ok "상한 500k → RESUME_OK" || bad "max override rc=$rc"
FT_RESUME_MAX=80000 "$GATE" "$T/small.jsonl" >"$T/o4" 2>&1; rc=$?
[ $rc -eq 1 ] && ok "env FT_RESUME_MAX=80000 → 90k 도 DISTILL" || bad "env rc=$rc"
"$GATE" "$T/does-not-exist.jsonl" >"$T/o5" 2>&1; rc=$?
{ [ $rc -eq 3 ] && grep -q 'UNKNOWN' "$T/o5"; } && ok "없는 파일 → UNKNOWN rc3" || bad "missing rc=$rc"
grep -q 'DISTILL' "$RR" && grep -q 'FT_RESUME_MAX' "$RR" && ok "reboot-restore 에 DISTILL 분기 배선" || bad "rr 배선"
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAIL=$fail"
exit "$fail"
