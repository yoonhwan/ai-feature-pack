#!/usr/bin/env python3
"""sat-mbox — 위성(mini) 쪽지함 ↔ 이 맥 쪽지함 얇은 ssh 중계 (원본: aifp-multihost #166xxx · r955 이식).

골의 어느 축: 사용자 접수 → mini → 이 맥 pull(②) 과 이 맥 → mini push(⑧⑨) 의 «한 다리».
새 키 없음: mini 에는 ssh 키가 없고 이 맥으로 못 온다 → ★이 맥이 먼저 ssh 로 mini 에 가서 가져온다(pull)★.

  push <mini수신자> <발신자> <본문>      이 맥 → mini : mini 의 ft-mbox send (본문은 base64 — 인용 사고 0)
  pull [--seats A,B | --seats-file F]    mini → 이 맥 : to ∈ 좌석 인 행만 «읽기만» → 이 맥 ft-mbox send → ack(삭제)
  status                                mini 쪽지함 대기 건수
  scp-card <mini경로> <결과폴더>         접수 카드 1장만 결과 폴더로 복사(그 폴더 밖 0)

이식에서 바꾼 것(원본 대비 · aifp #170038 조건):
  · 내부 절대경로 기본값 제거 — 이 맥 쪽지함·장부 경로는 env(FT_MBOX_DIR · SAT_STATE) 필수, 없으면 리포 루트 추정
  · ssh 대상·hostname = 인자/환경변수(MINI · SAT_SSH 로 argv 통째 교체 가능 — 시험용)
  · 쪽지함 큐 ≥10 이면 보내지 않고 로그 1줄(조용한 버림 0 · 기획 §6)
  · 좌석 목록 파일(--seats-file · 기본 $SAT_SEATS_FILE) 1개를 pull 데몬 1개가 읽는다(r955 겹침 대조)

rc: 0 정상 · 2 usage/설정 · 3 read/ack 실패 · 4 전달 실패 · 5 큐 상한으로 보류
"""
import base64
import json
import os
import subprocess
import sys

CALL_TIMEOUT = 7  # 하드 룰 12 — 외부 호출 1회 7초. 넘으면 실패(기다리지 않는다)
MINI = os.environ.get("MINI", "mini")
MINI_DIR = os.environ.get("SAT_MINI_MBOX_DIR", "$HOME/.fable-team/comm")
MINI_PY = os.environ.get("SAT_MINI_PY", "$HOME/.claude/skills/fable-team/scripts/ft-mbox.py")
QUEUE_CAP = int(os.environ.get("SAT_QUEUE_CAP", "10"))


def repo_root() -> str:
    """git 리포 루트 추정 — 절대경로 기본값을 코드에 박지 않기 위한 것(env 우선)."""
    r = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, timeout=7)
    return r.stdout.strip() if r.returncode == 0 else ""


def setting(env: str, sub_path: str) -> str:
    val = os.environ.get(env, "")
    if val:
        return val
    root = repo_root()
    if not root:
        sys.exit(f"STOP {env} 미설정 · 리포 루트 추정 실패 — 설정 없이 돌지 않는다")
    return os.path.join(root, sub_path)


MAC_SH = os.environ.get("FT_MBOX_SH", "") or os.path.expanduser("~/.claude/skills/fable-team/scripts/ft-mbox.sh")
MAC_DIR = setting("FT_MBOX_DIR", ".fable-team/comm")
STATE = setting("SAT_STATE", ".fable-team/sat/delivered-mini.json")
SSH = os.environ.get("SAT_SSH", "").split() or ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=6", "-o", "ServerAliveInterval=10", MINI]
PRE = "export PATH=/opt/homebrew/bin:$HOME/.local/bin:$PATH; export FT_MBOX_DIR=" + MINI_DIR + "; mkdir -p \"$FT_MBOX_DIR\"; "


def mini(cmd, stdin=None, t=CALL_TIMEOUT):
    try:
        r = subprocess.run(SSH + [PRE + cmd], input=stdin, capture_output=True, text=True, timeout=t)
    except subprocess.TimeoutExpired:
        return 7, "", "7초 초과(ssh)"
    return r.returncode, r.stdout, r.stderr


def remote(py_code, arg, step):
    """원격 파이썬 조각 1회 — argv 인용 사고 0, 7초 상한."""
    try:
        r = subprocess.run(SSH + [PRE + "python3 -c \"$(cat)\" '" + arg + "'"], input=py_code,
                           capture_output=True, text=True, timeout=CALL_TIMEOUT)
    except subprocess.TimeoutExpired:
        return 7, "", "7초 초과(%s)" % step
    return r.returncode, r.stdout, r.stderr


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
    os.makedirs(os.path.dirname(STATE) or ".", exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(sorted(s)[-2000:], f)
    os.replace(tmp, STATE)


def queue_len() -> int:
    """이 맥 쪽지함의 대기 건수 — 상한을 넘으면 보내지 않는다(쌓아 두면 늦게라도 간다)."""
    path = os.path.join(MAC_DIR, "mailbox.jsonl")
    try:
        with open(path, encoding="utf-8") as f:
            return sum(1 for ln in f if ln.strip())
    except OSError:
        return 0


def push(to, frm, body):
    b64 = base64.b64encode(body.encode()).decode()
    cmd = ("B=$(printf %s '" + b64 + "' | base64 -d); "
           "bash $HOME/.claude/skills/fable-team/scripts/ft-mbox.sh send '" + to + "' '" + frm + "' \"$B\" 2>&1 | tail -2")
    rc, out, err = mini(cmd)
    print(out.strip() or err.strip())
    return rc


def pull(seats):
    rc, out, err = remote(READ_PY, ",".join(seats), "read")
    if rc != 0:
        print("PULL_FAIL read rc=%s %s" % (rc, err.strip()[:200]))
        return 3
    rows = json.loads(out.strip() or "[]")
    done, ok = load_state(), []
    held = 0
    for idx, row in enumerate(rows):
        q = queue_len()  # ★쪽지 1건마다 다시 센다★ — 패스 시작에 한 번 재면 그 사이 늘어난 큐를 놓친다
        if q >= QUEUE_CAP:
            held = len(rows) - idx
            print("HOLD queue=%d remaining=%d — 이번 패스는 여기서 멈춘다(원격 ack 0 · 버리지 않음)" % (q, held))
            break
        key = "mini:%s:%s" % (row.get("seq"), row.get("ts"))
        if key not in done:
            env = dict(os.environ, FT_MBOX_DIR=MAC_DIR)
            try:
                p = subprocess.run(["bash", MAC_SH, "send", row["to"], row["from"], row["body"]],
                                   capture_output=True, text=True, env=env, timeout=CALL_TIMEOUT)
            except subprocess.TimeoutExpired:
                print("DELIVER_FAIL seq=%s 7초 초과(전달)" % row.get("seq"))
                continue
            if "QUEUED" not in p.stdout:
                print("DELIVER_FAIL seq=%s %s" % (row.get("seq"), (p.stdout + p.stderr).strip()[-200:]))
                continue
            done.add(key)
            save_state(done)
        ok.append(row["seq"])
    if ok:
        arc, _aout, aerr = remote(ACK_PY, json.dumps(ok), "ack")
        if arc != 0:
            print("ACK_FAIL rc=%s %s (다음 pull 에서 중복 없이 재시도)" % (arc, aerr.strip()[:200]))
            return 3
    print("PULL ok delivered=%d seen=%d held=%d" % (len(ok), len(rows), held))
    return 5 if held else 0


def seats_of(a):
    if "--seats-file" in a:
        path = a[a.index("--seats-file") + 1]
    else:
        path = os.environ.get("SAT_SEATS_FILE", "")
    if path:
        try:
            names = [ln.strip() for ln in open(os.path.expanduser(path), encoding="utf-8") if ln.strip() and not ln.startswith("#")]
        except OSError as e:
            print("STOP 좌석 목록 파일 읽기 실패: %s (%s)" % (path, type(e).__name__))
            return None
        return names or None
    return (a[a.index("--seats") + 1] if "--seats" in a else "").split(",") if "--seats" in a else None


def scp_card(remote, out_dir):
    """접수 카드 1장만 결과 폴더로 — 그 폴더 밖에는 쓰지 않는다."""
    os.makedirs(out_dir, exist_ok=True)
    name = os.path.basename(remote)
    rc, out, err = mini("cat " + remote)
    if rc != 0:
        print("SCP_FAIL %s %s" % (name, err.strip()[:160]))
        return 4
    with open(os.path.join(out_dir, name), "w", encoding="utf-8") as f:
        f.write(out)
    print("SCP ok %s -> %s" % (name, out_dir))
    return 0


def status():
    rc, out, err = remote(LOAD + "rows=m._locked(m.CANON,lambda:m._load(m.CANON));print(len(rows))", "", "status")
    print("mini_pending=" + out.strip() if rc == 0 else "STATUS_FAIL " + err.strip()[:200])
    return rc


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["push"] and len(a) >= 4:
        sys.exit(push(a[1], a[2], " ".join(a[3:])))
    if a[:1] == ["pull"]:
        seats = seats_of(a)
        if not seats:
            print("STOP 좌석 목록 없음 — --seats / --seats-file / SAT_SEATS_FILE 중 하나가 필요하다", file=sys.stderr)
            sys.exit(2)
        sys.exit(pull(seats))
    if a[:1] == ["scp-card"] and len(a) >= 3:
        sys.exit(scp_card(a[1], a[2]))
    if a[:1] == ["status"]:
        sys.exit(status())
    print("usage: sat-mbox.py push <to> <from> <body> | pull [--seats A,B | --seats-file F] | scp-card <mini경로> <결과폴더> | status", file=sys.stderr)
    sys.exit(2)
