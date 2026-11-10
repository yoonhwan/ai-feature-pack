#!/usr/bin/env bash
# test_nano_spawn_default_pi_r1385.sh — r1385: ft-nano-spawn 기본 에이전트 = pi (오빠 10-22 «pi = 모든 팀 기본» · 10-26 «pi deepseek 먼저 · 아니면 sonnet-5-5 · Opus 금지»)
#   N1 인자 없음 = pi/FT_PI_MODEL · N2 --agent claude 사유 없음 REJECT · N3 사유 있으면 통과 · N4 --tier 로 우회 0 · N5 --agent codex REJECT
#   N6 pi·cmd·opencode(deepseek 계열)는 사유 0 · N7 fable = R149 판정 1641 이 먼저 · N8 FT_NANO_DEFAULT_AGENT 손잡이로도 게이트 유지
#   + 티어 표(:1 = pi · :2·:3 = sonnet-5-5 · codex luna 칸 삭제) · 게이트가 부작용(worktree·tmux·명부·카드) «전» 인지 = 줄 대조
#   시험 꼴 = test_nano_spawn_tier.sh 와 같다(블록 추출 · 실 tmux·워크트리·명부·카드 쓰기 0 · 송신 0)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
mkdir -p "$T/bin"; ln -s "$HERE/../bin/ft_raised.py" "$T/bin/ft_raised.py"   # 게이트가 부르는 판정기만 이 자리에 둔다(계정·자원 문지기 = 이 시험 범위 밖)

for SP in "$HERE/../bin/ft-nano-spawn.sh" "$HERE/../kit/fable-team/bin/ft-nano-spawn.sh"; do
  tag="$(basename "$(cd -- "$(dirname -- "$SP")/../.." && pwd)")"
  DEF="$(grep -m1 '^AGENT=' "$SP")"
  _s="$(grep -n '^_A0="\$AGENT"' "$SP" | head -1 | cut -d: -f1)"
  _e="$(awk -v s="${_s:-0}" 'NR>s && /^if \[ -z "\$MODEL" \]; then case/{f=1} f && /^fi$/{print NR; exit}' "$SP")"
  sed -n "${_s:-0},${_e:-0}p" "$SP" > "$T/blockA.sh" 2>/dev/null
  awk '/ft_raised\.py. is-raised/{f=1} f && /^# R387 --research/{exit} f{print}' "$SP" > "$T/blockG.sh"
  awk '/^_A0="\$AGENT"/{f=1} f{print} f && /^esac$/{exit}' "$SP" > "$T/blockT.sh"
  { [ -s "$T/blockA.sh" ] && [ -s "$T/blockG.sh" ] && [ -s "$T/blockT.sh" ]; } && ok "$tag: 블록 추출(기본·티어/모델·사유 게이트)" || { bad "$tag: 블록 추출 실패"; continue; }
  case "$DEF" in *'${FT_NANO_DEFAULT_AGENT:-pi}'*) ok "$tag: 기본 AGENT = \${FT_NANO_DEFAULT_AGENT:-pi}";; *) bad "$tag: 기본 AGENT 줄 → $DEF";; esac

  # run <env 줄(export K=V; … 또는 빈)> <prelude(bash 줄)> — 스크립트 15행 상태를 흉내낸다(prelude = --agent/--model/--tier/--raise 파싱 결과)
  #   env 명령 뒤에는 «글자» 만 둔다(env -i PATH=.. HERE=.. bash ..) — 변수 펼침이 비면 env 가 환경을 출력해 판정기가 명령을 못 정한다(r1385 반송 260155).
  run() { local envs="$1" pre="$2"
    { printf '%s\n' "$envs"; printf '%s\n' "$DEF"; echo '_cmd_on="${FT_CMD_ENABLED:-0}"'; printf '%s\n' "$pre"
      cat "$T/blockA.sh" "$T/blockG.sh"; echo 'echo "RESULT agent=$AGENT model=$MODEL role=$ROLE"'; } > "$T/case.sh"
    env -i PATH="$PATH" HERE="$T/bin" bash "$T/case.sh" 2>&1; }
  has()   { case "$2" in *"$3"*) ok "$tag: $1";; *) bad "$tag: $1 → $(printf '%s' "$2" | tr '\n' ' ')";; esac; }
  hasnt() { case "$2" in *"$3"*) bad "$tag: $1 → $(printf '%s' "$2" | tr '\n' ' ')";; *) ok "$tag: $1";; esac; }
  rc_is() { [ "$2" = "$3" ] && ok "$tag: $1" || bad "$tag: $1 → rc=$2 (기대 $3)"; }

  # N1 인자 없음 → pi + FT_PI_MODEL 기본
  r="$(run '' '')"; rc=$?; rc_is "N1 인자 없음 rc0" "$rc" 0
  has "N1 기본 = pi/FT_PI_MODEL" "$r" "RESULT agent=pi model=opengateway/deepseek/deepseek-v4.1-flash-ultrafast"
  hasnt "N1 사유 요구 없음" "$r" "REJECT"
  # N2 --agent claude 사유 없음 → REJECT rc1
  r="$(run '' 'AGENT="claude"; AGENT_SET=1')"; rc=$?; rc_is "N2 --agent claude 사유 없음 rc1" "$rc" 1
  has "N2 REJECT 문구" "$r" 'REJECT 나노 기본 = pi — claude/claude-sonnet-5-5[1m] 은 --raise "<사유>" 필수(오빠 10-22·10-26 · r1385)'
  # N3 --agent claude --raise "긴 리팩토링" → 통과(+ 명부 raised 기록 줄 실재)
  r="$(run '' 'AGENT="claude"; AGENT_SET=1; RAISE="긴 리팩토링"')"; rc=$?; rc_is "N3 사유 있으면 rc0" "$rc" 0
  has "N3 claude 열림" "$r" "RESULT agent=claude model=claude-sonnet-5-5[1m]"
  grep -q 'd\[name\]\["raised"\] = collections.OrderedDict' "$SP" && ok "$tag: N3 명부 raised{reason,…} 기록 줄 실재" || bad "$tag: N3 명부 raised 기록 줄 없음"
  # N4 --tier impl:2 로 우회 0 → claude 로 풀린 뒤 REJECT
  r="$(run '' 'TIER="impl:2"')"; rc=$?; rc_is "N4 --tier impl:2 우회 rc1" "$rc" 1
  has "N4 티어가 claude 로 풀린 뒤 REJECT" "$r" "REJECT 나노 기본 = pi — claude/claude-sonnet-5-5[1m]"
  r="$(run '' 'TIER="impl:2"; RAISE="리팩토링"')"; rc=$?; rc_is "N4 사유 있으면 --tier impl:2 rc0" "$rc" 0
  has "N4 impl:2 = sonnet-5-5" "$r" "RESULT agent=claude model=claude-sonnet-5-5[1m] role=impl"
  # N5 --agent codex 사유 없음 → REJECT
  r="$(run '' 'AGENT="codex"; AGENT_SET=1')"; rc=$?; rc_is "N5 --agent codex 사유 없음 rc1" "$rc" 1
  has "N5 codex REJECT 문구" "$r" "REJECT 나노 기본 = pi — codex/gpt-6-luna"
  # N6 deepseek 계열은 사유 0
  r="$(run '' 'AGENT="pi"; AGENT_SET=1')"; rc=$?; { [ "$rc" = 0 ] && has "N6 --agent pi 사유 0" "$r" "RESULT agent=pi"; } || bad "$tag: N6 --agent pi → rc=$rc"
  r="$(run '' 'TIER="search"')"; rc=$?; { [ "$rc" = 0 ] && has "N6 --tier search 사유 0" "$r" "RESULT agent=pi"; } || bad "$tag: N6 --tier search → rc=$rc"
  r="$(run '' 'AGENT="opencode"; AGENT_SET=1')"; rc=$?; { [ "$rc" = 0 ] && has "N6 --agent opencode 사유 0" "$r" "RESULT agent=opencode"; } || bad "$tag: N6 opencode → rc=$rc"
  r="$(run '' 'AGENT="cmd"; AGENT_SET=1')"; rc=$?; { [ "$rc" = 0 ] && has "N6 --agent cmd 사유 0" "$r" "RESULT agent=cmd"; } || bad "$tag: N6 cmd → rc=$rc"
  # N7 fable = R149(판정 1641) 문구가 먼저 걸린다
  r="$(run '' 'AGENT="claude"; AGENT_SET=1; MODEL="claude-fable-5-1"')"; rc=$?; rc_is "N7 fable 사유 없음 rc1" "$rc" 1
  has "N7 R149 문구 그대로" "$r" "REJECT 상향 모델(claude-fable-5-1)은 --raise"
  hasnt "N7 r1385 문구 아님(먼저 걸림)" "$r" "REJECT 나노 기본 = pi"
  # N8 기본 손잡이를 claude 로 바꿔도 사유 게이트는 남는다
  r="$(run 'export FT_NANO_DEFAULT_AGENT=claude' '')"; rc=$?; rc_is "N8 FT_NANO_DEFAULT_AGENT=claude 사유 없음 rc1" "$rc" 1
  has "N8 손잡이 경로도 REJECT" "$r" "REJECT 나노 기본 = pi — claude/claude-sonnet-5-5[1m]"
  r="$(run 'export FT_NANO_DEFAULT_AGENT=claude' 'RAISE=x')"; rc=$?; rc_is "N8 손잡이 + 사유 rc0" "$rc" 0
  # 티어 표 — :1 = pi · :2·:3 = sonnet-5-5 · codex luna 칸 삭제 · FT_CMD_ENABLED=1 은 :1 자리
  r="$(run '' 'TIER="checker:1"')"; has "티어 checker:1 = pi" "$r" "RESULT agent=pi"
  r="$(run '' 'TIER="tester:1"')";  has "티어 tester:1 = pi" "$r" "RESULT agent=pi"
  r="$(run '' 'TIER="impl:1"')";    has "티어 impl:1 = pi" "$r" "RESULT agent=pi"
  r="$(run '' 'TIER="tester:2"')"; rc=$?; { [ "$rc" = 1 ] && has "티어 tester:2 = sonnet-5-5(사유 없으면 REJECT)" "$r" "REJECT 나노 기본 = pi — claude/claude-sonnet-5-5[1m]"; } || bad "$tag: 티어 tester:2 → rc=$rc"
  r="$(run '' 'TIER="tester:2"; RAISE="x"')"; has "티어 tester:2 = sonnet-5-5" "$r" "RESULT agent=claude model=claude-sonnet-5-5[1m] role=tester"
  r="$(run '' 'TIER="impl:3"; RAISE="x"')";   has "티어 impl:3 = sonnet-5-5" "$r" "RESULT agent=claude model=claude-sonnet-5-5[1m] role=impl"
  r="$(run 'export FT_CMD_ENABLED=1' 'TIER="checker:1"')"; has "FT_CMD_ENABLED=1 checker:1 = cmd deepseek" "$r" "RESULT agent=cmd model=deepseek/deepseek-v4-flash"
  grep -q 'gpt-6-luna' "$T/blockT.sh" && bad "$tag: 티어 표에 codex luna 칸 남음" || ok "$tag: 티어 표 codex luna 칸 삭제"
  # 부작용 0 자리 — 게이트가 worktree·tmux·명부·카드 쓰기 «앞» 인지 줄 번호로 본다
  _g="$(awk '/ft_raised\.py. is-raised/{f=1} f && /^case "\$AGENT" in/{print NR; exit}' "$SP")"
  [ -n "$_g" ] && ok "$tag: r1385 게이트 줄 찾음($_g)" || bad "$tag: r1385 게이트 줄 없음"
  for _m in 'OPEN=(tmuxc open' 'python3 - "$SEATS" "$NAME"' 'bash "$HERE/ft-index-move.sh"' 'git -C "$ROOT" worktree add --no-checkout'; do
    _l="$(grep -n -F -- "$_m" "$SP" | head -1 | cut -d: -f1)"
    { [ -n "$_l" ] && [ -n "$_g" ] && [ "$_l" -gt "$_g" ]; } && ok "$tag: 게이트 < 「${_m}」 (${_g:-?} < ${_l:-?})" || bad "$tag: 게이트가 「${_m}」(${_l:-?}) 뒤 — 부작용 0 아님"
  done
  # ── 보탬(arch#225 · master#162 #259818) 좌석 이름 끝 하이픈 — N9·N10·N11 ──
  _fl="$(grep -n '^_slug() {' "$SP" | head -1 | cut -d: -f1)"
  _bs="$(grep -n '^SLUG="\$(_slug' "$SP" | head -1 | cut -d: -f1)"
  _be="$(awk -v s="${_bs:-0}" 'NR>s && /^if \[ .*RESEARCH.* = 1 \]; then SLUG=/{print NR; exit}' "$SP")"
  [ -n "${_be:-}" ] || { bad "$tag: slug 블록 끝(리서치 줄) 못 찾음"; _be=$_bs; }
  slugh() { { [ -n "$_fl" ] && sed -n "${_fl}p" "$SP"; sed -n "${_bs:-0},${_be:-0}p" "$SP"; echo 'echo "SLUG=$SLUG"'; } > "$T/slug.sh"
    env -i PATH="$PATH" IDX="$1" RESEARCH="$2" bash "$T/slug.sh" 2>&1; }
  r="$(slugh "$T/r1386-merge-land-heavy-slot-wait-within-budget.md" 0)"
  [ "$r" = "SLUG=r1386-merge-land-heavy-slot-wait-within" ] && ok "$tag: N9 카드 40자째가 - → 이름 끝 하이픈 0" || bad "$tag: N9 → $r"
  bash "$HERE/../bin/ft-name-lint.sh" "byz-harness-nano-r1386-merge-land-heavy-slot-wait-within#0" >/dev/null 2>&1 && ok "$tag: N9 ft-name-lint PASS(옛 이름은 REJECT)" || bad "$tag: N9 ft-name-lint REJECT"
  r="$(slugh "$T/r1386-merge-land-heavy-slot-wait-within-budget.md" 1)"
  [ "$r" = "SLUG=r1386-merge-land-heavy-slot-wa-research" ] && ok "$tag: N10 리서치 꼬리 = -research 하나" || bad "$tag: N10 → $r"
  case "$r" in *--research*) bad "$tag: N10 하이픈 둘(--research)";; *) ok "$tag: N10 하이픈 둘 아님";; esac
  r="$(slugh "$T/한글카드이름.md" 0)"; rc=$?
  { [ "$rc" = 1 ] && has "N11 영문·숫자 0 인 카드 이름 → REJECT" "$r" "REJECT 카드 이름에서 좌석 이름을 못 만듦"; } || bad "$tag: N11 rc=$rc (기대 1)"
  grep -q 'slug="$(_slug "$IDX" 40)"' "$SP" && ok "$tag: reopen 경로도 _slug(끝 - 제거)" || bad "$tag: reopen 경로가 옛 slug 계산"
  head -12 "$SP" | grep -q '기본 pi' && ok "$tag: 머리 주석에 기본 pi" || bad "$tag: 머리 주석에 기본 pi 없음"
done
cmp -s "$HERE/../bin/ft-nano-spawn.sh" "$HERE/../kit/fable-team/bin/ft-nano-spawn.sh" && ok "추적본 = 키트(cmp)" || bad "추적본 ≠ 키트"
echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
