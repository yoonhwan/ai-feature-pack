"""팀 뿌리 글 «이슈 목록»·결정 기다림·갱신 실패 — T4 열림·진행·닫힘 PR·sha · T5 결정 요청 따로 + 기다림 줄 · T5a 같은 이슈 질문 2 · T6 chat.update 실패 (판정 623)."""
from pathlib import Path

import pytest
from _slack_fakes import FakeSlack
from _team_fakes import Clock, World, kst, lib, tr


@pytest.fixture
def slack():
    s = FakeSlack()
    yield s
    s.srv.shutdown()


def test_t4_issue_list_shows_opened_progress_and_closed_pr_with_sha(tmp_path: Path, slack: FakeSlack):
    clock = Clock(kst(2026, 10, 9, 9, 0))
    w = World(tmp_path, slack, {20: ["team:harness"]}, clock)
    w.send("#20", "g1", "새 기능", kind="opened", num=20)
    clock.t = kst(2026, 10, 9, 9, 30)
    w.send("#20", "g2", "절반 진행")
    clock.t = kst(2026, 10, 9, 10, 0)
    w.send("#20", "g3", "거의 끝")
    assert "#20 새 기능 — 열림 09:00 · 진행 2 · 진행 중" in w.root("harness")["text"]
    clock.t = kst(2026, 10, 9, 11, 0)
    w.send("#20", "g4", "병합", kind="merged", num=20, sha="abcdef0123456789")
    assert "#20 새 기능 — 열림 09:00 · 진행 2 · 닫힘 PR #20 abcdef0 11:00" in w.root("harness")["text"]
    clock.t = kst(2026, 10, 9, 11, 5)
    w.send("#20", "g5", "병합", kind="merged", num=20, sha=None)  # sha 조회 실패한 글도 화면에는 사유가 보인다
    assert "sha 확인 불가" in w.root("harness")["text"]


def test_t5_hil_question_stays_on_issue_root_and_team_root_lists_it_as_waiting(tmp_path: Path, slack: FakeSlack):
    w = World(tmp_path, slack, {30: ["team:harness"]})
    q = {"key": "#30", "seat": "src#1", "what": "어느 쪽?", "options": []}
    w.send("#30", "h1", "어느 쪽으로 갈까요", question=q)
    issue_root = next(m for m in slack.roots if m["text"].startswith("[작업상황] #30 시작"))
    assert len(slack.replies(issue_root)) == 1 and w.replies_of("harness") == []  # 질문 카드 = 원래 키 스레드 (오빠 답글 라우팅 보존)
    text = w.root("harness")["text"]
    assert "결정 기다림: 어느 쪽으로 갈까요 https://fake.slack.com/archives/C1/p" in text
    w.send("#30", "h2", "답대로 진행")  # 같은 키의 일반 보고 = 기다림 해소 · 팀 스레드에 게시
    assert "결정 기다림" not in w.root("harness")["text"] and len(w.replies_of("harness")) == 1


def test_t5a_two_questions_on_one_issue_share_one_issue_root(tmp_path: Path, slack: FakeSlack):
    w = World(tmp_path, slack, {31: ["team:harness"]})
    q = {"key": "#31", "seat": "src#1", "what": "질문", "options": []}
    w.send("#31", "i1", "질문 하나", question=q)
    w.send("#31", "i2", "질문 둘", question=q)
    issue_roots = [m for m in slack.roots if m["text"].startswith("[작업상황] #31 시작")]
    assert len(issue_roots) == 1 and len(slack.replies(issue_roots[0])) == 2


def test_t6_chat_update_failure_is_loud_tails_next_reply_and_heals(tmp_path: Path, slack: FakeSlack, monkeypatch, capsys):
    w = World(tmp_path, slack, {40: ["team:ops"]})
    real, broken = lib.api_call, {"on": True}

    def flaky(base, token, method, params, **kw):
        if method == "chat.update" and broken["on"]:
            raise lib.MirrorError("chat.update ok=false: ratelimited")
        return real(base, token, method, params, **kw)

    monkeypatch.setattr(lib, "api_call", flaky)
    w.send("#40", "j1", "하나")
    assert "chat.update 실패" in capsys.readouterr().err and w.state()["roots"]["team:ops:2026-10-09"]["fail"] is True
    broken["on"] = False
    w.send("#40", "j2", "둘")
    assert w.replies_of("ops")[1]["text"].endswith(tr.FAIL_TAIL) and not w.replies_of("ops")[0]["text"].endswith(tr.FAIL_TAIL)
    assert "진행 2" in w.root("ops")["text"] and w.state()["roots"]["team:ops:2026-10-09"]["fail"] is False  # 다음 성공 렌더가 통째로 맞춤
    w.send("#40", "j3", "셋")
    assert not w.replies_of("ops")[2]["text"].endswith(tr.FAIL_TAIL)



def test_now_line_strips_index_tokens_instead_of_skipping_the_newest_summary(tmp_path: Path, slack: FakeSlack):
    w = World(tmp_path, slack, {50: ["team:ops"]})
    w.send("#50", "p1", "앞선 쉬운 문장입니다")
    w.send("#50", "p2", "판정 609 쉬운 판을 재현하고 있어요")
    lines = w.root("ops")["text"].split("\n")
    assert lines[1] == "쉬운 판을 재현하고 있어요" and lines[2] == "앞선 쉬운 문장입니다"  # 최신 글이 번호를 걷은 채 맨 위
    assert not any("판정 609" in ln for ln in lines[:3])


def test_now_line_skips_a_summary_only_when_too_short_after_stripping(tmp_path: Path, slack: FakeSlack):
    w = World(tmp_path, slack, {51: ["team:ops"]})
    w.send("#51", "q1", "남는 문장이 충분해요")
    w.send("#51", "q2", "판정 609 #7 R12")  # 걷으면 빈 글 → 건너뜀
    assert w.root("ops")["text"].split("\n")[1] == "남는 문장이 충분해요"
