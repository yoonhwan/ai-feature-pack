#!/usr/bin/env python3
"""ft 2.0 keeper — 끝난 좌석 자동 닫기 (r1812 · 카드 B0~B5 · DA r1 APPROVE).

core 는 일을 기록만 하고 좌석을 닫지 않는다(close_next «kill = 호출자»). 그 닫는 호출자가 이 명령이다.
한 바퀴(--once) = 잠금 O_EXCL → git fetch(리포당 1회) → 팀마다 B1 complete 누락 잡기 → B2 착지 끝 나노 세션 닫기 →
B3 승계 끝 옛 좌석 → B4 보고. 파일 넷: 이 파일(바퀴·잠금) · keeper_land.py(B1·B1r) · keeper_close.py(B2·B3) ·
keeper_report.py(B4·쪽지). 끝나지 않은 일 = r1813 멈춤 갈래(keeper_stall.py · 깨움 → 재배정).
core 손 0 — 공개 동사(cli.run)·공개 API(project·CloseNext)만 부른다. 상한: git 25초 · tmux·쪽지 7초 · 바퀴 60초.
    python3 core/cli.py keeper --root R (--once | --report) [--pack 팩리포]
"""
import datetime
import importlib.util
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
FT2 = os.path.dirname(os.path.dirname(HERE))
GIT_S, CALL_S, ROUND_S, STALE_S, FETCH_S = 25, 7, 60, 600, 7   # r1937 FETCH_S = fetch 1회 7초(+ 재시도 1)
OK = "접수 성공"


def _load(path, alias):
    spec = importlib.util.spec_from_file_location(alias, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


projection = _load(os.path.join(FT2, "core", "projection.py"), "ft2_keeper_projection")
land = _load(os.path.join(HERE, "keeper_land.py"), "ft2_keeper_land")
closing = _load(os.path.join(HERE, "keeper_close.py"), "ft2_keeper_close")
reporting = _load(os.path.join(HERE, "keeper_report.py"), "ft2_keeper_report")
full_alert = _load(os.path.join(HERE, "full_alert.py"), "ft2_keeper_full_alert")   # r1886
hold = _load(os.path.join(HERE, "keeper_hold.py"), "ft2_keeper_hold")   # r1931 카드 HOLD 줄 → holder 깨움


class Keeper(land.Landing, closing.Closing, reporting.Reporting):
    fa = full_alert   # r1886 keeper_land·keeper_next 도 이것으로 부른다
    def __init__(self, root, env=None, now=None):
        self.root = os.path.abspath(root)
        self.env = dict(os.environ if env is None else env)
        self.now = now or time.time
        self.pack = self.env.get("FT2_PACK_REPO") or os.path.expanduser("~/Project/ai-feature-pack")
        self.tmux = self.env.get("FT_TMUX") or "tmux"
        self.close_bin = self.env.get("FT_SEAT_CLOSE_BIN") or ""
        self.mbox = self.env.get("FT2_KEEPER_MBOX") or os.path.join(self.root, ".fable-team", "comm", "mbox.sh")
        self.dir = os.path.join(self.root, ".fable-team", "state", "ft2-keeper")
        self.project, self.lines, self.cache = projection.project, [], {}
        self.state = {key: {} for key in ("held", "open", "sent", "handled", "woke", "reassigned")}
        self.stall = _load(os.path.join(HERE, "keeper_stall.py"), "ft2_keeper_stall").Stall(self)   # r1813 S1~S5
        self.spent, self.sock, self.skip = dict.fromkeys(("fetch", "b1", "b2", "b3", "stall"), 0.0), True, set()

    def call(self, argv, timeout=CALL_S, retry=0):
        """바깥 호출 1곳 → (rc, stdout, stderr 1줄) · 넘침·실행 실패 = rc None · retry = rc≠0 때 다시 부르는 횟수."""
        for _ in range(retry + 1):
            try:
                done = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, env=self.env, cwd=self.root)
                out = (done.returncode, done.stdout, done.stderr.strip()[:200])
            except (OSError, subprocess.TimeoutExpired) as exc:
                out = (None, "", str(exc)[:200])
            if out[0] == 0:
                break
        return out

    def git(self, repo, *args, retry=0, timeout=GIT_S):
        return self.call(["git", "-C", repo] + list(args), timeout, retry)

    def fetch_refs(self, repo):
        """r1937 — keeper 가 읽는 ref 만: 팩 = main · BYZ = main·ops/main-base + directive-roots.tsv 의 `.` 행 origin/<가지>
        (고정 목록 밖이면 ls-remote 1회로 원격 실재만 · 로컬 ref 없어도 첫 수신 · 원격에 없는 가지 = 빠짐) · 표·ls-remote 실패 = 고정 목록만."""
        names = ["main"] if repo == self.pack else ["main", "ops/main-base"]
        try:
            with open(os.path.join(self.root, ".fable-team", "state", "directive-roots.tsv"), encoding="utf-8") as fh:
                rows = [x.rstrip("\n").split("\t") for x in fh if not x.startswith("#") and len(x.split("\t")) >= 4]
        except (OSError, UnicodeError):
            rows = []
        extra = list(dict.fromkeys(r[2][7:] for r in rows if repo == self.root and r[1] == "." and r[2].startswith("origin/") and r[2][7:] not in names))
        if extra:
            rc, out, _ = self.git(repo, "ls-remote", "--heads", "origin", *("refs/heads/" + n for n in extra), retry=1, timeout=FETCH_S)
            have = {x.partition("\trefs/heads/")[2] for x in out.splitlines()} if rc == 0 else set()
            names += [n for n in extra if n in have]
        return ["+refs/heads/%s:refs/remotes/origin/%s" % (n, n) for n in names]

    def stamp(self):
        return datetime.datetime.fromtimestamp(self.now()).strftime("%Y-%m-%dT%H:%M:%S")

    def log(self, kind, team="", text=""):
        """로그 1줄 = 출력 + state/ft2-keeper/<YYYYMMDD>.jsonl append. 반환 None(= 거짓 · `return self.log(...)` 로 끝낸다)."""
        line, at = " ".join(w for w in (kind, team, text) if w), self.stamp()
        self.lines.append(line)
        os.makedirs(self.dir, exist_ok=True)
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

    def locked(self, body):
        """잠금 O_EXCL 1개 — 앞 바퀴 진행 중 = 바퀴 0 · 로그 1줄. 10분 넘은 잠금(죽은 바퀴)은 지우고 1줄. 상태 = 원자 쓰기."""
        os.makedirs(self.dir, exist_ok=True)
        lock, path = os.path.join(self.dir, "keeper.lock"), os.path.join(self.dir, "state.json")
        if os.path.exists(lock) and time.time() - os.path.getmtime(lock) > STALE_S:
            os.unlink(lock)
            self.log("STALE-LOCK", text="10분 넘은 잠금을 지움")
        try:
            os.close(os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644))
        except FileExistsError:
            return self.log("SKIP", text="앞 바퀴 진행 중(잠금) — 바퀴 0")
        try:
            self.state.update(self.read_json(path))
            out = body()
            with open(path + ".tmp", "w", encoding="utf-8") as fh:
                json.dump(self.state, fh, ensure_ascii=False, sort_keys=True)
            os.replace(path + ".tmp", path)
            return out
        finally:
            os.unlink(lock)

    def run_once(self):
        return self.locked(self._round) or 0

    def report_once(self):
        self.skip = self.skipped()   # r1835 K4 — 판독 실패 = probe·쪽지 0 · 출력 1줄(로그 줄 0)
        return "판정 불가 · SKIP_TEAMS 판독 실패" if self.skip is None else self.locked(self.report) or "판정 불가 · 바퀴 진행 중"

    def skipped(self):
        """r1835 K1 — SKIP_TEAMS 줄마다 팀 1개(빈 줄·# 무시) · 바퀴마다 읽음 · 없음 = 빈 집합 · 못 읽음 = None."""
        try:
            with open(os.path.join(self.dir, "SKIP_TEAMS"), encoding="utf-8") as fh:
                return {x.strip() for x in fh if x.strip() and not x.strip().startswith("#")}
        except (OSError, UnicodeDecodeError) as exc:
            return set() if isinstance(exc, FileNotFoundError) else None

    def timed(self, stage, fn, *args):
        """r1817 D3 — 단계별 초(주입 시계 self.now) 누적 · 반환 = fn 결과."""
        at = self.now()
        try:
            return fn(*args)
        finally:
            self.spent[stage] += self.now() - at

    def socket_ok(self):
        """r1817 D4 — 기준 소켓(FT2_TMUX_SOCKET · 설치 렌더 고정)과 tmux 가 보는 서버가 같을 때만 닫는다 · 기준 없음 = 셀 손 실행."""
        want = self.env.get("FT2_TMUX_SOCKET")
        if not want:
            return True
        rc, out, err = self.call([self.tmux, "display", "-p", "#{socket_path}"])
        if rc == 0 and out.strip() == want:
            return True
        return self.log("판정 불가", text="tmux 소켓 %s ≠ 기준 %s (rc %s) — 이 바퀴 닫기 0" % (out.strip() or err or "-", want, rc))

    def _round(self):
        start, self.skip = time.monotonic(), self.skipped()
        if self.skip is None:
            return self.log("판정 불가", text="SKIP_TEAMS 판독 실패 — 이 바퀴 B1·B2·B3·B4 0")
        def fetch(repo):
            return self.git(repo, "fetch", "-q", "--no-tags", "origin", *self.fetch_refs(repo), retry=1, timeout=FETCH_S)[0]
        bad = [repo for repo in (self.root, self.pack) if self.timed("fetch", fetch, repo) != 0]
        self.sock = self.socket_ok()
        if bad:
            self.log("판정 불가", text="git fetch 실패 %s — 이 바퀴 B1·B2 0" % " ".join(bad))
        order = [] if bad else self.teams()
        if self.state.get("cap_next") in order:   # r1898 — 앞 바퀴 컷에 걸린 팀부터(뒤쪽 팀 굶음 0)
            at = order.index(self.state["cap_next"])
            order = order[at:] + order[:at]
        for team in order:
            if time.monotonic() - start > ROUND_S:
                self.log("ROUND-CAP", text="60초 넘음 — 남은 팀은 다음 바퀴")
                self.state["cap_next"] = team
                self.fa.observe(self.root, "keeper 바퀴", "keeper", max(int(time.monotonic() - start), ROUND_S), ROUND_S, "남은 팀 " + team)
                break
            self.team_round(team)
        else:   # r1886 ⓒ 60초 안 끝 = 정상 관측
            self.state.pop("cap_next", None)
            self.fa.observe(self.root, "keeper 바퀴", "keeper", int(time.monotonic() - start), ROUND_S)
        if self.sock:
            self.timed("b3", self.retired)
        self.report()
        s = sum(self.spent.values())
        cells = " ".join("%s=%g" % (key, round(val, 1)) for key, val in self.spent.items())
        self.log("ROUND", text="s=%g %s%s%s" % (round(s, 1), cells, " OVER" if s > ROUND_S else "", self.skip and " skip=" + ",".join(sorted(self.skip)) or ""))

    def teams(self):
        """대상 팀 = ft20-switch/<팀>.json ∪ <팀>.held 가 있고 runtime 이 있는 팀."""
        switch = os.path.join(self.root, ".fable-team", "state", "ft20-switch")
        found = os.listdir(switch) if os.path.isdir(switch) else []
        names = {name.rsplit(".", 1)[0] for name in found if name.endswith((".json", ".held"))}
        return sorted(team for team in names if os.path.isdir(projection.runtime_path(self.root, team)) and team not in self.skip)

    def team_round(self, team):
        """최신 묶음 = work 마다 최신 dispatch 1줄의 (attempt · holder) (launch.seat 와 같은 규칙 · 옛 intent 로 대신 0)."""
        proj = self.project(self.root, team)
        if proj.get("result") != OK:
            return self.log("판정 불가", team, "투영 %s" % proj.get("reason", ""))
        node = projection.journal.Journal(projection.runtime_path(self.root, team), rec=projection.record)
        rows = node.records()
        latest = {rec["work"]: (rec.get("attempt"), rec.get("holder")) for rec in rows
                  if rec.get("kind") == "dispatch" and rec.get("work")}
        for work, (attempt, dispatched) in sorted(latest.items()):
            row = proj["works"].get(work) or {}
            if "%s|%s@%s" % (team, work, attempt) in self.state["handled"]:
                continue
            if row.get("done") or self.timed("b1", lambda: self.complete(team, work, attempt, self.landing(team, work))):
                if self.sock:
                    self.timed("b2", self.close, team, work, attempt, row, dispatched)
            elif self.sock:   # r1817 fix1 R1 — 소켓 실패 바퀴 = 깨움·재배정도 0
                self.timed("stall", self.stall.check, team, work, attempt, rows)   # r1813 · r1898 ROUND stall 칸 — 진척 0 좌석 깨움 1회 → 재배정
                self.timed("stall", hold.check, self, team, work, attempt, rows)   # r1931 HOLD 줄 늘면 깨움 1회 · 누적 3 = 인터뷰 길
        if self.sock:   # r1913 — 닫힘이 없어도 빈 나노 칸 1장(팀마다 1회 · gates 재계산)
            self.timed("b2", closing.keeper_next.fill, self, team)


def main(argv):
    flags = [arg for arg in argv if arg in ("--once", "--report")]
    rest = [arg for arg in argv if arg not in ("--once", "--report")]
    opts = dict(zip(rest[::2], rest[1::2]))
    if len(flags) != 1 or len(rest) % 2 or set(opts) - {"--root", "--pack"} or "--root" not in opts:
        usage = {"result": "사용법", "reason": "keeper --root R (--once | --report) [--pack P]"}
        sys.stdout.write(json.dumps(usage, ensure_ascii=False) + "\n")
        return 64
    env = dict(os.environ, **({"FT2_PACK_REPO": opts["--pack"]} if "--pack" in opts else {}))
    keeper = Keeper(opts["--root"], env)
    line = keeper.run_once() if flags[0] == "--once" else keeper.report_once()
    tail = "" if flags[0] == "--once" else line + "\n"
    sys.stdout.write("".join(text + "\n" for text in keeper.lines) + tail)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
