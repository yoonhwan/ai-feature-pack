"""제안서 발행 시험 공용 도구 — 장애 주입이 되는 가짜 Slack 서버(replies·첨부 content-type) · 제안서 견본 · 공용 fixture. 네트워크 0."""
import json
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import pytest
from _magazine_fakes import KIT  # noqa: F401 — sys.path 에 키트 경로를 넣는다

import byz_proposal_publish as bp
from magazine_eli5_batches import Eli5Error
from magazine_slack import Target

BODY = """# 제안서 — 한국어 줄바꿈 CSS
- 상태: {status}
- 팀·나노: feature / nano-x

## 결론
word-break 한 줄이면 된다.

## 오빠가 결정할 것
<적용할까요> 승인 / 수정 / 폐기?

## 제안
- 한 줄 CSS

## 되돌림
CSS 한 줄 revert.

## 검증
화면에서 줄이 단어 중간에서 안 끊긴다.
"""


class FakeSlack:
    """postMessage(thread_ts 저장) · history · replies · 파일 3단. 장애: drop_next_post(글 만들고 응답 유실) · fail_complete(첨부 마무리 실패)."""

    def __init__(self) -> None:
        self.msgs: list[dict] = []
        self.files: list[dict] = []
        self.upload_types: list[str] = []
        self.upload_bodies: list[bytes] = []
        self.drop_next_post = False
        self.fail_complete = False
        self.complete_faults: dict[int, str] = {}  # n번째 complete → "applied"(공유됐는데 응답 유실) · "dropped"(공유 안 됐고 응답 유실) · "rejected"(ok=false 거절)
        self._completes = 0
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
                data = self.rfile.read(int(self.headers["Content-Length"]))
                if self.path.startswith("/upload/"):
                    outer.upload_types.append(self.headers["Content-Type"])
                    outer.upload_bodies.append(data)
                    return self._reply({"ok": True})
                req = json.loads(data)
                outer._seq += 1
                ts = f"{time.time() + outer._seq * 0.001:.6f}"
                outer.msgs.append({"ts": ts, "text": req["text"], "bot_id": "B1", "thread_ts": req.get("thread_ts", "")})
                if outer.drop_next_post:
                    outer.drop_next_post = False
                    self.connection.shutdown(socket.SHUT_RDWR)
                    return
                self._reply({"ok": True, "ts": ts})

            def do_GET(self) -> None:
                u = urlparse(self.path)
                q = {k: v[0] for k, v in parse_qs(u.query).items()}
                if u.path.endswith("conversations.history"):
                    roots = [m for m in outer.msgs if not m["thread_ts"] and float(m["ts"]) > float(q["oldest"])]
                    return self._reply({"ok": True, "messages": list(reversed(roots))})
                if u.path.endswith("conversations.replies"):
                    thread = [m for m in outer.msgs if m["ts"] == q["ts"] or m["thread_ts"] == q["ts"]]
                    return self._reply({"ok": True, "messages": thread})
                if u.path.endswith("files.getUploadURLExternal"):
                    return self._reply({"ok": True, "upload_url": f"{outer.base}/upload/F1", "file_id": "F1"})
                outer._completes += 1
                fault = outer.complete_faults.get(outer._completes)
                if outer.fail_complete or fault == "rejected":
                    return self._reply({"ok": False, "error": "internal_error"})
                if fault != "dropped":
                    title = json.loads(q["files"])[0]["title"]
                    outer.files.append({"title": title, "thread_ts": q["thread_ts"]})
                    for m in outer.msgs:  # 실 슬랙처럼 스레드 봇 글에 files 가 보인다(has_file_title 의 원격 표식) — 뿌리 글에 붙인다
                        if m["ts"] == q["thread_ts"]:
                            m.setdefault("files", []).append({"title": title})
                if fault:
                    self.connection.shutdown(socket.SHUT_RDWR)
                    return
                self._reply({"ok": True})

        self.srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        self.base = f"http://127.0.0.1:{self.srv.server_port}"

    @property
    def roots(self) -> list[dict]:
        return [m for m in self.msgs if not m["thread_ts"]]

    @property
    def replies(self) -> list[dict]:
        return [m for m in self.msgs if m["thread_ts"]]


@pytest.fixture
def slack() -> FakeSlack:
    return FakeSlack()


@pytest.fixture
def t(slack) -> Target:
    return Target(slack.base, "tok", "C1", "")


def make_md(tmp_path: Path, status: str = "컨펌 대기", mutate=None) -> Path:
    p = tmp_path / "design" / "feature" / "PROPOSAL-ko-line-break-20261008.md"
    p.parent.mkdir(parents=True, exist_ok=True)
    text = BODY.format(status=status)
    p.write_text(mutate(text) if mutate else text, encoding="utf-8")
    return p


class FakeBuild:
    """쉬운 판 생성기 대역 — 호출 기록(calls) · fail=Eli5Error 사유(없으면 성공). 실 LLM 0."""

    def __init__(self) -> None:
        self.calls: list[tuple[str, str]] = []
        self.fail = ""

    def __call__(self, text: str, key: str, cmd: str) -> str:
        self.calls.append((key, text))
        if self.fail:
            raise Eli5Error(self.fail)
        return f"<html>fake eli5 {key}</html>"


@pytest.fixture
def build() -> FakeBuild:
    return FakeBuild()


def pub(t, md, tmp_path, rev="r0", build=None, **kw):
    return bp.publish(t, md, rev, tmp_path / "state.json", cache_dir=tmp_path / "cache", build=build or FakeBuild(), **kw)


KEY = "feature/ko-line-break"
