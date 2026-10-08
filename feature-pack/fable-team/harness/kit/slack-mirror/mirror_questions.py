"""mirror_questions — 열린 질문(오빠 답을 기다리는 [HIL])의 공유 저장소와 «보드» 메시지.

정방향 미러가 카드 «전» 에 add, 역방향이 답을 좌석에 전달하면 delivered, 좌석이 같은 키로 다음 보고를 올리면 close.
해소된 질문은 tombstone(resolved)에 남겨 재개 때 부활하지 않는다. 보드 = 채널 메시지 1개를 chat.update 로 제자리 갱신.
정본 설계: design/harness/DESIGN-slack-inbound-820.md §3·§4·§6.
"""
import json
import os
import re
import time
from pathlib import Path

import mirror_deliver as dv
import mirror_lib as lib
import mirror_share as ms

_CIRCLED = {"①": 1, "②": 2, "③": 3, "④": 4}
_OPT = re.compile(r"^\s*(?:(\d)\s*[).]|([①②③④]))\s*(\S.*)$")
MAX_OPTIONS = 4
BOARD_HEAD = "[상태] 결정 대기"
OLD_BOARD_HEAD = "답을 기다리는 질문"  # 머리표 도입 전 보드 — 새 글을 또 올리지 않고 이 글을 찾아 제자리 갱신한다
Q_PREFIX = re.compile(r"^\s*Q(\d+)(?!\d)\s*")
_ASKS = re.compile(r"[?？]|선택|고르|골라|번호|답해|판정")


def parse_options(text: str) -> list[str]:
    """본문 «마지막» 연속 번호 블록(1부터 이어지는 2개 이상) 중 바로 위 줄이 질문처럼 보이는(?·선택·번호·판정…) 것만 선택지다 — 절차 목록 오인을 줄인다."""
    blocks: list[tuple[str, dict[int, str]]] = []
    cur: dict[int, str] = {}
    above, prev = "", ""
    for ln in text.splitlines():
        m = _OPT.match(ln)
        n = (int(m.group(1)) if m.group(1) else _CIRCLED[m.group(2)]) if m else 0
        if m and n == len(cur) + 1:
            if not cur:
                above = prev
            cur[n] = m.group(3).strip()
            continue
        if cur:
            blocks.append((above, cur))
            cur = {}
        if m and n == 1:
            above = prev
            cur[1] = m.group(3).strip()
        elif ln.strip():
            prev = ln
    if cur:
        blocks.append((above, cur))
    good = [b for ab, b in blocks if len(b) >= 2 and _ASKS.search(ab)]
    return list(good[-1].values())[:MAX_OPTIONS] if good else []


def format_options(options: list[str]) -> str:
    """선택지는 참고용 한 줄 — 답하는 법·질문 번호는 싣지 않는다(슬랙은 읽기 전용). 없으면 빈 문자열(줄 생략)."""
    return "선택지(참고): " + " ".join(f"{i}) {lib.esc(o)}" for i, o in enumerate(options, 1)) if options else ""


def load(path: Path) -> dict[str, dict]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        data = {}
    except (ValueError, OSError) as e:
        raise lib.MirrorError(f"열린 질문 파일 읽기 실패: {path} ({type(e).__name__})") from e
    return {"open": dict(data.get("open", {})), "resolved": dict(data.get("resolved", {})), "meta": dict(data.get("meta", {}))}


def _save(path: Path, data: dict[str, dict]) -> None:
    tmp = path.with_suffix(".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def add(path: Path, seq: int, entry: dict[str, object]) -> bool:
    """멱등 — 이미 열렸거나 해소된(tombstone) 질문은 건드리지 않는다. 새로 열렸으면 True."""
    with dv.locked(path):
        data = load(path)
        if str(seq) in data["open"] or str(seq) in data["resolved"]:
            return False
        data["open"][str(seq)] = {**entry, "state": "open", "asked_at": int(time.time())}
        _save(path, data)
        return True


def set_delivered(path: Path, seq: int, answer_ts: str, mbox_seq: int = 0) -> None:
    with dv.locked(path):
        data = load(path)
        e = data["open"].get(str(seq))
        if e and e.get("state") == "open":
            e.update(state="delivered", answer_ts=answer_ts, mbox_seq=mbox_seq)
            _save(path, data)


def close(path: Path, seq: int) -> bool:
    with dv.locked(path):
        data = load(path)
        gone = data["open"].pop(str(seq), None) is not None
        if gone:
            data["resolved"][str(seq)] = int(time.time())
            _save(path, data)
        return gone


def in_thread(data: dict[str, dict], thread_ts: str, state: str = "open") -> list[tuple[int, dict]]:
    return sorted((int(k), e) for k, e in data["open"].items() if e.get("thread_ts") == thread_ts and e.get("state") == state)


def delivered_for(data: dict[str, dict], key: str, seat: str, row_seq: int) -> list[int]:
    """답 전달(mbox_seq) «이후» 에 그 좌석이 같은 키로 올린 보고만 닫는다 — 답 전에 큐에 있던 옛 보고는 증거가 아니다."""
    return [int(k) for k, e in data["open"].items()
            if e.get("state") == "delivered" and e.get("key") == key and e.get("seat") == seat and row_seq > int(e.get("mbox_seq", 0))]


def set_notes(path: Path, notes: list[str]) -> None:
    """보드 첫 줄 끝 경고(인박스 밖 k건 · 정리 확인 불가(<사유>)) — 저장소 meta 에 두어 보드 갱신 호출부가 모두 같은 경고를 읽는다."""
    with dv.locked(path):
        data = load(path)
        if data["meta"].get("board_notes", []) != notes:
            data["meta"]["board_notes"] = notes
            _save(path, data)


def render_board(*args, **kwargs) -> str:
    """본체는 mirror_board.render_board(바이트 상한 3500) — 순환 import 를 피해 호출 시점에 import 한다."""
    import mirror_board as mb
    return mb.render_board(*args, **kwargs)


def update_board(path: Path, api_base: str, token: str, channel: str, seats: str | None = None) -> None:
    """보드를 올리거나(처음 — 채널에 이미 있으면 재사용) 제자리 갱신한다. 글이 그대로면 API 를 부르지 않는다. 실패는 raise."""
    with dv.locked(path):
        data = load(path)
        text = render_board(data["open"], place=ms.place_text(seats), notes=data["meta"].get("board_notes", []))
        ts = data["meta"].get("board_ts")
        if ts and data["meta"].get("board_text") == text:
            return
        if not ts:
            for m in lib.paged(api_base, token, "conversations.history", {"channel": channel, "limit": 200}):
                if m.get("bot_id") and not m.get("thread_ts") and str(m.get("text", "")).startswith((BOARD_HEAD, OLD_BOARD_HEAD)):
                    ts = str(m["ts"])
                    break
        if ts:
            lib.api_call(api_base, token, "chat.update", {"channel": channel, "ts": ts, "text": text})
        else:
            ts = lib.post(api_base, token, channel, text)
        data["meta"].update(board_ts=ts, board_text=text)
        _save(path, data)
