#!/usr/bin/env python3
"""ft-seat-open-work.py <좌석> [--root R] [--mbox-dir D] — 이 좌석이 «받을 일» 이 있는지 판정한다(r1539 · 읽기 전용 · 표시·소비·쓰기·kill 0).
rc 0 = 받을 일 0(후계 0 · 좌석 닫기 대기) · 1 = 있음(기존 승계) · 3 = 판정 불가(기존 승계 + stderr 1줄) · stdout = `OPEN-WORK 0|있음|불가 이유=…` (+ rc0 이면 `LEADER <팀장|->`)
입력 = ①우편함(아직 recv 안 한 큐 + 받고도 «처리함|인계» 표시 없는 영수) ②진행 카드 «- 배정: 좌석 <좌석>» ③state/card-assign «seat» ④팀장 좌석이면 팀 진행 카드 · 좌석 계보 = «#» 앞 이름 · «일 아님» 꼴 목록(정본 = 이 파일 한 곳) = 머리 «[처리»·«[다음 없음»·«[알림»·«[정리» · 본문 첫 줄에 «다음 일 없음» · recv 인용 «READ » — 그 밖은 일로 센다.
"""
import glob, json, os, re, sys
NOT_WORK = ("[처리", "[다음 없음", "[알림", "[정리")
ASSIGN = re.compile(r"^-\s*배정:\s*좌석\s+([A-Za-z0-9._#-]+)", re.M)
NAME = re.compile(r"^[A-Za-z0-9._#-]+$")

def rk(name):   # 좌석 계보 = «#» 앞 이름
    return re.sub(r"#\d+$", "", name or "")

def rows(path):   # jsonl 읽기 — 파일 없음 = 0건 · 깨짐 = ValueError(판정 불가)
    try:
        with open(path, encoding="utf-8") as f:
            return [json.loads(line) for line in f if line.strip()]
    except FileNotFoundError:
        return []

def is_not_work(body):
    b = body or ""
    m = re.match(r"\s*(\[[^\]]*\])", b)
    if m and m.group(1).startswith(NOT_WORK):
        return True
    first = (b.lstrip().splitlines() or [""])[0]
    return first.startswith("READ ") or "다음 일 없음" in first

def unread(seat, mdir):   # 미처리 쪽지 = 아직 recv 안 한 큐 + 받고도 «처리함|인계» 표시가 없는 영수
    key = rk(seat)
    out = [r for r in rows(os.path.join(mdir, "mailbox.jsonl")) if rk(r.get("to")) == key and r.get("from") != seat]
    rec = rows(os.path.join(mdir, "receipts", key + ".jsonl"))
    done = {r.get("seq") for r in rec if "mark" in r}
    return out + [r for r in rec if "mark" not in r and r.get("seq") not in done]

def load(path):   # json 1장 — 깨지면 ValueError(판정 불가)
    with open(path, encoding="utf-8") as f:
        return json.load(f)

def roster(root):   # 명부(seats*.json) 좌석 이름 값 — 못 읽는 파일은 건너뛴다(추측 0)
    names = []
    for f in sorted(glob.glob(os.path.join(root, ".fable-team", "seats*.json"))):
        try:
            names += [v for v in load(f).values() if isinstance(v, str)]
        except ValueError:
            continue
    return names

def verdict(seat, root, mdir):
    key = rk(seat)
    team = key.split("-")
    try:
        msgs = unread(seat, mdir)
    except (OSError, ValueError) as e:
        return 3, "쪽지 %s" % type(e).__name__, ""
    dirs = sorted(glob.glob(os.path.join(root, "design", "*", "indices", "진행")))
    if not dirs:
        return 3, "카드 폴더 없음 design/*/indices/진행", ""
    cards, states = [], []
    try:
        for p in sorted(sum([glob.glob(os.path.join(d, "*.md")) for d in dirs], [])):
            with open(p, encoding="utf-8") as f:
                cards += [os.path.basename(p) for m in ASSIGN.finditer(f.read()) if rk(m.group(1)) == key]
        st = os.path.join(root, ".fable-team", "state", "card-assign")
        for n in sorted(os.listdir(st)) if os.path.isdir(st) else []:
            if n.endswith(".json") and rk(load(os.path.join(st, n)).get("seat") or "") == key:
                states.append(n)
    except (OSError, ValueError) as e:
        return 3, "카드·배정 %s" % type(e).__name__, ""
    tdir = os.path.join(root, "design", team[1] if len(team) > 1 else "", "indices", "진행")
    if len(team) > 2 and team[2] in ("master", "arch"):   # 팀장 좌석 = 팀 진행 카드도 이 좌석 일
        if not os.path.isdir(tdir):
            return 3, "팀 카드 폴더 없음 %s" % tdir, ""
        if glob.glob(os.path.join(tdir, "*.md")):
            return 1, "팀 진행 %d" % len(glob.glob(os.path.join(tdir, "*.md"))), ""
    work = [m for m in msgs if not is_not_work(m.get("body"))]
    if work:
        return 1, "쪽지 일 %d" % len(work), ""
    if cards:
        return 1, "배정 %d (%s)" % (len(cards), cards[0]), ""
    if states:
        return 1, "카드 배정 %d (%s)" % (len(states), states[0]), ""
    lead = ""
    for head in ("master", "arch"):
        lead = next((v for v in roster(root) if rk(v).startswith("%s-%s-" % ("-".join(team[:2]), head)) and rk(v) != key), "")
        if lead:
            break
    return 0, "쪽지0(일 아님 %d)·배정0·진행0" % (len(msgs) - len(work)), lead or "-"

def main(argv):
    args, root, mbox_dir, seat = list(argv), "", "", (argv[0] if argv else "")
    while len(args) > 1:   # 남는 인자 = usage(rc2) — 모르는 값을 조용히 무시하지 않는다
        if args[1] not in ("--root", "--mbox-dir") or len(args) < 3:
            seat = ""
            break
        if args[1] == "--root":
            root = args[2]
        else:
            mbox_dir = args[2]
        del args[1:3]
    if not NAME.match(seat or ""):
        sys.stderr.write("usage: %s <좌석> [--root R] [--mbox-dir D]\n" % os.path.basename(sys.argv[0]))
        return 2
    here = os.path.dirname(os.path.abspath(__file__))
    root = root or os.environ.get("FT_ROOT") or os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mbox_dir = mbox_dir or os.environ.get("FT_MBOX_DIR") or os.path.join(root, ".fable-team", "comm")
    rc, why, lead = verdict(seat, root, mbox_dir)
    if rc == 3:
        sys.stderr.write("받을 일 판정 불가 %s — 기존 승계\n" % why)
        print("OPEN-WORK 불가 이유=%s" % why)
        return 3
    if rc == 1:
        print("OPEN-WORK 있음 이유=%s" % why)
        return 1
    print("OPEN-WORK 0 이유=%s" % why)
    print("LEADER %s" % lead)
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
