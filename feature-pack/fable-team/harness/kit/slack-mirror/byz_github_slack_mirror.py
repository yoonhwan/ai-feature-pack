#!/usr/bin/env python3
"""byz_github_slack_mirror — GitHub Issue·PR 의 열림·닫힘·머지·hil:needed → Slack (읽기 전용 미러 · ⓔ).

정본 설계: design/harness/DESIGN-slack-mirror.md §10 · D5 = mbox 미러와 같은 이슈 스레드(공유 스레드 맵) · D6 = 4종만.
실패 = raise(exit 1) · 재시도 0 · launchd KeepAlive 가 재기동. 요약(LLM) 실패만 «보이게» 제목 그대로 내려간다.
exactly-once: pending 기록 → 게시(재시작 시 스레드에서 마커 조회) → 스냅샷·since 확정.
첫 실행은 baseline — 열린 것 전부를 기록만 하고 쏟아내지 않는다.
"""
import argparse
import fcntl
import json
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mirror_github as gh  # noqa: E402
import mirror_lib as lib  # noqa: E402
import mirror_summary as summ  # noqa: E402
from byz_mbox_slack_mirror import read_token, save_state  # noqa: E402
from mirror_deliver import Deliverer  # noqa: E402

API = "https://slack.com/api"
GITHUB_API = "https://api.github.com"
FACT = {"opened": "열렸어요", "closed": "닫혔어요", "merged": "머지됐어요", "hil": "오빠 판정이 필요해요(hil:needed 라벨)"}


class GithubMirror:
    def __init__(self, a: argparse.Namespace):
        self.a = a
        slug = re.sub(r"[^A-Za-z0-9._-]", "_", a.repo)
        self.state_path = Path(a.state_dir) / f"byz_github_slack_mirror.{slug}.json"
        self.gh_token = gh.read_token()
        self.deliv = None if a.dry_run else Deliverer(
            a.api_base, read_token(Path(a.token_file).expanduser()), a.channel,
            Path(a.state_dir) / f"byz_slack_threads.{a.channel}.json")
        self.posted = 0

    def _save(self, st: dict[str, object]) -> None:
        if not self.a.dry_run:
            save_state(self.state_path, st)

    def _item(self, issue: dict[str, object], kind: str) -> dict[str, object]:
        n, title = int(str(issue["number"])), str(issue.get("title", ""))
        what_kind = "PR" if issue.get("pull_request") else "이슈"
        facts = f"{what_kind} {n} {FACT[kind]} — {title}"
        try:
            s: dict[str, str | None] | None = summ.summarize(
                self.a.summarizer_cmd, "HIL" if kind == "hil" else "보고", facts, self.a.summary_timeout)
        except summ.SummaryError as e:
            print(f"ERROR: 요약 실패 #{n} {kind}: {e} — 제목 그대로 게시", file=sys.stderr)
            s = None
        iid = f"github #{n} {kind}"
        row: dict[str, object] = {"from": "github", "seq": iid}
        text = lib.format_row(row, "HIL" if kind == "hil" else "보고", self.a.mention, s, facts)
        text = text.replace(f"(github · #{iid}", f"({iid}")  # 꼬리 = 마커(id) 그대로
        return {"id": iid, "num": n, "kind": kind, "key": f"#{n}", "what": s["what"] if s else title, "text": text}

    def _deliver(self, st: dict[str, object], item: dict[str, object], resume: bool = False) -> None:
        if self.deliv is None:
            print(f"[thread {item['key']}]\n{item['text']}\n---")
        else:
            st["pending"] = item
            self._save(st)
            self.deliv.send(item, resume)
            st["pending"] = None
        self.posted += 1

    def _baseline(self, st: dict[str, object]) -> int:
        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        issues, etag = gh.fetch_issues(self.a.github_api, self.a.repo, self.gh_token, None, None)
        snaps = {str(i["number"]): gh.snapshot(i) for i in issues}
        st.update(baseline=now, since=now, etag=None, etag_since=None, pending=None, issues=snaps)
        self._save(st)
        print(f"baseline open={len(snaps)} since={now}", file=sys.stderr)
        return 0

    def _apply(self, st: dict[str, object], issue: dict[str, object]) -> None:
        snaps = st["issues"]
        assert isinstance(snaps, dict)
        key, cur = str(issue["number"]), gh.snapshot(issue)
        prev = snaps.get(key)
        if prev is None and str(issue.get("created_at", "")) <= str(st["baseline"]):
            snaps[key] = cur  # baseline 이전에 이미 닫힌 것 — 기록만
            return
        while kinds := gh.transitions(prev, cur):
            self._deliver(st, self._item(issue, kinds[0]))
            prev = gh.advance(prev, kinds[0], cur)
            snaps[key] = prev
            self._save(st)

    def run_pass(self) -> int:
        self.posted = 0
        st: dict[str, object] = json.loads(self.state_path.read_text(encoding="utf-8")) if self.state_path.exists() else {}
        if not st:
            return self._baseline(st)
        pending = st.get("pending")
        if isinstance(pending, dict) and self.deliv:
            self._deliver(st, pending, resume=True)
            snaps = st["issues"]
            assert isinstance(snaps, dict)
            k = str(pending["num"])  # 게시한 전이를 스냅샷에 반영 — 같은 전이를 다시 만들지 않는다
            snaps[k] = gh.advance(snaps.get(k), str(pending["kind"]), {"pr": False})
            self._save(st)
        since = str(st["since"])
        old = st.get("etag")
        etag = str(old) if old and st.get("etag_since") == since else None
        issues, new_etag = gh.fetch_issues(self.a.github_api, self.a.repo, self.gh_token, since, etag)
        st.update(etag=new_etag, etag_since=since)
        for issue in issues:
            self._apply(st, issue)
            st["since"] = str(issue["updated_at"])
            self._save(st)
        self._save(st)
        return self.posted


def parse() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--repo", required=True, help="예: ByourzCorp/BYZ-Agents")
    p.add_argument("--channel", required=True)
    p.add_argument("--state-dir", default=str(Path.home() / ".hermes" / "state"))
    p.add_argument("--token-file", default="~/.hermes/secrets/yoonhwan_bot.env")
    p.add_argument("--mention", default="", help="[HIL] 에서 멘션할 Slack 사용자 ID 1개(고정)")
    p.add_argument("--summarizer-cmd", default=summ.DEFAULT_CMD)
    p.add_argument("--summary-timeout", type=float, default=90.0)
    p.add_argument("--api-base", default=API)
    p.add_argument("--github-api", default=GITHUB_API)
    p.add_argument("--interval", type=float, default=30.0)
    p.add_argument("--once", action="store_true")
    p.add_argument("--dry-run", action="store_true")
    return p.parse_args()


def main() -> int:
    a = parse()
    Path(a.state_dir).mkdir(parents=True, exist_ok=True)
    lock = open(Path(a.state_dir) / "byz_github_slack_mirror.lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        print("ERROR: 다른 GitHub 미러 인스턴스가 실행 중", file=sys.stderr)
        return 2
    try:
        m = GithubMirror(a)
        while True:
            m.run_pass()
            if a.once:
                return 0
            time.sleep(a.interval)
    except lib.MirrorError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
