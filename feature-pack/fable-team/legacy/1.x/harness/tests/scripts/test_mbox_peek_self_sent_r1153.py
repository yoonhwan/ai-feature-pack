"""r1153 — peek 이 recv 와 같은 규칙으로 «내가 보낸 행(from == me)» 을 빼고 센다.

승계 때 후계(X#2)가 구 좌석(X#1)에 보낸 [레디] 는 역할 키가 같아 후계 몫으로 잡힌다.
recv 는 자기 발신을 안 가져가므로 peek 이 그것을 세면 지울 수 없는 미읽음 1 이 영구히 남는다.
가짜 쪽지함 폴더(FT_MBOX_DIR) + 가짜 명부(FT_SEATS_JSON) 만 쓴다 · 실 우편함 0 · 자기 재호출 0.
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

MBOX = Path(__file__).resolve().parents[3] / "harness" / "comm" / "mbox.py"
OLD, NEW, PEER = "byz-t-arch-claude#1", "byz-t-arch-claude#2", "byz-t-master-claude#1"


def _run(box: Path, *args: str):
    env = {**os.environ, "FT_MBOX_DIR": str(box), "FT_MBOX_RELAY_DIR": str(box / "relay"),
           "FT_SEATS_JSON": str(box / "seats.json")}
    return subprocess.run([sys.executable, str(MBOX), *args], env=env, capture_output=True, text=True, timeout=30)


def _roster(box: Path, replaced: bool):
    old = {"role": "arch", "_replaced_by": NEW} if replaced else {"role": "arch"}
    (box / "seats.json").write_text(json.dumps({OLD: old, NEW: {"role": "arch"}}), encoding="utf-8")


def _send(box: Path, to: str, frm: str, body: str):
    r = _run(box, "send", to, frm, body)
    assert r.returncode == 0, r.stdout + r.stderr


def test_r1_successor_ready_to_retired_seat_not_counted(tmp_path: Path):
    _roster(tmp_path, replaced=False)
    _send(tmp_path, OLD, NEW, "[레디] 받음")
    _roster(tmp_path, replaced=True)   # 구 좌석이 읽기 전에 retire
    peek = _run(tmp_path, "peek", NEW)
    assert peek.returncode == 0, peek.stderr
    assert peek.stdout.startswith("pending=0 "), peek.stdout
    assert "READ none" in _run(tmp_path, "recv", NEW).stdout


def test_r2_predecessor_handover_still_counted_and_read(tmp_path: Path):
    _roster(tmp_path, replaced=True)
    _send(tmp_path, NEW, OLD, "[인계] 마지막 작업 목록")
    peek = _run(tmp_path, "peek", NEW)
    assert re.match(rf"pending=1 latest_seq=\d+ from={re.escape(OLD)} ", peek.stdout), peek.stdout
    assert f"READ [{OLD}->{NEW}] #" in _run(tmp_path, "recv", NEW).stdout


def test_r3_live_predecessor_reads_ready(tmp_path: Path):
    _roster(tmp_path, replaced=False)
    _send(tmp_path, OLD, NEW, "[레디] 받음")
    peek = _run(tmp_path, "peek", OLD)
    assert re.match(rf"pending=1 latest_seq=\d+ from={re.escape(NEW)} ", peek.stdout), peek.stdout
    assert f"READ [{NEW}->{OLD}] #" in _run(tmp_path, "recv", OLD).stdout


def test_r4_rows_one_line_per_pending_including_lineage(tmp_path: Path):
    """r4(카드 ft2-done-seat-short-idle A4) — `peek --rows` = 머리줄 꼴 그대로 + 미읽음마다 JSON 1줄.

    집합 = pending 을 세는 그 목록(계보 옛 이름 앞 쪽지 포함 · from == me 는 셈 밖) · 줄 수 = pending · 읽기만(mark·recv 0).
    `--rows` 없으면 지금과 같은 한 줄이다(출력 바이트 같음).
    """
    _roster(tmp_path, replaced=True)
    _send(tmp_path, OLD, PEER, "[발주] 옛 이름 앞으로 온 쪽지")   # to = 은퇴한 옛 이름 → 계보로 현역 몫
    _send(tmp_path, NEW, NEW, "[발주] 내가 보낸 쪽지")             # from == me = 셈 밖(r1153)
    _send(tmp_path, NEW, OLD, "[마감 #1] 할 일 0")
    plain = _run(tmp_path, "peek", NEW)
    rows = _run(tmp_path, "peek", NEW, "--rows")
    assert plain.returncode == rows.returncode == 0, plain.stdout + plain.stderr + rows.stderr
    head = plain.stdout.strip()
    assert head.startswith("pending=2 ") and len(plain.stdout.strip().splitlines()) == 1, plain.stdout
    assert rows.stdout.splitlines()[0] == head, rows.stdout   # 머리줄 꼴 그대로
    docs = [json.loads(x) for x in rows.stdout.splitlines()[1:]]
    assert len(docs) == 2, rows.stdout
    assert sorted((d["to"], d["from"]) for d in docs) == sorted([(OLD, PEER), (NEW, OLD)]), docs
    assert all(d["body"] and d["seq"] and d["ts"] for d in docs)
    assert _run(tmp_path, "peek", NEW).stdout == plain.stdout   # 여러 번 읽어도 같다(mark 0)
