"""ft 2.0 keeper — r2055 settle() 한 길 (keeper.py 가 섞어 쓴다 · 설계 design/harness/DESIGN-r2055-seat-settle-one-path.md r8).

좌석마다 판정 1개 = LANDED(착지 끝) · PARKED(끝남 ∧ 남길 것 안전 → kill + core park) · WORKING(손 0) · UNKNOWN(kill 0 + [긴급]).
«일하나» 는 tmuxc 규칙을 같은 값으로 쓴다(UC12 CPU 문턱·간격 · pane_descendant_pids 깊이 8 · cmd_clean 셸 목록).
★CPU idle 단독은 유휴·닫기 근거 0★ — 유휴 = jsonl 무활동 ≥ PARK_IDLE ∧ CPU idle 2회(셸만 남은 pane 은 CPU 무관).
정지(.fable-team/state/ALL_STOP.json) 중 = 판정·[긴급]·«예정» 줄만 · kill·park·깨움·fill 0.
"""
import datetime
import glob
import importlib.util
import json
import os
import re

PARK_IDLE, WAIT_S, DAY = 3600, 900, 86400   # 유휴 문턱 60분 · 질문 창 15분
CPU_IDLE, CPU_GAP, CPU_DEPTH = 0.3, 30, 8   # tmuxc UC12 %cpu < 0.3 · 표본 간격 ≥ 30초 · pane_descendant_pids 깊이 8
SHELLS = ("zsh", "bash", "fish")            # tmuxc cmd_clean
KINDS = ("nano", "master", "arch", "da", "desk", "tester", "pm", "qa", "orch", "temp")   # S1 명부 role 칸 = 좌석 종류 낱말
BUSY = re.compile("Working|[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]")
NAME = re.compile(r"byz-[a-z0-9]+(?:-[A-Za-z0-9._]+)+#\d+")
NEXT = {"waiting-input": "팀장이 질문 창에 답", "dirty": "나노에게 커밋·push 요청", "unpushed": "나노에게 push 요청",
        "shell-only-unsafe": "워크트리 확인 뒤 손 정리", "owner-orphan": "owner·intent 대조 뒤 손 park",
        "accept-only": "거두기(r1925 길) 또는 배정", "roster-outside": "명부 등록 또는 손 정리", "name-bad": "세션 이름 확인",
        "tmuxc-mismatch": "tmuxc·settle 판정 대조"}


HERE = os.path.dirname(os.path.abspath(__file__))
FT2 = os.path.dirname(os.path.dirname(HERE))


def _load(path, alias):
    spec = importlib.util.spec_from_file_location(alias, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


cli = _load(os.path.join(FT2, "core", "cli.py"), "ft2_keeper_settle_cli")
PROJ = cli._load("projection")
endings = _load(os.path.join(HERE, "keeper_endings.py"), "ft2_keeper_settle_endings")


def descendants(rows, root, depth=CPU_DEPTH):
    """tmuxc pane_descendant_pids 와 같은 규칙 — root 부터 너비 우선 depth 단(root 포함)."""
    kids, out, level = {}, [], [root]
    for pid, ppid, _cpu, _cmd in rows:
        kids.setdefault(ppid, []).append(pid)
    for _ in range(depth):
        if not level:
            break
        out += level
        level = [kid for pid in level for kid in kids.get(pid, [])]
    return out


def working(pane):
    """A13 pane 일함 근거 — 끝 12줄 · 입력줄(❯ · ›) 뒤 글자 = 근거 0(고스트) · Working · esc to interrupt · 스피너."""
    rows = [x for x in pane.rstrip("\n").splitlines()[-12:] if not x.lstrip().startswith(("❯", "›"))]
    return any(BUSY.search(x) or "esc to interrupt" in x for x in rows)


class Settling:
    def fresh_samples(self):
        """표본 장부(cpu · pane2)는 직전 바퀴에 잰 것만 남김(바퀴 시작 1회) — 끊긴 표본으로 쉼 확정 0 · 영구 pending 0(arch #308380)."""
        prev, self.state["round_at"] = self.state.get("round_at"), self.now()
        for name in ("cpu", "pane2"):
            book = self.state.setdefault(name, {})
            for seat in [x for x, v in book.items() if prev is None or not isinstance(v, dict) or v.get("at", 0) < prev]:
                book.pop(seat)

    def stopped(self):
        """ALL_STOP 판독 1회/바퀴 — 없음 = 진행 · 있음(released 표식 없음) = 정지 · 깨짐 = 정지 + 판정 불가 1줄."""
        path = os.path.join(self.root, ".fable-team", "state", "ALL_STOP.json")
        if not os.path.lexists(path):
            return False
        try:
            with open(path, encoding="utf-8") as fh:
                doc = json.load(fh)
        except (OSError, ValueError) as exc:
            doc = exc
        if not isinstance(doc, dict):
            self.log("판정 불가", text="ALL_STOP 판독 실패(%s) — 정지로 봄" % type(doc).__name__)
            return True
        return not doc.get("released")

    def ps_rows(self):
        """[(pid, ppid, %cpu, comm)] 바퀴당 1회(ps 1번 · 7초) · 실패 = None."""
        got = self.cache.setdefault("@round", {})
        if "ps" not in got:
            rc, out, _ = self.call(["ps", "-A", "-o", "pid=,ppid=,pcpu=,comm="])
            rows = []
            for line in out.splitlines() if rc == 0 else ():
                cells = line.split(None, 3)
                try:
                    rows.append((int(cells[0]), int(cells[1]), float(cells[2]), cells[3] if len(cells) > 3 else ""))
                except (ValueError, IndexError):
                    continue
            got["ps"] = rows if rc == 0 else None
        return got["ps"]

    def pane_info(self, seat):
        """(pane_pid, pane_current_command) · 못 읽음 = None."""
        rc, out, _ = self.call([self.tmux, "display-message", "-p", "-t", "=" + seat + ":", "#{pane_pid}\t#{pane_current_command}"])
        pid, tab, cmd = out.strip().partition("\t")
        return (int(pid), cmd) if rc == 0 and tab and pid.isdigit() else None

    def cpu(self, seat, info):
        """busy | idle(표본 2개 이상 · 간격 ≥ 30초 · 모두 < 0.3) | pending | unknown — 바퀴당 표본 1개 · 직전 표본 = state.cpu."""
        rows = self.ps_rows() if info else None
        if rows is None:
            return "unknown"
        mine = set(descendants(rows, info[0]))
        load, book, now = sum(c for pid, _pp, c, _cmd in rows if pid in mine), self.state.setdefault("cpu", {}), self.now()
        if load >= CPU_IDLE:
            book[seat] = {"at": now, "cpu": load}
            return "busy"
        prev = book.get(seat) or {}
        first = prev.get("first", prev.get("at")) if prev.get("cpu", CPU_IDLE) < CPU_IDLE else None
        book[seat] = {"at": now, "cpu": load, "first": now if first is None else first}
        return "idle" if first is not None and now - first >= CPU_GAP else "pending"

    def pi_turn(self, intent):
        """(jsonl 무활동 초, 마지막 줄 stopReason) · 파일 없음 = (None, None)."""
        why = self.pi_last_turn(intent)
        if why.startswith(("세션 파일 없음", "intent 시각 없음")):
            return None, None
        sessions = self.env.get("FT2_PI_SESSIONS") or os.path.expanduser("~/.pi/agent/sessions")
        folder = os.path.join(sessions, "--%s--" % (intent.get("worktree") or "").strip("/").replace("/", "-"))
        newest = max((os.path.join(folder, f) for f in os.listdir(folder) if f.endswith(".jsonl")), key=os.path.getmtime)
        stop = "stop" if not why else why.rpartition("/")[2] if why.startswith("마지막 줄") else None
        return self.now() - os.path.getmtime(newest), stop

    def with_why(self, tail, work):
        why = getattr(self, "why", "") if work != "-" else ""
        return tail if not why or why in tail else " · ".join(x for x in (tail, why) if x)

    def verdict(self, team, work, seat, word, code, tail=""):
        """판정 1줄 — 같은 좌석·같은 (판정, 사유) 반복 로그 0 · UNKNOWN 은 바퀴마다 셈(ROUND unknown=N)."""
        self.unknown += word == "UNKNOWN"
        tail = self.with_why(tail, work)   # 착지 판정 사유 = 꼬리 끝
        two = self.cache.get("@round", {}).get("two", {}).get(seat)   # A13 2차로 내려간 좌석
        tail = " · ".join(x for x in (tail, two) if x) if two and two not in tail else tail
        key, book = "%s|%s|%s" % (team, work, seat), self.state.setdefault("verdict", {})
        if book.get(key) != [word, code]:
            book[key] = [word, code]
            self.log(word, team, " ".join(x for x in (work, seat, code) if x) + (" · " + tail if tail else ""))
        return word

    def alert(self, team, work, attempt, seat, code, tail=""):
        tail = self.with_why(tail, work)
        """UNKNOWN [긴급] 1통 — 지문 (team, work, attempt, reason) 하루 1회 · 새 사유·새 attempt = 즉시 · 전송 실패도 그날 지문(r2065 E3·E4 · 재시도 0 · 상한 밖이면 다음 바퀴)."""
        sig, day = "%s|%s|%s|%s" % (team, work, attempt, code), self.stamp()[:10]
        book = self.state.setdefault("alerts", {})
        if book.get(sig) == day:
            return
        body = "[긴급] UNKNOWN %s %s %s %s%s · 다음 수 %s" % (team, work, seat, code, " · " + tail[:80] if tail else "", NEXT.get(code, "판독 확인"))
        if self.notify(team, "unknown|%s|%s" % (day, sig), body):
            book[sig] = day

    def unknown_seat(self, team, work, attempt, seat, code, tail=""):
        self.verdict(team, work, seat, "UNKNOWN", code, tail)
        self.alert(team, work, attempt, seat, code, tail)
        return "UNKNOWN"

    def unknown_line(self, team, work, code, text):
        """좌석 칸 없는 UNKNOWN 줄(옛 HELD 자리 · 호출자가 같은 사유 반복을 거름) + [긴급] 1통(지문 하루 1회) · ROUND unknown 셈."""
        self.unknown += 1
        self.log("UNKNOWN", team, text)
        self.alert(team, work, "-", "-", code, text)

    def settle_nano(self, team, work, attempt, holder, row, why):
        """착지 판정 밖 나노 1석 → 판정 1개(LANDED 는 호출자 몫) · why = 착지 판정 사유(모든 판정 줄 꼬리 끝에 남김)."""
        self.why = why or ""
        done, owner = bool(row.get("done")), row.get("owner")
        raw = self.read_json(os.path.join(PROJ.runtime_path(self.root, team), "launch", "%s@%s.intent" % (work, attempt)))
        seen = self.probe(holder)
        if seen == "absent":
            if done:
                return self.verdict(team, work, holder, "PARKED", "session-absent", why)
            if owner and raw.get("state") in ("failed", "closed"):   # 반쪽(r1968·r1973 꼴) = 세션 0 · owner 남음
                return self.park_seat(team, work, attempt, holder, "launch-failed", why, alive=False, done=False)
            return self.unknown_seat(team, work, attempt, holder, "owner-orphan" if owner else "session-absent", why)
        if seen != "alive":
            return self.unknown_seat(team, work, attempt, holder, "tmux-error", seen)
        intent = endings.intent(self, team, work, attempt, holder)
        if not intent.get("worktree") or not os.path.isdir(intent["worktree"]):   # 새 꼴(worktree 칸 없음·폴더 없음)
            return self.unknown_seat(team, work, attempt, holder, "intent-bad", "worktree %r" % intent.get("worktree"))
        return self.settle_alive(team, work, attempt, holder, intent, done, why)

    def look(self, team, work, attempt, holder, age, stop, wait="jsonl-active"):
        """A13 한 판독(설계 §13) → "REST"(쉼 · 닫기 판독 통과) 또는 판정 낱말(줄은 여기서 냄) — 모든 닫기 길 공용.
        1차 = tmuxc clean(shell-only) + CPU(후손 pid) + jsonl 나이 · pane 글자 0 · 2차(pane 끝 12줄) = 그 좌석 1차를 못 세운 때만.
        판독 실패 = WORKING 아님(probe-fail · session-none = UNKNOWN [긴급]) · age·stop = jsonl 무활동 초·마지막 줄(파일 없음 = None)."""
        status, info = self.tmuxc_status(holder), self.pane_info(holder)
        shell = status == "shell"   # 1차 성립 = clean rc0 ∧ raw pane_pid ∧ ps ∧ 세션 파일(clean 은 list-panes 실패를 rc0 빈 출력으로 삼킴 · arch #308361)
        miss = "tmuxc 없음·실패" if status is None else "pane_pid 판독 실패" if info is None else "ps 판독 실패" if self.ps_rows() is None else ""
        miss = miss or ("세션 파일 없음" if age is None else "")
        self.cache.setdefault("@round", {}).setdefault("first", {})[holder] = not miss   # kill 직전 가드가 tmuxc-mismatch 를 가름
        if miss:
            pane = self.pane2(holder)
            two = " · 판독 2차(%s)" % miss
            if pane is None:
                return self.unknown_seat(team, work, attempt, holder, "probe-fail", "1차 %s · capture 실패" % miss)
            if pane == "busy":
                return self.verdict(team, work, holder, "WORKING", "pane-working", "Working" + two)
            if age is None:   # 닫기에 필요한 jsonl 무활동을 못 잼
                return self.unknown_seat(team, work, attempt, holder, "session-none", "pi 세션 파일 없음" + two)
            if pane == "pending":
                return self.verdict(team, work, holder, "WORKING", "pane-pending", "쉼 표본 1개" + two)
            cpu = "idle"   # 2차 쉼 ×2 = CPU idle ×2 자리
            self.cache["@round"].setdefault("two", {})[holder] = two[3:]   # 닫기 판정 줄 꼬리 «판독 2차(<사유>)»(verdict 가 붙임)
        else:
            cpu = "unknown" if shell else self.cpu(holder, info)
        if cpu == "busy":
            return self.verdict(team, work, holder, "WORKING", "cpu-busy")
        if not shell and stop not in (None, "stop") and age is not None and age >= WAIT_S and cpu == "idle":
            return self.unknown_seat(team, work, attempt, holder, "waiting-input", "마지막 줄 %s · 무활동 %d분" % (stop, age // 60))
        idle = age is not None and age >= PARK_IDLE and (shell or cpu == "idle")   # CPU 단독 = 근거 0
        if not idle:
            return self.verdict(team, work, holder, "WORKING", wait if age is None or age < PARK_IDLE else "cpu-" + cpu)
        if not shell and stop != "stop":
            return self.unknown_seat(team, work, attempt, holder, "turn-open", "마지막 줄 %s" % stop)
        self.cache["@round"].setdefault("shell", {})[holder] = shell
        return "REST"

    def seat_path(self, seat):
        """tmux #{session_path} · 바퀴당 좌석 1회 · 못 읽음 = ""."""
        book = self.cache.setdefault("@round", {}).setdefault("spath", {})
        if seat not in book:
            rc, out, _ = self.call([self.tmux, "display-message", "-p", "-t", "=" + seat + ":", "#{session_path}"])
            book[seat] = out.strip() if rc == 0 and out.strip().startswith("/") else ""
        return book[seat]

    def seat_born(self, seat):
        """tmux #{session_created}(좌석 시작 epoch 초) · 못 읽음 = None."""
        rc, out, _ = self.call([self.tmux, "display-message", "-p", "-t", "=" + seat + ":", "#{session_created}"])
        return float(out.strip()) if rc == 0 and out.strip().isdigit() else None

    def seat_turn(self, seat):
        """장기 좌석(intent 없음) jsonl 나이(arch #308361 Q1) · 마지막 줄 판독 0(stop 으로 봄) · 못 정함 = (None, None) → 한 판독 2차·session-none.
        ① 재개 기록 seat-resume/<세션명>.json 의 jsonl 칸(파일 실재할 때만 · mtime = 나이)
        ② 없으면 session_path 의 pi(`--<cwd>--`)·claude(projects/<cwd `/`·`.` → `-`>) 폴더 최신 *.jsonl = 상한 — 무활동 ≥ PARK_IDLE = 그 나이 ·
        더 최근 ∧ 같은 session_path 에 살아 있는 byz 세션 2개 이상 = 누구 것인지 못 가름(None) · 혼자 쓰는 폴더 = 그 나이 · jsonl 0 = None."""
        home = self.env.get("HOME") or os.path.expanduser("~")
        doc = self.read_json(os.path.join(self.env.get("FT2_SEAT_RESUME_DIR") or os.path.join(home, ".claude", "state", "seat-resume"), seat + ".json"))
        log = str(doc.get("jsonl") or "") if isinstance(doc, dict) else ""
        if log and os.path.isfile(log) and self.resume_ok(seat):   # R2 검증을 통과한 기록만(칸이 있다는 것만으로 0)
            return self.now() - os.path.getmtime(log), "stop"
        cwd, born = self.seat_path(seat), self.seat_born(seat)
        if not cwd or born is None:
            return None, None
        pi = self.env.get("FT2_PI_SESSIONS") or os.path.join(home, ".pi", "agent", "sessions")
        claude = self.env.get("FT2_CLAUDE_PROJECTS") or os.path.join(home, ".claude", "projects")
        files = glob.glob(os.path.join(pi, "--%s--" % cwd.strip("/").replace("/", "-"), "*.jsonl")) + glob.glob(os.path.join(claude, re.sub(r"[/.]", "-", cwd), "*.jsonl"))
        times = [t for t in map(os.path.getmtime, files) if t >= born]   # 좌석 시작(session_created) 뒤에 쓰인 jsonl 만
        if not times:
            return None, None
        age = self.now() - max(times)
        if age < PARK_IDLE and sum(1 for x in self.alive_sessions() if x.startswith("byz-") and self.seat_path(x) == cwd) >= 2:
            return None, None
        return age, "stop"

    def pane2(self, holder):
        """2차 판독 — capture-pane 끝 12줄(입력줄 ❯·› 뒤 글자 = 근거 0) Working·esc to interrupt·스피너 = busy · 없음 표본 2개(간격 ≥ 30초) = rest · 1개 = pending · capture 실패 = None."""
        rc, pane, _ = self.call([self.tmux, "capture-pane", "-p", "-t", "=" + holder + ":"])
        if rc != 0:
            return None
        book, now = self.state.setdefault("pane2", {}), self.now()
        if working(pane):
            book.pop(holder, None)
            return "busy"
        first = book.setdefault(holder, {"first": now})["first"]
        book[holder]["at"] = now
        return "rest" if now - first >= CPU_GAP else "pending"

    def settle_alive(self, team, work, attempt, holder, intent, done, why):
        got = self.look(team, work, attempt, holder, *self.pi_turn(intent))
        if got != "REST":
            return got
        shell = self.cache["@round"]["shell"][holder]
        bad = self.unsafe(team, work, holder, intent, done)
        if bad:
            return self.unknown_seat(team, work, attempt, holder, "shell-only-unsafe" if shell else bad, why)
        return self.park_seat(team, work, attempt, holder, "idle-done", ("shell-only · " if shell else "") + why, alive=True, done=done)

    def unsafe(self, team, work, seat, intent, done):
        """남길 것 안전 = 사유 "" · clean ∧ (HEAD = origin 같은 가지 ∨ base 위 커밋 0) ∧ 미수신 쪽지 0 ∧ 미확정·효과 표식 0."""
        tree = intent["worktree"]
        rc, out, _ = self.git(tree, "status", "--porcelain")
        if rc != 0 or out.strip():
            return "git-error" if rc != 0 else "dirty"
        branch = self.git(tree, "rev-parse", "--abbrev-ref", "HEAD")[1].strip()
        rc, heads, _ = self.git(tree, "rev-parse", "HEAD", "refs/remotes/origin/" + branch)
        if not (rc == 0 and len(set(heads.split())) == 1):
            base = str(intent.get("base_sha") or "")
            if not base or self.git(tree, "rev-list", "--count", base + "..HEAD")[:2] != (0, "0\n"):
                return "unpushed"
        rc, out, _ = self.call(["bash", self.mbox, "peek", seat])
        got = re.search(r"pending=(\d+)", out or "")
        if rc != 0 or not got or int(got.group(1)):
            return "mail-pending" if got and rc == 0 else "mail-unknown"
        ex = cli._load("dispatch").Dispatch(self.root, team).ex
        state, records = ex._state_records()
        hold = ex._hold(state, records, work, (state.get("generations") or {}).get(work, 0), rotation=True)
        return "uncertain" if hold is not None and not done else ""

    def park_seat(self, team, work, attempt, holder, reason, tail, alive, done):
        """PARKED 실행 — 정지 중 = «예정 PARKED» 1줄 · 아니면 kill(살아 있으면) → park 1줄(done 0 일 때만) · 실패 = UNKNOWN."""
        if self.halt:
            return self.verdict(team, work, holder, "예정 PARKED", reason, "정지 중 kill·park 0")
        if alive:
            if not self.idle(team, work, holder, attempt):   # kill 직전 가드(마지막 확인 1회)
                return "WORKING"
            if self.held_attached(team, work, holder):
                return "UNKNOWN"
            self.call([self.tmux, "kill-session", "-t", "=" + holder])
            seen = self.probe(holder)
            if seen != "absent":
                return self.unknown_seat(team, work, attempt, holder, "kill-failed", seen)
            self.state["open"].pop(holder, None)
        if not done:
            out, rc = cli.run(["park", "--work", work, "--attempt", attempt, "--reason", reason, "--root", self.root, "--team", team])
            if rc != 0:
                return self.unknown_seat(team, work, attempt, holder, "park-refused", "%s %s" % (out.get("result"), out.get("reason", "")[:60]))
        return self.verdict(team, work, holder, "PARKED", reason, tail)

    def wide_landed(self, team, work, intent, done):
        """A7 착지 근거 넓힘 — (원장 done ∧ 카드 완성 폴더) ∨ 가지 커밋 전부 base 에 있음(git cherry 전부 −) · 가지 이름 무관 · 못 채움 = ""."""
        cards = self.resolve_card(team, work)[0]
        if done and not isinstance(cards, str) and any("/indices/완성/" in path for _, path in cards):
            return "done-card-완성"
        tree, base = intent.get("worktree") or "", intent.get("base") or ""
        if not (tree and base and os.path.isdir(tree)):
            return ""
        rc, out, _ = self.git(tree, "cherry", base, "HEAD")
        lines = out.split() and out.splitlines()
        return "cherry-all-in-base" if rc == 0 and lines and all(x.startswith("-") for x in lines) else ""

    def accept_only(self, team, rows):
        """⑪ accept 만(dispatch 0) · PARK_IDLE 넘음 · 의무 장부에 남음 → UNKNOWN accept-only 1개(work 단위)."""
        state = PROJ.record.recover_state(PROJ.journal.Journal(PROJ.runtime_path(self.root, team), rec=PROJ.record).state(), rows)
        left, sent, first = set(PROJ.record.remaining(state, rows)), {r.get("work") for r in rows if r["kind"] == "dispatch" and isinstance(r.get("work"), str)}, {}
        for rec in rows:
            if rec["kind"] == "accept" and rec["command"] in left and isinstance(rec.get("work"), str) and rec["work"] not in sent:   # ㉕ work 가 str 아님 = work 없는 접수(core record.remaining·capacity 규칙)
                first.setdefault(rec["work"], rec)
        for work, rec in sorted(first.items()):
            try:
                age = self.now() - datetime.datetime.strptime(rec["at"], "%Y-%m-%dT%H:%M:%S").timestamp()
            except ValueError:
                continue
            if age >= PARK_IDLE:
                n = sum(1 for r in rows if r["kind"] == "accept" and r.get("work") == work and r["command"] in left)
                self.unknown_seat(team, work, rec["attempt"], "-", "accept-only", "접수 %d줄 · %d분" % (n, age // 60))

    def tmuxc_status(self, seat):
        """tmuxc 상태 칸(agent | shell | None) — tmuxc UC6 `clean`(읽기만 · 바퀴당 1회 · 7초) 출력 = shell-only 세션 · 그 밖 = agent ·
        tmuxc 없음·실패 = None(대조 0) · 경로 = FT2_TMUXC 또는 ~/.local/bin/tmuxc."""
        got = self.cache.setdefault("@round", {})
        if "tmuxc" not in got:
            tool = self.env.get("FT2_TMUXC") or os.path.join(self.env.get("HOME") or os.path.expanduser("~"), ".local", "bin", "tmuxc")
            rc, out, _ = self.call([tool, "clean"]) if os.access(tool, os.X_OK) else (None, "", "")
            got["tmuxc"] = set(out.splitlines()) - {""} if rc == 0 else None
        return None if got["tmuxc"] is None else "shell" if seat in got["tmuxc"] else "agent"

    def ready_seen(self, new, old):
        """후계 [레디] 영수 = 우편함(mailbox.jsonl · mailbox.log.jsonl)에 from new · to old · «[레디] new <- old» 줄 · 바퀴당 1회 읽기."""
        got = self.cache.setdefault("@round", {})
        if "ready" not in got:
            comm, pairs = self.env.get("FT2_MAILBOX_DIR") or os.path.join(self.root, ".fable-team", "comm"), set()
            for name in ("mailbox.jsonl", "mailbox.log.jsonl"):
                try:
                    with open(os.path.join(comm, name), encoding="utf-8", errors="replace") as fh:
                        rows = [json.loads(x) for x in fh if "[레디]" in x]
                except (OSError, ValueError):
                    continue
                pairs |= {(r.get("from"), r.get("to")) for r in rows if isinstance(r, dict)
                          and str(r.get("body", "")).startswith("[레디] %s <- %s" % (r.get("from"), r.get("to")))}
            got["ready"] = pairs
        return (new, old) in got["ready"]

    def resume_ok(self, seat):
        """hil.md 검증된 재개 기록 = seat-resume/<세션명>.json(ft-seat-retire) · name 같음 · codex 아님 · 작업 폴더가 keeper roots 안 ·
        대화 결속 = jsonl 칸이 실제 파일 ∧ 파일 이름이 uuid 로 끝남 ∧ 담긴 폴더 = 그 cwd 의 세션 폴더(pi `--<cwd>--` · claude `/`·`.` → `-`)."""
        home = self.env.get("HOME") or os.path.expanduser("~")
        doc = self.read_json(os.path.join(self.env.get("FT2_SEAT_RESUME_DIR") or os.path.join(home, ".claude", "state", "seat-resume"), seat + ".json"))
        cwd, uuid, log = str(doc.get("cwd") or ""), str(doc.get("uuid") or ""), str(doc.get("jsonl") or "")
        if doc.get("name") != seat or not uuid or doc.get("engine") == "codex" or not any((cwd + "/").startswith(r + "/") for r in self.roots()):
            return False
        folders = ("--%s--" % cwd.strip("/").replace("/", "-"), re.sub(r"[/.]", "-", cwd))
        return os.path.isfile(log) and os.path.basename(log).endswith(uuid + ".jsonl") and os.path.basename(os.path.dirname(log)) in folders

    def roots(self):
        """S1 keeper roots(FETCH_TARGETS 와 같은 표 · BYZ root · 팩) — 있는 폴더만 · 중복 0."""
        both = (self.root, self.pack)
        return [r for i, r in enumerate(both) if r and os.path.isdir(r) and r not in both[:i]]

    def rosters(self):
        """S1 모든 roots 의 명부 [(경로, 행 dict)] · 바퀴당 1회."""
        got = self.cache.setdefault("@round", {})
        if "rosters" not in got:
            paths = [p for r in self.roots() for p in sorted(glob.glob(os.path.join(r, ".fable-team", "seats*.json")))]
            got["rosters"] = [(p, rows) for p in paths for rows in [self.read_json(p)] if isinstance(rows, dict)]
        return got["rosters"]

    def seat_kind(self, seat, row):
        """S1 좌석 종류 = 명부 role 칸(종류 낱말일 때) · 상태 낱말(stop-ready 등)·칸 없음 = 이름 셋째 토큰."""
        role = row.get("role") if isinstance(row, dict) else None
        return role if role in KINDS else (seat.split("-") + ["", ""])[2]

    def bound(self, seat, new):
        """S2 이름 바뀐 승계 결속 = 명부 seat._replaced_by == new ∧ new._replaces == seat(어느 roots 명부든)."""
        rows = {}
        for _, got in self.rosters():
            rows.update({key: val for key, val in got.items() if isinstance(val, dict)})
        return (rows.get(seat) or {}).get("_replaced_by") == new and (rows.get(new) or {}).get("_replaces") == seat

    def keep_gate(self, seat, new, alive):
        """S2 닫기 자격 — 계보(base#N · 이름 바뀐 승계는 양방향 결속 ∧ 후계 생존일 때만 새 세대로 셈) 순번 1 = keep-recent · 순번 2 = 검증된 재개 기록 있을 때만 · 그 밖 keep-last-2 · 3 이상 = 자격 있음("")."""
        base, _, n = seat.rpartition("#")
        newer = {x for x in alive if x.rpartition("#")[0] == base and x.rpartition("#")[2].isdigit() and n.isdigit() and int(x.rpartition("#")[2]) > int(n)}
        newer |= {new} if new and new in alive and new.rpartition("#")[0] != base and self.bound(seat, new) else set()
        if not newer:
            return "keep-recent"
        if len(newer) == 1 and not self.resume_ok(seat):
            return "keep-last-2"
        return ""

    def closed_seats(self):
        """ft2 close 영수가 있는 좌석 이름(모든 팀 state.close_receipts) · 바퀴당 1회."""
        got = self.cache.setdefault("@round", {})
        if "closed" not in got:
            seats = set()
            for team in self.teams():
                try:
                    state = cli._load("dispatch").Dispatch(self.root, team).ex._state_records()[0]
                except ValueError:
                    continue
                seats |= {row.get("seat") for row in (state.get("close_receipts") or {}).values()}
            got["closed"] = seats
        return got["closed"]

    def outsiders(self, alive, known):
        """S1·S3 — 살아 있는 byz-* 중 어느 명부·최신 dispatch·나노 이름에도 없는 세션 = UNKNOWN roster-outside · 이름 lint 실패 = name-bad · kill 0."""
        scope = getattr(self, "orphan_scope", set())   # 이 바퀴 고아 길(endings.orphans)이 판정한 팀 · 정지 중 = 빈 집합(고아 꼴도 여기서 판정)
        for seat in sorted(x for x in alive if x.startswith("byz-") and x not in known and not ((m := endings.ORPHAN.fullmatch(x)) and m.group(1) in scope)):
            team = (seat.split("-") + [""])[1]
            if team in self.skip:   # r1835 K2 — 제외 팀 좌석 = 손 0
                continue
            self.unknown_seat(team, "-", "-", seat, "roster-outside" if NAME.fullmatch(seat) else "name-bad")
