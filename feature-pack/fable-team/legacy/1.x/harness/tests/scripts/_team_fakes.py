"""팀 뿌리 글 시험 공용 — Deliverer + TeamRoots + 가짜 라벨·시계 (판정 623). 실 Slack·GitHub 호출 0."""
import json
import sys
import threading
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

KIT = Path(__file__).resolve().parents[3] / "harness" / "kit" / "slack-mirror"
sys.path.insert(0, str(KIT))
import mirror_deliver as md  # noqa: E402
import mirror_lib as lib  # noqa: E402
import mirror_team as mt  # noqa: E402
import mirror_team_roots as tr  # noqa: E402

KST = timezone(timedelta(hours=9))


def kst(y: int, mo: int, d: int, h: int, mi: int) -> float:
    return datetime(y, mo, d, h, mi, tzinfo=KST).timestamp()


class Clock:
    def __init__(self, t: float):
        self.t = t

    def __call__(self) -> float:
        return self.t


class World:
    """한 미러 프로세스 흉내 — rebuild() 는 재시작(같은 파일·새 객체)."""

    def __init__(self, tmp: Path, slack, labels: dict[int, list[str]] | None = None, clock: Clock | None = None):
        self.tmp, self.slack, self.labels = tmp, slack, labels if labels is not None else {}
        self.clock, self.fetches = clock or Clock(kst(2026, 10, 9, 12, 0)), []
        self.threads = tmp / "threads.json"
        self.rebuild()

    def rebuild(self) -> None:
        issues = mt.IssueTeams(self.tmp / "issue_team.json", self._fetch)
        self.teams = tr.TeamRoots(self.tmp, self.slack.base, "tok", "C1", mt.Router(issues, self.clock))
        self.deliv = md.Deliverer(self.slack.base, "tok", "C1", self.threads, teams=self.teams)

    def _fetch(self, n: int) -> list[str]:
        self.fetches.append(n)
        if n not in self.labels:
            raise lib.MirrorError(f"GitHub 호출 실패: HTTP 404 (#{n})")
        return self.labels[n]

    def item(self, key: str, iid: str, what: str = "첫 보고", **kw: object) -> dict[str, object]:
        return {"id": iid, "key": key, "what": what, "text": f"[작업상황] {what}\n할 일 없음\n({iid})", **kw}

    def send(self, key: str, iid: str, what: str = "첫 보고", resume: bool = False, **kw: object) -> dict[str, object]:
        it = self.item(key, iid, what, **kw)
        self.deliv.send(it, resume)
        return it

    def state(self) -> dict:
        return json.loads((self.tmp / "byz_team_roots.json").read_text(encoding="utf-8"))

    def root(self, team: str, day: str = "2026-10-09") -> dict[str, str]:
        (m,) = [m for m in self.slack.roots if f"(mirror · team:{team}:{day} 시작)" in m["text"]]
        return m

    def replies_of(self, team: str, day: str = "2026-10-09") -> list[dict[str, str]]:
        return self.slack.replies(self.root(team, day))


class FakeLabels:
    """GitHub `/repos/o/r/issues/N` 만 답하는 가짜 — 모든 이슈에 team:harness."""

    def __init__(self) -> None:
        class H(BaseHTTPRequestHandler):
            def log_message(self, format: str, *args: object) -> None:  # noqa: A002
                pass

            def do_GET(self) -> None:
                raw = json.dumps({"labels": [{"name": "team:harness"}]}).encode()
                self.send_response(200)
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

        self.srv = HTTPServer(("127.0.0.1", 0), H)
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        self.base = f"http://127.0.0.1:{self.srv.server_port}"
