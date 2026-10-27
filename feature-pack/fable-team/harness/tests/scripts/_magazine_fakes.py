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

KIT = Path(__file__).resolve().parents[3] / "harness" / "kit" / "slack-mirror"
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


def detail_fixture() -> dict:
    """설계 DESIGN-magazine-full-detail §3 `detail` 칸 1벌 — ①수집 ↔ ②렌더 접점(칸 이름·모양 고정)."""
    return {
        "refs": [{"name": "origin/main", "start_sha": "a" * 40, "end_sha": "b" * 40}, {"name": "ops/main-base", "start_sha": None, "end_sha": "c" * 40}],
        "units": [{
            "team": "harness", "path": "design/harness/indices/완성/x.md", "title": "예시 단위", "why": "왜 이 단위를 했는지 전문",
            "coord": "하네스 GOAL 표 / 닫는 증거: …", "evidence": ["- 세트: " + "d" * 40 + " · 시험: pytest rc=0 · 이슈: 0"],
            "done": "- 닫힘 판정문: design/harness/OPS-VERDICTS-20261008.md#§3 — 완성 이동 = master --landed " + "e" * 10,
            "da": "design/harness/OPS-VERDICTS-20261008.md#§3", "moved_sha": "e" * 40, "ref": "origin/ops/main-base",
        }],
        "malformed": [],
        "verdict_sections": [{"path": "design/harness/OPS-VERDICTS-20261008.md", "section": "§3", "title": "예시 판정 — 닫힘", "body": "판정 본문 전문"}],
        "decisions": [{
            "n": 354, "ts": "2026-10-08T07:10:00", "to": "byz-harness-master-claude#12", "body": "판정 354 본문 전문",
            "relay_path": "/tmp/mbox/x.md", "relay_text": None, "rollback": ["원문에 되돌림 없음"], "more": 1,
        }],
        "merge_bodies": {"1" * 40: "[feature] 슬랙 미러 요약 (#883)\n\nWhy: …\nWhat: …\nVerify: …\nImpact: …"},
        "issue_evidence": {"880": "닫는 증거 댓글 전문", "881": None},
        "open": {
            "cards": [{"team": "harness", "state": "진행", "path": "design/harness/indices/진행/y.md", "title": "진행 단위", "tail": ["- 상태 1", "- 상태 2", "- 상태 3"]}],
            "requests": [{"id": "R24", "text": "증상 → 접수"}],
            "malformed_requests": [],
            "holds": [{"path": "design/harness/DA-z.md", "verdict": "HOLD"}],
            "breaches": [{"path": "state/gce-op-model/BREACH.md", "text": "# GCE 감시 …"}],
        },
        "seats_closed": [{"path": "design/harness/NANO-LEDGER-harness.md", "line": "- **[2026-10-08 …] `seat#0` 닫힘(ft-nano-close)**"}],
        "appendix": [{"path": "design/harness/BRIEFING-morning-20261008.md", "text": "브리핑 전문"}],
    }


DETAIL_FIXTURE = detail_fixture()


class FakeMagazineSlack:
    """postMessage(스레드 답글 포함) · history · replies · 파일 업로드 3단.
    장애: drop_after_create(글 만들고 응답 유실) · fail_complete(업로드 마무리 실패) · drop_after_complete(공유 성공 뒤 응답 유실)
          · fail_complete_at(n번째 complete 만 거절) · hide_shared_files(공유는 됐는데 replies 에 아직 안 보임) · fail_replies(replies 조회 실패). 호출 기록: upload_url_calls(getUploadURLExternal 횟수) · complete_calls."""

    def __init__(self) -> None:
        self.msgs: list[dict] = []
        self.files: list[dict] = []
        self.uploads: list[bytes] = []
        self.content_types: list[str] = []  # 업로드 바이트 전송 때 보낸 Content-Type(첨부 확장자 시험)
        self.drop_after_create = False
        self.fail_complete = False
        self.drop_after_complete = False
        self.fail_replies = False
        self.fail_permalink = False
        self.fail_complete_at: set[int] = set()
        self.hide_shared_files = False
        self.upload_url_calls = 0
        self.complete_calls = 0
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
                    outer.content_types.append(self.headers.get("Content-Type", ""))
                    return self._reply({"ok": True})
                ts = outer._next_ts()
                body = json.loads(data)
                outer.msgs.append({"ts": ts, "text": body["text"], "bot_id": "B1", "thread_ts": body.get("thread_ts", "")})
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
                if u.path.endswith("conversations.replies"):
                    if outer.fail_replies:
                        return self._reply({"ok": False, "error": "internal_error"})
                    thread = [m for m in outer.msgs if m["ts"] == q["ts"] or m["thread_ts"] == q["ts"]]
                    return self._reply({"ok": True, "messages": thread})
                if u.path.endswith("files.getUploadURLExternal"):
                    outer.upload_url_calls += 1
                    return self._reply({"ok": True, "upload_url": f"{outer.base}/upload/F{outer.upload_url_calls}", "file_id": f"F{outer.upload_url_calls}"})
                if u.path.endswith("chat.getPermalink"):
                    if outer.fail_permalink:
                        return self._reply({"ok": False, "error": "message_not_found"})
                    return self._reply({"ok": True, "permalink": f"https://slack.test/archives/{q['channel']}/p{q['message_ts'].replace('.', '')}"})
                if u.path.endswith("files.info"):
                    return self._reply({"ok": True, "file": {"id": q["file"], "permalink": f"https://slack.test/files/{q['file']}"}})
                outer.complete_calls += 1
                if outer.fail_complete or outer.complete_calls in outer.fail_complete_at:
                    return self._reply({"ok": False, "error": "internal_error"})
                files = json.loads(q["files"])
                outer.files.append({"files": files, "channel_id": q["channel_id"], "thread_ts": q["thread_ts"]})
                if not outer.hide_shared_files:
                    outer.msgs.append({"ts": outer._next_ts(), "text": "", "bot_id": "B1", "thread_ts": q["thread_ts"], "files": files})
                if outer.drop_after_complete:
                    outer.drop_after_complete = False
                    self.connection.shutdown(socket.SHUT_RDWR)
                    return
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

    def titles(self, thread_ts: str) -> list[str]:
        """스레드에 붙은 파일 제목들(공유된 순서)."""
        return [f["title"] for m in self.msgs if m["thread_ts"] == thread_ts for f in m.get("files", [])]

    def replies_of(self, thread_ts: str) -> list[dict]:
        return [m for m in self.msgs if m["thread_ts"] == thread_ts and m["text"]]


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
