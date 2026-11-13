#!/usr/bin/env bash
# r1850 — ci search: probe 결과 줄 출력 panic(rc 134/133/101 · stderr «panicked at») 감지 → 부분 출력 버리고 rg 폴백
#   (카드 ci-search-nonascii-panic · 설계 design/aifp/arch-ci-search-nonascii-panic-20261113.md §3)
#   P1~P17 반례 · 기준판(origin/main 판 ci) 대조 · 변이 V1~V10(원본 대조) · 실 probe 0 · sleep 0 · 네트워크 0.
#   실행: bash feature-pack/code-intel/tests/test_ci_search_nonascii_panic.sh   (CI_UNDER_TEST=<ci 경로> 로 다른 판 대조)
[ -n "${CI_SEARCH_PANIC_TEST_GUARD:-}" ] && exit 0        # 재진입 표지(자기 호출 가드)
if [ -z "${CI_SEARCH_PANIC_TEST_TIMED:-}" ]; then
  export CI_SEARCH_PANIC_TEST_TIMED=1
  command -v timeout >/dev/null 2>&1 && exec timeout 70 bash "$0" "$@"   # 시험 1개 상한 70초(하드 룰 22)
fi
export CI_SEARCH_PANIC_TEST_GUARD=1
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI="${CI_UNDER_TEST:-$HERE/../skill/scripts/ci}"
[ -f "$CI" ] || { echo "판정 불가: ci 파일 없음 — $CI"; exit 2; }

# 사용자 프로세스 상한(지금 + 여유) — 시험이 fork 폭주로 다른 좌석을 막지 않게(r1041)
_nproc="$(ps -U "$(id -u)" -o pid= 2>/dev/null | wc -l | tr -d ' ')"
[ -n "$_nproc" ] && ulimit -u "$((_nproc + 300))" 2>/dev/null

n=0; fail=0
ok()  { n=$((n+1)); echo "  ok   $1"; }
bad() { n=$((n+1)); fail=$((fail+1)); echo "  FAIL $1"; }
chk() { [ "$2" = "$3" ] && ok "$1 ($3)" || bad "$1 — 기대[$3] 얻음[$2]"; }
has() { case "$2" in *"$3"*) ok "$1";; *) bad "$1 — [$3] 없음: $(printf '%s' "$2" | head -2 | tr '\n' ' ')";; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 — [$3] 있으면 안 됨";; *) ok "$1";; esac; }
utf8() { if printf '%s' "$2" | python3 -c 'import sys; sys.stdin.buffer.read().decode("utf-8")' 2>/dev/null; then ok "$1"; else bad "$1 — UTF-8 아님"; fi; }
cnt() { printf '%s\n' "$2" | grep -c -- "$3" 2>/dev/null || true; }

SB="$(mktemp -d "${TMPDIR:-/tmp}/ci-search-panic.XXXXXX")" || { echo "판정 불가: 임시 폴더 생성 실패"; exit 2; }
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/home" "$SB/tmp" "$SB/core" "$SB/ten" "$SB/long" "$SB/pathfront"

# ── fixture ────────────────────────────────────────────────────────────────
printf '판정 불가 · x = 1\nreopen y\n' > "$SB/core/a.py"
printf '판정 불가 문서 줄\n'            > "$SB/core/doc.md"
for i in 1 2 3 4 5 6 7 8 9 10; do printf '판정 불가 hit %s\n' "$i" > "$SB/ten/f$i.py"; done
python3 - "$SB/long/l.py" <<'PY'                                          # 다중 바이트 400자 한 줄(P9)
import sys
open(sys.argv[1], "w", encoding="utf-8").write("판정 불가 " + "가나다라마" * 80 + "\n")
PY

# ── 대역(bin) ─────────────────────────────────────────────────────────────
cat > "$SB/probe" <<'FAKE'
#!/usr/bin/env bash
# 가짜 probe — q 에 « OR » 가 있으면 2단계 · FAKE_PROBE_1 / FAKE_PROBE_2 로 꼴 선택
q="$2"
printf '%s\n' "$*" >> "$FAKE_LOG"
st=1; case "$q" in *" OR "*) st=2 ;; esac
mv="FAKE_PROBE_$st"; mode="${!mv:-panic}"
case "$mode" in
  panic)    printf 'FAKE_PARTIAL 1\nFAKE_PARTIAL 2\n'; printf "thread 'main' panicked at %s\n" "${FAKE_PANIC:-src/search/search_output.rs:2566:31 end byte index}" >&2; exit "${FAKE_RC:-134}" ;;
  rconly)   exit "${FAKE_RC:-134}" ;;
  errpanic) printf "thread 'main' panicked at %s\n" "${FAKE_PANIC:-src/search/search_output.rs:2566:31}" >&2; exit 0 ;;
  nohits)   printf 'No results found.\n'; exit 1 ;;
  hit)      printf 'File: a.py\n  1: reopen\n'; exit 0 ;;
esac
exit 0
FAKE
cat > "$SB/rg-stub" <<'FAKE'
#!/usr/bin/env bash
# 가짜 rg — 인자 기록 · 고정 결과 1줄 · rc = FAKE_RG_RC
printf '%s\n' "$*" >> "$FAKE_RG_LOG"
printf '%s:1:FAKE_RG_MATCH\n' "${FAKE_RG_PATH:-a.py}"
exit "${FAKE_RG_RC:-0}"
FAKE
cat > "$SB/pathfront/timeout" <<'FAKE'
#!/usr/bin/env bash
# 가짜 timeout — 받은 인자 전부 기록 · FAKE_TO_MODE: 124(rg 안 부르고 즉시 rc124) · run(나머지 실행)
printf '%s\n' "$*" >> "$FAKE_TO_LOG"
case "${FAKE_TO_MODE:-124}" in
  124) exit 124 ;;
  run) shift; exec "$@" ;;
esac
FAKE
chmod +x "$SB/probe" "$SB/rg-stub" "$SB/pathfront/timeout"

E=(env HOME="$SB/home" TMPDIR="$SB/tmp" PROBE_BIN="$SB/probe" CI_TIMEOUT=10
   FAKE_LOG="$SB/probe.log" FAKE_RG_LOG="$SB/rg.log" FAKE_TO_LOG="$SB/to.log" FAKE_RG_PATH="$SB/core/a.py")
RUNENV=("${E[@]}")
run_ci() { # $1=ci · $2..=ci 인자 → OUT · ERR · RC (대역 기록 초기화)
  local ci="$1"; shift
  : > "$SB/probe.log"; : > "$SB/rg.log"; : > "$SB/to.log"
  OUT="$("${RUNENV[@]}" bash "$ci" search "$@" 2>"$SB/err")"; RC=$?
  ERR="$(cat "$SB/err")"
}
first() { printf '%s\n' "$1" | head -n 1; }

POL="== rg 폴백 (probe panic rc=134) =="

# ── P1~P17 ────────────────────────────────────────────────────────────────
echo "== P1 비ASCII 질의 · panic rc134 + stderr → 폴백 =="
P1() { RUNENV=("${E[@]}"); run_ci "$CI" "판정 불가" "$SB/core" --max 5
  chk "P1 rc" "$RC" "0"
  chk "P1 stdout 첫 줄 = 폴백 표지" "$(first "$OUT")" "$POL"
  has  "P1 결과 줄(a.py)" "$OUT" "a.py:1"
  hasnt "P1 부분 stdout 0(FAKE_PARTIAL)" "$OUT" "FAKE_PARTIAL"
  utf8 "P1 stdout UTF-8 유효" "$OUT"
  has  "P1 stderr 경고 1줄" "$ERR" "[warn] probe panic rc=134"
}
P1

echo "== P2 ASCII 질의 reopen · 같은 panic → 폴백 =="
P2() { RUNENV=("${E[@]}"); run_ci "$CI" "reopen" "$SB/core" --max 5
  chk "P2 rc" "$RC" "0"
  chk "P2 stdout 첫 줄 = 폴백 표지" "$(first "$OUT")" "$POL"
  has  "P2 결과 줄(a.py)" "$OUT" "a.py:"
  hasnt "P2 부분 stdout 0" "$OUT" "FAKE_PARTIAL"
}
P2

echo "== P3a/b/c rconly(출력 0) rc 134 · 133 · 101 → 폴백 =="
P3a() { RUNENV=("${E[@]}" FAKE_PROBE_1=rconly FAKE_RC=134); run_ci "$CI" "reopen" "$SB/core" --max 5
  chk "P3a rc" "$RC" "0"; has "P3a 결과 줄" "$OUT" "a.py:"; has "P3a stderr 없음 표기" "$ERR" "stderr 없음"; }
P3a
P3b() { RUNENV=("${E[@]}" FAKE_PROBE_1=rconly FAKE_RC=133); run_ci "$CI" "reopen" "$SB/core" --max 5
  chk "P3b rc" "$RC" "0"; has "P3b 결과 줄" "$OUT" "a.py:"; }
P3b
P3c() { RUNENV=("${E[@]}" FAKE_PROBE_1=rconly FAKE_RC=101); run_ci "$CI" "reopen" "$SB/core" --max 5
  chk "P3c rc" "$RC" "0"; has "P3c 결과 줄" "$OUT" "a.py:"; }
P3c

echo "== P4 errpanic(rc0 + stderr panicked) → 폴백 =="
P4() { RUNENV=("${E[@]}" FAKE_PROBE_1=errpanic); run_ci "$CI" "reopen" "$SB/core" --max 5
  chk "P4 rc" "$RC" "0"
  chk "P4 stdout 첫 줄 = 표지(rc 0 표기)" "$(first "$OUT")" "== rg 폴백 (probe panic rc=0) =="
  has "P4 결과 줄" "$OUT" "a.py:"
}
P4

echo "== P5 panic · 0건 → rc1 + 표지 + (0건) =="
P5() { RUNENV=("${E[@]}"); run_ci "$CI" "zzzznotfound" "$SB/core" --max 5
  chk "P5 rc" "$RC" "1"
  chk "P5 stdout 첫 줄 = 표지" "$(first "$OUT")" "$POL"
  has "P5 (0건)" "$OUT" "(0건)"
  hasnt "P5 부분 stdout 0" "$OUT" "FAKE_PARTIAL"
}
P5

echo "== P6 panic · rg 없음 → rc3 · stdout 0줄 · 판정 불가 =="
P6() { RUNENV=("${E[@]}" RG_BIN=/없는/경로 PATH=/usr/bin:/bin); run_ci "$CI" "reopen" "$SB/core" --max 5
  chk "P6 rc" "$RC" "3"
  chk "P6 stdout 0줄" "$OUT" ""
  has "P6 판정 불가 1줄" "$ERR" "판정 불가 ci search"
}
P6

echo "== P7 정상 hit → stdout 그대로 · 표지 0 · rc0 (회귀) =="
P7() { RUNENV=("${E[@]}" FAKE_PROBE_1=hit); run_ci "$CI" "reopen" "$SB/core" --max 5
  chk "P7 rc" "$RC" "0"
  chk "P7 stdout 그대로" "$OUT" "File: a.py
  1: reopen"
  hasnt "P7 표지 0" "$OUT" "rg 폴백"
}
P7

echo "== P8 정상 nohits rc1 · 한 낱말 → rc1 · 표지 0 (회귀) =="
P8() { RUNENV=("${E[@]}" FAKE_PROBE_1=nohits); run_ci "$CI" "zzzz" "$SB/core" --max 5
  chk "P8 rc" "$RC" "1"
  chk "P8 stdout 그대로" "$OUT" "No results found."
  hasnt "P8 표지 0" "$OUT" "rg 폴백"
}
P8

echo "== P9 panic · 다중 바이트 400자 줄 → 본문 <=160자 · UTF-8 유효 =="
P9() { RUNENV=("${E[@]}"); run_ci "$CI" "판정 불가" "$SB/long" --max 3
  local body len
  body="$(printf '%s\n' "$OUT" | grep -v '^==' | grep -v '^$' | tail -n 1 | sed 's/^  //')"
  len="$(printf '%s' "$body" | python3 -c 'import sys; print(len(sys.stdin.read()))' 2>/dev/null || echo -1)"
  chk "P9 rc" "$RC" "0"
  has "P9 결과 줄(l.py)" "$OUT" "l.py:1"
  [ "$len" -ge 1 ] && [ "$len" -le 160 ] && ok "P9 본문 문자 수 <=160 ($len)" || bad "P9 본문 문자 수 — $len (1~160 이어야)"
  utf8 "P9 stdout UTF-8 유효" "$OUT"
}
P9

echo "== P10 비ASCII panic · doc.md 겹침 0 (md 절 1번 · 폴백 절에 md 0) =="
P10() { RUNENV=("${E[@]}"); run_ci "$CI" "판정 불가" "$SB/core" --max 5
  chk "P10 rc" "$RC" "0"
  chk "P10 md 절 1번" "$(cnt "$OUT" "$OUT" '^== markdown ')" "1"
  chk "P10 doc.md 등장 1번" "$(cnt "$OUT" "$OUT" 'doc.md')" "1"
  hasnt "P10 폴백 절에 md 0" "$(printf '%s\n' "$OUT" | sed -n '/^== rg 폴백/,/^== markdown/p')" "doc.md"
}
P10

echo "== P11 pipefail 아래 | head -1 = P6 PIPESTATUS[0]=3 · P1 첫 줄 표지 =="
P11() {
  local ps
  RUNENV=("${E[@]}" RG_BIN=/없는/경로 PATH=/usr/bin:/bin)
  : > "$SB/to.log"
  "${RUNENV[@]}" bash "$CI" search "reopen" "$SB/core" --max 5 2>/dev/null | head -n 1 > "$SB/p11a.out"
  ps=("${PIPESTATUS[@]}")
  chk "P11a P6 PIPESTATUS[0]" "${ps[0]}" "3"
  RUNENV=("${E[@]}")
  "${RUNENV[@]}" bash "$CI" search "판정 불가" "$SB/core" --max 5 2>/dev/null | head -n 1 > "$SB/p11b.out"
  chk "P11b P1 head 1줄 = 표지" "$(cat "$SB/p11b.out")" "$POL"
}
P11

echo "== P12 다중어 · 1단계 nohits rc1 → 2단계(OR) panic → 출력 보류 =="
P12() { RUNENV=("${E[@]}" FAKE_PROBE_1=nohits FAKE_PROBE_2=panic); run_ci "$CI" "판정 불가" "$SB/core" --max 5
  chk "P12 rc" "$RC" "0"
  chk "P12 stdout 첫 줄 = 표지" "$(first "$OUT")" "$POL"
  hasnt "P12 No results found 0" "$OUT" "No results found"
  hasnt "P12 FAKE_PARTIAL 0" "$OUT" "FAKE_PARTIAL"
}
P12

echo "== P13a rg 대역 = 결과 1줄 낸 뒤 rc2 → rc3 · stdout 0줄 =="
P13a() { RUNENV=("${E[@]}" RG_BIN="$SB/rg-stub" FAKE_RG_RC=2); run_ci "$CI" "reopen" "$SB/core" --max 5
  chk "P13a rc" "$RC" "3"
  chk "P13a stdout 0줄(대역 줄 0)" "$OUT" ""
  has "P13a 판정 불가" "$ERR" "판정 불가 ci search"
}
P13a

echo "== P13b 실제 rg · 없는 폴더(rg rc2) → rc3 · stdout 0줄 =="
P13b() { RUNENV=("${E[@]}"); run_ci "$CI" "reopen" "$SB/no-such-dir" --max 5
  chk "P13b rc" "$RC" "3"
  chk "P13b stdout 0줄" "$OUT" ""
  has "P13b 사유 rc=2" "$ERR" "rc=2"
}
P13b

echo "== P14 가짜 timeout = 즉시 rc124 (sleep 0) → rc3 · 사유 rc=124 · rg 호출 0 =="
P14() { RUNENV=("${E[@]}" PATH="$SB/pathfront:$PATH"); run_ci "$CI" "reopen" "$SB/core" --max 5
  chk "P14 rc" "$RC" "3"
  chk "P14 stdout 0줄" "$OUT" ""
  has "P14 사유 rc=124" "$ERR" "rc=124"
  has "P14 가짜 timeout 인자에 RG 경로" "$(cat "$SB/to.log")" "rg"
  chk "P14 rg 호출 0" "$(cat "$SB/rg.log")" ""
}
P14

echo "== P15 10파일 hit · --max 3 → 결과 정확히 3개 · SIGPIPE·판정 불가 0 =="
P15() { RUNENV=("${E[@]}"); run_ci "$CI" "판정 불가" "$SB/ten" --max 3
  chk "P15 rc" "$RC" "0"
  chk "P15 결과 줄 3개" "$(printf '%s\n' "$OUT" | grep -cE '^.*\.py:[0-9]+$')" "3"
  hasnt "P15 SIGPIPE 0" "$ERR" "SIGPIPE"
  hasnt "P15 판정 불가 0" "$ERR" "판정 불가"
}
P15

echo "== P16 RG_BIN 대역 우선(PATH 에 실제 rg 있음) → 대역이 불린다 =="
P16() { RUNENV=("${E[@]}" RG_BIN="$SB/rg-stub"); run_ci "$CI" "reopen" "$SB/core" --max 5
  chk "P16 rc" "$RC" "0"
  has "P16 대역 결과" "$OUT" "FAKE_RG_MATCH"
  [ -s "$SB/rg.log" ] && ok "P16 대역 인자 기록 있음" || bad "P16 대역이 안 불렸다"
}
P16

echo "== P17 CI_RG_TIMEOUT=300 · 가짜 timeout(기록 후 실행) → 기록된 상한 = 25 =="
P17() { RUNENV=("${E[@]}" CI_RG_TIMEOUT=300 PATH="$SB/pathfront:$PATH" FAKE_TO_MODE=run)
  run_ci "$CI" "reopen" "$SB/core" --max 5
  chk "P17 기록된 상한" "$(awk '{print $1}' "$SB/to.log" | head -n 1)" "25"
  chk "P17 rc" "$RC" "0"
}
P17

# ── 기준판(origin/main 판 ci) 대조 ────────────────────────────────────────
echo "== 기준판 대조 — P7·P8 만 PASS, 나머지 전부 FAIL 이어야 =="
ROOT="$(cd "$HERE/../../.." && pwd)"
BASE_SHA="$(git -C "$ROOT" rev-parse origin/main 2>/dev/null || true)"
BASE="$SB/ci-base"
if [ -n "$BASE_SHA" ] && git -C "$ROOT" show "$BASE_SHA:feature-pack/code-intel/skill/scripts/ci" > "$BASE" 2>/dev/null; then
  echo "  기준판 = $BASE_SHA"
  bl() { # bl <검사함수> <기대: fail|pass>
    local f="$1" want="$2" bn=$n bf=$fail changed
    CI="$BASE"; "$f" > "$SB/base.$f" 2>&1
    changed=$(( fail - bf )); n=$bn; fail=$bf; CI="${CI_UNDER_TEST:-$HERE/../skill/scripts/ci}"
    if [ "$want" = "fail" ]; then
      [ "$changed" -gt 0 ] && ok "기준판 $f FAIL(기대대로 · ${changed}건)" || bad "기준판 $f 통과 — FAIL 이어야"
    else
      [ "$changed" -eq 0 ] && ok "기준판 $f PASS(기대대로)" || bad "기준판 $f FAIL(${changed}건) — PASS 이어야"
    fi
  }
  for f in P1 P2 P3a P3b P3c P4 P5 P6 P9 P10 P11 P12 P13a P13b P14 P15 P16 P17; do bl "$f" fail; done
  bl P7 pass; bl P8 pass
else
  bad "기준판 추출 실패(origin/main ci 를 git show 로 못 꺼냈다)"
fi

# ── 변이 V1~V10 ───────────────────────────────────────────────────────────
echo "== 변이 — 각각 지정 반례가 FAIL 해야(잡힘) =="
mutant() { # $1=이름 · $2..=«옛 글@@새 글» 쌍(각 옛 글은 정확히 1번)
  local name="$1"; shift
  MUT="$SB/ci-$name"
  python3 - "$CI" "$MUT" "$@" <<'PY'
import sys
src, dst, pairs = sys.argv[1], sys.argv[2], sys.argv[3:]
s = open(src, encoding="utf-8").read()
for p in pairs:
    old, new = p.split("@@", 1)
    if s.count(old) != 1:
        sys.exit("변이 자리 못 찾음(%d회): %r" % (s.count(old), old))
    s = s.replace(old, new)
open(dst, "w", encoding="utf-8").write(s)
PY
}
vcheck() { # vcheck <이름> <검사함수> <옛 글@@새 글>…
  local name="$1" fn="$2"; shift 2
  local bn=$n bf=$fail caught=0 orig="$CI"
  mutant "$name" "$@" || { bad "$name 변이 만들기 실패"; return; }
  CI="$MUT"; "$fn" > "$SB/mut.$name" 2>&1; [ "$fail" -gt "$bf" ] && caught=1
  n=$bn; fail=$bf; CI="$orig"
  [ "$caught" -eq 1 ] && ok "$name 변이 → $fn FAIL(잡힘)" || bad "$name 변이 → $fn 통과(못 잡음)"
}
vcheck V1 P1 \
  'case "$SE_RC" in 101|133|134) SE_PANIC=1 ;; esac@@:' \
  'grep -q "panicked at" "$SE_ERR" 2>/dev/null && SE_PANIC=1@@:'
vcheck V2 P4 'grep -q "panicked at" "$SE_ERR" 2>/dev/null && SE_PANIC=1@@:'
vcheck V3 P3a 'case "$SE_RC" in 101|133|134) SE_PANIC=1 ;; esac@@:'
vcheck V4 P13b 'failwhy="rg 실패 rc=$rgrc"@@failwhy=""'
vcheck V5 P9 'cut -c1-160@@cut -b1-160'
vcheck V6 P10 '[ "$md_excl" = 1 ] && gopts+=(-g "!*.md")@@:'
vcheck V7 P12 'SE_RC=$?
  SE_PANIC=0@@SE_RC=$?
  cat "$SE_OUT"
  SE_PANIC=0'
vcheck V8 P13a '-- "$path" >"$_SE_DIR/rg.out" 2>"$_SE_DIR/rg.err"@@-- "$path" 2>"$_SE_DIR/rg.err" | head -n "$max" >"$_SE_DIR/rg.out"' \
  'set -uo pipefail@@set -uo'
vcheck V9 P17 '[ "$rgt" -gt 25 ] && rgt=25@@:'
vcheck V10 P16 'RG="${RG_BIN:-$(_resolve rg || true)}"@@RG="$(_resolve rg || true)"'

echo "== 요약: $n 검사 · 실패 $fail =="
[ "$fail" -eq 0 ] || exit 1
echo "PASS"
