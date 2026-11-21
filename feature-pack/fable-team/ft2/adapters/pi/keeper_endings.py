"""ft 2.0 keeper 끝 판정 (r1960 · DA APPROVE-DESIGN #301612) — ① pr_landed: 착지 줄 없음 → 가지 nano/<work> merged PR 정확히 1개 ∧ mergeCommit
허용 base 조상 ∧ pre_attempt(HEAD 조상 단독·추측 0) ② ending: 우선 ref 단일 카드 완성후·아카이브 · «## 상태» 마지막 유효 항목 머리(refuse 0)
③ intent 대체 ④ unsure 재깨움 1회 → [크리티컬] 1통/일 ⑤ orphans: 스냅샷 «뒤» journal 새로 읽기 · launch intent 근거 ∧ 끝 ∧ 가드 → kill 1.
r2319(nano) — journal 판독에서 닫힌 segment 는 디스크 캐시(keeper 상태 폴더 · 팀마다 1파일)를 쓰고
활성 파일만 매번 새로 읽는다. 캐시 지문 = 닫힌 목록 (이름 · size · mtime_ns) · 판독 전·후 두 번 재서
같을 때만 씀 · 캐시 없음·깨짐·쓰기 실패 = 지금과 같은 전부 판독(예외 0) · 1초 넘으면 ROWS-SLOW 1줄.
r2346(nano) — 그 ROWS-SLOW 줄 끝에 load+active 구간의 파이썬 CPU 초를 %.2f 로 붙인다(문턱·앞 글자 그대로).
r2362(nano) — load 한 칸을 세 구간 초로 나눠 같은 줄 끝에 붙인다: proj(projection 가져오기 + Journal 만들기) ·
key(닫힌 segment stat) · get(닫힌 행 읽기 — 캐시 hit = json 1개 · miss = 닫힌 전부 판독) · 세 칸 합 = load.
"""
import glob, importlib.util, json, os, re, time  # noqa: E401
HERE = os.path.dirname(os.path.abspath(__file__))
ANC_S = 7   # r2022 착지 조상 확인(merge-base --is-ancestor) 1회 7초 · 재시도 0 · keeper_land 도 이 값
GH_S, BASES, DONE, HEADS = 7, ("main", "ops/main-base"), ("완성후", "아카이브"), (("중단:", "suspended"), ("대체:", "superseded"), ("거절:", "superseded"))
SETLINE = re.compile(r"세트:\s*[0-9a-f]{40}\s*·\s*시험:.+\src=0\s*·\s*이슈:\s*0\s*$")   # r2088 D2 ④ scope_code_check 정규식 그대로
ORPHAN, REPO, SHA = re.compile(r"byz-([a-z0-9]+)-nano-(.+)#\d+"), re.compile(r"github\.com[:/]([^/]+/[^/]+?)(?:\.git)?/?$"), re.compile(r"[0-9a-f]{40}")
_MOD = {}
def _mod(name, path):
    if name not in _MOD:   # keeper_land 는 늦게 읽는다(keeper_land 가 이 파일을 읽으므로 순환 0)
        _MOD[name] = importlib.util.module_from_spec(spec := importlib.util.spec_from_file_location("ft2_keeper_endings_" + name, path))
        spec.loader.exec_module(_MOD[name])
    return _MOD[name]
def _proj():
    return _mod("projection", os.path.join(os.path.dirname(os.path.dirname(HERE)), "core", "projection.py"))
def held(k, team, key, text):
    """같은 사유 1회 UNKNOWN 1줄(held 키) · 반환 None · r2055 HELD 폐지."""
    if k.state["held"].get(key) != text:
        k.state["held"][key] = text
        k.unknown_line(team, "-", "held", text)   # r2055 UNKNOWN = [긴급]
ROWS_CACHE, ROWS_SLOW_S, ROWS_V = "journal-rows", 1.0, 1   # r2319 C6 캐시 폴더 · C7 문턱 · 캐시 꼴 판
NOLEASE_IDLE, NOLEASE_ON = 300, "1"   # r2400 K1·K4 문턱(초 · desk#236 #364526) · 스위치 켬 값(그 밖 = «예정» 줄만)

def no_lease_idle(k):
    """r2400 K1 문턱 초 FT2_NOLEASE_IDLE — env > 루트 .fable-team > ~/.claude/fable-team > 샘플(r1860 순서) · 못 읽음 = 300."""
    val = thresh(k, "FT2_NOLEASE_IDLE", str(NOLEASE_IDLE))
    return int(val) if val.isascii() and val.isdigit() else NOLEASE_IDLE

def no_lease_on(k):
    """r2400 K4 권한 스위치 FT2_NOLEASE_CLOSE — 정확히 «1» 일 때만 켬(«true»·«yes» = 끔) · 기본 = 샘플 값(끔)."""
    return thresh(k, "FT2_NOLEASE_CLOSE", "") == NOLEASE_ON

def thresh(k, name, default):
    """문턱 한 값 — env > 루트 thresholds.env > ~/.claude thresholds.env > 이 폴더 샘플 · 없음 = default(바퀴 캐시)."""
    got = k.cache.setdefault("@round", {})
    if ("thresh", name) not in got:
        home = k.env.get("HOME") or os.path.expanduser("~")
        files = (os.path.join(k.root, ".fable-team", "thresholds.env"),
                 os.path.join(home, ".claude", "fable-team", "thresholds.env"), os.path.join(HERE, "thresholds.env.sample"))
        got[("thresh", name)] = (k.env.get(name) or "").strip() or next((x for x in (thresh_one(p, name) for p in files) if x), default)
    return got[("thresh", name)]

def thresh_one(path, name):
    """thresholds 파일 1개의 그 키 값 · 파일 없음·못 읽음 = ""(예외 0)."""
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return next((line.split("=", 1)[1].strip() for line in fh if line.startswith(name + "=")), "")
    except OSError:
        return ""

def pi_dir(k, tree):
    """Pi 세션 폴더 경로(`--<cwd>--` · 쓰레기 이음 그대로) · cwd 없음 = ""."""
    sessions = k.env.get("FT2_PI_SESSIONS") or os.path.expanduser("~/.pi/agent/sessions")
    return os.path.join(sessions, "--%s--" % tree.strip("/").replace("/", "-")) if tree else ""

def pi_files(k, tree):
    """r2400 intent worktree 폴더의 Pi jsonl 전부(glob 이음 그대로) · 폴더 없음 = []."""
    folder = pi_dir(k, tree)
    return glob.glob(os.path.join(glob.escape(folder), "*.jsonl")) if folder else []

def no_lease(k, seat, it, ok):
    """r2400 K1 근거 없는 석 판정 — «그 팀 최신 dispatch holder ∨ 300초 안 활동» 의 둘째 근거만 본다(첫째는 고아 조건이 이미 뺐다).
    ok(자동 개설 근거) 참 = intent worktree 폴더 최신 jsonl 나이 · 거짓(손 개설 석) = pane 폴더(seat_turn · 누구 것인지 못 가름 = 근거 있음).
    반환 = (근거 없음, 무활동 초, Pi jsonl 개수) · 못 잼 = (False, None, 0)."""
    idle = no_lease_idle(k)
    if ok:
        files = pi_files(k, it.get("worktree") or "")
        if not files:
            return False, None, 0
        age = k.now() - max(map(os.path.getmtime, files))
        return age >= idle, int(age), len(files)
    age, _stop = k.seat_turn(seat)   # r2135 L1 장기 좌석 길 재사용(폴더 1개 = 그 나이 · 모호·jsonl 0 = None)
    return (age is not None and age >= idle), (None if age is None else int(age)), 0

def held_day(k, team, key, kind, text):
    """같은 좌석·같은 줄 하루 1줄(HELD-NOLEASE · 예정) — keeper 상태 파일 기억 = 재기동해도 그날 반복 0 · 반환 None."""
    book, day = k.state.setdefault("held", {}), k.stamp()[:10]
    if book.get(key) != day:
        book[key] = day
        k.log(kind, team, text)

def resume_put(k, seat, it):
    """r2400 K2 재개 기록 — Pi jsonl 정확히 1개일 때만 seat-resume/<좌석>.json(tmp → replace) · 검증은 파일을 다시 읽어 resume_ok.
    반환 "" = 통과 · 그 밖 = 사유(기록 0 · kill 0)."""
    files = pi_files(k, it.get("worktree") or "")
    if len(files) != 1:
        return "Pi jsonl %d개" % len(files)
    cwd, log = it.get("worktree") or "", files[0]
    uuid = os.path.basename(log)[:-len(".jsonl")].rpartition("_")[2]
    base = k.env.get("FT2_SEAT_RESUME_DIR") or os.path.join(k.env.get("HOME") or os.path.expanduser("~"), ".claude", "state", "seat-resume")
    path, old = os.path.join(base, seat + ".json"), k.read_json(os.path.join(base, seat + ".json"))
    if not (old.get("name") == seat and old.get("uuid") == uuid):   # 같은 name·uuid = 다시 쓰기 0
        rec = {"name": seat, "engine": "pi", "uuid": uuid, "jsonl": log, "cwd": cwd, "no_lease": True, "at": k.stamp(),
               "binding": {"source": "ft2-keeper-no-lease", "session": seat, "uuid": uuid, "jsonl": log}}
        try:
            os.makedirs(base, exist_ok=True)
            with open(path + ".tmp", "w", encoding="utf-8") as fh:
                json.dump(rec, fh, ensure_ascii=False)
            os.replace(path + ".tmp", path)
        except OSError as exc:
            return "쓰기 %s" % type(exc).__name__
    return "" if resume_ok(k, seat, k.read_json(path)) else "검증 실패"

def resume_ok(k, seat, doc):
    """재개 기록 검증 — 이름 같음 · codex 아님 · jsonl 실재 ∧ 이름 끝 uuid.jsonl ∧ 담긴 폴더 = cwd 세션 폴더(keeper_settle.resume_ok 에서 roots 검사만 뺀 것)."""
    cwd, uuid, log = str(doc.get("cwd") or ""), str(doc.get("uuid") or ""), str(doc.get("jsonl") or "")
    return (doc.get("name") == seat and bool(uuid) and doc.get("engine") != "codex" and bool(cwd) and os.path.isfile(log)
            and os.path.basename(log).endswith(uuid + ".jsonl") and os.path.dirname(os.path.realpath(log)) == os.path.realpath(pi_dir(k, cwd)))

def quiet(k, team, work, seat, it, ok):
    """r2400 K1 쉼 판정 — 한 판독 쉼(k.look · idle_s = NOLEASE_IDLE) ∧ pane Working 0(k.idle) ∧ attached free ∧ holder 그대로.
    keeper 가 연 석 = intent worktree jsonl 나이 · 손 개설 석 = pane 폴더 나이(seat_turn · **읽기만** · 기록 근거로는 안 쓴다).
    거짓 = 지금 줄 그대로(닫기 0 · 관문에 안 셈) · 판정 줄은 look·idle·attached 가 쓴다."""
    age, stop = k.pi_turn(it) if ok else k.seat_turn(seat)
    if k.look(team, work, "-", seat, age, stop, idle_s=no_lease_idle(k)) != "REST":
        return False
    att = k.attached(seat)
    if att != "free":   # 사람 화면 = 닫기 0(r1839 A1 · ②)
        if att.startswith("attached "):
            k.verdict(team, work, seat, "WORKING", "attached", "%s · 닫기 0" % att)
        else:
            k.unknown_seat(team, work, "-", seat, "attached-unknown", "판정 불가 attached(%s) · kill 0" % att[10:])
        return False
    if not k.idle(team, work, seat):   # kill 직전 pane 끝 12줄 Working 없음(② pane 글자 · 판정 줄은 idle 이 쓴다)
        return False
    return seat not in {h for _, h in (latest(k, team) or {0: (0, seat)}).values()}   # ⑦e 읽는 사이 holder 바뀜·판독 실패 = 닫기 0

def unleased(k, team, work, seat, it, lease, ok, why=""):
    """r2400 K2~K6 근거 없는 석 1개 처리 — K1(quiet) 이미 참일 때만 온다.
    손 개설 = HELD-NOLEASE(K3) · 정지 = 예정(K6) · 스위치 끔 = 예정(K4) → 재개 기록(K2) → kill 1 → «CLOSED-NOLEASE». 반환 = 로그 낱말."""
    age = lease[1]
    if not ok:   # K3 손 개설 석 = 닫지 않는다 · 재개 기록 0 · kill 0
        return held_day(k, team, "nolease|" + seat, "HELD-NOLEASE",
                        "%s idle=%s — 손 개설 · 닫는 손 = planner 수동 닫기%s" % (seat, age, " · " + why if why else ""))
    if k.halt:   # K6 정지 중 = 예정 줄만(kill·기록 0 · 스위치 무관)
        return held_day(k, team, "nolease-halt|" + seat, "예정", "CLOSED-NOLEASE %s idle=%s — ALL_STOP 중 · kill 0 · 재개 기록 0" % (seat, age))
    if not no_lease_on(k):   # K4 권한 스위치(오빠 «네» · hil.md 행 전 = 켜지 않는다)
        return held_day(k, team, "nolease-off|" + seat, "예정", "CLOSED-NOLEASE %s idle=%s — 스위치 끔 · kill 0 · 재개 기록 0" % (seat, age))
    why = resume_put(k, seat, it)   # K2 재개 기록 먼저(실패 = 기록 0 · kill 0 · ③)
    if why:
        return k.unknown_seat(team, work, "-", seat, "no-lease-resume", "%s · 재개 기록 0 · kill 0" % why)
    k.call([k.tmux, "kill-session", "-t", "=" + seat])
    gone = k.probe(seat)
    if gone != "absent":
        return k.unknown_seat(team, work, "-", seat, "kill-failed", "재개 기록 1 · 부재 확인 없음(%s)" % gone)
    return k.log("CLOSED-NOLEASE", team, "%s idle=%s · 재개 기록 1 · kill 1" % (seat, age))

def _cpu():   # r2346 — 이 프로세스가 쓴 CPU 초(쓰레드 시계) · 가짜 시계 대역에 없으면 0.0
    fn = getattr(time, "thread_time", None)
    return fn() if fn else 0.0

def _rows_cache(k, team):   # 캐시 파일 1개 = keeper 상태 폴더 아래(journal runtime 폴더 쓰기 0 · C6 · 하드 룰 19)
    base = getattr(k, "dir", None) or os.path.join(k.root, ".fable-team", "state", "ft2-keeper")
    return os.path.join(base, ROWS_CACHE, team + ".json")

def _rows_key(j):   # 닫힌 segment 지문 [(N, 이름, size, mtime_ns)] — 이름·size·mtime 셋 다 (C1·C2)
    out = []
    for n, path in j.closed():
        st = os.stat(path)
        out.append([n, os.path.basename(path), st.st_size, st.st_mtime_ns])
    return out

def _rows_get(path, key):   # 캐시 행 · 없음·깨짐·지문 다름 = None → 전부 판독 (C3)
    try:
        with open(path, encoding="utf-8") as fh:
            got = json.load(fh)
        rows = got["rows"]
        if (got.get("v") == ROWS_V and got.get("closed") == key and isinstance(rows, list)
                and all(isinstance(r, dict) and isinstance(r.get("seq"), int) for r in rows)):
            return rows
    except (OSError, ValueError, KeyError, TypeError):
        pass
    return None

def _rows_put(path, key, rows):   # 원자 쓰기 tmp → replace · 실패 = 판독 결과 그대로(예외 0 · C3)
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path + ".tmp", "w", encoding="utf-8") as fh:
            json.dump({"v": ROWS_V, "closed": key, "rows": rows}, fh, ensure_ascii=False)
        os.replace(path + ".tmp", path)
    except OSError:
        pass

def _rows_join(closed, active, err):   # 닫힌 + 활성 이음 — seq 역행·중복 = CorruptStateError (C5)
    out = []
    for rec in list(closed) + list(active):
        if out and rec["seq"] <= out[-1]["seq"]:
            raise err("journal seq 역행·중복: %r <= %r" % (rec["seq"], out[-1]["seq"]))
        out.append(rec)
    return out

def _rows(k, team):
    """journal 판독 — 닫힌 segment = 캐시 · 활성 = 매번(r2319 C1~C8) · 못 읽음 = None(판독 실패 = 대체·고아 닫기 0)."""
    t0, c0 = time.monotonic(), _cpu()   # r2346 c0 = load+active 구간 CPU 초의 시작
    try:
        proj = _proj()
        j = proj.journal.Journal(proj.runtime_path(k.root, team), rec=proj.record)
        ta = time.monotonic()   # r2362 proj 칸 끝(load 첫 구간)
        key, path = _rows_key(j), _rows_cache(k, team)
        tb = time.monotonic()   # r2362 key 칸 끝(load 둘째 구간)
        closed = _rows_get(path, key) if key else None   # C1·C2·C3
        hit = closed is not None
        if not hit:   # 캐시 없음·틀림·깨짐 = 닫힌 쪽 전부 판독(부분 갱신 0 · 단순)
            closed = [rec for _n, seg in j.closed() for rec in j._records_of(seg)]
        t1 = time.monotonic()   # r2362 get 칸 끝(load 셋째 구간 · 세 칸 합 = load)
        active = j._records_of(j.active_path) if os.path.exists(j.active_path) else []   # 활성은 매번 (C1)
        t2 = time.monotonic()
        spent = _cpu() - c0   # r2346 — load+active 구간 파이썬 CPU 초(이음·캐시 쓰기 앞)
        rows = _rows_join(closed, active, j.rec.CorruptStateError)   # C5 이음 검사
        if key and not hit and _rows_key(j) == key:   # C8 판독 사이 회전 = 캐시 쓰기 0
            _rows_put(path, key, closed)
    except (OSError, ValueError):   # C3·C4 — 캐시 탓도 판독 실패도 지금과 같은 None
        return None
    if t2 - t0 >= ROWS_SLOW_S:   # C7 효과 가림 — 1초 넘을 때만 1줄
        k.log("ROWS-SLOW", team, "cache=%s load=%.2f active=%.2f n=%d cpu=%.2f" % ("hit" if hit else ("miss" if key else "none"), t1 - t0, t2 - t1, len(rows), spent)
              + " proj=%.2f key=%.2f get=%.2f" % (ta - t0, tb - ta, t1 - tb))   # r2362 load 3칸 초(합 = load)
    return rows
def latest(k, team):   # {work: (attempt, holder)} 최신 dispatch · 못 읽음 = None
    rows = _rows(k, team)
    return None if rows is None else {r["work"]: (r.get("attempt"), r.get("holder")) for r in rows if r.get("kind") == "dispatch" and r.get("work")}
def intents(k, team, pattern="*"):
    for path in sorted(glob.glob(os.path.join(glob.escape(os.path.join(_proj().runtime_path(k.root, team), "launch")), pattern + "@*.intent"))):
        work, _, attempt = os.path.basename(path)[:-len(".intent")].rpartition("@")
        yield work, attempt, k.read_json(path)
def intent(k, team, work, attempt, holder):
    """③ 그 attempt intent · 없으면 같은 work·holder·opened ∧ journal 에서 그 holder 에 dispatch 된 attempt 의 최신 1개(close·pre_attempt 공용 · DA R1 #301944)."""
    got = k.read_json(os.path.join(_proj().runtime_path(k.root, team), "launch", "%s@%s.intent" % (work, attempt)))
    if got.get("state") == "opened" and got.get("FT2_HOLDER"):
        return got
    sent = {r.get("attempt") for r in _rows(k, team) or () if r.get("kind") == "dispatch" and r.get("work") == work and r.get("holder") == holder}
    rows = [r for _, a, r in intents(k, team, glob.escape(work)) if a in sent and r.get("state") == "opened" and r.get("FT2_HOLDER") == holder]
    return max(rows, key=lambda r: str(r.get("at") or ""), default={})
def _prs(k, repo, branch):
    rc, out, _ = k.call([k.env.get("FT2_GH") or "gh", "pr", "list", "-R", repo, "--head", branch, "--state", "merged",
                         "--json", "number,mergeCommit,baseRefName"], GH_S, retry=1)
    try:
        return json.loads(out) if rc == 0 else None
    except ValueError:
        return None
def _common(k, repo):   # git common-dir(clone·linked worktree 는 remote-tracking ref 공유) · 못 읽음 = 경로 그대로
    return os.path.realpath(k.git(repo, "rev-parse", "--path-format=absolute", "--git-common-dir")[1].strip() or repo)
def pr_landed(k, team, work):
    """① (mergeCommit, 근거 ref, "") · 근거 못 채움 = (None, None, "착지 줄 없음") · 옛 착지 = (None, None, 사유)."""
    none = (None, None, "착지 줄 없음")
    attempt, holder = (latest(k, team) or {}).get(work, (None, None))
    it = intent(k, team, work, attempt, holder) if attempt else {}
    tree = it.get("worktree") or ""
    if not os.path.isdir(tree) or k.git(tree, "rev-parse", "--abbrev-ref", "HEAD")[1].strip() != "nano/" + work:
        return none
    if bad := [r for r in sorted(getattr(k, "stale", ())) if _common(k, r) == _common(k, tree)]:   # DA R2 #302302 — 낡은 리포 ref = 조상 검사 0
        return None, None, "판정 불가 · %s fetch 실패" % bad[0]
    url = k.git(tree, "config", "--get", "remote.origin.url")[1].strip()
    prs = _prs(k, REPO.search(url).group(1) if REPO.search(url) else url, "nano/" + work)
    pr = prs[0] if isinstance(prs, list) and len(prs) == 1 and isinstance(prs[0], dict) else {}
    sha, base = str((pr.get("mergeCommit") or {}).get("oid") or ""), pr.get("baseRefName")
    if not SHA.fullmatch(sha) or base not in BASES:
        return none
    if (rc := k.git(tree, "merge-base", "--is-ancestor", sha, "origin/" + base, timeout=ANC_S)[0]) != 0:
        return none if rc == 1 else (None, None, "판정 불가 · PR 착지 조상 git rc %s" % rc)   # r2022
    if old := k.pre_attempt(team, work, tree, sha, it):
        return None, None, old
    k.notify(team, "%s|noline|%s|%s" % (k.stamp()[:10], team, work), "[줄 보완] ft2 keeper %s 카드 착지 줄 없음 · PR #%s 병합 %s — 카드에 «- 착지: %s» 보완(keeper 카드 쓰기 0)" % (work, pr.get("number"), sha[:10], sha))
    return sha, "origin/%s · 착지 줄 없음 · PR #%s 병합" % (base, pr.get("number")), ""
def evidence_notice(k, team, work):
    """r2088 done 갈래 — OPEN PR 1개 ∧ 카드 ref 마지막 «세트:» 줄 D2 ④ 꼴 아님 → 받는 곳 첫 값에 묶음 0 · 1통/일 · 못 읽음 = 판정 불가 1줄 · 쓰기 0."""
    key, (attempt, holder) = "%s|noset|%s|%s" % (k.stamp()[:10], team, work), (latest(k, team) or {}).get(work, (None, None))
    tree = "" if team in k.skip or k.blocked(key) or not attempt else intent(k, team, work, attempt, holder).get("worktree") or ""
    if not os.path.isdir(tree):
        return None
    (brc, branch, _), (urc, url, _) = k.git(tree, "rev-parse", "--abbrev-ref", "HEAD"), k.git(tree, "config", "--get", "remote.origin.url")
    if brc != 0 or urc != 0 or not url.strip():   # DA HOLD #314896 — 못 읽음(rc) ≠ 다른 가지(정상 결과)
        return k.log("판정 불가", team, "%s 증거 줄 안내 0통 · git rev-parse rc %s · config remote rc %s" % (work, brc, urc))
    if branch.strip() != "nano/" + work:
        return None
    url, (cards, mapped) = url.strip(), k.resolve_card(team, work)
    cards = [] if isinstance(cards, str) else [(r, p) for r, p in cards if mapped or os.path.basename(p) == work + ".md"] or [   # landing F1 이름 고르기
        (r, p) for r, p in cards if os.path.basename(p).startswith(work + "-") and p.endswith(".md")]
    rc, out, _ = k.call([k.env.get("FT2_GH") or "gh", "pr", "list", "-R", REPO.search(url).group(1) if REPO.search(url) else url, "--head", "nano/" + work,
                         "--state", "open", "--limit", "2", "--json", "number,headRefOid"], GH_S, retry=1)
    ref = next((r for r in _mod("land", os.path.join(HERE, "keeper_land.py")).REFS if r in dict(cards)), None)
    paths = sorted({p for r, p in cards if r == ref}) if ref else []   # 우선 ref 하나 · 그 ref 에 2장↑ = 판독 실패(추측 0)
    crc, body, _ = k.git(k.root, "show", "%s:%s" % (ref, paths[0])) if len(paths) == 1 else (None, "", "")
    try:
        prs = json.loads(out) if rc == 0 else None
    except ValueError:
        prs = None
    if crc != 0 or not isinstance(prs, list) or not all(isinstance(p, dict) and SHA.fullmatch(str(p.get("headRefOid"))) for p in prs):
        return k.log("판정 불가", team, "%s 증거 줄 안내 0통 · %s" % (work, "카드 ref 판독 실패" if crc != 0 else "gh rc %s" % rc))
    if len(prs) != 1 or SETLINE.search(([x for x in body.splitlines() if "세트:" in x] or [""])[-1]):
        return None
    to, num, head = k.recipients(team)[0], prs[0].get("number"), prs[0]["headRefOid"]
    text = "[줄 보완] ft2 keeper %s 카드 증거 줄 없음 · PR #%s head %s — D2 좌석이 `bash ft-card-evidence.sh --card %s --set %s --pr %s --test \"<나노 보고 시험 줄> rc=0\"` 1회(keeper 카드 쓰기 0)" % (work, num, head[:10], work, head, num)
    if to and (k.stopping() or not k.budget(team)):   # E5 상한 밖·R8 미룸 = 지문 0 · 다음 바퀴
        return None
    return k.finish(team, key, to, *(k.send(to, text) if to else ("받는 곳 없음", "")), text)
def _cards(k, team, ref):
    """우선 ref 의 팀 폴더 indices 아래 .md 전부(단계 5 · 아카이브 하위 폴더 포함) · 판독 실패 = None · 바퀴 안 캐시."""
    if ("endings", team, ref) not in k.cache:
        land, names = _mod("land", os.path.join(HERE, "keeper_land.py")), []
        rc, md, _ = k.git(k.root, "show", ref + ":design/TEAMS.md")
        row = land.team_row(md, team) if rc == 0 else None
        for folder in land.folders(row[1]) if row else ():
            rc, out, _ = k.git(k.root, "ls-tree", "-r", "--name-only", ref, "--", folder + "/indices")
            names = names + [(folder, p) for p in out.splitlines()] if rc == 0 and names is not None else None
        k.cache[("endings", team, ref)] = names if row else None
    return k.cache[("endings", team, ref)]
def _head(body):
    """«## 상태» 절 마지막 유효 항목(맨 줄 «중단:» 포함)의 머리 → (결과, 근거) | None."""
    part = re.split(r"^## 상태[ \t]*$", body, maxsplit=1, flags=re.M)
    rows = [x.strip() for x in re.split(r"^## ", part[1], maxsplit=1, flags=re.M)[0].splitlines() if x.strip()] if len(part) == 2 else []
    last = re.sub(r"^\d{4}-\d{2}-\d{2}[^—]*—\s*", "", re.sub(r"^-\s*", "", rows[-1])) if rows else ""
    return next(((kind, "상태 " + last[:60]) for head, kind in HEADS if last.startswith(head)), None)
def ending(k, team, work, seat=None):
    """② landed 아닌 끝 → (suspended|superseded|empty, 근거) | None · 우선 ref 에 후보 2개↑·판독 실패 = None(추측 0) · r1972 empty = seat(B2 holder) 줄 때만."""
    got = _card_end(k, team, work)
    return None if got is False else got or (seat and _empty(k, team, work, seat)) or None
def _empty(k, team, work, seat):
    """r1972 ⓐ 원장 done ⓑ dispatch holder == seat ⓒ base_sha..HEAD 0 ⓓ status 0줄(untracked 포함) ⓔ nano/<work> OPEN 0 ∧ MERGED 0(상태별 limit 1 조회 · 잘린 목록을 전체로 쓰지 않음) → (empty, 근거) · 그 밖·판독 실패 = None."""
    attempt, holder = (latest(k, team) or {}).get(work, (None, None))
    if not ((k.project(k.root, team).get("works") or {}).get(work) or {}).get("done") or holder != seat:
        return None
    it = intent(k, team, work, attempt, holder)
    tree, base = it.get("worktree") or "", str(it.get("base_sha") or "")
    if not os.path.isdir(tree) or not SHA.fullmatch(base) or k.git(tree, "rev-list", "--count", base + "..HEAD")[:2] != (0, "0\n"):
        return None
    if k.git(tree, "status", "--porcelain", "--untracked-files=all")[:2] != (0, ""):
        return None
    url = k.git(tree, "config", "--get", "remote.origin.url")[1].strip()
    seen = {}
    for state, n in (("open", "1"), ("merged", "1"), ("closed", "30")):   # DA HOLD R1 — 안전 = open·merged 존재(상태 필터 · limit 1) · closed = 근거 출력만
        rc, out, _ = k.call([k.env.get("FT2_GH") or "gh", "pr", "list", "-R", REPO.search(url).group(1) if REPO.search(url) else url, "--head", "nano/" + work,
                             "--state", state, "--limit", n, "--json", "number"], GH_S, retry=1)
        try:
            seen[state] = json.loads(out) if rc == 0 else None
        except ValueError:
            return None
        if not isinstance(seen[state], list) or (state != "closed" and seen[state]):
            return None
    return "empty", "done · 커밋 0 · 변경 0 · PR %s" % ("닫힘 " + ",".join("#%s" % p.get("number") for p in seen["closed"] if isinstance(p, dict)) if seen["closed"] else "없음")
def _card_end(k, team, work):
    """카드 끝 → (결과, 근거) | None(끝 아님) | False(판독 실패·후보 충돌)."""
    if k.resolve_card(team, work)[1]:   # r2055 R4 짝 표 먼저(landing 과 같은 순서) · 판정 불가 = _resolved_end 값 그대로
        return _resolved_end(k, team, work)
    land = _mod("land", os.path.join(HERE, "keeper_land.py"))
    for ref in land.REFS:
        if (names := _cards(k, team, ref)) is None:
            return False
        hits = [(f, p) for f, p in names if p.endswith(".md") and p[len(f) + 9:].split("/")[0] in land.STAGES + DONE
                and (os.path.basename(p) == work + ".md" or os.path.basename(p).startswith(work + "-"))]
        hits = [h for h in hits if os.path.basename(h[1]) == work + ".md"] or hits
        if len(hits) > 1:
            return False
        if hits:
            stage = hits[0][1][len(hits[0][0]) + 9:].split("/")[0]
            if stage in DONE:
                return "superseded", "카드 %s/" % stage
            rc, body, _ = k.git(k.root, "show", "%s:%s" % (ref, hits[0][1]))
            if rc != 0 or (got := _head(body)) or stage != "완성" or re.search(r"^- 착지: ", body, re.M):
                return False if rc != 0 else got   # r2296 A1·A2 — 완성 · 착지 줄 0 · _head None 일 때만 아래
            done = re.findall(r"^- 완료: .*$", body, re.M)
            return ("superseded", "카드 완성 · ALREADY") if done and "ALREADY" in done[-1] else held(k, team, "end-done-noland:" + work, "%s 완성 · 착지 줄 0 · 끝 판독 불가" % work)
    return _resolved_end(k, team, work)
def _resolved_end(k, team, work):
    """r2055 A1·A7 §3b — 팀 폴더 후보 0 = landing 과 같은 resolve_card(짝 표 → 팀 폴더 → 발주 본문) 카드의 «## 상태» 머리 · 우선 ref 에 2장↑ = False · 0 = None."""
    cards, mapped = k.resolve_card(team, work)
    if isinstance(cards, str):   # r2177 R11 — 짝 표 1줄의 카드가 진행·대기·완성에 없을 때만 완성후·아카이브를 찾는다
        return _moved_end(k, mapped[0]) if mapped and len(mapped) == 1 and cards.startswith("판정 불가 · 짝 표 카드 없음") else None
    land = _mod("land", os.path.join(HERE, "keeper_land.py"))
    for ref in land.REFS:
        paths = sorted({p for r, p in cards if r == ref})
        if len(paths) > 1:
            return False
        if paths:
            rc, body, _ = k.git(k.root, "show", "%s:%s" % (ref, paths[0]))
            return _head(body) if rc == 0 else False
    return None
def _moved_end(k, path):
    """r2177 R11 — 짝 표 경로와 같은 indices 의 완성후/·아카이브/(월 폴더 포함) 같은 파일 이름 · 가지 순서 · 가지마다 ls-tree 1회.
    처음 나온 가지에 1개 = superseded · 2개↑ = False · 두 가지 0 = None · ls-tree 실패 = False."""
    land = _mod("land", os.path.join(HERE, "keeper_land.py"))
    m = land.MAPPED.match(path)
    head = m and m.group(1) + "/indices/"
    for ref in land.REFS if m else ():
        rc, names, _ = k.git(k.root, "ls-tree", "-r", "--name-only", ref, "--", *(head + d for d in DONE))
        if rc != 0:
            return False
        hits = [p[len(head):] for p in names.splitlines() if p.startswith(head) and os.path.basename(p) == m.group(2)
                and p[len(head):].split("/")[0] in DONE and p[len(head):].count("/") <= 2]
        if len(hits) > 1:
            return False
        if hits:
            return "superseded", "카드 %s/" % hits[0].split("/")[0]
    return None
def unsure(st, team, work, holder, key, idle, fmt=None, slot=""):
    """④ 미확인 깨움 — after_s 뒤 재깨움 1회(정상·오류 턴 길 같은 rewoke 키) · 또 미확인 = harness master [크리티컬] 1통/일 · 재배정·kill 0."""
    k, retry = st.k, st.k.state.setdefault("rewoke", {})
    if key not in retry and k.now() - k.state["unsure"][key] >= st.after_s:
        retry[key] = k.stamp()
        return st.wake(team, work, holder, key, idle, fmt, slot)
    if key not in retry:
        return k.log("판정 불가", team, "%s %s 깨움 도달 미확인(%s) — 재깨움 %d초 뒤 1회 · 재배정 0" % (work, holder, k.state["unsure"][key], st.after_s))
    k.notify("harness", "%s|unsure|%s" % (k.stamp()[:10], key), "[크리티컬] ft2 keeper 깨움 도달 미확인 %s %s %s — 재깨움 1회 뒤에도 미확인 · 재배정·kill 0(사람·팀장 판단)" % (team, work, holder))
def orphans(k, teams):
    """⑤ 고아 — 이름 꼴 byz-<팀>-nano-<stem>#N ∧ 그 팀 최신 dispatch holder 밖 · 자동 개설 = ft2_holders.auto_opened(launch 영수 생애 결속) 공용.
    r2400 — 그 석의 «열려 있을 근거»(dispatch holder ∨ no_lease_idle 초 안 활동)가 없으면 끝 근거와 상관없이 새 갈래로 간다:
    keeper 가 연 석 = 재개 기록 → kill(«CLOSED-NOLEASE» · 스위치·정지·사람 화면·jsonl 개수 가드) · 손 개설 석 = «HELD-NOLEASE» 1줄(닫기 0).
    근거 없는 석은 하나도 안 닫혀도 state["noleft"] 에 남겨 keeper_next.gates 관문이 다음 나노를 막는다(K5)."""
    H, alive = _mod("holders", os.path.join(HERE, "ft2_holders.py")), k.alive_sessions()
    held_by = {t: {h for _, h in got.values()} for t in teams if (got := latest(k, t)) is not None}
    k.orphan_scope = set(held_by)   # r2055 S1 — 이 팀들의 고아 꼴 좌석 판정 = 이 길(명부 밖 판정이 겹쳐 보지 않음)
    left = {}
    for seat in sorted(alive or ()):
        team = m.group(1) if (m := ORPHAN.fullmatch(seat)) else None
        if team not in held_by or seat in held_by[team]:
            continue
        mine = [x for x in intents(k, team) if x[2].get("FT2_HOLDER") == seat]
        work, _, it = max(mine, key=lambda x: str(x[2].get("at") or "")) if len({x[0] for x in mine}) == 1 else (None, None, {})
        ok, why = H.auto_opened(k.call, k.tmux, seat, it) if work else (False, "자동 개설 근거 없음·모호(launch intent work %d개)" % len({x[0] for x in mine}))
        lease = no_lease(k, seat, it, ok)   # r2400 K1 — 열려 있을 근거 판정(dispatch 밖 = 첫 근거 없음 · 활동 = 둘째)
        if k.halt or not ok:   # r2400 K6 정지 중 · K3 손 개설 석 — 새 갈래 밖 손 0
            if lease[0] and quiet(k, team, work, seat, it, ok):   # K1 참 = 이번 바퀴에 닫히지 않고 남는 석(K5 가 센다)
                left.setdefault(team, set()).add(seat)
                unleased(k, team, work, seat, it, lease, ok, why)
                continue
            if k.halt:
                continue   # 정지 중 = «예정 CLOSED-NOLEASE» 줄만(옛 HELD-ORPHAN·UNKNOWN 줄도 0)
            if k.state["held"].get("orphan|" + seat) != k.stamp()[:10]:
                k.state["held"]["orphan|" + seat] = k.stamp()[:10]
                k.log("HELD-ORPHAN", team, "%s %s · 닫기 0" % (seat, why))
            k.unknown_seat(team, work or "-", "-", seat, "roster-outside", why)   # r2055 S3 명부·dispatch 밖 = UNKNOWN [긴급](옛 [고아] 쪽지 자리) · kill 0
            continue
        sha, _, why = k.landing(team, work)
        end = ("landed", sha) if sha and not why else ending(k, team, work)
        if not end:   # r2055 S1 판정 없는 좌석 0
            if lease[0] and quiet(k, team, work, seat, it, ok):   # r2400 K2~K4 — 끝 근거 0 + K1 참 = 새 갈래
                left.setdefault(team, set()).add(seat)
                unleased(k, team, work, seat, it, lease, ok)
                continue
            k.verdict(team, work, seat, "WORKING", "orphan-open", why or "끝 근거 없음")
            continue
        if k.look(team, work, "-", seat, *k.pi_turn(it)) != "REST" or not k.turn_ended(team, work, seat, it):
            continue   # r2055 R1·A13 닫기 = 끝남 ∧ 한 판독 쉼(jsonl 무활동 ≥ PARK_IDLE)
        if not k.idle(team, work, seat) or k.held_attached(team, work, seat):   # kill 직전 가드
            continue
        if seat in {h for _, h in (latest(k, team) or {0: (0, seat)}).values()}:   # ⑦e 읽는 사이 holder 바뀜·판독 실패 = 닫기 0
            continue
        k.call([k.tmux, "kill-session", "-t", "=" + seat])
        gone = k.probe(seat)
        if gone != "absent":   # r2055 UNKNOWN = [긴급]
            k.unknown_seat(team, work, "-", seat, "kill-failed", "%s %s 부재 확인 없음(%s)" % (end[0], end[1], gone))
            continue
        k.log("CLOSED-ORPHAN", team, "%s %s %s %s" % (work, seat, end[0], end[1]))
    k.state["noleft"] = {team: sorted(seats) for team, seats in left.items()}   # r2400 K5 — 다 돈 바퀴에서만 갈아 쓴다(중간 Cut = 옛 값 그대로)
