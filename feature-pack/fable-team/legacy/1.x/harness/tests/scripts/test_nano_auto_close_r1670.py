"""r1670 ⓔ — ft_stall_scan.py 의 auto_close(): FT_NANO_AUTO_CLOSE=1 일 때만 close-due 의 «갈래=승인» 줄마다 닫기를 1회 부른다.

T1 켜짐 → 「갈래=승인」 줄 2개 = 닫기 2회(꺼짐 줄·착지 갈래 줄은 세지 않는다) · 성공 줄은 CLOSED 표기 + 상태 파일 비움
T2 같은 좌석 실패는 «같은 HEAD 동안» 재시도 0 — 두 번째 회차 호출 0, HEAD 가 바뀌면 다시 1회
T3 꺼짐(기본 0) = 호출 0 · 출력 0줄(지금 그대로) — close-due 자체도 안 부른다
T4 close-due 실패(rc≠0) = «판정 불가 … 닫기 0» 1줄 · close 호출 0
T5 회차 상한 = 줄 수(줄 3개면 3회 · 4회 이상 0)
M2 변이(«FT_NANO_AUTO_CLOSE=1 확인» 삭제) → T3 FAIL

격리: close-due·close 는 이 파일이 만든 스텁 스크립트(호출을 파일에 적는다) — 실 도구·실 좌석·네트워크 0 · sleep 0.
"""
from __future__ import annotations

import json
import os
import stat
import sys
import time
from pathlib import Path

import pytest

BIN = Path(os.environ.get("R1670_BIN") or Path(__file__).resolve().parents[2] / "kit/fable-team/bin")


def _import_scan(bin_dir: Path):
    if str(bin_dir) not in sys.path:
        sys.path.insert(0, str(bin_dir))
    sys.modules.pop("ft_stall_scan", None)
    import ft_stall_scan as m  # noqa: PLC0415 — 사본 bin 을 그때그때 import 한다(변이 시험)

    return m


def _stub(path: Path, body: str) -> Path:
    path.write_text("#!/usr/bin/env bash\n" + body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)
    return path


def _scan(m, tmp: Path):
    o = object.__new__(m.Scan)  # 자동 배정·명부 조회 없이 auto_close() 만 본다(단위)
    o.root = tmp
    o.state_dir = tmp / "state"
    o.state_dir.mkdir(parents=True, exist_ok=True)
    o.now = time.time()
    return o


def _due(tmp: Path, lines: list[str], rc: int = 0) -> Path:
    body = "".join(f"printf '%s\\n' \"{ln}\"\n" for ln in lines) + f"exit {rc}\n"
    return _stub(tmp / "due.sh", body)


def _close(tmp: Path, rc: int = 0, first: str = "CLOSED ok#0 approved=1 set=S1") -> Path:
    return _stub(
        tmp / "close.sh",
        'printf "%s\\n" "$*" >> "$STUB_CALLS"\n'
        + f'printf "%s\\n" "{first}"\n'
        + f"exit {rc}\n",
    )


def _lines(seat: str, head: str) -> list[str]:
    return [
        f"닫기 차례 {seat} 팀=harness 갈래=승인 set={head} main=abc123456 — bash ft-nano-close.sh {seat} --approved /tmp/da.md --result /tmp/r.md --recv 7",
        f"닫기 차례 {seat}b 팀=harness 갈래=승인 set={head} main=abc123456 — bash ft-nano-close.sh {seat}b --approved /tmp/da.md --result /tmp/r.md --recv 7",
        f"닫기 차례 {seat}c 팀=harness 가지=nano/x landed=ff main=abc123456 — bash ft-nano-close.sh {seat}c --landed-pr - --result <산출> --recv <seq>",
    ]


@pytest.fixture()
def env(tmp_path, monkeypatch):
    calls = tmp_path / "calls.txt"
    monkeypatch.setenv("STUB_CALLS", str(calls))
    monkeypatch.setenv("FT_NANO_CLOSE_DUE", str(_due(tmp_path, _lines("byz-h-x#0", "S1"))))
    monkeypatch.setenv("FT_NANO_CLOSE", str(_close(tmp_path)))
    return tmp_path, calls


def test_t1_two_approval_lines_two_calls(env, monkeypatch):
    tmp, calls = env
    monkeypatch.setenv("FT_NANO_AUTO_CLOSE", "1")
    m = _import_scan(BIN)
    out = _scan(m, tmp).auto_close()
    assert calls.read_text().count("--approved") == 2, calls.read_text()   # 착지 갈래 줄은 안 부른다
    assert sum(1 for ln in out if "auto-close CLOSED" in ln) == 2, out
    assert json.loads((tmp / "state" / "nano-auto-close.json").read_text()) == {}


def test_t2_same_head_failure_no_retry(env, monkeypatch):
    tmp, calls = env
    monkeypatch.setenv("FT_NANO_AUTO_CLOSE", "1")
    monkeypatch.setenv("FT_NANO_CLOSE", str(_close(tmp, rc=1, first="REJECT ok#0")))
    m = _import_scan(BIN)
    o = _scan(m, tmp)
    out = o.auto_close()
    assert calls.read_text().count("--approved") == 2, calls.read_text()
    assert sum(1 for ln in out if "auto-close 실패" in ln) == 2, out
    assert set(json.loads((tmp / "state" / "nano-auto-close.json").read_text())) == {"byz-h-x#0", "byz-h-x#0b"}, "같은 HEAD 는 시도 기록"
    calls.write_text("")
    assert o.auto_close() == [], "같은 HEAD 재시도 0 · 출력 0"
    assert calls.read_text() == "", "같은 HEAD 는 close 를 다시 안 부른다"
    monkeypatch.setenv("FT_NANO_CLOSE_DUE", str(_due(tmp, _lines("byz-h-x#0", "S2"))))   # HEAD 가 바뀌면 다시 1회
    monkeypatch.setenv("FT_NANO_CLOSE", str(_close(tmp)))
    out = _scan(m, tmp).auto_close()
    assert calls.read_text().count("--approved") == 2, calls.read_text()
    assert sum(1 for ln in out if "auto-close CLOSED" in ln) == 2, out


def test_t3_off_is_noop(env, monkeypatch):
    tmp, calls = env
    monkeypatch.delenv("FT_NANO_AUTO_CLOSE", raising=False)
    m = _import_scan(BIN)
    assert _scan(m, tmp).auto_close() == [], "꺼짐 = 출력 0줄(지금 그대로)"
    assert not calls.exists(), "꺼짐 = close 호출 0"
    assert not (tmp / "state" / "nano-auto-close.json").exists(), "꺼짐 = 상태 파일 0"


def test_t4_due_failure_is_unknown_line(env, monkeypatch):
    tmp, calls = env
    monkeypatch.setenv("FT_NANO_AUTO_CLOSE", "1")
    monkeypatch.setenv("FT_NANO_CLOSE_DUE", str(_due(tmp, [], rc=3)))
    m = _import_scan(BIN)
    out = _scan(m, tmp).auto_close()
    assert len(out) == 1 and out[0].startswith("판정 불가 auto-close close-due rc=3"), out
    assert not calls.exists(), "close-due 가 못 냈으면 close 호출 0(하드 룰 20)"


def test_t5_cap_is_line_count(env, monkeypatch):
    tmp, calls = env
    monkeypatch.setenv("FT_NANO_AUTO_CLOSE", "1")
    assert _scan(_import_scan(BIN), tmp).auto_close() and calls.read_text().count("--approved") == 2


def test_m2_mutation_off_check_removed_fails_t3(tmp_path, monkeypatch):
    """M2 — «FT_NANO_AUTO_CLOSE=1 확인» 삭제 → 꺼짐에서도 close 를 부른다(T3 계약 위반 = 변이 검출)."""
    mut = tmp_path / "mut"
    mut.mkdir()
    src = (BIN / "ft_stall_scan.py").read_text(encoding="utf-8")
    old = '        if os.environ.get("FT_NANO_AUTO_CLOSE") != "1":\n            return []\n'
    assert old in src, "M2 앵커 없음"
    for name in ("ft_stall_scan.py", "ft_stall_detect.py", "ft_stall_seats.py", "ft_stall_state.py", "ft_stall_headline.py",
                 "ft_headline_seats.py", "ft_penalty.py", "ft_card_assign_pause.py"):
        (mut / name).write_text((BIN / name).read_text(encoding="utf-8"), encoding="utf-8")
    (mut / "ft_stall_scan.py").write_text(src.replace(old, "", 1), encoding="utf-8")
    calls = tmp_path / "calls.txt"
    monkeypatch.setenv("STUB_CALLS", str(calls))
    monkeypatch.setenv("FT_NANO_CLOSE_DUE", str(_due(tmp_path, _lines("byz-h-x#0", "S1"))))
    monkeypatch.setenv("FT_NANO_CLOSE", str(_close(tmp_path)))
    monkeypatch.delenv("FT_NANO_AUTO_CLOSE", raising=False)
    sys.path.insert(0, str(mut))
    sys.modules.pop("ft_stall_scan", None)
    m = _import_scan(mut)
    out = _scan(m, tmp_path).auto_close()
    assert calls.exists() and "--approved" in calls.read_text(), "변이면 꺼짐에도 부른다(T3 가 잡는다)"
    assert out, "변이면 꺼짐에도 출력이 있다"
