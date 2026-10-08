#!/usr/bin/env bash
# test_seat_retire.sh — R43: 틱 정지 감시는 _master 아닌 옛 role=master 행을 건너뛴다 · ft-seat-retire.sh · ft-role-spawn.sh 옛 행 닫기.
# 모든 쓰기는 mktemp scratch 안 — 라이브 좌석표·stamp·tmux 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../scripts/fable-team-bin"
TICK="$BIN/ft-tick.sh"; RETIRE="$BIN/ft-seat-retire.sh"; SPAWN="$BIN/ft-role-spawn.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
J() { jq -r "$2" "$1"; }

for f in "$TICK" "$RETIRE" "$SPAWN"; do bash -n "$f" && ok "bash -n $(basename "$f")" || bad "bash -n $f"; done
chk "ft-seat-retire.sh ≤ 80줄" "$([ "$(wc -l < "$RETIRE")" -le 80 ] && echo yes || echo no)" yes

# ①② 틱 stall 대상 (dry-run) · all_seats 는 함수 추출
stall_seats() { # <좌석표 json>
  printf '%s' "$1" > "$TMP/s.json"
  FT_TICK_IDLE_ENABLED=0 FT_TICK_WT_SWEEP=0 FT_TICK_DRIFT=0 FT_TICK_SEATS="$TMP/s.json" FT_TICK_STAMP_PREFIX="$TMP/p-" FT_TICK_STATE_DIR="$TMP/st" \
    bash "$TICK" --once --dry-run 2>&1 | sed -n 's/^DRY kind=stall .* seats=//p' | xargs
}
all_seats() { printf '%s' "$1" > "$TMP/s.json"; bash -c "SEATS=$TMP/s.json; $(sed -n '/^all_seats() {/,/^}/p' "$TICK")"$'\n''all_seats' | cut -f1 | xargs; }
ROW='"role": "master", "tick": "ft-master-tick"'
WITH="{\"_master\": \"M#2\", \"M#1\": {$ROW}, \"M#2\": {\"role\": \"master\", \"tick\": null}, \"N#0\": {\"role\": \"nano\"}}"
chk "①stall: 옛 M#1 제외 · M#2·N#0 포함" "$(stall_seats "$WITH")" "M#2 N#0"
chk "①all_seats: 옛 M#1 제외" "$(all_seats "$WITH")" "M#2 N#0"
WITHOUT="{\"M#1\": {$ROW}, \"M#2\": {\"role\": \"master\"}, \"N#0\": {\"role\": \"nano\"}}"
chk "②_master 없음 → 무변경(M#1 M#2 N#0)" "$(stall_seats "$WITHOUT")" "M#1 M#2 N#0"
chk "②all_seats _master 없음 → 무변경" "$(all_seats "$WITHOUT")" "M#1 M#2 N#0"
chk "②_master 문자열 아님 → 무변경" "$(stall_seats "{\"_master\": 7, \"M#1\": {$ROW}, \"M#2\": {\"role\": \"master\"}}")" "M#1 M#2"

# ③ retire 정상
S="$TMP/seats-a.json"; printf '%s' "{\"_master\": \"M#1\", \"_hil_route\": \"M#1\", \"_version\": \"x\", \"M#1\": {\"role\": \"master\", \"agent\": \"claude\", \"model\": \"m1\", \"tick\": \"ft-master-tick\"}}" > "$S"
out="$(bash "$RETIRE" 'M#1' 'M#2' --seats "$S")"; rc=$?
chk "③rc" "$rc" 0
chk "③출력 1줄" "$out" "RETIRED M#1 -> M#2 file=$S keys=['_master', '_hil_route']"
chk "③구 행 _replaced_by·role·_retired_role·tick" "$(J "$S" '[.["M#1"]._replaced_by, .["M#1"].role, .["M#1"]._retired_role, (.["M#1"].tick|tostring)]|join(",")')" "M#2,stop-ready,master,null"
chk "③후계 행 생성(role·agent·model·tick·_replaces)" "$(J "$S" '.["M#2"]|[.role,.agent,.model,.tick,(._replaces|join("+"))]|join(",")')" "master,claude,m1,ft-master-tick,M#1"
chk "③_master·_hil_route → M#2" "$(J "$S" '[._master,._hil_route,._version]|join(",")')" "M#2,M#2,x"
chk "③백업 1개" "$(ls "$S".bak-retire-* 2>/dev/null | wc -l | tr -d ' ')" 1

# ⑤ 두 번째 호출 NOOP (바이트 불변)
cp "$S" "$TMP/after1.json"
out="$(bash "$RETIRE" 'M#1' 'M#2' --seats "$S")"; rc=$?
chk "⑤NOOP rc" "$rc" 0
chk "⑤NOOP 출력" "${out%% *}" NOOP
chk "⑤바이트 불변" "$(cmp -s "$S" "$TMP/after1.json" && echo same || echo changed)" same

# ④ 후계 은퇴 → rc 3 · 바이트 그대로
S="$TMP/seats-b.json"; printf '%s' '{"_master": "M#1", "M#1": {"role": "master", "tick": "t"}, "M#2": {"role": "stop-ready", "tick": null, "_replaced_by": "M#9"}}' > "$S"; cp "$S" "$TMP/b.orig"
bash "$RETIRE" 'M#1' 'M#2' --seats "$S" > /dev/null; rc=$?
chk "④rc 3" "$rc" 3
chk "④파일 바이트 그대로" "$(cmp -s "$S" "$TMP/b.orig" && echo same || echo changed)" same
chk "④백업 0" "$(ls "$S".bak-retire-* 2>/dev/null | wc -l | tr -d ' ')" 0

# ⑥ 명부 2개에 같은 키 → rc 1 · 쓰기 0 (루트 탐색: git 리포 scratch)
R="$TMP/repo"; mkdir -p "$R/.fable-team"; git -C "$R" init -q
printf '%s' '{"M#1": {"role": "master"}}' > "$R/.fable-team/seats.json"; printf '%s' '{"M#1": {"role": "master"}}' > "$R/.fable-team/seats-x.json"
(cd "$R" && env -u FT_SEATS_JSON bash "$RETIRE" 'M#1' 'M#2' > "$TMP/six.out"); rc=$?
chk "⑥rc 1" "$rc" 1
chk "⑥쓰기 0(백업·후계 행 없음)" "$(ls "$R/.fable-team" | grep -c bak; jq 'has("M#2")' "$R/.fable-team/seats.json")" $'0\nfalse'
rm "$R/.fable-team/seats-x.json"
(cd "$R" && env -u FT_SEATS_JSON bash "$RETIRE" 'M#1' 'M#2' > /dev/null); rc=$?
chk "⑥b 후보 1개 → 자동 선택 rc 0" "$rc" 0
chk "⑥b 구 행 은퇴" "$(J "$R/.fable-team/seats.json" '.["M#1"]._replaced_by')" "M#2"

# ⑦ role-spawn 옛 행 닫기 — 스크립트의 두 번째 python 블록만 추출해 임시 명부에 돌린다(tmux 0)
sed -n '/^python3 - "\$SEATS" "\$NAME"/,/^PY$/p' "$SPAWN" | sed '1d;$d' > "$TMP/spawn_block.py"
chk "⑦블록 추출(비어 있지 않음)" "$([ -s "$TMP/spawn_block.py" ] && echo yes || echo no)" yes
S="$TMP/seats-c.json"; printf '%s' '{"_master": "B#1", "_hil_route": "B#1", "B#1": {"role": "master", "agent": "claude", "tick": "ft-master-tick"}, "B#0": {"role": "master", "_replaced_by": "B#1", "tick": null}}' > "$S"
python3 "$TMP/spawn_block.py" "$S" 'B#2' master claude m2 design/inbox/master B B
chk "⑦옛 행 B#1 닫힘" "$(J "$S" '.["B#1"]|[._replaced_by,.role,._retired_role,(.tick|tostring)]|join(",")')" "B#2,stop-ready,master,null"
chk "⑦_master·_hil_route → B#2" "$(J "$S" '[._master,._hil_route]|join(",")')" "B#2,B#2"
chk "⑦새 행 tick 상속·_replaces" "$(J "$S" '.["B#2"]|[.tick,(._replaces|join("+"))]|join(",")')" "ft-master-tick,B#1"
chk "⑦이미 닫힌 B#0 불변" "$(J "$S" '.["B#0"]|[._replaced_by,.role]|join(",")')" "B#1,master"

# ⑧ 기존 시험
for t in test_ft_tick_master_seat.sh test_role_spawn_name.sh test_kit_bin_sync.sh; do
  bash "$HERE/$t" > "$TMP/$t.out" 2>&1; chk "⑧$t rc=0" "$?" 0
done

echo "fail=$fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit "$fail"
