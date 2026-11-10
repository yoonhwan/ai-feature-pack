#!/usr/bin/env bash
# test_nano_spawn_tier.sh — r286: ft-nano-spawn 모델 선택(티어 case + 기본 모델 블록)을 스크립트에서 꺼내 돌린다 — 세션·워크트리·명부 0.
#   impl 기본 = claude-sonnet-5-5[1m] · checker/tester sonnet 칸 = claude-sonnet-5-5[1m] · --tier search = opencode/deepseek-v4.1-flash-free · --agent opencode 기본 모델
#   + opencode 좌석 pid 기록 줄·검색 나노 발주 문단 실재(추적본·키트 둘 다).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
SELENV=""
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
for SP in "$HERE/../bin/ft-nano-spawn.sh" "$HERE/../kit/fable-team/bin/ft-nano-spawn.sh"; do
  tag="$(basename "$(dirname "$(dirname "$SP")")")"
  _s="$(grep -n '^_A0="\$AGENT"' "$SP" | head -1 | cut -d: -f1)"; _e="$(awk -v s="${_s:-0}" 'NR>s && /^if \[ -z "\$MODEL" \]; then case/{f=1} f && /^fi$/{print NR; exit}' "$SP")"
  { [ -n "$_s" ] && [ -n "$_e" ] && sed -n "${_s},${_e}p" "$SP" && echo 'echo "$AGENT|$MODEL|$ROLE"'; } > "$T/sel.sh"
  [ -s "$T/sel.sh" ] && ok "$tag: 선택 블록 추출" || { bad "$tag: 선택 블록 추출 실패"; continue; }
  sel() { env -i PATH="$PATH" TIER="$1" AGENT="${2:-claude}" MODEL="${3:-}" AGENT_SET="${4:-0}" FT_CMD_ENABLED=0 $SELENV bash "$T/sel.sh" 2>&1; }
  r="$(sel '')"; [ "$r" = "claude|claude-sonnet-5-5[1m]|nano" ] && ok "$tag: 기본 impl = sonnet-5-5" || bad "$tag: 기본 → $r"
  r="$(sel impl)"; [ "$r" = "claude|claude-sonnet-5-5[1m]|impl" ] && ok "$tag: --tier impl = sonnet-5-5" || bad "$tag: impl → $r"
  r="$(sel checker:2)"; [ "$r" = "claude|claude-sonnet-5-5[1m]|checker" ] && ok "$tag: checker:2 = sonnet-5-5" || bad "$tag: checker:2 → $r"
  r="$(sel tester:3)"; [ "$r" = "claude|claude-sonnet-5-5[1m]|tester" ] && ok "$tag: tester:3 = sonnet-5-5" || bad "$tag: tester:3 → $r"
  # 2026-10-20 일반화(오빠 «ft-nano-spawn.sh 일반화 업그레이드» · chatbot #120064: --agent pi --tier search 가 opencode 로 열림)
  #   ①--tier search 기본 에이전트 = FT_SEARCH_AGENT(기본 pi — opencode 무료 경로는 이 IP 에서 차단) ②--agent 를 명시하면 tier 가 에이전트·모델·effort 를 덮어쓰지 않는다
  r="$(sel search)"; [ "$r" = "pi|opengateway/deepseek/deepseek-v4.1-flash-ultrafast|search" ] && ok "$tag: --tier search 기본 = pi deepseek flash" || bad "$tag: search 기본 → $r"
  r="$(SELENV="FT_SEARCH_AGENT=opencode" sel search)"; [ "$r" = "opencode|opencode/deepseek-v4.1-flash-free|search" ] && ok "$tag: FT_SEARCH_AGENT=opencode 로 되돌림" || bad "$tag: search+opencode env → $r"
  r="$(sel search pi '' 1)"; [ "$r" = "pi|opengateway/deepseek/deepseek-v4.1-flash-ultrafast|search" ] && ok "$tag: --agent pi --tier search = pi" || bad "$tag: agent pi + search → $r"
  r="$(sel search opencode '' 1)"; [ "$r" = "opencode|opencode/deepseek-v4.1-flash-free|search" ] && ok "$tag: --agent opencode --tier search = opencode(명시 우선)" || bad "$tag: agent opencode + search → $r"
  r="$(sel search claude '' 1)"; [ "$r" = "claude|claude-sonnet-5-5[1m]|search" ] && ok "$tag: --agent claude --tier search = claude(명시 우선)" || bad "$tag: agent claude + search → $r"
  r="$(sel search pi x/y 1)"; [ "$r" = "pi|x/y|search" ] && ok "$tag: --agent pi --model 명시 우선" || bad "$tag: pi 명시 모델 → $r"
  r="$(sel checker:1 pi '' 1)"; [ "$r" = "pi|opengateway/deepseek/deepseek-v4.1-flash-ultrafast|checker" ] && ok "$tag: --agent pi --tier checker:1 = pi(tier 가 codex 로 덮지 않음)" || bad "$tag: agent pi + checker:1 → $r"
  r="$(sel impl:3 pi '' 1)"; [ "$r" = "pi|opengateway/deepseek/deepseek-v4.1-flash-ultrafast|impl" ] && ok "$tag: --agent pi --tier impl:3 = pi" || bad "$tag: agent pi + impl:3 → $r"
  r="$(sel bogus pi '' 1)"; case "$r" in *"unknown --tier bogus"*) ok "$tag: 명시 에이전트여도 모르는 티어는 거절";; *) bad "$tag: agent pi + bogus → $r";; esac
  r="$(sel '' opencode)"; [ "$r" = "opencode|opencode/deepseek-v4.1-flash-free|nano" ] && ok "$tag: --agent opencode 모델 없음 → 기본(REJECT 0)" || bad "$tag: opencode 기본 → $r"
  r="$(sel '' opencode x/y)"; [ "$r" = "opencode|x/y|nano" ] && ok "$tag: --agent opencode --model 명시 우선" || bad "$tag: opencode 명시 → $r"
  r="$(sel '' gemini)"; case "$r" in *"REJECT --model 필수"*) ok "$tag: 표에 없는 에이전트 → REJECT";; *) bad "$tag: gemini → $r";; esac
  r="$(sel bogus)"; case "$r" in *"unknown --tier bogus"*search*) ok "$tag: 모르는 티어 → 안내에 search";; *) bad "$tag: bogus → $r";; esac
  grep -q 'ft-opencode-reap.sh" "$NAME" --wt "$WTDIR" --record --since "$_OC_SINCE"' "$SP" && ok "$tag: opencode 좌석 pid 기록 줄" || bad "$tag: pid 기록 줄 없음"
  grep -q '^\[ "\$TIER" != search \] || BODY="\$BODY ★검색 나노(\$AGENT' "$SP" && ok "$tag: 검색 나노 발주 문단(에이전트 이름)" || bad "$tag: 검색 나노 문단 없음"
  head -3 "$SP" | grep -q 'claude|codex|cmd|opencode|pi' && ok "$tag: 머리 usage 에 pi" || bad "$tag: 머리 usage 에 pi 없음"
done
cmp -s "$HERE/../bin/ft-nano-spawn.sh" "$HERE/../kit/fable-team/bin/ft-nano-spawn.sh" && ok "추적본 = 키트(cmp)" || bad "추적본 ≠ 키트"
echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
