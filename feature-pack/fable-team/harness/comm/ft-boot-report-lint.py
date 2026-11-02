#!/usr/bin/env python3
"""[부팅 보고] 본문 lint (P4 r-succession-gate · 판정 1155 ①) — stdin 본문 + --from <좌석> --seats-dir <명부 폴더>.
출력 1줄 `OK` | `REJECT <사유>` · rc 0/1/2(2 = 명부 판정 불가 — 하드 룰 20. 부르는 쪽(mbox_guard.sh)은 rc≠0 을 전부 REJECT 로 본다).
  ⓪r1319 발동 조건(C3) = mbox_retire_check.is_boot_report — 실제 보고 머리 꼴(«[HIL] 부팅 끝: …» · «골자표: … · [부팅 보고] arch#204»)을 포함 · 남의 부팅 보고를 언급한 쪽지는 0.
  ①승계(C0c = me 행 `_replaces` · 또는 _closed 아닌 X#N-1 의 [인계] 기록 — «X#N-1 행 있음» 만으로는 승계 아님)면 본문에 `retire=<구>-><후계> rc=0`(-> 또는 →) +
    C0 검사(같은 폴더 명부 `_*` 칸에 구 이름이 남으면 REJECT). · 명부 고르기 = C0b(그 좌석 키를 가진 파일 → 팀 명부) — mbox_retire_check 공용. 판정 불가 = rc 2.
  ②발신 좌석 role 이 master·arch 면 `cron=<id>` 칸(BOOT 16)
  ③planner 팀장(seats-planner.json `_master`)·desk(role=desk) 면 `adhd=O` 칸(BOOT 2·9 · r625) — 그 밖 좌석 검사 0 · ④승계 master·planner·desk·arch 면 «담당 없는 오빠 지시 N · 멈춘 오빠 지시 M · 판본 <stamp>» 칸 = stamps.tsv 행 대조·30분(r1212) · ⑤같은 좌석 «배정 없는 카드 N · 대기 초과 M · 판본 <stamp>» 칸(r1224 · 전용 card-assign/stamps.tsv · 독립 호출)
설계 정본 = PLAN-planner-no-stall-20261012 r5 §4-2 · 명부 파일 선택 = mbox_guard.sh tfile 규칙(v65 → seats.json, 그 외 seats-<팀>.json)."""
import argparse, json, os, re, sys, time
import mbox_retire_check   # r1319 — C0·C0b·C0c·C3·C4 검사(승계·명부)는 그 모듈 하나. 200줄 규칙.
from typing import NoReturn


def say(verb: str, msg: str = "", code: int = 0) -> NoReturn:
    print((verb + " " + msg).strip())
    sys.exit(code if code else (1 if verb == "REJECT" else 0))


def gate(g) -> None:   # (rc, 문구) — None 통과 · rc 3 REJECT(rc1) · rc 2 판정 불가(rc2)
    if g:
        say("REJECT", g[1][7:].strip() if g[1].startswith("REJECT ") else g[1], 1 if g[0] == 3 else 2)


def seats_root(seats_dir, me):   # r1319 C0b — 명부 폴더를 행이 있는 파일 기준으로 좁힌다(retire 와 같은 규칙). 판정 불가면 팀 명부 폴더.
    f = mbox_retire_check.pick(seats_dir, me)[0]
    return os.path.dirname(f) or seats_dir


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="me", default="")
    ap.add_argument("--seats-dir", required=True)
    a = ap.parse_args()
    body = sys.stdin.read()
    if not mbox_retire_check.is_boot_report(body, a.me):   # C3 — 부팅 보고가 아니면 검사 0(남의 보고를 언급한 쪽지 포함)
        say("OK")
    root = seats_root(a.seats_dir, a.me)
    d = mbox_retire_check.pick(root, a.me)[1]
    row = d.get(a.me) if isinstance(d.get(a.me), dict) else None
    succ, why = mbox_retire_check.succession(root, a.me, mbox_retire_check._sent())   # C0c
    if succ is None:
        say("REJECT", "부팅 보고 반송 — 판정 불가: " + why, 2)   # C6 — 명부를 못 읽으면 조용한 통과 0
    gate(mbox_retire_check.boot_gate(root, a.me, body))          # C4 — retire 칸 + C0 검사
    if (row or {}).get("role") in ("master", "arch") and not re.search(r"cron=[A-Za-z0-9_-]+", body):
        say("REJECT", "부팅 보고 반송 — cron 칸 없음: cron=<job id> (BOOT 16 — 부팅 보고 턴에 CronCreate)")
    adhd_seat = (a.me == d.get("_master") and a.me.startswith(("byz-planner-", "ft-planner-"))) or (row or {}).get("role") == "desk"
    if adhd_seat and not re.search(r"(?<![A-Za-z0-9_])adhd=O(?![A-Za-z0-9_])", body):
        say("REJECT", "부팅 보고 반송 — adhd 칸 없음: adhd=O (i-have-adhd 로드 뒤 · BOOT 2·9)")
    if succ and ((row or {}).get("role") in ("master", "arch", "desk") or a.me == d.get("_master")):
        directive_cell(os.environ.get("FT_DIRECTIVE_STAMPS") or os.path.join(root, "state", "directive-watch", "stamps.tsv"), body)
        directive_cell(os.environ.get("FT_CARD_ASSIGN_STAMPS") or os.path.join(root, "state", "card-assign", "stamps.tsv"), body, *ASSIGN)
    say("OK")
ASSIGN = ("배정", r"배정 없는 카드 (\d+) · 대기 초과 (\d+)(?:\([^)]*\))?(?: · 정지 중 \d+)?(?: · 보류 중 \d+)?(?: · 판정 불가 Q \d+)?(?: · 카드 없는 발주 \d+)?", "배정 없는 카드 N · 대기 초과 M", "ft-card-assign-watch.sh")  # ⑤ r1224 — 전용 stamps · 머리의 (사유별)·정지 중·발주 칸은 건너뛴다
def directive_cell(f, body, what="지시", rx=r"담당 없는 오빠 지시 (\d+) · 멈춘 오빠 지시 (\d+)", fmt="담당 없는 오빠 지시 N · 멈춘 오빠 지시 M", tool="ft-directive-watch.sh"):  # ④ r1212 승계 master·planner·desk·arch — 지시 칸을 다시 세지 않고 stamps.tsv 의 그 판본 행과 대조 · «판정 불가 · <사유>» 칸만 WARN 통과 · 판본 파일 없음 = 반송
    if re.search(what + r" 감시 판정 불가 · \S", body):
        return print("WARN 부팅 보고 lint — " + what + " 칸 «판정 불가» · 대조 없이 통과", file=sys.stderr)
    m = re.search(rx + r" · 판본 ((\d+)-[0-9a-f]{8})", body)
    rows = {r[0]: r[1:3] for r in (ln.rstrip("\n").split("\t") for ln in open(f, encoding="utf-8")) if len(r) >= 3} if os.path.isfile(f) else None
    why = "칸 없음" if not m else "판본 파일 없음(" + f + ")" if rows is None else "판본 행 없음" if m.group(3) not in rows else "숫자 다름" if rows[m.group(3)] != [m.group(1), m.group(2)] else "판본 30분 넘음" if float(os.environ.get("FT_DIRECTIVE_NOW") or time.time()) - int(m.group(4)) > 1800 else ""
    if why:
        say("REJECT", "부팅 보고 반송 — " + what + " " + why + ": " + fmt + " · 판본 <stamp> (" + tool + " status 를 새로 돌려 머리 1줄 복붙)")

main()
