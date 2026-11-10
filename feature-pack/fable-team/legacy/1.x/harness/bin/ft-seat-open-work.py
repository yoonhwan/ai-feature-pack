#!/usr/bin/env python3
"""ft-seat-open-work.py <좌석> [--root R] [--mbox-dir D] — 이 좌석이 «받을 일» 이 있는지 판정한다(r1539 · 읽기 전용 · 표시·소비·쓰기·kill 0).
rc 0 = 받을 일 0(후계 0 · 좌석 닫기 대기) · 1 = 있음(기존 승계) · 3 = 판정 불가(기존 승계 + stderr 1줄 · ①쪽지·카드 못 읽음 ②indices/ 자체가 없음 — 진행/ 만 없으면 0 이다 r1541) · stdout = `OPEN-WORK 0|있음|불가 이유=…` (+ rc0 이면 `LEADER <팀장|->`)
입력 = ①우편함(아직 recv 안 한 큐 + 받고도 «처리함|인계» 표시 없는 영수) ②진행 카드 «- 배정: 좌석 <좌석>» ③state/card-assign «seat» ④팀장 좌석이면 팀 진행 카드 · 좌석 계보 = «#» 앞 이름 · «일 아님» 꼴 목록(정본 = 이 파일 한 곳) = 머리 «[처리»·«[다음 없음»·«[알림»·«[정리» · 본문 첫 줄에 «다음 일 없음» · recv 인용 «READ » — 그 밖은 일로 센다. «내가 나에게» 보낸 쪽지만 빼고 같은 계보 후계에게 보낸 [인계] 는 센다(r1575).
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
    out = [r for r in rows(os.path.join(mdir, "mailbox.jsonl")) if rk(r.get("to")) == key and not (r.get("from") == r.get("to") == seat)]   # ★«내가 나에게»만 뺀다 — 같은 계보 후계에게 보낸 [인계] 도 일(r1575)
    rec = []   # ★영수 파일 이름 = 실제로는 «좌석#번호.jsonl»(번호 있음) — 계보 키 하나만 보면 발주를 놓친다(DA r1539 R1)
    rdir = os.path.join(mdir, "receipts")
    for n in (sorted(os.listdir(rdir)) if os.path.isdir(rdir) else []):
        rec += rows(os.path.join(rdir, n)) if n.endswith(".jsonl") and rk(n[:-6]) == key else []
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
    idx = sorted({d for pat in ("design/*/indices", "design/teams/*/indices") for d in glob.glob(os.path.join(root, pat))})   # ★두 꼴★ design/<팀>/ · design/teams/<팀>/ (DA r1539 R2)
    dirs = [os.path.join(d, "진행") for d in idx if os.path.isdir(os.path.join(d, "진행"))]
    if not idx:   # ★진행/ 없음 ≠ 못 읽음★ git 은 빈 폴더를 안 남긴다 — indices/ 가 있으면 진행 카드 0 으로 판정 계속(r1541)
        return 3, "카드 폴더 없음 design/*/indices · design/teams/*/indices", ""
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
    tm = team[1] if len(team) > 1 else ""
    tidx = [p for p in ("design/" + tm, "design/teams/" + tm) if os.path.isdir(os.path.join(root, p, "indices"))]
    tdir = next((os.path.join(root, p, "indices", "진행") for p in tidx if os.path.isdir(os.path.join(root, p, "indices", "진행"))), "")
    if len(team) > 2 and team[2] in ("master", "arch"):   # 팀장 좌석 = 팀 진행 카드도 이 좌석 일
        if not tidx:   # 팀 indices/ 자체가 없을 때만 판정 불가 · 진행/ 만 없으면 진행 카드 0(r1541)
            return 3, "팀 카드 폴더 없음 %s" % tdir, ""
        if tdir and glob.glob(os.path.join(tdir, "*.md")):
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
    seat, root, mbox_dir = (argv[0] if argv else ""), "", ""
    root = argv[argv.index("--root") + 1] if "--root" in argv[:-1] else ""
    mbox_dir = argv[argv.index("--mbox-dir") + 1] if "--mbox-dir" in argv[:-1] else ""
    if len(argv) != 1 + 2 * (bool(root) + bool(mbox_dir)):   # 모르는·빠진 인자 = usage(rc2) — 조용히 무시 0
        seat = ""
    if not NAME.match(seat or ""):
        sys.stderr.write("usage: %s <좌석> [--root R] [--mbox-dir D]\n" % os.path.basename(sys.argv[0]))
        return 2
    root = root or os.environ.get("FT_ROOT") or os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
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
