"""ft2 Slack 수신 경로 — 재개 필요 · thread 컨텍스트 · 인터뷰 답 (r1585 · PR③ 셋째 장).

계약 줄 9·10·14·17. `route(event)` 는 binding 을 먼저 읽어 목적지를 정하고 판정은 r1580 의 수신 어댑터(`handle`)에
넘긴다 — 거름·키·기록·확인·입구는 그쪽 몫이고 이 장은 «누구에게 무엇으로» 만 더한다. 닫힘·담당 없음 = kind «재개
필요» · @team-desk · 옛 owner 깨움 0 · 미처리는 다음 좌석이 본다(표식은 thread 가 아니라 그 글). 열린 thread = 그
좌석에 그 thread 변경분만(다른 thread 섞임 0 · 전체 재로드 0 · 목적지는 binding · 모델 분류기 0). **영수 없이 전달
하지 않는다(R1)** — 전달·컨텍스트·pending 은 dispatched 일 때만이고 중복·거름·유휴·full 은 도구 안에서 끝난다.
목적지·kind 는 client 주입점(`RoutingClient`)으로 입구 영수의 같은 command 에 남고 전달 직전 binding 을 다시 읽는다
(R2). 질문 글 root = 요청 번호(이미 있으면 상태 유지) · 같은 답 재전달 = duplicate · 닫힌 뒤 답 = «늦은 답 Q7»(R4).
"""

import importlib.util
import json
import os
import time

_HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location("ft2_slack_binding", os.path.join(_HERE, "binding.py"))
binding = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(binding)

DESK = "@team-desk"
NEW, ANSWER, LATE, REOPEN = "새 업무", "답 %s", "늦은 답 %s", "재개 필요"
QUESTION, ANSWERED = "question", "answer"
OPEN, CLOSED = "open", "closed"
DISPATCHED, DUPLICATE, IGNORED, IDLE = "dispatched", "duplicate", "ignored", "idle"
NOTE, REQ, ROUTE, SEEN = "note", "req", "route", "seen"

#: 이 장이 덮는 계약 줄 — 계약 낱말 그대로 적는다(시험이 사례 expect 낱말과 대조한다).
COVERS = {
    9: "thread 1 = 주제 1 = 논리 컨텍스트 1 · 파일 분리 ≠ 모델 입력 격리",
    10: "답 = 그 thread 1곳 · 요청 번호 = 팀 도구 번호 그대로",
    14: "닫히면 담당 없음 · 새 글 = 재개 필요 · 답 거절",
    17: "목적지는 binding·상태로(모델 분류기 0) · 좌석에는 그 thread 변경분과 필요 근거만 · 전체 대화 재로드 0",
}


def thread_key(event):
    """thread 키 = (workspace, channel, root) — thread_ts 가 있으면 그 root, 없으면 글 자체가 root."""
    return binding.thread_key(event.get("team") or event.get("workspace"), event.get("channel"),
                              event.get("thread_ts") or event.get("ts"))


def digest(text):
    """같은 답 재전달 판정용 지문 — 낱말을 그대로 담는다(해시 금지: 시험이 값을 그대로 읽는다)."""
    return " ".join(str(text or "").split())


class RoutingClient:
    """client 주입점 — 입구 영수(work)에 route 의 목적지·kind·thread 를 같은 command 로 남긴다."""
    def __init__(self, inner, describe):
        self.inner, self.describe = inner, describe

    def __getattr__(self, name):
        return getattr(self.inner, name)

    def submit(self, command, body, work=None):
        return self.inner.submit(command, body, dict(work or {}, route=dict(self.describe() or {})))


class SlackRoute:
    """thread 1건 = 판정 1개. 목적지는 `to` 하나, 판정은 `state` 한 낱말로만 말한다."""
    def __init__(self, root, *, receive, bindings=None, team="harness", clock=None, deliver=None,
                 notify=None, context_limit=4):
        self.receive, self.team, self.current = receive, team, None
        self.binding = bindings or binding.ThreadBinding(root, team, clock=clock)
        self.clock = clock or (lambda: time.strftime("%Y-%m-%dT%H:%M:%S"))
        self.deliver, self.notify = deliver or (lambda to, kind, lines: None), notify or (lambda row: None)
        self.context_limit = int(context_limit)
        inner = getattr(receive, "client", None)
        self.relay = RoutingClient(inner, self.describe) if inner is not None else None
        receive.client = self.relay or inner  # 영수와 route 장부를 같은 command 로 잇는다(R2)
        data = os.path.join(os.path.abspath(str(root)), ".fable-team", "teams", team, "slack")
        os.makedirs(data, exist_ok=True)
        self.path = os.path.join(data, "route.jsonl")

    def entries(self, kind=None):
        if not os.path.exists(self.path):
            return []
        with open(self.path, encoding="utf-8") as handle:
            rows = [json.loads(line) for line in handle if line.strip()]
        return [row for row in rows if kind is None or row.get("t") == kind]

    def _append(self, row):
        with open(self.path, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(dict(row, schema=1, at=self.clock()), ensure_ascii=False, sort_keys=True) + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        fd = os.open(os.path.dirname(self.path), os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
        return row

    def requests(self):
        return {tuple(row["key"]): {"id": row["id"], "state": row["state"]} for row in self.entries(REQ)}

    def request(self, key):
        return self.requests().get(tuple(key))

    def register(self, key, request_id):  # 질문 글 root → 요청 번호. 이미 있으면 상태 유지(닫힘 보존 · R4)
        now = self.request(key)
        if now is not None:
            return {"t": REQ, "key": list(key), "id": now["id"], "state": now["state"]}
        return self._append({"t": REQ, "key": list(key), "id": str(request_id), "state": OPEN})

    def close(self, key):
        """질문 닫힘 — 뒤에 오는 답은 «늦은 답» 이 된다. 등록 없는 thread 는 닫지 않는다."""
        now = self.request(key)
        return None if now is None else self._append(
            {"t": REQ, "key": list(key), "id": now["id"], "state": CLOSED})

    def answers(self, request_id):  # 이미 넘긴 답 지문 — 같은 답 재전달 = duplicate(사례 f4 · R1)
        return {row.get("digest") for row in self.entries(ROUTE)
                if row.get("which") == ANSWERED and row.get("id") == request_id}

    def describe(self):
        """제출 시점의 현재 binding 으로 목적지를 다시 말한다 — ack 안에서 닫혀도 반영된다(R2)."""
        if not self.current:
            return {}
        key, event = self.current
        which = ANSWERED if str(event.get("thread_ts") or "") else QUESTION
        kind, to = self._plan(key, self.binding.get(key), which, event)[:2]
        return {"thread": key.root, "workspace": key.workspace, "channel": key.channel, "to": to,
                "kind": kind, "id": (self.request(key) or {}).get("id")}

    def note(self, key, line):
        return self._append({"t": NOTE, "key": list(key), "line": str(line)})

    def context(self, key):
        """그 thread 의 최근 변경분 줄만 — 다른 thread 줄은 섞이지 않는다(변이 M2)."""
        lines = [row["line"] for row in self.entries(NOTE) if tuple(row["key"]) == tuple(key)]
        return lines[-self.context_limit:]

    def route(self, event):
        """사건 1건 → 판정 1개. 목적지는 binding 이, kind 는 상태가 정한다(모델 분류기 0)."""
        if not event:  # 무변화 pass = 도구 안에서 끝난다 — 모델 호출·좌석 깨움·기록 증가 0(줄 16)
            return {"t": ROUTE, "kind": None, "to": None, "state": IDLE}
        key = thread_key(event)
        which = ANSWERED if str(event.get("thread_ts") or "") else QUESTION
        kind, to, repeated = self._plan(key, self.binding.get(key), which, event)
        if repeated:  # 이미 넘긴 답 = 접수 0 · 좌석 전달 0 · Slack 확인만(줄 16 · R1)
            self.receive.ack(event)
            return self._record(key, kind, to, DUPLICATE, which, event)
        self.current = (key, event)
        try:
            verdict = self.receive.handle(event)  # 거름·키·기록·확인·입구 — r1580 몫
        finally:
            self.current = None
        state = verdict.get("state")
        if state == DISPATCHED and which == QUESTION and event.get("request_id"):
            self.register(key, event["request_id"])  # 거른 사건은 요청을 만들지 않는다(R4)
        kind, to, _repeated = self._plan(key, self.binding.get(key), which, event)  # 전달 직전 재확인(R2)
        row = self._record(key, kind, to, state, which, event, verdict)
        if state != DISPATCHED:  # 중복·거름·유휴·영수 없음 = 좌석 깨움 0(줄 16 · R1)
            return row
        self.note(key, self._line(event))
        if to == DESK:  # 닫힘 = 옛 owner 깨움 0 · 미처리 1건은 다음 좌석이 본다(줄 14)
            self.notify(row)
        else:  # 열린 thread = 그 좌석에 그 thread 변경분만 넘긴다(전체 재로드 0)
            self.deliver(to, kind, self.context(key))
        return row

    def _plan(self, key, now, which, event):
        """kind·목적지·중복 판정. 닫힘/담당 없음이 먼저다(변이 M1 이 잡히는 자리)."""
        if now is None or not now.open:
            return REOPEN, DESK, False
        asked = self.request(key)
        if which == ANSWERED and asked is not None:
            if asked["state"] == CLOSED:
                return LATE % asked["id"], DESK, False  # 버리지 않고 표시해 넘긴다(사례 f4 · R4)
            return ANSWER % asked["id"], now.seat, digest(event.get("text")) in self.answers(asked["id"])
        return NEW, now.seat, False

    def _line(self, event):  # 컨텍스트 1줄 = 그 thread 변경분 1건(누가·무엇)
        return "%s %s %s" % (str(event.get("ts") or ""), str(event.get("user") or ""),
                             " ".join(str(event.get("text") or "").split()))

    def _record(self, key, kind, to, state, which, event, verdict=None):
        now = self.binding.get(key)
        return self._append({
            "t": ROUTE, "key": list(key), "kind": kind, "to": to, "state": state, "which": which,
            "id": (self.request(key) or {}).get("id"), "digest": digest(event.get("text")),
            "seat": None if now is None else now.seat, "gen": None if now is None else now.gen,
            "open": bool(now and now.open), "command": None if verdict is None else verdict.get("command"),
            "why": None if verdict is None else verdict.get("reason")})

    def pending(self, seat):
        """닫힌 thread 로 온 글 중 아무도 안 본 것 — 표식은 그 글(command)만 소비한다."""
        seen = {row.get("command") for row in self.entries(SEEN)}
        rows = [row for row in self.entries(ROUTE) if row.get("kind") == REOPEN
                and row.get("state") == DISPATCHED and row.get("command") not in seen]
        for row in rows:
            self._append({"t": SEEN, "key": row["key"], "command": row["command"], "by": str(seat)})
        return rows

    def seen_by_next(self):
        """다음 좌석이 실제로 본 미처리 수(사례 c6 = 1)."""
        return len(self.entries(SEEN))
