#!/usr/bin/env bash
# test_seat_retire_ft2_row_fields_r2142.sh — r2142: 옛 행 source=ft2-launch 이고 R370 이 index 를 넘길 때 work · source 도 같이 넘긴다(후계에 있는 칸은 덮어쓰기 0).
#   ① 후계 행 없음 → index · work · source 상속 + ft2_nano 두 조건식 참 · ② 후계 행 미리 있음(index · work 없음) → ① 과 같음
#   ③ 후계 행에 source · work 다른 값(③b 빈 문자열 · null) → 그대로 · index 만 · ④ 1.x 옛 행(source 없음 · work=legacy) → index 만
#   ⑤ ft2 옛 행 · 후계 index 이미 있음 → 아무 칸도 안 넘김.
#   모든 쓰기는 mktemp scratch 리포 — 실 명부·실 tmux·실 우편함 0 · 가짜 tmux(세션 없음).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"; RETIRE="${R2142_RETIRE:-$BIN/ft-seat-retire.sh}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT; TMP="$(cd "$TMP" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$TMP/reap.sh"; export FT_SEAT_REAP_BIN="$TMP/reap.sh"   # 은퇴 reap = 스텁(실기계 프로세스 0)
FK="$TMP/fake"; mkdir -p "$FK"; printf '#!/bin/sh\nexit 1\n' > "$FK/tmux"; chmod +x "$FK/tmux"
OLD='byz-t-nano-x#1'; NEW='byz-t-nano-x#2'
FT2='{"role": "nano", "agent": "claude", "model": "m", "tick": null, "work": "W", "attempt": "a1", "source": "ft2-launch", "index": "진행/W.md"}'
# run <사례> <옛 행 JSON> [후계 행 JSON] → "rc 후계행(index·work·source · 없는 칸 = -) ft2_nano"
run() { local r="$TMP/r-$1"; mkdir -p "$r/.fable-team"; git -C "$r" init -q
  if [ -n "${3:-}" ]; then printf '{"%s": %s, "%s": %s}' "$OLD" "$2" "$NEW" "$3"; else printf '{"%s": %s}' "$OLD" "$2"; fi > "$r/.fable-team/seats-t.json"
  (cd "$r" && HOME="$TMP/home" PATH="$FK:$PATH" env -u FT_SEATS_JSON bash "$RETIRE" "$OLD" "$NEW" >"$TMP/out-$1" 2>&1); local rc=$?
  python3 - "$r/.fable-team/seats-t.json" "$NEW" "$rc" <<'PY'
import json, sys
n = json.load(open(sys.argv[1])).get(sys.argv[2]) or {}
c = lambda k: json.dumps(n[k], ensure_ascii=False) if k in n else "-"
ft2 = n.get("role") == "nano" and (n.get("source") == "ft2-launch" or "/.fable-team/teams/" in str(n.get("worktree") or ""))   # scan.sh ft2_nano 같은 두 조건식
print(sys.argv[3], c("index"), c("work"), c("source"), "ft2" if ft2 else "1x")
PY
}
PRE='{"role": "nano", "agent": "claude", "model": "m", "tick": null'
chk "bin·kit ft-seat-retire.sh cmp0" "$(cmp -s "$BIN/ft-seat-retire.sh" "$KIT/ft-seat-retire.sh" && echo same || echo diff)" same
chk "① ft2 옛 행 · 후계 없음 → index·work·source 상속 · ft2_nano 참" "$(run c1 "$FT2")" '0 "진행/W.md" "W" "ft2-launch" ft2'
chk "② ft2 옛 행 · 후계 미리 있음(index·work 없음) → ① 과 같음" "$(run c2 "$FT2" "$PRE}")" '0 "진행/W.md" "W" "ft2-launch" ft2'
chk "③ 후계 source·work 다른 값 → 그대로 · index 만" "$(run c3 "$FT2" "$PRE, \"source\": \"other\", \"work\": \"W2\"}")" '0 "진행/W.md" "W2" "other" 1x'
chk "③b 후계 source 빈 문자열·work null → 그대로 · index 만" "$(run c3b "$FT2" "$PRE, \"source\": \"\", \"work\": null}")" '0 "진행/W.md" null "" 1x'
chk "④ 1.x 옛 행(source 없음 · work=legacy) → index 만" "$(run c4 "$PRE, \"work\": \"legacy\", \"index\": \"진행/L.md\"}")" '0 "진행/L.md" - - 1x'
chk "⑤ ft2 옛 행 · 후계 index 이미 있음 → 아무 칸도 안 넘김" "$(run c5 "$FT2" "$PRE, \"index\": \"진행/X.md\"}")" '0 "진행/X.md" - - 1x'
[ "$fail" = 0 ] || for f in "$TMP"/out-*; do echo "--- $f"; head -3 "$f"; done
echo "fail=$fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit "$fail"
