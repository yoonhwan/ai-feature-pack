#!/usr/bin/env bash
# test_autonomy_critical_hil_record_r2105.sh — r2105 design/ 아래 소문자 .hil 계획 글의 추가 줄은 destroy 판정 밖(같은 PR 의 .hil·.md 밖 파일에 글자 .hil 0 일 때만)
#   반례 ①~③ · 키트 사본 cmp0 · 변이 M1~M4(변이마다 원본으로 같은 사례 대조) · ④ 기존 시험은 따로 돌린다(시험 1개 70초 상한)
#   격리: 임시 리포(origin bare + clone) · 실 상태·실 원격·press 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$(cd "$HERE/../bin" && pwd -P)"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:200}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T/iso"; R="$W"
pr() {  # pr <경로> <줄…> [-- <경로> <줄…>]… → PRSHA(origin/main 에서 1커밋 · 여러 파일)
  git -C "$R" checkout -q -B "pr$RANDOM" origin/main; local f="" ; local -a lns=()
  put() { [ -n "$f" ] && { mkdir -p "$R/$(dirname -- "$f")"; printf '%s\n' "${lns[@]}" > "$R/$f"; }; lns=(); }
  for a in "$@"; do
    if [ -z "$f" ]; then f="$a"; elif [ "$a" = -- ]; then put; f=""; else lns+=("$a"); fi
  done; put
  cm "$R" "r2105 case"; PRSHA="$(sha "$R" HEAD)"; git -C "$R" checkout -q main; }
crit() { out="$(python3 "${2:-$BIN}/autonomy_scope_classify.py" classify "$1" --repo "$R" --critical ${3:+--critical-profile "$3"} 2>&1)"; rc=$?; }
okc() { [ "$rc" = 0 ] && [ "$out" = CRITICAL-OK ]; }
dst() { [ "$rc" = 3 ] && [[ $out =~ ^CRITICAL\ kind=destroy\  ]]; }
KILL="trap 'kill \"\$TPID\"' EXIT"; RMRF='rm -rf "$D"'; DROP='DROP TABLE t;'
P=design/teams/ops/plans/x.sh.hil
pr "$P" '#!/usr/bin/env bash' "$KILL" "$RMRF" "$DROP"; C1="$PRSHA"
crit "$C1"; okc; ck "① design/ .hil 1파일(kill·rm -rf·DROP TABLE) 기본 profile → CRITICAL-OK" $?
crit "$C1" "" d2; okc; ck "① 같은 PR profile d2 → CRITICAL-OK(scoped 0)" $?
pr "$P" "$KILL" "$RMRF" "$DROP" -- design/x/NOTE.md '# 메모' '' 'bash x.sh.hil 로 돌린다'; C1B="$PRSHA"
crit "$C1B"; okc; ck "① + design/x/NOTE.md «bash x.sh.hil» 줄 → CRITICAL-OK(.md 는 ⓒ 밖)" $?
pr scripts/x.sh.hil "$KILL"; C2A="$PRSHA"; crit "$C2A"; dst && [[ $out == *"scripts/x.sh.hil:1 "* ]]; ck "② scripts/x.sh.hil kill → destroy(ⓐ)" $?
pr design/x/run.hil.sh "$KILL"; crit "$PRSHA"; dst; ck "② design/x/run.hil.sh → destroy(ⓑ)" $?
pr design/x/a.hil/run.sh "$KILL"; crit "$PRSHA"; dst; ck "② design/x/a.hil/run.sh(폴더만 .hil) → destroy" $?
pr design/x/X.HIL "$KILL"; crit "$PRSHA"; dst; ck "② design/x/X.HIL(대문자) → destroy" $?
pr design/x/y.sh.hil '# 계획' "$KILL" -- bin/run.sh 'bash design/x/y.sh.hil'; C2E="$PRSHA"
crit "$C2E"; dst && [[ $out == *"design/x/y.sh.hil:2 "* ]]; ck "② y.sh.hil + bin/run.sh 가 부름 → destroy(위치 = y.sh.hil:2 · ⓒ)" $?
pr design/x/y.sh.hil "$KILL" -- design/x/go.sh 'for f in *.hil; do :; done'; crit "$PRSHA"; dst && [[ $out == *"design/x/y.sh.hil:1 "* ]]; ck "② y.sh.hil + design/x/go.sh «for f in *.hil» → destroy" $?
pr bin/tool.sh 'kill -9 1'; crit "$PRSHA"; dst; ck "② bin/tool.sh kill(.hil 0) → destroy(기준판과 같음)" $?
pr design/x/y.sh.hil "-----BEGIN RSA PRIV""ATE KEY-----" "$KILL"; C2H="$PRSHA"
crit "$C2H"; [ "$rc" = 3 ] && [[ $out =~ ^CRITICAL\ kind=secret\  ]]; ck "② design/ .hil 비밀 줄 → kind=secret 그대로" $?
crit "$C2A" "" d2; [ "$rc" = 0 ] && [ "$out" = "CRITICAL-OK scoped=scripts/x.sh.hil:1" ]; ck "② d2 scripts/x.sh.hil kill → CRITICAL-OK scoped=scripts/x.sh.hil:1" $?
crit "$C1"; [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] && [ "$out" = CRITICAL-OK ]; ck "③ ① 의 stdout = 정확히 CRITICAL-OK 1줄" $?
crit "$C2A"; [[ ${out%%$'\n'*} =~ ^CRITICAL\ kind=destroy\ scripts/x\.sh\.hil:1\ trap ]]; ck "③ destroy 첫 줄 꼴 = CRITICAL kind=destroy <경로:줄> <줄 글>" $?
cmp -s "$BIN/autonomy_scope_rules.py" "$BIN/../kit/fable-team/bin/autonomy_scope_rules.py"; ck "키트 사본 cmp0 autonomy_scope_rules.py" $?
mut() {  # mut <이름> <원문> <바꿀 글> → $T/mut-<이름>(rules 만 바꾼 bin)
  local mb="$T/mut-$1"; mkdir -p "$mb"; for f in "$BIN"/*; do ln -s "$f" "$mb/$(basename "$f")"; done; rm -f "$mb/autonomy_scope_rules.py"
  python3 - "$BIN/autonomy_scope_rules.py" "$mb/autonomy_scope_rules.py" "$2" "$3" <<'PY' || { echo "FAIL 변이 $1 못 만듦"; fail=$((fail+1)); }
import sys
s = open(sys.argv[1], encoding="utf-8").read()
assert s.count(sys.argv[3]) == 1, sys.argv[3]
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4]))
PY
}
mut m1 ' or hil_record_exempt(path, blocks)' ''
crit "$C1" "$T/mut-m1"; dst && { crit "$C1"; okc; }; ck "M1 예외 호출 삭제 → ① destroy(빨강) · 원본 = CRITICAL-OK" $?
mut m2 'not p.startswith("design/") or ' ''
crit "$C2A" "$T/mut-m2"; okc && { crit "$C2A"; dst; }; ck "M2 ⓐ design/ 조건 삭제 → ② scripts/x.sh.hil 새어 통과(빨강) · 원본 = destroy" $?
mut m3 'return not any(".hil" in t.casefold()' 'return True or not any(".hil" in t.casefold()'
crit "$C2E" "$T/mut-m3"; okc && { crit "$C2E"; dst; }; ck "M3 ⓒ 조건 삭제 → ② bin/run.sh 사례 새어 통과(빨강) · 원본 = destroy" $?
mut m4 'why = secret() if secret else ""' 'why = secret() if secret and not all(hil_record_exempt(p, blocks) for p, _i, _n in blocks) else ""'
crit "$C2H" "$T/mut-m4"; okc && { crit "$C2H"; [ "$rc" = 3 ] && [[ $out =~ ^CRITICAL\ kind=secret\  ]]; }; ck "M4 예외를 비밀 줄까지 넓힘 → ② 비밀 사례 새어 통과(빨강) · 원본 = secret" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
