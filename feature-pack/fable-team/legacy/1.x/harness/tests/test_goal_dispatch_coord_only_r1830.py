#!/usr/bin/env python3
"""r1830 — 좌표 머리([발주]·[팀 발주]·[착지 차례]) = `골좌표:` 1줄만(골 표 블록 요구 0 · 붙은 표는 떼고 적재 + GOAL-TRIM) · 판정기 `check - --coord-only`.
표 머리([부팅]·[틱]·[A6]·[완료·휴식]) = 지금 그대로(블록 + 골좌표) · 반례 ①~⑦″(카드 동결) · 격리: 임시 git 리포 = 임시 루트(comm·bin 사본 · state · 명부) · tmux 스텁 · 공지 mbox 스텁 · 실 우편함·실 Slack·실 launchd 0 · sleep 0.
변이용: env R1830_SRC = 다른 harness 폴더(comm·bin 사본을 거기서 뜬다)."""
import filecmp
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

H = Path(os.environ.get("R1830_SRC") or Path(__file__).resolve().parent.parent)
T = Path(tempfile.mkdtemp())
R, CP = T / "root", "design/planner/AUTONOMY-GOAL-A6-20261018.md"
FT = R / ".fable-team"
NOW, LATE = "2026-11-13 12:00", "2026-11-14 13:00"   # LATE = 번호표 바뀐 뒤 25시간(유예 24시간 밖)
PM, HM, NANO, TO = "byz-planner-master-claude#9", "byz-harness-master-claude#64", "byz-harness-nano-x#0", "byz-zz-nano-q#0"
G6 = ["v65 마이크 넘기기 완성", "룸 이전 사용성", "강의 이전 PiP", "하네스 운영 정리 — 끝난 일", "전팀 지침 재기동", "메모리 제한 완성"]
C4 = "골좌표: 4 — 하네스 운영 정리 —"
FAIL = []

def ck(name, cond, info=""):
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else f" :: {str(info)[:400]}"))
    if not cond:
        FAIL.append(name)

def run(*a, inp=None, now=NOW):
    env = dict(os.environ, PATH=f"{T}/stub:{os.environ['PATH']}", FT_ROOT=str(R), FT_NOW=now, FT_GOAL_A6_MD=f"gitref:origin/main:{CP}",
               FT_GOAL_A6_LEDGER=str(T / "없는원장.md"), FT_GOAL_REPO=str(R), FT_LEDGER_REPO=str(R), FT_MBOX=str(T / "stub/mbox"),
               FT_SEATS_JSON=str(R / "seats/seats.json"), FT_MBOX_DIR=str(FT / "comm"), FT_MBOX_RATE_N="999",
               FT_MBOX_FANOUT_WINDOW="0", FT_MBOX_RESEND_COOLDOWN="0")
    for k in ("FT_PLANNER_HEAD_MODE", "FT_BIN", "FT_GOAL_RENUMBER_GRACE_H", "FT_TEAMS_REF"):
        env.pop(k, None)
    p = subprocess.run([str(x) for x in a], input=inp, env=env, cwd=R, capture_output=True, text=True, timeout=60)
    return p.returncode, p.stdout, p.stderr

def git(*a):
    subprocess.run(["git", "-C", str(R), "-c", "user.name=t", "-c", "user.email=t@t", *a], check=True, capture_output=True)

def canon(goals):
    rows = "".join(f"| {g} | 팀x | 착지 sha |\n" for g in goals)
    (R / CP).write_text("# 자율 골 A6 (시험)\n\n## 골 → 팀 → 닫는 증거\n\n| 골(원문) | 담당 팀 | 닫는 증거 |\n|---|---|---|\n" + rows, encoding="utf-8")
    git("add", "design")
    git("commit", "-qm", "canon")
    git("update-ref", "refs/remotes/origin/main", "HEAD")
    rc, out, err = run("bash", FT / "bin/ft-goal-table.sh")
    return out.strip() if rc == 0 else f"render rc={rc} {err}"

def setup():
    for d in (FT / "comm", FT / "bin", FT / "state", R / "seats", R / "design/planner", T / "stub"):
        d.mkdir(parents=True)
    for p in [*(H / "comm").glob("mbox*.sh"), *(H / "comm").glob("mbox*.py"), H / "comm/bang_command_check.py"]:
        shutil.copy(p, FT / "comm")
    for f in ("ft-goal-table.sh", "ft_goal_table.py", "ft_goal_ledger.py", "ft_team_lib.py", "ft_goal_readjust_state.py"):
        shutil.copy(H / "bin" / f, FT / "bin")
    for name, v in {"seats-planner.json": {"_master": PM}, "seats-harness.json": {"_master": HM, NANO: {"role": "nano"}}, "seats.json": {}}.items():
        (R / "seats" / name).write_text(json.dumps(v), encoding="utf-8")
    for name, body in (("tmux", "exit 1"), ("mbox", "exit 0")):
        (T / "stub" / name).write_text(f"#!/bin/sh\n{body}\n")
        (T / "stub" / name).chmod(0o755)
    subprocess.run(["git", "init", "-q", "-b", "main", str(R)], check=True)

def box():
    p = FT / "comm/mailbox.jsonl"
    return [json.loads(x) for x in p.read_text(encoding="utf-8").splitlines() if x.strip()] if p.exists() else []

def send(frm, body, armed=True, verb="send", attach=None, now=NOW):
    flag = FT / "state/goal-gate.armed"
    flag.touch() if armed else flag.unlink(missing_ok=True)
    rc, out, err = run("bash", FT / "comm/mbox.sh", verb, TO, frm, *([attach] if attach else []), body, now=now)
    seq = re.search(r"QUEUED seq=(\d+)", out)   # ring 포화로 옛 줄이 밀려나도 «이번 적재» 줄만 본다
    return rc, out + err, next((e["body"] for e in box() if seq and str(e.get("seq")) == seq[1]), None)

def check(body, *flags, now=NOW):
    rc, out, err = run("bash", FT / "bin/ft-goal-table.sh", "check", "-", *flags, inp=body, now=now)
    return rc, out + err

setup()
BLOCK = canon(G6)
ck("기준 렌더 = 골 표 블록", BLOCK.startswith("★골 표 A6 (") and BLOCK.endswith("★/골 표★"), BLOCK)

rc, out, b = send(PM, "[발주] r1830 시험\n" + C4)
ck("① 무장 · _master [발주] + 골좌표 · 표 없음 → 통과 · 적재 1", rc == 0 and b == "[발주] r1830 시험\n" + C4, f"rc={rc} b={b!r} {out}")
rc, out, b = send(PM, "[발주] 좌표 없음\n본문")
ck("①′ 골좌표도 없음 → REJECT «골좌표 줄 없음» · 적재 0", rc == 3 and b is None and "골좌표" in out and "줄이 없다" in out, f"rc={rc} {out}")

def trimmed(head):
    rc, out, b = send(PM, f"{head} 표 붙음\n{BLOCK}\n{C4}\n나머지 본문")
    return (rc == 0 and b == f"{head} 표 붙음\n{C4}\n나머지 본문" and len(re.findall(r"^GOAL-TRIM \d+B$", out, re.M)) == 1), f"rc={rc} b={b!r} {out}"


ok, info = trimmed("[발주]")
ck("② [발주] + 골 표 블록 + 골좌표 → 블록만 떼고 적재 · GOAL-TRIM 1줄", ok, info)

rc, out, b = send(HM, "[틱] 보고\n세션=x")
ck("③ [틱] 표 없음 → REJECT(회귀)", rc == 3 and b is None and "골 없음" in out, f"rc={rc} {out}")
rc, out, b = send(HM, "[부팅 보고] 세션=x\n" + C4)
ck("③ [부팅 보고] 표 없음(골좌표만) → REJECT(회귀)", rc == 3 and b is None, f"rc={rc} {out}")
rc, out, b = send(HM, f"[틱] 보고\n{BLOCK}\n{C4}")
ck("③ [틱] 표 있음 → 블록 그대로 적재 · GOAL-TRIM 0", rc == 0 and b is not None and BLOCK in b and "GOAL-TRIM" not in out, f"rc={rc} b={b!r} {out}")

for h in ("[팀 발주]", "[착지 차례]"):
    rc, out, b = send(PM, f"{h} 시험\n{C4}")
    ck(f"④ {h} + 골좌표 · 표 없음 → 통과", rc == 0 and b == f"{h} 시험\n{C4}", f"rc={rc} b={b!r} {out}")
    rc, out, b = send(PM, f"{h} 좌표 없음\n본문")
    ck(f"④ {h} 골좌표 없음 → REJECT", rc == 3 and b is None, f"rc={rc} {out}")
    ok, info = trimmed(h)
    ck(f"④ {h} + 블록 → 블록만 뗌", ok, info)

rc, out, b = send(NANO, f"[발주] 나노\n{BLOCK}\n본문")
ck("⑤ 나노 발신 [발주] → 검사 0 · 본문 그대로(떼기 0)", rc == 0 and b == f"[발주] 나노\n{BLOCK}\n본문" and "GOAL-TRIM" not in out, f"rc={rc} b={b!r} {out}")
rc, out, b = send(PM, "[긴급] 중단\n본문")
ck("⑤ [긴급] → 검사 0", rc == 0 and b is not None, f"rc={rc} {out}")

rc, out, b = send(PM, "[발주] 비무장\n본문", armed=False)
log = (FT / "state/mbox-guard-goal.log").read_text(encoding="utf-8") if (FT / "state/mbox-guard-goal.log").exists() else ""
ck("⑥ 비무장 · [발주] 골좌표 없음 → WOULD-REJECT 로그 · 적재 1", rc == 0 and b is not None and "WOULD-REJECT" in log.splitlines()[-1], f"rc={rc} log={log[-200:]} {out}")

att = T / "att.md"
att.write_text(f"{BLOCK}\n첨부 본문\n", encoding="utf-8")
rc, out, b = send(PM, "[발주] relay 시험\n" + C4, verb="relay", attach=str(att))
snap = re.search(r"상세\(전문\): (\S+)", b or "")
stext = Path(snap[1]).read_text(encoding="utf-8") if snap and Path(snap[1]).exists() else ""
ck("② relay 좌표 머리 → 첨부 사본에서 블록만 뗌 · 원본 손 0", rc == 0 and "첨부 본문" in stext and "★골 표" not in stext and BLOCK in att.read_text(encoding="utf-8"),
   f"rc={rc} snap={stext!r} {out}")

rc, out = check("본문\n" + C4, "--coord-only")
ck("⑦ check - --coord-only · 블록 없음 + 지금 번호표 골좌표 → rc0 GOAL-OK n=4", rc == 0 and "GOAL-OK n=4" in out and "유예" not in out, f"rc={rc} {out}")
rc, out = check("본문\n" + C4)
ck("⑦ 같은 본문 check -(인자 없음) → rc3 블록 없음(check 불변)", rc == 3 and "골 표 블록" in out, f"rc={rc} {out}")

G6b = [G6[0], "새 골 둘째 항목", *G6[2:]]
canon(G6b)
mark = FT / "state/goal-numbering.tsv"
ck("번호표 바뀐 렌더 → 표식에 직전 판 줄", "\nprev\t" in mark.read_text(encoding="utf-8"), mark.read_text(encoding="utf-8"))
OLD = "본문\n골좌표: 2 — 룸 이전 사용성"
rc, out = check(OLD, "--coord-only")
ck("⑦′ 직전 판 번호 골좌표 · 유예 안 → rc0 «옛 번호표(유예 …)»", rc == 0 and "GOAL-OK n=2 옛 번호표(유예" in out, f"rc={rc} {out}")
rc, out = check("본문\n골좌표: 2 — 새 골 둘째 항목", "--coord-only")
ck("⑦′ 새 번호표 골좌표 → rc0 · 유예 문구 0", rc == 0 and "GOAL-OK n=2" in out and "유예" not in out, f"rc={rc} {out}")
rc, out, b = send(PM, "[발주] 옛 번호" + OLD[2:])
ck("⑦′ 가드 경유 → 통과 + GL-GRACE 1줄", rc == 0 and b is not None and len(re.findall(r"^GL-GRACE .*옛 번호표\(유예", out, re.M)) == 1, f"rc={rc} {out}")
rc, out = check(OLD, "--coord-only", now=LATE)
ck("⑦″ 유예 밖(25시간) → rc3", rc == 3 and "REJECT" in out and "옛 번호표(유예" not in out, f"rc={rc} {out}")
good = mark.read_text(encoding="utf-8")
mark.write_text(re.sub(r"\nprev\t[0-9a-f]{10}", "\nprev\tzzzzzzzzzz", good), encoding="utf-8")
rc, out = check(OLD, "--coord-only")
ck("⑦″ 표식 prev 손상 → rc3", rc == 3 and "REJECT" in out, f"rc={rc} {out}")
mark.write_text(good, encoding="utf-8")

ck("kit 사본 = bin 사본(ft_goal_table.py)", filecmp.cmp(H / "bin/ft_goal_table.py", H / "kit/fable-team/bin/ft_goal_table.py", shallow=False))
shutil.rmtree(T, ignore_errors=True)
print(f"== test_goal_dispatch_coord_only_r1830: fail={len(FAIL)}")
sys.exit(1 if FAIL else 0)
