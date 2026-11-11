#!/usr/bin/env bash
# test_seat_close_renamed_lineage_r1691.sh — r1691: 이름 접두가 바뀐 승계도 네 근거가 다 서면 표준 닫기(kill). 하나라도 빠지면 held rc 3 그대로.
#   ⓐ 네 근거 → CLOSED-SESSION kill=ok + `lineage=renamed:<후계>` ⓑ _replaces 에 옛 좌석 없음 ⓒ 후계 세션 없음 ⓓ 재개 기록 없음 ⓔ 후계 행이 은퇴 → held rc 3(옛 세션 살아 있음)
#   ⓕ 같은 이름 계보(r1691t#0→#1) = 지금과 같은 출력(`lineage=` 0) ⓖ 명부 JSON 깨짐 = CLOSED 0 · kill 0 · ⓗ 회귀는 이 파일 밖(test_seat_close*.sh rc0 · RUN 줄)
#   픽스처: 실 tmux 세션 이름 = 이 회차 pid 꼴 · 임시 명부·가짜 재개 기록·reap 스텁(left=0) · 실 명부·실 좌석 쓰기 0 · sleep 0
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$HERE/../bin"; CLOSE="$BIN/ft-seat-close.sh"
T0="$(mktemp -d)"; TMP="$(cd "$T0" && pwd -P)"; PID=$$
O="byz-r1691o-$PID#0"; N="r1691n-$PID#0"; S1="r1691t-$PID#0"; S2="r1691t-$PID#1"
cleanup() { local s; for s in "$O" "$N" "$S1" "$S2"; do tmux kill-session -t "=$s" 2>/dev/null; done; rm -rf "$T0"; }
trap cleanup EXIT INT TERM
mkdir -p "$TMP/wt" "$TMP/resume" "$TMP/cf/comm"; git -C "$TMP/wt" init -q
printf '#!/bin/sh\necho "reap left=0"\nexit 0\n' > "$TMP/reap0.sh"
printf 'print("CLOSE-OK stub")\n' > "$TMP/mbox-stub.py"
export ZC_RESUME_DIR="$TMP/resume" FT_SEAT_REAP_BIN="$TMP/reap0.sh" FT_MBOX_PY="$TMP/mbox-stub.py"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
mksess() { tmux kill-session -t "=$1" 2>/dev/null; tmux new-session -d -s "$1" -c "$TMP/wt" "sleep 300"; }
up() { tmux has-session -t "=$1" 2>/dev/null && echo up || echo gone; }
mkseats() {  # mkseats <모드> — normal | noreplicates | retired | same | broken
  if [ "$1" = broken ]; then printf '{"_master": "M#1", %s: {' "$O" > "$TMP/cf/seats.json"; return; fi
  python3 - "$TMP/cf/seats.json" "$O" "$N" "$S1" "$S2" "$1" <<'PY'
import json, sys
p, o, n, s1, s2, mode = sys.argv[1:7]
if mode == "same":
    d = {"_master": "M#1", "M#1": {"role": "master"}, s1: {"role": "tester", "agent": "claude", "tick": None}, s2: {"role": "tester", "agent": "claude", "tick": None}}
else:
    old = {"role": "stop-ready", "_replaced_by": n, "_retired_role": "arch"}
    new = {"role": "arch", "agent": "claude", "_replaces": [o]}
    if mode == "noreplicates": new.pop("_replaces")
    if mode == "retired": new["_replaced_by"] = "x#9"   # 후계가 이미 은퇴
    d = {"_master": "M#1", "M#1": {"role": "master"}, o: old, n: new}
open(p, "w", encoding="utf-8").write(json.dumps(d, ensure_ascii=False))
PY
}
run() { out="$(cd "$TMP/wt" && bash "${CL:-$CLOSE}" "$1" --reason "r1691 시험" --seats "$TMP/cf/seats.json" 2>/dev/null)"; rc=$?; }
first() { head -1 <<<"$out"; }
fresh() { rm -f "$TMP/resume/$O.json" "$TMP/resume/$S1.json"; tmux kill-session -t "=$O" 2>/dev/null; tmux kill-session -t "=$N" 2>/dev/null; }

echo "== ⓐ 네 근거 모두 → CLOSED-SESSION · kill=ok · lineage=renamed:<후계>"
mkseats normal; mksess "$O"; mksess "$N"; : > "$TMP/resume/$O.json"; run "$O"
chk "ⓐ rc0 · CLOSED-SESSION · kill=ok" "$rc $(first | grep -c '^CLOSED-SESSION.*kill=ok')" "0 1"
chk "ⓐ 결과 줄 lineage=renamed:$N" "$(first | grep -c "lineage=renamed:$N")" 1
chk "ⓐ 옛 세션 gone · 후계 up" "$(up "$O") $(up "$N")" "gone up"

echo "== ⓑ 후계 _replaces 에 옛 좌석 없음 → held rc 3 · 옛 세션 살아 있음"
fresh; mkseats noreplicates; mksess "$O"; mksess "$N"; : > "$TMP/resume/$O.json"; run "$O"
chk "ⓑ rc3 · kill=held" "$rc $(first | grep -c 'kill=held')" "3 1"
chk "ⓑ 옛 세션 살아 있음" "$(up "$O")" up

echo "== ⓒ 후계 tmux 세션 없음 → held rc 3"
fresh; mkseats normal; mksess "$O"; : > "$TMP/resume/$O.json"; run "$O"
chk "ⓒ rc3 · kill=held · 옛 세션 살아 있음" "$rc $(first | grep -c 'kill=held') $(up "$O")" "3 1 up"

echo "== ⓓ 재개 기록 없음 → held rc 3"
fresh; mkseats normal; mksess "$O"; mksess "$N"; run "$O"
chk "ⓓ rc3 · kill=held · 옛 세션 살아 있음" "$rc $(first | grep -c 'kill=held') $(up "$O")" "3 1 up"

echo "== ⓔ 후계 행이 이미 은퇴(_replaced_by 있음) → held rc 3"
fresh; mkseats retired; mksess "$O"; mksess "$N"; : > "$TMP/resume/$O.json"; run "$O"
chk "ⓔ rc3 · kill=held · 후계 살아 있음" "$rc $(first | grep -c 'kill=held') $(up "$N")" "3 1 up"

echo "== ⓕ 같은 이름 계보(#0→#1) = 지금과 같은 출력 (lineage= 0)"
mkseats same; mksess "$S1"; mksess "$S2"; : > "$TMP/resume/$S1.json"; run "$S1"
chk "ⓕ rc0 · CLOSED-SESSION · kill=ok" "$rc $(first | grep -c '^CLOSED-SESSION.*kill=ok')" "0 1"
chk "ⓕ lineage= 덧붙임 0" "$(first | grep -c 'lineage=')" 0
chk "ⓕ 옛 세션 gone" "$(up "$S1")" gone

echo "== ⓖ 명부 JSON 깨짐 → CLOSED 0 · kill 0 · 세션 살아 있음"
mkseats broken; mksess "$O"; run "$O"
chk "ⓖ CLOSED 0 · rc≠0 · 세션 살아 있음" "$(first | grep -c '^CLOSED') $(up "$O")" "0 up"

echo "== 변이(사본에서만) — 근거 하나씩 지우면 그 사례가 닫혀 버린다(검출)"
mut() {  # mut <이름> <옛글자> <새글자> — bin 사본 + 1치환 · 못 찾으면 판정 불가 = FAIL
  local d="$TMP/mb/$1"; mkdir -p "$d"; cp "$BIN"/ft-seat-close.sh "$BIN"/ft-seat-reap.sh "$BIN"/ft_roster_lib.py "$BIN"/ft-harness-root.sh "$BIN"/ft-verdict-row.sh "$BIN"/ft-team-lib.sh "$d"/ 2>/dev/null
  python3 - "$d/ft-seat-close.sh" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
assert old in s, "치환 자리 없음: " + old
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
  echo "$d/ft-seat-close.sh"
}
check_mut() {  # check_mut <이름> <사례 모드> <세션2개 y/n> <재개기록 y/n> <기대: 닫힘=CLOSED>
  fresh; mkseats "$2"; mksess "$O"; [ "$3" = y ] && mksess "$N"; [ "$4" = y ] && : > "$TMP/resume/$O.json"
  CL="$5" run "$O"
  case "$rc:$(first)" in 0:CLOSED-SESSION*kill=ok*) ok "변이 $1 → $2 를 닫아 버림(시험 검출)";; *) bad "변이 $1 → $2 여전히 held (rc=$rc)";; esac
}
M1="$(mut M1 'seat not in (nxt.get("_replaces") or [])' 'False')" && check_mut M1 noreplicates y y "$M1"
M2="$(mut M2 'tmux has-session -t "=$n" 2>/dev/null || return 1' ':')" && check_mut M2 normal n y "$M2"
M3="$(mut M3 '[ -f "$RECF" ] || return 1' ':')" && check_mut M3 normal y n "$M3"
M4="$(mut M4 'or nxt.get("_replaced_by")' 'or False')" && check_mut M4 retired y y "$M4"

echo; if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; fi; echo "FAILED $fail"; exit 1
