#!/usr/bin/env python3
"""r1945 — 골 재조정 멈춤 요청(A)·판정 1줄 강제(B)·머리 «판정 빠짐 N행»(C). 반례 ①~⑦(카드 동결).
격리: 임시 루트(state·명부) · 가짜 mbox(인자 기록만) · 임시 git 원장 · measure 는 가짜 회차 dict · 실 우편함 0 · sleep 0.
변이용: env R1945_SRC = 다른 harness 폴더(bin 을 거기서 부른다)."""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

H = Path(os.environ.get("R1945_SRC") or Path(__file__).resolve().parent.parent)
T, FAIL = Path(tempfile.mkdtemp()), []
PM = "byz-planner-master-claude#9"
MBOX = T / "mbox.sh"
MBOX.write_text('#!/bin/sh\nprintf "SEND to=%s from=%s\\n%s\\n---END---\\n" "$2" "$3" "$4" >> "$MBOX_LOG"\necho "seq=7"\n')
MBOX.chmod(0o755)
LEDGER = T / "ledger"
subprocess.run(["git", "init", "-q", str(LEDGER)], check=True)
DRIVER = """
import json, sys
sys.path.insert(0, sys.argv[1] + "/bin")
import ft_goal_readjust as gr
row = json.loads(sys.argv[2])
commit = __import__("subprocess").run(["git", "-C", sys.argv[3], "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
def fake(d, now, run):
    return {"run": run, "attempt": 0, "started": now.strftime("%Y-%m-%d %H:%M:%S"), "status": "OK", "error": "",
            "inputs": {"repos": {"byz": {"ref": "origin/main", "commit": commit}}}, "rows": [row["row"]],
            "facts": {"close_candidates": row["close"], "goal_files_outside_canon": [], "unassigned_cards": [], "stale_numbered_cards": [],
                      "open_cards": {}, "broken_links": [], "unknown": []}, "alarms": [], "baseline": None, "baseline_reason": "",
            "send": {"state": "none", "key": "GR-" + run}}
gr.measure = fake
sys.exit(gr.collect(request="r1945 시험"))
"""


def ck(name, cond, info=""):
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else f" :: {str(info)[:400]}"))
    FAIL.extend([] if cond else [name])


def root(name):
    r = T / name
    (r / ".fable-team/state/goal-readjust/rounds").mkdir(parents=True)
    (r / ".fable-team/seats-planner.json").write_text(json.dumps({"_master": PM}), encoding="utf-8")
    return r


def env(r, now):
    return dict(os.environ, FT_ROOT=str(r), FT_NOW=now, FT_MBOX=str(MBOX), MBOX_LOG=str(r / "mbox.log"),
                FT_GOAL_REPO=str(LEDGER), FT_GOAL_VERDICTS="gitref:HEAD:VERDICTS.md")


def rnd(r, name, data):
    (r / ".fable-team/state/goal-readjust/rounds" / name).write_text(data if isinstance(data, str) else json.dumps(data), encoding="utf-8")


def alert(r, now, *a):
    p = subprocess.run([sys.executable, str(H / "bin/ft_goal_stall_alert.py"), *a], env=env(r, now), capture_output=True, text=True, timeout=30)
    return p.returncode, p.stdout + p.stderr


def mlog(r):
    log = r / "mbox.log"
    return log.read_text(encoding="utf-8") if log.exists() else ""


def sends(r):
    return mlog(r).count("SEND to=")


def ledger(*lines):
    text = "| 번호 | 시각 | 내용 | 판정자 | 근거 |\n|---|---|---|---|---|\n" + "".join(f"{x}\n" for x in lines)
    (LEDGER / "VERDICTS.md").write_text(text, encoding="utf-8")
    subprocess.run(["git", "-C", str(LEDGER), "add", "-A"], check=True)
    subprocess.run(["git", "-C", str(LEDGER), "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "v", "--allow-empty"], check=True)


def collect(r, now, label="변화 0(30시간)", close=(), age=30):
    row = {"n": 4, "goal12": "하네스 운영", "goal_hash": "h", "team": "harness", "label": label, "cards_added": 0, "evidence": "-",
           "ledger_row_changed": False, "row_age_h": age, "unknown": []}
    p = subprocess.run([sys.executable, "-c", DRIVER, str(H), json.dumps({"row": row, "close": list(close)}), str(LEDGER)],
                       env=env(r, now), capture_output=True, text=True, timeout=60)
    files = sorted(x for x in (r / ".fable-team/state/goal-readjust/rounds").glob("*.json") if not x.name.endswith(("sent.json", "failed.json")))
    return p.returncode, json.loads(files[-1].read_text(encoding="utf-8")) if files else {}, p.stdout + p.stderr


def header(r, now):
    code = f"import sys; sys.path.insert(0, '{H}/bin'); import ft_goal_readjust_state as s; print(s.header(s.read()))"
    return subprocess.run([sys.executable, "-c", code], env=env(r, now), capture_output=True, text=True, timeout=30).stdout


OK0 = {"run": "20261111-1", "attempt": 1, "status": "OK", "finished": "2026-11-11 16:01:00", "rows": []}

# ① 26시간 안 0 · 69시간 1통 · 같은 회차 키 0 · 새 OK 회차 = 키 바뀜
r = root("a1")
rnd(r, "20261111-1-01.json", OK0)
alert(r, "2026-11-12 10:00")
ck("①26시간 안 = 쪽지 0", sends(r) == 0)
rc, out = alert(r, "2026-11-14 13:01")
body = mlog(r)
ck("①69시간 = planner 1통", sends(r) == 1 and f"to={PM}" in body, out)
ck("①첫 줄 [결정] 재조정 없음 69시간 · 회차 요청 명령", "[결정] 골 재조정 없음 69시간" in body and "ft-goal-readjust.sh --request" in body, body)
alert(r, "2026-11-14 13:03")
ck("①같은 회차 다시 = 0(M1)", sends(r) == 1)
rnd(r, "20261114-1-01.json", {**OK0, "run": "20261114-1", "finished": "2026-11-14 13:00:00"})
alert(r, "2026-11-15 16:00")
ck("①새 OK 회차 = 키 바뀜 1통", sends(r) == 2)

# ⑥ --dry-run 쪽지 0 · 키 안 씀
r = root("a6")
rnd(r, "20261111-1-01.json", OK0)
rc, out = alert(r, "2026-11-14 13:01", "--dry-run")
ck("⑥--dry-run = 쪽지 0", sends(r) == 0 and "[결정]" in out, out)
alert(r, "2026-11-14 13:02")
ck("⑥dry-run 뒤 실제 = 1통", sends(r) == 1)

# ⑤ 엄격 읽기: 이름순 최신 회차 파일만 깨짐 + 앞에 69시간 전 OK → 쪽지 0 · 로그 1줄
r = root("a5")
rnd(r, "20261111-1-01.json", OK0)
rnd(r, "20261114-1-01.json", "{깨짐")
rc, out = alert(r, "2026-11-14 13:01")
log = r / ".fable-team/state/goal-stall-alert.log"
ck("⑤최신 깨짐 = 쪽지 0(M3)", sends(r) == 0, out)
ck("⑤로그 1줄 판정 불가", log.exists() and len(log.read_text(encoding="utf-8").splitlines()) == 1 and "판정 불가" in log.read_text(encoding="utf-8"))

# ② 변화 0(30시간) + 판정 줄 0 → 판정 빠짐 · 머리 · 같은 쪽지 묶음 · 판정 줄 뒤 재시도 OK
ledger()
r = root("b2")
rc, rec, out = collect(r, "2026-11-14 13:00")
ck("②판정 빠짐 1행(M2)", rec.get("status") == "판정 빠짐" and rec.get("verdict_missing") == [4] and rc != 0, (rc, rec.get("status"), out))
ck("②머리 «판정 빠짐 1행»", "판정 빠짐 1행" in header(r, "2026-11-14 13:00"), header(r, "2026-11-14 13:00"))
rnd(r, "20261111-1-01.json", OK0)
(r / "mbox.log").unlink(missing_ok=True)
alert(r, "2026-11-14 13:01")
ck("②A 쪽지에 판정 빠짐 1줄 묶음", "판정 빠짐 1행" in mlog(r), mlog(r))
ledger("| 4200 | 11-14 13:05 | 골 4행 유지(r1945 진행 중) | planner | t |")
rc, rec, out = collect(r, "2026-11-14 13:10")
ck("②판정 줄 뒤 재시도 = OK · 같은 run", rc == 0 and rec.get("status") == "OK" and rec.get("run") == "20261114-1", (rc, rec.get("status"), out))

# ③ close_candidates 행 + 판정 줄 0 → 판정 빠짐
ledger()
r = root("b3")
rc, rec, out = collect(r, "2026-11-14 13:00", label="움직임", close=[4], age=1)
ck("③닫기 후보 판정 빠짐", rec.get("status") == "판정 빠짐" and rec.get("verdict_missing") == [4], (rec.get("status"), out))

# ④ 옛 판정(고정 시각보다 앞) = 빠짐
ledger("| 4190 | 11-14 12:50 | 골 4행 재조정 | planner | t |")
r = root("b4")
rc, rec, out = collect(r, "2026-11-14 13:00")
ck("④옛 판정 = 빠짐", rec.get("status") == "판정 빠짐", (rec.get("status"), out))

# ⑦ 13:00 빠짐 → 13:01 판정 → 13:02 재시도 OK · run 그대로
ledger()
r = root("b7")
collect(r, "2026-11-14 13:00")
ledger("| 4201 | 11-14 13:01 | 골 4행 닫기 | planner | t |")
rc, rec, out = collect(r, "2026-11-14 13:02")
ck("⑦고정 시각 기준 = OK · run 그대로(M4)", rec.get("status") == "OK" and rec.get("run") == "20261114-1" and rec.get("attempt") == 2, (rec.get("status"), out))

# ⑤ 원장 판독 실패 → 판정 불가 · 쪽지 0 · 로그 1줄
r = root("b5")
e = env(r, "2026-11-14 13:00")
row = {"n": 4, "goal12": "g", "goal_hash": "h", "team": "harness", "label": "변화 0(30시간)", "cards_added": 0, "evidence": "-",
       "ledger_row_changed": False, "row_age_h": 30, "unknown": []}
p = subprocess.run([sys.executable, "-c", DRIVER, str(H), json.dumps({"row": row, "close": []}), str(LEDGER)],
                   env={**e, "FT_GOAL_VERDICTS": "gitref:HEAD:없는원장.md"}, capture_output=True, text=True, timeout=60)
rec = json.loads(sorted((r / ".fable-team/state/goal-readjust/rounds").glob("*-01.json"))[0].read_text(encoding="utf-8"))
glog = (r / ".fable-team/state/goal-readjust/goal-readjust.log").read_text(encoding="utf-8")
ck("⑤원장 판독 실패 = 판정 불가 · 쪽지 0", rec.get("status") == "판정 불가" and sends(r) == 0, (rec.get("status"), p.stdout + p.stderr))
ck("⑤로그 1줄", sum("판정 불가" in x for x in glog.splitlines()) == 1, glog)

print(f"요약 {'FAIL ' + ','.join(FAIL) if FAIL else 'PASS'}")
sys.exit(1 if FAIL else 0)
