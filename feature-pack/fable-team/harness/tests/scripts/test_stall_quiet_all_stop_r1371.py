"""r1371 — 사람이 «전팀 정지·크론 정지» 를 걸었으면 멈춤 감시기가 경보를 쌓지 않는다.

표식 = <루트>/.fable-team/state/ALL_STOP.json(r626 정본 ft-all-stop.sh · since = 초).
on  = a(지금 spawn)·f(팀장 심박 끊김)·h(헤드라인 멈춤) 발신 0 + «보류 <종류> <팀> — 전팀 정지(since HH:MM)» 1줄.
보류하지 않는 것 = c(정책 정지·정지 파일 0) 같이 정지 중에도 보여야 하는 경보.
없음(off) = 지금 판 그대로(회귀 0) · 깨짐·읽기 실패 = 경보 그대로 + «판정 불가 ALL_STOP» 1줄(조용한 보류 0).
on → off 다음 회차 = 그 회차 판정만(몰아 보내기 0).
R1371_BIN = 시험할 bin 폴더(기본 kit · 셸 짝 tests/test_stall_quiet_all_stop_r1371.sh 가 변이 사본을 넣는다).
"""
import os
import subprocess
from pathlib import Path

import pytest

from _stall_world import NOW, World, counts
from real_state_guard import guard_begin_module  # noqa: F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

BIN = Path(os.environ.get("R1371_BIN") or Path(__file__).resolve().parents[2] / "kit/fable-team/bin")


@pytest.fixture
def w(tmp_path: Path) -> World:
    return World(tmp_path)


def scan(w: World, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["bash", str(BIN / "ft-stall-scan.sh"), *args], env=w.env, capture_output=True, text=True, timeout=60)


def marker(w: World, since: float = NOW - 3600, body: str | None = None) -> Path:
    """전팀 정지 표식 — 본문을 주면 그대로(깨짐 시험)."""
    path = w.root / ".fable-team/state/ALL_STOP.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    text = body if body is not None else (
        '{"since": %d, "by": "byz-planner-master-claude#229", "reason": "사람 정지 시험용", "notify_failed": []}' % int(since)
    )
    _ = path.write_text(text + ("\n" if body is None else ""), encoding="utf-8")
    return path


def hhmm(since: float) -> str:
    import time

    return time.strftime("%H:%M", time.localtime(since))


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


# ── S1 — 표식 on · 팀장 심박 끊김: [멈춤] 0 · 보류 노트 ─────────────────────────────────
def test_s1_on_team_lead_heartbeat_no_stall_notice(w: World) -> None:
    since = NOW - 3600
    marker(w, since)
    lead(w)
    r = scan(w)
    assert r.returncode == 0, r.stderr
    c = counts(r.stdout)
    assert c["f"] == "1" and c["b"] == "0" and c["d"] == "0", r.stdout  # 잡히기는 한다(보이게)
    assert not w.mbox_log() and not w.tmux_log(), (w.mbox_log(), w.tmux_log())  # [멈춤]·ring 0
    (found,) = lines(r.stdout, "f t1-master#1 ")
    assert found.endswith("(전팀 정지 처리 0)"), found
    assert f"보류 f t1 — 전팀 정지(since {hhmm(since)})" in lines(r.stdout, "보류 f"), r.stdout
    assert not [x for x in w.scan_log() if "act=f" in x], w.scan_log()
    assert [x for x in w.scan_log() if "보류 f t1 — 전팀 정지" in x], w.scan_log()  # 감시 로그 1줄


# ── S2 — 표식 on · 헤드라인 낡음: [헤드라인 멈춤] 0 · 보류 노트 ────────────────────────────
def test_s2_on_stale_headline_no_alert(w: World) -> None:
    since = NOW - 3600
    marker(w, since)
    w.headline("t1", 1000)  # 15분 훨씬 넘은 헤드라인
    r = scan(w)
    assert r.returncode == 0, r.stderr
    assert counts(r.stdout)["h"] == "1", r.stdout  # 감지는 한다
    assert not sends(w, "t1-master#1"), w.mbox_log()  # 1단계 헤드라인 경보 0
    assert not sends(w, "planner-desk#0"), w.mbox_log()
    assert f"보류 h t1 — 전팀 정지(since {hhmm(since)})" in lines(r.stdout, "보류 h"), r.stdout
    assert not (w.root / ".fable-team/state/stall-headline.json").exists(), "on 중엔 1·2단계 상태를 적지 않는다"


# ── S3 — 표식 on · a 후보(대기 카드 + master IDLE): «지금 spawn» 0 · 보류 노트 ──────────────
def test_s3_on_spawn_candidate_no_nudge(w: World) -> None:
    marker(w)
    w.cards("t1", ["card-a"])
    w.state("t1-master#1", "IDLE", 8)
    r = scan(w)
    c = counts(r.stdout)
    assert c["a"] == "1", r.stdout
    assert not w.mbox_log(), w.mbox_log()  # «지금 spawn» 0
    assert not w.calls("flow.calls"), w.calls("flow.calls")  # 상한 판정 호출 0
    assert "보류 a t1 — 전팀 정지(since " in r.stdout, r.stdout
    (found,) = lines(r.stdout, "a t1-master#1 ")
    assert found.endswith("(전팀 정지 처리 0)"), found


# ── S4 — 표식 on 이어도 c(정책 정지) 는 그대로 나간다 ────────────────────────────────────
def test_s4_on_policy_stop_c_alert_survives(w: World) -> None:
    marker(w)
    w.freeze()  # RESOURCE_FREEZE = c 후보
    r = scan(w)
    c = counts(r.stdout)
    assert c["c"] == "1", r.stdout
    (sent,) = [x for x in sends(w, "planner#1") if "[긴급] 정지 중" in x]
    assert "RESOURCE_FREEZE" in sent, w.mbox_log()


# ── S5 — 표식이 깨짐: 경보 그대로 + «판정 불가 ALL_STOP» 1줄 ───────────────────────────────
def test_s5_broken_marker_alerts_as_before(w: World) -> None:
    marker(w, body="{not json")
    lead(w)
    r = scan(w)
    assert counts(r.stdout)["f"] == "1", r.stdout
    assert len(sends(w, "t1-master#1")) == 1, w.mbox_log()
    assert [x for x in r.stdout.splitlines() if x.startswith("판정 불가 ALL_STOP ")], r.stdout
    assert len([x for x in r.stdout.splitlines() if x.startswith("판정 불가 ALL_STOP ")]) == 1, r.stdout
    assert not lines(r.stdout, "보류 f"), r.stdout


def test_s5b_marker_without_since_is_unknown(w: World) -> None:
    marker(w, body='{"by": "x", "reason": "칸 없음"}')
    w.cards("t1", ["card-a"])
    w.state("t1-master#1", "IDLE", 8)
    r = scan(w)
    assert counts(r.stdout)["a"] == "1" and w.mbox_log(), r.stdout
    assert "판정 불가 ALL_STOP since 없음·꼴 틀림" in r.stdout, r.stdout


def test_s5c_marker_is_directory_is_unknown(w: World) -> None:
    (w.root / ".fable-team/state/ALL_STOP.json").mkdir(parents=True)  # 폴더 = 표식 아님(하드 룰 19)
    lead(w)
    r = scan(w)
    assert len(sends(w, "t1-master#1")) == 1, (r.stdout, w.mbox_log())
    assert [x for x in r.stdout.splitlines() if x.startswith("판정 불가 ALL_STOP ")], r.stdout


# ── S6 — 표식 없음(off) = 지금 그대로(회귀 0) ────────────────────────────────────────────
def test_s6_no_marker_is_current_behaviour(w: World) -> None:
    lead(w)
    r = scan(w)
    assert counts(r.stdout)["f"] == "1", r.stdout
    (sent,) = sends(w, "t1-master#1")
    assert sent.split("|")[4].startswith("[멈춤] t1-master#1 팀장 심박"), sent
    assert not lines(r.stdout, "보류 f"), r.stdout
    assert "판정 불가 ALL_STOP" not in r.stdout, r.stdout


# ── S7 — on → off 다음 회차: 그 회차 판정만([멈춤] 1통 · 몰아 보내기 0) ────────────────────
def test_s7_on_then_off_alerts_once(w: World) -> None:
    path = marker(w)
    lead(w)
    first = scan(w)
    assert counts(first.stdout)["f"] == "1" and not w.mbox_log(), first.stdout
    (path).unlink()  # 사람이 재개(ft-all-stop.sh off)
    w.advance(900)  # REPEAT_S 창 밖
    r = scan(w)
    assert len(sends(w, "t1-master#1")) == 1, (r.stdout, w.mbox_log())  # 그 회차 1통
    w.advance(60)
    again = scan(w)
    assert counts(again.stdout)["f"] == "1", again.stdout  # 계속 감지는 하지만
    assert len(sends(w, "t1-master#1")) == 1, w.mbox_log()  # 몰아 보내기·반복 0
