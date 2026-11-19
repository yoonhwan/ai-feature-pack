#!/usr/bin/env bash
# test_card_wt_r2278.sh — r2278: 좌석 베이스당 카드 폴더만 펼친 sparse worktree 1개 재사용(ft-card-wt.sh).
#   반례 ⑤ ⑥ (카드 동결 · 사전 DA H2 보정 = non-cone 패턴 고정) · C3 sparse 재사용 · C4 실패 꼴.
# 격리만: 임시 bare origin + 클론 · FT_CARDWT_DIR = 임시 폴더 · 실 리포 · /private/tmp/ft-cardwt 0 · sleep 0.
# 변이용: R2278_WT=<사본 경로> 로 도구를 바꿔 끼운다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$(cd "$HERE/.." && pwd)"
TOOL="${R2278_WT:-$REPO/bin/ft-card-wt.sh}"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_NOSYSTEM=1 HOME="$T/home" GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t FT_CARDWT_DIR="$T/cardwt"
mkdir -p "$HOME"
[ -f "$TOOL" ] || { echo "FAIL 도구 없음 ($TOOL)"; exit 1; }
cmp -s "$REPO/bin/ft-card-wt.sh" "$REPO/kit/fable-team/bin/ft-card-wt.sh" && ok "bin · kit 같은 바이트" || bad "bin · kit 다름"
bash -n "$TOOL" && ok "bash -n" || bad "bash -n"

W="$T/W" O="$T/O.git" R="$T/R"
put() { mkdir -p "$W/$(dirname "$1")"; printf '%s\n' "$2" > "$W/$1"; }
git init -q -b ops/main-base "$W" && git init -q --bare -b main "$O"
IN=(design/harness/indices/대기/a.md design/harness/GOAL-harness.md design/TEAMS.md design/teams/ccu/indices/진행/c.md design/teams/ccu/GOAL-ccu.md)
OUTSIDE=(design/harness/DA-x.md design/teams/ccu/DA-y.md design/top.md gateway/z.py)
for p in "${IN[@]}" "${OUTSIDE[@]}"; do put "$p" "$p"; done
git -C "$W" add -A && git -C "$W" commit -qm base && git -C "$W" push -q "$O" ops/main-base ops/main-base:main 2>/dev/null
git clone -q -b main "$O" "$R" 2>/dev/null
run() { OUT="$(cd "$R" && bash "$TOOL" "$@" 2>&1)"; RC=$?; }
D="$T/cardwt/byz-harness-arch-pi"
files() { (cd "$D" && find . -type f -not -name .git | sed 's|^\./||' | sort); }

# ⑤ 처음 → sparse worktree 1개 · 펼친 파일 = 패턴 안만 · 분리 HEAD
wl0="$(git -C "$R" worktree list | wc -l | tr -d " ")"; h0="$(git -C "$O" rev-parse ops/main-base)"
run 'byz-harness-arch-pi#471'
want="$(printf '%s\n' "${IN[@]}" | sort)"
{ [ "$RC" = 0 ] && [ "$OUT" = "WT $D head=$h0" ] && [ "$(files)" = "$want" ] && [ "$(git -C "$R" worktree list | wc -l | tr -d " ")" = $((wl0+1)) ] \
  && ! git -C "$D" symbolic-ref -q HEAD >/dev/null; } && ok "⑤ 처음 → sparse 1개 · 패턴 안만 · 분리 HEAD" || bad "⑤ rc=$RC out=$OUT files=$(files | tr '\n' ' ')"
# ⑤ 두 번째(원격이 앞섬) → 같은 경로 재사용 · worktree 수 그대로 · 새 끝
put design/harness/indices/대기/b.md b; put design/harness/DA-z.md z
git -C "$W" add -A && git -C "$W" commit -qm next && git -C "$W" push -q "$O" ops/main-base 2>/dev/null; h1="$(git -C "$O" rev-parse ops/main-base)"
run 'byz-harness-arch-pi#472'
{ [ "$RC" = 0 ] && [ "$OUT" = "WT $D head=$h1" ] && [ "$(git -C "$R" worktree list | wc -l | tr -d " ")" = $((wl0+1)) ] \
  && [ -f "$D/design/harness/indices/대기/b.md" ] && [ ! -e "$D/design/harness/DA-z.md" ]; } && ok "⑤ 두 번째 → 같은 경로 재사용 · 수 그대로" || bad "⑤ 재사용 rc=$RC out=$OUT"

# ⑥ 재사용 폴더에 수정 파일 → REJECT · 글자 0
printf 'mine\n' > "$D/design/harness/indices/대기/a.md"
put design/harness/indices/대기/a.md theirs; git -C "$W" add -A && git -C "$W" commit -qm theirs && git -C "$W" push -q "$O" ops/main-base 2>/dev/null
run 'byz-harness-arch-pi#473'
{ [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q '^REJECT 수정 파일 있음' && [ "$(cat "$D/design/harness/indices/대기/a.md")" = mine ] \
  && [ "$(git -C "$D" rev-parse HEAD)" = "$h1" ]; } && ok "⑥ 수정 파일 → REJECT · 덮어쓰기 0" || bad "⑥ rc=$RC out=$OUT"

# 실패 꼴: 좌석 이름에 / → REJECT · fetch 실패 → 판정 불가 fetch
run '../evil'
[ "$RC" = 1 ] && ok "좌석 이름 꼴 → REJECT" || bad "이름 rc=$RC out=$OUT"
git -C "$R" remote set-url origin "$T/none.git"; run 'byz-ccu-arch-pi#1'
{ [ "$RC" = 3 ] && [ "$OUT" = "판정 불가 fetch" ] && [ ! -e "$T/cardwt/byz-ccu-arch-pi" ]; } && ok "fetch 실패 → 판정 불가 fetch" || bad "fetch rc=$RC out=$OUT"

echo "---"; [ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }; echo "FAIL $fail"; exit 1
