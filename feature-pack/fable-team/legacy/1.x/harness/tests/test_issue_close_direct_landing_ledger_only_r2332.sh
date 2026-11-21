#!/usr/bin/env bash
# test_issue_close_direct_landing_ledger_only_r2332.sh — r2332 · ft-issue-close-check 직접 착지 길 바뀐 파일 대조 (Issue #10088 · 실사건 room #5186)
#   직접 착지 sha 가 조상이어도 바뀐 파일(첫 부모 대비 · 뿌리 = --root · diff-tree -z)이 전부 «^design/(teams/)?<x>/(indices|baselines)/» 면 MISS.
#   반례 ①~⑩ · ⑪b · ⑫ · D3(가짜 git) · 기준판(팩 main 24d192abc3 = ① ② PASS → Red) · 변이 M1~M6(사본 · 변이마다 원본으로 같은 사례 1회 더) · bin·kit cmp.
# 임시 리포 + bare 가짜 원격 + --from-json + 가짜 gh(기록만 · exit 1) — 실 gh·실 원격 0 · sleep 0.
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
cmp -s "$BIN/ft-issue-close-check.sh" "$MIR/ft-issue-close-check.sh" && ok "bin·kit cmp 0" || bad "bin·kit 불일치"
PACK="$(git -C "$HERE" rev-parse --show-toplevel)"   # 기준판 꺼낼 팩 리포(전역 설정 끄기 전에 푼다)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1   # ⑪b: 사용자 전역 quotePath 와 무관하게

# ── 임시 리포: main 위에 사례 커밋을 한 줄로 쌓고 bare 원격에 올린다 · side = main 조상 아님 ──
R="$T/repo"; O="$T/origin.git"; git init -q --bare -b main "$O"
git init -q -b main "$R"; git -C "$R" config user.email t@t; git -C "$R" config user.name t; git -C "$R" config core.quotePath true
mkf() { # mkf <메시지> <경로…> → 그 파일들에 한 줄 더하고 커밋 · sha
  local m="$1" p; shift
  for p in "$@"; do mkdir -p "$R/$(dirname -- "$p")"; echo "$m" >> "$R/$p"; done
  git -C "$R" add -A; git -C "$R" commit -qm "$m"; git -C "$R" rev-parse HEAD; }
ROOT="$(mkf base f)"
C1="$(mkf c1 "design/teams/room/indices/진행/R-x.md" design/teams/v65/baselines/B.md)"
C2="$(mkf c2 design/harness/indices/대기/r9.md)"
C3="$(mkf c3 clients/web/src/a.ts design/harness/indices/대기/r9.md)"
C4="$(mkf c4 tests/test_a.sh)"
C5="$(mkf c5 design/rag/sql/NUMBERS.md)"
C6="$(mkf c6 docs/rules/a.md)"
git -C "$R" commit -q --allow-empty -m c7; C7="$(git -C "$R" rev-parse HEAD)"
C11="$(mkf c11b "design/teams/room/indices/진행/한글카드.md")"
C12="$(mkf c12 design/teams/v65/baselines/B.md)"
# ⑧ merge — 첫 부모 대비 장부만(둘째 부모 대비면 code 가 보이는 꼴) · 첫 부모 대비 코드 포함
git -C "$R" checkout -q -b s1; mkf m1 design/harness/indices/진행/m.md >/dev/null
git -C "$R" checkout -q main; mkf mm code/x.py >/dev/null; git -C "$R" merge -q --no-ff -m merge1 s1; M8A="$(git -C "$R" rev-parse HEAD)"
git -C "$R" checkout -q -b s2; mkf m2 src/y.py >/dev/null
git -C "$R" checkout -q main; mkf mm2 design/harness/indices/진행/m2.md >/dev/null; git -C "$R" merge -q --no-ff -m merge2 s2; M8B="$(git -C "$R" rev-parse HEAD)"
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main; git -C "$R" fetch -q origin
git -C "$R" checkout -q -b side "$C2"; E="$(mkf e src/e.py)"; git -C "$R" checkout -q main
Z="0123456789abcdef0123456789abcdef01234567"
unset FT_LAND_REF

mkdir -p "$T/bin"; GH_LOG="$T/gh.log"; : > "$GH_LOG"
printf '#!/usr/bin/env bash\necho "gh $*" >> "%s"; exit 1\n' "$GH_LOG" > "$T/bin/gh"; chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH"

S="$T/state.json"; PRJ="$T/pr.json"; printf '[]' > "$PRJ"
Y0=$'원인 확정: Y — 로그·코드·재현으로 원인 확정함\n같은 증상 보류: 0'
SIX=$'[close-6항]\n- 닫는 사건: 재현 스텝 3회 PASS\n- PR: 직접 착지 main\n- 재현 PASS: repro 코멘트\n- 정리: 워크트리·나노 세션 정리 확인\n- 기록: design/harness/CLOSEOUT-x.md\n- 정본 영향 없음: 하네스 키트 시험 입력'
mkstate() { local cl="$1"; shift
  jq -n --argjson c "$cl" '{number:9000,state:"OPEN",title:"[fixture] r2332",labels:[],closedByPullRequestsReferences:$c,comments:[$ARGS.positional[]|{body:.}]}' --args "$SIX"$'\n'"$Y0" "$@" > "$S"; }
DL() { printf '연결 PR: 없음 · 직접 착지 main %s' "$1"; }
chk() { OUT="$(FT_PR_STATE_FROM_JSON="$PRJ" bash "${1:-$BIN}/ft-issue-close-check.sh" 9000 --from-json "$S" --repo "$R" 2>&1)"; RC=$?; }
LED="카드 장부·기준선 파일만 바뀜(코드·문서·시험 착지 아님)"
is_ok()  { mkstate '[]' "$(DL "$1")"; chk "${2:-}"; [ $RC -eq 0 ] && grep -qF "OK 연결 PR 없음 · 직접 착지 ${1:0:10} origin/main 조상" <<<"$OUT" && grep -q "PASS #9000" <<<"$OUT"; }
is_led() { mkstate '[]' "$(DL "$1")"; chk "${2:-}"; [ $RC -eq 1 ] && grep -qF "MISS 직접 착지 ${1:0:10} — $LED" <<<"$OUT" && grep -q "FAIL #9000" <<<"$OUT" && ! grep -q "PASS #9000" <<<"$OUT"; }

: > "$GH_LOG"
is_led "$C1" && ok "① room indices + v65 baselines 만 → MISS D2 · 전체 FAIL" || bad "① rc=$RC $OUT"
is_led "$C2" && ok "② harness indices 만 → MISS" || bad "② rc=$RC $OUT"
is_ok "$C3" && ok "③ 코드 + 카드 장부 1줄 → OK" || bad "③ rc=$RC $OUT"
is_ok "$C4" && ok "④ 시험만 → OK" || bad "④ rc=$RC $OUT"
is_ok "$C5" && ok "⑤ design/rag 문서만 → OK" || bad "⑤ rc=$RC $OUT"
is_ok "$C6" && ok "⑥ docs/rules 만 → OK" || bad "⑥ rc=$RC $OUT"
is_led "$C7" && ok "⑦ 빈 커밋 → MISS D2" || bad "⑦ rc=$RC $OUT"
is_led "$M8A" && ok "⑧ merge 첫 부모 대비 장부만 → MISS" || bad "⑧a rc=$RC $OUT"
is_ok "$M8B" && ok "⑧ merge 첫 부모 대비 코드 포함 → OK" || bad "⑧b rc=$RC $OUT"
is_ok "$ROOT" && ok "뿌리 커밋(--root · f) → OK" || bad "뿌리 rc=$RC $OUT"
[ ! -s "$GH_LOG" ] && ok "D4 직접 착지 길 gh 호출 0" || bad "D4 gh=$(cat "$GH_LOG")"

# ⑨ 지금 문구 그대로
mkstate '[]' "$(DL "$E")"; chk
[ $RC -eq 1 ] && grep -q "MISS 직접 착지 ${E:0:10} — origin/main 조상 아님" <<<"$OUT" && ! grep -qF "$LED" <<<"$OUT" && ok "⑨ 조상 아님 → 지금 문구" || bad "⑨a rc=$RC $OUT"
mkstate '[]' "$(DL "$Z")"; chk
[ $RC -eq 1 ] && grep -q "MISS 직접 착지 ${Z:0:10} — 로컬에 없음 — git fetch 후 다시" <<<"$OUT" && ok "⑨ 로컬에 없음 → 지금 문구" || bad "⑨b rc=$RC $OUT"
mkstate '[]' "연결 PR: 없음 · 직접 착지 main ${C2:0:20}"; chk
[ $RC -eq 1 ] && grep -q "꼴 아님(sha 40자)" <<<"$OUT" && ok "⑨ 40hex 아님 → 지금 문구" || bad "⑨c rc=$RC $OUT"
# ⑩ «연결 PR: #N» 있으면 직접 착지 길 안 탐
printf '[{"number":9100,"state":"MERGED"}]' > "$PRJ"; mkstate '[]' '연결 PR: #9100' "$(DL "$C2")"; chk
[ $RC -eq 0 ] && grep -q "«연결 PR: #9100» 병합 확인" <<<"$OUT" && ! grep -q "직접 착지" <<<"$OUT" && ok "⑩ 연결 PR #N → 직접 착지 길 안 탐" || bad "⑩ rc=$RC $OUT"
printf '[]' > "$PRJ"
# ⑪b 한글 장부 경로 · quotePath=true 에서 줄 단위면 따옴표 경로가 새는 자리
case "$(git -C "$R" diff-tree -r --name-only "$C11^" "$C11")" in '"'*) ok "⑪b 전제: quotePath 로 따옴표 경로";; *) bad "⑪b 전제 깨짐(따옴표 없음)";; esac
is_led "$C11" && ok "⑪b 한글 장부 경로 → MISS" || bad "⑪b rc=$RC $OUT"
is_led "$C12" && ok "⑫ v65 baselines 만(기준선 산출 카드) → MISS · PR 길로 닫음" || bad "⑫ rc=$RC $OUT"
# D3 diff-tree 실패(가짜 git rc=7) → 판정 불가 1줄 · PASS 0
REALGIT="$(command -v git)"; mkdir -p "$T/fgit"
printf '#!/usr/bin/env bash\nfor a; do [ "$a" = diff-tree ] && exit 7; done\nexec "%s" "$@"\n' "$REALGIT" > "$T/fgit/git"; chmod +x "$T/fgit/git"
d3() { mkstate '[]' "$(DL "$C3")"; OUT="$(PATH="$T/fgit:$PATH" FT_PR_STATE_FROM_JSON="$PRJ" bash "${1:-$BIN}/ft-issue-close-check.sh" 9000 --from-json "$S" --repo "$R" 2>&1)"; RC=$?
  [ $RC -eq 1 ] && grep -qF "MISS 직접 착지 ${C3:0:10} — 바뀐 파일 판정 불가(git rc=7)" <<<"$OUT" && ! grep -q "PASS #9000" <<<"$OUT"; }
d3 && ok "D3 diff-tree 실패 → MISS 판정 불가(git rc=7)" || bad "D3 rc=$RC $OUT"

# 기준판 — 고치기 직전 팩 main 은 ① ② 를 PASS 했다(Red)
OB="$T/base-bin"; mkdir -p "$OB"; BASE_SHA=24d192abc33fee0756cdea818bd0549e612af542
if git -C "$PACK" show "$BASE_SHA:feature-pack/fable-team/legacy/1.x/harness/bin/ft-issue-close-check.sh" > "$OB/ft-issue-close-check.sh" 2>/dev/null; then
  is_ok "$C1" "$OB" && ok "기준판 ① = PASS(지금 행동 · Red)" || bad "기준판 ① rc=$RC $OUT"
  is_ok "$C2" "$OB" && ok "기준판 ② = PASS(지금 행동 · Red)" || bad "기준판 ② rc=$RC $OUT"
else bad "기준판 $BASE_SHA 를 못 꺼냄 — 팩 리포 git fetch 후 다시"; fi

# 변이 — 표식 줄 1개를 바꾼 사본 · 변이마다 원본으로 같은 사례 1회 더
mut() { # mut <폴더> <표식> <python 식: l → 새 줄>
  mkdir -p "$T/$1"; cp "$BIN/ft-issue-close-check.sh" "$T/$1/"
  python3 - "$T/$1/ft-issue-close-check.sh" "$2" "$3" <<'PY'
import sys
p, tag, expr = sys.argv[1:4]
lines = open(p, encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if tag in l]
assert len(hit) == 1, (tag, hit)
l = lines[hit[0]]; new = eval(expr)
assert new != l, tag
lines[hit[0]] = new
open(p, "w", encoding="utf-8").write("\n".join(lines))
PY
}
mut m1 "# r2332-mut:files" 'l.replace("direct_files \"$S\" || return 1", ":")'
! is_led "$C1" "$T/m1" && is_led "$C1" && ok "M1 파일 대조 단 지움 → ① FAIL · 원본 ① MISS" || bad "M1 안 잡힘"
mut m2 "# r2332-mut:ledger-re" 'l.replace("(indices|baselines)", "indices")'
! is_led "$C1" "$T/m2" && is_led "$C1" && ok "M2 baselines 거름 지움 → ① FAIL · 원본 ① MISS" || bad "M2 안 잡힘"
mut m3 "# r2332-mut:any-code" '"  grep -Eq \"$LEDGER_RE\" <<<\"$L\" || return 0   # r2332-mut:any-code"'
! is_ok "$C3" "$T/m3" && is_ok "$C3" && ok "M3 하나라도 장부면 MISS → ③ FAIL · 원본 ③ OK" || bad "M3 안 잡힘"
mut m4 "# r2332-mut:empty" '"  [ -n \"$L\" ] || return 0   # r2332-mut:empty"'
! is_led "$C7" "$T/m4" && is_led "$C7" && ok "M4 빈 커밋 OK → ⑦ FAIL · 원본 ⑦ MISS" || bad "M4 안 잡힘"
mut m5 "# r2332-mut:git-fail" '"  [ \"$RC\" -eq 0 ] || return 0   # r2332-mut:git-fail"'
! d3 "$T/m5" && d3 && ok "M5 diff-tree 실패 OK → D3 FAIL · 원본 D3 MISS" || bad "M5 안 잡힘"
mut m6 "# r2332-mut:nul" 'l.replace("diff-tree -z ", "diff-tree ")'
! is_led "$C11" "$T/m6" && is_led "$C11" && ok "M6 -z 지움 → ⑪b FAIL · 원본 ⑪b MISS" || bad "M6 안 잡힘"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
