#!/usr/bin/env bash
# run-r989.sh — r989 증거 채집: --add / --add 없음 두 꼴의 PLAN 줄과 명부 전후.
# 전부 mktemp 안(가짜 tmux/tmuxc · 가짜 송신 · 가짜 자원 센서) — 실 명부·실 tmux·실 쪽지 0.
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1 FT_TEAMSET=0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_ROLE_BASE_PREFIX FT_PENALTY_TEAM
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../../kit/fable-team/bin"; TB="$HERE/../../tests"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
. "$TB/lib/fake_resource_env.sh"; fake_resource_env "$T/sensors" ok
R="$T/repo"; B="$T/bin"; FK="$T/fake"; mkdir -p "$R/.fable-team" "$B" "$FK"
git init -q "$R"; mkdir -p "$R/design"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| feat | `design/teams/feat/` | x | 현역 |\n' > "$R/design/TEAMS.md"
mkdir -p "$R/design/teams/feat/indices/inbox/arch"; : > "$R/design/teams/feat/SEATBELT-README.md"
roster() { printf '{"_name":"feat","_master":"byz-feat-master-claude#30","_arch":"byz-feat-arch-claude#3",\n "byz-feat-arch-claude#3":{"role":"arch","agent":"claude","tick":null,"model":"claude-opus-5-5[1m]","index":"design/teams/feat/indices/inbox/arch/"}}\n' > "$R/.fable-team/seats-feat.json"; }
for f in ft-role-spawn.sh ft-team-lib.sh ft_raised.py ft-resource-gate.sh ft-resource-swap-lib.sh ft-reclaim-capped.sh ft_teamset.py ft_spawn_queue.py ft-resource-sample.sh ft-harness-root.sh; do cp -p "$KIT/$f" "$B/"; done
printf '#!/usr/bin/env bash\nexit 0\n' > "$B"/ft-all-stop.sh
printf '#!/bin/bash\necho "SENT $*"\nexit 0\n' > "$B/ft-send-verified.sh"
OPENED="$T/opened"; : > "$OPENED"
printf '#!/bin/bash\n[ "$1" = open ] || exit 0\nn=""; d=0; while [ $# -gt 0 ]; do [ "$1" = --name ] && n="$2"; [ "$1" = --dry-run ] && d=1; shift; done\n[ "$d" = 1 ] && { echo "TMUXC-DRY $n"; exit 0; }\necho "$n" >> %s\n' "$OPENED" > "$FK/tmuxc"
cat > "$FK/tmux" <<EOF
#!/bin/bash
case "\$1" in
  has-session) n="\${3#=}"; grep -qxF -- "\$n" "$OPENED";;
  list-panes) while read -r n; do echo "\$n|%9"; done < "$OPENED";;
  show-option) echo 1;;
  *) exit 0;;
esac
EOF
chmod +x "$B"/* "$FK"/*
rs() { (cd "$R" && PATH="$FK:$PATH" bash "$B/ft-role-spawn.sh" "$@" 2>&1); }
rows() { python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));
for k,v in d.items():
  print(k if not isinstance(v,dict) else "%s role=%s tick=%s _replaced_by=%s _replaces=%s"%(k,v.get("role"),v.get("tick"),v.get("_replaced_by"),v.get("_replaces")))' "$R/.fable-team/seats-feat.json"; }

echo "=== PLAN 두 꼴 ==="
roster; echo "--- (1) ft-role-spawn.sh arch --team feat --add --dry-run"; rs arch --team feat --add --dry-run | grep -E '^(PLAN|TMUXC-DRY)'
roster; echo "--- (2) ft-role-spawn.sh arch --team feat --dry-run  (--add 없음)"; rs arch --team feat --dry-run | grep -E '^(PLAN|TMUXC-DRY)'
echo
echo "=== 명부 전후: (1) --add ==="
roster; echo "--- 전"; rows; rs arch --team feat --add >/dev/null 2>&1; echo "--- 후"; rows
echo
echo "=== 명부 전후: (2) --add 없음(교체) ==="
roster; : > "$OPENED"; echo "--- 전"; rows; rs arch --team feat >/dev/null 2>&1; echo "--- 후"; rows
