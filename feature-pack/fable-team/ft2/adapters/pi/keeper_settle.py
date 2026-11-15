"""ft 2.0 keeper — r2055 settle() 한 길 (keeper.py 가 섞어 쓴다 · 설계 design/harness/DESIGN-r2055-seat-settle-one-path.md r8).

좌석마다 판정 1개 = LANDED(착지 끝) · PARKED(끝남 ∧ 남길 것 안전 → kill + core park) · WORKING(손 0) · UNKNOWN(kill 0 + [긴급]).
«일하나» 는 tmuxc 규칙을 같은 값으로 쓴다(UC12 CPU 문턱·간격 · pane_descendant_pids 깊이 8 · cmd_clean 셸 목록).
★CPU idle 단독은 유휴·닫기 근거 0★ — 유휴 = jsonl 무활동 ≥ PARK_IDLE ∧ CPU idle 2회(셸만 남은 pane 은 CPU 무관).
정지(.fable-team/state/ALL_STOP.json) 중 = 판정·[긴급]·«예정» 줄만 · kill·park·깨움·fill 0.
"""
import datetime
import importlib.util
import json
import os
import re

PARK_IDLE, WAIT_S, DAY = 3600, 900, 86400   # 유휴 문턱 60분 · 질문 창 15분
CPU_IDLE, CPU_GAP, CPU_DEPTH = 0.3, 30, 8   # tmuxc UC12 %cpu < 0.3 · 표본 간격 ≥ 30초 · pane_descendant_pids 깊이 8
SHELLS = ("zsh", "bash", "fish")            # tmuxc cmd_clean
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


class Settling:
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
        key, book = "%s|%s|%s" % (team, work, seat), self.state.setdefault("verdict", {})
        if book.get(key) != [word, code]:
            book[key] = [word, code]
            self.log(word, team, " ".join(x for x in (work, seat, code) if x) + (" · " + tail if tail else ""))
        return word

    def alert(self, team, work, attempt, seat, code, tail=""):
        tail = self.with_why(tail, work)
        """UNKNOWN [긴급] 1통 — 지문 (team, work, attempt, reason) 하루 1회 · 새 사유·새 attempt = 즉시 · 전송 실패 = 지문 미소비."""
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

    def settle_alive(self, team, work, attempt, holder, intent, done, why):
        rc, pane, _ = self.call([self.tmux, "capture-pane", "-p", "-t", "=" + holder + ":"])
        if rc != 0:
            return self.unknown_seat(team, work, attempt, holder, "capture-error", "capture rc %s" % rc)
        if BUSY.search(pane[-2000:]):
            return self.verdict(team, work, holder, "WORKING", "spinner")
        info = self.pane_info(holder)
        shell = bool(info) and os.path.basename(info[1]) in SHELLS   # tmuxc cmd_clean = 에이전트 끝난 shell-only
        if shell and self.tmuxc_status(holder) == "agent":   # S3 두 도구가 다른 «끝남» = 드러냄
            return self.unknown_seat(team, work, attempt, holder, "tmuxc-mismatch", "tmuxc agent · settle shell-only")
        cpu = "unknown" if shell else self.cpu(holder, info)
        if cpu == "busy":
            return self.verdict(team, work, holder, "WORKING", "cpu-busy")
        age, stop = self.pi_turn(intent)
        if not shell and stop not in (None, "stop") and age is not None and age >= WAIT_S and cpu == "idle":
            return self.unknown_seat(team, work, attempt, holder, "waiting-input", "마지막 줄 %s · 무활동 %d분" % (stop, age // 60))
        idle = age is not None and age >= PARK_IDLE and (shell or cpu == "idle")   # CPU 단독 = 근거 0
        if not idle:
            return self.verdict(team, work, holder, "WORKING", "jsonl-active" if age is None or age < PARK_IDLE else "cpu-" + cpu)
        if not shell and stop != "stop":
            return self.unknown_seat(team, work, attempt, holder, "turn-open", "마지막 줄 %s" % stop)
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
        left, sent, first = set(PROJ.record.remaining(state, rows)), {r.get("work") for r in rows if r["kind"] == "dispatch"}, {}
        for rec in rows:
            if rec["kind"] == "accept" and rec["command"] in left and rec.get("work") and rec["work"] not in sent:
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
        """tmuxc 상태 칸(agent | shell | None) — keeper 는 tmuxc 를 부르지 않는다(§3c) · 주입이 없으면 None(대조 0)."""
        return None

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
        """hil.md 검증된 재개 기록 = seat-resume/<세션명>.json · name 같음 · 대화 uuid 있음 · codex 아님 · 작업 폴더가 이 루트 안."""
        home = self.env.get("HOME") or os.path.expanduser("~")
        doc = self.read_json(os.path.join(self.env.get("FT2_SEAT_RESUME_DIR") or os.path.join(home, ".claude", "state", "seat-resume"), seat + ".json"))
        cwd = str(doc.get("cwd") or "")
        return doc.get("name") == seat and bool(doc.get("uuid")) and doc.get("engine") != "codex" and (cwd + "/").startswith(self.root + "/")

    def keep_gate(self, seat, new, alive):
        """S2 닫기 자격 — 계보(base#N · 이름 바뀐 승계는 살아 있는 후계를 새 세대로 셈) 순번 1 = keep-recent · 순번 2 = 재개 기록 있을 때만 · 그 밖 keep-last-2 · 3 이상 = 자격 있음("")."""
        base, _, n = seat.rpartition("#")
        newer = {x for x in alive if x.rpartition("#")[0] == base and x.rpartition("#")[2].isdigit() and n.isdigit() and int(x.rpartition("#")[2]) > int(n)}
        newer |= {new} if new and new in alive and new.rpartition("#")[0] != base else set()
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
        for seat in sorted(x for x in alive if x.startswith("byz-") and x not in known and not endings.ORPHAN.fullmatch(x)):
            team = (seat.split("-") + [""])[1]
            if team in self.skip:   # r1835 K2 — 제외 팀 좌석 = 손 0
                continue
            self.unknown_seat(team, "-", "-", seat, "roster-outside" if NAME.fullmatch(seat) else "name-bad")
