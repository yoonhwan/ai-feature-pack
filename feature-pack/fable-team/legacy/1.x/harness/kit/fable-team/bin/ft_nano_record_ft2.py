# pyright: basic
"""ft_nano_record_ft2.py — r1868: 명부 행이 없는 좌석의 done 을 ft2 원장으로 판정한다(읽기 전용 · 명부·원장 쓰기 0).
ft2_card(ctx, doc, seat, stem) → 카드 경로(명부 _cards/진행/<stem>.md) · 아니면 Reject(쓰기 0) · 원장 판독 불가 = Unjudged(rc 3).
  판독 = <FT2_HOME 또는 ~/.claude/fable-team/ft2>/CURRENT 판 core/cli.py project --root <루트> --team <좌석 둘째 마디> 1회(읽기 동사 · 25초).
  인정 = result 접수 성공 ∧ stem 이 <work> 이거나 <work>- 로 시작하는 work 정확히 1개 ∧ owner.holder == 좌석 ∧ done False ∧ 역할 마디 nano.
  r1873: owner 없음(ft2 result 가 반납)이면 같은 판 projection 의 Journal.records() 를 읽어 그 work 마지막 result holder 를 인정(result_holder)."""
from __future__ import annotations

import importlib.util
import json
import os
import sys
from pathlib import Path

from ft_nano_record import Reject, Unjudged, run
from ft_nano_record_due import card_key


def result_holder(core, root, team, key, seat, gen):
    """마지막 result 줄 holder == 좌석 ∧ gen == 지금 gen ∧ 그 뒤 같은 work 의 dispatch·claim 0 · 읽기만 · 판독 불가 = Unjudged."""
    try:
        p = importlib.util.module_from_spec(spec := importlib.util.spec_from_file_location("ft2_projection_r1873", core / "projection.py"))
        spec.loader.exec_module(p)
        recs = [r for r in p.journal.Journal(p.runtime_path(str(root), team), rec=p.record).records() if r.get("work") == key]
    except Exception as exc:
        raise Unjudged(f"ft2 journal 판독 rc=1 ({type(exc).__name__})") from None
    i = max((n for n, r in enumerate(recs) if r.get("kind") == "result"), default=-1)
    r = recs[i] if i >= 0 else {}
    if i < 0 or r.get("holder") != seat or r.get("gen") != gen:   # r1873-mut:holder·gen
        return False
    return not any(x.get("kind") in ("dispatch", "claim") for x in recs[i + 1:])   # r1873-mut:after


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
        hits = [(k, w) for k, w in d["works"].items() if stem == k or stem.startswith(k + "-")]
    except (ValueError, KeyError, TypeError, AttributeError):
        raise Unjudged("ft2 project JSON rc=1") from None
    if d.get("result") != "접수 성공":
        raise Unjudged(f"ft2 project {d.get('result')}")
    if len(hits) != 1 or not isinstance(hits[0][1], dict):
        raise Reject(f"ft2 원장에 {stem} 에 맞는 work {len(hits)}개(정확히 1개만 인정)")
    key, w = hits[0]
    if w.get("owner") is None and result_holder(cli.parent, ctx.root, team, key, seat, w.get("gen")):   # r1873
        pass
    elif not isinstance(w.get("owner"), dict) or w["owner"].get("holder") != seat:   # r1868-mut:holder
        raise Reject(f"ft2 원장 {stem} 의 지금 holder 가 {seat} 아님")
    if w.get("done") is not False:   # r1868-mut:done
        raise Reject(f"ft2 원장 {stem} 은 반환됨(done) — {seat}")
    key = card_key(f"{doc.get('_cards') or ''}/진행/{stem}.md")
    if not doc.get("_master") or not key:
        raise Unjudged("명부 _master·_cards 없음 rc=1")
    return f"{doc['_cards']}/진행/{stem}.md"
