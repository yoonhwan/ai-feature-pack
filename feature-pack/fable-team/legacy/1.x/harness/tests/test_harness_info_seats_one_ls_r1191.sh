#!/usr/bin/env bash
# test_harness_info_seats_one_ls_r1191.sh — ft-harness-info.sh seats 의 «팀 명부» 열림 셈 = tmux ls 1회 집합(행마다 has-session 0).
# 반례 R1~R4(카드 r1191 동결) · 변이 1(행마다 has-session 되살림 → 호출 305 = FAIL 이어야 함). 가짜 tmux · 임시 루트만(실 tmux·실 명부 0).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
t0=$(date +%s)

T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
# 가짜 tmux: ls = 고정 이름 3개(FAKE_LS_RC=1 이면 서버 없음 rc1) · has-session = 호출 수를 파일에 적고 rc1
mkdir -p "$T/fake"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  ls) [ "${FAKE_LS_RC:-0}" = 1 ] && exit 1; printf 'byz-a-master-claude#1\nbyz-a-nano-x#0\nbyz-b-master-claude#2\n' ;;
  has-session) echo 1 >> "$FAKE_HS_LOG"; exit 1 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$T/fake/tmux"
printf '#!/usr/bin/env bash\necho ALIVE\n' > "$T/fake/alive.sh"

# 임시 루트: seats-a 300행(2개 열림) · seats-b 5행(1개 열림) · seats-c 깨짐
R="$T/root"; mkdir -p "$R/.fable-team"; git -C "$R" init -q
python3 -I - "$R/.fable-team" <<'PY'
import json, sys
d = sys.argv[1]
a = {"_master": "byz-a-master-claude#1", "_arch": "-", "_hil_route": "-"}
a.update({"byz-a-old-%d#0" % i: {"role": "nano"} for i in range(298)})
a["byz-a-master-claude#1"] = {"role": "master"}; a["byz-a-nano-x#0"] = {"role": "nano"}
b = {"_master": "byz-b-master-claude#2"}
b.update({"byz-b-old-%d#0" % i: {"role": "nano"} for i in range(4)})
b["byz-b-master-claude#2"] = {"role": "master"}
json.dump(a, open(d + "/seats-a.json", "w")); json.dump(b, open(d + "/seats-b.json", "w"))
open(d + "/seats-c.json", "w").write("{깨짐")
PY

# run_seats <스크립트> <ls rc> → $OUT · $RC · $HS(has-session 호출 수)
run_seats() {
  : > "$T/hs.log"
  OUT="$(cd "$R" && PATH="$T/fake:$PATH" FAKE_HS_LOG="$T/hs.log" FAKE_LS_RC="$2" FT_AGENT_ALIVE_BIN="$T/fake/alive.sh" bash "$1" seats 2>&1)"; RC=$?
  HS=$(wc -l < "$T/hs.log" | tr -d ' ')
}

# check <스크립트> → 반례 R1~R4 실패 수(출력은 ok/bad 줄)
check() {
  local s="$1" n0=$fail
  run_seats "$s" 0
  echo "$OUT" | grep -qx 'seats-a.json master=byz-a-master-claude#1 arch=- hil=- 좌석=300 열림=2' && ok "R1 seats-a 좌석=300 열림=2" || bad "R1 seats-a: $(echo "$OUT" | grep seats-a)"
  [ "$HS" -eq 0 ] && ok "R1 has-session 호출 0" || bad "R1 has-session 호출 $HS"
  echo "$OUT" | grep -qx 'seats-b.json master=byz-b-master-claude#2 arch=- hil=- 좌석=5 열림=1' && ok "R2 seats-b 좌석=5 열림=1" || bad "R2 seats-b: $(echo "$OUT" | grep seats-b)"
  echo "$OUT" | grep -qx 'ERR seats-c.json 파싱 실패' && ok "R3 깨진 명부 ERR 줄" || bad "R3: $(echo "$OUT" | grep seats-c)"
  [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" -eq 7 ] && ok "rc0 · 줄 수 = 세션 3 + 명부 3 + 1" || bad "rc=$RC 줄 수: $(printf '%s\n' "$OUT" | wc -l)"
  run_seats "$s" 1
  [ "$RC" -eq 0 ] && ok "R4 tmux 서버 없음 rc0" || bad "R4 rc=$RC"
  [ "$(printf '%s\n' "$OUT" | grep -c 'PASS\|REJECT')" -eq 0 ] && ok "R4 세션 줄 0" || bad "R4 세션 줄: $OUT"
  [ "$(printf '%s\n' "$OUT" | grep -c '좌석=.* 열림=0$')" -eq 2 ] && ok "R4 명부 열림=0" || bad "R4 명부: $OUT"
  return $((fail - n0))
}

bash -n "$BIN/ft-harness-info.sh" && ok "bash -n" || bad "bash -n"
check "$BIN/ft-harness-info.sh"
t1=$(date +%s)

# 변이: 행마다 has-session 되살림 → R1 이 FAIL 이어야 시험이 살아 있다
cp -R "$BIN" "$T/mbin"
python3 -I - "$T/mbin/ft-harness-info.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = "up = sum(1 for k in rows if k in live)"
new = 'up = sum(1 for k in rows if __import__("subprocess").run(["tmux", "has-session", "-t", "=" + k], capture_output=True).returncode == 0)'
assert old in s, "변이 자리 없음"
open(p, "w").write(s.replace(old, new))
PY
mfail=$fail
check "$T/mbin/ft-harness-info.sh" >/dev/null; mrc=$?
fail=$mfail
run_seats "$T/mbin/ft-harness-info.sh" 0
[ "$mrc" -gt 0 ] && [ "$HS" -eq 305 ] && ok "변이(행마다 has-session) → FAIL $mrc 건 · 호출 $HS" || bad "변이가 살아남음 mrc=$mrc 호출=$HS"
t2=$(date +%s)

echo "단계 초: 반례 $((t1 - t0))s · 변이 $((t2 - t1))s"
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "fail=$fail"
exit "$fail"
