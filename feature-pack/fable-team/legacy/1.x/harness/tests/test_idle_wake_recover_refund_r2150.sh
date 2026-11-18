#!/usr/bin/env bash
# test_idle_wake_recover_refund_r2150.sh — r2150: ft-idle-wake 확장 좌석 복구(recover)는 깨움이 확실히 안 나간 갈래에서 예약을 돌려준다.
#  F1 예약 뒤 재확인 예외 ① · F2 Escape 예외 ② · F3 ring --reserved rc≠0 ③ · F4 ring 예외 = unsure·환불 0 ④ · 정상 ⑤ · F5 run 상한 ≤25 ⑦
#  격리: 임시 루트 · 스텁 mbox.sh(budget · ring rc · 호출 기록) · 가짜 tmux(실 tmux 0) · 가짜 HOME(확장 파일) — r2128 바깥 쪽 대역 꼴.
#  시간 초과 주입 = 시험 쪽 PYTHONPATH 의 sitecustomize.py 가 subprocess.run 을 감싼다: 예약(budget reserve) 뒤 argv 에 R2150_INJECT 낱말이
#        있으면 TimeoutExpired · ft-idle-wake 의 run() 이 넘긴 timeout 값 기록(제품에 시험 전용 문 0 · sleep 0).
#  기준판: R2150_IW=<옛 ft-idle-wake.sh> R2150_MUT=0 bash <이 파일> → ① ② ③ ⑦ FAIL
#  변이(사본): M1 F1 환불 지움 → ① · M2 F3 환불 지움 → ③ · M3 ring 예외에도 환불 → ④ — 변이마다 원본 대조 1회.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
IW="${R2150_IW:-$HERE/../bin/ft-idle-wake.sh}"
MUT="${R2150_MUT:-1}"
SEAT="byz-knowledge-master-pi#107"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "기대 '$3' 실제 '$2'"; fi; }
[ -f "$IW" ] || { echo "FAIL 대상 없음 $IW"; exit 1; }
T="$(mktemp -d "${TMPDIR:-/tmp}/r2150.XXXXXX")"; trap 'rm -rf "$T"' EXIT
t0=$(date +%s); NOW="$t0"
mkdir -p "$T/stub" "$T/site" "$T/home/.pi/agent/extensions"; : > "$T/home/.pi/agent/extensions/ft-mbox-wake.ts"
cat > "$T/stub/mbox.sh" <<'EOF'
#!/bin/bash
echo "$*" >> "$BOX/calls.log"
case "$1 $2" in "budget reserve"|"budget refund") exit 0;; esac
case "$1" in
  ring) case " $* " in *" --reserved "*) echo "RING $2 doorbell=sent"; exit "${RING_RC:-0}";; esac; echo "RING $2 doorbell=ext";;
  send) echo "SENT #1";;
esac
exit 0
EOF
cat > "$T/stub/tmux.sh" <<'EOF'
#!/bin/bash
echo "$*" >> "$BOX/tmux.log"
case "$1" in
  list-clients) cat "$BOX/activity";;
  list-panes) echo "$SEAT_NAME|%9";;
  show-environment) exit 1;;
esac
exit 0
EOF
printf '#!/bin/bash\necho "$(cat "$BOX/status") 2026-11-16T00:00:00 1000 yes jsonl"\n' > "$T/stub/status.sh"
printf 'import sys\nprint(sys.argv[2])\n' > "$T/stub/mbox.py"
cat > "$T/site/sitecustomize.py" <<'EOF'
import os, subprocess, sys
_real, _armed = subprocess.run, [False]
def _run(argv, *a, **kw):
    if "recover" in sys._getframe(1).f_globals:  # ft-idle-wake 의 run() 이 부른 것만(빈 석 채우기 등 다른 도구 0)
        with open(os.path.join(os.environ["BOX"], "timeouts.log"), "a") as f:
            f.write(f"{kw.get('timeout')}\n")
        if "reserve" in argv:
            _armed[0] = True
        w = os.environ.get("R2150_INJECT")
        if _armed[0] and w and w in argv:
            raise subprocess.TimeoutExpired(argv, kw.get("timeout") or 0)
    return _real(argv, *a, **kw)
subprocess.run = _run
EOF
KEY="$(printf '%s' "$SEAT" | sed 's/[^A-Za-z0-9._#-]/_/g')"
box() { # <이름> <seq> — 확장 좌석 11분 미읽음 · .beat 사건이 미읽음 앞 · IDLE · 키 입력 오래됨
  BOX="$T/box-$1"; rm -rf "$BOX"; mkdir -p "$BOX/.fable-team/comm" "$BOX/.fable-team/state/pi-wake"
  printf '{"_master":"%s","%s":{"agent":"pi"}}\n' "$SEAT" "$SEAT" > "$BOX/.fable-team/seats-knowledge.json"
  printf '{"_master":"planner-m#1","_desk":"byz-planner-desk#3"}\n' > "$BOX/.fable-team/seats-planner.json"
  python3 -c 'import json,sys,time;print(json.dumps({"seq":int(sys.argv[1]),"ts":time.strftime("%Y-%m-%dT%H:%M:%S",time.localtime(int(sys.argv[2])-660)),"to":sys.argv[3],"from":"x","body":"[발주] 일"}))' "$2" "$NOW" "$SEAT" > "$BOX/.fable-team/comm/mailbox.jsonl"
  echo "event=$((NOW - 1000)) check=$((NOW - 900)) why=empty inTurn=0 wakePending=0 watchers=2 rearm=$((NOW - 1000)) woke=0" > "$BOX/.fable-team/state/pi-wake/$KEY.beat"
  echo IDLE > "$BOX/status"; echo "$((NOW - 1000))" > "$BOX/activity"; : > "$BOX/calls.log"; : > "$BOX/tmux.log"; : > "$BOX/timeouts.log"
}
iw() { # <스크립트> <시계 오프셋초> [env…]
  local s="$1" off="$2"; shift 2
  env BOX="$BOX" SEAT_NAME="$SEAT" HOME="$T/home" FT_ROOT="$BOX" FT_MBOX="$T/stub/mbox.sh" FT_MBOX_PY="$T/stub/mbox.py" FT_SEAT_STATUS="$T/stub/status.sh" \
    FT_TMUX="bash $T/stub/tmux.sh" FT_IDLE_WAKE_NOW="$((NOW + off))" FT_IDLE_SLOT_LOG="$BOX/slot.log" PYTHONPATH="$T/site" "$@" timeout 70 bash "$s" >/dev/null 2>"$BOX/err"
}
n() { local c; c="$(grep -c -- "$1" "$2" 2>/dev/null)"; printf '%s' "${c:-0}"; }
cnt() { printf 'res%s ref%s esc%s ring%s send%s' "$(n '^budget reserve' "$BOX/calls.log")" "$(n '^budget refund' "$BOX/calls.log")" \
  "$(n 'send-keys -t %9 Escape' "$BOX/tmux.log")" "$(n '^ring .*--reserved' "$BOX/calls.log")" "$(n '^send ' "$BOX/calls.log")"; }
rec() { python3 -c 'import json,sys;print((json.load(open(sys.argv[1])).get(sys.argv[2]) or {}).get("result","-"))' "$BOX/.fable-team/state/idle-wake.json" "$SEAT" 2>/dev/null || echo "-"; }
lg() { n "$SEAT seq=$1 .*$2" "$BOX/.fable-team/state/idle-wake.log"; }
# 사례 = 첫 실행(주입) 결과 | 다음 실행(주입 끔 · 30초 뒤) 누적 결과
c1() { box 1 11; iw "$1" 0 R2150_INJECT=turn; local a; a="$(cnt) $(rec) log$(lg 11 '예약 뒤 재확인 예외 TimeoutExpired — refund rc=0 · 복구 깨움 0')"; iw "$1" 30; echo "$a | $(cnt) $(rec)"; }
c2() { box 2 21; iw "$1" 0 R2150_INJECT=send-keys; local a; a="$(cnt) $(rec) log$(lg 21 'refund rc=0 · 복구 깨움 0')"; iw "$1" 30; echo "$a | $(cnt) $(rec)"; }
c3() { box 3 31; iw "$1" 0 RING_RC=1; echo "$(cnt) $(rec) log$(lg 31 '복구 ring rc=1 .*refund rc=0')"; }
c4() { box 4 41; iw "$1" 0 R2150_INJECT=--reserved; local a; a="$(cnt) $(rec)"; iw "$1" 30; echo "$a | $(cnt) $(rec) log$(lg 41 '복구 결과 불명 TimeoutExpired — 재전송 0')"; }
c5() { box 5 51; iw "$1" 0; echo "$(cnt) $(rec)"; }
W1="res1 ref1 esc0 ring0 send0 - log1 | res2 ref1 esc1 ring1 send2 sent"
W2="res1 ref1 esc0 ring0 send0 failed log1 | res2 ref1 esc1 ring1 send2 sent"  # esc0 = 주입이 스텁 앞에서 막음
W3="res1 ref1 esc1 ring1 send0 failed log1"
W4="res1 ref0 esc1 ring0 send0 unsure | res1 ref0 esc1 ring0 send0 unsure log1"  # ring0 = 주입이 스텁 앞에서 막음 · 다음 실행도 ring 시도 0(esc 그대로 1)
W5="res1 ref0 esc1 ring1 send2 sent"
eq "① 예약 뒤 STATUS 시간 초과 → refund 1 · Escape 0 · ring 0 · st 없음 · 로그 1 · 다음 실행 = 복구 1회" "$(c1 "$IW")" "$W1"
eq "② Escape 시간 초과 → refund 1 · ring 0 · failed · 다음 실행 = 복구 다시 1회" "$(c2 "$IW")" "$W2"
eq "③ ring --reserved rc=1 → refund 1 · failed · 로그에 refund rc" "$(c3 "$IW")" "$W3"
eq "④ ring 시간 초과 → refund 0 · unsure · 같은 seq 다음 실행 Escape·ring 0" "$(c4 "$IW")" "$W4"
eq "⑤ 정상 → reserve 1 · Escape 1 · ring --reserved 1 · 알림 2 · sent · refund 0" "$(c5 "$IW")" "$W5"
eq "⑦ ①~⑤ 동안 ft-idle-wake run timeout 모두 ≤ 25" "$(cat "$T"/box-*/timeouts.log | awk '$1=="None"||$1>25{print}' | sort -u | tr '\n' ' ')" ""
eq "⑦-b timeout 기록 있음(주입기 작동)" "$([ "$(cat "$T"/box-*/timeouts.log | wc -l)" -gt 10 ] && echo yes || echo no)" yes
eq "Traceback 0" "$(cat "$T"/box-*/err | grep -c Traceback)" 0
t1=$(date +%s)

# ══ 변이 M1~M3(사본) — 변이 = 그 사례 FAIL · 원본 = 같은 사례 PASS ═══════════════════════════════
mut() { python3 - "$@" <<'PY'
import sys; src, dst, old, new = sys.argv[1:5]; s = open(src, encoding="utf-8").read()
if s.count(old) != 1: sys.exit(f"변이 자리 {s.count(old)}곳")
open(dst, "w", encoding="utf-8").write(s.replace(old, new))
PY
}
mi() { # <이름> <사례 함수> <기대> <옛> <새> — 같은 폴더에 ft_card_rest.py 사본
  mkdir -p "$T/mi-$1"; cp "$(dirname "$IW")/ft_card_rest.py" "$T/mi-$1/" 2>/dev/null
  mut "$IW" "$T/mi-$1/ft-idle-wake.sh" "$4" "$5" >/dev/null 2>&1 || { bad "$1 변이 자리 없음"; return; }
  local m o; m="$($2 "$T/mi-$1/ft-idle-wake.sh")"; o="$($2 "$IW")"
  if [ "$m" != "$3" ]; then ok "$1 → $2 FAIL 검출($m)"; else bad "$1 → $2 FAIL 검출"; fi
  eq "$1 대조 원본 → $2 PASS" "$o" "$3"; }
if [ "$MUT" = 1 ]; then
  mi M1 c1 "$W1" "재확인 예외 {type(e).__name__} — refund rc={budget('refund', seat)}" "재확인 예외 {type(e).__name__} — refund rc=0"
  mi M2 c3 "$W3" "rf = \"\" if r.returncode == 0 else f\" · refund rc={budget('refund', seat)}\"" "rf = \"\" if r.returncode == 0 else \" · refund rc=0\""
  mi M3 c4 "$W4" '복구 결과 불명 {type(e).__name__} — 재전송 0")' '복구 결과 불명 {type(e).__name__} — 재전송 0"); budget("refund", seat)'
else echo "SKIP 변이 M1~M3 — R2150_MUT=0"; fi
t2=$(date +%s)
bash -n "$0" && ok "S bash -n rc0" || bad "S bash -n rc0"
echo "TIME 사례 $((t1 - t0))s · 변이 $((t2 - t1))s"
echo "---"
if [ "$fail" = 0 ]; then echo "ALL PASS"; exit 0; fi
echo "FAIL ($fail)"; exit 1
