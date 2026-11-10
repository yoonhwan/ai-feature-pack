#!/usr/bin/env bash
# test_fake_resource_env.sh — R218 가짜 센서 헬퍼(lib/fake_resource_env.sh · tests/scripts/fake_resource_env.py)가
# 문지기를 «무력화하지 않고» 값만 바꾸는지 본다. 실 측정·실 동결 파일·실 tmux 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1   # R201: 시험은 추적 사본 원본을 직접 부른다(LIVE_BIN 으로 넘기지 않음)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
GATE="$REPO/harness/bin/ft-resource-gate.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
REAL_STATE="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir | sed 's|/\.git$||')/.fable-team/state"
frozen_before=0; [ -e "$REAL_STATE/RESOURCE_FREEZE" ] && frozen_before=1

# ⓐ ok 모드 — 실 문지기 rc0
OUT="$(env -u GIT_DIR bash -c 'source "$1"; fake_resource_env "$2" ok; bash "$3" check' _ "$HERE/lib/fake_resource_env.sh" "$T/ok" "$GATE" 2>&1)"; RC=$?
{ [ "$RC" -eq 0 ] && echo "$OUT" | grep -q '^OK .*level=1 .*agents=35'; } && ok "ⓐ ok 모드 → 실 gate check rc0" || bad "ⓐ rc=$RC $OUT"

# ⓑ reject 모드 — 문지기가 여전히 막는다(헬퍼가 문지기를 무력화하지 않음)
OUT="$(env -u GIT_DIR bash -c 'source "$1"; fake_resource_env "$2" reject; bash "$3" check' _ "$HERE/lib/fake_resource_env.sh" "$T/rej" "$GATE" 2>&1)"; RC=$?
{ [ "$RC" -ne 0 ] && echo "$OUT" | grep -q '^REJECT resource level=4'; } && ok "ⓑ reject 모드 → rc≠0 + REJECT 줄" || bad "ⓑ rc=$RC $OUT"
OUT="$(env -u GIT_DIR bash -c 'source "$1"; fake_resource_env "$2" reject; bash "$3" check --succession' _ "$HERE/lib/fake_resource_env.sh" "$T/rej2" "$GATE" 2>&1)"; RC=$?
{ [ "$RC" -ne 0 ] && echo "$OUT" | grep -q '^REJECT resource level=4'; } && ok "ⓑ reject 모드 승계 점검도 REJECT" || bad "ⓑ(승계) rc=$RC $OUT"

# ⓒ 가짜 pgrep — `-a -x claude` 외 인자는 진짜 pgrep 으로(이 셸의 PID 를 정확히 찾는다)
OUT="$(bash -c 'source "$1"; fake_resource_env "$2" ok; sleep 30 & p=$!; pgrep -f "sleep 30" | grep -qx "$p"; r=$?; kill $p; wait $p 2>/dev/null; exit $r' _ "$HERE/lib/fake_resource_env.sh" "$T/pg" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && ok "ⓒ 가짜 pgrep 이 그 밖의 인자를 진짜 pgrep 에 넘김" || bad "ⓒ rc=$RC $OUT"
OUT="$(bash -c 'source "$1"; fake_resource_env "$2" ok; pgrep -a -x claude | wc -l | tr -d " "' _ "$HERE/lib/fake_resource_env.sh" "$T/pg2" 2>&1)"
[ "$OUT" = 35 ] && ok "ⓒ -a -x claude 는 가짜 수(35)" || bad "ⓒ(가짜 수) $OUT"

# ⓓ 실 .fable-team/state 쓰기 0 — 표본은 임시 FT_RES_ROOT 에만, 실 RESOURCE_FREEZE 는 그대로
[ -s "$T/rej/resroot/.fable-team/state/pressure.tsv" ] && ok "ⓓ 표본은 임시 FT_RES_ROOT 에 기록" || bad "ⓓ 임시 pressure.tsv 없음"
frozen_after=0; [ -e "$REAL_STATE/RESOURCE_FREEZE" ] && frozen_after=1
[ "$frozen_before" = "$frozen_after" ] && ok "ⓓ 실 RESOURCE_FREEZE 변화 0" || bad "ⓓ 실 RESOURCE_FREEZE 가 바뀜 $frozen_before→$frozen_after"

# ⓔ 문턱 env 10개를 «막는 값» 으로 export 한 셸에서도 같다 — 헬퍼가 문턱 env 를 지운다
BLOCK='export FT_AGENT_MAX=1 FT_DISK_MIN_GIB=99999 FT_MEM_FREE_MIN_PCT=99 FT_MEM_FREE_MIN_SUCC=99 FT_PRESSURE_MAX=0 FT_PRESSURE_MAX_SUCC=0 FT_SWAP_HARD_MIB=1 FT_SWAP_MAX_MIB=1 FT_SWAP_RATE_MAX=0 FT_SWAP_RATE_MAX_SUCC=0'
OUT="$(env -u GIT_DIR bash -c "$BLOCK"'; source "$1"; fake_resource_env "$2" ok; bash "$3" check' _ "$HERE/lib/fake_resource_env.sh" "$T/blk-ok" "$GATE" 2>&1)"; RC=$?
{ [ "$RC" -eq 0 ] && echo "$OUT" | grep -q '^OK '; } && ok "ⓔ 문턱 env 막는 값 + ok 모드 → rc0" || bad "ⓔ ok rc=$RC $OUT"
OUT="$(env -u GIT_DIR bash -c "$BLOCK"'; source "$1"; fake_resource_env "$2" reject; bash "$3" check' _ "$HERE/lib/fake_resource_env.sh" "$T/blk-rej" "$GATE" 2>&1)"; RC=$?
{ [ "$RC" -ne 0 ] && echo "$OUT" | grep -q '^REJECT resource level=4'; } && ok "ⓔ 문턱 env 막는 값 + reject 모드 → rc≠0 + level=4 REJECT" || bad "ⓔ reject rc=$RC $OUT"

# ⓕ 파이썬 판 — 같은 값(ok rc0 · reject rc≠0)
for m in ok reject; do
  OUT="$(env -u GIT_DIR python3 -I -c '
import subprocess, sys
sys.path.insert(0, sys.argv[1])
from pathlib import Path
from fake_resource_env import fake_resource_env
e = fake_resource_env(Path(sys.argv[2]), sys.argv[3])
r = subprocess.run(["bash", sys.argv[4], "check"], env=e, capture_output=True, text=True)
print(r.returncode, r.stdout.strip())' "$HERE/scripts" "$T/py-$m" "$m" "$GATE" 2>&1)"
  case "$m" in
    ok) echo "$OUT" | grep -q '^0 OK .*level=1' && ok "ⓕ 파이썬 판 ok → rc0" || bad "ⓕ ok $OUT";;
    reject) echo "$OUT" | grep -Eq '^[1-9][0-9]* REJECT resource level=4' && ok "ⓕ 파이썬 판 reject → REJECT" || bad "ⓕ reject $OUT";;
  esac
done

bash -n "$HERE/lib/fake_resource_env.sh" && ok "bash -n 헬퍼" || bad "bash -n 헬퍼"
[ "$(wc -l < "$HERE/lib/fake_resource_env.sh" | tr -d ' ')" -le 60 ] && ok "헬퍼 ≤60줄" || bad "헬퍼 줄 수"
[ "$(git -C "$REPO" config --get core.bare)" = false ] && ok "core.bare=false" || bad "core.bare"
echo "fail=$fail"; [ $fail -eq 0 ]
