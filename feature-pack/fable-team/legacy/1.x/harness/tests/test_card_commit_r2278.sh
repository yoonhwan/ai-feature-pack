#!/usr/bin/env bash
# test_card_commit_r2278.sh — r2278: 카드 고침 공용 도구 ft-card-commit.sh(worktree · checkout 0 · 임시 index 커밋 · push).
#   반례 ① ② ③ⓐⓑⓒ ④ⓐⓑⓒⓓⓔ ⑦ (카드 동결 · 사전 DA H1 · H3 보정 · 구현 메모 ⓐ) · C1 공용 도구 · C2 쓰기 전 검사 · C4 출력 · 실패.
# 격리만: 임시 bare origin + 클론 · lint = 대역(FT_CARD_LINT) · 실 리포 · 실 원격 0 · sleep 0.
# 변이용: R2278_TOOL=<사본 경로> 로 도구를 바꿔 끼운다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$(cd "$HERE/.." && pwd)"
TOOL="${R2278_TOOL:-$REPO/bin/ft-card-commit.sh}"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_NOSYSTEM=1 HOME="$T/home" GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$HOME"
[ -f "$TOOL" ] || { echo "FAIL 도구 없음 ($TOOL)"; exit 1; }
cmp -s "$REPO/bin/ft-card-commit.sh" "$REPO/kit/fable-team/bin/ft-card-commit.sh" && ok "bin · kit 같은 바이트" || bad "bin · kit 다름"
bash -n "$TOOL" && ok "bash -n" || bad "bash -n"

LINT="$T/lint.sh"   # ft-index-lint 대역: 원장 = 카드 머리 ledger 또는 FT_GOAL_LEDGER · 루트 = git toplevel · 사유 = «  - » 줄
cat > "$LINT" <<'EOF'
#!/usr/bin/env bash
ROOT="$(git rev-parse --show-toplevel)"; f="$1"; bad=()
led="$(grep -oE '<!-- *ledger: *[^ >]+ *-->' "$f" | sed -E 's/.*ledger: *([^ >]+).*/\1/')"; led="${led:-${FT_GOAL_LEDGER:-}}"
grep -q LINTUNK "$f" && exit 3
while IFS= read -r g; do grep -qxF "$g" "$ROOT/$led" 2>/dev/null || bad+=("골줄 원장에 없음 ($g)"); done < <(sed -n 's/^골줄: //p' "$f")
grep -q LINTBAD "$f" && bad+=("금지어 LINTBAD")
grep -q LINTOLD "$f" && bad+=("옛 사유 LINTOLD")
[ ${#bad[@]} -eq 0 ] && { echo "OK $f"; exit 0; }; echo "REJECT $f"; printf '  - %s\n' "${bad[@]}"; exit 1
EOF
CA='design/harness/indices/대기/a.md' CB='design/harness/indices/대기/b.md' LED='design/harness/GOAL-harness.md'
card() { printf '<!-- ledger: %s -->\n# 카드\n골줄: %s\n%s\n' "$LED" "$1" "$2"; }
put() { mkdir -p "$W/$(dirname "$1")"; printf '%s' "$2" > "$W/$1"; }
world() {   # W(작업) → O(bare) → R(클론 = 원 리포 · ops/main-base checkout)
  local d="$T/w.$RANDOM$RANDOM"; W="$d/W" O="$d/O.git" R="$d/R"
  git init -q -b ops/main-base "$W" && git init -q --bare -b main "$O"
  put "$LED" $'GL-A\n'; put "$CA" "$(card GL-A '본문 1')"; put "$CB" "$(card GL-A 'LINTOLD 본문')"
  put design/x.md $'x1\n'; put design/old.md $'old\n'; put design/TEAMS.md $'| 팀 |\n'; put gateway/y.py $'y=1\n'
  git -C "$W" add -A && git -C "$W" commit -qm base && git -C "$W" push -q "$O" ops/main-base ops/main-base:main 2>/dev/null
  git clone -q -b ops/main-base "$O" "$R" 2>/dev/null
}
tip() { git -C "$O" rev-parse refs/heads/ops/main-base; }
run() { OUT="$(cd "$R" && FT_CARD_LINT="$LINT" bash "$TOOL" "$@" 2>&1)"; RC=$?; }
f() { printf '%s' "$2" > "$T/$1"; echo "$T/$1"; }

# ① 카드 1장 바꿈 → 끝에 커밋 1 · 부모 = 이전 끝 · 원 리포 worktree 수 · status 같음
world; t0="$(tip)"; wl0="$(git -C "$R" worktree list | wc -l)"; st0="$(git -C "$R" status --porcelain)"
run ops/main-base "카드 고침" "$CA=$(f a1 "$(card GL-A '본문 2')")"
t1="$(tip)"
{ [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -qx "PUSHED $t1 base=$t0" && [ "$(git -C "$O" rev-parse "$t1^")" = "$t0" ] \
  && git -C "$O" show "$t1:$CA" | grep -qx '본문 2' && [ "$(git -C "$R" worktree list | wc -l)" = "$wl0" ] \
  && [ "$(git -C "$R" status --porcelain)" = "$st0" ]; } && ok "① 커밋 1 · 부모 = 이전 끝 · worktree 수 · status 같음" || bad "① rc=$RC out=$OUT st=$(git -C "$R" status --porcelain | head -3)"

# ② +덧붙이기 · -지우기 · 새 파일 → 커밋 diff = 그 셋만
world; t0="$(tip)"
run ops/main-base "섞음" "+design/x.md=$(f ap $'x2\n')" "-design/old.md" "design/new.md=$(f nw $'new\n')"
t1="$(tip)"; ns="$(git -C "$O" diff --name-status "$t0" "$t1" | sort | tr '\t\n' ' ')"
{ [ "$RC" = 0 ] && [ "$ns" = "A design/new.md D design/old.md M design/x.md " ] \
  && [ "$(git -C "$O" show "$t1:design/x.md")" = $'x1\nx2' ]; } && ok "② 덧붙이기 · 지우기 · 새 파일 = 그 셋만" || bad "② rc=$RC ns=$ns out=$OUT"

# ③ⓐ push 거절(원격이 앞섬) → fetch 뒤 새 끝 위 1회 다시 · 성공
world; t0="$(tip)"; put design/ahead.md $'ahead\n'; git -C "$W" add -A && git -C "$W" commit -qm ahead && git -C "$W" push -q "$O" ops/main-base:refs/heads/tmp-ahead 2>/dev/null
AH="$(git -C "$W" rev-parse HEAD)"
printf '#!/bin/bash\n[ -f "$GIT_DIR/once" ] && exit 0\ntouch "$GIT_DIR/once"; env -u GIT_QUARANTINE_PATH git update-ref refs/heads/ops/main-base %s\nexit 1\n' "$AH" > "$O/hooks/pre-receive"; chmod +x "$O/hooks/pre-receive"
run ops/main-base "앞섬" "$CA=$(f a3 "$(card GL-A '본문 3')")"
t1="$(tip)"
{ [ "$RC" = 0 ] && [ "$(git -C "$O" rev-parse "$t1^")" = "$AH" ] && printf '%s' "$OUT" | grep -qx "PUSHED $t1 base=$AH" \
  && git -C "$O" cat-file -e "$t1:design/ahead.md" && git -C "$O" show "$t1:$CA" | grep -qx '본문 3'; } && ok "③ⓐ 거절 → 새 끝 위 1회 다시 · 성공" || bad "③ⓐ rc=$RC out=$OUT"
# ③ 두 번째도 거절 → rc≠0 · 원격 글자 0
printf '#!/bin/bash\nexit 1\n' > "$O/hooks/pre-receive"; t0="$(tip)"
run ops/main-base "거절" "$CA=$(f a4 "$(card GL-A '본문 4')")"
{ [ "$RC" != 0 ] && [ "$(tip)" = "$t0" ] && printf '%s' "$OUT" | grep -q '^판정 불가 push'; } && ok "③ 두 번 거절 → rc≠0 · 원격 그대로" || bad "③ 두 번 rc=$RC out=$OUT"
rm -f "$O/hooks/pre-receive"
# ③ⓑ 경로 gateway/x.py → REJECT · push 0 · ③ⓒ 가지 main → REJECT · push 0
t0="$(tip)"; m0="$(git -C "$O" rev-parse main)"
run ops/main-base "밖" "gateway/x.py=$(f gx 'x=1')"
{ [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q '^REJECT 경로 design' && [ "$(tip)" = "$t0" ]; } && ok "③ⓑ design/** 밖 → REJECT · push 0" || bad "③ⓑ rc=$RC out=$OUT"
run ops/main-base "밖2" "design/../gateway/x.py=$(f gx 'x=1')"
{ [ "$RC" = 1 ] && [ "$(tip)" = "$t0" ]; } && ok "③ⓑ design/../ → REJECT" || bad "③ⓑ2 rc=$RC out=$OUT"
run main "main" "$CA=$(f a5 "$(card GL-A '본문 5')")"
{ [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q '^REJECT 가지 허용 목록 밖' && [ "$(git -C "$O" rev-parse main)" = "$m0" ]; } && ok "③ⓒ 가지 main → REJECT · push 0" || bad "③ⓒ rc=$RC out=$OUT"

# ④ⓐ lint 새 사유 1 → push 0 · rc≠0 · 사유 1줄
world; t0="$(tip)"
run ops/main-base "새 사유" "$CA=$(f l1 "$(card GL-A 'LINTBAD 본문')")"
{ [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q '^REJECT lint 새 사유' && [ "$(printf '%s\n' "$OUT" | grep -c '^  - ')" = 1 ] \
  && printf '%s' "$OUT" | grep -qx '  - 금지어 LINTBAD' && [ "$(tip)" = "$t0" ]; } && ok "④ⓐ lint 새 사유 → push 0 · 사유 1줄" || bad "④ⓐ rc=$RC out=$OUT"
# ④ⓑ UTF-8 아닌 .md → push 0
printf '\xff\xfe bad\n' > "$T/nu.md"
run ops/main-base "utf8" "design/nu.md=$T/nu.md"
{ [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q '^REJECT UTF-8 아님' && [ "$(tip)" = "$t0" ]; } && ok "④ⓑ UTF-8 아님 → push 0" || bad "④ⓑ rc=$RC out=$OUT"
# ④ⓒ 루트 checkout 원장 ≠ 가지 원장(가지에만 GL-B) → 가지 판으로 판정 · 고치기 전 판에 있던 사유 = 새 사유 아님
put "$LED" $'GL-A\nGL-B\n'; git -C "$W" add -A && git -C "$W" commit -qm gl-b && git -C "$W" push -q "$O" ops/main-base 2>/dev/null
run ops/main-base "가지 원장" "$CA=$(f l2 "$(card GL-B '본문 6')")"
{ [ "$RC" = 0 ] && ! grep -q GL-B "$R/$LED" && git -C "$O" show "$(tip):$CA" | grep -qx '골줄: GL-B'; } && ok "④ⓒ 가지 원장으로 판정(루트 판 아님)" || bad "④ⓒ rc=$RC out=$OUT"
run ops/main-base "옛 사유" "$CB=$(f l3 "$(card GL-A 'LINTOLD 본문 고침')")"
[ "$RC" = 0 ] && ok "④ⓒ 고치기 전에 있던 사유 → push" || bad "④ⓒ 옛 사유 rc=$RC out=$OUT"
# ④ⓓ lint 판정 불가(rc3) → rc≠0 · push 0 (rc 를 파이프 뒤로 넘기면 거짓 통과)
t0="$(tip)"
run ops/main-base "unk" "$CA=$(f l4 "$(card GL-A 'LINTUNK')")"
{ [ "$RC" = 3 ] && printf '%s' "$OUT" | grep -q '^판정 불가 lint rc=3' && [ "$(tip)" = "$t0" ]; } && ok "④ⓓ lint rc3 → 판정 불가 · push 0" || bad "④ⓓ rc=$RC out=$OUT"
# ④ⓔ 카드 머리 ledger 없음 · 팀 env 없음 → 판정 불가(거짓 통과 0) · 팀 env FT_GOAL_LEDGER 있으면 그 원장
NC='design/harness/indices/대기/n.md'
run ops/main-base "원장 없음" "$NC=$(f n1 $'# 새\n골줄: GL-A\n')"
{ [ "$RC" = 3 ] && printf '%s' "$OUT" | grep -q '^판정 불가 lint-원장' && [ "$(tip)" = "$t0" ]; } && ok "④ⓔ 원장 못 정함 → 판정 불가" || bad "④ⓔ rc=$RC out=$OUT"
mkdir -p "$R/.fable-team/bin-harness"; printf 'export FT_GOAL_LEDGER=%s\n' "$LED" > "$R/.fable-team/bin-harness/harness-env.sh"
run ops/main-base "팀 env 원장" "$NC=$(f n2 $'# 새\n골줄: GL-B\n')"
[ "$RC" = 0 ] && ok "④ⓔ 팀 env FT_GOAL_LEDGER → 가지 원장으로 판정" || bad "④ⓔ env rc=$RC out=$OUT"

# ⑦ git 없음 · fetch 실패 → «판정 불가 <단계>» rc≠0 · push 0
world; t0="$(tip)"
OUT="$(cd "$R" && PATH=/nonexistent /bin/bash "$TOOL" ops/main-base m "$CA=$(f g1 x)" 2>&1)"; RC=$?
{ [ "$RC" = 3 ] && [ "$OUT" = "판정 불가 git" ]; } && ok "⑦ git 없음 → 판정 불가 git" || bad "⑦ git rc=$RC out=$OUT"
git -C "$R" remote set-url origin "$T/none.git"
run ops/main-base m "$CA=$(f g2 "$(card GL-A '본문 7')")"
{ [ "$RC" = 3 ] && [ "$OUT" = "판정 불가 fetch" ] && [ "$(tip)" = "$t0" ]; } && ok "⑦ fetch 실패 → 판정 불가 fetch · push 0" || bad "⑦ fetch rc=$RC out=$OUT"

echo "---"; [ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }; echo "FAIL $fail"; exit 1
