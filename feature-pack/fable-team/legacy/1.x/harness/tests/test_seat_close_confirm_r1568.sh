#!/usr/bin/env bash
# test_seat_close_confirm_r1568.sh — r1568: 승계는 후계가 «옛 세션 닫힘» 을 확인해야 끝난다(ft-seat-reap 마지막 정지 1회 + ft-seat-close 닫힘 확인).
#   ⓐ 짧은 자식 1번(3세대 사슬) = reap left=0 rc0 · 남은 사슬 0 — 마지막 정지가 없으면 left≥1(M1)
#   ⓑ 계속 남는 자식 = left≥1 rc=1 ⓒ 정지 횟수 상한 3(reap-kill 3줄 · M2 면 4줄+) ⓓ 서비스(reap-skip)는 정지 0
#   ⓕ h8128 꼴(세션 kill 뒤 ②b 자식) → CLOSED-SESSION · 세션 부재 · reap left=0 · close-fail 기록 0
#   ⓖ pid 재사용(주입 ps 표 = lstart 다름) → KILL 0 · 살아 있음 ⓗ 소유 바뀜(주입 ps 표 = argv 에서 --seat 사라짐) → KILL 0 · 살아 있음
#   ⓘ 무관·공유 프로세스(규칙 밖 · 워크트리 밖 cwd) → 후보 0 · 신호 0 · 살아 있음
#   ⓙ 세션 없이 자식이 남음 → CLOSE-FAIL rc≠0 · «CLOSED»·«GONE» 글자 0 · 기록 1개(담당·다음 실행 칸) + master 쪽지 1통
#   ⓚ 다음 닫기 성공(자식 정리 뒤) → CLOSED-SESSION · 기록 지워짐
#   변이 M1 마지막 정지 빼기(range 3→2) · M2 상한 없음(3→12) · M3 남은 것을 rc0 · M4 KILL 직전 소유 재확인 빼기 · M5 lstart 비교 빼기
#     · M6 성공 판정에서 «자식 0» 빼기 · M7 실패 기록 쓰기 빼기 · M8 서비스 제외 빼기 — 전부 «그 기준값이 뒤집히면» 잡힌다
# 실프로세스 픽스처 = argv 가 «ft-bg-loop.sh --seat <좌석>» 인 faux 래퍼(reap ②b 규칙 — macOS 에서 env 가 ps 에 안 보이는 머신에서도 잡힌다)
#   · 쓰기는 mktemp 안(FT_*_DIR 로 실데이터 루트 차단) · press 0 · FT_REAP_TERM_WAIT 는 시험 전용 대기 단축(제품 기본 3초 그대로).
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; REAP="$BIN/ft-seat-reap.sh"; CLOSE="$BIN/ft-seat-close.sh"; BASH_X="$(command -v bash)"
T0="$(mktemp -d)"; TMP="$(cd "$T0" && pwd -P)"; MKX="r1568fx-$$"
S="r1568t-$$#0"; S1="r1568t-$$#1"; SD="r1568d-$$#0"; SD1="r1568d-$$#1"
mkdir -p "$TMP/else" "$TMP/wt" "$TMP/mb" "$TMP/psbin" "$TMP/resume" "$TMP/cf/comm"
git -C "$TMP/wt" init -q
export ZC_RESUME_DIR="$TMP/resume" FT_REAP_DEFER_DIR="$TMP/defer" FT_PERMIT_DIR="$TMP/permits" FT_BG_FINITE_LEDGER="$TMP/ledger.tsv"
export FT_PRESS_RUNNER_RE="r1568-never-$$" FT_SUCCESSOR_DIR="$TMP/succ" FT_MBOX_PY="$TMP/mbox-ok.py"
export FT_REAP_TERM_WAIT=0.15   # 시험 전용 — TERM 뒤 대기 0.15초(제품 기본 = 3초) · 1회차 70초 안에 끝내려고
printf 'print("CLOSE-OK stub")\n' > "$TMP/mbox-ok.py"
printf '#!/bin/sh\necho "$*" >> %s/mbox.log\nexit 0\n' "$TMP/cf" > "$TMP/cf/comm/mbox.sh"
cleanup() { local s p; pkill -f "$TMP/keeper.sh" 2>/dev/null; for s in "$S" "$S1" "$SD" "$SD1"; do tmux kill-session -t "=$s" 2>/dev/null; done; for p in $(pgrep -f "$MKX"); do kill -9 "$p" 2>/dev/null; done; }
trap 'cleanup; rm -rf "$T0"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
nu()  { case "$1" in *"$2"*) bad "$3 — 있으면 안 되는 글자: «$2» ← ${1:0:400}";; *) ok "$3";; esac; }
alive() { kill -0 "$1" 2>/dev/null && echo alive || echo dead; }
endline() { tail -1 <<< "$1" | grep -oE 'left=[0-9?]+ rc=[0-9]+'; }
nkills() { grep '^reap-kill' <<< "$1" | grep -vc 'via=자손'; }

# faux 래퍼 — reap 의 ②b(argv) 규칙만 흉내낸다. --next 가 있으면 TERM 때 다음 세대를 낳고 죽는다(사슬 · h8128 꼴)
mkdir -p "$TMP/faux"
cat > "$TMP/faux/ft-bg-loop.sh" <<'EOS'
#!/bin/bash
seat=""; nxt=""; gen=0; max=0; tag=""
while [ $# -gt 0 ]; do case "$1" in --seat) seat="$2"; shift 2;; --next) nxt="$2"; shift 2;; --gen) gen="$2"; shift 2;; --max) max="$2"; shift 2;; *) tag="$1"; shift;; esac; done
if [ -n "$nxt" ] && [ "$gen" -lt "$max" ]; then
  trap "nohup /bin/bash '$0' --seat '$seat' --gen $((gen+1)) --max '$max' --next '$nxt' '$nxt-$((gen+1))' </dev/null >/dev/null 2>&1 & exit 0" TERM
elif [ -n "${STUBBORN_ARM:-}" ]; then
  trap 'touch "$STUBBORN_ARM"; :' TERM   # TERM 을 «무시» — 표식 파일만 남기고 계속 산다(KILL 분기 재현)
fi
# 둘 다 아니면 기본 TERM(죽는다) — 서비스·짧은 자식 픽스처
while :; do sleep 0.05; done # $tag
EOS
pick() {  # pick <표식> — faux «본체» pid(래퍼 셸은 argv 가 «bash -c …» 라 걸러진다)
  pgrep -f "$1" | while read -r p; do ps -o command= -p "$p" 2>/dev/null | grep -qE '^[^ ]*bash [^ ]*faux/ft-bg-loop\.sh --seat ' && echo "$p"; done | head -1
}
spawn_faux() {  # spawn_faux <좌석> <표식> <표식파일|-> [--gen N --max M --next TAG] — 고아 1개
  local st="$1" tag="$2" arm="$3"; shift 3
  ( cd "$TMP/else" && if [ "$arm" = - ]; then nohup "$BASH_X" "$TMP/faux/ft-bg-loop.sh" --seat "$st" "$@" "$tag" </dev/null >/dev/null 2>&1 & else STUBBORN_ARM="$arm" nohup "$BASH_X" "$TMP/faux/ft-bg-loop.sh" --seat "$st" "$@" "$tag" </dev/null >/dev/null 2>&1 & fi )
  sleep 0.5
}
kill_mk() { local p; for p in $(pgrep -f "$1"); do kill -9 "$p" 2>/dev/null; done; }
wait_dead() { local i; for i in 1 2 3 4 5 6 7 8 9 10; do [ -z "$(pgrep -f "$1")" ] && return 0; sleep 0.1; done; }

# 변이 사본 — bin 사본 + 문자열 1개 치환(못 찾으면 그 변이는 판정 불가 = FAIL)
mut() {  # mut <이름> <파일> <옛글자> <새글자>
  local d="$TMP/mb/$1"; mkdir -p "$d"
  cp "$BIN/ft-seat-reap.sh" "$BIN/ft-seat-close.sh" "$BIN/ft-leak-reap.sh" "$BIN/ft-bg-finite.sh" "$BIN/ft-harness-root.sh" "$BIN/ft_roster_lib.py" "$BIN/ft-verdict-row.sh" "$BIN/ft-team-lib.sh" "$d"/ 2>/dev/null
  python3 - "$d/$2" "$3" "$4" <<'PY'
import sys
p, o, n = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if s.count(o) != 1: print(f"mut: «{o}» 개수 {s.count(o)}"); sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(o, n))
PY
}

mut2() {  # mut2 <이름> <파일> <옛1> <새1> <옛2> <새2> — 변이 2단(한 갈래를 통째로 되돌린다)
  mut "$1" "$2" "$3" "$4" || return 1
  python3 - "$TMP/mb/$1/$2" "$5" "$6" <<'PYX'
import sys
p, o, n = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if s.count(o) != 1: print(f"mut2: «{o}» 개수 {s.count(o)}"); sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(o, n))
PYX
}

bash -n "$REAP" && ok "bash -n ft-seat-reap.sh" || bad "bash -n $REAP"
bash -n "$CLOSE" && ok "bash -n ft-seat-close.sh" || bad "bash -n $CLOSE"
cmp -s "$REAP" "$BIN/../kit/fable-team/bin/ft-seat-reap.sh" && ok "짝 cmp0 ft-seat-reap.sh" || bad "짝 다름 ft-seat-reap.sh"
cmp -s "$CLOSE" "$BIN/../kit/fable-team/bin/ft-seat-close.sh" && ok "짝 cmp0 ft-seat-close.sh" || bad "짝 다름 ft-seat-close.sh"

echo "== ⓐ 짧은 자식 1번(3세대 사슬) → reap left=0 rc=0 · 남은 사슬 0 (M1 마지막 정지 빼면 left≥1)"
spawn_faux "$S" "$MKX-a" - --gen 1 --max 3 --next "$MKX-a"
chk "ⓐ픽스처 1개" "$([ -n "$(pick "$MKX-a")" ] && echo 1)" 1
out="$(bash "$REAP" "$S")"; rc=$?
chk "ⓐleft=0 rc=0" "$rc $(endline "$out")" "0 left=0 rc=0"
chk "ⓐ남은 사슬 0" "$(wait_dead "$MKX-a"; pgrep -f "$MKX-a" | wc -l | tr -d ' ')" 0
mut M1 ft-seat-reap.sh 'for _ in range(3):' 'for _ in range(2):' || bad "M1 치환 실패"
spawn_faux "$S" "$MKX-m1" - --gen 1 --max 3 --next "$MKX-m1"
out="$(bash "$TMP/mb/M1/ft-seat-reap.sh" "$S")"; rc=$?
chk "M1 마지막 정지 빼면 left≥1 rc≠0(변이 잡힘)" "$rc $([ "$(endline "$out")" != "left=0 rc=0" ] && echo caught)" "1 caught"
kill_mk "$MKX-m1"

echo "== ⓑ 계속 남는 자식 = left≥1 rc=1 · ⓒ 정지 3회 상한 · M2 상한 없으면 4줄+ · M3 남은 것을 rc0"
spawn_faux "$S" "$MKX-b" -
out="$(FT_REAP_NOSIGNAL=1 bash "$REAP" "$S")"; rc=$?
chk "ⓑleft≥1 rc=1" "$rc $(endline "$out")" "1 left=1 rc=1"
chk "ⓒreap-kill 3줄(정지 3회 상한)" "$(nkills "$out")" 3
mut M2 ft-seat-reap.sh 'for _ in range(3):' 'for _ in range(12):' || bad "M2 치환 실패"
out="$(FT_REAP_NOSIGNAL=1 bash "$TMP/mb/M2/ft-seat-reap.sh" "$S")"; rc=$?
chk "M2 상한 없으면 정지 4줄+(변이 잡힘)" "$([ "$(nkills "$out")" -ge 4 ] && echo caught)" "caught"
mut M3 ft-seat-reap.sh 'rc = 1 if left else 0' 'rc = 0' || bad "M3 치환 실패"
out="$(FT_REAP_NOSIGNAL=1 bash "$TMP/mb/M3/ft-seat-reap.sh" "$S")"; rc=$?
chk "M3 남은 것을 rc0 으로(변이 잡힘)" "$rc $(grep -qE 'left=[1-9]' <<< "$out" && echo left)" "0 left"
kill_mk "$MKX-b"

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
out="$(PATH="$TMP/psbin:$PATH" PS_MODE=lstart PS_ARM="$ARMG" PS_PID="$TMP/pid-g" bash "$REAP" "$S")"; rc=$?
chk "ⓖKILL 0 · 살아 있음 · rc≠0" "$(alive "$L") $rc" "alive 1"
has "$out" "why=owner-changed" "ⓖ reap-skip why=owner-changed"
mut M5 ft-seat-reap.sh 'if p in t and t[p][3] == cand[p][1] and p not in anc' 'if p in t and p not in anc' || bad "M5 치환 실패"
ARMG2="$TMP/armed-g2"; rm -f "$ARMG2"; spawn_faux "$S" "$MKX-g2" "$ARMG2"
L2="$(pick "$MKX-g2")"; echo "$L2" > "$TMP/pid-g2"
PATH="$TMP/psbin:$PATH" PS_MODE=lstart PS_ARM="$ARMG2" PS_PID="$TMP/pid-g2" bash "$TMP/mb/M5/ft-seat-reap.sh" "$S" >/dev/null 2>&1
chk "M5 lstart 비교 빼면 죽는다(변이 잡힘)" "$(alive "$L2")" "dead"
kill_mk "$MKX-g"

echo "== ⓗ 소유 바뀜(주입 ps 표: argv 에서 --seat 규칙이 사라짐) → KILL 0 · 살아 있음 (M4 소유 재확인 빼면 죽는다)"
ARMS="$TMP/armed-s"; rm -f "$ARMS"; spawn_faux "$S" "$MKX-h" "$ARMS"
H="$(pick "$MKX-h")"; echo "$H" > "$TMP/shim-h"
out="$(PATH="$TMP/psbin:$PATH" PS_MODE=owner PS_ARM="$ARMS" PS_PID="$TMP/shim-h" bash "$REAP" "$S")"; rc=$?
chk "ⓗKILL 0 · 살아 있음(규칙이 사라져 후보 아님)" "$(alive "$H")" "alive"
mut M4 ft-seat-reap.sh 'and p not in svc and still_mine(p, cand[p][0], t, tree, bg, cw, wt, oth)' 'and p not in svc' || bad "M4 치환 실패"
ARMS2="$TMP/armed-s2"; rm -f "$ARMS2"; spawn_faux "$S" "$MKX-h2" "$ARMS2"
H2="$(pick "$MKX-h2")"; echo "$H2" > "$TMP/shim-h2"
PATH="$TMP/psbin:$PATH" PS_MODE=owner PS_ARM="$ARMS2" PS_PID="$TMP/shim-h2" bash "$TMP/mb/M4/ft-seat-reap.sh" "$S" >/dev/null 2>&1
chk "M4 소유 재확인 빼면 죽는다(변이 잡힘)" "$(alive "$H2")" "dead"
kill_mk "$MKX-h"

echo "== ⓕ h8128 꼴 — 세션 kill 뒤에도 남는 ②b 자식 → CLOSED-SESSION · 세션 부재 · reap left=0 · close-fail 기록 0"
printf '{"_master": "M#1", "M#1": {"role": "master", "tick": "t"}, "%s": {"role": "tester", "agent": "claude", "model": "m", "tick": null}, "%s": {"role": "tester", "agent": "claude", "model": "m", "tick": null}}\n' "$S" "$S1" > "$TMP/cf/seats.json"
tmux new-session -d -s "$S" -c "$TMP/wt" -e "FT_SEAT=$S"; tmux new-session -d -s "$S1" -c "$TMP/wt" -e "FT_SEAT=$S1"; : > "$ZC_RESUME_DIR/$S.json"
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
while tmux has-session -t "=$KP_SEAT" 2>/dev/null; do sleep 0.02; done   # 세션이 죽은 «뒤» 자식을 낳는다(h8128 꼴)
n=0
while [ "$n" -lt 200 ]; do   # 10ms 마다 하나 — «계속 태어나는 자식»(정지·재조사 사이에 반드시 새 자식이 있다)
  ( cd "$KP_DIR" && nohup "$KP_BASH" "$KP_FAUX" --seat "$KP_SEAT" "$KP_TAG" </dev/null >/dev/null 2>&1 & )
  n=$((n+1)); sleep 0.01
done
EOS
tmux new-session -d -s "$SD" -c "$TMP/wt" -e "FT_SEAT=$SD"; tmux new-session -d -s "$SD1" -c "$TMP/wt" -e "FT_SEAT=$SD1"; : > "$ZC_RESUME_DIR/$SD.json"
# tmux 얇은 껍데기 — kill-session «그 순간» 감시자를 켜 자식이 태어난다(h8128: 세션이 죽으며 뜨는 git 자식)
mkdir -p "$TMP/tmuxbin"; REAL_TMUX="$(command -v tmux)"
cat > "$TMP/tmuxbin/tmux" <<EOS
#!/bin/bash
"$REAL_TMUX" "\$@"; rc=\$?
if [ "\$1" = kill-session ]; then
  ( cd "$TMP/else" && STUBBORN_ARM="$TMP/armed-j" nohup "$BASH_X" "$TMP/faux/ft-bg-loop.sh" --seat "$SD" "$MKX-j" </dev/null >/dev/null 2>&1 & )   # 세션이 죽는 그 순간 태어나는 자식
  STUBBORN_ARM="$TMP/armed-j" KP_SEAT="$SD" KP_TAG="$MKX-j" KP_DIR="$TMP/else" KP_BASH="$BASH_X" KP_FAUX="$TMP/faux/ft-bg-loop.sh" nohup bash "$TMP/keeper.sh" </dev/null >/dev/null 2>&1 &   # bg-ok: cleanup trap 이 keeper·표식 프로세스를 kill -9 한다
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
tmux new-session -d -s "$SD" -c "$TMP/wt" -e "FT_SEAT=$SD"
out="$(PATH="$TMP/tmuxbin:$PATH" bash "$TMP/mb/M6/ft-seat-close.sh" "$SD" --reason "r1568 변이" --seats "$TMP/cf/seats-d.json" 2>/dev/null)"; rc=$?
chk "M6 자식 0 판정 빼면 CLOSED(변이 잡힘)" "$([ "$rc" -eq 0 ] && head -1 <<< "$out" | grep -c '^CLOSED')" "1"
pkill -f "$TMP/keeper.sh" 2>/dev/null; kill_mk "$MKX-j"; sleep 0.2
mut M7 ft-seat-close.sh 'CF="$CFD/$SEAT.txt"' 'CF=/dev/null' || bad "M7 치환 실패"
rm -rf "$TMP/cf/state"
tmux new-session -d -s "$SD" -c "$TMP/wt" -e "FT_SEAT=$SD"
PATH="$TMP/tmuxbin:$PATH" bash "$TMP/mb/M7/ft-seat-close.sh" "$SD" --reason "r1568 변이" --seats "$TMP/cf/seats-d.json" >/dev/null 2>&1
chk "M7 기록 쓰기 빼면 기록 0(변이 잡힘)" "$(ls "$TMP/cf/state/close-fail" 2>/dev/null | wc -l | tr -d ' ')" 0

echo "== ⓚ 자식 정리 뒤 다음 닫기 성공 → CLOSED-SESSION · 기록 지워짐"
pkill -f "$TMP/keeper.sh" 2>/dev/null; kill_mk "$MKX-j"; wait_dead "$MKX-j"
out="$(bash "$CLOSE" "$SD" --reason "r1568 시험 2" --seats "$TMP/cf/seats-d.json" 2>/dev/null)"; rc=$?
chk "ⓚrc0 · CLOSED-SESSION · kill=none" "$rc $(head -1 <<< "$out" | grep -oE 'CLOSED-SESSION|kill=none' | tr '\n' ' ' | sed 's/ $//')" "0 CLOSED-SESSION kill=none"
chk "ⓚ기록 지워짐" "$(ls "$TMP/cf/state/close-fail" 2>/dev/null | wc -l | tr -d ' ')" 0


echo "== R1 (DA②) 죽은 좌석(--verdict) 도 «세션 부재 ∧ 최종 재조사 left=0» — 자식이 살아 있으면 CLOSED-DEAD 0(거짓 성공) 0"
S3="r1568c-$$#0"
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
mkdir -p "$TMP/cf2/keep"
cat > "$TMP/keep2.sh" <<'EOS'
#!/bin/bash
n=0
while [ "$n" -lt 200 ]; do
  ( cd "$KP_DIR" && nohup "$KP_BASH" "$KP_FAUX" --seat "$KP_SEAT" "$KP_TAG" </dev/null >/dev/null 2>&1 & )
  n=$((n+1)); sleep 0.01
done
EOS
KP_SEAT="$S3" KP_TAG="$MKX-r1b" KP_DIR="$TMP/else" KP_BASH="$BASH_X" KP_FAUX="$TMP/faux/ft-bg-loop.sh" nohup bash "$TMP/keep2.sh" </dev/null >/dev/null 2>&1 &
sleep 0.4
out="$(dead_close "$CLOSE")"; rc=$?
chk "R1 자식 살아 있음 → rc≠0 · CLOSE-FAIL · «CLOSED» 0" "$([ "$rc" -ne 0 ] && echo ne0) $(head -1 <<< "$out" | grep -c '^CLOSE-FAIL') $(grep -c 'CLOSED' <<< "$out")" "ne0 1 0"
chk "R1 실패 기록 1개" "$(ls "$TMP/cf2/state/close-fail" 2>/dev/null | wc -l | tr -d ' ')" 1
pkill -f "$TMP/keep2.sh" 2>/dev/null; kill_mk "$MKX-r1b"
mut2 M9 ft-seat-close.sh 'else reap; KILL=none; fi' 'else [ "$DEAD" = 1 ] || reap; KILL=none; fi' $'\nfinal\n' $'\n[ "$DEAD" = 1 ] || final\n' || bad "M9 치환 실패"
KP_SEAT="$S3" KP_TAG="$MKX-r1c" KP_DIR="$TMP/else" KP_BASH="$BASH_X" KP_FAUX="$TMP/faux/ft-bg-loop.sh" nohup bash "$TMP/keep2.sh" </dev/null >/dev/null 2>&1 &
sleep 0.4; rm -rf "$TMP/cf2/state"
out="$(dead_close "$TMP/mb/M9/ft-seat-close.sh")"; rc=$?
chk "M9 DEAD 자식 정리 빼면 CLOSED-DEAD 0(변이 잡힘)" "$rc $(head -1 <<< "$out" | grep -c '^CLOSED-DEAD')" "0 1"
pkill -f "$TMP/keep2.sh" 2>/dev/null; kill_mk "$MKX-r1c"

echo "== R2 (DA②) 후보③ — TERM 뒤 cwd 가 워크트리 밖으로 바뀌면 KILL 0 · 살아 있음 (M10 cwd 재확인 빼면 죽는다)"
S4="r1568w-$$#0"; MOVED="$TMP/moved-$$"; rm -f "$MOVED"; mkdir -p "$TMP/wt2"; git -C "$TMP/wt2" init -q
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

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
