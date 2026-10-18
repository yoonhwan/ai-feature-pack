#!/usr/bin/env bash
# test_ft_sets.sh — ft-sets.sh 시험(설계 §8-1): 표·필터·정렬·건수·원장 없음·머리줄·--check·발주 sha:경로 본문·미전달·보호 ref·Issue 겹침. 임시 git 리포에서만 돈다(원격 0).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SETS="$HERE/../../harness/kit/sets/ft-sets.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { printf '%s' "$1" | grep -qF -- "$2"; }

bash -n "$SETS" && ok "bash -n" || bad "bash -n"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
R="$T/repo"; mkdir -p "$R/design/issues" "$R/design/planner/orders"; cd "$R" || exit 1
git init -q . && git config user.email t@t && git config user.name t && git config commit.gpgsign false && git config core.hooksPath /dev/null
ORD=design/planner/orders/ORDER-359-cfo.md
printf '# ORDER\n## s1\n본문 v1\n' > "$ORD"; git add -A; git commit -qm v1; V1="$(git rev-parse HEAD)"; V1S="${V1:0:10}"
printf '# ORDER\n## s1\n본문 v2 (이후 개정)\n' > "$ORD"; git add -A; git commit -qm v2
git update-ref refs/orders/359-cfo "$V1"

HEAD_ROW='| 세트 | 팀 | 상태 | 골 축 | 닫는 사건 | Issue | 발주 | 판정 | 적용 id | 갱신 |'
row() { echo "| $1 | ${1%%/*} | $2 | 골 축 | 닫는 사건 | $3 | byz-agents@${4:-$V1S}:$ORD#s1 | ${5:-359} | ${6:--} | 10-08 09:34 issues#3 |"; }
mk() { { echo '# 세트 원장 (시험)'; echo "$HEAD_ROW"; echo '|---|---|---|---|---|---|---|---|---|---|'; cat; } > "$1"; }
export FT_SETS_FILE="$R/design/issues/SETS.md" FT_SETS_REPO="$R" FT_SETS_TEAM_ROOT="$R"
{ row 'cfo/s3-held' '보류 — close 실패 #14' '#14'; row 'kk/s1-done' '닫힘 — 증거 abc · close 1/1' '#15'
  row 'cfo/s2-second' '발주' '#13'; row 'cfo/s1-close-bundle' '진행' '#11 #12' "$V1S" 359 cfo-s1-01; } | mk "$FT_SETS_FILE"
git add -A; git commit -qm ledger

# 1 원장 없음 → rc 3, 표 0 (다른 경로로 안 넘어감)
out="$(FT_SETS_FILE="$T/없음.md" bash "$SETS" cfo 2>&1)"; rc=$?
{ [ $rc -eq 3 ] && has "$out" "원장 없음" && ! has "$out" "cfo/s"; } && ok "원장 없음 rc=3 · 표 0" || bad "원장 없음 rc=$rc: $out"
out="$(env -u FT_SETS_FILE bash "$SETS" 2>&1)"; rc=$?; { [ $rc -eq 3 ] && has "$out" "미설정"; } && ok "FT_SETS_FILE 미설정 rc=3" || bad "미설정 rc=$rc"

# 2 머리줄 commit·미커밋 / 건수 / 정렬 / 팀 필터
out="$(bash "$SETS")"; rc=$?
{ [ $rc -eq 0 ] && has "$out" "원장 $FT_SETS_FILE @ $(git log -1 --format=%H -- design/issues/SETS.md | cut -c1-10) · 미커밋 변경 없음"; } && ok "머리줄 commit·미커밋 없음" || bad "머리줄: $(printf '%s' "$out" | head -1)"
has "$out" "세트 진행 1 · 발주 1 · 보류 1 · 닫힘 1" && ok "전체 끝줄 건수 1·1·1·1" || bad "끝줄: $(printf '%s' "$out" | tail -1)"
pos() { printf '%s\n' "$out" | grep -n "$1" | head -1 | cut -d: -f1; }
{ [ "$(pos 'cfo/s1-close-bundle')" -lt "$(pos 'cfo/s2-second')" ] && [ "$(pos 'cfo/s2-second')" -lt "$(pos 'cfo/s3-held')" ] && [ "$(pos 'cfo/s3-held')" -lt "$(pos 'kk/s1-done')" ]; } && ok "정렬 진행→발주→보류→닫힘" || bad "정렬"
out="$(bash "$SETS" cfo)"
{ ! has "$out" "kk/s1-done" && has "$out" "세트 진행 1 · 발주 1 · 보류 1 · 닫힘 0"; } && ok "팀 필터 cfo — kk 행 0 · 닫힘 0" || bad "팀 필터"
echo '<!-- 미커밋 -->' >> "$FT_SETS_FILE"
has "$(bash "$SETS")" "미커밋 변경 있음" && ok "머리줄 미커밋 변경 있음" || bad "미커밋 표시"
git checkout -q -- design/issues/SETS.md

# 3 --check 정상
out="$(bash "$SETS" --check)"; rc=$?; { [ $rc -eq 0 ] && has "$out" "CHECK OK"; } && ok "--check 정상 rc=0 (닫힘·kk 는 보호 ref 없이도 통과)" || bad "check 정상 rc=$rc: $out"

# 4 --check 실패 사례들 — 각 한 줄 원장
chk() { local name="$1" want="$2"; shift 2; "$@" | mk "$T/bad.md"; out="$(FT_SETS_FILE="$T/bad.md" bash "$SETS" --check 2>&1)"; rc=$?
  { [ $rc -ne 0 ] && has "$out" "$want"; } && ok "$name → rc=$rc" || bad "$name rc=$rc 기대 '$want': $out"; }
chk "이름 틀림(대문자)" "이름 형식" row 'CFO/S1-x' '진행' '#1'
chk "상태 6번째 값" "상태 5종 아님" row 'cfo/s1-close-bundle' '대기' '#1'
chk "보류 사유 없음" "상태 5종 아님" row 'cfo/s1-close-bundle' '보류' '#1'
chk "없는 sha = 미전달" "미전달" row 'cfo/s1-close-bundle' '진행' '#1' deadbeef00
chk "보호 ref 없음(판정 360)" "보호 ref refs/orders/360-cfo 없음" row 'cfo/s1-close-bundle' '진행' '#1' "$V1S" 360
chk "닫힘 close 일부(2/3)" "close 3/3 확인 없음" row 'cfo/s1-close-bundle' '닫힘 — 증거 abc · close 2/3' '#1 #2 #3'
chk "Issue 칸 형식" "Issue 칸 형식" row 'cfo/s1-close-bundle' '진행' '11'
dup() { row 'cfo/s1-close-bundle' '진행' '#1'; row 'cfo/s1-close-bundle' '진행' '#2'; }
chk "세트 행 중복" "행 중복" dup

# 5 같은 Issue 두 세트 → 경고, rc=0
two() { row 'cfo/s1-close-bundle' '진행' '#11'; row 'cfo/s2-second' '발주' '#11 #13'; }
two | mk "$T/ov.md"; out="$(FT_SETS_FILE="$T/ov.md" bash "$SETS" --check 2>&1)"; rc=$?
{ [ $rc -eq 0 ] && has "$out" "WARN Issue #11"; } && ok "Issue 겹침 경고 rc=0" || bad "겹침 rc=$rc: $out"

# 6 ★S2★ 발주 칸 sha:경로 = 정확 본문(이후 개정본 아님) / 없는 sha = 미전달
out="$(bash "$SETS" --body cfo/s1-close-bundle)"; rc=$?
{ [ $rc -eq 0 ] && has "$out" "본문 v1" && ! has "$out" "v2"; } && ok "--body = 발주 commit 본문(v1), 같은 경로 이후 개정본(v2) 아님" || bad "--body rc=$rc: $out"
[ "$(cat "$ORD")" != "$(printf '%s\n' "$out")" ] && ok "작업 트리 파일(v2)과 다름 확인" || bad "작업 트리와 같음"
row 'cfo/s1-close-bundle' '진행' '#1' deadbeef00 | mk "$T/ns.md"
out="$(FT_SETS_FILE="$T/ns.md" bash "$SETS" --body cfo/s1-close-bundle 2>&1)"; rc=$?
{ [ $rc -ne 0 ] && has "$out" "미전달"; } && ok "--body 없는 sha rc≠0 미전달" || bad "--body 미전달 rc=$rc"
# 절대경로 없는 수신 환경: 작업 트리 파일을 지워도 sha 로 복원
rm -f "$ORD"; out="$(bash "$SETS" --body cfo/s1-close-bundle)"; has "$out" "본문 v1" && ok "워크트리 파일 삭제 후에도 sha 로 복원" || bad "파일 삭제 후 복원"; git checkout -q -- "$ORD"

# 7 ★S1★ 팀 필터 — SET-REQUESTS 적용 - → PENDING / 적용 commit 이 원장 HEAD 조상 아님 → STALE
mkdir -p design/cfo/orders; REQ=design/cfo/orders/SET-REQUESTS.md
echo "- cfo-s2-01 · cfo/s2-second · 발주 → 진행 · 증거 abc1234 · 보냄 seq 61300 · 적용 -" > "$REQ"
out="$(bash "$SETS" cfo)"; { has "$out" "PENDING cfo-s2-01" && has "$out" "요청 1건 · 미완료 1"; } && ok "적용 - 줄 → PENDING" || bad "PENDING: $out"
git checkout -q -b issues-side; echo '<!-- side -->' >> design/issues/SETS.md; git commit -qam side; SIDE="$(git rev-parse HEAD)"; git checkout -q -;
echo "- cfo-s2-01 · cfo/s2-second · 발주 → 진행 · 증거 abc1234 · 보냄 seq 61300 · 적용 $SIDE" > "$REQ"
out="$(bash "$SETS" cfo)"; has "$out" "STALE cfo-s2-01" && ok "적용 commit 이 원장 HEAD 에 없음 → STALE" || bad "STALE: $out"
echo "- cfo-s2-01 · cfo/s2-second · 발주 → 진행 · 증거 abc1234 · 보냄 seq 61300 · 적용 $V1" > "$REQ"
out="$(bash "$SETS" cfo)"; { ! has "$out" "STALE" && ! has "$out" "PENDING" && has "$out" "미완료 0"; } && ok "적용 commit 이 HEAD 조상 → STALE·PENDING 0" || bad "적용 정상: $out"

echo "---"; [ $fail -eq 0 ] && echo "ALL PASS" || echo "FAIL $fail"
exit $((fail>0))
