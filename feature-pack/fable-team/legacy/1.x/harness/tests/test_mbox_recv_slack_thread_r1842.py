#!/usr/bin/env python3
"""r1842 — recv 1회 = Slack thread 1개 묶음 또는 일반 쪽지 묶음(Slack 0) · 남은 수 = WAIT 1줄(수만).
격리: comm 사본 + FT_MBOX_DIR 임시 우편함 · 행은 mailbox.jsonl 에 직접 · 실 우편함·Slack·명부 0 · sleep 0 · 반례 ①~⑦ ⑨~⑪."""
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

COMM = Path(__file__).resolve().parent.parent / "comm"
LISTEN = "ft2-slack-listen"


def slack(seq, root, cmd, tag, kind="새글"):
    return {"seq": seq, "ts": "2026-11-13T00:00:00", "to": "a#1", "from": LISTEN,
            "body": f"[Slack] {kind} · thread {root} · command {cmd}\n본문 {tag}"}


def plain(seq, tag, frm="s1#1"):
    return {"seq": seq, "ts": "2026-11-13T00:00:00", "to": "a#1", "from": frm, "body": f"일반 {tag}"}


def cmd(ch, ts="1800000001.000001"):
    return f"slack:WORKSPACE:{ch}:{ts}"


def A(seq, tag, **k):   # thread a
    return slack(seq, "1800000000.111111", cmd("C1"), tag, **k)


def B(seq, tag):   # thread b
    return slack(seq, "1800000000.222222", cmd("C1"), tag)


class Box:
    def __init__(self, tmp, rows, limit="5"):
        self.c = tmp / ".fable-team/comm"
        for d in (self.c, tmp / ".fable-team/state", tmp / "tmp"):
            d.mkdir(parents=True)
        for p in [*COMM.glob("mbox*.sh"), *COMM.glob("mbox*.py"), COMM / "ft-agent-alive.sh"]:
            shutil.copy(p, self.c)
        (self.c / "mailbox.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows))
        self.env = dict(os.environ, FT_MBOX_DIR=str(self.c), FT_SEATS_JSON=str(tmp / "seats.json"), FT_BIN=str(tmp / "nobin"),
                        FT_MBOX_RECV_LIMIT=limit, TMPDIR=str(tmp / "tmp"), FT_MBOX_STATE_DIR=str(tmp / ".fable-team/state"))

    def recv(self, *extra):
        p = subprocess.run(["bash", str(self.c / "mbox.sh"), "recv", "a#1", *extra], env=self.env,
                           capture_output=True, text=True, timeout=60)
        assert p.returncode == 0, p.stderr
        return p.stdout


def seqs(out):
    return sorted(int(s) for s in re.findall(r"^READ \[[^\]]*\] #(\d+)", out, re.M))


def wait(out):
    m = re.findall(r"^WAIT .*$", out, re.M)
    return m[0] if m else None


def pending(out):
    return int(re.search(r"^PENDING-AFTER (\d+)", out, re.M).group(1))


def test_1_two_threads_split(tmp_path):
    b = Box(tmp_path, [A(10, "AAA"), B(11, "BBB")])
    o = b.recv()
    assert seqs(o) == [10] and wait(o) == "WAIT thread 1 · 일반 0 — 이 묶음 답 뒤 recv 다시", o
    assert "BBB" not in o and "222222" not in o and "#11" not in o and pending(o) == 1, o
    o = b.recv()
    assert seqs(o) == [11] and wait(o) is None and pending(o) == 0, o


def test_2_same_thread_alert_together(tmp_path):
    b = Box(tmp_path, [A(10, "AAA"), B(11, "BBB"), A(12, "ALERT", kind="알림 깨움 실패")])
    assert seqs(o := b.recv()) == [10, 12] and "BBB" not in o, o
    assert seqs(b.recv()) == [11]


def test_3_plain_first_no_slack(tmp_path):
    b = Box(tmp_path, [plain(9, "P9", "master-a#1"), A(10, "AAA"), plain(13, "P13")])
    o = b.recv()
    assert seqs(o) == [9, 13] and "AAA" not in o and wait(o).startswith("WAIT thread 1 · 일반 0") and pending(o) == 1, o
    assert seqs(b.recv()) == [10]


def test_4_urgent_between_threads(tmp_path):
    b = Box(tmp_path, [A(10, "AAA"), plain(11, "[긴급] URG"), B(12, "BBB")])
    o = b.recv()
    assert seqs(o) == [10] and wait(o).startswith("WAIT thread 1 · 일반 1"), o
    assert [seqs(b.recv()), seqs(b.recv())] == [[11], [12]]


def test_5_limit_held_only_picked(tmp_path):
    b = Box(tmp_path, [A(10 + i, f"A{i}") for i in range(7)] + [B(20, "BBB")])
    o = b.recv()
    assert seqs(o) == [12, 13, 14, 15, 16] and "HELD 2 more" in o, o
    held = re.findall(r"^  · #(\d+)", o, re.M)
    assert held == ["11", "10"] and "BBB" not in o and "#20" not in o, o


def test_6_listen_without_head_is_plain(tmp_path):
    odd = dict(plain(10, "[Slack 아님] ODD · thread x · command slack:W:C:1"), **{"from": LISTEN})
    b = Box(tmp_path, [plain(9, "P9"), odd, A(11, "AAA")])
    assert seqs(o := b.recv()) == [9, 10] and "AAA" not in o, o


def test_7_no_slack_bytes_same(tmp_path):
    b = Box(tmp_path, [plain(9, "P9"), plain(10, "P10")])
    o = b.recv()
    mb = b.c / "mailbox.jsonl"
    assert o == (f"SCANNED 1 mailbox(es): {mb} lineage=0\nREAD [s1#1->a#1] #10 — 일반 P10\n"
                 f"READ [s1#1->a#1] #9 — 일반 P9\nPENDING-AFTER 0\n"), o
    b = Box(tmp_path / "all", [A(10 + i, f"A{i}") for i in range(7)] + [B(20, "BBB")])
    o = b.recv("--all")
    assert seqs(o) == list(range(10, 17)) and "BBB" not in o and "HELD" not in o and wait(o), o


def test_9_same_root_other_channel(tmp_path):
    r = "1800000000.123456"
    b = Box(tmp_path, [slack(10, r, cmd("A"), "CHA"), slack(11, r, cmd("B"), "CHB")])
    o = b.recv()
    assert seqs(o) == [10] and "CHB" not in o and wait(o).startswith("WAIT thread 1 · 일반 0"), o
    assert seqs(b.recv()) == [11]


def test_10_same_root_other_reply_ts(tmp_path):
    r = "1800000000.123456"
    b = Box(tmp_path, [slack(10, r, cmd("A"), "R1"), slack(12, r, cmd("A", "1800000002.000002"), "R2")])
    assert seqs(o := b.recv()) == [10, 12] and wait(o) is None, o


def test_11_unidentified_alone(tmp_path):
    b = Box(tmp_path, [plain(9, "P9"), slack(10, "1800000000.123456", "slack:WORKSPACE", "BAD"), A(11, "AAA")])
    assert [seqs(b.recv()), seqs(b.recv()), seqs(b.recv())] == [[9], [10], [11]]


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-q"]))
