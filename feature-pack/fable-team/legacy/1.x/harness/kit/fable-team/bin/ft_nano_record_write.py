#!/usr/bin/env python3
# pyright: basic
"""ft_nano_record_write.py — r1717 A6~A10 `landed --seat <좌석> --pr <N> --card <stem> [--test "<명령> rc=0"] [--left "<종류>=<담당>"] [--handoff <경로>]`.
조건(A6): 장부에 (pr · 카드) 줄 · 착지 sha Q 가 그 리포 origin/<target> 의 조상 · <좌석> 이 «지금» 그 카드의 차례 좌석 · --test 는 rc=0 으로 끝난다. 아니면 REJECT(rc 1 · 쓰기 0).
쓰는 줄(A7 · 카드 «## 상태» 절 끝 · 줄마다 «없을 때만»): ⓢ `- 세트:` · ⓛ `- 착지: <Q>` · ⓒ `- 완료: <좌석>` — 있던 줄은 지우거나 고치지 않는다.
카드 ref 반영(A8): 바탕 = 방금 받은 원격 끝 · 새 커밋 = 부모 1개 · 바뀐 경로 = 그 카드 1개 · 더한 줄뿐(임시 인덱스 + commit-tree → URL 로 non-force push).
  공유 작업 트리·인덱스·HEAD·로컬 가지·remote-tracking 손 0(객체만) · 잠금 = state/land-record.lock(fetch 부터 확인까지) · non-FF 거절 = 새 끝에서 1회 다시 · force 0.
  확인 = push 뒤 다시 받아 이번 줄이 다 보일 때만 stdout `DONE`(쓸 줄 0 = `ALREADY` · 뒤 단계는 건너뛰지 않는다 — A9).
뒤 단계(종류=닫기 · 잔여 없음): A13 세션 기록 → A10 팀장 «[완료·닫기 요청]» → 끝줄 `NEXT bash ft-nano-close.sh <좌석> --landed-pr <N> --result <세션 기록> --recv <seq>`.
  값이 하나라도 없으면 NEXT 0 · «닫기 명령 보류 빠짐=…» rc 3. tmux kill·닫기 도구 호출 0(A14). env: FT_LAND_RECORD_LOCK_S(잠금 기다림 · 기본 25)."""
from __future__ import annotations

import argparse
import fcntl
import os
import re
import sys
import tempfile
import time
from contextlib import contextmanager
from pathlib import Path

from ft_nano_record import ENV, SET_RX, Ctx, Reject, Unjudged, check_test, left_free, left_of, marks, need, rec_of, run, section
from ft_nano_record_due import card_key, owners
from ft_nano_record_notify import close_request, send, seq_known, try_record, update


@contextmanager
def lock(ctx):   # A8 ㉢ — 배타 잠금(일반 파일) · 못 쥐면 «판정 불가 lock»
    ctx.state.mkdir(parents=True, exist_ok=True)
    budget, t0 = float(os.environ.get("FT_LAND_RECORD_LOCK_S") or 25), time.monotonic()
    with open(ctx.state / "land-record.lock", "a", encoding="utf-8") as fh:
        while True:
            try:
                fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError:
                if time.monotonic() - t0 >= budget:
                    raise Unjudged("lock rc=-") from None
                time.sleep(0.1)
        yield


def commit_on(ctx, t, path, data, msg):   # 원격 끝 t 위에 «그 카드 1개» 만 바꾼 커밋 1개(임시 인덱스 · 작업 트리·공유 인덱스 손 0)
    root = str(ctx.root)
    _, blob = need(["git", "-C", root, "hash-object", "-w", "--stdin"], "git hash-object", inp=data)
    _, ent = need(["git", "-C", root, "ls-tree", t["sha"], "--", path], "git ls-tree")
    fd, idx = tempfile.mkstemp(prefix="ft-record-idx-")
    os.close(fd)
    os.unlink(idx)
    env = {**ENV, "GIT_INDEX_FILE": idx}
    try:
        need(["git", "-C", root, "read-tree", t["sha"]], "git read-tree", env=env)
        need(["git", "-C", root, "update-index", "--cacheinfo", f"{ent.split()[0]},{blob.strip()},{path}"], "git update-index", env=env)
        _, tree = need(["git", "-C", root, "write-tree"], "git write-tree", env=env)
    finally:
        for f in (idx, idx + ".lock"):
            if os.path.exists(f):
                os.unlink(f)
    _, sha = need(["git", "-C", root, "commit-tree", tree.strip(), "-p", t["sha"], "-m", msg], "git commit-tree")
    return sha.strip()


def read_sec(ctx, team, iroot, stem):   # 카드 ref 를 새로 받아 → (끝 정보, 경로, 줄들, 절 시작, 절 끝)
    ctx.fetch, ctx._tips = True, {}
    path, raw = ctx.card(team, iroot, stem)
    lines, st, en = section(raw.decode("utf-8"))
    if st is None:
        raise Reject(f"카드에 «## 상태» 절 없음({path})")
    if ctx.store()["tips"].get(team) != ctx.tip(team)["sha"]:   # 마지막에 본 원격 끝 — due 의 fetch 0 판이 이 뒤로 물러서지 않게
        update(ctx, lambda s: s["tips"].__setitem__(team, ctx.tip(team)["sha"]))
    return ctx.tip(team), path, lines, st, en


def verify(ctx, team, iroot, stem, add):   # A8 ㉣ — 다시 받아 이번 줄이 전부 보일 때만 통과
    _t, _p, lines, st, en = read_sec(ctx, team, iroot, stem)
    if any(a not in lines[st + 1:en] for a in add):
        raise Unjudged("확인(카드 ref 에 이번 줄이 안 보임) rc=1")
    return lines[st + 1:en]


def apply(ctx, team, iroot, stem, plan, msg):   # A8·A9 → ("DONE"|"ALREADY", 확인한 상태 절) · plan(상태 절 줄들) → 더할 줄
    for attempt in (1, 2):
        t, path, lines, st, en = read_sec(ctx, team, iroot, stem)
        add = plan(lines[st + 1:en])
        if not add:
            return "ALREADY", lines[st + 1:en]
        if not t["url"]:
            raise Unjudged(f"카드 ref 가 원격 가지 꼴 아님({t['ref']}) rc=1")
        k = en
        while k > st + 1 and not lines[k - 1].strip():
            k -= 1
        new = "\n".join(lines[:k] + add + lines[k:])
        sha = commit_on(ctx, t, path, (new if new.endswith("\n") else new + "\n").encode("utf-8"), msg)
        _, purl = need(["git", "-C", str(ctx.root), "remote", "get-url", "--push", t["ref"].split("/")[0]], "git remote get-url")
        rc, _out, err = run(["git", "-C", str(ctx.root), "push", "-q", purl.strip(), f"{sha}:refs/heads/{t['br']}"])
        if rc == 0:
            break
        if attempt == 2 or not re.search(r"rejected|non-fast-forward|fetch first|stale info", err):
            raise Unjudged(f"push rc={'-' if rc is None else rc}")
    return "DONE", verify(ctx, team, iroot, stem, add)   # r1717-mut:verify


def lines_for(ctx, e, stem, a, info, sec):   # A7 — 줄마다 «없을 때만»(순서 ⓢ ⓛ ⓒ)
    q, m, add = e["landed"], marks(sec, a.seat, e["landed"]), []
    if not m["s"]:
        if a.test is None or not re.fullmatch(r"[0-9a-f]{40}", str(e.get("pr_head") or "")):
            raise Reject("세트 줄 없음 — --test 필요" if a.test is None else "장부 줄에 pr_head 40-hex 없음 — 세트 줄을 못 쓴다")
        add.append(f"- 세트: {e['pr_head']} · 시험: {a.test} · 이슈: 0")
    if not m["l"]:   # r1717-mut:sameq
        add.append(f"- 착지: {q} ({Path(str(e.get('repo'))).name} origin/{e.get('target')} · PR #{e.get('pr')} · 끝줄 head {str(e.get('pr_head'))[:8]} · 기록 {a.seat})")
    turn = (ctx.store()["sent"].get(f"{a.seat}|{stem}|{q}|차례") or {}).get("seq") or "-"
    if info["sort"] == "닫기":
        want = (a.left or "").strip() or "없음"
        if not m["c"] or left_of(m["c"]) != want:
            add.append(f"- 완료: {a.seat} · 병합 상태: 착지 {q[:10]} · 남은 일: {want} · 차례 #{turn}")
    elif not m["c"] and info["sort"] != "팀장":   # r1814 A1: 팀장 갈래 = 세트·착지 두 줄뿐(due «끝 주인 기록»)
        add.append(f"- 완료: {a.seat} · 병합 상태: 착지 {q[:10]} · 좌석 계속(지금 카드 {info['cur']}) · 차례 #{turn}")
    return add


def finish(ctx, r, a):   # A13 세션 기록 → A10 닫기 요청 · NEXT (종류=닫기 만 · 잔여 판정 = left_free 한 곳)
    if r["sort"] != "닫기":
        return 0
    seat, stem, q, lf = r["seat"], r["stem"], r["q"], left_of(r["m"]["c"])
    if not left_free(lf, r["master"]):   # 나노 몫 남은 일 — 기록은 남기고 닫기 요청 0
        key = f"{seat}|{stem}|{q}"
        if ctx.store()["left"].get(key) != lf and r["master"] and send(ctx, r["master"], seat, f"[기록 완료 · 남은 일] {seat} {stem} — {lf} · 닫기 요청 0") is not None:
            update(ctx, lambda st: st["left"].__setitem__(key, lf))
        return 0
    where = f"{r['ref']}:{r['path']}"
    path = try_record(ctx, seat, {"카드": f"{stem} ({where})", "산출": f"세트 {SET_RX.search(r['m']['s']).group(1)} · PR #{r['pr']} · 착지 {q}", "남은 일": lf or "없음",
                                  "다시 열 때 먼저 읽을 것": f"{where} «## 상태» 절", "받은 쪽지 seq": r["m"]["c"].rsplit("#", 1)[-1].strip()}, a.handoff or "")
    seq = close_request(ctx, {**r, "rec": rec_of(r["m"])}, path) if path else None
    want = path or ctx.state / "seat-record" / f"{seat}.md"
    miss = [n for n, ok in (("세션 기록", path is not None and want.is_file()), ("닫기 요청 seq", seq_known(ctx, seq))) if not ok]   # r1717-mut:inputs
    if miss:
        print(f"닫기 명령 보류 빠짐={'·'.join(miss)} 채울 이={seat}(landed 를 다시)")
        return 3
    print(f"NEXT bash ft-nano-close.sh {seat} --landed-pr {r['pr']} --result {want} --recv {seq}")
    return 0


def cmd_landed(ctx, a):
    hit = [(e, c) for e in ctx.ledger() if e.get("pr") == a.pr for c in e["cards"] if (card_key(c) or ("", "", ""))[2] == a.card]
    if not hit:
        raise Reject(f"장부에 (PR #{a.pr} · {a.card}) 줄 없음")
    e, cpath = hit[-1]
    team, iroot, stem = card_key(cpath)
    if a.test is not None:
        check_test(a.test)
    q, repo, target = e["landed"], str(e.get("repo") or ""), str(e.get("target") or "main")
    rc, _o, _e = run(["git", "-C", repo, "merge-base", "--is-ancestor", q, f"refs/remotes/origin/{target}"])   # r1717-mut:ancestor
    if rc == 1:
        raise Reject(f"착지 sha {q[:10]} 가 origin/{target} 의 조상 아님({repo})")
    if rc != 0:
        raise Unjudged(f"git merge-base({repo}) rc={'-' if rc is None else rc}")
    doc, info = ctx.seats(team), {}

    def plan(sec):
        own = {s: (k, c) for s, k, c in owners(ctx, doc, stem, sec)}
        own = own or {s: ("팀장", stem) for s in [doc.get("_master")] if s and s == a.seat}   # r1805 A1 · r1814 A1
        if a.seat not in own:   # r1717-mut:turnseat
            raise Reject(f"{a.seat} 은 {stem} 의 차례 좌석이 아님(지금 차례 = {' '.join(own) or '없음'})")
        info["sort"], info["cur"] = own.get(a.seat) or ("닫기", stem)
        return lines_for(ctx, e, stem, a, info, sec)

    with lock(ctx):
        status, sec = apply(ctx, team, iroot, stem, plan, f"[docs] {stem} 착지·완료 줄 (나노 {a.seat})")
        t = ctx.tip(team)
        path = ctx.card(team, iroot, stem)[0]
    print(status)
    return finish(ctx, {"pr": a.pr, "q": q, "stem": stem, "seat": a.seat, "sort": info["sort"], "master": str(doc.get("_master") or ""),
                        "m": marks(sec, a.seat, q), "ref": t["ref"], "path": path}, a)


def main(argv):
    p = argparse.ArgumentParser(prog="ft-nano-record.sh landed")
    p.add_argument("--seat", required=True)
    p.add_argument("--pr", type=int, required=True)
    p.add_argument("--card", required=True)
    p.add_argument("--test")
    p.add_argument("--left")
    p.add_argument("--handoff")
    a = p.parse_args(argv[1:])
    try:
        return cmd_landed(Ctx(), a)
    except Reject as e:
        print(f"REJECT {e}")
        return 1
    except Unjudged as e:
        print(f"판정 불가 {e}")
        return 3


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
