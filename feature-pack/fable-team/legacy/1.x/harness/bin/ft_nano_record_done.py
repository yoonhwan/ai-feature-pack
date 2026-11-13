#!/usr/bin/env python3
# pyright: basic
"""ft_nano_record_done.py — r1717 묶음 2(A12~A16): 일 끝 완료 줄 `done` · 닫기 거절 이력 `refused`.
done --seat <좌석> --card <stem> --did "<한 일 1줄>" --test "<명령> rc=0" [--pr <N>] [--left "<종류>=<담당> …|없음"] [--wt <작업 폴더>] [--handoff <경로>]
  조건: 명부 role=nano(A14) · 그 좌석의 지금 배정 카드 · 나노 가지 미커밋 0 · --test 가 rc=0 · 남은 일이 «잔여 없음»(A15 — 나노 몫이면 REJECT).
  쓰는 줄(landed 와 같은 길로 카드 ref 까지): 세트 줄이 없으면 `- 세트: <가지 HEAD>` + `- 완료: <좌석> · 한 일 · 산출 · 병합 상태 · 남은 일` · 같은 세트 재실행 = ALREADY.
  그 뒤 A13 세션 기록 1파일(못 쓰면 «판정 불가» rc 3 · 쪽지 0) → 팀장 «[완료·닫기 요청]» 1통(네 칸 + «닫는 길 = 승인 갈래»).
refused --seat <좌석> --cause "<진행 아닌 거절 사유 전부>" (r1718 A5b 가 1회 부른다)
  키 = (카드 · 좌석 이름에서 #N 뺀 것 · 원인 글에서 숫자·sha 뺀 앞 60자 · 세트) · 시도 수 = 보낸 기록 파일에 누적.
  1회째 = 그 나노에 «[정리 차례 · 닫기 거절]» · 2회째 = 팀장 «[유보]» · 3회째부터 발신 0 · 그 좌석의 전달된 rec 를 «거절된 rec» 로 적는다.
이 도구는 tmux kill·ft-nano-close·ft-seat-close 를 부르지 않는다(A14)."""
from __future__ import annotations

import argparse
import re
import sys

from ft_nano_record import DONE_RX, SET_RX, Ctx, Reject, Unjudged, check_test, left_free, need, section
from ft_nano_record_due import card_key, idx_stem
from ft_nano_record_ft2 import ft2_card
from ft_nano_record_notify import FROM, send, try_record, update
from ft_nano_record_write import apply, lock


def branch_state(wt):   # 나노 작업 폴더 → (HEAD, 가지, 미커밋 줄 수) · .serena 잡음은 안 센다(close-due 와 같은 규칙)
    _, out = need(["git", "-C", wt, "status", "--porcelain=v2", "--branch"], "git status")
    head = br = ""
    dirty = 0
    for ln in out.split("\n"):
        if ln.startswith("# branch.oid "):
            head = ln.split()[2]
        elif ln.startswith("# branch.head "):
            br = ln.split(" ", 2)[2]
        elif ln and not ln.startswith("#") and not ln.rstrip().endswith((".serena/project.yml", ".serena/")):
            dirty += 1
    if not re.fullmatch(r"[0-9a-f]{40}", head):
        raise Unjudged("git status HEAD rc=1")
    return head, br, dirty


def checked(ctx, a):   # done 조건(A12·A14·A15) → (카드 키, 팀장, 남은 일, HEAD, 가지) · 아니면 Reject(쓰기 0)
    doc = ctx.seats((a.seat.split("-") + ["", ""])[1])
    row, master, left = doc.get(a.seat), str(doc.get("_master") or ""), (a.left or "").strip() or "없음"
    if a.seat not in doc:   # r1868-mut:order — 명부 «행 없음» 만 ft2 원장 갈래(행이 있으면 꼴이 깨져도 아래 명부 검사 · 우회 0)
        row = {"role": "nano", "index": ft2_card(ctx, doc, a.seat, a.card)}
    if not isinstance(row, dict) or row.get("role") != "nano":   # r1717-mut:role
        raise Reject(f"done 은 명부 role=nano 좌석만 — {a.seat}(arch·DA·팀장은 팀이 닫힐 때 닫힌다)")
    key = card_key(str(row.get("index") or ""))
    if not key or key[2] != a.card:
        raise Reject(f"{a.seat} 의 지금 배정 카드가 {a.card} 아님(명부 index = {idx_stem(row) or '-'})")
    check_test(a.test)
    if not left_free(left, master):   # r1717-mut:left
        raise Reject("남은 일에 나노 몫 — 끝낸 뒤 다시")
    head, br, dirty = branch_state(a.wt or ".")
    if dirty:
        raise Reject(f"나노 가지 미커밋 {dirty}줄 — 커밋한 뒤 다시")
    return key, master, left, head, br


def cmd_done(ctx, a):
    (team, iroot, stem), master, left, head, br = checked(ctx, a)
    merge = f"착지 전(PR #{a.pr})" if a.pr else "착지 전(push 전)"
    four = f"한 일: {a.did} · 산출: {br}@{head[:10]} · 병합 상태: {merge} · 남은 일: {left}"

    def plan(sec):
        add = [] if any(SET_RX.search(ln) for ln in sec) else [f"- 세트: {head} · 시험: {a.test} · 이슈: 0"]
        same = any(m and m.group(1) == a.seat and f"@{head[:10]} ·" in ln for ln in sec for m in [DONE_RX.match(ln)])
        return add + ([] if same else [f"- 완료: {a.seat} · {four}"])

    with lock(ctx):
        status, _sec = apply(ctx, team, iroot, stem, plan, f"[docs] {stem} 완료 줄 (나노 {a.seat})")
        where = f"{ctx.tip(team)['ref']}:{ctx.card(team, iroot, stem)[0]}"
    print(status)
    path = try_record(ctx, a.seat, {"카드": f"{stem} ({where})", "한 일": a.did, "산출": f"가지 {br} · 세트 {head} · PR {'#' + str(a.pr) if a.pr else '-'} · 착지 전",
                                    "남은 일": left, "다시 열 때 먼저 읽을 것": f"{where} «## 상태» 절 · 가지 {br}", "받은 쪽지 seq": "-"}, a.handoff or "")
    if not path:   # r1717-mut:seatrec
        return 3
    k2 = f"{a.seat}|{stem}|{head}"
    if ctx.store()["done"].get(k2):   # 같은 세트의 «[완료]» 는 1통
        return 0
    seq = send(ctx, master, a.seat, f"[완료·닫기 요청] {a.seat} {stem} · {four} · 세션 기록 {path} · 닫는 길 = 승인 갈래(DA APPROVE · 인수 · 원격 보존 — r1670 조건 그대로)") if master else None
    if seq is None:
        return 3
    update(ctx, lambda st: st["done"].__setitem__(k2, seq or True))
    return 0


def last_set(ctx, key):   # 카드 ref 판(remote-tracking · fetch 0)의 마지막 세트 줄 sha — 못 읽으면 «-»
    try:
        ctx.fetch = False
        lines, s0, s1 = section(ctx.card(*key)[1].decode("utf-8", "replace"))
    except Unjudged:
        return "-"
    return ([m.group(1) for ln in (lines[s0 + 1:s1] if s0 is not None else []) for m in [SET_RX.search(ln)] if m] or ["-"])[-1]


def cmd_refused(ctx, a):
    doc = ctx.seats((a.seat.split("-") + ["", ""])[1])
    row = doc.get(a.seat) if isinstance(doc.get(a.seat), dict) else {}
    key = card_key(str(row.get("index") or ""))
    stem = key[2] if key else "-"
    flat = " / ".join(x.strip() for x in a.cause.splitlines() if x.strip())
    rk = f"{stem}|{a.seat.rsplit('#', 1)[0]}|{re.sub(r'[0-9a-f]{7,40}|[0-9]+', '', flat)[:60]}|{last_set(ctx, key) if key else '-'}"
    n = int(ctx.store()["refused"].get(rk) or 0) + 1   # r1717-mut:count

    def fn(s):
        s["refused"][rk] = n
        s["rejrec"].update({k: v.get("rec") for k, v in s["close"].items() if k.startswith(a.seat + "|")})

    update(ctx, fn)
    if n == 1:
        send(ctx, a.seat, FROM, f"[정리 차례 · 닫기 거절] 원인: {flat} — 고친 뒤 landed 또는 done 을 다시")
    elif n == 2 and doc.get("_master"):
        send(ctx, str(doc["_master"]), FROM, f"[유보] {a.seat} {stem} 원인: {flat} — 사람 1줄 필요")
    print(f"REFUSED {a.seat} {n}회째")
    return 0


def main(argv):
    p = argparse.ArgumentParser(prog="ft-nano-record.sh")
    sub = p.add_subparsers(dest="verb", required=True)
    d = sub.add_parser("done")
    for name in ("--seat", "--card", "--did", "--test"):
        d.add_argument(name, required=True)
    d.add_argument("--pr", type=int)
    for name in ("--left", "--wt", "--handoff"):
        d.add_argument(name)
    r = sub.add_parser("refused")
    r.add_argument("--seat", required=True)
    r.add_argument("--cause", required=True)
    a = p.parse_args(argv)
    try:
        return (cmd_done if a.verb == "done" else cmd_refused)(Ctx(), a)
    except Reject as e:
        print(f"REJECT {e}")
        return 1
    except Unjudged as e:
        print(f"판정 불가 {e}")
        return 3


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
