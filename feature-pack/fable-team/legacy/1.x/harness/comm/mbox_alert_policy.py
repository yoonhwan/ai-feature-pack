# 도구 알림 표 판정 — mbox.sh send 가 큐에 넣기 «전» 에 부른다(r2167 · 원장 판정 4392).
"""표 = 같은 폴더 alert-policy.tsv(탭 · 머리 줄 1) · 칸 = 발신 · 머리 꼴 · 머리 뒤 첫 낱말 · 갈래 · 값.
  check <to> <from> <body>   : 읽기만. stdout 1줄 = «QUEUE» | «QUEUE\t<현역 이름>\t<wake_at>»(적재 뒤 record 필요 · 빈 칸 가능 · r2169) | «SKIPPED alert-policy …»
  record <from> <holder> <body> [<to> <seq> <wake_at>] : 큐 적재 rc 0 «뒤» 에만 부른다 — last.json · first.json(r2169 첫 통) 의 그 열쇠를 갈아 쓴다 · wake_at = batched.log 1줄.
판정 불가(표 깨짐 · 기록 깨짐 · 현역 이름 풀이 실패 · 예외) = QUEUE + stderr «WARN alert-policy 판정 불가 — <사유>» 1줄.
표 파일 없음 = QUEUE · stderr 0. 열쇠 = 발신 · 머리 꼴 · 받는 좌석 현역 이름(raw «mbox.py holder» · 주소 fallback 0).
"""
import hashlib
import json
import os
import re
import signal
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
KINDS = ("안 넣음", "바뀐 때만", "주기")
WAKE = ("묶음", "첫 통")   # r2169 깨움 무리 — 큐에는 넣고 wake_at 칸만 단다(거름 무리 KINDS 가 먼저)
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
        ok = len(c) == 5 and c[0] and c[1] and c[3] in KINDS + WAKE
        if ok and c[3] in WAKE:
            ok = _mins(c[3], c[4]) is not None
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
    got = _filter([r for r in rows if r[3] in KINDS], to, frm, body)
    if got.startswith("SKIPPED"):
        return got   # r2169 W1 — 걸러진 통 = 깨움 판정 · 기록 · 흔적 0
    hold = got.partition("\t")[2]
    try:
        wake, whold = wake_judge([r for r in rows if r[3] in WAKE], to, frm, body)
    except Exception as e:   # r2169 W6 판정 불가 = 칸 없음(즉시) · 거름 결과는 그대로
        why = str(e) if isinstance(e, Unsure) else f"wake_judge 예외({type(e).__name__})"
        print(f"WARN alert-policy 판정 불가 — {why}", file=sys.stderr)
        return got
    hold = hold or whold
    return f"QUEUE\t{hold}\t{'' if wake is None else wake}" if hold or wake is not None else "QUEUE"


def wake_judge(rows, to, frm, body):
    """r2169 깨움 무리(묶음 · 첫 통) → (wake_at | None, 첫 통 기록용 현역 이름 | ""). 값 0분 = 칸 없음."""
    row, head = _match(rows, frm, body)
    if row is None:
        return None, ""
    m, now = _mins(row[3], row[4]), int(_now())
    hold, first = _holder(to), _first_load()   # W6 — 현역 이름 풀이 실패 · 첫 통 기록 깨짐 = 두 갈래 모두 판정 불가(칸 없음 · 반례 ⑧)
    if row[3] == "묶음":
        return (now + m[0] * 60 if m[0] else None), ""
    prev = first.get(_first_key(frm, head, hold, body))
    if prev is None or now - float(prev.get("ts", 0)) >= m[0] * 60:
        return None, hold
    return (now + m[1] * 60 if m[1] else None), hold


def _mins(kind, v):   # «N분» (묶음) | «N분 · N분» (첫 통) → [분…] · 못 읽으면 None
    m = re.fullmatch(r"(\d+)분" if kind == "묶음" else r"(\d+)분 · (\d+)분", v)
    return [int(x) for x in m.groups()] if m else None


KEEP = re.compile(r"([A-Za-z0-9_.\-]*#\d+)|((?<![A-Za-z0-9])r\d+(?![A-Za-z0-9]))|\d+")


def _first_key(frm, head, hold, body):   # W3 지문 = ⓐ «이름#숫자» ⓑ 카드 번호 «r숫자» 그대로 · 그 밖 숫자열 N · 전문 → sha256
    fp = KEEP.sub(lambda x: x.group(1) or x.group(2) or "N", body)
    return "\t".join((frm, head, hold, hashlib.sha256(fp.encode()).hexdigest()))


def _first_load():
    p = os.path.join(_state(), "first.json")
    if not os.path.lexists(p):
        return {}
    try:
        d = json.load(open(p, encoding="utf-8"))
    except (OSError, ValueError):
        raise Unsure("첫 통 기록 파일 깨짐")
    if not isinstance(d, dict) or not all(isinstance(v, dict) for v in d.values()):
        raise Unsure("첫 통 기록 파일 깨짐")
    return d


def _filter(rows, to, frm, body):
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


def record(frm, hold, body, to="", seq="", wake=""):
    t = _table()
    if t and hold:
        _first_record(t[0], frm, hold, body)
    if t and wake:
        _batched(t[0], frm, to, seq, body, wake)
    row, head = _match([r for r in t[0] if r[3] in KINDS], frm, body) if t and hold else (None, "")
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


def _first_record(rows, frm, hold, body):   # W3 — 첫 통 행이면 첫 통이든 반복이든 적재 시각으로 갈아 쓴다 · 창이 지난 기록은 지운다
    row, head = _match([r for r in rows if r[3] in WAKE], frm, body)
    if row is None or row[3] != "첫 통":
        return
    try:
        first = _first_load()
    except Unsure:
        first = {}   # 깨진 기록은 새 기록으로 갈아 쓴다(WARN 은 check 가 이미 냈다)
    now = _now()
    first = {k: v for k, v in first.items() if now - float(v.get("ts", 0)) < float(v.get("win", 0))}
    first[_first_key(frm, head, hold, body)] = {"ts": now, "win": _mins(row[3], row[4])[0] * 60}
    d = _state()
    os.makedirs(d, exist_ok=True)
    tmp = os.path.join(d, f".first.json.{os.getpid()}")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(first, f, ensure_ascii=False)
    os.replace(tmp, os.path.join(d, "first.json"))


def _batched(rows, frm, to, seq, body, wake):   # W8 — 칸을 단 통마다 1줄(시각 · seq · 발신 · 받는 좌석 · 머리 꼴 · 갈래 · wake_at)
    row, head = _match([r for r in rows if r[3] in WAKE], frm, body)
    try:
        os.makedirs(_state(), exist_ok=True)
        with open(os.path.join(_state(), "batched.log"), "a", encoding="utf-8") as f:
            f.write("\t".join((time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(_now())), seq, frm, to, head, row[3] if row else "-", wake)) + "\n")
    except OSError as e:
        print(f"WARN alert-policy batched.log 쓰기 실패({type(e).__name__})", file=sys.stderr)


def main(a):
    signal.alarm(7)   # 셸의 timeout 이 없을 때의 상한(7초 룰)
    try:
        if len(a) == 4 and a[0] == "check":
            print(check(a[1], a[2], a[3]))
        elif len(a) in (4, 7) and a[0] == "record":
            record(*a[1:])
        else:
            print("usage: mbox_alert_policy.py check <to> <from> <body> | record <from> <holder> <body> [<to> <seq> <wake_at>]", file=sys.stderr)
            return 2
    except Exception as e:   # Unsure · 쓰기 실패 · 뜻밖의 예외 모두 = 판정 불가(넣는다)
        why = str(e) if isinstance(e, Unsure) else f"{a[0]} 예외({type(e).__name__})"
        print(f"WARN alert-policy 판정 불가 — {why}", file=sys.stderr)
        if a[0] == "check":
            print("QUEUE")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
