#!/usr/bin/env python3
"""ft-inbox.py — 메인팀 인박스(좌석 없는 스크립트 큐). 판정 425-B·430 · 설계 DESIGN-news-tree-workqueue-viz-20261009 §6-3·§8.

명령: ingest <seq> | show <좌석> [--compact] | mark <seq|group> 처리|위임|보류 "<1줄>" | report <seq|group…> | archive <좌석>
경로: FT_ROOT/.fable-team/comm/{mailbox.jsonl,mailbox.log.jsonl,bodies/} (읽기) · FT_ROOT/.fable-team/state/inbox/<계보>.jsonl (큐)
Haiku: FT_INBOX_HAIKU(기본 `claude -p --model claude-haiku-5-5`) 일회 호출 — 분류 미상·show --compact 때만. 상주·자발 압축·삭제 0.
실패는 전부 stderr + exit≠0 (조용한 강등 0).
"""
import glob
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ft_inbox_core import (  # noqa: E402
    COMM, HOOK_ERRORS, INBOX, PRIO, die, find_mail, group_closed, haiku, haiku_class,
    lineage, locked, norm_key, obligation_closed, qpath, read_q, rule_class, write_q,
)


def cmd_ingest(seq):
    mail = find_mail(int(seq))
    if mail is None:
        die(f"seq={seq} 를 mailbox 에서 못 찾음")
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
    out = []
    for gid in dict.fromkeys(x["group"] for x in sorted(rows, key=lambda x: (x["prio"], x["seq"]))):
        mem = [x for x in rows if x["group"] == gid]
        if group_closed(rows, gid):
            continue
        open_seqs = [str(x["seq"]) for x in mem if not obligation_closed(x)]
        first = open(mem[0]["body_path"], encoding="utf-8").readline().strip()[:80] if os.path.exists(mem[0]["body_path"]) else ""
        out.append(f"[{mem[0]['cls']}] {gid} seq={','.join(str(x['seq']) for x in mem)} 미닫힘={','.join(open_seqs)} "
                   f"from={mem[0]['from']} 원문={mem[0]['body_path']} | {first}")
    return out


def cmd_show(seat, compact):
    lines = view(read_q(qpath(seat)))
    if not compact:
        print("\n".join(lines) if lines else "EMPTY")
        return
    if not lines:
        print("EMPTY")
        return
    try:  # 보기 전용 — 큐 파일은 건드리지 않는다
        print(haiku("아래 인박스 줄을 한 장으로 압축해 보여라. 줄마다 seq 와 원문 경로를 그대로 유지하고 원문을 대체하지 마라.\n" + "\n".join(lines)))
    except Exception as e:
        die(f"show --compact haiku 실패: {e}")


def locate(targets):
    """seq 또는 group id → (큐 경로, 대상 seq 집합). 전 큐를 찾는다."""
    hits = {}
    for qp in glob.glob(f"{INBOX}/*.jsonl"):
        for x in read_q(qp):
            for t in targets:
                if t == x["group"] or t == str(x["seq"]):
                    hits.setdefault(qp, set()).add(x["seq"])
    found = {t for t in targets if any(t == x["group"] or t == str(x["seq"]) for qp in hits for x in read_q(qp))}
    if found != set(targets):
        die(f"대상 못 찾음: {sorted(set(targets) - found)}")
    return hits


def mutate(targets, fn):
    for qp, seqs in locate(targets).items():
        with locked(qp):
            rows = read_q(qp)
            for x in rows:
                if x["seq"] in seqs:
                    fn(x)
            write_q(qp, rows)
        print(f"OK {os.path.basename(qp)} seq={','.join(map(str, sorted(seqs)))}")


def cmd_mark(target, kind, note):
    if kind not in ("처리", "위임", "보류") or not note.strip():
        die('usage: mark <seq|group> 처리|위임|보류 "<1줄>"', 2)
    mutate([target], lambda x: x.update(mark={"kind": kind, "note": note.strip(), "ts": time.strftime("%Y-%m-%dT%H:%M:%S")}))


def cmd_report(targets):
    mutate(targets, lambda x: x.update(reported=True))


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
        if c == "mark" and len(a) == 4:
            return cmd_mark(a[1], a[2], a[3])
        if c == "report" and len(a) >= 2:
            return cmd_report(a[1:])
        if c == "archive" and len(a) == 2:
            return cmd_archive(a[1])
    except (ValueError, OSError, json.JSONDecodeError) as e:
        die(f"{c}: {e}")
    die("usage: ft-inbox.sh ingest <seq> | show <좌석> [--compact] | mark <seq|group> 처리|위임|보류 \"<1줄>\" | report <seq|group…> | archive <좌석>", 2)


if __name__ == "__main__":
    main(sys.argv[1:])
