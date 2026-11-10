"""주간 점검표의 표 쓰기·읽기 한 쌍 + 이월 + 통보 상태 (R131 교정 r2 · DA⑥ C1·C2).

셀 값 안의 `|` 는 `\\|` 로 쓰고(마크다운 표 표준), 읽을 때는 이스케이프되지 않은 `|` 로만 나눈 뒤 `\\|` 를 `|` 로 복원한다.
점검표 행(`| P1 … | 사실 | 결정 |`)이 정확히 3열이 아니면 raise — 사실이 결정 칸으로 밀리거나 이월에서 빠지는 무음 0 (#0 RULE).
"""
from __future__ import annotations

import json
import re
from pathlib import Path

DECISION_CELL = ""
NOT_OPEN = ("없음", "손 점검", "빈 표 틀")
NOTIFIED = re.compile(r"<!-- notified: (.+?)=(ok|fail) -->")


def esc(value: str) -> str:
    return re.sub(r"\s*\n\s*", " ", str(value)).replace("|", "\\|")


def cells(line: str) -> list[str]:
    return [c.replace("\\|", "|").strip() for c in re.split(r"(?<!\\)\|", line.strip().strip("|"))]


def table_rows(text: str) -> list[list[str]]:
    rows = [cells(ln) for ln in text.splitlines() if ln.lstrip().startswith("|")]
    return [c for c in rows if not all(re.fullmatch(r":?-{3,}:?", x) for x in c if x)]


def carry(prev_text: str) -> list[tuple[int, str, str]]:
    main, _, tail = prev_text.partition("\n## 이월")
    out = {}
    for c in table_rows(main):
        if not re.match(r"[PH]\d", c[0]):
            continue
        if len(c) != 3:
            raise ValueError(f"지난주 점검표 행이 3열이 아님({len(c)}열): {' | '.join(c)[:80]}")
        if not c[2] and not c[1].startswith(NOT_OPEN):
            out[c[0]] = (1, c[1])
    for n, key, fact, dec in re.findall(r"^- \[이월 (\d+)주\] (.+?) · (.*) · 결정:(.*)$", tail.split("\n## ")[0], re.M):
        if not dec.strip():
            out[key] = (int(n) + 1, fact)
    return [(n, k, f) for k, (n, f) in out.items()]


def render(title: str, monday: str, rows, snap: dict, carried, seat: str) -> str:
    cell = f" {DECISION_CELL} " if DECISION_CELL else " "
    out = [f"# 주간 점검 — {title} (주 시작 {monday})", f"<!-- snap: {json.dumps(snap, ensure_ascii=False)} -->",
           f"<!-- notified: {seat}=fail -->", "",
           "> 도구가 채운 것은 사실 칸뿐 — 결정 칸은 사람이 채운다. 닫힘 = 결정 칸 전부 + 그 주 패치 sha. 못 읽은 칸은 «확인 못 함».", "",
           "| 항목 | 사실 | 결정 |", "|---|---|---|"] + [f"| {esc(k)} | {esc(f)} |{cell}|" for k, f in rows]
    out += ["", "## 이월"] + [f"- [이월 {n}주] {k} · {f} · 결정:" for n, k, f in carried]
    return "\n".join(out) + "\n"


def notified_state(path: Path) -> str:
    """통보 상태 — 줄이 없는 옛 파일은 이미 알린 것으로 본다."""
    m = NOTIFIED.search(path.read_text(encoding="utf-8"))
    return m.group(2) if m else "ok"


def set_notified(path: Path, seat: str, state: str) -> None:
    path.write_text(NOTIFIED.sub(f"<!-- notified: {seat}={state} -->", path.read_text(encoding="utf-8"), count=1), encoding="utf-8")
