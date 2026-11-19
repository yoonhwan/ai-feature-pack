#!/usr/bin/env python3
# pyright: basic
"""ft_nano_record_batch.py — r2071 due·notify 길에서만 쓰는 묶음 읽기(판정 규칙·출력·rc 0 변경). 부르는 곳 = ft_nano_record_due.due_rows 한 곳.
A2 카드 본문 = 한 판에 `git cat-file --batch` 1회(팀·ref 끝·경로 묶음 · 장부 항목 수와 무관) · 실패(rc≠0 · 7초 · 본문 빠짐) = 그 카드 줄 «판정 불가 … rc=<N>».
A3 fetch = 원격 URL 마다 1회(같은 URL 팀들의 카드 가지를 한 번에 개인 ref 로 받고 sha 만 쥐고 전부 지운다) · 묶음 rc≠0 = 그 URL 의 팀은 팀마다 fetch(기준판 길 · 실패 = 그 팀만 판정 불가) · r2250 notify(Budget) = fetch 예산 안 · 건너뜀·실패 = fetch 0 판(다시 받기 0).
묶음은 그 Ctx 인스턴스의 tip·card 만 씌운다(landed·settle·done·refused 의 Ctx 손 0 · A5)."""
from __future__ import annotations

import os

from ft_nano_record import STAGES, Unjudged, need, run
from ft_nano_record_budget import stage


def arm(ctx):   # 그 ctx 하나에 묶음 판 tip·card 를 씌운다(1회) → 묶음 상태 {bad: 팀 → 판정 불가, blobs: (팀, 뿌리, stem) → (경로, 본문)|판정 불가}
    if "_batch" not in vars(ctx):
        st, tip0, card0 = {"bad": {}, "blobs": {}}, ctx.tip, ctx.card

        def tip(team):   # 묶음 fetch 실패 뒤 팀마다 다시 받기도 실패한 팀 = 그 판정 불가 그대로(그 판의 다시 받기 = 팀마다 1회)
            if team in st["bad"]:
                raise st["bad"][team]
            return tip0(team)

        def card(team, iroot, stem):
            got = st["blobs"].get((team, iroot, stem))
            if isinstance(got, Unjudged):
                raise got
            return got or card0(team, iroot, stem)   # 묶음에 없는 카드(ref·ls-tree 실패 · 카드 없음) = 기준판 길이 같은 판정 불가를 낸다
        ctx.tip, ctx.card, ctx._batch = tip, card, st
    return ctx._batch


def prepare(ctx, keys):   # 한 판 머리에 1회 — fetch 판이면 URL 마다 묶음 fetch · 그다음 카드 본문 묶음 읽기 · 돌려줌 = ctx
    st = arm(ctx)
    st["bad"], st["blobs"] = {}, {}
    keys = list(dict.fromkeys(keys))
    ctx._fetchn = (0, 0, 0)   # r2316 R1 — (묶음 수 · 시도 수 · 받은 수) · fetch 0 판 = 0
    if ctx.fetch:
        ctx._fetchn = fetch_all(ctx, list(dict.fromkeys(k[0] for k in keys)), st["bad"])
        stage(ctx, "fetch")   # r2316 R3 — fetch 단계 끝 시각(«fetch» 표식은 들어가기 직전이라 여기서 센다)
    st["blobs"] = read_all(ctx, keys)
    return ctx


def fetch_cap(bud):   # r2250 O1 — Budget(notify) 있으면 fetch 마감 FB = B÷2 · URL 상한 = min(7, FB − 지난 초) · 없으면 7초(due 손 실행 그대로)
    return min(7.0, bud.b / 2 - bud.elapsed()) if bud else 7.0


def fetch_all(ctx, teams, bad):   # A3 — 팀의 ref·URL·가지 = fetch 0 판 tip()(같은 한 곳) · URL 마다 git fetch 1회 → ctx._tips 를 원격 끝으로 · 돌려줌 = r2316 R1 (묶음 수 · 시도 수 · 받은 수)
    root, groups, bud = str(ctx.root), {}, getattr(ctx, "bud", None)
    ctx.fetch = False
    for team in teams:
        try:
            t = ctx.tip(team)
        except Unjudged:
            continue   # 기준판 길 — card() 의 tip() 이 fetch 판으로 다시 본다
        if t["url"] and t["br"]:   # URL 없는 팀 = fetch 판도 같은 끝(기준판) → 그대로
            groups.setdefault(t["url"], []).append(team)
    ctx.fetch = True
    tries = 0   # r2316 R1 — 상한 ≥1 이라 git fetch 를 부른 묶음 수
    gotn = 0    # r2316 R1 — 받은 수(got 있음)
    for url, ts in groups.items():
        brs = sorted({ctx._tips[t]["br"] for t in ts})
        priv = [f"refs/ft-record/{os.getpid()}-{i}" for i in range(len(brs))]
        name, cap, rc, out = ctx._tips[ts[0]]["ref"].partition("/")[0], fetch_cap(bud), "건너뜀", ""
        if cap >= 1:   # 1초 미만 = 그 URL fetch 0
            tries += 1
            if bud:
                bud.mark("fetch", name)   # O3 — 멎은 곳에 어느 원격인지
            rc = run(["git", "-c", "gc.auto=0", "-C", root, "fetch", "-q", "--no-write-fetch-head", url] + [f"+refs/heads/{b}:{p}" for b, p in zip(brs, priv)], cap)[0]
            rc, out, _e = run(["git", "-C", root, "rev-parse", *[p + "^{commit}" for p in priv]]) if rc == 0 else (rc, "", "")
            run(["git", "-C", root, "update-ref", "--stdin"], inp="".join(f"delete {p}\n" for p in priv).encode())
        got = dict(zip(brs, out.split())) if rc == 0 and len(out.split()) == len(brs) else {}
        gotn += 1 if got else 0
        if bud and not got:   # O1·O2 — 건너뜀·실패 = 1줄(rc 그대로)
            print(f"fetch {name} {rc if rc == '건너뜀' else '실패 rc=' + ('-' if rc is None else str(rc or 1))} — remote-tracking 판")
        for team in ts:
            t = ctx._tips.pop(team)
            if t["br"] in got:
                ctx._tips[team] = {**t, "sha": got[t["br"]], "files": {}}
                continue
            if bud:   # O2 — 팀마다 다시 받기 0 · fetch 0 판 tip(remote-tracking · landed tips 규칙) 그대로
                ctx._tips[team] = t
                continue
            try:
                ctx.tip(team)   # 묶음 실패 = 기준판 길(팀마다 fetch 1회 · 실패 = 그 팀 카드 줄만 판정 불가)
            except Unjudged as u:
                bad[team] = u
    return len(groups), tries, gotn   # r2316 R1


def read_all(ctx, keys):   # A2 — 카드 경로는 Ctx.card 와 같은 ls-tree·단계 순서(진행 › 완성 › 대기 › 그 밖) · 본문 = cat-file --batch 1회
    root, want, skip = str(ctx.root), {}, set()
    for team, iroot, stem in keys:
        if (team, iroot) in skip:
            continue
        try:
            t = ctx.tip(team)
            if iroot not in t["files"]:
                t["files"][iroot] = need(["git", "-C", root, "ls-tree", "-r", "--name-only", "-z", t["sha"], "--", iroot], "git ls-tree 카드")[1].split("\0")
        except Unjudged:
            skip.add((team, iroot))
            continue
        hits = sorted((p for p in t["files"][iroot] if p.rsplit("/", 1)[-1] == stem + ".md"),
                      key=lambda p: (STAGES.index(p.split("/")[-2]) if p.split("/")[-2] in STAGES else 9, p))
        if hits:
            want[(team, iroot, stem)] = (hits[0], f"{t['sha']}:{hits[0]}")
    specs = list(dict.fromkeys(s for _p, s in want.values()))
    rc, out, _e = run(["git", "-C", root, "cat-file", "--batch"], inp="".join(s + "\n" for s in specs).encode(), raw=True) if specs else (0, b"", "")
    got = parse(out, specs) if rc == 0 else {}
    why = Unjudged(f"git cat-file 카드 rc={'-' if rc is None else rc or 1}")
    return {k: (p, got[s]) if s in got else why for k, (p, s) in want.items()}


def parse(out, specs):   # cat-file --batch 출력 → {spec: 본문} · missing·blob 아님·잘린 꼴 = 그 spec 없음(→ 판정 불가 rc=1)
    got, i = {}, 0
    try:
        for s in specs:
            j = out.index(b"\n", i)
            head, i = out[i:j].split(), j + 1
            if head[-1] in (b"missing", b"ambiguous"):
                continue
            n = int(head[-1])
            if head[1] == b"blob" and len(out) > i + n - 1:
                got[s] = out[i:i + n]
            i += n + 1
    except (ValueError, IndexError):
        pass
    return got
