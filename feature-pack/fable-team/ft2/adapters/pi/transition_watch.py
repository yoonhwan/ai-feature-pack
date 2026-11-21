#!/usr/bin/env python3
"""r2275 ft2 keeper — 카드 전이 증거 감시(상태 × 넘어가는 증거 × 상한 표 1개 · 알림만 · 사전 DA#28 APPROVE-DESIGN).
keeper 바퀴 끝(report · 하루 정리 뒤) check(k) 1회 · `--survey [--root R] [--pack P]` = 칸마다 1줄(쓰기·알림 0) · 카드 = TEAMS.md 팀 폴더(쌍둥이) × indices/{대기,진행,완성} × BYZ 두 ref(앞 ref 먼저).
구현 착지 = keeper_land.land_kind(r2274) · 예외 = no_code · 카드 1장 = 한 바퀴 한 칸(① 증거 모순 → ② 위임 → ③ 시간 상한 첫 일치) · 알림 = (팀 · 칸) 하루 묶음 1통 (지문 «전이|칸|팀|날짜|이름 집합 해시» · 집합이 바뀌면 1통 더 · 하루 3통 · 스캔이 끝난 바퀴만) · 예산 바퀴마다 5초(+카드 1장 · 넘으면 이어서) · git·장부 못 읽음 = 판정 불가 1줄 · 알림 0 · 카드 이동·장부 쓰기 0.
"""
import datetime, hashlib, importlib.util, os, re, subprocess, sys, time  # noqa: E401

HERE = os.path.dirname(os.path.abspath(__file__))
def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_tw_" + name, os.path.join(HERE, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

land, lw = _load("keeper_land"), _load("land_wait")   # lw = r2297 착지 대기 거짓 경보 판독
BUDGET_S, GIT_S, DAY_CAP, NAMES, DAY = 5.0, 7, 3, 10, 86400   # 예산 5초 = 마지막 카드 1장(git log·land_kind)이 넘쳐도 바퀴 +7초 안
Stop = type("Stop", (Exception,), {"__doc__": "C6 R2 문 — 바퀴 남은 몫 < 7초 = 이 바퀴 멈춤(이어 보기 · 판정 불가 아님 · seen 그대로)"})
CARD, LANDT = re.compile(r"^(design/.+)/indices/(대기|진행|완성)/([^/]+)\.md$"), re.compile(land.LAND.pattern + "(.*)$", re.M)
PRE, TOK, SETL = re.compile(r"^- 선행:(.*)$", re.M), re.compile(r"[^\s()·,`'\"<>«»:;]+"), re.compile(r"^- 세트(?:\([^)\n]*\))?:", re.M)   # r2293 세트 증거 줄 = «- 세트:» · «- 세트(…):»
LEDG = re.compile(r"^- 대기 사유:.*장부 done 은 거짓", re.M)   # r2358 K3 사람 분류 표지 = 장부 칸 알림 0(그 카드는 다시 접수 0)
# C1 표 한 곳 — (칸, 증거 함수 e_<이름>, 상한 키, 기본 초, 위임 대상 · 빈칸 = 신규 알림) · 차례 = 고정 첫 일치(① 증거 모순 → ② 위임 → ③ 시간 상한)
ROWS = (("완성 증거 0", "done0", "", 0, ""), ("장부 완료 · 카드 열림", "ledger", "FT2_TW_DONE_OPEN_S", 3600, ""),
        ("선행 풀림 미반영", "prereq", "FT2_TW_PREREQ_S", 3600, ""), ("착지 대기", "land", "FT2_TW_LAND_WAIT_S", 600, ""),   # r2293 C1 4번째 = e_seat 앞
        ("진행 · 좌석 있음", "seat", "", 0, "keeper_stall"),
        ("승계 중", "succ", "", 0, "stall-scan"), ("대기 · 배정", "wait", "", 0, "assign-watch"),
        ("진행 · 나노 승계 막힘", "nano", "FT2_TW_NANO_S", 1800, ""), ("병합 거절", "reject", "FT2_TW_REJECT_S", DAY, ""),
        ("진행 24시간", "prog", "FT2_TW_PROGRESS_S", DAY, ""))
HINT = {"done0": "카드 착지 줄 확인(되돌림 = 팀장 판단)", "ledger": "다시 접수", "prereq": "«풀림» 줄 또는 착수",
        "nano": "나노 승계 막힘 · 2.0 승계 길 없음", "reject": "새 head 재검 또는 착지", "prog": "착지 줄 또는 새 판정 줄",
        "land": "착지(h 또는 try-auto --land) · 막힌 단계 확인"}
def limits(k):   # 상한 = env > <루트>/.fable-team/thresholds.env > ~/.claude/fable-team > 샘플(keeper_next 차례) · 못 읽음 = 기본값.
    files = [p for p in (os.path.join(k.root, ".fable-team", "thresholds.env"), os.path.join(k.env.get("HOME") or os.path.expanduser("~"), ".claude", "fable-team", "thresholds.env"),
                         os.path.join(HERE, "thresholds.env.sample")) if os.path.isfile(p)]
    return {fn: int(v) if (v := (k.env.get(key) or next((x.split("=", 1)[1].strip() for p in files for x in open(p, encoding="utf-8") if x.startswith(key + "=")), "")) if key else "").isascii() and v.isdigit() else sec
            for _, fn, key, sec, _ in ROWS}
class Watch:
    def __init__(s, k, clock=time.monotonic, hard=None):   # hard = 바깥 호출 문 끝 시각(check = 시작 + 7+7초 · survey = None = 문 없음)
        s.k, s.clock, s.hard, s.now, s.lim, s.books, s.recent, s.st = k, clock, hard, k.now(), limits(k), {}, {}, k.state.setdefault("transition", {})
        s.kind, s.nc = s.st.setdefault("kind", {}), s.st.setdefault("nc", {})   # 구현 착지 판정 · no_code 기억(바퀴 사이 · 4000 넘으면 비움)
    def run(s, argv, inp=None):   # 바깥 호출 1곳 · 7초 · 재시도 0(하드 룰 12) · 넘침·실행 실패 = rc None
        if s.hard is not None and (s.hard - s.clock() < GIT_S or (left := s.k.left()) is not None and left < GIT_S):
            raise Stop("남은 몫 7초 아래")   # C6 문 — 남은 몫(문 끝·keeper 구획) ≥ 7초일 때만 시작 = check 1회 바깥 호출 합 ≤ 7+7초
        try:
            done = subprocess.run(argv, input=inp, capture_output=True, timeout=GIT_S, env=s.k.env, cwd=s.k.root)
        except (subprocess.TimeoutExpired, OSError) as exc:
            return None, type(exc).__name__
        return done.returncode, done.stdout if inp else done.stdout.decode("utf-8", "replace")   # inp(cat-file --batch) = 바이트 그대로
    def call(s, argv, cap): return s.run(argv)   # keeper_land.lib_call 손 → (rc, stdout)
    def git(s, *args, inp=None): return s.run(["git", "-C", s.k.root, "-c", "core.quotepath=off"] + list(args), inp)
    def index(s):   # [카드 dict] 경로 순 · 같은 (팀, stem) = ref 마다 첫 사본 → lw.pick 1장(r2297 A4 · cat-file 1회 그대로) · 판독 실패 = «판정 불가 <사유>».
        fmap, pick, (rc, md) = {}, {}, s.git("show", land.REFS[0] + ":design/TEAMS.md")
        for cells in ([x.strip() for x in ln.strip().strip("|").split("|")] for ln in md.splitlines()) if rc == 0 else ():
            [fmap.setdefault(f, cells[0]) for f in (land.folders(cells[1]) if len(cells) > 1 and "design/" in cells[1] else ())]
        for ref in land.REFS if rc == 0 else ():
            rc, out = s.git("ls-tree", "-r", "-z", ref, "--", "design")
            for meta, _, path in (row.partition("\t") for row in out.split("\0")) if rc == 0 else ():
                team = fmap.get(m.group(1)) if (m := CARD.match(path)) and len(meta.split()) == 3 else None
                team and pick.setdefault((team, m.group(3)), {}).setdefault(ref, {"team": team, "stage": m.group(2), "stem": m.group(3), "path": path, "ref": ref, "blob": meta.split()[2]})
        every, pos = [c for refs in pick.values() for c in refs.values()], 0
        rc, raw = s.git("cat-file", "--batch", inp="".join(c["blob"] + "\n" for c in every).encode()) if rc == 0 else (rc, b"")
        if rc != 0:
            return "판정 불가 카드 판독 git rc %s" % rc
        for c in every:
            size = int(raw[pos:(nl := raw.index(b"\n", pos))].split()[2])
            c["body"], pos = raw[nl + 1:nl + 1 + size].decode("utf-8", "replace"), nl + 2 + size
        cards = sorted((lw.pick(list(refs.values())) for refs in pick.values()), key=lambda c: c["path"])
        s.stems = {c["stem"]: c for c in reversed(cards)}   # 같은 stem = 경로 순 앞 카드
        return cards
    def ledger(s, team):   # 팀 장부 {done: {work: 시각}, open: {work: holder}, all} · runtime 없음 = 빈 장부 · 못 읽음 = «판정 불가 …».
        if team not in s.books:
            P, runtime = land.PROJ, land.PROJ.runtime_path(s.k.root, team)
            try:
                st = P.record.recover_state(*(lambda n: (n.state(), n.records()))(P.journal.Journal(runtime, rec=P.record))) if os.path.isdir(runtime) else {}
                done = {w: datetime.datetime.fromisoformat(v["at"]).timestamp() if isinstance(v.get("at"), str) else None for w, v in (st.get("done") or {}).items()}
                own = {w: (o or {}).get("holder") for w, o in (st.get("owners") or {}).items() if w not in done and (o or {}).get("holder")}
                s.books[team] = {"done": done, "open": own, "all": set(st.get("generations") or {}) | set(done) | set(own)}
            except Exception as exc:   # noqa: BLE001 — 장부 손상 = 판정 불가(하드 룰 20)
                s.books[team] = "판정 불가 장부 %s %s" % (team, type(exc).__name__)
        return s.books[team]
    def works(s, c, book, cell):   # r2335 카드 stem 에 맞는 work(정확 우선 → «work-» 접두 · 긴 것 먼저) — W1 정확 대조 = 장부 전체(book["all"]) · 칸 교집합만(W2 접두 = 칸에 있고 그 work 의 주인 카드가 s.stems 에 없는 것)
        if c["stem"] in book["all"]:
            return [c["stem"]] if c["stem"] in book[cell] else []   # 정확 일치가 있으면 접두로 안 내려간다(내 work = 열림·세대만 = 남의 끝난 work 아님)
        return [x for x in (c["stem"][:i] for i in range(len(c["stem"]) - 1, 0, -1) if c["stem"][i] == "-") if x in book[cell] and x not in s.stems]
    def kind_of(s, sha, tail):   # r2274 land_kind 1곳(착지 줄 꼬리에 ai-feature-pack = 팩 먼저) · 판정 불가 = 기억 0
        for repo in ((s.k.pack, s.k.root) if "ai-feature-pack" in tail else (s.k.root, s.k.pack)) if sha not in s.kind else ():
            if not (word := land.land_kind(s.k.root, repo, sha, s.call)).startswith("판정 불가"):
                s.kind[sha] = word
                break
        return s.kind.get(sha) or word
    def impl(s, c):   # C3 구현 착지 증거 — "" = 있음(구현 착지 · no_code 예외) · 그 밖 = 사유(착지 줄 0 · 카드 문서만 · 판정 불가).
        lands = LANDT.findall(c["body"])
        why = s.kind_of(*lands[-1]) if lands else "착지 줄 0"
        if why == "구현" or why.startswith("판정 불가"):
            return "" if why == "구현" else why
        ex = s.nc[c["blob"]] if c["blob"] in s.nc else s.nc.setdefault(c["blob"], land.no_code(s.k.root, c["body"], s.call))
        return ex if ex.startswith("판정 불가") else "" if ex else ("카드 문서만 " + lands[-1][0][:8] if lands else why)
    def ct(s, c):   # 카드 마지막 줄 시각 = ref 마다 최근 창(상한 최대 + 1일) git log 1회 · 창 밖 = 창 끝(어느 상한보다 오래됨)
        if c["ref"] not in s.recent:
            since, got, at = int(s.now - max(s.lim.values()) - DAY), {}, 0
            rc, out = s.git("log", "--no-renames", "--since=%d" % since, "--format=@%ct", "--name-only", c["ref"], "--", "design")
            for ln in out.splitlines() if rc == 0 else ():
                at = int(ln[1:]) if ln.startswith("@") else at
                ln.startswith("@") or not ln or got.setdefault(ln, at)
            s.recent[c["ref"]] = (got, since) if rc == 0 else "판정 불가 git log %s rc %s" % (c["ref"], rc)
        return got if isinstance(got := s.recent[c["ref"]], str) else got[0].get(c["path"], got[1])
    def marker(s, holder):   # keeper_succeed.marker 와 같은 증류 미완 표식 · 나이(초) · 없음·남의 좌석 = None
        path = os.path.join(s.k.root, ".fable-team", "state", "pi-distill-pending", re.sub(r"#\d+$", "", holder))
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                return s.now - os.stat(path).st_mtime if "seat=" + holder in fh.read().split() else None
        except FileNotFoundError:
            return None
    def replaced(s, team, holder):   # 명부(keeper 받는 곳 차례의 그 팀 명부) _replaced_by
        row = s.k.read_json(s.k.cells(team)[0][0] or "").get(holder)
        return bool(isinstance(row, dict) and row.get("_replaced_by"))
    def aged(s, c, fn):   # 시간 상한 칸 공통 — 넘음 = «<카드> <N>시간» · 판정 불가 = 사유
        at = s.ct(c)
        return at if isinstance(at, str) else "%s %d시간" % (c["stem"], (s.now - at) // 3600) if s.now - at >= s.lim[fn] else None
    def e_done0(s, c): return (s.impl(c) or None) if c["stage"] == "완성" and "ft2 card_stage" in c["body"] else None
    def e_ledger(s, c):
        if LEDG.search(c["body"]):
            return None   # r2358 K3 — «장부 done 은 거짓» 분류 카드 = 장부 칸 hit 0(선행이 아직이라 다시 접수하면 나노가 선행 없이 열린다)
        book = s.ledger(c["team"]) if c["stage"] != "완성" else {"done": {}, "open": {}, "all": set()}
        for w in [] if isinstance(book, str) else s.works(c, book, "done"):
            again = [x for x in book["all"] if re.fullmatch(re.escape(w) + r"-r\d+", x)]
            if any(x not in book["done"] for x in again) or book["done"][w] is None or s.now - book["done"][w] < s.lim["ledger"]:
                continue   # 다시 접수가 열려 있음 · 시각 못 읽음 · 1시간 안
            if why := s.impl(c):
                return why if why.startswith("판정 불가") else "%s · 다시 접수 = %s-r%d" % (w, w, len(again) + 2)
        return book if isinstance(book, str) else None
    def e_prereq(s, c):
        line = PRE.search(c["body"]) if c["stage"] == "대기" else None
        pre = [s.stems[t] for t in dict.fromkeys(x.rstrip(".") for x in TOK.findall(line.group(1))) if t in s.stems and t != c["stem"]] if line and "풀림" not in line.group(1) else []
        if not pre or any(p["stage"] != "완성" or s.impl(p) for p in pre):
            return None   # C2 선행 = 모두 완성 ∧ 구현 착지일 때만 풀림
        at = sorted((s.ct(p) for p in pre), key=lambda x: isinstance(x, str), reverse=True)   # 판정 불가 사유 먼저
        return at[0] if isinstance(at[0], str) else "%s ← %s" % (c["stem"], " ".join(p["stem"] for p in pre)) if s.now - max(at) >= s.lim["prereq"] else None
    def e_land(s, c):   # r2293 C1 착지 대기 — 완성 아님 · 세트 증거 줄 · 착지 줄 0 · r2297 표지·끝 줄 0(lw.skip) · 카드 마지막 줄 시각(ct) 뒤 상한 넘음 = 분 단위(꼴 틀림 이름표 = lw.text)
        return None if c["stage"] == "완성" or not SETL.search(c["body"]) or LANDT.search(c["body"]) or lw.skip(land.endings, c["body"]) else at if isinstance(at := s.ct(c), str) else lw.text(c["stem"], c["body"], (s.now - at) // 60) if s.now - at >= s.lim["land"] else None
    def e_seat(s, c): return s.o if not isinstance(s.o, tuple) else None if s.marker(s.o[1]) is not None or s.replaced(c["team"], s.o[1]) else ""
    def e_succ(s, c): return "" if isinstance(s.o, tuple) and s.marker(s.o[1]) is None and s.replaced(c["team"], s.o[1]) else None
    def e_wait(s, c): return "" if c["stage"] == "대기" and not s.rej and s.o is None else None
    def e_nano(s, c): return "%s %s" % s.o if isinstance(s.o, tuple) and (s.marker(s.o[1]) or -1) >= s.lim["nano"] else None
    def e_reject(s, c): return s.aged(c, "reject") if c["stage"] != "완성" and s.rej else None
    def e_prog(s, c): return s.aged(c, "prog") if c["stage"] == "진행" and not s.rej and s.o is None else None
    def classify(s, c):
        book = s.ledger(c["team"])
        found = book if isinstance(book, str) else s.works(c, book, "open")
        s.o = found if isinstance(found, str) else (found[0], book["open"][found[0]]) if found else None   # 열린 ft2 work (work, holder) · 없음 None · 장부 판정 불가 = 사유
        s.rej = "REJECT" in ([x for x in c["body"].splitlines() if "착지" in x] or [""])[-1]   # 마지막 착지 시도 줄 REJECT
        return next(((row, got) for row in ROWS for got in [getattr(s, "e_" + row[1])(c)] if got is not None), None)   # C1 첫 일치 (행, 내용) · 일치 0 = None · 판정 불가 = 그 칸에서 멈춤(내용 = 사유)
def sweep(w, deadline=None):   # 카드 차례대로 한 칸씩 · (끝났나, 판정 불가 사유) · 결과 = st.hits {팀|칸: [[이름, 내용, 표시], …]} · 이어 보기 = st.seen.
    fresh, rest = [], True   # r2358 fresh = 이번 부름 본 루프가 append 한 항목 · rest = 본 루프가 끝 카드까지 갔나
    try:
        cards = w.index()
        seen, hits = set(w.st.setdefault("seen", [])), w.st.setdefault("hits", {})
        for c in [] if isinstance(cards, str) else [c for c in cards if c["path"] not in seen]:
            if deadline is not None and w.clock() >= deadline:
                rest = False   # C6 예산 넘음 = 다음 바퀴 이어서(묶음 0)
                break
            got = w.classify(c)
            if got:
                hits.setdefault("%s|%s" % (c["team"], got[0][1]), []).append(item := [c["stem"], got[1], 1])   # r2358 표시 1 = 이번 부름이 이미 판정한 항목(재판정 0)
                fresh.append(item)
            w.st["seen"].append(c["path"])
    except Stop:
        rest, cards = False, ""   # C6 문 = 이 카드 seen 0 · 다음 바퀴 그 자리부터
    if not rest or isinstance(cards, str):
        for x in fresh:
            del x[2:]   # r2358 본 루프만 끝난 바퀴 = 재판정 전이라 표시를 지운다(다음 바퀴 새 본문으로 다시 본다)
        return False, cards if isinstance(cards, str) else ""
    try:
        return recheck(w, cards, deadline), ""   # r2358 K1 — 묶기 전에 이 바퀴 본문으로 한 번 다시 판정
    except Stop:
        return False, ""   # r2358 재판정 7초 문 = 이 바퀴 묶음 0 · 표시한 항목은 다음 바퀴 이어서
def recheck(w, cards, deadline):   # r2358 K1·K2 — 알림 칸(위임 칸 = 손 0)의 표시 없는 항목만 그 바퀴 본문(cards)으로 1회 다시 판정 · 같은 칸 = 새 내용 · «판정 불가» = 원 칸에 새 내용 · 칸 이동·카드 없음 = 버림 · 끝 = True · 예산 넘음 = False(남은 항목은 표시 없이 다음 바퀴).
    hits, by = w.st.get("hits") or {}, {(c["team"], c["stem"]): c for c in cards}
    for key in sorted(hits):
        team, fn = (key.split("|") + [""])[:2]
        row = next((r for r in ROWS if r[1] == fn), None)
        if row is None or row[4]:
            continue   # 위임 칸 = 알림 0 · 그대로 둔다
        out, left = [], list(hits[key])
        while left:
            item = left.pop(0)
            if len(item) > 2 and item[2]:
                out.append(item)   # 이번 부름이 이미 판정한 항목
                continue
            if deadline is not None and w.clock() >= deadline:
                hits[key][:] = out + [item] + left
                return False   # 이어 보기 — 재판정을 끝낸 항목만 표시 1
            got = w.classify(by[(team, item[0])]) if (team, item[0]) in by else None
            if got is not None and (got[0][1] == fn or got[1].startswith("판정 불가")):
                item[1:] = [got[1], 1]
                out.append(item)
        hits[key][:] = out
    return True
def bundles(w, hits, day):   # C6 (팀 · 칸) 묶음 = [팀, 칸, 날짜, 지문, 본문] · 위임 칸 = 0 · 판정 불가 = 1줄(알림 0).
    out = []
    for key in sorted(hits):
        team, fn = key.split("|")[:2]
        row = next(r for r in ROWS if r[1] == fn)
        items, bad = ([x for x in hits[key] if x[1].startswith("판정 불가") == flag] for flag in (False, True))
        bad and w.k.log("판정 불가", team, "전이 %s %d장 · %s" % (row[0], len(bad), bad[0][1][:80]))
        if items and not row[4]:   # C1 위임 칸 = 판정만(알림 0)
            out.append([team, row[0], day, "전이|%s|%s|%s|%s" % (row[0], team, day, hashlib.sha1("\n".join(sorted(x[0] for x in items)).encode()).hexdigest()[:12]), "[크리티컬] 카드 전이 감시 · %s · %s %d장 — %s · 다음 수 = %s" % (row[0], team, len(items), " · ".join(x[1] for x in sorted(items)[:NAMES]), HINT.get(fn, "-"))])
    return out
def flush(w, day):   # C6 보내기 — keeper notify 길 · (팀 · 칸) 하루 3통 · 미룸(False) = 다음 바퀴 다시 · 날짜가 지난 묶음·제외 팀 = 버림.
    cap, keep = {key: n for key, n in w.st.setdefault("cap", {}).items() if n[0] == day}, []
    for team, cell, at, fp, body in w.st.get("out") or []:
        n = cap.get(team + "|" + cell, [day, 0])[1]
        if at != day or n >= DAY_CAP or w.k.blocked(fp):
            continue
        if w.k.notify(team, fp, body):
            cap[team + "|" + cell] = [day, n + 1]
        elif team not in w.k.skip:
            keep.append([team, cell, at, fp, body])
    w.st["cap"], w.st["out"] = cap, keep
def check(k, clock=time.monotonic, budget=BUDGET_S):   # keeper 바퀴 끝 1회(반환 None) — 미룬 묶음 보내기 → 이어 스캔(예산 안) → 스캔이 끝났으면 묶음 → 보내기.
    if (left := k.left()) is not None and left < 2 or k.root in k.stale or not os.path.exists(os.path.join(k.root, ".git")):
        return None   # 남은 몫 2초 아래 · BYZ 낡음(keeper 가 판정 불가 1줄을 이미 씀) · git 리포 아닌 루트 = 이 바퀴 0
    w, day = Watch(k, clock, clock() + 2 * GIT_S), k.stamp()[:10]
    done, err = sweep(w, clock() + min(budget, left - 1 if left is not None else budget))
    w.st["err"] = (err and w.st.get("err") != err and k.log("판정 불가", text="전이 감시 " + err)) or err   # 판정 불가 = 사유가 바뀔 때 1줄
    if done:
        w.st["out"], w.st["seen"] = (w.st.get("out") or []) + bundles(w, w.st.pop("hits", {}), day), []
        [w.st[x].clear() for x in ("kind", "nc") if len(w.st[x]) > 4000]
    flush(w, day)   # 미룬 묶음 + 끝난 스캔 묶음
def survey(root, pack=None):   # C7 전수 조사 — 칸마다 1줄(수 · 위임 · 판정 불가 · 이름 앞 20) + 끝 줄 초 · keeper 는 만들기만(바퀴·로그·쪽지·state 쓰기 0).
    t, out = time.monotonic(), []
    err = sweep(w := Watch(_load("keeper").Keeper(root, dict(os.environ, **({"FT2_PACK_REPO": pack} if pack else {})))))[1]
    for name, fn, _, _, deleg in ROWS:
        items = sorted((key.split("|")[0] + ":" + x[0], x[1]) for key, xs in w.st.get("hits", {}).items() if key.split("|")[1] == fn for x in xs)
        good, bad = ([x for x in items if x[1].startswith("판정 불가") == flag] for flag in (False, True))
        out.append("전이 %s %s" % (name, err) if err else "전이 %s %d%s%s · %s" % (name, len(good), " 위임=" + deleg if deleg else "",
                   " 판정불가=%d(%s)" % (len(bad), bad[0][1][:60]) if bad else "", " ".join(x[0] for x in good[:20])))
    return out + ["전이 survey s=%g" % round(time.monotonic() - t, 1)]
if __name__ == "__main__":
    ARGS = dict(zip(sys.argv[2::2], sys.argv[3::2])) if sys.argv[1:2] == ["--survey"] and len(sys.argv) % 2 == 0 else {"?": 1}
    OK = not set(ARGS) - {"--root", "--pack"}
    sys.stdout.write("\n".join(survey(ARGS.get("--root") or os.getcwd(), ARGS.get("--pack"))) + "\n" if OK else "사용법: transition_watch.py --survey [--root R] [--pack P]\n")
    sys.exit(0 if OK else 64)
