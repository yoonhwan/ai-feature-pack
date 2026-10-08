#!/usr/bin/env bash
# test_mbox_reply_exempt_cap.sh — 회신 면제 사용 이력 보존 + EXEMPT_CAP fail-closed (판정 423 ④ · 구현 DA r2 Q1 잔여)
#  ⑦ 받은 seq 201개에 차례로 `쪽지 #seq` 회신 → 첫 seq 재인용은 면제 0 (가드 로그 200행 절단에 면제 이력이 밀리지 않는다)
#  ⑧ 다른 좌석 일반 발신 250건이 끼어도(공용 로그 넘침) 같은 결과
#  ⑨ FT_MBOX_EXEMPT_CAP=3 · 면제 행 3개 → 새 seq 회신은 면제 0 + stderr EXEMPT_CAP 1줄 · 발신은 산다
#  ⑩ 창(600초) 지난 면제 행은 저장 때 빠진다 (시각 주입)
#  변이: 면제 행 분리 보존을 빼면 ⑦ FAIL · 상한 검사를 빼면 ⑨ FAIL
# 임시 FT_MBOX_DIR 에서 mbox.py 를 직접 import — 실제 send·tmux·라이브 .fable-team 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."
SRC="$REPO/tools/comm-canonical/mbox.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (기대 '$3' 실제 '$2')"; }

cat > "$T/probe.py" <<'PYEOF'
import contextlib, io, json, os, sys, time, types
C, scen = sys.argv[1], sys.argv[2]
sys.path.insert(0, C)
import mbox

def quiet_send(*a, **k):
    with contextlib.redirect_stdout(io.StringIO()):
        mbox.send(*a, **k)

def last_seq():
    return max(r["seq"] for r in mbox._load(C))

def window_log():
    return [r for r in mbox._guard_log() if time.time() - r.get("t", 0) < max(mbox.FANOUT_WIN, mbox.RATE_WIN)]

def reply_201(noise):
    frm, seqs = "rx#1", []
    for i in range(201):
        quiet_send(frm, "mk%d#1" % i, "받을 쪽지 %d" % i)
        seqs.append(last_seq())
    for i, s in enumerate(seqs):
        quiet_send("pe%d#1" % i, frm, "[rx#1->pe%d#1] 쪽지 #%d 회신 %d" % (i, s, i))
    if noise:
        for i in range(250):
            quiet_send("nzr%d#1" % i, "nz%d#1" % i, "남의 일반 발신 %d" % i)
    ex = mbox._reply_exempt(frm, "쪽지 #%d 재인용" % seqs[0], window_log())
    kept = any(r.get("r") == [seqs[0]] for r in mbox._guard_log())
    print("REEX", ex, "KEPT", kept, "LOG", len(mbox._guard_log()))

if scen in ("a", "b"):
    reply_201(scen == "b")
elif scen == "cap":
    frm, seqs = "cx#1", []
    for i in range(4):
        quiet_send(frm, "mc%d#1" % i, "받을 쪽지 %d" % i)
        seqs.append(last_seq())
    for i in range(3):
        quiet_send("pc%d#1" % i, frm, "[cx#1->pc%d#1] 쪽지 #%d 회신" % (i, seqs[i]))
    with contextlib.redirect_stderr(io.StringIO()):
        ex = mbox._reply_exempt(frm, "쪽지 #%d 네 번째" % seqs[3], window_log())
    err = io.StringIO()
    with contextlib.redirect_stderr(err):
        try:
            quiet_send("pc3#1", frm, "[cx#1->pc3#1] 쪽지 #%d 네 번째" % seqs[3])
            sent = True
        except SystemExit:
            sent = False
    last = [r for r in mbox._guard_log() if r["f"] == frm][-1]
    print("CAP", ex, "WARN", err.getvalue().count("EXEMPT_CAP"), "SENT", sent, "R", last["r"])
elif scen == "win":
    clock = [1000.0]
    real = time
    mbox.time = types.SimpleNamespace(**{n: getattr(real, n) for n in dir(real) if not n.startswith("__")})
    mbox.time.time = lambda: clock[0]
    mbox._guard_record("t#1", "f#1", "a", [111])
    clock[0] = 1300.0
    mbox._guard_record("t#1", "f#1", "b", [222])
    clock[0] = 1601.0
    mbox._guard_record("t#1", "f#1", "c", [])
    print("WIN", [r["r"] for r in mbox._guard_log()])
PYEOF

run() {  # <mbox.py 경로> <시나리오> [env=값…] → 새 임시 comm 에서 실행
  local py="$1" scen="$2"; shift 2
  local c="$T/comm-$RANDOM$RANDOM"; mkdir -p "$c"; cp "$py" "$c/mbox.py"
  env FT_MBOX_DIR="$c" "$@" python3 "$T/probe.py" "$c" "$scen" 2>&1 | grep -E '^(REEX|CAP|WIN)'
}

eq "⑦ 201개 회신 뒤 첫 seq 재인용 = 면제 0 · 면제 행 보존" "$(run "$SRC" a | sed 's/ LOG .*//')" "REEX [] KEPT True"
eq "⑧ 다른 좌석 일반 발신 250건이 끼어도 같은 결과" "$(run "$SRC" b | sed 's/ LOG .*//')" "REEX [] KEPT True"
eq "⑨ EXEMPT_CAP=3 → 새 seq 회신 면제 0 · stderr EXEMPT_CAP 1줄 · 발신 산다 · 기록 r=[]" "$(run "$SRC" cap FT_MBOX_EXEMPT_CAP=3)" "CAP [] WARN 1 SENT True R []"
eq "⑩ 창(600초) 지난 면제 행은 저장 때 빠진다 · 안 지난 건 남는다" "$(run "$SRC" win)" "WIN [[222], []]"

# 변이 대조 — 사본의 한 줄만 바꿔 위 시험이 «잡는지» 본다
mut() {  # <원문> <대체> → $T/mut.py
  python3 - "$SRC" "$T/mut.py" "$1" "$2" <<'PYEOF'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
assert sys.argv[3] in s, "변이 대상 없음: " + sys.argv[3]
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4], 1))
PYEOF
}
mut 'log = sorted([r for r in log if not _is_exempt_row(r)][-200:] + ex[-EXEMPT_CAP:], key=lambda r: r.get("t", 0))' 'log = log[-200:]'
r="$(run "$T/mut.py" a | sed 's/ LOG .*//')"
[ "$r" != "REEX [] KEPT True" ] && ok "변이: 면제 행 분리 보존을 빼면 ⑦ 이 FAIL(첫 seq 가 재면제됨): $r" || bad "변이: 분리 보존을 빼도 ⑦ 이 통과함"
mut '>= EXEMPT_CAP:  # 이력이' '>= 10**9:  # 이력이'
r="$(run "$T/mut.py" cap FT_MBOX_EXEMPT_CAP=3)"
case "$r" in "CAP []"*) bad "변이: 상한 검사를 빼도 ⑨ 가 통과함: $r";; *) ok "변이: 상한 검사를 빼면 ⑨ 가 FAIL(새 seq 가 면제됨): $r";; esac

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
