#!/usr/bin/env bash
# test_scope_classify_card_wire_r1799.sh — r1799 scope-approve --card 가 분류기 호출 인자로 넘어간다(r1778 빠진 배선)
#   계약 C1(--card → 분류기 인자 --card) · C2(--card 없음 = 인자 바이트 그대로) · C3(판정·거절 원장 꼴 그대로)
#   반례 ①~⑤ + 변이 M1(배선 줄 빼기)·M2(빈 값도 붙이기) · 분류기 = 실물(FT_SCOPE_CLASSIFY) 또는 인자 기록 가짜
#   격리: 임시 origin(bare)+clone · 임시 상태·카드 · 가짜 슬랙 · 실 리포·실 원격·실 상태 0 · press 0 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
unset FT_AUTONOMY_LEVEL
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$(cd "$HERE/../bin" && pwd -P)"
KIT="$(cd "$HERE/../kit/fable-team/bin" && pwd -P)"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
has() { grep -qE -- "$1" <<<"$out"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; S="$T/state"; LOG="$S/autonomy.log"; mkdir -p "$S" "$T/planner"
REAL="$BIN/autonomy_scope_classify.py"; DDL="$BIN/../kit/fable-team/templates/scope-ddl-record.tsv"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/args.log"\n[ "$1" = check-revert ] && { echo OK; exit 0; }\necho "CLASS docs"\n' "$T" > "$T/fake.sh"
printf '#!/usr/bin/env bash\necho "SLACK-TS 1800000000.000100"\n' > "$T/post.sh"; chmod +x "$T/fake.sh" "$T/post.sh"
export FT_ROOT="$W" FT_AUTONOMY_STATE_DIR="$S" FT_PLANNER_DIR="$T/planner" FT_SCOPE_SLACK_POST="$T/post.sh" FT_AUTONOMY_GOAL_TABLE=0
export FT_SCOPE_DDL_RECORDS="$DDL" FT_SCOPE_CLASSIFY="$REAL"

# 기준 저장소 — 카드 범위 안/밖 문서·코드 · main 은 한 칸 앞(가지 = ff 아님)
mkdir -p "$W/design" "$W/docs" "$W/scripts"
echo d > "$W/design/x.md"; echo d > "$W/docs/a.md"; printf '#!/bin/sh\n' > "$W/scripts/run.sh"
cm "$W" base2; git -C "$W" push -q origin main; BASE="$(sha "$W" HEAD)"
echo m1 > "$W/m1.txt"; cm "$W" m1; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
mk() { local br="$1"; shift; git -C "$W" checkout -q -B "$br" "$BASE"; ( cd "$W" && eval "$*" ); cm "$W" "$br"; SHA="$(sha "$W" HEAD)"; git -C "$W" checkout -q main; }
CARD="$W/card.md"; printf '# 카드\n\n## 구현 범위\n\n- `design/x.md`\n- `scripts/run.sh`\n\n## 상태\n- 2026\n' > "$CARD"
grep -qx '/card*.md' "$W/.git/info/exclude" || echo '/card*.md' >> "$W/.git/info/exclude"; git -C "$W" update-ref refs/remotes/origin/ops/main-base "$(git -C "$W" commit-tree "$(printf '100644 blob %s\t%s\n' "$(git -C "$W" hash-object -w "$CARD")" "${CARD##*/}" | git -C "$W" mktree)" -m card)"   # r1904: 카드 = 원장(FT_ROOT) 안 · 고정 ref 커밋 판 · 가지 커밋엔 안 들어감(exclude)
mk din 'git rm -q design/x.md'; D_IN="$SHA"
mk dcode 'git rm -q scripts/run.sh'; D_CODE="$SHA"
mk dout 'git rm -q docs/a.md'; D_OUT="$SHA"
mk add 'echo n > docs/new.md'; D_ADD="$SHA"

A="${ABIN:-$BIN}"
a() { FT_NOW=1800000000 "$BASH" "$A/ft-autonomy.sh" "$@"; }
run() { out="$("$@" 2>&1)"; rc=$?; }
fresh() { rm -rf "$S" "$T/args.log"; mkdir -p "$S"; FT_NOW=1800000000 "$BASH" "$BIN/ft-autonomy.sh" on --for 12h >/dev/null 2>&1; }   # 승인 줄 = 원본 판(변이 판은 scope-approve 만)
denied() { local n; n="$(grep -c "^$1	delete	" "$S/autonomy-scope/denied.tsv" 2>/dev/null)"; echo "${n:-0}"; }
NOCARD_ARGS() { printf 'classify %s --repo %s --remote origin --target main --scope S1 --ddl-records %s' "$1" "$W" "$DDL"; }

bash -n "$0"; ck "bash -n 시험" $?
cmp -s "$BIN/ft-autonomy-scope.sh" "$KIT/ft-autonomy-scope.sh"; ck "bin = kit ft-autonomy-scope.sh 같은 바이트" $?

# ── ① --card 있음 + 카드 범위 안 삭제 → 분류 통과(문서 = SCOPE-OK docs · 코드 = CLASS code 로 code 단계 진입 · FORBID 0)
fresh; run a scope-approve "$D_IN" --card "$CARD"
[ "$rc" = 0 ] && has "^SCOPE-OK $D_IN class=docs " && [ "$(denied "$D_IN")" = 0 ]; ck "① 카드 범위 안 문서 삭제 → SCOPE-OK class=docs(거절 원장 0)" $?
fresh; run a scope-approve "$D_CODE" --card "$CARD"
[ "$rc" = 2 ] && ! has 'FORBID' && has '카드 증거 줄' && [ "$(denied "$D_CODE")" = 0 ]; ck "① 카드 범위 안 코드 삭제 → FORBID 0 · CLASS code 로 code 증거 단계까지 감" $?
out="$(python3 "$REAL" classify "$D_CODE" --repo "$W" --scope S1 --ddl-records "$DDL" --card "$CARD" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "CLASS code" ]; ck "① 같은 세트 분류기 직접 = CLASS code" $?
# ── ② --card 없음 + 같은 삭제 → FORBID kind=delete 그대로(거절 원장 1행)
fresh; run a scope-approve "$D_IN"
[ "$rc" = 2 ] && has '분류기 거절 rc=3: FORBID kind=delete' && [ "$(denied "$D_IN")" = 1 ]; ck "② --card 없음 + 삭제 → FORBID kind=delete · 원장 1행" $?
# ── ③ --card 있음 + 카드 범위 밖 삭제 → FORBID kind=delete
fresh; run a scope-approve "$D_OUT" --card "$CARD"
[ "$rc" = 2 ] && has '분류기 거절 rc=3: FORBID kind=delete' && [ "$(denied "$D_OUT")" = 1 ]; ck "③ 카드 범위 밖 삭제 → FORBID kind=delete · 원장 1행" $?
# ── ④ --card 있음 + 삭제 없음 → 지금과 같은 결과(SCOPE-OK docs)
fresh; run a scope-approve "$D_ADD" --card "$CARD"
[ "$rc" = 0 ] && has "^SCOPE-OK $D_ADD class=docs "; ck "④ --card 있음 + 문서 추가 → SCOPE-OK class=docs(그대로)" $?
fresh; run a scope-approve "$D_ADD"
[ "$rc" = 0 ] && has "^SCOPE-OK $D_ADD class=docs "; ck "④ --card 없음 + 문서 추가 → SCOPE-OK class=docs(그대로)" $?
# ── ⑤ 빈 --card 값 → 기존 usage 거절 그대로(분류기 호출 0)
FT_SCOPE_CLASSIFY="$T/fake.sh"; fresh; run a scope-approve "$D_ADD" --card ""
[ "$rc" = 2 ] && [[ "$out" == *"--card 값 없음"* ]] && [ ! -e "$T/args.log" ]; ck "⑤ 빈 --card → «--card 값 없음» 거절 · 분류기 호출 0" $?
# ── C1·C2 인자 대조(가짜 분류기 = 인자 기록)
fresh; run a scope-approve "$D_ADD" --card "$CARD"
[ "$rc" = 0 ] && grep -qxF "$(NOCARD_ARGS "$D_ADD") --card $CARD" "$T/args.log"; ck "C1 --card 있음 → 분류기 인자 끝에 --card <카드>" $?
fresh; run a scope-approve "$D_ADD"
[ "$rc" = 0 ] && grep -qxF "$(NOCARD_ARGS "$D_ADD")" "$T/args.log" && ! grep -q -- '--card' "$T/args.log"; ck "C2 --card 없음 → 분류기 인자 바이트 그대로(--card 0)" $?
FT_SCOPE_CLASSIFY="$REAL"

# ── 변이 M1·M2 — 사본(심볼릭 묶음 + 바뀐 ft-autonomy-scope.sh)에서 «잡혀야 할 칸» 이 뒤집히는지
WIRE='[ -z "${card:-}" ] || a+=(--card "$card")'
mut() {  # mut <이름> <새 줄> → $T/mut-<이름>
  local mb="$T/mut-$1"; mkdir -p "$mb"; for f in "$BIN"/*; do ln -s "$f" "$mb/$(basename "$f")"; done; rm -f "$mb/ft-autonomy-scope.sh"
  python3 - "$BIN/ft-autonomy-scope.sh" "$mb/ft-autonomy-scope.sh" "$WIRE" "$2" <<'PY' || { echo "FAIL 변이 $1 못 만듦"; fail=$((fail+1)); }
import sys
s = open(sys.argv[1], encoding="utf-8").read()
assert s.count(sys.argv[3]) == 1, sys.argv[3]
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4]))
PY
}
mut m1 ':'; A="$T/mut-m1"; fresh; run a scope-approve "$D_IN" --card "$CARD"
[ "$rc" = 2 ] && has 'FORBID kind=delete'; ck "M1 배선 줄 빼기 → ① 칸이 FORBID 로 뒤집힌다(잡힘)" $?
mut m2 'a+=(--card "${card:-}")'; A="$T/mut-m2"; FT_SCOPE_CLASSIFY="$T/fake.sh"; fresh; run a scope-approve "$D_ADD"
[ -s "$T/args.log" ] && ! grep -qxF "$(NOCARD_ARGS "$D_ADD")" "$T/args.log"; ck "M2 빈 값도 붙이기 → C2·④ 인자 대조가 깨진다(잡힘)" $?
A="$BIN"; FT_SCOPE_CLASSIFY="$REAL"

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
