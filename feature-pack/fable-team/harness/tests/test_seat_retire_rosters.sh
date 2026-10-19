#!/usr/bin/env bash
# test_seat_retire_rosters.sh — r429: ft-seat-retire.sh 가 같은 폴더(루트 .fable-team) 명부 전부의 «라우팅 칸»(_hil_route…)을 후계로 바꾼다 ·
#   r465 부터 역할 칸(_master·_arch)도 남의 명부까지(공유 arch) · 명부 1개 손상 = ERROR rc 1 · 쓰기 0. 모든 쓰기는 mktemp scratch 리포 — 실 명부 0 · 가짜 tmux(세션 없음).
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
chk "ⓐRETIRED 첫 줄 · files=3 · routes" "${out%%$'\n'*}" "RETIRED $OLD -> $NEW file=$(F "$R" seats-planner.json) keys=['_master', '_hil_route'] files=3 roles=['seats-a.json:_master'] routes=['seats-a.json:_hil_route', 'seats-a.json:_desk_route', 'seats.json:_hil_route']"
chk "ⓐ자기 명부 _master·_hil_route·_version" "$(J "$(F "$R" seats-planner.json)" '[._master,._hil_route,._version]|join(",")')" "$NEW,$NEW,x"
chk "ⓐseats.json _hil_route 후계 · _master 불변" "$(J "$(F "$R" seats.json)" '[._hil_route,._master]|join(",")')" "$NEW,byz-v65-master-claude#3"
chk "ⓐseats-a _hil_route·_desk_route 후계" "$(J "$(F "$R" seats-a.json)" '[._hil_route,._desk_route]|join(",")')" "$NEW,$NEW"
# ⓑ r465 — 남의 명부의 역할 칸(_master)도 값이 옛 이름이면 후계(같은 좌석 · 공유 역할 좌석)
chk "ⓑseats-a _master 후계(r465 · 역할 칸도 남의 명부까지)" "$(J "$(F "$R" seats-a.json)" ._master)" "$NEW"
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
# ⓒ' r465 — 옛 이름이 남의 명부 «역할 칸»(_master)에 있어도 R282 ② REJECT 0 · 그 칸도 후계(옛 판 = REJECT 라 손 편집 말고 길이 없었다)
R="$(repo c2)"; python3 - "$(F "$R" seats-planner.json)" "$OLD" <<'PY'
import json, sys; d = json.load(open(sys.argv[1])); d.pop(sys.argv[2]); json.dump(d, open(sys.argv[1], "w"))
PY
out="$(run "$R")"; rc=$?
chk "ⓒ' 남의 명부 _master → RETIRED rc 0 · seats-a _master 후계 · .bak 3" "$rc ${out%% *} $(J "$(F "$R" seats-a.json)" ._master) $(ls "$R/.fable-team"/*.bak-retire-* 2>/dev/null | wc -l | tr -d ' ')" "0 RETIRED $NEW 3"
# ⓓ 명부 1개 JSON 손상 → ERROR(그 파일) rc 1 · 모든 명부 바이트 불변 · .bak 0
R="$(repo d)"; printf '{"_hil_route": "%s",' "$OLD" > "$(F "$R" seats-b.json)"; mkdir -p "$TMP/d.orig"; cp "$R/.fable-team"/*.json "$TMP/d.orig/"
out="$(run "$R")"; rc=$?
chk "ⓓrc 1 · ERROR · 손상 파일 이름" "$rc ${out%% *} $(grep -c "seats-b.json" <<< "$out")" "1 ERROR 1"
chk "ⓓ명부 4개 바이트 불변" "$(for f in "$TMP/d.orig"/*.json; do cmp -s "$f" "$R/.fable-team/$(basename "$f")" || echo "changed $(basename "$f")"; done | wc -l | tr -d ' ')" 0
chk "ⓓ.bak·tmp 0" "$(ls "$R/.fable-team" | grep -c 'bak-retire\|\.tmp-')" 0
# ⓔ 시간 상한 600/300 0 (외부 호출 7초 룰)
chk "ⓔ600/300 0" "$(grep -cE '\b(600|300)\b' "$RETIRE")" 0
# r465 — 공유 역할 좌석(arch 262 가 v65 seats.json 의 행·_arch + lecture 명부 _arch) 승계 · NOOP 재실행 보정 · 빈 역할 칸 채우기
A1='byz-v65-arch-claude#262'; A2='byz-v65-arch-claude#263'; ROW='{"role": "arch", "agent": "claude", "model": "m", "tick": null}'
FA="$TMP/fake-alive"; mkdir -p "$FA"; printf '#!/usr/bin/env bash\n[ "$1" = has-session ] && [ "${3:-}" = "=${FAKE_ALIVE_NAME:-}" ] && exit 0\nexit 1\n' > "$FA/tmux"; chmod +x "$FA/tmux"
srepo() { # <라벨> <seats.json 내용> → scratch 리포(seats.json · seats-lecture · seats-room · seats-planner)
  local r="$TMP/s-$1"; mkdir -p "$r/.fable-team"; git -C "$r" init -q; printf '%s' "$2" > "$r/.fable-team/seats.json"
  printf '{"_master": "byz-lecture-master-claude#3", "_arch": "%s"}' "$A1" > "$r/.fable-team/seats-lecture.json"
  printf '{"_master": "byz-room-master-claude#1", "_hil_route": "%s"}' "$A1" > "$r/.fable-team/seats-room.json"
  printf '{"_master": "byz-planner-master-claude#9"}' > "$r/.fable-team/seats-planner.json"; echo "$r"; }
srun() { (cd "$1" && HOME="$TMP/home" PATH="$FA:$PATH" env -u FT_SEATS_JSON bash "$RETIRE" "${@:2}"); }
cells_old() { python3 -c 'import json,glob,sys; print(sum(1 for f in glob.glob(sys.argv[1]+"/.fable-team/seats*.json") for k,v in json.load(open(f)).items() if k.startswith("_") and v==sys.argv[2]))' "$1" "$2"; }
V65="{\"_master\": \"byz-v65-master-claude#211\", \"_arch\": \"$A1\", \"$A1\": $ROW}"
R="$(srepo a "$V65")"; cp "$(F "$R" seats-planner.json)" "$TMP/pl.orig"; out="$(srun "$R" "$A1" "$A2")"; rc=$?
chk "r465ⓐrc 0 · RETIRED 첫 줄 files=3 roles·routes" "$rc ${out%%$'\n'*}" "0 RETIRED $A1 -> $A2 file=$(F "$R" seats.json) keys=['_arch'] files=3 roles=['seats-lecture.json:_arch'] routes=['seats-room.json:_hil_route']"
chk "r465ⓐseats·lecture _arch · room _hil_route = 후계" "$(J "$(F "$R" seats.json)" ._arch) $(J "$(F "$R" seats-lecture.json)" ._arch) $(J "$(F "$R" seats-room.json)" ._hil_route)" "$A2 $A2 $A2"
chk "r465ⓐ파일마다 .bak 1(3) · planner 바이트 불변 · 옛 이름 칸 0" "$(ls "$R/.fable-team"/*.bak-retire-* | wc -l | tr -d ' ') $(cmp -s "$(F "$R" seats-planner.json)" "$TMP/pl.orig" && echo same || echo changed) $(cells_old "$R" "$A1")" "3 same 0"
# r465ⓑ 재실행(이미 은퇴)인데 lecture _arch 가 옛 이름 → 그 칸만 보정(FIXED) · 다시 = NOOP(멱등)
printf '{"_master": "byz-lecture-master-claude#3", "_arch": "%s"}' "$A1" > "$(F "$R" seats-lecture.json)"; cp "$(F "$R" seats.json)" "$TMP/v65.after"
out="$(srun "$R" "$A1" "$A2")"; rc=$?
chk "r465ⓑrc 0 · FIXED files=1 roles=[lecture]" "$rc ${out%%$'\n'*}" "0 FIXED $A1 -> $A2 file=$(F "$R" seats.json) keys=[] files=1 roles=['seats-lecture.json:_arch'] routes=[]"
chk "r465ⓑlecture _arch 후계 · seats.json 바이트 불변" "$(J "$(F "$R" seats-lecture.json)" ._arch) $(cmp -s "$(F "$R" seats.json)" "$TMP/v65.after" && echo same || echo changed)" "$A2 same"
out="$(srun "$R" "$A1" "$A2")"; chk "r465ⓑ세 번째 = NOOP" "${out%% *}" NOOP
# r465ⓒ 명부 1개 손상 → ERROR rc 1 · 바이트 불변 · .bak 0 (은퇴 전·NOOP 재실행 둘 다)
R="$(srepo c "$V65")"; printf '{"_master": ' > "$(F "$R" seats-planner.json)"; mkdir -p "$TMP/c.orig"; cp "$R/.fable-team"/*.json "$TMP/c.orig/"; out="$(srun "$R" "$A1" "$A2")"; rc=$?
chk "r465ⓒrc 1 · ERROR · 손상 파일 이름 · 바이트 불변 · .bak 0" "$rc ${out%% *} $(grep -c seats-planner.json <<< "$out") $(for f in "$TMP/c.orig"/*.json; do cmp -s "$f" "$R/.fable-team/$(basename "$f")" || echo x; done | wc -l | tr -d ' ') $(ls "$R/.fable-team" | grep -c 'bak-retire')" "1 ERROR 1 0 0"
R="$(srepo c2 "$V65")"; srun "$R" "$A1" "$A2" > /dev/null; printf '{"_arch": "%s",' "$A1" > "$(F "$R" seats-planner.json)"; out="$(srun "$R" "$A1" "$A2")"; rc=$?
chk "r465ⓒNOOP 경로도 손상 → ERROR rc 1" "$rc ${out%% *}" "1 ERROR"
# r465ⓓ 기존 REJECT 그대로 — 옛 이름이 어느 명부 키에도 없고 이름 lint 실패 · 후계가 이미 은퇴(rc 3)
R="$(srepo d "$V65")"; mkdir -p "$TMP/d2.orig"; cp "$R/.fable-team"/*.json "$TMP/d2.orig/"; out="$(srun "$R" 'X#1' 'X#2')"; rc=$?
chk "r465ⓓ명부 후보 0 + lint 실패 → REJECT rc 1 · 바이트 불변" "$rc ${out%% *} $(for f in "$TMP/d2.orig"/*.json; do cmp -s "$f" "$R/.fable-team/$(basename "$f")" || echo x; done | wc -l | tr -d ' ')" "1 REJECT 0"
R="$(srepo d3 "{\"_arch\": \"$A1\", \"$A1\": $ROW, \"$A2\": {\"role\": \"stop-ready\", \"_replaced_by\": \"byz-v65-arch-claude#264\"}}")"; out="$(srun "$R" "$A1" "$A2")"; rc=$?
chk "r465ⓓ후계 이미 은퇴 → rc 3 · lecture 불변 · .bak 0" "$rc $(J "$(F "$R" seats-lecture.json)" ._arch) $(ls "$R/.fable-team" | grep -c 'bak-retire')" "3 $A1 0"
# r465ⓔ close 262 — 옛 판(lecture _arch 잔존)은 «현역 역할 좌석» REJECT · r465 은퇴 뒤엔 그 REJECT 0
CLOSE="$HERE/../../harness/bin/ft-seat-close.sh"
R="$(srepo e0 "$V65")"; out="$(cd "$R" && HOME="$TMP/home" PATH="$FA:$PATH" env -u FT_SEATS_JSON bash "$CLOSE" "$A1" --reason r465 2>&1)"
chk "r465ⓔ대조: 은퇴 전 close → 현역 역할 좌석 REJECT" "$(grep -c '현역 역할 좌석' <<< "$out")" 1
R="$(srepo e "$V65")"; srun "$R" "$A1" "$A2" > /dev/null; out="$(cd "$R" && HOME="$TMP/home" PATH="$FA:$PATH" env -u FT_SEATS_JSON bash "$CLOSE" "$A1" --reason r465 2>&1)"
chk "r465ⓔ은퇴 뒤 close → 현역 역할 좌석 REJECT 0 · 옛 이름 칸 0" "$(grep -c '현역 역할 좌석' <<< "$out") $(cells_old "$R" "$A1")" "0 0"
# r465ⓕ 빈 역할 칸 채우기(사례 2 — close --verdict 가 _arch="" 로 비운 뒤 resume) · 살아 있는 다른 좌석이면 REJECT
NROW='{"role": "arch", "agent": "claude", "model": "m", "tick": null}'
R="$(srepo f "{\"_arch\": \"\", \"$A1\": $ROW, \"$A2\": $NROW}")"; out="$(srun "$R" "$A1" "$A2")"; rc=$?
chk "r465ⓕ은퇴 + 빈 _arch → FILLED · 값 후계" "$rc $(sed -n 1p <<< "$out" | grep -oE 'FILLED .*') $(J "$(F "$R" seats.json)" ._arch)" "0 FILLED seats.json:_arch $A2"
R="$(srepo f2 "{\"$A1\": {\"role\": \"stop-ready\", \"_replaced_by\": \"$A2\"}, \"$A2\": $NROW}")"; out="$(srun "$R" "$A1" "$A2")"; rc=$?
chk "r465ⓕNOOP 경로 + _arch 없음 → FIXED … FILLED (NOOP 아님)" "$rc ${out%% *} $(grep -oE 'FILLED .*' <<< "$out") $(J "$(F "$R" seats.json)" ._arch)" "0 FIXED FILLED seats.json:_arch $A2"
LIVE='byz-v65-arch-claude#300'; R="$(srepo f3 "{\"_arch\": \"$LIVE\", \"$A1\": {\"role\": \"stop-ready\", \"_replaced_by\": \"$A2\"}, \"$A2\": $NROW}")"; cp "$(F "$R" seats.json)" "$TMP/f3.orig"
out="$(cd "$R" && FAKE_ALIVE_NAME="$LIVE" HOME="$TMP/home" PATH="$FA:$PATH" env -u FT_SEATS_JSON bash "$RETIRE" "$A1" "$A2")"; rc=$?
chk "r465ⓕ_arch = 살아 있는 다른 좌석 → REJECT rc 1 · 쓰기 0" "$rc ${out%% *} $(cmp -s "$(F "$R" seats.json)" "$TMP/f3.orig" && echo same || echo changed) $(ls "$R/.fable-team" | grep -c 'bak-retire')" "1 REJECT same 0"
R="$(srepo f4 "{\"_arch\": \"$LIVE\", \"$A1\": {\"role\": \"stop-ready\", \"_replaced_by\": \"$A2\"}, \"$A2\": $NROW}")"; out="$(srun "$R" "$A1" "$A2")"
chk "r465ⓕ_arch = 죽은 다른 좌석 → 채우기 0 (추측 0) · lecture·room 만 보정" "$(J "$(F "$R" seats.json)" ._arch) $(grep -c FILLED <<< "$out") ${out%% *}" "$LIVE 0 FIXED"
# r499 — 옛 행이 이미 stop-ready(은퇴 전 닫힘 표기)면 후계 role = _retired_role → 역할 칸 → 이름 토큰 · 재실행도 stop-ready 꼴 현역 후계를 고침
trepo() { local r="$TMP/t-$1"; mkdir -p "$r/.fable-team"; git -C "$r" init -q; printf '%s' "$2" > "$r/.fable-team/seats.json"; echo "$r"; }
SR='{"role": "stop-ready", "agent": "claude", "model": "m", "tick": null}'
R="$(trepo g "{\"_arch\": \"$A1\", \"$A1\": $SR}")"; out="$(srun "$R" "$A1" "$A2")"; rc=$?
chk "r499ⓖ옛 stop-ready·_retired_role 없음·후계 행 없음 → rc 0 · 첫 줄 role stop-ready->arch" "$rc ${out%%$'\n'*}" "0 RETIRED $A1 -> $A2 file=$(F "$R" seats.json) keys=['_arch'] files=1 roles=[] routes=[] role stop-ready->arch"
chk "r499ⓖ후계 role=arch · _arch 후계 · 옛 행 _retired_role 안 씀(추측 0)" "$(J "$(F "$R" seats.json)" "[.[\"$A2\"].role, ._arch, (.[\"$A1\"]|has(\"_retired_role\"))]|map(tostring)|join(\",\")")" "arch,$A2,false"
R="$(trepo h "{\"_arch\": \"$A1\", \"$A1\": {\"role\": \"stop-ready\", \"_retired_role\": \"master\", \"agent\": \"claude\", \"tick\": null}}")"; out="$(srun "$R" "$A1" "$A2")"; rc=$?
chk "r499ⓗ옛 _retired_role=master → 후계 role=master (역할 칸보다 먼저)" "$rc $(J "$(F "$R" seats.json)" ".[\"$A2\"].role") $(grep -oE 'role stop-ready->[a-z]+' <<< "$out")" "0 master role stop-ready->master"
R="$(trepo i "{\"_arch\": \"$A1\", \"$A1\": $SR, \"$A2\": $SR}")"; out="$(srun "$R" "$A1" "$A2")"; rc=$?
chk "r499ⓘ후계 행 있음·stop-ready·_replaced_by 없음 → 도출 role · 출력 role stop-ready->arch" "$rc ${out%% *} $(J "$(F "$R" seats.json)" ".[\"$A2\"].role") $(grep -oE 'role stop-ready->[a-z]+' <<< "$out")" "0 RETIRED arch role stop-ready->arch"
R="$(trepo i2 "{\"_arch\": \"$A1\", \"$A1\": $ROW, \"$A2\": $NROW}")"; out="$(srun "$R" "$A1" "$A2")"
chk "r499ⓘ대조: 정상 승계(옛 arch · 후계 arch) → role 꼬리 0" "$(J "$(F "$R" seats.json)" ".[\"$A2\"].role") $(grep -c 'role stop-ready->' <<< "$out")" "arch 0"
R="$(trepo j "{\"_arch\": \"$A2\", \"$A1\": {\"role\": \"stop-ready\", \"_replaced_by\": \"$A2\"}, \"$A2\": $SR}")"; out="$(srun "$R" "$A1" "$A2")"; rc=$?
chk "r499ⓙ재실행(NOOP 자리) + 현역 후계 stop-ready 꼴 → FIXED … role stop-ready->arch rc 0" "$rc ${out%%$'\n'*}" "0 FIXED $A1 -> $A2 file=$(F "$R" seats.json) keys=[] files=1 roles=[] routes=[] role stop-ready->arch"
chk "r499ⓙ후계 role=arch · .bak 1 · 다시 = NOOP" "$(J "$(F "$R" seats.json)" ".[\"$A2\"].role") $(ls "$R/.fable-team" | grep -c 'bak-retire') $(srun "$R" "$A1" "$A2" | head -1 | cut -d' ' -f1)" "arch 1 NOOP"
N1='byz-harness-nano-r1-x#0'; N2='byz-harness-nano-r1-x#1'; R="$(trepo j2 "{\"_master\": \"byz-harness-master-claude#1\", \"$N1\": {\"role\": \"stop-ready\", \"_replaced_by\": \"$N2\"}, \"$N2\": $SR}")"; cp "$(F "$R" seats.json)" "$TMP/j2.orig"; out="$(srun "$R" "$N1" "$N2")"; rc=$?
chk "r499ⓙ역할 칸 값 아님·_retired_role 없음·이름 토큰 nano → 고치지 않음(NOOP 그대로 · 바이트 불변)" "$rc ${out%% *} $(cmp -s "$(F "$R" seats.json)" "$TMP/j2.orig" && echo same || echo changed)" "0 NOOP same"
# ⑧ 짝 cmp0 (bin ↔ kit)
chk "짝 cmp0" "$(cmp -s "$RETIRE" "$HERE/../kit/fable-team/bin/ft-seat-retire.sh" && echo same || echo diff)" same
chk "짝 cmp0 (ft_roster_lib.py · r465)" "$(cmp -s "$(dirname "$RETIRE")/ft_roster_lib.py" "$HERE/../kit/fable-team/bin/ft_roster_lib.py" && echo same || echo diff)" same

echo "fail=$fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit "$fail"
