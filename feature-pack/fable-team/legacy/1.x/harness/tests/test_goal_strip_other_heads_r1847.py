#!/usr/bin/env python3
"""r1847 — 표 머리([부팅]·[틱]·[A6]·[완료·휴식])·좌표 머리 밖 쪽지에 붙은 골 표는 머리·발신자 검사 «앞»에서 떼고 적재 + GOAL-TRIM 1줄.
반례 ①~③(카드 동결) · 격리: 임시 git 리포 = 임시 루트(comm·bin 사본 · state · 명부) · tmux·공지 mbox 스텁 · 실 우편함 0 · sleep 0.
변이용: env R1847_SRC = 다른 harness 폴더(comm·bin 사본을 거기서 뜬다)."""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

H = Path(os.environ.get("R1847_SRC") or Path(__file__).resolve().parent.parent)
T = Path(tempfile.mkdtemp())
R, FT, CP = T / "root", T / "root/.fable-team", "design/planner/AUTONOMY-GOAL-A6-20261018.md"
PM, HM, NANO, TO = "byz-planner-master-claude#9", "byz-harness-master-claude#64", "byz-harness-nano-x#0", "byz-zz-nano-q#0"
G6 = ["v65 마이크 넘기기 완성", "룸 이전 사용성", "강의 이전 PiP", "하네스 운영 정리 — 끝난 일", "전팀 지침 재기동", "메모리 제한 완성"]
C4, FAIL = "골좌표: 4 — 하네스 운영 정리 —", []

def ck(name, cond, info=""):
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else f" :: {str(info)[:400]}"))
    FAIL.extend([] if cond else [name])

def run(*a):
    env = dict(os.environ, PATH=f"{T}/stub:{os.environ['PATH']}", FT_ROOT=str(R), FT_NOW="2026-11-13 12:00", FT_GOAL_A6_MD=f"gitref:origin/main:{CP}",
               FT_GOAL_A6_LEDGER=str(T / "없는원장.md"), FT_GOAL_REPO=str(R), FT_LEDGER_REPO=str(R), FT_MBOX=str(T / "stub/mbox"),
               FT_SEATS_JSON=str(R / "seats/seats.json"), FT_MBOX_DIR=str(FT / "comm"), FT_MBOX_RATE_N="999", FT_MBOX_FANOUT_WINDOW="0", FT_MBOX_RESEND_COOLDOWN="0")
    [env.pop(k, None) for k in ("FT_PLANNER_HEAD_MODE", "FT_BIN", "FT_GOAL_RENUMBER_GRACE_H", "FT_TEAMS_REF")]
    p = subprocess.run([str(x) for x in a], env=env, cwd=R, capture_output=True, text=True, timeout=60)
    return p.returncode, p.stdout + p.stderr, p.stdout

[d.mkdir(parents=True) for d in (FT / "comm", FT / "bin", FT / "state", R / "seats", R / "design/planner", T / "stub")]
[shutil.copy(p, FT / "comm") for p in [*(H / "comm").glob("mbox*.sh"), *(H / "comm").glob("mbox*.py"), H / "comm/bang_command_check.py"]]
[shutil.copy(H / "bin" / f, FT / "bin") for f in ("ft-goal-table.sh", "ft_goal_table.py", "ft_goal_ledger.py", "ft_team_lib.py", "ft_goal_readjust_state.py")]
for name, v in {"seats-planner.json": {"_master": PM}, "seats-harness.json": {"_master": HM, NANO: {"role": "nano"}}, "seats.json": {}}.items():
    (R / "seats" / name).write_text(json.dumps(v), encoding="utf-8")
for name, body in (("tmux", "exit 1"), ("mbox", "exit 0")):
    (T / "stub" / name).write_text(f"#!/bin/sh\n{body}\n") or (T / "stub" / name).chmod(0o755)
subprocess.run(["git", "init", "-q", "-b", "main", str(R)], check=True)
rows = "".join(f"| {g} | 팀x | 착지 sha |\n" for g in G6)
(R / CP).write_text("# 자율 골 A6 (시험)\n\n## 골 → 팀 → 닫는 증거\n\n| 골(원문) | 담당 팀 | 닫는 증거 |\n|---|---|---|\n" + rows, encoding="utf-8")
for a in (("add", "design"), ("commit", "-qm", "canon"), ("update-ref", "refs/remotes/origin/main", "HEAD")):
    subprocess.run(["git", "-C", str(R), "-c", "user.name=t", "-c", "user.email=t@t", *a], check=True, capture_output=True)
(FT / "state/goal-gate.armed").touch()
BLOCK = run("bash", FT / "bin/ft-goal-table.sh")[2].strip()
ck("기준 렌더 = 골 표 블록", BLOCK.startswith("★골 표 A6 (") and BLOCK.endswith("★/골 표★"), BLOCK)

def send(frm, body, verb="send", attach=None):
    rc, out, _ = run("bash", FT / "comm/mbox.sh", verb, TO, frm, *([attach] if attach else []), body)
    seq, p = re.search(r"QUEUED seq=(\d+)", out), FT / "comm/mailbox.jsonl"
    box = [json.loads(x) for x in p.read_text(encoding="utf-8").splitlines() if x.strip()] if p.exists() else []
    return rc, out, next((e["body"] for e in box if seq and str(e.get("seq")) == seq[1]), None), len(re.findall(r"^GOAL-TRIM \d+B$", out, re.M))

for name, frm, head in (("① [HIL] · 명부 역할", PM, "[HIL] 판단 필요"), ("① [정지 레디] · 명부 역할", HM, "[정지 레디] 멈춤"), ("② 나노 [회신]", NANO, "[회신] 끝")):
    rc, out, b, n = send(frm, f"{head}\n{BLOCK}\n{C4}\n본문")
    ck(f"{name} + 붙은 표 → 표 0 · GOAL-TRIM 1줄 · rc0", rc == 0 and b == f"{head}\n{C4}\n본문" and n == 1, f"rc={rc} b={b!r} {out}")
att = T / "att.md"
att.write_text(f"{BLOCK}\n첨부 본문\n", encoding="utf-8")
rc, out, b, n = send(NANO, "[회신] relay\n본문", verb="relay", attach=str(att))
snap = re.search(r"상세\(전문\): (\S+)", b or "")
stext = Path(snap[1]).read_text(encoding="utf-8") if snap and Path(snap[1]).exists() else ""
ck("② relay 나노 [회신] + 첨부 표 → 사본에서만 뗌 · GOAL-TRIM 1줄", rc == 0 and stext == "첨부 본문\n" and n == 1 and att.read_text(encoding="utf-8").startswith(BLOCK), f"rc={rc} snap={stext!r} {out}")
rc, out, b, n = send(HM, f"[부팅 보고] 세션=x\n{BLOCK}\n{C4}")
ck("③ [부팅 보고] + 표 → 그대로 적재 · GOAL-TRIM 0", rc == 0 and b is not None and BLOCK in b and n == 0, f"rc={rc} b={b!r} {out}")
rc, out, b, n = send(PM, f"[발주] 표 붙음\n{BLOCK}\n{C4}")
ck("③ [발주] + 표 → r1830 그대로(뗌 · GOAL-TRIM 1줄)", rc == 0 and b == f"[발주] 표 붙음\n{C4}" and n == 1, f"rc={rc} b={b!r} {out}")
shutil.rmtree(T, ignore_errors=True)
print(f"== test_goal_strip_other_heads_r1847: fail={len(FAIL)}")
sys.exit(1 if FAIL else 0)
