#!/usr/bin/env python3
"""ft_queue_watch — 좌석 우편함 «거의 참» 경보 (r630).

좌석 우편함은 ring(FT_MBOX_RING · 기본 10)건이 차면 가장 오래된 쪽지를 조용히 버린다. 그 전에(ring-2 건+) 그 좌석
팀 명부 `_master` 에 «[우편함 거의 참]» 1통. 명부 = 명부 폴더의 seats*.json 전부(desk 가 있는 planner 명부 포함).
좌석이 곧 자기 팀 `_master` 면 planner 명부 `_master` 에 · 그것도 자기면 WARN 1줄(쪽지 0).

scan --mbox <mbox.sh> --rosters <.fable-team> --state <json>  틱 전용 — 서명(건수·가장 오래된 seq)이 바뀐 좌석만 1통
mail --mbox <mbox.sh> --rosters <.fable-team> --seat <좌석>    슬랙 수신 데몬 «가득 참» 미룸 때 1통
출력 = SENT / WARN / ERROR 줄(조용한 0 없음) · rc 0(감시 실패가 틱을 멈추지 않게) · 인자 잘못 = rc 2.
"""
import argparse
import fcntl
import json
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ft_stall_detect import load_teams  # noqa: E402

RING = int(os.environ.get("FT_MBOX_RING") or 10)
NEAR = RING - 2  # harness-monitor.sh ring-2 판정과 같은 문턱


def teams(rosters: Path) -> list[dict]:
    """깨진 명부는 ERROR 1줄 뒤 건너뜀(load_teams 는 조용히 건너뛴다) — 나머지 명부는 계속 본다."""
    for f in sorted(rosters.glob("seats*.json")):
        try:
            json.loads(f.read_text(encoding="utf-8"))
        except (OSError, ValueError) as e:
            print(f"ERROR 명부를 못 읽음 {f}: {e} — 이 명부 좌석만 감시 건너뜀")
    return load_teams(rosters.parent)


def target(ts: list[dict], seat: str) -> str | None:
    own = next((t["master"] for t in ts if seat in t["seats"] or t["master"] == seat), None)
    if own and own != seat:
        return own
    planner = next((t["master"] for t in ts if t["team"] == "planner"), None)
    if planner and planner != seat:
        return planner
    print(f"WARN {seat} 우편함 거의 참인데 알릴 master 없음(자기 팀·planner _master = {own or '-'}·{planner or '-'}) — 쪽지 0")
    return None


def queue(mbox: str) -> dict[str, list[int]]:
    by: dict[str, list[int]] = {}
    p = Path(mbox).parent / "mailbox.jsonl"
    for ln in p.read_text(encoding="utf-8").splitlines() if p.exists() else []:
        try:
            r = json.loads(ln)
        except ValueError:
            continue
        by.setdefault(str(r.get("to")), []).append(int(r.get("seq") or 0))
    return by


def mail(mbox: str, to: str, seat: str, n: int) -> bool:
    body = f"[우편함 거의 참] {seat} 미읽음 {n}/{RING} — 그 좌석이 recv 해야 함 · 넘치면 오래된 것부터 사라짐"
    try:
        r = subprocess.run(["bash", mbox, "send", to, "ft-tick", body], capture_output=True, text=True, timeout=7)
    except subprocess.TimeoutExpired:
        print(f"ERROR {seat} → {to} 쪽지 7초 초과")
        return False
    if r.returncode:
        print(f"ERROR {seat} → {to} 쪽지 실패 rc={r.returncode}: {(r.stderr.strip().splitlines() or ['-'])[-1][:200]}")
        return False
    print(f"SENT {to} {seat} {n}/{RING}")
    return True


def scan(a: argparse.Namespace) -> int:
    ts, by = teams(Path(a.rosters)), queue(a.mbox)
    state = Path(a.state)
    state.parent.mkdir(parents=True, exist_ok=True)
    with open(f"{state}.lock", "w") as lk:  # 팀 틱 여럿이 같은 서명 파일을 쓴다
        fcntl.flock(lk, fcntl.LOCK_EX)
        try:
            old = json.loads(state.read_text(encoding="utf-8")) if state.exists() else {}
        except ValueError:
            print(f"ERROR 서명 파일 깨짐 {state} — 새로 시작")
            old = {}
        new: dict[str, list[int]] = {}
        for seat in sorted({s for t in ts for s in t["seats"]}):
            seqs = by.get(seat, [])
            if len(seqs) < NEAR:
                continue
            sig, prev = [len(seqs), min(seqs)], old.get(seat)
            if prev and sig[0] <= prev[0] and sig[1] == prev[1]:
                new[seat] = prev
                continue
            to = target(ts, seat)
            new[seat] = sig if to and mail(a.mbox, to, seat, sig[0]) else (prev or [0, -1])
        state.write_text(json.dumps(new, ensure_ascii=False), encoding="utf-8")
    return 0


def mail_one(a: argparse.Namespace) -> int:
    to = target(teams(Path(a.rosters)), a.seat)
    if to:
        mail(a.mbox, to, a.seat, len(queue(a.mbox).get(a.seat, [])))
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in ("scan", "mail"):
        s = sub.add_parser(name)
        s.add_argument("--mbox", required=True)
        s.add_argument("--rosters", required=True)
        s.add_argument("--state" if name == "scan" else "--seat", required=True)
    a = p.parse_args()
    return scan(a) if a.cmd == "scan" else mail_one(a)


if __name__ == "__main__":
    sys.exit(main())
