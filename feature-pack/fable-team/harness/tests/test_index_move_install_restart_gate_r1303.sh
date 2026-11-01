#!/usr/bin/env bash
# r1303 stale daemon restart scan — isolated HOME and launchctl/ps stubs only.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export LC_ALL=C
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$HERE/../bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; P="$T/project"; Q="$T/other"; LIVE="$T/live"; LA="$HOME/Library/LaunchAgents"
mkdir -p "$P/.fable-team/bin" "$P/.worktrees/w/.fable-team/bin" "$Q/fable-team/live/v1/bin" "$Q/.worktrees/w/.fable-team/bin" "$LIVE/fable-team/live/v1/bin" "$T/project-suffix/.fable-team/bin" "$LA" "$T/stub"
touch -t 202601010000 "$P/.fable-team/bin/tick.sh" "$P/.worktrees/w/.fable-team/bin/tick.sh" "$Q/fable-team/live/v1/bin/tick.sh" "$Q/.worktrees/w/.fable-team/bin/tick.sh" "$LIVE/fable-team/live/v1/bin/tick.sh" "$T/project-suffix/.fable-team/bin/tick.sh"
touch -t 202301010000 "$P/.fable-team/bin/current.sh"
cat > "$T/stub/launchctl" <<'EOF'
#!/bin/bash
[ "${LC_RC:-0}" = 0 ] || exit "$LC_RC"
printf '{\n\t"PID" = 4242;\n};\n'
EOF
cat > "$T/stub/ps" <<'EOF'
#!/bin/bash
[ "${PS_RC:-0}" = 0 ] || exit "$PS_RC"
echo "${PS_START:-Thu Oct 15 10:00:00 2024}"
EOF
chmod 755 "$T/stub/launchctl" "$T/stub/ps"
export FT_LAUNCHCTL="$T/stub/launchctl" FT_PS="$T/stub/ps"
plist() { python3 - "$LA/$1.plist" "$2" "$3" "${4:-}" "${5:-}" <<'PY'
import plistlib, sys
row = {"Label": sys.argv[2], "ProgramArguments": [sys.argv[3]]}
if sys.argv[4] == "FT_ROOT":
    row["EnvironmentVariables"] = {"FT_ROOT": sys.argv[5]}
elif sys.argv[4] == "WorkingDirectory":
    row["WorkingDirectory"] = sys.argv[5]
with open(sys.argv[1], "wb") as f:
    plistlib.dump(row, f)
PY
}
plist target com.byz.target "$P/.fable-team/bin/tick.sh"
plist other com.byz.other "$Q/.fable-team/bin/tick.sh"
plist shim com.byz.shim "$Q/fable-team/live/v1/bin/tick.sh"
plist worktree-other com.byz.worktree-other "$Q/.worktrees/w/.fable-team/bin/tick.sh"
plist prefix-other com.byz.prefix-other "$T/project-suffix/.fable-team/bin/tick.sh"
plist live-other-root com.byz.live-other-root "$LIVE/fable-team/live/v1/bin/tick.sh" FT_ROOT "$Q"
plist live-other-wd com.byz.live-other-wd "$LIVE/fable-team/live/v1/bin/tick.sh" WorkingDirectory "$Q"
plist current com.byz.current "$P/.fable-team/bin/current.sh"
scan() { out="$(python3 -I "$BIN/ft_live_install_check.py" --restart-scan --project "$1" 2>&1)"; rc=$?; }
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 rc=$rc out=${out:0:250}"; exit 1; fi; }

scan "$P"; [[ "$rc" = 0 && "$out" == *"RESTART com.byz.target — launchctl kickstart"* && "$out" != *"com.byz.other"* && "$out" != *"com.byz.shim"* && "$out" != *"com.byz.current"* ]]; ck "R1 stale target, newer and other-root daemons filtered" $?
[[ "$out" != *"com.byz.prefix-other"* ]]; ck "R3b sibling path-prefix collision ignored" $?
[[ "$out" != *"com.byz.worktree-other"* ]]; ck "R3c other-root worktree shim ignored" $?
[[ "$out" != *"com.byz.live-other-root"* ]]; ck "R3d foreign FT_ROOT live script ignored" $?
[[ "$out" != *"com.byz.live-other-wd"* ]]; ck "R3e foreign WorkingDirectory live script ignored" $?
mv "$LA/target.plist" "$T/target.plist"; plist worktree-project com.byz.worktree-project "$P/.worktrees/w/.fable-team/bin/tick.sh"; scan "$P"; [[ "$rc" = 0 && "$out" == *"RESTART com.byz.worktree-project — launchctl kickstart"* ]]; ck "R2 project worktree shim is included" $?
mv "$LA/worktree-project.plist" "$T/worktree-project.plist"; mv "$LA/other.plist" "$T/other.plist"; mv "$LA/shim.plist" "$T/shim.plist"; scan "$P"; [[ "$rc" = 0 && "$out" = "RESTART 0" ]]; ck "R3 other-root plist and shim return RESTART 0" $?
plist live-root com.byz.live-root "$LIVE/fable-team/live/v1/bin/tick.sh" FT_ROOT "$P"
plist live-wd com.byz.live-wd "$LIVE/fable-team/live/v1/bin/tick.sh" WorkingDirectory "$P"
scan "$P"; [[ "$rc" = 0 && "$out" == *"RESTART com.byz.live-root — launchctl kickstart"* && "$out" == *"RESTART com.byz.live-wd — launchctl kickstart"* ]]; ck "R4 project FT_ROOT and WorkingDirectory live paths detected" $?
LC_RC=7 scan "$P"; [[ "$rc" = 3 && "$out" == *"재기동 판정 불가: launchctl"* ]]; ck "R5 launchctl failure fails closed" $?
LC_RC=124 scan "$P"; [[ "$rc" = 3 && "$out" == *"재기동 판정 불가: launchctl"* ]]; ck "R6 timeout status fails closed" $?
LC_RC=0 PS_RC=7 scan "$P"; [[ "$rc" = 3 && "$out" == *"재기동 판정 불가: ps"* ]]; ck "R7 ps failure fails closed" $?
PS_RC=0 scan "$T/missing"; [[ "$rc" = 3 && "$out" == *"재기동 판정 불가: 프로젝트 루트 없음"* ]]; ck "R8 missing project fails closed" $?
mv "$LA/live-root.plist" "$T/live-root.plist"; mv "$LA/live-wd.plist" "$T/live-wd.plist"; mv "$T/other.plist" "$LA/other.plist"; mv "$T/shim.plist" "$LA/shim.plist"; LC_RC=0 scan "$P"; [[ "$rc" = 0 && "$out" = "RESTART 0" ]]; ck "mutation 9: no target project plist cannot inherit other-root stale daemon" $?
echo "ALL PASS"
