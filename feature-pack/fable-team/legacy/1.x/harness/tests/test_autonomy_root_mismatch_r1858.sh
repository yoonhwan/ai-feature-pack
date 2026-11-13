#!/usr/bin/env bash
# test_autonomy_root_mismatch_r1858.sh — r1858: FT_ROOT 와 라이브 루트(.fable-team/LIVE_ROOT)가 다르면 status·scope-status·scope-approve 가
#   남의 state 를 읽어 «자율 OFF» 를 내지 않고 REJECT 1줄 + rc1 (카드 반례 ①~④ · 변이 M1·M2)
# 격리: 임시 리포(state = OFF) + 임시 라이브 worktree(state = ON A17) · 옛 꼴 폴더 · 실 리포 state·장부 0 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN0="$HERE/../bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
SHA=0123456789abcdef0123456789abcdef01234567; R="$T/repo"; L="$T/live"; O="$T/old"
git init -q "$R" && git -C "$R" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base && git -C "$R" worktree add -q "$L" -b live 2>/dev/null || { echo "FAIL 픽스처 리포"; exit 1; }
st() { mkdir -p "$1/.fable-team/state"; printf '100\t%s\t%s\n' "$2" "$3" > "$1/.fable-team/state/autonomy.log"
  printf '{"mode":"%s","since":100,"event":"%s","until":null}\n' "$2" "$3" > "$1/.fable-team/state/autonomy.json"; }
st "$R" off A3; st "$L" on A17; st "$O" off A3; printf '%s\n' "$L" > "$R/.fable-team/LIVE_ROOT"
ft() { local b="$1" r="$2"; shift 2; ( cd /tmp && env -i HOME="$T" PATH="/usr/bin:/bin" FT_ROOT="$r" bash "$b/ft-autonomy.sh" "$@" ) >"$T/o" 2>"$T/e"; echo $?; }
nap() { find "$R/.fable-team/state" "$L/.fable-team/state" -path '*autonomy-merge-approved/*' -type f 2>/dev/null | grep -c .; }
REJ="REJECT 승인 폴더 어긋남 — FT_ROOT=$R · 라이브 루트=$L"
c1() {  # <bin> → ① status 어긋남 = stdout 0 · REJECT 1줄 · rc1
  local f0=$fail rc; rc="$(ft "$1" "$R" status)"
  [ "$rc" = 1 ] && [ ! -s "$T/o" ] && [ "$(grep -c . "$T/e")" = 1 ] && grep -qF "$REJ" "$T/e" && ok "① status rc1 · stdout 0 · REJECT 1줄" || bad "① rc=$rc out=$(cat "$T/o") err=$(head -c 300 "$T/e")"
  return $((fail - f0)); }
c2() {  # <bin> → ② scope-status·scope-approve 어긋남 = rc1 · REJECT · 승인 파일 0
  local f0=$fail rc c
  for c in scope-status "scope-approve $SHA"; do rc="$(ft "$1" "$R" $c)"
    [ "$rc" = 1 ] && [ ! -s "$T/o" ] && grep -qF "$REJ" "$T/e" && [ "$(nap)" = 0 ] && ok "② $c rc1 · REJECT · 승인 파일 0" || bad "② $c rc=$rc out=$(cat "$T/o") err=$(head -c 300 "$T/e") 파일=$(nap)"; done
  return $((fail - f0)); }
echo "== ① ② 어긋남"; c1 "$BIN0"; c2 "$BIN0"
echo "== ③ FT_ROOT = 라이브 루트 → 지금 그대로"
rc="$(ft "$BIN0" "$L" status)"; [ "$rc" = 0 ] && grep -q '^\[자율 ON A17 ' "$T/o" && ! grep -q REJECT "$T/e" && ok "③ status rc0 · [자율 ON A17 …]" || bad "③ status rc=$rc out=$(cat "$T/o") err=$(head -c 300 "$T/e")"
rc="$(ft "$BIN0" "$L" scope-status)"; [ "$rc" = 0 ] && grep -q '^\[범위 승인 없음' "$T/o" && ok "③ scope-status rc0 · 지금 출력" || bad "③ scope-status rc=$rc out=$(cat "$T/o") err=$(head -c 300 "$T/e")"
echo "== ④ LIVE_ROOT 없는 옛 꼴 → 지금 그대로"
rc="$(ft "$BIN0" "$O" status)"; [ "$rc" = 0 ] && [ "$(cat "$T/o")" = "[자율 OFF]" ] && ! grep -q REJECT "$T/e" && ok "④ status rc0 · [자율 OFF]" || bad "④ rc=$rc out=$(cat "$T/o") err=$(head -c 300 "$T/e")"
rc="$(ft "$BIN0" "$O" scope-status)"; [ "$rc" = 0 ] && ! grep -q REJECT "$T/e" && ok "④ scope-status rc0 · REJECT 0" || bad "④ scope-status rc=$rc err=$(head -c 300 "$T/e")"
echo "== bin·kit 같은 내용"; cmp -s "$BIN0/ft-autonomy.sh" "$HERE/../kit/fable-team/bin/ft-autonomy.sh" && ok "cmp0 ft-autonomy.sh" || bad "키트 다름 ft-autonomy.sh"
mutant() { local m="$T/mut-$1"; cp -R "$BIN0" "$m" && sed "$2" "$BIN0/ft-autonomy.sh" > "$m/ft-autonomy.sh"
  cmp -s "$BIN0/ft-autonomy.sh" "$m/ft-autonomy.sh" && return 1; echo "$m"; }   # 사본 = 원본이면 rc1 → 부른 줄이 FAIL
mutv() { local f0=$fail; "$@" >/dev/null 2>&1; local d=$?; fail=$f0; [ "$d" -gt 0 ]; }
echo "== 변이 M1·M2 — 대응 칸 FAIL 검출"
m="$(mutant M1 's/in status|scope-status|scope-approve) live_match/in status) live_match/')" && { mutv c2 "$m" && ok "M1(scope-approve 빠짐) → ② FAIL 검출" || bad "M1 을 못 잡음"; } || bad "변이 M1 사본 = 원본"
m="$(mutant M2 's/scope-approve) live_match || exit 1/scope-approve) live_match || :/')" && { mutv c1 "$m" && ok "M2(경고만 · rc0) → ① FAIL 검출" || bad "M2 를 못 잡음"; } || bad "변이 M2 사본 = 원본"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL $fail"; exit 1; }
