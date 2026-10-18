#!/usr/bin/env bash
# test_install_check_repo_outside.sh — r385 r4(사건 #109675 B): 하네스 루트(설치본 HARNESS_ROOT)가 --repo 밖일 때 ft-live-install-check
#   --range A..B → 범위가 건드린(ACMR) 옛 하네스 경로 4 + kit/ 파일 0 = `OK n=0 skip=0 (…)` rc0 · 1개라도 있으면 ERROR rc=3 + 파일명
#   --all → 옛 ERROR 그대로 · 호출 꼴 = ft-index-move-install.sh:26(`<sha>^..<sha>`) · ft-merge-land.sh:104(`--ref <B>`)
# mktemp 만 쓴다 — 실 HOME·실 리포 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HR="$(cd -- "$HERE/.." && pwd -P)"   # 팩 harness/ (kit/fable-team 실재)
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
unset FT_HARNESS_ROOT FT_ROOT FT_BIN

H="$T/home"; V="$H/.claude/fable-team/live/9.9.9"; LB="$V/bin"; mkdir -p "$LB"
cp -p "$HR/kit/fable-team/bin"/* "$LB/" 2>/dev/null; printf '%s\n' "$HR" > "$V/HARNESS_ROOT"
FX="$T/fx"; mkdir -p "$FX/docs"; git -C "$FX" init -q -b main
gc() { git -C "$FX" -c user.name=t -c user.email=t@t "$@"; }
echo a > "$FX/docs/a.md"; mkdir -p "$FX/scripts/fable-team-bin"; echo old > "$FX/scripts/fable-team-bin/old.sh"
gc add -A; gc commit -qm c0; C0="$(git -C "$FX" rev-parse HEAD)"
echo b > "$FX/docs/b.md"; gc add -A; gc commit -qm c1; C1="$(git -C "$FX" rev-parse HEAD)"
echo x > "$FX/scripts/fable-team-bin/x.sh"; gc add -A; gc commit -qm c2; C2="$(git -C "$FX" rev-parse HEAD)"
gc rm -q "$FX/scripts/fable-team-bin/old.sh" "$FX/scripts/fable-team-bin/x.sh"; gc commit -qm c3; C3="$(git -C "$FX" rev-parse HEAD)"
mkdir -p "$FX/feature-pack/fable-team/harness/kit/fable-team/bin"; echo k > "$FX/feature-pack/fable-team/harness/kit/fable-team/bin/k.sh"
gc add -A; gc commit -qm c4; C4="$(git -C "$FX" rev-parse HEAD)"
snap() { (cd "$H" && find . -type f ! -path '*/__pycache__/*' | LC_ALL=C sort); }
BEFORE="$(snap)"
chk() { (cd "$FX" && env HOME="$H" bash "$LB/ft-live-install-check.sh" "$@" 2>&1); }

out="$(chk --range "$C0..$C1" --repo "$FX")"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "OK n=0 skip=0 (하네스 루트가 --repo 밖 · 범위에 하네스 파일 0)" ] && ok "범위에 하네스 파일 0 → OK n=0 rc0" || bad "하네스 0 rc=$rc «${out}»"
out="$(chk --range "$C1^..$C1" --repo "$FX")"; rc=$?
[ "$rc" = 0 ] && case "$out" in "OK n=0 "*) true;; *) false;; esac && ok "index-move 꼴 <sha>^..<sha> → OK n=0 rc0" || bad "^.. 꼴 rc=$rc «${out}»"
out="$(chk --range "$C0..$C1" --ref "$C1" --repo "$FX")"; rc=$?
[ "$rc" = 0 ] && case "$out" in "OK n=0 "*) true;; *) false;; esac && ok "merge-land 꼴 --ref <B> → OK n=0 rc0" || bad "--ref 꼴 rc=$rc «${out}»"
out="$(chk --range "$C1..$C2" --repo "$FX")"; rc=$?
[ "$rc" = 3 ] && case "$out" in "ERROR "*"--repo"*"밖"*"scripts/fable-team-bin/x.sh"*) true;; *) false;; esac && ok "범위에 scripts/fable-team-bin/x.sh → ERROR rc3 + 파일명" || bad "하네스 1 rc=$rc «${out}»"
out="$(chk --range "$C2..$C3" --repo "$FX")"; rc=$?
[ "$rc" = 0 ] && case "$out" in "OK n=0 "*) true;; *) false;; esac && ok "옛 하네스 파일 삭제만(r386 꼴) → OK n=0 rc0" || bad "삭제만 rc=$rc «${out}»"
out="$(chk --range "$C3..$C4" --repo "$FX")"; rc=$?
[ "$rc" = 3 ] && case "$out" in "ERROR "*"harness/kit/fable-team/bin/k.sh"*) true;; *) false;; esac && ok "팩 꼴 */harness/kit/ 변경(다른 체크아웃) → ERROR rc3 + 파일명" || bad "팩 꼴 rc=$rc «${out}»"
out="$(chk --range "$C0..nosuch" --repo "$FX")"; rc=$?
[ "$rc" = 3 ] && ok "범위 끝 sha 없음 → ERROR rc3" || bad "없는 sha rc=$rc «${out}»"
out="$(chk --all --repo "$FX")"; rc=$?
[ "$rc" = 3 ] && [ "$out" = "ERROR 하네스 루트($HR)가 --repo($FX) 밖 — --kit 를 준다" ] && ok "--all → 옛 ERROR 그대로 rc3" || bad "--all rc=$rc «${out}»"
[ "$(snap)" = "$BEFORE" ] && ok "임시 HOME 밑 새 파일 0" || bad "임시 HOME 에 새 파일: $(comm -13 <(printf '%s\n' "$BEFORE") <(snap) | head -3 | tr '\n' ' ')"

echo "== $( [ $fail = 0 ] && echo ALL PASS || echo "FAIL $fail" ) =="
[ $fail = 0 ]
