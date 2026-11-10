#!/usr/bin/env bash
# test_index_move_team_goal_lines_r1166.sh — ft-index-move 대기→진행: FT_GOAL_LINES_FILE 이 비면 카드 팀 env 에서 읽는다(r1166).
#   반례 R1~R4 + 변이 1. lint 는 «골 3줄 대조» 만 하는 스텁(ft-index-lint.sh 의 골 줄 분기와 같은 규칙) — 이 시험은 이동 도구의 골 파일 결정만 본다.
#   임시 리포·임시 env 만 — 실 리포·실 명부 0 · 자기 재호출 0 · 고정 sleep 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRCDIR="$HERE/../bin"; KITDIR="$HERE/../kit/fable-team/bin"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$SRCDIR/ft-index-move.sh" && ok "bash -n bin" || bad "bash -n bin"
cmp -s "$SRCDIR/ft-index-move.sh" "$KITDIR/ft-index-move.sh" && ok "ⓓ bin·kit cmp0" || bad "ⓓ bin·kit 다름"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkbin() {  # <dir> <move 스크립트> — 이동 도구 + 골 대조 스텁 lint
  mkdir -p "$1"; cp "$2" "$1/ft-index-move.sh"; cp "$SRCDIR/ft-team-lib.sh" "$1/"
  cat > "$1/ft-index-lint.sh" <<'LINT'
#!/usr/bin/env bash
# 스텁: 골 3줄 대조만(진짜 lint 와 같은 분기) · 받은 환경 값을 $LINT_SEEN 에 남긴다
if [ -n "${FT_GOAL_LINES_FILE:-}" ] && [ -f "$FT_GOAL_LINES_FILE" ]; then
  G1="$(sed -n 1p "$FT_GOAL_LINES_FILE")"; G2="$(sed -n 2p "$FT_GOAL_LINES_FILE")"; G3="$(sed -n 3p "$FT_GOAL_LINES_FILE")"
else
  G1='목표는 빠른 유용 원문, 실시간 교정, N언어의 병렬·독립 발행, 소실·비의도 중복 없는 최종 말풍선이다.'
  G2='LST ON 우선이며 LST OFF/전환과 기존 M0–M7·통합 조건도 남긴다.'
  G3='단순히 실패 사례를 많이 모았다는 이유로 실험을 닫지 않는다.'
fi
[ -z "${LINT_SEEN:-}" ] || printf 'prefix=[%s]\n' "${FT_NANO_PREFIX:-}" > "$LINT_SEEN"
C="$(sed -n '/^## 골 원문/,/^## /p' "$1" | sed -n 2,4p)"
[ "$C" = "$G1
$G2
$G3" ] || { echo "골 1줄 불일치 — lint 실패(스텁)"; exit 1; }
LINT
}
BIN="$T/bin"; mkbin "$BIN" "$SRCDIR/ft-index-move.sh"
export HOME="$T/home"; mkdir -p "$HOME"
unset FT_GOAL_LINES_FILE FT_TEAM FT_NANO_PREFIX

REPO="$T/repo"; mkdir -p "$REPO/design/teams/g/indices/대기" "$REPO/design/v65/indices/대기" "$REPO/.fable-team/bin-g"
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| g | `design/teams/g/` | g | 현역 |\n| v65 | `design/v65/` | v | 현역 |\n' > "$REPO/design/TEAMS.md"
git -C "$REPO" init -q -b main . && git -C "$REPO" config user.email t@t && git -C "$REPO" config user.name t
printf 'G줄1\nG줄2\nG줄3\n' > "$REPO/.fable-team/bin-g/goal-lines-g.txt"
printf 'ENV줄1\nENV줄2\nENV줄3\n' > "$T/other-goal.txt"
cat > "$REPO/.fable-team/bin-g/g-env.sh" <<'ENV'
_R="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
export FT_GOAL_LINES_FILE="$_R/.fable-team/bin-g/goal-lines-g.txt"
export FT_NANO_PREFIX=byz-g-nano-
unset _R
ENV
V1='목표는 빠른 유용 원문, 실시간 교정, N언어의 병렬·독립 발행, 소실·비의도 중복 없는 최종 말풍선이다.'
V2='LST ON 우선이며 LST OFF/전환과 기존 M0–M7·통합 조건도 남긴다.'
V3='단순히 실패 사례를 많이 모았다는 이유로 실험을 닫지 않는다.'
gcard() { printf '# 인덱스: X\n## 골 원문 (항상 이 3줄)\nG줄1\nG줄2\nG줄3\n## 상태\n- 대기\n' > "$REPO/design/teams/g/indices/대기/X.md"; }
vcard() { printf '# 인덱스: V\n## 골 원문 (항상 이 3줄)\n%s\n%s\n%s\n## 상태\n- 대기\n' "$V1" "$V2" "$V3" > "$REPO/design/v65/indices/대기/V.md"; }
reset_cards() { rm -rf "$REPO/design/teams/g/indices/진행" "$REPO/design/v65/indices/진행"; gcard; vcard; git -C "$REPO" add -A >/dev/null 2>&1; git -C "$REPO" commit -qm c >/dev/null 2>&1 || true; }
mv_g() { bash "$1/ft-index-move.sh" "$REPO/design/teams/g/indices/대기/X.md" 진행 --seat s 2>&1; }

reset_cards
out="$(LINT_SEEN="$T/seen" mv_g "$BIN")"; rc=$?
{ [ "$rc" = 0 ] && [ -f "$REPO/design/teams/g/indices/진행/X.md" ]; } && ok "R1/ⓐ 팀 env 골 파일 · rc0 · 진행 폴더" || bad "R1 rc=$rc: $out"
echo "$out" | grep -q '^INFO 골 줄 출처 = 팀 g env' && ok "R1 INFO 출처 1줄" || bad "R1 INFO 없음: $out"
grep -q 'prefix=\[\]' "$T/seen" 2>/dev/null && ok "R1 env 의 다른 값(FT_NANO_PREFIX)이 이동 도구에 안 샌다" || bad "R1 env 누출: $(cat "$T/seen" 2>/dev/null)"

reset_cards
out="$(FT_GOAL_LINES_FILE="$T/other-goal.txt" mv_g "$BIN")"; rc=$?
{ [ "$rc" = 1 ] && [ -f "$REPO/design/teams/g/indices/대기/X.md" ]; } && ok "R2/ⓑ 명시 파일이 이김(그 파일 기준 REJECT)" || bad "R2 rc=$rc: $out"

reset_cards
out="$(bash "$BIN/ft-index-move.sh" "$REPO/design/v65/indices/대기/V.md" 진행 --seat s 2>&1)"; rc=$?
{ [ "$rc" = 0 ] && [ -f "$REPO/design/v65/indices/진행/V.md" ]; } && ok "R3/ⓒ v65 카드 · env 없음 → v65 기본 rc0" || bad "R3 rc=$rc: $out"

reset_cards; mv "$REPO/.fable-team/bin-g/g-env.sh" "$T/g-env.sh.off"
out="$(mv_g "$BIN")"; rc=$?
{ [ "$rc" = 1 ] && echo "$out" | grep -q 'REJECT lint 실패' && echo "$out" | grep -q '^INFO 골 줄 출처 = v65 기본' && [ -f "$REPO/design/teams/g/indices/대기/X.md" ]; } && ok "R4/ⓒ g env 없음 → v65 기본 REJECT rc1 + INFO" || bad "R4 rc=$rc: $out"
mv "$T/g-env.sh.off" "$REPO/.fable-team/bin-g/g-env.sh"

# 변이 1: 팀 env 에서 값을 읽는 줄 삭제 → R1 이 rc1 이어야 한다(= 시험이 그 줄을 지킨다)
MB="$T/binmut"; grep -v '_gl_file="\$( \. "\$_gl_env"' "$SRCDIR/ft-index-move.sh" > "$T/mut.sh"
[ "$(wc -l < "$T/mut.sh")" -lt "$(wc -l < "$SRCDIR/ft-index-move.sh")" ] && ok "변이 줄 실재(삭제됨)" || bad "변이 줄을 못 찾음"
mkbin "$MB" "$T/mut.sh"; reset_cards
out="$(mv_g "$MB")"; rc=$?
[ "$rc" = 1 ] && ok "변이 1 → R1 rc1 = FAIL 로 잡힘" || bad "변이 1 이 안 잡힘 rc=$rc: $out"

echo "RESULT fail=$fail"; [ "$fail" = 0 ]
