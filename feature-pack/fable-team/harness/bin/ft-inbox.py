#!/usr/bin/env python3
"""ft-inbox.py — 메인팀 인박스(좌석 없는 스크립트 큐). 판정 425-B·430 · 설계 DESIGN-news-tree-workqueue-viz-20261009 §6-3·§8.

명령: ingest <seq> | show <좌석> [--compact] | mark <seq|group> 처리|위임|보류 "<1줄>" [--seat <좌석>] | report <seq|group…> [--seat <좌석>] | waive <좌석> --before <ISO ts> "<판정 N 사유>" | archive <좌석>
경로: FT_ROOT/.fable-team/comm/{mailbox.jsonl,mailbox.log.jsonl,bodies/} (읽기) · FT_ROOT/.fable-team/state/inbox/<계보>.jsonl (큐)
Haiku: FT_INBOX_HAIKU(기본 `claude -p --model claude-haiku-5-5`) 일회 호출 — 분류 미상·show --compact 때만. 상주·자발 압축·삭제 0.
실패는 전부 stderr + exit≠0 (조용한 강등 0).
"""
import glob
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ft_inbox_core import (  # noqa: E402
    COMM, HOOK_ERRORS, INBOX, PRIO, answered_seqs, die, find_mail, find_seq, group_closed, haiku, haiku_class, hits,
    lineage, locked, mail_files, norm_key, obligation_closed, qpath, read_q, rule_class, take_seat, write_q,
)


def cmd_ingest(seq, mail=None):
    mail = mail or find_mail(int(seq))
    if mail is None:
        die(f"seq={seq} 를 mailbox 에서 못 찾음 — 읽은 파일: {', '.join(mail_files()) or '없음'}")
    os.makedirs(f"{COMM}/bodies", exist_ok=True)
    bp = f"{COMM}/bodies/{seq}.txt"
    if not os.path.exists(bp):
        with open(bp, "w", encoding="utf-8") as f:
            f.write(mail["body"])
    q = qpath(mail["to"])
    with locked(q):
        rows = read_q(q)
        if any(x["seq"] == mail["seq"] for x in rows):
            print(f"SKIP seq={seq} 이미 적재")
            return
        cls = rule_class(mail["body"])  # 규칙표만 — 즉시 적재(Haiku 대기 0)
        rows.append({"seq": mail["seq"], "ts": mail["ts"], "from": mail["from"], "cls": cls,
                     "prio": PRIO[cls], "group": norm_key(mail["from"], mail["body"]),
                     "body_path": bp, "mark": None, "reported": False,
                     "via": "unknown" if cls == "미상" else "rule"})  # 분류 출처 — 셈 전용(표시·mark·report 무관)
        write_q(q, rows)
    if cls == "미상":  # 분리 백그라운드(부모 대기 0) — 라벨은 나중에 같은 잠금 안에서 갱신
        subprocess.Popen([sys.executable, os.path.abspath(__file__), "classify", str(seq), mail["to"]],
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True, close_fds=True)
    print(f"INGEST seq={seq} queue={lineage(mail['to'])} cls={cls} group={rows[-1]['group']}")


def cmd_classify(seq, to):
    """미상 줄 하나에 Haiku 라벨을 붙인다(ingest 가 분리 실행). 실패·timeout 이면 미상 유지 + hook-errors.log 1줄."""
    q = qpath(to)
    try:
        row = next(x for x in read_q(q) if x["seq"] == int(seq))
        cls = haiku_class(open(row["body_path"], encoding="utf-8").read())
    except Exception as e:  # 미상 유지(①과 ② 사이 · 빼기 0) — 사유는 로그에 남긴다
        os.makedirs(os.path.dirname(HOOK_ERRORS), exist_ok=True)
        with open(HOOK_ERRORS, "a", encoding="utf-8") as f:
            f.write(f"{time.strftime('%Y-%m-%dT%H:%M:%S')} ft-inbox classify seq={seq} 미상 유지: {type(e).__name__} {e}\n")
        return
    with locked(q):
        rows = read_q(q)
        for x in rows:
            if x["seq"] == int(seq) and x["cls"] == "미상":
                x.update(cls=cls, prio=PRIO[cls], via="haiku")
        write_q(q, rows)


def view(rows):
    mem = {}
    for x in sorted(rows, key=lambda x: (x["prio"], x["seq"])):
        mem.setdefault(x["group"], []).append(x)  # 묶음 사전 — 행은 한 바퀴만(r677)
    out = []
    for g, ms in mem.items():
        if not all(obligation_closed(x) for x in ms):  # 닫힌 묶음 = 그 묶음 행만 본다(전체 훑기 0)
            first = open(ms[0]["body_path"], encoding="utf-8").readline().strip()[:80] if os.path.exists(ms[0]["body_path"]) else ""
            out.append(f"[{ms[0]['cls']}] {g} seq={','.join(str(x['seq']) for x in ms)} 미닫힘={','.join(str(x['seq']) for x in ms if not obligation_closed(x))} "
                       f"from={ms[0]['from']} 원문={ms[0]['body_path']} | {first}")
    return out


def cmd_show(seat, compact):
    lines = view(read_q(qpath(seat)))
    if not compact or not lines:  # r593: 두 빈 분기 합침(동작 동일) — 파일 200줄 한도
        print("\n".join(lines) if lines else "EMPTY")
        return
    try:  # 보기 전용 — 큐 파일은 건드리지 않는다
        print(haiku("아래 인박스 줄을 한 장으로 압축해 보여라. 줄마다 seq 와 원문 경로를 그대로 유지하고 원문을 대체하지 마라.\n" + "\n".join(lines)))
    except Exception as e:
        die(f"show --compact haiku 실패: {e}")


def locate(seat, targets):
    """seq 또는 group id → 그 «좌석 큐»의 대상 seq 집합. 다른 큐에만 있으면 REJECT(그 큐 이름을 알린다).
    큐에 없는 seq 는 우편함 파일(mail_files 순)에서 찾아 이 좌석 계보 앞 쪽지면 적재 뒤 대상으로 삼는다(r430 · send 때 적재 빠진 쪽지)."""
    mine, unseen = hits(qpath(seat), targets), []
    for t in [t for t in targets if not mine[t] and t.isdigit()]:
        if (mail := find_mail(int(t))) and lineage(mail["to"]) == lineage(seat):
            cmd_ingest(t, mail)
            mine[t] = {int(t)}
        unseen += [] if mail else [t]
    missing = [t for t in targets if not mine[t]]
    if missing:
        others = sorted({os.path.basename(qp)[:-6] for qp in glob.glob(f"{INBOX}/*.jsonl") if qp != qpath(seat)
                         for s in hits(qp, missing).values() if s})
        die(f"대상 못 찾음(좌석 {seat}): {missing}" + (f" — 그 줄은 {', '.join(others)} 큐 것(남의 큐는 고치지 않는다)" if others else "")
            + "".join(f" · 대상 못 찾음 seq={t} ({len(mail_files())} 파일 조회)" for t in unseen))
    return set().union(*mine.values())


def mutate(seat, targets, fn):
    seqs, qp = locate(seat, targets), qpath(seat)
    with locked(qp):
        rows = read_q(qp)
        for x in rows:
            if x["seq"] in seqs:
                fn(x)
        write_q(qp, rows)
    print(f"OK {os.path.basename(qp)} seq={','.join(map(str, sorted(seqs)))}")


def cmd_mark(seat, target, kind, note):
    if kind not in ("처리", "위임", "보류") or not note.strip():
        die('usage: mark <seq|group> 처리|위임|보류 "<1줄>" [--seat <좌석>]', 2)
    mutate(seat, [target], lambda x: x.update(mark={"kind": kind, "note": note.strip(), "ts": time.strftime("%Y-%m-%dT%H:%M:%S")}))
    if target.isdigit():  # 쪽지 원본이 있는 우편함 파일(r430) — 큐에만 있으면 «없음(큐만)»
        print(f"MARKED seq={target} file={os.path.basename(find_seq(int(target))[0] or '없음(큐만)')}")
    seqs, ans = set().union(*hits(qpath(seat), [target]).values()), answered_seqs(seat)  # r593: 표시 = 닫힘 아님 — 정본 술어로 1줄씩
    for x in sorted((r for r in read_q(qpath(seat)) if r["seq"] in seqs), key=lambda r: r["seq"]):
        print(f"CLOSED seq={x['seq']}" if obligation_closed(x, ans) else f"STILL-OPEN seq={x['seq']} cls={x['cls']} — report {x['seq']} 또는 회신 쪽지")


def cmd_report(seat, targets):
    mutate(seat, targets, lambda x: x.update(reported=True))


def cmd_waive(seat, before, reason):
    """판정 번호가 있는 사유로, 그 좌석 큐의 경계 전·mark 있는·열린 줄에만 waived 를 붙인다. reported 불변."""
    if not re.search(r"판정 [0-9]+", reason):
        die('usage: waive <좌석> --before <ISO ts> "<판정 N 이 든 사유>"', 2)
    cut = datetime.fromisoformat(before)
    q = qpath(seat)
    with locked(q):
        rows = read_q(q)
        early = [x for x in rows if datetime.fromisoformat(x["ts"]) < cut]
        hit = [x for x in early if x["mark"] is not None and not obligation_closed(x)]
        for x in hit:
            x["waived"] = {"by": reason.strip(), "ts": time.strftime("%Y-%m-%dT%H:%M:%S")}
        if hit:
            write_q(q, rows)
    print(f"WAIVED {len(hit)} seq={','.join(str(x['seq']) for x in hit)}")
    print(f"SKIPPED_NO_MARK {sum(1 for x in early if x['mark'] is None)}")


def cmd_archive(seat):
    q = qpath(seat)
    with locked(q):
        rows = read_q(q)
        move = [x for x in rows if group_closed(rows, x["group"])]
        stay = [x for x in rows if not group_closed(rows, x["group"])]
        for x in stay:
            if x["mark"] is not None:  # 표시는 있는데 술어가 거짓 = 이동 거부 사유를 보인다
                print(f"REFUSED seq={x['seq']} cls={x['cls']} reported={str(x['reported']).lower()} — 술어 거짓(이동 거부)")
        if move:
            os.makedirs(f"{INBOX}/archive", exist_ok=True)
            with open(f"{INBOX}/archive/{lineage(seat)}-{time.strftime('%Y%m%d')}.jsonl", "a", encoding="utf-8") as f:
                f.writelines(json.dumps(x, ensure_ascii=False) + "\n" for x in move)
            write_q(q, stay)
    print(f"ARCHIVED {len(move)} KEPT {len(stay)}")


def main(a):
    c = a[0] if a else ""
    try:
        if c == "ingest" and len(a) == 2:
            return cmd_ingest(a[1])
        if c == "classify" and len(a) == 3:  # 내부용 — ingest 가 미상 줄에만 분리 실행
            return cmd_classify(a[1], a[2])
        if c == "show" and len(a) in (2, 3):
            return cmd_show(a[1], a[2:] == ["--compact"])
        if c in ("mark", "report"):
            seat, r = take_seat(a[1:])
            if c == "mark" and len(r) == 3:
                return cmd_mark(seat, *r)
            if c == "report" and r:
                return cmd_report(seat, r)
        if c == "waive" and len(a) == 5 and a[2] == "--before":
            return cmd_waive(a[1], a[3], a[4])
        if c == "archive" and len(a) == 2:
            return cmd_archive(a[1])
    except (ValueError, TypeError, OSError, json.JSONDecodeError) as e:
        die(f"{c}: {e}", 2 if c == "waive" else 1)
    die("usage: ft-inbox.sh ingest <seq> | show <좌석> [--compact] | mark <seq|group> 처리|위임|보류 \"<1줄>\" [--seat <좌석>] | report <seq|group…> [--seat <좌석>] | waive <좌석> --before <ISO ts> \"<판정 N 사유>\" | archive <좌석>", 2)


if __name__ == "__main__":
    main(sys.argv[1:])
