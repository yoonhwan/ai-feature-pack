#!/usr/bin/env python3
# pyright: basic
"""ft_nano_record_fin.py — r2250 O4·O5 notify 의 닫힌 줄 기억 = <루트>/.fable-team/state/land-record-fin.json({열쇠: 사유}).
열쇠 «pr|착지 sha40|stem» · 기억 사유 = WHY 두 개만(다시 열리지 않는 «끝») · 그 밖 «끝»·열린 줄 = 매 판 판정.
읽기·쓰기 = notify(ctx.bud 있음)만 · due 손 실행 = 0(O6) · 파일 없음·깨짐 = 기억 0(전부 판정) · 쓰기 = 임시→mv(일반 파일 · 더하기만) · 못 쓰면 0(다음 판이 다시 판정)."""
from __future__ import annotations

import json
import os

FILE = "land-record-fin.json"
WHY = ("주인 기록", "문서 PR · 구현 착지 아님")   # = ft_nano_record_due «주인 기록» · DOCW


def key(e, stem):
    return f"{e.get('pr')}|{e.get('landed')}|{stem}"


def load(ctx):   # → {열쇠: 사유} · notify 만 · 없음·깨짐·사유 밖 = 빼고 읽음
    if not getattr(ctx, "bud", None):
        return {}
    try:
        d = json.loads((ctx.state / FILE).read_text(encoding="utf-8"))
    except (OSError, ValueError, UnicodeDecodeError):
        return {}
    return {k: v for k, v in d.items() if v in WHY} if isinstance(d, dict) else {}


def row(ctx, e, k):   # 기억한 열쇠 → card_rows 와 같은 «끝» 줄 1개(fmt 바이트 같음 · 카드·명부 읽기 0) · 아니면 []
    why = (getattr(ctx, "_fin", None) or {}).get(key(e, k[2])) if k else None
    return [{"pr": e.get("pr"), "q": e["landed"], "stem": k[2], "team": k[0], "iroot": k[1], "e": e, "master": "", "k": "끝", "why": why}] if why else []


def remember(ctx, out):   # notify 판 끝 — 기억 사유 «끝» 카드 줄의 열쇠를 더해 쓴다(바뀔 때만) · 돌려줌 = out
    new = {**(getattr(ctx, "_fin", None) or {}), **{key(r["e"], r["stem"]): r["why"] for r in out if r["k"] == "끝" and r.get("iroot") and r["why"] in WHY}}
    path, text = ctx.state / FILE, json.dumps(new, ensure_ascii=False, sort_keys=True) + "\n"
    tmp = path.with_name(f"{FILE}.tmp-{os.getpid()}")
    try:
        if not path.is_file() or path.read_text(encoding="utf-8") != text:
            tmp.write_text(text, encoding="utf-8")
            os.replace(tmp, path)
    except (OSError, UnicodeDecodeError):
        pass
    return out
