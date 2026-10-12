#!/usr/bin/env bash
# test_index_move_rule_line.sh — ft-index-move 진행→완성: 카드 `- 규칙:` 줄 검사(r106b · R106 자매).
#   규칙은 «읽히는 곳(상시 로드 지침)» + «막는 곳(훅·게이트)» 이 실재해야 닫는다. 임시 HOME·임시 git 리포 픽스처만 — 실제 indices·홈 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRCDIR="$HERE/../../scripts/fable-team-bin"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

for f in ft-index-move.sh "../harness-install/fable-team/bin/ft-index-move.sh"; do bash -n "$SRCDIR/$f" && ok "bash -n $f" || bad "bash -n $f"; done

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
BIN="$T/bin"; mkdir -p "$BIN"
cp "$SRCDIR/ft-index-move.sh" "$SRCDIR/ft-index-move-canon.sh" "$SRCDIR/ft-evidence-inject-scan.sh" "$BIN/"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/ft-index-lint.sh"
export HOME="$T/home" FT_INDEX_STATE_DIR="$T/state" FT_SEATS_JSON="$T/none.json" FT_MBOX=/bin/true FT_LAND_REF=HEAD
mkdir -p "$HOME/.claude" "$T/state"
echo "# 전역 지침" > "$HOME/.claude/CLAUDE.md"

REPO="$T/repo"; IDX="$REPO/design/harness/indices"; mkdir -p "$IDX"/{대기,진행,완성} "$REPO/.claude/rules" "$REPO/hooks"
printf '# 판정문\n## §1 닫힘: 카드 이름 r1 r2 r3 r4 r5 r6 r7 r8 h1 h2 h3 h4 h5 h6\n' > "$REPO/design/harness/DA-x.md"
echo "# 프로젝트 지침" > "$REPO/CLAUDE.md"; echo "# 규칙" > "$REPO/.claude/rules/r.md"; echo "# 일반 문서" > "$REPO/design/x.md"
echo '#!/usr/bin/env bash' > "$REPO/hooks/guard.sh"
git -C "$REPO" init -q -b main . && git -C "$REPO" config user.email t@t && git -C "$REPO" config user.name t
git -C "$REPO" add -A && git -C "$REPO" commit -qm base
DA="$REPO/design/harness/DA-x.md#§1"

# card <폴더> <이름> [규칙 줄 전문 — 생략하면 줄 없음]
card() {
  local f="$IDX/$1/$2.md"
  { echo "# 인덱스: $2"; echo "## 상태"; echo "- 정본 영향 없음: 하네스 도구만 변경 — 제품 정본 없음"
    [ $# -ge 3 ] && echo "- 규칙: $3"; } > "$f"
  echo "$f"
}
mv_() { bash "$BIN/ft-index-move.sh" "$@" 2>&1; }
expect_rej() { # <번호> <카드> <출력> <패턴>
  [ -f "$2" ] && [ ! -f "$IDX/완성/$(basename "$2")" ] && echo "$3" | grep -q "^REJECT.*$4" && ok "$1" || bad "$1: $3"
}
expect_mv() { [ -f "$IDX/완성/$2.md" ] && echo "$3" | grep -q '^MOVED' && ok "$1" || bad "$1: $3"; }

# ⓐ 규칙 줄 없음 → REJECT
c="$(card 진행 r1)"; out="$(mv_ "$c" 완성 --da "$DA" --seat s)"
expect_rej "ⓐ 규칙 줄 없음 → REJECT" "$c" "$out" "「- 규칙:」 줄 없음"
# ⓑ 없음 — 사유 10자 이상 → 통과
c="$(card 진행 r2 "없음 — 시험 fixture 카드(규칙 무관)")"; out="$(mv_ "$c" 완성 --da "$DA" --seat s)"
expect_mv "ⓑ 없음 + 사유 10자 이상 → 통과" r2 "$out"
# ⓒ 없음 — 짧음 → REJECT
c="$(card 진행 r3 "없음 — 짧음")"; out="$(mv_ "$c" 완성 --da "$DA" --seat s)"
expect_rej "ⓒ 사유 10자 미만 → REJECT" "$c" "$out" "사유"
# ⓓ 지침(전역 CLAUDE.md · ~ 펼침)·강제 둘 다 실재 → 통과
c="$(card 진행 r4 "지침=~/.claude/CLAUDE.md:3 · 강제=hooks/guard.sh")"; out="$(mv_ "$c" 완성 --da "$DA" --seat s)"
expect_mv "ⓓ 지침·강제 실재 → 통과" r4 "$out"
# ⓔ 강제 경로 실재 0 → REJECT
c="$(card 진행 r5 "지침=CLAUDE.md · 강제=hooks/none.sh")"; out="$(mv_ "$c" 완성 --da "$DA" --seat s)"
expect_rej "ⓔ 강제 경로 없음 → REJECT" "$c" "$out" "강제"
# ⓕ 지침이 상시 로드 목록 밖 → REJECT
c="$(card 진행 r6 "지침=design/x.md · 강제=hooks/guard.sh")"; out="$(mv_ "$c" 완성 --da "$DA" --seat s)"
expect_rej "ⓕ 상시 로드 목록 밖 지침 → REJECT" "$c" "$out" "상시 로드"
# ⓕb 지침 경로 실재 0 → REJECT · 프로젝트 .claude/rules 아래 md 는 통과
c="$(card 진행 r7 "지침=.claude/rules/none.md · 강제=hooks/guard.sh")"; out="$(mv_ "$c" 완성 --da "$DA" --seat s)"
expect_rej "ⓕb 지침 경로 없음 → REJECT" "$c" "$out" "지침"
c="$(card 진행 r8 "지침=.claude/rules/r.md · 강제=hooks/guard.sh")"; out="$(mv_ "$c" 완성 --da "$DA" --seat s)"
expect_mv "ⓕc 프로젝트 rules md → 통과" r8 "$out"
# ⓖ 대기→진행 이동은 규칙 줄 검사 0
c="$(card 대기 g1)"; out="$(mv_ "$c" 진행 --seat s)"
[ -f "$IDX/진행/g1.md" ] && echo "$out" | grep -q '^MOVED' && ok "ⓖ 대기→진행 검사 0" || bad "ⓖ: $out"

# fix1 (DA⑥ H1) — 값은 «정확한 두 형식»만: 접두 «없음» 만으로 면제되지 않는다
c="$(card 진행 h1 "없음X 잘못된문장이지만 열자는 넘는다")"; out="$(mv_ "$c" 완성 --da "$DA" --seat s)"
expect_rej "fix1ⓐ 없음X … → REJECT" "$c" "$out" "형식"
c="$(card 진행 h2 "없음 - 하이픈 사유 열자이상입니다")"; out="$(mv_ "$c" 완성 --da "$DA" --seat s)"
expect_rej "fix1ⓑ 하이픈 구분자 → REJECT" "$c" "$out" "형식"
c="$(card 진행 h3 "없음—붙여쓴 사유 열자이상")"; out="$(mv_ "$c" 완성 --da "$DA" --seat s)"
expect_rej "fix1ⓒ 붙여쓴 em dash → REJECT" "$c" "$out" "형식"
c="$(card 진행 h4 "없음 — 정상 사유 열자 이상")"; out="$(mv_ "$c" 완성 --da "$DA" --seat s)"
expect_mv "fix1ⓓ 정상 사유 → 통과" h4 "$out"
c="$(card 진행 h5 "지침=CLAUDE.md")"; out="$(mv_ "$c" 완성 --da "$DA" --seat s)"
expect_rej "fix1ⓔ 강제 칸 없음 → REJECT" "$c" "$out" "형식"
c="$(card 진행 h6 "없음 — 아홉글자사유입니다")"; out="$(mv_ "$c" 완성 --da "$DA" --seat s)"
expect_rej "fix1ⓕ 한글 9자 사유 → REJECT(바이트 아닌 글자 수)" "$c" "$out" "형식"

echo "fail=$fail"; [ "$fail" = 0 ]
