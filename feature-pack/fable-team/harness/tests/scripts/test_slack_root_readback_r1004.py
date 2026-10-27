"""r1004 슬랙 뿌리 글 «되읽기 가드» — 예외 없는 판 (가짜 Slack·가짜 mbox · 실 Slack·실 명부 0).

계약 대응표(카드 §계약↔시험) 를 그대로 칸으로 옮겼다.
  C1 ⓐ 위반 3꼴 = 지움 + rc1 + 쪽지 1 · 골 표·각주 표·머리 줄도 예외 없이 위반
  C2 ⓑ 정상 글 4칸 = 그대로 남는다(슬랙 링크 파이프 · «…» 1·2개 통과)
  C3 ⓒ 되읽기 실패 · 삭제 실패 = 조용한 통과 0 · ERROR 사건당 1줄 + 쪽지 1 · 삭제 0/글 남음
  C4 ⓓ 게시 자리 7곳 모두 가드 호출 — 자리마다 호출을 지우면(변이) 그 글은 안 지워진다
  C5 ⓔ 쪽지 = planner · 사건 키당 1통(반복·동시 포함) · 보드 장부에서 지운 글 뺌
실행: python3 -m pytest tests/scripts/test_slack_root_readback_r1004.py -q
"""
import json
import os
import threading
import urllib.request
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from types import SimpleNamespace
from urllib.parse import parse_qs, urlparse

import pytest

ROOT = Path(__file__).resolve().parents[3]
BIN = ROOT / "harness" / "bin"
KITBIN = ROOT / "harness" / "kit" / "fable-team" / "bin"
KIT = ROOT / "harness" / "kit" / "slack-mirror"
import sys  # noqa: E402

sys.path[:0] = [str(KIT), str(KITBIN), str(BIN)]
os.environ.setdefault("FT_HERMES_SCRIPTS", str(KIT))  # 설치본(~/.hermes/scripts) 아닌 키트판을 부른다(ft_news_publish 가 설치 폴더를 sys.path 앞에 넣는다)

import ft_news_publish as np  # noqa: E402
import magazine_doc as md  # noqa: E402
import root_readback_guard as g  # noqa: E402
import thread_ledger as lg  # noqa: E402
import thread_post_update as tpu  # noqa: E402
from _magazine_fakes import FakeMagazineSlack  # noqa: E402
from _magazine_ledger import argv as mag_argv, make_env  # noqa: E402
from magazine_slack import Target  # noqa: E402
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541

GOOD = "결론 — 매거진 발행을 마쳤어요\n오빠 할 일: 없음\n바뀐 것: 3줄\n자세히 = 스레드의 HTML"
TABLE_TEXT = "결론\n| 팀 | 상태 |\n|---|------|\n| kk | 진행 |"
PIPE_TEXT = "결론: 개발이 진행 중입니다.\n팀 | 상태\n--- | ---\n개발 | 진행"
DOTS_TEXT = "결론\n본문 … … …"
LIST_FIRST = "1. 확인할 일\n결론은 둘째 줄"
HEAD_FIRST = "## 오늘의 팀 상태\n결론은 둘째 줄"
LINKED = "결론 — <https://x.slack.com/a|팀 | 상태> 링크 하나\n둘째 줄"
FOOTNOTE_TAIL = GOOD + "\n| 번호 | 뜻 |\n|---|---|\n| 1 | 판정 |"
GOAL_BLOCK = "결론\n★골 표 A6 뉴스·매거진 정상화★\n| 축 | 값 |\n|---|---|\n| A6 | 1 |\n★/골 표★"
DAY = "2026-10-27"
NOW = datetime(2026, 10, 27, 9, 15)


class FakeSlack:
    """postMessage·chat.update·chat.delete·history(inclusive)·파일 업로드 3단. fail_read·fail_delete 로 반례를 만든다."""

    def __init__(self) -> None:
        self.msgs: list[dict] = []
        self.fail_read = False
        self.fail_delete = False
        self.deleted: list[str] = []
        self.history_calls = 0
        self.hide_uploads = False  # 업로드는 되는데 히스토리 조회가 0(글 번호를 못 얻는 자리 · ⓒ)
        self._seq = 0
        outer = self

        class H(BaseHTTPRequestHandler):
            def log_message(self, format: str, *args: object) -> None:  # noqa: A002
                pass

            def _reply(self, body: dict) -> None:
                raw = json.dumps(body).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

            def do_POST(self) -> None:
                raw = self.rfile.read(int(self.headers["Content-Length"]))
                if self.path.startswith("/upload/"):
                    return self._reply({"ok": True})
                body = json.loads(raw)
                if self.path.endswith("chat.delete"):
                    if outer.fail_delete:
                        return self._reply({"ok": False, "error": "cant_delete_message"})
                    outer.msgs = [m for m in outer.msgs if m["ts"] != body["ts"]]
                    outer.deleted.append(body["ts"])
                    return self._reply({"ok": True})
                if self.path.endswith("chat.update"):
                    for m in outer.msgs:
                        if m["ts"] == body["ts"]:
                            m["text"] = body["text"]
                    return self._reply({"ok": True, "ts": body["ts"]})
                outer._seq += 1
                ts = f"{1_900_000_000 + outer._seq}.000000"
                outer.msgs.append({"ts": ts, "text": body["text"], "bot_id": "B1", "thread_ts": body.get("thread_ts", "")})
                self._reply({"ok": True, "ts": ts})

            def do_GET(self) -> None:
                u = urlparse(self.path)
                q = {k: v[0] for k, v in parse_qs(u.query).items()}
                if u.path.endswith("conversations.history"):
                    outer.history_calls += 1
                    if outer.fail_read:
                        return self._reply({"ok": False, "error": "missing_scope"})
                    lo, hi = float(q["oldest"]), float(q.get("latest") or "9" * 12)
                    inc = q.get("inclusive") == "true"
                    got = [m for m in outer.msgs if not m["thread_ts"] and (lo <= float(m["ts"]) if inc else lo < float(m["ts"])) and float(m["ts"]) <= hi]
                    return self._reply({"ok": True, "messages": got})
                if u.path.endswith("files.getUploadURLExternal"):
                    outer._seq += 100
                    return self._reply({"ok": True, "upload_url": f"{outer.base}/upload/F{outer._seq}", "file_id": f"F{outer._seq}"})
                if u.path.endswith("files.completeUploadExternal"):
                    outer._seq += 1
                    ts = f"{1_900_000_000 + outer._seq}.000000"
                    if not outer.hide_uploads:
                        outer.msgs.append({"ts": ts, "text": q.get("initial_comment", ""), "bot_id": "B1", "thread_ts": ""})
                    return self._reply({"ok": True})
                return self._reply({"ok": True, "permalink": f"https://fake.slack/archives/{q.get('channel', 'C1')}/p1"})

        self.srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        self.base = f"http://127.0.0.1:{self.srv.server_port}"

    def post(self, text: str) -> str:
        req = urllib.request.Request(f"{self.base}/chat.postMessage", data=json.dumps({"channel": "C1", "text": text}).encode(),
                                     headers={"Content-Type": "application/json", "Authorization": "Bearer T"})
        with urllib.request.urlopen(req, timeout=7) as resp:
            return str(json.loads(resp.read())["ts"])

    def texts(self) -> list[str]:
        return [m["text"] for m in self.msgs]


@pytest.fixture()
def mail(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """쪽지함·표식·수신 좌석을 임시 폴더로 — 실 명부·실 쪽지함 0. 반환 = 쪽지 기록 파일."""
    log = tmp_path / "mbox.log"
    mbox = tmp_path / "mbox.sh"
    mbox.write_text(f'#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> {log}\n', encoding="utf-8")
    (tmp_path / ".fable-team").mkdir()
    monkeypatch.setenv("FT_ROOT", str(tmp_path))
    monkeypatch.setenv("FT_READBACK_MBOX", str(mbox))
    monkeypatch.setenv("FT_READBACK_STATE", str(tmp_path / "state"))
    monkeypatch.setenv("FT_READBACK_TO", "byz-harness-master-fake#0")
    return log


def _sends(log: Path) -> list[str]:
    return log.read_text(encoding="utf-8").splitlines() if log.exists() else []


# ── C1 ⓐ 위반 3꼴 + 예외 0 ───────────────────────────────────

def test_c1_three_shapes_and_mail_and_rc(mail: Path) -> None:
    """위반 꼴마다 = 지움 · 쪽지 1통 · 글 없음."""
    for text in (TABLE_TEXT, PIPE_TEXT, DOTS_TEXT, LIST_FIRST, HEAD_FIRST):
        slack = FakeSlack()
        ts = slack.post(text)
        with pytest.raises(g.ReadbackError):
            g.readback(g.Post(slack.base, "T", "C1", ts, f"magazine:{DAY}"))
        assert slack.deleted == [ts] and slack.msgs == [], text
    assert len(_sends(mail)) == 1  # 같은 사건 키 = 1통


def test_c1_goal_table_and_footnote_table_are_violations(mail: Path) -> None:
    """예외 0 — 골 표 블록·맨 끝 각주 표도 위반(옛 판의 두 예외를 지웠다)."""
    assert "표 줄" in (g.check(GOAL_BLOCK) or "")
    assert "표 줄" in (g.check(FOOTNOTE_TAIL) or "")


def test_c1_heading_rules(mail: Path) -> None:
    """`##` 이하 제목 = 결론 아님 · 글자 없는 제목 표지 = 결론 아님 · `# 뉴스 — …` 제품 머리 줄은 결론 자리(뉴스 본문 계약)."""
    assert g.check("## 오늘의 팀 상태\n결론은 둘째 줄") == "첫 줄이 결론 문장이 아님"
    assert g.check("#\n결론") == "첫 줄이 결론 문장이 아님"
    assert g.check("# 뉴스 — 2026-10-27 09:15\n- 오빠 할 일: 없음") is None


def test_c1_blank_first_line_is_violation(mail: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """ⓐ 새 칸 — 앞 빈 줄을 건너뛰지 않는다: «첫 줄» = 원문 첫 줄 그대로."""
    assert g.check("\n결론: 발행을 마쳤어요") == "첫 줄이 결론 문장이 아님"
    assert g.check("   \n결론: 발행을 마쳤어요") is not None
    slack = FakeSlack()
    _news_target(monkeypatch, slack, tmp_path)
    assert np.publish_line("\n결론: 발행을 마쳤어요", NOW) == 1  # 지움 + rc1
    assert slack.deleted and slack.msgs == []
    assert len(_sends(mail)) == 1  # 쪽지 1통
    assert np.publish_line("결론: 발행을 마쳤어요\n둘째 줄", NOW) == 0  # 빈 줄이 없으면 그대로 통과


def test_c1_empty_text_is_violation() -> None:
    assert g.check("   \n\n") == "첫 줄이 결론 문장이 아님"


# ── C2 ⓑ 정상 글은 그대로 ───────────────────────────────────

def test_c2_normal_texts_pass(mail: Path) -> None:
    for text in (GOOD, LINKED, "결론입니다 …", "결론\n본문 … …", "결론 — <https://x/a|가> · <https://x/b|나>"):
        assert g.check(text) is None, text
    slack = FakeSlack()
    ts = slack.post(GOOD)
    g.readback(g.Post(slack.base, "T", "C1", ts, f"magazine:{DAY}"))
    assert slack.deleted == [] and slack.texts() == [GOOD]
    assert _sends(mail) == []


def test_c2_link_pipe_is_not_a_table_row() -> None:
    assert g.check(LINKED) is None


# ── C3 ⓒ 실패 = 조용한 통과 0 ───────────────────────────────

def test_c3_read_failure_deletes_nothing_and_mails_once(mail: Path) -> None:
    slack = FakeSlack()
    ts = slack.post(TABLE_TEXT)
    slack.fail_read = True
    with pytest.raises(g.ReadbackError):
        g.readback(g.Post(slack.base, "T", "C1", ts, f"news:{DAY}"))
    assert slack.deleted == [] and slack.texts() == [TABLE_TEXT]
    assert len(_sends(mail)) == 1 and "[긴급]" in _sends(mail)[0]


def test_c3_delete_failure_keeps_text_and_mails(mail: Path) -> None:
    slack = FakeSlack()
    ts = slack.post(TABLE_TEXT)
    slack.fail_delete = True
    with pytest.raises(g.ReadbackError):
        g.readback(g.Post(slack.base, "T", "C1", ts, f"board:{DAY}"))
    assert slack.texts() == [TABLE_TEXT] and slack.deleted == []
    assert len(_sends(mail)) == 1


def test_c3_one_error_line_per_call_site(mail: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture) -> None:
    """부르는 쪽이 ERROR 1줄 — 가드는 로그를 남기지 않는다(사건당 2줄 금지)."""
    slack = FakeSlack()
    _news_target(monkeypatch, slack, tmp_path)
    slack.fail_read = True
    with caplog.at_level("WARNING"):
        assert np.publish_line(GOOD, NOW) == 1
    assert len([r for r in caplog.records if r.levelname == "ERROR"]) == 1
    assert len(_sends(mail)) == 1


def test_c3_publish_html_without_ts_is_a_readback_failure(mail: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture) -> None:
    """ⓒ 새 칸 — 게시 뒤 글 번호 조회가 [] 면 되읽기 실패: 조용한 성공 0 · ERROR 1줄 · 쪽지 1 · rc≠0."""
    slack = FakeSlack()
    slack.hide_uploads = True  # 올렸는데 조회 0
    html = tmp_path / "m.html"
    html.write_text("<html></html>", encoding="utf-8")
    _news_target(monkeypatch, slack, tmp_path)
    with caplog.at_level("WARNING"):
        rc, receipt = np.publish_html(html, GOOD, NOW)  # type: ignore[arg-type]
    assert rc != 0 and receipt is None
    assert len([r for r in caplog.records if r.levelname == "ERROR"]) == 1
    assert len(_sends(mail)) == 1 and "[긴급]" in _sends(mail)[0]


# ── C5 ⓔ 쪽지 = 사건 키당 1통 · 장부 ───────────────────────

def test_c5_same_event_one_mail_across_error_kinds(mail: Path) -> None:
    slack = FakeSlack()
    ts = slack.post(TABLE_TEXT)
    slack.fail_read = True
    with pytest.raises(g.ReadbackError):
        g.readback(g.Post(slack.base, "T", "C1", ts, f"sheet:{DAY}"))
    slack.fail_read, slack.fail_delete = False, True
    with pytest.raises(g.ReadbackError):
        g.readback(g.Post(slack.base, "T", "C1", ts, f"sheet:{DAY}"))
    slack.fail_delete = False
    with pytest.raises(g.ReadbackError):
        g.readback(g.Post(slack.base, "T", "C1", ts, f"sheet:{DAY}"))
    assert len(_sends(mail)) == 1


def test_c5_concurrent_same_event_one_mail(mail: Path) -> None:
    slack = FakeSlack()
    ts = slack.post(TABLE_TEXT)
    slack.fail_delete = True

    def hit() -> None:
        with pytest.raises(g.ReadbackError):
            g.readback(g.Post(slack.base, "T", "C1", ts, f"race:{DAY}"))

    threads = [threading.Thread(target=hit) for _ in range(4)]
    [t.start() for t in threads]
    [t.join() for t in threads]
    assert len(_sends(mail)) == 1


def test_c5_mail_goes_to_hil_route_from_seats(mail: Path, monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.delenv("FT_READBACK_TO")
    (tmp_path / ".fable-team" / "seats.json").write_text(json.dumps({"_hil_route": "planner-fake#9", "_master": "m#1"}), encoding="utf-8")
    slack = FakeSlack()
    ts = slack.post(TABLE_TEXT)
    with pytest.raises(g.ReadbackError):
        g.readback(g.Post(slack.base, "T", "C1", ts, f"magazine:{DAY}"))
    assert "planner-fake#9" in _sends(mail)[0]


def test_c5_board_drops_deleted_root_from_ledger(mail: Path, tmp_path: Path) -> None:
    slack = FakeSlack()
    ledger = tmp_path / "board.json"
    lg.init(ledger)
    body = tmp_path / "body.txt"
    args = SimpleNamespace(key=f"board:{DAY}", text_file=str(body), channel="C1", ledger=str(ledger), reply=None)
    target = lambda a: Target(slack.base, "T", "C1", "")  # noqa: E731
    body.write_text(GOOD, encoding="utf-8")
    assert tpu.cmd_update(args, target) == 0
    first = lg.get(ledger, f"board:{DAY}")["root_ts"]  # type: ignore[index]
    body.write_text(TABLE_TEXT, encoding="utf-8")
    with pytest.raises(g.ReadbackError):
        tpu.cmd_update(args, target)
    assert lg.get(ledger, f"board:{DAY}") is None  # 지운 글 번호를 장부에 남기지 않는다
    assert first in slack.deleted
    body.write_text(GOOD, encoding="utf-8")
    assert tpu.cmd_update(args, target) == 0  # 다음 갱신 = 새 글(장부에 지운 번호 0)
    assert lg.get(ledger, f"board:{DAY}")["root_ts"] != first  # type: ignore[index]


# ── C4 ⓓ 게시 자리 7곳 ─────────────────────────────────────

def _news_target(monkeypatch: pytest.MonkeyPatch, slack: FakeSlack, tmp: Path) -> None:
    (tmp / ".fable-team").mkdir(parents=True, exist_ok=True)
    monkeypatch.setenv("FT_NEWS_DIR", str(tmp / "news"))
    (tmp / "news").mkdir(exist_ok=True)
    monkeypatch.setattr(np, "_target", lambda day, polished: Target(slack.base, "T", "C1", ""))


def test_c4_news_post_new_deletes_violation(mail: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    slack = FakeSlack()
    _news_target(monkeypatch, slack, tmp_path)
    with pytest.raises(g.ReadbackError):
        np._post_new(DAY, tmp_path / "x.md", TABLE_TEXT)  # type: ignore[arg-type]
    assert slack.deleted and slack.msgs == []
    assert len(_sends(mail)) == 1


def test_c4_news_adopted_post_is_checked(mail: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    slack = FakeSlack()
    _news_target(monkeypatch, slack, tmp_path)
    slack.post(TABLE_TEXT)  # 이미 올라가 있던 위반 글 — «이미 올라감» 으로 통과시키지 않는다
    with pytest.raises(g.ReadbackError):
        np._post_new(DAY, tmp_path / "x.md", TABLE_TEXT)  # type: ignore[arg-type]
    assert slack.deleted and slack.msgs == []


def test_c4_publish_html_deletes_violation(mail: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    slack = FakeSlack()
    html = tmp_path / "m.html"
    html.write_text("<html></html>", encoding="utf-8")
    _news_target(monkeypatch, slack, tmp_path)
    rc, receipt = np.publish_html(html, "결론\n| 팀 | 상태 |\n|---|---|", NOW)  # type: ignore[arg-type]
    assert rc == 1 and receipt is None and slack.deleted and slack.msgs == []
    assert len(_sends(mail)) == 1


def test_c4_publish_line_deletes_violation(mail: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    slack = FakeSlack()
    _news_target(monkeypatch, slack, tmp_path)
    assert np.publish_line(DOTS_TEXT, NOW) == 1
    assert slack.deleted and slack.msgs == []


def test_c4_magazine_publish_deletes_violation(mail: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """매거진 뿌리 글 자리 — 표 꼴 뿌리 글이면 지우고 발행 실패(rc1 · 조용한 성공 0)."""
    bag = make_env(tmp_path)
    slack = FakeMagazineSlack()
    monkeypatch.setattr(md, "root_text", lambda date, conclusion="": TABLE_TEXT)
    assert md.main(mag_argv(bag, "--publish", slack)) == 1
    assert slack.roots == []  # 지운 글은 남지 않는다
    assert len(_sends(mail)) == 1


def test_c4_board_create_and_update_delete_violation(mail: Path, tmp_path: Path) -> None:
    slack = FakeSlack()
    ledger = tmp_path / "board.json"
    lg.init(ledger)
    body = tmp_path / "body.txt"
    body.write_text(TABLE_TEXT, encoding="utf-8")
    args = SimpleNamespace(key=f"board:{DAY}", text_file=str(body), channel="C1", ledger=str(ledger), reply=None)
    target = lambda a: Target(slack.base, "T", "C1", "")  # noqa: E731
    with pytest.raises(g.ReadbackError):
        tpu.cmd_update(args, target)  # 생성 자리
    assert slack.deleted and slack.msgs == []
    assert lg.get(ledger, f"board:{DAY}") is None  # 만든 글도 지웠으면 장부에 안 남긴다


# ── C4 ⓓ 변이 = 자리마다 호출을 지우면 그 글은 안 지워진다 ─────

def test_c4_mutation_each_site_is_load_bearing(mail: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """자리마다 readback 을 «아무것도 안 함» 으로 바꾼다 → 위반 글이 살아남는다(= 그 자리 시험이 FAIL 한다)."""
    noop = lambda *a, **k: None  # noqa: E731
    html = tmp_path / "m.html"
    html.write_text("<html></html>", encoding="utf-8")

    slack = FakeSlack()
    _news_target(monkeypatch, slack, tmp_path)
    monkeypatch.setattr(np, "readback", noop)
    np._post_new(DAY, tmp_path / "x.md", TABLE_TEXT)  # type: ignore[arg-type]
    assert slack.texts() == [TABLE_TEXT], "뉴스 새 글 자리 변이"
    np._post_new(DAY, tmp_path / "x.md", TABLE_TEXT)  # type: ignore[arg-type]  채택 자리도 같은 호출 하나
    assert len(slack.texts()) == 1, "뉴스 채택 자리 변이"
    assert np.publish_html(html, TABLE_TEXT, NOW)[0] == 0, "뉴스 HTML 자리 변이"
    assert any("|" in text for text in slack.texts())
    assert np.publish_line(DOTS_TEXT, NOW) == 0, "뉴스 한 줄 자리 변이"
    assert DOTS_TEXT in slack.texts()
    assert _sends(mail) == []

    slack = FakeSlack()
    ledger = tmp_path / "board2.json"
    lg.init(ledger)
    body = tmp_path / "body2.txt"
    body.write_text(TABLE_TEXT, encoding="utf-8")
    args = SimpleNamespace(key=f"board:{DAY}", text_file=str(body), channel="C1", ledger=str(ledger), reply=None)
    target = lambda a: Target(slack.base, "T", "C1", "")  # noqa: E731
    monkeypatch.setattr(tpu, "readback", noop)
    assert tpu.cmd_update(args, target) == 0, "보드 생성 자리 변이"
    assert slack.texts() == [TABLE_TEXT]
    assert tpu.cmd_update(args, target) == 0, "보드 갱신 자리 변이"
    assert slack.texts() == [TABLE_TEXT]

    bag = make_env(tmp_path)
    mag = FakeMagazineSlack()
    monkeypatch.setattr(md, "root_text", lambda date, conclusion="": TABLE_TEXT)
    monkeypatch.setattr(md, "readback", noop)
    assert md.main(mag_argv(bag, "--publish", mag)) == 0, "매거진 자리 변이"
    assert [m["text"] for m in mag.roots] == [TABLE_TEXT]
    assert _sends(mail) == []


def test_mutation_blank_first_line_rule_is_load_bearing(mail: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """변이 — «앞 빈 줄을 버리는» 옛 판정으로 되돌리면 ⓐ 새 칸은 FAIL(발행이 통과한다)."""
    slack = FakeSlack()
    _news_target(monkeypatch, slack, tmp_path)
    real = g.check
    monkeypatch.setattr(g, "check", lambda text: real(text.lstrip("\n")))  # 되돌린 판
    assert np.publish_line("\n결론: 발행을 마쳤어요", NOW) == 0
    assert slack.deleted == [] and _sends(mail) == []


def test_mutation_posted_ts_fix_is_load_bearing(mail: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """변이 — 글 번호 0 을 그냥 넘기면(옛 판) ⓒ 새 칸은 FAIL(rc0 · 쪽지 0)."""
    slack = FakeSlack()
    slack.hide_uploads = True
    html = tmp_path / "m.html"
    html.write_text("<html></html>", encoding="utf-8")
    _news_target(monkeypatch, slack, tmp_path)
    monkeypatch.setattr(np, "_posted_ts", lambda t, ts, day: ts)  # 되돌린 판(글 번호 0 을 그냥 넘긴다)
    monkeypatch.setattr(np, "readback", lambda *a, **k: None)  # 되돌린 판(글 번호가 없으면 가드를 건너뛴다)
    rc, receipt = np.publish_html(html, GOOD, NOW)  # type: ignore[arg-type]
    assert rc == 0 and receipt is not None and receipt["ts"] == "" and _sends(mail) == []
