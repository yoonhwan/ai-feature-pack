#!/usr/bin/env bash
# test_head_sync_apply_scope.sh — R749: ft-head-sync.sh --apply 의 쓰기 범위 = «부른 자리의 워크트리 1개» · 전 순회는 --all --confirm N
#   + ft_head_lag.py 조치문 = «그 워크트리 안에서(cd <절대경로>)». 임시 origin+clone+워크트리 픽스처만(실 워크트리·실 원격 0 · press 0)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; SYNC="$BIN/ft-head-sync.sh"; PY="$BIN/ft_head_lag.py"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:400}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
syn() {  # syn <cwd> [인자…] — 그 자리에서 ft-head-sync 를 부른다(cwd = 쓰기 범위 판정의 기준)
  local d="$1"; shift; out="$( ( cd "$d" && bash "$SYNC" "$@" ) 2>&1 )"; rc=$?
}
head_of() { sha "$1" HEAD; }
snapall() { for d in a b c; do head_of "$T/f1/wt-$d"; git -C "$T/f1/wt-$d" status --porcelain; done | shasum; }
lagmsg() { python3 -I -c 'import sys; sys.path.insert(0, sys.argv[2]); from ft_head_lag import build
print(build([{"path": "/tmp/wtA", "branch": "nano/a", "n": 2, "secs": 18000}], "a" * 40, sys.argv[1]))' "$1" "$2"; }

# ── 픽스처 1: main 이 한 번 전진한 뒤, M0 에서 딴 워크트리 3개(A·B·C)가 전부 뒤처짐 · 미커밋 0
mkrepo "$T/f1"; W="$T/f1/w"
wt() { git -C "$W" worktree add -q -b "nano/$1" "$T/f1/wt-$1" "$M0"; git -C "$T/f1/wt-$1" config user.name t; git -C "$T/f1/wt-$1" config user.email t@t; }
wt a; echo a > "$T/f1/wt-a/a.txt"; cm "$T/f1/wt-a" "work a"
wt b; echo b > "$T/f1/wt-b/b.txt"; cm "$T/f1/wt-b" "work b"
wt c; echo c > "$T/f1/wt-c/c.txt"; cm "$T/f1/wt-c" "work c"
echo m1 > "$W/m.txt"; cm "$W" "main moves"; git -C "$W" push -q origin main
M1="$(sha "$W" HEAD)"

bash -n "$SYNC"; ck "bash -n head-sync" $?
[ "$(wc -l < "$SYNC" | tr -d ' ')" -le 130 ]; ck "ft-head-sync.sh ≤ 130줄" $?

# ── ⓕ 표 모드(--apply 없음) = 지금과 같음 — 전 워크트리 나열 · 읽기 전용
S0="$(snapall)"; syn "$T" --repo "$W"
[ "$rc" = 0 ] && [[ "$out" == *"apply=0"* ]] && [ "$(printf '%s\n' "$out" | grep -cE '^nano/(a|b|c) ')" = 3 ]; ck "ⓕ 표 모드는 A·B·C 셋 다 나열(apply=0)" $?
[ "$(printf '%s\n' "$out" | grep -c '최신화 필요')" -ge 3 ] && [ "$(snapall)" = "$S0" ]; ck "ⓕ 표 모드 = 셋 다 «최신화 필요» · HEAD/상태 불변" $?

# ── ⓑ A 안에서 --apply (--repo 는 그 리포) → A 만 최신화 · B·C 비파괴
H0a="$(head_of "$T/f1/wt-a")"; H0b="$(head_of "$T/f1/wt-b")"; H0c="$(head_of "$T/f1/wt-c")"
syn "$T/f1/wt-a" --apply --repo "$W"
[ "$rc" = 0 ] && printf '%s\n' "$out" | awk '$1=="nano/a"' | grep -q '최신화함'; ck "ⓑ A 안 --apply rc=0 · a 줄 «최신화함»" $?
[ "$(head_of "$T/f1/wt-a")" != "$H0a" ] && git -C "$T/f1/wt-a" merge-base --is-ancestor "$M1" HEAD && [ "$(git -C "$T/f1/wt-a" rev-list --parents -n1 HEAD | wc -w | tr -d ' ')" = 3 ]; ck "ⓑ A 만 merge 1커밋(부모 2) · main 조상" $?
[ "$(head_of "$T/f1/wt-b")" = "$H0b" ] && [ "$(head_of "$T/f1/wt-c")" = "$H0c" ] && [ -z "$(git -C "$T/f1/wt-b" status --porcelain)" ] && [ -z "$(git -C "$T/f1/wt-c" status --porcelain)" ]; ck "ⓑ 비파괴 대조: B·C HEAD 전후 같음 · 미커밋 0" $?
printf '%s\n' "$out" | awk '$1=="nano/b"' | grep -q '다른 워크트리 — 그 자리에서' && printf '%s\n' "$out" | awk '$1=="nano/c"' | grep -q '다른 워크트리 — 그 자리에서'; ck "ⓑ 표에 B·C = «다른 워크트리 — 그 자리에서»" $?
[[ "$out" == *"비파괴 증거"* ]]; ck "ⓑ 비파괴 증거 줄 출력" $?

# ── ⓒ 리포 공용 루트·제외 목록 가지(main)·비-repo 자리 = REJECT rc 2 · 쓰기 0
S1="$(snapall)"; syn "$W" --apply --repo "$W"
[ "$rc" = 2 ] && [[ "$out" == *"이 자리는 최신화 대상 워크트리가 아니다"* ]] && [ "$(snapall)" = "$S1" ]; ck "ⓒ main 워크트리에서 --apply → REJECT rc2 · 쓰기 0" $?
syn "$T" --apply --repo "$W"
[ "$rc" = 2 ] && [ "$(snapall)" = "$S1" ]; ck "ⓒ 리포 공용 루트(워크트리 아님)에서 --apply → REJECT rc2 · 쓰기 0" $?
syn "$T/f1/origin.git" --apply --repo "$W"
[ "$rc" = 2 ] && [ "$(snapall)" = "$S1" ]; ck "ⓒ bare origin 안에서 --apply → REJECT rc2 · 쓰기 0" $?
! printf '%s\n' "$out" | grep -qi 'usage'; ck "ⓒ REJECT 문구에 usage 오분류 0" $?

# ── ⓓ --apply --all 만(--confirm 없음) = REJECT + 지금 수 출력 · 쓰기 0
syn "$T" --apply --all --repo "$W"
[ "$rc" = 2 ] && [[ "$out" == *"--confirm"* ]] && [[ "$out" == *"«최신화 필요» 2 곳"* ]] && [ "$(snapall)" = "$S1" ]; ck "ⓓ --apply --all 만 → REJECT rc2 · «최신화 필요» 2 곳 출력 · 쓰기 0" $?
# ── ⓔ --confirm 틀린 수 = REJECT 쓰기 0 · 맞는 수 = 지금 판과 같은 전 순회
syn "$T" --apply --all --confirm 99 --repo "$W"
[ "$rc" = 2 ] && [[ "$out" == *"99"* ]] && [[ "$out" == *"2 곳"* ]] && [ "$(snapall)" = "$S1" ]; ck "ⓔ --confirm 99(틀림) → REJECT rc2 · 쓰기 0" $?
syn "$T" --apply --all --confirm 2 --repo "$W"
[ "$rc" = 0 ] && printf '%s\n' "$out" | awk '$1=="nano/b"' | grep -q '최신화함' && printf '%s\n' "$out" | awk '$1=="nano/c"' | grep -q '최신화함'; ck "ⓔ --confirm 2(맞음) → B·C 전 순회 최신화함(cwd 무관)" $?
[ "$(git -C "$T/f1/wt-b" merge-base --is-ancestor "$M1" HEAD; echo $?)" = 0 ] && [ "$(git -C "$T/f1/wt-c" merge-base --is-ancestor "$M1" HEAD; echo $?)" = 0 ]; ck "ⓔ B·C 에 main 조상 포함" $?

# ── ⓖ 알림 조치문 = «그 워크트리 안에서(cd <절대경로>)» · 목록에 절대 경로 · 문구에 --all 0
out="$(lagmsg "$BIN" "$BIN")"
[[ "$out" == *"/tmp/wtA"* ]]; ck "ⓖ 목록 줄에 절대 경로" $?
[[ "$out" == *"그 워크트리 안에서(cd /tmp/wtA)"* ]] && [[ "$out" == *"--apply (그 워크트리만"* ]]; ck "ⓖ 조치문 = 그 워크트리 안에서(cd <경로>) … --apply (그 워크트리만)" $?
! printf '%s\n' "$out" | grep -q -- '--all'; ck "ⓖ 조치문에 --all 0" $?
! printf '%s\n' "$out" | grep -q '조치: 미커밋 0 이면'; ck "ⓖ 옛 조치문(어디서 쳐야 하는지 없음) 0" $?

# ── ⓘ 변이 2종 — 단언이 실제로 잡는가
mkbin() { local d="$1"; mkdir -p "$d"; for f in "$BIN"/*; do ln -s "$f" "$d/$(basename "$f")"; done; rm -f "$d/ft-head-sync.sh" "$d/ft_head_lag.py"; }
mkrepo "$T/f2"; W="$T/f2/w"; M2="$(sha "$W" HEAD)"
for d in a b c; do git -C "$W" worktree add -q -b "nano/$d" "$T/f2/wt-$d" "$M2"; git -C "$T/f2/wt-$d" config user.name t; git -C "$T/f2/wt-$d" config user.email t@t; echo "$d" > "$T/f2/wt-$d/$d.txt"; cm "$T/f2/wt-$d" "work $d"; done
echo m > "$W/m.txt"; cm "$W" "main moves"; git -C "$W" push -q origin main
mkbin "$T/mut1"; sed -e '/elif ! awk -F/d' -e '/다른 워크트리 — 그 자리에서/d' "$SYNC" > "$T/mut1/ft-head-sync.sh"
H0b2="$(head_of "$T/f2/wt-b")"
out="$( ( cd "$T/f2/wt-a" && bash "$T/mut1/ft-head-sync.sh" --apply --repo "$W" ) 2>&1 )"; rc=$?
[ "$rc" = 0 ] && [ "$(head_of "$T/f2/wt-b")" != "$H0b2" ]; ck "ⓘ 변이(cwd 한정 삭제) → B 도 병합됨 = ⓑ 단언이 잡는다" $?
mkbin "$T/mut2"; sed "s|조치: 그 워크트리 안에서(cd {where}) |조치: |" "$PY" > "$T/mut2/ft_head_lag.py"
out="$(lagmsg "$T/mut2" "$T/mut2")"
! [[ "$out" == *"(cd /tmp/wtA)"* ]]; ck "ⓘ 변이(옛 조치문) → (cd <경로>) 사라짐 = ⓖ 단언이 잡는다" $?

# ── 정적 · 격리
! grep -vE '^\s*#' "$SYNC" | grep -qE 'git[^|]*(reset|rebase|--force|push)|\+refs'; ck "정적: reset·rebase·force·push 호출 0" $?
[ "$(git -C "$W" config --get core.bare)" != true ]; ck "core.bare 오염 0" $?
! grep -qE '"worktree", "list"' <(grep -vE '^\s*#' "$SYNC"); ck "정적: 다른 리포 워크트리를 이름으로 고르는 인자 0" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
