#!/usr/bin/env bash
# test_nano_spawn_pack_wt_line_r1205.sh — 카드 r1205: ft-nano-spawn.sh pack_wt_line 판별 = 카드 첫 5줄 원장 줄
#   (nano-close r621·r688 과 같은 규칙 · 머리 `- 설치:` 줄 무관)
#   R1 원장 줄 + 설치: 있음 → 줄 있음 · R2 원장 줄 + 설치: 없음 → 줄 있음(지금 0 · r1197·r1204)
#   R3 원장 줄 없음 + 설치: 있음 → 0 · R4 원장 줄이 6번째 줄 뒤에만 → 0 · bin·kit cmp0
# 함수 본문만 추출해 부른다 — 실 리포·tmux·spawn·외부 호출 0 · 자기 재호출 0.
# 변이 확인: FT_R1205_SPAWN=<바꾼 사본> 으로 그 사본의 pack_wt_line 을 시험한다(cmp 칸은 건너뜀).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TRACKED="$HERE/../../harness/bin/ft-nano-spawn.sh"
KIT="$HERE/../../harness/kit/fable-team/bin/ft-nano-spawn.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

MARK='<!-- ledger: design/harness/GOAL-harness.md -->'
printf '# 인덱스: r1\n%s\n- 설치: 있음 — 팩 키트 1\n\n## 상태\n' "$MARK" > "$T/r1.md"
printf '# 인덱스: r2\n%s\n- 설치: 없음 — 시험만\n\n## 상태\n' "$MARK" > "$T/r2.md"
printf '# 인덱스: r3\n<!-- ledger: design/v65/GOAL-LEDGER-v65.md -->\n- 설치: 있음 — 팩 키트 1\n\n## 상태\n' > "$T/r3.md"
printf '# 인덱스: r4\n- 설치: 없음\n- a\n- b\n- c\n- d\n%s\n' "$MARK" > "$T/r4.md"

# check <label> <spawn 사본>
check() {
  local label="$1" f="$2" fn o
  fn="$(awk '/^pack_wt_line\(\) \{/,/^\}/' "$f")"
  [ -n "$fn" ] || { bad "$label pack_wt_line 함수 없음"; return; }
  eval "$fn"
  o="$(FT_PACK_ROOT=/x/pack pack_wt_line "$T/r1.md" s1 nano/s1)"
  case "$o" in *"팩 작업 폴더 = /x/pack/.worktrees/s1"*) ok "$label R1 원장 줄 + 설치: 있음 → 줄";; *) bad "$label R1 줄 없음: «${o}»";; esac
  o="$(FT_PACK_ROOT=/x/pack pack_wt_line "$T/r2.md" s2 nano/s2)"
  case "$o" in *"팩 작업 폴더 = /x/pack/.worktrees/s2"*"nano-close --wt /x/pack/.worktrees/s2 --branch nano/s2"*) ok "$label R2 원장 줄 + 설치: 없음 → 줄";; *) bad "$label R2 줄 없음: «${o}»";; esac
  o="$(FT_PACK_ROOT=/x/pack pack_wt_line "$T/r3.md" s3 nano/s3)"
  [ -z "$o" ] && ok "$label R3 원장 줄 없음(제품) → 0" || bad "$label R3 줄이 나옴: «${o}»"
  o="$(FT_PACK_ROOT=/x/pack pack_wt_line "$T/r4.md" s4 nano/s4)"
  [ -z "$o" ] && ok "$label R4 원장 줄 6번째 줄 뒤 → 0" || bad "$label R4 줄이 나옴: «${o}»"
  unset -f pack_wt_line
}

if [ -n "${FT_R1205_SPAWN:-}" ]; then
  check "변이" "$FT_R1205_SPAWN"
else
  check "추적본" "$TRACKED"
  check "키트" "$KIT"
  cmp -s "$TRACKED" "$KIT" && ok "bin·kit cmp0" || bad "bin·kit 내용 다름"
fi

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
