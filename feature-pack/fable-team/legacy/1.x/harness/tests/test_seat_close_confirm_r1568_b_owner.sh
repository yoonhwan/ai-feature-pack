#!/usr/bin/env bash
# test_seat_close_confirm_r1568_b_owner.sh — r1682 쪼갠 ②(소유 판정): ⓓ 서비스 제외 · ⓘ 규칙 밖 · ⓖ pid 재사용 · ⓗ 소유 바뀜 · 변이 M8·M5·M4.
#   ⓓ 서비스(reap-skip)는 정지 0 · ⓘ 무관·공유 프로세스(규칙 밖 · 워크트리 밖 cwd) → 후보 0 · 신호 0 · 살아 있음
#   ⓖ pid 재사용(주입 ps 표 = lstart 다름) → KILL 0 · 살아 있음 ⓗ 소유 바뀜(주입 ps 표 = argv 에서 --seat 사라짐) → KILL 0
#   픽스처·도구는 test_seat_close_confirm_r1568_fixtures.sh — 이 파일은 사례만 담는다(70초 안 · 하드 룰 22)
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/test_seat_close_confirm_r1568_fixtures.sh"

echo "== ⓓ 서비스(reap-skip)는 정지 0 (M8 서비스 제외 빼면 죽는다)"
spawn_faux "$S" "$MKX-d" -
P="$(pick "$MKX-d")"
out="$(FT_REAP_SERVICE_RE="$MKX-d" bash "$REAP" "$S")"; rc=$?
has "$out" "reap-skip pid=$P why=service-cmd" "ⓓ reap-skip why=service-cmd"
chk "ⓓ서비스 생존 · left=0 rc=0" "$(alive "$P") $rc $(endline "$out")" "alive 0 left=0 rc=0"
mut M8 ft-seat-reap.sh 'if via and pid in svc:' 'if via and pid in ():' || bad "M8 치환 실패"
out="$(FT_REAP_SERVICE_RE="$MKX-d" bash "$TMP/mb/M8/ft-seat-reap.sh" "$S")"; rc=$?
chk "M8 서비스 제외 빼면 죽는다(변이 잡힘)" "$(alive "$P")" "dead"
kill_mk "$MKX-d"

echo "== ⓘ 규칙 밖 프로세스(FT_SEAT 없음 · ft-bg-loop.sh 아님 · 워크트리 밖 cwd) → 후보 0 · 신호 0"
( cd "$TMP/else" && env -u FT_SEAT nohup "$BASH_X" -c "while :; do sleep 0.5; done # $MKX-i" </dev/null >/dev/null 2>&1 & ); sleep 0.6
IO="$(pgrep -f "$MKX-i" | head -1)"
dry="$(bash "$REAP" "$S" --wt "$TMP/wt" --dry-run)"; rc=$?
chk "ⓘdry-run rc0 · 후보에 없음" "$rc $(case "$dry" in *"$IO"*) echo in;; *) echo out;; esac)" "0 out"
out="$(bash "$REAP" "$S" --wt "$TMP/wt")"
chk "ⓘ살아 있음 · left=0" "$(alive "$IO") $(endline "$out")" "alive left=0 rc=0"
kill -9 "$IO" 2>/dev/null

echo "== ⓖ pid 재사용(주입 ps 표: TERM 뒤 같은 pid 의 lstart 다름) → KILL 0 · 살아 있음 (M5 lstart 비교 빼면 죽는다)"
cat > "$TMP/psbin/ps" <<'EOS'
#!/usr/bin/env python3
import os, re, subprocess, sys
out = subprocess.run(["/bin/ps"] + sys.argv[1:], capture_output=True, text=True).stdout
mode = os.environ.get("PS_MODE", ""); arm = os.environ.get("PS_ARM", ""); pid = 0
if mode and arm and os.path.exists(arm):
    try: pid = int(open(os.environ.get("PS_PID", "")).read().strip())
    except (OSError, ValueError): pid = 0
    lines = out.splitlines()
    for i, ln in enumerate(lines):
        f = ln.split(None, 9)
        if pid and len(f) >= 10 and f[0].isdigit() and int(f[0]) == pid:
            if mode == "lstart":
                try: n = int(open(arm + ".n").read().strip() or 0)
                except (OSError, ValueError): n = 0
                open(arm + ".n", "w").write(str(n + 1))
                lines[i] = " ".join(f[:4] + ["Mon", "Jan", "1", "00:00:%02d" % (n % 60), "1990", f[9]])
            elif mode == "owner": lines[i] = " ".join(f[:9] + [f[9].replace("ft-bg-loop.sh", "ft-bg-loop-gone.sh")])
    out = "\n".join(lines) + ("\n" if out.endswith("\n") else "")
sys.stdout.write(out)
EOS
chmod 0755 "$TMP/psbin/ps"
ARMG="$TMP/armed-g"; rm -f "$ARMG"; spawn_faux "$S" "$MKX-g" "$ARMG"
L="$(pick "$MKX-g")"; echo "$L" > "$TMP/pid-g"
out="$(PATH="$TMP/psbin:$PATH" FT_PS="$TMP/psbin/ps" PS_MODE=lstart PS_ARM="$ARMG" PS_PID="$TMP/pid-g" bash "$REAP" "$S")"; rc=$?
chk "ⓖKILL 0 · 살아 있음 · rc≠0" "$(alive "$L") $rc" "alive 1"
has "$out" "why=owner-changed" "ⓖ reap-skip why=owner-changed"
mut M5 ft-seat-reap.sh 'if p in t and t[p][3] == cand[p][1] and p not in anc' 'if p in t and p not in anc' || bad "M5 치환 실패"
ARMG2="$TMP/armed-g2"; rm -f "$ARMG2"; spawn_faux "$S" "$MKX-g2" "$ARMG2"
L2="$(pick "$MKX-g2")"; echo "$L2" > "$TMP/pid-g2"
PATH="$TMP/psbin:$PATH" FT_PS="$TMP/psbin/ps" PS_MODE=lstart PS_ARM="$ARMG2" PS_PID="$TMP/pid-g2" bash "$TMP/mb/M5/ft-seat-reap.sh" "$S" >/dev/null 2>&1
chk "M5 lstart 비교 빼면 죽는다(변이 잡힘)" "$(alive "$L2")" "dead"
kill_mk "$MKX-g"

echo "== ⓗ 소유 바뀜(주입 ps 표: argv 에서 --seat 규칙이 사라짐) → KILL 0 · 살아 있음 (M4 소유 재확인 빼면 죽는다)"
ARMS="$TMP/armed-s"; rm -f "$ARMS"; spawn_faux "$S" "$MKX-h" "$ARMS"
H="$(pick "$MKX-h")"; echo "$H" > "$TMP/shim-h"
out="$(PATH="$TMP/psbin:$PATH" FT_PS="$TMP/psbin/ps" PS_MODE=owner PS_ARM="$ARMS" PS_PID="$TMP/shim-h" bash "$REAP" "$S")"; rc=$?
chk "ⓗKILL 0 · 살아 있음(규칙이 사라져 후보 아님)" "$(alive "$H")" "alive"
mut M4 ft-seat-reap.sh 'and p not in svc and still_mine(p, cand[p][0], t, tree, bg, cw, wt, oth)' 'and p not in svc' || bad "M4 치환 실패"
ARMS2="$TMP/armed-s2"; rm -f "$ARMS2"; spawn_faux "$S" "$MKX-h2" "$ARMS2"
H2="$(pick "$MKX-h2")"; echo "$H2" > "$TMP/shim-h2"
PATH="$TMP/psbin:$PATH" FT_PS="$TMP/psbin/ps" PS_MODE=owner PS_ARM="$ARMS2" PS_PID="$TMP/shim-h2" bash "$TMP/mb/M4/ft-seat-reap.sh" "$S" >/dev/null 2>&1
chk "M4 소유 재확인 빼면 죽는다(변이 잡힘)" "$(alive "$H2")" "dead"
kill_mk "$MKX-h"

finish
