#!/usr/bin/env bash
# test_regress_pack.sh — C21 회귀 팩 시험: mktemp 저장소로 add→select(겹침 있음/없음)→run(unit PASS/FAIL·press 목록만)→retire 1바퀴 + 상한 경고.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TOOL="$HERE/../../scripts/fable-team-bin/ft-regress-pack.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { # chk <설명> <조건 rc>
  [ "$2" -eq 0 ] && ok "$1" || bad "$1"
}

bash -n "$TOOL" && ok "bash -n" || bad "bash -n"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
git -C "$T" init -q && git -C "$T" config user.email t@t && git -C "$T" config user.name t
mkdir -p "$T/src"; echo a > "$T/src/a.txt"; echo b > "$T/src/b.txt"; echo ok > "$T/probe.txt"
git -C "$T" add -A && git -C "$T" commit -qm base
BASE="$(git -C "$T" rev-parse HEAD)"
echo a2 > "$T/src/a.txt"; git -C "$T" commit -qam cand
CAND="$(git -C "$T" rev-parse HEAD)"
git -C "$T" commit -q --allow-empty -m empty
EMPTY="$(git -C "$T" rev-parse HEAD)"
export FT_REGRESS_REPO="$T" FT_REGRESS_PACK="$T/tests/regression/issue_pack.jsonl"
run() { bash "$TOOL" "$@" 2>&1; }

# add 1바퀴: unit PASS 행 · unit FAIL 행 · press 행 · 겹치지 않는 행
out="$(run add --issue 1 --closed-sha "$BASE" --repro-cmd 'cat probe.txt' --expected ok --files src/a.txt --mode unit --team t)"
echo "$out" | grep -q '^ADDED #1' && ok "add unit PASS 행" || bad "add unit PASS 행: $out"
out="$(run add --issue 2 --closed-sha "$BASE" --repro-cmd 'cat probe.txt' --expected NOPE --files src/a.txt --mode alt --team t)"
echo "$out" | grep -q '^ADDED #2' && ok "add alt FAIL 행" || bad "add alt FAIL 행: $out"
out="$(run add --issue 3 --closed-sha "$BASE" --repro-cmd 'touch "$FT_REGRESS_REPO/PRESS_RAN"' --expected x --files src/a.txt --mode press --team t)"
echo "$out" | grep -q '^ADDED #3' && ok "add press 행" || bad "add press 행: $out"
out="$(run add --issue 4 --closed-sha "$BASE" --repro-cmd 'true' --expected '' --files src/b.txt --mode unit --team t)"
echo "$out" | grep -q '^REJECT expected' && ok "add 빈 expected REJECT" || bad "add 빈 expected: $out"
out="$(run add --issue 4 --closed-sha "$BASE" --repro-cmd 'true' --expected t --files src/b.txt --mode unit --team t)"
echo "$out" | grep -q '^ADDED #4' && ok "add 겹치지 않는 행" || bad "add 겹치지 않는 행: $out"
out="$(run add --issue 1 --closed-sha "$BASE" --repro-cmd 'x' --expected x --files src/a.txt --mode unit --team t)"
echo "$out" | grep -q '^REJECT 중복 issue #1' && ok "add 중복 issue 거부" || bad "add 중복: $out"
out="$(run add --issue 5 --closed-sha zzz --repro-cmd x --expected x --files f --mode unit --team t)"
echo "$out" | grep -q '^REJECT closed_sha' && ok "add 나쁜 sha 거부" || bad "add 나쁜 sha: $out"
out="$(run add --issue 5 --closed-sha "$BASE" --repro-cmd x --expected x --files f --mode bogus --team t)"
echo "$out" | grep -q '^REJECT mode' && ok "add 나쁜 mode 거부" || bad "add 나쁜 mode: $out"

# select: 겹침 있음(#1·#2·#3, #4 제외) / 없음
out="$(run select "$BASE" "$CAND")"
echo "$out" | grep -q '^#1' && echo "$out" | grep -q '^#2' && echo "$out" | grep -q '^#3' && ! echo "$out" | grep -q '^#4' \
  && ok "select 겹침 있음 → #1 #2 #3 만" || bad "select 겹침 있음: $out"
out="$(run select "$CAND" "$EMPTY")"
echo "$out" | grep -q '^NONE' && ok "select 겹침 없음 → NONE" || bad "select 겹침 없음: $out"
run select "$BASE" deadbeef >/dev/null; [ $? -eq 2 ] && ok "select 나쁜 sha exit 2" || bad "select 나쁜 sha exit"

# run: unit PASS · alt FAIL(exit 1) · press 는 목록만(실행 증거 파일 없음)
out="$(run run "$BASE" "$CAND")"; rc=$?
[ $rc -eq 1 ] && ok "run FAIL 행 있으면 exit 1" || bad "run exit=$rc"
echo "$out" | grep -q '^PASS unit #1' && ok "run unit PASS" || bad "run unit PASS: $out"
echo "$out" | grep -q '^FAIL alt #2' && ok "run alt FAIL" || bad "run alt FAIL: $out"
echo "$out" | grep -q '^LIST press #3' && [ ! -e "$T/PRESS_RAN" ] && ok "run press 는 목록만(미실행)" || bad "run press: $out"
echo "$out" | grep -q 'RESULT pass=1 fail=1 press_listed=1' && ok "run 요약 값" || bad "run 요약: $out"

# retire: 기록(삭제 아님) → select/run 에서 빠짐 · 재retire 거부
out="$(run retire 2)"; echo "$out" | grep -q '^RETIRED #2' && ok "retire #2" || bad "retire: $out"
[ "$(jq -s 'length' "$FT_REGRESS_PACK")" -eq 4 ] && jq -e 'select(.issue==2 and .retired_at!=null)' "$FT_REGRESS_PACK" >/dev/null \
  && ok "retire = retired_at 기록(행 삭제 아님)" || bad "retire 기록"
out="$(run select "$BASE" "$CAND")"; ! echo "$out" | grep -q '^#2' && ok "retire 행은 select 제외" || bad "retire 후 select: $out"
out="$(run retire 2)"; echo "$out" | grep -q '^REJECT #2 이미' && ok "재retire 거부" || bad "재retire: $out"
out="$(run retire 99)"; echo "$out" | grep -q '^REJECT #99 행 없음' && ok "없는 issue retire 거부" || bad "없는 retire: $out"
out="$(run run "$BASE" "$CAND")"; rc=$?
[ $rc -eq 0 ] && ok "retire 뒤 run exit 0" || bad "retire 뒤 run exit=$rc $out"

# 상한 경고: 상한 1 로 낮춰 press 2행 → 경고 / 상한 이하면 경고 없음
out="$(FT_REGRESS_PRESS_MAX=1 run add --issue 6 --closed-sha "$BASE" --repro-cmd true --expected t --files src/b.txt --mode press --team t)"
echo "$out" | grep -q '^WARN press 활성 행 2 > 상한 1' && ok "상한 초과 경고" || bad "상한 경고: $out"
out="$(run select "$BASE" "$CAND")"; ! echo "$out" | grep -q '^WARN' && ok "상한 이하 경고 없음(기본 20)" || bad "상한 이하: $out"

# 저장소의 예시 팩 형식(2행 · 실제 1 + 합성 1) 이 jq 로 읽히는지
PK="$HERE/../regression/issue_pack.jsonl"
[ "$(jq -s 'length' "$PK" 2>/dev/null)" = "2" ] && ok "issue_pack.jsonl 예시 2행" || bad "issue_pack.jsonl 예시 2행"

echo "fail=$fail"; [ $fail -eq 0 ]
