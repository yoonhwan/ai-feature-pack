"""mirror_inbound — Slack 사람 글 읽기(페이지·필터)와 mbox 전달(토큰 검색·send·relay).

정본 설계: design/harness/DESIGN-slack-inbound-820.md §5 · §6.
"""
import hashlib
import json
import re
import subprocess
from pathlib import Path

import mirror_lib as lib

FROM = "slack-oppa"  # 오빠 글이 mbox 에 실릴 때의 발신자 이름 — 좌석이 아니다
RING = 10  # mbox 수신자별 큐 상한 — 가득 차면 오래된 것이 밀리므로 우리는 보내지 않고 미룬다
MAX_BODY = 600
_TAIL = re.compile(r"^\(([A-Za-z0-9._-]+#\d+) · #\d+[^)]*\)$")
_PICK = re.compile(r"^\s*(\d)\s*(?:번|\))?\s*$")


def unescape(text: str) -> str:
    return text.replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&")


def is_human(m: dict[str, object], allowed: str) -> bool:
    return m.get("user") == allowed and not m.get("bot_id") and m.get("subtype") in (None, "thread_broadcast")


def inferred_seat(thread_msgs: list[dict[str, object]]) -> str | None:
    """열린 질문이 없을 때만 쓰는 추정 — 스레드 루트와 «같은 봇» 이 올린 글의 꼬리 줄(= 3째 줄)만 믿는다."""
    if not thread_msgs:
        return None
    trusted = thread_msgs[0].get("bot_id")
    for m in reversed(thread_msgs):
        lines = str(m.get("text", "")).split("\n")
        if trusted and m.get("bot_id") == trusted and len(lines) >= 3:
            hit = _TAIL.match(lines[2].strip())
            if hit:
                return hit.group(1)
    return None


def resolve_pick(text: str, options: list[str]) -> str:
    m = _PICK.match(text)
    if m and 1 <= int(m.group(1)) <= len(options):
        n = int(m.group(1))
        return f"선택 {n}: {options[n - 1]}"
    return text


def planner_seat(seats_file: Path) -> str:
    try:
        seat = json.loads(seats_file.read_text(encoding="utf-8")).get("_hil_route")
    except (OSError, ValueError) as e:
        raise lib.MirrorError(f"seats 파일 읽기 실패: {seats_file} ({type(e).__name__})") from e
    if not seat:
        raise lib.MirrorError(f"seats 파일에 _hil_route 없음: {seats_file}")
    return str(seat)


def _rows(comm_dir: Path, names: tuple[str, ...]) -> list[dict[str, object]]:
    out: list[dict[str, object]] = []
    for name in names:
        p = comm_dir / name
        if not p.exists():
            continue
        for ln in p.read_text(encoding="utf-8").splitlines():
            try:
                r = json.loads(ln)
            except ValueError:
                continue
            if isinstance(r, dict):
                out.append(r)
    return out


def marker_seen(comm_dir: Path, token: str, to: str) -> bool:
    """큐와 사본 로그(회전본 포함)에서 «우리가 그 수신자에게 보낸 행» 의 꼬리 줄 「(토큰)」 과 정확히 같은 줄만 본다 — 부분문자열·다른 수신자·사람 글은 오탐이 아니다."""
    want = f"({token})"
    for r in _rows(comm_dir, ("mailbox.jsonl", "mailbox.log.jsonl", "mailbox.log.jsonl.1")):
        if r.get("from") == FROM and r.get("to") == to and any(ln.strip().endswith(want) for ln in str(r.get("body", "")).split("\n")):
            return True
    return False


def queue_len(comm_dir: Path, to: str) -> int:
    return sum(1 for r in _rows(comm_dir, ("mailbox.jsonl",)) if r.get("to") == to)


def send(mbox: str, to: str, body: str, spool: Path) -> int:
    """argv 로만 호출한다(셸 문자열 금지). 반환 = 큐에 들어간 행의 seq. 실패는 raise."""
    if len(body) > MAX_BODY:  # 긴 글은 relay 파일 + 머리 요약(토큰 포함)
        spool.mkdir(parents=True, exist_ok=True)
        f = spool / f"inbound-{hashlib.sha1(body.encode()).hexdigest()[:16]}.txt"
        f.write_text(body, encoding="utf-8")
        tail = body.rsplit("\n", 1)[-1]
        argv = ["bash", mbox, "relay", to, FROM, str(f), f"오빠(Slack) 긴 글 — 전문 파일 {tail}"]
    else:
        argv = ["bash", mbox, "send", to, FROM, body]
    try:
        r = subprocess.run(argv, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise lib.MirrorError(f"mbox 호출 실패: {type(e).__name__}") from e
    m = re.search(r"QUEUED seq=(\d+)", r.stdout)
    if r.returncode != 0 or not m:
        raise lib.MirrorError(f"mbox 전달 실패 rc={r.returncode}: {(r.stdout + r.stderr)[:120]}")
    return int(m.group(1))
