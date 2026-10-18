#!/usr/bin/env python3
"""ft_live_install_check.py — 키트(하네스 코드 루트의 kit/)가 라이브 위치와 같은지 «읽기만» 검사 (R245).
종료: 0 OK · 1 PENDING · 2 usage · 3 ERROR(지도·ref 못 품 · B 가 ref 조상 아님 — #0 RULE). 쓰기 0 · fetch 0 · launchctl·ps 각 7초 상한.
--range A..B 는 대상 파일 집합만 정하고, 대조 blob 은 --ref(기본 origin/main) tip 에서 읽는다 (R367).
r385: --repo 기본 = 하네스 코드 루트(FT_HARNESS_ROOT · <이 폴더>/../HARNESS_ROOT · 팩 harness/)의 리포 · --kit 기본 = 그 리포 기준 kit/ 경로 ·
--project = shim 대조할 프로젝트 루트(기본 = --repo 의 공용 루트)."""
import fnmatch
import os
import re
import subprocess
import sys
import time

KD = MAPPATH = KBIN = ""  # main 이 --kit 으로 채운다(리포 기준 키트 경로 · 끝 / )
SHIMMARK = "# ft-root-bin-shim:"  # ft-root-bin-shim.sh 가 연결 파일 2행에 쓰는 표식


def die(msg):
    print("ERROR " + msg)
    sys.exit(3)


def run(cmd, inp=None):
    try:  # C 로케일 — ps lstart 가 한글 요일로 나오면 해석 불가
        return subprocess.run(cmd, input=inp, capture_output=True, text=True, timeout=7, env={**os.environ, "LC_ALL": "C"})
    except (subprocess.TimeoutExpired, OSError) as e:
        die("실행 실패/7초 초과: %s (%s)" % (cmd[0], e))


def git(repo, *args, inp=None):
    """한글 경로(indices/대기 등)는 core.quotepath=false 로 원형 · 바이트로 받아 surrogateescape 로 푼다 — non-UTF8 이름(0xff)도 예외 없이 원형 보존 (R377 DA⑥ r1)."""
    try:
        r = subprocess.run(["git", "-C", repo, "-c", "core.quotepath=false", *args], input=None if inp is None else inp.encode("utf-8", "surrogateescape"),
                           capture_output=True, timeout=7, env={**os.environ, "LC_ALL": "C"})
    except (subprocess.TimeoutExpired, OSError) as e:
        die("실행 실패/7초 초과: git (%s)" % e)
    if r.returncode:
        die("git %s 실패: %s" % (" ".join(args[:2]), r.stderr.decode("utf-8", "surrogateescape").strip()[:120]))
    return r.stdout.decode("utf-8", "surrogateescape")


def parse_args(argv):
    o = {"range": None, "all": False, "ref": "origin/main", "repo": None, "map": None, "kit": None, "project": None}
    i = 0
    while i < len(argv):
        if argv[i] == "--all":
            o["all"], i = True, i + 1
        elif argv[i] in ("--range", "--ref", "--repo", "--map", "--kit", "--project") and i + 1 < len(argv):
            o[argv[i][2:]], i = argv[i + 1], i + 2
        else:
            sys.exit(2)
    if bool(o["range"]) == o["all"]:
        sys.exit(2)
    return o


def harness_root():
    """ft-harness-root.sh 와 같은 순서: env FT_HARNESS_ROOT → <이 폴더>/../HARNESS_ROOT → 팩 harness/bin · harness/kit/fable-team/bin 위치. 못 풀면 None."""
    here = os.path.dirname(os.path.abspath(__file__))
    c = os.environ.get("FT_HARNESS_ROOT") or ""
    if not c and os.path.isfile(os.path.join(here, "..", "HARNESS_ROOT")):
        with open(os.path.join(here, "..", "HARNESS_ROOT"), encoding="utf-8") as fh:
            c = fh.readline().strip()
    for cand in ([c] if c else [os.path.join(here, ".."), os.path.join(here, "..", "..", "..")]):
        if os.path.isdir(os.path.join(cand, "kit", "fable-team")):
            return os.path.realpath(cand)
    return None


def resolve_kit(o):
    """--repo·--kit 기본값을 하네스 코드 루트에서 푼다 (r385 · 리포 루트 전제 0) · 못 풀면 ERROR."""
    global KD, MAPPATH, KBIN
    hr = None if (o["repo"] and o["kit"]) else harness_root()
    if not o["repo"] or not o["kit"]:
        if not hr:
            die("하네스 루트를 못 풂(FT_HARNESS_ROOT · ../HARNESS_ROOT 없음) — --repo·--kit 를 준다")
    repo = o["repo"] or git(hr, "rev-parse", "--show-toplevel").strip()
    if o["kit"]:
        kd = o["kit"]
    else:
        rel = os.path.relpath(os.path.join(hr, "kit"), os.path.realpath(repo))
        if rel.startswith(".."):
            outside_repo(o, hr, repo)
        kd = rel
    KD = kd.rstrip("/") + "/"
    MAPPATH, KBIN = KD + "LIVE-MAP.tsv", KD + "fable-team/bin/"
    return repo


OLD_HARNESS = ("scripts/fable-team-bin/", "scripts/harness-install/", "tools/comm-canonical/", "tests/harness/", "kit/",
               ":(glob)**/harness/kit/**")  # 마지막 = --repo 가 팩 리포의 다른 체크아웃일 때 팩 키트 변경(조용한 통과 0)


def outside_repo(o, hr, repo):
    """하네스 루트가 --repo 밖 (r385 r4): --range 면 범위가 건드린 옛 하네스 경로 파일이 0 일 때만 OK n=0 · 있거나 --all 이면 ERROR (fail-closed)."""
    msg = "하네스 루트(%s)가 --repo(%s) 밖 — --kit 를 준다" % (hr, repo)
    a, _, b = (o["range"] or "").partition("..")
    if not a or not b:
        die(msg)
    for x in (a, b):
        git(repo, "rev-parse", "--verify", "-q", x + "^{commit}")
    hit = [f for f in git(repo, "diff", "--name-only", "--diff-filter=ACMR", a, b, "--", *OLD_HARNESS).split("\n") if f]
    if hit:
        die(msg + " · 범위에 하네스 파일 %d: %s" % (len(hit), " ".join(sorted(hit))))
    print("OK n=0 skip=0 (하네스 루트가 --repo 밖 · 범위에 하네스 파일 0)")
    sys.exit(0)


def load_map(text):
    rows = [ln.split("\t") for ln in text.splitlines() if ln.strip() and not ln.startswith("#")]
    for c in rows:
        if len(c) < 4 or c[1] not in ("bin", "cmp", "plist", "skip"):
            die("지도 행 형식 오류: " + "\t".join(c)[:80])
    return [c[:4] for c in rows]


def subst(p):
    ft = os.environ.get("FT_BIN")
    if "$FT_BIN" in p and not ft:
        die("FT_BIN 환경변수 없음 — 라이브 도구 폴더를 모른다")
    return p.replace("$FT_BIN", ft or "").replace("$HOME", os.environ["HOME"])


def live_path(row, f):
    """라이브 파일 경로 = 라이브 폴더 + 지도 패턴의 «첫 와일드카드 앞» 이후 상대 경로(중첩 폴더 보존). 와일드카드 없으면 파일 이름만 (R377)."""
    pre = row[0].split("*")[0]
    rel = f[len(KD):]
    sub = rel[len(pre):] if pre and rel.startswith(pre) else ""
    return os.path.join(subst(row[2]), sub or os.path.basename(f))


def plist_items(repo, path, blob):
    """템플릿 Label 적재 여부 + 프로세스 시작 시각 < 라이브 스크립트 mtime → RESTART."""
    body = git(repo, "cat-file", "blob", blob)
    m = re.search(r"<key>Label</key>\s*<string>([^<]+)</string>", body)
    label = m.group(1) if m and "__" not in m.group(1) else os.path.basename(path)[: -len(".plist.template")]  # 치환 자리표시 라벨 = 파일 이름이 라벨
    # r385: 하네스 bin 을 부르는 데몬은 데이터 루트를 cwd·env 로만 푼다(설치본이 git 밖) — 둘 다 없으면 PENDING
    if re.search(r"__FT_BIN__|/\.fable-team/bin/", body) and not re.search(r"<key>WorkingDirectory</key>|<key>FT_(RES_)?ROOT</key>", body):
        return ["NOROOT %s (하네스 bin 데몬에 WorkingDirectory·FT_ROOT 없음 — 설치본 위치로 루트를 못 푼다)" % label]
    r = run([os.environ.get("FT_LAUNCHCTL", "launchctl"), "list", label])
    if r.returncode:
        return ["NOTLOADED " + label]
    pm = re.search(r'"PID"\s*=\s*(\d+)', r.stdout)
    scripts = [os.environ["HOME"] + s for s in re.findall(r"<string>__HOME__(/[^<]+\.(?:py|sh))</string>", body)]
    miss = ["MISSING %s -> %s" % (path, s) for s in scripts if not os.path.isfile(s)]
    if not pm or miss:
        return miss  # PID 없음(주기 실행 job) = 시작 시각 비교 불가 — 적재만 확인
    ls = run([os.environ.get("FT_PS", "ps"), "-o", "lstart=", "-p", pm.group(1)]).stdout.split()
    try:
        started = time.mktime(time.strptime(" ".join(ls), "%a %b %d %H:%M:%S %Y"))
    except ValueError:
        die("ps lstart 해석 실패: %s" % ls)
    return ["RESTART " + label] if started < max((os.path.getmtime(s) for s in scripts), default=0) else []


def shim_items(repo, tree, project=None):
    """라이브 bin 에 실재하는 키트 도구마다 루트 .fable-team/bin/<이름> 연결 파일(앞 3줄에 SHIMMARK)이 있는지 (R374). LIVE_BIN 파일 없음 = 검사 대상 아님.
    루트 = --project(r385 · 키트 리포와 프로젝트가 갈린 뒤) 또는 키트 리포의 공용 루트."""
    if project:
        root = os.path.realpath(project)
    else:
        gc = git(repo, "rev-parse", "--path-format=absolute", "--git-common-dir").strip()
        root = gc[: -len("/.git")] if gc.endswith("/.git") else os.path.dirname(gc)
    lf = os.path.join(root, ".fable-team", "LIVE_BIN")
    if not os.path.isfile(lf):
        return [], ""
    with open(lf, encoding="utf-8") as fh:
        live = fh.readline().strip()
    if not os.path.isabs(live) or not os.path.isdir(live):
        die("LIVE_BIN 이 절대경로 폴더가 아님: %r (%s)" % (live, lf))
    rbin = os.path.join(root, ".fable-team", "bin")
    names = sorted({os.path.basename(p) for p in tree if p.startswith(KBIN) and p.endswith((".sh", ".py")) and os.path.isfile(os.path.join(live, os.path.basename(p)))})
    miss = [n for n in names if not is_shim(os.path.join(rbin, n))]
    return miss, "bash %s/ft-root-bin-shim.sh --root %s --live %s" % (live, root, live)


def is_shim(path):
    if os.path.islink(path) or not os.path.isfile(path):
        return False
    with open(path, encoding="utf-8", errors="replace") as fh:
        return any(SHIMMARK in fh.readline() for _ in range(3))


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")  # 로케일과 무관하게 한글은 원형 · non-UTF8 경로는 \udcff 대신 이스케이프 출력
    o = parse_args(sys.argv[1:])
    repo = resolve_kit(o)
    ref, landed, removed = o["ref"], None, []
    if o["range"]:  # A..B 는 «대상 파일 집합»만 정한다 — 대조 blob 은 ref tip (R367)
        a, _, landed = o["range"].partition("..")
        if not a or not landed:
            sys.exit(2)
        for x in (a, landed, ref):
            git(repo, "rev-parse", "--verify", "-q", x + "^{commit}")
        if run(["git", "-C", repo, "merge-base", "--is-ancestor", landed, ref]).returncode:
            die("%s 가 ref(%s) 조상 아님 — 다른 가지 착지를 tip 로 재지 않는다" % (landed[:10], ref))
        files = set(git(repo, "diff", "--name-only", "--diff-filter=ACMR", a, landed, "--", KD).split("\n"))
    else:
        files = None
        git(repo, "rev-parse", "--verify", "-q", ref + "^{commit}")
    tree = {}
    for ln in git(repo, "ls-tree", "-r", ref, "--", KD).splitlines():
        meta, _, path = ln.partition("\t")
        tree[path] = (meta.split()[0], meta.split()[2])
    if files is not None:
        removed = sorted(f for f in files if f and f not in tree and ".bak" not in f)
    files = sorted(f for f in (files if files is not None else tree) if f in tree and ".bak" not in f)
    try:
        rows = load_map(open(o["map"], encoding="utf-8").read() if o["map"] else git(repo, "show", ref + ":" + MAPPATH))
    except OSError as e:
        die("지도를 못 읽음: %s" % e)
    bad, hints, skip, checked, pairs = [], {}, 0, 0, []
    miss, shint = shim_items(repo, tree, o["project"])
    bad += ["PENDING shim " + n for n in miss]
    hints.update({"shim": shint} if miss else {})
    for f in files:
        rel = f[len(KD):]
        row = next((r for r in rows if fnmatch.fnmatch(rel, r[0])), None)
        if row is None:
            bad.append("UNMAPPED " + f)
        elif row[1] == "skip":
            skip += 1
        elif row[1] == "plist":
            checked += 1
            items = plist_items(repo, f, tree[f][1])
            bad += items
            hints.update({rel.split("/")[0]: row[3]} if items else {})
        else:
            checked += 1
            pairs.append((f, live_path(row, f), row))
    live = [p for p in pairs if os.path.isfile(p[1])]
    hashes = git(repo, "hash-object", "--no-filters", "--stdin-paths", inp="".join(p[1] + "\n" for p in live)).split() if live else []
    hmap = {p[1]: h for p, h in zip(live, hashes)}
    for f, lp, row in pairs:
        why = "MISSING" if lp not in hmap else ("DIFF" if hmap[lp] != tree[f][1] else "")
        if not why and tree[f][0] == "100755" and not os.access(lp, os.X_OK):
            why = "MODE"
        if why:
            tail = " live=%s tip=%s landed=%s" % (hmap[lp][:10], tree[f][1][:10], landed[:10]) if why == "DIFF" and landed else ""
            bad.append("%s %s -> %s%s" % (why, f, lp, tail))
            hints[f[len(KD):].split("/")[0]] = row[3]
    drows = rows if (o["map"] or not removed) else load_map(git(repo, "show", landed + ":" + MAPPATH))
    for f in removed:  # tip 에서 삭제된 파일 — landed(B) 시점 지도로 라이브 경로를 풀어 잔재가 있으면 PENDING (읽기만 · 삭제 0)
        row = next((r for r in drows if fnmatch.fnmatch(f[len(KD):], r[0])), None)
        if row is None or row[1] == "plist":
            bad.append("UNKNOWN %s (삭제 파일 — landed 지도로 라이브 경로를 못 풂)" % f)
        elif row[1] != "skip" and os.path.isfile(live_path(row, f)):
            bad.append("STALE %s -> %s" % (f, live_path(row, f)))
            hints[f[len(KD):].split("/")[0]] = row[3]
        else:
            print("REMOVED %s (ref tip 에서 삭제 · 라이브 잔재 0)" % f)
    if not bad:
        print("OK n=%d skip=%d" % (checked, skip))
        return 0
    print("PENDING n=%d" % len(bad))
    print("\n".join(sorted(bad)))
    print("\n".join("HINT %s %s" % (k, hints[k]) for k in sorted(hints)))
    return 1


if __name__ == "__main__":
    sys.exit(main())
