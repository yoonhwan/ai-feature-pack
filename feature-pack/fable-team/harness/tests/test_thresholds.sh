#!/usr/bin/env bash
# test_thresholds.sh — r1427 문턱 «한 곳»: ft-thresholds.sh 하나를 증류 게이트·리줌 게이트가 같이 본다.
#   픽스처만 사용(실 세션·홈·tmux 쓰기 0) · 고정 sleep 0 · 외부 호출 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../kit/fable-team/bin"
GATE="$HERE/../kit/fable-team/templates/hooks/context-distill-gate.sh"
fail=0; ok(){ echo "PASS $1"; }; bad(){ echo "FAIL $1"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/nohome"; mkdir -p "$HOME"   # 사용자 문턱파일 차단(시험 격리)
TH="$T/th.env"; printf 'FT_DISTILL_WARN=100000\nFT_DISTILL_BLOCK=120000\nFT_DISTILL_RECV=100000\nFT_RESUME_MAX=50000\n' > "$TH"

"$BIN/ft-thresholds.sh" --export > "$T/e1" 2>&1
grep -q 'FT_DISTILL_WARN=250000' "$T/e1" && grep -q 'FT_RESUME_MAX=150000' "$T/e1" && ok "기본값 export" || bad "기본값 export: $(cat "$T/e1")"
FT_THRESHOLDS="$TH" "$BIN/ft-thresholds.sh" --export > "$T/e2" 2>&1
grep -q 'FT_DISTILL_WARN=100000' "$T/e2" && grep -q 'FT_RESUME_MAX=50000' "$T/e2" && ok "파일 override export" || bad "override: $(cat "$T/e2")"

python3 - "$T/small.jsonl" 90000 <<'PY'
import json,sys
open(sys.argv[1],"w").write(json.dumps({"type":"assistant","message":{"usage":{"input_tokens":int(sys.argv[2]),"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}})+"\n")
PY
FT_THRESHOLDS="$TH" "$BIN/ft-resume-gate.sh" "$T/small.jsonl" > "$T/o1" 2>&1; rc=$?
{ [ $rc -eq 1 ] && grep -q 'max=50,000' "$T/o1"; } && ok "리줌 게이트가 문턱파일을 봄(DISTILL max=50k)" || bad "리줌 게이트 rc=$rc $(cat "$T/o1")"

# 증류 게이트: 110k transcript + warn 100k → 경고 1
python3 - "$T/t.jsonl" 110000 <<'PY'
import json,sys
open(sys.argv[1],"w").write(json.dumps({"type":"assistant","message":{"model":"claude-opus-5-5","usage":{"input_tokens":int(sys.argv[2]),"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}})+"\n")
PY
mkdir -p "$T/rep/.fable-team" "$T/fakebin" "$T/home"; git -C "$T/rep" init -q 2>/dev/null
printf '#!/usr/bin/env bash\ncase "$1" in display) echo "t-seat-claude#1";; esac; exit 0\n' > "$T/fakebin/tmux"; chmod +x "$T/fakebin/tmux"
json="$(python3 -c 'import json,sys;print(json.dumps({"transcript_path":sys.argv[1],"cwd":sys.argv[2],"tool_name":"","tool_input":{}}))' "$T/t.jsonl" "$T/rep")"
printf '%s' "$json" | FT_THRESHOLDS="$TH" HOME="$T/home" PATH="$T/fakebin:$PATH" TMUX_PANE=%1 bash "$GATE" warn > "$T/o2" 2>"$T/e3"; rc=$?
{ [ $rc -eq 0 ] && grep -q '110k' "$T/o2" && grep -q '100k' "$T/o2"; } && ok "증류 게이트가 같은 문턱파일을 봄(경고선 100k)" || bad "게이트 rc=$rc out=$(head -c 200 "$T/o2") err=$(head -c 120 "$T/e3")"

printf 'FT_DISTILL_WARN=300000\nFT_DISTILL_BLOCK=200000\n' > "$T/bad.env"
FT_THRESHOLDS="$T/bad.env" "$BIN/ft-thresholds.sh" --export > "$T/o3" 2>&1; rc=$?
{ [ $rc -eq 2 ] && grep -q 'REJECT' "$T/o3"; } && ok "BLOCK<=WARN → REJECT rc2" || bad "검증 rc=$rc"
FT_THRESHOLDS="$T/bad.env" "$BIN/ft-thresholds.sh" --set FT_RESUME_MAX=abc > "$T/o4" 2>&1; rc=$?
{ [ $rc -eq 2 ] && grep -q 'ERROR\|REJECT' "$T/o4"; } && ok "정수 아닌 값 → REJECT rc2" || bad "정수검증 rc=$rc $(cat "$T/o4")"
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAIL=$fail"
exit "$fail"
