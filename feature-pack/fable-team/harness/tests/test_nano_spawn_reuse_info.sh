#!/usr/bin/env bash
# test_nano_spawn_reuse_info.sh — 카드 r196-worktree-reuse-info-rewrite: ft-nano-spawn 재사용 가지가 info 없을 때만 .worktree-info.json 을 다시 쓴다
# 임시 git 리포만 쓴다 — 실제 리포·seats·tmux·원격 0. 스크립트의 «R196 블록» 을 잘라 eval 한다(test_nano_close_sha_base.sh 꼴).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../scripts/harness-install/fable-team/bin"
TRK="$HERE/../../scripts/fable-team-bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:500}";; esac; }

bash -n "$SRC/ft-nano-spawn.sh" && ok "bash -n ft-nano-spawn.sh" || bad "bash -n ft-nano-spawn.sh"
cmp -s "$SRC/ft-nano-spawn.sh" "$TRK/ft-nano-spawn.sh" && ok "사본 cmp (원본 = 설치 키트)" || bad "사본 불일치"

SNIP="$(awk '/^  # R196:/{p=1} p&&/^fi$/{exit} p{print}' "$SRC/ft-nano-spawn.sh")"
[ -n "$SNIP" ] && ok "spawn 에 R196 블록 있음" || bad "spawn 에 R196 블록 없음"

REPO="$T/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main
GIT() { git -C "$REPO" -c user.email=t@t -c user.name=t "$@"; }
echo base > "$REPO/a.txt"; GIT add a.txt; GIT commit -q -m init
BASE_SHORT="$(GIT rev-parse --short HEAD)"
BR="nano/reuse-x"; WT="$REPO/.worktrees/v65-reuse-x"
GIT worktree add -q "$WT" -b "$BR" main
echo w > "$WT/w.txt"; git -C "$WT" add w.txt; git -C "$WT" -c user.email=t@t -c user.name=t commit -q -m work   # 나노 HEAD 는 main 보다 앞섬 → merge-base = main 팁

# reuse <snippet> <BRANCH> → 블록을 서브셸에서 돌려 stdout·rc 를 돌려준다 (exit 가 서브셸만 끝낸다)
reuse() { ( WTDIR="$WT"; BRANCH="$2"; BASE_BRANCH=main; INFO_BASE=main; IDX_REL="design/x/진행/r196.md"; eval "$1" ) 2>&1; }

echo "== ⓐ 재사용 + info 없음 + HEAD = \$BRANCH → info 생성"
rm -f "$WT/.worktree-info.json"
out="$(reuse "$SNIP" "$BR")"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "INFO 재작성 $WT" "rc=0 + INFO 재작성 1줄" || bad "ⓐ rc=$rc ← $out"
keys="$(python3 -c 'import json,sys;print(",".join(sorted(json.load(open(sys.argv[1])))))' "$WT/.worktree-info.json" 2>/dev/null)"
[ "$keys" = "base,base_sha,branch,created_at,purpose" ] && ok "  └ 키 5개" || bad "키: $keys"
get() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2],""))' "$WT/.worktree-info.json" "$1"; }
[ "$(get branch)" = "$BR" ] && ok "  └ branch = HEAD 브랜치" || bad "branch=$(get branch)"
[ "$(get base)" = "main" ] && ok "  └ base = INFO_BASE" || bad "base=$(get base)"
[ "$(get base_sha)" = "$BASE_SHORT" ] && ok "  └ base_sha = merge-base 짧은 sha" || bad "base_sha=$(get base_sha) 기대 $BASE_SHORT"
has "$(get purpose)" "nano · reuse · design/x/진행/r196.md" "  └ purpose 에 reuse 표시"

echo "== ⓑ 재사용 + info 있음 → 파일 바이트 그대로(created_at 보존)"
printf '{"branch":"%s","base":"main","base_sha":"old","created_at":"2026-01-01 00:00:00","purpose":"keep"}\n' "$BR" > "$WT/.worktree-info.json"
before="$(shasum "$WT/.worktree-info.json")"
out="$(reuse "$SNIP" "$BR")"; rc=$?
[ "$rc" -eq 0 ] && [ "$before" = "$(shasum "$WT/.worktree-info.json")" ] && ok "바이트 동일 · rc=0" || bad "ⓑ rc=$rc 변경됨 ← $out"
case "$out" in *"INFO 재작성"*) bad "ⓑ 재작성 줄 출력됨";; *) ok "  └ INFO 재작성 줄 없음";; esac

echo "== ⓒ 재사용 + HEAD ≠ \$BRANCH → REJECT · info 쓰기 0"
rm -f "$WT/.worktree-info.json"
out="$(reuse "$SNIP" "nano/other")"; rc=$?
[ "$rc" -ne 0 ] && has "$out" "REJECT 재사용 워크트리 브랜치 불일치 — HEAD=$BR 기대=nano/other" "REJECT 문구 · rc≠0" || bad "ⓒ rc=$rc ← $out"
[ ! -e "$WT/.worktree-info.json" ] && ok "  └ info 쓰기 0" || bad "REJECT 인데 info 생성됨"
echo "   (detached)"
git -C "$WT" checkout -q --detach
out="$(reuse "$SNIP" "$BR")"; rc=$?
[ "$rc" -ne 0 ] && has "$out" "HEAD=detached 기대=$BR" "detached → REJECT" || bad "detached rc=$rc ← $out"
[ ! -e "$WT/.worktree-info.json" ] && ok "  └ info 쓰기 0" || bad "detached REJECT 인데 info 생성됨"
git -C "$WT" checkout -q "$BR"

echo "== ⓓ 새로 만들기 경로 — 출력·info 꼴 무변경(printf 줄 그대로 · 재작성 줄은 else 가지에만)"
grep -qF '"nano · %s"}\n'"'"' "$BRANCH" "$INFO_BASE" "$(git -C "$ROOT" rev-parse --short "$BASE_BRANCH")"' "$SRC/ft-nano-spawn.sh" \
  && ok "새로 만들 때 info printf 인자 그대로" || bad "새로 만들기 printf 변경됨"
[ "$(grep -c 'INFO 재작성' "$SRC/ft-nano-spawn.sh")" = "1" ] && ok "INFO 재작성 출력 1곳(else 가지)" || bad "INFO 재작성 출력 개수 불일치"

echo "== ⓔ 생성된 info 를 ft-nano-close 의 branch 읽기가 branch=? 없이 읽는다"
rm -f "$WT/.worktree-info.json"; reuse "$SNIP" "$BR" >/dev/null
CLOSE_BR="$(grep -m1 '^br="\$(python3' "$SRC/ft-nano-close.sh")"
[ -n "$CLOSE_BR" ] && ok "close 에 branch 읽기 줄 있음" || bad "close 의 branch 읽기 줄 없음"
got="$( ( eval "$CLOSE_BR"; printf '%s' "$br" ) 2>&1 )"   # close 는 $WT 를 워크트리 경로로 쓴다(= 이 시험의 WT)
[ "$got" = "$BR" ] && ok "close 가 읽은 branch = $BR (nano/*)" || bad "close branch=${got:-?}"

echo "== ⓕ 쓰기 불가 폴더(0555) → REJECT · info 없음 · 임시 파일 잔재 0 · 열기 단계 0 (DA⑥ H1)"
rm -f "$WT/.worktree-info.json"; chmod 555 "$WT"
out="$(reuse "$SNIP; echo OPENED" "$BR")"; rc=$?
chmod 755 "$WT"
[ "$rc" -ne 0 ] && has "$out" "REJECT 재사용 워크트리 info 쓰기 실패 — $WT/.worktree-info.json" "REJECT 문구 · rc≠0" || bad "ⓕ rc=$rc ← $out"
case "$out" in *"INFO 재작성"*|*OPENED*) bad "ⓕ 성공 줄/열기 단계가 출력됨 ← $out";; *) ok "  └ INFO 재작성·열기 단계 0";; esac
[ ! -e "$WT/.worktree-info.json" ] && ok "  └ info 없음" || bad "ⓕ info 생성됨"
[ -z "$(ls -A "$WT" | grep 'worktree-info.json.tmp')" ] && ok "  └ 임시 파일 잔재 0" || bad "임시 파일 잔재"

echo "== 변이 — else 가지 제거 → ⓐ 단언 FAIL 이어야 한다"
rm -f "$WT/.worktree-info.json"
reuse ":" "$BR" >/dev/null
[ ! -e "$WT/.worktree-info.json" ] && ok "변이(블록 제거) 시 info 생성 안 됨 → ⓐ 는 FAIL 로 잡힌다" || bad "변이인데 info 가 생김"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
