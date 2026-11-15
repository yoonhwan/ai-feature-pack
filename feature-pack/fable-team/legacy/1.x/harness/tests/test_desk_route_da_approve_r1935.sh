#!/usr/bin/env bash
# test_desk_route_da_approve_r1935.sh — r1935: 명부 `_da` 계보의 «[판정] APPROVE + 세트 40hex 1개 + 판정문 .md 1개» 는 desk 로 바로 통과 · 그 밖은 그대로 REJECT.
#   ① 통과 ② HOLD REJECT ③ arch·나노 같은 본문 REJECT ④ 세트 줄 없음 REJECT ⑤ 회전 DA(#N+1) 통과 ⑥ 기존 예외·ⓐ 방향 그대로
#   변이 M1(세트 검사 삭제 → ④ 깨짐) · M2(_da 계보 검사 삭제 → ③ 깨짐) — 임시 명부·임시 우편함만 · 실 큐 0 · sleep 0 · 외부 호출 0.
[ -n "${R1935_DESK_ROUTE_TEST_GUARD:-}" ] && exit 0
export R1935_DESK_ROUTE_TEST_GUARD=1
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="${FT_R1935_GATE:-$HERE/../bin/ft_desk_route_gate.py}"; KITGATE="$HERE/../kit/fable-team/bin/ft_desk_route_gate.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
mkdir -p "$T/seats" "$T/comm"
printf '%s' '{"_master": "byz-planner-master-pi#328", "_desk": "byz-planner-desk-claude#38"}' > "$T/seats/seats-planner.json"
printf '%s' '{"_master": "byz-harness-master-pi#293", "_da": "byz-harness-da-codex#11", "_arch": "byz-harness-arch-pi#346"}' > "$T/seats/seats-harness.json"
D='byz-planner-desk-claude#38'; DA='byz-harness-da-codex#11'; S="$(printf 'a%.0s' {1..40})"
OKB="[판정] APPROVE r1935 PR #9\n세트: $S\n판정문: design/harness/verdicts/DA-r1935.md"
gate() { printf '%b\n' "$4" > "$T/body"; OUT="$(python3 "$1" --to "$2" --from "$3" --body-file "$T/body" --seats-dir "$T/seats" --comm "$T/comm" 2>/dev/null)"; RC=$?; }
want() { case "$2" in pass) [ "$RC" = 0 ] && ok "$1 → 통과" || bad "$1 → 통과여야 :: rc=$RC $OUT";; reject) [ "$RC" = 3 ] && ok "$1 → REJECT" || bad "$1 → REJECT 여야 :: rc=$RC $OUT";; esac; }

gate "$GATE" "$D" "$DA" "$OKB";                                         want "① _da APPROVE+세트+판정문" pass
gate "$GATE" "$D" "$DA" "${OKB/APPROVE/HOLD}";                          want "② _da HOLD" reject
gate "$GATE" "$D" "$DA" "${OKB/APPROVE/APPROVE-DESIGN}";                want "② _da APPROVE-DESIGN(다른 머리)" reject
gate "$GATE" "$D" 'byz-harness-arch-pi#346' "$OKB";                    want "③ arch 같은 본문" reject
gate "$GATE" "$D" 'byz-harness-nano-x#0' "$OKB";                       want "③ 나노 같은 본문" reject
gate "$GATE" "$D" 'byz-harness-master-pi#293' "$OKB";                  want "③ 팀 master 같은 본문" reject
gate "$GATE" "$D" "$DA" "[판정] APPROVE r1935\n판정문: x/DA-r1935.md";  want "④ 세트 줄 없음" reject
gate "$GATE" "$D" "$DA" "$OKB\n세트: ${S//a/b}";                        want "④ 세트 2개" reject
gate "$GATE" "$D" "$DA" "[판정] APPROVE r1935\n세트: $S";              want "④ 판정문 경로 없음" reject
gate "$GATE" "$D" "$DA" "$OKB\n참고: y/other.md";                       want "④ 판정문 경로 2개" reject
gate "$GATE" "$D" 'byz-harness-da-codex#12' "$OKB";                    want "⑤ 회전 DA(#N+1)" pass
gate "$GATE" "$D" 'byz-harness-arch-pi#346' '[HIL] r1935 오빠 판정';  want "⑥ [HIL] 예외 그대로" pass
gate "$GATE" "$D" 'byz-harness-arch-pi#346' '[진행] r1935';           want "⑥ 일반 쪽지 그대로 REJECT" reject
gate "$GATE" "$DA" "$D" '[진행] r1935';                                want "⑥ desk → DA(ⓐ 방향 그대로)" reject
cmp -s "$HERE/../bin/ft_desk_route_gate.py" "$KITGATE" && ok "bin·kit 같은 바이트" || bad "bin·kit 판정기가 다르다"

mutant() { MUT="$T/gate-$1.py"; python3 - "$GATE" "$MUT" "$2" "$3" <<'PY' || { bad "$1 변이 자리 못 찾음"; return 1; }
import sys
src, dst, a, b = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
if s.count(a) != 1: sys.exit(1)
open(dst, "w", encoding="utf-8").write(s.replace(a, b))
PY
}
if mutant M1 'len(SET_LINE.findall(body)) == 1' 'True'; then
  gate "$MUT" "$D" "$DA" "[판정] APPROVE r1935\n판정문: x/DA-r1935.md"; [ "$RC" = 0 ] && ok "M1 변이: ④ 가 통과로 깨진다" || bad "M1 변이가 ④ 를 못 깬다 rc=$RC"
fi
if mutant M2 'base(frm) in das' 'True'; then
  gate "$MUT" "$D" 'byz-harness-arch-pi#346' "$OKB"; [ "$RC" = 0 ] && ok "M2 변이: ③ 이 통과로 깨진다" || bad "M2 변이가 ③ 을 못 깬다 rc=$RC"
fi
echo "fail=$fail"; [ "$fail" = 0 ]
