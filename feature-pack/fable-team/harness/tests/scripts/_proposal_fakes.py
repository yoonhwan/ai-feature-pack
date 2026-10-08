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
        self.drop_next_post = False
        self.fail_complete = False
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
                if outer.fail_complete:
                    return self._reply({"ok": False, "error": "internal_error"})
                outer.files.append({"title": json.loads(q["files"])[0]["title"], "thread_ts": q["thread_ts"]})
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


def pub(t, md, tmp_path, rev="r0", **kw):
    return bp.publish(t, bp.parse(md), md, rev, tmp_path / "state.json", **kw)


KEY = "feature/ko-line-break"
