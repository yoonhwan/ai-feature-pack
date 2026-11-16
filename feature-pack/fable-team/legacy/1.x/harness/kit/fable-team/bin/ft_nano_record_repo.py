#!/usr/bin/env python3
# pyright: basic
"""ft_nano_record_repo.py — r1849 ⓑ 카드가 장부 루트 밖 리포(팩)에 있을 때 그 리포의 카드 ref·명부를 읽는다. 부르는 곳 = ft_nano_record_due(card_rows · cmd_settle).
r2056 resolve_owner = due·landed 공통 차례 찾기(카드 팀 명부 → 0 이면 같은 폴더 다른 명부) · ft2 settle 의 resolve_card(카드 자리)와 별개.
상태·보낸 기록·우편함 = 장부 루트 그대로(sub.state·sub.comm = 부른 ctx 것). 같은 루트 = 부른 ctx 그대로(git 호출 0 · r2071 묶음 판 불변)."""
from __future__ import annotations

from ft_nano_record import CARD_RX, Ctx, Reject, Unjudged, need


def proxy_master(ctx, doc, team):   # r2039 A1 판정 한 곳(due 가 내보냄 · notify 받는 이·write 차례 좌석) — 그 팀 카드 ref 가지 = main → 팀장(차례 나노 대리) · 아니면 None · ref 읽기 실패 = Unjudged 그대로
    return (str(doc.get("_master") or "") or None) if ctx.tip(team)["br"] == "main" else None   # r2039-mut:main


def proxy_turn(ctx, doc, team, own, seat):   # r2039 A3·A5 → («완료» 칸 좌석들, 차례 좌석 표) · own = 차례 나노 · 팀장 대리 = 나노마다(표에 팀장 덧붙임) · main 팀 나노 직접 = push 전 REJECT(나노 main push 0 · 가드 불변)
    px = proxy_master(ctx, doc, team)
    if px and seat in own:   # r2039-mut:pre
        raise Reject(f"카드 ref = main — 기록 = 팀장 대리(landed --seat {px})")
    return (sorted(own), {**own, seat: ("대리", "")}) if own and seat == px else ([seat], own)


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


def resolve_owner(ctx, team, doc, stem, sec):   # r2056 A1~A5 — 차례(owners) 카드 팀 명부 먼저 · 0 이면 같은 폴더 seats.json·seats-*.json(카드 팀 제외 · 파일 이름 순 · 같은 규칙) → (차례를 찾은 명부, 차례들)
    from ft_nano_record_due import owners   # due 가 이 파일을 먼저 읽는다(순환 import 0)
    own, said = owners(ctx, doc, stem, sec), vars(ctx).setdefault("_r2056_said", set())

    def say(m):   # 실행당 같은 줄 1번(due 두 판 · landed 재시도)
        if m not in said:
            said.add(m)
            print(m, flush=True)
    if own:   # r2056-mut:stop
        return doc, own   # A2 — 다른 명부 읽기 0
    for p in sorted((ctx.root / ".fable-team").glob("seats*.json")):   # r2056-mut:cross
        name = "v65" if p.name == "seats.json" else p.name[6:-5] if p.name.startswith("seats-") else ""
        if not name or name == team:
            continue
        try:
            d = ctx.seats(name)
        except Unjudged:   # A4 — 그 명부만 건너뜀(카드 팀 명부 실패 = 부른 쪽 Unjudged 그대로)
            say(f"명부 {p.name} 판정 불가 — 건너뜀")
            continue
        if found := owners(ctx, d, stem, sec):
            say(f"차례 명부 {p.name} 카드={stem} (카드 팀 명부 차례 0)")
            return d, found
    return doc, own   # A3 — 0 이면 지금 길(카드 팀 명부 · r1805 팀장)
