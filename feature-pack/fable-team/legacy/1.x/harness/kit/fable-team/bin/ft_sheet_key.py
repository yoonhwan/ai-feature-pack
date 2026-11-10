"""ft-sheet-events 사건 키 규칙 (PLAN §3-1 불변 사건 키) — ft_sheet_events.py 200줄 규칙 분리."""
import hashlib
import re

HEADS = (("[정지 레디]", "stop-ready"), ("[완료·휴식]", "done"), ("[완료]", "done"))
EVS = {"spawn", "nano-close", "issue-close", "label", "land-candidate", "merge-queue", "stop-ready", "done"}


def sha16(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def make_key(ev: str, a: str, b: str = "") -> str:
    """mbox 는 본문 sha16 을 쓴다 — 머리 3종이 아니면 빈 값. 미등록 ev 는 ValueError(호출부가 REJECT rc 2)."""
    if ev == "mbox":
        head = next((e for h, e in HEADS if b.startswith(h)), None)
        return f"{head}:{a}:{sha16(b)}" if head else ""
    if ev not in EVS:
        raise ValueError(ev)
    if ev == "nano-close" and not re.fullmatch(r"[0-9a-f]{40}", b):
        b = sha16(b)  # 세트 sha 가 아니면 결과 문자열의 sha16
    return {"issue-close": f"issue-close:#{a}", "label": f"label:#{a}:{b}"}.get(ev, f"{ev}:{a}:{b}")
