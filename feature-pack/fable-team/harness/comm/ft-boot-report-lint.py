#!/usr/bin/env python3
"""[부팅 보고] 본문 lint (P4 r-succession-gate · 판정 1155 ①) — stdin 본문 + --from <좌석> --seats-dir <명부 폴더>.
출력 1줄 `OK` | `REJECT <사유>` · rc 0/1. 명부 파싱 실패·행 없음 = OK + stderr WARN 1줄(조용한 통과 아님). 외부 호출 0.
  ①승계(발신 이름 X#N 이고 명부에 X#N-1 행 있음, 또는 _replaces 있음)면 본문에 `retire=<구>-><후계> rc=0`(-> 또는 →) —
    구 ∈ {X#N-1, _replaces} · 후계 == 발신 좌석 · 구 행 _replaced_by == 발신 좌석(칸 글자가 아니라 명부 사실)
  ②발신 좌석 role 이 master·arch 면 `cron=<id>` 칸(BOOT 16)
  ③planner 팀장(seats-planner.json `_master`)·desk(role=desk) 면 `adhd=O` 칸(BOOT 2·9 · r625) — 그 밖 좌석 검사 0
설계 정본 = PLAN-planner-no-stall-20261012 r5 §4-2 · 명부 파일 선택 = mbox_guard.sh tfile 규칙(v65 → seats.json, 그 외 seats-<팀>.json)."""
import argparse, json, os, re, sys
from typing import NoReturn


def say(verb: str, msg: str = "") -> NoReturn:
    print((verb + " " + msg).strip())
    sys.exit(1 if verb == "REJECT" else 0)


def warn_ok(msg: str) -> NoReturn:
    print("WARN 부팅 보고 lint — " + msg + " · 검사 없이 전송", file=sys.stderr)
    say("OK")


def seats_doc(seats_dir, me):
    m = re.match(r"^(?:byz|ft)-([a-z0-9]+)-", me)
    if not m:
        warn_ok("발신 좌석 이름에서 팀을 못 읽음(" + (me or "from 없음") + ")")
    f = os.path.join(seats_dir, "seats.json" if m.group(1) == "v65" else "seats-" + m.group(1) + ".json")
    try:
        return json.load(open(f, encoding="utf-8"))
    except Exception:
        warn_ok("명부 읽기 실패 " + os.path.basename(f))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="me", default="")
    ap.add_argument("--seats-dir", required=True)
    a = ap.parse_args()
    body = sys.stdin.read()
    d = seats_doc(a.seats_dir, a.me)
    if not isinstance(d, dict):
        warn_ok("명부가 객체가 아님")
    row = d.get(a.me) if isinstance(d.get(a.me), dict) else None
    n = re.match(r"^(.+)#(\d+)$", a.me)  # 승계 판별 = 이름 X#N 이고 명부에 X#N-1 행(후계 행·_replaces 무관 — retire 를 안 돌린 승계도 잡는다)
    prev = n.group(1) + "#" + str(int(n.group(2)) - 1) if n and int(n.group(2)) >= 1 else ""
    prev_row = d.get(prev) if isinstance(d.get(prev), dict) else None
    cands = list(dict.fromkeys(([prev] if prev_row else []) + list((row or {}).get("_replaces") or [])))
    if row is None and not cands:
        warn_ok("명부에 행 없음 " + a.me)
    if cands:
        want = "retire=" + cands[0] + "->" + a.me + " rc=0"
        m = re.search(r"retire=([^\s>→]+?)\s*(?:->|→)\s*([^\s·,;]+)\s+rc=0", body)
        if not m:
            say("REJECT", "부팅 보고 반송 — retire 칸 없음: " + want + " (ft-seat-retire.sh <구> <후계> 를 먼저 실행해 출력 복붙)")
        old, new = m.group(1), m.group(2)
        if old not in cands or new != a.me:
            say("REJECT", "부팅 보고 반송 — retire 칸 불일치(" + old + "->" + new + "): " + want)
        old_row = d.get(old)
        if not isinstance(old_row, dict) or old_row.get("_replaced_by") != a.me:
            say("REJECT", "부팅 보고 반송 — retire 칸은 있는데 명부 미반영 — ft-seat-retire.sh " + old + " " + a.me + " 실행 뒤 다시")
    if (row or {}).get("role") in ("master", "arch") and not re.search(r"cron=[A-Za-z0-9_-]+", body):
        say("REJECT", "부팅 보고 반송 — cron 칸 없음: cron=<job id> (BOOT 16 — 부팅 보고 턴에 CronCreate)")
    adhd_seat = (a.me == d.get("_master") and a.me.startswith(("byz-planner-", "ft-planner-"))) or (row or {}).get("role") == "desk"
    if adhd_seat and not re.search(r"(?<![A-Za-z0-9_])adhd=O(?![A-Za-z0-9_])", body):
        say("REJECT", "부팅 보고 반송 — adhd 칸 없음: adhd=O (i-have-adhd 로드 뒤 · BOOT 2·9)")
    say("OK")


main()
