"""R132a — codex 좌석 턴 판정 (`ft_seat_codex.py` · `ft-seat-status.sh turn` 위임) 시험.

가짜 ps·lsof 스텁 + 가짜 rollout jsonl 만 쓴다 — 실제 tmux·lsof·~/.codex 조회 0.
행 8열: STATE TURN_END DURATION_MS REPORTED SOURCE READ_BYTES ABORTED(aborted|-) REASON(-|사유)
"""

import json
import os
import subprocess
import sys
from pathlib import Path

BIN = Path(__file__).resolve().parents[3] / "harness" / "bin"
SEAT = "t-da-codex#1"
BODY = "SECRET_BODY_MUST_NOT_APPEAR"


def _event(kind: str, turn_id: str, ts: str, **extra) -> dict:
    return {"timestamp": ts, "type": "event_msg", "payload": {"type": kind, "turn_id": turn_id, **extra}}


def _noise(ts: str) -> dict:
    return {"timestamp": ts, "type": "response_item", "payload": {"type": "message", "text": BODY}}


def _write_rollout(root: Path, name: str, events: list[dict]) -> Path:
    p = root / "2026" / "10" / "13" / f"rollout-{name}.jsonl"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text("".join(json.dumps(e, ensure_ascii=False) + "\n" for e in events), encoding="utf-8")
    return p


class Env:
    """한 좌석 환경 — 프로세스 표(자손)와 lsof 가 돌려줄 rollout 목록을 스텁으로 주입한다."""

    def __init__(self, tmp: Path, files: list[str], procs: list[tuple[int, int, str]]):
        ps, lsof = tmp / "ps.sh", tmp / "lsof.sh"
        ps.write_text("#!/bin/sh\n" + "".join(f"echo '{p} {pp} {c}'\n" for p, pp, c in procs), encoding="utf-8")
        opened = "".join(f"echo 'n{f}'\n" for f in files)
        lsof.write_text(f'#!/bin/sh\n[ "$1" = 101 ] && {{ echo "n/tmp/other.jsonl"; {opened}}}\nexit 0\n', encoding="utf-8")
        self.env = {**os.environ, "FT_SEAT_CODEX_PANE_PID": "100", "FT_SEAT_CODEX_PS": f"sh {ps}",
                    "FT_SEAT_CODEX_LSOF": f"sh {lsof}", "FT_SEAT_CODEX_ROOT": str(tmp / "sessions")}

    def run(self) -> list[str]:
        r = subprocess.run([sys.executable, str(BIN / "ft_seat_codex.py"), SEAT], capture_output=True, text=True, env=self.env)
        assert r.returncode == 0, r.stderr
        assert BODY not in r.stdout + r.stderr  # 대화 본문 키는 읽어도 출력에 안 나온다
        return r.stdout.rstrip("\n").split("\t")


CODEX_PROCS = [(100, 1, "/bin/zsh"), (101, 100, "/x/bin/codex"), (102, 101, "/x/bin/codex-code-mode-host"), (103, 100, "/usr/bin/node")]


def _setup(tmp_path: Path, events: list[dict] | None, n_files: int = 1, procs=None) -> Env:
    """events=None 이면 열린 rollout 0개. 아니면 같은 사건열의 rollout n_files 개를 본체가 열고 있다."""
    root = tmp_path / "sessions"
    root.mkdir(exist_ok=True)
    files = [] if events is None else [str(_write_rollout(root, f"f{i}", events + [_noise("2026-10-13T09:00:00.000Z")])) for i in range(n_files)]
    return Env(tmp_path, files, procs or CODEX_PROCS)


def test_1_started_complete_is_idle(tmp_path: Path) -> None:
    ev = [_event("task_started", "T1", "2026-10-13T08:00:00.000Z"),
          _event("task_complete", "T1", "2026-10-13T08:05:00.000Z", duration_ms=300000)]
    row = _setup(tmp_path, ev).run()
    assert row[:5] == ["IDLE", "2026-10-13T08:05:00.000Z", "300000", "-", "codex"]
    assert row[6:] == ["-", "-"]


def test_2_started_aborted_is_idle_with_abort_mark(tmp_path: Path) -> None:
    ev = [_event("task_started", "T1", "2026-10-13T08:00:00.000Z"), _event("turn_aborted", "T1", "2026-10-13T08:02:00.000Z")]
    row = _setup(tmp_path, ev).run()
    assert row[:2] == ["IDLE", "2026-10-13T08:02:00.000Z"]
    assert row[6] == "aborted"


def test_3_new_start_after_abort_is_working(tmp_path: Path) -> None:
    ev = [_event("task_started", "T1", "2026-10-13T08:00:00.000Z"), _event("turn_aborted", "T1", "2026-10-13T08:02:00.000Z"),
          _event("task_started", "T2", "2026-10-13T08:03:00.000Z")]
    row = _setup(tmp_path, ev).run()
    assert row[0] == "WORKING" and row[4] == "codex" and row[6:] == ["-", "-"]


def test_4_rollout_zero_is_unknown(tmp_path: Path) -> None:
    row = _setup(tmp_path, None).run()
    assert row[0] == "UNKNOWN" and row[4] == "codex" and row[7] == "rollout 0"


def test_5_rollout_two_is_unknown(tmp_path: Path) -> None:
    ev = [_event("task_started", "T1", "2026-10-13T08:00:00.000Z"), _event("task_complete", "T1", "2026-10-13T08:05:00.000Z")]
    row = _setup(tmp_path, ev, n_files=2).run()
    assert row[0] == "UNKNOWN" and row[7] == "rollout 2"


def test_6_no_codex_body_is_unknown(tmp_path: Path) -> None:
    host_only = [(100, 1, "/bin/zsh"), (102, 100, "/x/bin/codex-code-mode-host"), (103, 100, "/usr/bin/node")]
    ev = [_event("task_started", "T1", "2026-10-13T08:00:00.000Z"), _event("task_complete", "T1", "2026-10-13T08:05:00.000Z")]
    row = _setup(tmp_path, ev, procs=host_only).run()
    assert row[0] == "UNKNOWN" and row[7] == "codex 본체 없음"


def test_7_terminal_turn_id_mismatch_is_unknown(tmp_path: Path) -> None:
    ev = [_event("task_started", "T1", "2026-10-13T08:00:00.000Z"), _event("task_complete", "OTHER", "2026-10-13T08:05:00.000Z")]
    row = _setup(tmp_path, ev).run()
    assert row[0] == "UNKNOWN" and row[7] == "turn_id 불일치"


def test_rollout_outside_sessions_root_is_not_counted(tmp_path: Path) -> None:
    """lsof 가 sessions 루트 밖 jsonl 만 돌려주면 rollout 0 — 다른 jsonl 을 본체 것으로 오인하지 않는다."""
    root = tmp_path / "sessions"
    root.mkdir()
    outside = tmp_path / "elsewhere" / "rollout-x.jsonl"
    outside.parent.mkdir()
    outside.write_text("", encoding="utf-8")
    row = Env(tmp_path, [str(outside)], CODEX_PROCS).run()
    assert row[0] == "UNKNOWN" and row[7] == "rollout 0"


def test_if_codex_gate_skips_non_codex_seats(tmp_path: Path) -> None:
    """--if-codex <명부 폴더>: 명부 agent 가 codex 가 아니면 rc 3 · 출력 0 (ft-seat-status.sh 가 기존 경로로 간다)."""
    (tmp_path / "seats-x.json").write_text(json.dumps({SEAT: {"agent": "claude"}, "t-c#1": {"agent": "codex"}}), encoding="utf-8")
    def run(seat: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run([sys.executable, str(BIN / "ft_seat_codex.py"), "--if-codex", str(tmp_path), seat],
                              capture_output=True, text=True, env={**os.environ, "FT_SEAT_CODEX_PANE_PID": "100"})

    r = run(SEAT)
    assert r.returncode == 3 and r.stdout == ""
    assert run("t-nobody#1").returncode == 3


def test_ft_seat_status_delegates_codex_seat(tmp_path: Path) -> None:
    """명부 agent=codex 좌석만 위임 — `turn --json` 에 source=codex · aborted 키. 그 외 경로 무변경은 기존 시험이 본다."""
    ev = [_event("task_started", "T1", "2026-10-13T08:00:00.000Z"), _event("turn_aborted", "T1", "2026-10-13T08:02:00.000Z")]
    env = _setup(tmp_path, ev)
    seats = tmp_path / "seats.json"
    seats.write_text(json.dumps({SEAT: {"agent": "codex"}}), encoding="utf-8")
    r = subprocess.run(["bash", str(BIN / "ft-seat-status.sh"), "turn", SEAT, "--json"], capture_output=True, text=True,
                       env={**env.env, "FT_SEATS_JSON": str(seats)})
    assert r.returncode == 0, r.stderr
    row = json.loads(r.stdout)
    assert row["state"] == "IDLE" and row["source"] == "codex" and row["aborted"] is True
    assert row["turn_end"] == "2026-10-13T08:02:00.000Z"
