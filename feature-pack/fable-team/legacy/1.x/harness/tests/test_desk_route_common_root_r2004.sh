#!/usr/bin/env bash
# test_desk_route_common_root_r2004.sh — r2004: 명부 없는 루트(aifp·kakao)의 desk 경로 판정 = roots.tsv «사람우편함» 칸의 공용 루트 seats-planner.json.
#   ⓐ aifp 루트(명부 없음) desk 직송 판정이 공용 명부로 돈다(WARN 0 · 공용 루트 직접 판정과 같은 결과)
#   ⓑ roots.tsv 행 없음 · 칸 «.» · 읽기 실패 = 지금 WARN 그대로 + 사유 «roots.tsv 사람우편함 없음» · 통과
#   ⓒ 공용 루트(명부 있음) = roots.tsv 안 읽음(미끼 행이 있어도 결과 같음) · FT_R2004_BASE_GATE=<고치기 전 판정기> 면 출력 바이트 대조
#   변이 M1(① 폴백 삭제) → ⓐ FAIL · 원본으로 같은 사례 1회 더(반대 결과).
# 임시 루트·임시 roots.tsv 만 · 실 명부·실 큐 0 · sleep 0.
[ -n "${R2004_DESK_ROUTE_TEST_GUARD:-}" ] && exit 0        # 재진입 표지(자기 호출 가드)
export R2004_DESK_ROUTE_TEST_GUARD=1
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="$HERE/../bin/ft_desk_route_gate.py"; KITGATE="$HERE/../kit/fable-team/bin/ft_desk_route_gate.py"
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
C="$T/common"; A="$T/aifp"; DECOY="$T/decoy"
mkdir -p "$C/.fable-team/comm" "$A/.fable-team/comm" "$DECOY/.fable-team/comm"
python3 - "$C/.fable-team" "$A/.fable-team" "$DECOY/.fable-team" <<'PY'
import json, sys
c, a, d = sys.argv[1:4]
def put(dd, name, doc): json.dump(doc, open("%s/%s" % (dd, name), "w"))
put(c, "seats-planner.json", {"_master": "byz-planner-master-pi#310", "_desk": "byz-planner-desk-pi#166"})
put(c, "seats-harness.json", {"_master": "byz-harness-master-pi#205"})
put(a, "seats-aifp.json", {"_master": "aifp-ft-master-pi#16"})
put(d, "seats-planner.json", {"_master": "byz-planner-master-pi#999", "_desk": "byz-planner-desk-pi#888"})
PY
printf '# name\tpath\trole\tref\thuman_mail\ttick\nbyz\t%s\t현역\torigin/main\t.\t기본\naifp\t%s\t현역\torigin/main\t%s/.fable-team/comm\t/tmp/x\n' "$C" "$A" "$C" > "$T/roots.tsv"
printf 'byz\t%s\t현역\torigin/main\t%s/.fable-team/comm\t기본\n' "$C" "$DECOY" > "$T/roots-decoy.tsv"
printf 'byz\t%s\t현역\torigin/main\t.\t기본\n' "$C" > "$T/roots-norow.tsv"
printf 'aifp\t%s\t현역\torigin/main\t.\t/tmp/x\n' "$A" > "$T/roots-dot.tsv"
D='byz-planner-desk-pi#166'; P='byz-planner-master-pi#310'; AM='aifp-ft-master-pi#16'; HM='byz-harness-master-pi#205'
gate() { # gate <판정기> <루트> <roots.tsv> <to> <from> <본문> → OUT · RC · ERR
  printf '%b\n' "$6" > "$T/body"
  OUT="$(FT_ROOTS_TSV="$3" python3 "$1" --to "$4" --from "$5" --body-file "$T/body" --seats-dir "$2/.fable-team" --comm "$2/.fable-team/comm" 2>"$T/err")"; RC=$?
  ERR="$(cat "$T/err")"
}
CASES=("$D|$AM|[진행] r2004 팀장 → desk" "$D|$P|[진행] planner → desk" "$HM|$D|[진행] desk → 팀 master" "$D|$AM|[HIL] r2004 오빠 판정" "byz-feature-nano-x#0|$D|[진행] desk → 나노")

# ⓐ aifp 루트 판정 = 공용 루트 직접 판정과 같다 · WARN 0
for c in "${CASES[@]}"; do
  IFS='|' read -r to frm body <<<"$c"
  gate "$GATE" "$C" "$T/roots.tsv" "$to" "$frm" "$body"; W_OUT="$OUT"; W_RC=$RC
  gate "$GATE" "$A" "$T/roots.tsv" "$to" "$frm" "$body"
  [ "$OUT|$RC" = "$W_OUT|$W_RC" ] && [ -z "$ERR" ] && ok "ⓐ $body → 공용 명부 판정(rc=$RC)" || bad "ⓐ $body :: aifp rc=$RC ${OUT:0:120} / 공용 rc=$W_RC · err=${ERR:0:160}"
done
gate "$GATE" "$A" "$T/roots.tsv" "$D" "$AM" '[진행] 직송'
[ "$RC" = 3 ] && case "$OUT" in "REJECT desk 에는 planner 가 보내요"*) ok "ⓐ aifp 팀장 → desk 일반 쪽지 = REJECT(판정이 실제로 돈다)";; *) bad "ⓐ 사유 :: $OUT";; esac || bad "ⓐ aifp 팀장 → desk rc=$RC"
gate "$GATE" "$A" "$T/roots.tsv" "$AM" "$D" '[진행] desk → aifp 팀장'
[ "$RC" = 0 ] && ok "ⓐ desk → aifp 팀 master(지금 폴더 명부의 _master) 통과" || bad "ⓐ desk → aifp 팀 master rc=$RC ${OUT:0:120}"

# ⓑ 행 없음 · 칸 «.» · roots.tsv 없음 = 지금 WARN 그대로 + 사유 · 통과
for rt in roots-norow.tsv roots-dot.tsv nope.tsv; do
  gate "$GATE" "$A" "$T/$rt" "$D" "$AM" '[진행] 직송'
  [ "$RC" = 0 ] && [ "$OUT" = OK ] && case "$ERR" in "WARN desk 경로 판정 0 — seats-planner.json 없음/깨짐("*"roots.tsv 사람우편함 없음"*) ok "ⓑ $rt → WARN + 통과";; *) bad "ⓑ $rt WARN 문구 :: $ERR";; esac || bad "ⓑ $rt rc=$RC ${OUT:0:120}"
done

# ⓒ 공용 루트(명부 있음) = roots.tsv 안 읽음 — 미끼 행(다른 planner)이 있어도 같은 결과
for c in "${CASES[@]}"; do
  IFS='|' read -r to frm body <<<"$c"
  gate "$GATE" "$C" "$T/roots.tsv" "$to" "$frm" "$body"; W="$OUT|$RC|$ERR"
  gate "$GATE" "$C" "$T/roots-decoy.tsv" "$to" "$frm" "$body"
  [ "$OUT|$RC|$ERR" = "$W" ] && ok "ⓒ $body → 미끼 roots.tsv 무시" || bad "ⓒ $body 미끼가 판정을 바꿨다 :: $OUT"
  if [ -n "${FT_R2004_BASE_GATE:-}" ]; then
    gate "$FT_R2004_BASE_GATE" "$C" "$T/roots.tsv" "$to" "$frm" "$body"
    [ "$OUT|$RC|$ERR" = "$W" ] && ok "ⓒ $body → 앞판과 바이트 같음" || bad "ⓒ $body 앞판과 다름 :: $OUT"
  fi
done
cmp -s "$GATE" "$KITGATE" && ok "bin·kit 판정기 같은 바이트" || bad "bin·kit 판정기가 다르다"

# 변이 M1 — ① 폴백 삭제 → ⓐ 깨짐
MUT="$T/gate-M1.py"
if python3 - "$GATE" "$MUT" <<'PY'
import sys
src, dst = sys.argv[1:3]
s = open(src, encoding="utf-8").read()
a = "cd = common_seats_dir(seats_dir)"
if s.count(a) != 1: sys.exit(1)
open(dst, "w", encoding="utf-8").write(s.replace(a, "cd = None"))
PY
then
  gate "$MUT" "$A" "$T/roots.tsv" "$D" "$AM" '[진행] M1'; [ "$RC" = 0 ] && [ -n "$ERR" ] && ok "M1 변이: ⓐ 가 WARN·통과로 깨진다" || bad "M1 변이가 ⓐ 를 못 깬다 rc=$RC"
  gate "$GATE" "$A" "$T/roots.tsv" "$D" "$AM" '[진행] M1'; [ "$RC" = 3 ] && [ -z "$ERR" ] && ok "M1 원본: ⓐ REJECT · WARN 0" || bad "M1 원본 ⓐ rc=$RC"
else
  bad "M1 변이 자리 못 찾음"
fi

echo "fail=$fail"; [ "$fail" = 0 ]
