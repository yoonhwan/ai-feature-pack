#!/usr/bin/env bash
# test_team_scaffold.sh — ft-team-scaffold.sh: 팀 폴더 빈 틀(R318a). 임시 git 리포 픽스처만 — 실제 design/ 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRCDIR="$HERE/../../harness/bin"
KIT="$HERE/../../harness/kit/fable-team"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

for f in "$SRCDIR/ft-team-scaffold.sh" "$KIT/bin/ft-team-scaffold.sh"; do bash -n "$f" && ok "bash -n ${f##*/}" || bad "bash -n $f"; done
cmp -s "$SRCDIR/ft-team-scaffold.sh" "$KIT/bin/ft-team-scaffold.sh" && ok "키트 사본 cmp0" || bad "키트 사본 cmp"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
export FT_TEAM_TEMPLATE_DIR="$KIT/templates/team"
REPO="$T/repo"; mkdir -p "$REPO/design"
cat > "$REPO/design/TEAMS.md" <<'E'
# 팀 명단 — 이 명단에 없는 design/ 폴더(v65·rag·ccu…)는 팀이 아니다
| 팀 | 폴더 | 오케 좌석 | 상태 |
|---|---|---|---|
| demo | `design/demo/` | demo-master 계열 | 현역 |
E
G() { git -C "$REPO" "$@"; }
G init -q -b main . && G config user.email t@t && G config user.name t && G add -A && G commit -qm base
SC() { (cd "$REPO" && bash "$SRCDIR/ft-team-scaffold.sh" "$@" 2>&1); }

# 1 명단에 없는 팀 → REJECT · 폴더 0
out="$(SC nope)"; rc=$?
[ "$rc" = 1 ] && echo "$out" | grep -q '^REJECT' && [ ! -e "$REPO/design/nope" ] && ok "1 TEAMS.md 밖 팀 REJECT" || bad "1: rc=$rc $out"

# 2 --dry-run → 쓰기 0 · 목록 출력 · rc0
out="$(SC --dry-run demo)"; rc=$?
[ "$rc" = 0 ] && [ ! -e "$REPO/design/demo" ] && echo "$out" | grep -q 'README.md' && echo "$out" | grep -q 'plans/.gitkeep' && ok "2 --dry-run 쓰기 0 + 목록" || bad "2: rc=$rc $out"

# 3 실행 → 빈 틀 전부 생성 rc0
out="$(SC demo)"; rc=$?
miss=""
for p in README.md GOAL-demo.md GUIDE-demo.md STATE.md plans/.gitkeep indices/inbox/.gitkeep indices/대기/.gitkeep indices/진행/.gitkeep indices/완성/.gitkeep orders/.gitkeep reviews/.gitkeep evidence/.gitkeep closeout/.gitkeep archive/.gitkeep; do
  [ -f "$REPO/design/demo/$p" ] || miss="$miss $p"
done
[ "$rc" = 0 ] && [ -z "$miss" ] && ok "3 빈 틀 생성(plans/ 포함 · 파일명 팀 치환)" || bad "3: rc=$rc miss=$miss $out"

# 4 프로젝트 기록 0 — 골 원문·좌석 이름·카드 번호가 만든 파일에 없다
hits="$(grep -rEl 'byz-|FB_|빠른 유용 원문|내부 하네스|REQUEST-LEDGER|#[0-9]+' "$REPO/design/demo" 2>/dev/null)"
[ -z "$hits" ] && ok "4 프로젝트 기록 0(grep)" || bad "4: $hits"

# 5 STATE 머리 문구 · GOAL 한 줄 · 자리표시 `<팀>` 이 남지 않는다
st="$(cat "$REPO/design/demo/STATE.md")"
echo "$st" | grep -q '요약' && echo "$st" | grep -q '링크' && echo "$st" | grep -q '명부' && echo "$st" | grep -q '카드 폴더' && echo "$st" | grep -q '팀 오케' && ok "5a STATE 머리 문구" || bad "5a STATE: $st"
grep -q '오빠 승인 뒤 기입' "$REPO/design/demo/GOAL-demo.md" && ok "5b GOAL 한 줄" || bad "5b GOAL"
grep -rq '<팀>' "$REPO/design/demo" && bad "5c <팀> 자리표시 잔존" || ok "5c <팀> 치환"

# 6 커밋에 빈 폴더 .gitkeep 이 남는다
G add -A && G commit -qm scaffold
[ "$(G ls-files design/demo | grep -c '\.gitkeep$')" = 10 ] && ok "6 .gitkeep 10개 추적" || bad "6: $(G ls-files design/demo | grep -c gitkeep)"

# 7 2회째 실행 변경 0 · 기존 파일 보존
echo "손으로 쓴 줄" >> "$REPO/design/demo/GUIDE-demo.md"; G commit -qam edit
out="$(SC demo)"; rc=$?
[ "$rc" = 0 ] && [ -z "$(G status --porcelain)" ] && echo "$out" | grep -q 'created=0' && grep -q '손으로 쓴 줄' "$REPO/design/demo/GUIDE-demo.md" && ok "7 멱등 · 기존 파일 보존" || bad "7: rc=$rc $out $(G status --porcelain)"

# 8 일부 칸만 없으면 그 칸만 만든다
rm -f "$REPO/design/demo/STATE.md"
out="$(SC demo)"; rc=$?
[ "$rc" = 0 ] && [ -f "$REPO/design/demo/STATE.md" ] && echo "$out" | grep -q 'created=1' && ok "8 없는 칸만 생성" || bad "8: rc=$rc $out"

# 9 인자 없음 → usage rc2
out="$(SC)"; rc=$?
[ "$rc" = 2 ] && ok "9 usage rc2" || bad "9: rc=$rc $out"

# 10 팀 이름에 경로 문자 → REJECT
out="$(SC '../x')"; rc=$?
[ "$rc" != 0 ] && [ ! -e "$REPO/design/../x" ] && ok "10 팀 이름 검증" || bad "10: rc=$rc $out"

# 11 깨진(dangling) 심볼릭 링크 = «있는 칸» — 링크를 따라 팀 폴더 밖에 파일을 만들지 않는다(DA⑥ r1 H2)
echo '| demo2 | `design/demo2/` | demo2-master 계열 | 현역 |' >> "$REPO/design/TEAMS.md"
mkdir -p "$REPO/design/demo2" "$T/out"
ln -s "$T/out/created-by-dangling.md" "$REPO/design/demo2/STATE.md"
out="$(SC demo2)"; rc=$?
[ "$rc" = 0 ] && [ ! -e "$T/out/created-by-dangling.md" ] && [ -L "$REPO/design/demo2/STATE.md" ] && echo "$out" | grep -q 'SKIP.*STATE.md' && ok "11 dangling 링크 SKIP · 밖 파일 0" || bad "11: rc=$rc $out $(ls "$T/out")"

# 12 하위 폴더 자체가 밖을 가리키는 링크 — 밖에 .gitkeep·파일을 만들지 않는다
rm -rf "$REPO/design/demo2" "$T/out"; mkdir -p "$REPO/design/demo2" "$T/out"
ln -s "$T/out" "$REPO/design/demo2/plans"
out="$(SC demo2)"; rc=$?
[ "$rc" = 0 ] && [ -z "$(ls -A "$T/out")" ] && echo "$out" | grep -q 'SKIP.*plans' && [ -f "$REPO/design/demo2/README.md" ] && ok "12 폴더 링크 탈출 SKIP · 밖 파일 0 · 나머지 칸은 생성" || bad "12: rc=$rc $out $(ls -A "$T/out")"

# 13 팀 폴더 자체가 밖을 가리키는 링크 — 밖에 아무것도 만들지 않는다
rm -rf "$REPO/design/demo2" "$T/out"; mkdir -p "$T/out"; ln -s "$T/out" "$REPO/design/demo2"
out="$(SC demo2)"
[ -z "$(ls -A "$T/out")" ] && ok "13 팀 폴더 링크 밖 파일 0" || bad "13: $out $(ls -A "$T/out")"

# 14 팀 폴더가 design/ 자체를 가리키는 링크 — REJECT · design/README.md 0 (DA⑥ r2 남은 1)
rm -rf "$REPO/design/demo2" "$T/out"; ln -s "$REPO/design" "$REPO/design/demo2"
out="$(SC demo2)"; rc=$?
[ "$rc" = 1 ] && echo "$out" | grep -q '^REJECT.*링크' && [ ! -e "$REPO/design/README.md" ] && ok "14 팀 폴더=design 링크 REJECT · design/README.md 0" || bad "14: rc=$rc $out $(ls "$REPO/design")"
rm -f "$REPO/design/demo2"

# 15 하위 폴더가 design/ 자체를 가리키는 링크(indices -> design/) — design/inbox 등 팀 밖 쓰기 0 · SKIP 1줄 · 나머지 칸 생성 (r318a DA⑥ r3 H2)
echo '| demo3 | `design/demo3/` | demo3-master 계열 | 현역 |' >> "$REPO/design/TEAMS.md"
mkdir -p "$REPO/design/demo3"; ln -s "$REPO/design" "$REPO/design/demo3/indices"
before="$(ls -A "$REPO/design" | LC_ALL=C sort | tr '\n' ' ')"
out="$(SC demo3)"; rc=$?
after="$(ls -A "$REPO/design" | LC_ALL=C sort | tr '\n' ' ')"
[ "$rc" = 0 ] && [ "$before" = "$after" ] && [ ! -e "$REPO/design/inbox" ] && echo "$out" | grep -q 'SKIP.*indices' && [ -f "$REPO/design/demo3/README.md" ] && ok "15 하위 링크=design 탈출 SKIP · design/inbox 0 · 나머지 칸 생성" || bad "15: rc=$rc before=[$before] after=[$after] $out"
rm -f "$REPO/design/demo3/indices"

echo "fail=$fail"; [ "$fail" = 0 ]
