#!/usr/bin/env bash
# test_autonomy_scope_card_delete_r1778.sh — r1778 카드 범위 안 파일 삭제 = forbid «delete» 대신 경로 분류(docs/code)
#   반례 ①~⑦ + 변이 M1(목록 확인 삭제)·M2(카드 못 읽음을 통과로) · ⑧(standing-approve 길)은 test_autonomy_card_delete_d2_r1778.sh
#   격리: 임시 origin(bare)+clone 만 · 실 저장소·실 gh·실 원격·실 상태 0 · press 0(나노는 쏘지 않는다) · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$(cd "$HERE/../bin" && pwd -P)"
CLS="$BIN/autonomy_scope_classify.py"; RULES="$BIN/autonomy_scope_rules.py"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
want() { [ "$rc" = "$2" ] && [[ "$out" == $3* ]]; ck "$1" $?; }   # want <이름> <rc> <출력 머리>
T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
mkrepo "$T"; export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state"; mkdir -p "$T/state"

# 기준 저장소 — 카드 범위 안/밖 경로를 한 커밋에 깔고 main = 그 커밋
mkdir -p "$W/design/teams/t/indices/대기" "$W/design/teams/t/indices/진행" "$W/docs" "$W/scripts" "$W/app"
echo d > "$W/design/x.md"; echo d > "$W/design/y.md"; echo d > "$W/docs/a.md"
printf '#!/bin/sh\n' > "$W/scripts/run.sh"; printf '#!/bin/sh\n' > "$W/scripts/run2.sh"; echo 'X=1' > "$W/app/.env"
seq 1 40 | sed 's/^/card line /' > "$W/design/teams/t/indices/대기/c1.md"
cm "$W" base2; git -C "$W" push -q origin main; BASE_MAIN="$(sha "$W" HEAD)"
echo m1 > "$W/m1.txt"; cm "$W" m1; git -C "$W" push -q origin main; git -C "$W" fetch -q origin; BASE="$BASE_MAIN"   # main = BASE 위 한 칸 → BASE 가지는 ff 아님(docs)
mk() {  # mk <가지> <셸 명령…> — BASE 에서 가지를 따 명령 실행 후 커밋 → SHA
  local br="$1"; shift; git -C "$W" checkout -q -B "$br" "$BASE"; ( cd "$W" && eval "$*" ); cm "$W" "$br"; SHA="$(sha "$W" HEAD)"; }
cls() { out="$(python3 "$CLS" classify "$1" --repo "$W" --scope S1 "${@:2}" 2>&1)"; rc=$?; }

# 카드 픽스처 — «- 대상:» 줄 · «## 구현 범위» 절의 backtick 경로만 목록
CA="$T/card-a.md"; printf '# 카드\n\n- 대상: `design/x.md`\n\n## 구현 범위\n\n- `scripts/run.sh`\n\n## 상태\n- 2026\n' > "$CA"
CABS="$T/card-abs.md"; printf '# 카드\n\n- 대상(절대): `%s/design/x.md`\n\n## 상태\n- 2026\n' "$W" > "$CABS"
CENV="$T/card-env.md"; printf '# 카드\n\n- 대상: `app/.env`\n\n## 상태\n- 2026\n' > "$CENV"
CDIR="$T/card-dir.md"; printf '# 카드\n\n- 대상: `scripts/`\n\n## 상태\n- 2026\n' > "$CDIR"
CNO="$T/card-none.md"; printf '# 카드\n\n## 구현 범위\n\n- 파일을 하나 지운다(`design/x.md:12`)\n\n## 상태\n- 2026\n' > "$CNO"
CY="$T/card-y.md"; printf '# 카드\n\n- 대상: `design/y.md`\n\n## 상태\n- 2026\n' > "$CY"

bash -n "$0"; ck "bash -n 시험" $?
python3 -I -m py_compile "$CLS" "$RULES"; ck "py_compile 2종" $?
[ "$(wc -l < "$CLS" | tr -d ' ')" -le 200 ]; ck "classify ≤ 200줄" $?

# ── ① 카드 대상 안 삭제 = 경로 분류(docs/code)
mk d1 'git rm -q design/x.md';    cls "$SHA" --card "$CA"; want "① 카드 대상 안 문서 삭제 → CLASS docs" 0 "CLASS docs"
mk d1c 'git rm -q scripts/run.sh'; cls "$SHA" --card "$CA"; want "① 카드 대상 안 코드 삭제 → CLASS code" 0 "CLASS code"
mk d1f 'git rm -q design/x.md';    cls "$SHA" --card "$CABS"; want "① 카드가 절대 경로로 지목 → CLASS docs" 0 "CLASS docs"
# ── ② 대상 밖 삭제 = 지금처럼 forbid delete
mk d2 'git rm -q docs/a.md';      cls "$SHA" --card "$CA"; want "② 카드 대상 밖 삭제 → FORBID kind=delete" 3 "FORBID kind=delete"
mk d2b 'git rm -q design/y.md design/x.md'; cls "$SHA" --card "$CA"; want "② 안·밖 섞인 삭제 → FORBID kind=delete" 3 "FORBID kind=delete"
# ── ③ 카드 못 읽음 = 닫힌 쪽
mk d3 'git rm -q design/x.md';    cls "$SHA" --card "$T/없는카드.md"; want "③ 카드 파일 없음 → FORBID kind=delete" 3 "FORBID kind=delete"
cls "$SHA" --card "$CNO"; want "③ 카드에 목록이 없음 → FORBID kind=delete" 3 "FORBID kind=delete"
# ── ④ 대상 안이지만 경계 종류(secret 경로) = 그 종류로 forbid
mk d4 'git rm -q app/.env';       cls "$SHA" --card "$CENV"; want "④ 대상 안 .env 삭제 → FORBID kind=key" 3 "FORBID kind=key"
# ── ⑤ 폴더는 명시됐을 때만 하위가 안 · 폴더 미명시 하위 파일은 밖
mk d5 'git rm -q scripts/run.sh scripts/run2.sh'; cls "$SHA" --card "$CA"; want "⑤ 폴더 미명시(run.sh 만 지목) 하위 묶음 삭제 → FORBID" 3 "FORBID kind=delete"
cls "$SHA" --card "$CDIR"; want "⑤ 폴더 «scripts/» 명시 → 두 파일 삭제 CLASS code" 0 "CLASS code"
# ── ⑥ 같은 팀 카드 이동 = R100 그대로(카드 범위가 판정을 바꾸지 않는다)
mk d6 'mkdir -p design/teams/t/indices/진행 && mv design/teams/t/indices/대기/c1.md design/teams/t/indices/진행/'; cls "$SHA" --card "$CA"; want "⑥ 카드 이동(R100) → CLASS docs(그대로)" 0 "CLASS docs"
mk d6b 'mkdir -p design/teams/t/indices/진행 && mv design/teams/t/indices/대기/c1.md design/teams/t/indices/진행/c9.md'; cls "$SHA" --card "$CA"; want "⑥ 이름 바꾼 이동 → FORBID rename(그대로)" 3 "FORBID kind=rename"
# ── ⑦ 기존 호출(--card 없음) = 지금과 같은 결과
mk d7 'git rm -q design/x.md'; cls "$SHA"; want "⑦ --card 없음 + 삭제 → FORBID kind=delete(그대로)" 3 "FORBID kind=delete"
mk d7b 'echo n > design/new.md'; cls "$SHA"; want "⑦ --card 없음 + 문서 추가 → CLASS docs(그대로)" 0 "CLASS docs"
# ── 카드 문맥: 목록 밖 낱말·예시 글롭은 목록 아님(닫힌 쪽)
CT="$T/card-trap.md"; printf '# 카드\n\n- 대상: `design/x.md`\n\n## 구현 범위\n\n- `scripts/**` · `docs/a.md:3` · `path_class`\n\n## 상태\n- 2026\n' > "$CT"
mk d8 'git rm -q docs/a.md'; cls "$SHA" --card "$CT"; want "글롭·줄번호가 붙은 경로는 목록 아님 → FORBID" 3 "FORBID kind=delete"

# ── 변이 M1·M2 — 변이 판에서 «빨강이어야 할 칸» 이 통과해 버리는지
mut() {  # mut <이름> <파일> <바꿀 줄(정확히 1회)> <새 줄>
  local mb="$T/mut-$1"; rm -rf "$mb"; mkdir -p "$mb"; for f in "$BIN"/*; do ln -s "$f" "$mb/$(basename "$f")"; done; rm -f "$mb/$2"
  python3 - "$BIN/$2" "$mb/$2" "$3" "$4" <<'PY' || { echo "FAIL 변이 $1 못 만듦"; fail=$((fail+1)); }
import sys
s = open(sys.argv[1], encoding="utf-8").read()
assert s.count(sys.argv[3]) == 1, sys.argv[3]
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4]))
PY
}
mcls() { out="$(python3 "$T/mut-$1/autonomy_scope_classify.py" classify "$2" --repo "$W" --scope S1 --card "$3" 2>&1)"; rc=$?; }
DB='    if st[0] == "D" and card_scope and all(in_card_scope(card_scope, p) for p in paths):'
mut m1 autonomy_scope_rules.py "$DB" '    if False:'; mcls m1 "$SHA" "$CT"
[ "$rc" = 3 ]; ck "M1 목록 확인 삭제 → ② 칸이 통과해 버린다(빨강)" $?
mut m2 autonomy_scope_rules.py '    if st[0] == "D" and card_scope and all(in_card_scope(card_scope, p) for p in paths):' \
  '    if st[0] == "D" and (not card_scope or all(in_card_scope(card_scope, p) for p in paths)):'
mcls m2 "$SHA" "$T/없는카드.md"
[ "$rc" = 0 ] && [[ "$out" == "CLASS docs" ]]; ck "M2 카드 못 읽음을 통과로 → ③ 칸이 삭제를 통과시킨다(빨강)" $?

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
