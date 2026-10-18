#!/usr/bin/env bash
# test_team_map_lint.sh — ft-team-map-lint.sh: README 파일 지도 ↔ 실제 바닥 파일 대조(R318a). 임시 폴더 픽스처만.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRCDIR="$HERE/../../scripts/fable-team-bin"
KIT="$HERE/../../scripts/harness-install/fable-team"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

for f in "$SRCDIR/ft-team-map-lint.sh" "$KIT/bin/ft-team-map-lint.sh"; do bash -n "$f" && ok "bash -n ${f##*/}" || bad "bash -n $f"; done
cmp -s "$SRCDIR/ft-team-map-lint.sh" "$KIT/bin/ft-team-map-lint.sh" && ok "키트 사본 cmp0" || bad "키트 사본 cmp"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
REPO="$T/repo"; mkdir -p "$REPO/design"; git -C "$REPO" init -q -b main .
LINT() { (cd "$REPO" && bash "$SRCDIR/ft-team-map-lint.sh" "$@" 2>&1); }
mkteam() { rm -rf "$REPO/design/$1"; mkdir -p "$REPO/design/$1"; }
# R382: 팀 폴더는 TEAMS.md 칸에서 푼다 — 시험 팀을 명단에 올린다
{ echo '| 팀 | 폴더 | 좌석 | 상태 |'; echo '|---|---|---|---|'; for t in h r s demo nothere; do echo "| $t | \`design/$t/\` | $t-master | 현역 |"; done; } > "$REPO/design/TEAMS.md"

# 1 harness 꼴 — 현역 원장 3종이 지도에 등록 → WARN 0 · rc0 (DA r1 ③ 표본)
mkteam h; D="$REPO/design/h"; mkdir -p "$D/indices/대기" "$D/indices/진행"
touch "$D/GOAL-h.md" "$D/REQUEST-LEDGER.md" "$D/LANDING-LEDGER.md" "$D/MACHINES.md" "$D/DA-1.md" "$D/DA-2.md"
cat > "$D/README.md" <<'E'
# h 트랙
## 파일 지도
| 파일 | 역할 | 갱신 |
|---|---|---|
| `GOAL-h.md` | 골 | 승인 때만 |
| `REQUEST-LEDGER.md` · `LANDING-LEDGER.md` · `MACHINES.md` | 현역 원장 | 행 추가만 |
| `indices/{대기,진행}/` | 카드 | 매 단위 |
| `DA-*.md` | 판정 원문 | 추가만 |
| `RELEASE-<ver>.md` | 발행 1장/버전 | 버전마다 |
E
out="$(LINT h)"; rc=$?
[ "$rc" = 0 ] && ! echo "$out" | grep -q '^WARN' && ! echo "$out" | grep -q '^ERR' && ok "1 현역 원장·glob·<ver> 등록 → WARN 0 ERR 0" || bad "1: rc=$rc $out"

# 2 지도에 없는 바닥 파일 = WARN(정리 후보) · rc0
touch "$D/stray-note.md"
out="$(LINT h)"; rc=$?
[ "$rc" = 0 ] && echo "$out" | grep -q '^WARN.*stray-note.md' && [ "$(echo "$out" | grep -c '^WARN')" = 1 ] && ok "2 지도 밖 바닥 파일 WARN 1 rc0" || bad "2: rc=$rc $out"

# 3 지도에 있는데 실제로 없음 = ERR · rc1
printf '| `GHOST.md` | 없는 파일 | - |\n' >> "$D/README.md"
out="$(LINT h)"; rc=$?
[ "$rc" = 1 ] && echo "$out" | grep -q '^ERR.*GHOST.md' && ok "3 지도 경로 부재 ERR rc1" || bad "3: rc=$rc $out"

# 4 ERR + WARN 동시 → rc1
echo "$out" | grep -q '^WARN.*stray-note.md' && ok "4 ERR 와 WARN 같이 보고" || bad "4: $out"

# 5 README 없음 → ERR rc1
mkteam r; touch "$REPO/design/r/x.md"
out="$(LINT r)"; rc=$?
[ "$rc" = 1 ] && echo "$out" | grep -q '^ERR.*README' && ok "5 README 없음 ERR rc1" || bad "5: rc=$rc $out"

# 6 팀 폴더 없음 → rc1 · 인자 없음 → rc2
out="$(LINT nothere)"; rc=$?; [ "$rc" = 1 ] && ok "6a 팀 폴더 없음 rc1" || bad "6a: rc=$rc $out"
out="$(LINT)"; rc=$?; [ "$rc" = 2 ] && ok "6b usage rc2" || bad "6b: rc=$rc $out"

# 7 하위 폴더의 파일은 바닥이 아니다(WARN 대상 아님) · 바닥 폴더는 대상 아님
mkteam s; D="$REPO/design/s"; mkdir -p "$D/plans/deep"; touch "$D/plans/P-1.md" "$D/plans/deep/Q.md"
printf '# s\n## 파일 지도\n| 파일 | 역할 |\n|---|---|\n| `plans/` | 설계 |\n' > "$D/README.md"
out="$(LINT s)"; rc=$?
[ "$rc" = 0 ] && ! echo "$out" | grep -q '^WARN' && ok "7 하위 폴더 파일 WARN 0" || bad "7: rc=$rc $out"

# 8 스캐폴드 산출물 그대로 → WARN 0 ERR 0 (scaffold ↔ lint 계약)
mkdir -p "$T/g"; cat > "$REPO/design/TEAMS.md" <<'E'
| 팀 | 폴더 | 오케 좌석 | 상태 |
|---|---|---|---|
| demo | `design/demo/` | demo-master 계열 | 현역 |
E
(cd "$REPO" && FT_TEAM_TEMPLATE_DIR="$KIT/templates/team" bash "$SRCDIR/ft-team-scaffold.sh" demo >/dev/null 2>&1)
out="$(LINT demo)"; rc=$?
[ "$rc" = 0 ] && ! echo "$out" | grep -qE '^(WARN|ERR)' && ok "8 스캐폴드 산출물 lint 깨끗" || bad "8: rc=$rc $out"

echo "fail=$fail"; [ "$fail" = 0 ]
