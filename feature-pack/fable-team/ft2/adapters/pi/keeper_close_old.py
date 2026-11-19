"""ft 2.0 keeper — 승계 끝 구 나노 닫기 (r2281 · 사전 DA#29 APPROVE-DESIGN + 조건 2 · keeper.py b3r 자리에서 retired() 앞에 1회).

C1 대상 = 팀 나노 세션 S · S 를 FT2_HOLDER 로 가진 가장 늦은 intent 의 work W · W 최신 dispatch holder H ≠ S · 같은 계보(# 앞 같음 · H 번호 > S 번호) · H 생존.
C2 커밋 지킴 = S worktree clean ∧ (S HEAD ⊂ H worktree HEAD ∨ S HEAD = 로컬 ref 끝 refs/heads/ · refs/ft2/keep/) · 아니면 «WORKING keep <사유>» 그날 1줄.
C3 유휴 = Pi 턴 끝 ∧ pane Working 0 ∧ 사람 화면 0(attached N 도 닫기 0).
C4 재개 기록 먼저 = seat-resume/<S>.json(uuid = cwd 세션 폴더 *.jsonl 정확히 1개 ∧ mtime ≥ session_created) · tmp → replace · resume_ok 통과 · 같은 name·uuid = 다시 쓰기 0.
C5 세션만 닫기 = kill-session 1 → 부재 확인 → «CLOSED-SUCCEEDED <팀> <W> <S> -> <H>» · 가지·worktree·keep ref·명부·ft2 장부 쓰기 0 · 정지 중 = «예정» 줄만.
C6 B2·B3·승계·판정 목록 길 글자 0 · 나노 밖 좌석 손 0 · 1.x 도구 호출 0.
"""
import glob, importlib.util, json, os  # noqa: E401

HERE = os.path.dirname(os.path.abspath(__file__))
FT2 = os.path.dirname(os.path.dirname(HERE))


def _load(path, alias):
    spec = importlib.util.spec_from_file_location("ft2_close_old_" + alias, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


projection = _load(os.path.join(FT2, "core", "projection.py"), "projection")
endings = _load(os.path.join(HERE, "keeper_endings.py"), "endings")


def lineage(old, new):
    """같은 계보 = # 앞 글자 같음 ∧ 두 번호 숫자 ∧ 후계 번호 > 구 번호."""
    (ob, _, on), (nb, _, nn) = old.rpartition("#"), new.rpartition("#")
    return ob == nb and on.isdigit() and nn.isdigit() and int(nn) > int(on)


def model_of(path):
    """pi 세션 파일의 마지막 model_change.modelId · 없으면 머리 modelId · 못 읽음 = ""."""
    last = ""
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for n, line in enumerate(fh):
                try:
                    doc = json.loads(line)
                except ValueError:
                    continue
                pick = isinstance(doc, dict) and (doc.get("type") == "model_change" or (n == 0 and not last))
                last = doc["modelId"] if pick and isinstance(doc.get("modelId"), str) and doc["modelId"] else last
    except OSError:
        return ""
    return last


class CloseOld:
    def __init__(self, keeper):
        self.k = keeper

    def sweep(self):
        """바퀴 1회 — 팀마다 최신 dispatch · intent 표 1회 → 후보 S 마다 one()."""
        k = self.k
        alive = k.alive_sessions()
        if not alive:
            return
        for team in k.teams():
            last = endings.latest(k, team)
            if last is None:
                k.log("판정 불가", team, "장부 못 읽음 — 승계 끝 구 나노 닫기 0")
                continue
            trees = self.intents(team)
            for seat in sorted(alive):
                hit = self.target(team, seat, alive, last, trees)
                if hit:
                    self.one(team, seat, alive, *hit)

    def intents(self, team):
        """holder → (work, intent) · FT2_HOLDER 로 가진 가장 늦은 intent 1개(at · 경로 순)."""
        got = {}
        for path in glob.glob(os.path.join(glob.escape(os.path.join(projection.runtime_path(self.k.root, team), "launch")), "*.intent")):
            it = self.k.read_json(path)
            holder = it.get("FT2_HOLDER") if isinstance(it, dict) else None
            if holder and (str(it.get("at") or ""), path) > got.get(holder, ("", ""))[:2]:
                got[holder] = (str(it.get("at") or ""), path, it)
        return {h: (os.path.basename(p)[:-len(".intent")].rpartition("@")[0], it) for h, (_, p, it) in got.items()}

    def target(self, team, seat, alive, last, trees):
        """C1 — (W, H, S intent, H intent) · 밖 = None(손 0 · 줄 0)."""
        if not seat.startswith("byz-%s-nano-" % team) or seat not in trees:
            return None
        work, intent = trees[seat]
        new = (last.get(work) or (None, None))[1]
        if not new or new == seat or new not in alive or not lineage(seat, new):
            return None
        return work, new, intent, (trees.get(new) or ("", {}))[1]

    def one(self, team, seat, alive, work, new, intent, new_intent):
        """C2 → C3 → 정지 중 «예정» → C4 재개 기록 → C5 kill 1 · 부재 확인 · 닫기 줄."""
        k = self.k
        why = self.keep(intent.get("worktree") or "", new_intent.get("worktree") or "")
        if why.startswith("판정 불가"):
            return k.log("판정 불가", team, "%s %s %s — 닫기 0" % (work, seat, why[len("판정 불가 · "):]))
        if why:
            return self.held(team, work, seat, why)
        if not self.idle(team, work, seat, intent):
            return None
        if k.halt:
            return k.verdict(team, work, seat, "예정 CLOSED-SUCCEEDED", "close-old", "-> %s · 정지 중 kill 0" % new) and None
        why = self.resume(seat, new, intent)
        if why:
            return k.log("판정 불가", team, "%s %s 재개 기록 %s — 닫기 0" % (work, seat, why))
        k.call([k.tmux, "kill-session", "-t", "=" + seat])
        seen = k.probe(seat)
        if seen != "absent":
            return k.unknown_seat(team, work, "-", seat, "kill-failed", "부재 확인 없음(%s)" % seen) and None
        alive.discard(seat)
        k.log("CLOSED-SUCCEEDED", team, "%s %s -> %s" % (work, seat, new))

    def keep(self, tree, new_tree):
        """C2 — "" = 통과 · 사유 = 닫기 0 · «판정 불가 · …» = git 실패(7초)."""
        k = self.k
        rc, dirty, _ = k.git(tree, "status", "--porcelain")
        if rc != 0:
            return "판정 불가 · git status rc %s" % rc
        if dirty.strip():
            return "dirty"
        rc, head, _ = k.git(tree, "rev-parse", "HEAD")
        if rc != 0:
            return "판정 불가 · rev-parse rc %s" % rc
        head = head.strip()
        if new_tree and k.git(new_tree, "merge-base", "--is-ancestor", head, "HEAD")[0] == 0:
            return ""
        rc, refs, _ = k.git(tree, "for-each-ref", "--points-at", head, "refs/heads/", "refs/ft2/keep/")
        if rc != 0:
            return "판정 불가 · for-each-ref rc %s" % rc
        return "" if refs.strip() else "not-ancestor %s" % head[:12]

    def held(self, team, work, seat, why):
        """«WORKING keep <사유>» — (팀, 좌석, 사유) 그날 1줄."""
        k = self.k
        book, day, key = k.state.setdefault("close_old", {}), k.stamp()[:10], "%s|%s|%s" % (team, seat, why)
        if book.get(key) != day:
            book[key] = day
            k.log("WORKING", team, "keep %s · %s %s" % (why, work, seat))

    def idle(self, team, work, seat, intent):
        """C3 — Pi 턴 끝 ∧ pane Working 0 ∧ attached 0(반례 ④ⓒ · attached N 도 닫기 0)."""
        k = self.k
        if not (k.turn_ended(team, work, seat, intent) and k.idle(team, work, seat)):
            return False
        why = k.attached(seat)
        if why != "free":
            k.verdict(team, work, seat, "WORKING", "attached", "%s · 닫기 0" % why)
            return False
        return True

    def resume(self, seat, new, intent):
        """C4 — "" = 검증된 기록 있음 · 그 밖 = 사유(기록 0 · 닫기 0)."""
        k = self.k
        cwd = intent.get("worktree") or ""
        sessions = k.env.get("FT2_PI_SESSIONS") or os.path.expanduser("~/.pi/agent/sessions")
        files = glob.glob(os.path.join(glob.escape(os.path.join(sessions, "--%s--" % cwd.strip("/").replace("/", "-"))), "*.jsonl"))
        born = k.seat_born(seat)
        if len(files) != 1 or born is None or os.path.getmtime(files[0]) < born:
            return "jsonl %d개 · session_created %s" % (len(files), born)
        log = files[0]
        uuid = os.path.basename(log)[:-len(".jsonl")].rpartition("_")[2]
        home = k.env.get("HOME") or os.path.expanduser("~")
        folder = k.env.get("FT2_SEAT_RESUME_DIR") or os.path.join(home, ".claude", "state", "seat-resume")
        path, old = os.path.join(folder, seat + ".json"), k.read_json(os.path.join(folder, seat + ".json"))
        if not (isinstance(old, dict) and old.get("name") == seat and old.get("uuid") == uuid):
            rec = {"name": seat, "engine": "pi", "uuid": uuid, "jsonl": log, "cwd": cwd, "model": model_of(log), "retired_by": new, "at": k.stamp(),
                   "binding": {"source": "ft2-keeper-close-old", "session": seat, "uuid": uuid, "jsonl": log}}
            try:
                os.makedirs(folder, exist_ok=True)
                with open(path + ".tmp", "w", encoding="utf-8") as fh:
                    json.dump(rec, fh, ensure_ascii=False)
                os.replace(path + ".tmp", path)
            except OSError as exc:
                return "쓰기 %s" % type(exc).__name__
        return "" if k.resume_ok(seat) else "검증 실패"
