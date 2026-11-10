"""ft2 Slack 수신 경로 — 재개 필요 · thread 컨텍스트 · 인터뷰 답 (r1585 · PR③ 셋째 장).

계약 줄 9·10·14·17. `route(event)` 는 binding 을 먼저 읽어 목적지를 정하고, 판정은 r1580 의 수신 어댑터
(`handle`)에 그대로 넘긴다 — 거름·키·기록·확인·입구는 그쪽 몫이고 이 장은 «누구에게 무엇으로» 만 더한다.
닫힌 thread·담당 없는 thread 의 새 사람 글 = kind «재개 필요» · 목적지 @team-desk · 옛 owner 깨움 0 ·
미처리 1건은 pending 으로 남아 다음 좌석이 본다. 열린 thread = 그 좌석에 그 thread 변경분만 넘긴다
(다른 thread 줄 섞임 0 · 전체 대화 재로드 0 · 목적지는 binding 이 정한다 · 모델 분류기 0). 인터뷰 질문 글의
root 는 요청 번호를 등록하고, 그 thread 의 답 = kind «답 Q7» · 같은 답 재전달 = duplicate · 질문이 닫힌 뒤의
답은 버리지 않고 «늦은 답 Q7» 로 표시해 넘긴다(계약 줄 10). 기록은 append-only jsonl · 쓰기마다 fsync.
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
NEW, ANSWER, LATE, REOPEN = "새 업무", "답 Q7", "늦은 답 Q7", "재개 필요"
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


class SlackRoute:
    """thread 1건 = 판정 1개. 목적지는 `to` 하나, 판정은 `state` 한 낱말로만 말한다."""
    def __init__(self, root, *, receive, bindings=None, team="harness", clock=None, deliver=None,
                 notify=None, context_limit=4, on_step=None):
        self.receive, self.team = receive, team
        self.on_step = on_step or (lambda name: None)
        self.binding = bindings or binding.ThreadBinding(root, team, clock=clock)
        self.clock = clock or (lambda: time.strftime("%Y-%m-%dT%H:%M:%S"))
        self.deliver, self.notify = deliver or (lambda to, kind, lines: None), notify or (lambda row: None)
        self.context_limit, self.steps = int(context_limit), []
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

    def _step(self, name):
        self.steps.append(name)
        self.on_step(name)

    # ── 인터뷰: 질문 글 root = 요청 번호(계약 줄 10) ──────────────────────────────
    def requests(self):
        return {tuple(row["key"]): {"id": row["id"], "state": row["state"]} for row in self.entries(REQ)}

    def request(self, key):
        return self.requests().get(tuple(key))

    def register(self, key, request_id):
        """질문 글 root → 요청 번호. 재기동 뒤에도 상태는 기록이 들고 있다(사례 f4)."""
        return self._append({"t": REQ, "key": list(key), "id": str(request_id), "state": OPEN})

    def close(self, key):
        """질문 닫힘 — 뒤에 오는 답은 «늦은 답» 이 된다. 등록 없는 thread 는 닫지 않는다."""
        now = self.request(key)
        if now is None:
            return None
        return self._append({"t": REQ, "key": list(key), "id": now["id"], "state": CLOSED})

    def answers(self, request_id):
        """그 요청 번호로 이미 넘긴 답 지문 — 같은 답 재전달 = duplicate(사례 f4)."""
        return {row.get("digest") for row in self.entries(ROUTE)
                if row.get("which") == ANSWERED and row.get("id") == request_id}

    # ── thread 컨텍스트: 그 thread 변경분만(계약 줄 9·17) ───────────────────────
    def note(self, key, line):
        return self._append({"t": NOTE, "key": list(key), "line": str(line)})

    def context(self, key):
        """그 thread 의 최근 변경분 줄만 — 다른 thread 줄은 섞이지 않는다(변이 M2)."""
        lines = [row["line"] for row in self.entries(NOTE) if tuple(row["key"]) == tuple(key)]
        return lines[-self.context_limit:]

    # ── 라우팅 ────────────────────────────────────────────────────────────
    def route(self, event):
        """사건 1건 → 판정 1개. 목적지는 binding 이, kind 는 상태가 정한다(모델 분류기 0)."""
        self.steps = []
        if not event:  # 무변화 pass = 도구 안에서 끝난다 — 모델 호출·좌석 깨움·기록 증가 0(줄 16)
            self._step("idle")
            return {"t": ROUTE, "kind": None, "to": None, "state": IDLE}
        key, which = thread_key(event), self._which(event)
        if which == QUESTION and event.get("request_id"):
            self.register(key, event["request_id"])
            self._step("request")
        now = self.binding.get(key)
        kind, to, repeated = self._plan(key, now, which, event)
        verdict = self.receive.handle(event)  # 거름·키·기록·확인·입구 — r1580 몫
        self._step("receive")
        state = verdict.get("state")
        if repeated and state not in (DUPLICATE, IGNORED, IDLE):
            state = DUPLICATE
        now = self.binding.get(key)  # 사건을 처리하는 동안 닫혔을 수 있다 — 판정은 지금 값으로
        row = self._append({"t": ROUTE, "key": list(key), "kind": kind, "to": to, "state": state, "which": which,
                            "id": (self.request(key) or {}).get("id"), "digest": digest(event.get("text")),
                            "seat": None if now is None else now.seat, "gen": None if now is None else now.gen,
                            "open": bool(now and now.open), "command": verdict.get("command"),
                            "why": verdict.get("reason")})
        if state in (IGNORED, IDLE):  # 미인가·bot·무변화 = 컨텍스트·전달·pending 0(줄 15·16)
            return row
        self.note(key, self._line(event))
        if to == DESK:  # 닫힘 = 옛 owner 깨움 0 · 미처리 1건은 다음 좌석이 본다(줄 14)
            self.notify(row)
            self._step("notify")
        else:  # 열린 thread = 그 좌석에 그 thread 변경분만 넘긴다(전체 재로드 0)
            self.deliver(to, kind, self.context(key))
            self._step("deliver")
        return row

    def _which(self, event):
        """답 = 이미 있는 thread 안의 글. 새 root 글 = 질문·새 업무(계약 줄 9·10)."""
        return ANSWERED if str(event.get("thread_ts") or "") else QUESTION

    def _plan(self, key, now, which, event):
        """kind·목적지·중복 판정. 닫힘/담당 없음이 먼저다(변이 M1 이 잡히는 자리)."""
        if now is None or not now.open:
            return REOPEN, DESK, False
        asked = self.request(key)
        if which == ANSWERED and asked is not None:
            if asked["state"] == CLOSED:
                return LATE, DESK, False  # 버리지 않고 표시해 넘긴다(사례 f4)
            return ANSWER, now.seat, digest(event.get("text")) in self.answers(asked["id"])
        return NEW, now.seat, False

    def _line(self, event):
        """컨텍스트 1줄 = 그 thread 변경분 1건(누가·무엇). 좌석에는 이 줄들만 간다."""
        return "%s %s %s" % (str(event.get("ts") or ""), str(event.get("user") or ""),
                             " ".join(str(event.get("text") or "").split()))

    # ── 미처리: 다음 좌석이 본다(사례 c6 pending_seen_by_next) ────────────────
    def pending(self, seat):
        """닫힌 thread 로 온 글 중 아무도 안 본 것 — 읽는 순간 «봤다» 를 남긴다."""
        seen = {tuple(row["key"]) for row in self.entries(SEEN)}
        rows = [row for row in self.entries(ROUTE)
                if row.get("kind") == REOPEN and row.get("state") == DISPATCHED and tuple(row["key"]) not in seen]
        for row in rows:
            self._append({"t": SEEN, "key": row["key"], "by": str(seat)})
        return rows

    def seen_by_next(self):
        """다음 좌석이 실제로 본 미처리 수(사례 c6 = 1)."""
        return len(self.entries(SEEN))
