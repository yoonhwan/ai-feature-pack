#!/usr/bin/env python3
"""ft_queue_watch — 좌석 우편함 «거의 참» 경보 (r630).

좌석 우편함은 ring(FT_MBOX_RING · 기본 10)건이 차면 가장 오래된 쪽지를 조용히 버린다. 그 전에(ring-2 건+) 그 좌석
팀 명부 `_master` 에 «[우편함 거의 참]» 1통. 명부 = 명부 폴더의 seats*.json 전부(desk 가 있는 planner 명부 포함).
좌석이 곧 자기 팀 `_master` 면 planner 명부 `_master` 에 · 그것도 자기면 WARN 1줄(쪽지 0).

r639 — 서명은 송신 «전» 에 남긴다({sig, sent, retry_at}) · 송신 실패·7초 초과(큐엔 들어갔을 수 있음)는 30분 뒤 1회만 재시도 ·
죽은 좌석(tmux 세션 없음)은 그 팀 대신 `seats-harness.json` `_master` 에 «명부 행 정리 대상» 1통 · tmux 목록 못 읽음 = 살아 있음.

scan --mbox <mbox.sh> --rosters <.fable-team> --state <json>  틱 전용 — 서명(건수·가장 오래된 seq)이 바뀐 좌석만 1통
mail --mbox <mbox.sh> --rosters <.fable-team> --seat <좌석>    슬랙 수신 데몬 «가득 참» 미룸 때 1통
출력 = SENT / WARN / ERROR 줄(조용한 0 없음) · rc 0(감시 실패가 틱을 멈추지 않게) · 인자 잘못 = rc 2.
env(시험): FT_NOW · FT_QUEUE_WATCH_TIMEOUT(기본 7 — 7초 룰).
"""
import argparse
import fcntl
import json
import os
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ft_stall_detect import load_teams, run  # noqa: E402

RING = int(os.environ.get("FT_MBOX_RING") or 10)
NEAR = RING - 2  # harness-monitor.sh ring-2 판정과 같은 문턱
SEND_TIMEOUT = float(os.environ.get("FT_QUEUE_WATCH_TIMEOUT") or 7)
RETRY_SEC = 1800


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


def dead_target(rosters: Path, seat: str) -> str | None:
    try:
        hm = json.loads((rosters / "seats-harness.json").read_text(encoding="utf-8")).get("_master")
    except (OSError, ValueError, AttributeError):
        hm = None
    if hm and hm != seat:
        return hm
    print(f"WARN {seat} 죽은 좌석 우편함 거의 참인데 알릴 하네스 master 없음(seats-harness.json _master = {hm or '-'}) — 쪽지 0")
    return None


def live_sessions() -> set[str] | None:
    """tmux 세션 이름(틱 pane_of·계보 판정과 같은 list-panes) · 명령 실패 = None(전부 살아 있음으로 본다)."""
    rc, out = run(["tmux", "list-panes", "-a", "-F", "#{session_name}"], timeout=SEND_TIMEOUT)
    return {s for s in out.splitlines() if s} if rc == 0 else None


def entry(v: object) -> dict | None:
    """서명 행 — 1.1.172 판 [건수, seq] 는 «보냄» 으로 읽는다(판 교체로 다시 보내지 않게)."""
    if isinstance(v, list) and len(v) == 2:
        return {"sig": v, "sent": True, "retry_at": None}
    if isinstance(v, dict) and isinstance(v.get("sig"), list):
        return {"sig": v["sig"], "sent": bool(v.get("sent")), "retry_at": v.get("retry_at")}
    return None


def queue(mbox: str) -> dict[str, list[int]]:
    by: dict[str, list[int]] = {}
    p = Path(mbox).parent / "mailbox.jsonl"
    for ln in p.read_text(encoding="utf-8").splitlines() if p.exists() else []:
        try:
            r = json.loads(ln)
        except ValueError:
            continue
        if r.get("from") == r.get("to"):  # r1185: recv 가 안 가져가는 자기 행(r1155 _rows_for 와 같은 규칙)은 셈 밖
            continue
        by.setdefault(str(r.get("to")), []).append(int(r.get("seq") or 0))
    return by


def mail(mbox: str, to: str, seat: str, n: int, dead: bool = False) -> str:
    """보냄 = "" · 못 보냄 = 사유(송신 상한 초과 | 송신 실패)."""
    body = (f"[우편함 거의 참 · 죽은 좌석] {seat} 미읽음 {n}/{RING} — 명부 행 정리 대상" if dead else
            f"[우편함 거의 참] {seat} 미읽음 {n}/{RING} — 그 좌석이 recv 해야 함 · 넘치면 오래된 것부터 사라짐")
    try:
        r = subprocess.run(["bash", mbox, "send", to, "ft-tick", body], capture_output=True, text=True, timeout=SEND_TIMEOUT)
    except subprocess.TimeoutExpired:
        print(f"ERROR {seat} → {to} 쪽지 {SEND_TIMEOUT:g}초 초과(큐엔 들어갔을 수 있음)")
        return "송신 상한 초과"
    if r.returncode:
        print(f"ERROR {seat} → {to} 쪽지 실패 rc={r.returncode}: {(r.stderr.strip().splitlines() or ['-'])[-1][:200]}")
        return "송신 실패"
    print(f"SENT {to} {seat} {n}/{RING}")
    return ""


def attempt(a: argparse.Namespace, ts: list[dict], seat: str, n: int, retrying: bool, live: set[str] | None) -> dict:
    """한 좌석 1통 — 결과 서명 행. 실패·상한 초과 = 30분 뒤 1회 재시도 · 재시도도 실패면 서명이 바뀔 때까지 0."""
    dead = live is not None and seat not in live
    to = dead_target(Path(a.rosters), seat) if dead else target(ts, seat)
    why = mail(a.mbox, to, seat, n, dead) if to else "-"
    if not why:
        return {"sent": True, "retry_at": None}
    if not to:
        return {"sent": False, "retry_at": None}
    if retrying:
        print(f"ERROR {seat} 재시도도 {why} — 서명이 바뀔 때까지 다시 0")
        return {"sent": False, "retry_at": None}
    print(f"ERROR {seat} {why} · 다음 재시도 30분 뒤")
    return {"sent": False, "retry_at": a.now + RETRY_SEC}


def scan(a: argparse.Namespace) -> int:
    ts, by = teams(Path(a.rosters)), queue(a.mbox)
    a.now = float(os.environ.get("FT_NOW") or time.time())
    state = Path(a.state)
    state.parent.mkdir(parents=True, exist_ok=True)
    with open(f"{state}.lock", "w") as lk:  # 팀 틱 여럿이 같은 서명 파일을 쓴다
        fcntl.flock(lk, fcntl.LOCK_EX)
        try:
            raw = json.loads(state.read_text(encoding="utf-8")) if state.exists() else {}
        except ValueError:
            print(f"ERROR 서명 파일 깨짐 {state} — 새로 시작")
            raw = {}
        old = {k: e for k, v in (raw.items() if isinstance(raw, dict) else []) if (e := entry(v))}
        new: dict[str, dict] = {}
        hot = [s for s in sorted({s for t in ts for s in t["seats"]}) if len(by.get(s, [])) >= NEAR]
        live = live_sessions() if hot else None  # 문턱 넘은 좌석이 있을 때만 tmux 1회
        for seat in hot:
            seqs = by[seat]
            sig, prev = [len(seqs), min(seqs)], old.get(seat)
            same = bool(prev) and sig[0] <= prev["sig"][0] and sig[1] == prev["sig"][1]
            due = same and not prev["sent"] and prev["retry_at"] is not None and a.now >= prev["retry_at"]
            if same and not due:
                new[seat] = prev
                continue
            new[seat] = {"sig": sig, "sent": False, "retry_at": None}  # 송신 «전» 에 서명 — 틱이 송신 중 죽어도 반복 0
            state.write_text(json.dumps({**old, **new}, ensure_ascii=False), encoding="utf-8")
            new[seat].update(attempt(a, ts, seat, sig[0], due, live))
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
