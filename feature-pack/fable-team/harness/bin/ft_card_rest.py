#!/usr/bin/env python3
# pyright: basic
"""ft_card_rest.py <좌석> — r849 닫기 대기 판정(ft-idle-wake 깨우기 제외).

rc 0 = 그 좌석 명부 행(seats*.json · index)의 카드 «## 상태» 절 마지막 줄이 나노 증거 줄(`세트: <40-hex> · 시험: … · 이슈: …` — [완료·휴식] 의 증거 줄)
       또는 중단 줄(`중단: …` — ft-nano-suspended-check.sh 표식).
rc 1 = 그 밖 · 명부 행·index·카드 못 찾음(닫기 대기 아님 = 지금처럼 깨운다).
jsonl·사용자 입력·쪽지 글자는 보지 않는다(DA⑥ r1 — 입력에 «[완료·휴식]» 글자가 든 정상 턴을 닫기 대기로 오판).
카드 원천 = «한 곳» — 명부에 _cards_wt 가 있으면 그 워크트리 카드만(ROOT 사본 0 · r993: ROOT 옛 사본이 일하는 나노를 «완료» 로 읽어 ring 0), 없으면 ROOT 만.
정한 원천에 카드가 없거나 못 읽으면 닫기 대기 «아님»(ring 그대로) + state/card-rest.log 1줄 — 조용한 «완료» 판정 0.
카드 위치: <원천>/<index> — 대기·진행·완성 폴더 이동도 같은 이름으로 찾는다. env: FT_ROOT.
"""
import json
import os
import re
import sys
import time
from pathlib import Path

EVIDENCE = re.compile(r"세트: [0-9a-f]{40} · 시험: .+ · 이슈: \S")
SUSPENDED = re.compile(r"중단: \S")
FOLDERS = ("대기", "진행", "완성")


def source(d: dict, root: Path) -> tuple[str, Path]:
    """(이름, 기준 경로) — 카드를 읽는 «한 곳». _cards_wt 가 있으면 ROOT 사본은 보지 않는다."""
    wt = d.get("_cards_wt")
    if isinstance(wt, str) and wt:
        return f"_cards_wt={wt}", root / ".worktrees" / wt
    return "ROOT", root


def log(root: Path, msg: str) -> None:
    """state/card-rest.log 1줄 — 못 써도 판정은 그대로(로그가 판정을 막지 않는다)."""
    try:
        p = root / ".fable-team" / "state" / "card-rest.log"
        p.parent.mkdir(parents=True, exist_ok=True)
        with p.open("a", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%dT%H:%M:%S ") + f"ft_card_rest: {msg}\n")
    except OSError:
        pass


def card_of(root: Path, seat: str) -> tuple[Path | None, str]:
    """(카드, 못 찾은 사유) — 사유 "" = 명부에 그 좌석 행이 없다(모름 · 로그 0)."""
    for f in sorted((root / ".fable-team").glob("seats*.json")):
        try:
            d = json.loads(f.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        row = d.get(seat) if isinstance(d, dict) else None
        idx = row.get("index") if isinstance(row, dict) else None
        if not isinstance(idx, str) or not idx.endswith(".md"):
            continue
        p = Path(idx)
        names = [p] + [p.parent.parent / k / p.name for k in FOLDERS if p.parent.name in FOLDERS and k != p.parent.name]
        name, base = source(d, root)
        for n in names:
            if (base / n).is_file():
                return base / n, ""
        return None, f"{seat} 원천={name} 카드 없음({idx})"
    return None, ""


def last_status_line(card: Path) -> str:
    inside, last = False, ""
    for line in card.read_text(encoding="utf-8").splitlines():
        if line.startswith("## "):
            inside = re.fullmatch(r"## 상태\s*", line) is not None
        elif inside and line.strip():
            last = line.strip().removeprefix("- ")
    return last


def rested(root: Path, seat: str) -> bool:
    card, why = card_of(root, seat)
    if card is None:
        if why:
            log(root, f"{why} — 닫기 대기 아님(ring)")
        return False
    try:
        last = last_status_line(card)
    except (OSError, ValueError) as e:
        log(root, f"{seat} 카드 못 읽음({card}) — 닫기 대기 아님(ring) {type(e).__name__}")
        return False
    return bool(EVIDENCE.match(last) or SUSPENDED.match(last))


if __name__ == "__main__":
    if len(sys.argv) != 2 or not os.environ.get("FT_ROOT"):
        print("usage: FT_ROOT=<루트> ft_card_rest.py <좌석>", file=sys.stderr)
        sys.exit(2)
    sys.exit(0 if rested(Path(os.environ["FT_ROOT"]), sys.argv[1]) else 1)
