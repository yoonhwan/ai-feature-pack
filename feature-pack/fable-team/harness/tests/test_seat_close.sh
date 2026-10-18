#!/usr/bin/env bash
# test_seat_close.sh — R297: ft-seat-close.sh «세션만 닫기» — 명부 stop-ready 표기 · 세션 kill · 거절 · 틱 resume_rows 에서 빠짐.
# 모든 쓰기는 mktemp scratch 안 — 가짜 tmux(PATH 앞) · 실제 세션·명부 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; CLOSE="${FT_SEAT_CLOSE_BIN:-$BIN/ft-seat-close.sh}"; TICK="$BIN/ft-tick.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
unset FT_SEATS_JSON
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
J() { jq -r "$2" "$1"; }

# 가짜 tmux — 호출을 로그에 남긴다. FAKE_SESSION=1|0 · FAKE_TAG=1|0 · FAKE_KILL_RC=<n> · FAKE_LIVE="<살아 있는 세션 공백구분>"
mkdir -p "$TMP/bin"; LOG="$TMP/tmux.log"
cat > "$TMP/bin/tmux" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$TMUX_LOG"
case "$1" in
  has-session) [ "${FAKE_SESSION:-1}" = 1 ];;
  show-options) [ "${FAKE_TAG:-1}" = 1 ] && echo 1; exit 0;;
  set-option) exit 0;;
  kill-session) exit "${FAKE_KILL_RC:-0}";;
  list-sessions) for x in ${FAKE_LIVE:-}; do echo "$x"; done;;
  display-message) echo caller#0;;
esac
EOF
chmod +x "$TMP/bin/tmux"
run() { PATH="$TMP/bin:$PATH" TMUX_LOG="$LOG" "$@"; }
kills() { grep -c '^kill-session' "$LOG" 2>/dev/null || true; }
mkseats() { printf '%s' '{"_master": "M#1", "_hil_route": "P#1", "M#1": {"role": "master", "tick": "ft-master-tick"}, "P#1": {"role": "planner", "tick": "t"}, "N#0": {"role": "nano", "agent": "claude", "model": "m", "tick": null, "index": "i.md"}, "W#1": {"role": "tester", "agent": "claude", "model": "m", "tick": null}}' > "$1"; }
export ZC_RESUME_DIR="$TMP/resume"; mkdir -p "$ZC_RESUME_DIR"

bash -n "$CLOSE" && ok "bash -n ft-seat-close.sh" || bad "bash -n ft-seat-close.sh"
chk "ft-seat-close.sh ≤ 120줄" "$([ "$(wc -l < "$CLOSE")" -le 120 ] && echo yes || echo no)" yes

resume_of() { # <명부> — 틱 resume_rows 출력의 좌석 열
  bash -c "SEATS=$1; $(sed -n '/^resume_rows() {/,/^}/p' "$TICK")"$'\n''resume_rows' | cut -f1 | xargs
}

# ① 직전 세대(W#1) + 재개 기록 + 후계 W#2 생존 + 태그 있음 → kill=ok
S="$TMP/a.json"; mkseats "$S"; : > "$LOG"; echo "{}" > "$ZC_RESUME_DIR/W#1.json"
out="$(FAKE_LIVE="W#1 W#2" FAKE_SESSION=1 FAKE_TAG=1 run bash "$CLOSE" 'W#1' --reason "판정 2050 노출 나노" --seats "$S")"; rc=$?
chk "①rc" "$rc" 0
chk "①출력" "$out" "CLOSED-SESSION W#1 file=$S role_was=tester kill=ok"
chk "①role·tick" "$(J "$S" '[.["W#1"].role,(.["W#1"].tick|tostring)]|join(",")')" "stop-ready,null"
chk "①_closed_role" "$(J "$S" '.["W#1"]._closed_role')" tester
chk "①_closed 3칸(by·at·reason)" "$(J "$S" '.["W#1"]._closed|[(.by!=null),(.at!=null),.reason]|join(",")')" "true,true,판정 2050 노출 나노"
chk "①.bak 1개" "$(ls "$S".bak-close-* 2>/dev/null | wc -l | tr -d ' ')" 1
chk "①kill 호출 1" "$(kills)" 1
chk "①태그 해제 호출 1 · kill 직전" "$(grep -c '^set-option .*-u @zc_v65_active' "$LOG") $(grep -B1 '^kill-session' "$LOG" | head -1 | cut -c1-10)" "1 set-option"
chk "①다른 행·_ 칸 불변" "$(J "$S" '[._master,._hil_route,.["M#1"].role,.["P#1"].role]|join(",")')" "M#1,P#1,master,planner"
chk "①틱 resume_rows 에 W#1 없음(M#1 P#1 만)" "$(resume_of "$S")" "M#1 P#1 N#0"

# ② 세션 없음 → kill=none · 표기는 됨 · 태그 해제·kill 호출 0
S="$TMP/b.json"; mkseats "$S"; : > "$LOG"
out="$(FAKE_SESSION=0 run bash "$CLOSE" 'N#0' --reason r --seats "$S")"; rc=$?
chk "②rc·출력" "$rc $out" "0 CLOSED-SESSION N#0 file=$S role_was=nano kill=none"
chk "②표기됨" "$(J "$S" '.["N#0"].role')" stop-ready
chk "②kill 0" "$(kills)" 0

# ③ 좌석이 _ 칸 값 → REJECT · 명부 쓰기 0
S="$TMP/c.json"; mkseats "$S"; cp "$S" "$TMP/c.orig"; : > "$LOG"
for s in 'M#1' 'P#1'; do
  out="$(run bash "$CLOSE" "$s" --reason r --seats "$S")"; rc=$?
  chk "③$s rc 1 · REJECT" "$rc ${out%% *}" "1 REJECT"
done
chk "③바이트 불변·.bak 0·kill 0" "$(cmp -s "$S" "$TMP/c.orig" && echo same || echo changed) $(ls "$TMP"/c.json.bak-close-* 2>/dev/null | wc -l | tr -d ' ') $(kills)" "same 0 0"

# ④ 명부 후보 0 / 2 → REJECT · --reason 없음 → rc 2
R="$TMP/repo"; mkdir -p "$R/.fable-team"; git -C "$R" init -q
mkseats "$R/.fable-team/seats.json"; mkseats "$R/.fable-team/seats-x.json"
(cd "$R" && run bash "$CLOSE" 'N#0' --reason r > "$TMP/d2.out"); rc=$?
chk "④후보 2개 rc 1 · REJECT" "$rc $(cut -c1-6 "$TMP/d2.out")" "1 REJECT"
chk "④후보 2개 쓰기 0" "$(ls "$R/.fable-team" | grep -c bak)" 0
(cd "$R" && run bash "$CLOSE" 'ZZ#9' --reason r > "$TMP/d0.out"); rc=$?
chk "④후보 0개 rc 1 · REJECT" "$rc $(cut -c1-6 "$TMP/d0.out")" "1 REJECT"
rm "$R/.fable-team/seats-x.json"
(cd "$R" && FAKE_SESSION=0 run bash "$CLOSE" 'N#0' --reason r > /dev/null); rc=$?
chk "④후보 1개 자동 선택 rc 0" "$rc $(J "$R/.fable-team/seats.json" '.["N#0"].role')" "0 stop-ready"
run bash "$CLOSE" 'N#0' --seats "$S" > /dev/null 2>&1; chk "④--reason 없음 rc 2" "$?" 2
run bash "$CLOSE" 'N#0' --reason "  " --seats "$S" > /dev/null 2>&1; chk "④--reason 공백 rc 2" "$?" 2
run bash "$CLOSE" > /dev/null 2>&1; chk "④좌석 없음 rc 2" "$?" 2

# ⑤ kill 실패 → FAIL rc 1 · 표기는 남음 · 틱 재개 0 (kill 범위 안: W#1 직전 세대 + 기록 + W#2 생존)
S="$TMP/e.json"; mkseats "$S"; : > "$LOG"; echo "{}" > "$ZC_RESUME_DIR/W#1.json"
out="$(FAKE_LIVE="W#1 W#2" FAKE_SESSION=1 FAKE_KILL_RC=1 run bash "$CLOSE" 'W#1' --reason r --seats "$S")"; rc=$?
chk "⑤rc 1 · FAIL kill" "$rc ${out%% W#1*}" "1 FAIL kill"
chk "⑤표기 남음" "$(J "$S" '.["W#1"].role')" stop-ready
chk "⑤틱 resume_rows 에 W#1 없음" "$(resume_of "$S")" "M#1 P#1 N#0"

# ⑥ 이미 닫힌 행 재호출 → _closed_role 이 stop-ready 로 덮이지 않는다
out="$(FAKE_SESSION=0 run bash "$CLOSE" 'W#1' --reason again --seats "$S")"
chk "⑥재호출 _closed_role 보존" "$(J "$S" '.["W#1"]._closed_role')" tester
chk "⑥재호출 reason 갱신" "$(J "$S" '.["W#1"]._closed.reason')" again

# ⑦ kill 범위(전역 표준승인) — 계보 최신 → held rc 3 · 표기 됨 · kill 0
S="$TMP/f.json"; mkseats "$S"; : > "$LOG"
out="$(FAKE_LIVE="N#0" FAKE_SESSION=1 run bash "$CLOSE" 'N#0' --reason r --seats "$S")"; rc=$?
chk "⑦a 계보 최신 rc 3 · kill=held" "$rc $(printf '%s' "$out" | grep -o 'kill=held')" "3 kill=held"
chk "⑦a 표기 됨 · kill 0" "$(J "$S" '.["N#0"].role') $(kills)" "stop-ready 0"
# ⑦b 직전 세대 + 기록 없음 + 후계 1개 → held
S="$TMP/g.json"; mkseats "$S"; : > "$LOG"; rm -f "$ZC_RESUME_DIR/W#1.json"
out="$(FAKE_LIVE="W#1 W#2" FAKE_SESSION=1 run bash "$CLOSE" 'W#1' --reason r --seats "$S")"; rc=$?
chk "⑦b 기록 없음·후계 1개 rc 3 · kill 0" "$rc $(kills)" "3 0"
# ⑦c 직전 세대 + 기록 없음 + 후계 2개 생존(keep-last-2) → ok
: > "$LOG"; S="$TMP/h.json"; mkseats "$S"
out="$(FAKE_LIVE="W#1 W#2 W#3" FAKE_SESSION=1 run bash "$CLOSE" 'W#1' --reason r --seats "$S")"; rc=$?
chk "⑦c 후계 2개 생존 rc 0 · kill 1" "$rc $(kills)" "0 1"
# ⑦d 기록 있음 + 후계 0(자기가 최신) → held
: > "$LOG"; S="$TMP/i.json"; mkseats "$S"; echo "{}" > "$ZC_RESUME_DIR/W#1.json"
FAKE_LIVE="W#1" FAKE_SESSION=1 run bash "$CLOSE" 'W#1' --reason r --seats "$S" > /dev/null; rc=$?
chk "⑦d 기록만 있고 후계 0 rc 3 · kill 0" "$rc $(kills)" "3 0"

# ⑦e 직전 세대 + 재개 기록 있음 + 후계 1개 생존 → rc 0 · kill 1 (판정 1344 주 경로 — lineage_ok 의 기록 갈래)
: > "$LOG"; S="$TMP/j.json"; mkseats "$S"; echo "{}" > "$ZC_RESUME_DIR/W#1.json"
out="$(FAKE_LIVE="W#1 W#2" FAKE_SESSION=1 run bash "$CLOSE" 'W#1' --reason r --seats "$S")"; rc=$?
chk "⑦e 기록 있음·후계 1개 rc 0 · kill=ok · kill 1" "$rc ${out##* } $(kills)" "0 kill=ok 1"

echo "fail=$fail"; [ "$fail" = 0 ]
