#!/usr/bin/env bash
# test_base_run_r2377_mut.sh — r2377 변이 M1~M7: ft-base-run.sh·린트 사본만 고쳐 그 사례가 FAIL 하는지, 그리고 원본으로 같은 사례를 한 번 더 돌려 통과하는지(대조)
#   사본은 $T/mut 아래에서만 · 실 bin 은 읽기만 · 변이마다 원본 대조 1회 · 사례 ①~⑫ 자체 = test_base_run_r2377.sh (70초 상한으로 쪼갬)
#   R2377_BIN(기준판 모드)이면 변이 전체 SKIP — 그 판에 ft-base-run.sh 가 없다
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/lib/r2377_fixture.sh"
. "$HERE/lib/r2377_cells.sh"

if [ "$BASE_MODE" = 1 ]; then
  sk "M1~M7" "기준판 모드(R2377_BIN) — ft-base-run.sh 없음"
  echo "(0 failed)"; exit 0
fi
MUTD="$T/mut"; mkdir -p "$MUTD"; cp -p "$EBIN"/* "$MUTD/" 2>/dev/null
cp -p "$SUT" "$MUTD/ft-base-run.sh"; cp -p "$BIN/ft-test-reentry-lint.sh" "$MUTD/"

mut() { # mut <이름> <옛 줄=>새 줄> — 사본만 고친다(원본 무변경)
  local ok=1; cp -p "$SUT" "$MUTD/ft-base-run.sh"
  python3 - "$MUTD/ft-base-run.sh" "$2" <<'PY' || ok=0
import sys
p, expr = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
old, new = (x.strip() for x in expr.split("=>", 1))
if old not in s:
    sys.exit(f"변이 대상 없음: {old!r}")
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
  [ "$ok" = 1 ] || { echo "FAIL $1 변이 적용 실패"; fail=$((fail+1)); }
}
mutlint() { # M6: BASECOPY 갈래(r2377)만 지운다
  cp -p "$BIN/ft-test-reentry-lint.sh" "$MUTD/ft-test-reentry-lint.sh"
  python3 - "$MUTD/ft-test-reentry-lint.sh" <<'PY'
import sys
p = sys.argv[1]; out = []; inside = False
for l in open(p, encoding="utf-8").read().splitlines(True):
    if "# r2377-rule" in l: inside = True
    if not inside: out.append(l)
    if "# /r2377-rule" in l: inside = False
open(p, "w", encoding="utf-8").write("".join(out))
PY
}
ex() { # ex <변이 이름> <사례 함수> <설명> — 변이는 FAIL 해야 하고 원본은 통과해야 한다(줄 끝 = 그 변이 초)
  local name="$1" fn="$2" desc="$3" t=$SECONDS
  RUN="$MUTD/ft-base-run.sh"; LINT_RUN="$MUTD/ft-test-reentry-lint.sh"
  "$fn"; if [ "$RES" = 0 ]; then echo "PASS $name 변이 → $desc FAIL"; else echo "FAIL $name 변이인데 $desc 가 통과 :: $MSG"; fail=$((fail+1)); fi
  RUN="$SUT"; LINT_RUN="$BIN/ft-test-reentry-lint.sh"
  "$fn"; if [ "$RES" = 1 ]; then echo "PASS $name 원본 대조 → $desc 통과 ($((SECONDS - t))초)"; else echo "FAIL $name 원본 대조인데 $desc 실패 :: $MSG ($((SECONDS - t))초)"; fail=$((fail+1)); fi
}

mut M1 'if [ "$ARCH_RC" != 0 ]; then => if false; then';               ex M1 c4 "④"   # archive 실패 무시
mut M2 'exit "$rc" => exit 0';                                          ex M2 c6 "⑥"   # rc 를 늘 0 으로
mut M3 'reap_dir end => :';                                             ex M3 c8 "⑧"   # 끝 rm 지움(trap 만)
mut M4 "trap 'on_signal 15' TERM => :";                                 ex M4 c9 "⑨"   # trap 에서 TERM 뺌
mut M5 'tmp.ftbase.XXXXXX => ftbase.XXXXXX';                            ex M5 c10 "⑩"  # 이름 머리에서 tmp. 뺌
mut M7 ') & CHILD=$!; wait "$CHILD"; rc=$? => ); rc=$?';                 ex M7 c9 "⑨"   # 앞쪽 실행으로 되돌림(& + wait 뺌)

mutlint                                                                # M6: 린트 갈래 지움
LINT_RUN="$MUTD/ft-test-reentry-lint.sh"; c11
if [ "$RES" = 0 ]; then echo "PASS M6 변이(린트 갈래 지움) → ⑪ FAIL"; else echo "FAIL M6 변이인데 ⑪ 이 통과 :: $MSG"; fail=$((fail+1)); fi
LINT_RUN="$BIN/ft-test-reentry-lint.sh"; c11
if [ "$RES" = 1 ]; then echo "PASS M6 원본 대조 → ⑪ 통과"; else echo "FAIL M6 원본 대조인데 ⑪ 실패 :: $MSG"; fail=$((fail+1)); fi

echo "[시간] 변이 M1~M7 $((SECONDS - T0))초"
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit "$fail"
