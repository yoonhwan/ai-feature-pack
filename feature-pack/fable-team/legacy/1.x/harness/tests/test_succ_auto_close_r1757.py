"""r1757 — ft_stall_scan.py succ_close(): 승계 끝 옛 좌석(일곱 조건)을 회차마다 ft-seat-close 표준 경로로 닫는다.

① 일곱 조건 참 + 켜짐 → 닫기 스텁 인자 = 옛 좌석·--reason · 로그 succ-close rc=0
② attached 1 → 호출 0      ③ 후계 세션 없음 → 호출 0      ④ 재개 기록 없음 → 호출 0
⑤ 스텁 rc 3 → 로그 rc=3 · 다음 회차 호출 0 · FT_SUCC_RETRY_S 지난 뒤 1회
⑥ 후보 5석 → 이번 회차 호출 3
⑦ tmux 조회 실패 1석 + 정상 1석 → 판정 불가 1줄 + 호출 1
⑧ 꺼짐 → 호출 0 · «후보 … (꺼짐)» 1줄
격리: 임시 루트·임시 HOME · tmux·ft-seat-close = 이 파일이 만든 스텁 — 실 tmux·실 명부·실 kill 0 · sleep 0.
"""
from __future__ import annotations

import inspect
import json
import os
import stat
import sys
import time
from pathlib import Path

import pytest

BIN = Path(os.environ.get("R1757_BIN") or Path(__file__).resolve().parents[1] / "kit/fable-team/bin")

TMUX_STUB = """#!/usr/bin/env bash
# has-session -t =<s> · display-message -p -t =<s> '#{session_attached}' — 칸 파일(alive·att·fail)로 답한다
case "$1" in
  has-session) t="${3#=}" ;;
  display-message) t="${4#=}" ;;
  *) exit 0 ;;
esac
grep -qxF -- "$t" "$TM_DIR/fail" 2>/dev/null && exit 2
case "$t" in %*) cat "$TM_DIR/me"; exit 0 ;; esac   # TMUX_PANE → 자기 세션 이름
if [ "$1" = has-session ]; then grep -qxF -- "$t" "$TM_DIR/alive" 2>/dev/null; exit $?; fi
grep -qxF -- "$t" "$TM_DIR/att" 2>/dev/null && echo 1 || echo 0
"""

CLOSE_STUB = """#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$STUB_CALLS"
printf 'CLOSED-SESSION %s stub\\nsecond line\\n' "$1"
exit "${STUB_RC:-0}"
"""


def _import_scan(bin_dir: Path):
    if str(bin_dir) not in sys.path:
        sys.path.insert(0, str(bin_dir))
    for mod in ("ft_stall_scan", "ft_seat_succ_close"):
        sys.modules.pop(mod, None)
    import ft_stall_scan as m  # noqa: PLC0415 — 사본 bin 을 그때그때 import 한다(변이 시험)

    return m


def _stub(path: Path, body: str) -> Path:
    path.write_text(body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)
    return path


class World:
    def __init__(self, tmp: Path) -> None:
        self.tmp, self.root = tmp, tmp / "root"
        (self.root / ".fable-team").mkdir(parents=True)
        self.tm = tmp / "tm"
        self.tm.mkdir()
        self.resume = tmp / "home/.claude/state/seat-resume"
        self.resume.mkdir(parents=True)
        self.calls = tmp / "calls.txt"
        self.alive: list[str] = []
        self.att: list[str] = []
        self.fail: list[str] = []

    def pair(self, old: str, new: str, *, file: str = "seats-a.json", resume: bool = True, alive_new: bool = True, att: bool = False) -> None:
        p = self.root / ".fable-team" / file
        d = json.loads(p.read_text(encoding="utf-8")) if p.exists() else {"_master": new}
        d[old] = {"role": "stop-ready", "_replaced_by": new}
        d[new] = {"role": "master", "opened_at": "2026-11-12T10:00"}
        p.write_text(json.dumps(d), encoding="utf-8")
        if resume:
            (self.resume / f"{old}.json").write_text("{}", encoding="utf-8")
        self.alive.append(old)
        if alive_new:
            self.alive.append(new)
        if att:
            self.att.append(old)

    def scan(self, m):
        for k in ("alive", "att", "fail"):
            (self.tm / k).write_text("".join(x + "\n" for x in getattr(self, k)), encoding="utf-8")
        o = object.__new__(m.Scan)  # 명부·tmux 전체 조회 없이 succ_close() 만 본다(단위)
        o.root = self.root
        o.state_dir = self.tmp / "state"
        o.state_dir.mkdir(parents=True, exist_ok=True)
        o.now = time.time()
        o.tmux = ["bash", str(self.tm / "tmux.sh")]
        return o

    def n_calls(self) -> int:
        return len(self.calls.read_text().splitlines()) if self.calls.exists() else 0


@pytest.fixture()
def w(tmp_path, monkeypatch):
    world = World(tmp_path)
    _stub(world.tm / "tmux.sh", TMUX_STUB)
    monkeypatch.setenv("TM_DIR", str(world.tm))
    monkeypatch.setenv("HOME", str(tmp_path / "home"))
    monkeypatch.delenv("ZC_RESUME_DIR", raising=False)
    monkeypatch.delenv("TMUX_PANE", raising=False)
    monkeypatch.setenv("STUB_CALLS", str(world.calls))
    monkeypatch.setenv("FT_SEAT_CLOSE_BIN", str(_stub(tmp_path / "close.sh", CLOSE_STUB)))
    monkeypatch.setenv("FT_SUCC_AUTO_CLOSE", "1")
    monkeypatch.delenv("FT_SUCC_RETRY_S", raising=False)
    return world


def test_c1_seven_true_calls_standard_close(w):
    w.pair("byz-x-master#1", "byz-x-master#2")
    m = _import_scan(BIN)
    out = w.scan(m).succ_close("T")
    args = w.calls.read_text().splitlines()
    assert args == ["byz-x-master#1 --reason 승계 끝 자동 닫기 → byz-x-master#2"], args
    assert out == ["T succ-close byz-x-master#1 rc=0 — CLOSED-SESSION byz-x-master#1 stub"], out


def test_c2_attached_is_not_candidate(w):
    w.pair("byz-x-master#1", "byz-x-master#2", att=True)
    out = w.scan(_import_scan(BIN)).succ_close("T")
    assert w.n_calls() == 0 and out == [], out


def test_c3_successor_dead_is_not_candidate(w):
    w.pair("byz-x-master#1", "byz-x-master#2", alive_new=False)
    out = w.scan(_import_scan(BIN)).succ_close("T")
    assert w.n_calls() == 0 and out == [], out


def test_c3b_successor_is_end_of_chain(w):
    w.pair("byz-x-master#1", "byz-x-master#2", alive_new=False)   # #2 도 승계됨 → 마지막 = #3
    w.pair("byz-x-master#2", "byz-x-master#3", resume=False)
    w.alive.remove("byz-x-master#2")
    out = w.scan(_import_scan(BIN)).succ_close("T")
    assert w.calls.read_text().splitlines() == ["byz-x-master#1 --reason 승계 끝 자동 닫기 → byz-x-master#3"], out


def test_c4_no_resume_record_is_not_candidate(w):
    w.pair("byz-x-master#1", "byz-x-master#2", resume=False)
    out = w.scan(_import_scan(BIN)).succ_close("T")
    assert w.n_calls() == 0 and out == [], out


def test_c5_rc3_no_retry_until_window(w, monkeypatch):
    w.pair("byz-x-master#1", "byz-x-master#2")
    monkeypatch.setenv("STUB_RC", "3")
    monkeypatch.setenv("FT_SUCC_RETRY_S", "100")
    o = w.scan(_import_scan(BIN))
    out = o.succ_close("T")
    assert w.n_calls() == 1 and out == ["T succ-close byz-x-master#1 rc=3 — CLOSED-SESSION byz-x-master#1 stub"], out
    assert o.succ_close("T") == [] and w.n_calls() == 1, "같은 상태 다음 회차 = 호출 0"
    o.now += 101
    _ = o.succ_close("T")
    assert w.n_calls() == 2, "재시도 창이 지나면 1회"


def test_c6_cap_three_per_round(w):
    for i in range(5):
        w.pair(f"byz-x{i}-master#1", f"byz-x{i}-master#2", file=f"seats-{i % 2}.json")
    out = w.scan(_import_scan(BIN)).succ_close("T")
    assert w.n_calls() == 3, out
    assert sum(1 for x in out if " rc=0 " in x) == 3, out


def test_c7_tmux_failure_is_unjudged_others_continue(w):
    w.pair("byz-bad-master#1", "byz-bad-master#2")
    w.pair("byz-ok-master#1", "byz-ok-master#2", file="seats-b.json")
    w.fail.append("byz-bad-master#1")
    out = w.scan(_import_scan(BIN)).succ_close("T")
    assert [x for x in out if "판정 불가 succ-close byz-bad-master#1 " in x] and len([x for x in out if "판정 불가" in x]) == 1, out
    assert w.calls.read_text().splitlines()[0].startswith("byz-ok-master#1 "), out
    assert w.n_calls() == 1, out


def test_c8_off_logs_candidate_only(w, monkeypatch):
    w.pair("byz-x-master#1", "byz-x-master#2")
    monkeypatch.delenv("FT_SUCC_AUTO_CLOSE")
    out = w.scan(_import_scan(BIN)).succ_close("T")
    assert w.n_calls() == 0, "꺼짐 = 호출 0"
    assert out == ["T succ-close 후보 byz-x-master#1 → byz-x-master#2 (꺼짐)"], out


def test_c9_self_lookup_failure_is_fail_closed(w, monkeypatch):
    w.pair("byz-x-master#1", "byz-x-master#2")
    monkeypatch.setenv("TMUX_PANE", "%9")
    w.fail.append("%9")
    out = w.scan(_import_scan(BIN)).succ_close("T")
    assert w.n_calls() == 0, "자기 세션 조회 실패 = 닫기 0"
    assert len(out) == 1 and out[0].startswith("T 판정 불가 succ-close - 자기 세션 조회 실패(rc=2)"), out


def test_c9b_self_session_is_excluded(w, monkeypatch):
    w.pair("byz-x-master#1", "byz-x-master#2")
    w.pair("byz-y-master#1", "byz-y-master#2", file="seats-b.json")
    monkeypatch.setenv("TMUX_PANE", "%9")
    (w.tm / "me").write_text("byz-x-master#1\n", encoding="utf-8")
    out = w.scan(_import_scan(BIN)).succ_close("T")
    assert w.calls.read_text().splitlines() == ["byz-y-master#1 --reason 승계 끝 자동 닫기 → byz-y-master#2"], out


def test_wired_into_round():
    m = _import_scan(BIN)
    src = inspect.getsource(m.Scan.run)
    assert "self.succ_close(stamp)" in src, "회차 호출 1곳"
