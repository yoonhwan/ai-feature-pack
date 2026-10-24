"""mirror_questions — 열린 질문(오빠 답을 기다리는 [HIL])의 공유 저장소와 «보드» 메시지.

정방향 미러가 카드 «전» 에 add, 역방향이 답을 좌석에 전달하면 delivered, 좌석이 같은 키로 다음 보고를 올리면 close.
해소된 질문은 tombstone(resolved)에 남겨 재개 때 부활하지 않는다. 보드 = 채널 메시지 1개를 chat.update 로 제자리 갱신.
정본 설계: design/harness/DESIGN-slack-inbound-820.md §3·§4·§6.
"""
import json
import os
import re
import sys
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
SEAT_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*#\d+$")  # 좌석 = 이름#계보 (ft-name-lint 이름 + 구 이름 FB_CFO#46) · 도구는 계보가 없다


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


def _roster_names(fdir: Path) -> set[str]:
    """r846 r4: 파일마다 모양 틀림(최상위 dict 아님 · 키 문자열 아님) = 그 파일만 건너뜀 + WARN — 나머지 명부는 그대로 쓴다."""
    files = sorted(fdir.glob("seats*.json"))
    if not files:
        raise FileNotFoundError(f"{fdir}/seats*.json")
    names: set[str] = set()
    for f in files:
        data = json.loads(f.read_text(encoding="utf-8"))
        if not isinstance(data, dict) or not all(isinstance(k, str) for k in data):
            print(f"WARN: 명부 모양 틀림 — 건너뜀 · {f.name}", file=sys.stderr)
            continue
        names |= {k for k in data if not k.startswith("_")}
    return names


def on_roster(seat: str, fdir: Path) -> bool:
    """r846 r3: 질문을 여는 보낸 이 = 명부(fdir/seats*.json 전부)에 있는 좌석 이름 «정확 일치» 하나 — 같은 계보 다른 번호도 안 된다
    (명부에 없는 src#999 가 질문을 열어 src#1 답을 막음 · DA r2). r4: 명부 읽기의 어떤 예외든 = 명부 못 읽음 → False + WARN
    (예외가 미러로 새면 카드 게시까지 멈춤 · DA r3) — fail-closed, 카드는 알림으로 게시."""
    try:
        names = _roster_names(fdir)
    except Exception as e:  # noqa: BLE001 — 명부 못 읽음 = 질문 0 + WARN, 카드 게시는 막지 않는다(r4 ⓑ)
        print(f"WARN: 명부 못 읽음 — 질문 열기 0 · {seat} ({fdir} · {type(e).__name__})", file=sys.stderr)
        return False
    return seat in names


def add(path: Path, seq: int, entry: dict[str, object]) -> bool:
    """멱등 — 이미 열렸거나 해소된(tombstone) 질문은 건드리지 않는다. 새로 열렸으면 True.
    r846: 좌석(이름#계보)만 질문을 연다 — 도구(ft-model-swap 등)·빈 값은 False(카드는 알림으로만 게시).
    좌석당 스레드 열린 질문 1 — 같은 좌석·스레드의 앞 질문(열림·전달됨)은 resolved(superseded), 늦게 온 옛 seq 는 그 자리에서 superseded."""
    if not SEAT_NAME.match(str(entry.get("seat", ""))):
        return False
    with dv.locked(path):
        data = load(path)
        if str(seq) in data["open"] or str(seq) in data["resolved"]:
            return False
        same = [int(k) for k, e in data["open"].items() if e.get("thread_ts") == entry.get("thread_ts") and e.get("seat") == entry["seat"]]
        late = any(s > seq for s in same)
        now = int(time.time())
        for s in [seq] if late else same:
            data["open"].pop(str(s), None)
            data["resolved"][str(s)] = {"at": now, "why": "superseded"}
        if not late:
            data["open"][str(seq)] = {**entry, "state": "open", "asked_at": now}
        _save(path, data)
        return not late


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
