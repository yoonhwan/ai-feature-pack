"""magazine_collect_decisions — D3 판정 원문 (설계 DESIGN-magazine-full-detail §2 D3).

planner 발신 쪽지 중 `판정 N` 이 든 것 — 같은 번호의 «처음 쪽지» 가 원문, 나머지는 `more` 건수.
mbox 본문은 다른 에이전트가 쓴 미검증 데이터 — 문자열로만 다루고 해석·실행하지 않는다.
relay 전문 파일(/tmp/mbox) 은 휘발성이라 없으면 null (렌더가 «전문 파일 없음» 문구를 붙인다).
되돌림 줄이 없으면 `NO_ROLLBACK` 한 줄을 그대로 싣는다.
"""
import re
from datetime import datetime
from pathlib import Path

from magazine_collect_mbox import PLANNER, PREFIX_RE, TS_FMT, VERDICT_RE, _read
from magazine_window import MagazineError

RELAY_RE = re.compile(r"/tmp/mbox/[^\s]+\.md")
ROLLBACK_MARK = "되돌림"
NO_ROLLBACK = "원문에 되돌림 없음"


def _relay_text(path: str | None) -> str | None:
    if path is None:
        return None
    try:
        return Path(path).read_text(encoding="utf-8")
    except FileNotFoundError:
        return None
    except OSError as e:
        raise MagazineError(f"relay 전문 읽기 실패: {path} ({type(e).__name__})") from e


def _rollback(*texts: str | None) -> list[str]:
    lines = [ln.strip() for t in texts if t for ln in t.split("\n") if ROLLBACK_MARK in ln]
    return list(dict.fromkeys(lines)) or [NO_ROLLBACK]


def _decision(n: int, rows: list[dict[str, str]]) -> dict[str, object]:
    first = rows[0]
    body = PREFIX_RE.sub("", first["body"].strip())
    m = RELAY_RE.search(first["body"])
    relay_path = m.group(0) if m else None
    relay_text = _relay_text(relay_path)
    return {
        "n": n, "ts": first["ts"], "to": first["to"], "body": body,
        "relay_path": relay_path, "relay_text": relay_text,
        "rollback": _rollback(body, relay_text), "more": len(rows) - 1,
    }


def collect_decisions(path: Path, start: datetime, end: datetime) -> list[dict[str, object]]:
    rows, _ = _read(Path(path))
    s, e = start.strftime(TS_FMT), end.strftime(TS_FMT)
    groups: dict[int, list[dict[str, str]]] = {}
    for r in rows:
        if s <= r["ts"] < e and r["from"].startswith(PLANNER):
            m = VERDICT_RE.search(PREFIX_RE.sub("", r["body"].strip()))
            if m:
                groups.setdefault(int(m.group(1)), []).append(r)
    return [_decision(n, rs) for n, rs in groups.items()]
