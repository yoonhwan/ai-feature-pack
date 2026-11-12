"""r1735 — ft_stall_scan.py auto_close(): 성공 판정 = 출력 «첫 줄» 이 아니라 «CLOSED 로 시작하는 줄이 있나».

① INFO + CLOSED · rc0 → 성공 줄 · tried 비움 (기준판 = 실패 줄 = Red)
② CLOSED 한 줄 · rc0 → 성공   ③ INFO + REJECT + «  - ⑥…» · rc1 → 실패 사유 = «REJECT …» · tried[seat]=head
④ INFO 만 · rc0 → 실패 사유 = 첫 줄   ⑤ INFO + CLOSED · rc1 → 실패(A3 rc 우선)   ⑥ 판정 불가 줄(rc3) = 지금과 같은 꼴
M1 첫 줄 판정 복귀 → ① FAIL · M2 rc 검사 삭제 → ⑤ FAIL · M3 INFO 건너뛰기 삭제 → ③ FAIL (변이마다 원본 대조 1회)
격리: close-due·close 는 스텁 · 실 좌석 0 · sleep 0 · o.now=0(stamp 고정 — ⑥ 바이트 대조) · 70초 안.
"""
from __future__ import annotations

import json
import os
import shutil
import stat
import sys
import time
from pathlib import Path

import pytest

BIN = Path(os.environ.get("R1735_BIN") or Path(__file__).resolve().parents[2] / "kit/fable-team/bin")
STAMP = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(0))
SEAT, S1, INFO = "byz-h-x#0", "S1", "INFO 카드 위치 ← /x"
CLOSED = f"CLOSED {SEAT} approved=1 set={S1}"


def _import_scan(bin_dir: Path):
    if str(bin_dir) not in sys.path:
        sys.path.insert(0, str(bin_dir))
    sys.modules.pop("ft_stall_scan", None)
    import ft_stall_scan as m  # noqa: PLC0415 — 사본 bin 을 그때그때 import(변이 시험)

    return m


def _stub(path: Path, body: str) -> Path:
    path.write_text("#!/usr/bin/env bash\n" + body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)
    return path


def _run(bin_dir: Path, tmp: Path, monkeypatch, rows: list[str], rc: int = 0, due_rc: int = 0, owed: bool = True):
    tmp.mkdir(parents=True, exist_ok=True)
    calls = tmp / "calls.txt"
    due = [f"닫기 차례 {SEAT} 팀=harness 갈래=승인 set={S1} main=abc123456 — bash ft-nano-close.sh {SEAT} --approved /tmp/da.md --result /tmp/r.md --recv 7"] if owed else []
    if due_rc == 3:
        due.insert(0, "판정 불가 B ft-seat-status turn rc=1")
    monkeypatch.setenv("STUB_CALLS", str(calls))
    monkeypatch.setenv("FT_NANO_AUTO_CLOSE", "1")
    monkeypatch.setenv("FT_NANO_CLOSE_DUE", str(_stub(tmp / "due.sh", "".join(f"printf '%s\\n' \"{ln}\"\n" for ln in due) + f"exit {due_rc}\n")))
    body = 'printf "%s\\n" "$*" >> "$STUB_CALLS"\n' + "".join(f'printf "%s\\n" "{r}"\n' for r in rows) + f"exit {rc}\n"
    monkeypatch.setenv("FT_NANO_CLOSE", str(_stub(tmp / "close.sh", body)))
    o = object.__new__(_import_scan(bin_dir).Scan)  # 자동 배정·명부 조회 없이 auto_close() 만(단위)
    o.root, o.state_dir, o.now = tmp, tmp / "state", 0
    o.state_dir.mkdir(parents=True, exist_ok=True)
    out = o.auto_close()
    sf = o.state_dir / "nano-auto-close.json"
    return out, (json.loads(sf.read_text()) if sf.exists() else {}), calls


def _mutant(root: Path, anchor: str, repl: str) -> Path:
    shutil.copytree(BIN, root, dirs_exist_ok=True)   # 사본 bin 전체(import 연쇄 그대로 나야 «변이만» 다르다)
    src = (BIN / "ft_stall_scan.py").read_text(encoding="utf-8")
    assert anchor in src, f"변이 앵커 없음: {anchor[:60]}"
    (root / "ft_stall_scan.py").write_text(src.replace(anchor, repl, 1), encoding="utf-8")
    return root


def test_a1_info_before_closed_is_success(tmp_path, monkeypatch):
    out, tried, calls = _run(BIN, tmp_path, monkeypatch, [INFO, CLOSED])
    assert out == [f"{STAMP} auto-close {CLOSED} set={S1}"], out   # 기준판(첫 줄 판정) = 실패 줄 = Red
    assert tried == {}, "성공은 tried 에서 지운다"
    assert "--approved" in calls.read_text()


def test_a1b_closed_only_is_success(tmp_path, monkeypatch):
    out, tried, _ = _run(BIN, tmp_path, monkeypatch, [CLOSED])
    assert out == [f"{STAMP} auto-close {CLOSED} set={S1}"], out


def test_a2_reason_skips_info(tmp_path, monkeypatch):
    out, tried, _ = _run(BIN, tmp_path, monkeypatch, [INFO, f"REJECT {SEAT}", "  - ⑥ 근거 없음"], rc=1)
    assert out == [f"{STAMP} auto-close 실패 {SEAT} rc=1 — REJECT {SEAT}"], out
    assert tried == {SEAT: S1}, "실패는 같은 HEAD 시도 기록"


def test_a2b_only_info_reason_is_first_line(tmp_path, monkeypatch):
    out, tried, _ = _run(BIN, tmp_path, monkeypatch, [INFO])
    assert out == [f"{STAMP} auto-close 실패 {SEAT} rc=0 — {INFO}"], out
    assert tried == {SEAT: S1}


def test_a3_rc_wins_over_closed_line(tmp_path, monkeypatch):
    out, tried, _ = _run(BIN, tmp_path, monkeypatch, [INFO, CLOSED], rc=1)
    assert len(out) == 1 and out[0].startswith(f"{STAMP} auto-close 실패 {SEAT} rc=1 — "), out
    assert "auto-close CLOSED" not in out[0], "rc≠0 은 성공 줄 0(A3)"
    assert tried == {SEAT: S1}


def test_a4_unknown_line_bytes_unchanged(tmp_path, monkeypatch):
    out, tried, calls = _run(BIN, tmp_path, monkeypatch, [], due_rc=3, owed=False)
    assert out == [f"{STAMP} 판정 불가 auto-close B ft-seat-status turn rc=1"], out
    assert not calls.exists(), "닫기 차례 줄이 없으면 close 호출 0"
    assert tried == {}


MUT = {
    # 변이 이름: (원본 앵커, 변이 치환, 사례, 기대 = «원본에서 통과해야 하는 것»)
    "M1 첫 줄 판정 복귀": (
        '            closed = next((x for x in rows if x.startswith("CLOSED")), "")',
        '            first = (rows or [""])[0]\n            closed = first if first.startswith("CLOSED") else ""',
        dict(rows=[INFO, CLOSED]), "auto-close CLOSED"),
    "M2 rc 검사 지움": ("if crc == 0 and closed:", "if closed:", dict(rows=[INFO, CLOSED], rc=1), "auto-close 실패"),
    "M3 INFO 건너뛰기 지움": (
        'why = next((x for x in rows if not x.startswith("INFO")), (rows or [""])[0])[:120]',
        'why = (rows or [""])[0][:120]', dict(rows=[INFO, f"REJECT {SEAT}"], rc=1), f"— REJECT {SEAT}"),
}


@pytest.mark.parametrize("mid", list(MUT))
def test_mutations(mid, tmp_path, monkeypatch):
    anchor, repl, case, want = MUT[mid]
    good, _, _ = _run(BIN, tmp_path / "orig", monkeypatch, **case)     # 원본 대조 — 같은 사례는 통과
    assert good and want in good[0], f"원본 대조 실패 {mid}: {good}"
    bad, _, _ = _run(_mutant(tmp_path / "mut", anchor, repl), tmp_path / "mutrun", monkeypatch, **case)
    assert not (bad and want in bad[0]), f"{mid} 변이인데 통과 = 검출 실패 {bad}"
