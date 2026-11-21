#!/usr/bin/env bash
# test_live_bin_drift_check_r2386_mut.sh — r2386 변이 M1~M6: 각 변이는 짝 시험이 FAIL 해야 하고, 원본은 PASS 해야 한다.
#   M1 묶음 정렬이 밀린다(MISSING 을 해시 목록에 넣음) → ③ · M2 묶음에서 파일 1개 빠짐 → ① · M3 해시 첫 줄 버림 → ①
#   M4 here-string 재도입 → ⑤ · M5 EXTRA 를 «앞부분 일치» 로 → ⑦ · M6 EXTRA 를 필드($1)로 비교 → ⑧(공백 이름)
set -uo pipefail
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/lib/r2386_fixture.sh"
. "$RF_HERE/r2386_cells.sh"
. "$RF_HERE/r2386_mut.sh"
T0=$SECONDS
[ -f "$SUT" ] || { echo "ERROR 검사 스크립트 없음: $SUT"; exit 1; }

mut M1 'if [ ! -f "$f" ]; then add "MISSING $name"; continue; fi => if [ ! -f "$f" ]; then add "MISSING $name"; fi' && ex M1 c3 "③ MISSING·EXTRA·MODE·DIFF 네 종 줄"
mut M2 'printf '"'"'%s'"'"' "$lp" | git -C "$REPO" hash-object => printf '"'"'%s'"'"' "$lp" | tail -n +2 | git -C "$REPO" hash-object' && ex M2 c1 "① OK 판(해시 묶음)"
mut M3 '3< <(printf '"'"'%s\n'"'"' "$hashes") => 3< <(printf '"'"'%s\n'"'"' "$hashes" | tail -n +2)' && ex M3 c1 "① OK 판(해시 줄 정렬)"
mut M4 'mode="${meta%% *}"; t1="${meta#* }"; type="${t1%% *}"; blob="${t1#* }" => read -r mode type blob <<< "$meta"; t1=""' && ex M4 c5 "⑤ here-string 0줄"
mut M5 '{ if (!($0 in seen)) print "EXTRA " $0 } => { f=0; for (k in seen) if (index(k, $0) == 1) f=1; if (!f) print "EXTRA " $0 }' && ex M5 c7 "⑦ EXTRA 이름 줄 전체 일치"
mut M6 '{ if (!($0 in seen)) print "EXTRA " $0 } => { if (!($1 in seen)) print "EXTRA " $1 }' && ex M6 c8 "⑧ 공백 이름 OK 판"

[ "${EXN:-0}" -eq 6 ] && echo "PASS 변이 6개 모두 돌았다(M1~M6)" || { echo "FAIL 변이 실행 수 = ${EXN:-0} (기대 6) — mut/ex 가 안 돌았다"; fail=$((fail + 1)); }
echo "[시간] 변이 M1~M6 총 $((SECONDS - T0))초"
[ "$((SECONDS - T0))" -le 70 ] && echo "PASS 시험 시간 상한(70초 · 실측 $((SECONDS - T0))초)" || { echo "FAIL 시험 시간 상한(70초 초과)"; fail=$((fail + 1)); }
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "($fail failed)"; exit 1
