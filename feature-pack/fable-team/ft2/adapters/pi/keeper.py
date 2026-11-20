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
import inspect
import json
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
FT2 = os.path.dirname(os.path.dirname(HERE))
GIT_S, CALL_S, ROUND_S, STALE_S, FETCH_S = 7, 7, 60, 600, 7   # r2098 R7 로컬 git 상한 25 → 7(하드 룰 12) · FETCH_S = fetch 1회 7초(+ 재시도 1)
SLOW_S = 5   # r1992 바깥 호출 1시도 ≥ 5초 = SLOW-CALL 1줄(동작 변경 0)
ITEM_STAGES, ITEM_SLOW_S = ("b1", "b2f"), 3   # r2339 I1 항목 = 한 work 안에서 재는 칸(b1·b2f 만) · I3 이 초 이상 쓴 항목만 ITEM-SLOW 1줄
OK = "접수 성공"
WORK_S, REPORT_S, TAIL_S = 45, 55, 60   # R1 구획 = 업무 0~45 · report 45~55 · 마무리 55~60(바깥 호출 0)
NANO_S, LONG_S, MIN_S = 7, 20, 1   # R6 나노 합 7초 · R2 긴 쓰기(자기 상한 > 7)는 20초 뒤 시작 0 · 남은 몫 < 1초 = 시작 0
ORDER = ("b1", "b2c", "stall", "b2f", "b3o", "b3r")   # R4 자리 차례(팀 → work → 칸 → b3o → b3r)
READ_GIT = frozenset(("rev-parse", "merge-base", "grep", "ls-tree", "ls-remote", "fetch", "log", "show", "cat-file", "cherry", "rev-list", "status"))   # R2 판독 git 동사
STUCK = ("착지 줄 없음", "완성 증거 0", "두 가지에 진행 카드", "진행·대기 둘 다 카드", "진행 카드 ")   # r2266 C1 card_stage 영구 Unsure 사유 머리 · done 없음·일시 사유 = 밖 · r2274 «완성 증거 0»(카드가 바뀌어야 풀림)
READ_TMUX = frozenset(("has-session", "display", "display-message", "capture-pane", "list-sessions"))   # R2 판독 tmux 동사


class Cut(BaseException):
    """R3 — 예산이 다해 그 자리에서 끊김. BaseException = `except Exception` 에 먹히지 않는다(㊳거)."""


class Ungraded(BaseException):
    """R7 — 로컬 git 이 자기 상한(7초)에 걸림 = `판정 불가` 1줄 · 그 자리의 남은 판정 0 · 다음 자리."""


class OutOfRound(Exception):
    """r2026 R1 — 바퀴 남은 예산 < git 1회 상한(card_stage.spawn 7초) · 다음 git 0 → 다음 바퀴."""


def head2(argv):
    """r2287 C3 — 호출 길 = 머리 2낱말(git -C <repo> 는 repo 를 건너뜀 · 경로 = 끝 이름) · 줄 칸에 공백이 없도록 + 로 잇는다."""
    words = [argv[0]] + list(argv[3:] if argv[1:2] == ["-C"] else argv[1:])
    if argv[1:2] == ["-c"] and os.path.basename(str(argv[0])) == "bash":   # DA#31 — lib bash = 함수 이름(lib_call = argv[5] · da_judge = 글 속 ft_ 함수)
        words = [argv[0]] + ([w for w in argv[5:6] if str(w).startswith("ft_")] or re.findall(r"\bft_\w+", str(argv[2]) if argv[2:3] else "")[-1:])
    return "+".join(os.path.basename(str(w).rstrip("/")) or str(w) for w in words[:2])


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
kblock = _load(os.path.join(HERE, "keeper_block.py"), "ft2_keeper_block")   # r2072 10분 넘게 이어진 줄 → 막힘 장부
daily = _load(os.path.join(HERE, "keeper_daily.py"), "ft2_keeper_daily")   # r2238 하루 정리 생존 검사
tw = _load(os.path.join(HERE, "transition_watch.py"), "ft2_keeper_transition")   # r2275 카드 전이 증거 감시(알림만)


class Keeper(land.Landing, closing.Closing, reporting.Reporting, settling.Settling):
    fa, cs = full_alert, cstage   # r1886 keeper_land·keeper_next 도 이것으로 부른다 · r2026 card_stage
    MIN_S = MIN_S   # r2311 K4 close_old.sweep 팀 끝 남은 몫 문턱(같은 값)
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
        self.succeed = _load(os.path.join(HERE, "keeper_succeed.py"), "ft2_keeper_succeed").Succeed(self)   # r2276 표식 승계(self.succeeding)
        self.close_old = _load(os.path.join(HERE, "keeper_close_old.py"), "ft2_keeper_close_old").CloseOld(self)   # r2281 승계 끝 구 나노 닫기
        self.spent, self.sock, self.skip, self.stale = dict.fromkeys(("fetch", "b1", "b2c", "b2f", "b3", "stall"), 0.0), True, set(), set()
        self.per, self.at, self.b3p = {}, None, {}   # r1969 (팀, 칸) 초 → ROUND slow 칸 · at = 지금 도는 팀(None = 팀 밖)
        self.b3r_parts = {}   # r2306 K1 b3r 자리 안 몫(b3r.sweep·b3r.retired) 초
        self.table, self.nano, self.refs, self.picked, self.bg, self.fetch_s, self.fetch_err = {}, {}, {}, [], {}, {}, {}   # r1975 · r2241 fetch_err
        self.stage, self.tally = "-", {}   # r1992 지금 칸(timed) · (팀, 칸) → [호출 시도 수, SLOW-CALL 초 합]
        self.cell_calls = {}   # r2287 C3 (팀, 칸) → [바깥 호출 초 합(keeper.call · 주입 손), 큰 3개 [(초, 길)]]
        self.item_parts, self.item_call, self.item_cur = {}, {}, None   # r2339 I1 (팀 · work · 칸) → 부분 단계 초 · I2 같은 키 → 호출 수·초·낱말별 초 · 지금 열린 항목
        self.halt, self.unknown = False, 0   # r2055 ALL_STOP(바퀴마다 판독) · 바퀴 UNKNOWN 수(ROUND unknown=N)
        self.start, self.sect, self.items, self.total, self.cut = None, WORK_S, 0, 0, "-"   # r2098 R1 예산 시계 · R10 ROUND 칸
        self.at_work, self.cursor_stage, self.nano_dl, self.in_fetch = "-", "-", None, False   # r2098 R4 자리 · R6 나노 몫
        self.nano_stat = {}   # r2315 N1 바퀴마다 비우는 나노 팀 셈(초·rows·git·works·slow·other)
        self.who = ""   # r2303 A3 나노 끊김 줄의 일지 team 칸(줄 글자 그대로)
        self.order, self.jrows, self.ws, self.curs, self.prev_cursor, self.cut_pos = [], {}, {}, None, None, None
        self.team_at, self.tcurs, self.capped = None, {}, False   # r2323 T1 팀 몫 시계(team_round 시작) · T2 바퀴 시작 team_cursor · 이 바퀴 상한 1회 이상
        self.jprojs = {}   # r2251 O1 팀 투영 바퀴 안 1회(book() · team_round 같은 값)
        self.report_seat, self.notify_used, self.deferred = None, 0, {}   # R8·R12 구획 상태(바퀴마다 새로)
        self.send_fails, self.send_stop = 0, False   # R8 send 시간 초과 2회 = 그 바퀴 남은 쪽지 미룸
        self.seen, self.tried, self.unused = set(), set(), set()   # r2201 K1 바퀴 밖 Keeper 도 stall 길을 탄다 · 바퀴마다 _round 가 다시 비운다
        self.fa = _Alert(self)   # R12 keeper 손 = 보내지 않고 state.alert_out 에 넣는다(바퀴 안 바깥 호출 0)

    def reading(self, argv):
        """R2 판독 목록 1개 — git 동사 13 · tmux 5 · gh pr list · ps · mbox peek · 벌점 판정기 check. 목록 밖 = 쓰기(모르는 호출도 쓰기)."""
        words = list(argv)
        while words and (os.path.basename(words[0]) == "env" or ("=" in words[0] and not words[0].startswith("-"))):
            words.pop(0)   # `env LC_ALL=C ps …` = ps
        if not words:
            return False
        head, rest = os.path.basename(words[0]), words[1:]
        if head == "git":
            at = 0
            while at < len(rest) and rest[at] == "-C":
                at += 2
            verb = rest[at] if at < len(rest) else ""
            return rest[at + 1:at + 2] == ["--get"] if verb == "config" else verb in READ_GIT
        if words[0] == self.tmux or head == "tmux":
            return bool(rest) and rest[0] in READ_TMUX
        if head == "gh":
            return rest[:2] == ["pr", "list"]
        if head == "ps":
            return True
        if head == "bash":
            return rest[1:2] == ["check"]   # 벌점 판정기 check <팀>
        return "peek" in rest and self.mbox in argv   # mbox peek = 우편함 장부 읽기

    def call(self, argv, timeout=CALL_S, retry=0):
        """바깥 호출 1곳 → (rc, stdout, stderr 1줄) · 넘침·실행 실패 = rc None · retry = rc≠0 때 다시 부르는 횟수.
        R2 문 — 판독 = min(자기 상한, 남은 몫)으로 줄여 부르고 그 상한에 걸리면 끊김 · 쓰기 = 남은 몫이 자기 상한보다 작으면 시작 0(끊김)."""
        if self.halt and (argv[1:2] in (["kill-session"], ["send-keys"]) or argv[:1] == [sys.executable] or self.close_bin in argv[1:2]):   # r2055 정지 중 실행 0(그물)
            self.log("판정 불가", self.at or "-", "ALL_STOP 정지 중 실행 막음 %s" % " ".join(os.path.basename(w) for w in argv[:2]))
            return None, "", "ALL_STOP"
        self.cache.get("@round", {}).pop("ls", None) if "kill-session" in argv or argv[:1] == [sys.executable] else None   # r1969 세션이 바뀜 = 바퀴 list-sessions 캐시 버림
        read, shrunk = self.reading(argv), False
        left = None if self.in_fetch else self.left()   # R6 fetch 는 지금 규칙 그대로(구획 밖)
        if left is not None:
            if left < MIN_S:
                raise self.cut_at()
            if read:
                shrunk, timeout = left < timeout, min(timeout, left)
            elif left < timeout or (timeout > CALL_S and time.monotonic() - self.start > LONG_S):   # R2 쓰기 = 시작 0
                raise self.cut_at()
        for n in range(1, retry + 2):
            at = self.now()
            over = False
            try:
                done = subprocess.run(argv, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout, env=self.env, cwd=self.root)   # r2115 A1 깨진 바이트 = U+FFFD
                out = (done.returncode, done.stdout, done.stderr.strip()[:200])
            except subprocess.TimeoutExpired as exc:
                out, over = (None, "", str(exc)[:200]), True
            except OSError as exc:
                out = (None, "", str(exc)[:200])
            dt, cell = self.now() - at, self.tally.setdefault((self.at, self.stage), [0, 0.0])
            self.note(head2(argv), dt)
            self.item_note(head2(argv), dt)   # r2339 I2 항목 안 호출이면 그 항목에 수·초(항목 밖 = 그 팀·칸에만 남고 ITEM-SLOW 는 항목 키만 읽는다)
            cell[:] = [cell[0] + 1, cell[1] + (dt if dt >= SLOW_S else 0.0)]
            if dt >= SLOW_S:   # r1992 시도마다 1줄 · argv 앞 3낱말(git -C <repo> = repo 이름 · 경로 = 끝 이름 · 뒤 토큰 0)
                head = [argv[0]] + argv[2:] if argv[1:2] == ["-C"] else argv
                self.log("SLOW-CALL", self.at or "-", "%s %s s=%g rc=%s try=%d/%d" % (self.stage, " ".join(os.path.basename(w.rstrip("/")) or w for w in head[:3]), round(dt, 1), out[0], n, retry + 1))
            if over and shrunk:
                raise self.cut_at()   # R2 남은 몫으로 줄인 상한에 걸림 = 느린 것이 아니라 예산이 다한 것(판정 불가 0)
            if over and read and self.git_call(argv) and not self.in_fetch:
                raise self.ungraded()   # R7 로컬 git 7초 넘음 = 판정 불가 1줄 · 성공으로도 실패로도 읽지 않는다
            if out[0] == 0:
                break
        return out

    def complete(self, *args):   # r2026 — complete 접수(done 확인) 직후 card_stage 1회
        return land.Landing.complete(self, *args) and (self.stage_card(*args[:2]) or True)

    def stage_card(self, team, work):
        """r2026 — STAGED·NOOP = 끝 · Unsure = 쓰기 0 + 다음 바퀴 재시도(같은 work · 하루 3회 상한)."""
        book, key, day = self.state.setdefault("staging", {}), team + "|" + work, self.stamp()[:10]
        if self.state.setdefault("staged", {}).get(key) == day or key in self.tried:   # r2140 K3 성공 기억(r2149 그날만) · DA ⓐ 한 바퀴 같은 work 1회
            return None
        self.tried.add(key)
        n = book[key][1] if book.get(key, [None])[0] == day else 0   # 날이 바뀜 = 0부터
        if n >= 3:
            return None
        if len(book.get(key, ())) > 2 and self.root not in self.stale and book[key][3] == self.hits(team, work):   # r2266 C1 영구 사유 · 적중 지문 같음 = 재시도 0(날 무관 · BYZ 낡은 바퀴 = 비교 0)
            return None
        real = {name: getattr(self.cs, name) for name in ("spawn", "proc") if hasattr(self.cs, name)}   # r2287 C2 git · lib bash 둘 다 문 안(대역은 spawn 만일 수 있음)
        heads = {"spawn": lambda cwd, args, env=None: head2(["git", "-C", cwd] + list(args)), "proc": lambda argv, *a, **kw: head2(argv)}
        for name, hand in real.items():
            setattr(self.cs, name, self.gate(hand, heads[name]))
        try:
            at = self.cs.done_at(self.root, team, work)
            if not at:
                raise self.cs.Unsure("done 없음")
            out = self.cs.stage(self.root, self.root, team, work, at, self.stamp(), **self.no_fetch())
        except (self.cs.Unsure, subprocess.TimeoutExpired, OSError) as exc:
            got = self.hits(team, work) if str(exc).startswith(STUCK) and self.root not in self.stale else None   # r2266 C1 값 기억 = [사유, 적중 지문]
            book[key] = [day, n + 1] + ([str(exc), got] if got is not None else [])
            return self.log("Unsure", team, "%s card_stage %s" % (work, exc))
        except OutOfRound as exc:   # 예산 모자람 = 하루 3회 셈 밖 · 다음 바퀴
            book[key] = [day, n]
            return self.log("DEFER", team, "%s card_stage %s — 다음 바퀴" % (work, exc))
        finally:
            [setattr(self.cs, name, hand) for name, hand in real.items()]
        book.pop(key, None)
        self.state["staged"][key] = day   # r2140 K3 STAGED·NOOP = 기억(state.json · Unsure·DEFER 는 0)
        if out:   # r2284 C1 STAGED = ref 옮김 → 그 팀 카드 목록 캐시 버림(같은 바퀴 B2 landing 새 ref 로 다시 읽음 · NOOP = 그대로)
            self.cache.pop(team, None), [self.cache["@round"].pop(x) for x in list(self.cache.get("@round", {})) if isinstance(x, tuple) and x[:2] == ("card", team)]
        return self.log("CARD-STAGE", team, "%s %s %s" % (work, out[1], out[2])) if out else self.log("NOOP", team, work + " 이미 완성")

    def no_fetch(self):
        """r2311 K1 — 이 바퀴 fresh 가 BYZ land.REFS 두 가지(main·ops/main-base)를 다 맞췄을 때만 card_stage 첫 fetch 0(사전 DA 조건 1) · 대역 stage 가 인자를 모르면 인자 0."""
        want = ["+refs/heads/%s:refs/remotes/origin/%s" % ((r.split("/", 1)[1],) * 2) for r in land.REFS]
        fresh = self.root not in self.stale and all(x in self.refs.get(self.root, ()) for x in want)
        return {"fetch": False} if fresh and "fetch" in inspect.signature(self.cs.stage).parameters else {}

    def gate(self, real, head):
        """r2026 R1 · r2287 C2 — card_stage 바깥 호출 1회(git spawn · lib proc) 전마다 바퀴 남은 몫 ≥ 7초 · 모자람 = OutOfRound(시작 0) · 초 = 칸 top(C3)."""
        def hand(*args, **kw):
            left = self.left()   # r2098 R1 바퀴 예산 시계(구획 끝까지 남은 초 · 바퀴 밖 = None = 묶음 0)
            if left is not None and left < CALL_S:
                raise OutOfRound("바퀴 예산 남음 %g초" % round(left, 1))
            at = self.now()
            try:
                return real(*args, **kw)
            finally:
                self.note(head(*args), self.now() - at)
        return hand

    def note(self, path, dt):
        """r2287 C3 — 지금 칸(팀, 칸)에 바깥 호출 1회 초 · 합 + 큰 3개(초 큰 순 · 같으면 먼저 온 것)."""
        got = self.cell_calls.setdefault((self.at, self.stage), [0.0, []])
        got[0] += dt
        got[1] = sorted(got[1] + [(round(dt, 1), path)], key=lambda x: -x[0])[:3]

    def item_note(self, path, dt):
        """r2339 I2 — 바깥 호출 1회를 지금 항목(b1·b2f 칸 안이면 열린 항목 · 밖이면 그 팀·칸)에 수 +1 · 초 더함 · 첫 두 낱말별 초 합."""
        got = self.item_call.setdefault(self.item_cur or (self.at, self.at_work, self.stage), [0, 0.0, {}])
        got[0] += 1
        got[1] += dt
        got[2][path] = got[2].get(path, 0.0) + dt

    def item_calls(self, key):
        """r2339 I2 — 그 항목 안에서만 센 바깥 호출 (수, 초, 낱말별 초) · 항목 밖 호출은 안 든다(없으면 0)."""
        return self.item_call.get(key) or (0, 0.0, {})

    def item_slow(self):
        """r2339 I3 — «ITEM-SLOW <칸> <팀>/<work> s=<초> parts=<이름>:<초>,… call=<수>:<초> top=<낱말>:<초>».
        항목(팀 · work · 칸) 합 ≥ ITEM_SLOW_S 만 · 느린 순 3개 · 넘치면 마지막 줄 끝에 more=N · 넘는 항목 0 = 빈 목록."""
        got = [(sum(parts.values()), stage, team, work, parts) for (team, work, stage), parts in self.item_parts.items()]
        slow = [row for row in got if row[0] >= ITEM_SLOW_S]   # r2339 I3 이 초 이상만
        slow.sort(key=lambda row: (-row[0], row[1], str(row[2]), str(row[3])))
        lines = []
        for sec, stage, team, work, parts in slow[:3]:
            calls, call_s, verbs = self.item_calls((team, work, stage))
            top = max(verbs.items(), key=lambda kv: (kv[1], kv[0])) if verbs else None
            order = sorted(parts.items(), key=lambda kv: (-kv[1], kv[0]))
            lines.append("%s %s/%s s=%.2f parts=%s call=%d:%.2f top=%s" % (
                stage, team or "-", work, sec, ",".join("%s:%.2f" % kv for kv in order), calls, call_s,
                "%s:%.2f" % top if top else "-"))
        more = len(slow) - len(lines)
        if more and lines:
            lines[-1] += " more=%d" % more
        return lines

    def hits(self, team, work):
        """r2266 C1 적중 지문 = land.REFS 두 ref 의 design/**/indices/<단계>/ 카드 중 card() 이름 규칙(짝 표 → <work>.md → <work>-*.md)에 드는 [ref, 경로, blob] 이름순(적중 0 = []) ·
        읽기 = 바퀴 fetch 로 신선한 remote-tracking ref(ls-tree 1회 · ref 마다 바퀴 캐시) · 판독 실패 = None."""
        mapped = self.cardmap(team)
        mapped = mapped.get(work) or [] if isinstance(mapped, dict) else mapped
        if isinstance(mapped, str):
            return None
        names, dirs, out, trees = {os.path.basename(p) for p in mapped}, [["indices", s] for s in land.STAGES], [], self.cache.setdefault("@round", {}).setdefault("tree", {})
        like = lambda b: b in names if names else b == work + ".md" or b.startswith(work + "-") and b.endswith(".md")   # noqa: E731
        for ref in land.REFS:
            if ref not in trees:
                rc, text, _ = self.git(self.root, "ls-tree", "-r", "-z", ref, "--", "design")
                if rc != 0:
                    return None
                trees[ref] = [row.partition("\t")[::2] for row in text.split("\0") if "\t" in row]
            out += [[ref, p, meta.split()[2]] for meta, p in trees[ref] if like(os.path.basename(p)) and p.split("/")[-3:-1] in dirs]
        return sorted(out)

    @staticmethod
    def git_call(argv):
        return bool(argv) and os.path.basename(argv[0]) == "git"

    def ungraded(self):
        """R7 — `판정 불가 <팀> <work> git 7초 넘음` 1줄 + Ungraded."""
        self.log("판정 불가", self.at or "-", "%s git %g초 넘음" % (self.at_work or "-", GIT_S))
        return Ungraded()

    def left(self):
        """R1 남은 몫(초) = 구획 끝까지(업무 45 · report 55 · 마무리 0) · 나노 가지 모으기 중이면 그 7초 끝까지 · 바퀴 밖 = None(문 없음)."""
        if self.start is None:
            return None
        end = self.start + self.sect
        if self.nano_dl is not None:
            end = min(end, self.nano_dl)
        return end - time.monotonic()   # R1 벽시계 = monotonic 주입점

    def nano_slow(self):
        """r2315 N2 — «NANO-SLOW s=<합> <팀>:<초>/rows=<초>/git=<수>:<초>/w=<수> … other=<합 밖> top=<팀>/<work>:<초>».
        초 큰 팀부터 5개 · 끊긴 팀도 셈이 있으면 든다(nanos 가 finally 에 남긴다 · DA H1) · 셈이 없으면 빈 칸."""
        rows = sorted(self.nano_stat.items(), key=lambda kv: kv[1]["s"], reverse=True)
        cells = ["%s:%.2f/rows=%.2f/git=%d:%.2f/w=%d" % (t, c["s"], c["rows"], c["git"], c["git_s"], c["works"])
                 for t, c in rows[:5]]
        slow = max((c["slow"] + (t,) for t, c in rows if c["slow"][0]), default=None, key=lambda x: x[1])
        return "s=%.2f %s other=%.2f top=%s" % (self.nano_s, " ".join(cells) or "-",
                                                max(0.0, self.nano_s - sum(c["s"] for _, c in rows)),
                                                "%s/%s:%.2f" % (slow[2], slow[0], slow[1]) if slow else "-")

    def cut_at(self):
        """R3·R4 — 끊긴 자리 = (팀, work, 칸) → Cut(예산)."""
        stage = "report" if self.sect != WORK_S else self.cursor_stage if self.cursor_stage != "-" else (self.stage or "-")
        self.cut_pos = (self.at or "-", self.at_work or "-", stage)
        self.cut = ":".join(self.cut_pos)
        return Cut(self.cut)

    def rows_of(self, team):
        """그 팀 journal 줄 — 바퀴 안 1회(R4 자리 차례·items 셈과 team_round 가 같은 읽기를 쓴다)."""
        if team not in self.jrows:
            try:
                node = projection.journal.Journal(projection.runtime_path(self.root, team), rec=projection.record)
                self.jrows[team] = node.records()
            except OSError:   # runtime 폴더 없음 = 일 0(자리 셈만 0)
                self.jrows[team] = []
        return self.jrows[team]

    def proj_of(self, team):
        """r2251 O1 그 팀 투영 — 바퀴 안 1회(book() 의 쉼 ∧ done 과 team_round 가 같은 값 · 바퀴 사이 complete = 다음 바퀴)."""
        if team not in self.jprojs:
            self.jprojs[team] = self.project(self.root, team)
        return self.jprojs[team]

    def works_of(self, team):
        if team not in self.ws:
            self.ws[team] = sorted({rec["work"] for rec in self.rows_of(team) if rec.get("kind") == "dispatch" and rec.get("work")})
        return self.ws[team]

    def key(self, team, work, stage):
        """R4 자리 좌표 = (팀 차례, work 차례, 칸 차례)."""
        teams, works = self.order, (self.works_of(team) if team in self.order else [])
        return (teams.index(team) if team in teams else len(teams), works.index(work) if work in works else len(works),
                ORDER.index(stage) if stage in ORDER else len(ORDER))

    def positions(self):
        """R4 자리 전부 = work 마다 b1·b2c·stall → 팀의 b2f(fill) → b3o → b3r(차례대로)."""
        pos = [(team, work, stage) for team in self.order for work in self.works_of(team) for stage in ("b1", "b2c", "stall")]
        pos += [(team, "-", "b2f") for team in self.order] + [("-", "-", "b3o"), ("-", "-", "b3r")]
        return sorted(pos, key=lambda one: self.key(*one))

    def cell_total(self):
        """R10 분모 — 이 바퀴에 돌 수 있는 자리 = 자리 목록 에서 cursor 앞 · 안 도는 자리(unused) · 처음부터 건너뛸 work 의 자리를 뺀 것.

        건너뛸 work 는 바퀴 시작 스냅샷(self.skipped_works)이다 — 이번 바퀴에 방문해서 handled 가 된 work(영수)는
        이미 센 자리라서 빼지 않는다(R3). 뒤 팀의 처리 끝난 work 는 시작부터 스냅샷에 있어 앞 팀에서 끊겨도 분모에 안 남는다(R2)."""
        return len([p for p in self.positions() if not self.before(*p) and p not in self.unused and (p[0], p[1]) not in self.skipped_works])

    def book(self, team):
        """r1990·r2055 — (반환·쉼 (work, attempt), 건너뛰는 work) · 고리와 분모 셈이 같은 식을 쓴다.

        r2251 O1 — 최신 attempt 가 쉼(LAUNCH_FAILED 아님)이고 투영 done 이면 건너뛰지 않는다(닫기 길) · handled 는 그대로 · 반환(O3)은 손 0."""
        rows = self.rows_of(team)
        back = {(rec["work"], rec.get("attempt")) for rec in rows if rec.get("kind") == "returned"}
        rest = {(rec["work"], rec.get("attempt")) for rec in rows if rec.get("kind") == "parked" and rec.get("reason") != settling.LAUNCH_FAILED} - back   # r2251 O3
        back |= rest
        latest = {rec["work"]: rec.get("attempt") for rec in rows if rec.get("kind") == "dispatch" and rec.get("work")}
        handled = {work for work, attempt in latest.items() if "%s|%s@%s" % (team, work, attempt) in self.state["handled"]}
        gone = handled | {work for work, attempt in latest.items() if (work, attempt) in back}
        open_ = {work for work in gone - handled if (work, latest[work]) in rest}
        if open_:   # r2251 투영 읽기 = 쉼 후보가 있을 때만(바퀴 안 1회 캐시)
            proj = self.proj_of(team)
            works = (proj.get("works") or {}) if proj.get("result") == OK else {}
            gone -= {work for work in open_ if (works.get(work) or {}).get("done")}   # r2251 O1 쉼 ∧ done
        return back, gone, open_   # r2258 O1 open_ = 쉼(LAUNCH_FAILED·반환 밖) ∧ handled 밖

    def left_over(self, team, work):
        """R10 — 판정이 끝난 work 의 안 돈 자리(b1 · b2c · stall)는 이 바퀴에 돌 수 있는 자리가 아니다."""
        for stage in ORDER[:3]:
            if (team, work, stage) not in self.seen:
                self.unused.add((team, work, stage))

    def team_key(self, team, work, stage):
        """r2323 T2 — 팀 안 자리 좌표(work 차례, 칸 차례) · team_cursor 는 그 팀 안에서만 견준다."""
        works = self.works_of(team) if team in self.order else []
        return (works.index(work) if work in works else len(works), ORDER.index(stage) if stage in ORDER else len(ORDER))

    def before(self, team, work, stage):
        """R4 — cursor 자리 앞이면 True(이번 바퀴 0 · 재판독 0).

        r2323 T2 — 바퀴 cursor 를 먼저 본다(T3 «R2 끊긴 자리 우선» · DA#39 ⓐ: 재개한 팀이 그 팀 안에서 끊긴 자리)
        그 뒤에 그 팀 자리(state team_cursor)를 견준다 — 상한으로 멈춘 팀만 · 1곳."""
        if self.curs is not None and self.key(team, work, stage) < self.curs:
            return True
        cur = self.tcurs.get(team)
        return bool(cur) and self.team_key(team, work, stage) < self.team_key(team, cur.get("work"), cur.get("stage") or "b1")

    def team_cap(self, team, work, stage):
        """r2323 T1·T2 — 이 바퀴 그 팀이 쓴 업무 초 ≥ WORK_S/2 이고 뒤 팀이 남았으면 그 팀은 여기서 멈춘다.

        멈춘 자리 = state team_cursor(그 팀만 · 다음 차례에 거기부터) · 바퀴 cursor = 다음 팀 머리(감아 돌기 0 · T4 혼자 남은 팀 = 상한 0)."""
        if team not in self.order:   # R4 거름 — order 밖 팀(단위 호출·낡은 명부) = 상한 0
            return False
        spent = self.now() - self.team_at
        nxt = self.order[self.order.index(team) + 1:]
        if not nxt or spent < WORK_S / 2:
            return False
        self.state.setdefault("team_cursor", {})[team] = {"work": work, "stage": stage}
        self.state["cursor"] = {"team": nxt[0], "work": "-", "stage": "b1", "cuts": 0}
        self.capped = True
        self.log("TEAM-CAP", team, "%s %s s=%g — 다음 팀" % (work, stage, round(spent, 1)))
        return True

    def at_pos(self, stage):
        """자리 1개 진입 — cursor 앞이면 False · 온 자리 = items + 1 · 지금 칸 = stage(끊김 자리 기록)."""
        if self.before(self.at, self.at_work, stage):
            return False
        self.items += 1
        self.cursor_stage = stage
        self.seen.add((self.at, self.at_work, stage))   # R10 분모 = 돈 자리
        return True

    def next_pos(self, team, work, stage):
        pos, here = self.positions(), (team, work, stage)
        return pos[pos.index(here) + 1] if here in pos and pos.index(here) + 1 < len(pos) else None

    def mark_cut(self):
        """R3·R4·R5 — 끊긴 자리를 cursor 로 남긴다 · 같은 자리 2바퀴 연속 = 판정 불가 1줄 + 다음 자리(굶김 0)."""
        team, work, stage = self.cut_pos or ("-", "-", "-")
        if stage == "report":
            self.state["rep_cursor"] = {"seat": self.report_seat or ""}
            self.log("ROUND-CAP", text="- - report — 다음 바퀴 여기부터")
            return
        prev = self.prev_cursor or {}
        cuts = int(prev.get("cuts") or 0) + 1 if (prev.get("team"), prev.get("work"), prev.get("stage")) == (team, work, stage) else 1
        self.log("ROUND-CAP", team, "%s %s — 다음 바퀴 여기부터" % (work, stage))
        if cuts >= 2:   # R5 — 같은 자리 2바퀴 연속 = 그 자리를 건너뛴다
            self.log("판정 불가", team, "%s %s 예산 2회 넘음 — 건너뜀" % (work, stage))
            nxt, cuts = self.next_pos(team, work, stage), 0
            if nxt is None:
                self.state.pop("cursor", None)
                return
            team, work, stage = nxt
        self.state["cursor"] = {"team": team, "work": work, "stage": stage, "cuts": cuts}

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
                rc, _, self.fetch_err[repo] = self.git(repo, "fetch", "-q", "--no-tags", "origin", *self.fetch_refs(repo), timeout=FETCH_S)   # r2241 stderr = 묵은 ref 잠금 찾기 첫 후보
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
            fh.write(json.dumps({"at": at, "kind": kind, "team": team or self.who, "line": line}, ensure_ascii=False) + "\n")

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
        return self.locked(lambda: kblock.after(self, self._round)) or 0   # r2072 바퀴 끝 장부 올림(잠금 안 · 판정·로그·rc 불변)

    def report_once(self):
        self.skip = self.skipped()   # r1835 K4 — 판독 실패 = probe·쪽지 0 · 출력 1줄(로그 줄 0)
        return "판정 불가 · SKIP_TEAMS 판독 실패" if self.skip is None else self.locked(self._report_round) or "판정 불가 · 바퀴 진행 중"

    def _report_round(self):
        """--report 한 바퀴 — R1 예산 시계는 여기도 돈다(report 구획 45~55초)."""
        self.start, self.sect = time.monotonic(), REPORT_S
        self.jrows, self.ws, self.report_seat, self.notify_used = {}, {}, None, 0
        self.deferred, self.send_fails, self.send_stop = {}, 0, False
        try:
            return self.report()
        except Cut:
            self.mark_cut()
            return "판정 불가 · report 예산 다함"

    def skipped(self):
        """r1835 K1 — SKIP_TEAMS 줄마다 팀 1개(빈 줄·# 무시) · 바퀴마다 읽음 · 없음 = 빈 집합 · 못 읽음 = None."""
        try:
            with open(os.path.join(self.dir, "SKIP_TEAMS"), encoding="utf-8") as fh:
                return {x.strip() for x in fh if x.strip() and not x.strip().startswith("#")}
        except (OSError, UnicodeDecodeError) as exc:
            return set() if isinstance(exc, FileNotFoundError) else None

    def timed(self, stage, fn, *args, part=None, work=None):
        """r1817 D3 — 단계별 초(주입 시계 self.now) 누적 · 반환 = fn 결과 · r2306 K1 part = b3r 자리 안 몫 키(b3r.sweep·b3r.retired).
        r2339 I1 work = 이 호출이 도는 work(명시 인자 · args 위치 해석 0) · 항목 칸(b1·b2f)이면 finally 에 (팀 · work · 칸) 합과 부분 단계(fn 이름) 초를 더한다."""
        at, prev, self.stage, pos = self.now(), self.stage, stage, self.cursor_stage
        item, outer = ((self.at, work, stage) if work is not None and stage in ITEM_STAGES else None), self.item_cur
        self.item_cur = item
        try:
            return fn(*args)
        finally:
            self.stage, self.item_cur, dt = prev, outer, self.now() - at
            self.spent[stage] += dt
            self.per[(self.at, stage)] = self.per.get((self.at, stage), 0.0) + dt
            if stage == "b3":   # r2298 A2 b3 칸 = b3o·b3r 자리 몫(at_pos 가 적은 자리)
                self.b3p[pos] = self.b3p.get(pos, 0.0) + dt
            if part:   # r2306 K1 b3r 자리 안 몫(끊김·예외로 빠져도 finally 에서 더함)
                self.b3r_parts[part] = self.b3r_parts.get(part, 0.0) + dt
            if item:   # r2339 I1 끊김(Cut)·예외로 빠져도 finally 에서 더한다 · 부분 단계 = fn 이름
                parts = self.item_parts.setdefault(item, {})
                name = getattr(fn, "__name__", None) or "-"
                parts[name] = parts.get(name, 0.0) + dt

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
        self.start, self.skip = time.monotonic(), self.skipped()   # r2098 R1 예산 시계 = 바퀴 시작 벽시계(주입 시계)
        self.sect, self.items, self.total, self.cut, self.cut_pos, self.prev_cursor, self.curs = WORK_S, 0, 0, "-", None, None, None
        self.capped = False   # r2323 T1 이 바퀴에 상한으로 멈춘 팀이 있었나(cursor 를 남기는 문)
        self.jrows, self.ws, self.order, self.report_seat, self.nano_dl, self.unused = {}, {}, [], None, None, set()
        self.item_parts, self.item_call, self.item_cur = {}, {}, None   # r2339 I3 항목 셈 = 바퀴 1개분(상주 누적 0)
        self.jprojs = {}   # r2251 O1 투영 = 바퀴마다 새로
        self.tried = set()   # r2140 DA ⓐ 이 바퀴에 card_stage 를 부른 team|work
        self.seen = set()   # R10 분모 = 이 바퀴에 돈 자리(at_pos 가 적는다) · 안 돈 자리는 left_over 가 뺀다
        self.skipped_works = set()   # R10 바퀴 시작에 건너뛸 work(handled·반환·쉼) — 이번 방문 뒤 handled 는 안 든다(R3)
        self.prev_cursor = dict(self.state.get("cursor") or {}) or None   # R5 «같은 자리 2바퀴 연속» 을 세려고 남긴다
        self.deferred = {}   # R8 쪽지 몫(notify_used · send_fails · send_stop)은 바퀴 끝에서 되돌린다(한 바퀴 3통 · 시간 초과 2회)
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
        at, got, nano_cut = time.monotonic(), {}, False   # r2098 R6 나노 가지 모으기 = 합 7초(판독을 R2 로 줄임)
        self.nano_stat = {}   # r2315 N1 바퀴마다 셈을 비운다
        self.nano_dl, order, team = at + NANO_S, ([] if self.table else self.teams()), ""
        first = order.index(self.state["nano_next"]) if self.state.get("nano_next") in order else 0   # r2303 A1 끊긴 팀부터 · A2 없으면 맨 앞
        order = order[first:] + order[:first]
        try:
            for team in order:
                got.update(kf.nanos(self, [team]))   # 팀마다 모아 두고 끊기면 모은 것만(부분 손실 0) · r2315 팀 셈은 nanos 가 self.nano_stat 에 남긴다(끊긴 팀도)
        except Cut:
            nano_cut = True
            self.cut, self.cut_pos = "-", None   # r2245 N1 — 나노 모으기 끊김은 업무 구획 끊김이 아니다(cut 칸·cursor 흔적 0)
            self.state["nano_next"] = order[1 % len(order)] if team == order[0] else team   # r2303 A1 시작 팀 끊김 = 다음 팀(혼자 몫 초과가 시작을 붙잡지 않게)
        if order and not nano_cut:   # r2303 A1 끊기지 않고 다 돎 = 키 지움
            self.state.pop("nano_next", None)
        self.nano, self.nano_s, self.nano_dl = ({} if self.table else got), time.monotonic() - at, None
        self.who = team if nano_cut else ""   # r2303 A3 끊김 줄 team 칸 = 끊긴 팀
        if nano_cut or self.nano_s >= NANO_S:
            self.log("판정 불가", text="나노 가지 모으기 7초 넘음 — 모은 것만")
            self.who = ""   # r2315 N2 — NANO-SLOW 줄은 team 칸 없이 `s=…` 로 시작한다
            self.log("NANO-SLOW", text=self.nano_slow())   # r2315 N2 넘김·끊김 때만 팀마다 초·git·work 를 남긴다
        self.who = ""
        def both(repos=self.picked):   # r1963 두 리포 동시 → fetch 단계 = 느린 쪽 하나 · 낡은 리포 집합은 바퀴마다 새로 · R6 fetch 는 지금 규칙 그대로
            with concurrent.futures.ThreadPoolExecutor(2) as pool:
                return [repo for repo, ok in zip(repos, pool.map(self.fresh, repos)) if not ok]
        self.in_fetch = True
        try:
            self.stale = {repo for repo in self.timed("fetch", both)}
        finally:
            self.in_fetch = False
        self.sock = self.socket_ok()
        if self.stale:   # BYZ 낡음 = 카드·TEAMS·짝 표도 낡음 → 판정 0 · 팩만 낡음 = 팩 ref 를 읽는 판정(landing 조상·다음 카드 target)만 0
            self.log("판정 불가", text="git fetch 실패 %s — %s%s" % (" ".join(r for r in (self.root, self.pack) if r in self.stale), kf.lock_note([r for r in (self.root, self.pack) if r in self.stale], self.fetch_err), "이 바퀴 B1·B2 0" if self.root in self.stale else "팩 기대 판정만 0"))
        if out := [r for r in (self.root, self.pack) if r not in self.picked]:   # r1975 ② 목록 밖 리포 = fetch 0 · 그 리포를 읽는 판정만 0
            self.stale |= set(out)
            self.log("판정 불가", text="FETCH_TARGETS 밖 %s — fetch 0 · %s" % (" ".join(out), "이 바퀴 B1·B2 0" if self.root in out else "팩 기대 판정만 0"))
        self.order = [] if self.root in self.stale else self.teams()   # R4 차례 = 팀(이름순) → work → 칸 → b3o → b3r
        if not self.state.get("cursor") and self.state.get("cap_next") in self.order:   # r1898 옛 키 = cursor 로 옮긴다(팀 자리)
            self.state["cursor"] = {"team": self.state.pop("cap_next"), "work": "-", "stage": "b1", "cuts": 0}
        self.curs = self.cursor_key()
        self.tcurs = {team: dict(cur) for team, cur in (self.state.get("team_cursor") or {}).items()}   # r2323 T2 바퀴 시작 스냅샷(분모·before 가 같은 값을 본다)
        self.skipped_works = {(team, work) for team in self.order for work in self.book(team)[1]}   # R10 처음부터 건너뛸 work = 모든 팀을 바퀴 시작에 센다
        self.total = self.cell_total()
        skip = self.order.index(self.state["cursor"]["team"]) if self.curs is not None else 0   # R4 커서 팀 앞은 이번 바퀴 0
        try:
            for team in self.order[skip:]:
                if (left := self.left()) is not None and left < MIN_S:   # R2 — 다음 팀 첫 호출 전에도 남은 몫을 본다
                    self.cut_pos, self.cut = (team, "-", "b1"), "%s:-:b1" % team
                    raise Cut(self.cut)
                try:
                    self.team_round(team)
                except Ungraded:
                    continue   # R7 팀 자리 판정 불가 = 그 자리 남은 판정 0 · 뒤 팀은 돈다(원천 = b2f = 그 팀 마지막 자리 · 남은 자리 0 · 분모 손 0)
            self.at, self.at_work = None, "-"
            self.cursor_stage = "stall"   # accept_only 동안(자리 없이 도는 팀 칸)
            if self.sock and not self.halt and self.at_pos("b3o"):
                try:
                    self.timed("b3", endings.orphans, self, self.order)   # r1960 ⑤ 스냅샷 뒤 journal 새로 읽기
                except Ungraded:
                    pass   # R7 b3o 판정 불가 = b3o 자리만 0 · b3r 은 돈다
            else:
                self.unused.add(("-", "-", "b3o"))   # R10 안 도는 자리 = 분모에 남기지 않는다
            if self.sock and self.at_pos("b3r"):
                self.timed("b3", self.close_old.sweep, part="b3r.sweep")   # r2281 승계 끝 구 나노 = B3 앞(닫힌 세션은 B3 list-sessions 밖)
                self.timed("b3", self.retired, part="b3r.retired")   # r2055 정지 중 = 판정·«예정» 줄만(retire_one 안에서)
            else:
                self.unused.add(("-", "-", "b3r"))
        except Cut:
            self.mark_cut()   # R3 끊김 = 이 바퀴 업무 구획 끝 · cursor 남김 · 뒤 항목 시작 0
        except Ungraded:
            pass   # R7 판정 불가 = 그 자리 남은 판정 0 · 다음 자리(이미 판정 줄을 썼다)
        for team in [t for t in self.state.get("wake_seen", {}) if t not in self.skip]:
            self.state["wake_seen"].pop(team)   # r2267 H2 휴면 밖 바퀴 = 기억 지움(다시 휴면 = 처음 보는 팀)
        cut0 = (self.cut, self.cut_pos)
        try:
            for team in ([] if self.root in self.stale else sorted(self.skip)):   # r2267 W1 업무 구획 끝 · 휴면 팀 선행 판독 · BYZ 낡은 바퀴 = 0
                if (left := self.left()) is not None and left < CALL_S:
                    break   # W1 남은 몫 < 7초 = 그 바퀴 0 · 다음 바퀴
                closing.keeper_next.wake_read(self, team)
        except (Cut, Ungraded):
            self.cut, self.cut_pos = cut0   # 판독 끊김 = 업무 구획 cut·cursor 흔적 0
        if self.cut == "-":   # R4 — 끊기지 않고 바퀴를 다 돌았으면 cursor 를 지운다
            if not self.capped:   # r2323 T1 상한으로 멈춘 바퀴 = 다음 팀 머리를 남긴다
                self.state.pop("cursor", None)
        self.at, self.at_work, self.cursor_stage = None, "-", "-"
        self.sect = REPORT_S   # R1 report 구획(45~55초)
        try:
            self.report()
            daily.check(self)   # r2238 O2~O4 하루 정리 생존 검사(하루 1회 · stat 1회 · 멈춤 = [긴급] 1통)
            try:
                tw.check(self)   # r2275 C6 바퀴 끝 · 예산 5초 + 카드 1장(넘으면 다음 바퀴 이어서) · (팀 · 칸) 하루 묶음
            except Exception as exc:   # noqa: BLE001 — 감시 결함이 바퀴를 세우지 않는다(판정 불가 1줄)
                self.log("판정 불가", text="전이 감시 %s %s" % (type(exc).__name__, str(exc)[:80]))
        except Cut:
            self.mark_cut()   # R3 report 끊김 = rep_cursor · 마무리는 한다
        self.sect = TAIL_S   # R1 마무리 구획(55~60초) = 바깥 호출 0
        self.cache.pop("@round", None)   # r1969 바퀴 캐시 닫음
        s = sum(self.spent.values())
        s += self.nano_s
        wall = max(time.monotonic() - self.start, s)   # R10 벽시계 — 칸 합계가 더 크면(주입 시계) 그 값
        self.fa.observe(self.root, "keeper 바퀴", "keeper", int(wall), ROUND_S)   # R12 관측 = 마무리 1회 · 값 = wall · 끊김만으로는 꽉 참 아님   # r1963b 나노 가지 모으기 초도 합계에(0.05초 미만이면 칸 0 = 옛 줄 그대로)
        cells = " ".join("%s=%g" % (key, round(val, 1)) for key, val in self.spent.items())
        cells += " fetch_root=%g fetch_pack=%g" % (round(self.fetch_s[self.root], 1), round(self.fetch_s[self.pack], 1))   # r1975 ⑤ 합계 fetch= 그대로
        cells += " nano=%g" % round(self.nano_s, 1) if round(self.nano_s, 1) else ""
        self.notify_used, self.send_fails, self.send_stop = 0, 0, False   # R8 쪽지 몫 = 바퀴마다 새로(바퀴 끝에 되돌린다)
        self.total = self.cell_total()   # R10 items = 돈 자리 / (돈 수 있는 자리)
        cells += " wall=%g other=%g items=%d/%d cut=%s" % (round(wall, 1), round(max(wall - s, 0.0), 1), self.items, self.total, self.cut)   # R10
        top = max((kv for kv in self.per.items() if kv[0][0] or kv[0] == (None, "b3")), key=lambda kv: kv[1], default=None)   # r1969 가장 느린 (팀, 칸) 1개
        who = top and (top[0][0] or "-")   # r2298 A1 팀 밖 b3 칸 = «-»
        if top:   # r1992 ⑦ slow 칸의 호출 시도 수·SLOW-CALL 합(5초 미만 여러 번 = slow_call 0 으로 드러남) · ROUND 줄 그대로
            got = self.tally.get(top[0], [0, 0.0])
            spent, big = self.cell_calls.get(top[0], (0.0, []))   # r2287 C3 끝에 덧붙임만 · 호출 밖 초 = 칸 초 − 호출 초 합
            tail = " top=%s py=%g" % (",".join("%s:%g" % (path, sec) for sec, path in big) or "-", round(max(top[1] - spent, 0.0), 1)) if big or round(top[1], 1) else ""   # 호출·초 둘 다 0 = 옛 줄 그대로
            sweep = round(self.b3r_parts.get("b3r.sweep", 0.0), 1)   # r2306 K1 b3r 나눔 · sweep 0 = b3r 전부 retired = 꼬리 그대로(r2298 줄 바이트 같음)
            split = ",b3r.sweep:%g,b3r.retired:%g" % (sweep, round(self.b3r_parts.get("b3r.retired", 0.0), 1)) if top[0] == (None, "b3") and sweep else ""
            tail += " parts=b3o:%g,b3r:%g" % (round(self.b3p.get("b3o", 0.0), 1), round(self.b3p.get("b3r", 0.0), 1)) if top[0] == (None, "b3") else ""
            self.log("SLOW-CELL", who, "%s s=%g n=%d slow_call=%g" % (top[0][1], round(top[1], 1), got[0], round(got[1], 1)) + tail + split)
        for text in self.item_slow():   # r2339 I3 넘는 항목만 느린 순 3개 · 넘는 항목 0 = 줄 0
            self.log("ITEM-SLOW", text=text)
        self.log("ROUND", text="s=%g %s slow=%s%s%s%s" % (round(s, 1), cells, "%s:%s:%g" % (who, top[0][1], round(top[1], 1)) if top else "-", " OVER" if wall > ROUND_S else "", " unknown=%d" % self.unknown if self.unknown else "",
                                                       self.skip and " skip=" + ",".join(sorted(self.skip)) or ""))   # r2055 unknown=N(skip= 은 끝 칸 그대로) · OVER = wall 판정(R10)

    def cursor_key(self):
        """R4 — state 의 cursor 를 이 바퀴 자리 좌표로 푼다(옛 cap_next 는 그 팀 머리 · 그 팀이 없으면 처음부터)."""
        cur = self.state.get("cursor") or {}
        team, work, stage = cur.get("team"), cur.get("work") or "-", cur.get("stage") or "b1"
        if team not in self.order:
            return None
        if work == "-" and stage == "b1":   # 옛 키 = 팀 자리 = 그 팀 첫 work 의 b1
            works = self.works_of(team)
            work, stage = (works[0], "b1") if works else ("-", "b2f")
        return self.key(team, work, stage)

    def teams(self):
        """대상 팀 = ft20-switch/<팀>.json ∪ <팀>.held 가 있고 runtime 이 있는 팀."""
        switch = os.path.join(self.root, ".fable-team", "state", "ft20-switch")
        found = os.listdir(switch) if os.path.isdir(switch) else []
        names = {name.rsplit(".", 1)[0] for name in found if name.endswith((".json", ".held"))}
        return sorted(team for team in names if os.path.isdir(projection.runtime_path(self.root, team)) and team not in self.skip)

    def team_round(self, team):
        """최신 묶음 = work 마다 최신 dispatch 1줄의 (attempt · holder) · 자리마다 R4 cursor·R2 문을 지난다(판정 규칙은 R11 그대로)."""
        self.at, self.team_at, proj = team, self.now(), self.proj_of(team)   # r2323 T1 팀 몫 시계 = team_round 시작(주입 시계) · r2251 O1 book() 과 같은 투영
        if proj.get("result") != OK:
            return self.log("판정 불가", team, "투영 %s" % proj.get("reason", ""))
        for key in [k for k in self.state.get("staging", {}) if k.startswith(team + "|")]:   # r2026 앞 바퀴 Unsure = 재시도
            self.timed("b1", self.stage_card, team, key[len(team) + 1:], work=key[len(team) + 1:])
        rows = self.rows_of(team)   # r2098 자리 순서 셈과 같은 읽기(바퀴 안 1회)
        if self.sock and not self.halt:
            self.succeed.sweep(team, proj, rows)   # r2276 owners 순회 · 표식 갈래 = S1 먼저(승계 시도만 stall 초)
        latest = {rec["work"]: (rec.get("attempt"), rec.get("holder")) for rec in rows
                  if rec.get("kind") == "dispatch" and rec.get("work")}
        back, gone, open_ = self.book(team)   # r1990 반환·r2055 쉼 줄 · R10 건너뛰는 work(분모 셈과 같은 식)
        self.parked_failed = {(team, rec["work"], rec.get("attempt")) for rec in rows if rec.get("kind") == "parked" and rec.get("reason") == settling.LAUNCH_FAILED}   # r2058 L1
        backed = self.superseded_back(team, proj, latest) if self.sock and not self.halt else None   # r2352 K2 — 대체 끝 done 0 되찾기(팀당 1건)
        for work, (attempt, dispatched) in sorted(latest.items()):
            if work == backed:   # 이번 바뀌에 K1 길로 끝냄 = 닫기 길이 같은 일을 다시 보지 않는다
                continue
            if work in gone:
                if (work, attempt) in back and (proj["works"].get(work) or {}).get("done"):
                    self.timed("b1", self.stage_card, team, work, work=work)   # r2140 K2
                elif work in open_:   # r2258 O1 쉼 ∧ done 아님 = 착지 판정만(깨움·stall·HOLD 0)
                    self.parked_landing(team, work, attempt)
                continue   # r1990 반환·r2055 쉼인 최신 attempt = B1 complete·판정·깨움 0(새 dispatch 면 attempt 가 달라 다시 본다)
            if self.team_cap(team, work, "b1"):   # r2323 T1 — 몫 절반 넘음 = 이 팀은 여기서 멈추고 다음 팀(남은 몫으로)
                return
            self.at_work, row, self.why = work, proj["works"].get(work) or {}, ""   # r2055 판정 줄 꼬리 = 이 work 의 착지 판정 사유
            try:
                close = self.one_work(team, work, attempt, row, dispatched, rows)
            except Ungraded:
                self.left_over(team, work)   # R7 git 7초 = 그 자리 남은 판정 0 · 다음 자리
                continue
            except Exception as exc:   # r2115 A2 예상 밖 예외 = 그 work 1줄 · close 0 · 다음 work(Cut 같은 BaseException = 위로)
                self.log("판정 불가", team, "%s 내부 오류 %s" % (work, type(exc).__name__))
                self.left_over(team, work)
                continue
            if close == "close" and self.sock and (team, work, attempt) not in self.parked_failed and self.at_pos("b2c"):
                self.timed("b2c", self.close, team, work, attempt, row, dispatched)   # r2058 L2 착지면 complete 만 · 세션 없으면 닫기 0
            self.left_over(team, work)   # R10 이 work 의 안 돈 자리 = 분모에 남기지 않는다
        self.at_work = "-"
        self.state.get("team_cursor", {}).pop(team, None)   # r2323 T2 이 팀을 끝까지 돌았으면 멈춘 자리 지움
        self.cursor_stage = "stall"
        if self.sock:
            self.timed("stall", self.accept_only, team, rows)   # r2055 ⑪ accept 만 · PARK_IDLE 넘음 = UNKNOWN
        if self.sock and not self.halt and self.at_pos("b2f"):   # r1913 빈 나노 칸 1장(팀마다 1회) · r2055 정지 중 fill 0
            self.timed("b2f", closing.keeper_next.fill, self, team, work="-")
        else:
            self.unused.add((team, "-", "b2f"))   # R10 이 바퀴에 안 도는 자리 = 분모에 남기지 않는다

    def tips(self):
        """r2258 O2 — landing 이 읽는 ref tip 3개(팩 origin/main · BYZ REFS 2) · 바퀴 안 1회 · 못 읽음 = None(기억 0)."""
        rnd = self.cache.setdefault("@round", {})
        if "tips" not in rnd:
            (prc, pout, _), (brc, bout, _) = self.git(self.pack, "rev-parse", "origin/main"), self.git(self.root, "rev-parse", *land.REFS)
            rnd["tips"] = pout.split() + bout.split() if prc == 0 and brc == 0 else None
        return rnd["tips"]

    def parked_landing(self, team, work, attempt):
        """r2258 O1·O2 — 쉼 work 착지 판정 1회 → 착지면 complete 1회(land_ready 0 · 쉼 = 이미 유휴 끝) · «미도달» 만 tip 3개 키로 기억 · 그 밖 줄 0."""
        memo, key, self.at_work = self.state.setdefault("parked_unreached", {}), "%s|%s@%s" % (team, work, attempt), work
        try:
            tips = self.tips()
            if tips and memo.get(key) == tips:
                return None   # O2 세 tip 같음 = 다시 안 봄
            got = self.timed("b1", self.landing, team, work, work=work)
            if got[2] == "미도달" and tips:
                memo[key] = tips
                return None
            memo.pop(key, None)   # 착지 줄 없음 · 판정 불가 = 기억 0(다음 바퀴 다시 봄)
            return bool(got[0] and not got[2]) and self.timed("b1", self.complete, team, work, attempt, got, work=work)
        except Ungraded:
            return None
        except Exception as exc:   # r2115 A2 꼴 — 그 work 1줄 · 다음 work
            return self.log("판정 불가", team, "%s 쉼 착지 내부 오류 %s" % (work, type(exc).__name__))

    def one_work(self, team, work, attempt, row, dispatched, rows):
        """B1 한 자리(landing + complete) → «close» | «none» · 착지 밖이면 stall 칸(끊기면 Cut 이 위로).

        R4 — 앞 바퀴가 b1 을 했으면 그때의 결정을 이어받는다: cursor 칸이 b2c 면 닫기로, 그 밖이면 stall 자리로.
        cursor 가 이 work 뒤면(다른 work·팀 칸) 이 work 는 이번 바퀴 0.
        """
        cur = self.state.get("cursor") or {}
        if self.before(team, work, "b1"):
            if cur.get("team") != team or cur.get("work") != work:
                return "none"   # R4 cursor 뒤 자리 = 재판독·재닫기 0
            if cur.get("stage") == "b2c":
                self.unused.add((team, work, "stall"))
                return "close"
            return self.stall_pos(team, work, attempt, dispatched, row, rows, "")
        if row.get("done"):   # 착지면 complete 만 = close 자리
            self.timed("b1", self.stage_card, team, work, work=work)   # r2140 K1
            self.unused.add((team, work, "stall"))
            self.unused.add((team, work, "b1"))   # R10 b1 자리 없이 닫기로 = 분모에 남기지 않는다
            endings.evidence_notice(self, team, work)   # r2088 증거 줄 없음 안내(close 바로 앞 · 쓰기 0)
            return "close"
        self.at_pos("b1")
        landed = self.timed("b1", self.landing, team, work, work=work)   # r2183 H1 착지 판정 초 = b1 칸(앞 판과 같다)
        if landed[0] and not landed[2] and self.sock and not self.land_ready(team, work, attempt, dispatched):
            return "none"   # r2055 A6·S4-1 landed-wait · complete·kill 0
        if self.timed("b1", self.complete, team, work, attempt, landed, work=work):
            self.unused.add((team, work, "stall"))
            return "close"
        if self.sock and endings.ending(self, team, work):   # r1960 끝(완성후·아카이브·상태 머리) = complete 0 · close 가드 그대로
            self.unused.add((team, work, "stall"))
            return "close"
        return self.stall_pos(team, work, attempt, dispatched, row, rows, landed[2])

    def stall_pos(self, team, work, attempt, dispatched, row, rows, why):
        """stall 자리 — settle 한 길 → 깨움 → HOLD(정지 중이면 깨움·재배정 0). 반환 = «none»."""
        if self.sock and self.at_pos("stall"):
            seen = self.timed("stall", self.settle_nano, team, work, attempt, dispatched, row, why)   # r2055 착지 밖 = settle 한 길
            if seen != "PARKED" and not self.halt:   # WORKING·UNKNOWN = 기존 회복 길 그대로 · 정지 중 = 깨움·재배정 0
                self.timed("stall", self.stall.check, team, work, attempt, rows)   # r1813 · r1898 ROUND stall 칸
                self.timed("stall", hold.check, self, team, work, attempt, rows)   # r1931 HOLD 줄 늘면 깨움 1회 · 누적 3 = 인터뷰 길
        return "none"

    def alert_hand(self, sig):
        """R12 — 알림 1통을 state.alert_out 에 넣는 손(바퀴 안 바깥 호출 0 · report 구획에서 문을 지나 나간다)."""
        def hand(argv, to, body, log):
            self.state.setdefault("alert_out", []).append({"to": to, "body": body, "sig": sig, "tries": 0, "mark": "", "log": log})
            return 0
        return hand


class _Alert:
    """R12 — keeper 바퀴의 full_alert 손. 보내지 않고 state.alert_out 에 1줄 넣기만 한다(바퀴 안 바깥 호출 0 · 서명 저장 순서는 full_alert 그대로).

    Slack 수신기 쪽(wiring·receive)은 지금처럼 ``full_alert`` 를 직접 불러 기본 손(_send)으로 보낸다."""

    INTAKE_CAP = full_alert.INTAKE_CAP

    def __init__(self, keeper):
        self.k = keeper

    def observe(self, root, cap, team, value, limit, blocked=""):
        return full_alert.observe(root, cap, team, value, limit, blocked, send=self.k.alert_hand("%s|%s" % (cap, team)))

    def remaining(self, root, team, result, blocked=""):
        return full_alert.remaining(root, team, result, blocked, send=self.k.alert_hand("남은 일|" + team))

    def journal(self, root, team, out, blocked=""):
        return full_alert.journal(root, team, out, blocked, send=self.k.alert_hand("journal|" + team))


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
