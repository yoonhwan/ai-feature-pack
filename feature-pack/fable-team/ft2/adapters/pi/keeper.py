#!/usr/bin/env python3
"""ft 2.0 keeper — 끝난 좌석 자동 닫기 (r1812 · 카드 B0~B5 · DA r1 APPROVE).

core 는 일을 기록만 하고 좌석을 닫지 않는다(close_next «kill = 호출자»). 그 닫는 호출자가 이 명령이다.
한 바퀴(--once) = 잠금 O_EXCL → git fetch(리포당 1회) → 팀마다 B1 complete 누락 잡기 → B2 착지 끝 나노 세션 닫기 →
B3 승계 끝 옛 좌석(ft-seat-close 가드 그대로) → B4 보고. core 손 0 — 공개 동사(cli.run)·공개 API(project·CloseNext)만 부른다.
상한: git 25초 · tmux·쪽지 7초(쪽지 재시도 1) · 바퀴 60초. 바깥 호출 실패 = 판정 불가 1줄(하드 룰 20) · 쓰기·kill 0.
kill = tmux 세션 1개씩(kill-server 0) · 대상 = launch intent 의 FT2_HOLDER 나노만 · 워크트리·가지·명부 행 삭제 0.
    python3 core/cli.py keeper --root R (--once | --report) [--pack 팩리포]
"""
import datetime, glob, importlib.util, json, os, re, subprocess, sys, time  # noqa: E401

FT2 = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GIT_S, CALL_S, ROUND_S, RETRY_S, OPEN_S, STALE_S = 25, 7, 60, 600, 1800, 600
REFS = ("origin/ops/main-base", "origin/main")       # BYZ 카드·착지 ref (B1r 순서)
STAGES = ("진행", "대기", "완성")
LAND = re.compile(r"^- 착지: ([0-9a-f]{40})\s*$", re.M)
BUSY = re.compile("Working|[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]")
OK, HOLD = "접수 성공", "완료 유보"


def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_keeper_" + name, os.path.join(FT2, "core", name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


cli, projection, close_next = _load("cli"), _load("projection"), _load("close_next")


class Keeper:
    def __init__(self, root, env=None, now=None):
        self.root, self.env, self.now = os.path.abspath(root), dict(os.environ if env is None else env), now or time.time
        self.pack = self.env.get("FT2_PACK_REPO") or os.path.expanduser("~/Project/ai-feature-pack")
        self.tmux, self.close_bin = self.env.get("FT_TMUX") or "tmux", self.env.get("FT_SEAT_CLOSE_BIN") or ""
        self.mbox = self.env.get("FT2_KEEPER_MBOX") or os.path.join(self.root, ".fable-team", "comm", "mbox.sh")
        self.dir = os.path.join(self.root, ".fable-team", "state", "ft2-keeper")
        self.project, self.lines, self.cache = projection.project, [], {}
        self.state = {key: {} for key in ("held", "open", "sent", "handled")}
    def call(self, argv, timeout=CALL_S, retry=0):
        """바깥 호출 1곳 → (rc, stdout, stderr 1줄) · 넘침·실행 실패 = rc None · retry = rc≠0 때 다시 부르는 횟수."""
        for _ in range(retry + 1):
            try:
                done = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, env=self.env, cwd=self.root)
                out = (done.returncode, done.stdout, done.stderr.strip()[:200])
            except (OSError, subprocess.TimeoutExpired) as exc:
                out = (None, "", str(exc)[:200])
            if out[0] == 0: break
        return out
    def git(self, repo, *args, retry=0):
        return self.call(["git", "-C", repo] + list(args), GIT_S, retry)
    def stamp(self):
        return datetime.datetime.fromtimestamp(self.now()).strftime("%Y-%m-%dT%H:%M:%S")
    def log(self, kind, team="", text=""):
        """로그 1줄 = 출력 + state/ft2-keeper/<YYYYMMDD>.jsonl append. 반환 None(= 거짓 · `return self.log(...)` 로 끝낸다)."""
        line, at = " ".join(w for w in (kind, team, text) if w), self.stamp()
        self.lines.append(line), os.makedirs(self.dir, exist_ok=True)
        with open(os.path.join(self.dir, at[:10].replace("-", "") + ".jsonl"), "a", encoding="utf-8") as fh:
            fh.write(json.dumps({"at": at, "kind": kind, "team": team, "line": line}, ensure_ascii=False) + "\n")
    @staticmethod
    def read_json(path):
        try:
            with open(path, encoding="utf-8") as fh:
                data = json.load(fh)
        except (OSError, ValueError):
            return {}
        return data if isinstance(data, dict) else {}
    def probe(self, seat):
        """tmux 부재 판독기 — rc1 + «can't find session»(서버 없음 포함) = absent · rc0 = alive · 그 밖 = 판정 불가 문자열."""
        rc, _, err = self.call([self.tmux, "has-session", "-t", "=" + seat])
        if rc == 1 and ("can't find session" in err or "no server running" in err): return "absent"
        return "alive" if rc == 0 else "판정 불가 · tmux has-session rc %s %s" % (rc, err)
    def locked(self, body):
        """잠금 O_EXCL 1개 — 앞 바퀴 진행 중 = 바퀴 0 · 로그 1줄. 10분 넘은 잠금(죽은 바퀴)은 지우고 1줄. 상태 = 원자 쓰기."""
        os.makedirs(self.dir, exist_ok=True)
        lock = os.path.join(self.dir, "keeper.lock")
        if os.path.exists(lock) and time.time() - os.path.getmtime(lock) > STALE_S: os.unlink(lock), self.log("STALE-LOCK", text="10분 넘은 잠금을 지움")
        try:
            os.close(os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644))
        except FileExistsError:
            return self.log("SKIP", text="앞 바퀴 진행 중(잠금) — 바퀴 0")
        try:
            self.state.update(self.read_json(os.path.join(self.dir, "state.json")))
            out = body()
            with open(os.path.join(self.dir, "state.json.tmp"), "w", encoding="utf-8") as fh:
                json.dump(self.state, fh, ensure_ascii=False, sort_keys=True)
            os.replace(os.path.join(self.dir, "state.json.tmp"), os.path.join(self.dir, "state.json"))
            return out
        finally:
            os.unlink(lock)
    def run_once(self):
        return self.locked(self._round) or 0
    def report_once(self):
        return self.locked(self.report) or "판정 불가 · 바퀴 진행 중"
    def _round(self):
        start, bad = time.monotonic(), [r for r in (self.root, self.pack) if self.git(r, "fetch", "-q", "origin", retry=1)[0] != 0]
        if bad: self.log("판정 불가", text="git fetch 실패 %s — 이 바퀴 B1·B2 0" % " ".join(bad))
        for team in [] if bad else self.teams():
            if time.monotonic() - start > ROUND_S:
                self.log("ROUND-CAP", text="60초 넘음 — 남은 팀은 다음 바퀴")
                break
            self.team_round(team)
        self.retired(), self.report()
    def teams(self):
        """대상 팀 = ft20-switch/<팀>.json ∪ <팀>.held 가 있고 runtime 이 있는 팀."""
        switch = os.path.join(self.root, ".fable-team", "state", "ft20-switch")
        names = {n.rsplit(".", 1)[0] for n in (os.listdir(switch) if os.path.isdir(switch) else []) if n.endswith((".json", ".held"))}
        return sorted(t for t in names if os.path.isdir(projection.runtime_path(self.root, t)))
    def team_round(self, team):
        """최신 묶음 = work 마다 최신 dispatch 1줄의 (attempt · holder) (launch.seat 와 같은 규칙 · 옛 intent 로 대신 0)."""
        proj = self.project(self.root, team)
        if proj.get("result") != OK: return self.log("판정 불가", team, "투영 %s" % proj.get("reason", ""))
        rows = projection.journal.Journal(projection.runtime_path(self.root, team), rec=projection.record).records()
        latest = {rec["work"]: rec.get("attempt") for rec in rows if rec.get("kind") == "dispatch" and rec.get("work")}
        for work, attempt in sorted(latest.items()):
            row = proj["works"].get(work) or {}
            if "%s|%s@%s" % (team, work, attempt) in self.state["handled"]: continue
            if row.get("done") or self.complete(team, work, attempt, self.landing(team, work)): self.close(team, work, attempt, row)
    def cards(self, team):
        """B1r 카드 후보 = TEAMS.md 팀 폴더(쌍둥이 포함) × indices/{진행,대기,완성} × REFS (git 읽기만 · 작업 트리 0)."""
        if team in self.cache: return self.cache[team]
        out = []
        for ref in REFS:
            rc, md, _ = self.git(self.root, "show", ref + ":design/TEAMS.md")
            row = next((c for c in ([x.strip() for x in ln.strip().strip("|").split("|")] for ln in md.splitlines()) if c[0] == team and len(c) > 1), None)
            if rc != 0 or row is None:
                out = "판정 불가 · %s:design/TEAMS.md rc %s 팀 행 %s" % (ref, rc, "있음" if row else "없음")
                break
            base = row[1].strip("`").replace("$FT_HARNESS_ROOT/", "").strip("/")
            twin = base.replace("design/teams/", "design/", 1) if "/teams/" in base else base.replace("design/", "design/teams/", 1)
            for folder in dict.fromkeys([base, twin]):
                rc, names, _ = self.git(self.root, "ls-tree", "-r", "--name-only", ref, "--", folder + "/indices")
                out = out + [(ref, p) for p in names.splitlines() if p[len(folder) + 9:].partition("/")[0] in STAGES
                             and p.count("/") == folder.count("/") + 3] if rc == 0 else "판정 불가 · ls-tree %s rc %s" % (ref, rc)
                if rc != 0: break
            if isinstance(out, str): break
        self.cache[team] = out
        return out
    def landing(self, team, work):
        """(sha, ref, 사유) — 마지막 `- 착지: <sha40>` 줄 · 후보 0·충돌 = 판정 불가 · 어느 ref 에도 조상 아님 = 미도달."""
        cards, hits = self.cards(team), {}
        if isinstance(cards, str): return None, None, cards
        for ref, path in cards:
            if os.path.basename(path).startswith(work + "-") and path.endswith(".md"):
                rc, body, _ = self.git(self.root, "show", "%s:%s" % (ref, path))
                if rc != 0: return None, None, "판정 불가 · git show %s rc %s" % (path, rc)
                hits[(ref, path)] = (LAND.findall(body) or [None])[-1]
        shas = sorted({v for v in hits.values() if v})
        if not hits or len(shas) > 1: return None, None, "판정 불가 · " + ("카드 후보 0" if not hits else "착지 줄 충돌 " + " ".join(shas))
        sha = (shas or [None])[0]
        for repo, ref in ((self.pack, "origin/main"), (self.root, REFS[0]), (self.root, REFS[1])) if sha else ():
            if self.git(repo, "merge-base", "--is-ancestor", sha, ref)[0] == 0: return sha, ("pack:" if repo == self.pack else "byz:") + ref, ""
        return sha, None, "미도달" if sha else "착지 줄 없음"
    def done(self, team, work):
        proj = self.project(self.root, team)
        return proj.get("result") == OK and bool((proj.get("works", {}).get(work) or {}).get("done"))
    def complete(self, team, work, attempt, land):
        """B1 — 착지 sha 가 조상일 때만 complete 1회 → 투영 done 재확인 뒤에만 참(= B2 로 간다 · Q1)."""
        sha, ref, why = land
        if why == "미도달": self.notify(team, "unreached|%s|%s|%s" % (team, work, sha), "[크리티컬] 착지 줄 sha 미도달 %s %s %s" % (team, work, sha))
        if why: return self.log("HELD", team, "%s %s" % (work, why))
        out, _rc = cli.run(["complete", "--root", self.root, "--team", team, "--work", work, "--attempt", attempt])
        if not self.done(team, work): return self.log("판정 불가", team, "%s complete 뒤 done 확인 못 함(%s) — B2 0" % (work, out.get("result")))
        return self.log("COMPLETED", team, "%s 착지 %s ref %s" % (work, sha, ref)) or True
    def close(self, team, work, attempt, row):
        """B2 — intent holder 나노 · 착지 조상 · pane 유휴 → kill 1 → 부재 확인 → 닫기 영수(공개 API)."""
        intent = self.read_json(os.path.join(projection.runtime_path(self.root, team), "launch", "%s@%s.intent" % (work, attempt)))
        holder, gen = intent.get("FT2_HOLDER"), row.get("gen") or 1
        if intent.get("state") != "opened" or not holder: return
        why = self.landing(team, work)[2]
        seen = why or self.probe(holder)
        if seen == "alive":
            self.state["open"].setdefault(holder, {"team": team, "since": self.now()})
            rc, pane, _ = self.call([self.tmux, "capture-pane", "-p", "-t", "=" + holder])
            if rc != 0: return self.log("HELD", team, "%s %s 판정 불가 · capture rc %s" % (work, holder, rc))
            if BUSY.search(pane[-2000:]): return self.log("HELD", team, "%s %s Working" % (work, holder))
            self.call([self.tmux, "kill-session", "-t", "=" + holder])
            seen = self.probe(holder)
            if seen != "absent": return self.log("HELD", team, "%s %s 부재 확인 없음(%s)" % (work, holder, seen))
            self.log("CLOSED-SESSION", team, "%s %s" % (work, holder))
        elif seen != "absent": return self.log("HELD", team, "%s %s %s" % (work, holder, seen))
        self.state["open"].pop(holder, None), self.receipt(team, work, attempt, holder, gen)
    def receipt(self, team, work, attempt, holder, gen, probe=None):
        """닫기 영수 = CloseNext(probe).receipt 같은 프로세스 · 증거(v1·v2)는 만들지 않는다(다음 배정 = 팀장 몫)."""
        out = close_next.CloseNext(self.root, team, probe=probe or self.probe).receipt(
            holder, gen, work, "keeper:%s@%s" % (work, attempt), holder, ())
        kind = {OK: "RECEIPT", "접수 거부": "RECEIPT-REFUSED"}.get(out.result, "RECEIPT-HOLD" if "켜기 전" in out.reason else "RECEIPT-UNSURE")
        self.log(kind, team, "%s %s %s · %s" % (work, holder, out.result, out.reason))
        if kind in ("RECEIPT", "RECEIPT-HOLD") or "재접수" in out.reason: self.state["handled"]["%s|%s@%s" % (team, work, attempt)] = self.stamp()
        return out
    def retired(self):
        """B3② — 명부 `_replaced_by` 행 + 세션 생존 → ft-seat-close 1회 · 실패·HELD 는 10분 안 재시도 0."""
        for path in sorted(glob.glob(os.path.join(self.root, ".fable-team", "seats*.json"))):
            name = os.path.basename(path)[:-5]
            for seat, row in sorted(self.read_json(path).items()):
                new = row.get("_replaced_by") if isinstance(row, dict) else None
                if not isinstance(new, str) or not new: continue
                if self.probe(seat) != "alive":
                    self.state["open"].pop(seat, None)
                    continue
                self.state["open"].setdefault(seat, {"team": name[6:] if name.startswith("seats-") else "v65", "since": self.now()})
                if self.now() - self.state["held"].get(seat, -RETRY_S) < RETRY_S: continue
                if not self.close_bin: return self.log("판정 불가", text="ft-seat-close 경로 없음(FT_SEAT_CLOSE_BIN) — B3 0")
                rc, out, err = self.call(["bash", self.close_bin, seat, "--reason", "retire -> " + new, "--seats", path], GIT_S)
                self.log("CLOSED-SEAT" if rc == 0 else "HELD-SEAT", name, "%s rc %s %s" % (seat, rc, ((out or err).strip().splitlines() or [""])[0][:160]))
                self.state["held"][seat] = self.now()
                if rc == 0: self.state["held"].pop(seat), self.state["open"].pop(seat, None)
    def notify(self, team, key, body):
        """팀 master 에 쪽지 1통(7초 + 재시도 1) · 같은 열쇠 재발신 0 · 실패 = 판정 불가 1줄."""
        if key in self.state["sent"]: return False
        master = self.read_json(os.path.join(self.root, ".fable-team", "seats-%s.json" % team)).get("_master")
        rc = self.call(["bash", self.mbox, "send", master, "ft2-keeper", body], CALL_S, retry=1)[0] if master else "_master 없음"
        if rc != 0: return self.log("판정 불가", team, "쪽지 %s — %s" % (rc, body[:80]))
        self.state["sent"][key] = self.stamp()
        return self.log("NOTIFIED", team, "%s %s" % (master, body[:120])) or True
    def report(self):
        """B4 — 끝난 뒤 30분 넘게 열린 좌석 N 1줄 · N>0 = 팀 master [크리티컬] 1통(하루 같은 좌석 1회)."""
        late, day = {}, self.stamp()[:10]
        for seat, v in sorted(self.state["open"].items()):
            seen = self.probe(seat)
            if seen == "absent": self.state["open"].pop(seat)
            elif self.now() - v["since"] > OPEN_S and seen == "alive": late.setdefault(v["team"], []).append(seat)
        line = "손 닫기 후보 %d(끝난 뒤 30분 넘게 열린 좌석)" % sum(map(len, late.values()))
        for team, seats in sorted(late.items()):
            fresh = [s for s in seats if "%s|open|%s" % (day, s) not in self.state["sent"]]
            if fresh and self.notify(team, "%s|open|%s" % (day, fresh[0]), "[크리티컬] %s · %s %s" % (line, team, " ".join(fresh))):
                self.state["sent"].update({"%s|open|%s" % (day, s): self.stamp() for s in fresh})
        return line



def main(argv):
    flags, rest = [a for a in argv if a in ("--once", "--report")], [a for a in argv if a not in ("--once", "--report")]
    opts = dict(zip(rest[::2], rest[1::2]))
    if len(flags) != 1 or len(rest) % 2 or set(opts) - {"--root", "--pack"} or "--root" not in opts:
        sys.stdout.write(json.dumps({"result": "사용법", "reason": "keeper --root R (--once | --report) [--pack P]"}, ensure_ascii=False) + "\n")
        return 64
    keeper = Keeper(opts["--root"], dict(os.environ, **({"FT2_PACK_REPO": opts["--pack"]} if "--pack" in opts else {})))
    line = keeper.run_once() if flags[0] == "--once" else keeper.report_once()
    sys.stdout.write("".join(x + "\n" for x in keeper.lines) + ("" if flags[0] == "--once" else line + "\n"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
