"""뉴스 발행 — 같은 판 재발행 0 · 다른 판은 채널 새 글 1 (R118b · 판정 1430). 매거진 연결·무초안 감시 시험은 R125 로 test_ft_news_ledger.py 로 옮김(원본=원장).

가짜 Slack 서버(기존 byz_thread_post 시험과 같은 방식: --slack-base) · 가짜 mbox · 실 Slack/실 mbox 0.
실행: python3 -m pytest tests/scripts/test_ft_news_publish.py -q
"""
import json
import socket
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import pytest

ROOT = Path(__file__).resolve().parents[3]
BIN = ROOT / "harness" / "bin"
KIT = ROOT / "harness" / "kit" / "slack-mirror"
sys.path.insert(0, str(BIN))
sys.path.insert(0, str(KIT))

import ft_news_publish as np  # noqa: E402
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

DAY = "2026-10-13"
PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"  # ft-tick.sh 와 같은 순서 — /usr/bin/python3 는 3.9 라 이 키트가 못 돈다
BODY_A = "# 뉴스 — 2026-10-13 09:10\n\n## 오빠가 할 일\n- 없음\n\n## 진행\n- 초안 생성기 랜딩\n"
BODY_A_LATER = BODY_A.replace("09:10", "09:40")
BODY_B = BODY_A.replace("초안 생성기 랜딩", "초안 생성기 랜딩 · 발행 연결 진행")


class FakeSlack:
    """chat.postMessage / chat.update + 조회(history·replies) 대역. drop_next_post = 글은 접수했는데 응답이 유실(C1 반례)."""

    def __init__(self) -> None:
        self.posts: list[dict] = []
        self.updates: list[dict] = []
        self.msgs: list[dict] = []
        self.drop_next_post = False
        self.history_has_replies = False  # 실제 Slack 은 답글을 history 에 안 주지만 broadcast 답글은 올 수 있다 — 후보 조건 시험용
        outer = self

        class H(BaseHTTPRequestHandler):
            def log_message(self, format: str, *args: object) -> None:  # noqa: A002
                pass

            def _reply(self, out: dict) -> None:
                raw = json.dumps(out).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

            def do_POST(self) -> None:
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                if self.path.endswith("chat.delete"):  # r1004 되읽기 가드
                    outer.msgs = [m for m in outer.msgs if m["ts"] != body["ts"]]
                    return self._reply({"ok": True})
                if self.path.endswith("chat.update"):
                    outer.updates.append(body)
                    for m in outer.msgs:
                        if m["ts"] == body["ts"]:
                            m["text"] = body["text"]
                    return self._reply({"ok": True})
                outer.posts.append(body)
                ts = f"{1_900_000_000 + len(outer.posts)}.000000"
                outer.msgs.append({"ts": ts, "text": body["text"], "bot_id": "B1", "thread_ts": body.get("thread_ts", "")})
                if outer.drop_next_post:
                    outer.drop_next_post = False
                    self.connection.shutdown(socket.SHUT_RDWR)
                    return
                self._reply({"ok": True, "ts": ts})

            def do_GET(self) -> None:
                u = urlparse(self.path)
                q = {k: v[0] for k, v in parse_qs(u.query).items()}
                if u.path.endswith("conversations.history"):
                    lo, hi = float(q["oldest"]), float(q.get("latest") or "9" * 12)
                    inc = q.get("inclusive") == "true"  # r1004 되읽기가 «그 글 하나»(oldest=latest=ts · inclusive)를 묻는다
                    roots = [m for m in outer.msgs if (outer.history_has_replies or m["thread_ts"] in ("", m["ts"]))
                             and (lo <= float(m["ts"]) if inc else lo < float(m["ts"])) and float(m["ts"]) <= hi]
                    return self._reply({"ok": True, "messages": list(reversed(roots))})
                if u.path.endswith("conversations.replies"):
                    return self._reply({"ok": True, "messages": [m for m in outer.msgs if m["ts"] == q["ts"] or m["thread_ts"] == q["ts"]]})
                self.send_response(404)
                self.end_headers()

        self.srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        self.base = f"http://127.0.0.1:{self.srv.server_port}"

    def calls(self) -> int:
        return len(self.posts) + len(self.updates)

    def replies(self) -> list[str]:
        return [p["text"] for p in self.posts if p.get("thread_ts")]


@pytest.fixture
def slack():
    s = FakeSlack()
    yield s
    s.srv.shutdown()


@pytest.fixture
def env(tmp_path, slack, monkeypatch):
    news = tmp_path / "design" / "planner" / "news"
    news.mkdir(parents=True)
    (tmp_path / ".fable-team").mkdir()
    (tmp_path / ".fable-team" / "seats-planner.json").write_text(json.dumps({"_master": "planner#9"}), encoding="utf-8")
    (tmp_path / "tok").write_text("YOONHWAN_BOT_TOKEN=xoxb-fake\n", encoding="utf-8")
    monkeypatch.setenv("FT_ROOT", str(tmp_path))
    monkeypatch.setenv("FT_NEWS_DIR", str(news))
    monkeypatch.setenv("FT_THREAD_POST", str(KIT / "byz_thread_post.py"))
    monkeypatch.setenv("FT_NEWS_POST_ARGS", f"--slack-base {slack.base} --token-file {tmp_path / 'tok'} --channel C1 --ledger {tmp_path / 'threads.json'}")
    (tmp_path / "threads.json").write_text("{}", encoding="utf-8")
    monkeypatch.setenv("FT_NEWS_NOW", f"{DAY} 09:15")
    return tmp_path, news


def polished(news: Path, stamp: str, body: str) -> Path:
    p = news / f"POLISHED-{stamp}.md"
    p.write_text(body, encoding="utf-8")
    return p


def draft(news: Path, stamp: str) -> Path:
    p = news / f"DRAFT-{stamp}.md"
    p.write_text("# 뉴스 초안\n", encoding="utf-8")
    return p


def records(tmp: Path) -> list[str]:
    f = tmp / ".fable-team" / "state" / "news-publish" / "processed.tsv"
    return f.read_text(encoding="utf-8").splitlines() if f.exists() else []


# ── ① 발행: 바뀐 것만 ─────────────────────────────────────────────

def test_norm_drops_only_the_head_clock():
    assert np.norm(BODY_A) == np.norm(BODY_A_LATER)
    assert np.norm(BODY_A) != np.norm(BODY_B)


def test_same_body_head_clock_only_and_rerun_publish_nothing_more(env, slack):
    tmp, news = env
    draft(news, "20261013-0900")
    assert np.main(["publish", str(polished(news, "20261013-0910", BODY_A))]) == 0
    assert (len(slack.posts), len(slack.updates), slack.replies()) == (1, 0, [])  # 날짜 첫 발행 = 뿌리 글 1개, 답글 0
    assert np.main(["publish", str(polished(news, "20261013-0911", BODY_A))]) == 0
    assert np.main(["publish", str(polished(news, "20261013-0940", BODY_A_LATER))]) == 0
    assert slack.calls() == 1  # 같은 판 · 머리 시각만 다른 판 = 발행 0


def test_changed_body_is_a_new_top_level_post_never_a_reply_or_update_and_rerun_adds_none(env, slack):
    """오빠 판정 1438 — 뉴스는 채널에 매번 신규 메세지로, 스레드 안에 넣지 않는다."""
    tmp, news = env
    assert np.main(["publish", str(polished(news, "20261013-0910", BODY_A))]) == 0
    b = polished(news, "20261013-0950", BODY_B)
    assert np.main(["publish", str(b)]) == 0
    assert len(slack.posts) == 2 and slack.posts[1]["text"] == BODY_B and "thread_ts" not in slack.posts[1]
    assert slack.updates == [] and slack.replies() == []
    assert np.main(["publish", str(b)]) == 0
    assert len(slack.posts) == 2  # 재실행 중복 0


def test_R217_success_line_carries_ts_channel_and_permalink_or_dash_and_same_content_keeps_old_line(env, slack, monkeypatch, capsys):
    """요약 쪽지가 파일이 아니라 이 stdout 줄로 이번 호출의 ts 를 받는다(DA⑥ H1·H2). FakeSlack 은 getPermalink 를 몰라(404) 링크는 «-» ."""
    tmp, news = env
    assert np.main(["publish", str(polished(news, "20261013-0910", BODY_A))]) == 0
    out = capsys.readouterr().out.strip()
    assert out == f"ft-news-publish: 발행 완료 ts={slack.msgs[0]['ts']} channel=C1 permalink=-"
    monkeypatch.setenv("FT_NEWS_WORKSPACE_URL", "https://w.slack.com/")
    assert np.main(["publish", str(polished(news, "20261013-0950", BODY_B))]) == 0
    assert capsys.readouterr().out.strip() == f"ft-news-publish: 발행 완료 ts={slack.msgs[1]['ts']} channel=C1 permalink=https://w.slack.com/archives/C1/p{slack.msgs[1]['ts'].replace('.', '')}"
    assert np.main(["publish", str(polished(news, "20261013-0951", BODY_B))]) == 0
    assert capsys.readouterr().out.strip() == "ft-news-publish: 같은 내용 — 발행 0"


def test_failed_slack_call_records_nothing_and_retry_publishes_once(env, slack, monkeypatch):
    tmp, news = env
    monkeypatch.setenv("FT_NEWS_POST_ARGS", f"--slack-base http://127.0.0.1:9 --token-file {tmp / 'tok'} --channel C1 --ledger {tmp / 'threads.json'}")
    d = draft(news, "20261013-0900")
    p = polished(news, "20261013-0910", BODY_A)
    assert np.main(["publish", str(p)]) != 0 and records(tmp) == []
    monkeypatch.setenv("FT_NEWS_POST_ARGS", f"--slack-base {slack.base} --token-file {tmp / 'tok'} --channel C1 --ledger {tmp / 'threads.json'}")
    assert np.main(["publish", str(p)]) == 0 and len(slack.posts) == 1 and d.name in records(tmp)[0]


def test_numbers_outside_trailing_footnote_table_are_logged_and_table_body_is_deleted(env, slack, caplog):
    """r1004 — 번호 경고는 그대로(경고 자체는 발행을 막지 않는다) · 그러나 맨 끝 각주 표도 이제 위반이라 글은 지워진다(가드 예외 0)."""
    tmp, news = env
    body = BODY_A + "\n- 판정 1430 반영\n\n| 번호 | 뜻 |\n|---|---|\n| 1430 | 판정 |\n"
    assert np.main(["publish", str(polished(news, "20261013-0910", body))]) == 1
    assert "각주 표 밖 번호" in caplog.text
    assert len(slack.posts) == 1 and slack.msgs == []  # 올렸다가 가드가 지웠다


# ── ③ 처리 기록 ───────────────────────────────────────────────────

def test_record_line_maps_draft_to_polished_or_same_content(env, slack):
    tmp, news = env
    draft(news, "20261013-0900")
    draft(news, "20261013-0930")
    np.main(["publish", str(polished(news, "20261013-0910", BODY_A))])
    assert records(tmp) == ["DRAFT-20261013-0900.md\tPOLISHED-20261013-0910.md"]
    np.main(["publish", str(polished(news, "20261013-0940", BODY_A_LATER))])
    assert records(tmp)[-1] == "DRAFT-20261013-0930.md\t같은 내용 · 발행 0" and len(records(tmp)) == 2


# ── 교정 r2 · DA⑥ 반례 C1~C3 ─────────────────────────────────────

def test_C1_post_accepted_but_response_lost_then_rerun_adopts_it_and_posts_nothing(env, slack):
    tmp, news = env
    p = polished(news, "20261013-0910", BODY_A)
    slack.drop_next_post = True
    assert np.main(["publish", str(p)]) != 0 and len(slack.posts) == 1  # 접수는 됐고 응답만 유실
    assert np.main(["publish", str(p)]) == 0
    assert len(slack.posts) == 1 and len([m for m in slack.msgs if not m["thread_ts"]]) == 1  # 최상위 글 1개 — 두 번째 post 0


def test_C1r3_root_with_replies_has_thread_ts_equal_ts_and_is_still_adopted(env, slack):
    tmp, news = env
    p = polished(news, "20261013-0910", BODY_A)
    slack.drop_next_post = True
    assert np.main(["publish", str(p)]) != 0 and len(slack.posts) == 1
    slack.msgs[0]["thread_ts"] = slack.msgs[0]["ts"]  # 누가 답글을 달면 Slack 이 최상위 글에도 thread_ts==ts 를 붙인다
    assert np.main(["publish", str(p)]) == 0
    assert len(slack.posts) == 1  # 채택 — 두 번째 최상위 post 0


def test_C1r3_same_body_real_reply_is_not_adopted(env, slack):
    tmp, news = env
    slack.history_has_replies = True
    slack.msgs.append({"ts": "1900000050.000000", "text": BODY_A, "bot_id": "B1", "thread_ts": "1900000001.000000"})  # thread_ts != ts = 실제 답글
    assert np.main(["publish", str(polished(news, "20261013-0910", BODY_A))]) == 0
    assert len(slack.posts) == 1 and slack.posts[0]["text"] == BODY_A  # 채택 0 · 새 글 1


def test_C1_every_changed_publish_is_its_own_top_level_message(env, slack):
    tmp, news = env
    for stamp, body in (("0910", BODY_A), ("0950", BODY_B), ("1030", BODY_B.replace("진행", "진행 중"))):
        assert np.main(["publish", str(polished(news, f"20261013-{stamp}", body))]) == 0
    assert len(slack.msgs) == 3 and all(not m["thread_ts"] for m in slack.msgs) and slack.updates == []


def test_C1_body_over_the_byte_limit_raises_and_posts_nothing(env, slack):
    tmp, news = env
    big = BODY_A + "가" * 1200  # 한글 3바이트 — 글자 수로는 한도 안, 바이트로는 넘음
    assert len(big) < np.MAX_BYTES < len(big.encode("utf-8"))
    assert np.main(["publish", str(polished(news, "20261013-0910", big))]) != 0 and slack.calls() == 0 and records(tmp) == []
