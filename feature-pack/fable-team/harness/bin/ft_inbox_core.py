"""ft_inbox_core.py — ft-inbox.py 의 공용부: 경로·큐 입출력·정본 술어 obligation_closed·묶기·분류·Haiku 일회 호출."""
import fcntl
import glob
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
    # 10-10 미상→Haiku 상위 머리말(R57) — 새 줄은 \A(본문 첫머리만): re.M 의 ^ 는 본문 중간 줄 머리에도 걸린다.
    ("⑤", r"\A\[완료·휴식"),
    ("⑥", r"\A\[?(부팅|첫 보고|승계|발주)"),
    ("②", r"\A\[HIL"),
    ("⑤", r"\A\[Issue 등록\]"),
]


def die(msg, rc=1) -> NoReturn:
    print(f"REJECT {msg}", file=sys.stderr)
    sys.exit(rc)


def root():
    r = os.environ.get("FT_ROOT")
    if not r:
        p = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
                           capture_output=True, text=True)
        r = re.sub(r"/\.git$", "", p.stdout.strip()) if p.returncode == 0 else ""
    if not r:  # 빈 루트로 «/.fable-team/comm» 을 읽으면 «쪽지 없음» 으로 둔갑한다 — 루트를 못 정했다고 말한다
        die(f"루트를 못 정함 — FT_ROOT 가 없고 cwd({os.getcwd()})가 git 저장소 밖 · FT_ROOT=<리포 루트> 를 주거나 저장소 안에서 부를 것")
    return r


R = root()
COMM = f"{R}/.fable-team/comm"
INBOX = f"{R}/.fable-team/state/inbox"
HOOK_ERRORS = f"{R}/.fable-team/state/hook-errors.log"


def lineage(name):
    return name.split("#")[0]


def qpath(seat):
    return f"{INBOX}/{lineage(seat)}.jsonl"


def tmux_session():
    """tmux 안이면 현재 세션 이름(= 좌석 이름). 밖이거나 못 읽으면 빈 문자열."""
    pane = os.environ.get("TMUX_PANE")
    if not pane:
        return ""
    try:
        return subprocess.run(["tmux", "display-message", "-p", "-t", pane, "#{session_name}"],
                              capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def take_seat(a):
    """인자에서 --seat <이름> 을 떼어 (좌석, 나머지). 없으면 FT_SEAT → tmux 세션 이름 · 전부 없으면 usage rc 2 (추측 0)."""
    a, seat = list(a), os.environ.get("FT_SEAT", "")
    if "--seat" in a:
        i = a.index("--seat")
        seat = "".join(a[i + 1:i + 2])
        del a[i:i + 2]
    elif not seat:
        seat = tmux_session()
    return seat or die("mark·report 는 호출 좌석이 필요하다 — --seat <좌석> 또는 FT_SEAT (추측 0)", 2), a


def hits(qp, targets):
    """큐 한 개에서 대상(seq 또는 group)별 seq 집합."""
    return {t: {x["seq"] for x in read_q(qp) if t in (x["group"], str(x["seq"]))} for t in targets}


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
    """정본 술어(설계 §8) — show·archive·묶음이 이 함수 하나만 호출한다. 판정 558 ④ · 명시 면제(waived)도 닫힘."""
    return line["mark"] is not None and (line["cls"] not in MUST_REPORT or line["reported"] is True
                                         or line.get("waived") is not None)


def group_closed(rows, gid):
    return all(obligation_closed(x) for x in rows if x["group"] == gid)


def mail_files():
    """쪽지를 찾는 파일 — 현행 → 로그 → 회전본(.1 .2 …, 숫자 순). 실재하는 것만."""
    rot = sorted((p for p in glob.glob(f"{COMM}/mailbox.log.jsonl.*") if p.rsplit(".", 1)[1].isdigit()),
                 key=lambda p: int(p.rsplit(".", 1)[1]))
    return [p for p in (f"{COMM}/mailbox.jsonl", f"{COMM}/mailbox.log.jsonl", *rot) if os.path.exists(p)]


def find_seq(seq):
    """mail_files() 순서로 첫 1건 → (파일 경로, 쪽지 행). 없으면 (None, None). 글자 선거름 뒤에만 json 해석(5MB ≤1초 · r430)."""
    key = f'"seq": {seq}'
    for p in mail_files():
        with open(p, encoding="utf-8") as f:
            for ln in f:
                if key in ln and json.loads(ln).get("seq") == seq:
                    return p, json.loads(ln)
    return None, None


def find_mail(seq):
    return find_seq(seq)[1]


def norm_key(frm, body):
    b = re.sub(r"^(\[[^\]]*\]\s*)+", "", body)
    b = re.sub(r"\[발주 #\d+\]|seq=\d+|\d{4}-\d{2}-\d{2}T?|\d{2}:\d{2}(:\d{2})?", "", b)
    return "g-" + hashlib.sha1((frm + "|" + re.sub(r"\s+", " ", b).strip()).encode()).hexdigest()[:10]


def haiku(prompt):
    cmd = shlex.split(os.environ.get("FT_INBOX_HAIKU") or "claude -p --model claude-haiku-5-5")
    t = float(os.environ.get("FT_INBOX_HAIKU_TIMEOUT", "7"))  # 외부 호출 7초 룰(전역 하드 룰 12) + 재시도 1회
    err = ""
    for _ in range(2):
        try:
            p = subprocess.run(cmd, input=prompt, capture_output=True, text=True, timeout=t)
        except subprocess.TimeoutExpired:
            err = f"timeout {t:g}s"
            continue
        if p.returncode == 0 and p.stdout.strip():
            return p.stdout.strip()
        err = f"rc={p.returncode} stderr={p.stderr.strip()[:120]} stdout={p.stdout.strip()[:120]}"
    raise RuntimeError(f"haiku {err}")


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
