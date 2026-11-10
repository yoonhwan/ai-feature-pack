#!/usr/bin/env bash
# run-mutate.sh — 변이(ⓔ): `old = [] if add else …` → `old = …` 로 되돌리면 --add 가 구 좌석을 닫는다(= ⓑ FAIL 재현).
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1 FT_TEAMSET=0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_ROLE_BASE_PREFIX FT_PENALTY_TEAM
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; KIT="$HERE/../../kit/fable-team/bin"; TB="$HERE/../../tests"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
. "$TB/lib/fake_resource_env.sh"; fake_resource_env "$T/sensors" ok
R="$T/repo"; B="$T/bin"; FK="$T/fake"; mkdir -p "$R/.fable-team" "$B" "$FK"
git init -q "$R"; mkdir -p "$R/design"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| feat | `design/teams/feat/` | x | 현역 |\n' > "$R/design/TEAMS.md"
mkdir -p "$R/design/teams/feat/indices/inbox/arch"; : > "$R/design/teams/feat/SEATBELT-README.md"
printf '{"_name":"feat","_master":"byz-feat-master-claude#30","_arch":"byz-feat-arch-claude#3",\n "byz-feat-arch-claude#3":{"role":"arch","agent":"claude","tick":null,"model":"claude-opus-5-5[1m]","index":"design/teams/feat/indices/inbox/arch/"}}\n' > "$R/.fable-team/seats-feat.json"
for f in ft-role-spawn.sh ft-team-lib.sh ft_raised.py ft-resource-gate.sh ft-resource-swap-lib.sh ft-reclaim-capped.sh ft_teamset.py ft_spawn_queue.py ft-resource-sample.sh ft-harness-root.sh; do cp -p "$KIT/$f" "$B/"; done
printf '#!/usr/bin/env bash\nexit 0\n' > "$B"/ft-all-stop.sh
printf '#!/bin/bash\necho "SENT $*"\nexit 0\n' > "$B/ft-send-verified.sh"
: > "$T/opened"
printf '#!/bin/bash\n[ "$1" = open ] || exit 0\nn=""; while [ $# -gt 0 ]; do [ "$1" = --name ] && n="$2"; shift; done\necho "$n" >> %s\n' "$T/opened" > "$FK/tmuxc"
printf '#!/bin/bash\ncase "$1" in has-session) grep -qxF -- "${3#=}" %s;; list-panes) while read -r n; do echo "$n|%%9"; done < %s;; show-option) echo 1;; *) exit 0;; esac\n' "$T/opened" "$T/opened" > "$FK/tmux"
chmod +x "$B"/* "$FK"/*
sed 's/^old = \[\] if add else /old = /' "$B/ft-role-spawn.sh" > "$B/mut.sh"
echo "--- 변이 diff (한 줄)"; diff "$B/ft-role-spawn.sh" "$B/mut.sh" | sed -n '2,3p'
echo "--- 변이 실행: arch --team feat --add"
(cd "$R" && PATH="$FK:$PATH" bash "$B/mut.sh" arch --team feat --add 2>&1)
echo "--- 변이 뒤 명부"
python3 -c 'import json,sys;d=json.load(open(sys.argv[1]))
for k,v in d.items():
  print(k if not isinstance(v,dict) else "%s role=%s _replaced_by=%s _replaces=%s"%(k,v.get("role"),v.get("_replaced_by"),v.get("_replaces")))' "$R/.fable-team/seats-feat.json"
echo "--- 판정: 구 #3 에 _replaced_by 가 찍히면 ⓑ(\"기존 행 _replaced_by 0\") FAIL 재현"
