#!/usr/bin/env python3
"""ft 2.0 keeper — 끝난 좌석 자동 닫기 (r1812 · 카드 B0~B5 · DA r1 APPROVE).

core 는 일을 기록만 하고 좌석을 닫지 않는다(close_next «kill = 호출자»). 그 닫는 호출자가 이 명령이다.
한 바퀴(--once) = 잠금 O_EXCL → git fetch(리포당 1회) → 팀마다 B1 complete 누락 잡기 → B2 착지 끝 나노 세션 닫기 →
B3 승계 끝 옛 좌석 → B4 보고. 파일 넷: 이 파일(바퀴·잠금) · keeper_land.py(B1·B1r) · keeper_close.py(B2·B3) ·
keeper_report.py(B4·쪽지). 끝나지 않은 일 = r1813 멈춤 갈래(keeper_stall.py · 깨움 → 재배정).
core 손 0 — 공개 동사(cli.run)·공개 API(project·CloseNext)만 부른다. 상한: git 25초 · tmux·쪽지 7초 · 바퀴 60초.
    python3 core/cli.py keeper --root R (--once | --report) [--pack 팩리포]
"""
import concurrent.futures
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
SLOW_S = 5   # r1992 바깥 호출 1시도 ≥ 5초 = SLOW-CALL 1줄(동작 변경 0)
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
endings = _load(os.path.join(HERE, "keeper_endings.py"), "ft2_keeper_endings")   # r1960 끝 판정 · 고아
hold = _load(os.path.join(HERE, "keeper_hold.py"), "ft2_keeper_hold")   # r1931 카드 HOLD 줄 → holder 깨움
kf = _load(os.path.join(HERE, "keeper_fetch.py"), "ft2_keeper_fetch")   # r1975 FETCH_TARGETS · 나노 가지 · 판정 뒤 백그라운드
settling = _load(os.path.join(HERE, "keeper_settle.py"), "ft2_keeper_settle")   # r2055 settle 한 길 · ALL_STOP
cstage = _load(os.path.join(HERE, "card_stage.py"), "ft2_keeper_card_stage")   # r2026 complete 뒤 대기|진행 → 완성


class Keeper(land.Landing, closing.Closing, reporting.Reporting, settling.Settling):
    fa, cs = full_alert, cstage   # r1886 keeper_land·keeper_next 도 이것으로 부른다 · r2026 card_stage
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
        self.spent, self.sock, self.skip, self.stale = dict.fromkeys(("fetch", "b1", "b2c", "b2f", "b3", "stall"), 0.0), True, set(), set()
        self.per, self.at = {}, None   # r1969 (팀, 칸) 초 → ROUND slow 칸 · at = 지금 도는 팀(None = 팀 밖)
        self.table, self.nano, self.refs, self.picked, self.bg, self.fetch_s = {}, {}, {}, [], {}, {}   # r1975
        self.stage, self.tally = "-", {}   # r1992 지금 칸(timed) · (팀, 칸) → [호출 시도 수, SLOW-CALL 초 합]
        self.halt, self.unknown = False, 0   # r2055 ALL_STOP(바퀴마다 판독) · 바퀴 UNKNOWN 수(ROUND unknown=N)

    def call(self, argv, timeout=CALL_S, retry=0):
        """바깥 호출 1곳 → (rc, stdout, stderr 1줄) · 넘침·실행 실패 = rc None · retry = rc≠0 때 다시 부르는 횟수."""
        if self.halt and (argv[1:2] in (["kill-session"], ["send-keys"]) or argv[:1] == [sys.executable] or self.close_bin in argv[1:2]):   # r2055 정지 중 실행 0(그물)
            self.log("판정 불가", self.at or "-", "ALL_STOP 정지 중 실행 막음 %s" % " ".join(os.path.basename(w) for w in argv[:2]))
            return None, "", "ALL_STOP"
        self.cache.get("@round", {}).pop("ls", None) if "kill-session" in argv or argv[:1] == [sys.executable] else None   # r1969 세션이 바뀜 = 바퀴 list-sessions 캐시 버림
        for n in range(1, retry + 2):
            at = self.now()
            try:
                done = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, env=self.env, cwd=self.root)
                out = (done.returncode, done.stdout, done.stderr.strip()[:200])
            except (OSError, subprocess.TimeoutExpired) as exc:
                out = (None, "", str(exc)[:200])
            dt, cell = self.now() - at, self.tally.setdefault((self.at, self.stage), [0, 0.0])
            cell[:] = [cell[0] + 1, cell[1] + (dt if dt >= SLOW_S else 0.0)]
            if dt >= SLOW_S:   # r1992 시도마다 1줄 · argv 앞 3낱말(git -C <repo> = repo 이름 · 경로 = 끝 이름 · 뒤 토큰 0)
                head = [argv[0]] + argv[2:] if argv[1:2] == ["-C"] else argv
                self.log("SLOW-CALL", self.at or "-", "%s %s s=%g rc=%s try=%d/%d" % (self.stage, " ".join(os.path.basename(w.rstrip("/")) or w for w in head[:3]), round(dt, 1), out[0], n, retry + 1))
            if out[0] == 0:
                break
        return out

    def complete(self, *args):   # r2026 — complete 접수(done 확인) 직후 card_stage 1회
        return land.Landing.complete(self, *args) and (self.stage_card(*args[:2]) or True)

    def stage_card(self, team, work):
        """r2026 — STAGED·NOOP = 끝 · Unsure = 쓰기 0 + 다음 바퀴 재시도(같은 work · 하루 3회 상한)."""
        book, key, day = self.state.setdefault("staging", {}), team + "|" + work, self.stamp()[:10]
        n = book[key][1] if book.get(key, [None])[0] == day else 0   # 날이 바뀜 = 0부터
        if n >= 3:
            return None
        try:
            at = self.cs.done_at(self.root, team, work)
            if not at:
                raise self.cs.Unsure("done 없음")
            out = self.cs.stage(self.root, self.root, team, work, at, self.stamp())
        except (self.cs.Unsure, subprocess.TimeoutExpired, OSError) as exc:
            book[key] = [day, n + 1]
            return self.log("Unsure", team, "%s card_stage %s" % (work, exc))
        book.pop(key, None)
        return self.log("CARD-STAGE", team, "%s %s %s" % (work, out[1], out[2])) if out else self.log("NOOP", team, work + " 이미 완성")

    def git(self, repo, *args, retry=0, timeout=GIT_S):
        return self.call(["git", "-C", repo] + list(args), timeout, retry)

    def fetch_refs(self, repo):
        """r1937 — keeper 가 읽는 ref 만: 팩 = main · BYZ = main·ops/main-base + directive-roots.tsv 의 `.` 행 origin/<가지>
        (고정 목록 밖이면 ls-remote 1회로 원격 실재만 · 로컬 ref 없어도 첫 수신 · 원격에 없는 가지 = 빠짐) · 표·ls-remote 실패 = 고정 목록만.
        r1975 — 바퀴마다 1회 계산 · FETCH_TARGETS 있음 = 그 목록만 · 없음 = 위 + 판정 대상 나노 가지(고정 목록 밖 취급) · 리포당 상한 5."""
        if repo not in self.refs:   # 바퀴 밖(따로 부름) 길 — 바퀴 안은 _fresh 가 ls-remote 1회로 먼저 채운다(r1963b)
            self.cap(repo, list(dict.fromkeys(self.table.get(repo, []))) if self.table else self.default_refs(repo))
        return self.refs[repo]

    def cap(self, repo, names):
        if len(names) > kf.CAP:
            self.log("FETCH-CAP", text="%s 지정 ref 초과 %d — 앞 %d 만" % (repo, len(names) - kf.CAP, kf.CAP))
        self.refs[repo] = ["+refs/heads/%s:refs/remotes/origin/%s" % (n, n) for n in names[:kf.CAP]]

    def default_refs(self, repo):
        names, extra = self.cand(repo)
        if extra:
            rc, out, _ = self.git(repo, "ls-remote", "--heads", "origin", *("refs/heads/" + n for n in extra), retry=1, timeout=FETCH_S)
            have = {x.partition("\trefs/heads/")[2] for x in out.splitlines()} if rc == 0 else set()
            names += [n for n in extra if n in have]
        return names

    def cand(self, repo):
        """r1963b — (고정 목록, 원격 실재를 물어야 하는 extra = 표 ref + 나노 가지) · 바깥 호출 0."""
        names = ["main"] if repo == self.pack else ["main", "ops/main-base"]
        try:
            with open(os.path.join(self.root, ".fable-team", "state", "directive-roots.tsv"), encoding="utf-8") as fh:
                rows = [x.rstrip("\n").split("\t") for x in fh if not x.startswith("#") and len(x.split("\t")) >= 4]
        except (OSError, UnicodeError):
            rows = []
        extra = list(dict.fromkeys(r[2][7:] for r in rows if repo == self.root and r[1] == "." and r[2].startswith("origin/") and r[2][7:] not in names))
        return names, extra + [n for n in (self.nano.get(endings._common(self, repo), []) if self.nano else []) if n not in names + extra]

    def fresh(self, repo):
        """r1975 ⑤ 리포별 초(self.fetch_s) — ROUND fetch_root=·fetch_pack= 칸."""
        at = self.now()
        try:
            return self._fresh(repo)
        finally:
            self.fetch_s[repo] = self.now() - at

    def _fresh(self, repo):
        """r1963 — 그 리포가 «신선» 인가. ls-remote(네트워크만) 의 원격 sha 가 읽는 ref 전부에서 로컬 remote-tracking sha 와 같으면 fetch 0
        (fetch 끝의 연결 검사가 그 리포 모든 ref 를 읽는다 = 느린 곳) · 다르면 fetch(7초 + 재시도 1) · ls-remote 실패면 fetch 1회(시도 합 2 그대로)."""
        def fetch(repo, retry=1):   # r1975 시도마다 1줄(소요 초·rc · 재시도 포함 · ROUND 합과 따로)
            for n in range(1, retry + 2):
                at = self.now()
                rc = self.git(repo, "fetch", "-q", "--no-tags", "origin", *self.fetch_refs(repo), timeout=FETCH_S)[0]
                self.log("FETCH-TRY", text="%s %d/%d rc=%s s=%g" % (repo, n, retry + 1, rc, round(self.now() - at, 1)))
                if rc == 0:
                    break
            return rc
        fixed, extra = (list(dict.fromkeys(self.table.get(repo, []))), []) if self.table else self.cand(repo)
        rc, out, _ = self.git(repo, "ls-remote", "origin", *("refs/heads/" + n for n in fixed + extra), timeout=FETCH_S)   # r1963b 리포당 1회 = 신선 대조 + extra 실재
        seen = {x.partition("\trefs/heads/")[2] for x in out.splitlines()} if rc == 0 else set(extra)   # 실패 = extra 를 빼지 않는다(없는 가지면 fetch 실패 = 낡음 · 낡은 판정 ref 로 신선 선언 0)
        self.cap(repo, fixed + [n for n in extra if n in seen])   # 거른 뒤 상한(없는 가지가 칸을 먹지 않는다)
        pairs = [spec.lstrip("+").split(":", 1) for spec in self.fetch_refs(repo)]   # (원격 ref, 로컬 ref) — 따로 대조
        names = [src for src, _ in pairs]
        if rc != 0:
            return fetch(repo, 0) == 0
        far = dict(reversed(x.split("\t", 1)) for x in out.splitlines() if "\t" in x)
        near = self.git(repo, "rev-parse", *(dst for _, dst in pairs))[1]
        return near.split() == [far.get(n) for n in names] or fetch(repo) == 0

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
        at, prev, self.stage = self.now(), self.stage, stage
        try:
            return fn(*args)
        finally:
            self.stage, dt = prev, self.now() - at
            self.spent[stage] += dt
            self.per[(self.at, stage)] = self.per.get((self.at, stage), 0.0) + dt

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
        self.halt, self.unknown, self.orphan_scope = self.stopped(), 0, set()   # r2055 orphan_scope = 고아 길이 판정한 팀(S1) 정지 = 판정·[긴급]·«예정» 만 · kill·park·깨움·fill·B3 0
        self.fresh_samples()   # r2055 A13 표본 = 직전 바퀴 것만
        self.cache["@round"] = {}   # r1969 바퀴 캐시(keeper_next.once · 팀 사이 공유 · 다음 바퀴 새로 읽음)
        if self.skip is None:
            return self.log("판정 불가", text="SKIP_TEAMS 판독 실패 — 이 바퀴 B1·B2·B3·B4 0")
        self.table, self.refs, self.fetch_s = kf.targets(self), {}, dict.fromkeys((self.root, self.pack), 0.0)
        if self.table is None:   # r1975 ④ 기본값으로 돌아가지 않는다
            return self.log("판정 불가", text="FETCH_TARGETS 판독 실패 — 이 바퀴 B1·B2 0")
        kf.collect(self)
        self.picked = [r for r in (self.root, self.pack) if not self.table or r in self.table]
        at = self.now()
        self.nano = {} if self.table else kf.nanos(self, self.teams())   # r1975 ⑥ · r1963b fetch 시계 밖(ROUND nano= 칸)
        self.nano_s = self.now() - at
        def both(repos=self.picked):   # r1963 두 리포 동시 → fetch 단계 = 느린 쪽 하나 · 낡은 리포 집합은 바퀴마다 새로
            with concurrent.futures.ThreadPoolExecutor(2) as pool:
                return [repo for repo, ok in zip(repos, pool.map(self.fresh, repos)) if not ok]
        self.stale = {repo for repo in self.timed("fetch", both)}
        self.sock = self.socket_ok()
        if self.stale:   # BYZ 낡음 = 카드·TEAMS·짝 표도 낡음 → 판정 0 · 팩만 낡음 = 팩 ref 를 읽는 판정(landing 조상·다음 카드 target)만 0
            self.log("판정 불가", text="git fetch 실패 %s — %s" % (" ".join(r for r in (self.root, self.pack) if r in self.stale), "이 바퀴 B1·B2 0" if self.root in self.stale else "팩 기대 판정만 0"))
        if out := [r for r in (self.root, self.pack) if r not in self.picked]:   # r1975 ② 목록 밖 리포 = fetch 0 · 그 리포를 읽는 판정만 0
            self.stale |= set(out)
            self.log("판정 불가", text="FETCH_TARGETS 밖 %s — fetch 0 · %s" % (" ".join(out), "이 바퀴 B1·B2 0" if self.root in out else "팩 기대 판정만 0"))
        order = [] if self.root in self.stale else self.teams()
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
        self.at, _ = None, self.cache.pop("@round", None)   # r1969 팀 밖 · 바퀴 캐시 닫음(B3 = 자기 list-sessions 1회 그대로)
        if self.sock and not self.halt:
            self.timed("b3", endings.orphans, self, order)   # r1960 ⑤ 스냅샷 뒤 journal 새로 읽기
        if self.sock:
            self.timed("b3", self.retired)   # r2055 정지 중 = 판정·«예정» 줄만(retire_one 안에서)
        self.report()
        s = sum(self.spent.values())
        s += self.nano_s   # r1963b 나노 가지 모으기 초도 합계에(0.05초 미만이면 칸 0 = 옛 줄 그대로)
        cells = " ".join("%s=%g" % (key, round(val, 1)) for key, val in self.spent.items())
        cells += " fetch_root=%g fetch_pack=%g" % (round(self.fetch_s[self.root], 1), round(self.fetch_s[self.pack], 1))   # r1975 ⑤ 합계 fetch= 그대로
        cells += " nano=%g" % round(self.nano_s, 1) if round(self.nano_s, 1) else ""
        top = max((kv for kv in self.per.items() if kv[0][0]), key=lambda kv: kv[1], default=None)   # r1969 가장 느린 (팀, 칸) 1개
        if top:   # r1992 ⑦ slow 칸의 호출 시도 수·SLOW-CALL 합(5초 미만 여러 번 = slow_call 0 으로 드러남) · ROUND 줄 그대로
            got = self.tally.get(top[0], [0, 0.0])
            self.log("SLOW-CELL", top[0][0], "%s s=%g n=%d slow_call=%g" % (top[0][1], round(top[1], 1), got[0], round(got[1], 1)))
        self.log("ROUND", text="s=%g %s slow=%s%s%s%s" % (round(s, 1), cells, "%s:%s:%g" % (top[0] + (round(top[1], 1),)) if top else "-", " OVER" if s > ROUND_S else "", " unknown=%d" % self.unknown if self.unknown else "",
                                                       self.skip and " skip=" + ",".join(sorted(self.skip)) or ""))   # r2055 unknown=N(skip= 은 끝 칸 그대로)

    def teams(self):
        """대상 팀 = ft20-switch/<팀>.json ∪ <팀>.held 가 있고 runtime 이 있는 팀."""
        switch = os.path.join(self.root, ".fable-team", "state", "ft20-switch")
        found = os.listdir(switch) if os.path.isdir(switch) else []
        names = {name.rsplit(".", 1)[0] for name in found if name.endswith((".json", ".held"))}
        return sorted(team for team in names if os.path.isdir(projection.runtime_path(self.root, team)) and team not in self.skip)

    def team_round(self, team):
        """최신 묶음 = work 마다 최신 dispatch 1줄의 (attempt · holder) (launch.seat 와 같은 규칙 · 옛 intent 로 대신 0)."""
        self.at, proj = team, self.project(self.root, team)
        if proj.get("result") != OK:
            return self.log("판정 불가", team, "투영 %s" % proj.get("reason", ""))
        for key in [k for k in self.state.get("staging", {}) if k.startswith(team + "|")]:   # r2026 앞 바퀴 Unsure = 재시도
            self.timed("b1", self.stage_card, team, key[len(team) + 1:])
        node = projection.journal.Journal(projection.runtime_path(self.root, team), rec=projection.record)
        rows = node.records()
        latest = {rec["work"]: (rec.get("attempt"), rec.get("holder")) for rec in rows
                  if rec.get("kind") == "dispatch" and rec.get("work")}
        back = {(rec["work"], rec.get("attempt")) for rec in rows if rec.get("kind") == "returned"}   # r1990 반환 줄
        back |= {(rec["work"], rec.get("attempt")) for rec in rows if rec.get("kind") == "parked" and rec.get("reason") != settling.LAUNCH_FAILED}   # r2055 쉼 줄
        self.parked_failed = {(team, rec["work"], rec.get("attempt")) for rec in rows if rec.get("kind") == "parked" and rec.get("reason") == settling.LAUNCH_FAILED}   # r2058 L1 — 열기 실패 쉼은 건너뛰지 않는다
        for work, (attempt, dispatched) in sorted(latest.items()):
            row, landed, self.why = proj["works"].get(work) or {}, None, ""   # r2055 판정 줄 꼬리 = 이 work 의 착지 판정 사유
            if "%s|%s@%s" % (team, work, attempt) in self.state["handled"] or (work, attempt) in back:
                continue   # r1990 반환·r2055 쉼인 최신 attempt = B1 complete·판정·깨움 0(새 dispatch 면 attempt 가 달라 다시 본다)
            if not row.get("done"):
                landed = self.timed("b1", self.landing, team, work)
                if landed[0] and not landed[2] and self.sock and not self.land_ready(team, work, attempt, dispatched):
                    continue   # r2055 A6·S4-1 카드 ② — 착지했어도 좌석이 쉬기 전 = WORKING landed-wait · complete·kill 0
            if row.get("done") or self.timed("b1", self.complete, team, work, attempt, landed):
                if self.sock and (team, work, attempt) not in self.parked_failed:   # r2058 L2 착지면 complete 만 · 세션이 없으니 닫기 호출 0
                    self.timed("b2c", self.close, team, work, attempt, row, dispatched)
            elif self.sock and endings.ending(self, team, work):   # r1960 끝(완성후·아카이브·상태 머리) = complete 0 · close 가드 그대로
                self.timed("b2c", self.close, team, work, attempt, row, dispatched)
            elif self.sock:   # r1817 fix1 R1 — 소켓 실패 바퀴 = 판정·깨움·재배정도 0
                seen = self.timed("stall", self.settle_nano, team, work, attempt, dispatched, row, landed[2])   # r2055 착지 밖 = settle 한 길
                if seen != "PARKED" and not self.halt:   # WORKING·UNKNOWN = 기존 회복 길 그대로 · 정지 중 = 깨움·재배정 0
                    self.timed("stall", self.stall.check, team, work, attempt, rows)   # r1813 · r1898 ROUND stall 칸 — 진척 0 좌석 깨움 1회 → 재배정
                    self.timed("stall", hold.check, self, team, work, attempt, rows)   # r1931 HOLD 줄 늘면 깨움 1회 · 누적 3 = 인터뷰 길
        if self.sock:
            self.timed("stall", self.accept_only, team, rows)   # r2055 ⑪ accept 만 · PARK_IDLE 넘음 = UNKNOWN
        if self.sock and not self.halt:   # r1913 — 닫힘이 없어도 빈 나노 칸 1장(팀마다 1회 · gates 재계산) · r2055 정지 중 fill 0
            self.timed("b2f", closing.keeper_next.fill, self, team)


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
    for repo in keeper.picked if flags[0] == "--once" else ():   # r1975 ⑦ 판정 뒤 전체 fetch = 던지고 기다리지 않음
        kf.background(keeper, repo)
    tail = "" if flags[0] == "--once" else line + "\n"
    sys.stdout.write("".join(text + "\n" for text in keeper.lines) + tail)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
