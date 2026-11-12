#!/usr/bin/env bash
# test_nano_close_landed_ref_wt_r1737.sh — r1737: ft-nano-close.sh --landed-pr 의 ①착지 판정 ref = FT_LAND_REF ②--landed-pr + --wt 좌석 워크트리 인정
#   ①ops/main-base 착지 나노가 «main 에 산출 없음» 으로 막히던 자리 · ②고침 중 새 가지를 판 좌석(가지 이름 ≠ 키)이 «후보 0» 으로 막히던 자리.
# 반례 ①ff(ops) ②squash(ops) ③ref 꼴 밖=usage2 ④env 없음=기준판 ⑤--wt 인정(닫힘) ⑥HEAD≠세트 ⑦남의 가지 ⑦b중간 -r숫자- 키=남의 가지 ⑧.wtrees 밖 ⑧b미등록 clone ⑨fetch 실패=판정 불가
# 변이 M1→② M2→⑥ M3→⑦ M4→③ M5→⑦b(기준판 d31ac751 과 같은 줄 복원) FAIL · 기준판(445533f6) ①⑤ Red · 설비는 _landed_ref_wt_r1737_fixture.sh(공용 픽스처).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/_landed_ref_wt_r1737_fixture.sh"

echo "== 짝 cmp · bash -n (/bin/bash 3.2 포함)"
cmp -s "$HERE/../../harness/bin/ft-nano-close.sh" "$SRC/ft-nano-close.sh" && ok "cmp bin == kit" || bad "cmp 다름"
bash -n "$SRC/ft-nano-close.sh" && ok "bash -n" || bad "bash -n"
/bin/bash -n "$SRC/ft-nano-close.sh" && ok "/bin/bash 3.2 -n" || bad "/bin/bash 3.2 -n"

echo "== ① PR head 가 origin/ops/main-base 조상(ff) · FT_LAND_REF=origin/ops/main-base → 착지 확인 ff · ref 표기"; setup; push_ref "$SET" ops/main-base; git -C "$ROOT" fetch -q origin
out="$(FT_LAND_REF=origin/ops/main-base close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "① rc=0" || bad "① rc=$rc ← ${out:0:800}"
has "$out" "착지 확인: ff · PR state=CLOSED · ref=origin/ops/main-base" "  └ INFO af «ref=origin/ops/main-base»"
closed_ok "①"
setup; push_ref "$SET" ops/main-base; git -C "$ROOT" fetch -q origin
out="$(CLOSE_BIN="$T/basebin/ft-nano-close.sh" FT_LAND_REF=origin/ops/main-base close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "main 에 산출 없음" "  └ 기준판 Red: 같은 입력이 REJECT(«main 에 산출 없음») = ① 이 고치는 자리" || bad "기준판 Red 아님 rc=$rc ← ${out:0:600}"

echo "== ② ops/main-base 에 squash 끝줄 · FT_LAND_REF=origin/ops/main-base → 착지 확인 squash"; setup; squash_on ops/main-base "$SQ"
out="$(FT_LAND_REF=origin/ops/main-base close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "② rc=0" || bad "② rc=$rc ← ${out:0:800}"
has "$out" "착지 확인: squash" "  └ squash 통과"
closed_ok "②"

echo "== ③ FT_LAND_REF=main(origin/ 없음) → usage rc 2 · 닫기 0"; setup; out="$(FT_LAND_REF=main close --landed-pr 363)"; rc=$?
[ "$rc" -eq 2 ] && has "$out" "FT_LAND_REF 는 «origin/<가지>» 꼴이어야 한다" "③ ref 꼴 밖 = usage 2" || bad "③ rc=$rc ← ${out:0:600}"
untouched "③"

echo "== ④ FT_LAND_REF 없음 · PR head 가 ops/main-base 에만 → 기준판과 같은 REJECT(동작 불변)"; setup; push_ref "$SET" ops/main-base; git -C "$ROOT" fetch -q origin
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "main 에 산출 없음" "④ env 없음 = origin/main 그대로" || bad "④ rc=$rc ← ${out:0:600}"
untouched "④"

echo "== ⑤ 가지 nano/refwt-cfg(≠키) · HEAD = 세트 · --wt → 좌석 워크트리 인정 · 닫힘"; setup; land_main; alive; out="$(close --landed-pr 363 --wt "$NW")"; rc=$?
[ "$rc" -eq 0 ] && ok "⑤ rc=0" || bad "⑤ rc=$rc ← ${out:0:3000}"
has "$out" "INFO 좌석 워크트리 ← --wt (HEAD = 세트" "  └ INFO 좌석 워크트리 ← --wt"
has "$out" "LANDED-PR-OK #363" "  └ ⑥ 착지 판정 통과"
closed_ok "⑤"
setup; land_main; alive
out="$(CLOSE_BIN="$T/basebin/ft-nano-close.sh" close --landed-pr 363 --wt "$NW")"; rc=$?
[ "$rc" -eq 1 ] && ok "  └ 기준판 Red: 같은 입력 REJECT(후보 0) = ⑤ 가 고치는 자리" || bad "기준판 Red 아님 rc=$rc ← ${out:0:600}"

echo "== ⑥ --wt 워크트리 HEAD ≠ 카드 세트 → REJECT «HEAD ≠ 세트» 1줄"; setup; land_main; alive; git -C "$NW" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "세트 뒤 커밋"
out="$(close --landed-pr 363 --wt "$NW")"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "≠ 카드 세트" "⑥ HEAD ≠ 세트 → REJECT" || bad "⑥ rc=$rc ← ${out:0:700}"
untouched "⑥"

echo "== ⑦ 그 가지를 키로 하는 다른 좌석 세션이 살아 있음 → REJECT «남의 좌석 가지»"; setup; land_main; alive; echo 'byz-ops-nano-refwt-cfg#1' > "$T/sessions"
out="$(close --landed-pr 363 --wt "$NW")"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "남의 좌석 가지" "⑦ 남의 세션 → REJECT" || bad "⑦ rc=$rc ← ${out:0:700}"
untouched "⑦"

echo "== ⑦b 가지 nano/refwt-r2-cfg(«중간» -r숫자-) · 다른 owner byz-ops-nano-refwt-r2-cfg#1 살아 있음 → REJECT «남의 좌석 가지»"
setup; land_main; alive2; echo 'byz-ops-nano-refwt-r2-cfg#1' > "$T/sessions"
out="$(close --landed-pr 363 --wt "$NW2")"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "남의 좌석 가지" "⑦b 중간 -r숫자- 키 → REJECT(DA R1 수용 반례)" || bad "⑦b rc=$rc ← ${out:0:700}"
untouched "⑦b"

echo "== ⑧ --wt 가 $ROOT/.worktrees/ 밖 → REJECT"; setup; land_main; alive; mkdir -p "$T/elsewhere"
out="$(close --landed-pr 363 --wt "$T/elsewhere")"; rc=$?
[ "$rc" -eq 1 ] && has "$out" ".worktrees/ 아래 등록 워크트리가 아니다" "⑧ 밖 경로 → REJECT" || bad "⑧ rc=$rc ← ${out:0:700}"
untouched "⑧"

echo "== ⑧b \$ROOT/.worktrees/ 아래 «별도 clone»(등록 워크트리 아님) → REJECT"
setup; land_main; alive; git clone -q "$ROOT" "$ROOT/.worktrees/unreg"; git -C "$ROOT/.worktrees/unreg" checkout -q -b nano/refwt-cfg "$SET"
out="$(close --landed-pr 363 --wt "$ROOT/.worktrees/unreg")"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "등록 워크트리가 아니다" "⑧b 미등록 clone → REJECT(DA Q1 회귀)" || bad "⑧b rc=$rc ← ${out:0:700}"
untouched "⑧b"; rm -rf "$ROOT/.worktrees/unreg"

echo "== ⑨ FT_LAND_REF 있는데 fetch 실패 → 판정 불가 rc≠0 · 닫기 0"; setup; push_ref "$SET" ops/main-base; git -C "$ROOT" fetch -q origin; set_origin "$T/nope.git"
out="$(FT_LAND_REF=origin/ops/main-base close --landed-pr 363)"; rc=$?
[ "$rc" -ne 0 ] && has "$out" "판정 불가로 닫지 않는다" "⑨ fetch 실패 → 판정 불가" || bad "⑨ rc=$rc ← ${out:0:700}"
untouched "⑨"

echo "== 변이 M1 «조상 검사만 새 ref · 끝줄 찾기는 origin/main» → ② 가 잡는다"
mutant 'git -C "$repo" log "$LP_LAND_REFS"' 'git -C "$repo" log refs/remotes/origin/main'
setup; squash_on ops/main-base "$SQ"
out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" FT_LAND_REF=origin/ops/main-base close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && ok "M1 FAIL(REJECT) = ② 가 잡는다" || bad "M1 안 먹음 rc=$rc ← $(printf '%s' "$out" | tail -3)"

echo "== 변이 M2 «HEAD == 세트 검사 지움» → ⑥ 이 잡는다"
mutant 'if [ "$_lp_wt_seat" = 1 ] && [ -n "$_lp_set" ]; then _lp_wt_head_gate || bad+=("$_lp_wt_head_err"); fi' ':' 
setup; land_main; alive; git -C "$NW" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "세트 뒤 커밋"
out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 363 --wt "$NW")"; rc=$?
[ "$rc" -eq 0 ] && ok "M2 FAIL(닫힘) = ⑥ 이 잡는다" || bad "M2 안 먹음 rc=$rc ← $(printf '%s' "$out" | tail -3)"

echo "== 변이 M3 «남의 좌석 세션 검사 지움» → ⑦ 이 잡는다"
mutant '  [ -z "$live" ] || { SEAT_WT_ERR="--wt($top)의 가지' '  true || { SEAT_WT_ERR="--wt($top)의 가지'
setup; land_main; alive; echo 'byz-ops-nano-refwt-cfg#1' > "$T/sessions"
out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 363 --wt "$NW")"; rc=$?
[ "$rc" -eq 0 ] && ok "M3 FAIL(닫힘) = ⑦ 이 잡는다" || bad "M3 안 먹음 rc=$rc ← $(printf '%s' "$out" | tail -3)"

echo "== 변이 M4 «ref 꼴 검사 지움» → ③ 이 잡는다"
mutant 'case "${LP_LAND_REF#origin/}" in' 'case "origin/ok" in'
setup; out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" FT_LAND_REF=main close --landed-pr 363)"; rc=$?
[ "$rc" -ne 2 ] && ok "M4 FAIL(usage 2 아님 rc=$rc) = ③ 이 잡는다" || bad "M4 안 먹음(rc=2 유지)"

echo "== 변이 M5 «중간 -r숫자- 자르기를 옛 꼴로 되돌림(기준판 d31ac751 과 같은 줄)» → ⑦b 가 잡는다"
mutant 'okey="${br#nano/}"; [[ "$okey" =~ ^(.*)-r[0-9]+$ ]] && okey="${BASH_REMATCH[1]}"' 'okey="${br#nano/}"; okey="${okey%-r[0-9]*}"'
setup; land_main; alive2; echo 'byz-ops-nano-refwt-r2-cfg#1' > "$T/sessions"
out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 363 --wt "$NW2")"; rc=$?
[ "$rc" -eq 0 ] && ok "M5 FAIL(닫힘) = ⑦b 가 잡는다(R1 구멍 재현)" || bad "M5 안 먹음 rc=$rc ← $(printf '%s' "$out" | tail -3)"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
