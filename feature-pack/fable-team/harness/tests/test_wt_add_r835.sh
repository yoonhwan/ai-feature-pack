#!/usr/bin/env bash
# test_wt_add_r835.sh — r835: kit/fable-team/bin/ft-wt-add.sh (팀 좌석 착지·카드 워크트리 = 나노와 같은 sparse).
#   픽스처 = mktemp 임시 리포(design/teams/{a,b,c}/ · design/harness/ · 루트 파일) + 자기 자신을 origin 으로 · 가짜 git(체크아웃 실패 주입 ⓔ).
#   실 리포·실 훅 등록·외부 호출 0 · GIT_* env 0. 변이 ⓘ = 사본에 한 줄 바꿔 이 파일을 다시 돌려 그 칸이 FAIL 인지(R835_MUT=1 은 재귀 0).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"
WT_ADD="${R835_WT_ADD:-$KIT/ft-wt-add.sh}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; T="$(cd "$T" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
G() { git -C "$R" "$@"; }

R="$T/r"; git init -q -b main "$R"; mkdir -p "$T/nohooks"
G config user.name t; G config user.email t@t; G config core.hooksPath "$T/nohooks"
mkdir -p "$R/design/teams/a" "$R/design/teams/b" "$R/design/teams/c" "$R/design/teams/planner" "$R/design/harness"
for t in a b c planner; do echo "$t" > "$R/design/teams/$t/f.md"; done
echo h > "$R/design/harness/h.md"; echo root > "$R/README.md"
G add -A; G commit -qm init
G remote add origin "$R"; G fetch -q origin
mkdir -p "$R/.venv"; echo X=1 > "$R/.env"
wt() { (cd "$R" && FT_SEAT=seat-t bash "$WT_ADD" "$@") >"$T/out" 2>&1; }
ondisk() { [ -e "$R/.worktrees/$1/$2" ]; }

echo "== ⓐ --team a -b docs/x --base main → sparse"
wt land-x --team a -b docs/x --base main; rc=$?
[ "$rc" = 0 ] && ok "ⓐ rc=0" || bad "ⓐ rc=$rc · $(cat "$T/out")"
want="$(printf '/*\n!/design/teams/*/\n/design/teams/a/')"
[ "$(git -C "$R/.worktrees/land-x" sparse-checkout list 2>/dev/null)" = "$want" ] && ok "ⓐ 패턴 3줄" || bad "ⓐ 패턴: $(git -C "$R/.worktrees/land-x" sparse-checkout list 2>&1)"
ondisk land-x design/teams/a/f.md && ok "ⓐ 자기 팀 a 있음" || bad "ⓐ a 없음"
! ondisk land-x design/teams/b && ! ondisk land-x design/teams/c && ok "ⓐ design/teams/b·c 디스크 0" || bad "ⓐ design/teams/b·c 디스크에 있음"
ondisk land-x design/harness/h.md && ondisk land-x README.md && ok "ⓐ design/harness·루트 파일 있음" || bad "ⓐ harness/루트 없음"
python3 - "$R/.worktrees/land-x/.worktree-info.json" "$(G rev-parse --short main)" <<'PY' && ok "ⓐ info(branch·base·base_sha·purpose)" || bad "ⓐ info: $(cat "$R/.worktrees/land-x/.worktree-info.json" 2>&1)"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["branch"] == "docs/x" and d["base"] == "main" and d["base_sha"] == sys.argv[2] and d["purpose"] == "wt-add · a", d
assert d["created_at"]
PY
[ "$(readlink "$R/.worktrees/land-x/.venv")" = ../../.venv ] && [ "$(readlink "$R/.worktrees/land-x/.env")" = ../../.env ] && ok "ⓐ .venv/.env 링크" || bad "ⓐ 링크 없음"
tail -1 "$T/out" | grep -Eq "^WT $R/.worktrees/land-x sparse team=a size=[0-9]+$" && ok "ⓐ 끝줄 WT … sparse team=a size=" || bad "ⓐ 끝줄: $(tail -1 "$T/out")"

echo "== ⓑ --branch <기존 가지>"
G branch feat/free main
wt b-ok --team a --branch feat/free; rc=$?
[ "$rc" = 0 ] && [ "$(git -C "$R/.worktrees/b-ok" symbolic-ref --short HEAD 2>/dev/null)" = feat/free ] && ok "ⓑ 기존 가지 체크아웃 rc=0" || bad "ⓑ rc=$rc · $(cat "$T/out")"
wt b-dup --team a --branch docs/x; rc=$?
[ "$rc" = 1 ] && grep -q '^REJECT worktree add 실패 — fatal: .*docs/x' "$T/out" && ok "ⓑ 다른 워크트리에 걸린 가지 = REJECT(git 문구 그대로)" || bad "ⓑ dup rc=$rc · $(cat "$T/out")"
[ ! -e "$R/.worktrees/b-dup" ] && ok "ⓑ 거절 때 폴더 0" || bad "ⓑ 거절인데 폴더 생김"

echo "== ⓒ --also (여러 번) · 없는 경로 REJECT"
wt c-ok --team a --also design/teams/planner/ --also design/teams/b/f.md -b docs/c --base main; rc=$?
[ "$rc" = 0 ] && ondisk c-ok design/teams/planner/f.md && ondisk c-ok design/teams/b/f.md && ! ondisk c-ok design/teams/c && ok "ⓒ planner·b/f.md 나옴 · c 0" || bad "ⓒ rc=$rc · $(cat "$T/out")"
wt c-bad --team a --also design/nope/ -b docs/cb --base main; rc=$?
[ "$rc" = 1 ] && grep -q '^REJECT --also 경로가 main 에 없다: design/nope/' "$T/out" && [ ! -e "$R/.worktrees/c-bad" ] && ok "ⓒ 없는 경로 = REJECT · 폴더 0" || bad "ⓒ bad rc=$rc · $(cat "$T/out")"

echo "== ⓓ --full <사유> · 사유 없음/짧음 · 둘 다 없음"
wt d-full --full "판정용 전체 사본이 필요함" -b docs/d --base main; rc=$?
[ "$rc" = 0 ] && ondisk d-full design/teams/b/f.md && ondisk d-full design/teams/c/f.md && ok "ⓓ 풀 체크아웃 rc=0" || bad "ⓓ full rc=$rc · $(cat "$T/out")"
tail -1 "$T/out" | grep -Eq "^WT $R/.worktrees/d-full full size=[0-9]+$" && ok "ⓓ 끝줄 WT … full" || bad "ⓓ 끝줄: $(tail -1 "$T/out")"
LOG="$R/.fable-team/state/wt-add-full.log"
[ "$(wc -l < "$LOG" 2>/dev/null | tr -d ' ')" = 1 ] && grep -Eq "^[0-9-]+ [0-9:]+ · seat-t · $R/.worktrees/d-full · 판정용 전체 사본이 필요함$" "$LOG" && ok "ⓓ 로그 1줄(시각·좌석·경로·사유)" || bad "ⓓ 로그: $(cat "$LOG" 2>&1)"
wt d-none --full -b docs/dn --base main; rc=$?
[ "$rc" = 1 ] && grep -q '^REJECT --full 사유는 10자 이상(지금 0자)' "$T/out" && ok "ⓓ 사유 없음 = REJECT" || bad "ⓓ none rc=$rc · $(cat "$T/out")"
wt d-short --full "짧은사유" -b docs/ds --base main; rc=$?
[ "$rc" = 1 ] && grep -q '^REJECT --full 사유는 10자 이상(지금 4자)' "$T/out" && ok "ⓓ 사유 짧음 = REJECT" || bad "ⓓ short rc=$rc · $(cat "$T/out")"
wt d-guess -b docs/dg --base main; rc=$?
[ "$rc" = 1 ] && grep -q '^REJECT --team <팀> 또는 --full' "$T/out" && ok "ⓓ --team·--full 둘 다 없음 = REJECT(추측 0)" || bad "ⓓ guess rc=$rc · $(cat "$T/out")"
[ ! -e "$R/.worktrees/d-none" ] && [ ! -e "$R/.worktrees/d-short" ] && [ ! -e "$R/.worktrees/d-guess" ] && [ "$(wc -l < "$LOG" | tr -d ' ')" = 1 ] && ok "ⓓ 거절 때 폴더·로그 0" || bad "ⓓ 거절인데 폴더/로그 생김"

echo "== ⓔ 체크아웃 실패 → 2 s 뒤 재시도(최대 3회)"
REAL_GIT="$(command -v git)"; mkdir -p "$T/fakebin"
cat > "$T/fakebin/git" <<EOF
#!/bin/bash
for a in "\$@"; do
  if [ "\$a" = checkout ]; then
    n=\$(( \$(cat "$T/co.count" 2>/dev/null || echo 0) + 1 )); echo \$n > "$T/co.count"
    [ \$n -le \${FAKE_CO_FAILS:-0} ] && { echo "error: fake checkout fail \$n" >&2; exit 1; }
    break
  fi
done
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$T/fakebin/git"
rm -f "$T/co.count"; ( export PATH="$T/fakebin:$PATH" FAKE_CO_FAILS=1; wt e-once --team a -b docs/e1 --base main ); rc=$?
[ "$rc" = 0 ] && grep -q '^RETRY checkout 1/3 실패 — 2 s 뒤 다시: error: fake checkout fail 1' "$T/out" && ondisk e-once design/teams/a/f.md && [ "$(cat "$T/co.count")" = 2 ] && ok "ⓔ 1회 실패 → 재시도 성공" || bad "ⓔ once rc=$rc · $(cat "$T/out")"
rm -f "$T/co.count"; ( export PATH="$T/fakebin:$PATH" FAKE_CO_FAILS=3; wt e-fail --team a -b docs/e3 --base main ); rc=$?
[ "$rc" = 1 ] && [ "$(cat "$T/co.count")" = 3 ] && grep -q "^REJECT 체크아웃 3회 실패(error: fake checkout fail 3) · 워크트리 남김: $R/.worktrees/e-fail · 가지 docs/e3" "$T/out" && [ -d "$R/.worktrees/e-fail" ] && ok "ⓔ 3회 실패 = REJECT + 남김 문구 · 3회만" || bad "ⓔ fail rc=$rc · count=$(cat "$T/co.count" 2>&1) · $(cat "$T/out")"

echo "== ⓗ sparse 워크트리에서 git merge origin/main"
wt h-ok --team a -b docs/h --base main >/dev/null
echo c2 > "$R/design/teams/c/f.md"; echo root2 > "$R/README.md"; G commit -qam "main: c·root"; G fetch -q origin
git -C "$R/.worktrees/h-ok" merge -q --no-edit origin/main >"$T/out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ "$(cat "$R/.worktrees/h-ok/README.md")" = root2 ] && ! ondisk h-ok design/teams/c && [ "$(git -C "$R/.worktrees/h-ok" show HEAD:design/teams/c/f.md)" = c2 ] && ok "ⓗ sparse 밖 변경 포함 merge rc=0 · c 디스크 0 · 트리엔 c2" || bad "ⓗ merge rc=$rc · $(cat "$T/out")"
G checkout -q -b docs/conf main; echo b-conf > "$R/design/teams/b/f.md"; G commit -qam "conf: b"; G checkout -q main
echo b-main > "$R/design/teams/b/f.md"; G commit -qam "main: b"; G fetch -q origin
wt h-conf --team a --branch docs/conf >/dev/null
! ondisk h-conf design/teams/b && ok "ⓗ 충돌 전 b 디스크 0" || bad "ⓗ 충돌 전 b 있음"
git -C "$R/.worktrees/h-conf" merge --no-edit origin/main >"$T/out" 2>&1; rc=$?
[ "$rc" != 0 ] && ondisk h-conf design/teams/b/f.md && ! ondisk h-conf design/teams/c && ok "ⓗ sparse 밖 충돌 = 그 파일만 디스크에 나옴(rc=$rc)" || bad "ⓗ conflict rc=$rc · $(cat "$T/out")"

echo "== 결과: FAIL=$fail"
[ "${R835_MUT:-0}" = 1 ] && exit $((fail > 0))

echo "== ⓘ 변이(사본에 한 줄 · 그 칸이 FAIL 이어야)"
mutate() {  # <이름> <찾을 글자> <바꿀 글자> <FAIL 이어야 할 칸 접두>
  local d="$T/mut-$1"; mkdir -p "$d"; cp "$KIT/ft-wt-add.sh" "$KIT/ft-team-lib.sh" "$d/"
  python3 - "$d/ft-wt-add.sh" "$2" "$3" <<'PY' || { bad "ⓘ $1 변이 글자 못 찾음"; return; }
import sys
p, a, b = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
assert s.count(a) == 1, s.count(a); open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
  R835_MUT=1 R835_WT_ADD="$d/ft-wt-add.sh" bash "$0" >"$d/run.txt" 2>&1; local rc=$?
  [ "$rc" != 0 ] && grep -q "^FAIL $4" "$d/run.txt" && ok "ⓘ $1 → $(grep -m1 "^FAIL $4" "$d/run.txt")" || bad "ⓘ $1 변이가 안 잡힘 rc=$rc"
}
mutate no-sparse-set 'ft_sparse_patterns "$TEAM" ${ALSO[@]+"${ALSO[@]}"} | git -C "$WT" sparse-checkout set' 'true | true' 'ⓐ design/teams/b·c'
mutate no-full-reason '[ "${n:-0}" -ge 10 ] ||' 'true ||' 'ⓓ short'
echo "== 결과(변이 포함): FAIL=$fail"
[ "$fail" = 0 ]
