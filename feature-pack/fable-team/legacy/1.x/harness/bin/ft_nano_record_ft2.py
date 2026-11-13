# pyright: basic
"""ft_nano_record_ft2.py — r1868: 명부 행이 없는 좌석의 done 을 ft2 원장으로 판정한다(읽기 전용 · 명부·원장 쓰기 0).
ft2_card(ctx, doc, seat, stem) → 카드 경로(명부 _cards/진행/<stem>.md) · 아니면 Reject(쓰기 0) · 원장 판독 불가 = Unjudged(rc 3).
  판독 = <FT2_HOME 또는 ~/.claude/fable-team/ft2>/CURRENT 판 core/cli.py project --root <루트> --team <좌석 둘째 마디> 1회(읽기 동사 · 25초).
  인정 = result 접수 성공 ∧ stem 이 <work> 이거나 <work>- 로 시작하는 work 정확히 1개 ∧ owner.holder == 좌석 ∧ done False ∧ 역할 마디 nano."""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from ft_nano_record import Reject, Unjudged, run
from ft_nano_record_due import card_key


def ft2_card(ctx, doc, seat, stem):
    team, role = (seat.split("-") + ["", "", ""])[1:3]
    if role != "nano":
        raise Reject(f"done 은 명부 role=nano 또는 ft2 나노 좌석만 — {seat}")
    home = Path(os.environ.get("FT2_HOME") or Path.home() / ".claude" / "fable-team" / "ft2")
    try:
        cli = home / "versions" / (home / "CURRENT").read_text(encoding="utf-8").strip() / "core" / "cli.py"
    except OSError:
        raise Unjudged("ft2 CURRENT 읽기 rc=1") from None
    rc, out, _err = run([sys.executable, str(cli), "project", "--root", str(ctx.root), "--team", team], cap=25.0)
    if rc != 0:
        raise Unjudged(f"ft2 project rc={'-' if rc is None else rc}")
    try:
        d = json.loads(out)
        hits = [w for k, w in d["works"].items() if stem == k or stem.startswith(k + "-")]
    except (ValueError, KeyError, TypeError, AttributeError):
        raise Unjudged("ft2 project JSON rc=1") from None
    if d.get("result") != "접수 성공":
        raise Unjudged(f"ft2 project {d.get('result')}")
    if len(hits) != 1 or not isinstance(hits[0], dict):
        raise Reject(f"ft2 원장에 {stem} 에 맞는 work {len(hits)}개(정확히 1개만 인정)")
    w = hits[0]
    if not isinstance(w.get("owner"), dict) or w["owner"].get("holder") != seat:   # r1868-mut:holder
        raise Reject(f"ft2 원장 {stem} 의 지금 holder 가 {seat} 아님")
    if w.get("done") is not False:   # r1868-mut:done
        raise Reject(f"ft2 원장 {stem} 은 반환됨(done) — {seat}")
    key = card_key(f"{doc.get('_cards') or ''}/진행/{stem}.md")
    if not doc.get("_master") or not key:
        raise Unjudged("명부 _master·_cards 없음 rc=1")
    return f"{doc['_cards']}/진행/{stem}.md"
