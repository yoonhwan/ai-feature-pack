#!/usr/bin/env bash
# test_goal_hook_adoption_archive.sh — R212: v65 커밋 훅의 «채택안 등재» 검사가 벽 ∪ 아카이브를 보는지.
# 임시 저장소 + --selftest 만 쓴다(실 리포 .git·공용 config 쓰기 0).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HOOK="$HERE/../../scripts/git-hooks/v65-goal-commit-msg.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$HOOK" && ok "bash -n" || bad "bash -n"
sh -n "$HOOK" && ok "sh -n" || bad "sh -n"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
EVID="닫는 증거 정본 문장 스무자 이상 들어간 줄입니다"
git_clean() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR \
  -u GIT_OBJECT_DIRECTORY -u GIT_CEILING_DIRECTORIES git "$@"; }

new_repo() {  # $1 = 디렉터리 이름
  local d="$T/$1"; mkdir -p "$d/design/v65/archive" && cd "$d" || exit 1
  git_clean init -q -b main . >/dev/null
  echo "$EVID" > design/v65/GOAL-LEDGER-v65.md
  printf '%s\n' "$d"
}
write_msg() {  # $1 = 채택안 경로 → $T/msg
  printf '[구현] 시험\n\n골좌표: M4 / 닫는 증거: %s\n채택안: %s\n' "$EVID" "$1" > "$T/msg"
}
run_hook() {  # stdout+stderr 를 $T/out 에 남기고 rc 반환 (훅은 임시 저장소 cwd 에서 root 를 잡는다)
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY \
    -u GIT_CEILING_DIRECTORIES sh "$HOOK" --selftest "$T/msg" worker/a.py > "$T/out" 2>&1
}

# ⓐ 벽에 있음 → 통과
new_repo a >/dev/null; echo "wall: ADOPT-a.md" > design/v65/DIRECTIVE-v65-wall.md
write_msg design/v65/ADOPT-a.md
run_hook && ok "ⓐ 벽에 있음 통과" || bad "ⓐ 벽에 있는데 거절"

# ⓑ 벽 없음·아카이브 1개에 있음 → 통과
new_repo b >/dev/null; echo "wall: other" > design/v65/DIRECTIVE-v65-wall.md
echo "closed: ADOPT-b.md" > design/v65/archive/DIRECTIVE-v65-wall-ledger-closed-20261015.md
write_msg design/v65/ADOPT-b.md
run_hook && ok "ⓑ 아카이브 1개 통과" || bad "ⓑ 아카이브에 있는데 거절"

# ⓒ 아카이브 2개 중 두 번째에만 있음 → 통과
new_repo c >/dev/null; echo "wall: other" > design/v65/DIRECTIVE-v65-wall.md
echo "closed: x" > design/v65/archive/DIRECTIVE-v65-wall-ledger-closed-20261001.md
echo "closed: ADOPT-c.md" > design/v65/archive/DIRECTIVE-v65-wall-ledger-closed-20261015.md
write_msg design/v65/ADOPT-c.md
run_hook && ok "ⓒ 아카이브 두 번째 통과" || bad "ⓒ 두 번째 아카이브에 있는데 거절"

# ⓓ 어디에도 없음 → 거절(미등재 · 원장 «벽 + 아카이브 2개»)
write_msg design/v65/ADOPT-none.md
if run_hook; then bad "ⓓ 어디에도 없는데 통과"
elif grep -q '미등재' "$T/out" && grep -q '벽 + 아카이브 2개' "$T/out"; then ok "ⓓ 미등재 거절"
else bad "ⓓ 거절 문구 불일치: $(cat "$T/out")"; fi

# ⓔ 벽 파일 자체 없음 → 거절(아카이브에 있어도)
new_repo e >/dev/null
echo "closed: ADOPT-e.md" > design/v65/archive/DIRECTIVE-v65-wall-ledger-closed-20261015.md
write_msg design/v65/ADOPT-e.md
if run_hook; then bad "ⓔ 벽 없는데 통과"
elif grep -q '벽 원장 파일이 없습니다' "$T/out"; then ok "ⓔ 벽 없음 거절"
else bad "ⓔ 거절 문구 불일치: $(cat "$T/out")"; fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "fail=$fail"
exit "$fail"
