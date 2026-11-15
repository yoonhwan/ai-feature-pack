#!/usr/bin/env bash
# test_stall_scan_desk_heartbeat_r2080.sh — r2080 A1~A5: desk 틱 끊김(t) = 좌석 밖 감시가 desk 를 깨우고 planner 팀장에 1통.
#   반례 ①~⑤ (카드 r2080-succession-tick-field-close-alarm-window) + 변이 M1~M4(사본 bin · 같은 사례 원본 1회 대조) + bin↔kit cmp.
#   격리: _stall_world 가짜 세계(임시 명부·우편함·tmux·mbox 스텁 · FT_NOW 고정) — 실 우편함·명부·tmux 0 · sleep 0.
#   R2080_BIN = 시험할 bin(기본 kit) · 인자 = 사례 이름(없으면 전부) · 기준판 = 팩 origin/main bin 을 R2080_BIN 으로 주면 ① Red.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"; TRK="$HERE/../bin"; SC="$HERE/scripts"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
cat > "$T/cases.py" <<'PY'
import json, os, subprocess, sys
from datetime import datetime
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from _stall_world import NOW, World, counts

BIN = Path(sys.argv[2])
TMUX = ('#!/bin/sh\ncase "$1" in\n  list-sessions) case "$3" in *session_created*) cat "$FT_STUB/created" 2>/dev/null;; *) cat "$FT_STUB/tmux" 2>/dev/null;; esac;;\n'
        '  list-panes) awk \'{print $1"|%"NR}\' "$FT_STUB/tmux";;\n  send-keys) echo "$*" >> "$FT_STUB/tmux.log";;\nesac\n')
D, P = "desk#1", "planner#1"


def world(tmp, desk=True):
    w = World(Path(tmp))
    (w.stub / "tmux.sh").write_text(TMUX)
    if desk:
        p = w.root / ".fable-team/seats-planner.json"
        d = json.loads(p.read_text(encoding="utf-8"))
        d[D] = {"role": "desk"}
        p.write_text(json.dumps(d), encoding="utf-8")
        w.live.append(D)
        w._tmux()
        w.state(D, "IDLE", 5)
    for s in ("planner#1", "t1-master#1", "t1-nano#0"):
        w.state(s, "WORKING", 0.1)
    (w.root / ".fable-team/comm/mailbox.jsonl").touch()
    w.env["FT_STALL_PENALTY_AUTO"] = "0"
    born(w)
    return w


def born(w, seat=None, minutes_ago=600.0):
    p = w.stub / "created"
    rows = dict(l.split() for l in p.read_text().splitlines()) if p.exists() else {}
    for s in w.live:
        rows.setdefault(s, str(int(NOW - 36000)))
    if seat:
        rows[seat] = str(int(float(w.env["FT_NOW"]) - minutes_ago * 60))
    p.write_text("".join(f"{k} {v}\n" for k, v in rows.items()))


def tick(w, minutes_ago, where="log", to=P, body="[완료] desk 틱 — HIL 대기 0건 · 쪽지 0건\n남은 일: 0\n회차: x", seq=500):
    ts = datetime.fromtimestamp(float(w.env["FT_NOW"]) - minutes_ago * 60).strftime("%Y-%m-%dT%H:%M:%S")
    name = "mailbox.log.jsonl" if where == "log" else "mailbox.jsonl"
    with open(w.root / ".fable-team/comm" / name, "a", encoding="utf-8") as f:
        f.write(json.dumps({"seq": seq, "ts": ts, "to": to, "from": D, "body": body}, ensure_ascii=False) + "\n")


def scan(w):
    r = subprocess.run(["bash", str(BIN / "ft-stall-scan.sh")], env=w.env, capture_output=True, text=True, timeout=60)
    assert r.returncode == 0, r.stderr[-400:]
    return r


def sends(w, to):
    return [l.split("|")[4] for l in w.mbox_log() if l.startswith(f"send|{to}|")]


def t_val(r):
    return counts(r.stdout).get("t")


def c1(tmp):  # ① 25분 전 심박(로그에만) → t 줄 · desk [멈춤] 1 · planner [긴급] 1 · 요약 끝 t=1
    w = world(tmp); tick(w, 25)
    r = scan(w)
    first = r.stdout.splitlines()[0]
    assert first.endswith(" t=1"), first
    assert any(l.startswith(f"t {D} 25 desk 틱 끊김") for l in r.stdout.splitlines()), r.stdout
    assert sends(w, D) == [f"[멈춤] {D} desk 틱 끊김 25분 — 지금 ft-desk-tick.sh 1회 돌리고 틱을 다시 걸어라 (ft-stall-scan)"], w.mbox_log()
    assert sends(w, P) == [f"[긴급] desk 틱 끊김 {D} 25분"], w.mbox_log()
    assert f"ring|{D}|" in w.mbox_log(), w.mbox_log()


def c2(tmp):  # ② 심박 읽기
    for where in ("queue", "log"):  # 5분 전 심박 = 0통
        w = world(f"{tmp}/{where}"); tick(w, 5, where)
        r = scan(w)
        assert t_val(r) == "0" and not w.mbox_log(), (where, r.stdout, w.mbox_log())
    w = world(f"{tmp}/other"); tick(w, 25); tick(w, 2, body="[완료] 다른 일 — 끝", seq=501)
    assert t_val(scan(w)) == "1" and len(sends(w, P)) == 1, w.mbox_log()
    w = world(f"{tmp}/to"); tick(w, 2, to="t1-master#1")
    assert t_val(scan(w)) == "1" and len(sends(w, P)) == 1, w.mbox_log()
    w = world(f"{tmp}/nodesk", desk=False)
    r = scan(w)
    assert r.stdout.splitlines()[0].endswith(" t=0") and not any(l.startswith("t ") for l in r.stdout.splitlines()) and not w.mbox_log(), r.stdout


def c3(tmp):  # ③ 구간당 1통
    w = world(tmp); tick(w, 25)
    for _ in range(3):
        scan(w); w.advance(601)
    assert len(sends(w, P)) == 1, w.mbox_log()
    assert len(sends(w, D)) == 3, w.mbox_log()
    tick(w, 0, seq=600); w.advance(25 * 60)
    scan(w)
    assert len(sends(w, P)) == 2, w.mbox_log()


def c4(tmp):  # ④ 조용한 경우 — 전팀 정지 / planner 정지 표식 / API 장애 / desk 시작 10분 전
    w = world(f"{tmp}/all"); tick(w, 25)
    (w.root / ".fable-team/state/ALL_STOP.json").write_text(json.dumps({"since": NOW - 600}))
    r = scan(w)
    assert not w.mbox_log() and "보류 t planner — 전팀 정지" in r.stdout and t_val(r) == "1", (r.stdout, w.mbox_log())
    w = world(f"{tmp}/pause"); tick(w, 25)
    pf = w.root / ".fable-team/state/planner-tick/PAUSED"
    pf.parent.mkdir(parents=True, exist_ok=True)
    pf.write_text("판정 1234 · 2026-11-16T01:00 · 시험용 정지 표식 사유", encoding="utf-8")
    r = scan(w)
    assert not sends(w, D) and not sends(w, P) and "(정지 중 처리 0)" in r.stdout, (r.stdout, w.mbox_log())
    w = world(f"{tmp}/api"); tick(w, 25)
    o = w.root / ".fable-team/state/api-outage/seats-planner.json"
    o.parent.mkdir(parents=True)
    o.write_text(json.dumps({"status": "OUTAGE", "since": NOW - 300}))
    os.utime(o, (NOW, NOW))
    r = scan(w)
    assert not w.mbox_log() and "t 1" in r.stdout and t_val(r) == "0", (r.stdout, w.mbox_log())
    w = world(f"{tmp}/young"); born(w, D, 10)
    r = scan(w)
    assert not w.mbox_log() and t_val(r) == "0", (r.stdout, w.mbox_log())


def c5(tmp):  # ⑤ 판정 불가 — 깨진 줄 / 우편함 폴더 없음 → 발신 0 · u +1 · 노트
    w = world(f"{tmp}/base"); tick(w, 5)
    u0 = int(counts(scan(w).stdout)["u"])
    w = world(f"{tmp}/broken"); tick(w, 5)
    with open(w.root / ".fable-team/comm/mailbox.log.jsonl", "a") as f:
        f.write("{깨진 줄\n")
    r = scan(w)
    assert not w.mbox_log() and int(counts(r.stdout)["u"]) == u0 + 1 and "desk 심박 판정 불가" in r.stdout, (u0, r.stdout)
    w = world(f"{tmp}/nodir")
    w.env["FT_MBOX_DIR"] = str(w.root / "no-comm")
    r = scan(w)
    assert not w.mbox_log() and int(counts(r.stdout)["u"]) == u0 + 1 and "desk 심박 판정 불가" in r.stdout, (u0, r.stdout)


bad = 0
for name in sys.argv[4:] or ["c1", "c2", "c3", "c4", "c5"]:
    try:
        globals()[name](f"{sys.argv[3]}/{name}")
        print(f"PASS {name}")
    except AssertionError as e:
        bad += 1
        print(f"FAIL {name} {str(e)[:600]}")
sys.exit(1 if bad else 0)
PY
cases() { local b="$1"; shift; local d; d="$(mktemp -d "$T/run.XXXXXX")"; python3 "$T/cases.py" "$SC" "$b" "$d" "$@"; }
BIN="${R2080_BIN:-$KIT}"
s0=$SECONDS
if [ $# -gt 0 ]; then cases "$BIN" "$@"; exit $?; fi
for c in c1 c2 c3 c4 c5; do out="$(cases "$BIN" "$c")"; r=$?; [ "$r" = 0 ] || printf '%s\n' "$out"; ck "사례 $c" "$r"; done
echo "단계 사례 $((SECONDS-s0))초"; s0=$SECONDS
[ "$BIN" = "$KIT" ] || { echo "FAIL=$fail"; [ "$fail" = 0 ]; exit $?; }

cp -Rp "$KIT" "$T/bin"
mutate() {  # $1 이름 $2 파일 $3 원문 $4 바꿀 글 $5 사례 — 사본 FAIL ∧ 원본 PASS
  cp -p "$KIT/$2" "$T/bin/$2"
  python3 - "$T/bin/$2" "$3" "$4" <<'PY' || { echo "FAIL 변이 $1 — 자리 못 찾음"; fail=$((fail+1)); return; }
import sys
p, a, b = sys.argv[1:]
s = open(p, encoding="utf-8").read()
assert s.count(a) == 1, s.count(a)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
  cases "$T/bin" "$5" >/dev/null; [ $? -ne 0 ]; ck "변이 $1 → $5 FAIL" $?
  cases "$KIT" "$5" >/dev/null; ck "변이 $1 대조 원본 $5 PASS" $?
  cp -p "$KIT/$2" "$T/bin/$2"
}
mutate "M1 role=desk 고르기 지움" ft_stall_detect.py 'isinstance(v, dict) and v.get("role") == "desk"' 'isinstance(v, dict) and v.get("role") == "desk-off"' c1
mutate "M2 머리 대조 지움" ft_stall_detect.py '    return isinstance(body, str) and body.lstrip().startswith(DESK_TICK_HEAD)' '    return isinstance(body, str)' c2
mutate "M3 구간 기록 지움" ft_stall_scan.py '            if s in sent and (hb is None' '            if False and (hb is None' c3
mutate "M4 시작 유예 지움" ft_stall_scan.py '            if self.now - born.get(s, 0) < thr * 60:' '            if False:' c4
echo "단계 변이 $((SECONDS-s0))초"

for n in ft_stall_scan.py ft_stall_detect.py; do cmp -s "$TRK/$n" "$KIT/$n"; ck "짝 사본 $n" $?; done
echo "FAIL=$fail"; [ "$fail" = 0 ]
