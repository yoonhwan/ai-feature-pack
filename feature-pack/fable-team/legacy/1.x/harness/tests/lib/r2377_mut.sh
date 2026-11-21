#!/usr/bin/env bash
# r2377_mut.sh — r2377 변이 도우미(사본에서만 고친다 · 원본 bin 은 읽기만). source 해서 쓴다.
#   mut <이름> <옛 줄=>새 줄> · mutlint(M6: BASECOPY 갈래 지움) · ex <이름> <사례 함수> <설명>(변이 FAIL + 원본 대조 PASS)
#   세계($T·$SUT·$BIN·$EBIN)는 tests/lib/r2377_fixture.sh 가 내준다 — 이 파일보다 먼저 source 한다.
# shellcheck shell=bash
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
