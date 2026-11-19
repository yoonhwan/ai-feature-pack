#!/usr/bin/env bash
# test_card_commit_ledger_r2283.sh — r2283: ft-card-commit.sh 원장 풀이 = 카드 머리 ledger → 팀 env FT_GOAL_LEDGER → 기본 원장
#   (ft-index-lint default_ledger 와 같은 규칙 · 명단 v65 꼴 후보 중 BASE tree 에 GOAL-LEDGER-v65.md 실재 정확히 1개).
#   반례 ①ⓐⓑ ②ⓐⓑ ③ ④ (카드 동결) · C1 순서 · C2 BASE tree 입력 · C3 판정 불가.
# 격리만: 임시 bare origin + 클론 · lint = 대역(FT_CARD_LINT · 옆에 실 ft-team-lib.sh) · 실 리포 · 실 원격 0 · sleep 0.
# 변이용: R2283_TOOL=<사본 경로> 로 도구를 바꿔 끼운다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$(cd "$HERE/.." && pwd)"
TOOL="${R2283_TOOL:-$REPO/bin/ft-card-commit.sh}"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_NOSYSTEM=1 HOME="$T/home" GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset FT_GOAL_LEDGER FT_TEAMS_REF FT_REPO_ROOT FT_TEAMS_MD
mkdir -p "$HOME"
[ -f "$TOOL" ] || { echo "FAIL 도구 없음 ($TOOL)"; exit 1; }
cp "$REPO/bin/ft-team-lib.sh" "$T/ft-team-lib.sh"   # lint 대역 옆 = 실 명단 풀이(ft-index-lint 와 같은 자리)

LINT="$T/lint.sh"   # ft-index-lint 대역: 원장 = 카드 머리 ledger 또는 FT_GOAL_LEDGER · 루트 = git toplevel · 사유 = «  - » 줄
cat > "$LINT" <<'EOF'
#!/usr/bin/env bash
ROOT="$(git rev-parse --show-toplevel)"; f="$1"; bad=()
led="$(grep -oE '<!-- *ledger: *[^ >]+ *-->' "$f" | sed -E 's/.*ledger: *([^ >]+).*/\1/')"; led="${led:-${FT_GOAL_LEDGER:-}}"
[ -n "$led" ] || bad+=("선언된 정본 없음")
while IFS= read -r g || [ -n "$g" ]; do grep -qxF "$g" "$ROOT/$led" 2>/dev/null || bad+=("골줄 원장에 없음 ($g)"); done < <(sed -n 's/^골줄: //p' "$f")
[ ${#bad[@]} -eq 0 ] && { echo "OK $f"; exit 0; }; echo "REJECT $f"; printf '  - %s\n' "${bad[@]}"; exit 1
EOF
HL='design/harness/GOAL-harness.md' EL='design/harness/GOAL-env.md' NC='design/harness/indices/대기/n'   # 사례마다 새 카드(고치기 전 판 0)
D1='design/teams/v65/GOAL-LEDGER-v65.md' D2='design/v65/GOAL-LEDGER-v65.md'
put() { mkdir -p "$W/$(dirname "$1")"; printf '%s' "$2" > "$W/$1"; }
world() {  # $1 = 기본 원장 BASE tree 판: one(D1 만) · none(없음) · two(D1 · D2 둘 다)
  local d="$T/w.$RANDOM$RANDOM"; W="$d/W" O="$d/O.git" R="$d/R"
  git init -q -b ops/main-base "$W" && git init -q --bare -b main "$O"
  put design/TEAMS.md $'| 팀 | 폴더 |\n|---|---|\n| v65 | `design/v65/` |\n| harness | `design/harness/` |\n'
  put "$HL" $'GL-H\n'; put "$EL" $'GL-E\n'; put design/x.md $'x\n'
  case "$1" in one) put "$D1" $'GL-D\n';; two) put "$D1" $'GL-D\n'; put "$D2" $'GL-D\n';; esac
  git -C "$W" add -A && git -C "$W" commit -qm base && git -C "$W" push -q "$O" ops/main-base ops/main-base:main 2>/dev/null
  git clone -q -b ops/main-base "$O" "$R" 2>/dev/null
}
tip() { git -C "$O" rev-parse refs/heads/ops/main-base; }
run() { OUT="$(cd "$R" && FT_CARD_LINT="$LINT" bash "$TOOL" "$@" 2>&1)"; RC=$?; }
f() { printf '%s' "$2" > "$T/$1"; echo "$T/$1"; }
pushed() { [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -qx "PUSHED $(tip) base=$1"; }
held() { [ "$RC" = "$2" ] && [ "$(tip)" = "$1" ]; }

# ①ⓐ 머리 ledger 0 · 팀 env 0 · 기본 원장 BASE tree 에 1개 · 닫는 증거 맞음 → PUSHED rc0 (기준판 = «판정 불가 lint-원장» rc3)
world one; t0="$(tip)"
run ops/main-base "기본 원장" "${NC}a1.md=$(f a1 $'# 새\n골줄: GL-D\n')"
pushed "$t0" && ok "①ⓐ 기본 원장으로 판정 → PUSHED" || bad "①ⓐ rc=$RC out=$OUT"
# ①ⓑ 같은 꼴 · 닫는 증거가 기본 원장에 없음 → REJECT lint 새 사유 · push 0
t0="$(tip)"
run ops/main-base "기본 원장 없는 증거" "${NC}a2.md=$(f a2 $'# 새\n골줄: GL-X\n')"
{ held "$t0" 1 && printf '%s' "$OUT" | grep -q '^REJECT lint 새 사유' && printf '%s' "$OUT" | grep -qxF '  - 골줄 원장에 없음 (GL-X)'; } \
  && ok "①ⓑ 기본 원장에 없는 증거 → REJECT · push 0" || bad "①ⓑ rc=$RC out=$OUT"

# ②ⓐ 머리 ledger 있음 · 기본 원장도 있음 → 머리 원장으로 판정(기본 원장 안 읽음)
t0="$(tip)"
run ops/main-base "머리 원장" "${NC}b1.md=$(f b1 $'<!-- ledger: design/harness/GOAL-harness.md -->\n# 새\n골줄: GL-H\n')"
pushed "$t0" && ok "②ⓐ 머리 원장 증거 → PUSHED" || bad "②ⓐ rc=$RC out=$OUT"
t0="$(tip)"
run ops/main-base "머리 원장 · 기본 증거" "${NC}b2.md=$(f b2 $'<!-- ledger: design/harness/GOAL-harness.md -->\n# 새\n골줄: GL-D\n')"
held "$t0" 1 && ok "②ⓐ 머리 원장 있으면 기본 원장 증거 → REJECT" || bad "②ⓐ 기본 rc=$RC out=$OUT"
# ②ⓑ 팀 env 만 있음 → env 원장으로 판정(기본 원장 안 읽음)
mkdir -p "$R/.fable-team/bin-harness"; printf 'export FT_GOAL_LEDGER=%s\n' "$EL" > "$R/.fable-team/bin-harness/harness-env.sh"
t0="$(tip)"
run ops/main-base "env 원장" "${NC}c1.md=$(f c1 $'# 새\n골줄: GL-E\n')"
pushed "$t0" && ok "②ⓑ env 원장 증거 → PUSHED" || bad "②ⓑ rc=$RC out=$OUT"
t0="$(tip)"
run ops/main-base "env 원장 · 기본 증거" "${NC}c2.md=$(f c2 $'# 새\n골줄: GL-D\n')"
held "$t0" 1 && ok "②ⓑ env 있으면 기본 원장 증거 → REJECT" || bad "②ⓑ 기본 rc=$RC out=$OUT"

# ③ 기본 원장이 루트 checkout 에만 있고 BASE tree 에 없음 → 판정 불가 lint-원장 rc3 · push 0
world none; t0="$(tip)"
mkdir -p "$R/$(dirname "$D1")"; printf 'GL-D\n' > "$R/$D1"
run ops/main-base "루트 판만" "${NC}d1.md=$(f d1 $'# 새\n골줄: GL-D\n')"
{ held "$t0" 3 && printf '%s' "$OUT" | grep -q '^판정 불가 lint-원장 (.*기본 원장 후보 0'; } && ok "③ 루트 checkout 판만 → 판정 불가 · push 0" || bad "③ rc=$RC out=$OUT"

# ④ 명단 꼴 후보 2개가 BASE tree 에 모두 실재 → 판정 불가 lint-원장 rc3 · push 0
world two; t0="$(tip)"
run ops/main-base "후보 둘" "${NC}e1.md=$(f e1 $'# 새\n골줄: GL-D\n')"
{ held "$t0" 3 && printf '%s' "$OUT" | grep -q '^판정 불가 lint-원장 (.*기본 원장 후보 2'; } && ok "④ 후보 2개 → 판정 불가 · push 0" || bad "④ rc=$RC out=$OUT"

echo "---"; [ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }; echo "FAIL $fail"; exit 1
