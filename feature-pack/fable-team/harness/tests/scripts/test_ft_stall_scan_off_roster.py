"""r525 — ft-stall-scan 종류 e: 명부 루프가 안 보는 tmux 라이브 좌석(교대 표시·명부 밖)의 조용한 정지.

가짜 세계(_stall_world) + pane 자식(ps 스텁) + ctx 계산기 스텁(FT_CTX_CMD). 처리 = 알림 쪽지만 — 깨우기·kill 0.
"""
import json
from pathlib import Path

import pytest

from _stall_world import World, counts

TMUX = (
    '#!/bin/sh\ncase "$1" in\n  list-sessions) cat "$FT_STUB/tmux" 2>/dev/null;;\n'
    '  list-panes) case "$*" in *pane_pid*) awk \'{print $1"|"1000+NR}\' "$FT_STUB/tmux";; *) awk \'{print $1"|%"NR}\' "$FT_STUB/tmux";; esac;;\n'
    '  send-keys|kill-session|kill-server) echo "$*" >> "$FT_STUB/tmux.log";;\nesac\n'
)
PS = '#!/bin/sh\ncat "$FT_STUB/ps" 2>/dev/null\n'
CTX = '#!/bin/sh\ncat "$FT_STUB/ctx/$1" 2>/dev/null || exit 1\n'


def _exe(path: Path, body: str) -> str:
    _ = path.write_text(body)
    path.chmod(0o755)
    return str(path)


@pytest.fixture
def w(tmp_path: Path) -> World:
    w = World(tmp_path)
    (w.stub / "ctx").mkdir()
    _ = _exe(w.stub / "tmux.sh", TMUX)
    w.env.update(FT_PS=_exe(w.stub / "ps.sh", PS), FT_CTX_CMD=_exe(w.stub / "ctx.sh", CTX))
    return w


def live(w: World, seat: str, agent: str | None = "claude") -> None:
    """tmux 라이브 세션 1개 + pane 셸(+ 그 자식 agent) — pane_pid = 1000 + 세션 순번(스텁 list-panes 와 같은 규칙)."""
    if seat not in w.live:
        w.live.append(seat)
        w._tmux()
    pid = 1000 + w.live.index(seat) + 1
    rows = f"{pid} 1 -zsh\n" + (f"{pid + 5000} {pid} /Users/x/.local/bin/{agent} --name {seat}\n" if agent else "")
    with open(w.stub / "ps", "a", encoding="utf-8") as fh:
        _ = fh.write(rows)


def ctx(w: World, seat: str, pct: int) -> None:
    _ = (w.stub / "ctx" / seat).write_text(f"{pct}\n")


def handed_over(w: World) -> None:
    """chatbot 명부 — 옛 concierge master 6 은 교대 표시(stop-ready · _replaced_by) · 현역 master = chatbot master 7."""
    rows = {"_master": "chatbot-master#7", "_label": "chatbot", "chatbot-master#7": {"role": "master"},
            "concierge-master#6": {"role": "stop-ready", "_replaced_by": "chatbot-master#7"}}
    _ = (w.root / ".fable-team/seats-chatbot.json").write_text(json.dumps(rows))
    live(w, "chatbot-master#7")
    w.state("chatbot-master#7", "WORKING", 0.1)


def sends(w: World) -> list[str]:
    return [r for r in w.mbox_log() if r.startswith("send|")]


def e_lines(out: str) -> list[str]:
    return [line for line in out.splitlines() if line.startswith("e ")]


def test_a_handed_over_row_live_idle_45_open_work(w: World) -> None:  # ⓐ (고치기 전 FAIL)
    handed_over(w)
    live(w, "concierge-master#6")
    w.state("concierge-master#6", "IDLE", 45)
    r = w.scan()
    assert r.returncode == 0, r.stderr
    assert counts(r.stdout).get("e") == "1", r.stdout
    assert e_lines(r.stdout)[0].startswith("e concierge-master#6 45 교대 표시인데 라이브 · 열린 일"), r.stdout
    to = sorted(s.split("|")[1] for s in sends(w))
    assert to == ["chatbot-master#7", "planner#1"], w.mbox_log()
    assert all("[정지] concierge-master#6 쉬는 45분" in s and "받는 쪽 판단" in s for s in sends(w))


def test_b_unregistered_live_claude_ctx_93_goes_to_planner_only(w: World) -> None:  # ⓑ
    live(w, "stray#3")
    w.state("stray#3", "IDLE", 40)
    ctx(w, "stray#3", 93)
    r = w.scan()
    assert counts(r.stdout)["e"] == "1"
    assert "ctx 93%" in e_lines(r.stdout)[0] and "명부 밖" in e_lines(r.stdout)[0]
    assert [s.split("|")[1] for s in sends(w)] == ["planner#1"], w.mbox_log()


def test_c_same_signature_next_run_no_note_but_log_line(w: World) -> None:  # ⓒ
    live(w, "stray#3")
    w.state("stray#3", "IDLE", 40)
    _ = w.scan()
    w.advance(660)  # 10분 반복 창 밖 — 막는 것은 서명(좌석·종류·IDLE 시작 시각)이어야 한다
    r = w.scan()
    assert counts(r.stdout)["e"] == "1"
    assert len(sends(w)) == 1, w.mbox_log()
    assert [line for line in w.scan_log() if line.startswith("stall=")][-1].split().count("e=1") == 1


def test_d_idle_25_is_zero(w: World) -> None:  # ⓓ
    live(w, "stray#3")
    w.state("stray#3", "IDLE", 25)
    r = w.scan()
    assert counts(r.stdout)["e"] == "0" and not sends(w)


def test_e_rest_low_ctx_zero_rest_high_ctx_counts(w: World) -> None:  # ⓔ
    live(w, "rest#1")
    w.state("rest#1", "IDLE", 50)
    w.jsonl("rest#1", "[완료·휴식] 끝났습니다")
    ctx(w, "rest#1", 40)
    assert counts(w.scan().stdout)["e"] == "0" and not sends(w)
    ctx(w, "rest#1", 95)
    r = w.scan()
    assert counts(r.stdout)["e"] == "1" and "ctx 95%" in e_lines(r.stdout)[0], r.stdout
    assert "열린 일" not in e_lines(r.stdout)[0]


def test_f_no_agent_zero_offroster_nano_counts(w: World) -> None:  # ⓕ
    live(w, "shell#0", agent=None)
    w.state("shell#0", "IDLE", 60)
    live(w, "byz-x-nano-y#0", agent="codex")
    w.state("byz-x-nano-y#0", "IDLE", 40)
    r = w.scan()
    assert counts(r.stdout)["e"] == "1", r.stdout
    assert e_lines(r.stdout)[0].startswith("e byz-x-nano-y#0 40 명부 밖"), r.stdout
    assert "ctx ?" in e_lines(r.stdout)[0]


def test_g_never_send_keys_or_kill_and_dry_run_sends_nothing(w: World) -> None:  # ⓖ
    handed_over(w)
    live(w, "concierge-master#6")
    w.state("concierge-master#6", "IDLE", 45)
    live(w, "stray#3")
    w.state("stray#3", "IDLE", 90)
    ctx(w, "stray#3", 99)
    assert counts(w.scan("--dry-run").stdout)["e"] == "2" and not w.mbox_log()
    r = w.scan()
    assert counts(r.stdout)["e"] == "2"
    assert not w.tmux_log(), w.tmux_log()
    assert not [x for x in w.mbox_log() if x.startswith("ring|")]
