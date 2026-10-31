#!/usr/bin/env bash
# test_test_run_reap_bg_r1234.sh — r1234: 시험 러너(ft-test-run.sh)가 끝난 시험의 프로세스 묶음 전체를 TERM → KILL 로 끝정리하고,
#   lint(ft-test-reentry-lint.sh)가 «& 로 띄운 자식 + trap kill 없음»(BGNOTRAP)·«timeout … & 에 -k 없음»(TIMEOUTNOK)을 rc3 으로 막는다.
#   R1~R3 = 러너(가짜 시험 3종 · 실 시험·실 좌석 kill 0) · R4~R6 = lint 새 패턴 · R7 = 옛 판정 그대로 · 변이 = 묶음 KILL 끔 → R1 FAIL
# 상한: 70초 안 · 자기 자신을 다시 부르지 않는다 · 고정 sleep 0(러너 안 폴링만) · 시험이 띄우는 자식은 자기 표지(R1234_MARK)로만 정리한다.
set -uo pipefail
[ -z "${FT_R1234_REENTRY:-}" ] || exit 0
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
RUN="$BIN/ft-test-run.sh"; LINT="$BIN/ft-test-reentry-lint.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1}» ≠ «${2}»"; }
rx()  { printf '%s' "$1" | grep -Eq -- "$2" && ok "$3" || bad "$3 — 패턴 없음: «${2}» ← ${1:0:300}"; }
T="$(cd "$(mktemp -d)" && pwd -P)"
export R1234_MARK="r1234-mark-$$-$RANDOM"
trap 'pkill -f -- "$R1234_MARK" 2>/dev/null; rm -rf "$T"' EXIT
mk() { sed -e 's/__AMP__/\&/g' -e 's/__O__/origin/g' > "$1"; }  # 표본 줄이 이 시험 자신의 lint 에 안 걸리게 글자를 치환해 쓴다

bash -n "$RUN" && ok "bash -n runner" || bad "bash -n runner"
bash -n "$LINT" && ok "bash -n lint" || bad "bash -n lint"
cmp -s "$RUN" "$KIT/ft-test-run.sh" && ok "키트 사본 cmp 0 runner" || bad "키트 사본 어긋남 runner"
cmp -s "$LINT" "$KIT/ft-test-reentry-lint.sh" && ok "키트 사본 cmp 0 lint" || bad "키트 사본 어긋남 lint"

# 가짜 시험 — 파일 이름에 .sh 를 붙이지 않는다(러너의 lint 단계가 시험 본체를 막지 않게 · 이 시험은 러너의 끝정리만 본다)
PY='import signal,time
signal.signal(signal.SIGTERM, signal.SIG_IGN)
for _ in range(900): time.sleep(0.1)'
export PY
mk "$T/fake_a" <<'EOF'
#!/usr/bin/env bash
python3 -c "$PY" "$R1234_MARK" >/dev/null 2>&1 __AMP__
exit 5
EOF
mk "$T/fake_b" <<'EOF'
#!/usr/bin/env bash
python3 -c "$PY" "$R1234_MARK" >/dev/null 2>&1 __AMP__
sleep 30
EOF
mk "$T/fake_c" <<'EOF'
#!/usr/bin/env bash
exit 7
EOF

# R1 ⓐ — TERM 무시 자식을 & 로 띄우고 kill 없이 끝남 → 러너 rc = 시험 rc(5) · 묶음 정리 줄 · 그 자식 0
r1_check() { # $1=러너 파일 — 전부 맞으면 0
  local rn="$1" rc c=0
  FT_TEST_TIMEOUT_SEC=20 bash "$rn" bash "$T/fake_a" > "$T/out_a" 2>&1; rc=$?
  [ "$rc" = 5 ] || { echo "r1 rc=$rc ≠ 5"; c=1; }
  grep -Eq '\[묶음 정리\] 남은 [1-9][0-9]* · TERM [1-9][0-9]* · KILL [1-9][0-9]* · 남은 묶음 0' "$T/out_a" || { echo "r1 묶음 정리 줄 없음 ← $(grep '묶음' "$T/out_a" | head -1)"; c=1; }
  pgrep -f -- "$R1234_MARK" >/dev/null && { echo "r1 자식이 ps 에 남음"; c=1; }
  return $c
}
r1_msg="$(r1_check "$RUN")" && ok "R1 TERM 무시 자식 · kill 없이 끝 → rc5 · 남은 묶음 0 · ps 자식 0" || bad "R1 ${r1_msg}"

# R2 ⓑ — 시험이 상한(2초) 넘김 + TERM 무시 자식 → rc124 · 상한+5초 안에 러너 끝 · 남은 묶음 0
SECONDS=0; FT_TEST_TIMEOUT_SEC=2 bash "$RUN" bash "$T/fake_b" > "$T/out_b" 2>&1; rc=$?; el=$SECONDS
eq "$rc" 124 "R2 상한 초과 rc124"
[ "$el" -le 10 ] && ok "R2 상한+5초 안에 끝(${el}초)" || bad "R2 너무 늦음 ${el}초"
rx "$(cat "$T/out_b")" '남은 묶음 0' "R2 남은 묶음 0"
pgrep -f -- "$R1234_MARK" >/dev/null && bad "R2 자식이 ps 에 남음" || ok "R2 ps 자식 0"

# R3 ⓒ — 자식 없음 → 남은 0 · 시험 rc 그대로(회귀)
bash "$RUN" bash "$T/fake_c" > "$T/out_c" 2>&1; rc=$?
eq "$rc" 7 "R3 자식 없음 rc7 그대로"
rx "$(cat "$T/out_c")" '\[묶음 정리\] 남은 0 · TERM 0 · KILL 0 · 남은 묶음 0' "R3 남은 0 줄"

# 변이 — 묶음 KILL 을 끈 러너(kill -KILL 줄을 :로) → R1 이 FAIL 해야 한다(시험이 변이를 잡는지)
sed 's/kill -KILL -- "-\$1" 2>\/dev\/null/:/' "$RUN" > "$T/run_mut.sh"
cmp -s "$RUN" "$T/run_mut.sh" && bad "변이 적용 안 됨(sed 가 줄을 못 찾음)" || ok "변이 적용됨"
FT_SEAT_QUIESCE_BIN="$BIN/ft-seat-quiesce.sh" FT_TEST_REENTRY_LINT_BIN="$LINT" r1_check "$T/run_mut.sh" > "$T/mut_msg" 2>&1 && bad "변이(KILL 끔)인데 R1 이 통과 — 시험이 변이를 못 잡음" || ok "변이 R1 FAIL(= 시험이 변이를 잡음)"
pkill -f -- "$R1234_MARK" 2>/dev/null

# R4 — timeout 70 … & (-k 없음) = TIMEOUTNOK rc3 · timeout -k 5 70 … & = OK
mk "$T/s4a.sh" <<'EOF'
#!/usr/bin/env bash
trap 'kill "$p"' EXIT
timeout 70 python3 x __AMP__
EOF
mk "$T/s4b.sh" <<'EOF'
#!/usr/bin/env bash
trap 'kill "$p"' EXIT
timeout -k 5 70 python3 x __AMP__
EOF
out="$("$LINT" "$T/s4a.sh" 2>/dev/null)"; rc=$?
eq "$rc" 3 "R4 timeout -k 없음 rc3"; eq "$(printf '%s' "$out" | head -1)" "TIMEOUTNOK $T/s4a.sh:3" "R4 첫 줄 = TIMEOUTNOK <파일>:<줄>"
out="$("$LINT" "$T/s4b.sh" 2>/dev/null)"; rc=$?
eq "$rc" 0 "R4 timeout -k 있음 rc0"; eq "$out" "OK $T/s4b.sh" "R4 출력 = OK <파일>"

# R5 — python3 srv.py & + trap 이 rm 만 = BGNOTRAP rc3 · trap kill 있음 = OK
mk "$T/s5a.sh" <<'EOF'
#!/usr/bin/env bash
trap 'rm -rf "$T"' EXIT
python3 srv.py __AMP__
EOF
mk "$T/s5b.sh" <<'EOF'
#!/usr/bin/env bash
trap 'kill "$p"' EXIT
python3 srv.py __AMP__
EOF
out="$("$LINT" "$T/s5a.sh" 2>/dev/null)"; rc=$?
eq "$rc" 3 "R5 trap 이 rm 만 rc3"; eq "$(printf '%s' "$out" | head -1)" "BGNOTRAP $T/s5a.sh:3" "R5 첫 줄 = BGNOTRAP <파일>:<줄>"
"$LINT" "$T/s5b.sh" >/dev/null 2>&1 && ok "R5 trap kill 있음 rc0" || bad "R5 trap kill 있는데 rc≠0"

# R6 — && · 주석 안 & · 문자열 안 & = 위반 0 · «# bg-ok: 이유» 꼬리 = 면제 1줄 rc0
mk "$T/s6.sh" <<'EOF'
#!/usr/bin/env bash
a && b
# python3 srv.py __AMP__
echo "a __AMP__"
EOF
mk "$T/s6x.sh" <<'EOF'
#!/usr/bin/env bash
python3 srv.py __AMP__ # bg-ok: 5초 안에 스스로 끝나는 서버
EOF
out="$("$LINT" "$T/s6.sh" 2>/dev/null)"; rc=$?
eq "$rc" 0 "R6 && · 주석 · 문자열 rc0"; eq "$out" "OK $T/s6.sh" "R6 위반 0 = OK"
out="$("$LINT" "$T/s6x.sh" 2>/dev/null)"; rc=$?
eq "$rc" 0 "R6 면제 꼬리 rc0"; eq "$(printf '%s' "$out" | head -1)" "면제 BGNOTRAP $T/s6x.sh:2 — 5초 안에 스스로 끝나는 서버" "R6 면제 1줄(첫 줄 · FLOATBASE 면제와 같은 꼴 — 뒤에 OK 줄)"
eq "$(printf '%s\n' "$out" | grep -c '^면제 ')" 1 "R6 면제 줄은 정확히 1개"

# R7 — 옛 판정 그대로(REENTRY·FLOATBASE 샘플) — 자세한 회귀는 test_test_reentry_lint.sh
mk "$T/s7a.sh" <<'EOF'
#!/usr/bin/env bash
bash "$0" --mutate
EOF
mk "$T/s7b.sh" <<'EOF'
#!/usr/bin/env bash
git -C . show __O__/main:a.txt > out.txt
EOF
out="$("$LINT" "$T/s7a.sh" 2>/dev/null)"; rc=$?
eq "$rc" 3 "R7 REENTRY rc3 그대로"; eq "$(printf '%s' "$out" | head -1)" "REENTRY $T/s7a.sh:2" "R7 REENTRY 줄"
out="$("$LINT" "$T/s7b.sh" 2>/dev/null)"; rc=$?
eq "$rc" 3 "R7 FLOATBASE rc3 그대로"; eq "$(printf '%s' "$out" | head -1)" "FLOATBASE $T/s7b.sh:2" "R7 FLOATBASE 줄"

echo "---"; [ "$fail" = 0 ] && echo "ALL PASS" || echo "FAIL $fail"
exit "$fail"
