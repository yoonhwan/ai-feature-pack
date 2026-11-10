#!/usr/bin/env bash
# test_autonomy_hooks_mode_retry.sh — r1073: 자율 훅 3개의 ft-autonomy.sh mode/status 읽기 = 1회 상한(FT_AUTONOMY_HOOK_CAP_S · 기본 7) + 실패 1회 재시도 · 2회 실패는 원인 로그(하드 룰 12)
# 반례 R1~R5 는 인덱스 §반례 집합(동결) 그대로 — R1 첫 호출 상한 초과 후 통과 · R2 둘 다 실패 · R3 첫 호출 rc=1 후 통과 · R4 정상 = 호출 1 · R5 상한 env 비/글자 = 7.
# 격리: 임시 루트(FT_ROOT)·임시 상태·가짜 도구(FT_AUTONOMY_SH) — 실 ~/.claude·실 상태 파일·실 gh 0. 고정 sleep 0(잠들기는 가짜 도구 안 «주입»뿐).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_AUTONOMY_LEVEL=each   # r466: --level 생략 = full(범위 승인 + 슬랙 게시) — 이 시험은 레벨 밖이라 each(실 슬랙 0)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."; HK="$ROOT/harness/kit/fable-team/templates/hooks"; BIN="$ROOT/harness/bin"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:240}"; fail=$((fail+1)); fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
IH="$T/hooks"; mkdir -p "$IH" "$T/.fable-team" "$T/state" "$T/outside"
cp "$HK/autonomy-"*.sh "$ROOT/harness/kit/hooks/merge_cmd.py" "$IH"/   # r546: 설치 꼴(한 폴더) 재현
IG="$IH/autonomy-interview-gate.sh"; SG="$IH/autonomy-state-guard.sh"; MG="$IH/autonomy-merge-guard.sh"
S="$T/state"; LOG="$T/hook.log"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$S" FT_AUTONOMY_HOOK_LOG="$LOG" FT_AUTONOMY_HOOK_CAP_S=1
unset FT_HARNESS_ROOT FT_PLANNER_DIR CLAUDE_PROJECT_DIR

# 가짜 도구(r1073 시험 입력) — n번째 호출만 잠들기·rc 주입 · 그 뒤는 진짜 도구로 위임(exec = 남는 자식 0)
FA="$T/fake"; mkdir -p "$FA"; C="$FA/count"; A="$FA/args"
cat > "$FA/ft-autonomy.sh" <<'FAKEEOF'
#!/usr/bin/env bash
n=$(( $(cat "$FAKE_COUNT" 2>/dev/null || echo 0) + 1 ))
printf '%s' "$n" > "$FAKE_COUNT"
printf '%s\n' "$*" >> "$FAKE_ARGS"
case "${FAKE_MODE:-ok}:$n" in
  sleep1:1|sleepall:*) sleep "${FAKE_SLEEP:-2}";;   # 잠든 뒤엔 진짜 도구로 위임
  rc1:1) exit 1;;
esac
exec bash "${FAKE_REAL:?}" "$@"
FAKEEOF
chmod +x "$FA/ft-autonomy.sh"
export FAKE_COUNT="$C" FAKE_ARGS="$A" FAKE_REAL="$BIN/ft-autonomy.sh" FT_AUTONOMY_SH="$FA/ft-autonomy.sh"

a() { "$BASH" "$BIN/ft-autonomy.sh" "$@"; }        # 오빠 `!` 와 같은 호출(준비용 실 도구)
rst() { rm -f "$C" "$A"; : > "$LOG"; }             # 호출 계수·인자·로그 초기화
nc() { cat "$C" 2>/dev/null || echo 0; }
na() { wc -l < "$A" 2>/dev/null | tr -d ' ' || echo 0; }
mkbash() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}},ensure_ascii=False))' "$1" "${2:-$T}"; }
mkask() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"AskUserQuestion","cwd":sys.argv[2],"tool_input":{"questions":[{"question":sys.argv[1],"header":"","multiSelect":False,"options":[{"label":"a","description":"x"},{"label":"b","description":"y"}]}]}},ensure_ascii=False))' "$1" "${2:-$T}"; }
run() { out="$(printf '%s' "$2" | "$BASH" "$1" 2>"$T/err")"; rc=$?; }
al() { run "$1" "$2"; [ "$rc" = 0 ] && [ -z "$out" ]; ck "$3" $?; }
dn() { run "$1" "$2"; [ "$rc" = 0 ] && grep -q 'permissionDecision": "deny"' <<<"$out"; ck "$3" $?; }
lg() { grep -q "$1" "$LOG"; ck "$2" $?; }
nlg() { ! grep -q "$1" "$LOG"; ck "$2" $?; }

for f in "$IG" "$SG" "$MG"; do bash -n "$f" 2>/dev/null; ck "bash -n $(basename "$f")" $?; done

# 준비: 자율 ON + 오빠 승인 sha(approve-merge) — R1/R3/R4 의 «허용» 칸이 승인 sha 로 서게
H=1111111111111111111111111111111111111111
a on >/dev/null 2>&1; a approve-merge "$H" >/dev/null 2>&1
GH="gh pr merge 7 --match-head-commit $H"
HP="$T/plan-am.sh.hil"; HE="$T/h9999"
printf '#!/usr/bin/env bash\nset -euo pipefail\nbash "$FT_BIN/ft-autonomy.sh" approve-merge %s\n' "$H" > "$HP"
printf '#!/usr/bin/env bash\n# ft-hil-entry plan=%s\nP=%s; bash "$P"\n' "$HP" "$HP" > "$HE"

# ===== R1 첫 호출이 상한을 넘고 두 번째가 on → 허용 + 로그 «재시도 통과» 1줄 =====
export FAKE_MODE=sleep1 FAKE_SLEEP=2
rst; al "$MG" "$(mkbash "$GH")" "R1 merge-guard: 1회차 시간 초과 → 2회차 on → gh pr merge 허용"
[ "$(nc)" = 2 ]; ck "R1b merge-guard 호출 수 2(재시도 1회)" $?
lg 'mode 재시도 통과(1회차 시간 초과 1초)' "R1c merge-guard 로그 «재시도 통과(1회차 원인)» 1줄"
rst; al "$SG" "$(mkbash "bash $HE")" "R1d state-guard: 1회차 시간 초과 → 2회차 on → approve-merge h 허용"
[ "$(nc)" = 2 ]; ck "R1e state-guard 호출 수 2" $?
lg 'mode 재시도 통과(1회차 시간 초과 1초)' "R1f state-guard 로그 «재시도 통과»"
rst; dn "$IG" "$(mkask "고를까요?")" "R1g interview-gate: 1회차 시간 초과 → 2회차 on → deny(자율 ON)"
grep -q '\[자율 ON' <<<"$out"; ck "R1h interview-gate deny 사유 = 상태 1줄(ON 읽힘)" $?
lg 'mode 재시도 통과(1회차 시간 초과 1초)' "R1i interview-gate 로그 «재시도 통과»"

# ===== R3 첫 호출 rc=1, 두 번째 on → R1 과 같다 =====
export FAKE_MODE=rc1
rst; al "$MG" "$(mkbash "$GH")" "R3 merge-guard: 1회차 rc=1 → 2회차 on → 허용"
lg 'mode 재시도 통과(1회차 rc=1)' "R3b merge-guard 로그 원인 = rc=1"
rst; al "$SG" "$(mkbash "bash $HE")" "R3c state-guard: 1회차 rc=1 → 2회차 on → 허용"
rst; dn "$IG" "$(mkask "고를까요?")" "R3d interview-gate: 1회차 rc=1 → 2회차 on → deny(ON)"

# ===== R4 정상(첫 호출 on) → 재시도 0 =====
export FAKE_MODE=ok
rst; al "$MG" "$(mkbash "$GH")" "R4 merge-guard 정상 → 허용"
[ "$(nc)" = 1 ]; ck "R4b merge-guard 호출 수 1(재시도 0)" $?
nlg '재시도 통과' "R4c merge-guard 로그에 «재시도 통과» 0줄"
rst; al "$SG" "$(mkbash "bash $HE")" "R4d state-guard 정상 → 허용"
[ "$(nc)" = 1 ]; ck "R4e state-guard 호출 수 1" $?
rst; dn "$IG" "$(mkask "고를까요?")" "R4f interview-gate 정상(ON) → deny"
[ "$(na)" = 2 ] && [ "$(sed -n 1p "$A")" = mode ] && [ "$(sed -n 2p "$A")" = status ]; ck "R4g interview-gate 호출 2회(mode·status, 재시도 0)" $?

# ===== R2 두 호출 모두 상한 초과 → 지금 정책 그대로 + 로그 끝 «(시간 초과 N초 ×2)» =====
export FAKE_MODE=sleepall FAKE_SLEEP=2
rst; dn "$MG" "$(mkbash "$GH")" "R2 merge-guard: 둘 다 시간 초과 → deny(정책 그대로)"
[ "$(nc)" = 2 ] && grep -q '(시간 초과 1초 ×2)' "$LOG"; ck "R2b merge-guard 호출 2 + 로그 «(시간 초과 1초 ×2)»" $?
grep -q '못 읽음' "$LOG"; ck "R2c merge-guard «못 읽음» 로그 유지(R176)" $?
rst; dn "$SG" "$(mkbash "bash $HE")" "R2d state-guard: 둘 다 시간 초과 → approve-merge h deny"
[ "$(nc)" = 2 ] && grep -q '(시간 초과 1초 ×2)' "$LOG"; ck "R2e state-guard 호출 2 + 로그 원인" $?
rst; run "$IG" "$(mkask "고를까요?")"; [ "$rc" = 0 ] && ! grep -q permissionDecision <<<"$out" && grep -q 'systemMessage' <<<"$out"; ck "R2f interview-gate: 둘 다 시간 초과 → allow + 화면 경고" $?
[ "$(nc)" = 2 ] && grep -q '(시간 초과 1초 ×2)' "$LOG"; ck "R2g interview-gate 호출 2 + 로그 원인" $?
unset FAKE_SLEEP

# ===== R5 상한 env 가 비거나 글자 → 7 (잠들기 5.6초 < 7 이므로 1회에 통과해야 한다) =====
export FAKE_MODE=sleepall FAKE_SLEEP=5.6
for v in "" "abc"; do
  rst; export FT_AUTONOMY_HOOK_CAP_S="$v"
  al "$MG" "$(mkbash "$GH")" "R5 상한 env='$v' → 7 로 읽혀 1회차 통과(허용)"
  [ "$(nc)" = 1 ] && [ "$(na)" = 1 ]; ck "R5b 상한 env='$v' 호출 수 1(상한 7 · 잠들기 5.6초 안)" $?
  nlg '재시도 통과' "R5c 상한 env='$v' 재시도 0줄"
done
unset FAKE_SLEEP FAKE_MODE; export FT_AUTONOMY_HOOK_CAP_S=1

# ===== 변이 2 — ⓵ 재시도 끔 ⓶ 상한을 5로 되돌림(env 무시) → 둘 다 R1 칸이 빨강 =====
CPF="    cap, causes = hook_cap(), []\n"
for name in retry cap5; do
  MH="$T/mut-$name"; mkdir -p "$MH"; cp "$IH"/autonomy-*.sh "$IH/merge_cmd.py" "$MH"/
  python3 - "$IH/autonomy-merge-guard.sh" "$MH/autonomy-merge-guard.sh" "$name" <<'PY' || { echo "FAIL 변이 $name 못 만듦"; fail=$((fail+1)); }
import sys
src, dst, kind = sys.argv[1:4]
s = open(src, encoding="utf-8").read()
old_cap = """def hook_cap():   # r1073: 1회 상한 — FT_AUTONOMY_HOOK_CAP_S(기본 7 · 숫자 아니면 7 · 하드 룰 12)
    try:
        v = float(os.environ.get("FT_AUTONOMY_HOOK_CAP_S") or "")
    except (TypeError, ValueError):
        return 7.0
    return v if v > 0 else 7.0"""
if kind == "retry":
    assert s.count("    for _ in (1, 2):") == 1
    s = s.replace("    for _ in (1, 2):", "    for _ in (1,):")
else:
    assert s.count(old_cap) == 1, old_cap
    s = s.replace(old_cap, "def hook_cap():\n    return 5.0")
open(dst, "w", encoding="utf-8").write(s)
PY
  export FAKE_MODE=sleep1 FAKE_SLEEP=2
  rst; run "$MH/autonomy-merge-guard.sh" "$(mkbash "$GH")"
  red=0
  grep -q 'permissionDecision": "deny"' <<<"$out" && red=1                     # 재시도 끔 = 못 읽음 deny
  grep -q 'mode 재시도 통과' "$LOG" || red=$((red+1))                          # 상한 5 = 시간 초과 없음 → 재시도 로그 0
  [ "$red" -ge 1 ]; ck "R1변이($name) → R1 칸 빨강(허용 아님 또는 재시도 로그 0)" $?
done
unset FAKE_MODE FAKE_SLEEP

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
