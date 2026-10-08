"""매거진 시험 공용 도구 — 설계 §8 계약 칸으로 만든 가짜 구조 모델 · 장애 주입이 되는 가짜 Slack 서버 (네트워크 0)."""
import json
import socket
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

KIT = Path(__file__).resolve().parents[2] / "scripts" / "harness-install" / "slack-mirror"
if str(KIT) not in sys.path:
    sys.path.insert(0, str(KIT))

SUMMARY_OK = '''\
import json, sys
sys.stdin.read()
print(json.dumps({"lines": ["main 에 두 건이 들어갔어요", "이슈는 하나 열렸어요", "오빠가 할 일은 하나예요"]}, ensure_ascii=False))
'''


def fake_model() -> dict:
    return {
        "date": "2026-10-08", "start": "2026-10-07T08:00:00+09:00", "end": "2026-10-08T08:00:00+09:00",
        "main": {"from_sha": "a" * 40, "to_sha": "b" * 40},
        "merges": [
            {"sha": "1" * 40, "at": "2026-10-07T10:00:00+09:00", "title": "[feature] 슬랙 미러 요약 (#883)", "pr": 883, "tag": "[feature]"},
            {"sha": "2" * 40, "at": "2026-10-07T11:00:00+09:00", "title": "[docs] 브리핑 갱신 see #12 (#884)", "pr": 884, "tag": "[docs]"},
            {"sha": "3" * 40, "at": "2026-10-07T12:00:00+09:00", "title": "직접 푸시", "pr": None, "tag": None},
        ],
        "issues_opened": [{"number": 885, "title": "아침 <@U1> 매거진", "state": "OPEN", "url": "https://github.com/o/r/issues/885"}],
        "issues_closed": [{"number": 880, "title": "옛 이슈", "state": "CLOSED", "url": "https://github.com/o/r/issues/880"}],
        "verdicts": [{"n": 347, "line": "판정 347 매거진 승인 #885"}, {"n": 348, "line": "판정 348 push 확정"}],
        "mbox": {"total": 42, "bad_lines": 2, "by_team": {"harness": {"count": 30, "recent": ["a|b", "c", "d"]}, "v65": {"count": 12, "recent": ["e"]}},
                 "hil_asked": 3, "hil": ["[HIL] <script>alert(1)</script> 판정 부탁 #77"]},
        "docs": [{"path": "design/harness/BRIEFING-morning-20261008.md", "url": "https://github.com/o/r/blob/main/x.md"}],
        "seats": {"succession": [["byz-harness-master-claude#11", "byz-harness-master-claude#12"]], "new": ["byz-harness-nano-x#0"]},
    }


class FakeMagazineSlack:
    """postMessage · history · 파일 업로드 3단. 장애: drop_after_create(글 만들고 응답 유실) · fail_complete(업로드 마무리 실패)."""

    def __init__(self) -> None:
        self.msgs: list[dict] = []
        self.files: list[dict] = []
        self.uploads: list[bytes] = []
        self.drop_after_create = False
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
                    outer.uploads.append(data)
                    return self._reply({"ok": True})
                ts = outer._next_ts()
                outer.msgs.append({"ts": ts, "text": json.loads(data)["text"], "bot_id": "B1", "thread_ts": ""})
                if outer.drop_after_create:
                    outer.drop_after_create = False
                    self.connection.shutdown(socket.SHUT_RDWR)
                    return
                self._reply({"ok": True, "ts": ts})

            def do_GET(self) -> None:
                u = urlparse(self.path)
                q = {k: v[0] for k, v in parse_qs(u.query).items()}
                if u.path.endswith("conversations.history"):
                    roots = [m for m in outer.msgs if not m["thread_ts"] and float(m["ts"]) > float(q["oldest"])]
                    return self._reply({"ok": True, "messages": list(reversed(roots))})
                if u.path.endswith("files.getUploadURLExternal"):
                    return self._reply({"ok": True, "upload_url": f"{outer.base}/upload/F1", "file_id": "F1"})
                if outer.fail_complete:
                    return self._reply({"ok": False, "error": "internal_error"})
                outer.files.append({"files": json.loads(q["files"]), "channel_id": q["channel_id"], "thread_ts": q["thread_ts"]})
                self._reply({"ok": True})

        self.srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        self.base = f"http://127.0.0.1:{self.srv.server_port}"

    def _next_ts(self) -> str:
        self._seq += 1
        return f"{time.time() + self._seq * 0.001:.6f}"

    @property
    def roots(self) -> list[dict]:
        return [m for m in self.msgs if not m["thread_ts"]]


def git(cwd: Path, *a: str) -> str:
    return subprocess.run(["git", "-C", str(cwd), *a], capture_output=True, text=True, check=True).stdout.strip()


def make_repo(tmp_path: Path) -> tuple[Path, Path, Path]:
    """가짜 origin(bare) + 클론(main) + origin/main 기준 ops/magazine 워크트리. 반환 (origin, main, wt)."""
    origin, main, wt = tmp_path / "origin.git", tmp_path / "main", tmp_path / "wt"
    subprocess.run(["git", "init", "-q", "--bare", "-b", "main", str(origin)], check=True)
    subprocess.run(["git", "clone", "-q", str(origin), str(main)], check=True, capture_output=True)
    for k, v in (("user.email", "t@t"), ("user.name", "t")):
        git(main, "config", k, v)
    (main / "a.txt").write_text("a")
    git(main, "add", "-A")
    git(main, "commit", "-qm", "init")
    git(main, "push", "-q", "origin", "HEAD:main")
    git(main, "fetch", "-q")
    git(main, "worktree", "add", "-q", "-b", "ops/magazine", str(wt), "origin/main")
    for k, v in (("user.email", "t@t"), ("user.name", "t")):
        git(wt, "config", k, v)
    return origin, main, wt
