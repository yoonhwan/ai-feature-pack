#!/usr/bin/env bash
# test_nano_spawn_tier.sh — r286: ft-nano-spawn 모델 선택(티어 case + 기본 모델 블록)을 스크립트에서 꺼내 돌린다 — 세션·워크트리·명부 0.
#   impl 기본 = claude-sonnet-5-5[1m] · checker/tester sonnet 칸 = claude-sonnet-5-5[1m] · --tier search = opencode/deepseek-v4.1-flash-free · --agent opencode 기본 모델
#   + opencode 좌석 pid 기록 줄·검색 나노 발주 문단 실재(추적본·키트 둘 다).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
for SP in "$HERE/../bin/ft-nano-spawn.sh" "$HERE/../kit/fable-team/bin/ft-nano-spawn.sh"; do
  tag="$(basename "$(dirname "$(dirname "$SP")")")"
  _s="$(grep -n '^case "\$TIER" in' "$SP" | head -1 | cut -d: -f1)"; _e="$(awk -v s="${_s:-0}" 'NR>s && /^if \[ -z "\$MODEL" \]; then case/{f=1} f && /^fi$/{print NR; exit}' "$SP")"
  { [ -n "$_s" ] && [ -n "$_e" ] && sed -n "${_s},${_e}p" "$SP" && echo 'echo "$AGENT|$MODEL|$ROLE"'; } > "$T/sel.sh"
  [ -s "$T/sel.sh" ] && ok "$tag: 선택 블록 추출" || { bad "$tag: 선택 블록 추출 실패"; continue; }
  sel() { env -i PATH="$PATH" TIER="$1" AGENT="${2:-claude}" MODEL="${3:-}" FT_CMD_ENABLED=0 bash "$T/sel.sh" 2>&1; }
  r="$(sel '')"; [ "$r" = "claude|claude-sonnet-5-5[1m]|nano" ] && ok "$tag: 기본 impl = sonnet-5-5" || bad "$tag: 기본 → $r"
  r="$(sel impl)"; [ "$r" = "claude|claude-sonnet-5-5[1m]|impl" ] && ok "$tag: --tier impl = sonnet-5-5" || bad "$tag: impl → $r"
  r="$(sel checker:2)"; [ "$r" = "claude|claude-sonnet-5-5[1m]|checker" ] && ok "$tag: checker:2 = sonnet-5-5" || bad "$tag: checker:2 → $r"
  r="$(sel tester:3)"; [ "$r" = "claude|claude-sonnet-5-5[1m]|tester" ] && ok "$tag: tester:3 = sonnet-5-5" || bad "$tag: tester:3 → $r"
  r="$(sel search)"; [ "$r" = "opencode|opencode/deepseek-v4.1-flash-free|search" ] && ok "$tag: --tier search = opencode deepseek-v4.1-flash-free" || bad "$tag: search → $r"
  r="$(sel '' opencode)"; [ "$r" = "opencode|opencode/deepseek-v4.1-flash-free|nano" ] && ok "$tag: --agent opencode 모델 없음 → 기본(REJECT 0)" || bad "$tag: opencode 기본 → $r"
  r="$(sel '' opencode x/y)"; [ "$r" = "opencode|x/y|nano" ] && ok "$tag: --agent opencode --model 명시 우선" || bad "$tag: opencode 명시 → $r"
  r="$(sel '' gemini)"; case "$r" in *"REJECT --model 필수"*) ok "$tag: 표에 없는 에이전트 → REJECT";; *) bad "$tag: gemini → $r";; esac
  r="$(sel bogus)"; case "$r" in *"unknown --tier bogus"*search*) ok "$tag: 모르는 티어 → 안내에 search";; *) bad "$tag: bogus → $r";; esac
  grep -q 'ft-opencode-reap.sh" "$NAME" --wt "$WTDIR" --record --since "$_OC_SINCE"' "$SP" && ok "$tag: opencode 좌석 pid 기록 줄" || bad "$tag: pid 기록 줄 없음"
  grep -q '^\[ "\$TIER" != search \] || BODY="\$BODY ★검색 나노(opencode' "$SP" && ok "$tag: 검색 나노 발주 문단" || bad "$tag: 검색 나노 문단 없음"
done
cmp -s "$HERE/../bin/ft-nano-spawn.sh" "$HERE/../kit/fable-team/bin/ft-nano-spawn.sh" && ok "추적본 = 키트(cmp)" || bad "추적본 ≠ 키트"
echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
