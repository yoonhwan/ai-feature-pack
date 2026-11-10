"""byz_github_slack_mirror — 가짜 GitHub·가짜 Slack 으로 baseline·전이 4종·침묵·exactly-once·공유 스레드·가드를 시험한다 (실호출 0)."""
import json
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import pytest
from _slack_fakes import FAKE_SUMMARIZER, FakeSlack

KIT = Path(__file__).resolve().parents[3] / "harness" / "kit" / "slack-mirror"
SCRIPT = KIT / "byz_github_slack_mirror.py"
REPO = "o/r"
OLD = "2020-01-01T00:00:00Z"  # baseline 이전
NEW = "2099-01-01T00:00:00Z"  # baseline 이후


class FakeGithub:
    def __init__(self) -> None:
        self.issues: list[dict[str, object]] = []
        self.fail = 0  # 0 이면 정상, 아니면 그 HTTP 코드
        self.hits_304 = 0
        self.version = 1
        outer = self

        class H(BaseHTTPRequestHandler):
            def log_message(self, format: str, *args: object) -> None:  # noqa: A002
                pass

            def do_GET(self) -> None:
                if outer.fail:
                    self.send_response(outer.fail)
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                q = parse_qs(urlparse(self.path).query)
                etag = f'"v{outer.version}-{q.get("since", [""])[0]}"'
                if self.headers.get("If-None-Match") == etag:
                    outer.hits_304 += 1
                    self.send_response(304)
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                rows = [i for i in outer.issues if q["state"][0] == "all" or i["state"] == "open"]
                if "since" in q:
                    rows = [i for i in rows if str(i["updated_at"]) >= q["since"][0]]
                rows.sort(key=lambda i: str(i["updated_at"]))
                raw = json.dumps(rows).encode()
                self.send_response(200)
                self.send_header("ETag", etag)
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

        self.srv = HTTPServer(("127.0.0.1", 0), H)
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        self.base = f"http://127.0.0.1:{self.srv.server_port}"

    def put(self, n: int, title: str = "제목", state: str = "open", labels: tuple[str, ...] = (),
            pr: bool = False, merged: bool = False, created: str = NEW, updated: str = NEW) -> None:
        self.issues = [i for i in self.issues if i["number"] != n]
        item: dict[str, object] = {"number": n, "title": title, "state": state, "created_at": created, "updated_at": updated,
                                   "html_url": f"https://github.com/o/r/{'pull' if pr else 'issues'}/{n}",
                                   "labels": [{"name": x} for x in labels]}
        if pr:
            item["pull_request"] = {"merged_at": NEW if merged else None}
        self.issues.append(item)
        self.version += 1


@pytest.fixture
def slack():
    s = FakeSlack()
    yield s
    s.srv.shutdown()


@pytest.fixture
def ghub():
    g = FakeGithub()
    yield g
    g.srv.shutdown()


@pytest.fixture
def env(tmp_path: Path) -> Path:
    (tmp_path / "tok.env").write_text("YOONHWAN_BOT_TOKEN=xoxp-test\n", encoding="utf-8")
    (tmp_path / "fake_sum.py").write_text(FAKE_SUMMARIZER, encoding="utf-8")
    return tmp_path


def run(tmp: Path, slack: FakeSlack, ghub: FakeGithub):
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--repo", REPO, "--channel", "C1", "--state-dir", str(tmp / "st"),
         "--token-file", str(tmp / "tok.env"), "--api-base", slack.base, "--github-api", ghub.base,
         "--mention", "U0AC2JF0M7D", "--repo", REPO, "--once", "--summarizer-cmd", f"{sys.executable} {tmp / 'fake_sum.py'}"],
        capture_output=True, text=True, timeout=60, env={"GITHUB_MIRROR_TOKEN": "t", "PATH": "/usr/bin:/bin"},
    )


def state(env: Path) -> dict:
    return json.loads((env / "st" / "byz_github_slack_mirror.o_r.json").read_text(encoding="utf-8"))


def start(env: Path, slack: FakeSlack, ghub: FakeGithub) -> None:
    ghub.put(1, "옛 열린 이슈", created=OLD, updated=OLD)
    ghub.put(2, "옛 닫힌 이슈", state="closed", created=OLD, updated=OLD)
    assert run(env, slack, ghub).returncode == 0 and slack.msgs == []


def test_baseline_records_open_issues_without_posting(env: Path, slack: FakeSlack, ghub: FakeGithub):
    start(env, slack, ghub)
    assert set(state(env)["issues"]) == {"1"}


def test_opened_issue_makes_root_and_reply_once(env: Path, slack: FakeSlack, ghub: FakeGithub):
    start(env, slack, ghub)
    ghub.put(10, "새 이슈")
    assert run(env, slack, ghub).returncode == 0
    assert len(slack.roots) == 1 and slack.roots[0]["text"].startswith("[작업상황] #10 시작")
    (reply,) = slack.replies(slack.roots[0])
    assert "(github #10 opened)" in reply["text"]
    assert run(env, slack, ghub).returncode == 0 and len(slack.msgs) == 2  # 재폴링 게시 0
    assert run(env, slack, ghub).returncode == 0 and len(slack.msgs) == 2
    assert ghub.hits_304 >= 1  # since 가 안 움직이면 ETag 304


def test_close_merge_and_hil_transitions_each_post_once(env: Path, slack: FakeSlack, ghub: FakeGithub):
    start(env, slack, ghub)
    ghub.put(1, "옛 열린 이슈", state="closed", created=OLD, updated="2099-01-02T00:00:00Z")
    ghub.put(20, "새 PR", pr=True, state="closed", merged=True, updated="2099-01-03T00:00:00Z")
    ghub.put(30, "판정 필요", labels=("hil:needed",), updated="2099-01-04T00:00:00Z")
    assert run(env, slack, ghub).returncode == 0
    tails = "\n".join(m["text"] for m in slack.msgs if m["thread_ts"])
    for tag in ("#1 closed", "#20 opened", "#20 merged", "#30 opened", "#30 hil"):
        assert f"(github {tag})" in tails
    hil = next(m for m in slack.msgs if "(github #30 hil)" in m["text"])
    assert "<@U0AC2JF0M7D>" in hil["text"]
    n = len(slack.msgs)
    assert run(env, slack, ghub).returncode == 0 and len(slack.msgs) == n


def test_other_label_and_title_edits_stay_silent(env: Path, slack: FakeSlack, ghub: FakeGithub):
    start(env, slack, ghub)
    ghub.put(1, "제목 바뀜", labels=("bug",), created=OLD, updated="2099-01-02T00:00:00Z")
    assert run(env, slack, ghub).returncode == 0 and slack.msgs == []


def test_github_5xx_raises_without_posting(env: Path, slack: FakeSlack, ghub: FakeGithub):
    start(env, slack, ghub)
    ghub.put(10, "새 이슈")
    ghub.fail = 502
    r = run(env, slack, ghub)
    assert r.returncode == 1 and "HTTP 502" in r.stderr and slack.msgs == []
    ghub.fail = 0
    assert run(env, slack, ghub).returncode == 0 and len(slack.roots) == 1


def test_title_mentions_are_neutralized(env: Path, slack: FakeSlack, ghub: FakeGithub):
    start(env, slack, ghub)
    ghub.put(10, "SUMFAIL <!channel> 긴급 <@U123>")  # 요약 실패 경로 = 제목이 루트·본문에 그대로 간다
    assert run(env, slack, ghub).returncode == 0
    assert all("<!channel>" not in m["text"] and "<@U123>" not in m["text"] for m in slack.msgs)


def test_summary_failure_falls_back_visibly(env: Path, slack: FakeSlack, ghub: FakeGithub):
    start(env, slack, ghub)
    ghub.put(10, "SUMFAIL 이슈")
    r = run(env, slack, ghub)
    assert r.returncode == 0 and "요약 실패" in r.stderr
    assert "원문 그대로" in slack.replies(slack.roots[0])[0]["text"]


def test_shares_the_thread_map_with_the_mbox_mirror(env: Path, slack: FakeSlack, ghub: FakeGithub):
    start(env, slack, ghub)
    slack.msgs.append({"ts": "1.0", "text": "#10 시작 — mbox 가 먼저", "thread_ts": ""})
    (env / "st" / "byz_slack_threads.C1.json").write_text(json.dumps({"threads": {"#10": "1.0"}}), encoding="utf-8")
    ghub.put(10, "새 이슈")
    assert run(env, slack, ghub).returncode == 0
    assert len(slack.roots) == 1 and len(slack.replies(slack.roots[0])) == 1  # 같은 스레드에 reply


def test_crash_after_reply_before_state_does_not_duplicate(env: Path, slack: FakeSlack, ghub: FakeGithub):
    start(env, slack, ghub)
    text = "무슨 일\n할 일 없음\n(github #10 opened)"
    slack.msgs += [{"ts": "1.0", "text": "#10 시작 — x", "thread_ts": ""}, {"ts": "2.0", "text": text, "thread_ts": "1.0"}]
    (env / "st" / "byz_slack_threads.C1.json").write_text(json.dumps({"threads": {"#10": "1.0"}}), encoding="utf-8")
    st = state(env)
    st["pending"] = {"id": "github #10 opened", "num": 10, "kind": "opened", "key": "#10", "what": "x", "text": text}
    (env / "st" / "byz_github_slack_mirror.o_r.json").write_text(json.dumps(st), encoding="utf-8")
    ghub.put(10, "새 이슈")
    assert run(env, slack, ghub).returncode == 0
    assert len(slack.msgs) == 2  # 이미 올라간 opened 는 다시 올리지 않는다


def test_old_closed_issue_touched_after_baseline_stays_silent(env: Path, slack: FakeSlack, ghub: FakeGithub):
    start(env, slack, ghub)
    ghub.put(2, "옛 닫힌 이슈", state="closed", created=OLD, updated="2099-01-02T00:00:00Z")  # 코멘트 등으로 갱신됨
    assert run(env, slack, ghub).returncode == 0 and slack.msgs == []


def test_root_and_replies_carry_issue_and_pr_urls(env: Path, slack: FakeSlack, ghub: FakeGithub):
    start(env, slack, ghub)
    ghub.put(20, "새 PR", pr=True, state="closed", merged=True)
    assert run(env, slack, ghub).returncode == 0
    assert slack.roots[0]["text"].endswith("\nhttps://github.com/o/r/issues/20")
    replies = [m["text"] for m in slack.replies(slack.roots[0])]
    assert len(replies) == 2 and all("링크: https://github.com/o/r/pull/20" in t for t in replies)  # 머지 reply = PR URL
