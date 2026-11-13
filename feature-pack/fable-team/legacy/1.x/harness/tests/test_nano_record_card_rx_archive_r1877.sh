#!/usr/bin/env bash
# test_nano_record_card_rx_archive_r1877.sh — r1877 CARD_RX 가 indices/아카이브/<YYYY-MM>/<stem>.md 도 카드로 읽는다: 반례 ①~④ + 변이 M1 + bin·kit 짝.
#   읽기만 · 임시 폴더(변이 사본)만 씀 · 실 장부·명부·pane 0 · sleep 0
set -u
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
H="$(cd -- "$HERE/.." && pwd)"; SRC="$H/bin"; KIT="$H/kit/fable-team/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "  PASS $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
key() {  # key <bin 폴더> <경로> → card_key 결과 1줄 (None | 팀|뿌리|stem)
  python3 - "$1" "$2" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
from ft_nano_record_due import card_key
k = card_key(sys.argv[2])
print("None" if k is None else "|".join(k))
PY
}
cases() {  # cases <bin 폴더> <표식> → 반례 ①~④
  local d="$1" w="$2" r
  r="$(key "$d" '/x/BYZ/design/harness/indices/아카이브/2026-11/r1483-x.md')"
  [ "$r" = "harness|design/harness/indices|r1483-x" ] && ok "$w ① 아카이브 달 폴더 → harness" || bad "$w ① 아카이브 달 폴더 ($r)"
  r="$(key "$d" '/x/BYZ/design/harness/indices/대기/r1871-x.md')"
  [ "$r" = "harness|design/harness/indices|r1871-x" ] && ok "$w ② 대기 카드 그대로" || bad "$w ② 대기 카드 ($r)"
  r="$(key "$d" '/x/BYZ/design/harness/indices/아카이브/foo/r1-x.md')"
  [ "$r" = "None" ] && ok "$w ③ 달 꼴 아님 → None" || bad "$w ③ 달 꼴 아님 ($r)"
  r="$(key "$d" 'design/teams/planner/indices/아카이브/2026-11/r9-x.md')"
  [ "$r" = "planner|design/teams/planner/indices|r9-x" ] && ok "$w ④ teams/planner 아카이브 → planner" || bad "$w ④ teams/planner ($r)"
}
echo "== 사전: 짝 사본"
cmp -s "$SRC/ft_nano_record.py" "$KIT/ft_nano_record.py" && ok "bin·kit ft_nano_record.py cmp0" || bad "bin·kit ft_nano_record.py 다름"
echo "== 반례 (bin · kit)"
cases "$SRC" bin
cases "$KIT" kit
echo "== 변이 M1: 달 꼴 검사 빼고 아무 폴더 2단 허용 → ③ FAIL 이어야"
mkdir -p "$T/m1"; cp "$SRC"/ft_nano_record*.py "$T/m1/"
python3 - "$T/m1/ft_nano_record.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
n = s.replace(r"(?:/\d{4}-\d{2})?", r"(?:/[^/]+)?", 1)
open(p, "w", encoding="utf-8").write(n); sys.exit(0 if n != s else 1)
PY
if [ $? -ne 0 ]; then bad "M1 변이 자리 없음(달 꼴 검사 미구현)"
else r="$(key "$T/m1" '/x/BYZ/design/harness/indices/아카이브/foo/r1-x.md')"
  [ "$r" != "None" ] && ok "M1 → ③ 이 잡음 ($r)" || bad "M1 살아남음(③ 이 못 잡음)"
fi
echo "결과: PASS $PASS · FAIL $FAIL"
[ "$FAIL" = 0 ]
