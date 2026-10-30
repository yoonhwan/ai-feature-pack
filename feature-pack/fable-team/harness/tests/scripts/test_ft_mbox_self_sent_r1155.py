"""r1155 — 라이브 bin ft-mbox.py recv·peek 이 comm mbox 와 같은 규칙으로 «내가 보낸 행(from == me)» 을 뺀다
· recv 가 가져간 쪽지마다 comm 과 같은 영수(receipts/<세션>.jsonl)를 남긴다.

승계 때 후계(X#2)가 구 좌석(X#1)에 보낸 [레디] 는 역할 키가 같아 후계 몫으로 잡힌다. bin 쪽 recv 가 그것을
«[X#2->X#2]» 로 읽고 지우면 구 좌석은 [레디] 를 못 받는다. 영수가 없으면 comm ready 가 «recv 안 함» 으로 거절한다.
가짜 쪽지함 폴더(FT_MBOX_DIR) + 가짜 명부(FT_SEATS_JSON) 만 쓴다 · 실 우편함 0 · 자기 재호출 0.
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

HARNESS = Path(__file__).resolve().parents[2]
FT_MBOX = HARNESS / "kit" / "fable-team" / "bin" / "ft-mbox.py"
COMM = HARNESS / "comm" / "mbox.py"
OLD, NEW = "byz-t-arch-claude#1", "byz-t-arch-claude#2"


def _run(box: Path, script: Path, *args: str):
    env = {**os.environ, "FT_MBOX_DIR": str(box), "FT_MBOX_RELAY_DIR": str(box / "relay"),
           "FT_SEATS_JSON": str(box / "seats.json")}
    return subprocess.run([sys.executable, str(script), *args], env=env, capture_output=True, text=True, timeout=30)


def _box(tmp: Path) -> Path:
    (tmp / "seats.json").write_text(json.dumps({OLD: {"role": "arch"}, NEW: {"role": "arch"}}), encoding="utf-8")
    return tmp


def _send(box: Path, to: str, frm: str, body: str) -> int:
    r = _run(box, FT_MBOX, "send", to, frm, body)
    assert r.returncode == 0, r.stdout + r.stderr
    return int(re.search(r"QUEUED seq=(\d+)", r.stdout).group(1))


def _queue(box: Path):
    p = box / "mailbox.jsonl"
    return [json.loads(l) for l in p.read_text(encoding="utf-8").splitlines() if l.strip()] if p.exists() else []


def test_r1_recv_skips_self_sent_ready(tmp_path: Path):
    box = _box(tmp_path)
    seq = _send(box, OLD, NEW, "[레디] 받음")
    r = _run(box, FT_MBOX, "recv", NEW)
    assert r.returncode == 0, r.stderr
    assert "READ none" in r.stdout and "READ [" not in r.stdout, r.stdout
    assert [x["seq"] for x in _queue(box)] == [seq]


def test_r2_peek_skips_self_sent_ready(tmp_path: Path):
    box = _box(tmp_path)
    _send(box, OLD, NEW, "[레디] 받음")
    r = _run(box, FT_MBOX, "peek", NEW)
    assert r.returncode == 0, r.stderr
    assert r.stdout.startswith("pending=0 "), r.stdout


def test_r3_successor_reads_handover_from_predecessor(tmp_path: Path):
    box = _box(tmp_path)
    seq = _send(box, NEW, OLD, "[인계] 마지막 작업 목록")
    assert re.match(rf"pending=1 latest_seq={seq} from={re.escape(OLD)} ", _run(box, FT_MBOX, "peek", NEW).stdout)
    assert f"READ [{OLD}->{NEW}] #{seq}" in _run(box, FT_MBOX, "recv", NEW).stdout


def test_r4_predecessor_reads_ready(tmp_path: Path):
    box = _box(tmp_path)
    seq = _send(box, OLD, NEW, "[레디] 받음")
    assert f"READ [{NEW}->{OLD}] #{seq}" in _run(box, FT_MBOX, "recv", OLD).stdout
    assert _queue(box) == []


def test_r5_recv_writes_receipt_and_comm_ready_passes(tmp_path: Path):
    box = _box(tmp_path)
    seq = _send(box, NEW, OLD, f"[인계] {OLD} -> {NEW} · 항목 0 · 끝")
    assert f"READ [{OLD}->{NEW}] #{seq}" in _run(box, FT_MBOX, "recv", NEW).stdout
    rows = [json.loads(l) for l in (box / "receipts" / f"{NEW}.jsonl").read_text(encoding="utf-8").splitlines()]
    assert [(x["seq"], x["from"]) for x in rows] == [(seq, OLD)], rows
    ready = _run(box, COMM, "ready-body", NEW, OLD)
    assert ready.returncode == 0 and "아직 recv 안 함" not in ready.stderr, ready.stdout + ready.stderr
    assert ready.stdout.startswith(f"[레디] {NEW} <- {OLD} · [인계] #{seq} 받음"), ready.stdout


def test_r5b_ready_receipt_auto_marked_done(tmp_path: Path):
    box = _box(tmp_path)
    seq = _send(box, OLD, NEW, "[레디] 받음")
    _run(box, FT_MBOX, "recv", OLD)
    rows = [json.loads(l) for l in (box / "receipts" / f"{OLD}.jsonl").read_text(encoding="utf-8").splitlines()]
    assert {"seq": seq, "mark": "처리함"}.items() <= rows[-1].items(), rows


def test_r6_receipt_write_failure_consumes_nothing(tmp_path: Path):
    box = _box(tmp_path)
    seq = _send(box, NEW, OLD, "[인계] 마지막 작업 목록")
    (box / "receipts").write_text("", encoding="utf-8")   # 영수 폴더 자리에 일반 파일 — makedirs 실패
    r = _run(box, FT_MBOX, "recv", NEW)
    assert r.returncode != 0, r.stdout
    assert "ERROR 영수 기록 실패" in r.stderr and "READ [" not in r.stdout, r.stdout + r.stderr
    assert [x["seq"] for x in _queue(box)] == [seq]
