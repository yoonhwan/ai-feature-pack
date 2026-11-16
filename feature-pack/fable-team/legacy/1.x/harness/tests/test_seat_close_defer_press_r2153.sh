#!/usr/bin/env bash
# test_seat_close_defer_press_r2153.sh — r2153: 승계(ft-seat-retire) 끝의 옛 좌석 세션 닫기(ft-seat-close)가 press 중이면 pane 자손 러너를 «미룸».
#   ① retire 2회째 꼴(옛 세션 살아 있음 · close-check 통과 · pane 자손 nohup press 러너) → 러너 생존 · reap-defer 줄 · 미룸 파일 1 · CLOSED-SESSION · rc 0
#   ② ft-seat-close --defer-press 직접 + press 진행 → final 통과 · CLOSE-FAIL 0 · 세션 닫힘
#   ③ ① 에서 press 없음(러너 경로 아님 · 허가 held 아님) → 자손 kill · left=0
#   ④ 플래그 없는 ft-seat-close + press 진행 → 지금처럼 kill
#   ⑤ ① 뒤 press 끝 → 다음 reap 이 lstart 같은 pid 만 정지 · 미룸 파일 삭제
#   변이 M1~M4(사본) — 변이마다 원본 대조는 위 사례가 맡는다. 픽스처 = test_seat_close_confirm_r1568_fixtures.sh(임시 폴더·tmux·표식 정리)
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/test_seat_close_confirm_r1568_fixtures.sh"
BIN="${R2153_BIN:-$BIN}"; CLOSE="$BIN/ft-seat-close.sh"; RETIRE="$BIN/ft-seat-retire.sh"; REAP="$BIN/ft-seat-reap.sh"
export FT_ROOT="$TMP/root" FT_ALLOW_TRACKED_BIN=1; mkdir -p "$FT_ROOT/.fable-team" "$TMP/tests/e2e"
printf 'import time\nwhile True: time.sleep(0.2)\n' > "$TMP/tests/e2e/r2153_press_fx.py"
printf 'import time\nwhile True: time.sleep(0.2)\n' > "$TMP/else/r2153_plain_fx.py"
PRE='tests/e2e/r2153_press_fx\.py'; NEVER="r2153-never-$$"
seats() { printf '{"_master": "M#1", "M#1": {"role": "master", "tick": "t"}, "%s": {"role": "tester", "agent": "claude", "model": "m", "tick": null}, "%s": {"role": "tester", "agent": "claude", "model": "m", "tick": null}}\n' "$1" "$2" > "$TMP/cf/seats.json"; }
rsess() {  # rsess <좌석> <스크립트> — pane 자손 = nohup python 러너 1개(표식 $MKX) · 러너 pid 출력
  tmux kill-session -t "=$1" 2>/dev/null   # 앞 사례가 남긴 세션(기준판 ② usage rc 2 등) 정리
  tmux new-session -d -s "$1" -c "$TMP/wt" -e "FT_SEAT=$1" "$BASH_X" -c "nohup python3 '$2' '$MKX-$1' </dev/null >/dev/null 2>&1 & while kill -0 $TEST_PID 2>/dev/null; do read -t 0.2 _ <> '$TMP/sess.fifo' || :; done"
  local i p; for i in 1 2 3 4 5 6 7 8 9 10; do p="$(pgrep -f "fx\.py $MKX-$1" | head -1)"; [ -n "$p" ] && { echo "$p"; return; }; sleep 0.05; done
}
up() { tmux has-session -t "=$1" 2>/dev/null && echo up || echo gone; }
mkfifo "$TMP/sess.fifo"
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
case1() {  # case1 <bin> → "rc 러너 세션 CLOSED줄 defer줄 파일" (retire 2회째 꼴)
  local b="$1" R out rc; seats "$S" "$S1"; : > "$ZC_RESUME_DIR/$S.json"; rm -f "$FT_REAP_DEFER_DIR/$S.jsonl"
  tmux has-session -t "=$S1" 2>/dev/null || mksess "$S1" "$TMP/wt"
  R="$(rsess "$S" "$TMP/tests/e2e/r2153_press_fx.py")"; [ -n "$R" ] || { echo "no-runner"; return; }
  out="$(FT_PRESS_RUNNER_RE="$PRE" bash "$b/ft-seat-retire.sh" "$S" "$S1" --seats "$TMP/cf/seats.json" 2>&1)"; rc=$?; echo "$R" > "$TMP/r1"
  echo "$rc $(alive "$R") $(up "$S") $(grep -c '^CLOSED-SESSION' <<< "$out") $(grep -q "reap-defer pid=$R why=press-active" <<< "$out" && echo 1 || echo 0) $([ -f "$FT_REAP_DEFER_DIR/$S.jsonl" ] && echo file || echo nofile)"
}
case2() {  # case2 <bin> → "rc 러너 세션 CLOSED줄 CLOSE-FAIL수"
  local b="$1" R out rc; seats "$SD" "$SD1"; : > "$ZC_RESUME_DIR/$SD.json"; rm -f "$FT_REAP_DEFER_DIR/$SD.jsonl"
  tmux has-session -t "=$SD1" 2>/dev/null || mksess "$SD1" "$TMP/wt"
  R="$(rsess "$SD" "$TMP/tests/e2e/r2153_press_fx.py")"; [ -n "$R" ] || { echo "no-runner"; return; }
  out="$(FT_PRESS_RUNNER_RE="$PRE" bash "$b/ft-seat-close.sh" "$SD" --reason "r2153 시험" --seats "$TMP/cf/seats.json" --defer-press 2>&1)"; rc=$?
  echo "$rc $(alive "$R") $(up "$SD") $(grep -c '^CLOSED-SESSION' <<< "$out") $(grep -c 'CLOSE-FAIL' <<< "$out")"; kill -9 "$R" 2>/dev/null
}
case4() {  # case4 <bin> → "rc 러너 세션" (플래그 없는 닫기 + press 진행)
  local b="$1" R out rc; seats "$SD" "$SD1"; : > "$ZC_RESUME_DIR/$SD.json"
  tmux has-session -t "=$SD1" 2>/dev/null || mksess "$SD1" "$TMP/wt"
  R="$(rsess "$SD" "$TMP/tests/e2e/r2153_press_fx.py")"; [ -n "$R" ] || { echo "no-runner"; return; }
  out="$(FT_PRESS_RUNNER_RE="$PRE" bash "$b/ft-seat-close.sh" "$SD" --reason "r2153 시험" --seats "$TMP/cf/seats.json" 2>&1)"; rc=$?
  wait_dead "$MKX-$SD"; echo "$rc $(alive "$R") $(up "$SD")"; kill -9 "$R" 2>/dev/null
}
for f in "$CLOSE" "$RETIRE"; do bash -n "$f" && ok "bash -n $(basename "$f")" || bad "bash -n $f"; done

echo "== ① retire 2회째 꼴 + press 러너(pane 자손 · nohup) → 러너 생존 · reap-defer · 미룸 파일 · CLOSED-SESSION · rc 0"
chk "① rc 러너 세션 CLOSED reap-defer 파일" "$(case1 "$BIN")" "0 alive gone 1 1 file"
R1="$(cat "$TMP/r1" 2>/dev/null)"
chk "① 미룸 파일에 러너 pid" "$(grep -q "\"pid\": $R1," "$FT_REAP_DEFER_DIR/$S.jsonl" 2>/dev/null && echo yes)" yes

echo "== ⑤ ① 뒤 press 끝 → 다음 reap 이 lstart 같은 pid 만 정지 · 미룸 파일 삭제"
( nohup python3 "$TMP/else/r2153_plain_fx.py" "$MKX-other" </dev/null >/dev/null 2>&1 & ); for i in 1 2 3 4 5 6 7 8 9 10; do OP="$(pgrep -f "$MKX-other" | head -1)"; [ -n "$OP" ] && break; sleep 0.05; done
chk "⑤ 전제 — ① 의 미룸 파일 있음" "$([ -f "$FT_REAP_DEFER_DIR/$S.jsonl" ] && echo file)" file
printf '{"pid": %s, "lstart": "Thu Jan  1 00:00:00 1970", "cmd": "fx", "via": "②"}\n' "$OP" >> "$FT_REAP_DEFER_DIR/$S.jsonl"
out="$(FT_PRESS_RUNNER_RE="$NEVER" bash "$REAP" "r2153other-$$#0" 2>&1)"; wait_dead "$MKX-$S"
chk "⑤ 미룸 러너 정지 · lstart 다른 pid 생존 · 파일 삭제" "$(alive "$R1") $(alive "$OP") $([ -f "$FT_REAP_DEFER_DIR/$S.jsonl" ] && echo left || echo gone)" "dead alive gone"
has "$out" "reap-deferred-done file=$FT_REAP_DEFER_DIR/$S.jsonl" "⑤ reap-deferred-done 줄"
kill -9 "$OP" 2>/dev/null

echo "== ② ft-seat-close --defer-press 직접 + press 진행 → final 통과 · CLOSE-FAIL 0 · 세션 닫힘"
chk "② rc 러너 세션 CLOSED CLOSE-FAIL" "$(case2 "$BIN")" "0 alive gone 1 0"

echo "== ③ ① 에서 press 없음(러너 경로 아님 · 허가 held 아님) → 자손 kill · left=0"
seats "$S" "$S1"; : > "$ZC_RESUME_DIR/$S.json"; rm -f "$FT_REAP_DEFER_DIR/$S.jsonl" "$FT_PERMIT_DIR/device.json"
R3="$(rsess "$S" "$TMP/else/r2153_plain_fx.py")"
out="$(FT_PRESS_RUNNER_RE="$NEVER" bash "$RETIRE" "$S" "$S1" --seats "$TMP/cf/seats.json" 2>&1)"; rc=$?; wait_dead "$MKX-$S"
chk "③ rc 러너 세션 CLOSED reap-defer 파일" "$rc $(alive "$R3") $(up "$S") $(grep -c '^CLOSED-SESSION' <<< "$out") $(grep -c 'reap-defer ' <<< "$out") $([ -f "$FT_REAP_DEFER_DIR/$S.jsonl" ] && echo file || echo nofile)" "0 dead gone 1 0 nofile"
has "$out" "left=0" "③ reap left=0"

echo "== ④ 플래그 없는 ft-seat-close + press 진행 + pane 자손 러너 → 지금처럼 kill"
chk "④ rc 러너 세션" "$(case4 "$BIN")" "0 dead gone"

echo "== 변이 M1~M4 (사본 · 원본 대조 = 위 ① ② ④)"
if grep -q -- '--defer-press' "$CLOSE"; then
  mutb M1 ft-seat-retire.sh '--reason "retire -> $NEW" --defer-press' '--reason "retire -> $NEW"' || bad "M1 치환 실패"
  chk "M1 retire 전달 지움 → ① 러너 kill(변이 잡힘)" "$(case1 "$TMP/mb/M1" | cut -d' ' -f2)" dead
  mutb M2 ft-seat-close.sh '"$SEAT" $DFR 2>&1)"; r=$?; RL=' '"$SEAT" 2>&1)"; r=$?; RL=' || bad "M2 치환 실패"
  chk "M2 close reap() 전달 지움 → ① 러너 kill" "$(case1 "$TMP/mb/M2" | cut -d' ' -f2)" dead
  chk "M2 → ② 러너 kill" "$(case2 "$TMP/mb/M2" | cut -d' ' -f2)" dead
  mutb M3 ft-seat-close.sh 'local o r g L; o="$(bash "${FT_SEAT_REAP_BIN:-$HERE/ft-seat-reap.sh}" "$SEAT" $DFR' 'local o r g L; o="$(bash "${FT_SEAT_REAP_BIN:-$HERE/ft-seat-reap.sh}" "$SEAT"' || bad "M3 치환 실패"
  chk "M3 close final() 전달 지움 → ① 러너 kill" "$(case1 "$TMP/mb/M3" | cut -d' ' -f2)" dead
  chk "M3 → ② 러너 kill" "$(case2 "$TMP/mb/M3" | cut -d' ' -f2)" dead
  mutb M4 ft-seat-close.sh 'DFR=""' 'DFR="--defer-press"' || bad "M4 치환 실패"
  chk "M4 늘 미룸 → ④ 러너 생존(변이 잡힘)" "$(case4 "$TMP/mb/M4" | cut -d' ' -f2)" alive
  kill_mk "$MKX-$S"; kill_mk "$MKX-$SD"
else echo "SKIP 변이 — 이 판에 --defer-press 없음(기준판)"; fi
finish
