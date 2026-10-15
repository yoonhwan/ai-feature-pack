"""mirror_inbound — Slack 사람 글 읽기(페이지·필터)와 mbox 전달(토큰 검색·send·relay).

정본 설계: design/harness/DESIGN-slack-inbound-820.md §5 · §6.
"""
import argparse
import hashlib
import json
import re
import subprocess
from collections.abc import Callable
from pathlib import Path

import mirror_lib as lib
import mirror_share as ms

PLANNER_TEAM = "byz-planner-"  # 옛 원장 이관 기준 접두 — `_master` 계보 일치는 역할명까지 바뀐 승계(arch#3 → master-claude#4)를 놓친다
FROM = "slack-oppa"  # 오빠 글이 mbox 에 실릴 때의 발신자 이름 — 좌석이 아니다
RING = 10  # mbox 수신자별 큐 상한 — 가득 차면 오래된 것이 밀리므로 우리는 보내지 않고 미룬다
MAX_BODY = 600
REJECT_RC = 3  # mbox 가드 REJECT(은퇴·닫힌 좌석) — 큐 적재 0
_TAIL = re.compile(r"^\(([A-Za-z0-9._-]+#\d+) · #\d+[^)]*\)$")
_PICK = re.compile(r"^\s*(\d)\s*(?:번|\))?\s*$")


def unescape(text: str) -> str:
    return text.replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&")


def is_user_post(m: dict[str, object]) -> bool:
    return bool(m.get("user")) and not m.get("bot_id") and m.get("subtype") in (None, "thread_broadcast")


def is_human(m: dict[str, object], allowed: str | frozenset[str]) -> bool:
    ids = frozenset({allowed}) if isinstance(allowed, str) else allowed
    return m.get("user") in ids and is_user_post(m)


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


def resolve(to: str, planner_seats: str | Path | None, to_key: str | None = None) -> tuple[str | None, str]:
    """수신자 표식 → (보낼 이름 | None, 사유). `@planner` 는 매번 명부 `_master` + tmux 생존으로 정한다(`_hil_route` 는 읽지 않는다).
    `to_key`(--to-key)가 있으면 모든 수신자를 명부 그 키(예 `_desk`)의 현역 좌석으로 — 전달마다 다시 읽는다(승계 뒤 손 대응 0)."""
    if to_key:  # 키 모드: 어떤 수신자 표식도 그 키의 현역 좌석으로 — 다른 좌석 도달 0 · 좌석 이름 고정 0
        return ms.live_planner(planner_seats, to_key)
    return ms.live_planner(planner_seats) if to == ms.PLANNER_ROLE else (to, "")


def sent_names(e: dict, role: str) -> tuple[int, set[str]]:
    """(시도 횟수, 보낸 이름들) — `@planner` 의 attempt 는 보낸 이름 목록, 나머지는 횟수 정수(옛 원장 호환)."""
    a = e["attempt"].get(role, 0)
    return (len(a), set(a)) if isinstance(a, list) else (int(a), {role} if a else set())


def migrate_planner(e: dict) -> None:
    """B-r3: 옛 원장의 planner 팀 접두(byz-planner-) 수신자를 `@planner` 로 1회 이관한다(done·attempt 도 옮겨 재발송 0).
    질문 좌석·추정 좌석은 접두가 달라 건드리지 않는다. 이미 이관된 항목은 아무것도 하지 않는다."""
    old = [to for to in e["recips"] if to.startswith(PLANNER_TEAM)]
    if not old:
        return
    role, tried = ms.PLANNER_ROLE, list(e["attempt"].get(ms.PLANNER_ROLE, []))
    for to in old:
        if e["done"].pop(to, None):
            e["done"].setdefault(role, to)
        tried += [to] * int(e["attempt"].pop(to, 0))
    if tried:
        e["attempt"][role] = tried
    i = min(e["recips"].index(to) for to in old)
    e["recips"] = [t for n, t in enumerate(e["recips"]) if t not in old and t != role]
    e["recips"].insert(i, role)


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


class MboxError(lib.MirrorError):
    """mbox 호출 실패 — rc 는 종료 코드(시간초과·실행 실패는 None). 문자열 매칭 대신 rc 로 가른다."""

    def __init__(self, msg: str, rc: int | None = None):
        super().__init__(msg)
        self.rc = rc


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
        raise MboxError(f"mbox 호출 실패: {type(e).__name__}") from e
    m = re.search(r"QUEUED seq=(\d+)", r.stdout)
    if r.returncode != 0 or not m:
        raise MboxError(f"mbox 전달 실패 rc={r.returncode}: {(r.stdout + r.stderr)[:120]}", r.returncode)
    return int(m.group(1))


def attempt_send(e: dict, role: str, to: str, n: int, tok: str, a: argparse.Namespace, spool: Path, seats: str, save: Callable[[], None]) -> tuple[str, int] | None:
    """시도 «전» 기록 → send → (보낸 이름, seq). 동적 수신자(@planner · 명부 키)가 가드에 거절되면(rc 3 = 큐 적재 0 이 확실) 그 시도를 빼고
    명부를 1회 다시 읽어 이름이 바뀌었으면 그 이름으로 다시 보낸다. 같거나 못 정하면 None(보관). rc≠3 실패는 시도로 남기고 raise."""
    prev = e["attempt"].get(role)
    for _ in range(2):
        e["attempt"][role] = [*(prev or []), to] if role == ms.PLANNER_ROLE else n + 1
        save()
        try:
            return to, send(a.mbox, to, f"[{FROM}->{to}] {e['text']}\n({tok})", spool)
        except MboxError as err:
            if err.rc != REJECT_RC or not (a.to_key or role == ms.PLANNER_ROLE):
                raise
            if prev is None:
                e["attempt"].pop(role)
            else:
                e["attempt"][role] = prev
            save()  # 확정 미적재는 «먼저» 영속 — 이어지는 명부·tmux 재조회 도중 재시작돼도 시도 0 (DA⑥ H1)
        again, _ = resolve(role, seats, a.to_key)
        if again is None or again == to:
            break
        to = again
    return None
