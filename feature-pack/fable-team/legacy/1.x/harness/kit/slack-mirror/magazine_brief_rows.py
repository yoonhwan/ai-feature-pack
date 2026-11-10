"""magazine_brief_rows — 원장 표 읽기 + «행 끝 괄호 근거» 떼기 (R259 · 판정 1988 · 매거진 지침 §3 처리 칸).

표 행은 머리 이름으로 읽는다(칸 위치 아님). 근거 괄호는 «행 끝» 한 곳이고 판정·#·커밋·5자리 쪽지 번호가 든 것만 뗀다 — 그 밖 글자는 건드리지 않는다.
"""
import re

_SEP = re.compile(r"^\|[\s:|-]+\|$")
_EVID = re.compile(r"\s*\(([^()]*)\)\s*$")
_TOKEN = re.compile(r"판정 ?\d+|#\d+|(?<![0-9A-Za-z])(?=[0-9a-f]*\d)(?=[0-9a-f]*[a-f])[0-9a-f]{7,40}(?![0-9A-Za-z])|\b\d{5}\b")


def split_evidence(text: str) -> tuple[str, str]:
    """(근거를 뗀 글, 근거). 행 끝 괄호에 번호 낱말이 없으면 글 그대로 · 근거 ''."""
    found = _EVID.search(text)
    if found and _TOKEN.search(found.group(1)):
        return text[:found.start()].rstrip(), found.group(1).strip()
    return text.strip(), ""


def table_rows(body: str) -> list[dict[str, str]]:
    """본문 안 모든 표의 데이터 행 — {머리 이름: 칸 글}. 머리 줄 바로 아래가 구분줄인 줄이 머리."""
    rows: list[dict[str, str]] = []
    head: list[str] = []
    lines = body.splitlines()
    for i, ln in enumerate(lines):
        if not ln.startswith("|") or _SEP.match(ln.strip()):
            continue
        cols = [c.strip() for c in ln.strip().strip("|").split("|")]
        if i + 1 < len(lines) and _SEP.match(lines[i + 1].strip()):
            head = cols
        elif head:
            rows.append(dict(zip(head, cols)))
    return rows


def is_done(state: str) -> bool:
    return state.startswith(("완료", "✅"))
