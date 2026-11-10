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
OLD, NEW = "byz-t-arch-claude#1", "byz-t-arch-claude#2"


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
