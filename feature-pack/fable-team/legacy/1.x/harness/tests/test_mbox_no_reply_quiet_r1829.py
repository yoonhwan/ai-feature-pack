#!/usr/bin/env python3
"""r1829 — 회신 불요 쪽지 = quiet(깨움 0 · 예산 0) + 굶김 상한 sweep(30분 또는 8통).
격리: 임시 박스(comm 사본 · state · TMPDIR) · fakebin tmux(send-keys 기록) · fake ps · 가짜 시계 FT_MBOX_NOW · 실 우편함·pane 0 · sleep 0 · 반례 ①~⑤ + 다른 깨움·recv 뒤 0 · peek 실패 = 울림."""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

COMM = Path(__file__).resolve().parent.parent / "comm"
T = Path(tempfile.mkdtemp())
W0 = 1700002800
FAIL = []
EXE = {
    "fakebin/tmux": """#!/bin/bash
printf '%s\\n' "$*" >> "$TMUX_LOG"
case "$1" in list-panes) shift; if [ "$1" = -a ]; then i=0; for s in $TMUX_SEATS; do i=$((i+1)); printf '%s|%%%d\\n' "$s" "$i"; done
  else echo 900001; fi; exit 0;; display-message) echo node; exit 0;; send-keys) exit 0;; esac; exit 1
""",
    "fakebin/ps": "#!/bin/sh\nprintf '%s\\n' '900001 1 S /bin/zsh' '900002 900001 S /usr/bin/claude --dangerously-skip-permissions'\n",
    "failpeek.sh": "#!/bin/sh\nexit 1\n",
}

def ck(name, cond, info=""):
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else f" :: {info}"))
    if not cond:
        FAIL.append(name)

def setup():
    (T / "fakebin").mkdir()
    for rel, body in EXE.items():
        (T / rel).write_text(body)
        (T / rel).chmod(0o755)
    (T / "seats.json").write_text(json.dumps({s: {"agent": a, "team": "t1", "tick": None} for s, a in (("a#1", "claude"), ("s1#1", "claude"), ("pl#1", "pi"))}))
    (T / "seats-planner.json").write_text('{"_master":"pl#1"}')

class Box:
    def __init__(self, name):
        self.r = T / f"box-{name}"
        self.c, self.log = self.r / ".fable-team/comm", self.r / "tmux.log"
        for d in (self.c, self.r / ".fable-team/state", self.r / "tmp"):
            d.mkdir(parents=True)
        for p in [*COMM.glob("mbox*.sh"), *COMM.glob("mbox*.py"), COMM / "ft-agent-alive.sh"]:
            shutil.copy(p, self.c)
        self.log.write_text("")
        self.env = dict(os.environ, PATH=f"{T}/fakebin:{os.environ['PATH']}", FT_SEATS_JSON=str(T / "seats.json"),
                        FT_PS_CMD=str(T / "fakebin/ps"), TMUX_LOG=str(self.log), FT_BIN=str(T / "nobin"),
                        TMUX_SEATS="a#1 s1#1 pl#1", FT_MBOX_RATE_N="1000", FT_MBOX_RESEND_COOLDOWN="0",
                        FT_MBOX_RECV_LIMIT="50", FT_MBOX_DIR=str(self.c), TMPDIR=str(self.r / "tmp"),
                        FT_MBOX_STATE_DIR=str(self.r / ".fable-team/state"))
        self.env.pop("FT_MBOX_PEEK_CMD", None)
    def run(self, now, *args, **extra):
        env = dict(self.env, FT_MBOX_NOW=str(now), **extra)
        return subprocess.run(["bash", str(self.c / "mbox.sh"), *args], env=env, capture_output=True, text=True, timeout=60).stdout
    def send(self, now, body, frm="s1#1"):
        return self.run(now, "send", "a#1", frm, body)
    def inj(self):
        return self.log.read_text().count("recv a#1")
    def budget(self):
        d = self.r / ".fable-team/state/wake-budget"
        return sorted(p.name for p in d.iterdir() if p.name != "_ledger.log") if d.exists() else []

def gate(out):
    m = re.search(r"gate=(\w+)", out)
    return m.group(1) if m else ""

def main():
    setup()
    b = Box("b1")  # ① ①′ ①″ ⑤
    for h in ("[받음]", "[전파]", "[정보]", "[독려]", "[참고]"):
        o = b.send(W0, f"{h} r1829 시험")
        ck(f"①{h} gate=quiet", gate(o) == "quiet", o)
    o = b.send(W0, "r1829 결과 공유 · 회신 불요\n본문 둘째 줄")
    ck("①″ 첫 줄 회신 불요 → quiet", gate(o) == "quiet", o)
    ck("① pane 주입 0 · 큐 적재 6", b.inj() == 0 and "pending=6" in o, o)
    ck("⑤ quiet 예산 차감 0", b.budget() == [], b.budget())
    o = Box("b2").send(W0, "r1829 결과 공유\n둘째 줄에만 회신 불요")
    ck("①″ 둘째 줄에만 → sent", gate(o) == "sent", o)
    b3 = Box("b3")  # ② 묶음 + 다른 깨움 뒤 0
    [b3.send(W0 + i, body) for i, body in enumerate(("[받음] 하나", "[받음] 둘"))]
    o = b3.send(W0 + 2, "[발주] r1829 일")
    ck("② 발주 때 주입 1", b3.inj() == 1 and gate(o) == "sent", o)
    o = b3.run(W0 + 1900, "sweep")
    ck("② 다른 깨움 뒤 굶김 sweep 0", "followup" not in o and b3.inj() == 1, o)
    o = b3.run(W0 + 1900, "recv", "a#1")
    ck("② recv 1회 3통 모두", all(w in o for w in ("하나", "둘", "r1829 일")) and "PENDING-AFTER 0" in o, o)
    b4 = Box("b4")  # ③
    ck("③ [긴급] … 회신 불요 → sent", gate(b4.send(W0, "[긴급] 장애 · 회신 불요")) == "sent")
    ck("③ 사람 글 [받음] → sent", gate(b4.send(W0, "[받음] 사람", "pl#1")) == "sent")
    b5 = Box("b5")  # ④ ④′
    b5.send(W0, "[받음] 굶김 1통")
    o = b5.run(W0 + 1799, "sweep")
    ck("④′ 1799초 → 주입 0", b5.inj() == 0 and "followup" not in o, o)
    pre = b5.budget()
    o = b5.run(W0 + 1801, "sweep")
    ck("④ 1801초 → 주입 1", b5.inj() == 1 and "followup=a#1" in o, o)
    ck("④ 굶김 깨움만 예산 1회(quiet 0)", pre == [] and b5.budget() != [], (pre, b5.budget()))
    b5.run(W0 + 3700, "sweep")
    ck("④ 깨운 뒤 다시 울리지 않음", b5.inj() == 1)
    b6 = Box("b6")  # ④″
    outs = [b6.send(W0 + i, f"[정보] {i}") for i in range(8)]
    ck("④″ 7통까지 굶김 깨움 0", all("followup" not in o for o in outs[:7]), outs[:7])
    ck("④″ 8통째 주입 1", b6.inj() == 1 and "followup=a#1" in outs[7], outs[7])
    b7, b8 = Box("b7"), Box("b8")  # recv 로 큐가 빈 뒤 0 · peek 실패 = 지금 규칙(울림)
    for x in (b7, b8):
        x.send(W0, "[참고] 하나")
    b7.run(W0 + 5, "recv", "a#1")
    o = b7.run(W0 + 1801, "sweep")
    ck("B3 recv 로 빈 뒤 0", b7.inj() == 0 and "followup" not in o, o)
    o = b8.run(W0 + 10, "sweep", FT_MBOX_PEEK_CMD=str(T / "failpeek.sh"))
    ck("B3 peek 실패 = 울림", b8.inj() == 1, o)
    b9, t1 = Box("b9"), W0 + 1802  # fix1 R1 — 빈 recv 뒤 새 묶음 = 새 ts(sweep 없이 recv → 새 send)
    b9.send(W0, "[받음] old")
    o = b9.run(W0 + 1801, "recv", "a#1") + b9.send(t1, "[받음] new")
    ck("R1 recv 뒤 새 send pane 0", b9.inj() == 0 and "followup" not in o, o)
    o = b9.run(t1 + 1799, "sweep") + " | " + b9.run(t1 + 1801, "sweep")
    ck("R1 새 ts 1799초 0 · 1801초 1", b9.inj() == 1 and "followup" not in o.split(" | ")[0] and "followup=a#1" in o, o)
    shutil.rmtree(T, ignore_errors=True)
    print("---\n" + ("ALL PASS" if not FAIL else f"FAIL {len(FAIL)}"))
    return 1 if FAIL else 0

if __name__ == "__main__":
    sys.exit(main())
