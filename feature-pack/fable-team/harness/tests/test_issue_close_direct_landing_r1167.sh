#!/usr/bin/env bash
# test_issue_close_direct_landing_r1167.sh — r1167 · ft-issue-close-check 직접 착지 갈래 (Issue #4971 · 실사건 #746)
#   Closes·«연결 PR: #N» 둘 다 없을 때 코멘트 가장 마지막 «연결 PR: 없음 · 직접 착지 main <40hex>» 의 sha 가 랜딩 ref 조상이면 OK.
#   반례 R1~R5(카드 동결) · 변이 1(새 갈래 끔 → R1 빨강) · 기준판(origin/main 판 = R1 MISS) · bin·kit cmp.
# 임시 리포 + bare 가짜 원격(main 3커밋) + --from-json + 가짜 gh(호출 기록만 · exit 1) — 실 gh·실 리포 쓰기 0 · 자기 재호출 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"
MIR="$HERE/../../harness/kit/fable-team/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
bash -n "$BIN/ft-issue-close-check.sh" && ok "bash -n" || bad "bash -n"

# ── 임시 리포 + bare 원격: main = base→A→B→C · side = B→E(main 조상 아님) · Z = 리포에 없는 40hex ──
R="$T/repo"; O="$T/origin.git"; git init -q --bare -b main "$O"
git init -q -b main "$R"; git -C "$R" config user.email t@t; git -C "$R" config user.name t
echo base > "$R/f"; git -C "$R" add -A; git -C "$R" commit -qm base
mkc() { echo "$1" >> "$R/f"; git -C "$R" commit -qam "$1"; git -C "$R" rev-parse HEAD; }
A="$(mkc a)"; B="$(mkc b)"; C="$(mkc c)"
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main; git -C "$R" fetch -q origin
git -C "$R" checkout -q -b side "$B"; E="$(mkc e)"; git -C "$R" checkout -q main
Z="0123456789abcdef0123456789abcdef01234567"
unset FT_LAND_REF   # 기본 랜딩 ref = origin/main

# 가짜 gh — 불리면 기록만 남기고 실패(실 gh 0 · 새 갈래 gh 호출 0 확인)
mkdir -p "$T/bin"; GH_LOG="$T/gh.log"; : > "$GH_LOG"
printf '#!/usr/bin/env bash\necho "gh $*" >> "%s"; exit 1\n' "$GH_LOG" > "$T/bin/gh"; chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH"

S="$T/state.json"; PRJ="$T/pr.json"
Y0=$'원인 확정: Y — 로그·코드·재현으로 원인 확정함\n같은 증상 보류: 0'
SIX=$'[close-6항]\n- 닫는 사건: 재현 스텝 3회 PASS\n- PR: 직접 착지 main\n- 재현 PASS: repro 코멘트\n- 정리: 워크트리·나노 세션 정리 확인\n- 기록: design/harness/CLOSEOUT-x.md\n- 정본 영향 없음: 하네스 키트 시험 입력'
mkstate() { # mkstate <closedBy JSON> <코멘트…>
  local cl="$1"; shift
  jq -n --argjson c "$cl" '{number:9000,state:"OPEN",title:"[fixture] r1167",labels:[],closedByPullRequestsReferences:$c,comments:[$ARGS.positional[]|{body:.}]}' --args "$SIX"$'\n'"$Y0" "$@" > "$S"; }
DL() { echo "연결 PR: 없음 · 직접 착지 main $1"; }
chk() { # chk [bin 폴더] → OUT·RC
  OUT="$(FT_PR_STATE_FROM_JSON="$PRJ" bash "${1:-$BIN}/ft-issue-close-check.sh" 9000 --from-json "$S" --repo "$R" 2>&1)"; RC=$?; }
printf '[]' > "$PRJ"

# ⓐ R1 — Closes 0 · 연결 PR #N 0 · 직접 착지 main 조상 → OK · gh 호출 0
mkstate '[]' "$(DL "$A")"; : > "$GH_LOG"; chk
[ $RC -eq 0 ] && grep -q "OK 연결 PR 없음 · 직접 착지 ${A:0:10} origin/main 조상" <<<"$OUT" && grep -q "PASS #9000" <<<"$OUT" && [ ! -s "$GH_LOG" ] \
  && ok "ⓐ R1 직접 착지(main 조상) → OK · gh 0" || bad "ⓐ R1 rc=$RC gh=$(cat "$GH_LOG") $OUT"
# ⓐ' 가장 마지막 줄만 — 앞 줄이 조상이어도 마지막 줄이 다른 가지면 MISS
mkstate '[]' "$(DL "$A")" "$(DL "$E")"; chk
[ $RC -eq 1 ] && grep -q "직접 착지 ${E:0:10} — origin/main 조상 아님" <<<"$OUT" && ok "ⓐ' 마지막 줄 기준(앞 줄로 안 내려감)" || bad "ⓐ' rc=$RC $OUT"

# ⓑ R2·R3 — 조상 아님 · 로컬에 없음 · 40hex 아님 → MISS
mkstate '[]' "$(DL "$E")"; chk
[ $RC -eq 1 ] && grep -q "MISS 직접 착지 ${E:0:10} — origin/main 조상 아님" <<<"$OUT" && grep -q "MISS Closes 연결 PR 없음" <<<"$OUT" \
  && ok "ⓑ R2 다른 가지 sha → MISS 조상 아님" || bad "ⓑ R2 rc=$RC $OUT"
mkstate '[]' "$(DL "$Z")"; chk
[ $RC -eq 1 ] && grep -q "MISS 직접 착지 ${Z:0:10} — 로컬에 없음 — git fetch 후 다시" <<<"$OUT" && ok "ⓑ R3 로컬에 없는 sha → MISS + git fetch 후 다시" || bad "ⓑ R3 rc=$RC $OUT"
mkstate '[]' "연결 PR: 없음 · 직접 착지 main"; chk
[ $RC -eq 1 ] && grep -q "꼴 아님(sha 40자)" <<<"$OUT" && grep -q "MISS Closes 연결 PR 없음" <<<"$OUT" && ok "ⓑ sha 없는 줄 → MISS" || bad "ⓑ sha 없음 rc=$RC $OUT"

# ⓒ R4·R5 — PR 길 우선 그대로
mkstate '[{"number":9100}]' "$(DL "$E")"; chk
[ $RC -eq 0 ] && grep -q "OK   Closes 연결 PR #9100" <<<"$OUT" && ! grep -q "직접 착지" <<<"$OUT" && ok "ⓒ R4 Closes 있음 → 지금과 같음(새 갈래 안 봄)" || bad "ⓒ R4 rc=$RC $OUT"
printf '[{"number":9100,"state":"MERGED"}]' > "$PRJ"; mkstate '[]' '연결 PR: #9100' "$(DL "$E")"; chk
[ $RC -eq 0 ] && grep -q "«연결 PR: #9100» 병합 확인" <<<"$OUT" && ! grep -q "직접 착지" <<<"$OUT" && ok "ⓒ R5 연결 PR #N(병합)+직접 착지 → 연결 PR 길" || bad "ⓒ R5 rc=$RC $OUT"
printf '[{"number":9100,"state":"OPEN"}]' > "$PRJ"; mkstate '[]' '연결 PR: #9100' "$(DL "$A")"; chk
[ $RC -eq 1 ] && grep -q "MISS 연결 PR #9100" <<<"$OUT" && ! grep -q "직접 착지" <<<"$OUT" && ok "ⓒ R5' 연결 PR #N(미병합)+직접 착지 → 지금처럼 MISS" || bad "ⓒ R5' rc=$RC $OUT"
printf '[]' > "$PRJ"

# ⓓ bin·kit 같은 내용
cmp -s "$BIN/ft-issue-close-check.sh" "$MIR/ft-issue-close-check.sh" && ok "ⓓ bin·kit cmp 0" || bad "ⓓ bin·kit 불일치"

# 기준판 — 고치기 직전 팩 main(고정 sha · r1132)은 R1 이 MISS 였다(시험이 바뀐 행동을 잡는지)
PACK="$(git -C "$HERE" rev-parse --show-toplevel)"; OB="$T/base-bin"; mkdir -p "$OB"
BASE_SHA=4580028c98de911a180c4ec2d5b9ab4925ce807a
if git -C "$PACK" show "$BASE_SHA:feature-pack/fable-team/harness/bin/ft-issue-close-check.sh" > "$OB/ft-issue-close-check.sh" 2>/dev/null; then
  mkstate '[]' "$(DL "$A")"; chk "$OB"
  [ $RC -eq 1 ] && grep -q "MISS Closes 연결 PR 없음" <<<"$OUT" && ok "기준판 R1 = MISS(지금 행동)" || bad "기준판 R1 rc=$RC $OUT"
else bad "기준판 $BASE_SHA 를 못 꺼냄 — 팩 리포 git fetch 후 다시"; fi

# 변이 1 — 새 갈래 끔 → ⓐ R1 빨강
MB="$T/mut"; mkdir -p "$MB"; cp "$BIN/ft-issue-close-check.sh" "$MB/"
python3 - "$MB/ft-issue-close-check.sh" <<'PY'
import sys
p = sys.argv[1]
lines = open(p, encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if "# r1167-mut:direct-path" in l]
assert len(hit) == 1, hit
lines[hit[0]] = "  elif false; then"
open(p, "w", encoding="utf-8").write("\n".join(lines))
PY
mkstate '[]' "$(DL "$A")"; chk "$MB"
[ $RC -eq 1 ] && ok "변이(직접 착지 갈래 끔) → ⓐ R1 이 빨강" || bad "변이에도 rc=$RC — 시험이 안 잡는다"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
