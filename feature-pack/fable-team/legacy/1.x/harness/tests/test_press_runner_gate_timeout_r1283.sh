#!/usr/bin/env bash
# test_press_runner_gate_timeout_r1283.sh — r1283 러너 훅 게이트 상한 70초 + 시간초과 deny 사유에 «단계 초» 줄(2/2 · 게이트 쪽은 test_press_gate_step1_git_hoist_r1283.sh)
#   R4 env 없음 → 70 · FT_PRESS_RUNNER_GATE_TIMEOUT=500·5·abc·빈 값·소수·유니코드 숫자 → 70 · 10~70 안(60·10) → 그 값 (훅이 로그에 «게이트 상한 N초» 한 줄을 남긴다)
#   R5 가짜 게이트가 «단계 초» 줄을 찍고 잠 → 상한(env 10) 뒤 deny · 사유에 «fail-closed(R106c)» + 그 단계 초 줄 · 줄 없이 자는 게이트는 사유에 줄 없음
#   R6 가짜 게이트 rc0 빠름 → 훅 통과(출력 0) · rc1 → 지금 그대로 «ft-press-gate 막힘»
#   변이 2 = 상한 70 을 60 고정으로 → R4 FAIL · 변이 3 = deny 사유에서 단계 초 줄 제거 → R5 FAIL
#   실 리포·실 tmux·실 Redis·네트워크 0 · 자기 재호출 0 · 고정 sleep 0(가짜 게이트의 잠은 상한 시험 자체 — env 10초 + 변이 칸 10초)
set -uo pipefail
[ -z "${FT_R1283_HOOK_REENTRY:-}" ] || { echo "FAIL 재진입"; exit 1; }
export FT_R1283_HOOK_REENTRY=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HOOK="$HERE/../kit/fable-team/templates/hooks/press-runner-gate.sh"
fail=0
ok(){ echo "PASS $1"; }
bad(){ echo "FAIL $1"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
bash -n "$HOOK" && ok "bash -n hook" || bad "bash -n hook"

mkgate(){ printf '#!/bin/sh\n%s\n' "$2" > "$T/$1"; chmod +x "$T/$1"; printf '%s' "$T/$1"; }
FAST="$(mkgate fast 'exit 0')"
BLOCK="$(mkgate block 'echo "✗ 미랜딩 제품 커밋 1 — v65-k"; exit 1')"
STAGE='단계 초: ⓪ 0.1 · ① 61.0(실행) · ②~⑤(dev) 1.0 · ⑥⑦⑧ 0.3'
SLEEP_STAGE="$(mkgate sleepstage "echo '· $STAGE'; exec sleep 40")"
SLEEP_PLAIN="$(mkgate sleepplain 'exec sleep 40')"
JSON="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"python3 tests/e2e/realtime_multi_e2e.py\"},\"cwd\":\"$T\"}"

runhook(){ # $1 = 훅 · $2 = 게이트 · $3 = 상한 env 값(없으면 "UNSET") → OUT(훅 출력) · LOGV(그 실행의 로그)
  : > "$T/hook.log"
  if [ "${3:-UNSET}" = UNSET ]; then
    OUT="$(printf '%s' "$JSON" | env -u FT_PRESS_RUNNER_GATE_TIMEOUT FT_PRESS_RUNNER_GATE_LOG="$T/hook.log" FT_PRESS_GATE_BIN="$2" bash "$1" 2>&1)"
  else
    OUT="$(printf '%s' "$JSON" | env FT_PRESS_RUNNER_GATE_TIMEOUT="$3" FT_PRESS_RUNNER_GATE_LOG="$T/hook.log" FT_PRESS_GATE_BIN="$2" bash "$1" 2>&1)"
  fi
  LOGV="$(cat "$T/hook.log")"
}
lim(){ printf '%s\n' "$LOGV" | grep -c "게이트 상한 $1초"; }

case_r4(){ local v exp
  runhook "$1" "$FAST" UNSET; [ "$(lim 70)" = 1 ] || return 1
  for v in 500 5 abc "" 60.5 "０６０" " 60" -10 071x; do runhook "$1" "$FAST" "$v"; [ "$(lim 70)" = 1 ] || { echo "env=[$v]"; return 1; }; done
  for v in 60 10 70; do runhook "$1" "$FAST" "$v"; [ "$(lim "$v")" = 1 ] || { echo "env=[$v]"; return 1; }; done; }
case_r5(){ runhook "$1" "$SLEEP_STAGE" 10
  printf '%s\n' "$OUT" | grep -q '"permissionDecision": "deny"' && printf '%s\n' "$OUT" | grep -qF 'fail-closed(R106c)' \
    && printf '%s\n' "$OUT" | grep -qF "$STAGE" || return 1
  runhook "$1" "$SLEEP_PLAIN" 10
  printf '%s\n' "$OUT" | grep -qF 'fail-closed(R106c)' && ! printf '%s\n' "$OUT" | grep -qF '단계 초'; }
case_r6(){ runhook "$1" "$FAST" UNSET; [ -z "$OUT" ] || return 1
  runhook "$1" "$BLOCK" UNSET; printf '%s\n' "$OUT" | grep -qF 'ft-press-gate 막힘(rc=1)' && printf '%s\n' "$OUT" | grep -qF '✗ 미랜딩 제품 커밋 1 — v65-k'; }
mut(){ # $1 = sed 식 → 변이 훅 경로 · 안 먹으면 rc1
  sed -e "$1" "$HOOK" > "$T/mut-$2.sh"; ! cmp -s "$T/mut-$2.sh" "$HOOK" || { echo "변이 적용 안 됨" >&2; return 1; }; printf '%s' "$T/mut-$2.sh"; }

run(){ local c; BAD=""; for c in "$@"; do if case_"$c" "$HOOK" >/dev/null 2>&1; then echo "  $c ok"; else BAD="$BAD $c"; fi; done; }
run r4 r5 r6
[ -z "$BAD" ] && ok "R4·R5·R6 통과" || bad "실패 칸:$BAD"
M2="$(mut 's/^T = limit()$/T = 60/' 2)" && { case_r4 "$M2" >/dev/null 2>&1 && bad "변이 2 가 R4 를 못 잡음" || ok "변이 2(상한 60 고정) → R4 FAIL"; } || bad "변이 2 사본"
M3="$(mut 's/ if stage_line(e.stdout) else ""/ if False else ""/' 3)" && { case_r5 "$M3" >/dev/null 2>&1 && bad "변이 3 이 R5 를 못 잡음" || ok "변이 3(사유 단계 초 줄 제거) → R5 FAIL"; } || bad "변이 3 사본"
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILED $fail"; exit 1
