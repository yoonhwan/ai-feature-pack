#!/usr/bin/env python3
# pyright: basic
"""ft_nano_record_repo.py — r1849 ⓑ 카드가 장부 루트 밖 리포(팩)에 있을 때 그 리포의 카드 ref·명부를 읽는다. 부르는 곳 = ft_nano_record_due(card_rows · cmd_settle).
상태·보낸 기록·우편함 = 장부 루트 그대로(sub.state·sub.comm = 부른 ctx 것). 같은 루트 = 부른 ctx 그대로(git 호출 0 · r2071 묶음 판 불변)."""
from __future__ import annotations

from ft_nano_record import CARD_RX, Ctx, Unjudged, need


def at(ctx, where):   # 카드 절대경로·장부 repo → 그 리포 Ctx(상태 = 장부 루트) · 루트 같음·상대경로 = ctx
    w = str(where or "")
    m = CARD_RX.search(w)
    r = w[:m.start()].rstrip("/") if m else w
    if not r.startswith("/") or r == str(ctx.root):
        return ctx
    roots, subs = vars(ctx).setdefault("_r1849_roots", {}), vars(ctx).setdefault("_r1849_subs", {})
    if r not in roots:
        roots[r] = Ctx(r).root   # 리포 경로(worktree 포함) → 공용 루트 · 실행당 경로마다 1회
    if roots[r].resolve() == ctx.root.resolve():   # r1849-mut:at
        return ctx
    key = (str(roots[r]), ctx.fetch, id(ctx._tips))   # due_rows 의 fetch 판(새 _tips)마다 새 sub
    if key not in subs:
        subs[key] = sub = Ctx(roots[r])
        sub.state, sub.comm, sub.fetch = ctx.state, ctx.comm, ctx.fetch
    return subs[key]


def seats_at(ctx, ents, team):   # settle 좌석 명부 — 장부 루트 먼저 · 못 읽고 장부 repo 가 다른 리포면 그 리포 명부(팩 팀장) · 그래도 실패 = Unjudged 그대로
    try:
        return ctx.seats(team)
    except Unjudged:
        sub = at(ctx, ents[-1].get("repo")) if ents else ctx   # r1849-mut:seats
        if sub is ctx:
            raise
        return sub.seats(team)


def repo_hits(ctx, ent, stem, hits):   # settle — 루트 카드 루트 표 0개({}) + 장부 repo 가 다른 리포 = 그 리포 카드 ref(ft_card_ref 팀 «») 트리의 <stem>.md 들 → {n: 절대경로} · 아니면 hits 그대로
    sub = at(ctx, (ent or {}).get("repo")) if hits == {} else ctx
    if sub is ctx:
        return hits
    out = need(["git", "-C", str(sub.root), "ls-tree", "-r", "--name-only", "-z", sub.tip("")["sha"], "--", "design"], "git ls-tree 카드")[1]
    return dict(enumerate(sorted(str(sub.root / p) for p in out.split("\0") for m in [CARD_RX.search(p)] if m and m.group(4) == stem)))
