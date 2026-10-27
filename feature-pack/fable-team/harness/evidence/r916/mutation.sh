#!/usr/bin/env bash
# mutation.sh — r916 close 변이 3종 검출. 검출식 = «FAIL 줄이 있고 ∧ 시험 rc≠0» (DA⑥ r1 반례 4: 초록도 합격하던 식 고침).
# 각 변이는 bin/ft-inbox.py 만 고치고 끝나면 되돌린다(원복 뒤 kit 짝 cmp0 확인). 실행: bash evidence/r916/mutation.sh
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
H="$(cd -- "$HERE/../.." && pwd)"  # = harness
BIN="$H/bin/ft-inbox.py"
KIT="$H/kit/fable-team/bin/ft-inbox.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cp "$BIN" "$T/orig.py"
restore() { cp "$T/orig.py" "$BIN"; }
fail=0
mutate() {  # <이름> <python 치환 스니펫 파일>
  name="$1"; snip="$2"
  restore
  python3 - "$BIN" "$snip" <<'PY'
import sys
p, snip = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
old, new = open(snip, encoding="utf-8").read().split("\n---\n")
if old not in s:
    sys.exit(f"치환 실패(옛 문장 없음): {old[:60]}")
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
  [ $? -ne 0 ] && { echo "MUTATION $name: 치환 실패"; fail=$((fail+1)); restore; return; }
  out="$(bash "$H/tests/test_inbox.sh" 2>&1)"; rc=$?
  hits="$(echo "$out" | grep -cE '^FAIL')"
  echo "=== MUTATION $name — FAIL $hits 줄 · rc=$rc"
  echo "$out" | grep -E '^FAIL' | sed -n '1,6p'
  if [ "$hits" -gt 0 ] && [ "$rc" -ne 0 ]; then echo "DETECTED $name"; else echo "MISSED $name (변이가 초록을 통과)"; fail=$((fail+1)); fi
  restore
}
mk() { printf '%s\n---\n%s\n' "$2" "$3" > "$T/$1.snip"; mutate "$1" "$T/$1.snip"; }

mk reported-생략 '            x.update(mark=m, reported=True)' '            x.update(mark=m)'
mk NOTFOUND-rc0 '    return 1 if [t for t in targets if not mine[t]] else 0' '    return 0'
mk usage-검사-삭제 '    if not targets or not note.strip():
        die('"'"'usage: close <seq|group…> "<사유>" [--seat <좌석>]'"'"', 2)' '    pass'

restore
cmp -s "$BIN" "$KIT" && echo "원복 뒤 kit 짝 cmp0" || { echo "원복 실패(kit 짝 다름)"; fail=$((fail+1)); }
echo "MUTATION RESULT fail=$fail"
[ "$fail" = 0 ]
