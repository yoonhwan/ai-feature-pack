#!/usr/bin/env python3
"""byz_slack_mbox_inbound — #byz-planner 의 오빠(사람) 글 → 좌석 mbox (Slack→mbox 역방향 · Issue #820).

정본 설계: design/harness/DESIGN-slack-inbound-820.md §5·§6. 계약 = «유실 0 · 중복은 최악 1회».
메시지별 영속 원장(ledger): 계획(수신자·본문 고정) → 수신자별 attempt 횟수 → send → done. 미완료 항목은 Slack 을 다시
읽지 않아도 독립적으로 재개한다(7일이 지나도 지우지 않는다). 재시작 때 attempt 인데 done 이 아니면 큐·사본 로그에서
«그 수신자의 꼬리 줄 토큰» 을 찾고, 흔적이 없으면 1회만 다시 보낸다(attempt 2 에서도 흔적이 없으면 멈추고 알린다).
수신자 큐가 가득(>=10)이면 밀려나게 두지 않고 보내지 않은 채 Slack 에 알린다. 실패는 전부 raise(exit 1) · launchd 재기동.
"""
import argparse
import fcntl
import json
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mirror_inbound as ib  # noqa: E402
import mirror_lib as lib  # noqa: E402
import mirror_questions as mq  # noqa: E402
import mirror_share as ms  # noqa: E402
from mirror_plan import plan  # noqa: E402

API = "https://slack.com/api"
WINDOW = 7 * 86400


def now_ts() -> str:
    return f"{time.time():.6f}"


class Inbound:
    def __init__(self, a: argparse.Namespace):
        self.a = a
        d = Path(a.state_dir)
        self.state_path = d / f"byz_slack_mbox_inbound.{a.channel}.json"
        self.qpath = d / f"byz_slack_questions.{a.channel}.json"
        self.spool = d / "spool"
        self.comm = Path(a.mbox).parent
        self.planner_seats = a.planner_seats or str(Path(a.seats_file).parent / "seats-planner.json")  # 명부 «경로» 만 유도 — 이름은 매번 live_planner
        self.token = lib.read_token(Path(a.token_file).expanduser())
        self.sent = 0
        self.seen_updates: dict[str, str] = {}

    def _save(self, st: dict[str, object]) -> None:
        lib.save_state(self.state_path, st)

    # --- Slack 읽기 -------------------------------------------------------------------------
    def _candidates(self, st: dict[str, object]) -> list[dict[str, object]]:
        base, tok, ch, baseline = self.a.api_base, self.token, self.a.channel, str(st["baseline"])
        ledger, seen = st["ledger"], st["seen"]
        assert isinstance(ledger, dict) and isinstance(seen, dict)
        found: dict[str, dict[str, object]] = {}
        threads: dict[str, str | None] = {}
        for m in lib.paged(base, tok, "conversations.history", {"channel": ch, "oldest": f"{time.time() - WINDOW:.6f}", "limit": 200}):
            if ib.is_human(m, self.a.human) and str(m["ts"]) > baseline:
                found[str(m["ts"])] = {**m, "thread_ts": ""}
            if m.get("latest_reply"):  # 기동 «전» 에 만들어진 스레드의 새 답도 여기서 발견된다
                threads[str(m["ts"])] = str(m["latest_reply"])
        for e in mq.load(self.qpath)["open"].values():  # 열린 질문의 스레드는 루트 순위와 무관하게 항상 읽는다
            if e.get("thread_ts"):
                threads.setdefault(str(e["thread_ts"]), None)
        for t, latest in threads.items():
            if latest is not None and seen.get(t) == latest:
                continue
            for m in lib.paged(base, tok, "conversations.replies", {"channel": ch, "ts": t, "oldest": baseline, "limit": 200}):
                if str(m["ts"]) != t and ib.is_human(m, self.a.human) and str(m["ts"]) > baseline:
                    found[str(m["ts"])] = {**m, "thread_ts": t}
            if latest is not None:
                self.seen_updates[t] = latest
        return sorted((m for ts, m in found.items() if ts not in ledger), key=lambda m: str(m["ts"]))

    # --- 전달 (Slack 을 다시 읽지 않고 원장만으로 재개) -------------------------------------------
    def _notice(self, e: dict, key: str, text: str) -> None:
        if not e.get(key):
            print(f"ERROR: {text}", file=sys.stderr)
            lib.post(self.a.api_base, self.token, self.a.channel, ms.tag("상태", text), e.get("thread") or None)
            e[key] = True

    def _deliver(self, st: dict[str, object], ts: str, e: dict) -> None:
        if not e["recips"]:  # 빈 수신자를 «다 보냈다» 로 읽지 않는다(all([]) 은 참)
            self._notice(e, "no_recips_notified", "오빠 글 수신자 0 — 원문 보관됨")
            return
        for role in e["recips"]:
            if e["done"].get(role):
                continue
            to, why = ib.resolve(role, self.planner_seats)
            if to is None:  # 현역 planner 를 모르면 보내지 않고 보관 — done 이 아니라 다음 패스에 다시 정한다
                self._notice(e, f"planner_missing_notified:{why}", f"오빠 글 전달 대기 — planner 현역 세션 확인 불가({why}) · 원문 보관됨")
                continue
            if role != to and to in e["recips"]:  # 질문 좌석이 곧 현역 planner — 같은 좌석에 두 번 보내지 않는다
                e["done"][role] = to
                continue
            tok, (n, names) = f"slack:{ts}:{role}", ib.sent_names(e, role)
            seen = next((nm for nm in sorted(names) if ib.marker_seen(self.comm, tok, nm) or ib.marker_seen(self.comm, f"slack:{ts}:{nm}", nm)), None)
            if n and seen:
                e["done"][role] = seen  # 이미 큐에 들어간 전달(옛 이름 큐 포함) — 다시 보내지 않는다
            elif n >= 2:  # 흔적 없이 두 번 보냈다 — 더 보내면 «최악 1회» 중복을 넘는다. 멈추고 사람에게 알린다
                self._notice(e, "stuck_notified", f"오빠 글을 {to} 에게 전달했는지 확인할 수 없어요 — 두 번 보내도 흔적이 없어서 멈췄어요. 사람 확인이 필요해요")
                continue
            elif ib.queue_len(self.comm, to) >= ib.RING:  # 가득 찬 큐에 넣으면 오래된 메시지가 밀린다 — 보내지 않고 알린다
                self._notice(e, "full_notified", f"{to} 의 mbox 큐가 가득 차 오빠 글 전달을 미뤘어요 — 좌석이 읽어야 전달돼요")
                continue
            else:
                e["attempt"][role] = [*e["attempt"].get(role, []), to] if role == ms.PLANNER_ROLE else n + 1
                self._save(st)  # 시도 «전» 기록
                seq = ib.send(self.a.mbox, to, f"[{ib.FROM}->{to}] {e['text']}\n({tok})", self.spool)
                e["done"][role] = to
                if role == e["recips"][0]:
                    e["mbox_seq"] = seq
            self._save(st)
        if not all(e["done"].get(role) for role in e["recips"]):
            return
        if e.get("q"):
            mq.set_delivered(self.qpath, int(e["q"]), ts, int(e.get("mbox_seq", 0)))
        if e.get("confirm"):
            mq.close(self.qpath, int(e["confirm"]))
        if self.qpath.exists():
            mq.update_board(self.qpath, self.a.api_base, self.token, self.a.channel, self.planner_seats)
        e["finished"] = True
        self._save(st)
        self.sent += 1

    def run_pass(self) -> int:
        self.sent = 0
        st = json.loads(self.state_path.read_text(encoding="utf-8")) if self.state_path.exists() else None
        if st is None:  # 첫 실행 — 과거 글을 쏟아내지 않는다
            self._save({"baseline": now_ts(), "ledger": {}, "seen": {}})
            print("baseline", file=sys.stderr)
            return 0
        st.setdefault("seen", {})
        ledger: dict[str, dict] = st["ledger"]
        for ts in sorted(k for k, v in ledger.items() if not v.get("finished")):
            ib.migrate_planner(ledger[ts])  # B-r3: 옛 planner 이름 수신자를 «역할» 로 1회 이관
            self._deliver(st, ts, ledger[ts])  # 미완료는 나이와 상관없이 독립 재개
        self.seen_updates = {}
        for m in self._candidates(st):
            ts = str(m["ts"])
            ledger[ts] = plan(self.a, self.token, self.qpath, m)
            self._save(st)
            self._deliver(st, ts, ledger[ts])
        st["seen"].update(self.seen_updates)  # 후보를 전부 원장에 올린 뒤에만 «읽었다» 로 표시한다
        cut = time.time() - WINDOW  # 끝난 항목만 정리 — 미완료는 지우지 않는다
        st["ledger"] = {k: v for k, v in ledger.items() if not v.get("finished") or float(k) > cut}
        self._save(st)
        if self.qpath.exists():
            mq.update_board(self.qpath, self.a.api_base, self.token, self.a.channel, self.planner_seats)  # 있어야 할 모습으로 맞춘다(글이 같으면 호출 0)
        return self.sent


def parse() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--channel", required=True)
    p.add_argument("--human", required=True, help="답을 받을 Slack 사용자 ID 1개(고정) 예: U0AC2JF0M7D")
    p.add_argument("--mbox", required=True, help="mbox.sh 경로")
    p.add_argument("--seats-file", required=True, help="같은 폴더의 seats-planner.json 으로 현역 planner 를 찾는다(_hil_route 는 읽지 않는다)")
    p.add_argument("--planner-seats", default="", help="planner 명부 경로(기본 = --seats-file 폴더의 seats-planner.json)")
    p.add_argument("--state-dir", default=str(Path.home() / ".hermes" / "state"))
    p.add_argument("--token-file", default="~/.hermes/secrets/yoonhwan_bot.env")
    p.add_argument("--api-base", default=API)
    p.add_argument("--interval", type=float, default=10.0)
    p.add_argument("--once", action="store_true")
    return p.parse_args()


def main() -> int:
    a = parse()
    Path(a.state_dir).mkdir(parents=True, exist_ok=True)
    lock = open(Path(a.state_dir) / f"byz_slack_mbox_inbound.{re.sub(r'[^A-Za-z0-9]', '', a.channel)}.lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        print("ERROR: 다른 inbound 인스턴스가 실행 중", file=sys.stderr)
        return 2
    try:
        m = Inbound(a)
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
