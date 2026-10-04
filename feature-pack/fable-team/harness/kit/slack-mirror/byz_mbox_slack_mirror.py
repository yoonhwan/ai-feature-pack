#!/usr/bin/env python3
"""byz_mbox_slack_mirror — mailbox.log.jsonl(보낸 행 사본) → Slack 읽기 미러 (단계 1 · 읽기 전용).

정본 설계: design/harness/DESIGN-slack-mirror.md · 포맷 = 역할 파일 §1-4(사람 말 3줄) · §1-5(작업 1개 = 스레드 1개).
실패 = raise(exit 1) · 재시도 0 · launchd KeepAlive 가 재기동. 요약(LLM) 실패만 «보이게» 원문 첫 문장으로 내려간다(유실 0).
exactly-once: pending 기록 → (루트) → reply → last_seq. 재시작 시 pending 은 채널·스레드에서 마커를 조회한 뒤 게시한다.
seq 공백(= 사본 기록 실패·로그 손실)은 «기타» 스레드에 1건으로 올린다 — 유실이 조용하면 안 된다.
"""
import argparse
import fcntl
import json
import os
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mirror_lib as lib  # noqa: E402
import mirror_summary as summ  # noqa: E402

API = "https://slack.com/api"
MAX_THREADS = 500  # (키 → thread_ts) 맵 상한 — 오래된 키부터 밀려난다(무한 증가 0)


def read_token(path: Path) -> str:
    try:
        for ln in path.read_text(encoding="utf-8").splitlines():
            if ln.startswith("YOONHWAN_BOT_TOKEN=") and ln.split("=", 1)[1].strip():
                return ln.split("=", 1)[1].strip()
    except OSError as e:
        raise lib.MirrorError(f"토큰 파일 읽기 실패: {path} ({type(e).__name__})") from e
    raise lib.MirrorError(f"토큰 파일에 YOONHWAN_BOT_TOKEN 없음: {path}")


def read_rows(log: Path) -> list[dict[str, object]]:
    rows: dict[int, dict[str, object]] = {}
    for p in (Path(str(log) + ".1"), log):
        if not p.exists():
            continue
        text = p.read_text(encoding="utf-8")
        lines = text.split("\n")
        if not text.endswith("\n"):
            lines = lines[:-1]  # 쓰는 중인 마지막 조각은 다음 패스에서 읽는다
        for ln in filter(str.strip, lines):
            try:
                r = json.loads(ln)
                rows[int(r["seq"])] = r
            except (ValueError, KeyError, TypeError) as e:
                raise lib.MirrorError(f"{p.name} 손상 행: {ln[:60]!r}") from e
    return [rows[k] for k in sorted(rows)]


def save_state(path: Path, st: dict[str, object]) -> None:
    tmp = path.with_suffix(".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(st, f, ensure_ascii=False)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


class Mirror:
    def __init__(self, a: argparse.Namespace):
        self.a = a
        self.log = Path(a.mailbox)
        self.state_path = Path(a.state_dir) / f"byz_mbox_slack_mirror.{a.project}.json"
        self.seat = re.compile(a.seat)
        self.token = "" if a.dry_run else read_token(Path(a.token_file).expanduser())
        self.posted = 0

    def _post(self, text: str, thread_ts: str | None = None) -> str:
        return lib.post(self.a.api_base, self.token, self.a.channel, text, thread_ts)

    def _thread_ts(self, st: dict[str, object], item: dict[str, object], resume: bool) -> str:
        threads = st.setdefault("threads", {})
        assert isinstance(threads, dict)
        key = str(item.get("key", lib.OTHER_KEY))
        if key not in threads:
            ts = self._find_root(key) if resume else None  # 루트만 올라가고 죽은 경우 되찾는다
            threads[key] = ts or self._post(lib.root_text(key, str(item.get("what", "")) or key))
            while len(threads) > MAX_THREADS:
                del threads[next(iter(threads))]
            save_state(self.state_path, st)
        return str(threads[key])

    def _find_root(self, key: str) -> str | None:
        marker = lib.root_marker(key)
        for ts, text in lib.channel_roots(self.a.api_base, self.token, self.a.channel):
            if lib.has_marker([text], marker):
                return ts
        return None

    def _send_item(self, st: dict[str, object], item: dict[str, object], resume: bool) -> None:
        ts = self._thread_ts(st, item, resume)
        if resume:  # 조회가 실패하면 raise — 중복보다 지연
            texts = lib.thread_texts(self.a.api_base, self.token, self.a.channel, ts)
            if lib.has_marker(texts, str(item["id"])):
                return
        self._post(str(item["text"]), ts)

    def deliver(self, st: dict[str, object], item: dict[str, object], resume: bool = False) -> None:
        if self.a.dry_run:
            print(f"[thread {item.get('key')}]\n{item['text']}\n---")
            st["last_seq"] = item["seq"]  # 메모리만 — 저장 0 (안 올리면 다음 행이 가짜 공백으로 보인다)
        else:
            st["pending"] = item
            save_state(self.state_path, st)
            self._send_item(st, item, resume)
            st.update(last_seq=item["seq"], pending=None)
            save_state(self.state_path, st)
        self.posted += 1

    def run_pass(self) -> int:
        self.posted = 0
        rows = read_rows(self.log)
        st = json.loads(self.state_path.read_text(encoding="utf-8")) if self.state_path.exists() else None
        if st is None:  # 첫 실행 — 과거 행을 쏟아내지 않는다
            base = int(str(rows[-1]["seq"])) if rows else 0
            if not self.a.dry_run:
                save_state(self.state_path, {"last_seq": base, "pending": None, "threads": {}})
            print(f"baseline last_seq={base}", file=sys.stderr)
            return 0
        if st.get("pending"):
            self.deliver(st, st["pending"], resume=True)
        for r in rows:
            self._row(st, r)
        return self.posted

    def _summarize(self, seq: int, label: str, text: str) -> dict[str, str | None] | None:
        try:
            return summ.summarize(self.a.summarizer_cmd, label, text, self.a.summary_timeout)
        except summ.SummaryError as e:  # 보이게 내려간다: stderr ERROR + 꼬리 「원문 그대로」
            print(f"ERROR: 요약 실패 seq={seq}: {e} — 원문 첫 문장으로 게시", file=sys.stderr)
            return None

    def _row(self, st: dict[str, object], r: dict[str, object]) -> None:
        s, prev = int(str(r["seq"])), int(str(st["last_seq"]))
        if s <= prev:
            return
        if s > prev + 1:
            self.deliver(st, {"id": f"#GAP-{prev + 1}-{s - 1}", "seq": s - 1, "key": lib.OTHER_KEY,
                              "what": "슬랙 미러가 알리는 기록 공백", "text": lib.format_gap(prev + 1, s - 1)})
        if not self.seat.search(str(r.get("to", ""))):
            st["last_seq"] = s
            if not self.a.dry_run:
                save_state(self.state_path, st)
            return
        label, text = lib.classify(str(r.get("body", "")))
        summary = self._summarize(s, label, text)
        self.deliver(st, {"id": f"#{s}", "seq": s, "key": lib.thread_key(r, text),
                          "what": summary["what"] if summary else lib.first_sentence(text),
                          "text": lib.format_row(r, label, self.a.mention, summary, text)})


def parse() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--project", required=True)
    p.add_argument("--mailbox", required=True, help="mailbox.log.jsonl 경로")
    p.add_argument("--seat", required=True, help="수신 좌석 정규식 예: ^byz-planner-arch#\\d+$")
    p.add_argument("--channel", required=True)
    p.add_argument("--state-dir", default=str(Path.home() / ".hermes" / "state"))
    p.add_argument("--token-file", default="~/.hermes/secrets/yoonhwan_bot.env")
    p.add_argument("--mention", default="", help="[HIL] 에서 멘션할 Slack 사용자 ID 1개(고정)")
    p.add_argument("--summarizer-cmd", default=summ.DEFAULT_CMD, help="프롬프트를 stdin 으로 받아 JSON 을 stdout 으로 내는 명령")
    p.add_argument("--summary-timeout", type=float, default=90.0)
    p.add_argument("--api-base", default=API)
    p.add_argument("--interval", type=float, default=5.0)
    p.add_argument("--once", action="store_true")
    p.add_argument("--dry-run", action="store_true")
    return p.parse_args()


def main() -> int:
    a = parse()
    Path(a.state_dir).mkdir(parents=True, exist_ok=True)
    lock = open(Path(a.state_dir) / f"byz_mbox_slack_mirror.{a.project}.lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        print("ERROR: 다른 미러 인스턴스가 실행 중", file=sys.stderr)
        return 2
    try:
        m = Mirror(a)
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
