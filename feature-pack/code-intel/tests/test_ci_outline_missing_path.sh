#!/usr/bin/env bash
# r1832 — ci outline: 없는 경로 = tilth 호출 0 · rc2(①①′④) · 정상(②) · 상한(③) · 바깥 조기 종료 뒤 자식 0(③′). 가짜 tilth · sleep 0.
#   실행: bash feature-pack/code-intel/tests/test_ci_outline_missing_path.sh   (CI_UNDER_TEST=<ci 경로> 로 다른 판 대조)
set -uo pipefail
[ -n "${EPOCHREALTIME:-}" ] || { echo "판정 불가: bash 5 이상 필요(EPOCHREALTIME)"; exit 2; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI="${CI_UNDER_TEST:-$HERE/../skill/scripts/ci}"
n=0; fail=0
ok()  { n=$((n+1)); echo "  ok   $1"; }
bad() { n=$((n+1)); fail=$((fail+1)); echo "  FAIL $1"; }
chk() { [ "$2" = "$3" ] && ok "$1 ($3)" || bad "$1 — 기대[$3] 얻음[$2]"; }
has() { case "$2" in *"$3"*) ok "$1";; *) bad "$1 — [$3] 없음: $(printf '%s' "$2" | head -2)";; esac; }
alive() { local s; s="$(ps -o stat= -p "$1" 2>/dev/null)"; [ -n "$s" ] && [ "${s#Z}" = "$s" ]; }   # 좀비 = 끝남
le() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a<=b)}'; }

SB="$(mktemp -d "${TMPDIR:-/tmp}/ci-outline.XXXXXX")"
cleanup() { local p; for p in $(cat "$SB"/pid 2>/dev/null); do kill -9 "$p" 2>/dev/null; done; rm -rf "$SB"; }
trap cleanup EXIT
mkdir -p "$SB/home" "$SB/dir"; echo 'def f(): pass' > "$SB/a.py"; mkfifo "$SB/fifo"
cat > "$SB/tilth" <<'FAKE'
#!/usr/bin/env bash
# 가짜 tilth — 인자 기록 · FAKE_TILTH: ok(즉시 출력) · hang(무한 read) · fifo(FIFO 읽기 대기)
echo "$#:$*" >> "$FAKE_LOG"; echo $$ >> "$FAKE_PID"
case "${FAKE_TILTH:-ok}" in
  ok)   echo "FAKE_OUTLINE $1" ;;
  hang) read -r _ <> "$FAKE_FIFO" ;;
  fifo) read -r _ < "$FAKE_FIFO" ;;
esac
FAKE
chmod +x "$SB/tilth"
E=(env HOME="$SB/home" TILTH_BIN="$SB/tilth" FAKE_LOG="$SB/log" FAKE_PID="$SB/pid" FAKE_FIFO="$SB/fifo" CI_TIMEOUT=3)

run() { # run <tilth 꼴> <ci 인자…> → OUT · ERR · RC · LOG
  local mode="$1"; shift; : > "$SB/log"
  OUT="$("${E[@]}" FAKE_TILTH="$mode" bash "$CI" outline "$@" 2>"$SB/err")"; RC=$?
  ERR="$(cat "$SB/err")"; LOG="$(cat "$SB/log")"
}
missing() { # missing <이름> <ci 인자…>
  local t="$1"; shift; run ok "$@"
  chk "$t rc" "$RC" "2"
  chk "$t stderr «파일 없음» 1줄" "$(printf '%s\n' "$ERR" | grep -c '^\[ci\] 파일 없음: ')" "1"
  chk "$t tilth 호출 0" "$(printf '%s' "$LOG" | grep -c .)" "0"
}

echo "== ① 없는 경로 =="; missing "①" "$SB/nope_xyz.py"
echo "== ①′ 없는 경로 + --section =="; missing "①′" "$SB/nope_xyz.py" --section 1-10
echo "== ④ 폴더 경로 =="; missing "④" "$SB/dir"
echo "== ② 있는 파일 · 즉시 끝남 =="; run ok "$SB/a.py"
chk "② rc" "$RC" "0"
chk "② 출력 그대로" "$OUT" "FAKE_OUTLINE $SB/a.py"
chk "② 인자 = 경로 1개" "$LOG" "1:$SB/a.py"

echo "== ③ 있는 파일 · 멈춤 · CI_OUTLINE_TIMEOUT=1 =="; : > "$SB/pid"
t0=$EPOCHREALTIME
timeout 5 "${E[@]}" FAKE_TILTH=hang CI_OUTLINE_TIMEOUT=1 bash "$CI" outline "$SB/a.py" >"$SB/out" 2>"$SB/err"; RC=$?
dt="$(awk -v a="$t0" -v b="$EPOCHREALTIME" 'BEGIN{printf "%.3f", b-a}')"
chk "③ rc" "$RC" "124"
le "$dt" 2 && ok "③ 2초 안 (${dt}초)" || bad "③ 2초 안 — 얻음 ${dt}초"
chk "③ [timeout] 안내 1줄" "$(grep -c '^\[timeout\]' "$SB/err")" "1"
p="$(head -1 "$SB/pid")"; [ -n "$p" ] && ! alive "$p" && ok "③ 가짜 tilth 생존 0" || bad "③ 가짜 tilth 생존(pid ${p:-없음})"

echo "== ③′ 바깥 timeout 1 · 안 상한 3초 · | cat =="; : > "$SB/pid"
t0=$EPOCHREALTIME
timeout 1 "${E[@]}" FAKE_TILTH=fifo CI_OUTLINE_TIMEOUT=3 bash "$CI" outline "$SB/a.py" 2>/dev/null | cat >/dev/null
RCS=("${PIPESTATUS[@]}")
dt="$(awk -v a="$t0" -v b="$EPOCHREALTIME" 'BEGIN{printf "%.3f", b-a}')"
chk "③′ 바깥 rc" "${RCS[0]}" "124"
le "$dt" 1.5 && ok "③′ pipe 닫힘 ≤1.5초 (${dt}초)" || bad "③′ pipe 닫힘 ≤1.5초 — 얻음 ${dt}초"
p="$(head -1 "$SB/pid")"; [ -n "$p" ] && ! alive "$p" && ok "③′ 가짜 tilth 생존 0" || bad "③′ 가짜 tilth 생존(pid ${p:-없음})"

echo "== 결과: $((n-fail))/$n 통과 =="
[ "$fail" -eq 0 ]
