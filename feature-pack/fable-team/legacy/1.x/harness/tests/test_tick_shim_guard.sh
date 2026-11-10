#!/usr/bin/env bash
# test_tick_shim_guard.sh — r459: 틱 데몬이 «shim 폴더의 옛 통째 사본» 으로 조용히 돌지 못하게 + 메인 plist 자리 규칙.
#   ⓐ ft-tick.sh·ft-tick-team.sh 를 shim 폴더(형제 ft_raised.py 첫 3줄에 ft-root-bin-shim 마커)에서 실행 → ERROR + exit 3 · 쪽지 0
#   ⓑ LIVE_BIN(형제 = 진짜 도구) 경로 실행 → 자가 검사 통과(exit 3 아님 · shim ERROR 0)
#   ⓒ ft-tick-install.sh 메인 plist 렌더 = WorkingDirectory 공용 루트 + FT_TICK_MBOX·FT_MBOX_DIR·FT_TICK_AGENT_ALIVE 공용 루트 comm · 공용 루트 comm 없음 = REJECT
# mktemp 만 — 실 launchd·실 우편함·실 tmux 송신 0 · GIT_* 경로 env 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HROOT="$(cd -- "$HERE/.." && pwd -P)"
KBIN="$HROOT/kit/fable-team/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; T="$(cd "$T" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 — 값 «$1» 기대 «$2»"; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:300}";; esac; }
unset FT_ROOT FT_MBOX_DIR FT_TICK_MBOX FT_HARNESS_ROOT

for f in ft-tick.sh ft-tick-team.sh ft-tick-install.sh; do bash -n "$KBIN/$f" && ok "bash -n $f" || bad "bash -n $f"; done
for f in ft-tick.sh ft-tick-team.sh ft-tick-install.sh ft-tick.plist; do cmp -s "$KBIN/$f" "$HROOT/bin/$f" && ok "bin·kit 짝 cmp0 $f" || bad "bin·kit 짝 다름 $f"; done

# 픽스처 리포(공용 루트 comm 있음) + 워크트리
R="$T/repo"; mkdir -p "$R/.fable-team/comm"; git -C "$R" init -q -b main; git -C "$R" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i
git -C "$R" worktree add -q "$T/wt" -b wt 2>/dev/null
printf '#!/bin/sh\necho "$@" >> "%s/mbox.log"\n' "$T" > "$R/.fable-team/comm/mbox.sh"; chmod 755 "$R/.fable-team/comm/mbox.sh"
printf '{}\n' > "$T/seats.json"
# r962: 설치 «시작 경로» 는 공용 루트 .fable-team/bin 아래만 — 픽스처 리포의 라이브 bin
mkdir -p "$R/.fable-team/bin"; cp -p "$KBIN/ft-tick.sh" "$R/.fable-team/bin/"
ENVX=(FT_TICK_LAUNCHD=0 FT_TICK_MAGAZINE=0 FT_TICK_IDLE_ENABLED=0 FT_TICK_WT_SWEEP=0 FT_TICK_HIL=0 FT_TICK_DRIFT=0 FT_TICK_RAISED=0
      FT_TICK_SEATS="$T/seats.json" FT_TICK_PIDFILE="$T/tick.pid" FT_TICK_STAMP_PREFIX="$T/p-" FT_TICK_STATE_DIR="$T/state")

# ── ⓐ shim 폴더 = 진짜 틱 + shim 형제 ──
SB="$T/root/.fable-team/bin"; mkdir -p "$SB"; cp -p "$KBIN/ft-tick.sh" "$KBIN/ft-tick-team.sh" "$KBIN/ft-harness-root.sh" "$SB/"
printf '#!/usr/bin/env bash\n# ft-root-bin-shim: ft_raised.py → LIVE_BIN (루트 옛 사본이 아니다)\nexec python3 /nowhere/ft_raised.py\n' > "$SB/ft_raised.py"
for f in ft-tick.sh ft-tick-team.sh; do
  out="$(cd "$T/wt" && env "${ENVX[@]}" bash "$SB/$f" --once --dry-run 2>&1)"; rc=$?
  eq "$rc" 3 "ⓐ shim 폴더 $f → exit 3"
  has "$out" "ERROR shim 폴더에서 실행 — launchctl kickstart 로 LIVE_BIN 재기동 ($SB)" "ⓐ $f ERROR 줄(재기동 안내)"
done
[ ! -s "$T/mbox.log" ] && ok "ⓐ 쪽지 0(조용히 돌지 않음)" || bad "ⓐ 쪽지가 나감: $(head -2 "$T/mbox.log")"

# ── ⓑ LIVE_BIN 경로 = 키트 bin 통째(형제 진짜) → 자가 검사 통과 ──
LB="$T/home/.claude/fable-team/live/9.9.9/bin"; mkdir -p "$LB"; cp -p "$KBIN"/* "$LB/" 2>/dev/null
for f in ft-tick.sh ft-tick-team.sh; do
  out="$(cd "$T/wt" && env "${ENVX[@]}" bash "$LB/$f" --once --dry-run 2>&1)"; rc=$?
  [ "$rc" != 3 ] && ok "ⓑ LIVE_BIN $f → exit 3 아님(rc=$rc)" || bad "ⓑ LIVE_BIN $f exit 3 «${out:0:200}»"
  case "$out" in *"shim 폴더에서 실행"*) bad "ⓑ LIVE_BIN $f 에 shim ERROR";; *) ok "ⓑ LIVE_BIN $f shim ERROR 0";; esac
  case "$out" in *"comm 폴더"*) bad "ⓑ LIVE_BIN $f comm 못 풂 «${out:0:200}»";; *) ok "ⓑ LIVE_BIN $f comm = 공용 루트로 풀림(cwd=워크트리)";; esac
done

# ── ⓒ 메인 plist 렌더(dry-run) = 공용 루트 자리 ──
out="$(cd "$T/wt" && FT_TICK_PRINT_PLIST=1 bash "$KBIN/ft-tick-install.sh" --worktree "$T/wt" --script "$R/.fable-team/bin/ft-tick.sh" --dry-run 2>&1)"; rc=$?
eq "$rc" 0 "ⓒ ft-tick-install --dry-run rc0"
has "$out" "cwd=$R · comm=$R/.fable-team/comm" "ⓒ PLAN 줄 cwd = 공용 루트(워크트리 아님)"
PL="$(printf '%s\n' "$out" | sed -n '/^<?xml/,/<\/plist>/p')"
val() { printf '%s' "$PL" | plutil -extract "$1" raw -o - - 2>/dev/null; }
eq "$(val WorkingDirectory)" "$R" "ⓒ WorkingDirectory = 공용 루트"
eq "$(val EnvironmentVariables.FT_TICK_MBOX)" "$R/.fable-team/comm/mbox.sh" "ⓒ FT_TICK_MBOX = 공용 루트 comm"
eq "$(val EnvironmentVariables.FT_MBOX_DIR)" "$R/.fable-team/comm" "ⓒ FT_MBOX_DIR = 공용 루트 comm"
eq "$(val EnvironmentVariables.FT_TICK_AGENT_ALIVE)" "$R/.fable-team/comm/ft-agent-alive.sh" "ⓒ FT_TICK_AGENT_ALIVE = 공용 루트 comm"
R2="$T/nocomm"; mkdir -p "$R2"; git -C "$R2" init -q -b main
out="$(FT_TICK_PRINT_PLIST=1 bash "$KBIN/ft-tick-install.sh" --worktree "$R2" --script "$R/.fable-team/bin/ft-tick.sh" --dry-run 2>&1)"; rc=$?
[ "$rc" != 0 ] && has "$out" "REJECT 공용 루트 comm 없음" "ⓒ 공용 루트 comm 없음 → REJECT" || bad "ⓒ comm 없음 rc=$rc «$out»"
! grep -nE '\b(600|300)\b' "$KBIN/ft-tick.plist" >/dev/null && ok "ⓒ plist 600/300 0" || bad "ⓒ plist 600/300"

echo "fail=$fail"
[ "$fail" = 0 ] && echo "ALL PASS"
exit "$fail"
