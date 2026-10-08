"""ft_inbox_core.py — ft-inbox.py 의 공용부: 경로·큐 입출력·정본 술어 obligation_closed·묶기·분류·Haiku 일회 호출."""
import fcntl
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
from contextlib import contextmanager
from typing import NoReturn

CLS = ["①", "②", "③", "④", "⑤", "⑥"]
PRIO = {"①": 1.0, "미상": 1.5, "②": 2.0, "③": 3.0, "④": 4.0, "⑤": 5.0, "⑥": 6.0}
MUST_REPORT = {"①", "②", "③", "④", "미상"}  # 미상도 ring 은 1~4 급 — 보고 의무를 6 급으로 강등하지 않는다
# 고정 기준표 — 순서만 바꾸고 빼지 않는다. 위에서부터 첫 일치.
RULES = [
    ("①", r"오빠 원문|^\[원문\]"),
    ("②", r"\[HIL\]|파괴 승인"),
    ("③", r"판정 요청|\[판정요청\]"),
    ("④", r"\[BLOCK\]|막힘"),
    ("⑤", r"판정 ?\d+ ?(집행|완료)|PR #?\d+ ?병합|병합 완료|닫힘"),
    ("⑥", r"^\[부팅 보고|진행 보고|참고|접수"),
]


def die(msg, rc=1) -> NoReturn:
    print(f"REJECT {msg}", file=sys.stderr)
    sys.exit(rc)


def root():
    r = os.environ.get("FT_ROOT")
    if not r:
        out = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
                             capture_output=True, text=True).stdout.strip()
        r = re.sub(r"/\.git$", "", out)
    return r


R = root()
COMM = f"{R}/.fable-team/comm"
INBOX = f"{R}/.fable-team/state/inbox"
HOOK_ERRORS = f"{R}/.fable-team/state/hook-errors.log"


def lineage(name):
    return name.split("#")[0]


def qpath(seat):
    return f"{INBOX}/{lineage(seat)}.jsonl"


@contextmanager
def locked(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".lock", "w") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        yield


def read_q(path):
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        return [json.loads(x) for x in f if x.strip()]


def write_q(path, rows):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.writelines(json.dumps(x, ensure_ascii=False) + "\n" for x in rows)
    os.replace(tmp, path)


def obligation_closed(line):
    """정본 술어(설계 §8) — show·archive·묶음이 이 함수 하나만 호출한다."""
    return line["mark"] is not None and (line["cls"] not in MUST_REPORT or line["reported"] is True)


def group_closed(rows, gid):
    return all(obligation_closed(x) for x in rows if x["group"] == gid)


def find_mail(seq):
    for fn in ("mailbox.jsonl", "mailbox.log.jsonl"):
        p = f"{COMM}/{fn}"
        if not os.path.exists(p):
            continue
        with open(p, encoding="utf-8") as f:
            for ln in f:
                row = json.loads(ln) if ln.strip() else {}
                if row.get("seq") == seq:
                    return row
    return None


def norm_key(frm, body):
    b = re.sub(r"^(\[[^\]]*\]\s*)+", "", body)
    b = re.sub(r"\[발주 #\d+\]|seq=\d+|\d{4}-\d{2}-\d{2}T?|\d{2}:\d{2}(:\d{2})?", "", b)
    return "g-" + hashlib.sha1((frm + "|" + re.sub(r"\s+", " ", b).strip()).encode()).hexdigest()[:10]


def haiku(prompt):
    cmd = shlex.split(os.environ.get("FT_INBOX_HAIKU") or "claude -p --model claude-haiku-5-5")
    t = float(os.environ.get("FT_INBOX_HAIKU_TIMEOUT", "20"))
    p = subprocess.run(cmd, input=prompt, capture_output=True, text=True, timeout=t)
    if p.returncode != 0 or not p.stdout.strip():
        raise RuntimeError(f"haiku rc={p.returncode} {p.stderr.strip()[:120]}")
    return p.stdout.strip()


def rule_class(body):
    """고정 기준표만(즉시·동기). 안 맞으면 '미상' — Haiku 라벨은 haiku_class 가 나중에(비동기) 붙인다."""
    first = re.sub(r"^(\[[^\]]*->[^\]]*\]\s*)", "", body)
    for cls, pat in RULES:
        if re.search(pat, first, re.M):
            return cls
    return "미상"


def haiku_class(body):
    """Haiku 일회 호출로 라벨만. 실패·해석 불가는 raise (호출자가 미상 유지 + 오류 로그)."""
    out = haiku("쪽지를 ①오빠 원문 ②[HIL]·파괴 승인 ③판정 요청 ④막힘 ⑤결과 ⑥진행·참고 중 하나로만 분류해 번호 한 글자로 답하라.\n본문:\n" + body[:1500])
    m = re.search(r"[①-⑥]|[1-6]", out)
    if not m:
        raise RuntimeError(f"라벨 해석 불가: {out[:60]}")
    return CLS["123456".index(m.group())] if m.group() in "123456" else m.group()
