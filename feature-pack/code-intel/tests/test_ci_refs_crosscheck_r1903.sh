#!/usr/bin/env bash
# r1903 — ci refs 가 LSP 빈 결과(«No references found» rc0)를 «참조 0곳» 으로 내보내지 않는다 · doctor 홈 workspace warn.
#   대역 probe(PROBE_BIN) + 기록용 rg 덧(RG_BIN) + 임시 폴더 · 실 LSP 0 · sleep 0.
#   실행: bash feature-pack/code-intel/tests/test_ci_refs_crosscheck_r1903.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI="${CI_UNDER_TEST:-$HERE/../skill/scripts/ci}"; CI="$(cd "$(dirname "$CI")" && pwd)/$(basename "$CI")"
REAL_RG="$(command -v rg)" || { echo "판정 불가 — rg 없음"; exit 3; }
n=0; fail=0
ok()  { n=$((n+1)); echo "  ok   $1"; }
bad() { n=$((n+1)); fail=$((fail+1)); echo "  FAIL $1"; }
chk() { [ "$2" = "$3" ] && ok "$1 ($3)" || bad "$1 — 기대[$3] 얻음[$2]"; }
has() { case "$2" in *"$3"*) ok "$1";; *) bad "$1 — [$3] 없음: $(printf '%s' "$2" | head -3)";; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 — [$3] 있으면 안 됨";; *) ok "$1";; esac; }

SB="$(mktemp -d "${TMPDIR:-/tmp}/ci-refs-r1903.XXXXXX")"; trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/home" "$SB/tmp"
cat > "$SB/probe" <<'FAKE'
#!/usr/bin/env bash
case "$1" in --version) echo "probe 0.6.0-fake" ;; search) echo "smoke-ok" ;;
  lsp) case "$2" in
    status) printf 'LSP Daemon Status\n  Status: Connected\n  Uptime: 120s\n\nLanguage Servers:\n  Python: Available (Ready)\n    Readiness: Ready (8s elapsed)\n    Workspaces: (2)\n      • /elsewhere\n'
            [ "${FAKE_WS_HOME:-0}" = 1 ] && printf '      • %s\n' "$HOME" ;;
    call) case "${FAKE_CALL:-zero}" in zero) echo "No references found" ;; list) printf 'b.py:1:1\nb.py:2:5\n' ;; esac ;;
  esac ;;
esac; exit 0
FAKE
printf '#!/usr/bin/env bash\necho "$*" >> "%s/rg.log"\n[ "${FAKE_RG:-}" = overflow ] && exit 124\nexec "%s" "$@"\n' "$SB" "$REAL_RG" > "$SB/rg"
chmod +x "$SB/probe" "$SB/rg"

# $1=작업 폴더(= 범위 PWD) · 나머지=ci 인자 → OUT · ERR · RC · RGN(rg 호출 수)
run() {
  local wd="$1"; shift; : > "$SB/rg.log"
  ( cd "$wd" && HOME="$SB/home" TMPDIR="$SB/tmp" PROBE_BIN="$SB/probe" RG_BIN="$SB/rg" \
    PROBE_LSP_CRASH_LOG="$SB/none.log" timeout 70 bash "$CI" "$@" >"$SB/out" 2>"$SB/err" )
  RC=$?; OUT="$(cat "$SB/out")"; ERR="$(cat "$SB/err")"; RGN="$(grep -c . "$SB/rg.log")"
}
ws() { rm -rf "$SB/ws"; mkdir -p "$SB/ws"; while [ $# -gt 0 ]; do printf "$2" > "$SB/ws/$1"; shift 2; done; }

echo "== ① LSP 0건 + 범위에 정의 1 · 사용 2 → rc3 · 출현 2 =="
ws a.py 'def claim():\n    pass\n' b.py 'claim()\nx = claim\n'
run "$SB/ws" refs "a.py#claim"
chk "① rc" "$RC" "3"; chk "① stdout 0줄" "$OUT" ""
has "① 판정 불가 줄" "$ERR" "판정 불가 ci refs — LSP 0건 · 글자 출현 2곳(LSP 미색인 의심 · ci lsp status 의 Workspaces 확인)"
has "① 출현 줄 동봉" "$ERR" "b.py:2:"; hasnt "① 선언 줄 뺌" "$ERR" "a.py:1:"

echo "== ② LSP 0건 + 범위에 정의 1곳뿐(claimant 는 낱말 밖) → rc0 그대로 =="
ws a.py 'def claim():\n    claimant = 1\n'
run "$SB/ws" refs "a.py#claim"
chk "② rc" "$RC" "0"; chk "② stdout 그대로" "$OUT" "No references found"; hasnt "② 판정 불가 0" "$ERR" "판정 불가"

echo "== ③ LSP 실제 참조 목록 → 교차 확인 0회 · 그대로 =="
ws a.py 'def claim():\n    pass\n' b.py 'claim()\n'
run "$SB/ws" refs "a.py#claim"; [ "$RC" = 3 ] || bad "③ 준비 — 같은 범위가 빈 결과에선 rc3 이어야 함"
FAKE_CALL=list run "$SB/ws" refs "a.py#claim"
chk "③ rc" "$RC" "0"; chk "③ rg 호출 0" "$RGN" "0"; chk "③ stdout 그대로" "$OUT" "$(printf 'b.py:1:1\nb.py:2:5')"

echo "== ④ rg 넘침(rc124) → rc3 교차 확인 실패 =="
FAKE_RG=overflow run "$SB/ws" refs "a.py#claim"
chk "④ rc" "$RC" "3"; has "④ 실패 줄" "$ERR" "판정 불가 ci refs — LSP 0건 · 교차 확인 실패"; chk "④ stdout 0줄" "$OUT" ""

echo "== ⑤ doctor: 홈 workspace 있으면 warn 1줄 · 없으면 0줄 =="
FAKE_WS_HOME=1 run "$SB/ws" doctor
chk "⑤ warn 1줄" "$(printf '%s\n' "$OUT" | grep -c 'LSP workspace 에 홈 전체')" "1"
has "⑤ warn 문구" "$OUT" "[warn] LSP workspace 에 홈 전체 — refs 느림·빈 결과 원인 · ci lsp repair"
run "$SB/ws" doctor
chk "⑤ 홈 없음 warn 0" "$(printf '%s\n' "$OUT" | grep -c 'LSP workspace 에 홈 전체')" "0"

echo "== ⑥ LSP 0건 + 'def claim(): return claim()' 1줄(절대 경로·CI_LSP_SCOPE) → rc3 · 출현 1 =="
ws a.py 'def claim(): return claim()\n'
CI_LSP_SCOPE="$SB/ws" run "$SB/home" refs "$SB/ws/a.py#claim"
chk "⑥ rc" "$RC" "3"; has "⑥ 출현 1" "$ERR" "글자 출현 1곳"

echo "== 요약: $n 검사 · 실패 $fail =="
[ "$fail" -eq 0 ] || exit 1
echo "PASS"
