#!/usr/bin/env bash
# r1706 — ci ast: probe 이상 종료(panic·rc≠0)를 rc0 로 숨기지 않는다(①~⑤) + 변이 W1~W3(원본 대조). 실 probe·실 ast-grep·실 캐시 0.
#   실행: bash feature-pack/code-intel/tests/test_ci_ast_probe_panic.sh        (CI_UNDER_TEST=<ci 경로> 로 다른 판 대조)
[ -n "${CI_AST_PANIC_TEST_GUARD:-}" ] && exit 0        # 재진입 표지(자기 호출 가드)
export CI_AST_PANIC_TEST_GUARD=1
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI="${CI_UNDER_TEST:-$HERE/../skill/scripts/ci}"
n=0; fail=0
ok()  { n=$((n+1)); echo "  ok   $1"; }
bad() { n=$((n+1)); fail=$((fail+1)); echo "  FAIL $1"; }
chk() { [ "$2" = "$3" ] && ok "$1 ($3)" || bad "$1 — 기대[$3] 얻음[$2]"; }
has() { case "$2" in *"$3"*) ok "$1";; *) bad "$1 — [$3] 없음: $(printf '%s' "$2" | head -2)";; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 — [$3] 있으면 안 됨";; *) ok "$1";; esac; }

SB="$(mktemp -d "${TMPDIR:-/tmp}/ci-ast-panic.XXXXXX")"; trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/home" "$SB/tmp" "$SB/src"; echo 'x = a | b' > "$SB/src/a.py"
PANIC="thread 'main' panicked at ast-grep-core-0.36.3/src/matcher/pattern.rs:216:30"
cat > "$SB/probe" <<'FAKE'
#!/usr/bin/env bash
# 가짜 probe — FAKE_PROBE: panic(문구 + rc134) · nores(«No results found» rc0) · match(정상 매치 rc0)
[ "$1" = query ] || exit 0
case "${FAKE_PROBE:-match}" in
  panic) echo "$FAKE_PANIC" >&2; exit 134 ;;
  nores) echo "No results found." ;;
  match) printf 'File: a.py\n  1 x = a | b  FAKE_PROBE_MATCH\n' ;;
esac
exit 0
FAKE
cat > "$SB/ast-grep" <<'FAKE'
#!/usr/bin/env bash
# 가짜 ast-grep — 받은 인자 기록 + 고정 매치 1줄 · rc = FAKE_SG_RC
echo "ARGS: $*" >> "$FAKE_SG_LOG"; echo "a.py:1:FAKE_SG_MATCH"; exit "${FAKE_SG_RC:-0}"
FAKE
chmod +x "$SB/probe" "$SB/ast-grep"

run_ast() { # run_ast <ci> <probe 꼴> [env…] → OUT(stdout) · ERR(stderr) · RC · SGLOG(ast-grep 인자 기록 · 없으면 빈 값)
  local ci="$1" mode="$2"; shift 2; rm -f "$SB/sg.log"
  OUT="$(env HOME="$SB/home" TMPDIR="$SB/tmp" PROBE_BIN="$SB/probe" ASTGREP_BIN="$SB/ast-grep" FAKE_PROBE="$mode" FAKE_PANIC="$PANIC" \
         FAKE_SG_LOG="$SB/sg.log" CI_TIMEOUT=10 "$@" bash "$ci" ast '$A | $B' "$SB/src/a.py" -l python 2>"$SB/err")"; RC=$?
  ERR="$(cat "$SB/err")"; SGLOG="$(cat "$SB/sg.log" 2>/dev/null || true)"
}
NOSG=(ASTGREP_BIN="$SB/no-such-ast-grep" PATH="/usr/bin:/bin")   # ast-grep 없음 = 실행 불가 경로 + 최소 PATH

echo "== ① probe panic rc134 · ast-grep 있음 → 폴백 매치 · rc0 =="; run_ast "$CI" panic
chk "① rc" "$RC" "0"
has "① stdout = ast-grep 매치 1줄" "$OUT" "a.py:1:FAKE_SG_MATCH"
hasnt "① stdout 에 panic 문구 0" "$OUT" "panicked"
has "① panic 원문은 stderr" "$ERR" "panicked"
has "① 폴백 안내 1줄(stderr)" "$ERR" "[fallback] ast-grep 사용 (probe rc=134)"
has "① ast-grep 인자(패턴·언어·경로)" "$SGLOG" 'ARGS: run -p $A | $B -l python '"$SB/src/a.py"
echo "== ② probe panic · ast-grep 없음 → rc≠0 · 판정 불가 1줄 =="; run_ast "$CI" panic "${NOSG[@]}"
chk "② rc≠0" "$([ "$RC" -ne 0 ] && echo nonzero || echo "$RC")" "nonzero"
chk "② 판정 불가 1줄" "$(printf '%s\n' "$ERR" | grep -c '^판정 불가 ci ast: probe rc=134 · ast-grep 없음$')" "1"
hasnt "② stdout 에 panic 문구 0" "$OUT" "panicked"
echo "== ③ probe «No results found» rc0 → 폴백(지금과 같음) =="; run_ast "$CI" nores
chk "③ rc" "$RC" "0"
has "③ ast-grep 매치" "$OUT" "a.py:1:FAKE_SG_MATCH"
has "③ 폴백 안내(0건)" "$ERR" "[fallback] ast-grep 사용 (probe query 0건)"
run_ast "$CI" nores "${NOSG[@]}"; chk "③b 0건 + ast-grep 없음 → rc0 그대로" "$RC" "0"
has "③b 설치 안내" "$ERR" "[hint] probe query 가 0건입니다"
echo "== ④ probe 정상 매치 rc0 → 그 출력 그대로 · ast-grep 호출 0 =="; run_ast "$CI" match
chk "④ rc" "$RC" "0"
has "④ probe 출력 그대로" "$OUT" "FAKE_PROBE_MATCH"
chk "④ ast-grep 인자 기록 없음" "$SGLOG" ""
echo "== ⑤ 폴백 ast-grep rc1 → ci rc1 =="; run_ast "$CI" panic FAKE_SG_RC=1
chk "⑤ rc" "$RC" "1"

mutant() { # mutant <이름> <옛 글> <새 글> → MUT(변이 사본 경로) · 옛 글이 정확히 1번 있어야 한다
  MUT="$SB/ci-$1"
  python3 - "$CI" "$MUT" "$2" "$3" <<'PY' || { bad "$1 변이 자리 못 찾음"; return 1; }
import sys
src, dst, a, b = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
if s.count(a) != 1: sys.exit(1)
open(dst, "w", encoding="utf-8").write(s.replace(a, b))
PY
}
echo "== 변이 W1 — rc 검사 삭제 → ① 이 깨진다(원본은 반대) =="
if mutant W1 'if [ "$prc" -ne 0 ]; then' 'if false; then'; then
  run_ast "$MUT" panic; has "W1 변이: panic 문구가 stdout 으로 샌다" "$OUT" "panicked"; chk "W1 변이: ast-grep 호출 0" "$SGLOG" ""
  run_ast "$CI" panic; hasnt "W1 원본: stdout panic 0" "$OUT" "panicked"; has "W1 원본: ast-grep 호출" "$SGLOG" "ARGS: run"
fi
echo "== 변이 W2 — ast-grep 없음 갈래를 rc0 로 → ② 가 깨진다(원본은 반대) =="
if mutant W2 'ast-grep 없음" >&2; exit 3; }' 'ast-grep 없음" >&2; exit 0; }'; then
  run_ast "$MUT" panic "${NOSG[@]}"; chk "W2 변이: rc0 로 숨는다" "$RC" "0"
  run_ast "$CI" panic "${NOSG[@]}"; chk "W2 원본: rc3" "$RC" "3"
fi
echo "== 변이 W3 — 정상 매치에도 폴백 → ④ 가 깨진다(원본은 반대) =="
if mutant W3 '*"No results found"*) why=' '*) why='; then
  run_ast "$MUT" match; has "W3 변이: ast-grep 을 부른다" "$SGLOG" "ARGS: run"
  run_ast "$CI" match; chk "W3 원본: ast-grep 호출 0" "$SGLOG" ""
fi

echo "== 요약: $n 검사 · 실패 $fail =="
[ "$fail" -eq 0 ] || exit 1
echo "PASS"
