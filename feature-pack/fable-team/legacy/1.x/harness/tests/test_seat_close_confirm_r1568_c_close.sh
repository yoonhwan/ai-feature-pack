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
n=0
while [ "$n" -lt 200 ]; do   # 10ms 마다 하나 — «계속 태어나는 자식»(정지·재조사 사이에 반드시 새 자식이 있다)
  should_stop && exit 0
  ( cd "$KP_DIR" && nohup "$KP_BASH" "$KP_FAUX" --seat "$KP_SEAT" "$KP_TAG" </dev/null >/dev/null 2>&1 & )
  n=$((n+1)); sleep 0.01
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

echo "== R1 (DA②) 죽은 좌석(--verdict) 도 «세션 부재 ∧ 최종 재조사 left=0» — 자식이 살아 있으면 CLOSED-DEAD 0(거짓 성공) 0"
mkdir -p "$TMP/vr/design/teams/planner" "$TMP/cf2"; git -C "$TMP/vr" init -q -b main
printf '| 팀 | 폴더 |\n|---|---|\n| planner | design/teams/planner/ | x | 현역 |\n' > "$TMP/vr/design/TEAMS.md"
printf '| 2400 | t | r1568 시험 |\n' > "$TMP/vr/design/teams/planner/VERDICTS-planner-1.md"
git -C "$TMP/vr" add -A && git -C "$TMP/vr" -c user.name=t -c user.email=t@t commit -qm ledger
printf '{"_master": "M#1", "M#1": {"role": "master", "tick": "t"}, "%s": {"role": "tester", "agent": "claude", "model": "m", "tick": null}}\n' "$S3" > "$TMP/cf2/seats.json"
printf '#!/bin/sh\necho "RESUME ok %s"\n' "$TMP/cf2/resume/$S3.json" > "$TMP/cf2/retire.sh"; chmod 0755 "$TMP/cf2/retire.sh"
dead_close() {  # dead_close <close스크립트> — 죽은 좌석(--verdict) 닫기 · cwd = 판정 원장 리포
  ( cd "$TMP/vr" && FAKE_SESSION=0 FT_ROOT="$TMP/vroot" FT_TEAMS_REF=main FT_SEAT_RETIRE_BIN="$TMP/cf2/retire.sh" bash "$1" "$S3" --reason "r1568 R1" --seats "$TMP/cf2/seats.json" --verdict 2400 2>"$TMP/r1err" )
}
spawn_faux "$S3" "$MKX-r1a" -
out="$(dead_close "$CLOSE")"; rc=$?
chk "R1 자식 정리됨 → CLOSED-DEAD rc0" "$rc $(head -1 <<< "$out" | grep -c '^CLOSED-DEAD')" "0 1"
chk "R1 자식 0 · 기록 0" "$(pgrep -f "$MKX-r1a" | wc -l | tr -d ' ') $(ls "$TMP/cf2/state/close-fail" 2>/dev/null | wc -l | tr -d ' ')" "0 0"
kill_mk "$MKX-r1a"
# 남는 자식(감시자) → DEAD 라도 거짓 성공 0 · 실패 기록 1
cat > "$TMP/keep2.sh" <<'EOS'
#!/bin/bash
should_stop() { [ -n "${KP_STOP:-}" ] && [ -f "$KP_STOP" ] && return 0; [ -n "${KP_PARENT:-}" ] && ! kill -0 "$KP_PARENT" 2>/dev/null && return 0; return 1; }
n=0
while [ "$n" -lt 200 ]; do
  should_stop && exit 0
  ( cd "$KP_DIR" && nohup "$KP_BASH" "$KP_FAUX" --seat "$KP_SEAT" "$KP_TAG" </dev/null >/dev/null 2>&1 & )
  n=$((n+1)); sleep 0.01
done
EOS
KP_SEAT="$S3" KP_TAG="$MKX-r1b" KP_DIR="$TMP/else" KP_BASH="$BASH_X" KP_FAUX="$TMP/faux/ft-bg-loop.sh" KP_STOP="$TMP/stop" KP_PARENT="$TEST_PID" nohup bash "$TMP/keep2.sh" </dev/null >/dev/null 2>&1 &
sleep 0.4
out="$(dead_close "$CLOSE")"; rc=$?
chk "R1 자식 살아 있음 → rc≠0 · CLOSE-FAIL · «CLOSED» 0" "$([ "$rc" -ne 0 ] && echo ne0) $(head -1 <<< "$out" | grep -c '^CLOSE-FAIL') $(grep -c 'CLOSED' <<< "$out")" "ne0 1 0"
chk "R1 실패 기록 1개" "$(ls "$TMP/cf2/state/close-fail" 2>/dev/null | wc -l | tr -d ' ')" 1
pkill -f "$TMP/keep2.sh" 2>/dev/null; kill_mk "$MKX-r1b"
mut2 M9 ft-seat-close.sh 'else reap; KILL=none; fi' 'else [ "$DEAD" = 1 ] || reap; KILL=none; fi' $'\nfinal\n' $'\n[ "$DEAD" = 1 ] || final\n' || bad "M9 치환 실패"
KP_SEAT="$S3" KP_TAG="$MKX-r1c" KP_DIR="$TMP/else" KP_BASH="$BASH_X" KP_FAUX="$TMP/faux/ft-bg-loop.sh" KP_STOP="$TMP/stop" KP_PARENT="$TEST_PID" nohup bash "$TMP/keep2.sh" </dev/null >/dev/null 2>&1 &
sleep 0.4; rm -rf "$TMP/cf2/state"
out="$(dead_close "$TMP/mb/M9/ft-seat-close.sh")"; rc=$?
chk "M9 DEAD 자식 정리 빼면 CLOSED-DEAD 0(변이 잡힘)" "$rc $(head -1 <<< "$out" | grep -c '^CLOSED-DEAD')" "0 1"
pkill -f "$TMP/keep2.sh" 2>/dev/null; kill_mk "$MKX-r1c"

echo "== R2 (DA②) 후보③ — TERM 뒤 cwd 가 워크트리 밖으로 바뀌면 KILL 0 · 살아 있음 (M10 cwd 재확인 빼면 죽는다)"
MOVED="$TMP/moved-$$"; rm -f "$MOVED"; mkdir -p "$TMP/wt2"; git -C "$TMP/wt2" init -q
( cd "$TMP/wt2" && env -u FT_SEAT nohup "$BASH_X" -c "env -u FT_SEAT nohup '$BASH_X' -c 'trap \"cd $TMP/else; touch $MOVED; :\" TERM; while :; do sleep 0.05; done # $MKX-r2' </dev/null >/dev/null 2>&1 &" </dev/null >/dev/null 2>&1 & ); sleep 0.8
R2P="$(pgrep -f "$MKX-r2" | while read -r p; do [ "$(ps -o ppid= -p "$p" | tr -d ' ')" = 1 ] && echo "$p"; done | head -1)"
chk "R2픽스처(ppid 1 · cwd=$TMP/wt2)" "$([ -n "$R2P" ] && echo 1) $(lsof -a -d cwd -p "${R2P:-0}" -Fn 2>/dev/null | tail -1)" "1 n$TMP/wt2"
out="$(bash "$REAP" "$S4" --wt "$TMP/wt2")"; rc=$?
chk "R2 cwd 바뀜 → KILL 0 · 살아 있음(후보에서도 빠짐 = left=0 rc0)" "$(alive "$R2P") $rc" "alive 0"
has "$out" "via=③" "R2 후보③ 로 잡힘"
has "$out" "why=owner-changed" "R2 남김 기록(why=owner-changed)"
chk "R2 TERM handler 가 cwd 를 옮겼다" "$([ -f "$MOVED" ] && echo moved)" "moved"
mut M10 ft-seat-reap.sh 'if via == "③": return r[5] is None and r[0] == 1 and p not in other and bool(wt) and p in cw and own_wt(os.path.realpath(cw[p]), wt) and bool(re.search(r"\b(sleep|while)\b", r[4]))' 'if via == "③": return r[5] is None and r[0] == 1' || bad "M10 치환 실패"
( cd "$TMP/wt2" && env -u FT_SEAT nohup "$BASH_X" -c "env -u FT_SEAT nohup '$BASH_X' -c 'trap \"cd $TMP/else; :\" TERM; while :; do sleep 0.05; done # $MKX-r2b' </dev/null >/dev/null 2>&1 &" </dev/null >/dev/null 2>&1 & ); sleep 0.8
R2P2="$(pgrep -f "$MKX-r2b" | while read -r p; do [ "$(ps -o ppid= -p "$p" | tr -d ' ')" = 1 ] && echo "$p"; done | head -1)"
bash "$TMP/mb/M10/ft-seat-reap.sh" "$S4" --wt "$TMP/wt2" >/dev/null 2>&1
chk "M10 cwd 재확인 빼면 죽는다(변이 잡힘)" "$(alive "$R2P2")" "dead"
kill -9 "$R2P" "$R2P2" 2>/dev/null

finish
