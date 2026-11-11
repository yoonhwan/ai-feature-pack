#!/usr/bin/env bash
# test_desk_route_team_master_r1708.sh — r1708 N1: desk → «어느 팀 명부의 _master 계보» 쪽지는 통과 · 그 밖은 그대로 REJECT.
#   ① desk → feature _master 통과 ② desk → issues _master 통과(이슈 알림 길) ③ desk → 나노·arch·이름만 맞는 좌석 REJECT ④ 팀 master → desk 방향은 그대로
#   변이 W1(팀 master 허용 삭제 → ①② 깨짐) · W2(아무 좌석 허용 → ③ 깨짐) — 변이마다 원본으로 같은 사례 1회 더(반대 결과).
# 판정기(ft_desk_route_gate.py)를 직접 부른다 — 임시 명부·임시 우편함 폴더만 · 실 큐·실 좌석·실 명부 0 · sleep 0.
#   기준판 대조 = FT_R1708_GATE=<고치기 전 판정기 경로> 로 같은 표를 돌린다(시험 입력 주입점 · 제품 우회 플래그 0).
[ -n "${R1708_DESK_ROUTE_TEST_GUARD:-}" ] && exit 0        # 재진입 표지(자기 호출 가드)
export R1708_DESK_ROUTE_TEST_GUARD=1
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="${FT_R1708_GATE:-$HERE/../bin/ft_desk_route_gate.py}"; KITGATE="$HERE/../kit/fable-team/bin/ft_desk_route_gate.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
mkdir -p "$T/seats" "$T/comm"
python3 - "$T/seats" <<'PY'
import json, sys
d = sys.argv[1]
def put(name, doc): json.dump(doc, open("%s/%s" % (d, name), "w"))
put("seats-planner.json", {"_master": "byz-planner-master-claude#94", "_desk": "byz-planner-desk-claude#38"})
put("seats-feature.json", {"_master": "byz-feature-master-pi#3", "byz-feature-master-pi#3": {"role": "master"}, "byz-feature-nano-x#0": {"role": "nano"}})
put("seats-issues.json", {"_master": "byz-issues-master-claude#7", "byz-issues-master-claude#7": {"role": "master"}})
put("seats-harness.json", {"_master": "byz-harness-master-pi#205", "_arch": "byz-harness-arch-pi#304", "byz-harness-arch-pi#304": {"role": "arch"}})
put("seats-empty.json", {"_master": ""})   # 빈 _master 칸은 누구도 허용하지 않는다
PY
D='byz-planner-desk-claude#38'; FM='byz-feature-master-pi#3'; IM='byz-issues-master-claude#7'
gate() { # gate <판정기> <to> <from> <본문> → OUT · RC
  printf '%b\n' "$4" > "$T/body"
  OUT="$(python3 "$1" --to "$2" --from "$3" --body-file "$T/body" --seats-dir "$T/seats" --comm "$T/comm" 2>"$T/err")"; RC=$?
}
want() { # want <이름> <pass|reject> [사유 조각]
  case "$2" in
    pass)   [ "$RC" = 0 ] && [ "$OUT" = OK ] && ok "$1 → 통과" || bad "$1 → 통과여야 한다 :: rc=$RC ${OUT:0:160}";;
    reject) [ "$RC" = 3 ] && case "$OUT" in "REJECT "*"${3:-}"*) ok "$1 → REJECT";; *) bad "$1 → 사유 문구 없음 :: ${OUT:0:160}";; esac || bad "$1 → REJECT 여야 한다 :: rc=$RC ${OUT:0:160}";;
  esac
}
WHY='desk 는 팀 master 또는 planner 에게만 보내요'

gate "$GATE" "$FM" "$D" '[진행] r1708 ① 보고';                 want "① desk → feature _master" pass
gate "$GATE" 'byz-feature-master-pi#9' "$D" '[진행] r1708 ① 계보'; want "① desk → feature _master 계보(번호 다름)" pass
gate "$GATE" "$FM" 'byz-planner-desk-codex#3' '[진행] r1708 ①';   want "① 이름 규약 desk(다른 베이스) → feature _master" pass
gate "$GATE" "$IM" "$D" '[이슈 등록] r1708 ② 알림';              want "② desk → issues _master(이슈 알림 길)" pass
gate "$GATE" 'byz-feature-nano-x#0' "$D" '[진행] r1708 ③';       want "③ desk → feature 나노" reject "$WHY"
gate "$GATE" 'byz-harness-arch-pi#304' "$D" '[진행] r1708 ③';    want "③ desk → harness arch" reject "$WHY"
gate "$GATE" 'byz-feature-master-claude#3' "$D" '[진행] r1708 ③'; want "③ desk → 이름만 맞는 좌석(명부 _master 계보 아님)" reject "$WHY"
gate "$GATE" 'byz-feature-nano-x#0' "$D" '[HIL] r1708 ③ 급함';   want "③ desk → 나노 [HIL] 도 REJECT" reject "$WHY"
gate "$GATE" 'byz-planner-master-claude#94' "$D" '[진행] r1708';  want "desk → planner(앞 판과 같음)" pass
gate "$GATE" "$D" "$FM" '[진행] r1708 ④ 보고';                   want "④ feature master → desk 일반 쪽지" reject 'desk 에는 planner 가 보내요'
gate "$GATE" "$D" "$FM" '[HIL] r1708 ④ 오빠 판정 필요';          want "④ feature master → desk [HIL]" pass
cmp -s "$HERE/../bin/ft_desk_route_gate.py" "$KITGATE" && ok "bin·kit 판정기 같은 바이트" || bad "bin·kit 판정기가 다르다"

mutant() { # mutant <이름> <옛 글> <새 글> → MUT · 옛 글이 정확히 1번 있어야 한다
  MUT="$T/gate-$1.py"
  python3 - "$GATE" "$MUT" "$2" "$3" <<'PY' || { bad "$1 변이 자리 못 찾음"; return 1; }
import sys
src, dst, a, b = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
if s.count(a) != 1: sys.exit(1)
open(dst, "w", encoding="utf-8").write(s.replace(a, b))
PY
}
if mutant W1 'is_planner(to) or base(to) in masters' 'is_planner(to)'; then   # W1 팀 master 허용 줄 삭제
  gate "$MUT" "$FM" "$D" '[진행] W1'; [ "$RC" = 3 ] && ok "W1 변이: ① 이 REJECT 로 깨진다" || bad "W1 변이가 ① 을 못 깬다 rc=$RC"
  gate "$MUT" "$IM" "$D" '[진행] W1'; [ "$RC" = 3 ] && ok "W1 변이: ② 가 REJECT 로 깨진다" || bad "W1 변이가 ② 를 못 깬다 rc=$RC"
  gate "$GATE" "$FM" "$D" '[진행] W1'; [ "$RC" = 0 ] && ok "W1 원본: ① 통과" || bad "W1 원본 ① rc=$RC"
  gate "$GATE" "$IM" "$D" '[진행] W1'; [ "$RC" = 0 ] && ok "W1 원본: ② 통과" || bad "W1 원본 ② rc=$RC"
fi
if mutant W2 'is_planner(to) or base(to) in masters' 'is_planner(to) or True'; then   # W2 허용을 «아무 좌석» 으로
  gate "$MUT" 'byz-feature-nano-x#0' "$D" '[진행] W2'; [ "$RC" = 0 ] && ok "W2 변이: ③ 나노가 통과로 깨진다" || bad "W2 변이가 ③ 을 못 깬다 rc=$RC"
  gate "$GATE" 'byz-feature-nano-x#0' "$D" '[진행] W2'; [ "$RC" = 3 ] && ok "W2 원본: ③ REJECT" || bad "W2 원본 ③ rc=$RC"
fi

echo "fail=$fail"; [ "$fail" = 0 ]
