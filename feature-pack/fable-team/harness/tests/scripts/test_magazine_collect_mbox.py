"""아침 매거진 ① mbox 수집 시험 — 설계 §9-2 (가짜 jsonl · 실 mbox 0)."""
import json
import sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import pytest

KIT = Path(__file__).resolve().parents[2] / "scripts" / "harness-install" / "slack-mirror"
sys.path.insert(0, str(KIT))
import magazine_collect_mbox as mm  # noqa: E402
from magazine_window import MagazineError  # noqa: E402

KST = ZoneInfo("Asia/Seoul")
START = datetime(2026, 10, 7, 8, tzinfo=KST)
END = datetime(2026, 10, 8, 8, tzinfo=KST)


def row(seq, ts, frm, to, body):
    return json.dumps({"seq": seq, "ts": ts, "from": frm, "to": to, "body": body}, ensure_ascii=False)


def write(tmp_path: Path, lines: list[str]) -> Path:
    p = tmp_path / "mailbox.log.jsonl"
    p.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return p


# 창 앞 사본 보장용 첫 줄(ts <= START)
HEAD = row(1, "2026-10-06T10:00:00", "byz-cfo-master-claude#3", "byz-planner-arch#2", "시작 줄")


def test_window_bounds_start_included_end_excluded(tmp_path):
    p = write(tmp_path, [
        HEAD,
        row(2, "2026-10-07T07:59:59", "byz-cfo-master-claude#3", "byz-planner-arch#2", "전"),
        row(3, "2026-10-07T08:00:00", "byz-cfo-master-claude#3", "byz-planner-arch#2", "경계 시작"),
        row(4, "2026-10-08T07:59:59", "byz-cfo-master-claude#3", "byz-planner-arch#2", "경계 끝 직전"),
        row(5, "2026-10-08T08:00:00", "byz-cfo-master-claude#3", "byz-planner-arch#2", "경계 끝"),
    ])
    out = mm.collect_mbox(p, START, END)
    assert out["mbox"]["total"] == 2


def test_by_team_counts_sender_team_and_recent_planner_received(tmp_path):
    p = write(tmp_path, [
        HEAD,
        row(2, "2026-10-07T09:00:00", "byz-cfo-master-claude#3", "byz-planner-arch#2", "[a->b] 첫째 끝났어요. 덧붙임"),
        row(3, "2026-10-07T09:01:00", "byz-cfo-master-claude#3", "byz-planner-arch#2", "[a->b] 둘째"),
        row(4, "2026-10-07T09:02:00", "byz-cfo-master-claude#3", "byz-planner-arch#2", "[a->b] 셋째"),
        row(5, "2026-10-07T09:03:00", "byz-cfo-master-claude#3", "byz-planner-arch#2", "[a->b] 넷째"),
        row(6, "2026-10-07T09:04:00", "byz-cfo-master-claude#3", "byz-cfo-nano-x#0", "planner 아닌 수신"),
        row(7, "2026-10-07T09:05:00", "ft-harness-ops#0", "byz-planner-arch#2", "팀 토막 없는 발신"),
    ])
    by_team = mm.collect_mbox(p, START, END)["mbox"]["by_team"]
    assert by_team["cfo"]["count"] == 5
    assert by_team["cfo"]["recent"] == ["둘째", "셋째", "넷째"]
    assert by_team["기타"]["count"] == 1


def ask(seq, ts, frm="byz-cfo-master-claude#3", body="[a->b] [HIL] 질문입니다. 뒷부분"):
    return row(seq, ts, frm, "byz-planner-arch#2", body)


def reply(seq, ts, to="byz-cfo-master-claude#3", frm="byz-planner-arch#2"):
    return row(seq, ts, frm, to, "[a->b] 값입니다")


def hil(tmp_path, lines):
    return mm.collect_mbox(write(tmp_path, [HEAD, *lines]), START, END)["mbox"]


def test_hil_request_is_body_start_not_mention(tmp_path):
    mb = hil(tmp_path, [
        ask(10, "2026-10-07T10:00:00", body="[a->b] [HIL] 진짜 요청입니다. 뒷부분"),
        ask(11, "2026-10-07T10:01:00", body="[a->b] 부팅 보고예요. 규칙: [HIL] 로 올립니다"),
        ask(12, "2026-10-07T10:02:00", body="[HIL · 오빠 손 1] 접두 없는 요청"),
        row(13, "2026-10-07T10:03:00", "byz-cfo-master-claude#3", "byz-cfo-nano-x#0", "[a->b] [HIL] 수신자가 planner 아님"),
    ])
    assert mb["hil_asked"] == 2 and mb["hil"] == ["[HIL] 진짜 요청입니다.", "[HIL · 오빠 손 1] 접두 없는 요청"]


def test_answered_request_is_dropped_other_seat_reply_is_not(tmp_path):
    mb = hil(tmp_path, [
        ask(10, "2026-10-07T10:00:00", "byz-cfo-master-claude#3"),
        ask(11, "2026-10-07T10:01:00", "byz-v65-master-claude#9", "[a->b] [HIL] 두번째 요청"),
        reply(12, "2026-10-07T10:05:00", to="byz-cfo-master-claude#3"),
        reply(13, "2026-10-07T10:06:00", to="byz-kk-master-claude#1"),  # 다른 좌석 회신은 무관
        reply(14, "2026-10-07T10:07:00", to="byz-v65-master-claude#9", frm="byz-cfo-master-claude#3"),  # planner 발신 아님
    ])
    assert mb["hil_asked"] == 2 and mb["hil"] == ["[HIL] 두번째 요청"]


def test_successor_seat_reply_counts_as_answer(tmp_path):
    mb = hil(tmp_path, [
        ask(10, "2026-10-07T10:00:00", "byz-v65-master-claude#145"),
        ask(11, "2026-10-07T10:01:00", "byz-cfo-master-claude#56", "[a->b] [HIL] 계보 다른 요청"),
        reply(12, "2026-10-07T10:05:00", to="byz-v65-master-claude#146"),  # 승계 후계 회신
        reply(13, "2026-10-07T10:06:00", to="byz-v65-master-claude#146"),
    ])
    assert mb["hil_asked"] == 2 and mb["hil"] == ["[HIL] 계보 다른 요청"]


def test_reply_before_request_or_after_window_end_does_not_count(tmp_path):
    mb = hil(tmp_path, [
        reply(10, "2026-10-07T09:00:00"),  # 요청보다 앞
        ask(11, "2026-10-07T10:00:00"),
        reply(12, "2026-10-08T08:00:00"),  # 창 끝 뒤
    ])
    assert mb["hil_asked"] == 1 and len(mb["hil"]) == 1


def test_hil_has_no_cap_and_keeps_old_first(tmp_path):
    mb = hil(tmp_path, [ask(10 + i, f"2026-10-07T10:{i:02d}:00", body=f"[a->b] [HIL] 질문 {i}번입니다. 뒷부분") for i in range(12)])
    assert mb["hil_asked"] == 12 and len(mb["hil"]) == 12 and mb["hil"][0] == "[HIL] 질문 0번입니다."


def test_verdicts_only_planner_sender_dedupe_ascending_first_mention(tmp_path):
    p = write(tmp_path, [
        HEAD,
        row(2, "2026-10-07T09:00:00", "byz-planner-arch#2", "byz-harness-master-claude#12", "머리말\n판정 347 오빠 컨펌\n끝"),
        row(3, "2026-10-07T09:10:00", "byz-planner-arch#2", "byz-harness-master-claude#12", "판정 345 와 판정 347 재언급"),
        row(4, "2026-10-07T09:20:00", "byz-cfo-master-claude#3", "byz-planner-arch#2", "판정 999 는 planner 발신이 아님"),
        row(5, "2026-10-07T09:30:00", "byz-planner-arch#2", "x", "판정 7 은 한 자리라 제외"),
    ])
    out = mm.collect_mbox(p, START, END)["verdicts"]
    assert [v["n"] for v in out] == [345, 347]
    assert out[1]["line"] == "판정 347 오빠 컨펌"


def test_succession_and_new_seats(tmp_path):
    p = write(tmp_path, [
        HEAD,  # byz-cfo-master-claude#3 이 창 전에 있었음
        row(2, "2026-10-06T11:00:00", "byz-harness-master-claude#11", "x", "창 전"),
        row(3, "2026-10-07T09:00:00", "byz-cfo-master-claude#3", "x", "기존 좌석 계속"),
        row(4, "2026-10-07T10:00:00", "byz-harness-master-claude#12", "x", "승계: 11 → 12"),
        row(5, "2026-10-07T10:01:00", "byz-harness-nano-magazine-collect#0", "x", "신규"),
    ])
    seats = mm.collect_mbox(p, START, END)["seats"]
    assert seats["succession"] == [["byz-harness-master-claude#11", "byz-harness-master-claude#12"]]
    assert seats["new"] == ["byz-harness-nano-magazine-collect#0"]


def test_broken_lines_are_counted_and_skipped(tmp_path):
    p = write(tmp_path, [
        HEAD,
        "{깨진 json",
        row(2, "2026-10-07T09:00:00", "byz-cfo-master-claude#3", "byz-planner-arch#2", "정상"),
        json.dumps(["dict 아님"]),
        json.dumps({"seq": 9, "ts": "2026-10-07T09:00:00"}),  # 키 부족
    ])
    mbox = mm.collect_mbox(p, START, END)["mbox"]
    assert mbox["bad_lines"] == 3
    assert mbox["total"] == 1


def test_first_valid_line_after_start_raises(tmp_path):
    p = write(tmp_path, [row(1, "2026-10-07T08:00:01", "byz-cfo-master-claude#3", "x", "너무 늦은 첫 줄")])
    with pytest.raises(MagazineError, match="앞부분"):
        mm.collect_mbox(p, START, END)


def test_no_valid_line_raises_even_if_all_broken(tmp_path):
    p = write(tmp_path, ["{깨짐", "또 깨짐"])
    with pytest.raises(MagazineError, match="앞부분"):
        mm.collect_mbox(p, START, END)


def test_missing_file_raises(tmp_path):
    with pytest.raises(MagazineError, match="mbox"):
        mm.collect_mbox(tmp_path / "없음.jsonl", START, END)
