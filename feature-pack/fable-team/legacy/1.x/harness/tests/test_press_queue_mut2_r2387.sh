#!/usr/bin/env bash
# test_press_queue_mut2_r2387.sh — r2387 변이 M5~M8: 계약이 깨지면 그 사례가 FAIL 하는가(변이 = 사본에서 글자 1곳 · 변이마다 원본으로 같은 사례 1회 더)
#   M5 꼬리 «남은 초 ≥ 8» 확인 지움 → ⑫ FAIL   M6 gh 재시도 지움 → ⑭ FAIL(호출 수)   M7 깨진 ref 에서 전체 중단 → ⑮ FAIL   M8 VALID 를 «앞» 에서만 봄(정정 전 규칙) → ⑩ FAIL
#   M5 는 ft-merge-land.sh(꼬리) 변이 · 틀 = _pushahead_r2368_fixture.sh + tail 시험의 PR·묶음 도우미 / M6~M8 = _press_queue_r2387_lib.sh
# 사용: timeout 70 bash <이 파일> → 마지막 줄 «== OK ==» · rc 0/1
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_press_queue_r2387_lib.sh"
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc el=${el:-0}s out=${out:0:700}"; fail=$((fail+1)); fi; }
S0=$SECONDS
qmut() { : > "$STUB_LOG"; out="$(bash "$1/ft-press-evidence.sh" queue --repo "$REPO" --main "${QMAIN:-origin/main}" 2>&1)"; rc=$?; }
mutfail() { local why="$1" want="$2"; qmut "$MBIN"
  if [ "$rc" = 0 ] && [[ "$out" == *"$want"* ]]; then echo "FAIL $why :: 변이가 기대와 같음 out=${out:0:200}"; fail=$((fail+1)); else echo "PASS $why"; fi; }
oksrc() { local why="$1" want="$2"; qmut "$BIN"
  if [ "$rc" = 0 ] && [[ "$out" == *"$want"* ]]; then echo "PASS $why"; else echo "FAIL $why :: 원본이 기대 못 냄 rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }

# ===== M6: gh 재시도 지움 → ⑭ FAIL(호출 수 1) =====
qreset; qm 141 pr141 10 worker/p141.py=p141
mut M6 verify '    for _ in (1, 2):
        try:
            p = subprocess.run(cmd, capture_output=True, text=True, timeout=secs, encoding="utf-8", errors="replace")' '    for _ in (1,):
        try:
            p = subprocess.run(cmd, capture_output=True, text=True, timeout=secs, encoding="utf-8", errors="replace")'
el=$SECONDS; GH_SLEEP=8 qmut "$MBIN"; n1="$(qgl)"; el=$((SECONDS - el))
[ "$el" -le 15 ] && [ "$n1" = 1 ] && [ "$rc" = 3 ]; ck "ⓜM6 gh 재시도 지움 → 호출 ${n1}회(2회여야) = ⑭ FAIL(계약 깨짐 재현)" $?
el=$SECONDS; GH_SLEEP=8 qmut "$BIN"; n2="$(qgl)"; el=$((SECONDS - el))
[ "$n2" = 2 ] && [ "$rc" = 3 ] && [ "$el" -le 15 ]; ck "ⓜM6 원본 재확인 → 호출 2회 · ${el}초(<15) = ⑭ 통과(같은 사례 1회 더)" $?
echo "단계 초: M6 $((SECONDS - S0))s"

# ===== M7: 깨진 ref 에서 전체 중단 → ⑮ FAIL =====
qreset
qm 111 pr111 40 worker/p111.py=p111
qm 112 pr112 30 worker/p112.py=p112
qm 113 pr113 20 worker/p113.py=p113
vbs "$(setof "$(sha "$REPO" pr111)")" 20261117-151000
vbs "$(setof "$(sha "$REPO" pr113)")" 20261117-150500
bks 0123456789abcdef0123456789abcdef01234567 20261117-150000
mut M7 verify '        except Reject as x:
            r = ("", "판정 불가", " · " + str(x))' '        except Reject as x:
            raise'
mutfail "ⓜM7 깨진 ref 에서 전체 중단 → 다른 줄(#111·#113)까지 사라짐 = ⑮ FAIL" "PR #111 VALID"
oksrc "ⓜM7 원본 재확인 → ⑮ 통과(깨진 묶음 = 그 줄만 판정 불가)" "PR #112 판정 불가"
unref refs/press/0123456789abcdef0123456789abcdef01234567-20261117-150000   # 깨진 묶음 = M7 몫(원격·로컬 둘 다 지운다 · queue 는 prune 0)
git -C "$REPO" update-ref -d refs/press/0123456789abcdef0123456789abcdef01234567-20261117-150000
echo "단계 초: M7 $((SECONDS - S0))s"

# ===== M8: VALID 를 «앞» 에서만 봄(정정 전 규칙) → ⑩ FAIL =====
qreset
qm 101 pr101 30 worker/p101.py=p101
qm 102 pr102 10 worker/p102.py=p102
vbs "$(setof "$(sha "$REPO" pr102)")" 20261117-152000
mut M8 verify '    valid = [r for r in rows if r[2] == "VALID"]' '    valid = [r for r in rows[:1] if r[2] == "VALID"]'
mutfail "ⓜM8 VALID 를 «앞» 에서만 봄 → ⑩ 의 «대기(VALID PR 102 …)» 0 = FAIL" "NEXT 대기(VALID PR 102 착지 뒤"
oksrc "ⓜM8 원본 재확인 → ⑩ 통과" "NEXT 대기(VALID PR 102 착지 뒤"
echo "단계 초: M8 $((SECONDS - S0))s"

# ===== M5: 꼬리 «남은 초 ≥ 8» 확인 지움 → ⑫ FAIL =====
FAIL9="$fail"   # 픽스처를 다시 source 하면 fail=0 으로 초기화된다(앞 사례 실패 수 보존)
. "$HERE/_pushahead_r2368_fixture.sh"
fail="$FAIL9"
T2="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T2"' EXIT
T="$T2"; pa_init "$T2"; pa_fix
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
echo "$*" >> "$STUB_LOG"
case "$1 $2" in "pr view") cat "$STUB_JSON";; "pr list") cat /dev/null;; esac
exit 0
EOF
chmod +x "$T/gh-stub"; export FT_GH="$T/gh-stub"
cat > "$FIX/ft-press-evidence.sh" <<EOF
#!/bin/bash
echo "PRESS \$1" >> "\$STUB_LOG"
case "\$1" in queue) exec bash "$BIN/ft-press-evidence.sh" "\$@";; esac
exit 0
EOF
chmod +x "$FIX/ft-press-evidence.sh"
mkdir -p "$W/docs/rules"; printf '# 목록\n## 목록\n- `worker/**`\n' > "$W/docs/rules/press_voice_paths.md"
git -C "$W" fetch -q origin; git -C "$W" checkout -q main 2>/dev/null || git -C "$W" checkout -q -b main origin/main
git -C "$W" add -A && git -C "$W" commit -q -m list; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
mkp() { local n="$1" f="worker/pr$1.py"; git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "pr$n" origin/main >/dev/null 2>&1
  mkdir -p "$(dirname "$W/$f")"; printf 'pr%s %s\n' "$n" "$SECONDS" > "$W/$f"
  git -C "$W" add -A && git -C "$W" commit -q -m "pr $n"; git -C "$W" push -q -f origin "pr$n:refs/pull/$n/head" >/dev/null 2>&1; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys
print(json.dumps({"headRefOid":sys.argv[1],"headRefName":"pr"+sys.argv[2],"isCrossRepository":False,"title":"feat: PR "+sys.argv[2],"body":"b","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$n" > "$STUB_JSON"; }
tl() { grep -c '^PRESS queue' "$STUB_LOG" 2>/dev/null || true; }
mkp 213; DL_OFF=10 FT_PUSH_FIXED_S=1 land "$FIX" 213 40
el=$((SECONDS - S0)); [ "$rc" = 0 ] && [ "$(tl)" = 0 ] && grep -q pressq <<<"$(ltail)"
ck "ⓜM5 준비: 원본 판 = ⑫ 통과(남은 초 < 8 → queue 부름 0 · pressq skip) · ${el}s" $?
MS="$T/mfix"; rm -rf "$MS"; cp -R "$FIX" "$MS"
python3 - "$MS/ft-merge-land.sh" <<'PY' || { echo "FAIL M5 변이 대상 없음"; fail=$((fail+1)); }
import io, sys
p = sys.argv[1]; s = io.open(p, encoding="utf-8").read()
a = 'if [ "$PQS" -lt 8 ] 2>/dev/null; then [ "$PQS" -lt 1 ] || ltk pressq; else'
assert s.count(a) == 1
io.open(p, "w", encoding="utf-8").write(s.replace(a, 'if false; then [ "$PQS" -lt 1 ] || ltk pressq; else'))
PY
mkp 214; DL_OFF=10 FT_PUSH_FIXED_S=1 land "$MS" 214 40
[ "$rc" = 0 ] && [ "$(tl)" -ge 1 ] && ! grep -q pressq <<<"$(ltail)"; M5R=$?; M5N="$(tl)"
ck "ⓜM5 꼬리 «남은 초 ≥ 8» 확인 지움 → 남은 초 0 에서도 queue 부름(${M5N}회) = ⑫ FAIL" "$M5R"

# ===== 격리 =====
[[ "$ORIGIN" == "$T/"* ]]; ck "격리: 원격 = 임시 bare 1개(실 원격·실 gh 0)" $?
echo "단계 초: M5 $((SECONDS - S0))s · 전체 $((SECONDS - S0))s"
echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
[ "$fail" = 0 ]
