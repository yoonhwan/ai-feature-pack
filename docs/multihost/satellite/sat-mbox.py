#!/usr/bin/env python3
"""sat-mbox — 위성(mini) 쪽지함 ↔ 이 맥 쪽지함 얇은 ssh 중계 (2026-10-25 · aifp-multihost-master-claude#4).

골의 어느 축: 오빠 «ft 의 mbox ssh 지원부터» → 위성 나노가 mbox 로 보고·수신 (이슈팀 나노 mini 위성 실험의 선행).
새 키 없음: mini 에는 ssh 키가 없고 이 맥으로 못 온다 → ★이 맥이 먼저 ssh 로 mini 에 가서 가져온다(pull)★.

  push <mini수신자> <발신자> <본문>   이 맥 → mini : mini 의 ft-mbox send (본문은 base64 로 넘겨 인용 사고 0)
  pull [--seats A,B]                 mini → 이 맥 : mini 쪽지함에서 to ∈ seats 인 행을 «읽기만» → 이 맥 ft-mbox send →
                                      ack(mini 에서 그 seq 삭제). 이 맥 delivered 장부로 중복 0(at-least-once + dedupe).
  status                             mini 쪽지함 대기 건수

잠금·형식은 mini 의 ft-mbox.py 를 그대로 import 해서 쓴다(복제 0). 원격 쓰기는 mini 쪽지함 파일뿐.
"""
import base64, json, os, subprocess, sys

MINI = os.environ.get("MINI", "mini")
MINI_DIR = os.environ.get("SAT_MINI_MBOX_DIR", "$HOME/.fable-team/comm")
MINI_PY = "$HOME/.claude/skills/fable-team/scripts/ft-mbox.py"
MAC_SH = os.path.expanduser("~/.claude/skills/fable-team/scripts/ft-mbox.sh")
MAC_DIR = os.environ.get("FT_MBOX_DIR", "/Users/yoonhwan/Project/ai-feature-pack/.fable-team/comm")
STATE = os.environ.get("SAT_STATE", "/Users/yoonhwan/Project/ai-feature-pack/.fable-team/sat/delivered-mini.json")
SSH = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=6", "-o", "ServerAliveInterval=10", MINI]
PRE = "export PATH=/opt/homebrew/bin:$HOME/.local/bin:$PATH; export FT_MBOX_DIR=" + MINI_DIR + "; mkdir -p \"$FT_MBOX_DIR\"; "


def mini(cmd, stdin=None, t=25):
    r = subprocess.run(SSH + [PRE + cmd], input=stdin, capture_output=True, text=True, timeout=t)
    return r.returncode, r.stdout, r.stderr


# mini 에서 실행되는 조각 — ft-mbox.py 를 모듈로 불러 같은 잠금으로 읽기/삭제
LOAD = (
    "import importlib.util,json,os,sys;"
    "s=importlib.util.spec_from_file_location('m',os.path.expandvars('" + MINI_PY + "'));"
    "m=importlib.util.module_from_spec(s);s.loader.exec_module(m);"
)
READ_PY = LOAD + (
    "seats=set(sys.argv[1].split(','));"
    "rows=m._locked(m.CANON,lambda:[r for r in m._load(m.CANON) if r.get('to') in seats]);"
    "print(json.dumps(rows,ensure_ascii=False))"
)
ACK_PY = LOAD + (
    "seqs=set(json.loads(sys.argv[1]))\n"
    "def op():\n"
    "  rows=m._load(m.CANON);keep=[r for r in rows if r.get('seq') not in seqs]\n"
    "  if len(keep)!=len(rows): m._save(m.CANON,keep)\n"
    "  print(len(rows)-len(keep))\n"
    "m._locked(m.CANON,op)"
)


def load_state():
    try:
        return set(json.load(open(STATE)))
    except Exception:
        return set()


def save_state(s):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    tmp = STATE + ".tmp"
    json.dump(sorted(s)[-2000:], open(tmp, "w"))
    os.replace(tmp, STATE)


def push(to, frm, body):
    b64 = base64.b64encode(body.encode()).decode()
    cmd = ("B=$(printf %s '" + b64 + "' | base64 -d); "
           "bash $HOME/.claude/skills/fable-team/scripts/ft-mbox.sh send '" + to + "' '" + frm + "' \"$B\" 2>&1 | tail -2")
    rc, out, err = mini(cmd)
    print(out.strip() or err.strip())
    return rc


def pull(seats):
    # 파이썬 조각은 stdin 으로 넘겨(`python3 -c "$(cat)"`) 인용 사고 0
    r = subprocess.run(SSH + [PRE + "python3 -c \"$(cat)\" '" + ",".join(seats) + "'"], input=READ_PY,
                       capture_output=True, text=True, timeout=25)
    if r.returncode != 0:
        print("PULL_FAIL read rc=%s %s" % (r.returncode, r.stderr.strip()[:200])); return 2
    rows = json.loads(r.stdout.strip() or "[]")
    done = load_state()
    ok = []
    for row in rows:
        key = "mini:%s:%s" % (row.get("seq"), row.get("ts"))
        if key not in done:
            env = dict(os.environ, FT_MBOX_DIR=MAC_DIR)
            p = subprocess.run(["bash", MAC_SH, "send", row["to"], row["from"], row["body"]],
                               capture_output=True, text=True, env=env, timeout=30)
            if "QUEUED" not in p.stdout:
                print("DELIVER_FAIL seq=%s %s" % (row.get("seq"), (p.stdout + p.stderr).strip()[-200:])); continue
            done.add(key); save_state(done)
        ok.append(row["seq"])
    if ok:
        a = subprocess.run(SSH + [PRE + "python3 -c \"$(cat)\" '" + json.dumps(ok) + "'"], input=ACK_PY,
                           capture_output=True, text=True, timeout=25)
        if a.returncode != 0:
            print("ACK_FAIL rc=%s %s (다음 pull 에서 중복 없이 재시도)" % (a.returncode, a.stderr.strip()[:200])); return 3
    print("PULL ok delivered=%d seen=%d" % (len(ok), len(rows)))
    return 0


def status():
    r = subprocess.run(SSH + [PRE + "python3 -c \"$(cat)\" ''"], input=LOAD + "rows=m._locked(m.CANON,lambda:m._load(m.CANON));print(len(rows))",
                       capture_output=True, text=True, timeout=25)
    print("mini_pending=" + r.stdout.strip() if r.returncode == 0 else "STATUS_FAIL " + r.stderr.strip()[:200])
    return r.returncode


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["push"] and len(a) >= 4:
        sys.exit(push(a[1], a[2], " ".join(a[3:])))
    if a[:1] == ["pull"]:
        seats = (a[a.index("--seats") + 1] if "--seats" in a else "aifp-multihost-master-claude#4").split(",")
        sys.exit(pull(seats))
    if a[:1] == ["status"]:
        sys.exit(status())
    sys.exit("usage: sat-mbox.py push <to> <from> <body> | pull [--seats A,B] | status")
