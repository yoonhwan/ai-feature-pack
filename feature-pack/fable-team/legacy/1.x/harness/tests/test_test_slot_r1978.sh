#!/usr/bin/env bash
# test_test_slot_r1978.sh — r1978: ft-test-slot = 머신 시험 동시 상한 4(슬롯 4개 flock) · 대기 상한 넘으면 rc 75 · 명령 rc 그대로 · 죽어도 슬롯 풀림.
#   ① 6개 동시 → 최대 4 ② 4개 다 잡힘 + 대기 1초 → rc 75 · 실행 0 ③ rc 1 그대로 · 슬롯 풀림 ④ SIGKILL 뒤 풀림 → 다음 요청 잡음
#   변이 M1(슬롯 잠금 삭제 → ① FAIL) · M2(대기 상한 삭제 → ② FAIL) — 임시 슬롯 폴더 · 가짜 명령 · sleep 은 가짜 명령 안 0.1초만.
[ -n "${R1978_TEST_SLOT_TEST_GUARD:-}" ] && exit 0
export R1978_TEST_SLOT_TEST_GUARD=1
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TOOL="${FT_R1978_TOOL:-$HERE/../bin/ft-test-slot}"; KIT="$HERE/../kit/fable-team/bin/ft-test-slot"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
cat > "$T/fake.py" <<'EOF'
import sys, time
log = sys.argv[1]
open(log, "a").write(f"S {time.time_ns()}\n"); time.sleep(0.1); open(log, "a").write(f"E {time.time_ns()}\n")
EOF
peak() { python3 -c 'import sys
ev=sorted((int(t),k) for k,t in (l.split() for l in open(sys.argv[1])))
n=m=0
for t,k in ev: n+=1 if k=="S" else -1; m=max(m,n)
print(m)' "$1"; }
free4() { python3 -c 'import fcntl,os,sys
for i in range(4):
    fd=os.open(os.path.join(sys.argv[1],f"{i}.lock"),os.O_RDWR|os.O_CREAT); fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB); os.close(fd)' "$1" 2>/dev/null; }
held4() { python3 -c 'import fcntl,os,subprocess,sys
d=sys.argv[1]; os.makedirs(d,exist_ok=True); fds=[os.open(os.path.join(d,f"{i}.lock"),os.O_RDWR|os.O_CREAT) for i in range(4)]
[fcntl.flock(f,fcntl.LOCK_EX) for f in fds]
print(subprocess.run(sys.argv[2:],stderr=open(d+"/err","w"),timeout=5).returncode)' "$@" 2>/dev/null || echo TIMEOUT; }
case1() { local tool="$1" d="$T/s1-$2" log="$T/log1-$2"; : > "$log"
  for _ in 1 2 3 4 5 6; do FT_TEST_SLOT_DIR="$d" "$tool" python3 "$T/fake.py" "$log" & done; wait
  [ "$(grep -c '^E' "$log")" = 6 ] && echo "$(peak "$log")" || echo "ends=$(grep -c '^E' "$log")"; }
case2() { held4 "$T/s2-$2" env FT_TEST_SLOT_DIR="$T/s2-$2" FT_TEST_SLOT_WAIT=1 "$1" touch "$T/ran-$2"; }

k=0; for tool in "$TOOL" "$KIT"; do lbl="${tool#"$HERE"/../}"; k=$((k+1))
  [ -x "$tool" ] || { bad "$lbl 실행 파일 없음"; continue; }
  p="$(case1 "$tool" "$k")"; [ "$p" -le 4 ] 2>/dev/null && [ "$p" -ge 2 ] && ok "① $lbl 6개 동시 → 최대 $p(≤4)" || bad "① $lbl 최대 동시 = $p"
  rc="$(case2 "$tool" x)"; [ "$rc" = 75 ] && [ ! -e "$T/ran-x" ] && grep -q '슬롯 대기 초과' "$T/s2-x/err" \
    && ok "② $lbl 다 잡힘 → rc 75 · 실행 0 · 1줄" || bad "② $lbl rc=$rc ran=$([ -e "$T/ran-x" ] && echo y)"
  rm -rf "$T/s2-x" "$T/ran-x"
  FT_TEST_SLOT_DIR="$T/s3" "$tool" bash -c 'exit 1'; rc=$?
  [ "$rc" = 1 ] && free4 "$T/s3" && ok "③ $lbl rc 1 그대로 · 슬롯 풀림" || bad "③ $lbl rc=$rc"
  rc="$( (FT_TEST_SLOT_DIR="$T/s4$k" "$tool" bash -c 'kill -9 $$') 2>/dev/null; echo $?)"
  free4 "$T/s4$k" && FT_TEST_SLOT_DIR="$T/s4$k" FT_TEST_SLOT_WAIT=1 "$tool" true \
    && ok "④ $lbl SIGKILL(rc=$rc) 뒤 슬롯 풀림 · 다음 요청 잡음" || bad "④ $lbl SIGKILL 뒤 슬롯 묶임 rc=$rc"
done
cmp -s "$TOOL" "$KIT" && ok "bin·kit 사본 같음" || bad "bin·kit 사본 다름"
FT_TEST_SLOT_DIR="$T/s5" "$TOOL" 2>/dev/null; [ $? = 2 ] && ok "명령 없음 → rc 2" || bad "명령 없음 rc≠2"

if [ -x "$TOOL" ]; then
  sed 's/fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)/pass/' "$TOOL" > "$T/m1"; chmod +x "$T/m1"
  p="$(case1 "$T/m1" m1)"; [ "$p" -gt 4 ] 2>/dev/null && ok "M1 슬롯 잠금 삭제 → ① FAIL(최대 $p)" || bad "M1 살아남음(최대 $p)"
  sed 's/>= end:/>= end + 1e9:/' "$TOOL" > "$T/m2"; chmod +x "$T/m2"
  rc="$(case2 "$T/m2" m2)"; [ "$rc" != 75 ] && ok "M2 대기 상한 삭제 → ② FAIL(rc=$rc)" || bad "M2 살아남음"
fi
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
