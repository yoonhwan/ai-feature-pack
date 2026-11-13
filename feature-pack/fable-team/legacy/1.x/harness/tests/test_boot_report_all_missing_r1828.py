#!/usr/bin/env python3
"""r1828 — 부팅 보고 관문이 빠진 칸을 한 번에 전부 알린다(반송 1번) · 부팅 보고면 골 표 결함도 같은 줄의 한 칸.
격리: 임시 박스(comm 사본 · 명부 · state · stamps 대역 · 골 표 판정기 대역 FT_BIN) · tmux 스텁 · 실 우편함·실 명부 0 · sleep 0 · 반례 ①~⑧."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

COMM = Path(__file__).resolve().parent.parent / "comm"
T = Path(tempfile.mkdtemp())
FAIL = []
A32, A33 = "byz-harness-arch-claude#32", "byz-harness-arch-claude#33"
M1, PM, L5, PL = "byz-harness-master-claude#1", "byz-harness-pm-claude#1", "byz-lab-arch-claude#5", "byz-planner-master-claude#9"
NOW = 1763000000
STAMP = f"{NOW - 60}-0000abcd"
CELLS = f"담당 없는 오빠 지시 0 · 멈춘 오빠 지시 0 · 판본 {STAMP} 배정 없는 카드 0 · 대기 초과 0 · 판본 {STAMP}"
RET = f"retire={A32}->{A33} rc=0"
GOAL = "★골 표 A6 (시험)★\n| 골 | 상태 |\n★/골 표★\n골좌표: 4 — 하네스 운영 정리 —"
JUDGE = """#!/bin/bash
echo x >> "$GOAL_CALLS"; b="$(cat)"
case "$b" in *'★골 표 A6 ('*'골좌표:'*) echo OK; exit 0;; esac
echo "REJECT 골 없음 — 골 표 블록 없음 (ft-goal-table.sh 출력 붙이기)"; exit 3
"""


def ck(name, cond, info=""):
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else f" :: {info}"))
    if not cond:
        FAIL.append(name)


class Box:
    def __init__(self, name, armed=False, broken=False):
        self.r = T / name
        self.c, self.st, seats, b = self.r / ".fable-team/comm", self.r / ".fable-team/state", self.r / "seats", self.r / "bin"
        for d in (self.c, self.st, seats, b, self.r / "tmp", self.r / "stub"):
            d.mkdir(parents=True)
        for p in [*COMM.glob("mbox*.sh"), *COMM.glob("mbox*.py"), COMM / "ft-boot-report-lint.py"]:
            shutil.copy(p, self.c)
        subprocess.run(["git", "init", "-q", str(self.r)], check=True)
        (self.r / "stub/tmux").write_text("#!/bin/sh\nexit 1\n")
        (b / "ft-goal-table.sh").write_text(JUDGE)
        for x in (self.r / "stub/tmux", b / "ft-goal-table.sh"):
            x.chmod(0o755)
        h = {"_arch": A33, "_master": M1, A32: {"role": "stop-ready", "_retired_role": "arch", "_replaced_by": A33},
             A33: {"role": "arch", "_replaces": [A32]}, M1: {"role": "master"}, PM: {"role": "pm"}}
        (seats / "seats.json").write_text("{}")
        (seats / "seats-harness.json").write_text('{"' + A33 + '": {"role": "arch", "_replaces": [' if broken else json.dumps(h))
        (seats / "seats-lab.json").write_text(json.dumps({"_arch": L5, L5: {"role": "arch"}}))
        (seats / "seats-planner.json").write_text(json.dumps({"_master": PL, PL: {"role": "master", "tick": None}}))
        (self.r / "dir.tsv").write_text(f"{STAMP}\t0\t0\n")
        (self.r / "asg.tsv").write_text(f"{STAMP}\t0\t0\t0\tabcd\n")
        if armed:
            (self.st / "goal-gate.armed").write_text("")
        self.calls = self.r / "calls"
        self.env = dict(os.environ, PATH=f"{self.r}/stub:{os.environ['PATH']}", FT_SEATS_JSON=str(seats / "seats.json"),
                        FT_PLANNER_HEAD_MODE="reject", FT_MBOX_DIR=str(self.c), FT_MBOX_RATE_N="999", FT_MBOX_FANOUT_WINDOW="0",
                        FT_BIN=str(b), GOAL_CALLS=str(self.calls), TMPDIR=str(self.r / "tmp"),
                        FT_DIRECTIVE_STAMPS=str(self.r / "dir.tsv"), FT_CARD_ASSIGN_STAMPS=str(self.r / "asg.tsv"),
                        FT_DIRECTIVE_NOW=str(NOW))

    def send(self, frm, to, body):
        p = subprocess.run(["bash", str(self.c / "mbox.sh"), "send", to, frm, body], cwd=self.r, env=self.env,
                           capture_output=True, text=True, timeout=60)
        return p.returncode, p.stdout + p.stderr

    def queued(self, to):
        f = self.c / "mailbox.jsonl"
        return sum(1 for ln in f.read_text().splitlines() if json.loads(ln).get("to") == to) if f.exists() else 0

    def judged(self):
        return len(self.calls.read_text().splitlines()) if self.calls.exists() else 0

    def goal_log(self, verb):
        f = self.st / "mbox-guard-goal.log"
        return sum(1 for ln in f.read_text().splitlines() if f" {verb} " in ln) if f.exists() else 0


def rejects(out):
    return [ln for ln in out.splitlines() if ln.startswith("REJECT")]


def main():
    boot = f"[부팅 보고] {A33} 세션=x 모델=y"
    # ① 승계 arch · retire·지시·배정 칸 없음(비무장) → REJECT 1줄 «빠진 칸 3» · 세 칸 문구
    b = Box("c1")
    rc, out = b.send(A33, PM, f"{boot} cron=abc12345")
    r = rejects(out)
    ck("① 세 칸 한 번에", rc == 3 and len(r) == 1 and "빠진 칸 3" in r[0] and all(k in r[0] for k in (f"retire 칸 없음: {RET}", "지시 칸 없음", "배정 칸 없음")) and b.queued(PM) == 0, out)
    # ② ① + 골 표 없음(무장) → «빠진 칸 4» 1줄 · 큐 0 · 판정기 1회
    b = Box("c2", armed=True)
    rc, out = b.send(A33, PM, f"{boot} cron=abc12345")
    r = rejects(out)
    ck("② 골 표까지 네 칸 1줄", rc == 3 and len(r) == 1 and "빠진 칸 4" in r[0] and "골 표 블록 없음" in r[0] and b.queued(PM) == 0 and b.judged() == 1, out)
    # ③ 네 칸 다 채워 다시 → OK · 큐 1 · 판정기 1회(이중 검사 0)
    j0 = b.judged()
    rc, out = b.send(A33, PM, f"{boot} {RET} cron=abc12345 {CELLS}\n{GOAL}")
    ck("③ 다 채우면 통과 · 골 판정 1회", rc == 0 and b.queued(PM) == 1 and b.judged() - j0 == 1, f"rc={rc} judged={b.judged()} :: {out}")
    # ④ 명부 판정 불가 + 다른 칸도 빠짐 → 판정 불가 문구 1줄만(비무장 · 무장 둘 다)
    for armed in (False, True):
        b = Box(f"c4{int(armed)}", armed=armed, broken=True)
        rc, out = b.send(A33, PL, boot)
        r = rejects(out)
        ck(f"④ 판정 불가 즉시(무장={armed})", rc == 3 and len(r) == 1 and "판정 불가" in r[0] and "빠진 칸" not in r[0] and b.queued(PL) == 0, out)
    # ⑤ 부팅 보고 아닌 [틱]·[발주](무장 · 골 표 없음) → 골 표 반송 문구 그대로 · 부팅 lint 칸 0
    for head in ("[틱] 하네스 상태 · 부팅 대기 좌석 0", "[발주] r9 나노 1"):
        b = Box("c5" + str(len(head)), armed=True)
        rc, out = b.send(M1, PM, head)
        r = rejects(out)
        ck(f"⑤ {head[:4]} 골 표 문구 그대로", rc == 3 and r == ["REJECT 골 없음 — 골 표 블록 없음 (ft-goal-table.sh 출력 붙이기)"] and b.judged() == 1 and b.goal_log("REJECT") == 1, out)
    # ⑥ 칸 하나만 빠짐 → «빠진 칸 1» · 칸 문구 = 지금 문구
    b = Box("c6")
    rc, out = b.send(A33, PM, f"{boot} {RET} {CELLS}")
    r = rejects(out)
    ck("⑥ 한 칸 · 지금 문구", rc == 3 and r == ["REJECT 부팅 보고 반송 — 빠진 칸 1: ①cron 칸 없음: cron=<job id> (BOOT 16 — 부팅 보고 턴에 CronCreate)"], out)
    # ⑦ 비무장 · 부팅 칸 다 있음 · 골 표 없음 → OK · 큐 1 · WOULD-REJECT 로그 1줄
    b = Box("c7")
    rc, out = b.send(A33, PM, f"{boot} {RET} cron=abc12345 {CELLS}")
    ck("⑦ 비무장 통과 · WOULD-REJECT 1", rc == 0 and b.queued(PM) == 1 and b.goal_log("WOULD-REJECT") == 1 and b.judged() == 1, f"rc={rc} log={b.goal_log('WOULD-REJECT')} :: {out}")
    # ⑧ 비승계 arch · «[HIL] 부팅 끝: <좌석> cron=test» · 무장 · 골 표 없음 → OK · 큐 1 · 판정기 0
    b = Box("c8", armed=True)
    rc, out = b.send(L5, PM, f"[HIL] 부팅 끝: {L5} cron=test")
    ck("⑧ [HIL] 부팅 끝 = 골 칸 0", rc == 0 and b.queued(PM) == 1 and b.judged() == 0 and not rejects(out), f"rc={rc} judged={b.judged()} :: {out}")
    shutil.rmtree(T, ignore_errors=True)
    print(f"{'FAIL' if FAIL else 'OK'} r1828 {len(FAIL)} fail")
    sys.exit(1 if FAIL else 0)


main()
