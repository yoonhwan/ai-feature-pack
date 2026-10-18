"""공용 시험 도구 — 가짜 Slack 서버·가짜 요약기 (mbox·GitHub 미러 시험이 함께 쓴다)."""
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

FAKE_SUMMARIZER = '''\
import json, sys
p = sys.stdin.read()
if "SUMFAIL" in p:
    sys.exit(1)
if "SUMJUNK" in p:
    print("죄송하지만 JSON 이 아니에요")
    sys.exit(0)
label = p.split("라벨: ", 1)[1].split("\\n", 1)[0]
text = p.rsplit("<보고>\\n", 1)[1].split("\\n</보고>", 1)[0]
print("```json")
print(json.dumps({"what": "요약:" + text[:14], "todo": "답해 주세요" if label == "HIL" else None}, ensure_ascii=False))
print("```")
'''


class FakeSlack:
    def __init__(self) -> None:
        self.msgs: list[dict[str, str]] = []  # {"ts","text","thread_ts"}
        self.fail_post = False
        self.fail_read = False
        outer = self

        class H(BaseHTTPRequestHandler):
            def log_message(self, format: str, *args: object) -> None:  # noqa: A002
                pass

            def _reply(self, body: dict[str, object]) -> None:
                raw = json.dumps(body).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

            def do_POST(self) -> None:
                data = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                if outer.fail_post:
                    return self._reply({"ok": False, "error": "channel_not_found"})
                if urlparse(self.path).path.endswith("chat.update"):
                    for m in outer.msgs:
                        if m["ts"] == data["ts"]:
                            m["text"] = data["text"]
                            return self._reply({"ok": True, "ts": m["ts"]})
                    return self._reply({"ok": False, "error": "message_not_found"})
                ts = f"{1000000000 + len(outer.msgs) + 1}.000000"
                outer.msgs.append({"ts": ts, "text": data["text"], "thread_ts": data.get("thread_ts", ""), "bot_id": "B1"})
                self._reply({"ok": True, "ts": ts})

            def do_GET(self) -> None:
                if outer.fail_read:
                    return self._reply({"ok": False, "error": "missing_scope"})
                u = urlparse(self.path)
                q = parse_qs(u.query)
                if u.path.endswith("conversations.history"):
                    roots = [{**m, **outer._thread_meta(m)} for m in outer.msgs if not m["thread_ts"] and m["ts"] > q.get("oldest", ["0"])[0]]
                    return self._reply(outer._page(list(reversed(roots)), q))
                if u.path.endswith("chat.getPermalink"):
                    return self._reply({"ok": True, "permalink": f"https://fake.slack.com/archives/C1/p{q['message_ts'][0]}"})
                ts = q["ts"][0]
                oldest = q.get("oldest", ["0"])[0]
                got = [m for m in outer.msgs if (m["ts"] == ts or m["thread_ts"] == ts) and (m["ts"] == ts or m["ts"] > oldest)]
                self._reply(outer._page(got, q))

        self.srv = HTTPServer(("127.0.0.1", 0), H)
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        self.base = f"http://127.0.0.1:{self.srv.server_port}"

    page_size = 100  # 시험이 줄여서 페이지네이션을 강제한다

    def _page(self, items: list[dict[str, str]], q: dict[str, list[str]]) -> dict[str, object]:
        start = int(q.get("cursor", ["0"])[0])
        end = start + min(int(q.get("limit", ["100"])[0]), self.page_size)
        body: dict[str, object] = {"ok": True, "messages": items[start:end]}
        if end < len(items):
            body["response_metadata"] = {"next_cursor": str(end)}
        return body

    def _thread_meta(self, root: dict[str, str]) -> dict[str, str]:
        kids = [m["ts"] for m in self.msgs if m["thread_ts"] == root["ts"]]
        return {"latest_reply": max(kids)} if kids else {}

    def human(self, text: str, thread_ts: str = "", user: str = "U0AC2JF0M7D") -> str:
        """사람(봇 아님) 글 한 건을 심는다 — 오빠 reply·루트 글 시험용."""
        ts = f"{time.time() + len(self.msgs) * 0.001:.6f}"  # 실시간 기준 — 미러 baseline 이후 글로 읽힌다
        self.msgs.append({"ts": ts, "text": text, "thread_ts": thread_ts, "user": user})
        return ts

    @property
    def roots(self) -> list[dict[str, str]]:
        return [m for m in self.msgs if not m["thread_ts"]]

    def replies(self, root: dict[str, str]) -> list[dict[str, str]]:
        return [m for m in self.msgs if m["thread_ts"] == root["ts"]]
