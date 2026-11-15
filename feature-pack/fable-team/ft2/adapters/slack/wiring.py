"""ft2 Slack 팀 도구 배선 (r1807 · S-2) — 어댑터 주입점(deliver·notify·post)에 좌석 깨움·issues 기록·게시를 꽂는다.
A2 deliver = 깨움 명령 1회(FT2_SLACK_WAKE · 기본 <root>/.fable-team/comm/mbox.sh send) · A3 «새 업무» = issues Intake
같은 command 기록만 · A4 notify = desk 깨움(같은 command·사유 재알림 0) · A5/A6 `slack reply`·`slack notify` = SlackPublish
1회. 어댑터 5파일·route 규칙은 손대지 않는다 · 모델 호출 0 · 실패는 rc≠0 기록 1줄(조용한 성공 0)."""

import collections, glob, hashlib, importlib.util, json, os, re, shlex, subprocess, sys, time  # noqa: E401

_HERE = os.path.dirname(os.path.abspath(__file__))
def _adapter(name):  # 경로로 읽기만(수정 0)
    spec = importlib.util.spec_from_file_location("ft2_wire_" + name, os.path.join(_HERE, name + ".py"))
    spec.loader.exec_module(module := importlib.util.module_from_spec(spec))
    return module
_PI = os.path.join(os.path.dirname(_HERE), "pi")
def _pi_adapter(name):  # r2065 행 E 가 넣은 공용 함수(장부 판독·명부 찾기)를 부른다 — 같은 판독을 여기 다시 만들지 않는다
    spec = importlib.util.spec_from_file_location("ft2_wire_pi_" + name, os.path.join(_PI, name + ".py"))
    spec.loader.exec_module(module := importlib.util.module_from_spec(spec))
    return module
keeper, roster = _pi_adapter("keeper_report"), _pi_adapter("launch_roster")
route, publish, receive, sender_tag, channels = map(_adapter, ("route", "publish", "receive", "sender_tag", "channels"))
binding, SENDER, USAGE, UNDECIDED = route.binding, "ft2-slack-listen", 2, 3
_fa = importlib.util.spec_from_file_location("ft2_wire_full_alert", os.path.join(os.path.dirname(_HERE), "pi", "full_alert.py"))
_fa.loader.exec_module(full_alert := importlib.util.module_from_spec(_fa))  # r1886 ⓐ
FENCE, TABLE_RULE = re.compile(r"```.*?(?:```|\Z)", re.S), re.compile(r"^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$")
RESEND_GAP, RESEND_CAP, ALERT_HEAD = 60, 3, "[Slack] 알림"   # r2065 G2 60초 · G3 3회(처음 시도 포함) · G1 알림 재귀 0
RESTORE_WINDOW = 600   # pG2 G12 (나) 재기동 복원 창 — 살아 있는 후보 1개가 끝나는 195초(send 25초×3 + 간격 60초×2)의 3배
LATE_WHY = "늦은 적재 확인"   # G5 — 보내기 전 장부에 이미 붙은 글

def _text(value):  # send 출력 = bytes·str 둘 다(잘린 send 는 bytes)
    return value.decode("utf-8", "replace") if isinstance(value, bytes) else str(value or "")

def _tail(text):  # G7 — 출력 마지막 줄 앞 160자
    lines = [line for line in _text(text).splitlines() if line.strip()]
    return lines[-1].strip()[:160] if lines else ""

def _epoch(text):  # 장부 at 문자열 → 초 · 못 읽음 = 0(간격 이미 지난 것으로 본다)
    try:
        return time.mktime(time.strptime(str(text), "%Y-%m-%dT%H:%M:%S"))
    except (TypeError, ValueError, OverflowError):
        return 0.0

def _landed_row(row):  # 앞 판 장부 호환 = why 칸 «적재 있음» 도 적재로 센다
    return row.get("landed") == "있음" or "적재 있음" in str(row.get("why") or "")

class _Ledger(keeper.Reporting):
    """r2065 E7 공용 장부 판독 — Reporting 은 root 만 있으면 tail_rows·boundary·arrived 를 쓴다(그대로 부른다)."""


def has_table(text):  # r1927 마크다운 표 = 파이프 2개 이상 줄 다음 구분선 줄 · 코드 블록(```) 안 = 제외
    lines = FENCE.sub("", str(text)).splitlines()
    return any(a.count("|") >= 2 and TABLE_RULE.match(b) for a, b in zip(lines, lines[1:]))


class Wiring:
    def __init__(self, root, *, team="planner", log=None, clock=None, wake=None, now=None):
        self.root, self.team = os.path.abspath(str(root)), team
        self.log, self.clock = log or (lambda line: None), clock or (lambda: time.strftime("%Y-%m-%dT%H:%M:%S"))
        self.now = now or time.time   # G2 간격 판정용 초 · 가짜 clock 주입점
        default = "bash %s" % shlex.quote(os.path.join(self.root, ".fable-team", "comm", "mbox.sh"))
        self.wake_argv = shlex.split(wake or os.environ.get("FT2_SLACK_WAKE") or default)
        self.path = os.path.join(self.root, ".fable-team", "teams", team, "slack", "wire.jsonl")
        self.ledger, self.last_wake = _Ledger(), {}   # 갓 만든 장부 판독 몸 — root 만 꽂는다
        self.ledger.root = self.root
        self.candidates = self._restore()   # G10 — 기동 때 장부 1회 읽어 다시 보낼 후보를 채운다(유휴 회차마다 읽기 0)

    def entries(self, kind=None):
        with open(self.path, encoding="utf-8") if os.path.exists(self.path) else open(os.devnull) as handle:
            return [row for row in map(json.loads, filter(str.strip, handle)) if kind in (None, row.get("t"))]

    def _append(self, row):
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        with open(self.path, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(dict(row, at=self.clock()), ensure_ascii=False, sort_keys=True) + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        return row

    def seat(self, name):  # 명부 1칸 읽기만(쓰기 0) · 못 읽음 = None
        try:
            with open(os.path.join(self.root, ".fable-team", "seats-planner.json"), encoding="utf-8") as handle:
                return json.load(handle).get(name) or None
        except (OSError, ValueError, AttributeError):
            return None

    def wake(self, to, body, command):  # 깨움 1회 · 상한 25초(하드 룰 12 로컬 하네스 · r1833 C3) · 실패 = rc≠0 기록 1줄
        """재시도 0(그 순간에 25초를 또 쓰지 않는다) · 대신 rc≠0 이면 G1 후보 표에 넣어 유휴 회차가 다시 보낸다.
        G6 경계(seq0)는 send 바로 전에 잡고 · G7 실패 출력은 out 칸 · 적재 판정은 seq 경계 뒤 «받는 곳·첫 줄»."""
        head, mark, out, slow = body.splitlines()[0], self.ledger.boundary(), "", False
        try:
            done = subprocess.run(self.wake_argv + ["send", str(to), SENDER, body], capture_output=True,
                                  timeout=float(os.environ.get("FT2_SLACK_WAKE_TIMEOUT") or 25))
            rc, out = done.returncode, _text(done.stdout) + _text(done.stderr)
        except (OSError, subprocess.SubprocessError) as exc:
            rc, slow = -1, isinstance(exc, subprocess.TimeoutExpired)
            self.log("깨움 실패 %s" % type(exc).__name__)
            out = _text(getattr(exc, "output", "") or getattr(exc, "stdout", "") or "")
        row = {"t": "wake", "to": to, "command": command, "rc": rc, "head": head, "seq0": mark}
        if rc != 0:  # 가드 거부·시간 초과 = 적재 3값 판정 1줄(조용한 유실 0) · 사유는 out 칸(G7)
            row["landed"] = self.landed_after(mark, to, body)
            row["out"] = _tail(out)
            if slow:
                row["why"] = "상한 초과 · 적재 " + row["landed"]
        self._append(row)
        self.last_wake = row
        if head.startswith(ALERT_HEAD):   # 알림 깨움 = 이 command 의 좌석 깨움 상태를 바꾸지 않는다(성공해도 후보 유지)
            return rc
        if rc == 0 or row["landed"] == "있음":   # G1 — rc 0 이나 적재 «있음» = 좌석이 받았다 → 후보에서 뺀다
            self.candidates.pop(command, None)
        else:
            self._queue(command, to, head, mark)
        return rc

    def landed_after(self, mark, to, head):  # G6 — 적재 판정 = 앞 카드 E7 공용 함수(tail_rows·arrived) 그대로 부른다
        seen = self.ledger.tail_rows()
        if seen is None or mark is None:
            return "판정 불가"
        got = self.ledger.arrived(seen, mark, to, head, sender=SENDER)
        return "있음" if got == "있음" else ("없음" if got == "없음" else "판정 불가")

    def _attempts(self, command):  # G9 — 시도 수 = 장부의 그 command «보낸 깨움» 줄 수(늦은 적재 확인 줄은 세지 않는다)
        return len([r for r in self.entries("wake") if r.get("command") == command
                    and not str(r.get("head") or "").startswith(ALERT_HEAD) and r.get("why") != LATE_WHY])

    def _queue(self, command, to, head, mark):  # G1 — 알림이 아닌 깨움 실패만 후보 · G3 3회 찬 command 는 넣지 않는다
        if not command or head.startswith(ALERT_HEAD):
            return None
        attempts = self._attempts(command)
        if attempts >= RESEND_CAP:
            self.candidates.pop(command, None)
            return None
        cand = self.candidates.setdefault(command, {})   # 같은 dict 를 그 자리에서 고친다(_resend 가 들고 있다)
        cand.update({"to": to, "head": head, "seq0": mark, "at": self.now(), "attempts": attempts})
        return cand

    def _restore(self):  # G10 — 재기동 1회 장부 읽기 · G12 = 이 판이 쓴 줄(seq0 칸) ∧ 기동 600초 안일 때만 후보
        try:
            rows = self.entries("wake")
        except (OSError, ValueError):
            self.log("재전송 후보 판정 불가 · wire.jsonl") and None
            return {}
        last, count = {}, {}
        for row in rows:
            command = row.get("command")
            if not command or str(row.get("head") or "").startswith(ALERT_HEAD) or row.get("why") == LATE_WHY:
                continue
            last[command], count[command] = row, count.get(command, 0) + 1
        started, candidates, no_edge, outside = self.now(), {}, 0, 0
        for command, row in last.items():
            if row.get("rc") in (0, None) or _landed_row(row) or count[command] >= RESEND_CAP:
                continue   # G1·G3 — 지금 그대로
            at = _epoch(row.get("at"))
            age = started - at
            if "seq0" not in row:   # G12 (가) — 경계 칸이 없으면 G5 늦은 적재 확인을 못 한다(다시 보내지 않는다)
                no_edge += 1
                continue
            if not 0 <= age <= RESTORE_WINDOW:   # G12 (나) — 창 밖 · at 못 읽음(0)·기동 시각보다 뒤도 창 밖
                outside += 1
                continue
            candidates[command] = {"to": row.get("to"), "head": row.get("head"), "seq0": row.get("seq0"),
                                   "at": at, "attempts": count[command]}
        if no_edge or outside:   # 뺀 것이 1건 이상이면 listen.log 1줄(건별 줄 0 · wire 쓰기 0 · 깨움 0)
            self.log("[재전송] 복원 제외 %d건 · 경계 칸 없음 %d · 창 밖 %d" % (no_edge + outside, no_edge, outside))
        return candidates

    def resend_wakes(self):  # G2 — 유휴 회차 1통 · 후보 표가 비면 읽기·쓰기·깨움 0(부르는 쪽이 먼저 빈 표를 본다)
        for command in sorted(self.candidates):
            cand = self.candidates[command]
            if self.now() - float(cand.get("at") or 0) < RESEND_GAP:
                return None   # G2 — 같은 command 는 앞 시도에서 60초 뒤에만
            return self._resend(command, cand)
        return None

    def _resend(self, command, cand):  # G4 본문 = recovered 와 같은 길 · G5 늦은 적재 확인 · G3·G8 3회 뒤 멈춤
        rows = [r for r in self.router.entries(route.ROUTE)
                if r.get("command") == command and r.get("state") == route.DISPATCHED]
        if not rows:  # 다시 만들 본문이 없다 = 멈추고 1줄(조용한 반복 0)
            self.candidates.pop(command, None)
            self.log("[재전송] route dispatched 없음 · 멈춤 %s" % command)
            return {"command": command, "why": "재전송 불가 route 없음"}
        row, to, head = rows[-1], rows[-1]["to"], cand.get("head") or ""
        if self.landed_after(cand.get("seq0"), to, head) == "있음":  # G5 — 보내기 전 늦은 적재 확인
            self._append({"t": "wake", "to": to, "command": command, "rc": 0, "head": head,
                          "seq0": cand.get("seq0"), "landed": "있음", "why": LATE_WHY})
            self.candidates.pop(command, None)
            return {"command": command, "why": LATE_WHY}
        n = int(cand.get("attempts") or 1) + 1   # 끝줄 회차 = 처음 시도를 1로 센다(첫 재전송 = 2/3)
        rc = self.deliver(to, row["kind"], self.router.context(binding.thread_key(*row["key"])), row,
                          quiet=True, extra="재전송 %d/%d" % (n, RESEND_CAP), resend=True)
        last = dict(self.last_wake or {})
        if rc == 0 or last.get("landed") == "있음":   # G1 — 적재 «있음» 도 성공(잘린 send 가 늦게 붙은 경우)
            self.candidates.pop(command, None)
            return {"command": command, "why": "재전송 %d/%d" % (n, RESEND_CAP)}
        cand.update({"attempts": n, "at": self.now(), "seq0": last.get("seq0"), "to": to,
                     "head": last.get("head") or head})
        if n >= RESEND_CAP:  # G8 — 3회째도 실패 = 멈추고 harness _master [긴급] 1통
            self.candidates.pop(command, None)
            self.critical(command, to, last)
            return {"command": command, "why": "깨움 3회 실패"}
        return {"command": command, "why": "재전송 %d/%d 실패" % (n, RESEND_CAP)}

    def _harness_master(self):  # G8 — 명부 찾기 = 앞 카드 E8 함수(launch_roster.roster_path) 하나
        path = roster.roster_path(self.root, "harness")
        try:
            with open(path, encoding="utf-8") as handle:
                return json.load(handle).get("_master") or None
        except (OSError, ValueError, AttributeError, TypeError):
            return None

    def critical(self, command, to, last):  # G8 — command 마다 1회 · 이 1통이 실패하면 listen.log 1줄(재시도 0)
        """알림 줄(why 깨움 3회 실패)로 dedup · 이 통은 wake() 가 아니라 직접 부른다(wire 에 wake 줄을 더하지 않는다)."""
        if any(r.get("why") == "깨움 3회 실패" and r.get("command") == command for r in self.entries("alert")):
            return None
        seat = self._harness_master()
        if not seat:
            return self.log("[재전송] harness _master 없음 · 깨움 3회 실패 %s" % command)
        thread = str(command).split(":")[3] if len(str(command).split(":")) > 3 else "-"
        text = "[긴급] Slack 글 깨움 3회 실패 · thread %s · command %s · 받는 곳 %s · 마지막 rc %s %s" % (
            thread, command, to, last.get("rc"), last.get("out") or "")
        self._append({"t": "alert", "command": command, "why": "깨움 3회 실패", "to": seat,
                      "rc": last.get("rc"), "out": last.get("out") or ""})
        try:
            rc = subprocess.run(self.wake_argv + ["send", str(seat), SENDER, text], capture_output=True,
                                timeout=float(os.environ.get("FT2_SLACK_WAKE_TIMEOUT") or 25)).returncode
        except (OSError, subprocess.SubprocessError) as exc:
            return self.log("[재전송] [긴급] 실패 %s · %s" % (type(exc).__name__, command))
        return rc if rc == 0 else self.log("[재전송] [긴급] rc %s · %s" % (rc, command))

    def deliver(self, to, kind, lines, row=None, quiet=False, extra="", resend=False):  # route 가 dispatched 뒤에만(A7)
        """quiet = 다시 보낸 통(재전송 실패 때 «알림 깨움 실패» 0 · G11) · extra = 본문 끝 1줄(재전송 n/3).
        resend = G13 재전송 통 — issues 입구는 처음 deliver 가 wake 앞에서 이미 불렀다(두 번 쓰지 않는다)."""
        row = row or self.router.entries(route.ROUTE)[-1]
        command, thread = row.get("command"), row["key"][2]
        if kind == route.NEW and not resend:
            self.record_issue(command)
        owner = channels.owner_of(self.root, self.team, row["key"][1])  # r1923 ⑪ 다른 팀 채널 = 수신기 --root/--team 답글 줄
        tail = [] if owner in ("-", None) else ["답글: ft2 slack reply --root %s --team %s --thread %s --command %s --seat %s "
                                                 "--body-file <파일>" % tuple(map(shlex.quote, map(str, (self.root, self.team, thread, command, to))))]
        body = "\n".join(["[Slack] %s · thread %s · command %s" % (kind, thread, command)] + list(lines) + tail
                          + ([extra] if extra else []))
        rc = self.wake(to, body, command)
        if rc != 0 and not quiet:
            self.alert(dict(row, reason="깨움 실패"), quiet=True)
        return rc

    def woke(self, command):  # G9 — «넘긴 글» = 알림이 아닌 wake 줄 중 rc 0 이거나 적재 있음(실패 줄은 세지 않는다)
        return any(r.get("command") == command and not str(r.get("head") or "").startswith(ALERT_HEAD)
                   and (r.get("rc") == 0 or _landed_row(r)) for r in self.entries("wake"))

    def recovered(self, verdict):  # 보정1 R2 — 재기동 복구 dispatched 도 정상 길처럼 입구 기록·좌석 깨움 1회
        command, router = verdict.get("command"), self.router
        if verdict.get("state") != route.DISPATCHED or self.woke(command):  # G9 — 실패한 깨움은 넘긴 글로 세지 않는다
            self.candidates.pop(command, None)   # 넘긴 글 = 다시 보낼 후보 아님
            return None
        if command and self._attempts(command) >= RESEND_CAP:   # G3·G9 — 재기동해도 3회 셈을 잇는다(4회째 0)
            self.candidates.pop(command, None)
            self.log("[재전송] 3회 상한 · 재기동 깨움 0 %s" % command)
            return None
        rows = [r for r in router.entries(route.ROUTE) if r.get("command") == command and r.get("state") == route.DISPATCHED]
        if not rows:  # route 앞에서 죽은 글 — S-1 이 묶은 root 만 이어 받는다(답글은 thread 불명 = desk)
            key, src = binding.thread_key(*verdict["key"]), ([r for r in self.receive.entries()
                                                            if r.get("command") == command and r.get("state") == "received"] or [{}])[-1]
            if router.binding.get(key) is None:
                return self.alert(dict(verdict, reason="복구 thread 불명"), quiet=True)
            content = route.digest(src.get("text"))
            kind, to = router._plan(key, router.binding.get(key), route.QUESTION, content)[:2]
            rows = [router._record(key, kind, to, route.DISPATCHED, route.QUESTION, content, receipt=True, command=command)]
            router._append({"t": route.NOTE, "key": list(key), "line": "%s %s %s" % (
                key.root, src.get("user") or "", " ".join(str(src.get("text") or "").split()))})
            if to == route.DESK:
                return self.alert(rows[0])
        if rows[-1]["to"] != route.DESK:  # 닫힘(desk)은 settled 가 이미 알렸다
            self.deliver(rows[-1]["to"], rows[-1]["kind"], router.context(binding.thread_key(*rows[-1]["key"])), rows[-1])

    def record_issue(self, command):  # A3 — issues 입구에 같은 command 기록만(새 attempt 0 · issues 깨움 0)
        issues = receive.intake.Intake(self.root, "issues", clock=self.clock)
        if issues.lookup(command) is not None:
            return
        text = [r.get("text") for r in self.receive.entries() if r.get("command") == command and r.get("text")]
        got = issues.submit(command, (text or [""])[-1], {"slack": {"team": self.team}})
        self._append({"t": "issue", "command": command, "result": got.result, "attempt": got.attempt})
        if got.result != receive.RESULT_OK:
            self.alert({"command": command, "reason": "issues " + got.result}, quiet=True)

    def alert(self, row, quiet=False):  # A4 — desk 1곳 깨움 · 같은 command·사유 재알림 0
        command = row.get("command")
        why = row.get("reason") if quiet else (row.get("kind") or row.get("k") or row.get("reason") or row.get("state"))
        episode = why == receive.RESULT_FULL and full_alert._read(os.path.join(  # r1927 꽉 참 회차 = 열린 시각
            self.root, ".fable-team", "state", "ft2-full-alert.json"), "남은 일|%s@at" % self.team)
        if command and any(r.get("command") == command and r.get("why") == why and r.get("episode") == (episode or None)
                           for r in self.entries("alert")):  # R3 용량 부족 = 같은 회차만 dedup · 다른 사유 옛 dedup
            return
        again = episode and any(r.get("episode") == episode for r in self.entries("alert"))
        self._append(dict({"t": "alert", "command": command, "why": why}, **({"episode": episode} if episode else {})))
        if again:  # 같은 꽉 참 회차 = desk 깨움 1회만
            return
        desk, key = self.seat("_desk"), row.get("key") or [None] * 3
        if not desk:
            return self.log("[notify] desk 없음 " + json.dumps(row, ensure_ascii=False))
        self.wake(desk, "[Slack] 알림 %s · thread %s · command %s" % (why, key[2], command), command)


def wire(root, *, receive, bindings, notify=None, log=None, team="planner", clock=None, wake=None, now=None):
    """S-1 route 생성 1곳 대체 — (route, notify). notify 를 주입받았으면 그대로 쓴다(시험·대역)."""
    hub = Wiring(root, team=team, log=log, clock=clock, wake=wake, now=now)
    alert = notify or hub.alert
    receive.resend = hub.resend_wakes   # G2 — 유휴 회차(pass_idle)가 부르는 1줄 훅
    hub.receive, receive.notify, submit = receive, alert, receive.client.submit
    receive.client.submit = lambda command, *a, **kw: (lambda got: (full_alert.remaining(  # r1886 ⓐ 접수 결과마다
        root, receive.client.team, got.result, command), got)[1])(submit(command, *a, **kw))
    hub.router = route.SlackRoute(root, receive=receive, bindings=bindings, notify=alert, deliver=hub.deliver,
                                  team=team, clock=clock)
    hub.router.recovered = hub.recovered  # 보정1 R2 — S-1 복구 갈래가 부른다
    return hub.router, alert


def _received(root, team):  # 수신기가 받아들인 글 키(거른 글 = ignored 제외) = 수신 채널 증거(보정1 R1)
    path = os.path.join(os.path.abspath(root), ".fable-team", "teams", team, "slack", "receive.jsonl")
    with open(path, encoding="utf-8") if os.path.exists(path) else open(os.devnull) as handle:
        return {tuple(r["key"]) for r in map(json.loads, filter(str.strip, handle))
                if r.get("key") and r.get("state") != receive.IGNORED}


def _env_path(root, team):  # r1818 E5 — 수신기가 남긴 env 경로 · 파일 없음 = None(다음 단계) · 못 읽음 = ""
    try:
        with open(os.path.join(os.path.abspath(root), ".fable-team", "teams", team, "slack", "ENV_PATH"),
                  encoding="utf-8") as handle:
            return handle.read().strip()
    except FileNotFoundError:
        return None
    except (OSError, ValueError):
        return ""


def _token(path, fallback=True):
    try:
        with open(path, encoding="utf-8") as handle:
            pairs = [ln.strip().split("=", 1) for ln in handle if "=" in ln and not ln.lstrip().startswith("#")]
    except (OSError, TypeError, ValueError):  # 경로 없음 = 환경변수 · ENV_PATH 대상(fallback=False) = False(판독 불가)
        return os.environ.get("SLACK_BOT_TOKEN") if fallback else False
    return {k.replace("export ", "", 1).strip(): v.strip().strip("'\"") for k, v in pairs}.get("SLACK_BOT_TOKEN")


def slack_post(token):  # chat.postMessage · 7초 · 재시도는 publish MAX_POSTS 몫(여기 0) · 응답 유실 = ResponseLost
    spec = importlib.util.spec_from_file_location("ft2_wire_socket", os.path.join(_HERE, "socket.py"))
    spec.loader.exec_module(socket := importlib.util.module_from_spec(spec))  # 늦게 읽음 = 순환 import 0
    def post(channel, thread_ts, text, metadata):  # metadata = JSON 문자열(form 의 dict repr 0 · r1818 E1)
        try:
            form = dict(channel=channel, text=text, metadata=json.dumps(metadata, ensure_ascii=False))
            return socket.web_api("chat.postMessage", token, dict(form, **({"thread_ts": thread_ts} if thread_ts
                                  else {})), retry=False)["ts"]  # r1852 빈 thread_ts = 새 root
        except socket.publish.RateLimited as exc:
            raise publish.RateLimited(exc.retry_after)
        except OSError as exc:
            raise publish.ResponseLost(type(exc).__name__)
    return post


def _rows(pattern, word=""):  # r1856 그 파일들의 JSON 행(word 든 줄만 · 깨진 줄 건너뜀) · 읽기만
    for path in sorted(glob.glob(pattern)):
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in (ln for ln in handle if word in ln):
                try:
                    yield dict(json.loads(line))
                except (ValueError, TypeError):
                    continue


def _human_ts(command):  # 의도 키 slack:<ws>:<채널>:<사람 글 ts>:<꼬리> 의 4번째 칸 · 아니면 None
    parts = str(command or "").split(":")
    return parts[3] if len(parts) > 3 and parts[0] == "slack" and parts[3] else None


def _seq(opts):  # r1856 요청 번호 = (숫자|None, 숫자 0 사유) · --seq = 숫자만 ∧ BYZ 우편함 기록에 있음
    base, ts = os.path.join(glob.escape(opts["root"]), ".fable-team"), _human_ts(opts.get("command"))
    if "seq" in opts:
        want = opts["seq"] if re.fullmatch(r"[0-9]+", opts["seq"]) else ""
        ok = want and any(r.get("seq") == int(want) for r in _rows(base + "/comm/mailbox.log.jsonl*", want))
        return (want, "") if ok else (None, "--seq %r 우편함 기록 없음" % opts["seq"])
    found = [m[1] for r in _rows(base + "/teams/%s/slack/publish.jsonl" % glob.escape(opts["team"]))  # 같은 사람 글 ts 만
             if ts and _human_ts(r.get("command")) == ts for m in [re.search(r"\n보낸이 \S+ ([0-9]+)\Z", str(r.get("body")))] if m]
    return (found[-1], "") if found else (None, "같은 사람 글 ts 의 장부 번호 없음")


def _desk(root, team):  # r1862 명부 seats-<team>.json `_desk` 읽기만 · 못 읽음·칸 없음 = None(대신 답 0)
    try:
        with open(os.path.join(root, ".fable-team", "seats-%s.json" % team), encoding="utf-8") as handle:
            return json.load(handle).get("_desk") or None
    except (OSError, ValueError, AttributeError):
        return None


def _bind(opts, ledger, key, ask):  # r1879 bind 성공 뒤에만 요청 등록 1회(id = post 의도 키) · 실패 = stderr 1줄 · 게시 결과 그대로
    try:  # R2 저장 예외도 거절과 같은 줄(게시 결과·rc 그대로)
        got = ledger.bind(key, opts["seat"])
    except Exception as exc:
        got = {"state": "error", "k": type(exc).__name__, "has": ""}
    if got["state"] != binding.BOUND:  # 이미 있음 = 덮어쓰기 0 · 등록 0
        return sys.stderr.write("binding 실패 · 판정 불가 — %s %s\n" % (got.get("k"), got.get("has"))) and ""
    try:  # 정상 SlackReceive 를 넘긴다(receive=None = 생성자 AttributeError · DA 296903) · ack 호출 0 · 실 Slack 0
        route.SlackRoute(opts["root"], receive=receive.SlackReceive(opts["root"], ack=lambda e: None, team=opts["team"]),
                         bindings=ledger, team=opts["team"]).register(key, ask)
    except Exception as exc:  # binding 은 그대로(답글은 이미 나감 · 하드 룰 20)
        return sys.stderr.write("요청 등록 실패 · 판정 불가 — %s\n" % type(exc).__name__) and ""
    return " bound=%s req=%s" % (got["owner"], ask)


def say(state, ts="", rc=0, reason="", tail=""):
    sys.stdout.write(("state=%s ts=%s" % (state, ts or "")) + (" reason=%s" % reason if reason else "") + tail + "\n")
    return rc


def main(argv, post=None, sleep=None):
    """`reply|notify --root R --team T --thread TS --seat S --body-file F [--command C] [--env E]` → 출력 1줄."""
    verb = (argv or [""])[0]  # r1852 `post --channel C` = 수신 채널 새 root(thread 없음)
    bind = verb == "post" and "--bind" in argv  # r1879 값 없는 선택 인자 · 없으면 r1852 그대로(자동 bind 0)
    argv = [a for a in argv if not (bind and a == "--bind")]
    need = {"reply": ("thread", "command"), "notify": ("thread",), "post": ("channel",)}.get(verb)
    opts = {k[2:]: v for k, v in zip(argv[1::2], argv[2::2]) if k.startswith("--")}
    known = {"root", "team", "seat", "body-file", "env", "seq"} | set(need or ())
    if need is None or len(argv) % 2 == 0 or len(opts) * 2 != len(argv) - 1 or set(opts) - known \
            or known - {"env", "seq"} - set(opts) or opts.get("command", "").startswith("receipt:"):
        return say("usage", rc=USAGE, reason="reply|notify --root --team --thread --seat --body-file [--command]")
    try:
        body = open(opts["body-file"], encoding="utf-8").read()
    except OSError:
        return say("usage", rc=USAGE, reason="body-file 판독 불가")
    if has_table(body):  # r1927 사람 채널 마크다운 표 = 게시 0 · 의도·binding·장부 쓰기 전
        return say("refused", rc=USAGE, reason="마크다운 표")
    if sender_tag.sender_tag(opts["seat"]):  # r1850 — 장부 기록 앞 = 재송·되살림도 같은 바이트
        seq, why = _seq(opts)  # r1856 — 못 찾음 = 숫자 0 · 게시는 그대로 · stderr 1줄
        body = "%s\n\n%s" % (body, sender_tag.sender_tag(opts["seat"], seq))
        sys.stderr.write("" if seq else "요청 번호 0 — %s\n" % why)
    else:  # lint 실패 = 표시 0 · 게시는 그대로
        sys.stderr.write("보낸이 표시 0 — 좌석 이름 lint 실패: %s\n" % opts["seat"])
    ledger = binding.ThreadBinding(opts["root"], opts["team"])
    heard = {k[1]: k[0] for k in _received(opts["root"], opts["team"])}.get(opts.get("channel"))
    if verb == "post" and heard is None:  # 수신 증거 없는 채널 = 게시 0(notify 와 같은 근거)
        return say("refused", rc=USAGE, reason="수신 증거 없는 채널")
    owner = channels.owner_of(opts["root"], opts["team"], opts["channel"]) if verb == "post" else "-"  # r1923 ⑩ 주인 검사
    seat = owner not in ("-", None) and channels.resolve(owner)
    if owner is None or seat is None:
        return say("판정불가", rc=UNDECIDED, reason="CHANNELS·채널 주인 명부 판독 불가")
    if seat and seat != opts["seat"]:
        return say("refused", rc=USAGE, reason="채널 주인 아님")
    rows = [r for r in ledger.settled().values() if r["key"][2] == opts.get("thread")]
    if verb == "notify":  # 수신 채널 thread 만 — 허용 밖 채널 binding = 게시 0(보정1 R1)
        rows = [r for r in rows if tuple(r["key"]) in _received(opts["root"], opts["team"])]
    now = rows and ledger.get(binding.thread_key(*rows[-1]["key"]))
    if verb != "post" and (not now or not now.open):  # binding 없음·닫힘 = 게시 0(새 root 를 만드는 길 0)
        return say("refused", rc=USAGE, reason="binding 없음" if not now else "닫힘")
    if post is None:
        path = opts.get("env") or os.environ.get("FT2_SLACK_ENV")  # --env → FT2_SLACK_ENV → ENV_PATH → 셸 env
        saved = None if path else _env_path(opts["root"], opts["team"])
        token = _token(path) if saved is None else _token(saved, fallback=False)
        if token is False:  # ENV_PATH 가 가리킨 파일 판독 실패 = 다음 단계로 넘기지 않는다
            return say("판정불가", rc=UNDECIDED, reason="ENV_PATH %s 판독 불가" % (saved or '""'))
        if not token:
            return say("판정불가", rc=UNDECIDED, reason="SLACK_BOT_TOKEN 없음")
        post = slack_post(token)
    key = binding.thread_key(heard, opts["channel"], "") if verb == "post" else binding.thread_key(
        now.workspace, now.channel, now.root)
    pub = publish.SlackPublish(opts["root"], team=opts["team"], bindings=ledger,
                               post=lambda root_ts, text, marker, metadata: post(key.channel, root_ts, text, metadata),
                               sleep=sleep or (lambda s: time.sleep(min(float(s), 7))),
                               delegate=lambda: _desk(opts["root"], opts["team"]))  # R1 게시 직전마다 다시 읽음
    if verb == "reply":  # 역할 답 의도 키 = 업무 command 그대로 · gen = binding 에서
        intent, seat, gen = opts["command"], opts["seat"], now.gen
    else:  # notify — 의도 키 = notify:<root>:<본문 sha12> · 담당 검사 대신 열린 binding 만
        intent, seat, gen = "notify:%s:%s" % (key.root, hashlib.sha256(body.encode()).hexdigest()[:12]), None, None
    ask = "post:%s:%s:%s" % (key.channel, opts["seat"], hashlib.sha256(body.encode()).hexdigest()[:12])
    try:
        row = pub.post_root(key, ask, body) if verb == "post" else pub.reply(key, intent, body, seat, gen)
    except Exception as exc:  # 429 두 번(post_failed)·Slack 오류 응답 = 보이는 실패 1줄(하드 룰 20)
        return say("failed", rc=1, reason=(getattr(exc, "row", None) or {}).get("k") or type(exc).__name__)
    if row["state"] == publish.REFUSED:
        if row.get("k") == "same_intent_unsettled":  # 같은 의도 결과 불명 = 보류(재송 0)
            return say(publish.UNCERTAIN, rc=1, reason=row.get("k"))
        same = row.get("k") == "same_intent"
        return say("duplicate" if same else "refused", row.get("ts"), 0 if same else USAGE, "" if same else row.get("k"))
    tail = _bind(opts, ledger, binding.thread_key(key.workspace, key.channel, row.get("ts")), ask) if bind and (
        row["state"] == publish.POSTED and row.get("ts")) else ""  # UNCERTAIN·ERROR = bind 0 · 등록 0
    return say(row["state"], row.get("ts"), 0 if row["state"] == publish.POSTED else 1, tail=tail)
