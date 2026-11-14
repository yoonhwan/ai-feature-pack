#!/usr/bin/env bash
# r1654 ⓒ — ci refs 전체(상태 확인 + 호출) 바깥 상한 시험. 실 probe·실 캐시·실 데몬 0 (가짜 probe + tmp HOME).
#   실행: bash feature-pack/code-intel/tests/test_ci_refs_timeout_r1654.sh
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

SB="$(mktemp -d "${TMPDIR:-/tmp}/ci-refs-to.XXXXXX")"; trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/home" "$SB/tmp"
cat > "$SB/probe" <<'FAKE'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "lsp status") [ "${FAKE_HANG:-}" = status ] && exec -a "$0-hang" tail -f /dev/null
                printf 'LSP Daemon Status\n  Status: Connected\n  Uptime: 120s\n' ;;
  "lsp call")   [ "${FAKE_HANG:-}" = call ] && exec -a "$0-hang" tail -f /dev/null
                echo "FAKE_REFERENCES 16" ;;
esac
exit 0
FAKE
chmod +x "$SB/probe"
run_refs() { # $1 = 매달릴 단계(call|status|빈칸)
  HOME="$SB/home" TMPDIR="$SB/tmp" PROBE_BIN="$SB/probe" FAKE_HANG="$1" \
    CI_REFS_TIMEOUT=2 CI_LSP_STATUS_TIMEOUT=10 bash "$CI" refs "a.py#f" 2>&1; }

for hang in call status; do
  echo "== ⓒ $hang 단계 무한 대기 → 상한 안 판정 불가 1줄 =="
  s=$SECONDS; out="$(run_refs "$hang")"; rc=$?; el=$((SECONDS - s))
  chk "$hang 매달림 rc" "$rc" "3"
  has "$hang 판정 불가 줄" "$out" "판정 불가 refs "
  has "$hang 폴백 안내" "$out" "초 — rg+Read 폴백(하드 룰 16)"
  chk "$hang 판정 불가 줄 1개" "$(printf '%s\n' "$out" | grep -c '판정 불가 refs')" "1"
  chk "$hang 상한+3초 안" "$([ "$el" -le 5 ] && echo ok || echo "$el")" "ok"
  chk "$hang 가짜 probe 잔류 0" "$(pgrep -f "$SB/probe" | grep -c .)" "0"
done

echo "== ⓓ 정상 refs 출력 불변 =="
out="$(run_refs "")"; rc=$?
chk "정상 rc" "$rc" "0"
has "참조 결과 그대로" "$out" "FAKE_REFERENCES 16"
hasnt "판정 불가 줄 없음" "$out" "판정 불가"

echo "== 결과: $((n - fail))/$n 통과 =="
[ "$fail" -eq 0 ]
