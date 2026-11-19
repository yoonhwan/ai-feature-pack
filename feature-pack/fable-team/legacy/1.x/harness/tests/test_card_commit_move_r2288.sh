#!/usr/bin/env bash
# test_card_commit_move_r2288.sh — r2288: ft-card-commit.sh 카드 폴더 이동 = «고치기 전 판» 을 옛 판으로 lint(새 경로 BASE 에 없을 때).
#   반례 ①~⑤ · 변이 M1(짝 찾기 끔) · M2(r0 = r1) (카드 동결) · C1 이동 짝 · C2 main 전용 옛 판 · C3 짝 꼴 이상 · C4 불변.
# 격리만: 임시 bare origin(ops/main-base · main 따로) + 클론 · lint = 대역(FT_CARD_LINT) · 실 리포 · 실 원격 0 · sleep 0.
# 변이용: R2288_TOOL=<사본 경로> 로 도구를 바꿔 끼운다(M1 · M2 는 이 시험이 사본을 만들어 돌린다).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$(cd "$HERE/.." && pwd)"
TOOL="${R2288_TOOL:-$REPO/bin/ft-card-commit.sh}"; T0="$TOOL"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_NOSYSTEM=1 HOME="$T/home" GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset FT_GOAL_LEDGER
mkdir -p "$HOME"
[ -f "$TOOL" ] || { echo "FAIL 도구 없음 ($TOOL)"; exit 1; }

LINT="$T/lint.sh"   # ft-index-lint 대역: 원장 = 카드 머리 ledger · 사유 = «  - » 줄(경로 글자 0)
cat > "$LINT" <<'EOF'
#!/usr/bin/env bash
ROOT="$(git rev-parse --show-toplevel)"; f="$1"; bad=()
led="$(grep -oE '<!-- *ledger: *[^ >]+ *-->' "$f" | sed -E 's/.*ledger: *([^ >]+).*/\1/')"
while IFS= read -r g; do grep -qxF "$g" "$ROOT/$led" 2>/dev/null || bad+=("골줄 원장에 없음 ($g)"); done < <(sed -n 's/^골줄: //p' "$f")
grep -q '^- 완료: ' "$f" || bad+=("완료 조건 절 비어 있음")
[ ${#bad[@]} -eq 0 ] && { echo "OK $f"; exit 0; }; echo "REJECT $f"; printf '  - %s\n' "${bad[@]}"; exit 1
EOF
LED='design/harness/GOAL-harness.md' I='design/harness/indices'
card() { printf '<!-- ledger: %s -->\n# 카드\n%s## 완료 조건\n%s## 상태\n- %s\n' "$LED" "$1" "$2" "$3"; }
OLDX="$(card '골줄: GL-OLD1\n' '- 완료: x\n' '대기')"
OLDZ="$(card '골줄: GL-OLD1\n골줄: GL-OLD2\n' '- 완료: z\n' '진행')"
put() { mkdir -p "$1/$(dirname "$2")"; printf "$3" > "$1/$2"; }
world() {   # W(ops/main-base) · M(main · 따로 뿌리) → O(bare) → R(클론 = 원 리포)
  local d="$T/w.$RANDOM$RANDOM" M; W="$d/W" M="$d/M" O="$d/O.git" R="$d/R"
  git init -q -b ops/main-base "$W" && git init -q -b main "$M" && git init -q --bare -b main "$O"
  put "$W" "$LED" 'GL-A\n'; put "$W" "$I/대기/X.md" "$OLDX"; put "$W" design/teamb/indices/대기/X2.md "$OLDX"
  put "$W" "$I/대기/X3.md" "$OLDX"; put "$W" "$I/완성/X3.md" "$OLDX"
  put "$M" "$LED" 'GL-A\n'; put "$M" "$I/진행/Z.md" "$OLDZ"; put "$M" "$I/진행/Q.md" "$OLDZ"; put "$M" "$I/대기/Q.md" "$OLDZ"
  git -C "$W" add -A && git -C "$W" commit -qm base && git -C "$W" push -q "$O" ops/main-base 2>/dev/null
  git -C "$M" add -A && git -C "$M" commit -qm main && git -C "$M" push -q "$O" main 2>/dev/null
  git clone -q -b ops/main-base "$O" "$R" 2>/dev/null
}
tip() { git -C "$O" rev-parse refs/heads/ops/main-base; }
run() { OUT="$(cd "$R" && FT_CARD_LINT="$LINT" bash "$TOOL" ops/main-base "r2288 시험" "$@" 2>&1)"; RC=$?; }
f() { printf "$2" > "$T/$1"; echo "$T/$1"; }
pushed() { [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -qx "PUSHED $(tip) base=$1"; }
held() { [ "$RC" = "$2" ] && [ "$(tip)" = "$1" ]; }
newr() { printf '%s\n' "$OUT" | grep -c '^  - '; }
case1() {   # ① -대기/X.md · +완성/X.md=<상태 줄만 바꿈> → PUSHED · diff = D 옛 · A 새
  world; t0="$(tip)"
  run "-$I/대기/X.md" "+$I/완성/X.md=$(f x1 "$(card '골줄: GL-OLD1\n' '- 완료: x\n' '완성')")"
  pushed "$t0" && [ "$(git -C "$O" -c core.quotepath=off diff --no-renames --name-status "$t0" "$(tip)" | tr '\t' ' ')" = "D $I/대기/X.md
A $I/완성/X.md" ]; }
case2() {   # ② 같은 짝 · 완료 조건 절을 비움 → REJECT 새 사유 그 1줄만 · push 0
  world; t0="$(tip)"
  run "-$I/대기/X.md" "+$I/완성/X.md=$(f x2 "$(card '골줄: GL-OLD1\n' '' '완성')")"
  held "$t0" 1 && printf '%s' "$OUT" | grep -qxF "REJECT lint 새 사유 ($I/완성/X.md)" && [ "$(newr)" = 1 ] \
    && printf '%s' "$OUT" | grep -qxF '  - 완료 조건 절 비어 있음'; }

case1 && ok "① 이동 짝 · 옛 사유만 → PUSHED · D 옛 · A 새" || bad "① rc=$RC out=$OUT"
case2 && ok "② 이동 짝 · 내 글자 사유 → REJECT 1줄 · push 0" || bad "② rc=$RC out=$OUT"

# ③ main 전용: BASE 에 없음 · origin/main 진행/Z.md(옛 사유 2) · +완성/Z.md=<옛 판 + 상태 줄> → PUSHED
world; t0="$(tip)"
run "+$I/완성/Z.md=$(f z1 "$(card '골줄: GL-OLD1\n골줄: GL-OLD2\n' '- 완료: z\n' '완성')")"
pushed "$t0" && ok "③ main 전용 옛 판 → PUSHED" || bad "③ rc=$RC out=$OUT"

# ④ⓐ main 후보 2개(진행/Q.md · 대기/Q.md) → 짝 없음 · 옛 사유 그대로 새 사유 → REJECT · push 0
t0="$(tip)"
run "+$I/완성/Q.md=$(f q1 "$(card '골줄: GL-OLD1\n골줄: GL-OLD2\n' '- 완료: z\n' '완성')")"
{ held "$t0" 1 && [ "$(newr)" = 2 ]; } && ok "④ⓐ main 후보 2개 → REJECT · push 0" || bad "④ⓐ rc=$RC out=$OUT"
# ④ⓑ 다른 팀 짝(-teamb/대기/X2.md · +harness/완성/X2.md) → 짝 아님 → REJECT · push 0
t0="$(tip)"
run "-design/teamb/indices/대기/X2.md" "+$I/완성/X2.md=$(f x3 "$(card '골줄: GL-OLD1\n' '- 완료: x\n' '완성')")"
{ held "$t0" 1 && printf '%s' "$OUT" | grep -qxF '  - 골줄 원장에 없음 (GL-OLD1)'; } && ok "④ⓑ 다른 팀 짝 → REJECT · push 0" || bad "④ⓑ rc=$RC out=$OUT"
# ④ⓒ 같은 이름 -짝 2개 → 짝 없음 → REJECT · push 0
t0="$(tip)"
run "-$I/대기/X3.md" "-$I/완성/X3.md" "+$I/진행/X3.md=$(f x4 "$(card '골줄: GL-OLD1\n' '- 완료: x\n' '진행')")"
held "$t0" 1 && ok "④ⓒ -짝 2개 → REJECT · push 0" || bad "④ⓒ rc=$RC out=$OUT"

# ⑤ 짝 없음 · 새 카드 +완성/Y.md(옛 판 어디에도 없음 · 사유 1) → REJECT · push 0
t0="$(tip)"
run "+$I/완성/Y.md=$(f y1 "$(card '골줄: GL-NEW\n' '- 완료: y\n' '완성')")"
{ held "$t0" 1 && [ "$(newr)" = 1 ]; } && ok "⑤ 새 카드 사유 → REJECT · push 0" || bad "⑤ rc=$RC out=$OUT"

# 변이(사본만 · 원본 줄은 위 ① ② 가 같은 사례 1회): M1 짝 찾기 끔 → ① FAIL · M2 r0 = r1 → ② FAIL
mut() {   # $1=이름 $2=sed 식 → 사본 TOOL · 글자 바뀜 확인
  sed "$2" "$T0" > "$T/$1.sh"; TOOL="$T/$1.sh"; ! cmp -s "$T0" "$TOOL"; }
if mut m1 's/^  for s in "\${SPECS\[@\]}"; do p=.*$/  :/'; then { ! case1 && held "$t0" 1; } && ok "M1 짝 찾기 끔 → ① FAIL(REJECT)" || bad "M1 rc=$RC out=$OUT"; else bad "M1 변이 자리 없음"; fi
if mut m2 's/git cat-file blob "\$BR" > "\$T\/before"/cp "$2" "$T\/before"/'; then { ! case2 && pushed "$t0"; } && ok "M2 r0 = r1 → ② FAIL(PUSHED)" || bad "M2 rc=$RC out=$OUT"; else bad "M2 변이 자리 없음"; fi
TOOL="$T0"

echo "---"; [ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }; echo "FAIL $fail"; exit 1
