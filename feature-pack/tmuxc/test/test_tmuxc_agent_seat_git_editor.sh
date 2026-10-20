#!/usr/bin/env bash
# test_tmuxc_agent_seat_git_editor.sh — r610: 비 claude 에이전트 좌석(pi·codex·opencode·cmd)의
#   tmux 세션 env 에 git 비대화 3종(GIT_EDITOR=true · GIT_SEQUENCE_EDITOR=true · GIT_TERMINAL_PROMPT=0)
#   을 심는다. pi 좌석이 화면 없는 vi 를 열고 54분 멈춘 사건(r599) 재발 방지.
#   픽스처 = --dry-run env 줄 + 가짜 tmux(new-session -e 기록) · 실 tmux 세션 0 · 외부 호출 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TMUXC="$HERE/../core/bin/tmuxc"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
GIT_ENVS=('env=GIT_EDITOR=true' 'env=GIT_SEQUENCE_EDITOR=true' 'env=GIT_TERMINAL_PROMPT=0')
mkdir -p "$T/wt" "$T/bin" "$T/home"

cat > "$T/bin/tmux" <<'SH'
#!/usr/bin/env bash
case "$1" in
  has-session) exit 1 ;;
  new-session) printf '%s\n' "$*" >> "$FAKE_OUT/tmux.log" ;;
  display-message) echo test-orch ;;
  *) exit 0 ;;
esac
SH
chmod +x "$T/bin/tmux"
run() { env -i PATH="$T/bin:$PATH" HOME="$T/home" FAKE_OUT="$T/out" bash "$TMUXC" open "$T/wt" --name R610 --dry-run "$@" 2>&1; }

# ⓐ pi — git 비대화 3줄 + 기존 pi 메타 env 유지
out="$(run --agent pi)"
n=0; for e in "${GIT_ENVS[@]}"; do printf '%s\n' "$out" | grep -qxF "$e" && n=$((n+1)); done
[ "$n" = 3 ] && ok "ⓐ pi env 3줄(GIT_EDITOR·GIT_SEQUENCE_EDITOR·GIT_TERMINAL_PROMPT)" || bad "ⓐ pi git env $n/3: $out"
printf '%s\n' "$out" | grep -qx 'env=TMUXC_PI_THINKING=medium' && ok "ⓐ pi 기존 메타 env 유지" || bad "ⓐ pi 메타 env: $out"

# ⓑ codex·opencode·cmd — 같은 3줄 (opencode 는 모델 env 와 «함께»)
for a in codex cmd; do
  out="$(run --agent "$a")"
  n=0; for e in "${GIT_ENVS[@]}"; do printf '%s\n' "$out" | grep -qxF "$e" && n=$((n+1)); done
  [ "$n" = 3 ] && ok "ⓑ $a env 3줄" || bad "ⓑ $a git env $n/3: $out"
done
out="$(run --agent opencode --model opencode/deepseek-v4.1-flash-free)"
n=0; for e in "${GIT_ENVS[@]}"; do printf '%s\n' "$out" | grep -qxF "$e" && n=$((n+1)); done
[ "$n" = 3 ] && ok "ⓑ opencode env 3줄" || bad "ⓑ opencode git env $n/3: $out"
printf '%s\n' "$out" | grep -qxF 'env=OPENCODE_CONFIG_CONTENT={"model":"opencode/deepseek-v4.1-flash-free"}' \
  && ok "ⓑ opencode 모델 env 유지" || bad "ⓑ opencode 모델 env: $out"

# ⓒ claude — env 줄 변화 0(회귀 0)
out="$(run --agent claude)"
printf '%s\n' "$out" | grep -q '^env=' && bad "ⓒ claude 에 env 줄: $out" || ok "ⓒ claude env 0(회귀 0)"
for e in "${GIT_ENVS[@]}"; do
  printf '%s\n' "$out" | grep -qxF "$e" && bad "ⓒ claude 에 $e" 
done
ok "ⓒ claude GIT_* 0"

# fork 경로도 같은 3줄(pi fork)
mkdir -p "$T/home/.pi/agent/sessions/p" && : > "$T/home/.pi/agent/sessions/p/20260101T000000_11111111-2222-3333-4444-555555555555.jsonl"
out="$(env -i PATH="$T/bin:$PATH" HOME="$T/home" FAKE_OUT="$T/out" TMUXC_PI_SESSION_ID=sid-x \
  bash "$TMUXC" fork "$T/wt" --name R610F --source 11111111-2222-3333-4444-555555555555 --agent pi --dry-run 2>&1)"
n=0; for e in "${GIT_ENVS[@]}"; do printf '%s\n' "$out" | grep -qxF "$e" && n=$((n+1)); done
[ "$n" = 3 ] && ok "fork pi env 3줄" || bad "fork pi git env $n/3: $out"

# 실전 경로(가짜 tmux) — new-session -e 로 세션에 실제로 실린다(pi)
mkdir -p "$T/out"
env -i PATH="$T/bin:$PATH" HOME="$T/home" FAKE_OUT="$T/out" bash "$TMUXC" open "$T/wt" --name R610 --agent codex >/dev/null 2>&1
log="$(cat "$T/out/tmux.log" 2>/dev/null)"
for e in "${GIT_ENVS[@]}"; do
  kv="${e#env=}"
  case "$log" in *"-e $kv"*) ok "실전 codex new-session -e $kv";; *) bad "실전 codex -e $kv 없음: $log";; esac
done
echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
