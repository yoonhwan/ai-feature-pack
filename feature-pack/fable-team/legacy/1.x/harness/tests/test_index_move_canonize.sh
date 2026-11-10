#!/usr/bin/env bash
# test_index_move_canonize.sh — ft-index-move 진행→완성: 세 번째 꼴 «정본화: <경로>[, <경로>…]»(R318a).
#   허용 뿌리 = docs/architect/ · docs/rules/ · design/<TEAMS.md 팀>/GUIDE-*.md · design/<팀>/README.md. 임시 git 리포 픽스처만.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRCDIR="$HERE/../../harness/bin"
KIT="$HERE/../../harness/kit/fable-team/bin"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

for f in ft-index-move.sh ft-index-move-canon.sh; do
  cmp -s "$SRCDIR/$f" "$KIT/$f" && ok "키트 사본 cmp0 $f" || bad "키트 사본 cmp $f"
done

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
BIN="$T/bin"; mkdir -p "$BIN"
cp "$SRCDIR/ft-index-move.sh" "$SRCDIR/ft-index-move-canon.sh" "$SRCDIR/ft-index-move-install.sh" "$SRCDIR/ft_da_hold_gate.py" "$SRCDIR/ft_git_capped.py" "$BIN/"
cp "$SRCDIR/ft-team-lib.sh" "$BIN/"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/ft-index-lint.sh"
export FT_MBOX=/bin/true FT_INDEX_STATE_DIR="$T/state" FT_LAND_REF=HEAD FT_SEATS_JSON="$T/none.json"
mkdir -p "$T/state"

REPO="$T/repo"; IDX="$REPO/design/harness/indices"; mkdir -p "$IDX"/{대기,진행,완성} "$REPO/docs/architect" "$REPO/docs/rules" "$REPO/design/other"
G() { git -C "$REPO" "$@"; }
cat > "$REPO/design/TEAMS.md" <<'E'
| 팀 | 폴더 | 오케 좌석 | 상태 |
|---|---|---|---|
| harness | `design/harness/` | h-master 계열 | 현역 |
E
echo "# 규칙" > "$REPO/docs/rules/foo.md"; echo "# 지침" > "$REPO/design/harness/GUIDE-harness.md"
echo "# 지도" > "$REPO/design/harness/README.md"; echo "# 비지침" > "$REPO/design/harness/notes.md"
echo "# 명단밖" > "$REPO/design/other/GUIDE-other.md"; echo "x" > "$REPO/x"
printf '## 절A 제목\nv1\n' > "$REPO/docs/architect/X.md"
echo outside > "$T/outside.md"; ln -s "$T/outside.md" "$REPO/docs/rules/link.md"
G init -q -b main . && G config user.email t@t && G config user.name t && G add -A && G commit -qm base

card() { # <이름> <줄...> — 진행/ 카드, 경로 출력
  local f="$IDX/진행/$1.md"; shift
  { echo "# 인덱스: c"; echo "## 상태"; printf '%s\n' "$@"; echo "- 규칙: 없음 — 시험 fixture 카드(규칙 무관)"; echo "- 설치: 없음"; } > "$f"; echo "$f"
}
da() { local f="$REPO/design/harness/DA-$1.md"; printf '# 판정문\n## §1 닫힘: %s\n' "$1" > "$f"; echo "$f"; }
mv_() { bash "$BIN/ft-index-move.sh" "$@" 2>&1; }
pass() { # <번호> <카드이름> <줄...>
  local n="$1" id="$2"; shift 2; local c d out; c="$(card "$id" "$@")"; d="$(da "$id")"
  out="$(mv_ "$c" 완성 --da "$d#§1" --seat s)"
  [ -f "$IDX/완성/$id.md" ] && echo "$out" | grep -q '^MOVED' && ok "$n" || bad "$n: $out"
}
rej() { # <번호> <카드이름> <사유 패턴> <줄...>
  local n="$1" id="$2" pat="$3"; shift 3; local c d out; c="$(card "$id" "$@")"; d="$(da "$id")"
  out="$(mv_ "$c" 완성 --da "$d#§1" --seat s)"
  [ -f "$c" ] && [ ! -f "$IDX/완성/$id.md" ] && echo "$out" | grep -q "^REJECT.*$pat" && ok "$n" || bad "$n: $out"
}

pass "1 정본화 docs/rules/ 실재 OK" k1 "- 정본화: docs/rules/foo.md"
pass "2 정본화 GUIDE-harness.md OK" k2 "- 정본화: design/harness/GUIDE-harness.md"
pass "3 정본화 팀 README OK" k3 "- 정본화: design/harness/README.md"
pass "4 정본화 docs/architect/ OK" k4 "- 정본화: docs/architect/X.md"
pass "5 정본화 두 경로(쉼표) OK" k5 "- 정본화: docs/rules/foo.md, design/harness/GUIDE-harness.md"
rej  "6 /etc/passwd REJECT" k6 "정본화" "- 정본화: /etc/passwd"
rej  "7 docs/../x REJECT" k7 "정본화" "- 정본화: docs/../x"
rej  "8 없는 파일 REJECT" k8 "정본화" "- 정본화: docs/rules/none.md"
rej  "9 심볼릭 링크 탈출 REJECT" k9 "정본화" "- 정본화: docs/rules/link.md"
rej  "10 TEAMS.md 밖 팀 GUIDE REJECT" k10 "정본화" "- 정본화: design/other/GUIDE-other.md"
rej  "11 팀 폴더 GUIDE·README 외 파일 REJECT" k11 "정본화" "- 정본화: design/harness/notes.md"
rej  "12 두 경로 중 하나라도 나쁘면 REJECT" k12 "정본화" "- 정본화: docs/rules/foo.md, /etc/passwd"
rej  "13 허용 뿌리 밖 repo 파일 REJECT" k13 "정본화" "- 정본화: x"

# 기존 꼴 회귀 0
pass "14 기존 정본 영향 없음(10자+) OK" k14 "- 정본 영향 없음: 하네스 도구만 변경 — 제품 정본 없음"
rej  "15 정본 줄 전부 없음 REJECT(세 꼴 안내)" k15 "정본화" "- 상태: 줄 없음"
# 기존 «정본 갱신» 은 --landed 필수 그대로
c="$(card k16 "- 정본 갱신: docs/architect/X.md §절A")"; d="$(da k16)"; out="$(mv_ "$c" 완성 --da "$d#§1" --seat s)"
[ -f "$c" ] && echo "$out" | grep -q '^REJECT.*landed' && ok "16 정본 갱신 --landed 필수 유지" || bad "16: $out"

# 허용 뿌리 «자체»가 워크트리 밖 링크(DA⑥ r1 H1) — 밖 파일이 통과하면 안 된다
mkdir -p "$T/outdocs" "$T/outteam"; echo "# 밖" > "$T/outdocs/foo.md"; echo "# 밖" > "$T/outteam/GUIDE-linkteam.md"
mv "$REPO/docs/rules" "$REPO/docs/rules.real"; ln -s "$T/outdocs" "$REPO/docs/rules"
ln -s "$T/outteam" "$REPO/design/linkteam"; echo '| linkteam | `design/linkteam/` | l-master 계열 | 현역 |' >> "$REPO/design/TEAMS.md"
rej  "17 뿌리(docs/rules)가 밖 링크 REJECT" k17 "정본화" "- 정본화: docs/rules/foo.md"
rej  "18 뿌리(design/<팀>)가 밖 링크 REJECT" k18 "정본화" "- 정본화: design/linkteam/GUIDE-linkteam.md"
rej  "19 두 경로 중 뿌리 링크 하나면 REJECT" k19 "정본화" "- 정본화: design/harness/README.md, docs/rules/foo.md"
pass "20 링크 아닌 뿌리는 여전히 OK" k20 "- 정본화: design/harness/GUIDE-harness.md"

echo "fail=$fail"; [ "$fail" = 0 ]
