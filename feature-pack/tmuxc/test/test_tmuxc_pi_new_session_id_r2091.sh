#!/usr/bin/env bash
# test_tmuxc_pi_new_session_id_r2091.sh — r2091: tmuxc 로 여는 pi 좌석(open · fork)은 부른 쪽 env 의
#   TMUXC_PI_SESSION_ID 와 무관하게 새 uuid4 를 뽑는다(S1) · argv --session-id = 세션 env 값(S2) ·
#   claude 명령 줄 · pi 메타 env 는 그대로(S3).
#   픽스처 = --dry-run 출력 · 임시 HOME · 실 tmux 서버 0 · 실 pi 0 · sleep 0.
#   변이 대상 지정: TMUXC_UNDER_TEST=<사본 경로>.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TMUXC="${TMUXC_UNDER_TEST:-$HERE/../core/bin/tmuxc}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
A="aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
SRC="11111111-2222-3333-4444-555555555555"
UUID4='^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
mkdir -p "$T/wt" "$T/home/.pi/agent/sessions/p"
: > "$T/home/.pi/agent/sessions/p/20260101T000000_${SRC}.jsonl"

# $1 = 부른 쪽 TMUXC_PI_SESSION_ID(빈 값 = env 없음) · 나머지 = tmuxc 인자
run() {
  local inh="$1"; shift
  if [[ -n "$inh" ]]; then
    env -i PATH="$PATH" HOME="$T/home" TMUXC_PI_SESSION_ID="$inh" bash "$TMUXC" "$@" --dry-run 2>&1
  else
    env -i PATH="$PATH" HOME="$T/home" bash "$TMUXC" "$@" --dry-run 2>&1
  fi
}
argv_sid() { printf '%s\n' "$1" | sed -n 's/^command=.* --session-id \([^ ]*\).*/\1/p' | head -1; }
env_sid()  { printf '%s\n' "$1" | sed -n 's/^env=TMUXC_PI_SESSION_ID=//p' | head -1; }
is_uuid4() { [[ "$1" =~ $UUID4 ]]; }

# ① 상속 무시 open(S1)
o1="$(run "$A" open "$T/wt" --name R2091 --agent pi)"
s1="$(argv_sid "$o1")"
[[ "$s1" != "$A" ]] && is_uuid4 "$s1" && ok "① open 새 id ≠ A · uuid4 ($s1)" || bad "① open id=$s1: $o1"

# ② 상속 무시 fork(S1)
o2="$(run "$A" fork "$T/wt" --name R2091F --source "$SRC" --agent pi)"
s2="$(argv_sid "$o2")"
[[ "$s2" != "$A" ]] && is_uuid4 "$s2" && ok "② fork 새 id ≠ A · uuid4 ($s2)" || bad "② fork id=$s2: $o2"
[[ "$(env_sid "$o2")" == "$s2" ]] && ok "② fork argv = env" || bad "② fork env=$(env_sid "$o2") argv=$s2"

# ③ env 없이 연속 두 번(S1)
a="$(argv_sid "$(run "" open "$T/wt" --name R2091a --agent pi)")"
b="$(argv_sid "$(run "" open "$T/wt" --name R2091b --agent pi)")"
is_uuid4 "$a" && is_uuid4 "$b" && [[ "$a" != "$b" ]] && ok "③ 연속 두 id 다름 · uuid4" || bad "③ a=$a b=$b"

# ④ argv = 세션 env(S2) — ① 의 실행
[[ -n "$s1" && "$(env_sid "$o1")" == "$s1" ]] && ok "④ open argv = env ($s1)" || bad "④ env=$(env_sid "$o1") argv=$s1"

# ⑤ 불변(S3) — pi 메타 env · claude 명령 줄 꼴(id 값만 다름)
printf '%s\n' "$o1" | grep -qx 'env=TMUXC_PI_MODEL=' && printf '%s\n' "$o1" | grep -qx 'env=TMUXC_PI_THINKING=medium' \
  && ok "⑤ pi 메타 env 유지" || bad "⑤ pi 메타 env: $o1"
oc="$(run "$A" open "$T/wt" --name R2091C --agent claude --model sonnet)"
cl="$(printf '%s\n' "$oc" | sed -n 's/^command=//p' | sed -E 's/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/<ID>/g')"
want="$T/home/.headroom/claude-hr.sh --dangerously-skip-permissions --model \"sonnet\" --name R2091C --remote-control R2091C --session-id <ID>"
[[ "$cl" == "$want" ]] && ok "⑤ claude 명령 줄 꼴 그대로" || bad "⑤ claude 명령 줄: $cl"
printf '%s\n' "$oc" | grep -q "$A" && bad "⑤ claude 에 A 유입" || ok "⑤ claude 에 A 0"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
