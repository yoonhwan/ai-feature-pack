"""r1294 reconciliation state, paging and cursor counterexamples."""
import json
from types import SimpleNamespace

import pytest

from _mirror_reconcile_support import DESK, row, rig, save_thread, slack as _slack_fixture  # noqa: F401
import byz_mbox_slack_mirror as bm
import mirror_lib as lib
import mirror_reconcile as mr

@pytest.fixture(autouse=True)
def settings(monkeypatch):
    for key, value in {"FT_RECONCILE_SEC": "600", "FT_RECONCILE_FIRST_SEC": "86400",
                       "FT_RECONCILE_WINDOW_SEC": "7200", "FT_RECONCILE_MAX": "20"}.items():
        monkeypatch.setenv(key, value)


def test_r19_missing_alert_once_then_recheck(tmp_path, slack, capsys):
    r = row(19, "[결정 대기] Issue #19", 1700000000)
    mirror = rig(tmp_path, slack, [r], 19)
    save_thread(mirror, lib.thread_key(r, lib.classify(r["body"])[1]), slack)
    mr.reconcile(mirror, json.loads(mirror.state_path.read_text()), 1700000300)
    assert "#RECON-1700000300" in slack.roots[-1]["text"]
    assert "bodies/" not in slack.roots[-1]["text"]
    mr.reconcile(mirror, json.loads(mirror.state_path.read_text()), 1700000900)
    assert len([m for m in slack.roots if "#RECON-" in m["text"]]) == 1
    assert "missing=1 new=0" in capsys.readouterr().err


def test_recheck_clears_missing_after_marker_arrives(tmp_path, slack):
    r = row(19, "[결정] Issue #19", 1700000000)
    mirror = rig(tmp_path, slack, [r], 19)
    root = save_thread(mirror, lib.thread_key(r, lib.classify(r["body"])[1]), slack)
    mr.reconcile(mirror, json.loads(mirror.state_path.read_text()), 1700000300)
    assert "19" in json.loads(mirror.state_path.read_text())["reconcile_missing"]
    lib.api_call(slack.base, "test", "chat.postMessage", {"channel": DESK,
                "text": "bodies/19.txt@mbox", "thread_ts": root})
    mr.reconcile(mirror, json.loads(mirror.state_path.read_text()), 1700000900)
    assert json.loads(mirror.state_path.read_text())["reconcile_missing"] == {}


def test_reconcile_read_failure_raises_and_keeps_interval_stamp(tmp_path, slack):
    r = row(19, "[결정] Issue #19", 1700000000)
    mirror = rig(tmp_path, slack, [r], 19)
    save_thread(mirror, lib.thread_key(r, lib.classify(r["body"])[1]), slack)
    slack.fail_read = True
    with pytest.raises(lib.MirrorError, match="conversations.replies"):
        mr.reconcile(mirror, json.loads(mirror.state_path.read_text()), 1700000300)
    saved = json.loads(mirror.state_path.read_text())
    assert saved["reconcile_at"] == 1700000300 and "reconcile_missing" not in saved


def test_r20_unmapped_root_marker_is_arrival(tmp_path, slack):
    r = row(20, "[HIL] Issue #20", 1700000000)
    mirror = rig(tmp_path, slack, [r], 20)
    save_thread(mirror, lib.thread_key(r, lib.classify(r["body"])[1]), slack, 20, marker_root=True)
    mr.reconcile(mirror, json.loads(mirror.state_path.read_text()), 1700000300)
    assert json.loads(mirror.state_path.read_text())["reconcile_missing"] == {}


def test_r21_held_page_resumes_cursor(tmp_path, slack):
    slack.page_size = 2
    r = row(21, "[결정] Issue #21", 1700000000)
    mirror = rig(tmp_path, slack, [r], 21)
    root = save_thread(mirror, lib.thread_key(r, lib.classify(r["body"])[1]), slack)
    lib.api_call(slack.base, "test", "chat.postMessage", {"channel": DESK, "text": "other", "thread_ts": root})
    lib.api_call(slack.base, "test", "chat.postMessage", {"channel": DESK,
                "text": "bodies/21.txt@mbox", "thread_ts": root})
    mr.reconcile(mirror, json.loads(mirror.state_path.read_text()), 1700000300)
    st = json.loads(mirror.state_path.read_text())
    assert st["reconcile_held"]["21"]["cursor"] == "2"
    before = len([c for c in slack.requests if c[0] == "GET"])
    mr.reconcile(mirror, st, 1700000900)
    st = json.loads(mirror.state_path.read_text())
    assert "21" not in st["reconcile_held"] and "21" not in st["reconcile_missing"]
    assert len([c for c in slack.requests if c[0] == "GET"]) - before == 1


def test_r22_recheck_and_new_each_get_ten_budget(tmp_path, slack):
    now = 1700000300
    rows = [row(i, f"[결정] Issue #{i}", now - 300) for i in range(16, 31)]
    missing = {str(i): {"team": "planner", "key": f"#{i}", "first_epoch": now - 10}
               for i in range(1, 16)}
    alarmed = {str(i): now - 10 for i in range(1, 16)}
    mirror = rig(tmp_path, slack, rows, 30, {"reconcile_missing": missing, "reconcile_alarmed": alarmed})
    for i in range(1, 16):
        save_thread(mirror, f"#{i}", slack, i)
    for r in rows[:10]:
        save_thread(mirror, lib.thread_key(r, lib.classify(r["body"])[1]), slack, r["seq"])
    slack.requests.clear()
    mr.reconcile(mirror, json.loads(mirror.state_path.read_text()), now)
    assert len([c for c in slack.requests if c[0] == "GET"]) <= 21
    saved = json.loads(mirror.state_path.read_text())
    assert saved["reconcile_cursor"] == 25 and saved["reconcile_first"] is True


def test_r23_first_window_waits_for_unprocessed_and_r24_real_body(tmp_path, slack):
    now = 1700000300
    r = row(24, "골좌표: 5 — 세션 생명주기\n[HIL] 러너 나노 닫기 길 … 선택지 ①②", now - 300)
    label, text = lib.classify(r["body"])
    assert label == "HIL" and text.startswith("골좌표: 5 —")
    mirror = rig(tmp_path, slack, [r], 23)
    mr.reconcile(mirror, json.loads(mirror.state_path.read_text()), now)
    st = json.loads(mirror.state_path.read_text())
    assert st["reconcile_first"] is True and st["reconcile_cursor"] == 0
    st["last_seq"] = 24
    mr.reconcile(mirror, st, now + 601)
    assert json.loads(mirror.state_path.read_text())["reconcile_cursor"] == 24


def test_recent_old_and_unprocessed_rows_do_not_get_checked(tmp_path, slack):
    now = 1700000300
    old, recent = row(1, "[결정] old", now - 9000), row(2, "[결정] recent", now - 30)
    mirror = rig(tmp_path, slack, [old, recent], 2, {"reconcile_first": False})
    mr.reconcile(mirror, json.loads(mirror.state_path.read_text()), now)
    st = json.loads(mirror.state_path.read_text())
    assert st["reconcile_cursor"] == 1 and not [c for c in slack.requests if c[0] == "GET"]
    pending_dir = tmp_path / "pending"
    pending_dir.mkdir()
    mirror = rig(pending_dir, slack, [row(3, "[결정] unprocessed", now - 300)], 2)
    mr.reconcile(mirror, json.loads(mirror.state_path.read_text()), now)
    st = json.loads(mirror.state_path.read_text())
    assert st["reconcile_cursor"] == 0 and st["reconcile_first"] is True


def test_run_pass_orders_pending_reconcile_before_backlog(tmp_path, monkeypatch):
    order = []
    mirror = object.__new__(bm.Mirror)
    mirror.a, mirror.qpath = SimpleNamespace(dry_run=False), tmp_path / "questions.json"
    mirror.log, mirror.state_path = tmp_path / "mailbox.log.jsonl", tmp_path / "state.json"
    mirror.threads_path, mirror.desk, mirror.posted = tmp_path / "threads.json", object(), 0
    mirror.state_path.write_text(json.dumps({"last_seq": 1, "pending": {"seq": 2}}), encoding="utf-8")
    monkeypatch.setattr(bm, "read_rows", lambda _: [])
    monkeypatch.setattr(bm, "seed_threads", lambda *a: order.append("seed"))
    monkeypatch.setattr(mirror, "deliver", lambda *a, **k: order.append("pending"))
    monkeypatch.setattr(bm.mr, "reconcile", lambda *a: order.append("reconcile"))
    monkeypatch.setattr(bm.bl, "skip_backlog", lambda *a: order.append("backlog") or True)
    assert mirror.run_pass() == 0
    assert order == ["seed", "pending", "reconcile", "backlog"]
