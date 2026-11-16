#!/usr/bin/env python3
# pyright: basic
"""ft_card_evidence.py — r2087(설계 r1944 §3): D2 좌석이 카드 ref «## 상태» 끝에 `- 세트: <A> · 시험: <test> · 이슈: 0` 0줄 또는 1줄만 쓴다(완료 줄 0).
단계 0 나노 좌석 거절 · 1 입력 꼴 · 2 gh PR(OPEN · head 가지 nano/<stem>) · 3 A 가 PR head 조상 · 4 마지막 세트 = A 면 ALREADY · 5 apply·lock 1커밋 push·verify. 카드 = 카드 루트 표 행(Ctx.root_hits · harness = ops/main-base · «*» = main) · PR 리포 = cwd · rc 0 DONE|ALREADY · 1 REJECT · 2 usage · 3 판정 불가(쓰기 0)."""
import argparse
import json
import os
import re
import sys

from ft_nano_record import SET_RX, Ctx, Reject, Unjudged, check_test, run
from ft_nano_record_due import card_key
from ft_nano_record_write import apply, lock


def judge(a):   # 단계 0~3 — 거절 = Reject · git·gh 실패 = Unjudged
    for bad, why in ((any("-nano-" in os.environ.get(k, "") for k in ("FT2_HOLDER", "FT_SEAT_NAME")), "나노 좌석 = D2 좌석 아님"), (not re.fullmatch(r"[0-9a-f]{40}", a.set), "--set 이 40hex 아님"), (bool(re.search(r"[\r\n]", a.test)), "--test 에 줄바꿈(CR·LF) — 한 줄만")):
        if bad:
            raise Reject(why)
    check_test(a.test)
    out = next((r[1] for r in map(lambda _: run(["gh", "pr", "view", str(a.pr), "--json", "state,headRefOid,headRefName"]), (1, 2)) if r[0] == 0), None)   # 7초 + 재시도 1(하드 룰 12 · 성공하면 멈춤)
    try:
        st, head, br = (str(v) for v in map(json.loads(out).__getitem__, ("state", "headRefOid", "headRefName")))
    except (ValueError, KeyError, TypeError):
        raise Unjudged("gh pr view rc≠0 또는 출력 꼴 아님") from None
    if st != "OPEN" or br != f"nano/{a.card}":
        raise Reject(f"PR #{a.pr} = {st} · {br}(OPEN · nano/{a.card} 아님)")
    if run(["git", "cat-file", "-e", head + "^{commit}"])[0] != 0:   # PR head 객체가 없으면 받기만(ref 손 0)
        run(["git", "fetch", "-q", "--no-write-fetch-head", "origin", head])
    rc, _o, _e = run(["git", "merge-base", "--is-ancestor", a.set, head])
    if rc != 0:
        raise Reject(f"세트가 PR head 조상 아님({a.set[:10]} ↛ {head[:10]})") if rc == 1 else Unjudged(f"git merge-base rc={'-' if rc is None else rc}")


def main(argv):
    p = argparse.ArgumentParser(prog="ft-card-evidence.sh")
    for name, kind in (("--card", str), ("--set", str), ("--pr", int), ("--test", str)):
        p.add_argument(name, type=kind, required=True)
    a = p.parse_args(argv)
    try:
        judge(a)
        hits = list((ctx := Ctx()).root_hits(a.card).values())   # 단계 4·5 — 카드 1장 · 마지막 세트 = A 면 0줄 · 아니면 세트 줄 1줄
        if len(hits) != 1:
            raise Reject(f"카드 루트 표에서 {a.card} 카드 {len(hits)}장(정확히 1장이어야 한다)")
        with lock(ctx):
            print(apply(ctx, *card_key(hits[0]), lambda sec: [] if [m.group(1) for ln in sec for m in [SET_RX.search(ln)] if m][-1:] == [a.set]
                        else [f"- 세트: {a.set} · 시험: {a.test} · 이슈: 0"], f"[docs] {a.card} 증거 줄 (D2 좌석 · PR #{a.pr})")[0])
        return 0
    except (Reject, Unjudged) as e:
        print(f"{'REJECT' if isinstance(e, Reject) else '판정 불가'} {e}")
        return 1 if isinstance(e, Reject) else 3


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
