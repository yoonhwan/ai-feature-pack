#!/usr/bin/env bash
# r2186 — ci 가 probe 를 부를 때 PROBE_LSP_DB_DISABLE_MVCC=1(L1) · repair 의 Uptime 다시 보기(L2) · repair 상한(L4).
#   대역 = 가짜 probe(받은 환경·인자 기록 · Uptime 순서 주입 · 가짜 시계) + 가짜 timeout·sleep + tmp HOME · TMPDIR.
#   실 probe·실 캐시·실 데몬·외부 호출 0 · 실제 기다림 0(CI_LSP_REPAIR_WAIT=0 · 가짜 sleep).
#   실행: bash feature-pack/code-intel/tests/test_ci_lsp_mvcc_off_repair_wait_r2186.sh  (CI_UNDER_TEST=<ci 사본> 으로 다른 판)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI="${CI_UNDER_TEST:-$HERE/../skill/scripts/ci}"
n=0; fail=0
ok()  { n=$((n+1)); echo "  ok   $1"; }
bad() { n=$((n+1)); fail=$((fail+1)); echo "  FAIL $1"; }
chk() { [ "$2" = "$3" ] && ok "$1 ($3)" || bad "$1 — 기대[$3] 얻음[$2]"; }
has() { case "$2" in *"$3"*) ok "$1";; *) bad "$1 — [$3] 없음: $(printf '%s' "$2" | head -2)";; esac; }
cnt() { grep -c -- "$2" "$1" 2>/dev/null | tr -d ' '; }   # $1=파일 $2=무늬 → 줄 수

SB=""
mk() { # 새 샌드박스: home/tmp · 워크스페이스 1개(cache.db-log) · 가짜 probe · 가짜 timeout·sleep(bin)
  [ -n "$SB" ] && rm -rf "$SB"
  SB="$(mktemp -d "${TMPDIR:-/tmp}/ci-r2186.XXXXXX")"
  ws="$SB/home/Library/Caches/probe/lsp/workspaces"
  mkdir -p "$ws/ws_a" "$SB/tmp" "$SB/bin"
  : > "$ws/ws_a/cache.db-log"; echo 0 > "$SB/clock"; : > "$SB/probe.log"; : > "$SB/to.log"; : > "$SB/sleep.log"
  cat > "$SB/probe" <<'FAKE'
#!/usr/bin/env bash
echo "D=${PROBE_LSP_DB_DISABLE_MVCC-unset} E=${PROBE_LSP_DB_ENABLE_MVCC-unset} ARGS: $*" >> "$FAKE_DIR/probe.log"
[ -n "${FAKE_STEP:-}" ] && echo $(( $(cat "$FAKE_DIR/clock") + FAKE_STEP )) > "$FAKE_DIR/clock"   # 가짜 시계 앞으로
case "$1" in
  --version) echo "probe 0.6.0-fake" ;;
  search)    echo "smoke-ok" ;;
  lsp) shift; case "${1:-status}" in
         status) i=$(( $(cat "$FAKE_DIR/st.n" 2>/dev/null || echo 0) + 1 )); echo "$i" > "$FAKE_DIR/st.n"
                 set -- ${FAKE_UPTIMES:-120s}; up="${!i:-${!#}}"; [ "$up" = "-" ] && up=""
                 printf 'LSP Daemon Status\n  Status: Connected\n'; [ -n "$up" ] && printf '  Uptime: %s\n' "$up" ;;
         call)   echo "FAKE_REFERENCES 1" ;;
       esac ;;
esac
exit 0
FAKE
  cat > "$SB/bin/timeout" <<'FAKE'
#!/usr/bin/env bash
echo "TO $*" >> "$FAKE_DIR/to.log"
case " $* " in *" lsp status "*) [ "${FAKE_TO_124:-}" = status ] && exit 124 ;; esac
shift; exec "$@"
FAKE
  printf '#!/usr/bin/env bash\necho "SLEEP $*" >> "$FAKE_DIR/sleep.log"\n' > "$SB/bin/sleep"
  chmod +x "$SB/probe" "$SB/bin/timeout" "$SB/bin/sleep"
}
run_ci() { # 부른 쪽 MVCC 값은 unset 으로 시작 · ③ ④ 은 MV_ENABLE / MV_DISABLE 로 준다(빈 값도 «준 값»)
  ( unset PROBE_LSP_DB_DISABLE_MVCC PROBE_LSP_DB_ENABLE_MVCC
    [ -n "${MV_ENABLE+x}" ] && export PROBE_LSP_DB_ENABLE_MVCC="$MV_ENABLE"
    [ -n "${MV_DISABLE+x}" ] && export PROBE_LSP_DB_DISABLE_MVCC="$MV_DISABLE"
    export HOME="$SB/home" TMPDIR="$SB/tmp" PROBE_BIN="$SB/probe" FAKE_DIR="$SB" CI_TIMEOUT=10
    bash "$CI" "$@" 2>&1 ); }
run_rp() { # repair = 가짜 timeout·sleep 가 PATH 앞 · 기다림 0 · 가짜 시계
  PATH="$SB/bin:$PATH" CI_LSP_REPAIR_WAIT=0 CI_LSP_REPAIR_NOW_CMD="cat $SB/clock" run_ci lsp repair; }
all_d() { # $1=이름 → 가짜 probe 가 받은 모든 호출에 D=1
  local a d; a="$(cnt "$SB/probe.log" 'ARGS:')"; d="$(cnt "$SB/probe.log" '^D=1 ')"
  chk "$1 — probe 호출 모두 DISABLE=1 (호출 $a)" "$([ "$a" -gt 0 ] && [ "$a" = "$d" ] && echo yes || echo "no:$d/$a")" "yes"; }

echo "== ② L1 — status · doctor · refs · search 가 probe 에 PROBE_LSP_DB_DISABLE_MVCC=1 =="
for v in "lsp status" "doctor" "refs a.py:1:1" "search foo ."; do
  mk; ( cd "$SB" && run_ci $v >/dev/null ); all_d "② ci $v"
done
echo "== ③ 부른 쪽 ENABLE=1 → 그대로 · DISABLE 없음 =="; mk
MV_ENABLE=1 run_ci lsp status >/dev/null
chk "③ probe 가 받은 값" "$(grep -m1 'ARGS:' "$SB/probe.log" | cut -d' ' -f1-2)" "D=unset E=1"
echo "== ④ 부른 쪽 DISABLE=0 → 0 그대로 =="; mk
MV_DISABLE=0 run_ci lsp status >/dev/null
chk "④ probe 가 받은 값" "$(grep -m1 'ARGS:' "$SB/probe.log" | cut -d' ' -f1-2)" "D=0 E=unset"

echo "== ⑤ L2 — 0s → 0s → 3s = OK =="; mk
out="$(FAKE_UPTIMES="0s 0s 3s" run_rp)"; rc=$?
chk "⑤ rc" "$rc" "0"; has "⑤ OK 글" "$out" "repair OK — 데몬 Uptime 3s"
chk "⑤ status 호출 수" "$(cnt "$SB/probe.log" 'ARGS: lsp status')" "3"
chk "⑤ 기다림 수" "$(cnt "$SB/sleep.log" SLEEP)" "2"
# ⑪ 같은 한 번: 가짜 probe 가 받은 호출 수 = 가짜 timeout 이 받은 호출 수 · 상한 인자 ≤ 7
chk "⑪ probe 호출 수 = timeout 호출 수" "$(cnt "$SB/to.log" '^TO ')" "$(cnt "$SB/probe.log" 'ARGS: lsp ')"
chk "⑪ 상한 인자 모두 1~7" "$(awk '$2<1||$2>7{b=1} END{print b?"over":"ok"}' "$SB/to.log")" "ok"
chk "⑪ timeout 기록 있음" "$([ -s "$SB/to.log" ] && echo yes || echo no)" "yes"
echo "== ⑥ 0s 3회 = 판정 불가 · 4회째 0 =="; mk
out="$(FAKE_UPTIMES="0s 0s 0s 9s" run_rp)"; rc=$?
chk "⑥ rc" "$rc" "3"; has "⑥ 글" "$out" "판정 불가 repair — 데몬이 Uptime>0 으로 서지 않았다"
chk "⑥ status 호출 수" "$(cnt "$SB/probe.log" 'ARGS: lsp status')" "3"
echo "== ⑦ 첫 status 2s = 곧바로 OK · 기다림 0 =="; mk
out="$(FAKE_UPTIMES="2s" run_rp)"; rc=$?
chk "⑦ rc" "$rc" "0"; has "⑦ 기준판 글" "$out" "repair OK — 데몬 Uptime 2s · 옮긴 워크스페이스 1 개"
chk "⑦ status 호출 수" "$(cnt "$SB/probe.log" 'ARGS: lsp status')" "1"
chk "⑦ 기다림 수" "$(cnt "$SB/sleep.log" SLEEP)" "0"
echo "== ⑧ 빈 값 → 0s → 5s = OK =="; mk
out="$(FAKE_UPTIMES="- 0s 5s" run_rp)"; rc=$?
chk "⑧ rc" "$rc" "0"; has "⑧ OK 글" "$out" "repair OK — 데몬 Uptime 5s"
echo "== ⑨ L4 예산 소진 — 호출마다 7초 · status 빈 값 =="; mk
out="$(FAKE_STEP=7 FAKE_UPTIMES="-" run_rp)"; rc=$?
chk "⑨ rc" "$rc" "3"; has "⑨ 상한 글" "$out" "판정 불가 repair — 상한"
chk "⑨ status 호출 수" "$(cnt "$SB/probe.log" 'ARGS: lsp status')" "2"
chk "⑨ 둘째 status 상한 인자" "$(grep 'lsp status' "$SB/to.log" | sed -n 2p | awk '{print $2}')" "4"
echo "== ⑩ 호출 상한 — 첫 status 가 rc124 =="; mk
out="$(FAKE_TO_124=status FAKE_UPTIMES="-" run_rp)"; rc=$?
chk "⑩ rc" "$rc" "3"; has "⑩ 상한 글" "$out" "판정 불가 repair — 상한"
chk "⑩ status 호출 수(timeout 기준)" "$(cnt "$SB/to.log" 'lsp status')" "1"
echo "== ⑫ timeout 없음 = probe 호출 0 · 옮김 0 =="; mk
mkdir -p "$SB/nobin"; for c in bash env sed head date mv basename cat; do ln -s "$(command -v "$c")" "$SB/nobin/$c"; done
out="$(PATH="$SB/nobin" run_ci lsp repair)"; rc=$?
chk "⑫ rc" "$rc" "3"; has "⑫ 글" "$out" "판정 불가 repair — timeout 없음"
chk "⑫ probe 호출 0" "$(cnt "$SB/probe.log" 'ARGS:')" "0"
chk "⑫ 워크스페이스 이름 그대로" "$([ -d "$ws/ws_a" ] && echo yes || echo no)" "yes"

echo "== 요약: $n 검사 · 실패 $fail =="; [ -n "$SB" ] && rm -rf "$SB"
[ "$fail" -eq 0 ] || exit 1
echo "PASS"
