#!/usr/bin/env bash
# test_nano_spawn_pi_effort_kind_r631.sh — r631: pi 나노 기본 effort 를 종류로 가른다(짧은 나노 low · 구현 나노 high).
#   short = --tier search·checker·tester 또는 --research · impl = 그 밖(--tier impl · 티어 없는 코드 나노) · 직접 적은 --effort 가 이긴다(explicit)
#   PLAN 줄 덧붙임 = « effort=<값>(<short|impl|explicit>[:<이유>]) serena=<…>»
#   시험 꼴 = test_nano_spawn_pi_effort_serena.sh 와 같다 — 블록 A(티어·effort)+블록 B(OPEN·serena·PLAN)를 꺼내 이어 돌린다. 실제 tmux·워크트리·pi 실행 0 · tmuxc 는 가짜.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

mkdir -p "$T/fake"
printf '%s\n' '#!/usr/bin/env bash' 'case "$1" in' '  help) echo "  --serena: --agent pi 전용(0.4.3)" ;;' '  open) echo "FAKE tmuxc open $*" ;;' 'esac' 'exit 0' > "$T/fake/tmuxc"
chmod +x "$T/fake/tmuxc"

for SP in "$HERE/../bin/ft-nano-spawn.sh" "$HERE/../kit/fable-team/bin/ft-nano-spawn.sh"; do
  tag="$(basename "$(cd -- "$(dirname -- "$SP")/../.." && pwd)")"
  _s="$(grep -n '^_A0="\$AGENT"' "$SP" | head -1 | cut -d: -f1)"
  _e="$(awk -v s="${_s:-0}" 'NR>s && /^if \[ -z "\$MODEL" \]; then case/{f=1} f && /^fi$/{print NR; exit}' "$SP")"
  _bs="$(grep -n '^OPEN=(tmuxc open' "$SP" | head -1 | cut -d: -f1)"
  _be="$(awk -v s="${_bs:-0}" 'NR>=s && /^_PLANX=/{print NR; exit}' "$SP")"
  { [ -n "$_s" ] && [ -n "$_e" ] && [ -n "$_bs" ] && [ -n "$_be" ] \
    && sed -n "${_s},${_e}p" "$SP" && sed -n "${_bs},${_be}p" "$SP" \
    && echo 'echo "EFFORT=$EFFORT"; echo "PLANX=[$_PLANX]"; echo "OPEN=${OPEN[*]}"'; } > "$T/ab.sh"
  [ -s "$T/ab.sh" ] && ok "$tag: 블록 A+B 추출" || { bad "$tag: 블록 A+B 추출 실패"; continue; }
  # run TIER AGENT AGENT_SET EFFORT EFFORT_SET RESEARCH [env…] — 스크립트 13·15행 뒤 상태를 흉내낸다(AGENT_SET=1 = --agent 직접)
  run() { local ti="$1" ag="$2" as="$3" ef="$4" es="$5" rs="$6"; shift 6
    env -i PATH="$T/fake:$PATH" WTDIR=/tmp/wt NAME=n#0 MODEL= FAST= TIER="$ti" AGENT="$ag" AGENT_SET="$as" EFFORT="$ef" EFFORT_SET="$es" RESEARCH="$rs" FT_CMD_ENABLED=0 "$@" bash "$T/ab.sh" 2>&1; }
  has() { case "$2" in *"$3"*) ok "$tag: $1";; *) bad "$tag: $1 → $(printf '%s' "$2" | tr '\n' ' ')";; esac; }
  hasnt() { case "$2" in *"$3"*) bad "$tag: $1 → $(printf '%s' "$2" | tr '\n' ' ')";; *) ok "$tag: $1";; esac; }

  # ⓐ(실패 시험 먼저) --agent pi --tier impl → high(impl:tier=impl) — 고치기 전 = low
  r="$(run impl pi 1 high 0 0)"
  has "ⓐ --agent pi --tier impl effort=high" "$r" "EFFORT=high"
  has "ⓐ PLAN effort=high(impl:tier=impl)" "$r" "PLANX=[ effort=high(impl:tier=impl) serena=off(은퇴 10-22)]"
  has "ⓐ tmuxc --effort high" "$r" "--effort high"
  # ⓑ --agent pi 티어 없음(코드 나노) → high(impl:code-nano)
  r="$(run '' pi 1 high 0 0)"
  has "ⓑ --agent pi 코드 나노 PLAN effort=high(impl:code-nano)" "$r" "PLANX=[ effort=high(impl:code-nano) serena=off(은퇴 10-22)]"
  # ⓒ 짧은 나노 = low
  r="$(run search pi 1 high 0 0)";  has "ⓒ --agent pi --tier search = low(short:tier=search)" "$r" "PLANX=[ effort=low(short:tier=search) serena=off(은퇴 10-22)]"
  r="$(run search pi 0 high 0 0)";  has "ⓒ --tier search(기본 pi) = low(short:tier=search)" "$r" "effort=low(short:tier=search)"
  r="$(run '' pi 1 high 0 1)";      has "ⓒ --agent pi --research = low(short:research)" "$r" "PLANX=[ effort=low(short:research) serena=off(은퇴 10-22)]"
  r="$(run checker pi 1 high 0 0)"; has "ⓒ --agent pi --tier checker = low(short:tier=checker)" "$r" "effort=low(short:tier=checker)"
  r="$(run tester:2 pi 1 high 0 0)"; has "ⓒ --agent pi --tier tester:2 = low(short:tier=tester)" "$r" "effort=low(short:tier=tester)"
  # r1107: Serena 은퇴 — checker·tester pi 나노도 serena off(짧은 effort 와 별개)
  has "ⓒ checker·tester pi serena=off(은퇴 10-22)" "$r" "serena=off(은퇴 10-22)]"
  # ⓓ 직접 적은 --effort 가 이긴다
  r="$(run impl pi 1 low 1 0)";     has "ⓓ --tier impl --effort low = low(explicit)" "$r" "PLANX=[ effort=low(explicit) serena=off(은퇴 10-22)]"
  r="$(run search pi 1 high 1 0)";  has "ⓓ --tier search --effort high = high(explicit)" "$r" "effort=high(explicit)"
  # ⓔ env 손잡이 — 새 이름 2개 · 옛 FT_PI_EFFORT 는 두 갈래 모두 + stderr WARN 1줄
  r="$(run search pi 1 high 0 0 FT_PI_EFFORT_SHORT=medium)"; has "ⓔ FT_PI_EFFORT_SHORT=medium → short 갈래" "$r" "effort=medium(short:tier=search)"
  r="$(run '' pi 1 high 0 0 FT_PI_EFFORT_SHORT=medium)";     has "ⓔ FT_PI_EFFORT_SHORT 는 impl 갈래 불변" "$r" "effort=high(impl:code-nano)"
  r="$(run '' pi 1 high 0 0 FT_PI_EFFORT_IMPL=low)";         has "ⓔ FT_PI_EFFORT_IMPL=low → impl 갈래" "$r" "effort=low(impl:code-nano)"
  r="$(run search pi 1 high 0 0 FT_PI_EFFORT_IMPL=low)";     has "ⓔ FT_PI_EFFORT_IMPL 은 short 갈래 불변" "$r" "effort=low(short:tier=search)"
  r="$(run '' pi 1 high 0 0 FT_PI_EFFORT=medium)";           has "ⓔ 옛 FT_PI_EFFORT → impl 갈래" "$r" "effort=medium(impl:code-nano)"
  has "ⓔ 옛 FT_PI_EFFORT stderr WARN" "$r" "WARN FT_PI_EFFORT 는 옛 이름"
  [ "$(printf '%s\n' "$r" | grep -c 'WARN FT_PI_EFFORT')" = 1 ] && ok "$tag: ⓔ WARN 1줄" || bad "$tag: ⓔ WARN 줄 수 ≠ 1"
  r="$(run search pi 1 high 0 0 FT_PI_EFFORT=medium)";       has "ⓔ 옛 FT_PI_EFFORT → short 갈래" "$r" "effort=medium(short:tier=search)"
  r="$(run search pi 1 high 0 0 FT_PI_EFFORT=medium FT_PI_EFFORT_SHORT=low)"; has "ⓔ 새 이름이 옛 이름보다 이긴다" "$r" "effort=low(short:tier=search)"
  r="$(run impl pi 1 low 1 0 FT_PI_EFFORT=medium)";          hasnt "ⓔ --effort 직접이면 옛 이름 WARN 0" "$r" "WARN FT_PI_EFFORT"
  r="$(run '' pi 1 high 0 0)";                               hasnt "ⓔ env 없으면 WARN 0" "$r" "WARN"
  # ⓕ pi 아닌 나노 — effort·PLAN 덧붙임 불변
  r="$(run '' claude 0 high 0 0)";     has "ⓕ claude effort=high" "$r" "EFFORT=high"; has "ⓕ claude PLANX 빈칸" "$r" "PLANX=[]"
  r="$(run '' claude 1 low 1 0)";      has "ⓕ claude --effort low 그대로" "$r" "EFFORT=low"
  r="$(run checker:1 claude 0 high 0 0)"; has "ⓕ codex checker:1 effort=high" "$r" "EFFORT=high"; has "ⓕ codex PLANX 빈칸" "$r" "PLANX=[]"
  r="$(run impl claude 0 high 0 0 FT_PI_EFFORT_IMPL=low)"; has "ⓕ claude --tier impl 은 pi env 무시" "$r" "EFFORT=high"
  r="$(run '' cmd 1 high 0 0 FT_PI_EFFORT=low)"; has "ⓕ cmd 는 옛 pi env 무시" "$r" "EFFORT=high"; hasnt "ⓕ cmd WARN 0" "$r" "WARN"
done
cmp -s "$HERE/../bin/ft-nano-spawn.sh" "$HERE/../kit/fable-team/bin/ft-nano-spawn.sh" && ok "추적본 = 키트(cmp)" || bad "추적본 ≠ 키트"
echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
