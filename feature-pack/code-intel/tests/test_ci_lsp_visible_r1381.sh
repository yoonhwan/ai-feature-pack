#!/usr/bin/env bash
# r1381 — ci LSP 실패를 «참조 없음»·빈 칸으로 숨기지 않는다 (doctor lsp 칸 · refs/def 실패 줄 · _lsp_ensure 안내).
#   대역 probe(PROBE_BIN) + 임시 폴더 · 진짜 데몬·실 소켓 0 · 고정 sleep 0.
#   실행: bash feature-pack/code-intel/tests/test_ci_lsp_visible_r1381.sh
[ -n "${CI_LSP_VISIBLE_TEST_GUARD:-}" ] && exit 0        # 자기 재호출 가드
export CI_LSP_VISIBLE_TEST_GUARD=1
set -uo pipefail
ulimit -u $(( $(ps -U "$(id -u)" -o pid= | wc -l) + 256 )) 2>/dev/null || true   # 사용자 전체 수 기준 = 지금 수 + 256

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI="${CI_UNDER_TEST:-$HERE/../skill/scripts/ci}"
n=0; fail=0
ok()  { n=$((n+1)); echo "  ok   $1"; }
bad() { n=$((n+1)); fail=$((fail+1)); echo "  FAIL $1"; }
chk() { [ "$2" = "$3" ] && ok "$1 ($3)" || bad "$1 — 기대[$3] 얻음[$2]"; }
has() { case "$2" in *"$3"*) ok "$1";; *) bad "$1 — [$3] 없음: $(printf '%s' "$2" | head -3)";; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 — [$3] 있으면 안 됨";; *) ok "$1";; esac; }

SB="$(mktemp -d "${TMPDIR:-/tmp}/ci-lsp-visible.XXXXXX")"
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/home" "$SB/tmp"
cat > "$SB/probe" <<'FAKE'
#!/usr/bin/env bash
case "$1" in
  --version) echo "probe 0.6.0-fake" ;;
  search)    echo "smoke-ok" ;;
  lsp) shift; case "${1:-status}" in
    status)
      case "${FAKE_STATUS:-ready}" in
        empty)   echo "INFO Starting embedded LSP daemon" >&2 ;;
        stalled) printf 'LSP Daemon Status\n  Status: Connected\n  Uptime: 120s\n\nLanguage Servers:\n  TypeScript: Available (Initializing)\n    Readiness: Initializing (60s elapsed)\n    Warning: Server initialization appears stalled\n  Python: Available (Ready)\n    Readiness: Ready (333s elapsed)\n' ;;
        ready)   printf 'LSP Daemon Status\n  Status: Connected\n  Uptime: 120s\n\nLanguage Servers:\n  Python: Available (Ready)\n    Readiness: Ready (8s elapsed)\n' ;;
      esac
      exit "${FAKE_STATUS_RC:-0}" ;;
    call)
      case "${FAKE_CALL:-two}" in
        timeout) echo "INFO Connecting" >&2; echo "Error: Timeout connecting to daemon after 30000ms" >&2; exit 1 ;;
        two)     printf 'ref-a.py:1:1\nref-b.py:2:2\n' ;;
        zero)    echo "No references found" ;;
      esac ;;
    shutdown) exit 0 ;;
  esac ;;
esac
exit 0
FAKE
chmod +x "$SB/probe"

# $1=status 모드 · $2=call 모드 · 나머지=ci 인자 → OUT · ERR · RC
run() {
  local st="$1" cl="$2"; shift 2
  HOME="$SB/home" TMPDIR="$SB/tmp" PROBE_BIN="$SB/probe" FAKE_STATUS="$st" FAKE_CALL="$cl" \
    PROBE_LSP_CRASH_LOG="$SB/none.log" timeout 70 bash "$CI" "$@" >"$SB/out" 2>"$SB/err"
  RC=$?; OUT="$(cat "$SB/out")"; ERR="$(cat "$SB/err")"
}

echo "== L1 status 빈 stdout rc0 → doctor 판정 불가 · smoke 따로 =="
run empty two doctor
has "L1 lsp 칸 판정 불가" "$OUT" "lsp   : 판정 불가 status rc=0 출력 0"
has "L1 smoke 칸은 따로" "$OUT" "smoke : OK"

echo "== L2 status stalled → doctor WARN · _lsp_ensure 안내 =="
run stalled two doctor
has "L2 doctor WARN" "$OUT" "lsp   : WARN TypeScript 초기화 멈춤"
run stalled two refs "a.py#f"
has "L2 refs 안내 1줄" "$ERR" "[hint] LSP TypeScript 초기화 멈춤"
chk "L2 refs 결과 그대로 rc" "$RC" "0"

echo "== L3 refs 데몬 시간 초과 → 판정 불가 rc3 =="
run ready timeout refs "a.py#f"
chk "L3 rc" "$RC" "3"
has "L3 판정 불가 줄" "$ERR" "판정 불가 ci refs — LSP 데몬 응답 없음(30s)"
has "L3 status 동봉" "$ERR" "status=Connected"
chk "L3 stdout 0줄" "$OUT" ""
run ready timeout def "a.py#f"
chk "L3 def rc" "$RC" "3"
has "L3 def 판정 불가 줄" "$ERR" "판정 불가 ci def — LSP 데몬 응답 없음(30s)"

echo "== L4 refs 정상 2줄 rc0 → 그대로 =="
run ready two refs "a.py#f"
chk "L4 rc" "$RC" "0"
chk "L4 stdout 같음" "$OUT" "$(printf 'ref-a.py:1:1\nref-b.py:2:2')"
hasnt "L4 판정 불가 0" "$ERR" "판정 불가"

echo "== L5 refs 정상 0건 꼴(probe «No references found» rc0) → 그대로 =="
run ready zero refs "a.py#f"
chk "L5 rc" "$RC" "0"
chk "L5 stdout 같음" "$OUT" "No references found"
hasnt "L5 판정 불가 0" "$ERR" "판정 불가"

echo "== L6 status Connected · Python Ready → 정상 줄 · 안내 0 =="
run ready two doctor
has "L6 doctor 정상 줄" "$OUT" "lsp   : LSP Daemon Status"
hasnt "L6 WARN 0" "$OUT" "WARN"
hasnt "L6 판정 불가 0" "$OUT" "판정 불가"
run ready two refs "a.py#f"
hasnt "L6 refs 안내 0" "$ERR" "[hint]"

echo "== 요약: $n 검사 · 실패 $fail =="
[ "$fail" -eq 0 ] || exit 1
echo "PASS"
