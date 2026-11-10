#!/usr/bin/env python3
"""ft-inbox.py — 메인팀 인박스(좌석 없는 스크립트 큐). 판정 425-B·430 · 설계 DESIGN-news-tree-workqueue-viz-20261009 §6-3·§8.

명령: ingest <seq> | show <좌석> [--seqs|--count] | rotate <좌석> --before <ISO ts> \"<판정 N 사유>\" | mark <seq|group> 처리|위임|보류 "<1줄>" [--seat <좌석>] | report <seq|group…> [--seat <좌석>] | close <seq|group…> "<사유>" [--seat <좌석>] | waive <좌석> --before <ISO ts> "<판정 N 사유>" | archive <좌석>
경로: FT_ROOT/.fable-team/comm/{mailbox.jsonl,mailbox.log.jsonl,bodies/}(읽기) · FT_ROOT/.fable-team/state/inbox/<계보>.jsonl(큐) · 분류는 규칙표만(밖이면 미상 · 라벨 호출 0 = 퇴역 r1560) · 실패는 전부 stderr + exit≠0 (조용한 강등 0).
show --seqs = 기계용(r1052) — 큐 파일 끝 창(ft_inbox_window.SEQ_N)만 읽고 본문 파일을 열지 않는다 · 창 위가 잘린 첫 묶음은 «보류(범위 밖)» 로 보수 보고.
"""
import glob
import json
import os
import re
import sys
import time
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ft_inbox_core import COMM, INBOX, PRIO, answered_seqs, die, find_mail, find_seq, group_closed, hits, lineage, locked, mail_files, norm_key, obligation_closed, qpath, read_q, rule_class, take_seat, write_q  # noqa: E402
from ft_inbox_rotate import cmd_count, cmd_rotate, rotated_head, tidy_hits  # noqa: E402
from ft_inbox_window import tail_rows, view, view_seqs  # noqa: E402


def cmd_ingest(seq, mail=None):
    mail = mail or find_mail(int(seq))
    if mail is None:
        die(f"seq={seq} 를 mailbox 에서 못 찾음 — 읽은 파일: {', '.join(mail_files()) or '없음'}")
    os.makedirs(f"{COMM}/bodies", exist_ok=True)
    bp = f"{COMM}/bodies/{seq}.txt"
    if not os.path.exists(bp):
        with open(bp, "w", encoding="utf-8") as f:
            f.write(mail["body"])
    with locked(q := qpath(mail["to"])):
        rows = read_q(q)
        if any(x["seq"] == mail["seq"] for x in rows):
            print(f"SKIP seq={seq} 이미 적재")
            return
        cls = rule_class(mail["body"])  # 규칙표만 — 즉시 적재(대기 0)
        rows.append({"seq": mail["seq"], "ts": mail["ts"], "from": mail["from"], "cls": cls, "prio": PRIO[cls], "group": norm_key(mail["from"], mail["body"]), "body_path": bp, "mark": None, "reported": False, "via": "unknown" if cls == "미상" else "rule"})  # 분류 출처 — 셈 전용(표시·mark·report 무관)
        write_q(q, rows)
    print(f"INGEST seq={seq} queue={lineage(mail['to'])} cls={cls} group={rows[-1]['group']}")  # 미상도 그대로 적재 — 분류기 스폰 0(r1560 퇴역)


def cmd_show(seat, flag):
    if flag == ["--count"]:  # r1052 단계 2 B1 — 줄 수만 필요한 소비자(상황판) · 본문 접근 0
        return cmd_count(seat)
    if flag not in ([], ["--seqs"]):  # r1560 퇴역: --compact 삭제 — 지운 옵션은 오류로 말한다(조용한 무시 0)
        die(f"show: 모르는 옵션 {flag[0]} — --compact 는 퇴역(r1560). 쓰는 것: --seqs · --count", 2)
    ans = answered_seqs(seat)  # B2 — show·--seqs·--count·rotate 가 같은 술어(회신 seq 포함)
    lines = view_seqs(*tail_rows(qpath(seat)), ans) if flag == ["--seqs"] else view(read_q(qpath(seat)), ans)
    head = rotated_head(seat) if flag == [] else None  # B4 — 회전으로 치운 묶음이 있으면 사람용 show 첫 줄에 보인다(조용한 소실 0)
    print("\n".join(([head] if head else []) + (lines or ["EMPTY"])))


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
        others = sorted({os.path.basename(qp)[:-6] for qp in glob.glob(f"{INBOX}/*.jsonl") if qp != qpath(seat) for s in hits(qp, missing).values() if s})
        die(f"대상 못 찾음(좌석 {seat}): {missing}" + (f" — 그 줄은 {', '.join(others)} 큐 것(남의 큐는 고치지 않는다)" if others else "") + "".join(f" · 대상 못 찾음 seq={t} ({len(mail_files())} 파일 조회)" for t in unseen))
    return set().union(*mine.values())


def mutate(seat, targets, fn):
    seqs, qp = locate(seat, targets), qpath(seat)
    with locked(qp):
        rows = read_q(qp)
        for x in [r for r in rows if r["seq"] in seqs]:
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


def cmd_close(seat, targets, note):
    """close = mark(처리·사유) + reported 를 «한 잠금» 안에서 · 없는 대상은 NOTFOUND rc≠0 (r593 · 재설계 r2) · 대상 조회(hits)도 같은 잠금: 밖에서 세면 그 사이 archive 가 줄을 옮겨 rc0·출력 0(DA⑥ r1 반례 2)."""
    if not targets or not note.strip():
        die('usage: close <seq|group…> "<사유>" [--seat <좌석>]', 2)
    q, m = qpath(seat), {"kind": "처리", "note": note.strip(), "ts": time.strftime("%Y-%m-%dT%H:%M:%S")}
    with locked(q):
        rows = read_q(q)
        mine = {t: {x["seq"] for x in rows if t in (x["group"], str(x["seq"]))} for t in targets}
        for x in [r for r in rows if r["seq"] in set().union(*mine.values())]:
            x.update(mark=m, reported=True)
        write_q(q, rows)
    print("\n".join(f"CLOSED {t} seq={','.join(map(str, sorted(mine[t])))}" if mine[t] else f"NOTFOUND {t}" for t in targets))
    return 1 if [t for t in targets if not mine[t]] else 0


def cmd_report(seat, targets):
    mutate(seat, targets, lambda x: x.update(reported=True))


def cmd_waive(seat, before, reason, tidy=False):
    """기본은 경계 전·mark 있는·열린 줄만 면제. --tidy는 잠금 안에서 반복 도구 알림만 고른다. reported 불변."""
    if not re.search(r"판정 [0-9]+", reason):
        die('usage: waive <좌석> --before <ISO ts> "<판정 N 이 든 사유>" [--tidy]', 2)
    cut, q = datetime.fromisoformat(before), qpath(seat)
    with locked(q):
        rows = read_q(q)
        early = [x for x in rows if datetime.fromisoformat(x["ts"]) < cut]
        hit = tidy_hits(rows, cut) if tidy else [x for x in early if x["mark"] is not None and not obligation_closed(x)]
        for x in hit:
            if tidy and x["mark"] is None:
                x["mark"] = {"kind": "처리", "note": "명시적 면제: " + reason.strip(), "ts": time.strftime("%Y-%m-%dT%H:%M:%S")}
            x["waived"] = {"by": reason.strip(), "ts": time.strftime("%Y-%m-%dT%H:%M:%S")}
        if hit:
            write_q(q, rows)
    print(f"WAIVED {len(hit)} seq={','.join(str(x['seq']) for x in hit)}", f"SKIPPED_NO_MARK {sum(1 for x in early if x['mark'] is None)}", sep="\n")


def cmd_archive(seat):
    with locked(q := qpath(seat)):
        rows = read_q(q)
        move = [x for x in rows if group_closed(rows, x["group"])]
        stay = [x for x in rows if not group_closed(rows, x["group"])]
        for x in [r for r in stay if r["mark"] is not None]:  # 표시는 있는데 술어가 거짓 = 이동 거부 사유를 보인다
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
        if c == "show" and len(a) in (2, 3):
            return cmd_show(a[1], a[2:])
        if c == "rotate" and len(a) == 5 and a[2] == "--before":
            return cmd_rotate(a[1], a[3], a[4])
        if c in ("mark", "report", "close"):
            seat, r = take_seat(a[1:])
            if c == "mark" and len(r) == 3:
                return cmd_mark(seat, *r)
            if c == "report" and r:
                return cmd_report(seat, r)
            if c == "close" and len(r) >= 2:  # r916 — 마지막 인자 = 사유, 앞은 대상들
                return cmd_close(seat, r[:-1], r[-1])
        if c == "waive" and len(a) in (5, 6) and a[2] == "--before" and (len(a) == 5 or a[5] == "--tidy"):
            return cmd_waive(a[1], a[3], a[4], tidy=len(a) == 6)
        if c == "archive" and len(a) == 2:
            return cmd_archive(a[1])
    except (ValueError, TypeError, OSError, json.JSONDecodeError) as e:
        die(f"{c}: {e}", 2 if c == "waive" else 1)
    die("usage: ft-inbox.sh ingest <seq> | show <좌석> [--seqs|--count] | rotate <좌석> --before <ISO ts> \"<판정 N 사유>\" | mark <seq|group> 처리|위임|보류 \"<1줄>\" [--seat <좌석>] | report <seq|group…> [--seat <좌석>] | close <seq|group…> \"<사유>\" [--seat <좌석>] | waive <좌석> --before <ISO ts> \"<판정 N 사유>\" | archive <좌석>", 2)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
