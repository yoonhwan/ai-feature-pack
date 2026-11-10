#!/usr/bin/env bash
# test_seat_retire_old_name_lint.sh — r573: ft-seat-retire.sh R282 ② 갈래에서 옛 이름이 ft-name-lint 를 못 넘으면
#   «후계» 이름(lint 통과 필수)에서 팀·역할·에이전트를 뽑아 은퇴 행을 만든다 · 후계도 lint 실패 = 지금처럼 REJECT.
#   옛 이름이 다른 명부 `_*` 칸의 현역이면 이 갈래보다 «먼저» REJECT(쓰기 0). 모든 쓰기는 mktemp scratch 리포 — 실 명부 0 · 가짜 tmux(세션 없음).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
RETIRE="${FT_RETIRE_BIN:-$HERE/../../harness/bin/ft-seat-retire.sh}"   # FT_RETIRE_BIN = 대조용 옛 판 주입(증거용 · 기본 = 현행)
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT; TMP="$(cd "$TMP" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
J() { jq -r "$2" "$1"; }
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$TMP/reap-stub.sh"; export FT_SEAT_REAP_BIN="$TMP/reap-stub.sh"
FK="$TMP/fake"; mkdir -p "$FK"; printf '#!/usr/bin/env bash\nexit 1\n' > "$FK/tmux"; chmod +x "$FK/tmux"   # 결속 0 → NORECORD(은퇴 결과와 분리)
repo() { # <라벨> → scratch 리포(.fable-team = seats-aifp.json · seats-planner.json · seats-b.json)
  local r="$TMP/r-$1"; mkdir -p "$r/.fable-team"; git -C "$r" init -q
  printf '{"_master": "old-aifp-master-pi#0", "_name": "Seatbelt-AIFP"}' > "$r/.fable-team/seats-aifp.json"
  printf '{"_master": "byz-planner-master-claude#9"}' > "$r/.fable-team/seats-planner.json"
  printf '{"_master": "byz-b-master-claude#1", "_hil_route": "byz-other#1"}' > "$r/.fable-team/seats-b.json"
  echo "$r"; }
run() { (cd "$1" && HOME="$TMP/home" PATH="$FK:$PATH" env -u FT_SEATS_JSON bash "$RETIRE" "${@:2}"); }
F() { echo "$1/.fable-team/$2"; }
snap() { mkdir -p "$TMP/snap-$2"; cp "$1/.fable-team"/*.json "$TMP/snap-$2/"; }
same_as() { for f in "$TMP/snap-$1"/*.json; do cmp -s "$f" "$2/.fable-team/$(basename "$f")" || echo "changed $(basename "$f")"; done | wc -l | tr -d ' '; }

bash -n "$RETIRE" && ok "bash -n" || bad "bash -n"
chk "ft-seat-retire.sh ≤ 200줄" "$([ "$(wc -l < "$RETIRE")" -le 200 ] && echo yes || echo no)" yes
# ⓐ(실패 시험 먼저) 옛 이름 lint 실패(에이전트 꼬리 없음) · 후계 lint PASS → 후계에서 팀·역할·에이전트 · 지금 판 = REJECT rc 1
OLD='old-aifp-master#1'; NEW='old-aifp-master-pi#0'
chk "ⓐ전제: 옛 이름 lint REJECT" "$(bash "$HERE/../kit/fable-team/bin/ft-name-lint.sh" "$OLD" >/dev/null 2>&1; echo $?)" 1
chk "ⓐ전제: 후계 lint PASS" "$(bash "$HERE/../kit/fable-team/bin/ft-name-lint.sh" "$NEW" >/dev/null 2>&1; echo $?)" 0
R="$(repo a)"; snap "$R" a; out="$(run "$R" "$OLD" "$NEW")"; rc=$?
chk "ⓐrc 0 · RETIRED 줄 1개" "$rc $(grep -c "^RETIRED $OLD -> $NEW" <<< "$out")" "0 1"
chk "ⓐINFO 줄 — 후계 이름으로 팀·역할·에이전트" "$(grep -c "INFO 옛 이름 lint 실패 — 후계 $NEW 이름으로 팀·역할·에이전트" <<< "$out")" 1
chk "ⓐ은퇴 행 = 후계 팀 명부(seats-aifp) role·agent = 후계 칸" "$(J "$(F "$R" seats-aifp.json)" ".[\"$OLD\"]|[._retired_role,.agent,._created_by,._replaced_by]|join(\",\")")" "master,pi,retire,$NEW"
chk "ⓐ후계 행 role master · _replaces 옛 이름" "$(J "$(F "$R" seats-aifp.json)" ".[\"$NEW\"]|[.role,(._replaces|join(\"\"))]|join(\",\")")" "master,$OLD"
chk "ⓐ재개 기록 결과 1줄(RESUME|NORECORD)" "$(grep -cE '^(RESUME|NORECORD)' <<< "$out")" 1
chk "ⓐ$NEW 가 아닌 명부에 옛 이름 칸 0" "$(grep -c "$OLD" "$(F "$R" seats-b.json)")" 0
# ⓑ 옛 이름 lint PASS → 지금 동작 그대로(옛 이름에서 칸 뽑기 · INFO 0)
O2='byz-planner-master-claude#9'; N2='byz-planner-master-claude#10'
R="$(repo b)"; out="$(run "$R" "$O2" "$N2")"; rc=$?
chk "ⓑrc 0 · RETIRED · INFO 0" "$rc $(cut -d' ' -f1 <<< "${out%%$'\n'*}") $(grep -c '^INFO' <<< "$out")" "0 RETIRED 0"
chk "ⓑ은퇴 행 = 옛 이름 팀 명부(seats-planner) role·agent 옛 칸" "$(J "$(F "$R" seats-planner.json)" ".[\"$O2\"]|[._retired_role,.agent,._replaced_by]|join(\",\")")" "master,claude,$N2"
# ⓒ 옛·후계 둘 다 lint 실패 → REJECT rc 1 그대로 · 이유에 «후계도 이름 lint 실패» · 쓰기 0
R="$(repo c)"; snap "$R" c; out="$(run "$R" 'tmm' 'tmm2')"; rc=$?
chk "ⓒrc 1 · REJECT · 후계도 lint 실패 문구" "$rc $(cut -d' ' -f1 <<< "${out%%$'\n'*}") $(grep -c '후계도 이름 lint 실패' <<< "$out")" "1 REJECT 1"
chk "ⓒ명부 3개 바이트 불변 · .bak 0" "$(same_as c "$R") $(ls "$R/.fable-team" | grep -c 'bak-retire')" "0 0"
# ⓓ 옛 이름 lint 실패 ∧ 다른 명부 `_*` 칸에 현역 → 이 갈래보다 먼저 REJECT(쓰기 0)
R="$(repo d)"; printf '{"_master": "%s", "_hil_route": "old-aifp-master-pi#0"}' "$OLD" > "$(F "$R" seats-b.json)"; snap "$R" d
out="$(run "$R" "$OLD" "$NEW")"; rc=$?
chk "ⓓrc 1 · REJECT · 다른 명부 _* 칸의 현역" "$rc $(cut -d' ' -f1 <<< "${out%%$'\n'*}") $(grep -cF '다른 명부 `_*` 칸의 현역' <<< "$out")" "1 REJECT 1"
chk "ⓓ명부 3개 바이트 불변 · .bak 0 · INFO 0" "$(same_as d "$R") $(ls "$R/.fable-team" | grep -c 'bak-retire') $(grep -c '^INFO' <<< "$out")" "0 0 0"
# 짝 cmp0 (bin ↔ kit)
chk "짝 cmp0" "$(cmp -s "$RETIRE" "$HERE/../kit/fable-team/bin/ft-seat-retire.sh" && echo same || echo diff)" same

echo "fail=$fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit "$fail"
