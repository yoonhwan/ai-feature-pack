#!/usr/bin/env bash
# test_desk_route_ft2_listen_r1851.sh — r1851: Slack 수신기(ft2-slack-listen)의 desk 깨움 쪽지는 desk 경로 문을 통과한다.
#   ① ft2-slack-listen → desk 통과 ② ft2-x#1 → desk REJECT ③ ft2-slack-listen-x(꼬리) → desk REJECT(정확 이름만)
#   변이 M1(추가 비교 빼기 → ① 깨짐) · M2(정확 비교 → startswith("ft2-") → ②③ 깨짐)
# 판정기를 직접 부른다 — 임시 명부·임시 우편함 폴더만 · 실 큐·실 명부 0 · sleep 0 · 기준판 = FT_R1851_GATE=<옛 판정기>.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="${FT_R1851_GATE:-$HERE/../bin/ft_desk_route_gate.py}"; KITGATE="$HERE/../kit/fable-team/bin/ft_desk_route_gate.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
mkdir -p "$T/seats" "$T/comm"
printf '%s' '{"_master": "byz-planner-master-pi#94", "_desk": "byz-planner-desk-pi#149"}' > "$T/seats/seats-planner.json"
D='byz-planner-desk-pi#149'; WHY='desk 에는 planner 가 보내요'
gate() { # gate <판정기> <from> → OUT · RC (받는 사람 = desk)
  printf '%s\n' '[slack] #byz-desk 새 글 1건' > "$T/body"
  OUT="$(FT_MBOX_DIR="$T/comm" python3 "$1" --to "$D" --from "$2" --body-file "$T/body" --seats-dir "$T/seats" --comm "$T/comm" 2>"$T/err")"; RC=$?
}
cases() { # cases <판정기> <접두> → 표 3줄
  gate "$1" 'ft2-slack-listen';   [ "$RC" = 0 ] && [ "$OUT" = OK ] && ok "$2① ft2-slack-listen → desk 통과" || bad "$2① 통과여야 한다 :: rc=$RC $OUT"
  gate "$1" 'ft2-x#1';            [ "$RC" = 3 ] && case "$OUT" in *"$WHY"*) ok "$2② ft2-x#1 → REJECT";; *) bad "$2② 사유 없음 :: $OUT";; esac || bad "$2② REJECT 여야 한다 :: rc=$RC $OUT"
  gate "$1" 'ft2-slack-listen-x'; [ "$RC" = 3 ] && case "$OUT" in *"$WHY"*) ok "$2③ 꼬리 붙은 이름 → REJECT";; *) bad "$2③ 사유 없음 :: $OUT";; esac || bad "$2③ REJECT 여야 한다 :: rc=$RC $OUT"
}
cases "$GATE" ""
cmp -s "$HERE/../bin/ft_desk_route_gate.py" "$KITGATE" && ok "bin·kit 판정기 같은 바이트" || bad "bin·kit 판정기가 다르다"
[ -n "${FT_R1851_GATE:-}" ] && { echo "fail=$fail"; [ "$fail" = 0 ]; exit; }

mutant() { # mutant <이름> <옛 글> <새 글> → $T/gate-<이름>.py · 옛 글이 정확히 1번 있어야 한다
  python3 - "$GATE" "$T/gate-$1.py" "$2" "$3" <<'PY' || { bad "$1 변이 자리 못 찾음"; return 1; }
import sys
src, dst, a, b = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
if s.count(a) != 1: sys.exit(1)
open(dst, "w", encoding="utf-8").write(s.replace(a, b))
PY
}
EXACT=' or frm == "ft2-slack-listen"'
mutant M1 "$EXACT" '' && { m="$(cases "$T/gate-M1.py" M1)"; case "$m" in *"FAIL M1①"*) ok "M1 추가 비교 빼기 → ① 깨짐(잡음)";; *) bad "M1 못 잡음 :: $m";; esac; }
mutant M2 "$EXACT" ' or frm.startswith("ft2-")' && { m="$(cases "$T/gate-M2.py" M2)"; case "$m" in *"FAIL M2②"*"FAIL M2③"*) ok "M2 startswith(ft2-) → ②③ 깨짐(잡음)";; *) bad "M2 못 잡음 :: $m";; esac; }
echo "fail=$fail"; [ "$fail" = 0 ]
