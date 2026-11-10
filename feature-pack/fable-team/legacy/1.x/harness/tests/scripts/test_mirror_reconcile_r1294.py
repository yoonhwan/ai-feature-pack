"""r1294 머리표와 직접 게시 반례."""
import json
import re

import pytest

from _mirror_reconcile_support import DESK, row, rig, save_thread, slack as _slack_fixture  # noqa: F401
import mirror_backlog as bl
import mirror_desk as desk
import mirror_lib as lib
import mirror_marker as markers
import mirror_reconcile as mr
import post_guard


@pytest.fixture(autouse=True)
def settings(monkeypatch):
    for key, value in {"FT_RECONCILE_SEC": "600", "FT_RECONCILE_FIRST_SEC": "86400",
                       "FT_RECONCILE_WINDOW_SEC": "7200", "FT_RECONCILE_MAX": "20"}.items():
        monkeypatch.setenv(key, value)


def test_r15_non_desk_head_never_reads_desk_configuration(monkeypatch):
    monkeypatch.setattr(post_guard, "human_channels", lambda: set())
    monkeypatch.setattr(post_guard, "check", lambda *a, **k: None)
    monkeypatch.setattr(post_guard, "desk_channel", lambda: (_ for _ in ()).throw(AssertionError("unexpected lookup")))
    monkeypatch.setattr(post_guard, "post", lambda *a, **k: "1.0")
    assert post_guard.guarded_post("x", "t", "C1", "[작업상황] ordinary") == "1.0"


def test_r01_to_r11_heads_and_preservation():
    cases = [
        ("[HIL] 결정", "HIL", "HIL"), ("[BLOCK] 멈춤", "BLOCK", "BLOCK"),
        ("[긴급] 처리", "긴급", "긴급"), ("[결정] 선택", "보고", "결정"),
        ("[결정 대기] 선택", "보고", "결정 대기"),
        ("골좌표: 5 — 세션 생명주기\n[HIL] 선택", "HIL", "HIL"),
        ("스크립트 4 · 인터뷰 2 · 막힌 팀 대기 1\n[결정] 선택", "보고", "결정"),
        ("스크립트 3 · 인터뷰 2 · 막힌 팀 대기 1 (낡음 7분)\n스크립트 4 · 인터뷰 2 · 막힌 팀 대기 1\n[결정] 선택", "보고", "결정"),
        ("골좌표: 1 — 첫 줄\n\n[긴급] 요청", "긴급", "긴급"),
        ("[from->to] [BLOCK] 멈춤", "BLOCK", "BLOCK"), ("[정리] 완료", "보고", None),
    ]
    for body, label, expected in cases:
        parsed, text = lib.classify(body)
        assert parsed == label and lib.desk_head(body) == expected
        if body.startswith("골좌표:"):
            assert text.startswith("골좌표:")


def test_r12_to_r14_desk_gate_sender_and_backlog():
    r = row(1, "[결정] 선택", 1)
    assert not desk.wants_desk(r, frozenset(), False)
    assert desk.wants_desk(r, frozenset(), True)
    assert desk.wants_desk(row(2, "[긴급] 장애", 2, sender="ft-api-outage"), frozenset({"ft-api-outage"}), True)
    assert not desk.urgent_from(row(3, "골좌표: 1 — 재개\n[재개] 복구", 3, sender="ft-api-outage"), frozenset({"ft-api-outage"}))
    assert bl.pick([r, row(2, "일반 보고", 2)], 0, re.compile(r"planner-arch"), 1, desk_on=True) == []


def test_r15_direct_post_copies_after_main_and_uses_original_head(monkeypatch):
    calls = []
    monkeypatch.setattr(post_guard, "human_channels", lambda: set())
    monkeypatch.setattr(post_guard, "check", lambda *a, **k: None)
    monkeypatch.setattr(post_guard, "desk_channel", lambda: DESK)
    monkeypatch.setattr(post_guard, "post", lambda base, token, channel, text, thread_ts=None:
                        calls.append((channel, text, thread_ts)) or ("100.1" if len(calls) == 1 else "100.2"))
    ts = post_guard.guarded_post("http://fake", "t", "C1", "[작업상황] 요약", head="[결정] 원문")
    assert ts == "100.1" and [c[0] for c in calls] == ["C1", DESK]
    assert calls[1][1].endswith("(desk-copy C1 100.1)")


def test_desk_copy_failure_propagates_after_main(monkeypatch):
    calls = []
    def post(base, token, channel, text, thread_ts=None):
        calls.append(channel)
        if channel == DESK:
            raise lib.MirrorError("desk failed")
        return "100.1"
    monkeypatch.setattr(post_guard, "human_channels", lambda: set())
    monkeypatch.setattr(post_guard, "check", lambda *a, **k: None)
    monkeypatch.setattr(post_guard, "desk_channel", lambda: DESK)
    monkeypatch.setattr(post_guard, "post", post)
    with pytest.raises(lib.MirrorError, match="desk failed"):
        post_guard.guarded_post("x", "t", "C1", "[결정] body")
    assert calls == ["C1", DESK]


def test_r16_destination_same_channel_does_not_copy(monkeypatch):
    calls = []
    monkeypatch.setattr(post_guard, "human_channels", lambda: set())
    monkeypatch.setattr(post_guard, "check", lambda *a, **k: None)
    monkeypatch.setattr(post_guard, "desk_channel", lambda: DESK)
    monkeypatch.setattr(post_guard, "post", lambda *a, **k: calls.append(a[2]) or "1.0")
    post_guard.guarded_post("x", "t", DESK, "[결정] same channel")
    assert calls == [DESK]


def test_r17_roster_fallback_and_r18_channel_isolation(tmp_path, monkeypatch, slack):
    (tmp_path / ".fable-team").mkdir()
    (tmp_path / ".fable-team" / "seats-planner.json").write_text(
        json.dumps({"_slack_channel": [DESK, "COTHER"]}), encoding="utf-8")
    monkeypatch.setenv("FT_ROOT", str(tmp_path))
    monkeypatch.delenv("BYZ_DESK_CHANNEL", raising=False)
    assert post_guard.desk_channel() == DESK
    mirror = rig(tmp_path, slack, [row(18, "[결정] channel", 1000)])
    r = mirror.rows[0]
    save_thread(mirror, lib.thread_key(r, lib.classify(r["body"])[1]), slack, 18, channel="C1")
    mr.reconcile(mirror, json.loads(mirror.state_path.read_text()), 2000)
    assert "18" in json.loads(mirror.state_path.read_text())["reconcile_missing"]


@pytest.mark.parametrize(("variant", "holds"), [
    ("drop-HIL", lambda: lib.desk_head("[HIL] x") == "HIL"),
    ("drop-BLOCK", lambda: lib.desk_head("[BLOCK] x") == "BLOCK"),
    ("drop-urgent", lambda: lib.desk_head("[긴급] x") == "긴급"),
    ("drop-decision", lambda: lib.desk_head("[결정] x") == "결정"),
    ("drop-decision-wait", lambda: lib.desk_head("[결정 대기] x") == "결정 대기"),
    ("anchored-head", lambda: lib.desk_head("[정리] x\n[결정] y") is None),
    ("all-counter-lines", lambda: lib.desk_head("스크립트 3 · 인터뷰 2 · 막힌 팀 대기 1\n스크립트 4 · 인터뷰 2 · 막힌 팀 대기 1\n[결정] x") == "결정"),
    ("cannot-counter", lambda: lib.desk_head("카운팅 확인 불가(형식)\n[결정] x") == "결정"),
    ("coordinate-preserved", lambda: lib.classify("골좌표: 5 — 세션\n[HIL] x")[1].startswith("골좌표:")),
    ("tag-removed", lambda: lib.classify("[HIL] x") == ("HIL", "x")),
    ("empty-senders-enabled", lambda: desk.wants_desk(row(1, "[결정] x", 1), frozenset(), True)),
    ("desk-disabled", lambda: not desk.wants_desk(row(1, "[결정] x", 1), frozenset(), False)),
    ("marker-exact", lambda: markers.has_marker(["bodies/1.txt@mbox"], "bodies/1.txt@mbox") and not markers.has_marker(["bodies/10.txt@mbox"], "bodies/1.txt@mbox")),
    ("age-cutoff", lambda: mr.MIN_AGE_SEC == 120),
    ("first-window", lambda: mr._setting("FT_RECONCILE_FIRST_SEC", 86400) == 86400),
    ("held-budget", lambda: mr.RECHECK_MAX == 10),
    ("single-page-budget", lambda: mr.RECHECK_MAX == 10),
    ("split-budget", lambda: mr.RECHECK_MAX * 2 == 20),
    ("team-parse", lambda: mr._team(row(1, "[결정] x", 1)) == "planner"),
    ("team-fallback", lambda: mr._team(row(1, "[결정] x", 1, sender="external")) == "external"),
    ("interval", lambda: mr._setting("FT_RECONCILE_SEC", 600) == 600),
    ("invalid-ts", lambda: mr._epoch({"seq": 1, "ts": "invalid"}) is None),
])
def test_variant_22_contracts(variant, holds):
    assert holds(), variant
