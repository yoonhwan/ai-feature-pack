"""ft2 Slack 답 발행 — 계약 줄 10·11·12·13·14 (r1582 · PR③ 둘째 장).

답은 binding 이 가리키는 thread 1곳에만 나가고 본문은 사람 글만 · metadata.command = 팀 도구 command 그대로다(줄 10 · r1818). 게시 «의도»
(표식 · root · command · owner 세대 · 본문)와 시도 1회를 post 앞에 내구화한다 — crash 뒤 재기동은 표식 조회가
먼저이고 429 예산은 장부 누적에서 복원된다(R2). 응답 유실 = UNCERTAIN · 자동 재송 0(줄 11). 표식 조회는 3값 —
«있음» = posted(게시 1) · «없음 확인» = 같은 표식으로 재송 · «판정 불가» = 보존 + 사람 알림 1. 429 = Retry-After
만큼 기다린 뒤 재시도 1 · 넘으면 보이는 오류 `post_failed`(줄 13). 옛 세대·닫힘 답은 첫 진입뿐 아니라 재송과 429
뒤 재시도 직전에도 재검사해 게시 0(줄 12·14 · R1). 거절 행은 유효한 답을 가리지 않는다(R3). 전송은 대역 주입.
"""

import importlib.util
import json
import os
import time

_HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location("ft2_slack_binding", os.path.join(_HERE, "binding.py"))
binding = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(binding)
_SPEC_D = importlib.util.spec_from_file_location("ft2_slack_reply_done", os.path.join(_HERE, "reply_done.py"))
_SPEC_D.loader.exec_module(reply_done := importlib.util.module_from_spec(_SPEC_D))  # r1872 답글 = 앞 글 완료

owner_label = binding.owner_label
POSTED, RESENT, UNCERTAIN, ERROR, REFUSED, IDLE = "posted", "resent", "uncertain", "error", "refused", "idle"
INTENT, ATTEMPT = "intent", "attempt"
UNSETTLED = (INTENT, ATTEMPT, UNCERTAIN)
FOUND, ABSENT, UNDECIDABLE = "found", "absent", "undecidable"

#: 이 장이 덮는 계약 줄 — 계약 낱말 그대로 적는다(시험이 사례 expect 낱말과 대조한다).
COVERS = {
    10: "답 = 그 thread 1곳 · 요청 번호 = 팀 도구 번호 그대로",
    11: "답 응답 불명 = UNCERTAIN · 표식 조회 3값(있음·없음 확인·판정 불가) · 판정 불가는 보존·사람 · 자동 재송 0",
    12: "담당 승계 사슬 · 옛 세대 답 거절",
    13: "429 = Retry-After · 재시도 1 · 넘으면 보이는 오류",
    14: "임시 채널은 사람이 만듦 · 닫히면 담당 없음 · 새 글 = 재개 필요 · 답 거절",
}


class RateLimited(Exception):
    """Slack 429 — `retry_after` 초만큼 기다린 뒤 재시도 1회(줄 13)."""
    def __init__(self, retry_after=0.0):
        super().__init__("429 Retry-After %s" % retry_after)
        self.retry_after = float(retry_after)


class ResponseLost(Exception):
    """post 응답 유실 — 결과 불명. 부르는 쪽이 자동 재송하지 않는다(줄 11)."""


class PostFailed(Exception):
    """재시도 예산 소진 = 보이는 오류. `row` 는 기록에 남은 그 행이다."""
    def __init__(self, row):
        super().__init__("post_failed %s" % row.get("root"))
        self.row = row


def marker_for(key, command):
    """답 표식 — 조회와 재송이 같은 값으로 판정하게 한다(receive.py 재송 표식과 다른 낱말)."""
    return "[[slack-reply %s %s/%s/%s]]" % (command, key.workspace, key.channel, key.root)


class SlackPublish:
    """팀 runtime 1곳의 답 발행. 판정은 `state` 한 낱말로만 말한다."""
    MAX_POSTS = 2  # 누적 예산 = 첫 시도 + 재시도 1 — 재기동이 장부에서 복원한다(하드 룰 12)

    def __init__(self, root, *, post, lookup=None, sleep=None, notify=None, team="harness",
                 bindings=None, clock=None, on_step=None, delegate=None):
        self.root, self.team, self.settled = root, team, None  # r1872 _settle 이 쓴다
        self.post, self.notify, self.delegate = post, notify or (lambda row: None), delegate  # r1862 명부 _desk
        self.lookup, self.sleep = lookup or (lambda marker: UNDECIDABLE), sleep or (lambda seconds: None)
        self.clock = clock or (lambda: time.strftime("%Y-%m-%dT%H:%M:%S"))
        self.binding, self.on_step, self.steps = (
            bindings or binding.ThreadBinding(root, team, clock=self.clock), on_step or (lambda step: None), [])
        self.path = os.path.join(os.path.abspath(str(root)), ".fable-team", "teams", team, "slack", "publish.jsonl")
        os.makedirs(os.path.dirname(self.path), exist_ok=True)

    def entries(self):
        if not os.path.exists(self.path):
            return []
        with open(self.path, encoding="utf-8") as handle:
            return [json.loads(line) for line in handle if line.strip()]

    def latest(self):
        """thread 별 마지막 «답» 기록 — 거절 행이 다른 유효한 답을 가리지 않는다(R3)."""
        return {tuple(entry["key"]): entry for entry in self.entries()
                if entry.get("key") and entry["state"] != REFUSED}

    def reply(self, key, command, body, seat=None, gen=None):
        """답 1건. 거절이면 게시 0, 아니면 «의도 기록 → post → 결과 기록»(ⓖ)."""
        self.steps = []
        repeated = self._repeated(key, command)  # 계약 3 — 같은 intent 재회신 = 게시 0(r1623)
        if repeated is not None:
            return self._append(repeated)
        refusal = self._refusal(key, command, seat, gen)
        if refusal is not None:
            return self._append(refusal)
        owner = owner_label(seat, gen) if seat is not None else None
        self._append({"state": INTENT, "root": key.root, "key": list(key), "command": command, "owner": owner,
                      "gen": gen, "marker": marker_for(key, command), "body": body, "post_calls": 0})
        self._step("after_intent")
        return self._post(key, command, body, seat, gen, owner, via=POSTED)

    def post_root(self, key, intent, body):
        """r1852 채널 새 root 1건 — key root = "" · 채널 허용은 부르는 쪽 · binding 검사 건너뜀 · binding 자동 열기 0."""
        self.steps = []
        repeated = self._repeated(key, intent)  # 같은 의도 = duplicate·미해소 보류(게시 0)
        if repeated is not None:
            return self._append(repeated)
        self._append({"state": INTENT, "root": key.root, "key": list(key), "command": intent, "owner": None,
                      "gen": None, "marker": marker_for(key, intent), "body": body, "post_calls": 0})
        self._gate = lambda *args: None  # 이 인스턴스만 · INTENT→ATTEMPT→POSTED|UNCERTAIN 은 _post 그대로
        return self._post(key, intent, body, None, None, None, via=POSTED)

    def resolve(self, key):
        """재기동·유실 뒤 판정 — 표식 조회 먼저 · 새 게시 0. 반환 = 판정 1개."""
        self.steps = []
        entry = self.latest().get(tuple(key))
        if entry is None:
            return {"state": IDLE, "reason": "게시 의도 없음", "key": list(key)}
        if entry["state"] not in UNSETTLED:
            return self._settle(entry)
        command, owner, gen = entry.get("command"), entry.get("owner"), entry.get("gen")
        seat = owner.rsplit("#", 1)[0] if owner else None
        answer = self._lookup(entry)
        self._step("lookup")
        settled = {"key": list(key), "command": command, "owner": owner, "gen": gen, "root": key.root,
                   "marker": entry["marker"], "body": entry.get("body", ""), "post_calls": entry.get("post_calls", 0)}
        if answer == FOUND:
            return self._settle(self._append(dict(settled, state=POSTED, via="lookup", resolve=POSTED)))
        if answer == ABSENT:
            return self._post(key, command, entry.get("body", ""), seat, gen, owner, via=RESENT,
                              prior=entry.get("post_calls", 0))
        repeated = entry.get("answer") == UNDECIDABLE  # 같은 «판정 불가» 를 두 번 알리지 않는다
        row = self._append(dict(settled, state=UNCERTAIN, reason="판정 불가 = 보존", answer=UNDECIDABLE,
                                resolve=UNDECIDABLE))
        if not repeated:
            self.notify(row)  # 판정 불가 = 보존 + 사람 알림 1(줄 11)
            self._step("notify")
        return row

    def _post(self, key, command, body, seat, gen, owner, via=POSTED, prior=0):
        """post 시도 — 매 시도 직전 binding 재검사(R1) · 예산은 장부 누적에서 복원(R2)."""
        calls, waits, budget = 0, [], self.MAX_POSTS - prior
        while calls < budget:
            calls += 1
            refusal = self._gate(key, command, seat, gen, via, calls)
            if refusal is not None:
                return self._append(refusal)
            self._append({"state": ATTEMPT, "root": key.root, "key": list(key), "command": command, "owner": owner,
                          "gen": gen, "marker": marker_for(key, command), "body": body, "post_calls": prior + calls})
            try:
                marker = marker_for(key, command)  # 본문 = body 만 · metadata.command = 요청 번호(줄 10 · r1818 E1)
                metadata = {"event_type": "ft2_reply", "event_payload": {"command": command, "marker": marker}}
                posted_ts = self.post(key.root, body, marker, metadata)
            except RateLimited as exc:
                waits.append(round(float(exc.retry_after), 1))
                self.sleep(float(exc.retry_after))
                self._step("after_wait")
                if calls >= budget:
                    return self._fail(key, command, owner, gen, waits, prior + calls)
                continue
            except ResponseLost:
                return self._append({"state": UNCERTAIN, "reason": "응답 유실 = 판정 보류", "root": key.root,
                                     "key": list(key), "command": command, "owner": owner, "gen": gen,
                                     "marker": marker_for(key, command), "body": body, "waits": waits,
                                     "post_calls": prior + calls, "attempts": prior + calls})
            row = self._append({"state": via, "resolve": via, "root": key.root, "key": list(key), "command": command,
                                "owner": owner, "gen": gen, "marker": marker_for(key, command), "ts": posted_ts,
                                "waits": waits, "post_calls": prior + calls, "attempts": prior + calls})
            self._step("after_posted")
            return self._settle(row)
        return self._fail(key, command, owner, gen, waits, prior, "재시도 예산 소진(장부 누적)", code=None)

    def _fail(self, key, command, owner, gen, waits, calls, reason="두 번째 429 = 보이는 오류", code=429):
        row = {"state": ERROR, "k": "post_failed", "code": code, "root": key.root, "reason": reason, "key": list(key),
               "command": command, "owner": owner, "gen": gen, "waits": waits, "post_calls": calls, "attempts": calls}
        self._append(row)
        self._step("failed")
        raise PostFailed(row)

    def _repeated(self, key, command):
        """같은 key·command 기록 — 게시됨이면 첫 게시 ts 를 돌려주는 거절 · 미해소면 resolve() 먼저(계약 3)."""
        same = [entry for entry in self.entries() if entry.get("key") == list(key) and entry.get("command") == command]
        posted = next((entry for entry in same if entry["state"] in (POSTED, RESENT)), None)
        if posted is not None:
            self._settle(posted)
            return self._refused(key, command, "same_intent", reason="같은 intent 재회신", ts=posted.get("ts"))
        if any(entry["state"] in UNSETTLED for entry in same):
            return self._refused(key, command, "same_intent_unsettled", reason="같은 intent 재회신 = 미해소 · resolve() 먼저")
        return None

    def _gate(self, key, command, seat, gen, via, call):  # 게시 전 재검사 — 옛 세대·닫힘은 게시 0(R1)
        return self._refusal(key, command, seat, gen)

    def _lookup(self, entry):  # 표식 조회 3값 — 조회 자체가 불명이면 «판정 불가»(재송 0)
        try:
            answer = self.lookup(entry["marker"])
        except Exception:  # 조회 실패 = 판정 불가 · 조용한 «없음» 으로 읽지 않는다
            return UNDECIDABLE
        return answer if answer in (FOUND, ABSENT) else UNDECIDABLE

    def _refusal(self, key, command, seat, gen):
        """답 거절 판정 — 닫힌 binding(줄 14) · 옛 세대(줄 12). 통과면 None."""
        now = self.binding.get(key)
        if now is None or not now.open:  # 닫히면 담당 없음 = 답 거절(줄 14)
            return self._refused(key, command, "reply_refused", reason="닫히면 담당 없음 = 답 거절",
                                 owner=None if now is None else now.owner)
        desk = self.delegate() if callable(self.delegate) else self.delegate  # r1862 R1 판정마다 현역 _desk 재판독
        if seat is not None and (seat, gen) != (now.seat, now.gen) and not (
                desk and seat == desk and gen == now.gen):  # r1862 desk 대신 답 · binding 쓰기 0
            return self._refused(key, command, "stale_owner", seat=owner_label(seat, gen or 0),
                                 owner=now.owner, reason="옛 세대 답 거절")
        return None

    def _refused(self, key, command, kind, **extra):
        return dict({"state": REFUSED, "k": kind, "key": list(key), "command": command, "root": key.root,
                     "posts": 0}, **extra)

    def _settle(self, row):  # r1872 게시 확정 3곳 공통 · 멱등 · 실패 = 판정 불가 1줄(게시 결과 그대로)
        if row.get("state") in (POSTED, RESENT):
            self.settled = reply_done.settle(self.root, self.team, row)
        return row

    def _step(self, name):
        self.steps.append(name)
        self.on_step(name)

    def _append(self, entry):
        with open(self.path, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(dict(entry, schema=1, at=self.clock()), ensure_ascii=False, sort_keys=True) + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        fd = os.open(os.path.dirname(self.path), os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
        return entry
