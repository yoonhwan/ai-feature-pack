"""r2146 — peek 의 pending 수 = recv(claim)가 limit 없이 가져갈 쪽지 수(K1 · K2 · K3).

peek 가 역할 키만 보고 세면, recv 가 명부 사슬(_mine)로 거르는 옛 계보 쪽지가 미읽음으로 영구히 남는다.
임시 우편함(FT_MBOX_DIR) + 임시 명부(seats-t.json) + 합성 쪽지 행만 쓴다 · 실 우편함·실 명부 0.
"""
import json
import os
import subprocess
import sys
from pathlib import Path

MBOX = Path(__file__).resolve().parents[3] / "harness" / "comm" / "mbox.py"
ME, P19, C18 = "byz-t-arch-pi#20", "byz-t-arch-pi#19", "byz-t-arch-claude#18"
P8, C5, PEER = "byz-t-arch-pi#8", "byz-t-arch-claude#5", "byz-t-master-claude#1"


def _run(box: Path, *args: str):
    env = {**os.environ, "FT_MBOX_DIR": str(box), "FT_MBOX_RELAY_DIR": str(box / "relay"),
           "FT_SEATS_JSON": str(box / "seats.json")}
    return subprocess.run([sys.executable, str(MBOX), *args], env=env, capture_output=True, text=True, timeout=30)


def _roster(box: Path):   # 계보 claude#18 → pi#19 → pi#20(me) · pi#8 = 철회 후계(stop-ready · _replaces [#7])
    (box / "seats-t.json").write_text(json.dumps({
        C18: {"role": "arch", "_replaced_by": P19},
        P19: {"role": "arch", "_replaced_by": ME, "_replaces": [C18]},
        ME: {"role": "arch", "_replaces": [P19]},
        P8: {"role": "stop-ready", "_replaces": ["byz-t-arch-pi#7"]},
    }), encoding="utf-8")


def _queue(box: Path, rows):   # 합성 쪽지 행 [(seq, to, from)]
    with open(box / "mailbox.jsonl", "w", encoding="utf-8") as f:
        for seq, to, frm in rows:
            f.write(json.dumps({"seq": seq, "ts": "2026-11-17T00:00:00", "to": to, "from": frm,
                                "body": "[발주] 합성 %d" % seq}, ensure_ascii=False) + "\n")


def _left(box: Path):
    return sorted(json.loads(x)["seq"] for x in (box / "mailbox.jsonl").read_text(encoding="utf-8").splitlines() if x.strip())


def _pending(box: Path):
    p = _run(box, "peek", ME)
    assert p.returncode == 0, p.stdout + p.stderr
    return p.stdout.split()[0]


def test_r1_withdrawn_successor_not_counted(tmp_path: Path):   # ① K1
    _roster(tmp_path)
    _queue(tmp_path, [(1, P8, PEER)])
    assert _pending(tmp_path) == "pending=0"
    assert "READ none" in _run(tmp_path, "recv", ME).stdout
    assert _left(tmp_path) == [1]


def test_r2_other_engine_old_number_not_counted(tmp_path: Path):   # ② K1 · claude#5 = role_key 계보 안 · 이름 계보 밖
    _roster(tmp_path)
    _queue(tmp_path, [(1, C5, PEER)])
    assert _pending(tmp_path) == "pending=0"
    assert "READ none" in _run(tmp_path, "recv", ME).stdout
    assert _left(tmp_path) == [1]


def test_r3_self_sent_not_counted(tmp_path: Path):   # ③ K1 · r1153 그대로
    _roster(tmp_path)
    _queue(tmp_path, [(1, P19, ME)])
    assert _pending(tmp_path) == "pending=0"
    assert "READ none" in _run(tmp_path, "recv", ME).stdout


def test_r4_rows_equal_recv_set(tmp_path: Path):   # ④ K1 · K2
    _roster(tmp_path)
    _queue(tmp_path, [(1, P19, PEER), (2, ME, PEER), (3, P8, PEER), (4, C5, PEER)])
    rows = _run(tmp_path, "peek", ME, "--rows")
    assert rows.returncode == 0, rows.stderr
    lines = rows.stdout.splitlines()
    assert lines[0].startswith(f"pending=2 latest_seq=2 from={PEER} scanned=1 lineage="), lines[0]
    shown = sorted(json.loads(x)["seq"] for x in lines[1:])
    assert shown == [1, 2], rows.stdout
    recv = _run(tmp_path, "recv", ME)
    assert recv.returncode == 0, recv.stderr
    assert _left(tmp_path) == [3, 4], recv.stdout   # recv 가 가져간 seq = {1, 2} = --rows 집합


def test_r5_roster_unreadable_role_key_only(tmp_path: Path):   # ⑤ K3 · 명부 없음 = 역할 키(pi)만
    _queue(tmp_path, [(1, P8, PEER), (2, C5, PEER)])
    assert _pending(tmp_path) == "pending=1"
    recv = _run(tmp_path, "recv", ME)
    assert recv.returncode == 0, recv.stderr
    assert _left(tmp_path) == [2], recv.stdout
