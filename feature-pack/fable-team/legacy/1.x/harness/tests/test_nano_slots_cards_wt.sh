#!/usr/bin/env bash
# test_nano_slots_cards_wt.sh — r606: 카드 폴더를 찾는 «체크아웃» = 명부 `_cards_wt` 워크트리
#   ⓐ 메인 체크아웃(옛 폴더만) cwd 에서 닫아도 후보 = `_cards_wt` 워크트리의 명단 폴더 카드(옛 쌍둥이 아님)
#   ⓑ 명부에 `_cards_wt` 없음 → 지금처럼 cwd 기준 · 명단 폴더가 없어 쌍둥이로 내려가면 WARN 1줄(조용한 후퇴 0)
#   ⓒ `_cards_wt` 워크트리 실재 0 → ERROR rc1(cwd 후퇴 0) · ⓓ FT_INDEX_DIR 명시 → 회귀 0
# 임시 리포·임시 명부·가짜 tmux 만 쓴다 — 실제 seats 파일·나노 세션·다른 팀 자료는 건드리지 않는다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$BIN/ft-nano-slots.sh" && ok "bash -n" || bad "bash -n"

mkdir -p "$T/bin"
cp "$BIN/ft-nano-slots.sh" "$BIN/ft-team-lib.sh" "$T/bin/"
cat > "$T/bin/ft-seat-status.sh" <<'EOF'
#!/usr/bin/env bash
echo "IDLE 2020-01-01T00:00:00Z"
EOF
cat > "$T/bin/tmux" <<EOF
#!/usr/bin/env bash
cat "$T/live.txt"
EOF
chmod +x "$T/bin/"*

card() {  # card <파일> — 머리줄 4줄 충족 카드
  { echo "# 인덱스: $1"; echo "Issue: #7"; echo "상태: 대기"; echo "선행: 없음"; echo "시험 입력: 없음"; echo "## 구현 범위"; } > "$1"
}

# 픽스처: 메인 체크아웃 = 명단 + 옛 폴더(design/v65)만 · 링크 워크트리 = 명단 폴더(design/teams/v65) + 옛 폴더 둘 다
R="$T/repo"; mkdir -p "$R/design/v65/indices/대기"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| v65 | `design/teams/v65/` | x | 현역 |\n' > "$R/design/TEAMS.md"
card "$R/design/v65/indices/대기/old-card.md"
gr() { git -C "$R" -c user.name=t -c user.email=t@t "$@"; }
gr init -q && gr add -A && gr commit -qm base && gr update-ref refs/remotes/origin/main HEAD
gr worktree add -q -b cards "$R/.worktrees/cards" >/dev/null 2>&1
mkdir -p "$R/.worktrees/cards/design/teams/v65/indices/대기" "$R/.worktrees/cards/design/v65/indices/대기"
card "$R/.worktrees/cards/design/teams/v65/indices/대기/v65-card.md"
card "$R/.worktrees/cards/design/v65/indices/대기/wt-old-card.md"
# 쌍둥이 전용 워크트리 = 명단 폴더 없음(옛 폴더만)
gr worktree add -q -b cards2 "$R/.worktrees/cards2" >/dev/null 2>&1
mkdir -p "$R/.worktrees/cards2/design/v65/indices/대기"
card "$R/.worktrees/cards2/design/v65/indices/대기/only-old.md"

printf 'w1\n' > "$T/live.txt"
mkdir -p "$T/idx/대기"; card "$T/idx/대기/direct-card.md"

runr() {  # runr <seats json 본문> [env…] — cwd = 메인 체크아웃(낡은 쪽)
  printf '%s\n' "$1" > "$T/seats.json"; shift
  (cd "$R" && unset FT_INDEX_DIR FT_TEAMS_REF FT_TEAMS_MD FT_REPO_ROOT FT_ACTIVE_ISSUES
   PATH="$T/bin:$PATH" FT_SEATS_JSON="$T/seats.json" "$@" bash "$T/bin/ft-nano-slots.sh" 2>"$T/err")
}

# ⓐ 낡은 메인 체크아웃 cwd · 명부 `_cards_wt=cards` → 워크트리 명단 폴더 카드가 후보, 옛 쌍둥이 카드 0 · WARN 0
out="$(runr '{"_cards_wt":"cards","w1":{"role":"nano"}}' env)"; rc=$?
[ "$rc" = 0 ] && echo "$out" | grep -q 'ft-nano-spawn.sh .*v65-card.md' && ok "ⓐ 워크트리 명단 폴더 카드 = 후보 (rc0)" || bad "ⓐ rc=$rc $(echo "$out" | head -2)"
echo "$out" | grep -q 'wt-old-card.md\|old-card.md' && bad "ⓐ 옛 쌍둥이 카드가 후보" || ok "ⓐ 옛 쌍둥이 카드 후보 0"
[ -s "$T/err" ] && bad "ⓐ stderr: $(cat "$T/err")" || ok "ⓐ stderr 0(명단 폴더 채택 · WARN 없음)"

# ⓑ1 명부에 `_cards_wt` 없음 → 지금처럼 cwd(메인 체크아웃) 기준 = 옛 폴더 카드
out="$(runr '{"w1":{"role":"nano"}}' env)"; rc=$?
[ "$rc" = 0 ] && echo "$out" | grep -q 'ft-nano-spawn.sh .*old-card.md' && ok "ⓑ1 _cards_wt 없음 → cwd 기준(옛 폴더) 회귀" || bad "ⓑ1 rc=$rc $(echo "$out" | head -2)"

# ⓑ2 명단 폴더가 없어 쌍둥이로 내려감 → stderr WARN 1줄(두 경로 명시) · 후보 = 쌍둥이 카드
out="$(runr '{"_cards_wt":"cards2","w1":{"role":"nano"}}' env)"; rc=$?
[ "$rc" = 0 ] && echo "$out" | grep -q 'ft-nano-spawn.sh .*only-old.md' && ok "ⓑ2 쌍둥이 폴더 카드 = 후보" || bad "ⓑ2 rc=$rc $(echo "$out" | head -2)"
[ "$(grep -c '^WARN 명단 폴더(' "$T/err")" = 1 ] && grep -q 'design/teams/v65/indices) 없음 — 쌍둥이 .*design/v65 로 셈' "$T/err" && ok "ⓑ2 WARN 1줄(명단 경로·쌍둥이 경로)" || bad "ⓑ2 WARN 줄: $(cat "$T/err")"

# ⓒ `_cards_wt` 워크트리 실재 0 → ERROR rc1 · SLOTS 0(cwd 후퇴 0)
out="$(runr '{"_cards_wt":"nope","w1":{"role":"nano"}}' env)"; rc=$?
[ "$rc" = 1 ] && grep -q '^ERROR 카드 워크트리 없음: nope' "$T/err" && ! echo "$out" | grep -q SLOTS && ok "ⓒ 워크트리 실재 0 → ERROR rc1 · cwd 후퇴 0" || bad "ⓒ rc=$rc out=$(echo "$out" | head -1) err=$(cat "$T/err")"

# ⓓ FT_INDEX_DIR 명시 → 지금과 같다(명부 `_cards_wt` 무시 · 회귀 0)
out="$(runr '{"_cards_wt":"nope","w1":{"role":"nano"}}' env FT_INDEX_DIR="$T/idx")"; rc=$?
[ "$rc" = 0 ] && echo "$out" | grep -q 'ft-nano-spawn.sh .*direct-card.md' && [ ! -s "$T/err" ] && ok "ⓓ FT_INDEX_DIR 명시 → 그 폴더 · rc0" || bad "ⓓ rc=$rc err=$(cat "$T/err")"

echo; [ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAIL $fail"
exit "$fail"
