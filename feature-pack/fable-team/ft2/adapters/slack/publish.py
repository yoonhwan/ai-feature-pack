"""ft2 Slack 답 발행 — 계약 줄 10·11·12·13·14 (r1582 · PR③ 둘째 장).

답은 binding 이 가리키는 thread 1곳에만 나가고, 머리의 요청 번호는 팀 도구 command 그대로다(줄 10 ·
사례 c1). 게시 «의도»(표식 · root · command · owner 세대 · 본문)를 post 앞에 내구화한다 — post 직후 결과
기록 전에 crash 해도 재기동은 표식 조회 먼저다(ⓖ). post 응답 유실 = UNCERTAIN · 자동 재송 0(줄 11).
표식 조회는 3값으로만 판정한다 — «있음» = posted(게시 1 · post 0) · «없음 확인» = 같은 표식으로 재송 1 ·
«판정 불가» = 보존 + 사람 알림 1(사례 t3). 429 = Retry-After 만큼 기다린 뒤 재시도 1 · 두 번째 429 =
보이는 오류 행 `post_failed`(줄 13 · 사례 c4). 옛 세대(gen 불일치) 답과 닫힌 binding 답은 거절 행만
남기고 게시 0(줄 12·14 · 사례 c7·c6·d4). 전송은 대역 주입이다 — 이 파일은 네트워크를 직접 부르지 않는다.
"""

import importlib.util
import json
import os
import time

_HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location("ft2_slack_binding", os.path.join(_HERE, "binding.py"))
binding = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(binding)

Key, owner_label = binding.Key, binding.owner_label
POSTED, RESENT, UNCERTAIN, ERROR, REFUSED, IDLE = "posted", "resent", "uncertain", "error", "refused", "idle"
INTENT = "intent"
UNSETTLED = (INTENT, UNCERTAIN)
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
    """두 번째 429 = 보이는 오류. `row` 는 기록에 남은 그 행이다."""
    def __init__(self, row):
        super().__init__("post_failed %s" % row.get("root"))
        self.row = row


def marker_for(key, command):
    """답 표식 — 조회와 재송이 같은 값으로 판정하게 한다(receive.py 재송 표식과 다른 낱말)."""
    return "[[slack-reply %s %s/%s/%s]]" % (command, key.workspace, key.channel, key.root)


def reply_text(key, command, body):
    """thread 에 나가는 답 — 첫 줄 = 요청 번호 그대로 · 둘째 줄 = 표식(줄 10)."""
    return "%s\n%s\n%s" % (command, marker_for(key, command), body)


class SlackPublish:
    """팀 runtime 1곳의 답 발행. 판정은 `state` 한 낱말로만 말한다."""
    MAX_POSTS = 2  # 첫 시도 + 재시도 1 — 세 번째 시도 0(하드 룰 12 · 계약 줄 13)

    def __init__(self, root, *, post, lookup=None, sleep=None, notify=None, team="harness",
                 bindings=None, clock=None, on_step=None):
        self.post = post
        self.lookup = lookup or (lambda marker: UNDECIDABLE)
        self.sleep = sleep or (lambda seconds: None)
        self.notify = notify or (lambda row: None)
        self.clock = clock or (lambda: time.strftime("%Y-%m-%dT%H:%M:%S"))
        self.binding = bindings or binding.ThreadBinding(root, team, clock=self.clock)
        self.on_step, self.steps = on_step or (lambda step: None), []
        data = os.path.join(os.path.abspath(str(root)), ".fable-team", "teams", team, "slack")
        os.makedirs(data, exist_ok=True)
        self.path = os.path.join(data, "publish.jsonl")

    def entries(self):
        if not os.path.exists(self.path):
            return []
        with open(self.path, encoding="utf-8") as handle:
            return [json.loads(line) for line in handle if line.strip()]

    def latest(self):
        """thread 별 마지막 기록 — 판정은 이 한 줄에서 시작한다."""
        return {tuple(entry["key"]): entry for entry in self.entries() if entry.get("key")}

    def reply(self, key, command, body, seat=None, gen=None):
        """답 1건. 거절이면 게시 0, 아니면 «의도 기록 → post → 결과 기록»(ⓖ)."""
        self.steps = []
        refusal = self._refusal(key, command, seat, gen)
        if refusal is not None:
            return self._append(refusal)
        owner = owner_label(seat, gen) if seat is not None else None
        self._append({"state": INTENT, "root": key.root, "key": list(key), "command": command,
                      "owner": owner, "gen": gen, "marker": marker_for(key, command), "body": body,
                      "post_calls": 0, "attempts": 0})
        self._step("after_intent")
        return self._post(key, command, body, seat, gen, owner, via=POSTED)

    def resolve(self, key):
        """재기동·유실 뒤 판정 — 표식 조회 먼저 · 새 게시 0. 반환 = 판정 1개."""
        self.steps = []
        entry = self.latest().get(tuple(key))
        if entry is None:
            return {"state": IDLE, "reason": "게시 의도 없음", "key": list(key)}
        if entry["state"] not in UNSETTLED:
            return entry
        command, owner, gen = entry.get("command"), entry.get("owner"), entry.get("gen")
        seat = owner.rsplit("#", 1)[0] if owner else None
        answer = self._lookup(entry)
        self._step("lookup")
        settled = {"key": list(key), "command": command, "owner": owner, "gen": gen,
                   "marker": entry["marker"], "root": key.root, "body": entry.get("body", ""),
                   "post_calls": entry.get("post_calls", 0), "attempts": entry.get("attempts", 0)}
        if answer == FOUND:
            return self._append(dict(settled, state=POSTED, via="lookup", resolve=POSTED))
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
        """post 시도 — 429 는 Retry-After 만큼 기다린 뒤 재시도 1회까지만."""
        calls, waits = 0, []
        while calls < self.MAX_POSTS:
            calls += 1
            try:
                posted_ts = self.post(key.root, reply_text(key, command, body), marker_for(key, command))
            except RateLimited as exc:
                waits.append(round(float(exc.retry_after), 1))
                self.sleep(float(exc.retry_after))
                self._step("wait")
                if calls >= self.MAX_POSTS:
                    row = {"state": ERROR, "k": "post_failed", "code": 429, "root": key.root,
                           "key": list(key), "command": command, "owner": owner, "gen": gen,
                           "waits": waits, "post_calls": prior + calls, "attempts": prior + calls}
                    self._append(row)
                    self._step("failed")
                    raise PostFailed(row)
                continue
            except ResponseLost:
                return self._append({"state": UNCERTAIN, "reason": "응답 유실 = 판정 보류", "root": key.root,
                                     "key": list(key), "command": command, "owner": owner, "gen": gen,
                                     "marker": marker_for(key, command), "body": body, "waits": waits,
                                     "post_calls": prior + calls, "attempts": prior + calls})
            return self._append({"state": via, "resolve": via, "root": key.root, "key": list(key), "command": command,
                                 "owner": owner, "gen": gen, "marker": marker_for(key, command), "ts": posted_ts,
                                 "waits": waits, "post_calls": prior + calls, "attempts": prior + calls})

    def _lookup(self, entry):
        """표식 조회 3값 — 조회 자체가 불명이면 «판정 불가»(재송 0)."""
        try:
            answer = self.lookup(entry["marker"])
        except Exception:  # 조회 실패 = 판정 불가 · 조용한 «없음» 으로 읽지 않는다
            return UNDECIDABLE
        return answer if answer in (FOUND, ABSENT) else UNDECIDABLE

    def _refusal(self, key, command, seat, gen):
        """답 거절 판정 — 닫힌 binding(줄 14) · 옛 세대(줄 12). 통과면 None."""
        now = self.binding.get(key)
        if now is None or not now.open:
            return self._refused(key, command, "reply_refused", reason="닫히면 담당 없음 = 답 거절",
                                 owner=None if now is None else now.owner)
        if seat is not None and (seat, gen) != (now.seat, now.gen):
            return self._refused(key, command, "stale_owner", seat=owner_label(seat, gen or 0),
                                 owner=now.owner, reason="옛 세대 답 거절")
        return None

    def _refused(self, key, command, kind, **extra):
        row = {"state": REFUSED, "k": kind, "key": list(key), "command": command, "root": key.root, "posts": 0}
        row.update(extra)
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
