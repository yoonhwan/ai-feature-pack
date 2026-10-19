#!/usr/bin/env bash
# test_seat_retire_rosters.sh — r429: ft-seat-retire.sh 가 같은 폴더(루트 .fable-team) 명부 전부의 «라우팅 칸»(_hil_route…)을 후계로 바꾼다 ·
#   역할 칸(_master·_arch)은 자기 팀 명부만 · 명부 1개 손상 = ERROR rc 1 · 쓰기 0. 모든 쓰기는 mktemp scratch 리포 — 실 명부 0 · 가짜 tmux(세션 없음).
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
RETIRE="$HERE/../../harness/bin/ft-seat-retire.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT; TMP="$(cd "$TMP" && pwd -P)"   # 루트 = git common dir(실경로 · macOS /private)
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
J() { jq -r "$2" "$1"; }
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$TMP/reap-stub.sh"; export FT_SEAT_REAP_BIN="$TMP/reap-stub.sh"   # r448: 은퇴의 reap = 스텁(실기계 프로세스 0 · test_seat_retire.sh 와 같은 꼴)
FK="$TMP/fake"; mkdir -p "$FK"; printf '#!/usr/bin/env bash\nexit 1\n' > "$FK/tmux"; chmod +x "$FK/tmux"   # 결속 0 → NORECORD(은퇴 결과와 분리)
OLD='byz-planner-master-claude#9'; NEW='byz-planner-master-claude#10'
repo() { # <라벨> → scratch 리포(.fable-team 에 seats-planner·seats.json·seats-a·seats-b)
  local r="$TMP/r-$1"; mkdir -p "$r/.fable-team"; git -C "$r" init -q
  printf '{"_master": "%s", "_hil_route": "%s", "_version": "x", "%s": {"role": "master", "agent": "claude", "model": "m", "tick": "t"}}' "$OLD" "$OLD" "$OLD" > "$r/.fable-team/seats-planner.json"
  printf '{"_master": "byz-v65-master-claude#3", "_hil_route": "%s"}' "$OLD" > "$r/.fable-team/seats.json"
  printf '{"_master": "%s", "_hil_route": "%s", "_desk_route": "%s"}' "$OLD" "$OLD" "$OLD" > "$r/.fable-team/seats-a.json"   # ⓑ _master 가 우연히 같은 이름
  printf '{"_master": "byz-b-master-claude#1", "_hil_route": "byz-other#1"}' > "$r/.fable-team/seats-b.json"
  echo "$r"; }
run() { (cd "$1" && HOME="$TMP/home" PATH="$FK:$PATH" env -u FT_SEATS_JSON bash "$RETIRE" "$OLD" "$NEW" "${@:2}"); }
F() { echo "$1/.fable-team/$2"; }

bash -n "$RETIRE" && ok "bash -n" || bad "bash -n"
chk "ft-seat-retire.sh ≤ 200줄" "$([ "$(wc -l < "$RETIRE")" -le 200 ] && echo yes || echo no)" yes
# ⓐ planner master 교대 → 자기 명부 _master·_hil_route + 남의 명부 2곳 _hil_route(+ _desk_route) 후계 · files=3
R="$(repo a)"; cp "$(F "$R" seats-b.json)" "$TMP/b.orig"; out="$(run "$R")"; rc=$?
chk "ⓐrc 0" "$rc" 0
chk "ⓐRETIRED 첫 줄 · files=3 · routes" "${out%%$'\n'*}" "RETIRED $OLD -> $NEW file=$(F "$R" seats-planner.json) keys=['_master', '_hil_route'] files=3 routes=['seats-a.json:_hil_route', 'seats-a.json:_desk_route', 'seats.json:_hil_route']"
chk "ⓐ자기 명부 _master·_hil_route·_version" "$(J "$(F "$R" seats-planner.json)" '[._master,._hil_route,._version]|join(",")')" "$NEW,$NEW,x"
chk "ⓐseats.json _hil_route 후계 · _master 불변" "$(J "$(F "$R" seats.json)" '[._hil_route,._master]|join(",")')" "$NEW,byz-v65-master-claude#3"
chk "ⓐseats-a _hil_route·_desk_route 후계" "$(J "$(F "$R" seats-a.json)" '[._hil_route,._desk_route]|join(",")')" "$NEW,$NEW"
# ⓑ 남의 명부의 역할 칸(_master)은 같은 이름이어도 그대로
chk "ⓑseats-a _master 불변(역할 칸은 자기 팀만)" "$(J "$(F "$R" seats-a.json)" ._master)" "$OLD"
chk "ⓑ관계없는 seats-b 바이트 불변 · .bak 0" "$(cmp -s "$(F "$R" seats-b.json)" "$TMP/b.orig" && echo same || echo changed) $(ls "$R/.fable-team"/seats-b.json.bak-retire-* 2>/dev/null | wc -l | tr -d ' ')" "same 0"
chk "ⓑ바뀐 파일마다 .bak 1개(planner·seats·a = 3)" "$(ls "$R/.fable-team"/*.bak-retire-* | wc -l | tr -d ' ')" 3
chk "ⓑtmp 잔류 0" "$(ls "$R/.fable-team" | grep -c '\.tmp-')" 0
out="$(run "$R")"; chk "ⓑ두 번째 호출 NOOP" "${out%% *}" NOOP
# ⓒ 옛 행이 어느 명부에도 없음 → R282 ② 그대로(팀 명부에 은퇴 행 생성 뒤 은퇴) · 남의 명부 _hil_route 가 옛 이름이어도 REJECT 0
R="$(repo c)"; python3 - "$(F "$R" seats-planner.json)" "$OLD" "$(F "$R" seats-a.json)" <<'PY'
import json, sys; d = json.load(open(sys.argv[1])); d.pop(sys.argv[2]); json.dump(d, open(sys.argv[1], "w"))
a = json.load(open(sys.argv[3])); a["_master"] = "byz-a-master-claude#1"; json.dump(a, open(sys.argv[3], "w"))
PY
out="$(run "$R")"; rc=$?
chk "ⓒrc 0 · RETIRED · files=3" "$rc $(sed -n 1p <<< "$out" | sed -E 's/^(RETIRED) .* (files=[0-9]+) .*/\1 \2/')" "0 RETIRED files=3"
chk "ⓒ은퇴 행 생성(_created_by=retire · _replaced_by)" "$(J "$(F "$R" seats-planner.json)" ".[\"$OLD\"]|[._created_by,._replaced_by]|join(\",\")")" "retire,$NEW"
chk "ⓒ자기 명부 _master + 남의 명부 _hil_route 후계" "$(J "$(F "$R" seats-planner.json)" ._master) $(J "$(F "$R" seats.json)" ._hil_route) $(J "$(F "$R" seats-a.json)" ._hil_route)" "$NEW $NEW $NEW"
# ⓒ' 옛 이름이 남의 명부 «역할 칸»(_master)에서 현역이면 R282 ② REJECT 그대로 — seats-a 의 _master 가 그 경우
R="$(repo c2)"; python3 - "$(F "$R" seats-planner.json)" "$OLD" <<'PY'
import json, sys; d = json.load(open(sys.argv[1])); d.pop(sys.argv[2]); json.dump(d, open(sys.argv[1], "w"))
PY
out="$(run "$R")"; rc=$?
chk "ⓒ' 남의 명부 _master 현역 → REJECT rc 1 · .bak 0" "$rc ${out%% *} $(ls "$R/.fable-team"/*.bak-retire-* 2>/dev/null | wc -l | tr -d ' ')" "1 REJECT 0"
# ⓓ 명부 1개 JSON 손상 → ERROR(그 파일) rc 1 · 모든 명부 바이트 불변 · .bak 0
R="$(repo d)"; printf '{"_hil_route": "%s",' "$OLD" > "$(F "$R" seats-b.json)"; mkdir -p "$TMP/d.orig"; cp "$R/.fable-team"/*.json "$TMP/d.orig/"
out="$(run "$R")"; rc=$?
chk "ⓓrc 1 · ERROR · 손상 파일 이름" "$rc ${out%% *} $(grep -c "seats-b.json" <<< "$out")" "1 ERROR 1"
chk "ⓓ명부 4개 바이트 불변" "$(for f in "$TMP/d.orig"/*.json; do cmp -s "$f" "$R/.fable-team/$(basename "$f")" || echo "changed $(basename "$f")"; done | wc -l | tr -d ' ')" 0
chk "ⓓ.bak·tmp 0" "$(ls "$R/.fable-team" | grep -c 'bak-retire\|\.tmp-')" 0
# ⓔ 시간 상한 600/300 0 (외부 호출 7초 룰)
chk "ⓔ600/300 0" "$(grep -cE '\b(600|300)\b' "$RETIRE")" 0
# ⑧ 짝 cmp0 (bin ↔ kit)
chk "짝 cmp0" "$(cmp -s "$RETIRE" "$HERE/../kit/fable-team/bin/ft-seat-retire.sh" && echo same || echo diff)" same

echo "fail=$fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit "$fail"
