#!/usr/bin/env bash
# r2292 — ci refs: LSP 빈 결과 = 글자 출현 교차 확인(rg) · 실 LSP 0(가짜 probe · tmp HOME)
#   실행: bash feature-pack/code-intel/tests/test_ci_refs_empty_crosscheck_r2292.sh   (CI_UNDER_TEST = 다른 ci 판)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI="${CI_UNDER_TEST:-$HERE/../skill/scripts/ci}"
n=0; fail=0
ok()  { n=$((n+1)); echo "  ok   $1"; }
bad() { n=$((n+1)); fail=$((fail+1)); echo "  FAIL $1"; }
chk() { [ "$2" = "$3" ] && ok "$1 ($3)" || bad "$1 — 기대[$3] 얻음[$2]"; }
has() { case "$2" in *"$3"*) ok "$1";; *) bad "$1 — [$3] 없음: $(printf '%s' "$2" | head -2)";; esac; }
REAL_RG="$(command -v rg)" || { echo "SKIP: rg 없음"; exit 0; }
SB="$(mktemp -d "${TMPDIR:-/tmp}/ci-refs-x.XXXXXX")"; trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/home" "$SB/tmp"
cat > "$SB/probe" <<'FAKE'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "lsp status") printf 'LSP Daemon Status\n  Status: Connected\n  Uptime: 120s\n%s' "${FAKE_WS:-}" ;;
  "lsp call") [ "${FAKE_OUT:-}" = list ] && echo "a.py:3:1 foo" || echo "No references found" ;;
  "--version") echo "probe 0.6.0" ;;
  "search "*) echo "x.py:1" ;;
esac
exit 0
FAKE
printf '#!/usr/bin/env bash\necho call >> "%s/rg.log"\n[ -n "${FAKE_RG_RC:-}" ] && exit "$FAKE_RG_RC"\nexec "%s" "$@"\n' "$SB" "$REAL_RG" > "$SB/rg"
chmod +x "$SB/probe" "$SB/rg"
case_() { # $1=이름 · $2=파일 내용(printf) · $3=loc · 나머지 = env → OUT · RC · RGN
  local nm="$1" body="$2" loc="$3"; shift 3; rm -rf "$SB/ws" "$SB/rg.log"; mkdir -p "$SB/ws"
  printf "$body" > "$SB/ws/${loc%%[#:]*}"
  OUT="$(cd "$SB/ws" && env HOME="$SB/home" TMPDIR="$SB/tmp" PROBE_BIN="$SB/probe" RG_BIN="$SB/rg" \
    CI_LSP_SCOPE="$SB/ws" "$@" bash "$CI" refs "$loc" 2>&1)"; RC=$?
  RGN="$(grep -c . "$SB/rg.log" 2>/dev/null || echo 0)"; echo "== $nm"; }

case_ "① 정의 1 + 사용 2" 'def foo():\n    pass\nfoo()\nfoo()\n' "a.py#foo"
chk "① rc" "$RC" 3; has "① 판정 불가 출현 2" "$OUT" "판정 불가 ci refs — LSP 0건 · 글자 출현 2곳"
case_ "② 정의 1곳뿐" 'def foo():\n    pass\n' "a.py#foo"
chk "② rc" "$RC" 0; has "② 출력 그대로" "$OUT" "No references found"
case_ "②ⓑ file:line:col" 'def foo():\n    pass\nfoo()\nfoo()\n' "a.py:1:5"
chk "②ⓑ rc" "$RC" 0; chk "②ⓑ rg 호출" "$RGN" 0
case_ "②ⓒ 점 든 이름" 'class Foo:\n    def bar(self): pass\nobj.bar()\nobj.bar()\n' "x.py#Foo.bar"
chk "②ⓒ rc" "$RC" 3; has "②ⓒ 출현 2" "$OUT" "글자 출현 2곳"
case_ "③ 재귀 1줄" 'def claim(): return claim()\n' "a.py#claim"
chk "③ rc" "$RC" 3; has "③ 출현 1" "$OUT" "글자 출현 1곳"
case_ "④ 실제 참조 목록" 'def foo():\n    pass\nfoo()\n' "a.py#foo" FAKE_OUT=list
chk "④ rc" "$RC" 0; chk "④ rg 호출" "$RGN" 0; has "④ 출력 그대로" "$OUT" "a.py:3:1 foo"
case_ "⑤ rg 넘침" 'def foo():\n    pass\nfoo()\n' "a.py#foo" FAKE_RG_RC=124
chk "⑤ rc" "$RC" 3; has "⑤ 교차 확인 실패" "$OUT" "판정 불가 ci refs — 교차 확인 실패"
doc() { env HOME="$SB/home" TMPDIR="$SB/tmp" PROBE_BIN="$SB/probe" FAKE_WS="$1" bash "$CI" doctor 2>&1 | grep -c 'LSP workspace 에 홈 전체'; }
echo "== ⑥ doctor"
chk "⑥ 홈 workspace = warn 1" "$(doc "    Workspaces: (2)
      • $SB/home
      • $SB/home/proj
")" 1
chk "⑥ 홈 없음 = 0" "$(doc "    Workspaces: (1)
      • $SB/home/proj
")" 0

if [ -z "${CI_UNDER_TEST:-}" ]; then  # 변이 = 사본에서만 · 각 변이에 맞는 사례가 FAIL 해야 한다
  for m in "M1|/_refs_cross \"\$2\"/d|①" "M2|/r2292-M2/d|② " "M3|s/ -n -o -F/ -n -F/|③"; do
    IFS='|' read -r mn sx want <<< "$m"; sed "$sx" "$HERE/../skill/scripts/ci" > "$SB/m.ci"
    cmp -s "$SB/m.ci" "$HERE/../skill/scripts/ci" && { bad "$mn 변이 적용 0"; continue; }
    r="$(CI_UNDER_TEST="$SB/m.ci" bash "$0" 2>&1 | grep "FAIL $want")"
    [ -n "$r" ] && ok "$mn 잡힘 ($want FAIL)" || bad "$mn 안 잡힘"
  done
fi
echo "== 결과: $((n - fail))/$n 통과 =="
[ "$fail" -eq 0 ]
