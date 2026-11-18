"""ft 2.0 keeper 좌석 열기 판독 (r1929) — keeper_next.reconcile 의 launch 갈래. keeper 는 launch.py 를 기다리지 않는다.
읽는 것 = 의도(<work>@<attempt>.intent) · 이어 열기 예약(.intent.resume) · 띄우기 로그(.log) · 띄운 자식 소유(.owner · 의도 전 구간) · 하는 것 = 띄우기 1회(Popen · 대기 0) 또는 판독 1줄.
반환 = None(opened → record 단계) · True(이번 바퀴 끝 · handled 0) · 문자열(«복구 필요» 사유 → 부르는 쪽이 handled).
"""
import importlib.util, os, subprocess, time  # noqa: E401

HERE = os.path.dirname(os.path.abspath(__file__))
FT2, LAUNCH_S = os.path.dirname(os.path.dirname(HERE)), 7   # 띄우기·판독 바깥 호출 상한(ps 1회 · 하드 룰 12)
OPEN_STALE = 900   # r2252 O0 이어 열기 문턱(초) · keeper_settle.OPEN_STALE(r2058 L6) 이 이 값을 쓴다(한 값)
def _load(path, alias):
    spec = importlib.util.spec_from_file_location(alias, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
planner = _load(os.path.join(HERE, "launch_plan.py"), "ft2_keeper_launch_plan")
projection = _load(os.path.join(FT2, "core", "projection.py"), "ft2_keeper_launch_projection")
def ps(k, argv):
    """ps 1회(FT2_KEEPER_PS · LC_ALL=C · 7초) → (rc, stdout)."""
    return k.call(["env", "LC_ALL=C", k.env.get("FT2_KEEPER_PS") or "ps"] + argv, LAUNCH_S)[:2]
def alive(k, row):
    """열기 pid → alive·dead·unknown(launch_plan.pid_state · 판정 못 함 = unknown)."""
    return planner.pid_state(row.get("pid"), row.get("started"), lambda argv: ps(k, argv))
def own(k, child, base):
    """r1929 ⓕ Popen 직후 .owner 원자 예약(tmp→fsync→link) = {child_pid, started(ps 시작 시각 · 못 읽음 = 지금), keeper_pid}."""
    rc, out = ps(k, ["-o", "lstart=", "-p", str(child.pid)])
    try:
        at = time.mktime(time.strptime(" ".join(out.split()), "%a %b %d %H:%M:%S %Y")) if rc == 0 else time.time()
    except ValueError:
        at = time.time()   # 늦은 시각 = 살아 있음 쪽(같은 pid 의 남 판정은 그 뒤 시작만)
    try:
        planner.reserve(base + ".owner", {"child_pid": child.pid, "started": at, "keeper_pid": os.getpid()})
    except OSError:
        pass
def busy(k, team, nh, kind, text):
    """이번 바퀴 끝 · handled 0 · 나노 정원에 «여는 중» 1칸으로 센다(keeper_next.gates)."""
    k.cache.setdefault("launching", set()).add(nh)
    return k.log(kind, team, "%s %s" % (nh, text)) or True
def spawn(k, team, nh, argv, base, what):
    """launch.py 를 따로 띄운다(start_new_session · stdout·stderr = 로그 덧붙임 · 대기 0) · 띄우기 실패 = «복구 필요» · 처음 열기만 .owner."""
    log = base + ".log"
    try:
        os.makedirs(os.path.dirname(log), exist_ok=True)
        with open(log, "a", encoding="utf-8") as fh:
            child = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=fh, stderr=fh, env=k.env, cwd=k.root, start_new_session=True)
    except OSError as exc:
        return "띄우기 실패 %s" % str(exc)[:80]
    k.cache.setdefault("spawned", []).append(child)
    own(k, child, base) if what == "열기" else None
    return busy(k, team, nh, "LAUNCHING", "%s %s · 대기 0" % (what, os.path.basename(log)))
def last_line(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return (fh.read().strip().splitlines() or [""])[-1]
    except OSError:
        return ""
def resumable(k, got):
    """r2252 O0(DA#23) «이어 열 수 있음» 한 판정 = intent failed ∧ resumable checkout ∧ intent at 부터 OPEN_STALE 안쪽 · 시각 못 읽음 = 거짓.
    launching(O2)·keeper_settle.settle_nano(O3) 가 같이 부른다 · 문턱을 넘으면 두 곳 모두 지금 길(«실패 …» · failed_end)."""
    if got.get("state") != "failed" or got.get("resumable") != "checkout":
        return False
    try:
        return k.now() - time.mktime(time.strptime(str(got.get("at")), "%Y-%m-%dT%H:%M:%S")) < OPEN_STALE
    except (ValueError, OverflowError):
        return False
def reserved(k, base):
    """r2252 O2·O3 이어 열기 예약(.intent.resume) = None 없음 · 그 밖 = 예약 pid 판정(alive·dead·unknown · launch.py reserve 가 쓴 pid·started)."""
    return alive(k, k.read_json(base + ".intent.resume")) if os.path.exists(base + ".intent.resume") else None
def launching(k, team, stem, attempt, nh, argv):
    """의도 판독 → ⓐ 없음 = .owner 없음 띄우기 · 있음 = ⓖ 자식 판정 ⓑ 열기 중 ⓒ opened ⓓ failed ⓔ 끊긴 열기 = 이어 열기 1회."""
    if not argv or not attempt:
        return "대상 못 정함" if not argv else "전달 attempt 없음"
    base = os.path.join(projection.runtime_path(k.root, team), "launch", "%s@%s" % (stem, attempt))
    got = k.read_json(base + ".intent")
    if got.get("state") == "opened":
        return None
    if got.get("state") == "failed":
        seen = reserved(k, base) if resumable(k, got) else "dead"   # r2252 O2 checkout 시간 초과 = attempt 당 이어 열기 1회(r2058 L3 예외 하나)
        if seen is None:
            return spawn(k, team, nh, argv + ["--resume"], base, "이어 열기")
        if seen != "dead":   # 예약 pid 살아 있음·판정 못 함 = again 길이 남은 묶음을 도는 중(intent 는 failed 그대로 · DA#22)
            return busy(k, team, nh, "LAUNCH-WAIT", "이어 열기 중")
        return "실패 %s %s" % (got.get("step"), str(got.get("reason"))[:60])
    if not os.path.exists(base + ".intent"):
        if not os.path.exists(base + ".owner"):
            return spawn(k, team, nh, argv, base, "열기")
        row = k.read_json(base + ".owner")
        seen = alive(k, {"pid": row.get("child_pid"), "started": row.get("started")})
        if seen == "dead":   # ⓖ 죽음 확인(ESRCH·같은 pid 다른 시작) = «복구 필요» · 살아 있음·판정 못 함 = 손 0(닫힌 쪽)
            return "intent 전 종료 %s" % last_line(base + ".log")[:80]
        return busy(k, team, nh, "LAUNCH-WAIT", "열기 중 · 의도 전")
    if got.get("state") not in ("claiming", "opening") or alive(k, got) != "dead":   # 판독 못 함·살아 있음 = 손 0(닫힌 쪽)
        return busy(k, team, nh, "LAUNCH-WAIT", "열기 중 %s" % got.get("state"))
    if os.path.exists(base + ".intent.resume"):
        return busy(k, team, nh, "LAUNCH-WAIT", "이어 열기 중") if alive(k, k.read_json(base + ".intent.resume")) != "dead" else "복구 1회 소진"
    if got.get("state") != "opening":
        return "끊긴 열기 · 확인 단계(%s)" % got.get("state")
    return spawn(k, team, nh, argv + ["--resume"], base, "이어 열기")
