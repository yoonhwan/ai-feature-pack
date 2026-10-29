#!/usr/bin/env bash
# test_nano_spawn_pi_effort_serena.sh — r556: ft-nano-spawn.sh 의 pi 나노 두 칸.
#   ①pi 나노 기본 effort = low(직접 적은 --effort 만 이긴다 · FT_PI_EFFORT=high 로 되돌림) ②(r1107) Serena 은퇴 — 어떤 나노에도 --serena 0 + BOOT 1번 안내문
#   시험 꼴 = 기존 test_nano_spawn_tier.sh 와 같다 — 스크립트에서 블록을 꺼내 돌린다. 실제 tmux·워크트리·pi 실행 0 · tmuxc 는 가짜 2벌.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

# 가짜 tmuxc 2벌 — --serena 를 아는 판(0.4.3+) / 모르는 판(옛 설치)
mkdir -p "$T/new" "$T/old"
printf '%s\n' '#!/usr/bin/env bash' 'case "$1" in' '  help) echo "  --serena: --agent pi 전용(0.4.3)" ;;' '  open) echo "FAKE tmuxc open $*" ;;' 'esac' 'exit 0' > "$T/new/tmuxc"
printf '%s\n' '#!/usr/bin/env bash' 'case "$1" in' '  help) echo "  --effort E / --fast on|off" ;;' '  open) echo "FAKE tmuxc open $*" ;;' 'esac' 'exit 0' > "$T/old/tmuxc"
chmod +x "$T/new/tmuxc" "$T/old/tmuxc"

for SP in "$HERE/../bin/ft-nano-spawn.sh" "$HERE/../kit/fable-team/bin/ft-nano-spawn.sh"; do
  tag="$(basename "$(cd -- "$(dirname -- "$SP")/../.." && pwd)")"
  # ── 블록 A: 티어·명시 --agent 결정 + pi 기본 effort(low) + 에이전트별 기본 모델 ──
  _s="$(grep -n '^_A0="\$AGENT"' "$SP" | head -1 | cut -d: -f1)"
  _e="$(awk -v s="${_s:-0}" 'NR>s && /^if \[ -z "\$MODEL" \]; then case/{f=1} f && /^fi$/{print NR; exit}' "$SP")"
  { [ -n "$_s" ] && [ -n "$_e" ] && sed -n "${_s},${_e}p" "$SP" && echo 'echo "$AGENT|$MODEL|$ROLE|$EFFORT"'; } > "$T/a.sh"
  [ -s "$T/a.sh" ] && ok "$tag: 블록 A 추출" || { bad "$tag: 블록 A 추출 실패"; continue; }
  # AGENT_SET=1 이면 호출자가 이미 --agent/--effort 로 넣은 값(스크립트 13·15행 뒤 상태)을 흉내낸다
  pick() { env -i PATH="$PATH" TIER="${1:-}" AGENT="${2:-claude}" AGENT_SET="${3:-0}" MODEL="${4:-}" EFFORT="${5:-high}" EFFORT_SET="${6:-0}" FT_CMD_ENABLED=0 ${7:+FT_PI_EFFORT="$7"} bash "$T/a.sh" 2>&1; }

  # ⓐ --agent pi 티어 없음 = 코드 나노 → high (r631 개정: 짧은 나노만 low · 종류별 전수 = test_nano_spawn_pi_effort_kind_r631.sh)
  r="$(pick '' pi 1)"; [ "$r" = "pi|opengateway/deepseek/deepseek-v4.1-flash-ultrafast|nano|high" ] && ok "$tag: ⓐ --agent pi 코드 나노 effort=high(r631)" || bad "$tag: ⓐ --agent pi → $r"
  # ⓑ --effort high 를 직접 적으면 이긴다
  r="$(pick '' pi 1 '' high 1)"; [ "$r" = "pi|opengateway/deepseek/deepseek-v4.1-flash-ultrafast|nano|high" ] && ok "$tag: ⓑ --agent pi --effort high = high" || bad "$tag: ⓑ → $r"
  # ⓒ --tier search(pi 기본 에이전트) 도 low — 티어가 넣은 high 를 pi 가 덮는다
  r="$(pick search pi 0)"; [ "$r" = "pi|opengateway/deepseek/deepseek-v4.1-flash-ultrafast|search|low" ] && ok "$tag: ⓒ --tier search(pi) effort=low" || bad "$tag: ⓒ search → $r"
  # ⓗ 되돌림 손잡이 = FT_PI_EFFORT=high
  r="$(pick '' pi 1 '' high 0 high 2>/dev/null | tail -1)"; [ "$r" = "pi|opengateway/deepseek/deepseek-v4.1-flash-ultrafast|nano|high" ] && ok "$tag: ⓗ FT_PI_EFFORT=high → high" || bad "$tag: ⓗ → $r"
  # 다른 에이전트 effort 불변(회귀 0)
  r="$(pick '')"; case "$r" in claude\|*'|high') ok "$tag: claude 기본 effort=high 불변";; *) bad "$tag: claude → $r";; esac
  r="$(pick checker:1 claude 0)"; case "$r" in codex\|*'|high') ok "$tag: codex checker:1 effort=high 불변";; *) bad "$tag: codex → $r";; esac
  r="$(pick impl )"; case "$r" in claude\|*'|high') ok "$tag: --tier impl effort=high 불변";; *) bad "$tag: impl → $r";; esac

  # ── 블록 B: OPEN 배열 + pi --serena + PLAN 덧붙임 ──
  _bs="$(grep -n '^OPEN=(tmuxc open' "$SP" | head -1 | cut -d: -f1)"
  _be="$(awk -v s="${_bs:-0}" 'NR>=s && /^_PLANX=/{print NR; exit}' "$SP")"
  { [ -n "$_bs" ] && [ -n "$_be" ] && grep '^pi_kind() ' "$SP" && sed -n "${_bs},${_be}p" "$SP" && echo 'echo "SERENA=$SERENA"; echo "PLANX=[$_PLANX]"; echo "OPEN=${OPEN[*]}"'; } > "$T/b.sh"
  [ -s "$T/b.sh" ] && ok "$tag: 블록 B 추출" || { bad "$tag: 블록 B 추출 실패"; continue; }
  op() { env -i PATH="$1:$ORIG_PATH" WTDIR=/tmp/wt NAME=n#0 AGENT="${2:-claude}" MODEL=m EFFORT="${3:-high}" EFFORT_WHY=impl:code-nano TIER="${4:-}" RESEARCH="${5:-0}" ${6:+FT_PI_SERENA="$6"} bash "$T/b.sh" 2>&1; }
  ORIG_PATH="$PATH"

  # ★r1107★ Serena 은퇴(10-22) — pi 나노도 늘 off · --serena 0 · FT_PI_SERENA 무시 · tmuxc 판과 무관(REJECT 0)
  nos() { case "$2" in *"--serena"*) bad "$tag: $1 OPEN 에 --serena";; *) ok "$tag: $1 OPEN 에 --serena 없음";; esac; }
  # ⓐ R1 pi 코드 나노 · FT_PI_SERENA 미설정 → off · PLAN serena=off(은퇴 10-22)
  r="$(op "$T/new" pi)"; nos "ⓐR1 코드 나노" "$r"
  case "$r" in *"PLANX=[ effort=high(impl:code-nano) serena=off(은퇴 10-22)]"*) ok "$tag: ⓐR1 PLAN 줄 effort+serena=off(은퇴 10-22)";; *) bad "$tag: ⓐR1 PLANX → $r";; esac
  # ⓐ R2 FT_PI_SERENA=1 이어도 off
  r="$(op "$T/new" pi high '' 0 1)"; nos "ⓐR2 FT_PI_SERENA=1" "$r"
  case "$r" in *"SERENA=off(은퇴 10-22)"*) ok "$tag: ⓐR2 FT_PI_SERENA=1 → off";; *) bad "$tag: ⓐR2 → $r";; esac
  # ⓑ R3 --serena 모르는 tmuxc → REJECT 0 · OPEN 까지 간다
  r="$(op "$T/old" pi)"; case "$r" in *"REJECT"*) bad "$tag: ⓑR3 옛 tmuxc 인데 REJECT → $r";; *"OPEN="*) ok "$tag: ⓑR3 옛 tmuxc REJECT 0";; *) bad "$tag: ⓑR3 → $r";; esac
  # ⓒ R4 --research · --tier search(pi) 도 off
  r="$(op "$T/new" pi high '' 1)"; nos "ⓒR4 research" "$r"
  case "$r" in *"SERENA=off(은퇴 10-22)"*) ok "$tag: ⓒR4 research → off";; *) bad "$tag: ⓒR4 → $r";; esac
  r="$(op "$T/new" pi low search)"; nos "ⓒR4 tier=search" "$r"
  # ⓖ claude·codex·cmd 출력 불변 — _PLANX 가 비고 --serena 가 안 붙는다
  for a in claude codex cmd; do
    r="$(op "$T/new" "$a")"; case "$r" in *"PLANX=[]"*) ok "$tag: ⓖ $a PLANX 빈칸";; *) bad "$tag: ⓖ $a PLANX → $r";; esac
    case "$r" in *"--serena"*|*"SERENA=on"*) bad "$tag: ⓖ $a 에 --serena";; *) ok "$tag: ⓖ $a --serena 없음";; esac
  done
done
# ⓖ 원문 대조: base(고치기 전) PLAN echo 줄 + «$_PLANX» 1개 글자만 다르다(_PLANX 가 비면 출력 문자 단위 동일)
#   base 줄을 시험에 그대로 박아 둔다(git 에 의존하지 않는다 — rebase 뒤 HEAD 가 내 커밋이 되어도 같은 값)
BASE_LINE='echo "PLAN seat=$NAME agent=$AGENT model=$MODEL$_VIA${TIER:+ tier=$TIER}${FAST:+ fast=$FAST} wt=$WTDIR branch=$BRANCH base=$BASE_BRANCH index=$IDX_REL"'
WANT_LINE="${BASE_LINE%\"}\$_PLANX\""
NEW_PLAN="$(grep -m1 '^echo "PLAN ' "$HERE/../../harness/kit/fable-team/bin/ft-nano-spawn.sh")"
[ "$WANT_LINE" = "$NEW_PLAN" ] && ok "ⓖ PLAN echo 줄 = base 글자 + \$_PLANX 1개" || bad "ⓖ PLAN echo 줄이 base 와 다르다 (want=[$WANT_LINE] new=[$NEW_PLAN])"
cmp -s "$HERE/../bin/ft-nano-spawn.sh" "$HERE/../kit/fable-team/bin/ft-nano-spawn.sh" && ok "ⓔ 추적본 = 키트(cmp)" || bad "ⓔ 추적본 ≠ 키트"
# ⓓ 안내문 COMM-GUIDE-BOOT.md 1번 = Serena 활성화 지시 0(은퇴 문장) · 2번 첫 보고 칸 = ci
BOOT="$HERE/../../../tmuxc/claude-code/skills/tmuxc/COMM-GUIDE-BOOT.md"
b1="$(grep -m1 '^1\. ' "$BOOT")"; b2="$(grep -m1 '^2\. ' "$BOOT")"
case "$b1" in *initial_instructions*|*activate_project*|'') bad "ⓓ BOOT 1번에 Serena 활성화 지시 → [$b1]";; *) ok "ⓓ BOOT 1번 Serena 활성화 지시 0";; esac
case "$b2" in *"Serena 가부"*|'') bad "ⓓ BOOT 2번 첫 보고 칸 Serena 가부";; *"ci 가부"*) ok "ⓓ BOOT 2번 첫 보고 칸 = ci 가부";; *) bad "ⓓ BOOT 2번 → [$b2]";; esac
echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
