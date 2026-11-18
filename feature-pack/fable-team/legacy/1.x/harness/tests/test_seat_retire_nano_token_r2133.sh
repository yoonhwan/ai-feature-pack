#!/usr/bin/env bash
# test_seat_retire_nano_token_r2133.sh — r2133: 옛 role(또는 쓸 _retired_role)이 nano 이고 후계 이름 토큰이 상주 역할이면 후계 role = 이름 토큰.
#   ① nano → arch 이름 = arch · ② stop-ready/_retired_role nano → arch 이름 = arch · ③ nano → nano 이름(토큰 없음) = nano · ④ arch → arch = arch · tester → arch 이름 = tester.
#   모든 쓰기는 mktemp scratch 리포 — 실 명부·실 tmux·실 우편함 0 · 가짜 tmux(세션 없음).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"; RETIRE="$BIN/ft-seat-retire.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT; TMP="$(cd "$TMP" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$TMP/reap.sh"; export FT_SEAT_REAP_BIN="$TMP/reap.sh"   # 은퇴 reap = 스텁(실기계 프로세스 0)
FK="$TMP/fake"; mkdir -p "$FK"; printf '#!/bin/sh\nexit 1\n' > "$FK/tmux"; chmod +x "$FK/tmux"
OLD='byz-t-arch-pi#1'
row() { printf '{"role": "%s", "agent": "claude", "model": "m", "tick": null%s}' "$1" "${2:-}"; }
# run <사례> <옛 행 JSON> <후계> — 후계 행 없음 · 역할 칸 0 → 출력 = "rc 후계role"
run() { local r="$TMP/r-$1"; mkdir -p "$r/.fable-team"; git -C "$r" init -q
  printf '{"%s": %s}' "$OLD" "$2" > "$r/.fable-team/seats-t.json"
  (cd "$r" && HOME="$TMP/home" PATH="$FK:$PATH" env -u FT_SEATS_JSON bash "$RETIRE" "$OLD" "$3" >"$TMP/out-$1" 2>&1); local rc=$?
  echo "$rc $(jq -r --arg n "$3" '.[$n].role // "MISSING"' "$r/.fable-team/seats-t.json")"; }

chk "bin·kit ft_roster_lib.py cmp0" "$(cmp -s "$BIN/ft_roster_lib.py" "$KIT/ft_roster_lib.py" && echo same || echo diff)" same
FT2=', "source": "ft2-launch", "work": "w1"'
chk "① nano(ft2-launch) → byz-t-arch-pi#2 = arch" "$(run c1 "$(row nano "$FT2")" 'byz-t-arch-pi#2')" "0 arch"
chk "② stop-ready · _retired_role nano → byz-t-arch-pi#3 = arch" "$(run c2 "$(row stop-ready ', "_retired_role": "nano"')" 'byz-t-arch-pi#3')" "0 arch"
chk "③ nano → byz-t-nano-x#1(토큰 없음) = nano" "$(run c3 "$(row nano "$FT2")" 'byz-t-nano-x#1')" "0 nano"
chk "④a arch → byz-t-arch-pi#2 = arch" "$(run c4a "$(row arch)" 'byz-t-arch-pi#2')" "0 arch"
chk "④b tester → byz-t-arch-pi#2 = tester" "$(run c4b "$(row tester)" 'byz-t-arch-pi#2')" "0 tester"
[ "$fail" = 0 ] || for f in "$TMP"/out-*; do echo "--- $f"; head -3 "$f"; done
echo "fail=$fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit "$fail"
