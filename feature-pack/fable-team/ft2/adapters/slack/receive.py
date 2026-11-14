"""ft2 Slack 수신 어댑터 — 계약 줄 2·3·4·5·6·15·16 (r1580 · PR③ 첫 장).

흐름(줄 2): 거름 → 메시지 키(줄 3) → 수신 기록 내구화 → Slack 확인 → 입구 전달 → 영수 판정(줄 4).
확인 ≠ 접수: Slack «받았다» 와 Intake 영수는 다른 사건이다. 넘김 완료는 두 경로로 갈린다 — 제출 경로 =
result «접수 성공» ∧ written True · 조회 경로 = result «접수 성공» ∧ attempt 있음(DA R1 §2: 조회 성공
영수는 written False · body_ref None 이 정상).
«완료 유보»·«복구 필요»·«용량 부족»·«BUSY»(r1579 실행권) = 미완 보존 — 영수 0 · 기록 보존 · 가득은 알림 1건.
미인가·bot·다른 채널(줄 15) = 확인만 하고 버린다. 유휴·중복·무변화(줄 16) = 도구 안에서 끝난다. 재송
(줄 5) = 머리에 메시지 키 표식 · 회차는 기록 누적 · 원문은 received 행에서 꺼낸다(같은 command 재부여 0).
"""

import collections
import importlib.util
import json
import os
import sys
import time

_HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location(
    "ft2_core_intake", os.path.join(os.path.dirname(os.path.dirname(_HERE)), "core", "intake.py"))
intake = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(intake)
_FA = importlib.util.spec_from_file_location("ft2_receive_full_alert", os.path.join(os.path.dirname(_HERE), "pi", "full_alert.py"))
_FA.loader.exec_module(full_alert := importlib.util.module_from_spec(_FA))  # r1885 보류 노출 = r1886 observe

RESULT_OK, RESULT_FULL = intake.RESULT_OK, intake.RESULT_FULL
DISPATCHED, DUPLICATE, IGNORED, SETTLED = "dispatched", "duplicate", "ignored", "settled"  # settled = 밖에서 답함(r1899)
RECEIVED, FULL, HOLD, IDLE = "received", "full", "hold", "idle"
UNFINISHED = (RECEIVED, HOLD, FULL)
BOT_SUBTYPES = ("bot_message", "bot_add")

#: 이 장이 덮는 계약 줄 — 계약 낱말 그대로 적는다(시험이 사례 expect 낱말과 대조한다).
COVERS = {
    2: "거름 → 메시지 키 → 기록 → Slack 확인 → 입구 전달 · 확인 ≠ 업무 접수",
    3: "메시지 키 (workspace, channel, ts) · 전송 힌트 event_id·client_msg_id",
    4: "넘김 완료 = 팀 도구 입구 영수 · 영수가 없으면 같은 전달 의도로 대조·복구",
    5: "재송 머리에 메시지 키 표식 · 같은 표식 2번째부터 안 읽음",
    6: "입구 가득이면 영수 0 · 접수 아님 · 기록 보존 + 알림",
    15: "미인가·bot·다른 채널은 확인만 하고 버림",
    16: "유휴·중복·무변화 — 모델 호출·좌석 깨움·틱 상태 메시지 0",
}

Key = collections.namedtuple("Key", "workspace channel ts")

def message_key(event):
    """메시지 키 3종 — event 안 team 이 없으면 envelope 최상위 team 을 쓴다."""
    return Key(str(event.get("team") or event.get("workspace") or ""),
               str(event.get("channel") or ""), str(event.get("ts") or ""))

def command_for(key):
    """입구 command = 메시지 키 3종 그대로. 같은 키 = 같은 command = 새 attempt 0."""
    return "slack:%s:%s:%s" % (key.workspace, key.channel, key.ts)

def resend_marker(key, attempts):
    """재송 머리 표식 — 2번째 시도부터 1줄. 회차는 기록이 정한다."""
    if attempts <= 1:
        return ""
    return "[[slack-key %s/%s/%s]] 재송 %d\n" % (key.workspace, key.channel, key.ts, attempts - 1)

class SlackReceive:
    """Slack 사건 1건 = 판정 1개. 상태는 `state` 한 낱말로만 말한다."""
    _key = staticmethod(message_key)
    def __init__(self, root, *, ack, client=None, team="harness", capacity=8, allowed_users=(),
                 allowed_channels=(), bot_users=(), notify=None, clock=None, on_step=None,
                 replies=None, deadline=None, mono=None, log=None):
        self.ack, self.root, self.team, self.capacity = ack, os.path.abspath(str(root)), team, capacity
        # r1899 — replies(channel, thread) → 메시지 목록 · deadline = 기동 monotonic + 60 · 없음 = 2.0.31 동작
        self.replies, self.deadline, self.mono = replies, deadline, mono or time.monotonic
        self.log = log or (lambda line: None)
        self.notify = notify or (lambda verdict: None)
        self.allowed_users, self.allowed_channels = set(allowed_users), set(allowed_channels)
        self.bot_users, self.clock = set(bot_users), clock or (lambda: time.strftime("%Y-%m-%dT%H:%M:%S"))
        self.on_step, self.steps = on_step or (lambda step: None), []
        data = os.path.join(os.path.abspath(str(root)), ".fable-team", "teams", team, "slack")
        os.makedirs(data, exist_ok=True)
        self.path = os.path.join(data, "receive.jsonl")
        self.settle_path = os.path.join(data, "settle.jsonl")  # r1906 desk 처리 기록 요청 — listen 은 읽기만
        self.client = client or intake.Intake(str(root), team, capacity=capacity, clock=self.clock)

    def entries(self):
        if not os.path.exists(self.path):
            return []
        with open(self.path, encoding="utf-8") as handle:
            return [json.loads(line) for line in handle if line.strip()]

    def latest(self):
        return {entry["command"]: entry for entry in self.entries() if entry.get("command")}

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

    def _step(self, name):
        self.steps.append(name)
        self.on_step(name)

    def _next_attempt(self, command):
        """시도 회차 = 기록 누적 최대값 + 1 — 재기동마다 새로 만들지 않는다."""
        seen = [entry.get("attempts", 1) for entry in self.entries() if entry.get("command") == command]
        return max(seen or [0]) + 1

    def handle(self, event):
        """사건 1건 처리. 반환 = 판정 1개. 사건이 비면 유휴 회차."""
        self.steps = []
        if not event:
            return self.pass_idle()
        self._step("filter")
        reason, key = self._drop_reason(event), self._key(event)
        self._step("key")
        command = command_for(key)
        if reason:
            self.ack(event)
            self._step("ack")
            return self._append({"state": IGNORED, "command": command, "key": list(key),
                                 "reason": reason, "attempts": 0, "acked": True})
        prior = self.latest().get(command)
        if prior and prior.get("state") in (DISPATCHED, DUPLICATE, IGNORED, SETTLED):
            self.ack(event)  # 같은 키 재전달 = 새 접수 0, 버린 사건은 계속 버린다(줄 15·16)
            self._step("ack")
            again = IGNORED if prior["state"] == IGNORED else DUPLICATE
            return self._append({"state": again, "command": command, "key": list(key),
                                 "reason": prior["state"], "attempts": prior.get("attempts", 0), "acked": True})
        if prior and prior.get("state") == FULL:  # r1906 — 다시 넣기 전에 desk 처리 기록 · 못 읽음 = 넣기 0
            asked = read_settle(self.settle_path)
            if asked is None or command in asked:
                self.ack(event)
                self._step("ack")
                if asked is None:
                    self.log("handle settle.jsonl 판정 불가 · %s full 그대로" % command)
                    return dict(prior, reason="판정 불가 settle.jsonl")
                return self._settle(command, prior, asked)
        if prior:
            return self._recover(command, entry=prior, event=event)
        return self._dispatch(command, key, event, self._next_attempt(command))

    def pass_idle(self):
        self._step("idle")  # 줄 16 — 모델 호출·좌석 깨움·기록 증가 0
        return {"state": IDLE, "reason": "무변화", "command": None}

    def recover(self):
        """재기동 1회 — 미완 기록마다 lookup 먼저(새 attempt 0). 반환 = 판정 목록. r1885: received·hold 먼저 → full 은
        예산 = max(0, capacity − 그때 남은 일)만큼 새 글(ts 큰 순) 먼저 · 나머지 full 손 0 · 남은 full 수 = observe «보류» 1곳."""
        asked = read_settle(self.settle_path)  # r1906 — 다시 넣기 전 1번 · None = 판정 불가
        for command, entry in sorted(self.latest().items()):
            self._settle(command, entry, asked or {})
        rows, ts = sorted(self.latest().items()), lambda row: float((row[1].get("key") or [0, 0, 0])[2] or 0)
        out = [self._recover(command, entry=entry) for command, entry in rows if entry.get("state") in (RECEIVED, HOLD)]
        team = getattr(self.client, "team", self.team)
        room = max(0, getattr(self.client, "capacity", self.capacity) - full_alert.projection.project(self.root, team)["remaining"])
        full = sorted((row for row in rows if row[1].get("state") == FULL), key=lambda row: (row[1].get("unknown", 0), -ts(row)))
        if asked is None:
            self.log("recover settle.jsonl 판정 불가 · full %d건 넣기 0 · 다음 기동" % len(full))
            full = []
        out += self._recover_full(full, room)
        held = sorted((row for row in self.latest().items() if row[1].get("state") == FULL), key=ts) or [("-", {})]
        oldest = time.strftime("%m-%d %H:%M", time.localtime(ts(held[0]))) if held[0][1] else "-"
        count = len(held) if held[0][1] else 0
        full_alert.observe(self.root, "보류", team, count, 1, "full %d건 · 가장 오래된 %s %s · 정리 = desk 대조 뒤 complete" % (count, oldest, held[0][0]))
        return out

    def _recover_full(self, full, room):
        """r1899 — 정렬 순서로 1건씩: 봇 답 있음 = settled(넣기 0) · 답 없음 = 넣기(room 1칸) · 판정 불가 = full 에 unknown+1.
        room 이 차면 멈춤 · deadline 지나면 남은 full 손 0 + listen.log 1줄 · replies 없음 = 앞에서 room 개 넣기."""
        out, seen, unknown = [], {}, 0
        for index, (command, entry) in enumerate(full):
            if len(out) >= room:
                break
            if self.replies is not None and self.deadline is not None and self.mono() >= self.deadline:
                self.log("recover 예산 끝 · 남은 full %d건 · 다음 기동" % (len(full) - index))
                break
            word, why = self._answered(command, entry, seen) if self.replies is not None else ("", "")
            if word == SETTLED:
                self._append({"state": SETTLED, "command": command, "key": entry.get("key"),
                              "attempts": entry.get("attempts", 1), "reason": why})
            elif word:
                unknown += 1
                self._append(dict(entry, unknown=entry.get("unknown", 0) + 1, reason="판정 불가 " + why))
            else:
                out.append(self._recover(command, entry=entry))
        if unknown:
            self.log("recover 판정 불가 %d건 · full 그대로 · 다음 기동" % unknown)
        return out

    def _settle(self, command, entry, asked):
        """r1906 — 처리 기록 요청이 있고 최신 상태가 full 일 때만 settled 1줄(끝 상태 위 덮기 0)."""
        if command not in asked or entry.get("state") != FULL:
            return None
        row = asked[command]
        return self._append({"state": SETTLED, "command": command, "key": entry.get("key"),
                             "attempts": entry.get("attempts", 1), "reason": "처리 기록 %s · %s" % (row.get("by"), row.get("why"))})

    def _answered(self, command, entry, seen):
        """thread = route 의 그 command 최신 key[2](없으면 글 ts) · thread 당 1번 읽음 → (settled|unknown|"", 이유)."""
        key = entry.get("key") or ["", "", "0"]
        route = os.path.join(os.path.dirname(self.path), "route.jsonl")
        rows = []
        if os.path.exists(route):
            with open(route, encoding="utf-8") as handle:
                rows = [json.loads(line) for line in handle if line.strip()]
        thread = ([r["key"][2] for r in rows if r.get("command") == command and r.get("key")] or [key[2]])[-1]
        if (key[1], thread) not in seen:
            try:
                seen[(key[1], thread)] = list(self.replies(key[1], thread))
            except Exception as exc:  # 넘침·ok false·시간 초과 = 판정 불가(답 없음으로 대신하지 않는다)
                seen[(key[1], thread)] = type(exc).__name__
        found = seen[(key[1], thread)]
        if isinstance(found, str):
            return "unknown", found
        later = [m["ts"] for m in found if m.get("bot_id") and float(m.get("ts") or 0) > float(key[2] or 0)]
        return (SETTLED, "봇 답 있음 %s" % later[0]) if later else ("", "")

    def _drop_reason(self, event):
        if event.get("type", "message") != "message":
            return "message 아님"
        if event.get("bot_id") or event.get("subtype") in BOT_SUBTYPES or event.get("user") in self.bot_users:
            return "bot"
        if event.get("user") not in self.allowed_users:
            return "미인가 사용자"
        if event.get("channel") not in self.allowed_channels:
            return "허용 밖 채널"
        return "" if str(event.get("text") or "").strip() else "무변화"

    def _dispatch(self, command, key, event, attempts, confirm=True):
        """새 전달 1회 — 기록 → 확인 → 입구 → 영수 판정(계약 줄 2 순서)."""
        self._append({"state": RECEIVED, "command": command, "key": list(key), "attempts": attempts,
                      "event_id": event.get("event_id"), "client_msg_id": event.get("client_msg_id"),
                      "user": event.get("user"), "text": str(event.get("text") or ""), "acked": False})
        self._step("record")
        if confirm:
            self.ack(event)
            self._step("ack")
        receipt = self.client.submit(command, resend_marker(key, attempts) + str(event.get("text") or ""),
                                     {"slack": {"workspace": key.workspace, "channel": key.channel,
                                                "ts": key.ts, "attempts": attempts}})
        self._step("submit")
        return self._verdict(receipt, command, key, attempts)

    def _recover(self, command, entry=None, event=None):
        """미완 기록 1건 — 들어온 사건은 확인부터(결과 무관) · lookup 먼저 · 원문은 received 행에서."""
        entry = entry or self.latest().get(command) or {}
        source = ([r for r in self.entries() if r.get("command") == command and r.get("state") == RECEIVED] or [entry])[-1]
        key = Key(*source["key"]) if source.get("key") else None
        redelivered = event is not None
        if redelivered:  # 재전달 확인은 lookup 결과와 무관하다(DA HOLD R2)
            self.ack(event)
            self._step("ack")
        receipt = self.client.lookup(command)
        self._step("lookup")
        if receipt is not None:
            return self._verdict(receipt, command, key, entry.get("attempts", 1), via="lookup")
        event = event or dict(source, type="message", team=key.workspace, channel=key.channel, ts=key.ts)
        return self._dispatch(command, key, event, self._next_attempt(command), confirm=not redelivered)

    def _verdict(self, receipt, command, key, attempts, via="submit"):
        state, reason = self._judge(receipt, via)
        verdict = self._append({"state": state, "command": command, "key": list(key), "attempts": attempts,
                                "via": via, "reason": reason,
                                "receipt": None if receipt is None else
                                {"result": receipt.result, "attempt": receipt.attempt,
                                 "written": receipt.written}})
        self._step("receipt")
        if receipt is not None and receipt.result == RESULT_FULL:
            self.notify(verdict)  # 줄 6 = 기록 보존 + 알림 1건
            self._step("notify")
        return verdict

    def _judge(self, receipt, via="submit"):
        """넘김 완료 판정 — 제출 경로와 조회 경로의 조건이 다르다(DA R1 §2)."""
        if receipt is None:  # 조회 None = 영수 없음 → 다음 시도 판단
            return HOLD, "영수 없음"
        if receipt.result != RESULT_OK:
            return (FULL if receipt.result == RESULT_FULL else HOLD), receipt.result
        if via == "lookup":
            return (DISPATCHED, "조회 영수") if receipt.attempt else (HOLD, "영수에 attempt 없음")
        return (DISPATCHED, "제출 영수") if receipt.written else (HOLD, "영수 미확정")


def read_settle(path):
    """r1906 settle.jsonl → {command: 첫 요청} · 파일 없음 = {} · 못 읽음 = None(판정 불가) · 깨진 줄 = 건너뜀."""
    if not os.path.exists(path):
        return {}
    try:
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
    except (OSError, UnicodeDecodeError):
        return None
    asked = {}
    for line in filter(str.strip, text.splitlines()):
        try:
            row = json.loads(line)
        except ValueError:
            continue
        if isinstance(row, dict) and row.get("command"):
            asked.setdefault(row["command"], row)
    return asked


def _slack_dir(root, team):
    return os.path.join(os.path.abspath(str(root)), ".fable-team", "teams", team, "slack")


def _rows(path):
    with open(path, encoding="utf-8") if os.path.exists(path) else open(os.devnull) as handle:
        return [json.loads(line) for line in handle if line.strip()]


def settle(root, team, command, by, why):
    """desk 처리 기록 요청 1줄(O_APPEND 1회 + fsync) — receive.jsonl 은 읽기만. 반환 = (rc, 출력 1줄)."""
    parts = str(command).split(":")
    if len(parts) != 4 or parts[0] != "slack" or not all(parts[1:]):
        return 2, "REJECT %s command 꼴 틀림(slack:<ws>:<ch>:<ts>)" % command
    folder = _slack_dir(root, team)
    try:
        state = {r.get("command"): r for r in _rows(os.path.join(folder, "receive.jsonl"))}.get(command, {}).get("state")
    except (OSError, ValueError) as exc:
        return 3, "판정 불가 slack settle %s receive.jsonl %s" % (command, type(exc).__name__)
    if state is None:
        return 2, "REJECT %s receive 에 없음" % command
    if state in (DISPATCHED, DUPLICATE, IGNORED, SETTLED):
        return 0, "NOOP %s %s" % (command, state)
    line = (json.dumps({"command": command, "by": by, "why": " ".join(str(why).split()),
                        "at": time.strftime("%Y-%m-%dT%H:%M:%S")}, ensure_ascii=False) + "\n").encode("utf-8")
    if len(line) >= 4096:
        return 2, "REJECT %s 한 줄 4KB 넘음" % command
    try:
        fd = os.open(os.path.join(folder, "settle.jsonl"), os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o644)
        try:
            if os.write(fd, line) != len(line):
                raise OSError("짧은 쓰기")
            os.fsync(fd)
        finally:
            os.close(fd)
    except OSError as exc:
        return 3, "판정 불가 slack settle %s %s" % (command, type(exc).__name__)
    return 0, "SETTLE-REQUESTED %s" % command


def list_full(root, team):
    """최신 full 글 1줄씩(ts 순) — `<command> <ts> <원문 낱말>[ 요청됨]` · desk 대조용 · 쓰기 0."""
    folder = _slack_dir(root, team)
    asked = read_settle(os.path.join(folder, "settle.jsonl"))
    if asked is None:
        return 3, ["판정 불가 slack list-full settle.jsonl"]
    latest, text = {}, {}
    for row in _rows(os.path.join(folder, "receive.jsonl")):
        latest[row.get("command")] = row
        text.update({row.get("command"): row.get("text")} if row.get("state") == RECEIVED else {})
    full = sorted((c.rsplit(":", 1)[1], c) for c, r in latest.items() if c and r.get("state") == FULL)
    return 0, ["%s %s %s%s" % (c, ts, " ".join(str(text.get(c) or "").split()), " 요청됨" if c in asked else "")
               for ts, c in full]


def main(argv=None):
    import argparse
    parser = argparse.ArgumentParser(prog="receive.py", description="r1906 desk 처리 기록 · full 목록")
    parser.add_argument("verb", nargs="?", choices=("settle",))
    parser.add_argument("--root", required=True)
    parser.add_argument("--team", required=True)
    parser.add_argument("--command")
    parser.add_argument("--by")
    parser.add_argument("--why")
    parser.add_argument("--list-full", action="store_true")
    args = parser.parse_args(argv)
    if args.list_full:
        rc, lines = list_full(args.root, args.team)
    elif args.verb == "settle" and args.command and args.by and args.why:
        rc, out = settle(args.root, args.team, args.command, args.by, args.why)
        lines = [out]
    else:
        parser.error("settle --command --by --why 또는 --list-full")
    for line in lines:
        print(line)
    return rc


if __name__ == "__main__":
    sys.exit(main())
