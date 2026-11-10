#!/usr/bin/env bash
# test_issue_close_leftover_r1346.sh — r1346 · ft-issue-close-check «남김» 줄 판정 (Issue #6146)
#   코멘트의 «- 남김 #N — …» = 남은 일 선언 → FAIL · «- 남김: 0 — 사유» = 해소 → 통과 · 가장 마지막 «남김» 줄 하나만(선택 먼저 · 검증 나중).
#   반례 L1~L12(카드 동결) · 기준판(고정 sha = 고치기 직전 팩 main) · 변이 7 · bin·kit cmp.
# --from-json + 가짜 Tank 래퍼(호출 기록만) — 실 gh·실 리포 쓰기 0 · 네트워크 0 · 자기 재호출 0(guard_begin 이 지키는 1회 재실행 외).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"
MIR="$HERE/../../harness/kit/fable-team/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; SECONDS=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
stage() { echo "STAGE $1 ${SECONDS}s"; }
bash -n "$BIN/ft-issue-close-check.sh" && bash -n "$BIN/ft-issue-close-gate.sh" && ok "bash -n" || bad "bash -n"

# 임시 리포(정본 판정 0 — --repo 자리만 채운다)
R="$T/repo"; git init -q -b main "$R"; git -C "$R" config user.email t@t; git -C "$R" config user.name t
echo base > "$R/f"; git -C "$R" add -A; git -C "$R" commit -qm base
unset FT_LAND_REF FT_PR_STATE_FROM_JSON

Y0=$'원인 확정: Y — 로그·코드·재현으로 원인 확정함\n같은 증상 보류: 0'
SIX=$'[close-6항]\n- 닫는 사건: 재현 스텝 3회 PASS\n- PR: 직접 착지 main\n- 재현 PASS: repro 코멘트\n- 정리: 워크트리·나노 세션 정리 확인\n- 기록: design/harness/CLOSEOUT-x.md\n- 정본 영향 없음: 하네스 키트 시험 입력'
BASE="$SIX"$'\n'"$Y0"
S="$T/state.json"; EX="$T/extra.md"
mk() { # mk <labels JSON> <본문> <코멘트…> — Closes 연결 PR 1개 · 베이스 코멘트(6항·7·8항) 먼저
  local lb="$1" body="$2"; shift 2
  jq -n --argjson l "$lb" --arg b "$body" '{number:9000,state:"OPEN",title:"[fixture] r1346",body:$b,labels:$l,closedByPullRequestsReferences:[{number:9100}],comments:[$ARGS.positional[]|{body:.,author:{login:"byz-tank"}}]}' --args "$BASE" "$@" > "$S"; }
mkb() { mk '[]' '' "$@"; }   # 일반(버그) Issue
chk() { # chk [bin 폴더] [extra 파일] → OUT·RC (일반 모드)
  local b="${1:-$BIN}" x=(); [ -z "${2:-}" ] || x=(--extra-comment "$2")
  OUT="$(bash "$b/ft-issue-close-check.sh" 9000 --from-json "$S" --repo "$R" ${x[@]+"${x[@]}"} 2>&1)"; RC=$?; }
gchk() { # gchk [bin 폴더] [extra 파일] → GOUT(stdout)·GERR·GRC (--gate)
  local b="${1:-$BIN}" x=(); [ -z "${2:-}" ] || x=(--extra-comment "$2")
  GOUT="$(bash "$b/ft-issue-close-check.sh" 9000 --gate --from-json "$S" --repo "$R" ${x[@]+"${x[@]}"} 2>"$T/gerr")"; GRC=$?; GERR="$(cat "$T/gerr")"; }
# 가짜 Tank 래퍼 — 불리면 기록만(L8 쓰기 0 확인)
WL="$T/wrap.log"; : > "$WL"; printf '#!/usr/bin/env bash\necho "wrap $*" >> "%s"\nexit 0\n' "$WL" > "$T/wrap.sh"
gate() { # gate <bin 폴더> <닫는 코멘트 파일|""> → GOUT2·GRC2 (닫기 관문 apply=1 · 쓰기는 가짜 래퍼로만)
  GOUT2="$(FT_TANK_WRAPPER="$T/wrap.sh" FT_CLOSE_CHECK_FROM_JSON="$S" FT_CLOSE_CHECK_REPO="$R" bash "$1/ft-issue-close-gate.sh" 9000 "$2" 1 2>&1)"; GRC2=$?; }
L1=$'## 닫기 준비(남김)\n- 남김 #2994 — 남은 일 있음'
DONE0=$'- 남김: 0 — #6134 로 뗌'

# 기준 — 남김 줄 0 → PASS (지금과 같음)
mkb; chk; BASEOUT="$OUT"
[ $RC -eq 0 ] && grep -q "PASS #9000 완료 8항 + Closes 연결" <<<"$OUT" && ok "기준: 남김 줄 없음 → PASS" || bad "기준 rc=$RC $OUT"

# ⓐ L1 — 유일 코멘트 끝 «- 남김 #N» → 일반 rc1 · --gate rc3 kind=leftover
mkb "$L1"; chk
[ $RC -eq 1 ] && grep -q "FAIL #9000 남김 선언 — - 남김 #2994" <<<"$OUT" && ok "L1 남김 #N → FAIL 남김 선언" || bad "L1 rc=$RC $OUT"
gchk
[ $GRC -eq 3 ] && grep -q "^GATE rc=3 kind=leftover" <<<"$GOUT" && grep -q "REJECT close #9000 — 남김 선언(#2994) — 남은 일을 새 Issue 로 떼고 «남김: 0 — #<새 번호> 으로 뗌»" <<<"$GERR" && ok "L1 --gate rc3 kind=leftover + 안내" || bad "L1 gate rc=$GRC $GOUT $GERR"
# ⓑ L2 — 뒤 코멘트 «남김: 0 — …» → 통과
mkb "$L1" "$DONE0"; chk
[ $RC -eq 0 ] && grep -q "PASS #9000" <<<"$OUT" && ok "L2 뒤 «남김: 0 — #6134 로 뗌» → 통과" || bad "L2 rc=$RC $OUT"
gchk; [ $GRC -eq 0 ] && grep -q "^GATE rc=0 kind=pass" <<<"$GOUT" && ok "L2 --gate 통과" || bad "L2 gate rc=$GRC $GOUT"
# ⓒ L3 — 남김 줄 없음: 낱말 0 · 산문 줄에만 낱말 → 기준과 같은 출력
mkb "아무 얘기 없음"; chk
[ $RC -eq 0 ] && [ "$OUT" = "$BASEOUT" ] && ok "L3a 남김 낱말 0 → 기준과 같은 출력" || bad "L3a rc=$RC $OUT"
mkb "이전 코멘트의 남김 #6134 줄을 새 Issue 로 뗐다"; chk
[ $RC -eq 0 ] && [ "$OUT" = "$BASEOUT" ] && ok "L3b 산문 속 낱말(줄 머리 아님) → 기준과 같은 출력" || bad "L3b rc=$RC $OUT"
# ⓓ L4 — 산문 줄만 뒤에 있고 L1 은 앞 코멘트 → 고른 줄 = L1 → FAIL
mkb "$L1" $'앞 코멘트의 «남김» 1행 … #6134 로 뗌'; chk
[ $RC -eq 1 ] && grep -q "FAIL #9000 남김 선언 — - 남김 #2994" <<<"$OUT" && ok "L4 산문은 해소가 아님 → FAIL" || bad "L4 rc=$RC $OUT"
# ⓔ L5 — --extra-comment
printf '%s\n' "$DONE0" | sed 's/#6134/#7000/;s/로 뗌/으로 뗌/' > "$EX"; mkb "$L1"; chk "$BIN" "$EX"
[ $RC -eq 0 ] && grep -q "PASS #9000" <<<"$OUT" && ok "L5 extra «남김: 0 — #7000 으로 뗌» + 앞 L1 → 통과" || bad "L5a rc=$RC $OUT"
printf '%s\n' '- 남김 #7001 — 새로 남음' > "$EX"; mkb "$L1" "$DONE0"; chk "$BIN" "$EX"
[ $RC -eq 1 ] && grep -q "FAIL #9000 남김 선언 — - 남김 #7001" <<<"$OUT" && ok "L5b extra «남김 #7001» → FAIL" || bad "L5b rc=$RC $OUT"
# ⓕ L6 — 자리표시 · L7 — 체크박스 꼴 · L11 — «#<새 번호>» · L12 — «01건»
mkb $'- 남김: <…>'; chk
[ $RC -eq 1 ] && grep -q "FAIL #9000 남김 줄 무효" <<<"$OUT" && ok "L6 «남김: <…>» → 남김 줄 무효" || bad "L6 rc=$RC $OUT"
mkb $'- [ ] 남김 #12 — 남은 일'; chk
[ $RC -eq 1 ] && grep -q "FAIL #9000 남김 선언 — - \[ \] 남김 #12" <<<"$OUT" && ok "L7 체크박스 «- [ ] 남김 #12» → FAIL" || bad "L7 rc=$RC $OUT"
mkb $'- 남김 #<새 번호> — 남은 일'; chk
[ $RC -eq 1 ] && grep -q "FAIL #9000 남김 줄 무효" <<<"$OUT" && ok "L11 «남김 #<새 번호>» → 남김 줄 무효" || bad "L11 rc=$RC $OUT"
printf '%s\n' '- 남김: 01건 — 아직 남음' > "$EX"; mkb "$L1" "$DONE0"; chk "$BIN" "$EX"
[ $RC -eq 1 ] && grep -q "FAIL #9000 남김 줄 무효" <<<"$OUT" && ok "L12 마지막 «남김: 01건» → 무효(앞 유효값으로 안 내려감)" || bad "L12 rc=$RC $OUT"
# ⓖ L9 — 앞 «남김: 0» + 마지막 extra «남김: <…>» → 무효
printf '%s\n' '- 남김: <…>' > "$EX"; mkb "$L1" "$DONE0"; chk "$BIN" "$EX"
[ $RC -eq 1 ] && grep -q "FAIL #9000 남김 줄 무효" <<<"$OUT" && ok "L9 앞 유효 + 마지막 무효 → 무효" || bad "L9 rc=$RC $OUT"
# ⓗ L8 — 닫기 관문 apply=1 + L1 → rc3 · 래퍼 호출 0
printf '%s\n' '- 남김 #2994 — 남은 일' > "$EX"; mkb; : > "$WL"; gate "$BIN" "$EX"
[ $GRC2 -eq 3 ] && [ ! -s "$WL" ] && ok "L8 관문 apply=1 → rc3 · 래퍼 호출 0" || bad "L8 rc=$GRC2 wrap=$(cat "$WL") $GOUT2"
# ⓘ L10 — 제안 마무리 경로 + 남김 #12
PL='[{"name":"proposal"},{"name":"approved"}]'; PB=$'처리: 마무리\nhttps 대신 design/harness/PROPOSAL-x.md 참고 완료'
mk "$PL" "$PB"; chk
[ $RC -eq 0 ] && grep -q "PASS #9000 제안 마무리" <<<"$OUT" && ok "L10 대조: 제안 마무리 경로 → PASS" || bad "L10 대조 rc=$RC $OUT"
mk "$PL" "$PB" $'- 남김 #12 — 남은 일'; chk
[ $RC -eq 1 ] && grep -q "FAIL #9000 남김 선언" <<<"$OUT" && ok "L10 제안 마무리 + 남김 #12 → 일반 FAIL(조기 통과 우회 0)" || bad "L10 rc=$RC $OUT"
gchk
[ $GRC -eq 3 ] && grep -q "^GATE rc=3 kind=leftover" <<<"$GOUT" && ok "L10 --gate rc3 kind=leftover" || bad "L10 gate rc=$GRC $GOUT"
stage "green"

# bin·kit 같은 내용
cmp -s "$BIN/ft-issue-close-check.sh" "$MIR/ft-issue-close-check.sh" && cmp -s "$BIN/ft-issue-close-gate.sh" "$MIR/ft-issue-close-gate.sh" && ok "bin·kit cmp 0" || bad "bin·kit 불일치"

# 기준판 — 고치기 직전 팩 main(고정 sha) 은 L1·L5b·L7·L8·L9·L10·L11·L12 가 FAIL 이 아니었다(시험이 바뀐 행동을 잡는지)
PACK="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)"; OB="$T/base-bin"; mkdir -p "$OB"
BASE_SHA=cdcbe3a2363a698ea1d0a50c129d8e446812db58
P="feature-pack/fable-team/harness/bin"
if git -C "$PACK" show "$BASE_SHA:$P/ft-issue-close-check.sh" > "$OB/ft-issue-close-check.sh" 2>/dev/null \
   && git -C "$PACK" show "$BASE_SHA:$P/ft-issue-close-gate.sh" > "$OB/ft-issue-close-gate.sh" 2>/dev/null; then
  nb=0; bchk() { chk "$OB" "${2:-}"; [ $RC -eq 0 ] && nb=$((nb+1)) || echo "  기준판이 $1 에서 rc=$RC"; }
  mkb "$L1"; bchk L1
  printf '%s\n' '- 남김 #7001 — 새로 남음' > "$EX"; mkb "$L1" "$DONE0"; bchk L5b "$EX"
  mkb $'- [ ] 남김 #12 — 남은 일'; bchk L7
  printf '%s\n' '- 남김: <…>' > "$EX"; mkb "$L1" "$DONE0"; bchk L9 "$EX"
  mk "$PL" "$PB" $'- 남김 #12 — 남은 일'; bchk L10
  mkb $'- 남김 #<새 번호> — 남은 일'; bchk L11
  printf '%s\n' '- 남김: 01건 — 아직 남음' > "$EX"; mkb "$L1" "$DONE0"; bchk L12 "$EX"
  printf '%s\n' '- 남김 #2994 — 남은 일' > "$EX"; mkb; : > "$WL"; gate "$OB" "$EX"
  [ "$GRC2" -ne 3 ] && nb=$((nb+1)) || echo "  기준판이 L8 에서 rc3"
  [ $nb -eq 8 ] && ok "기준판(8 반례) 전부 지금 판에서만 FAIL — 기준판은 통과/비거절" || bad "기준판 반례 $nb/8 만 통과"
else bad "기준판 $BASE_SHA 를 못 꺼냄 — 팩 리포 git fetch 후 다시"; fi
stage "기준판"

# 변이 7 — 각각 지정 반례가 빨강이 되어야 한다
MB="$T/mut"
mkmut() { # mkmut <이름> <파일> <py 치환식: old|new|…> — 기준 bin 복사 뒤 함수/블록 안 한 곳만 치환
  rm -rf "$MB"; mkdir -p "$MB"; cp "$BIN"/ft-*.sh "$MB/"
  python3 - "$MB/$2" "$3" "$4" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding="utf-8").read()
i = s.find("leftover_eval() {")
i = max(i, 0)   # 함수가 있으면 그 안부터 찾는다(pick_last 의 같은 낱말을 건드리지 않게)
j = s.find(old, i)
assert j >= 0, "치환 대상 없음: " + old
open(p, "w", encoding="utf-8").write(s[:j] + new + s[j + len(old):])
PY
}
# 변이 1 — 선택을 «첫 줄» 로 → L2 FAIL
mkmut m1 ft-issue-close-check.sh '| last // empty' '| first // empty'
mkb "$L1" "$DONE0"; chk "$MB"
[ $RC -eq 1 ] && ok "변이1(첫 줄 선택) → L2 빨강" || bad "변이1 에도 rc=$RC"
# 변이 2 — 줄 머리 조건 빼고 낱말 포함 → L3b FAIL
mkmut m2 ft-issue-close-check.sh 'select(test($p + "남김(' 'select(test(".*남김('
mkb "이전 코멘트의 남김 #6134 줄을 새 Issue 로 뗐다"; chk "$MB"
[ $RC -eq 1 ] && ok "변이2(낱말 포함) → L3b 빨강" || bad "변이2 에도 rc=$RC"
# 변이 3 — gate case 에서 leftover 를 뺌 → L8 FAIL(쓰기 발생)
mkmut m3 ft-issue-close-gate.sh '|leftover) exit 3' ') exit 3'
printf '%s\n' '- 남김 #2994 — 남은 일' > "$EX"; mkb; : > "$WL"; gate "$MB" "$EX"
[ -s "$WL" ] && ok "변이3(gate case 에서 leftover 뺌) → L8 빨강(쓰기 발생)" || bad "변이3 에도 래퍼 호출 0 rc=$GRC2"
# 변이 4 — «#숫자» 판정을 뺌 → L1 FAIL(선언 문구가 무효로 바뀜)
mkmut m4 ft-issue-close-check.sh '"^#[0-9]+"' '"^NEVER$"'
mkb "$L1"; chk "$MB"
! grep -q "FAIL #9000 남김 선언" <<<"$OUT" && ok "변이4(#숫자 판정 뺌) → L1 빨강" || bad "변이4 에도 선언 문구 $OUT"
# 변이 5 — 마지막 줄이 무효면 앞 유효 줄로 내려감 → L9 FAIL
mkmut m5 ft-issue-close-check.sh 'select(test($p + "남김(\\s*[:：]|\\s+#)"))' 'select(test($p + "남김(\\s*[:：]\\s*0|\\s+#[0-9])"))'
printf '%s\n' '- 남김: <…>' > "$EX"; mkb "$L1" "$DONE0"; chk "$MB" "$EX"
[ $RC -eq 0 ] && ok "변이5(무효 줄이면 앞으로 내려감) → L9 빨강" || bad "변이5 에도 rc=$RC"
# 변이 6 — 남김 판정을 proposal_close_eval 조기 통과 뒤로 → L10 FAIL
rm -rf "$MB"; mkdir -p "$MB"; cp "$BIN"/ft-*.sh "$MB/"
python3 - "$MB/ft-issue-close-check.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
blk = s[s.index("leftover_eval   # r1346 · 남김 판정"):s.index("proposal_close_eval   # R234 교정 1")]
s = s.replace(blk, "", 1)
anchor = '[ "$P_RC" -eq 3 ] && { echo "FAIL #$N ${P_MSG#REJECT close #$N — }"; exit 1; }\n'
assert s.count(anchor) == 1
open(p, "w", encoding="utf-8").write(s.replace(anchor, anchor + blk, 1))
PY
mk "$PL" "$PB" $'- 남김 #12 — 남은 일'; chk "$MB"
[ $RC -eq 0 ] && ok "변이6(남김 판정을 조기 통과 뒤로) → L10 빨강" || bad "변이6 에도 rc=$RC"
# 변이 7 — 해소 조건을 «0 으로 시작» 으로 느슨하게 → L12 FAIL
mkmut m7 ft-issue-close-check.sh '"^0(\\s*$|\\s+[—–-]+\\s*\\S)"' '"^0"'
printf '%s\n' '- 남김: 01건 — 아직 남음' > "$EX"; mkb "$L1" "$DONE0"; chk "$MB" "$EX"
[ $RC -eq 0 ] && ok "변이7(0 으로 시작) → L12 빨강" || bad "변이7 에도 rc=$RC"
stage "변이"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
