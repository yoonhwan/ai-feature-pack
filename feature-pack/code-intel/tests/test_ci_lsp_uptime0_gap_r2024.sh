#!/usr/bin/env bash
# r2024 — Uptime 0s «2회 연속» 은 stamp 나이 2초(CI_LSP_UPTIME0_MIN_GAP) 이상일 때만 센다. 실 probe·실 캐시·실 데몬 0 · sleep 0.
#   실행: bash feature-pack/code-intel/tests/test_ci_lsp_uptime0_gap_r2024.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI="$HERE/../skill/scripts/ci"
n=0; fail=0
ok()  { n=$((n+1)); echo "  ok   $1"; }
bad() { n=$((n+1)); fail=$((fail+1)); echo "  FAIL $1"; }
chk() { [ "$2" = "$3" ] && ok "$1 ($3)" || bad "$1 — 기대[$3] 얻음[$2]"; }
has() { case "$2" in *"$3"*) ok "$1";; *) bad "$1 — [$3] 없음: $(printf '%s' "$2" | head -2)";; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 — [$3] 있으면 안 됨";; *) ok "$1";; esac; }
command -v timeout >/dev/null 2>&1 || { echo "SKIP: GNU timeout 없음"; exit 0; }

SB="$(mktemp -d "${TMPDIR:-/tmp}/ci-up0-gap.XXXXXX")"; trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/home" "$SB/tmp"
ST="$SB/tmp/ci-lsp-uptime0.$(id -u)"
cat > "$SB/probe" <<'FAKE'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "lsp status") # FAKE_CHAIN = 첫 호출만 바로 답 · 나머지는 첫 호출의 stamp 가 생긴 뒤 답(같은 데몬의 0s 를 뒤이어 봄 · 상한 = refs 바깥 상한)
                if [ -n "${FAKE_CHAIN:-}" ] && ! mkdir "$FAKE_CHAIN" 2>/dev/null; then while [ ! -s "$FAKE_ST" ]; do :; done; fi
                echo "  Uptime: ${FAKE_UPTIME:-120s}" ;;
  "lsp call")   echo "FAKE_REFERENCES 16" ;;
esac
exit 0
FAKE
chmod +x "$SB/probe"
refs() { # $1 = Uptime 값
  HOME="$SB/home" TMPDIR="$SB/tmp" PROBE_BIN="$SB/probe" FAKE_UPTIME="$1" PROBE_LSP_CRASH_LOG="$SB/crash.log" \
    CI_REFS_TIMEOUT=20 bash "$CI" refs "a.py#f" 2>&1; }
stamp_ago() { echo $(( $(date +%s) - $1 )) > "$ST"; }   # $1 = stamp 나이(초)

echo "== ① stamp 나이 0초 + Uptime 0s → crash-loop 아님 =="
stamp_ago 0
out="$(refs 0s)"; rc=$?
chk "① rc" "$rc" "0"
hasnt "① crash-loop 줄 없음" "$out" "crash-loop"
echo "== ② 하한 미만이면 stamp 값 그대로 (하한 60초 · 나이 10초 = 다시 쓰면 값이 바뀜) =="
stamp_ago 10; before="$(cat "$ST")"; out="$(CI_LSP_UPTIME0_MIN_GAP=60 refs 0s)"; chk "② rc" "$?" "0"
chk "② stamp 값" "$(cat "$ST" 2>/dev/null)" "$before"

echo "== ③ stamp 없음 + 0s 에서 refs 4개 동시 → rc3 0건 =="
rm -f "$ST"
export FAKE_CHAIN="$SB/chain" FAKE_ST="$ST"
for i in 1 2 3 4; do ( refs 0s > "$SB/p$i.out"; echo $? > "$SB/p$i.rc" ) & done; wait
unset FAKE_CHAIN
chk "③ rc3 건수" "$(cat "$SB"/p[1-4].rc | grep -c '^3$')" "0"
chk "③ rc0 건수" "$(cat "$SB"/p[1-4].rc | grep -c '^0$')" "4"

echo "== ④ stamp 나이 3초 + 0s → «Uptime 0s 2회 연속» rc3 =="
stamp_ago 3; out="$(refs 0s)"; rc=$?
chk "④ rc" "$rc" "3"
has "④ 판정 줄" "$out" "판정 불가 LSP 데몬 crash-loop — ci lsp repair (Uptime 0s 2회 연속)"

echo "== ⑤ crash 기록 창 안 2건 → crash-loop (stamp 무관) =="
rm -f "$ST"; t="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
printf 'timestamp: %s\nmessage: %s\ntimestamp: %s\nmessage: %s\n' "$t" "couldn't read enough data" "$t" "couldn't read enough data" > "$SB/crash.log"
out="$(refs 5s)"; rc=$?
chk "⑤ rc" "$rc" "3"
has "⑤ crash 기록 판정" "$out" "창 안 2 회"
rm -f "$SB/crash.log"

echo "== ⑥ stamp 나이 200초 + 0s → 아님 · stamp 새 값 =="
stamp_ago 200; old="$(cat "$ST")"
out="$(refs 0s)"; rc=$?
chk "⑥ rc" "$rc" "0"
chk "⑥ stamp 새로 씀" "$([ "$(cat "$ST" 2>/dev/null || echo 0)" -gt "$old" ] && echo yes || echo no)" "yes"

echo "== ⑦ Uptime 5s → 아님 · stamp 삭제 =="
stamp_ago 3; out="$(refs 5s)"; rc=$?
chk "⑦ rc" "$rc" "0"
chk "⑦ stamp 삭제" "$([ -e "$ST" ] && echo yes || echo no)" "no"
has "⑦ 참조 결과 그대로" "$out" "FAKE_REFERENCES 16"

echo "== 결과: $((n - fail))/$n 통과 =="
[ "$fail" -eq 0 ]
