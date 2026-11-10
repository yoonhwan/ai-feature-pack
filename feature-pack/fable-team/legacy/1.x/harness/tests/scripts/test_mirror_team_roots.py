"""팀·날짜 뿌리 글 — T1 뿌리 1·답글 3 · T2 팀 판정 · T3 날짜 경계 · T7 재시작 재사용 · T8 planner 한눈에 (판정 623 · 가짜 Slack·GitHub)."""
from pathlib import Path

import pytest
from _slack_fakes import FakeSlack
from _team_fakes import Clock, World, kst, mt


@pytest.fixture
def slack():
    s = FakeSlack()
    yield s
    s.srv.shutdown()


def test_t1_one_team_root_and_three_replies(tmp_path: Path, slack: FakeSlack):
    w = World(tmp_path, slack, {10: ["team:harness"], 11: ["team:shared-harness"]})
    w.send("#10", "a1")
    w.send("#11", "a2")
    w.send("byz-harness-master-claude", "a3")
    assert len(slack.roots) == 2  # harness 뿌리 글 1 + planner 한눈에 1
    assert len(w.replies_of("harness")) == 3
    text = w.root("harness")["text"]
    assert "#10" in text and "#11" in text and text.startswith("[작업상황] harness · 2026-10-09")
    assert "· 첫 보고" in w.replies_of("harness")[0]["text"].split("\n")[0]  # 머리표 뒤 «쉬운 제목 ·»


def test_t2_label_maps_and_missing_label_or_failed_lookup_go_to_other_visibly(tmp_path: Path, slack: FakeSlack, capsys):
    w = World(tmp_path, slack, {20: ["team:shared-harness"], 21: ["bug"], 23: ["team:ccu"]})
    w.send("#20", "b1")
    w.send("#20", "b2")
    assert w.fetches == [20]  # 두 번째는 캐시
    w.send("#21", "b3")
    assert w.replies_of("기타")[0]["text"].split("\n")[1] == "팀 라벨 없음"
    w.send("#22", "b4")  # 조회 실패
    assert "이슈 #22 라벨 조회 실패" in capsys.readouterr().err and len(w.replies_of("기타")) == 2
    w.send("#23", "b5")  # 위성 팀 라벨 = 기타 (라벨 없음 줄 없음)
    assert "팀 라벨 없음" not in w.replies_of("기타")[2]["text"]
    w.send("#22", "b6")
    assert w.fetches.count(22) == 2  # 실패는 캐시하지 않는다 → 다음 글에서 다시 조회


def test_t3_kst_0800_day_boundary(tmp_path: Path, slack: FakeSlack):
    clock = Clock(kst(2026, 10, 10, 7, 59))
    w = World(tmp_path, slack, {1: ["team:ops"]}, clock)
    w.send("#1", "c1")
    clock.t = kst(2026, 10, 10, 8, 0)
    w.send("#1", "c2")
    assert len(w.replies_of("ops", "2026-10-09")) == 1 and len(w.replies_of("ops", "2026-10-10")) == 1
    assert mt.day_of(kst(2026, 10, 10, 7, 59)) == "2026-10-09" and mt.day_of(kst(2026, 10, 10, 8, 0)) == "2026-10-10"


def test_t7_restart_reuses_todays_root(tmp_path: Path, slack: FakeSlack):
    w = World(tmp_path, slack, {1: ["team:cfo"]})
    w.send("#1", "d1")
    w.rebuild()  # 재시작 — 스레드 맵·원장·이슈 캐시 다시 읽기
    w.send("#1", "d2")
    assert len(slack.roots) == 2 and len(w.replies_of("cfo")) == 2
    assert w.fetches == [1]


def test_t8_planner_root_has_seven_team_lines_and_counts(tmp_path: Path, slack: FakeSlack):
    w = World(tmp_path, slack, {1: ["team:cfo"], 2: ["team:v65"]})
    w.send("#1", "e1", kind="opened", num=1)
    w.send("#1", "e2", kind="closed", num=1)
    w.send("#2", "e3", "v65 진행")
    text = w.root("planner")["text"]
    assert text.startswith("[작업상황] 오늘 메인 팀 7 한눈에 · 2026-10-09")
    rows = [ln for ln in text.split("\n") if ln.startswith("• ")]
    assert [r.split(" ")[1] for r in rows] == ["cfo", "harness", "issues", "feature", "ops", "loom", "v65", "기타"]
    assert "• cfo" in text and "(열린 0 · 닫힌 1)" in rows[0] and "v65 진행" in rows[6] and "(열린 1 · 닫힌 0)" in rows[6]


def _bucket(n: int, title: str) -> dict:
    evs = {f"e{i}": {"issue": i, "key": f"k{i}", "kind": "opened", "at": 1000.0 + i, "title": f"{title}{i}", "link": None} for i in range(1, n + 1)}
    return {"events": evs}


def test_t9_long_titles_fold_list_into_char_budget():
    from mirror_team_render import render_team

    out = render_team("기타", "2026-10-12", _bucket(60, "긴 제목 " * 14), "pk")
    lines = out.split("\n")
    shown = lines.index("이슈 목록")
    kept = len(lines) - shown - 3  # 이슈 목록 머리·접힘 줄·꼬리 제외
    assert len(out) <= 3500
    assert lines[-2] == f"… 외 {60 - kept}건 — 스레드 참고" and 0 < kept < 40


def test_t9_planner_root_also_fits_budget():
    from mirror_team import PLANNER
    from mirror_team_render import render_planner

    out = render_planner("2026-10-12", {PLANNER: _bucket(60, "긴 제목 " * 14)}, "pk")
    assert len(out) <= 3500 and out.split("\n")[-2].startswith("… 외 ")


def test_t9_short_titles_bytes_unchanged_and_cap_40_kept():
    from mirror_team_render import issue_line, issues, render_team

    b10 = _bucket(10, "짧은 제목")
    old = [*render_team("ops", "d", {"events": {}}, "pk").split("\n")[:2]]  # 머리 + 빈 글 안내
    out10 = render_team("ops", "d", b10, "pk").split("\n")
    assert out10[out10.index("이슈 목록") + 1:-1] == [issue_line(n, r) for n, r in issues(b10).items()] and old
    out50 = render_team("ops", "d", _bucket(50, "짧은 제목"), "pk").split("\n")
    assert out50[-2] == "… 외 10건 — 스레드 참고" and len(out50) - out50.index("이슈 목록") == 40 + 3


def test_t9_now_and_waiting_lines_kept_when_list_folds():
    from mirror_team_render import render_team

    b = _bucket(60, "긴 제목 " * 14)
    b["events"]["h1"] = {"issue": None, "key": "hk", "kind": "hil", "at": 2000.0, "title": "승인 필요한 결정", "link": None}
    out = render_team("기타", "d", b, "pk")
    assert "결정 기다림: 승인 필요한 결정" in out and "긴 제목" in out.split("이슈 목록")[0] and len(out) <= 3500


def _size(s: str) -> int:
    return len(s.encode("utf-8"))


def _bucket_with_others(total: int) -> dict:
    """목록 밖 본문(머리·지금 하는 일·결정 기다림·꼬리)이 정확히 total «바이트» + 이슈 1건 bucket."""
    from mirror_team_render import render_team

    b = _bucket(1, "가")
    h = {"issue": None, "key": "hk", "kind": "hil", "at": 2000.0, "title": "n", "what": "안건을 확인하고 있어요", "link": None}
    b["events"]["h"] = h
    base = _size(render_team("ops", "d", {"events": {"h": h}}, "pk"))
    h["title"] = "n" * (1 + total - base)
    return b


def test_t10_small_remaining_room_prefers_head_fold_then_fold_then_nothing():
    from mirror_team_render import _fold, render_team

    fold, head = _size(_fold(1)) + 1, _size("이슈 목록") + 1
    cases = [(fold - 1, ""), (fold, _fold(1) + "\n"), (head + fold - 1, _fold(1) + "\n"), (head + fold, "이슈 목록\n" + _fold(1) + "\n")]
    for room, expect in cases:
        out = render_team("ops", "d", _bucket_with_others(3500 - room), "pk")
        assert _size(out) <= 3500, (room, _size(out))
        assert out.endswith(expect + "(mirror · pk 시작)"), (room, out[-60:])
        assert ("이슈 목록" in out) == expect.startswith("이슈 목록")


def _korean_bucket(n_issues: int, n_hil: int = 0) -> dict:
    b = _bucket(n_issues, "한글 제목입니다 " * 6)
    for i in range(n_hil):
        b["events"][f"h{i}"] = {"issue": None, "key": f"h{i}", "kind": "hil", "at": 2000.0 + i, "title": "결정이 필요한 안건입니다 " * 3 + str(i), "what": "한글로 지금 하는 일을 적습니다 " * 3 + str(i), "link": None}
    return b


def test_t11_korean_list_fits_utf8_byte_budget():  # ⓐ
    from mirror_team_render import render_planner, render_team

    out = render_team("기타", "2026-10-12", _korean_bucket(40), "pk")
    assert _size(out) <= 3500 and "이슈 목록" in out
    from mirror_team import PLANNER

    assert _size(render_planner("2026-10-12", {PLANNER: _korean_bucket(40)}, "pk")) <= 3500


def test_t11_h1_ascii_fixture_still_passes():  # ⓑ
    from mirror_team_render import render_team

    b = _bucket(1, "a")
    b["events"]["h"] = {"issue": None, "key": "hk", "kind": "hil", "at": 2000.0, "title": "n" * 3300, "what": "x" * 10 + " status", "link": None}
    assert _size(render_team("ops", "d", b, "pk")) <= 3500


def test_t11_others_over_budget_fold_now_then_waiting():  # ⓒ
    from mirror_team_render import render_team

    out = render_team("ops", "d", _korean_bucket(3, n_hil=100), "pk")
    lines = out.split("\n")
    assert _size(out) <= 3500 and lines[0].startswith("[작업상황] ops") and lines[-1] == "(mirror · pk 시작)"
    assert any(ln.startswith("… 외 ") and ln.endswith("줄") for ln in lines)


def test_t11_cut_path_is_utf8_safe_visible_and_logged(capsys):  # ⓓ
    from mirror_team_render import render_team

    out = render_team("가" * 2000, "d", _korean_bucket(2), "pk")
    out.encode("utf-8").decode("utf-8")
    lines = out.split("\n")
    assert _size(out) <= 3500 and lines[-2] == "…(뿌리 글 예산 초과 — 접힘)" and lines[-1] == "(mirror · pk 시작)"
    assert capsys.readouterr().err.count("ERROR") == 1


def test_t11_mutation_len_instead_of_bytes_fails_korean_budget(monkeypatch):  # ⓔ
    import mirror_team_render as rd

    monkeypatch.setattr(rd, "_size", len)
    assert _size(rd.render_team("기타", "2026-10-12", _korean_bucket(40), "pk")) > 3500
