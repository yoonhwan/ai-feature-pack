"""ft2 경보 수신 갈래 (r2337) — GCP 경보 Slack 글 → 사건 장부 → issues 쪽지 1통.

계약(r2337 카드 G1~G6): 주기 폴링 0 · 새 상주 프로세스 0(수신기 안 일꾼 스레드 1) · Slack 쓰기 0(mbox send 만).
- 받기(G1): 수신기가 bot 글을 버리기 전에 부른다(feed). 채널 ∈ 경보 채널 ∧ app_id·bot_id = 설정 고정값일 때만
  큐에 넣는다. 재연결(hello)·수신기 재시작 사건마다 경보 채널 conversations.history 1쪽 1회(oldest = 장부 마지막
  글 ts · 빈 장부 = 지금 시각 = 보충 0)를 같은 판독에 넣는다(socket 이 부르고 ingest 로 큐를 지난다).
- 고르기(G2): 본문 = text ∨ attachments·blocks · 정책 ∧ 사건 id ∧ 상태 셋 다 읽혀야 경보 글 · 하나라도 못 읽으면
  «판독 불가 글» 1시간 1통.
- 묶기(G3): 열쇠 = 사건 id · 처음 보는 id = 새 사건 · 같은 id 재알림 = 횟수만 +1(재알림 3회 = «오래 열림» 1통) ·
  닫힘 = 닫힘 시각 + «닫힘» 30분 보류 · 같은 정책 새 id 가 앞 사건 닫힘 30분 안 = 앞 줄 «다시 열림 +1» ·
  앞 «닫힘» 취소 · 새 쪽지 0 · 새 줄도 «발송됨» 물려받음.
- 쪽지(G4): 새 사건 = 바로 1통 · 5분 창 안 새 사건이 3개를 넘으면 넘친 것만 묶어 창 끝 1통 · 1시간 상한 6통
  (6번째 끝 «상한 닿음») · 넘침 = 다음 정시 첫 통 · 같은 event 재전달 = 쪽지 0 · send 1회 7초 상한 ·
  rc0 = «발송됨» · 실패 = «발송 안 됨» 인 채 60초 뒤 1회 더 · 두 번 실패 = «발송 멈춤» 장부 1줄 + log 1
  (다음 시도는 수신기 재기동 때 1회뿐 · 끝없는 재시도 0).
- 늦출 일(G5): 마감 표는 메모리 · 일꾼 queue.get(timeout=1) 마다 마감 지난 것만 · 1초 루프의 장부 읽기·stat 0 ·
  수신 루프(socket) 손 = on_idle 의 일꾼 is_alive 1줄 · 죽었으면 다시 띄우고 장부 1회 읽어 마감 표 재구성.
- 쓰기 범위(G6): 사건 장부(<root>/.fable-team/state/alert-intake/incidents.jsonl) · mbox send 뿐 ·
  장부 쓰기 = 일꾼 하나(수신 쪽 «받기 넘침» 은 메모리 셈만).

설정 = <root>/.fable-team/teams/<team>/slack/ALERT_INTAKE.json 한 파일
(`channels` · `app_id` · `bot_id` · `to` · `suggest`). 설정 없음·판독 불가 = 갈래 0(수신 결과 지금 그대로).

경보 글 원문 꼴(arch 실측 · a493 gcp-hist.json·gcp-close.json) = text 한 줄이 정본이고 attachments 0 ·
blocks 는 같은 글자다. 판독 4칸 —
- 정책 = 링크 이름 칸 (`<https://…|…>` 의 `|` 뒤) · 사건 id = 링크 `alerts/<id>` ·
- 상태 = `Alert status Alert open|closed` · 값 = `with a value of <수>`.
`&amp;`·`&gt;` escape 는 그대로 둔다(풀지 않는다). 꼴이 어긋나면 글자 표지(열림·닫힘·FIRING·RESOLVED)와
`key: value` 줄로 한 번 더 본다 — 못 읽으면 «판독 불가 글».
"""

import json
import os
import queue
import re
import shlex
import subprocess
import threading
import time

SENDER = "ft2-alert-intake"
CONFIG = "ALERT_INTAKE.json"
LEDGER = ("state", "alert-intake", "incidents.jsonl")
WINDOW_S, FOLD_N, HOLD_S, RETRY_S = 300, 3, 1800, 60
HOUR_S, HOUR_MAX, STALE_N, UNREADABLE_S = 3600, 6, 3, 3600
MAX_TRIES, RESTART_GAP = 2, 60  # 쪽지 1통 = 시도 2회(지금 1 + 60초 뒤 1) · 일꾼 재기동은 60초에 1회
QUEUE_MAX, SEND_S = 1000, 7.0
OPEN_WORDS = ("firing", "alerting", "[open]", "열림", "발생")
CLOSE_WORDS = ("resolved", "[closed]", "닫힘", "해소", "back to normal")
FIELD = r"(?im)^\s*%s\s*[:：]\s*(.+?)\s*$"
LINK = re.compile(r"<([^|>\s]+)\|([^>]+)>")  # GCP 경보 = 링크 이름 칸이 정책 이름
ALERT_ID = re.compile(r"alerts/([^?&\s>]+)")
STATUS = re.compile(r"alert status\s+alert\s+(open|closed)", re.I)
VALUE = re.compile(r"value of\s*([0-9][0-9,]*(?:\.[0-9]+)?)", re.I)
URL = re.compile(r"https?://[^\s<>)\]]+")
INC_ID = re.compile(r"\b\d+\.[0-9a-f]{8,}\b|\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b", re.I)
HEAD = {"new": "새 사건", "bundle": "묶음 새 사건", "close": "닫힘", "stale": "오래 열림",
        "overflow": "받기 넘침", "unreadable": "판독 불가 글", "밀림": "밀림"}


def config_path(root, team):
    return os.path.join(str(root), ".fable-team", "teams", team, "slack", CONFIG)


def ledger_path(root):
    return os.path.join(str(root), ".fable-team", *LEDGER)


def load_config(root, team):
    """설정 1파일 → dict · 없음·깨짐·필수 칸 없음 = None(갈래 0 · 수신은 지금 그대로)."""
    try:
        with open(config_path(root, team), encoding="utf-8") as handle:
            conf = json.load(handle)
    except (OSError, ValueError):
        return None
    if not isinstance(conf, dict):
        return None
    ok = conf.get("channels") and conf.get("app_id") and conf.get("bot_id") and conf.get("to")
    return conf if ok else None


def body_text(event):
    """글 본문 = text ∨ attachments·blocks 의 글자 전부(한 덩어리 · 빈 줄 접기)."""
    parts = [str(event.get("text") or "")]
    for att in event.get("attachments") or []:
        if isinstance(att, dict):
            parts += [str(att.get(key) or "") for key in ("pretext", "title", "text", "fallback")]
            for field in att.get("fields") or []:
                if isinstance(field, dict):
                    parts.append("%s: %s" % (field.get("title") or "", field.get("value") or ""))
    for block in event.get("blocks") or []:
        if not isinstance(block, dict):
            continue
        parts += [str((block.get("text") or {}).get("text") or "")] if isinstance(block.get("text"), dict) else []
        for field in block.get("fields") or []:
            if isinstance(field, dict):
                parts.append(str(field.get("text") or ""))
    return "\n".join(line for line in parts if line.strip())


def _field(text, *names):
    for name in names:
        found = re.search(FIELD % re.escape(name), text)
        if found:
            return found.group(1).strip()
    return ""


def state_of(text):
    """상태 = 글자 표지가 먼저 나온 쪽 · 없으면 빈 값(판독 불가)."""
    low = text.lower()
    close_at = min([low.find(word) for word in CLOSE_WORDS if low.find(word) >= 0] or [10 ** 9])
    open_at = min([low.find(word) for word in OPEN_WORDS if low.find(word) >= 0] or [10 ** 9])
    return "닫힘" if close_at < open_at else ("열림" if open_at < 10 ** 9 else "")


def parse(event):
    """경보 글 1건 → {policy, id, state, value, link} · 못 읽은 칸 = 빈 값.

    실측 꼴이 먼저다(링크 이름 = 정책 · alerts/<id> · «Alert status Alert open|closed» · value of <수>).
    꼴이 어긋난 글은 글자 표지와 `key: value` 줄로 한 번 더 본다(관대한 폴백).
    """
    text = body_text(event)
    named = LINK.search(text)
    policy = named.group(2).strip() if named else ""
    if not policy:
        policy = _field(text, "policy", "정책", "policy name", "alert policy")
    if not policy:
        head = re.search(r"\[(?:FIRING|RESOLVED)[^\]]*\]\s*([^\n()\[]+)", text, re.I)
        policy = head.group(1).strip() if head else ""
    found = ALERT_ID.search(text)
    inc = found.group(1) if found else (_field(text, "incident id", "사건 id", "alert id") or "")
    if not inc:
        token = INC_ID.search(text)
        inc = token.group(0) if token else ""
    status = STATUS.search(text)
    state = {"open": "열림", "closed": "닫힘"}.get(status.group(1).lower(), "") if status else ""
    value = VALUE.search(text)
    return {"policy": policy, "id": inc, "state": state or state_of(text),
            "value": value.group(1) if value else _field(text, "condition", "값", "metric", "지표", "value"),
            "link": named.group(1) if named else (URL.search(text).group(0) if URL.search(text) else "")}


class AlertIntake:
    """경보 글 1건 = 사건 1개 · 쪽지 1통(창·상한 안) · 장부 쓰기 = 일꾼 스레드 하나."""

    def __init__(self, root, *, team="harness", conf=None, mbox=None, send=None, now=None, clock=None,
                 log=None, queue_max=QUEUE_MAX, send_s=SEND_S):
        self.root, self.team = os.path.abspath(str(root)), team
        self.conf = dict(conf if conf is not None else (load_config(self.root, team) or {}))
        self.channels = tuple(str(c) for c in self.conf.get("channels") or ())
        self.app_id, self.bot_id = str(self.conf.get("app_id") or ""), str(self.conf.get("bot_id") or "")
        self.to, self.suggest = str(self.conf.get("to") or ""), str(self.conf.get("suggest") or "미정")
        self.path = ledger_path(self.root)
        self.now = now or time.time
        self.clock = clock or (lambda: time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(self.now())))
        self.log = log or (lambda line: None)
        self.queue = queue.Queue(maxsize=int(queue_max))
        self.send_s = float(send_s)
        self.argv = shlex.split(mbox or os.environ.get("FT2_ALERT_MBOX")
                               or "bash " + shlex.quote(os.path.join(self.root, ".fable-team", "comm", "mbox.sh")))
        self.send = send or self._mbox
        self.inc, self.pending, self.sent_at, self.once = {}, [], [], {}
        self.window_start, self.window_ids, self.held = None, [], []
        self.last_ts, self.mid, self.overflow, self.capped = 0.0, 0, 0, None
        self.worker, self.stopping = None, threading.Event()
        self.last_start = 0.0
        self.stats = {"read": 0, "write": 0, "send": 0}
        self.writers = set()

    @property
    def enabled(self):
        return bool(self.channels and self.app_id and self.bot_id and self.to)

    # ── 수신 쪽(수신기 루프) — 넣고 바로 돌아간다. 장부·send 는 일꾼 몫.
    def feed(self, event):
        """경보 글 후보 1건 → 큐 · 반환 = 갈래로 갔는지(판정·쪽지 아님). 갈래 아님 = False."""
        if not self.enabled or not self._candidate(event):
            return False
        try:
            self.queue.put_nowait(("event", event))
        except queue.Full:
            self.overflow += 1  # 수신 쪽 메모리 셈만 · 장부 1줄은 일꾼이 쓴다
        return True

    def ingest(self, rows, more=False):
        """재연결·재시작 history 1쪽 → 같은 판독 · 판독도 큐를 지난다(장부 쓰기 = 일꾼)."""
        if not self.enabled:
            return
        try:
            self.queue.put_nowait(("history", list(rows or []), bool(more)))
        except queue.Full:
            self.overflow += 1

    def oldest(self):
        """history oldest — 장부에서 본 마지막 글 ts · 빈 장부 = 지금 시각(보충 0)."""
        return "%.6f" % (self.last_ts or self.now())

    def _candidate(self, event):
        return (str(event.get("channel") or "") in self.channels
                and str(event.get("app_id") or "") == self.app_id
                and str(event.get("bot_id") or "") == self.bot_id)

    # ── 일꾼 수명 · 루프
    def prepare(self):
        """장부 1회 읽어 마감 표·셈·마지막 글 ts 를 다시 만든다(기동·일꾼 재기동)."""
        rows, self.inc, mails, marks = [], {}, {}, {}
        if os.path.exists(self.path):
            self.stats["read"] += 1
            with open(self.path, encoding="utf-8") as handle:
                for line in handle:
                    try:
                        rows.append(json.loads(line))
                    except ValueError:
                        continue
        for row in rows:
            self._apply(row, mails, marks)
        self._restore(mails, marks)

    def _apply(self, row, mails, marks):
        kind = row.get("t")
        if kind == "inc":
            self.inc[row["id"]] = {"id": row["id"], "policy": row.get("policy") or "", "count": int(row.get("count") or 1),
                                   "sent": bool(row.get("sent")), "prev": row.get("prev") or "",
                                   "closed_at": row.get("closed_at"), "stale": bool(row.get("stale")),
                                   "reopened": int(row.get("reopened") or 0), "ts": float(row.get("ts") or 0),
                                   "seen": {float(row.get("ts") or 0)}, "value": row.get("value") or "",
                                   "link": row.get("link") or "", "opened_at": row.get("opened_at") or self.now()}
            self.last_ts = max(self.last_ts, float(row.get("ts") or 0))
        elif kind == "mail":
            mails[int(row.get("mid") or 0)] = row
        elif kind == "mark":
            marks[row.get("kind") or ""] = float(row.get("at_epoch") or 0)

    def _restore(self, mails, marks):
        now = self.now()
        self.mid = max(list(mails) or [0])
        self.pending, self.sent_at = [], []
        for mid in sorted(mails):
            row = mails[mid]
            at = float(row.get("at_epoch") or 0)
            if row.get("sent"):
                self.sent_at.append(at)
                continue
            # 재기동 = 한 번 더 시도할 수 있게 한 칸만 남긴다(시도 2회 상한 그대로 · 끝없는 재시도 0)
            self.pending.append({"mid": mid, "kind": row.get("kind") or "", "ids": list(row.get("ids") or []),
                                 "due": now, "extra": row.get("extra") or "", "tries": MAX_TRIES - 1})
        for inc in self.inc.values():
            if inc["closed_at"] is not None and inc["sent"] and not inc["reopened"] \
                    and not self._has_mail("close", inc["id"], mails):
                self.mid += 1
                self.pending.append({"mid": self.mid, "kind": "close", "ids": [inc["id"]],
                                     "due": max(float(inc["closed_at"]) + HOLD_S, now), "extra": ""})
        for name in ("overflow", "unreadable", "밀림"):
            if name in marks:
                self.once[name] = marks[name]

    def _has_mail(self, kind, inc_id, mails):
        return any(row.get("kind") == kind and inc_id in (row.get("ids") or []) for row in mails.values())

    def start(self):
        self.last_start = self.now()
        self.prepare()
        self._spawn()

    def _spawn(self):
        self.last_start = self.now()
        self.stopping.clear()
        self.worker = threading.Thread(target=self._loop, name="alert-intake", daemon=True)
        self.worker.start()

    def _loop(self):
        while not self.stopping.is_set():
            try:
                item = self.queue.get(timeout=1)
            except queue.Empty:
                item = None
            self._work(item)

    def stop(self, timeout=5.0):
        self.stopping.set()
        worker, self.worker = self.worker, None
        if worker is not None and worker is not threading.current_thread() and worker.is_alive():
            worker.join(timeout)

    def on_idle(self):
        """envelope 0 인 1초 — 일꾼 수명만 본다(입출력 0). 죽었으면 다시 띄우고 장부 1회 읽는다.

        같은 자리에서 늘 죽는 경우를 막으려고 재기동은 60초에 1회까지만 한다(장부 읽기 폭주 0).
        """
        if not self.enabled:
            return
        if self.worker is not None and self.worker.is_alive():
            return
        if self.now() - self.last_start < RESTART_GAP:
            return
        self.log("경보 일꾼 죽음 · 다시 띄움 + 장부로 마감 표 재구성")
        self.start()

    def tick(self):
        """일꾼 1회분(시험·루프 공용) — 큐 1개 + 마감 지난 것."""
        try:
            item = self.queue.get_nowait()
        except queue.Empty:
            item = None
        self._work(item)

    def _work(self, item):
        if item is not None:
            if item[0] == "event":
                self._event(item[1])
            elif item[0] == "history":
                self._history(item[1], item[2])
        self._expire(self.now())

    # ── 판독·장부
    def _history(self, rows, more):
        for row in sorted(rows, key=lambda r: float(r.get("ts") or 0)):
            self._event(row)
        if more:
            self._once("밀림", "재연결 history 1쪽 넘침 = 밀림")

    def _event(self, event):
        ts = str(event.get("ts") or "")
        got = parse(event) if ts else {}
        if not got or not (got["policy"] and got["id"] and got["state"]):
            if ts:
                self._once("unreadable", "판독 불가 글 %s" % ts)
            return
        stamp = float(ts)
        self.last_ts = max(self.last_ts, stamp)
        inc = self.inc.get(got["id"])
        if inc is None:
            return self._new(got, stamp)
        if stamp in inc["seen"]:
            return  # 같은 event 재전달(Socket 재전달·Backfill 재생) = 쪽지 0
        inc["seen"].add(stamp)
        inc["ts"] = stamp
        if got["state"] == "닫힘":
            return self._close(inc)
        inc["count"] += 1
        self._write_inc(inc)
        if inc["count"] - 1 >= STALE_N and not inc["stale"]:
            inc["stale"] = True
            self._write_inc(inc)
            self._intent("stale", [inc["id"]], self.now())

    def _new(self, got, stamp):
        now = self.now()
        prior = self._fold_target(got["policy"], now)
        inc = {"id": got["id"], "policy": got["policy"], "count": 1, "sent": False, "prev": "",
               "closed_at": None, "stale": False, "reopened": 0, "ts": stamp, "seen": {stamp},
               "value": got["value"], "link": got["link"], "opened_at": now}
        if prior is not None:  # 흔들림 접기 — 앞 사건 닫힘 30분 안 같은 정책 새 id
            inc.update(sent=prior["sent"], prev=prior["id"], count=prior["count"])
            prior["reopened"] += 1
            self._write_inc(prior)
            self._cancel("close", prior["id"])
        self.inc[inc["id"]] = inc
        if got["state"] == "닫힘":
            inc["closed_at"] = now
            return self._write_inc(inc)
        self._write_inc(inc)
        if prior is not None:
            return inc  # 접힌 새 id = 쪽지 0
        self._queued_new(inc, now)

    def _queued_new(self, inc, now):
        """새 사건 = 바로 1통 · 5분 창에 3개 넘게 오면 넘친 것만 창 끝 1통."""
        if self.window_start is None or now - self.window_start >= WINDOW_S:
            self.window_start, self.window_ids = now, []
        self.window_ids.append(inc["id"])
        if len(self.window_ids) <= FOLD_N:
            self._intent("new", [inc["id"]], now)
        else:
            self.held.append(inc["id"])
        return inc

    def _fold_target(self, policy, now):
        for inc in self.inc.values():
            if inc["policy"] == policy and inc["closed_at"] is not None and now - inc["closed_at"] <= HOLD_S:
                return inc
        return None

    def _close(self, inc):
        now = self.now()
        inc["closed_at"] = now
        self._write_inc(inc)
        if inc["sent"]:
            self._intent("close", [inc["id"]], now + HOLD_S)

    def _write_inc(self, inc):
        self._write({"t": "inc", "id": inc["id"], "policy": inc["policy"], "count": inc["count"],
                     "sent": inc["sent"], "prev": inc["prev"], "closed_at": inc["closed_at"],
                     "stale": inc["stale"], "reopened": inc["reopened"], "ts": inc["ts"],
                     "value": inc["value"], "link": inc["link"], "opened_at": inc["opened_at"]})
        return inc

    def _write(self, row):
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        line = (json.dumps(dict(row, at=self.clock(), at_epoch=self.now()), ensure_ascii=False,
                           sort_keys=True) + "\n").encode("utf-8")
        fd = os.open(self.path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o644)
        try:
            os.write(fd, line)
            os.fsync(fd)
        finally:
            os.close(fd)
        self.stats["write"] += 1
        self.writers.add(threading.get_ident())

    # ── 마감 표
    def _intent(self, kind, ids, due, extra=""):
        self.mid += 1
        self.pending.append({"mid": self.mid, "kind": kind, "ids": list(ids), "due": float(due), "extra": extra})

    def _cancel(self, kind, inc_id):
        self.pending = [m for m in self.pending if not (m["kind"] == kind and inc_id in m["ids"])]

    def _once(self, name, why, count=1):
        now = self.now()
        if now - self.once.get(name, 0) < (UNREADABLE_S if name == "unreadable" else HOUR_S):
            return
        self.once[name] = now
        self._write({"t": "mark", "kind": name, "count": count})
        self._intent("unreadable" if name == "unreadable" else name, [], now, extra=why)

    def _expire(self, now):
        if self.overflow:
            count, self.overflow = self.overflow, 0
            self._once("overflow", "큐 가득 %d건 = 받기 넘침" % count, count)
        if self.window_start is not None and now - self.window_start >= WINDOW_S:
            if self.held:
                self._intent("bundle", list(self.held), now)
            self.held, self.window_start, self.window_ids = [], None, []
        hour = now - now % HOUR_S
        if self.capped is not None and self.capped != hour and self.pending:
            merged = [m for m in self.pending if m["kind"] in ("new", "bundle")]
            if merged:
                ids = [inc_id for m in merged for inc_id in m["ids"]]
                self.pending = [m for m in self.pending if m["kind"] not in ("new", "bundle")]
                self._intent("bundle", ids, now, extra="지난 시간 상한 넘침 · 다음 정시 첫 통")
            self.capped = None
        self._flush(now)

    def _flush(self, now):
        hour = now - now % HOUR_S
        sent = len([at for at in self.sent_at if at >= hour])
        for intent in sorted([m for m in self.pending if m["due"] <= now], key=lambda m: (m["due"], m["mid"])):
            if sent >= HOUR_MAX:
                self.capped = hour
                break
            if self._send_intent(intent, now, sent + 1 == HOUR_MAX):
                sent += 1

    def _send_intent(self, intent, now, cap):
        """쪽지 1통 = 시도 2회까지. 둘 다 실패 = «발송 멈춤» 장부 1줄 + log 1(다음 기동 때 1회만 더)."""
        intent["tries"] = int(intent.get("tries") or 0) + 1
        body, tries = self._body(intent, cap), intent["tries"]
        self._write({"t": "mail", "mid": intent["mid"], "kind": intent["kind"], "ids": intent["ids"],
                     "sent": False, "tries": tries, "extra": intent["extra"]})
        rc = self._call(body)
        self._write({"t": "mail", "mid": intent["mid"], "kind": intent["kind"], "ids": intent["ids"],
                     "sent": rc == 0, "rc": rc, "tries": tries, "extra": intent["extra"]})
        if rc != 0 and tries < MAX_TRIES:
            intent["due"] = now + RETRY_S
            self.log("쪽지 실패 %s rc=%s · %d초 뒤 한 번 더" % (intent["kind"], rc, RETRY_S))
            return False
        if rc != 0:  # 두 번 실패 = 멈춘다(끝없는 재시도 0 · 다음 기동 때 1회)
            self.pending.remove(intent)
            self._write({"t": "mark", "kind": "발송 멈춤", "count": tries, "mid": intent["mid"]})
            self.log("쪽지 발송 멈춤 %s · 시도 %d회 실패 · 다음 기동까지 그대로" % (intent["kind"], tries))
            return False
        self.pending.remove(intent)
        self.sent_at.append(now)
        for inc_id in intent["ids"]:
            inc = self.inc.get(inc_id)
            if inc is not None and not inc["sent"]:
                inc["sent"] = True
                self._write_inc(inc)
        return True

    def _call(self, body):
        self.stats["send"] += 1
        try:
            return self.send(self.to, SENDER, body)
        except subprocess.TimeoutExpired:
            return -1
        except OSError:
            return -1

    def _mbox(self, to, sender, body):
        """mbox send 1회 — 7초 상한 · 재시도 0(다시 보내는 몫은 마감 표)."""
        try:
            done = subprocess.run(self.argv + ["send", to, sender, body], capture_output=True, timeout=self.send_s)
        except subprocess.TimeoutExpired:
            return -1
        return done.returncode

    def _body(self, intent, cap):
        kind, ids = intent["kind"], intent["ids"]
        lines = ["[r2337 경보 · %s] %s %d — %s" % (self.team, HEAD.get(kind, kind), max(len(ids), 1), self.clock())]
        if intent.get("extra"):
            lines.append("사유: %s" % intent["extra"])
        for inc_id in ids:
            inc = self.inc.get(inc_id) or {}
            when = time.strftime("%m-%d %H:%M", time.localtime(float(inc.get("opened_at") or self.now())))
            if kind in ("new", "bundle"):
                lines.append("· 새 사건 %s · 정책 %s · 값 %s · 시각 %s · 링크 %s · 제안 팀 %s"
                             % (inc_id, inc.get("policy") or "-", inc.get("value") or "-", when,
                                inc.get("link") or "-", self.suggest))
            elif kind == "close":
                lines.append("· 닫힘 %s · 정책 %s · 닫힘 시각 %s" % (inc_id, inc.get("policy") or "-", when))
            elif kind == "stale":
                lines.append("· 오래 열림 %s · 정책 %s · 재알림 %d회" % (inc_id, inc.get("policy") or "-",
                                                                     int(inc.get("count") or 1) - 1))
        if cap:
            lines.append("상한 닿음: 이 시간 쪽지 %d통 상한 · 넘침은 다음 정시 첫 통" % HOUR_MAX)
        return "\n".join(lines)
