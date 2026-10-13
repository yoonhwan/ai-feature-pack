"""ft_news_ledger_notify — 원장 갱신 알림 (R125 → R139 개정). 쓰는 쪽은 ft_news_ledger.py.

대상 = 판정표 행 중 내용이 «(오빠)» 로 시작하고 그 판정 번호가 원장 «본문»에 없는 것. 시각 칸은 쓰지 않는다(판정표 시계가 실제와 어긋남).
한 틱 최대 1통(번호를 묶어 300자 이내 · 넘치면 «외 N건») · 보낸 번호는 notified.txt · 그 파일이 없는 첫 실행 = 현재 판정 번호 전부 기록만(발송 0).
쪽지 실패는 ERROR 만 · 번호를 기록하지 않아 다음 틱에 다시 — 뉴스를 막지 않는다(호출부가 예외를 삼킨다).
"""
import json
import logging
import os
import re
import subprocess
from pathlib import Path

LOG = logging.getLogger("ft_news_ledger")
VERDICT_ROW = re.compile(r"^\|\s*(\d+)\s*\|\s*(\d{1,2}):([\dx]{2})\s*\|\s*(.*?)\s*\|?\s*$")
OPPA = "(오빠)"
MAX_CHARS = 300
HEAD = "[원장 갱신 확인] 오빠 결정인데 원장 본문에 번호가 없음 — 판정 "
TAIL = " · 반영됐나요?"


def verdict_rows(root: Path, wt: str) -> list[tuple[str, str]]:
    """[(판정 번호, 내용 칸)] — 카드 워크트리의 VERDICTS-planner-*-*.md 전부."""
    out = []
    for f in sorted((root / ".worktrees" / wt / "design" / "planner").glob("VERDICTS-planner-*-*.md")):
        out += [(m[1], m[4]) for ln in f.read_text(encoding="utf-8").splitlines() if (m := VERDICT_ROW.match(ln))]
    return out


def pending_oppa(rows: list[tuple[str, str]], ledger_text: str, sent: set[str]) -> list[tuple[str, str]]:
    """오빠 결정 행 중 아직 안 알렸고 원장 본문에 번호(숫자 경계)가 없는 것."""
    return [(n, t) for n, t in rows if t.startswith(OPPA) and n not in sent and not re.search(rf"(?<!\d){n}(?!\d)", ledger_text)]


def bundle(nums: list[str]) -> str:
    """번호 묶음 한 통 — MAX_CHARS 안에 들어가는 만큼 싣고 나머지는 «외 N건»."""
    for k in range(len(nums), 0, -1):
        rest = len(nums) - k
        msg = HEAD + "·".join(nums[:k]) + (f" 외 {rest}건" if rest else "") + TAIL
        if len(msg) <= MAX_CHARS:
            return msg
    return HEAD + f"외 {len(nums)}건" + TAIL


def notify(root: Path, ledger_text: str, state: Path) -> None:
    seats = json.loads((root / ".fable-team" / "seats-planner.json").read_text(encoding="utf-8"))
    if not (wt := seats.get("_cards_wt")):
        return
    rows = verdict_rows(root, wt)
    sent_f = state / "notified.txt"
    state.mkdir(parents=True, exist_ok=True)
    if not sent_f.exists():  # 첫 실행 = 기준선만
        sent_f.write_text("\n".join(sorted({n for n, _ in rows})) + "\n", encoding="utf-8")
        return
    sent = set(sent_f.read_text(encoding="utf-8").split())
    if not (nums := [n for n, _ in pending_oppa(rows, ledger_text, sent)]):
        return
    mbox = os.environ.get("FT_MBOX") or str(root / ".fable-team" / "comm" / "mbox.sh")
    if subprocess.run(["bash", mbox, "send", seats["_master"], "ft-news-ledger", bundle(nums)], capture_output=True, check=False).returncode != 0:
        LOG.error("알림 쪽지 실패 판정 %s — 다음 틱에 다시", "·".join(nums))
        return
    sent_f.write_text("\n".join(sorted(sent | set(nums))) + "\n", encoding="utf-8")
