#!/usr/bin/env bash
# test_seat_close_confirm_r1568_c_close.sh — r1682 쪼갠 ③(닫기 확인): ⓕ · ⓙ · ⓚ + R1(죽은 좌석) · R2(후보③) · 변이 M6·M7·M9·M10.
#   ⓕ h8128 꼴(세션 kill 뒤 ②b 자식) → CLOSED-SESSION · 세션 부재 · reap left=0 · close-fail 기록 0
#   ⓙ 세션 없이 자식이 남음 → CLOSE-FAIL rc≠0 · «CLOSED»·«GONE» 글자 0 · 기록 1개(담당·다음 실행 칸) + master 쪽지 1통
#   ⓚ 다음 닫기 성공(자식 정리 뒤) → CLOSED-SESSION · 기록 지워짐
#   R1 죽은 좌석(--verdict) 도 «세션 부재 ∧ 최종 재조사 left=0» — 자식이 살아 있으면 CLOSED-DEAD 0(거짓 성공) 0
#   R2 후보③ — TERM 뒤 cwd 가 워크트리 밖으로 바뀌면 KILL 0 · 살아 있음
#   픽스처·도구는 test_seat_close_confirm_r1568_fixtures.sh — 이 파일은 사례만 담는다(70초 안 · 하드 룰 22)
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/test_seat_close_confirm_r1568_fixtures.sh"

echo "== ⓕ h8128 꼴 — 세션 kill 뒤에도 남는 ②b 자식 → CLOSED-SESSION · 세션 부재 · reap left=0 · close-fail 기록 0"
printf '{"_master": "M#1", "M#1": {"role": "master", "tick": "t"}, "%s": {"role": "tester", "agent": "claude", "model": "m", "tick": null}, "%s": {"role": "tester", "agent": "claude", "model": "m", "tick": null}}\n' "$S" "$S1" > "$TMP/cf/seats.json"
mksess "$S" "$TMP/wt"; mksess "$S1" "$TMP/wt"; : > "$ZC_RESUME_DIR/$S.json"
spawn_faux "$S" "$MKX-f" -
chk "ⓕ픽스처 — 세션 살아 있음 · 자식 1" "$(tmux has-session -t "=$S" 2>/dev/null && echo up) $([ -n "$(pick "$MKX-f")" ] && echo 1)" "up 1"
out="$(bash "$CLOSE" "$S" --reason "r1568 시험" --seats "$TMP/cf/seats.json" 2>/dev/null)"; rc=$?
chk "ⓕrc0 · CLOSED-SESSION · kill=ok · reap left=0" "$rc $(head -1 <<< "$out" | grep -c '^CLOSED-SESSION')" "0 1"
chk "ⓕ세션 부재 · 자식 0 · 기록 0" "$(tmux has-session -t "=$S" 2>/dev/null && echo up || echo gone) $(wait_dead "$MKX-f"; pgrep -f "$MKX-f" | wc -l | tr -d ' ') $(ls "$TMP/cf/state/close-fail" 2>/dev/null | wc -l | tr -d ' ')" "gone 0 0"
kill_mk "$MKX-f"

echo "== ⓙ 세션 없이 자식이 남음 → CLOSE-FAIL rc≠0 · «CLOSED»·«GONE» 0 · 기록 1개 + master 쪽지 1통 (M6·M7 변이)"
printf '{"_master": "M#1", "M#1": {"role": "master", "tick": "t"}, "%s": {"role": "tester", "agent": "claude", "model": "m", "tick": null}, "%s": {"role": "tester", "agent": "claude", "model": "m", "tick": null}}\n' "$SD" "$SD1" > "$TMP/cf/seats-d.json"
cat > "$TMP/keeper.sh" <<'EOS'
#!/bin/bash
should_stop() { [ -n "${KP_STOP:-}" ] && [ -f "$KP_STOP" ] && return 0; [ -n "${KP_PARENT:-}" ] && ! kill -0 "$KP_PARENT" 2>/dev/null && return 0; return 1; }
while tmux has-session -t "=$KP_SEAT" 2>/dev/null; do should_stop && exit 0; sleep 0.02; done   # 세션이 죽은 «뒤» 자식을 낳는다(h8128 꼴)
t0=$SECONDS   # r1682 보정: 회차 수(200) 대신 «멈춤 표식·부모 감시까지» — 부하로 닫기가 길어져도 자식이 계속 태어난다(안전 상한 20초)
while [ $((SECONDS - t0)) -lt "${KP_CAP:-20}" ]; do   # 100ms 마다 하나(정지·재조사 사이에 반드시 새 자식이 있다 · 10ms 는 부하에서 후보가 수천으로 불어나 reap 이 느려진다)
  should_stop && exit 0
  ( cd "$KP_DIR" && nohup "$KP_BASH" "$KP_FAUX" --seat "$KP_SEAT" "$KP_TAG" </dev/null >/dev/null 2>&1 & )
  sleep 0.1
done
EOS
mksess "$SD" "$TMP/wt"; mksess "$SD1" "$TMP/wt"; : > "$ZC_RESUME_DIR/$SD.json"
# tmux 얇은 껍데기 — kill-session «그 순간» 감시자를 켜 자식이 태어난다(h8128: 세션이 죽으며 뜨는 git 자식)
mkdir -p "$TMP/tmuxbin"; REAL_TMUX="$(command -v tmux)"
cat > "$TMP/tmuxbin/tmux" <<EOS
#!/bin/bash
"$REAL_TMUX" "\$@"; rc=\$?
if [ "\$1" = kill-session ]; then
  ( cd "$TMP/else" && STUBBORN_ARM="$TMP/armed-j" nohup "$BASH_X" "$TMP/faux/ft-bg-loop.sh" --seat "$SD" "$MKX-j" </dev/null >/dev/null 2>&1 & )   # 세션이 죽는 그 순간 태어나는 자식
  STUBBORN_ARM="$TMP/armed-j" KP_SEAT="$SD" KP_TAG="$MKX-j" KP_DIR="$TMP/else" KP_BASH="$BASH_X" KP_FAUX="$TMP/faux/ft-bg-loop.sh" KP_STOP="$TMP/stop" KP_PARENT="$TEST_PID" nohup bash "$TMP/keeper.sh" </dev/null >/dev/null 2>&1 &   # bg-ok: cleanup·guard 가 keeper·표식 프로세스를 kill -9 한다
fi
exit \$rc
EOS
chmod 0755 "$TMP/tmuxbin/tmux"
out="$(PATH="$TMP/tmuxbin:$PATH" bash "$CLOSE" "$SD" --reason "r1568 시험" --seats "$TMP/cf/seats-d.json" 2>/dev/null)"; rc=$?
chk "ⓙrc≠0 · CLOSE-FAIL" "$([ "$rc" -ne 0 ] && echo ne0) $(head -1 <<< "$out" | grep -c '^CLOSE-FAIL')" "ne0 1"
nu "$out" "CLOSED" "ⓙ«CLOSED» 글자 0"
nu "$out" "GONE" "ⓙ«GONE» 글자 0"
chk "ⓙ기록 1개" "$(ls "$TMP/cf/state/close-fail" 2>/dev/null | wc -l | tr -d ' ')" 1
chk "ⓙ기록 칸(담당·다음 실행)" "$(grep -cE '^담당=|^다음 실행:' "$TMP/cf/state/close-fail/$SD.txt" 2>/dev/null)" 2
chk "ⓙmaster 쪽지 1통" "$(grep -c "^send M#1 " "$TMP/cf/mbox.log" 2>/dev/null)" 1
pkill -f "$TMP/keeper.sh" 2>/dev/null; kill_mk "$MKX-j"; sleep 0.2
mut M6 ft-seat-close.sh '[ "$r" -eq 0 ] && [ "$g" = gone ]' '[ "$g" = gone ]' || bad "M6 치환 실패"
mksess "$SD" "$TMP/wt"
out="$(PATH="$TMP/tmuxbin:$PATH" bash "$TMP/mb/M6/ft-seat-close.sh" "$SD" --reason "r1568 변이" --seats "$TMP/cf/seats-d.json" 2>/dev/null)"; rc=$?
chk "M6 자식 0 판정 빼면 CLOSED(변이 잡힘)" "$([ "$rc" -eq 0 ] && head -1 <<< "$out" | grep -c '^CLOSED')" "1"
pkill -f "$TMP/keeper.sh" 2>/dev/null; kill_mk "$MKX-j"; sleep 0.2
mut M7 ft-seat-close.sh 'CF="$CFD/$SEAT.txt"' 'CF=/dev/null' || bad "M7 치환 실패"
rm -rf "$TMP/cf/state"
mksess "$SD" "$TMP/wt"
PATH="$TMP/tmuxbin:$PATH" bash "$TMP/mb/M7/ft-seat-close.sh" "$SD" --reason "r1568 변이" --seats "$TMP/cf/seats-d.json" >/dev/null 2>&1
chk "M7 기록 쓰기 빼면 기록 0(변이 잡힘)" "$(ls "$TMP/cf/state/close-fail" 2>/dev/null | wc -l | tr -d ' ')" 0

echo "== ⓚ 자식 정리 뒤 다음 닫기 성공 → CLOSED-SESSION · 기록 지워짐"
pkill -f "$TMP/keeper.sh" 2>/dev/null; kill_mk "$MKX-j"; wait_dead "$MKX-j"
out="$(bash "$CLOSE" "$SD" --reason "r1568 시험 2" --seats "$TMP/cf/seats-d.json" 2>/dev/null)"; rc=$?
chk "ⓚrc0 · CLOSED-SESSION · kill=none" "$rc $(head -1 <<< "$out" | grep -oE 'CLOSED-SESSION|kill=none' | tr '\n' ' ' | sed 's/ $//')" "0 CLOSED-SESSION kill=none"
chk "ⓚ기록 지워짐" "$(ls "$TMP/cf/state/close-fail" 2>/dev/null | wc -l | tr -d ' ')" 0

finish
