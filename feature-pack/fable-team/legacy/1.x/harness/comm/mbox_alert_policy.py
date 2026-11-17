# 도구 알림 표 판정 — mbox.sh send 가 큐에 넣기 «전» 에 부른다(r2167 · 원장 판정 4392).
"""표 = 같은 폴더 alert-policy.tsv(탭 · 머리 줄 1) · 칸 = 발신 · 머리 꼴 · 머리 뒤 첫 낱말 · 갈래 · 값.
  check <to> <from> <body>   : 읽기만. stdout 1줄 = «QUEUE» | «QUEUE\t<현역 이름>»(적재 뒤 record 필요) | «SKIPPED alert-policy …»
  record <from> <holder> <body> : 큐 적재 rc 0 «뒤» 에만 부른다 — state/alert-policy/last.json 의 그 열쇠를 갈아 쓴다.
판정 불가(표 깨짐 · 기록 깨짐 · 현역 이름 풀이 실패 · 예외) = QUEUE + stderr «WARN alert-policy 판정 불가 — <사유>» 1줄.
표 파일 없음 = QUEUE · stderr 0. 열쇠 = 발신 · 머리 꼴 · 받는 좌석 현역 이름(raw «mbox.py holder» · 주소 fallback 0).
"""
import json
import os
import re
import signal
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
KINDS = ("안 넣음", "바뀐 때만", "주기")
HEAD = re.compile(r"\s*(\[[^\]\n]*\])")   # 본문 첫 «[…]»


class Unsure(Exception):
    """판정 불가 — 큐에 넣는다."""


def _now():
    raw = os.environ.get("FT_MBOX_NOW")
    try:
        return float(raw) if raw else time.time()
    except ValueError:
        raise Unsure(f"FT_MBOX_NOW 읽기 실패({raw[:40]})")


def _state():
    return os.path.join(os.environ.get("FT_MBOX_STATE_DIR") or os.path.join(HERE, "..", "state"), "alert-policy")


def _table():
    """→ (행 목록, 깨진 행 번호 목록) · 파일 없음 = None."""
    path = os.path.join(HERE, "alert-policy.tsv")
    if not os.path.lexists(path):
        return None
    try:
        lines = open(path, encoding="utf-8").read().splitlines()
    except (OSError, UnicodeDecodeError) as e:
        raise Unsure(f"표 읽기 실패({type(e).__name__})")
    rows, broken = [], []
    for n, ln in enumerate(lines[1:], 2):
        if not ln.strip():
            continue
        c = ln.split("\t")
        ok = len(c) == 5 and c[0] and c[1] and c[3] in KINDS
        if ok and c[3] == "주기":
            ok = c[4].isdigit() and int(c[4]) > 0
        if ok and c[3] == "바뀐 때만":
            ok = _fp_spec(c[4]) is not None
        (rows if ok else broken).append(c if ok else n)
    if not rows and not broken:
        raise Unsure("표에 행 없음(머리 줄만)")
    return rows, broken


def _fp_spec(v):
    """«전문» | «줄:<시작 글>|글:<꼴 · N=숫자열>|…» → [(종류, 글)] · 못 읽으면 None."""
    if v == "전문":
        return [("전문", "")]
    out = []
    for part in v.split("|"):
        k, _, s = part.partition(":")
        if k not in ("줄", "글") or not s:
            return None
        out.append((k, s))
    return out


def _match(rows, frm, body):
    m = HEAD.match(body)
    if not m:
        return None, ""
    head = re.sub(r"\d+", "N", m.group(1))
    rest = body[m.end():].lstrip()
    for r in rows:
        if r[0] == frm and r[1] == head and (not r[2] or rest.startswith(r[2])):
            return r, head
    return None, head


def _strip(s):   # 시각 · 날짜 · «N분» · «N분째» 를 뺀다
    s = re.sub(r"\d+-\d+-\d+", "", s)
    s = re.sub(r"\d+:\d+(:\d+)?", "", s)
    return re.sub(r"\d+분(째)?", "", s)


def _fingerprint(spec, body):
    if spec[0][0] == "전문":
        return _strip(body)
    got = []
    for k, s in spec:
        if k == "줄":
            got += [ln.strip() for ln in body.splitlines() if ln.strip().startswith(s)]
        else:
            got += re.findall(re.escape(s).replace("N", r"\d+"), body)
    return _strip("\n".join(got))


def _load():
    p = os.path.join(_state(), "last.json")
    if not os.path.lexists(p):
        return {}
    try:
        d = json.load(open(p, encoding="utf-8"))
    except (OSError, ValueError):
        raise Unsure("기록 파일 깨짐")
    if not isinstance(d, dict) or not all(isinstance(v, dict) for v in d.values()):
        raise Unsure("기록 파일 깨짐")
    return d


def _holder(to):
    try:   # send :215 holder_of 와 같은 파일(같은 폴더 mbox.py) · rc · 빈 출력만 본다
        r = subprocess.run([sys.executable, os.path.join(HERE, "mbox.py"), "holder", to], capture_output=True, text=True, timeout=7)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise Unsure(f"받는 좌석 현역 이름 풀이 실패({type(e).__name__})")
    h = r.stdout.strip()
    if r.returncode != 0 or not h:
        raise Unsure(f"받는 좌석 현역 이름 풀이 실패(rc={r.returncode} · 빈 글={not h})")
    return h


def check(to, frm, body):
    t = _table()
    if t is None:
        return "QUEUE"
    rows, broken = t
    if broken:
        print(f"WARN alert-policy 판정 불가 — 깨진 행 {','.join(map(str, broken))}번 줄 — 그 행만 건너뜀", file=sys.stderr)
    row, head = _match(rows, frm, body)
    if row is None:
        return "QUEUE"
    last = _load()
    kind = row[3]
    if kind != "안 넣음":
        hold = _holder(to)
        prev = last.get("\t".join((frm, head, hold)))
        if prev is None:
            return f"QUEUE\t{hold}"
        if kind == "주기":
            if _now() - float(prev.get("ts", 0)) >= int(row[4]) * 60:
                return f"QUEUE\t{hold}"
        elif _fingerprint(_fp_spec(row[4]), body) != prev.get("fp"):
            return f"QUEUE\t{hold}"
    line = f"SKIPPED alert-policy 갈래={kind} from={frm} to={to} head={head}"
    try:
        os.makedirs(_state(), exist_ok=True)
        with open(os.path.join(_state(), "skipped.log"), "a", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(_now())) + "\t" + line + "\n")
    except OSError as e:
        print(f"WARN alert-policy skipped.log 쓰기 실패({type(e).__name__})", file=sys.stderr)
    return line


def record(frm, hold, body):
    t = _table()
    row, head = _match(t[0], frm, body) if t else (None, "")
    if row is None or row[3] == "안 넣음":
        return
    try:
        last = _load()
    except Unsure:
        last = {}   # 깨진 기록은 새 기록으로 갈아 쓴다(판정 불가 WARN 은 check 가 이미 냈다)
    fp = _fingerprint(_fp_spec(row[4]), body) if row[3] == "바뀐 때만" else ""
    last["\t".join((frm, head, hold))] = {"fp": fp, "ts": _now()}
    d = _state()
    os.makedirs(d, exist_ok=True)
    tmp = os.path.join(d, f".last.json.{os.getpid()}")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(last, f, ensure_ascii=False)
    os.replace(tmp, os.path.join(d, "last.json"))


def main(a):
    signal.alarm(7)   # 셸의 timeout 이 없을 때의 상한(7초 룰)
    try:
        if len(a) == 4 and a[0] == "check":
            print(check(a[1], a[2], a[3]))
        elif len(a) == 4 and a[0] == "record":
            record(a[1], a[2], a[3])
        else:
            print("usage: mbox_alert_policy.py check <to> <from> <body> | record <from> <holder> <body>", file=sys.stderr)
            return 2
    except Exception as e:   # Unsure · 쓰기 실패 · 뜻밖의 예외 모두 = 판정 불가(넣는다)
        why = str(e) if isinstance(e, Unsure) else f"{a[0]} 예외({type(e).__name__})"
        print(f"WARN alert-policy 판정 불가 — {why}", file=sys.stderr)
        if a[0] == "check":
            print("QUEUE")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
