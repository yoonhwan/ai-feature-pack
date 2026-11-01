"""r1307 — ft-stall-scan 이 팀 정지 표식(PAUSED) 팀을 «정지 중» 으로 보고 경보를 보내지 않는다.

판정 = ft_card_assign_pause.team_paused(<루트>, <팀>) 재사용(r1291 정본 · r1300 꼴) · 팀마다 이번 scan 안 1회(캐시).
on  = 처리 0(f·d·b 전부) + 요약 줄 «(정지 중 처리 0)» · none = 지금 그대로 · q = 막지 않음 + WARN 1줄(조용한 통과 0).
FT_STALL_PAUSED_SKIP=0 = 표식 판정 자체 0(지금 판과 같다) · 팀 "-"(하네스 전체 c 칸) = 판정 0.
R1~R8 = 카드 반례 · R1307_BIN = 시험할 bin 폴더(기본 kit · 셸 짝 tests/test_stall_scan_skip_paused_r1307.sh 가 변이 사본을 넣는다).
"""
import importlib
import os
import subprocess
import sys
from pathlib import Path

import pytest

from _stall_world import World, counts
from real_state_guard import guard_begin_module  # noqa: F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

BIN = Path(os.environ.get("R1307_BIN") or Path(__file__).resolve().parents[2] / "kit/fable-team/bin")
FORM = "판정 3165 · 2026-11-02T06:00:00 · 사람 정지 시험용 사유"  # r1291 정본 꼴


@pytest.fixture
def w(tmp_path: Path) -> World:
    return World(tmp_path)


def scan(w: World, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["bash", str(BIN / "ft-stall-scan.sh"), *args], env=w.env, capture_output=True, text=True, timeout=60)


def marker(w: World, team: str, body: str = FORM) -> Path:
    d = w.root / f".fable-team/state/{team}-tick"
    d.mkdir(parents=True, exist_ok=True)
    p = d / "PAUSED"
    _ = p.write_text(body + "\n", encoding="utf-8")
    return p


def lead(w: World, seat: str = "t1-master#1", minutes: float = 5) -> None:
    """팀장 f 후보 — IDLE 문턱 넘김 + 마지막 글이 미래형 선언(도구 0) · 심박 판정은 우편함 파일이 있어야 돈다."""
    if not (w.root / ".fable-team/comm/mailbox.jsonl").exists():
        w.mail("planner#1", 1, 30, frm="x", body="발주 확인")  # 심박 아님([정리] 아님) — 파일만 세운다
    w.state(seat, "IDLE", minutes)
    w.jsonl(seat, "확인했습니다. 지금 착수하겠습니다")


def sends(w: World, to: str) -> list[str]:
    return [r for r in w.mbox_log() if r.startswith(f"send|{to}|")]


def lines(out: str, prefix: str) -> list[str]:
    return [x for x in out.splitlines() if x.startswith(prefix)]


def inproc_calls(w: World, monkeypatch: pytest.MonkeyPatch, skip: str | None = None) -> list[str]:
    """실제 판정 모듈을 이 프로세스에서 한 번 돌려 team_paused 호출을 센다(모듈 경로 = R1307_BIN · 의미 변경 0)."""
    for k, v in w.env.items():
        monkeypatch.setenv(k, str(v))
    if skip is None:
        monkeypatch.delenv("FT_STALL_PAUSED_SKIP", raising=False)
    else:
        monkeypatch.setenv("FT_STALL_PAUSED_SKIP", skip)
    sys.path.insert(0, str(BIN))
    try:
        mod = importlib.import_module("ft_stall_scan")
    finally:
        sys.path.remove(str(BIN))
    cap = sys.modules["ft_card_assign_pause"]
    real, calls = cap.team_paused, []

    def counting(root: Path, team: str) -> tuple[str, str, float, str]:
        calls.append(team)
        return real(root, team)

    monkeypatch.setattr(cap, "team_paused", counting)
    assert mod.Scan().run(False) == 0
    return calls


# ── R1 — 표식 on 팀 팀장: 감지는 하되 [멈춤]·ring 0 · 요약 줄에 «(정지 중 처리 0)» ─────────────
def test_r1_paused_team_lead_gets_no_stall_notice(w: World) -> None:
    marker(w, "t1")
    lead(w)
    r = scan(w)
    assert r.returncode == 0, r.stderr
    c = counts(r.stdout)
    assert c["f"] == "1" and c["b"] == "0" and c["d"] == "0", r.stdout  # 잡히기는 한다
    assert not w.mbox_log() and not w.tmux_log(), (w.mbox_log(), w.tmux_log())  # 경보·ring 0
    (found,) = lines(r.stdout, "f t1-master#1 ")
    assert found.endswith("(정지 중 처리 0)"), found
    assert not [x for x in w.scan_log() if "act=f" in x], w.scan_log()


# ── R2 — 표식 없음: 지금 판 그대로 [멈춤] 1통 ────────────────────────────────────────
def test_r2_no_marker_alert_is_unchanged(w: World) -> None:
    lead(w)
    r = scan(w)
    c = counts(r.stdout)
    assert c["f"] == "1", r.stdout
    (sent,) = sends(w, "t1-master#1")
    assert sent.split("|")[4].startswith("[멈춤] t1-master#1 팀장 심박"), sent
    assert len([x for x in w.scan_log() if "act=f to=t1-master#1" in x]) == 1, w.scan_log()


# ── R3 — 표식이 폴더·심링크·꼴 틀림 = 판정 불가(q): 경보는 보내고 WARN 1줄 ──────────────────
def test_r3a_marker_is_directory_warns_and_still_alerts(w: World) -> None:
    (w.root / ".fable-team/state/t1-tick/PAUSED").mkdir(parents=True)  # 폴더 = 표식 아님(하드 룰 19)
    lead(w)
    r = scan(w)
    assert counts(r.stdout)["f"] == "1" and len(sends(w, "t1-master#1")) == 1, r.stdout
    assert "WARN 정지 표식 판정 불가 — 경보 보냄(t1 · 표식 자리가 일반 파일 아님)" in lines(r.stdout, "WARN"), r.stdout


def test_r3b_marker_is_symlink_warns_and_still_alerts(w: World) -> None:
    real = w.root / "elsewhere.txt"
    _ = real.write_text(FORM + "\n", encoding="utf-8")
    d = w.root / ".fable-team/state/t1-tick"
    d.mkdir(parents=True)
    (d / "PAUSED").symlink_to(real)
    lead(w)
    r = scan(w)
    assert counts(r.stdout)["f"] == "1" and len(sends(w, "t1-master#1")) == 1, r.stdout
    assert "WARN 정지 표식 판정 불가 — 경보 보냄(t1 · 표식 자리가 일반 파일 아님)" in lines(r.stdout, "WARN"), r.stdout


def test_r3c_marker_wrong_form_warns_and_still_alerts(w: World) -> None:
    marker(w, "t1", "정지")
    lead(w)
    r = scan(w)
    assert counts(r.stdout)["f"] == "1" and len(sends(w, "t1-master#1")) == 1, r.stdout
    (warn,) = lines(r.stdout, "WARN")
    assert warn.startswith("WARN 정지 표식 판정 불가 — 경보 보냄(t1 · 표식 꼴 아님"), warn


# ── R4 — 두 팀: 표식 팀은 f·d 둘 다 처리 0 · 표식 없는 팀만 [멈춤] · 판정은 팀당 1회 ──────────
def test_r4_two_teams_one_judgement_each(w: World, monkeypatch: pytest.MonkeyPatch) -> None:
    w.env["FT_STALL_PENALTY_AUTO"] = "0"
    marker(w, "t1")
    lead(w)  # t1 팀장 f 후보
    w.state("t1-nano#0", "IDLE", 4)  # 같은 팀 비팀장 d 후보(미읽음 쪽지 4분)
    w.mail("t1-nano#0", 31, 4)
    w.team("t2", "t2-master#1", [])  # 표식 없는 팀
    lead(w, "t2-master#1")
    r = scan(w)
    c = counts(r.stdout)
    assert c["f"] == "2" and c["d"] == "1", r.stdout  # 둘 다 감지
    assert not [x for x in w.mbox_log() if "t1-" in x], w.mbox_log()  # 표식 팀 = 처리 0
    assert len(sends(w, "t2-master#1")) == 1, w.mbox_log()  # 표식 없는 팀만 1통
    calls = inproc_calls(w, monkeypatch)
    assert calls.count("t1") == 1 and calls.count("t2") == 1, calls  # 팀마다 1회(캐시)
    assert len(calls) == len(set(calls)), calls


# ── R5 — 표식 팀은 페널티 자동 켜기 제외(trig) · 표식 없는 팀은 지금처럼 켠다 ──────────────────
def test_r5a_paused_team_does_not_turn_on_penalty(w: World) -> None:
    w.state("t1-nano#0", "IDLE", 4)
    w.mail("t1-nano#0", 32, 4)
    _ = scan(w)  # ① 표식 없음 — 처리되어 handled 에 남는다
    marker(w, "t1")  # ② 사람이 정지시켰다
    w.advance(120)
    r = scan(w)
    assert counts(r.stdout)["d"] == "1", r.stdout
    assert not [x for x in w.scan_log() if "penalty-on" in x], w.scan_log()
    assert not (w.root / ".fable-team/state/PENALTY_STOP").exists()


def test_r5b_no_marker_turns_on_penalty_as_before(w: World) -> None:
    w.state("t1-nano#0", "IDLE", 4)
    w.mail("t1-nano#0", 33, 4)
    _ = scan(w)
    w.advance(120)
    _ = scan(w)
    assert [x for x in w.scan_log() if "penalty-on keys=d:t1-nano#0" in x], w.scan_log()
    assert (w.root / ".fable-team/state/PENALTY_STOP").exists()


# ── R6 — FT_STALL_PAUSED_SKIP=0 = 표식 판정 0 · 지금 판과 같다 ─────────────────────────────
def test_r6_skip_off_is_current_behaviour(w: World, monkeypatch: pytest.MonkeyPatch) -> None:
    marker(w, "t1")
    lead(w)
    w.env["FT_STALL_PAUSED_SKIP"] = "0"
    r = scan(w)
    assert counts(r.stdout)["f"] == "1" and len(sends(w, "t1-master#1")) == 1, r.stdout
    assert not lines(r.stdout, "WARN"), r.stdout
    assert not [x for x in r.stdout.splitlines() if "(정지 중 처리 0)" in x], r.stdout
    assert inproc_calls(w, monkeypatch, skip="0") == []  # 판정 함수 호출 0


# ── R7 — 닫는 사건: 표식을 지우면(team_resume) 다음 scan 부터 경보 재개 ──────────────────────
def test_r7_resume_then_alert_resumes(w: World) -> None:
    marker(w, "t1")
    lead(w)
    first = scan(w)
    assert counts(first.stdout)["f"] == "1" and not w.mbox_log(), first.stdout
    (w.root / ".fable-team/state/t1-tick/PAUSED").unlink()
    w.advance(900)  # REPEAT_S 창 밖
    r = scan(w)
    assert len(sends(w, "t1-master#1")) == 1, (r.stdout, w.mbox_log())


# ── R8 — 표식 팀의 b(비팀장·미읽음 0)도 처리 0 · ring 0 ──────────────────────────────────
def test_r8_paused_team_b_alone_gets_no_ring(w: World) -> None:
    marker(w, "t1")
    w.state("t1-nano#0", "IDLE", 5)
    w.jsonl("t1-nano#0", "지금 착수하겠습니다")
    r = scan(w)
    c = counts(r.stdout)
    assert c["b"] == "1" and c["d"] == "0", r.stdout
    (found,) = lines(r.stdout, "b t1-nano#0 ")
    assert found.endswith("(정지 중 처리 0)"), found
    assert not w.mbox_log() and not w.tmux_log(), (w.mbox_log(), w.tmux_log())
