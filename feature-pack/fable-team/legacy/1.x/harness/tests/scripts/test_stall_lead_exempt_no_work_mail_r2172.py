"""r2172 — 받을 일이 없는 팀장은 60분까지 [멈춤](팀장 심박 없음) 0 · 쉼 심박 뒤 «사건» = 일 쪽지만.

계약: L1 일 쪽지 = 받는이 role_key 가 그 팀 현역 팀장 ∧ 발신 ≠ ft-stall-scan ∧ is_not_work(본문) 거짓 ∧ 도구 일반 알림 아님
(발신이 «#숫자» 로 안 끝나고 «ft-»·«ft2-» 로 시작 · 머리 [긴급]·[크리티컬] 제외) · 팀장 발신 = 일 쪽지 아님 ·
L2 쉼 면제의 사건 = 일 쪽지만 · L3 마지막 심박 H 가 N분 안이면 H 뒤 일 쪽지 0 = 경보 0 · 있으면 첫 일 쪽지부터 20분 ·
L4 N = FT_LEAD_IDLE_EXEMPT_MIN(0~240 · 0 = L3 끔 · 그 밖 = 60) · L5 읽기 오류 = 면제 0 · 읽기 횟수 그대로.
R2172_BIN = 시험할 bin 폴더(기본 kit) — 변이 사본을 넣어 반대 결과를 대조한다.
"""
import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

import pytest

from _stall_world import NOW, World, counts
from real_state_guard import guard_begin_module  # noqa: F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

BIN = Path(os.environ.get("R2172_BIN") or Path(__file__).resolve().parents[2] / "kit/fable-team/bin")
sys.path.insert(0, str(BIN))
import ft_stall_detect as d  # noqa: E402

M = "t1-master#1"
PLAIN = "[정리] 한 일 3줄"
REST2 = "[정리] 한 일 3줄\n[다음 없음]"


@pytest.fixture
def w(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> World:
    for k in ("FT_LEAD_IDLE_EXEMPT_MIN", "FT_SEAT_OPEN_WORK", "FT_LEAD_HEARTBEAT_MIN", "FT_LEAD_REST_MAX_MIN"):
        monkeypatch.delenv(k, raising=False)
    return World(tmp_path)


def alert(w: World) -> tuple[bool, float | None, bool]:
    return d.lead_alert(w.root, w.root / ".fable-team/comm", M, NOW)


def lead(w: World, minutes: float, body: str = PLAIN, *mails: tuple[str, float, str, str]) -> bool:
    """M 의 심박(받는이 planner#1) + 곁쪽지들(받는이, 몇 분 전, 보낸이, 본문) → lead_alert 의 경보."""
    w.heartbeat(M, minutes, body=body)
    for i, (to, ago, frm, text) in enumerate(mails):
        w.mail(to, 800 + i, ago, frm=frm, body=text)
    a, _age, undec = alert(w)
    assert undec is False
    return a


def log_line(w: World, line: str) -> None:
    with open(w.root / ".fable-team/comm/mailbox.log.jsonl", "a", encoding="utf-8") as f:
        _ = f.write(line + "\n")


def log_mail(w: World, minutes_ago: float, to: str, frm: str, body: str) -> None:
    ts = datetime.fromtimestamp(NOW - minutes_ago * 60).strftime("%Y-%m-%dT%H:%M:%S")
    log_line(w, json.dumps({"seq": 7, "ts": ts, "to": to, "from": frm, "body": body}, ensure_ascii=False))


# ── ① L3 [정리] 25분 · 그 뒤 쪽지 0 = 경보 0 ────────────────────────────────
def test_r1_plain_25min_no_mail_is_quiet(w: World) -> None:
    assert lead(w, 25) is False


def test_r1_scan_sends_no_stall(w: World) -> None:  # scan 끝까지 = [멈춤] 0통
    for seat in ("planner#1", "t1-nano#0"):
        w.state(seat, "WORKING", 0.1)
    w.state(M, "IDLE", 5)
    w.jsonl(M, "확인했습니다. 지금 착수하겠습니다")
    w.heartbeat(M, 25)
    r = subprocess.run(["bash", str(BIN / "ft-stall-scan.sh")], env=w.env, capture_output=True, text=True, timeout=70)
    assert r.returncode == 0, r.stderr
    assert counts(r.stdout)["f"] == "0", r.stdout
    assert not [x for x in w.mbox_log() if x.startswith(f"send|{M}|")]


# ── ② 도구 일반 알림 · 일 아님 꼴 = 일 쪽지 아님 ─────────────────────────────
def test_r2_tool_notice_and_not_work_are_not_work_mail(w: World) -> None:
    assert lead(w, 25, PLAIN, (M, 10, "ft-idle-scan", "[유휴 점검] t1 좌석 3"), (M, 10, "t2-master#3", "[정리] 다른 팀 한 일")) is False


def test_r2b_tool_notice_22min_is_not_work_mail(w: World) -> None:  # 10분 사례는 일 쪽지로 세도 20분 안이라 ⓓ 변이(M2)를 못 잡는다
    assert lead(w, 25, PLAIN, (M, 22, "ft-idle-scan", "[유휴 점검] t1 좌석 3")) is False


# ── ③ 좌석 발신 [보고] = 일 쪽지 · 첫 일 쪽지부터 20분 ──────────────────────
@pytest.mark.parametrize(("ago", "want"), [(22, True), (10, False)], ids=["22분 경보", "10분 조용"])
def test_r3_seat_report_restarts_20min(w: World, ago: float, want: bool) -> None:
    assert lead(w, 25, PLAIN, (M, ago, "t1-nano#0", "[보고] 산출 1건")) is want


def test_r3_boundary_20min_exact(w: World) -> None:  # 경계: 첫 일 쪽지 나이 20분 = 경보 0 · 20분 1초 = 경보 1
    assert lead(w, 40, PLAIN, (M, 20, "t1-nano#0", "[보고] 산출 1건")) is False
    w2 = World(w.root.parent / "b")
    assert lead(w2, 40, PLAIN, (M, 20 + 1 / 60, "t1-nano#0", "[보고] 산출 1건")) is True


# ── ④ 도구 발신 [긴급] = 일 쪽지 · [다음 막힘] = 도구 일반 알림 ─────────────────
@pytest.mark.parametrize(("body", "want"), [("[긴급] keeper 막힘", True), ("[크리티컬] keeper 막힘", True), ("[다음 막힘] keeper 대기", False)],
                         ids=["긴급", "크리티컬", "다음 막힘"])
def test_r4_tool_urgent_is_work_mail(w: World, body: str, want: bool) -> None:
    assert lead(w, 25, PLAIN, (M, 22, "ft2-keeper", body)) is want


# ── ⑤ 팀장이 보낸 쪽지 = 일 쪽지 아님 ───────────────────────────────────────
def test_r5_lead_sent_order_is_not_work_mail(w: World) -> None:
    assert lead(w, 25, PLAIN, ("t1-nano#0", 22, M, "[발주] 이어서 하세요")) is False


# ── ⑥ 상한 N · 운영값 ──────────────────────────────────────────────────────
@pytest.mark.parametrize(("n", "minutes", "want"), [
    (None, 60, False), (None, 61, True), (None, 60 + 1 / 60, True), ("0", 25, True), ("60", 60, False),
    ("x", 60, False), ("x", 61, True), ("-1", 60, False), ("-1", 61, True), ("241", 60, False), ("241", 61, True),
    ("nan", 60, False), ("nan", 61, True), ("inf", 61, True), ("120", 100, False),
], ids=lambda v: str(v))
def test_r6_idle_cap(w: World, monkeypatch: pytest.MonkeyPatch, n: str | None, minutes: float, want: bool) -> None:
    if n is not None:
        monkeypatch.setenv("FT_LEAD_IDLE_EXEMPT_MIN", n)
    assert lead(w, minutes) is want


# ── ⑦⑧ L2 쉼 심박 뒤 사건 = 일 쪽지만 ──────────────────────────────────────
IDLE3 = [(M, 90, "ft-idle-scan", "[5분 점검] 좌석 1"), (M, 70, "ft-idle-scan", "[5분 점검] 좌석 2"), (M, 50, "ft-idle-scan", "[5분 점검] 좌석 3"),
         ("planner#1", 30, M, "[보고] 팀 상황 1줄")]


def test_r7_rest_with_tool_notices_and_lead_mail_is_quiet(w: World) -> None:
    assert lead(w, 100, REST2, *IDLE3) is False


def test_r8a_rest_then_seat_done_is_alert(w: World) -> None:
    assert lead(w, 100, REST2, *IDLE3, (M, 30, "t1-nano#0", "[완료] 카드 1장")) is True


def test_r8b_rest_over_cap_is_alert(w: World) -> None:
    assert lead(w, 241, REST2) is True


# ── ⑨ L5 판정 불가 = 면제 0 · 읽기 횟수 그대로 ──────────────────────────────
def counted(monkeypatch: pytest.MonkeyPatch) -> list[str]:
    calls: list[str] = []
    for name in ("_read_mailbox", "_read_mailbox_log"):
        real = getattr(d, name)
        monkeypatch.setattr(d, name, lambda *a, _r=real, _n=name, **k: (calls.append(_n), _r(*a, **k))[1])
    return calls


def test_r9_read_count_same_as_baseline(w: World, monkeypatch: pytest.MonkeyPatch) -> None:  # 후보 1명 = 큐+로그 × 2(심박 · 확장)
    calls = counted(monkeypatch)
    assert lead(w, 25) is False
    assert calls == ["_read_mailbox", "_read_mailbox_log"] * 2


def test_r9a_broken_line_in_extended_window_is_alert(w: World, monkeypatch: pytest.MonkeyPatch) -> None:
    log_line(w, "{ 깨진 줄")  # 파일 앞 — 20분 창은 닿지 않고 확장 읽기(240분)만 닿는다
    log_mail(w, 60, "planner#1", "x", "발주")
    calls = counted(monkeypatch)
    w.heartbeat(M, 25)
    assert alert(w) == (True, pytest.approx(25), False)
    assert len(calls) == 4


def test_r9b_open_work_unreadable_is_alert(w: World, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("FT_SEAT_OPEN_WORK", str(w.root / "없는-open-work.py"))
    calls = counted(monkeypatch)
    w.heartbeat(M, 25)
    assert alert(w) == (True, pytest.approx(25), False)
    assert len(calls) == 4


def test_r9c_initial_read_error_stays_undecided(w: World) -> None:  # 초기 심박 ERROR = 판정 불가 그대로(DA 보충 ㉡)
    w.heartbeat(M, 25)
    w.raw_mail("{ 깨진 줄")
    assert alert(w) == (False, None, True)
