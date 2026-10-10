"""thread_unit — 다른 발행 경로(제안서 발행·매거진)가 «단위 스레드»를 카드·장부에 올리는 공용 두 동작 (분리 · 200줄 한도).

note_attempt = 게시 «전» 카드에 `- 슬랙: <ch> · 시도 <ISO>` (이미 줄이 있으면 그대로) ·
ensure_root  = 게시 «후» 카드 줄을 `- 슬랙: <ch> <root_ts>` 로 + 장부에 키가 없으면 만든다(있는데 root_ts 가 다르면 raise).
"""
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import thread_ledger as lg
from mirror_lib import api_call
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


def repair_root(a, tgt) -> int:
    """`repair --root <ts>` (R81) — 사람이 아는 뿌리 ts 로 카드 줄·장부를 채운다(ensure_root 재사용).
    카드 줄이 «시도» 이거나 없을 때만 · 그 ts 가 «뿌리 글»(봇 글 · 답글 아님)일 때만 — 아니면 카드·장부 쓰기 «전» 에 raise."""
    card, line = Path(a.card), read_line(Path(a.card))
    if line is not None and line[1] is not None:
        raise lg.LedgerError(f"카드에 이미 뿌리 ts({line[1]})가 있다 — --root 는 「시도」 줄이거나 줄이 없을 때만: {card}")
    ch, t = (line[0] if line else a.channel), tgt(a)
    raw = api_call(t.base, t.token, "conversations.replies", {"channel": ch, "ts": a.root, "limit": 1}, get=True).get("messages")
    first = raw[0] if isinstance(raw, list) and raw and isinstance(raw[0], dict) else {}
    if str(first.get("ts")) != a.root:
        raise lg.LedgerError(f"--root {a.root} 글을 채널 {ch} 에서 못 찾았다")
    if not first.get("bot_id"):
        raise lg.LedgerError(f"--root {a.root} 는 봇 글이 아니다")
    if first.get("thread_ts") not in (None, "", a.root):
        raise lg.LedgerError(f"--root {a.root} 는 답글이다(뿌리 {first.get('thread_ts')}) — 답글 ts 는 뿌리가 아니다")
    print(f"repaired {ensure_root(card, a.team, Path(a.ledger), ch, a.root)} root_ts={a.root}")
    return 0
