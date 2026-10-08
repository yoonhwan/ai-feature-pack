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
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mirror_board as mb  # noqa: E402
import mirror_lib as lib  # noqa: E402
import mirror_summary as summ  # noqa: E402
import mirror_questions as mq  # noqa: E402
import resume_block as rb  # noqa: E402
from mirror_deliver import Deliverer, seed_threads  # noqa: E402

API = "https://slack.com/api"


def format_gap(first: int, last: int) -> str:
    n = last - first + 1
    return (f"[상태] 슬랙에 못 올라간 보고가 {n}건 있어요 — 보낸 기록이 비어 있어요\n"
            f"할 일 없음 — 하네스 담당이 확인해요\n(mirror · #GAP-{first}-{last})")


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


class Mirror:
    def __init__(self, a: argparse.Namespace):
        mb.check_args(a)
        self.a = a
        self.log = Path(a.mailbox)
        self.state_path = Path(a.state_dir) / f"byz_mbox_slack_mirror.{a.project}.json"
        self.seat = re.compile(a.seat)
        self.planner_seats = a.planner_seats or str(self.log.resolve().parent.parent / "seats-planner.json")  # 명부 «경로» 만 유도 — 현역 이름은 매번 live_planner
        self.resume_script = Path(a.resume_script) if a.resume_script else self.log.resolve().parent.parent / "bin" / "ft-resume-cmd.sh"
        if not self.resume_script.is_file():
            raise lib.MirrorError(f"재개 명령 스크립트 없음: {self.resume_script} (--resume-script)")
        self.token = "" if a.dry_run else lib.read_token(Path(a.token_file).expanduser())
        self.threads_path = Path(a.state_dir) / f"byz_slack_threads.{a.channel}.json"
        self.qpath = Path(a.state_dir) / f"byz_slack_questions.{a.channel}.json"
        self.deliv = Deliverer(a.api_base, self.token, a.channel, self.threads_path)
        self.posted = 0

    def _send_item(self, item: dict[str, object], resume: bool) -> None:
        q = item.get("question")
        if isinstance(q, dict):  # 루트 확보 → 질문 등록 → 카드 게시: 카드 직후 답해도 열린 질문이 이미 있다
            ts = self.deliv.thread_ts(item, resume)
            mq.add(self.qpath, int(str(item["seq"])), {**q, "thread_ts": ts})
            mq.update_board(self.qpath, self.a.api_base, self.token, self.a.channel, self.planner_seats)
        self.deliv.send(item, resume)

    def _close_answered(self, r: dict[str, object], key: str) -> None:
        """답이 전달된 질문은 «그 좌석이 같은 키로 다음 보고를 올릴 때» 닫힌다 — 좌석이 값으로 움직였다는 증거."""
        if self.a.dry_run or not self.qpath.exists():
            return
        mq.update_board(self.qpath, self.a.api_base, self.token, self.a.channel, self.planner_seats)  # 이전 패스에서 close 만 되고 끊긴 보드도 맞춘다(글이 같으면 호출 0)
        seqs = mq.delivered_for(mq.load(self.qpath), key, str(r.get("from", "")), int(str(r["seq"])))
        for q in seqs:
            mq.close(self.qpath, q)
        if seqs:
            mq.update_board(self.qpath, self.a.api_base, self.token, self.a.channel, self.planner_seats)

    def deliver(self, st: dict[str, object], item: dict[str, object], resume: bool = False) -> None:
        if self.a.dry_run:
            print(f"[thread {item.get('key')}]\n{item['text']}\n---")
            st["last_seq"] = item["seq"]  # 메모리만 — 저장 0 (안 올리면 다음 행이 가짜 공백으로 보인다)
        else:
            st["pending"] = item
            lib.save_state(self.state_path, st)
            self._send_item(item, resume)
            st.update(last_seq=item["seq"], pending=None)
            lib.save_state(self.state_path, st)
        self.posted += 1

    def run_pass(self) -> int:
        self.posted = 0
        if not self.a.dry_run and self.qpath.exists():  # 닫는 사건 = planner 인박스 — 패스당 1회 · 닫힌 질문은 보드에서도 뺀다(글이 같으면 호출 0)
            mb.sweep(self.a, self.qpath, self.planner_seats, self.log.resolve().parents[2])
            mq.update_board(self.qpath, self.a.api_base, self.token, self.a.channel, self.planner_seats)
        rows = read_rows(self.log)
        st = json.loads(self.state_path.read_text(encoding="utf-8")) if self.state_path.exists() else None
        if st is None:  # 첫 실행 — 과거 행을 쏟아내지 않는다
            base = int(str(rows[-1]["seq"])) if rows else 0
            if not self.a.dry_run:
                lib.save_state(self.state_path, {"last_seq": base, "pending": None})
            print(f"baseline last_seq={base}", file=sys.stderr)
            return 0
        if not self.a.dry_run:  # 옛 state 의 스레드 맵 → 공유 맵 이관(맵 파일이 없을 때만)
            seed_threads(self.threads_path, dict(st.get("threads") or {}))
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
                              "what": "슬랙 미러가 알리는 기록 공백", "text": format_gap(prev + 1, s - 1)})
        if not self.seat.search(str(r.get("to", ""))) or str(r.get("from", "")) == "slack-oppa":  # 오빠 글(역방향이 넣은 행)은 메아리로 다시 올리지 않는다
            st["last_seq"] = s
            if not self.a.dry_run:
                lib.save_state(self.state_path, st)
            return
        label, text = lib.classify(str(r.get("body", "")))
        full = lib.read_full(r)
        summary = self._summarize(s, label, full or text)
        key = lib.thread_key(r, text)
        url = lib.issue_url(self.a.repo, key)
        urls = lib.links([text, full or ""], url)
        what = summary["what"] if summary else lib.first_sentence(text)
        opts = mq.parse_options(full or text) if label == "HIL" else []
        question = {"key": key, "seat": str(r.get("from", "")), "what": what, "options": opts} if label == "HIL" else None
        self._close_answered(r, key)
        self.deliver(st, {"id": f"#{s}", "seq": s, "key": key, "url": url, "what": what, "question": question,
                          "text": lib.format_row(r, label, self.a.mention, summary, text, block=rb.mirror_block(r, label, self.resume_script),
                                                 full=full, urls=urls, options_text=mq.format_options(opts) if label == "HIL" else None, seats=self.planner_seats)})


def parse() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--project", required=True)
    p.add_argument("--mailbox", required=True, help="mailbox.log.jsonl 경로")
    p.add_argument("--seat", required=True, help="수신 좌석 정규식 예: ^byz-planner-arch#\\d+$")
    p.add_argument("--channel", required=True)
    p.add_argument("--repo", default="", help="Issue 링크용 <소유자>/<저장소> — 비우면 링크 줄을 만들지 않는다")
    p.add_argument("--state-dir", default=str(Path.home() / ".hermes" / "state"))
    p.add_argument("--token-file", default="~/.hermes/secrets/yoonhwan_bot.env")
    p.add_argument("--mention", default="", help="[HIL] 에서 멘션할 Slack 사용자 ID 1개(고정)")
    p.add_argument("--summarizer-cmd", default=summ.DEFAULT_CMD, help="프롬프트를 stdin 으로 받아 JSON 을 stdout 으로 내는 명령")
    p.add_argument("--summary-timeout", type=float, default=90.0)
    p.add_argument("--api-base", default=API)
    p.add_argument("--planner-seats", default="", help="planner 명부(seats-planner.json) 경로 (기본 <mailbox 폴더 상위>/seats-planner.json)")
    p.add_argument("--resume-script", default="", help="ft-resume-cmd.sh (기본 <mailbox 폴더 상위>/bin/ft-resume-cmd.sh)")
    mb.add_args(p)
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
