#!/usr/bin/env python3
# pyright: basic
"""ft_nano_record_notify.py — r1717 A3 `notify [--pr N] [--no-fetch]` + 쓰기 공용(보낸 기록 · 쪽지 · 세션 기록 A13 · 닫기 요청 A10).
notify = due 의 열린 줄마다 1통: «차례» → 그 나노 «[정리 차례]»(landed 명령 1줄) · «주인 없음»·«카드 없음» → 팀장 · «닫기 요청 밀림» → 팀장 «[완료·닫기 요청]» 을 다시.
  같은 (받는 이 · 카드|PR · Q · 줄 종류) 재발신 0 · FT_LAND_RECORD_REMIND_S(기본 1800초) 넘게 같은 줄이면 1회만 다시(+ «차례» 면 팀장 «[정리 차례 무응답]») · 열쇠당 총 2통.
  발신 실패 = WARN 1줄 · 보낸 기록 0(다음 호출이 다시). 보낸 기록 = <루트>/.fable-team/state/land-record-notified.json(임시→mv · 일반 파일).
env: FT_MBOX(우편함 도구) · FT_LAND_RECORD_NOW(시험용 시계 · epoch 초)."""
from __future__ import annotations

import argparse
import fcntl
import json
import os
import re
import sys
import time

from ft_nano_record import HERE, Ctx, Unjudged, run, seq_dropped
from ft_nano_record_due import due_rows, fmt

FROM = "ft-nano-record"
FIELDS = ("카드", "한 일", "산출", "남은 일", "다시 열 때 먼저 읽을 것", "받은 쪽지 seq")


def write_atomic(path, text):   # 임시→mv (일반 파일 · 하드 룰 19)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f"{path.name}.tmp-{os.getpid()}")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)


def update(ctx, fn):   # 보낸 기록 읽기→고치기→쓰기(짧은 배타 잠금)
    ctx.state.mkdir(parents=True, exist_ok=True)
    with open(ctx.state / "land-record-notified.lock", "a", encoding="utf-8") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        st = ctx.store()
        fn(st)
        write_atomic(ctx.state / "land-record-notified.json", json.dumps(st, ensure_ascii=False, indent=1) + "\n")


def send(ctx, to, frm, body):   # → 실제 seq(못 읽으면 0) | None(발신 실패 · WARN 1줄) · 7초
    rc, out, _err = run(["bash", os.environ.get("FT_MBOX") or str(ctx.comm / "mbox.sh"), "send", to, frm, body], env=dict(os.environ))
    if rc != 0:
        print(f"WARN 쪽지 발신 실패 → {to}(rc={'-' if rc is None else rc})")
        return None
    m = re.search(r"\bseq=(\d+)", out)
    return int(m.group(1)) if m else 0


def seq_known(ctx, seq):   # ft-nano-close ② 와 같은 검사 — 그 seq 가 우편함 기록에 있다
    if not seq:
        return False
    if (ctx.comm / "bodies" / f"{seq}.txt").is_file():
        return True
    try:
        if int(seq) <= int((ctx.comm / ".mbox-seq").read_text(encoding="utf-8").strip() or 0):
            return True
    except (OSError, ValueError):
        pass
    try:
        return re.search(rf'"seq": *{int(seq)},', (ctx.comm / "mailbox.jsonl").read_text(encoding="utf-8", errors="replace")) is not None
    except OSError:
        return False


def seat_record(ctx, seat, fields, handoff=""):   # A13 세션 기록 1파일(인계서 꼴 6칸 · HANDOFF 가 있으면 경로만) — 못 쓰면 OSError
    path = ctx.state / "seat-record" / f"{seat}.md"
    try:
        old = dict(m.groups() for m in re.finditer(r"^- ([^:\n]+): (.*)$", path.read_text(encoding="utf-8"), re.M))
    except OSError:
        old = {}
    handoff = handoff or old.get("인계서", "")
    if handoff and os.path.isfile(handoff):
        body = f"- 인계서: {os.path.abspath(handoff)}\n"
    else:
        body = "".join(f"- {k}: {fields.get(k) or old.get(k) or '-'}\n" for k in FIELDS)
    write_atomic(path, f"# 세션 기록: {seat}\n{body}")
    return path


def try_record(ctx, seat, fields, handoff=""):   # → 경로 | None(«판정 불가» 1줄 — 뒤 단계 닫기 요청 0)
    try:
        return seat_record(ctx, seat, fields, handoff)
    except OSError as e:
        print(f"판정 불가 세션 기록 쓰기 rc=1 — {str(e)[:120]}")
        return None


def close_request(ctx, r, path):   # A10 — 팀장에 «[완료·닫기 요청]» 1통(보내는 이 = 그 좌석) → 실제 seq + rec 를 전달 기록에 · 같은 rec 재발신 0
    key = f"{r['seat']}|{r['stem']}|{r['q']}"
    had = ctx.store()["close"].get(key) or {}
    if had.get("rec") == r["rec"]:
        try:   # r1820 B3 — 기록한 seq 가 우편함에서 버려졌으면 같은 rec 를 1회 다시 · 판독 실패 = «판정 불가» 1줄 · 재발신 0
            if not seq_dropped(ctx, had.get("seq")):
                return had.get("seq")
        except Unjudged as e:
            print(f"판정 불가 {e}")
            return None
        print(f"INFO 닫기 요청 #{had.get('seq')} 우편함에서 버려짐 → 다시 보냄")
    if not r["master"]:
        print(f"WARN 닫기 요청 생략 — 명부에 _master 없음({r['stem']})")
        return None
    seq = send(ctx, r["master"], r["seat"], f"[완료·닫기 요청] {r['stem']} 착지 {r['q'][:10]} · 좌석 {r['seat']} · 세션 기록 {path}")
    if not seq:
        if seq == 0:
            print("WARN 닫기 요청 쪽지의 seq 를 못 읽음 — 전달 기록 0")
        return None
    update(ctx, lambda st: st["close"].__setitem__(key, {"rec": r["rec"], "seq": seq, "result": str(path), "pr": r["pr"]}))
    print(f"NOTIFIED 닫기 요청 → {r['master']} #{seq}")
    return seq


def body_of(ctx, r):   # 열린 줄 → (받는 이, 본문)
    q10, tool = r["q"][:10], f"FT_ROOT={ctx.root} bash {HERE}/ft-nano-record.sh"
    test = ' --test "<그 세트에서 돌린 시험 명령> rc=0"' if "ⓢ" in r.get("miss", "") else ""
    if r["k"] == "차례":
        return r["seat"], (f"[정리 차례] {r['stem']} 착지 {q10}(PR #{r['pr']} · 종류 {r['sort']} · 빠짐 {r['miss']}) — 실행: {tool} landed --seat {r['seat']}"
                           f" --pr {r['pr']} --card {r['stem']}{test} · 남은 일이 있으면 --left \"<종류>=<담당>\"")
    if r["k"] == "주인없음":
        return r["master"], f"[정리 차례 · 주인 없음] {r['stem']} 착지 {q10}(PR #{r['pr']}) — 기록 담당 = 팀장 · 빠짐 {r['miss']} · 닫는 길 = {tool} landed --seat {r['master']} --pr {r['pr']} --card {r['stem']}{test}"
    return r["master"], (f"[정리 차례 · 카드 없음] PR #{r['pr']} 착지 {q10} — 기록 담당 = 팀장 · 닫는 길 = {tool} settle --seat <좌석> --pr {r['pr']}"
                         " (--card <stem> | --no-card \"<사유>\")")


def notify_row(ctx, r, now, gap):
    if r["k"] == "밀림":
        path = ctx.state / "seat-record" / f"{r['seat']}.md"
        if path.is_file():
            close_request(ctx, r, path)
        else:
            print(f"닫기 요청 보류 {r['seat']} 세션 기록 없음 — landed 를 다시")
        return
    to, body = body_of(ctx, r)
    if not to:
        print(f"INFO 정리 차례 쪽지 생략 — 팀 못 정함({r['stem']})")
        return
    key = f"{to}|{r['stem']}|{r['q']}|{r['k']}"
    ent = ctx.store()["sent"].get(key)
    if ent and not (ent.get("n") == 1 and now - float(ent.get("ts") or 0) >= gap):   # r1717-mut:sent
        return
    seq = send(ctx, to, FROM, body)
    if seq is None:
        return
    update(ctx, lambda st: st["sent"].__setitem__(key, {"n": (ent or {}).get("n", 0) + 1, "ts": now, "seq": seq}))
    print(f"NOTIFIED {r['k']} → {to} #{seq}")
    if ent and r["k"] == "차례" and r["master"]:
        send(ctx, r["master"], FROM, f"[정리 차례 무응답] {r['seat']} {r['stem']} 빠짐 {r['miss']} — 착지 {r['q'][:10]}(PR #{r['pr']}) · 차례 쪽지 2통에 기록 없음")


def main(argv):
    p = argparse.ArgumentParser(prog="ft-nano-record.sh notify")
    p.add_argument("--pr", type=int)
    p.add_argument("--no-fetch", action="store_true")
    a = p.parse_args(argv[1:])
    now, gap = float(os.environ.get("FT_LAND_RECORD_NOW") or time.time()), float(os.environ.get("FT_LAND_RECORD_REMIND_S") or 1800)
    try:
        ctx = Ctx()
        out = due_rows(ctx, a.pr, not a.no_fetch)
    except Unjudged as e:
        print(f"판정 불가 {e}")
        return 3
    for r in out:
        if r["k"] in ("차례", "주인없음", "카드없음", "밀림"):
            notify_row(ctx, r, now, gap)
        elif r["k"] == "판정불가":
            print(fmt(r))
    return 3 if any(r["k"] == "판정불가" for r in out) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
