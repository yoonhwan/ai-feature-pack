#!/usr/bin/env bash
# test_index_move_followup_r1997.sh — r1997: 진행→완성 이동 때 카드 «- 남은 범위:» 줄 검사(followup_gate).
#   꼴 = «- 남은 범위: 없음» 또는 «- 남은 범위: <카드 이름>[ · <카드 이름> …] — <설명>» · 여러 줄이면 마지막 줄 · 후속 카드 = 같은 팀 indices/{대기,진행,완성,완성후}/ 실재.
#   임시 HOME·임시 git 리포 픽스처만 — 실제 indices·홈 쓰기 0. SRC=<bin 폴더> 로 옛 판·변이를 같은 시험으로 돌린다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="${SRC:-$(cd "$HERE/../bin" && pwd -P)}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 HOME="$T/home"
unset FT_INSTALL_CHECK FT_INSTALL_PENDING_DIR FT_LANDED_MARKER FT_TEAMS_MD FT_TRACK FT_THREAD_POST
export FT_INDEX_STATE_DIR="$T/state" FT_SEATS_JSON="$T/seats.json" FT_MBOX=/bin/true FT_LAND_REF=HEAD
BIN="$T/bin"; mkdir -p "$BIN" "$HOME" "$T/state"; echo "{}" > "$T/seats.json"
cp "$SRC"/ft-index-move.sh "$SRC"/ft-index-move-canon.sh "$SRC"/ft-index-move-install.sh "$SRC"/ft_da_hold_gate.py "$SRC"/ft_git_capped.py "$SRC"/ft-evidence-inject-scan.sh "$SRC"/ft-team-lib.sh "$BIN/"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/ft-index-lint.sh"   # lint 는 이 카드의 계약이 아니다

REPO="$T/repo"; IDX="$REPO/design/harness/indices"; mkdir -p "$IDX"/{대기,진행,완성,완성후}
git -C "$REPO" init -q -b main . && git -C "$REPO" config user.email t@t && git -C "$REPO" config user.name t
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n| v65 | `design/v65/` | v | 현역 |\n' > "$REPO/design/TEAMS.md"
cat > "$REPO/design/harness/DA-x.md" <<'EOF'
# 판정문
## §1 닫힘: f1 f2 f3 f4 f5 f6 f7 r9100-self
## §2 f8 — 닫힘 (CLOSE)
닫힘 — f8 — 버림
EOF
git -C "$REPO" add -A && git -C "$REPO" commit -qm base
DA="$REPO/design/harness/DA-x.md"

# card <폴더> <이름> [남은 범위 값 …(줄마다 1개 · 생략 = 줄 없음)]
card() {
  local f="$IDX/$1/$2.md" v; shift 2
  { echo "# 인덱스: $(basename "$f" .md)"; echo "## 상태"; echo "- 정본 영향 없음: 하네스 도구만 변경 — 제품 정본 없음"
    echo "- 규칙: 없음 — 시험 fixture 카드(규칙 무관)"; echo "- 설치: 없음"
    for v in "$@"; do echo "- 남은 범위: $v"; done; } > "$f"
  echo "$f"
}
mv_() { bash "$BIN/ft-index-move.sh" "$@" 2>&1; }
expect_rej() { [ -f "$2" ] && echo "$3" | grep -q "^REJECT.*$4" && ok "$1" || bad "$1 :: ${3:0:400}"; }
expect_mv()  { [ -f "$IDX/$4/$2.md" ] && echo "$3" | grep -q '^MOVED' && ok "$1" || bad "$1 :: ${3:0:400}"; }

c="$(card 진행 f1)"; out="$(mv_ "$c" 완성 --da "$DA#§1" --seat s)"
expect_rej "① 남은 범위 줄 없음 → REJECT" "$c" "$out" "남은 범위 줄 없음"
c="$(card 진행 f2 "없음")"; out="$(mv_ "$c" 완성 --da "$DA#§1" --seat s)"
expect_mv "② 없음 → 이동" f2 "$out" 완성
echo "# 인덱스: r9002-registry" > "$IDX/대기/r9002-registry.md"
c="$(card 진행 f3 "r9002 — 등록표")"; out="$(mv_ "$c" 완성 --da "$DA#§1" --seat s)"
expect_mv "③ r9002 대기/ 실재 → 이동" f3 "$out" 완성
rm -f "$IDX/대기/r9002-registry.md"
c="$(card 진행 f4 "r9002 — 등록표")"; out="$(mv_ "$c" 완성 --da "$DA#§1" --seat s)"
expect_rej "④ r9002 없음 → REJECT" "$c" "$out" "후속 카드 r9002 없음"
c="$(card 진행 f5 "등록표 일반화 남음")"; out="$(mv_ "$c" 완성 --da "$DA#§1" --seat s)"
expect_rej "⑤ 이름 없는 설명 → REJECT" "$c" "$out" "후속 카드 이름 없음"
c="$(card 진행 f6 "r9002 — 등록표" "없음")"; out="$(mv_ "$c" 완성 --da "$DA#§1" --seat s)"
expect_mv "⑥ 두 줄 · 마지막 «없음» → 이동" f6 "$out" 완성
echo "# 인덱스: f7-next" > "$IDX/완성후/f7-next.md"
c="$(card 진행 f7 "r9002 — 등록표" "f7-next · f7 — 자기 이름 섞임")"; out="$(mv_ "$c" 완성 --da "$DA#§1" --seat s)"
expect_rej "⑦a 자기 이름 → REJECT" "$c" "$out" "자기 자신"
c="$(card 진행 r9100-self "r9100 — 자기 머리")"; out="$(mv_ "$c" 완성 --da "$DA#§1" --seat s)"
expect_rej "⑦b 자기 r 머리 → REJECT" "$c" "$out" "자기 자신"
c="$(card 진행 f9 "f7-next — 완성후/ 실재")"; printf '## §3 닫힘: f9\n' >> "$DA"; out="$(mv_ "$c" 완성 --da "$DA#§3" --seat s)"
expect_mv "⑦c 완성후/ 후속 카드 실재 → 이동" f9 "$out" 완성
c="$(card 진행 f8)"; out="$(mv_ "$c" 아카이브 --da "$DA#§2" --seat s)"
expect_mv "⑧ 아카이브 갈래 · 줄 없음 → 이동" f8 "$out" "아카이브/$(date '+%Y-%m')"
c="$(card 대기 f10)"; out="$(mv_ "$c" 진행 --seat s)"
expect_mv "⑨ 대기→진행 · 줄 없음 → 이동" f10 "$out" 진행

echo "fail=$fail"; [ "$fail" = 0 ]
