#!/usr/bin/env bash
# test_r1882_stall_pi_error_turn.sh — r1882 g = pi 좌석 턴이 모델 일시 오류(UNAVAILABLE)로 끝나 멈춤 → 표준 ring 1회 + 고정 [재개] 본문 · 같은 서명 둘째 = 계보 master [멈춤] 1통 · 셋째 = 0통.
#   반례 ①~⑥ + 변이 M1(120초 조건 빼기 → ④ FAIL) · M2(서명 기억 빼기 → ②③ FAIL) + kit 짝 cmp.
# 격리: 임시 루트 · 가짜 pi jsonl · FT_NOW · 가짜 명부·tmux·mbox(_stall_world) — 실 장부·명부·pane·mbox 쓰기 0 · sleep 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"; TRK="$HERE/../bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
cat >"$T/drive.py" <<'PY'
import json, os, subprocess, sys
from datetime import datetime, timezone
from pathlib import Path
sys.path.insert(0, sys.argv[3])
from _stall_world import World, counts, NOW
BIN, case = Path(sys.argv[1]), sys.argv[2]
STATUS = ('#!/bin/sh\ncase "$1" in\n  turn) [ "$2" = --file ] && exec bash "$R1882_REAL" turn --file "$3"; cat "$FT_STUB/turn/$2" 2>/dev/null || echo "UNKNOWN - - - pane";;\n'
          '  jsonl) [ -f "$FT_STUB/jsonl/$2.jsonl" ] && echo "$FT_STUB/jsonl/$2.jsonl" || exit 1;;\nesac\n')
iso = lambda t: datetime.fromtimestamp(t, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
def msg(t, role, **kw):
    return {"type": "message", "id": f"m{t}{role}", "timestamp": iso(t), "message": {"role": role, "content": [], **kw}}
def world(err_ago, err="503 credential validation failed"):
    w = World(Path(sys.argv[4]) / case)
    (w.stub / "st.sh").write_text(STATUS)
    w.env.update(FT_SEAT_STATUS=str(w.stub / "st.sh"), R1882_REAL=str(BIN / "ft-seat-status.sh"), FT_SEATS_JSON="/nonexistent",
                 FT_CRITICAL_OFF="1", FT_STALL_PENALTY_AUTO="0")
    w.state("t1-master#1", "WORKING", 0)
    w.pi = w.stub / "jsonl/t1-nano#0.jsonl"
    recs = [{"type": "session", "version": 3, "id": "s", "timestamp": iso(NOW - 900), "cwd": "/tmp"},
            msg(NOW - err_ago - 5, "user"), msg(NOW - err_ago, "assistant", stopReason="error", errorMessage=err)]
    w.pi.write_text("".join(json.dumps(r) + "\n" for r in recs))
    return w
def scan(w):
    r = subprocess.run(["bash", str(BIN / "ft-stall-scan.sh")], env=w.env, capture_output=True, text=True, timeout=60)
    assert r.returncode == 0, r.stdout + r.stderr
    return counts(r.stdout), r.stdout
def mine(w):  # 이 좌석 관련 쪽지만(헤드라인·planner 잡음 제외)
    return [x for x in w.mbox_log() if "t1-nano#0" in x]
def chk(name, ok, extra=""):
    print(("ok " if ok else "NG ") + name + (f" — {extra}" if extra and not ok else ""))
    return ok
ok = True
if case == "seq":  # ①②③⑥ 한 세계
    w = world(150)
    c, out = scan(w)
    m = mine(w)
    body = [x for x in m if x.startswith("send|t1-nano#0|")]
    ok &= chk("① g=1 · ring 1 · 고정 본문", c.get("g") == "1" and [x for x in m if x.startswith("ring|")] == ["ring|t1-nano#0|"]
              and len(body) == 1 and "[재개] 모델 일시 오류로 턴이 끝났다(" in body[0] and ") · 마지막 일을 이어서" in body[0], f"{c} {m}")
    w.advance(120); n1 = len(m)
    c, out = scan(w); m2 = mine(w)[n1:]
    ok &= chk("② ring 0 · master [멈춤] 1통", c.get("g") == "1" and not [x for x in m2 if x.startswith("ring|")]
              and len(m2) == 1 and m2[0].startswith("send|t1-master#1|") and "[멈춤] t1-nano#0" in m2[0], f"{c} {m2}")
    w.advance(120); n2 = len(mine(w))
    c, out = scan(w)
    ok &= chk("③ 재알림 0", c.get("g") == "1" and len(mine(w)) == n2, f"{c} {mine(w)[n2:]}")
    w.advance(120); now = int(w.env["FT_NOW"])
    with w.pi.open("a") as fh:
        fh.write(json.dumps(msg(now - 20, "user")) + "\n" + json.dumps(msg(now - 10, "assistant", stopReason="stop")) + "\n")
    c, out = scan(w)
    ok &= chk("⑥ 새 정상 stop → g=0 · 쪽지 0", c.get("g") == "0" and len(mine(w)) == n2, f"{c} {mine(w)[n2:]}")
elif case == "young":
    w = world(60); c, out = scan(w)
    ok &= chk("④ 60초 전 → g=0 · 처리 0", c.get("g") == "0" and not mine(w), f"{c} {mine(w)}")
elif case == "ratelimit":
    w = world(150, "rate_limit_error"); c, out = scan(w)
    ok &= chk("⑤ rate_limit_error → g=0 · 처리 0", c.get("g") == "0" and not mine(w), f"{c} {mine(w)}")
sys.exit(0 if ok else 1)
PY
drive() { python3 "$T/drive.py" "$1" "$2" "$HERE/scripts" "$T/w-$3" >"$T/$3.log" 2>&1; }
for c in seq young ratelimit; do
  s=$SECONDS; drive "$KIT" "$c" "k-$c"; r=$?; sed 's/^/  /' "$T/k-$c.log"; ck "$c ($((SECONDS - s))초)" $r
done

# 변이 — 사본 bin 한 곳씩 바꾸면 그 반례가 FAIL 해야 한다
mutate() {  # $1 이름 $2 원문 $3 바꿀 글 $4 case
  rm -rf "$T/mb"; cp -Rp "$KIT" "$T/mb"
  python3 - "$T/mb/ft_stall_scan.py" "$2" "$3" <<'PY' || { echo "FAIL $1 — 변이 자리 못 찾음"; fail=$((fail+1)); return; }
import sys
p, a, b = sys.argv[1:]
s = open(p, encoding="utf-8").read()
assert s.count(a) == 1, s.count(a)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
  drive "$T/mb" "$4" "m-$4-$RANDOM"; [ $? -ne 0 ]; ck "$1 → $4 FAIL" $?
}
mutate "M1 120초 조건 빼기" 'at is not None and self.now - at >= G_MIN_S' 'at is not None' young
mutate "M2 서명 기억 빼기" 'n = sigs.get(f["sig"], 0)' 'n = 0' seq

# 짝 사본(harness/bin ↔ kit) 바이트·실행 비트 동일
cmp -s "$TRK/ft_stall_scan.py" "$KIT/ft_stall_scan.py" && [ "$(stat -f %Lp "$TRK/ft_stall_scan.py")" = "$(stat -f %Lp "$KIT/ft_stall_scan.py")" ]; ck "짝 사본 ft_stall_scan.py" $?
echo "FAIL=$fail"; [ "$fail" = 0 ]
