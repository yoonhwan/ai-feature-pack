#!/usr/bin/env bash
# test_pre_push_range.sh — r511: push 게이트(kit/fable-team/githooks/pre-push)의 range 계산.
#   새 가지(remote_sha 0) range = merge-base(origin/main, tip)..tip — 커밋 하나만 넘기면 git diff 가
#   «그 커밋 ↔ 작업 트리» 로 읽어 미커밋 변경을 잡고(오탐) 올라가는 제품 커밋은 놓친다(누락).
#   ⓐ 새 가지 · 문서 커밋 + 작업 트리 gateway 미커밋 → 통과  ⓑ 새 가지 · gateway/b.py 커밋 → 거부 + «range: <mb>..<tip>»
#   ⓒ 기존 가지 문서만 → 통과 · 제품 포함 → 거부  ⓓ origin/main 없음 → 거부 «merge-base … 못 구함» · diff 실패 → 거부
#   ⓔ GATE_BRANCH 아님 → 검사 0 · FT_PUSH_DA6_OK 우회 기록 그대로 · 변이 = PRE_PUSH=<옛 판> 로 돌리면 ⓐ·ⓑ FAIL
# 임시 bare origin + 클론만 — push 0(훅에 stdin 줄 직접) · 외부 호출 0 · GIT_* env 0 · bd 는 가짜(실 beads 0).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HOOK="${PRE_PUSH:-$HERE/../kit/fable-team/githooks/pre-push}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_PUSH_DA6_OK
ZERO=0000000000000000000000000000000000000000
GB=feat/v6-realtime-live

sh -n "$HOOK" && ok "sh -n pre-push" || bad "sh -n pre-push"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/fakebin"; printf '#!/bin/sh\nexit 0\n' > "$T/fakebin/bd"; chmod 755 "$T/fakebin/bd"
export PATH="$T/fakebin:$PATH"

git init -q -b main "$T/seed"
S() { git -C "$T/seed" "$@"; }
S config user.email t@t; S config user.name t
mkdir -p "$T/seed/gateway" "$T/seed/docs"
echo a > "$T/seed/gateway/a.py"; echo x > "$T/seed/docs/x.md"
S add -A; S commit -qm base
git clone -q --bare "$T/seed" "$T/origin.git"

# 클론 하나 = 시험 하나(작업 트리 상태가 섞이지 않게)
clone() {
  git clone -q "$T/origin.git" "$T/$1"
  git -C "$T/$1" config user.email t@t; git -C "$T/$1" config user.name t
  git -C "$T/$1" checkout -q -b "${2:-$GB}"
}
commit_file() { mkdir -p "$(dirname "$T/$1/$2")"; echo "$3" > "$T/$1/$2"; git -C "$T/$1" add -A; git -C "$T/$1" commit -qm "$2"; }
# run <클론> <local_sha> <remote_sha> — 훅 rc 와 stderr 를 $T/out 에
run() {
  ( cd "$T/$1" && printf 'refs/heads/%s %s refs/heads/%s %s\n' "$GB" "$2" "$GB" "$3" \
      | sh "$HOOK" origin "$T/origin.git" ) 2> "$T/out"
}
MB=$(git -C "$T/seed" rev-parse HEAD)

# ⓐ 새 가지 · 문서 커밋 · 작업 트리에 gateway 미커밋 수정 → 통과
clone a; commit_file a docs/y.md y; echo dirty >> "$T/a/gateway/a.py"
run a "$(git -C "$T/a" rev-parse HEAD)" "$ZERO"; rc=$?
[ "$rc" = 0 ] && ok "ⓐ 새 가지 문서만 + 미커밋 제품 → 통과 rc0" || { bad "ⓐ rc=$rc (기대 0)"; sed 's/^/    /' "$T/out"; }

# ⓑ 새 가지 · gateway/b.py 커밋 → 거부 + range: <mb>..<tip>
clone b; commit_file b gateway/b.py b; TIP=$(git -C "$T/b" rev-parse HEAD)
run b "$TIP" "$ZERO"; rc=$?
[ "$rc" = 1 ] && ok "ⓑ 새 가지 제품 커밋 → 거부 rc1" || bad "ⓑ rc=$rc (기대 1)"
grep -q "range: $MB..$TIP" "$T/out" && ok "ⓑ 출력 range: <mb>..<tip>" || { bad "ⓑ range 줄 없음"; sed 's/^/    /' "$T/out"; }
grep -q 'gateway/b.py' "$T/out" && ok "ⓑ 출력에 gateway/b.py" || bad "ⓑ gateway/b.py 없음"
FT_PUSH_DA6_OK=abc run b "$TIP" "$ZERO"; rc=$?
[ "$rc" = 0 ] && grep -q "PUSH_GATE_BYPASS: FT_PUSH_DA6_OK=abc range=$MB..$TIP" "$T/out" \
  && ok "ⓑ 우회 FT_PUSH_DA6_OK → 통과 + BYPASS 기록" || { bad "ⓑ 우회 rc=$rc"; sed 's/^/    /' "$T/out"; }

# ⓒ 기존 가지(remote_sha 있음) — 문서만 → 통과 · 제품 포함 → 거부
clone c; commit_file c docs/z.md z; R1=$(git -C "$T/c" rev-parse HEAD)
commit_file c docs/w.md w; echo dirty >> "$T/c/gateway/a.py"
run c "$(git -C "$T/c" rev-parse HEAD)" "$R1"; rc=$?
[ "$rc" = 0 ] && ok "ⓒ 기존 가지 문서만 → 통과" || { bad "ⓒ 문서 rc=$rc"; sed 's/^/    /' "$T/out"; }
commit_file c gateway/c.py c; TIP=$(git -C "$T/c" rev-parse HEAD)
run c "$TIP" "$R1"; rc=$?
[ "$rc" = 1 ] && grep -q "range: $R1..$TIP" "$T/out" && ok "ⓒ 기존 가지 제품 포함 → 거부 range remote..local" \
  || { bad "ⓒ 제품 rc=$rc"; sed 's/^/    /' "$T/out"; }

# ⓓ origin/main 못 찾음 → 거부(조용한 통과 0) · diff 실패(remote sha 모름) → 거부
clone d; commit_file d docs/y.md y; git -C "$T/d" update-ref -d refs/remotes/origin/main
run d "$(git -C "$T/d" rev-parse HEAD)" "$ZERO"; rc=$?
[ "$rc" = 1 ] && grep -q 'merge-base origin/main) 못 구함 — 거부 유지' "$T/out" \
  && ok "ⓓ origin/main 없음 → 거부 rc1 + 사유" || { bad "ⓓ 기준 없음 rc=$rc"; sed 's/^/    /' "$T/out"; }
run d "$(git -C "$T/d" rev-parse HEAD)" 1111111111111111111111111111111111111111; rc=$?
[ "$rc" = 1 ] && grep -q 'diff 실패' "$T/out" && ok "ⓓ diff 실패(모르는 remote sha) → 거부 rc1" \
  || { bad "ⓓ diff 실패 rc=$rc"; sed 's/^/    /' "$T/out"; }

# ⓔ 현재 가지가 GATE_BRANCH 아님 → 검사 0
clone e feat/other; commit_file e gateway/e.py e
run e "$(git -C "$T/e" rev-parse HEAD)" "$ZERO"; rc=$?
[ "$rc" = 0 ] && [ ! -s "$T/out" ] && ok "ⓔ GATE_BRANCH 아님 → 검사 0" || bad "ⓔ rc=$rc"

echo "--- $([ "$fail" = 0 ] && echo ALL PASS || echo "FAIL $fail")"
[ "$fail" = 0 ]
