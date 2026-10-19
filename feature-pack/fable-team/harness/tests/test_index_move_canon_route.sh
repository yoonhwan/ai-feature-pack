#!/usr/bin/env bash
# test_index_move_canon_route.sh — r487: 완성 이동의 «정본 갱신 요청» 쪽지 수신자 = 카드 팀 명부(seats-<팀>.json · v65 = seats.json)의 `_arch`.
#   ⓐ 팀 a 카드 → seats-a.json `_arch`(A#1) · seats.json(V#1) 0  ⓑ FT_SEATS_JSON 명시가 이김 → V#1
#   ⓒ 팀 b 카드(명부 없음) → 쪽지 0 + INFO «팀 명부 없음(b)» · 이동 rc0  ⓓ v65 카드 → seats.json `_arch`(기존 동작)
# 임시 git 리포·가짜 mbox 기록기만 — 실 mbox·실 명부·실 indices 쓰기 0 · GIT_* env 0. BASH_BIN=/bin/bash 로 3.2 검사.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRCDIR="$HERE/../bin"; BB="${BASH_BIN:-bash}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_SEATS_JSON FT_TEAMS_MD FT_REPO_ROOT FT_TRACK

"$BB" -n "$SRCDIR/ft-index-move.sh" && ok "bash -n ft-index-move.sh" || bad "bash -n ft-index-move.sh"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; T="$(cd "$T" && pwd -P)"   # macOS /var → /private/var — 쪽지의 리포 상대 경로 비교용
BIN="$T/bin"; mkdir -p "$BIN"
cp "$SRCDIR/ft-index-move.sh" "$SRCDIR/ft-index-move-canon.sh" "$SRCDIR/ft-index-move-install.sh" "$SRCDIR/ft_da_hold_gate.py" "$SRCDIR/ft-team-lib.sh" "$BIN/"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/ft-index-lint.sh"
printf '#!/usr/bin/env bash\necho "$*" >> "$MBOX_LOG"\nexit 0\n' > "$T/fake-mbox.sh"; chmod 755 "$T/fake-mbox.sh"
export FT_MBOX="$T/fake-mbox.sh" MBOX_LOG="$T/mbox.log" FT_INDEX_STATE_DIR="$T/state" FT_LAND_REF=main
mkdir -p "$T/state"

REPO="$T/repo"; mkdir -p "$REPO/docs/architect" "$REPO/.fable-team"
for t in a b v65; do mkdir -p "$REPO/design/teams/$t/indices"/{대기,진행,완성}; done
G() { git -C "$REPO" "$@"; }
G init -q -b main . && G config user.email t@t && G config user.name t
X=docs/architect/X.md
printf '## 절A 제목\nv1\n' > "$REPO/$X"
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| a | `design/teams/a/` | a | 현역 |\n| b | `design/teams/b/` | b | 현역 |\n| v65 | `design/teams/v65/` | v | 현역 |\n' > "$REPO/design/TEAMS.md"
printf '.fable-team/\n' > "$REPO/.gitignore"
printf '{"_label":"a","_arch":"A#1"}\n' > "$REPO/.fable-team/seats-a.json"
printf '{"_label":"v65","_arch":"V#1"}\n' > "$REPO/.fable-team/seats.json"
G add -A && G commit -qm base
# 정본 갱신 카드가 통과하려면 랜딩 S 에 X 가 있어야 한다(ft-index-move-canon.sh) — 한 번 랜딩해 두고 모든 카드가 같은 S·C 를 쓴다
G checkout -q -b c1; echo v2 >> "$REPO/$X"; G commit -qam "x v2"; C="$(G rev-parse HEAD)"
G checkout -q main; G merge -q --squash c1 >/dev/null; G commit -qm "squash c1"; S="$(G rev-parse HEAD)"

card() { local f="$REPO/design/teams/$1/indices/진행/$2.md"   # card <팀> <이름>
  { echo "# 인덱스: $2"; echo "## 상태"; echo "- 정본 갱신: $X §절A"
    echo "- 규칙: 없음 — 시험 fixture 카드(규칙 무관)"; echo "- 설치: 없음"; } > "$f"; echo "$f"; }
D="$REPO/design/da.md"; printf '# 판정문\n## §1 닫힘: ka kb kc kd\n정본 diff 확인: %s §절A @%s — v2\n' "$X" "$C" > "$D"
mv_() { "$BB" "$BIN/ft-index-move.sh" "$@" 2>&1; }
moved() { [ -f "$REPO/design/teams/$1/indices/완성/$2.md" ]; }

# ⓐ 팀 a 카드 → A#1 · V#1 0
: > "$MBOX_LOG"; c="$(card a ka)"
out="$(mv_ "$c" 완성 --da "$D#§1" --seat s --landed "$S")"; rc=$?
[ "$rc" = 0 ] && moved a ka && grep -q '^send A#1 s \[정본 갱신 요청\] design/teams/a/indices/완성/ka.md' "$MBOX_LOG" && ! grep -q 'V#1' "$MBOX_LOG" \
  && echo "$out" | grep -qx 'NOTIFIED 정본 갱신 요청 → A#1 (팀 a)' && ok "ⓐ 팀 a 카드 → seats-a.json _arch A#1 · V#1 0" || bad "ⓐ rc=$rc: $out / $(cat "$MBOX_LOG")"

# ⓑ FT_SEATS_JSON 명시 → V#1(명시가 이김)
: > "$MBOX_LOG"; c="$(card a kb)"
out="$(FT_SEATS_JSON="$REPO/.fable-team/seats.json" mv_ "$c" 완성 --da "$D#§1" --seat s --landed "$S")"; rc=$?
[ "$rc" = 0 ] && moved a kb && grep -q '^send V#1 ' "$MBOX_LOG" && ! grep -q 'A#1' "$MBOX_LOG" \
  && echo "$out" | grep -qx 'NOTIFIED 정본 갱신 요청 → V#1 (팀 a · 명부 FT_SEATS_JSON)' && ok "ⓑ FT_SEATS_JSON 명시 → V#1" || bad "ⓑ rc=$rc: $out / $(cat "$MBOX_LOG")"

# ⓒ 팀 b 카드(seats-b.json 없음) → 쪽지 0 + INFO · 이동 rc0
: > "$MBOX_LOG"; c="$(card b kc)"
out="$(mv_ "$c" 완성 --da "$D#§1" --seat s --landed "$S")"; rc=$?
[ "$rc" = 0 ] && moved b kc && [ ! -s "$MBOX_LOG" ] && echo "$out" | grep -qx 'INFO 정본 쪽지 생략 — 팀 명부 없음(b)' && ! echo "$out" | grep -q '^NOTIFIED' \
  && ok "ⓒ 팀 b 명부 없음 → 쪽지 0 · INFO · 이동 rc0" || bad "ⓒ rc=$rc: $out / $(cat "$MBOX_LOG")"

# ⓓ v65 카드 → seats.json _arch V#1(기존 동작)
: > "$MBOX_LOG"; c="$(card v65 kd)"
out="$(mv_ "$c" 완성 --da "$D#§1" --seat s --landed "$S")"; rc=$?
[ "$rc" = 0 ] && moved v65 kd && grep -q '^send V#1 ' "$MBOX_LOG" && ! grep -q 'A#1' "$MBOX_LOG" \
  && echo "$out" | grep -qx 'NOTIFIED 정본 갱신 요청 → V#1 (팀 v65)' && ok "ⓓ v65 카드 → seats.json _arch V#1" || bad "ⓓ rc=$rc: $out / $(cat "$MBOX_LOG")"

echo "fail=$fail"; [ "$fail" = 0 ]
