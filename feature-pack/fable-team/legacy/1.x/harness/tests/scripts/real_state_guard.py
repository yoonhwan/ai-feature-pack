#!/usr/bin/env python3
"""real_state_guard.py — 시험이 «실» 하네스 상태를 바꾸지 않게 지키는 도우미 (r541 · 사건 A11~A18:
FT_ROOT 없이 BYZ cwd 에서 돈 시험이 ft_data_root ②(cwd 공용 루트 LIVE_ROOT)를 따라 실 자율 상태에 씀).
CLI(셸 짝 tests/lib/real_state_guard.sh): `snap --out <파일> --cwd <폴더>` = cwd 기준 실 루트 3종(데이터·리포·우편함)
지문 저장 · `compare <파일>` = 다시 떠 비교 → stderr PASS/WARN/FAIL · FAIL rc1.
r684 r2: h<N> 축은 «계획 경로» 로 가른다 — 시험 사본(mktemp 아래) 계획이면 FAIL, 동시 실행 좌석의 실 계획이면 WARN 만
(번호표 폴더 /tmp 는 전역이라 좌석의 approve-merge 만으로도 늘어난다 · master#93 2026-10-22 03:34 h259 사건).
파이썬 스크립트 시험: 맨 위 `guard_begin()` = 지문 → git 밖 임시 폴더에서 같은 시험을 자식으로 다시 돌림 → 비교.
pytest 시험: `from real_state_guard import guard_begin_module  # noqa: F401` = 모듈 autouse 픽스처(같은 일 · FAIL = pytest.fail)."""
import hashlib, json, os, re, subprocess, sys, tempfile  # noqa: E401

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT_SH = os.path.join(HERE, "..", "..", "bin", "ft-harness-root.sh")
FAIL_STATE = ("autonomy.json", "autonomy.log", "autonomy.queued", "autonomy-merge-approved",
              "autonomy-scope", "press-permits", "permits", "install-pending")
ROOT_ENV = ("FT_ROOT", "FT_MBOX_DIR", "FT_RES_ROOT")
TAIL_BYTES, TAG = 4 << 20, "REAL-STATE-GUARD"


def _resolve(fn, cwd, keep_env):
    """ft-harness-root.sh 의 풀이 함수를 그대로 부른다 — 도구와 같은 규칙 · 못 풀면 None."""
    drop = ("GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_CEILING_DIRECTORIES") + (() if keep_env else ROOT_ENV)
    env = {k: v for k, v in os.environ.items() if k not in drop}
    r = subprocess.run(["bash", "-c", f'. "$1" && {fn} ""', "_", ROOT_SH], cwd=cwd, env=env,
                       capture_output=True, text=True, timeout=7)
    out = r.stdout.strip()
    return os.path.realpath(out) if r.returncode == 0 and out else None


def roots(cwd):  # [[종류, 경로]] — cwd 기준(env 없음) + 부르는 쪽 env 기준 · 중복 제거
    res = []
    for keep in (False, True):
        for kind, fn in (("data", "ft_data_root"), ("repo", "ft_repo_root"), ("comm", "ft_comm_dir")):
            p = _resolve(fn, cwd, keep)
            if p and [kind, p] not in res and os.path.isdir(p):
                res.append([kind, p])
    return res


def _sig(p, deep):
    st = os.stat(p)
    if deep and os.path.isfile(p):
        with open(p, "rb") as f:
            return [st.st_size, st.st_mtime_ns, hashlib.sha256(f.read()).hexdigest()]
    return [st.st_size, st.st_mtime_ns]


def _tree_sig(p):  # 파일이면 크기·mtime·sha · 폴더면 그 아래 모든 파일
    if not os.path.isdir(p):
        return {p: _sig(p, True)}
    return {os.path.join(d, f): _sig(os.path.join(d, f), True) for d, _, fs in os.walk(p) for f in fs}


def _names(raw):
    try:
        j = json.loads(raw)
    except ValueError:
        return set()
    vals = [x for k in ("from", "to") for x in (j.get(k) if isinstance(j.get(k), list) else [j.get(k)])]
    return {x for x in vals if isinstance(x, str) and x}


def _mailbox_snap(path):
    with open(path, "rb") as f:
        size = f.seek(0, 2)
        f.seek(max(0, size - TAIL_BYTES))
        tail = f.read().splitlines()[1 if size > TAIL_BYTES else 0:]  # 잘린 첫 줄만 버림
    return {"size": size, "names": sorted(set().union(*map(_names, tail)) if tail else ())}


def _listdir(d):
    return sorted(os.listdir(d)) if os.path.isdir(d) else []


def _hil_dir():  # r684: 사람 `!` 실행 번호표 폴더 = ft-hil.sh 의 $D 와 같은 규칙
    return os.path.realpath(os.environ.get("HIL_DIR") or "/tmp")


def _hil_snap(d):  # r684: h<숫자> 최대 번호·개수·이름 — 시험이 실 폴더에 번호표를 쓰면 «늘어난다»
    names = sorted(f for f in _listdir(d) if re.fullmatch(r"h(\d+)", f)
                   and (os.path.exists(os.path.join(d, f)) or os.path.islink(os.path.join(d, f))))
    nums = [int(f[1:]) for f in names]
    return {"dir": d, "max": max(nums, default=0), "count": len(nums), "names": names}


def _hil_plan(p):  # 번호표 본문 첫 줄들 `# ft-hil-entry plan=<계획 파일>`
    try:
        with open(p, "rb") as f:
            m = re.search(r"ft-hil-entry plan=(\S+)", f.read(600).decode("utf-8", "replace"))
    except OSError:
        return None
    return m.group(1) if m else None


def _simulated(plan):  # r684 r2: 계획이 임시 폴더(mktemp) 아래면 «시험 사본» = 누수 · 실 좌석 계획은 <repo>/.fable-team/…
    if not plan:
        return True
    p = os.path.realpath(plan)
    temps = {os.path.realpath(t) for t in ("/tmp", "/var/folders", tempfile.gettempdir())}
    return any(p == t or p.startswith(t + "/") for t in temps)


def _seat_names(path):
    try:
        with open(path) as f:
            d = json.load(f)
    except (OSError, ValueError):
        return set()
    return set(d.get("seats") or {}) if isinstance(d, dict) else set()


def fingerprint(rs):
    fp = {"fail": {}, "warn": {}, "mailbox": {}, "hil": _hil_snap(_hil_dir())}
    for kind, p in rs:
        if kind == "data":
            st = os.path.join(p, ".fable-team", "state")
            for name in _listdir(st):
                q = os.path.join(st, name)
                fp["fail"].update(_tree_sig(q)) if name in FAIL_STATE else fp["warn"].update({q: _sig(q, False)})
        elif kind == "repo":
            ft = os.path.join(p, ".fable-team")
            fp["warn"].update({os.path.join(ft, n): _sig(os.path.join(ft, n), False)
                               for n in _listdir(ft) if n.startswith("seats") and n.endswith(".json")})
        elif os.path.isfile(os.path.join(p, "mailbox.jsonl")):
            fp["mailbox"][os.path.join(p, "mailbox.jsonl")] = _mailbox_snap(os.path.join(p, "mailbox.jsonl"))
    return fp


def _known_names(fp, rs):
    """시험 시작 전 우편함에 나온 이름 + 지금 명부(seats*.json)의 좌석 이름."""
    known = set().union(*(set(s["names"]) for s in fp["mailbox"].values()))
    fts = {os.path.join(p, ".fable-team") for k, p in rs if k == "repo"} | {os.path.dirname(p) for k, p in rs if k == "comm"}
    return known.union(*(_seat_names(os.path.join(ft, n)) for ft in fts for n in _listdir(ft)
                         if n.startswith("seats") and n.endswith(".json")))


def _new_mail(path, snap):
    """시험 시작 뒤 새 줄 [(이름들, 앞 160자)] · 파일이 줄었거나 없으면(회전) None."""
    if not os.path.isfile(path) or os.path.getsize(path) < snap["size"]:
        return None
    with open(path, "rb") as f:
        f.seek(snap["size"])
        return [(_names(raw), raw[:160].decode("utf-8", "replace")) for raw in f.read().splitlines() if raw.strip()]


def check(before):  # (FAIL 줄들, WARN 줄들, 요약)
    rs, fp = before["roots"], before["fp"]
    after = fingerprint(rs)
    fails = [f"실 상태 바뀜: {q}" for q in sorted(set(fp["fail"]) | set(after["fail"])) if fp["fail"].get(q) != after["fail"].get(q)]
    warns = [f"시험 밖 변경일 수 있음: {q}" for q in sorted(set(fp["warn"]) | set(after["warn"])) if fp["warn"].get(q) != after["warn"].get(q)]
    hb, ha = fp.get("hil"), after.get("hil")
    if isinstance(hb, dict) and isinstance(ha, dict):
        # r684 r2: 번호표 폴더는 «전역»(/tmp)이라 동시 실행 좌석의 실 approve-merge 계획도 늘린다
        #   → 계획 경로로 가른다. 시험 사본(tmp 아래) = 누수 FAIL · 실 좌석 계획(<repo>/.fable-team) = WARN 만.
        for name in sorted(set(ha.get("names") or ()) - set(hb.get("names") or ())):
            q = os.path.join(ha["dir"], name)
            plan = _hil_plan(q)
            if _simulated(plan):
                fails.append(f"실 상태 바뀜: {q}")
            else:
                warns.append(f"번호표 늘었으나 실 좌석 계획(동시 실행): {q} ← {plan}")  # 줄어듦(사람 정리)은 FAIL 아님
    known = _known_names(fp, rs)
    for mb, snap in fp["mailbox"].items():
        new = _new_mail(mb, snap)
        if new is None:
            warns.append(f"우편함 줄어듦/없음(회전?): {mb}")
        fails += [f"우편함 가짜 이름 새 줄: {sorted(n - known)} :: {h}" for n, h in (new or []) if n - known]
    summary = ",".join(f"{k}:{p}" for k, p in rs)
    return fails, warns, f"roots={summary} files={len(fp['fail'])}"


def compare(snap_file):
    with open(snap_file) as f:
        before = json.load(f)
    if not before["roots"]:
        print(f"{TAG} PASS 실 루트 없음(cwd={before['cwd']})", file=sys.stderr)
        return 0
    fails, warns, summary = check(before)
    for line in [f"WARN {w}" for w in warns] + [f"FAIL {x}" for x in fails] + ([] if fails else [f"PASS 실 상태 그대로 {summary}"]):
        print(f"{TAG} {line}", file=sys.stderr)
    return 1 if fails else 0


def snap(out, cwd):
    rs = roots(cwd)
    with open(out, "w") as f:
        json.dump({"cwd": cwd, "roots": rs, "fp": fingerprint(rs)}, f)


def _isolate():  # (지문 파일, git 밖 임시 cwd, 자식 env)
    tmp = os.path.realpath(tempfile.mkdtemp(prefix="rsg-"))
    snap_file = os.path.join(tempfile.mkdtemp(prefix="rsg-snap-"), "snap.json")
    snap(snap_file, os.getcwd())
    hil = os.path.join(tmp, "hil")
    os.makedirs(hil, exist_ok=True)  # r684: 기본으로 막는다 — 시험이 진짜 ${HIL_DIR:-/tmp}/h<N> 을 안 쓰게
    return snap_file, tmp, dict(os.environ, RSG_ACTIVE="1", GIT_CEILING_DIRECTORIES=os.path.dirname(tmp), HIL_DIR=hil)


def guard_begin():
    """파이썬 스크립트 시험 맨 위에서 부른다 — 이미 지켜지는 중(RSG_ACTIVE)이면 아무것도 안 함."""
    if os.environ.get("RSG_ACTIVE"):
        return
    snap_file, tmp, env = _isolate()
    rc = subprocess.call([sys.executable, os.path.abspath(sys.argv[0]), *sys.argv[1:]], cwd=tmp, env=env)
    grc = compare(snap_file)
    subprocess.call(["rm", "-rf", tmp, os.path.dirname(snap_file)])
    sys.exit(rc or grc)


pytest = sys.modules.get("pytest")  # pytest 안에서 import 될 때만 픽스처 — CLI(셸 짝)는 pytest 를 싣지 않는다
if pytest is not None:
    @pytest.fixture(scope="module", autouse=True)
    def guard_begin_module():
        """pytest 모듈 하나 = 지문 → git 밖 임시 cwd·RSG_ACTIVE·GIT_CEILING_DIRECTORIES → 끝나면 비교(FAIL = pytest.fail)."""
        if os.environ.get("RSG_ACTIVE"):
            yield
            return
        old_cwd, old_env = os.getcwd(), dict(os.environ)
        snap_file, tmp, env = _isolate()
        os.environ.update(env)
        os.chdir(tmp)
        try:
            yield
        finally:
            os.chdir(old_cwd)
            os.environ.clear(), os.environ.update(old_env)
        rc = compare(snap_file)
        subprocess.call(["rm", "-rf", tmp, os.path.dirname(snap_file)])
        if rc:
            pytest.fail(f"{TAG} FAIL — 시험이 실 상태를 바꿈(위 stderr 줄)")


def main(argv):
    if len(argv) == 5 and argv[0] == "snap" and argv[1] == "--out" and argv[3] == "--cwd":
        return snap(argv[2], argv[4]) or 0
    if len(argv) == 2 and argv[0] == "compare":
        return compare(argv[1])
    print("usage: real_state_guard.py snap --out <파일> --cwd <폴더> | compare <파일>", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
