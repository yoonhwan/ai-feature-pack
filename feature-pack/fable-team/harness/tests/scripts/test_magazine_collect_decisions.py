"""아침 매거진 ① D3 판정 원문 시험 — 설계 §9-2 (mbox 사본 가짜 jsonl · relay 가짜 파일 · 네트워크 0)."""
import json
import re
import sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

KIT = Path(__file__).resolve().parents[2] / "scripts" / "harness-install" / "slack-mirror"
sys.path.insert(0, str(KIT))
import magazine_collect_decisions as md  # noqa: E402

KST = ZoneInfo("Asia/Seoul")
START = datetime(2026, 10, 7, 8, tzinfo=KST)
END = datetime(2026, 10, 8, 8, tzinfo=KST)
PLANNER = "byz-planner-master-claude#7"
MASTER = "byz-harness-master-claude#12"


COVER = ("2026-10-07T07:00:00", "byz-other#1", MASTER, "창 시작 앞 기록")  # e8c5718a8c: 첫 기록이 창 시작을 덮어야 읽는다


def mbox(tmp_path: Path, *rows: tuple[str, str, str, str]) -> Path:
    p = tmp_path / "mailbox.log.jsonl"
    rows = (COVER, *rows)
    p.write_text("\n".join(json.dumps(dict(zip(("ts", "from", "to", "body"), r)), ensure_ascii=False) for r in rows), encoding="utf-8")
    return p


def row(ts: str, body: str, frm: str = PLANNER) -> tuple[str, str, str, str]:
    return (f"2026-10-07T{ts}", frm, MASTER, f"[{frm}->{MASTER}] {body}")


def test_first_message_of_a_verdict_number_is_the_original_and_rest_are_counted(tmp_path):
    p = mbox(tmp_path, row("09:00:00", "판정 354 원문\n둘째 줄"), row("10:00:00", "판정 354 정정"), row("11:00:00", "판정 355 다른 건"))
    d = md.collect_decisions(p, START, END)
    assert [x["n"] for x in d] == [354, 355]
    assert d[0]["body"] == "판정 354 원문\n둘째 줄" and d[0]["more"] == 1 and d[1]["more"] == 0
    assert d[0]["ts"] == "2026-10-07T09:00:00" and d[0]["to"] == MASTER


def test_non_planner_sender_and_out_of_window_are_excluded(tmp_path):
    p = mbox(tmp_path, row("09:00:00", "판정 360 남의 말", frm="byz-harness-master-claude#12"), row("09:30:00", "판정 361 창 안"),
             ("2026-10-08T09:00:00", PLANNER, MASTER, "판정 362 창 밖"), ("2026-10-06T09:00:00", PLANNER, MASTER, "판정 363 창 앞"))
    assert [x["n"] for x in md.collect_decisions(p, START, END)] == [361]


def test_relay_file_present_returns_full_text_and_missing_returns_null(tmp_path, monkeypatch):
    relay = tmp_path / "relay.md"
    relay.write_text("전문 첫 줄\n되돌림: PR revert 후 install 복원\n", encoding="utf-8")
    monkeypatch.setattr(md, "RELAY_RE", re.compile(re.escape(str(tmp_path)) + r"/[^\s]+\.md"))
    p = mbox(tmp_path, row("09:00:00", f"판정 354 전문 {relay}"), row("10:00:00", f"판정 355 전문 {tmp_path}/없음.md"))
    d = md.collect_decisions(p, START, END)
    assert d[0]["relay_path"] == str(relay) and d[0]["relay_text"] == relay.read_text(encoding="utf-8")
    assert d[1]["relay_path"] == f"{tmp_path}/없음.md" and d[1]["relay_text"] is None
    assert md.collect_decisions(mbox(tmp_path, row("09:00:00", "판정 356 relay 없음")), START, END)[0]["relay_path"] is None


def test_rollback_lines_come_from_body_and_relay_and_default_sentence_otherwise(tmp_path, monkeypatch):
    relay = tmp_path / "r.md"
    relay.write_text("되돌림: 설치 복원\n딴 줄\n", encoding="utf-8")
    monkeypatch.setattr(md, "RELAY_RE", re.compile(re.escape(str(tmp_path)) + r"/[^\s]+\.md"))
    p = mbox(tmp_path, row("09:00:00", f"판정 354 본문\n되돌림: PR revert\n{relay}"), row("10:00:00", "판정 355 복구 얘기 없음"))
    d = md.collect_decisions(p, START, END)
    assert d[0]["rollback"] == ["되돌림: PR revert", "되돌림: 설치 복원"]
    assert d[1]["rollback"] == ["원문에 되돌림 없음"]


def test_missing_mailbox_raises(tmp_path):
    import pytest
    from magazine_window import MagazineError

    with pytest.raises(MagazineError, match="mbox 사본 읽기 실패"):
        md.collect_decisions(tmp_path / "없음.jsonl", START, END)
