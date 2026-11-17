#!/usr/bin/env bash
# test_seat_reap_keep_hil_r2160.sh — r2160: 좌석 닫기·승계의 reap 이 실행 중인 h(사람 실행 /tmp/hN)를 TERM 하지 않는다.
#   ① pane 자손 bash /tmp/h8538 + 자식(timeout 30 psql · 토큰 0) → reap-skip why=hil-running h=h8538 · 조상 셸·h·자식 reap-kill 0 · hil=1 · left=0
#   ② ① 의 좌석에 ft-seat-close → WAIT why=hil-running rc 4 · kill-session 0 · 명부 무변경(.bak-close 0)
#   ③ 자손이 tail -f /tmp/h8538.out(h 아님) → 지금처럼 reap-kill  ③' bash /private/tmp/h8538 → ① 과 같음
#   ④ h 끝남(프로세스 0) → reap-kill 그대로 · 자손 0 좌석 닫기 = CLOSED-SESSION rc 0 · kill-session 1
#   ⑤ press 진행 + h 없음 + --defer-press → reap-defer press-active 그대로  ⑤' h 있음 + press → h 나무는 미룸 파일 0
#   R1b(구현 DA HOLD #324785) 같은 뿌리 아래 형제 자식(h 와 무관한 psql) → 신호 0 · left 에 안 셈
#   R1a(같은 HOLD) press 미룸(h 없음) 뒤 그 셸 아래 h 시작 → 미룸 소화가 h 조상을 정지 경로에 넣지 않음 · 미룸 행 보존
#   변이 M1(건너뜀 지움) · M2(토큰 «/tmp/h 로 시작») · M3(토큰 프로세스 1개만) — 사본에서 · 원본 대조는 같은 사례
#   입력 = 가짜 ps 표(FT_PS) · 가짜 lsof(FT_LSOF) · 가짜 tmux(PATH) · 임시 명부 · FT_REAP_NOSIGNAL=1 — 실 h·실 세션·실 신호 0 · sleep 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${R2160_BIN:-$HERE/../bin}"; BIN="$(cd "$BIN" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/r2160.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
U="$(id -u)"; SEAT="r2160t#3"; B=4193000; P=$((B+1)) A=$((B+2)) S=$((B+3)) H=$((B+4)) C=$((B+5))
LS="Mon Nov 17 09:00:00 2026"
mkdir -p "$TMP/fake" "$TMP/defer" "$TMP/permit" "$TMP/resume" "$TMP/root/.fable-team" "$TMP/nowt"
cat > "$TMP/fake/ps" <<'EOS'
#!/bin/bash
case " $* " in *" -axEww "*) awk '{c=""; for (i = 10; i <= NF; i++) c = c (i > 10 ? " " : "") $i; print $1, c}' "$FPS";; *) cat "$FPS";; esac
EOS
printf '#!/bin/sh\nexit 0\n' > "$TMP/fake/lsof"
cat > "$TMP/fake/tmux" <<'EOS'
#!/bin/bash
echo "$*" >> "$TLOG"
case "$1" in
  list-panes) printf '%s\t%s\t%s\t%s\n' "$FSEAT" "$FPANE" "$FWT" "$FWT";;
  list-sessions) printf '%s\n' "$FSEAT" "${FSEAT%#*}#8" "${FSEAT%#*}#9";;
  has-session) [ -f "$FKILLED" ] && exit 1;;
  display-message) echo 0;;
  kill-session) : > "$FKILLED";;
esac
exit 0
EOS
chmod +x "$TMP/fake/"*
export PATH="$TMP/fake:$PATH" FT_PS="$TMP/fake/ps" FT_LSOF="$TMP/fake/lsof" FPS="$TMP/ps.txt" TLOG="$TMP/tmux.log" FKILLED="$TMP/killed"
export FSEAT="$SEAT" FPANE="$P" FWT="$TMP/nowt" FT_REAP_NOSIGNAL=1 FT_REAP_TERM_WAIT=0 FT_REAP_DEFER_DIR="$TMP/defer" FT_PERMIT_DIR="$TMP/permit"
export FT_BG_FINITE_LEDGER="$TMP/bg.tsv" ZC_RESUME_DIR="$TMP/resume" FT_ROOT="$TMP/root" FT_MBOX_PY="$TMP/none/mbox.py" FT_PRESS_PS_SNAPSHOT="$TMP/press.txt"
unset TMUX_PANE FT_SEATS_JSON
: > "$TMP/press.txt"
row() { printf '%s %s %s %s %s %s\n' "$1" "$2" "$1" "$U" "$LS" "$3"; }
table() {  # table <h 명령|-> — pane P → 에이전트 A → 셸 S → [h H → 자식 C]
  { row "$P" 1 "-bash"; row "$A" "$P" "node /opt/agent/cli.js"; row "$S" "$A" "/bin/zsh -i"
    [ "$1" = - ] || { row "$H" "$S" "$1"; row "$C" "$H" "timeout 30 psql -c select_1"; }; } > "$FPS"; }
reap() { (cd "$TMP" && bash "$1/ft-seat-reap.sh" "$SEAT" "${@:2}" 2>&1); }
nkill() { local n=0 p; for p in "${@:2}"; do grep -q "^reap-kill pid=$p " <<< "$1" && n=$((n+1)); done; echo "$n"; }
case1() {  # case1 <bin> <h 명령> → "kill수(A S H C) skip줄수 h이름 끝줄"
  local o; table "$2"; o="$(reap "$1")"
  echo "$(nkill "$o" "$A" "$S" "$H" "$C") $(grep -c '^reap-skip pid=.* why=hil-running h=h8538$' <<< "$o") $(tail -1 <<< "$o" | sed "s/^reap $SEAT //")"
}
seats() { printf '{"_master": "M#1", "M#1": {"role": "master", "tick": "t"}, "%s": {"role": "tester", "agent": "claude", "model": "m", "tick": null}}\n' "$SEAT" > "$TMP/seats.json"; }
close() {  # close <bin> → "rc WAIT줄수 kill-session수 명부같음 bak수"
  local o rc m0; seats; m0="$(cksum < "$TMP/seats.json")"; rm -f "$TLOG" "$FKILLED" "$TMP"/seats.json.bak-*
  o="$(cd "$TMP" && bash "$1/ft-seat-close.sh" "$SEAT" --reason "r2160 시험" --seats "$TMP/seats.json" 2>/dev/null)"; rc=$?; echo "$o" > "$TMP/close.out"
  echo "$rc $(grep -c "^WAIT $SEAT why=hil-running h=h8538 " <<< "$o") $(grep -c '^kill-session' "$TLOG" 2>/dev/null) $([ "$(cksum < "$TMP/seats.json")" = "$m0" ] && echo same || echo changed) $(ls "$TMP" | grep -c 'seats.json.bak-')"
}
mutb() {  # mutb <이름> <파일> <옛> <새> — bin 통째 사본 + 1곳 치환
  local d="$TMP/mb/$1"; mkdir -p "$d"; cp -R "$BIN/." "$d"/
  python3 - "$d/$2" "$3" "$4" <<'PY'
import sys
p, o, n = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if s.count(o) != 1: print(f"mutb: «{o}» 개수 {s.count(o)}"); sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(o, n))
PY
}
for f in ft-seat-reap.sh ft-seat-close.sh; do bash -n "$BIN/$f" && ok "bash -n $f" || bad "bash -n $f"; done
W1="0 4 stopped=0 hil=1 left=0 rc=0"   # 뿌리 4(에이전트·셸·h·자식 = 모두 ① pane 자손) 마다 reap-skip 1줄
echo "== ① pane 자손 bash /tmp/h8538 + 자식 psql → 조상 셸·h·자식 신호 0 · hil=1 · left=0"
chk "① kill수 skip줄 끝줄" "$(case1 "$BIN" "bash /tmp/h8538")" "$W1"
echo "== ② ① 의 좌석 ft-seat-close → WAIT rc 4 · kill-session 0 · 명부 무변경"
table "bash /tmp/h8538"; chk "② rc WAIT kill 명부 bak" "$(close "$BIN")" "4 1 0 same 0"
echo "== ③ tail -f /tmp/h8538.out(h 아님) → 지금처럼 reap-kill"
table "tail -f /tmp/h8538.out"; o3="$(reap "$BIN")"
chk "③ h자리·자식 reap-kill · hil 줄 0" "$(nkill "$o3" "$H" "$C" "$S") $(grep -c 'hil' <<< "$o3")" "3 0"
echo "== ③' bash /private/tmp/h8538 → ① 과 같음"
chk "③' kill수 skip줄 끝줄" "$(case1 "$BIN" "bash /private/tmp/h8538")" "$W1"
echo "== ④ h 끝남 → reap-kill 그대로 · 자손 0 좌석 닫기 = CLOSED-SESSION"
table -; o4="$(reap "$BIN")"; chk "④ 셸 reap-kill · hil 줄 0" "$(nkill "$o4" "$S") $(grep -c 'hil' <<< "$o4")" "1 0"
row "$P" 1 "-bash" > "$FPS"; chk "④ 닫기 rc WAIT kill 명부 bak" "$(close "$BIN" | cut -d' ' -f1-4)" "0 0 1 changed"
chk "④ CLOSED-SESSION 1줄" "$(grep -c "^CLOSED-SESSION $SEAT " "$TMP/close.out")" 1
echo "== ⑤ press 진행 + h 없음 + --defer-press → reap-defer press-active 그대로"
echo "$((B+9)) $U python3 tests/e2e/x_press.py" > "$TMP/press.txt"
table -; o5="$(reap "$BIN" --defer-press)"
chk "⑤ press-active · 셸 미룸 · kill 0 · 끝줄" "$(grep -c '^reap-press-active' <<< "$o5") $(grep -c "^reap-defer pid=$S why=press-active" <<< "$o5") $(grep -c '^reap-kill' <<< "$o5") $(tail -1 <<< "$o5" | sed "s/^reap $SEAT //")" "1 1 0 stopped=0 left=0 deferred=2 rc=0"
rm -f "$TMP/defer/"*; table "bash /tmp/h8538"; o5b="$(reap "$BIN" --defer-press)"
chk "⑤' h + press → hil 건너뜀 · h 나무 미룸 파일 0" "$(grep -c 'why=hil-running' <<< "$o5b") $(cat "$TMP/defer/"* 2>/dev/null | grep -cE "\"pid\": ($A|$S|$H|$C),")" "4 0"
: > "$TMP/press.txt"
X=$((B+6))
echo "== R1b 같은 뿌리 아래 형제 자식(토큰 0 · h 와 무관) → 신호 0 · left 에 안 셈"
table "bash /tmp/h8538"; row "$X" "$S" "timeout 30 psql other_task" >> "$FPS"; o7="$(reap "$BIN")"
chk "R1b reap-kill 0 · 끝줄" "$(grep -c '^reap-kill' <<< "$o7") $(tail -1 <<< "$o7" | sed "s/^reap $SEAT //")" "0 stopped=0 hil=1 left=0 rc=0"
echo "== R1a press 미룸(h 없음) → press 끝 + h 시작 → 미룸 소화가 조상 정지 0 · 미룸 행 보존"
rm -f "$TMP/defer/"*; echo "$((B+9)) $U python3 tests/e2e/x_press.py" > "$TMP/press.txt"; table -; reap "$BIN" --defer-press >/dev/null
: > "$TMP/press.txt"; table "bash /tmp/h8538"; o8="$(reap "$BIN")"
chk "R1a reap-kill 0 · 미룸 행 2 남음 · 끝줄" "$(grep -c '^reap-kill' <<< "$o8") $(cat "$TMP/defer/"*.jsonl 2>/dev/null | grep -cE "\"pid\": ($A|$S),") $(tail -1 <<< "$o8" | sed "s/^reap $SEAT //")" "0 2 stopped=0 hil=1 left=0 rc=0"
rm -f "$TMP/defer/"*
echo "== 변이(사본) — 원본 대조 = 위 ①②③"
if mutb M1 ft-seat-reap.sh "keep = hil_tree(t, me)" "keep = {}"; then
  chk "M1 건너뜀 지움 → ① FAIL(잡힘)" "$([ "$(case1 "$TMP/mb/M1" "bash /tmp/h8538")" != "$W1" ] && echo caught)" caught
  table "bash /tmp/h8538"; chk "M1 → ② FAIL(잡힘)" "$([ "$(close "$TMP/mb/M1")" != "4 1 0 same 0" ] && echo caught)" caught
else bad "M1 사본 치환 실패"; fi
if mutb M2 ft-seat-reap.sh 'r"^(?:/private)?/tmp/h\d+$"' 'r"^(?:/private)?/tmp/h"'; then
  table "tail -f /tmp/h8538.out"; chk "M2 토큰 느슨 → ③ FAIL(잡힘)" "$([ "$(nkill "$(reap "$TMP/mb/M2")" "$H" "$C" "$S")" != 3 ] && echo caught)" caught
else bad "M2 사본 치환 실패"; fi
if mutb M3 ft-seat-reap.sh "tree = set(chain) | desc(t, [top]) | desc(t, [h])" "tree = {h}"; then
  table "bash /tmp/h8538"; o="$(reap "$TMP/mb/M3")"
  chk "M3 토큰 1개만 → ① 자식·조상 TERM(잡힘)" "$([ "$(nkill "$o" "$C" "$S")" != 0 ] && echo caught)" caught
else bad "M3 사본 치환 실패"; fi
echo; if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "FAILED $fail"; exit 1; fi
