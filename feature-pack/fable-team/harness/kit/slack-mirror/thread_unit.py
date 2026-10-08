"""thread_unit — 다른 발행 경로(제안서 발행·매거진)가 «단위 스레드»를 카드·장부에 올리는 공용 두 동작 (분리 · 200줄 한도).

note_attempt = 게시 «전» 카드에 `- 슬랙: <ch> · 시도 <ISO>` (이미 줄이 있으면 그대로) ·
ensure_root  = 게시 «후» 카드 줄을 `- 슬랙: <ch> <root_ts>` 로 + 장부에 키가 없으면 만든다(있는데 root_ts 가 다르면 raise).
"""
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import thread_ledger as lg
from thread_card import read_line, unit_id, write_line

KST = ZoneInfo("Asia/Seoul")


def note_attempt(card: Path, channel: str) -> None:
    if read_line(card) is None:
        write_line(card, f"- 슬랙: {channel} · 시도 {datetime.now(KST).isoformat(timespec='seconds')}")


def ensure_root(card: Path, team: str | None, ledger: Path, channel: str, root_ts: str) -> str:
    uid = unit_id(card, team)
    line = read_line(card)
    if line is None or line[1] != root_ts:
        write_line(card, f"- 슬랙: {channel} {root_ts}")
    rec = lg.get(ledger, uid)
    if rec is None:
        lg.create(ledger, uid, channel=channel, root_ts=root_ts, kind="unit", card_path=str(card))
    elif rec.get("root_ts") != root_ts:
        raise lg.LedgerError(f"장부 root_ts({rec.get('root_ts')}) ≠ 이번 root_ts({root_ts}): {uid} — 사람이 확인한다")
    return uid
