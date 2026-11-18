#!/usr/bin/env python3
"""ft-seat-open-work.py <좌석> [--root R] [--mbox-dir D] — 이 좌석이 «받을 일» 이 있는지 판정한다(r1539 · 읽기 전용 · 표시·소비·쓰기·kill 0).
rc 0 = 받을 일 0(후계 0 · 좌석 닫기 대기) · 1 = 있음(기존 승계) · 3 = 판정 불가(기존 승계 + stderr 1줄 · ①쪽지·카드 못 읽음 ②indices/ 자체가 없음 — 진행/ 만 없으면 0 이다 r1541) · stdout = `OPEN-WORK 0|있음|불가 이유=…` (+ rc0 이면 `LEADER <팀장|->`)
입력 = ①우편함(아직 recv 안 한 큐 + 받고도 «처리함|인계» 표시 없는 영수) ②진행 카드 «- 배정: 좌석 <좌석>» ③state/card-assign «seat» ④팀장 좌석이면 팀 진행 카드 · 좌석 계보 = «#» 앞 이름 · «일 아님» 꼴 목록(정본 = 이 파일 한 곳) = 머리 «[처리»·«[다음 없음»·«[알림»·«[정리» · 본문 첫 줄에 «다음 일 없음» · recv 인용 «READ » — 그 밖은 일로 센다. «내가 나에게» 보낸 쪽지만 빼고 같은 계보 후계에게 보낸 [인계] 는 센다(r1575).
"""
import glob, json, os, pathlib, re, shutil, subprocess, sys
NOT_WORK = ("[처리", "[다음 없음", "[알림", "[정리")
ASSIGN = re.compile(r"^-\s*배정:\s*좌석\s+([A-Za-z0-9._#-]+)", re.M)
NAME = re.compile(r"^[A-Za-z0-9._#-]+$")
IDX = re.compile(r"design/(?:teams/)?[^/]+/indices/")   # ★두 꼴★ design/<팀>/ · design/teams/<팀>/ (DA r1539 R2)

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

def intake(root, tm, seat):   # r2076 E5·E6 — 팀장 빈 2.0 팀의 사슬 끝 팀장 행 = ft2 접수 남은 일 · None = 해당 없음·남은 일 0
    mk = os.path.join(root, ".fable-team", "state", "ft20-switch", tm + ".json")
    if not os.path.isfile(mk):
        return None
    try:
        d, ros = load(mk), load(os.path.join(root, ".fable-team", "seats-%s.json" % tm))
        if not (isinstance(d, dict) and str(d.get("h") or "") and isinstance(ros, dict)):   # 표식 h 빈 글 · 명부가 객체 아님 = 판독 실패(DA 인수 칸)
            raise ValueError("표식·명부 꼴")
    except (OSError, ValueError):
        return 3, "2.0 표식·명부 판독", ""
    row = ros.get(seat)
    if ros.get("_master") != "" or not isinstance(row, dict) or row.get("_replaced_by"):
        return None
    try:   # ft2 CURRENT 판 core/cli.py project 1회(읽기 동사 · 25초 · 재시도 0 · ft_nano_record_ft2.py 와 같은 길)
        home = os.environ.get("FT2_HOME") or os.path.expanduser("~/.claude/fable-team/ft2")
        cli = os.environ.get("FT2_CLI") or os.path.join(home, "versions", open(os.path.join(home, "CURRENT"), encoding="utf-8").read().strip(), "core", "cli.py")
        if not os.path.isfile(cli):
            raise OSError(cli)
        r = subprocess.run([sys.executable, cli, "project", "--root", root, "--team", tm], capture_output=True, text=True, timeout=25)
        out = json.loads(r.stdout) if r.returncode == 0 else {}
        n = out.get("remaining") if out.get("result") == "접수 성공" else None
    except Exception:   # 시간 초과·JSON 아님·꼴 틀림 = 판독 실패(rc 0 으로 새지 않음)
        n = None
    if type(n) is not int or n < 0:
        return 3, "접수 판독", ""
    return (1, "접수 남은 일 %d" % n, "") if n else None

def cards_of(root):   # r2268 (indices · 진행 폴더 · {진행 카드: 본문}) 상대 경로 — 카드 루트 표(directive-roots.tsv · keeper_next cards() 같은 읽기)의 행마다 정본 ref 1개만(C1 · «*» 행은 자기 행 있는 팀 뺌 · 표 밖 루트 0) · 표·ref 없음 = 작업 트리(C2 · 표 읽기 실패 = OSError·ValueError) · git 실패·7초 = SubprocessError(C3 · 작업 트리로 안 내려감)
    git = lambda d, *a, ok=False: subprocess.run(["git", "-C", d] + list(a), capture_output=True, timeout=7, check=not ok, env=dict(os.environ, GIT_CEILING_DIRECTORIES=os.path.dirname(os.path.abspath(d))))   # 1회 7초 · 재시도 0 · fetch 0 · 루트 위 리포 ref 0
    rows = [x for x in (y.split("\t") for y in t.read_text(encoding="utf-8").splitlines() if not y.startswith("#")) if len(x) >= 4 and shutil.which("git") and git(os.path.join(root, x[1]), "rev-parse", "-q", "--verify", x[2] + "^{commit}", ok=True).returncode == 0] if (t := pathlib.Path(root, ".fable-team", "state", "directive-roots.tsv")).is_file() else []   # ref 없는 행 = 0
    seen = {os.path.relpath(p, root) + "/" * os.path.isdir(p): "" for b in ("design/*/indices", "design/teams/*/indices") for s in ("", "/진행", "/진행/*.md") for p in ([] if rows else glob.glob(os.path.join(root, b + s)))}
    [seen.setdefault(p, (os.path.join(root, x[1]), x[2])) for x in rows for p in git(os.path.join(root, x[1]), "ls-tree", "-r", "-z", "--name-only", x[2], "--", x[3].split("*")[0]).stdout.decode().split("\0") if (m := re.match(re.escape(x[3]).replace(r"\*", "([^/]+)") + "/", p)) and not (m.groups() and m.group(1) in {y[0] for y in rows})]
    ms = [m for m in map(IDX.match, seen) if m]
    dirs = {m.group(0) + "진행" for m in ms if m.string.startswith(m.group(0) + "진행/")}
    read = lambda p: git(seen[p][0], "cat-file", "blob", "%s:%s" % (seen[p][1], p)).stdout.decode() if rows else pathlib.Path(root, p).read_text(encoding="utf-8")
    return sorted({m.group(0)[:-1] for m in ms}), dirs, {p: read(p) for p in sorted(seen) if os.path.dirname(p) in dirs and re.match(r"[^.].*\.md$", os.path.basename(p))}

def verdict(seat, root, mdir):
    key = rk(seat)
    team = key.split("-")
    try:
        msgs = unread(seat, mdir)
    except (OSError, ValueError) as e:
        return 3, "쪽지 %s" % type(e).__name__, ""
    try:
        idx, dirs, body = cards_of(root)
    except (OSError, ValueError, subprocess.SubprocessError) as e:
        return 3, ("카드 ref 판독 %s" if isinstance(e, subprocess.SubprocessError) else "카드·배정 %s") % type(e).__name__, ""
    if not idx:   # ★진행/ 없음 ≠ 못 읽음★ git 은 빈 폴더를 안 남긴다 — indices/ 가 있으면 진행 카드 0 으로 판정 계속(r1541)
        return 3, "카드 폴더 없음 design/*/indices · design/teams/*/indices", ""
    cards, states = [os.path.basename(p) for p in sorted(body) for m in ASSIGN.finditer(body[p]) if rk(m.group(1)) == key], []
    try:
        st = os.path.join(root, ".fable-team", "state", "card-assign")
        for n in sorted(os.listdir(st)) if os.path.isdir(st) else []:
            if n.endswith(".json") and rk(load(os.path.join(st, n)).get("seat") or "") == key:
                states.append(n)
    except (OSError, ValueError) as e:
        return 3, "카드·배정 %s" % type(e).__name__, ""
    tm = team[1] if len(team) > 1 else ""
    tidx = [p for p in ("design/" + tm, "design/teams/" + tm) if p + "/indices" in idx]
    tdir = next((p + "/indices/진행" for p in tidx if p + "/indices/진행" in dirs), "")
    if len(team) > 2 and team[2] in ("master", "arch"):   # 팀장 좌석 = 팀 진행 카드도 이 좌석 일
        if not tidx:   # 팀 indices/ 자체가 없을 때만 판정 불가 · 진행/ 만 없으면 진행 카드 0(r1541)
            return 3, "팀 카드 폴더 없음 %s" % tdir, ""
        if tdir and any(os.path.dirname(c) == tdir for c in body):
            return 1, "팀 진행 %d" % sum(os.path.dirname(c) == tdir for c in body), ""
    work = [m for m in msgs if not is_not_work(m.get("body"))]
    if work:
        return 1, "쪽지 일 %d" % len(work), ""
    if cards:
        return 1, "배정 %d (%s)" % (len(cards), cards[0]), ""
    if states:
        return 1, "카드 배정 %d (%s)" % (len(states), states[0]), ""
    got = intake(root, tm, seat) if len(team) > 2 and team[2] == "master" else None   # r2076 — 기존 판정이 전부 0 일 때만
    if got:
        return got
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
