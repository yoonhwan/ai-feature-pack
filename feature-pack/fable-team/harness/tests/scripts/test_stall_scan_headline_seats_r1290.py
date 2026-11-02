"""r1290 — 팀 헤드라인 좌석 칸 초안(ft_headline_seats) R1~R11.

칸 값 = 이번 scan 이 이미 읽은 좌석 캐시(jsonl 턴 경계 + 마지막 assistant 기록의 API 오류 표식)뿐 — 화면(capture-pane) 읽기 0.
R1290_BIN = 시험할 bin 폴더(기본 kit · 셸 짝 tests/test_headline_seats_r1290.sh 가 변이 사본을 넣는다).
"""
import fcntl
import importlib
import json
import os
import re
import stat
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import pytest

from _stall_world import World, counts
from real_state_guard import guard_begin_module  # noqa: F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

BIN = Path(os.environ.get("R1290_BIN") or Path(__file__).resolve().parents[2] / "kit/fable-team/bin")
NOW = datetime(2026, 11, 1, 10, 50, tzinfo=timezone.utc).timestamp()  # KST 19:50 — R1 의 «✻ 19:45» 와 같은 날
END = "2026-11-01T10:45:00.000Z"  # KST 19:45
TD = {"type": "system", "subtype": "turn_duration"}
GHOST = (
    '#!/bin/sh\ncase "$1" in\n  list-sessions) cat "$FT_STUB/tmux" 2>/dev/null;;\n'
    '  list-panes) awk \'{print $1"|%"NR}\' "$FT_STUB/tmux";;\n  send-keys) echo "$*" >> "$FT_STUB/tmux.log";;\n'
    '  capture-pane) echo "capture $*" >> "$FT_STUB/capture.log"; printf "❯ 작업 중입니다\\nesc to interrupt\\n";;\nesac\n'
)


@pytest.fixture(autouse=True)
def seoul(monkeypatch: pytest.MonkeyPatch) -> None:
    """로컬 시각 판정 = TZ 고정(호스트 TZ 무관 · R1·R5)."""
    monkeypatch.setenv("TZ", "Asia/Seoul")
    time.tzset()


@pytest.fixture
def w(tmp_path: Path) -> World:
    world = World(tmp_path)
    world.env.update(FT_NOW=str(int(NOW)), TZ="Asia/Seoul", FT_STALL_PENALTY_AUTO="0")
    return world


def assistant(stamp: str = END, text: str = "ok") -> dict:
    return {"type": "assistant", "timestamp": stamp, "message": {"content": [{"type": "text", "text": text}]}}


def api_error(stamp: str = "2026-11-01T10:32:00.000Z") -> dict:
    return {"type": "assistant", "timestamp": stamp, "isApiErrorMessage": True, "message": {"content": [{"type": "text", "text": "API Error: 529 overloaded"}]}}


def seat(w: World, name: str, state: str, end: str = END, records: list[dict] | None = None) -> None:
    """턴 경계 스텁 + (있으면) jsonl — jsonl 파일이 없으면 «jsonl 없는 좌석»(판정 불가 갈래)."""
    (w.stub / "turn").mkdir(parents=True, exist_ok=True)
    _ = (w.stub / "turn" / name).write_text(f"{state} {end} 1000 no jsonl\n")
    if records is not None:
        (w.stub / "jsonl").mkdir(parents=True, exist_ok=True)
        _ = (w.stub / "jsonl" / f"{name}.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in records))


def roster_add(w: World, label: str, rows: dict[str, dict], live: bool = True) -> None:
    path = w.root / f".fable-team/seats-{label}.json"
    doc = json.loads(path.read_text())
    doc.update(rows)
    _ = path.write_text(json.dumps(doc))
    if live:
        w.live.extend(seat for seat in rows if seat not in w.live)
        w._tmux()


def ghost_tmux(w: World) -> Path:
    """화면 스텁 — capture-pane 을 부르면 고스트 글자를 내고 호출을 기록한다(R6: 호출 0 이어야 한다)."""
    path = w.stub / "tmux-ghost.sh"
    _ = path.write_text(GHOST)
    path.chmod(path.stat().st_mode | stat.S_IEXEC)
    w.env["FT_TMUX"] = str(path)
    return w.stub / "capture.log"


def scan(w: World, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["bash", str(BIN / "ft-stall-scan.sh"), *args], env=w.env, capture_output=True, text=True, timeout=70)


def draft(w: World, team: str = "t1") -> Path:
    return w.root / f".fable-team/state/{team}-tick/HEADLINE-seats.txt"


def text(w: World, team: str = "t1") -> str:
    return draft(w, team).read_text(encoding="utf-8")


def module():
    """이 프로세스에서 실제 모듈을 한 번 불러온다(R1290_BIN · 변이 사본 대응)."""
    sys.path.insert(0, str(BIN))
    try:
        return importlib.import_module("ft_headline_seats")
    finally:
        sys.path.remove(str(BIN))


# ── R1 — jsonl IDLE · TURN_END 10:45Z → «✻ 19:45»(로컬 · 하루 안) ─────────────────────
def test_r1_idle_turn_end_is_local_clock(w: World) -> None:
    seat(w, "t1-master#1", "WORKING", END, [TD, assistant(END)])
    seat(w, "t1-nano#0", "IDLE", END, [TD, assistant(END), TD])
    r = scan(w)
    assert r.returncode == 0, r.stderr
    body = text(w)
    assert body.startswith("19:50 초안 · 팀장(작업 중) · "), body
    assert "t1-nano#0=?(✻ 19:45)" in body, body
    assert len(body.splitlines()) == 1
    assert counts(r.stdout)["stall"] == "0", r.stdout  # 판정·발신 칸은 그대로


# ── R2 — WORKING·PENDING = «작업 중» ────────────────────────────────────────────
def test_r2_working_and_pending_are_working(w: World) -> None:
    seat(w, "t1-master#1", "PENDING", END, [TD, assistant(END)])
    seat(w, "t1-nano#0", "WORKING", END, [TD, assistant(END)])
    assert scan(w).returncode == 0
    body = text(w)
    assert "팀장(작업 중)" in body and "t1-nano#0=?(작업 중)" in body, body


# ── R3 — IDLE · 마지막 assistant 가 API 오류 → «오류 19:32»(✻ 아님) ──────────────────
def test_r3_api_error_turn_is_error_cell(w: World) -> None:
    seat(w, "t1-master#1", "WORKING", END, [TD, assistant(END)])
    seat(w, "t1-nano#0", "IDLE", END, [TD, api_error(), TD])
    assert scan(w).returncode == 0
    body = text(w)
    assert "t1-nano#0=?(오류 19:32)" in body, body
    assert "✻" not in body.split("t1-nano#0")[1], body


# ── R4 — 오류 기록 뒤 정상 턴이 끝났다 → «✻ 19:45»(오류 아님) ─────────────────────────
def test_r4_normal_turn_after_error_is_idle(w: World) -> None:
    seat(w, "t1-master#1", "WORKING", END, [TD, assistant(END)])
    seat(w, "t1-nano#0", "IDLE", END, [TD, api_error("2026-11-01T10:20:00.000Z"), TD, assistant(END), TD])
    assert scan(w).returncode == 0
    body = text(w)
    assert "t1-nano#0=?(✻ 19:45)" in body, body
    assert "오류" not in body, body


# ── R5 — LOGGEDOUT(첫 실패 08:00Z) → «로그아웃 17:00» ───────────────────────────────
def test_r5_logged_out_uses_first_failure_clock(w: World) -> None:
    seat(w, "t1-master#1", "WORKING", END, [TD, assistant(END)])
    seat(w, "t1-nano#0", "LOGGEDOUT", "2026-11-01T08:00:00.000Z", [TD, api_error("2026-11-01T08:00:00.000Z"), TD])
    assert scan(w).returncode == 0
    body = text(w)
    assert "t1-nano#0=?(로그아웃 17:00)" in body, body


# ── R6 — 화면 스텁에 «❯ 작업 중입니다»·«esc to interrupt» 고스트 글자 → 칸 «✻ 19:45» · capture-pane 0 ─
def test_r6_screen_ghost_text_is_not_used(w: World) -> None:
    calls = ghost_tmux(w)
    seat(w, "t1-master#1", "WORKING", END, [TD, assistant(END)])
    seat(w, "t1-nano#0", "IDLE", END, [TD, assistant(END), TD])
    assert scan(w).returncode == 0
    body = text(w)
    assert "t1-nano#0=?(✻ 19:45)" in body, body
    assert not calls.exists(), calls.read_text() if calls.exists() else ""


# ── R7 — jsonl 없는 좌석 → «판정 불가(jsonl 없음)» ─────────────────────────────────
def test_r7_seat_without_jsonl_is_undecided(w: World) -> None:
    seat(w, "t1-master#1", "WORKING", END, [TD, assistant(END)])
    seat(w, "t1-nano#0", "IDLE", END, None)  # jsonl 파일 없음(codex·pi 좌석)
    assert scan(w).returncode == 0
    body = text(w)
    assert "t1-nano#0=?(판정 불가(jsonl 없음))" in body, body


# ── R8 — 명부 _closed·stop-ready 좌석 = 칸 0 · 명부 현역인데 tmux 없음 → «세션 없음» ─────────
def test_r8_closed_and_stop_ready_are_not_cells(w: World) -> None:
    roster_add(w, "t1", {"t1-nano#9": {"role": "nano", "_closed": True}, "t1-nano#8": {"role": "stop-ready"}, "t1-nano#7": {"role": "nano"}}, live=False)
    seat(w, "t1-master#1", "WORKING", END, [TD, assistant(END)])
    seat(w, "t1-nano#0", "IDLE", END, [TD, assistant(END), TD])
    assert scan(w).returncode == 0
    body = text(w)
    assert "t1-nano#9" not in body and "t1-nano#8" not in body, body
    assert "t1-nano#7=?(세션 없음)" in body, body


# ── R9 — 처리 0 인 실행(--dry-run · 앞 실행 잠금) 뒤 초안 그대로 · 다음 정상 실행이 덮어씀(1줄) ──
def test_r9_only_a_processing_run_rewrites_the_draft(w: World) -> None:
    seat(w, "t1-master#1", "WORKING", END, [TD, assistant(END)])
    seat(w, "t1-nano#0", "IDLE", END, [TD, assistant(END), TD])
    assert scan(w).returncode == 0
    before, first = text(w), draft(w).stat().st_mtime_ns
    assert scan(w, "--dry-run").returncode == 0
    assert text(w) == before and draft(w).stat().st_mtime_ns == first  # --dry-run = 초안 0
    with open(w.root / ".fable-team/state/stall-scan.lock", "a+") as lock:  # r1282 기한 초과도 «처리 0» 같은 길
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        blocked = scan(w)
        assert "앞 실행이 아직 돈다" in blocked.stdout, blocked.stdout
        assert text(w) == before and draft(w).stat().st_mtime_ns == first
    w.advance(120)
    assert scan(w).returncode == 0
    lines = text(w).splitlines()
    assert len(lines) == 1 and lines[0].startswith("19:52 초안 · "), lines  # 덮어쓰기(누적 0)


# ── R10 — 20석 · 300자 초과 → «+N석 유휴(✻ 가장 늦은 HH:MM)» 로 묶임 ─────────────────
def test_r10_many_idle_seats_are_folded(w: World) -> None:
    rows = {f"byz-t1-nano-t1-n{index}#0": {"role": "nano"} for index in range(1, 20)}
    roster_add(w, "t1", rows)
    seat(w, "t1-master#1", "WORKING", END, [TD, assistant(END)])
    for name in [*rows, "t1-nano#0"]:
        seat(w, name, "IDLE", END, [TD, assistant(END), TD])
    assert scan(w).returncode == 0
    body = text(w)
    (line,) = body.splitlines()
    head, _, seats = line.partition(" 초안 · ")
    assert re.search(r"\+[0-9]+석 유휴\(✻ 19:45\)", seats), seats  # 접힌 칸 = 가장 늦은 ✻ 시각
    assert len(seats) <= 300, len(seats)
    assert len(line) <= 300 + len(head) + len(" 초안 · "), len(line)
    assert "n1=?(✻ 19:45)" in seats, seats  # 덜 오래된 유휴 칸은 그대로 남는다


# ── R11 — 짧은 이름(팀 이름 낱말 떼기 · 역할#N) ──────────────────────────────────────
def test_r11_short_names() -> None:
    mod = module()
    assert mod.short_name("byz-ops-nano-ops-k4-chatbot-name-test-org#0") == "k4"
    assert mod.short_name("byz-harness-nano-r1228-news-brief-goal-step-team-line-pla#0") == "r1228"
    assert mod.short_name("byz-lecture-tester-claude#14") == "tester#14"
    assert mod.short_name("byz-ops-nano-ops-longname-without-number#7") == "longname-without-num"
