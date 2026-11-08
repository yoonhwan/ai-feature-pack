#!/usr/bin/env bash
# test_seat_retire_desk_cell_r1461.sh — r1461: desk 승계 뒤 seats-planner.json 의 _desk 가 후계 이름이고 후계 행 role=desk 다(정식 도구 재실행만 · 손 편집 0).
#   T1 재실행(FIXED) · T2 첫 retire(RETIRED) · T3 살아 있는 다른 좌석(_desk) REJECT · T4 master 후계 role 유지 · T5 successor-open 선등록 role 도출 · T7 도출≠이름 토큰 REJECT.
#   모든 쓰기는 mktemp scratch 리포 — 실 명부·실 tmux·실 우편함 0 · 가짜 tmux(세션 없음 · FAKE_ALIVE_NAME 만 살아 있음).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
RETIRE="$BIN/ft-seat-retire.sh"; OPEN_KIT="$KIT/ft-successor-open.sh"; OPEN_SK="$HERE/../../skill/scripts/ft-successor-open.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT; TMP="$(cd "$TMP" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
J() { jq -r "$2" "$1"; }
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$TMP/reap.sh"; export FT_SEAT_REAP_BIN="$TMP/reap.sh"   # r448 은퇴 reap = 스텁(실기계 프로세스 0)
FK="$TMP/fake"; mkdir -p "$FK"
printf '#!/usr/bin/env bash\ncase "$*" in *"${FAKE_ALIVE_NAME:-@@none@@}"*) exit 0;; esac\nexit 1\n' > "$FK/tmux"; chmod +x "$FK/tmux"
OLD='byz-planner-desk-claude#118'; NEW='byz-planner-desk-claude#121'
O2='byz-planner-master-claude#9'; N2='byz-planner-master-claude#10'
retired() { printf '{"role": "stop-ready", "agent": "claude", "model": "m", "tick": null, "_replaced_by": "%s", "_retired_role": "desk"}' "$1"; }
prereg()  { printf '{"role": "master", "agent": "codex", "model": "m", "tick": null, "persona": "successor (auto-registered by ft-successor-open r1435)", "_replaces": ["%s"]}' "$1"; }
repo() { local r="$TMP/r-$1"; mkdir -p "$r/.fable-team"; git -C "$r" init -q; printf '%s' "$2" > "$r/.fable-team/seats-planner.json"; echo "$r"; }
F() { echo "$1/.fable-team/seats-planner.json"; }
srun() { (cd "$1" && HOME="$TMP/home" PATH="$FK:$PATH" env -u FT_SEATS_JSON bash "$RETIRE" "$2" "$3" "${@:4}"); }
baks() { ls "$1/.fable-team"/*.bak-retire-* 2>/dev/null | wc -l | tr -d ' '; }

bash -n "$RETIRE" && ok "bash -n ft-seat-retire.sh" || bad "bash -n ft-seat-retire.sh"
python3 -m py_compile "$BIN/ft_roster_lib.py" && ok "py_compile ft_roster_lib.py" || bad "py_compile ft_roster_lib.py"
chk "bin·kit ft_roster_lib.py cmp0" "$(cmp -s "$BIN/ft_roster_lib.py" "$KIT/ft_roster_lib.py" && echo same || echo diff)" same

# T1 — _desk="" · 옛 행 은퇴 완료 · 후계 선등록 role=master → 재실행 = FIXED · _desk=후계 · role=desk
R="$(repo t1 "{\"_desk\": \"\", \"$OLD\": $(retired "$NEW"), \"$NEW\": $(prereg "$OLD")}")"; cp "$(F "$R")" "$TMP/t1.orig"
out="$(srun "$R" "$OLD" "$NEW")"; rc=$?
chk "T1 rc 0" "$rc" 0
chk "T1 FIXED · FILLED seats-planner.json:_desk" "$(sed -n 1p <<< "$out" | cut -d' ' -f1) $(grep -oE 'FILLED [^ ]+' <<< "$out" | head -1)" "FIXED FILLED seats-planner.json:_desk"
chk "T1 _desk = 후계" "$(J "$(F "$R")" ._desk)" "$NEW"
chk "T1 후계 role = desk" "$(J "$(F "$R")" ".[\"$NEW\"].role")" desk
chk "T1 .bak 1 · tmp 잔류 0" "$(baks "$R") $(ls "$R/.fable-team" | grep -c '\.tmp-')" "1 0"

# T2 — 같은 조건 첫 retire(옛 행 미은퇴) → RETIRED · _desk=후계 · role=desk
R="$(repo t2 "{\"_desk\": \"\", \"$OLD\": {\"role\": \"desk\", \"agent\": \"claude\", \"model\": \"m\", \"tick\": null}, \"$NEW\": $(prereg "$OLD")}")"
out="$(srun "$R" "$OLD" "$NEW")"; rc=$?
chk "T2 rc 0 · RETIRED" "$rc $(sed -n 1p <<< "$out" | cut -d' ' -f1)" "0 RETIRED"
chk "T2 _desk = 후계 · role = desk" "$(J "$(F "$R")" ._desk) $(J "$(F "$R")" ".[\"$NEW\"].role")" "$NEW desk"
chk "T2 옛 행 _retired_role = desk · role = stop-ready" "$(J "$(F "$R")" ".[\"$OLD\"]|[._retired_role,.role]|join(\",\")")" "desk,stop-ready"

# T3 — _desk = 살아 있는 다른 좌석 → REJECT · 명부 쓰기 0
LIVE='byz-planner-desk-claude#999'
R="$(repo t3 "{\"_desk\": \"$LIVE\", \"$OLD\": $(retired "$NEW"), \"$NEW\": $(prereg "$OLD")}")"; cp "$(F "$R")" "$TMP/t3.orig"
out="$(cd "$R" && FAKE_ALIVE_NAME="$LIVE" HOME="$TMP/home" PATH="$FK:$PATH" env -u FT_SEATS_JSON bash "$RETIRE" "$OLD" "$NEW" 2>&1)"; rc=$?
chk "T3 rc 1 · REJECT" "$rc ${out%% *}" "1 REJECT"
chk "T3 명부 바이트 불변 · .bak 0" "$(cmp -s "$(F "$R")" "$TMP/t3.orig" && echo same || echo changed) $(baks "$R")" "same 0"

# T4 — 선등록 master 후계(master 이름) retire → role=master 유지
R="$(repo t4 "{\"_master\": \"\", \"$O2\": $(retired "$N2"), \"$N2\": $(prereg "$O2")}")"
out="$(srun "$R" "$O2" "$N2")"; rc=$?
chk "T4 rc 0 · _master = 후계" "$rc $(J "$(F "$R")" ._master)" "0 $N2"
chk "T4 후계 role = master 유지" "$(J "$(F "$R")" ".[\"$N2\"].role")" master

# T5 — successor-open 선등록 role = 이름 토큰(byz-<팀>-<역할>-<에이전트>#N) · 토큰 밖 = stop-ready + stderr 1줄
awk '/^register_successor\(\) \{/{f=1} f&&/<<.PY./{p=1;next} p&&/^PY$/{exit} p' "$OPEN_KIT" > "$TMP/reg.py"
chk "T5 register_successor python 추출(1~)" "$([ -s "$TMP/reg.py" ] && echo yes || echo no)" yes
ERR=""; ROLE=""
reg_run() { local r="$TMP/reg-$1"; mkdir -p "$r/.fable-team"; git -C "$r" init -q
  printf '{"byz-planner-desk-claude#118": {"role": "desk", "agent": "claude"}}' > "$r/.fable-team/seats-planner.json"
  ERR="$(python3 "$TMP/reg.py" "$r" "$2" claude m wt "byz-planner-desk-claude#118" 2>&1 >/dev/null)"
  ROLE="$(jq -r --arg n "$2" '.[$n].role // "MISSING"' "$r/.fable-team/seats-planner.json")"; }
reg_run desk 'byz-planner-desk-claude#121'; chk "T5 desk 이름 → role=desk · stderr 0" "$ROLE|$ERR" "desk|"
reg_run master 'byz-planner-master-claude#121'; chk "T5 master 이름 → role=master" "$ROLE|$ERR" "master|"
reg_run nano 'byz-harness-nano-r1461-x#0'; chk "T5 토큰 밖 → role=stop-ready + stderr role 미도출 1줄" "$ROLE|$(grep -c 'role 미도출 byz-harness-nano-r1461-x#0' <<< "$ERR")" "stop-ready|1"
chk "T5 kit·skill 판 같은 도출 줄" "$(grep -c 'r1461 이름 토큰' "$OPEN_KIT") $(grep -c 'r1461 이름 토큰' "$OPEN_SK")" "1 1"

# T7 — 선등록 행(persona 접두 · _replaces 있음)인데 도출 role(_retired_role) ≠ 이름 토큰 → REJECT rc1 · 쓰기 0
R="$(repo t7 "{\"_desk\": \"\", \"$OLD\": {\"role\": \"stop-ready\", \"agent\": \"claude\", \"tick\": null, \"_replaced_by\": \"$NEW\", \"_retired_role\": \"master\"}, \"$NEW\": $(prereg "$OLD")}")"; cp "$(F "$R")" "$TMP/t7.orig"
out="$(srun "$R" "$OLD" "$NEW")"; rc=$?
chk "T7 rc 1 · REJECT" "$rc ${out%% *}" "1 REJECT"
chk "T7 명부 바이트 불변 · .bak 0" "$(cmp -s "$(F "$R")" "$TMP/t7.orig" && echo same || echo changed) $(baks "$R")" "same 0"

echo "fail=$fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit "$fail"
