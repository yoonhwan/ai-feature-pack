"""r504 ⓐ~ⓔ — 좌석 턴 판정기 하나(ft_seat_turn) · 뉴스 HTML·지도 = 좌석별 하위 프로세스 0.

픽스처 = 임시 projects 폴더 + 좌석 40개 jsonl(IDLE 20 · WORKING 15 · PENDING 3 · UNKNOWN 2) + 가짜 tmux(호출 기록) + 가짜 ft-seat-status.sh(불리면 기록).
옛 판정 = origin/main 의 ft-seat-status.sh(heredoc 본문)를 임시 파일로 꺼내 같은 픽스처에 돌려 대조(파리티). 실 좌석 기록·외부 호출 0 · GIT_* env 0.
실행: python3 -m pytest tests/scripts/test_seat_turn_batch.py -q
"""
import importlib.util
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

import pytest

PACK = Path(__file__).resolve().parents[3]
BIN = PACK / "harness" / "bin"
sys.path.insert(0, str(BIN))

import ft_news_html as fh  # noqa: E402
import ft_seat_turn as st  # noqa: E402

MASTER = "byz-t-master-claude#1"
KINDS = ["IDLE"] * 20 + ["WORKING"] * 15 + ["PENDING"] * 3 + ["UNKNOWN"] * 2
SEATS = [f"byz-t-nano-{i:02d}#0" for i in range(40)]
GIT_ENV = ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY")
FAKE_TMUX = """#!/usr/bin/env bash
# 가짜 tmux — 호출마다 1줄 기록 · ls = 세션 이름 · list-panes = 세션\\tcwd(FAKE_PANES 파일)
echo "$*" >> "$FAKE_TMUX_LOG"
case "$1" in
  ls|list-sessions) cut -f1 "$FAKE_PANES" ;;
  list-panes) cat "$FAKE_PANES" ;;
  *) exit 1 ;;
esac
"""
FAKE_STATUS = """#!/usr/bin/env bash
# 가짜 ft-seat-status.sh — 불리면 기록 · one = pane IDLE
echo "$*" >> "$FAKE_STATUS_LOG"
[ "$1" = one ] && printf '%s IDLE - claude\\n' "$2"
"""


def _j(rec: dict) -> str:
    return json.dumps(rec, separators=(",", ":"), ensure_ascii=False) + "\n"  # 실 jsonl 처럼 공백 없는 꼴(좌석명 바늘 대조)


def _end(i: int) -> dict:
    return {"type": "system", "subtype": "turn_duration", "timestamp": f"2026-10-20T02:{i % 60:02d}:00Z", "durationMs": 1000 + i}


def _msg(kind: str, text: str = "x") -> dict:
    return {"type": kind, "message": {"role": kind, "content": [{"type": "text", "text": text}]}}


def _report() -> dict:
    return {"type": "assistant", "message": {"content": [{"type": "tool_use", "input": {"command": f"bash mbox.sh send {MASTER} me hi"}}]}}


def _records(i: int, seat: str, kind: str) -> list[dict]:
    head = [{"type": "agent-name", "agentName": seat}, _msg("user", "go")]
    pad = [_msg("assistant", "p" * 3000) for _ in range(i % 4 * 30)]  # 일부는 64KB 창 밖으로 — 창 2배 늘리기 경로
    turn1 = [_msg("assistant"), *([_report()] if i % 3 == 0 else []), _end(i)]
    if kind == "UNKNOWN":
        return [{"type": "custom-title", "customTitle": seat}, {"type": "system", "subtype": "away_summary"}]
    tail = {"IDLE": [], "WORKING": [_msg("user", "next")], "PENDING": [{"type": "queue-operation", "operation": "enqueue"}]}[kind]
    return [*head, *pad, *turn1, _msg("user", "t2"), *([_report()] if i % 2 else []), _end(i + 1), *tail]


@pytest.fixture
def world(tmp_path, monkeypatch):
    """40석 jsonl(좌석 0~38 = 폴더 wt-a · 39 = 폴더 없는 cwd) + 가짜 tmux·seat-status (PATH · FT_TMUX · fh.HERE)."""
    projects, fake, cwd = tmp_path / "projects", tmp_path / "fake", "/tmp/r504/wt-a"
    d = projects / re.sub(r"[^A-Za-z0-9]", "-", cwd)
    for p in (d, fake):
        p.mkdir(parents=True)
    files = {}
    for i, (seat, kind) in enumerate(zip(SEATS, KINDS)):
        files[seat] = d / f"{i:02d}.jsonl"
        files[seat].write_text("".join(_j(r) for r in _records(i, seat, kind)), encoding="utf-8")
    panes = tmp_path / "panes.tsv"
    panes.write_text("".join(f"{s}\t{cwd if s != SEATS[-1] else '/tmp/r504/없는-cwd'}\n" for s in SEATS), encoding="utf-8")
    for name, body in (("tmux", FAKE_TMUX), ("ft-seat-status.sh", FAKE_STATUS)):
        (fake / name).write_text(body, encoding="utf-8")
        (fake / name).chmod(0o755)
    env = {"FAKE_TMUX_LOG": tmp_path / "tmux.log", "FAKE_STATUS_LOG": tmp_path / "status.log", "FAKE_PANES": panes,
           "FT_CLAUDE_PROJECTS": projects, "FT_TMUX": fake / "tmux", "PATH": f"{fake}:{os.environ['PATH']}"}
    for k, v in env.items():
        monkeypatch.setenv(k, str(v))
    for k in GIT_ENV:
        monkeypatch.delenv(k, raising=False)
    (tmp_path / "tmux.log").write_text("", encoding="utf-8")
    (tmp_path / "status.log").write_text("", encoding="utf-8")
    return {"tmp": tmp_path, "files": files, "fake": fake}


def _log(world, name: str) -> list[str]:
    return (world["tmp"] / f"{name}.log").read_text(encoding="utf-8").splitlines()


def _old_status(tmp: Path) -> Path:
    """고치기 전 셸 도구(heredoc 판정 본문) — origin/main 판을 임시 파일로(리포 쓰기 0)."""
    rel = "feature-pack/fable-team/harness/bin/ft-seat-status.sh"
    out = subprocess.run(["git", "-C", str(PACK), "show", f"origin/main:{rel}"], capture_output=True, text=True, check=True).stdout
    assert "python3 - <<'PY'" in out.split("turn_of_file()", 1)[1][:400], "origin/main 판이 이미 고친 판 — 대조 기준 아님"
    old = tmp / "old-bin" / "ft-seat-status.sh"
    old.parent.mkdir()
    old.write_text(out, encoding="utf-8")
    return old


def _shell(script: Path, f: Path, *flags: str) -> bytes:
    env = {**os.environ, "FT_MASTER_SEAT": MASTER, "FT_SEATS_JSON": "/nonexistent/seats.json", "FT_SEAT_TAIL_START": "8192", "FT_SEAT_TAIL_BYTES": "262144"}
    r = subprocess.run(["bash", str(script), "turn", "--file", str(f), *flags], capture_output=True, env=env, check=False)
    assert r.returncode == 0, r.stderr
    return r.stdout


FLAGS = [(), ("--no-reported",), ("--json",), ("--bytes",), ("--no-reported", "--json")]


def test_a_module_matches_old_shell_verdict_40_of_40(world):
    old = _old_status(world["tmp"])
    same = 0
    for seat, kind in zip(SEATS, KINDS):
        f = world["files"][seat]
        for status_only, master, flags in ((False, MASTER, ()), (True, "", ("--no-reported",))):
            want = _shell(old, f, *flags).decode().rstrip("\n").split(" ")
            got = st.turn_of_file(str(f), 262144, 8192, master, status_only)
            assert [*got[:4], "jsonl", str(got[4])][:5] == want[:5], (seat, flags)
        assert st.turn_of_file(str(f))[0] == kind, seat
        same += 1
    assert same == 40


def test_e_shell_turn_output_bytes_unchanged(world):
    old, new = _old_status(world["tmp"]), BIN / "ft-seat-status.sh"
    for seat in SEATS:
        for flags in FLAGS:
            assert _shell(new, world["files"][seat], *flags) == _shell(old, world["files"][seat], *flags), (seat, flags)


def test_b_news_html_live_teams_one_list_panes_no_seat_status_calls(world, monkeypatch):
    fable = world["tmp"] / ".fable-team"
    fable.mkdir()
    (fable / "seats-t.json").write_text("{}", encoding="utf-8")
    monkeypatch.setattr(fh, "HERE", world["fake"])  # 옛 경로(HERE/ft-seat-status.sh)가 불리면 status.log 에 남는다
    start = time.monotonic()
    t = next(x for x in fh.live_teams(world["tmp"]) if x["team"] == "t")
    assert time.monotonic() - start < 7
    assert (t["live"], t["working"]) == (40, 15)
    assert [ln for ln in _log(world, "tmux") if ln.startswith("list-panes")] == ["list-panes -a -F #{session_name}\t#{pane_current_path}"]
    assert _log(world, "status") == []


def _tree(world):
    spec = importlib.util.spec_from_file_location("ft_news_tree_r504", BIN / "ft-news-tree.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    ctx = {"seats": {s: {"role": "nano"} for s in SEATS}, "alive": set(SEATS), "status_sh": world["fake"] / "ft-seat-status.sh"}
    return mod, ctx


def test_c_news_tree_seat_state_40_seats_only_unknown_go_to_pane(world):
    mod, ctx = _tree(world)
    got = [mod.seat_state(ctx, s) for s in SEATS]
    assert got.count("작업중") == 15 and got.count("PENDING") == 3
    status = _log(world, "status")
    assert all(ln.startswith("one ") for ln in status)  # turn 하위 호출 0
    assert sorted(ln.split()[1] for ln in status) == sorted([SEATS[38], SEATS[39]])  # UNKNOWN 1 + jsonl 없음 1 만 pane 판정 1회씩
    assert len([ln for ln in _log(world, "tmux") if ln.startswith("list-panes")]) == 1


def test_d_seat_without_jsonl_is_unknown_with_reason_not_resting(world, monkeypatch):
    got = st.turns(SEATS, os.environ["FT_TMUX"], Path(os.environ["FT_CLAUDE_PROJECTS"]))
    assert got[SEATS[39]] == ("?", "jsonl 없음")
    assert sum(v[0] == "WORKING" for v in got.values()) == 15
    world["files"][SEATS[0]].unlink()  # 찾은 뒤 읽기 전에 지워짐 = 읽기 실패
    monkeypatch.setattr(st, "find_jsonls", lambda seats, tmux, projects: {SEATS[0]: str(world["files"][SEATS[0]])})
    assert st.turns([SEATS[0], SEATS[39]], "tmux", Path("/x")) == {SEATS[0]: ("?", "읽기 실패"), SEATS[39]: ("?", "jsonl 없음")}
    fable = world["tmp"] / ".fable-team"
    fable.mkdir()
    (fable / "seats-z.json").write_text("{}", encoding="utf-8")
    monkeypatch.setattr(fh, "_sessions", lambda: ["byz-z-a#0", "byz-z-b#0"])
    monkeypatch.setattr(fh, "_turns", lambda seats: {"byz-z-a#0": ("?", "jsonl 없음"), "byz-z-b#0": ("?", "jsonl 없음")})
    live = fh.live_teams(world["tmp"])
    z = next(x for x in live if x["team"] == "z")
    assert (z["working"], z["unknown"], z["unknown_reason"]) == (0, 2, "jsonl 없음 2석")
    facts = fh.facts(live, "모름")
    assert "z" in facts["확인 불가"] and "z" not in facts["쉬는 팀"]


def test_tmux_timeout_marks_all_unknown_with_reason(monkeypatch):
    def boom(*_a):
        raise subprocess.TimeoutExpired("tmux", 7)
    import ft_seat_turn
    monkeypatch.setattr(ft_seat_turn, "turns", boom)
    assert fh._turns(["a", "b"]) == {"a": ("?", "tmux 시간 초과"), "b": ("?", "tmux 시간 초과")}
