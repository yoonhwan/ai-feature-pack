"""r2337 GCP 경보 좌석 수신 — 반례 ①~㉒(④b · ④c) + 변이 M1~M10 (기준판 ① = Red).

경보 글 = Slack 대역 글 1건 · 쪽지 = 가짜 send 1회 · 장부 = tmp 의 incidents.jsonl · 실 Slack·실 mbox·sleep 0.
⑯⑱⑬(history 갈래)만 Socket 상주 루프를 대역 ws·대역 Web 으로 돌린다. 단계별 초 = 시험 파일 끝 요약.
"""
import importlib.util, json, os, shutil, subprocess, threading, time  # noqa: E401
import pytest
from websockets.sync.server import serve

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEAM, CH, HUMAN = "harness", "C0CKHQHB6V8", "UOPPA"   # 채널 = #byz-gcp-alerts
APP, BOT, TO = "A03EA2WU3", "B0CKL07QS5P", "byz-issues-master#0"   # GCP Monitoring 앱 고정값 · issues master
INC = "0.of8egtef5beq"   # 실측 사건 id(a493 gcp-hist.json)
POLICY = "[TEST r2337] byz-redis memory &gt; 0 시험"   # 링크 이름 칸 · escape 그대로

# 실측 원문(a493 · arch #354564) — text 한 줄이 정본 · attachments 0 · blocks 같은 글자
_HEAD = ('*<https://console.cloud.google.com/monitoring/alerting/alerts/' + INC + '?channelType=slack&amp;project=byz-agents-484214|'
         + POLICY + '>* Memory Usage Ratio for byz-agents-484214 Cloud Memorystore Redis Instance labels '
         '{project_id=byz-agents-484214, region=asia-northeast3, instance_id=projects/byz-agents-484214/locations/asia-northeast3/'
         'instances/byz-agents-redis-dev, node_id=node-0} with metric labels {role=primary} ')
_TAIL = ' No severity '
_LINK_VIEW = ('*<https://console.cloud.google.com/monitoring/alerting/alerts/' + INC + '?channelType=slack&amp;'
              'project=byz-agents-484214|View alert>*')
OPEN_TEXT = _HEAD + 'is above the threshold of 0.000 with a value of 0.313. Alert status Alert open' + _TAIL \
    + '*Documentation* r2337 시험 경보 · 열림 1 · 닫힘 1 확인용 · 끝나면 지움(ops h) ' + _LINK_VIEW
CLOSE_TEXT = _HEAD + 'returned to normal with a value of 0.313. Alert status Alert closed' + _TAIL + _LINK_VIEW
HELLO = {"type": "hello", "num_connections": 1}


# ── 대역(시계·쪽지·글)
class Clock:
    def __init__(self, start=1800000000.0):
        self.t = float(start)

    def now(self):
        return self.t

    def iso(self):
        return time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(self.t))

    def go(self, seconds):
        self.t += float(seconds)


class Sender:
    """가짜 send — 적고 rc 를 돌려준다. slow = 처리 가짜 초(시계만 감는다) · timeout = 9초 뒤 끊김."""

    def __init__(self, clock, fails=(), slow=0.0, timeout=False):
        self.clock, self.fails, self.slow, self.timeout = clock, list(fails), float(slow), timeout
        self.notes, self.tries = [], []

    def __call__(self, to, sender, body):
        if self.timeout:
            self.clock.go(9)
            raise subprocess.TimeoutExpired("mbox", 7)
        self.tries.append(body)
        if self.slow:
            self.clock.go(self.slow)
        rc = self.fails.pop(0) if self.fails else 0
        if rc == 0:  # 도착한 쪽지만 센다(실패 = «발송 안 됨»)
            self.notes.append({"to": to, "sender": sender, "body": body})
        return rc


def post(ts, inc=INC, state="열림", policy=POLICY, channel=CH, app=APP, bot=BOT, text=None, blocks=False):
    """실측 원문 꼴 그대로 — id·정책·상태 글자만 바꿔 쓴다(text= 로 꼴 다른 글도 넣는다)."""
    body = (OPEN_TEXT if state == "열림" else CLOSE_TEXT).replace(INC, inc).replace(POLICY, policy)
    if text is not None:
        body = text.replace(INC, inc).replace(POLICY, policy)
    event = {"type": "message", "team": "TFAKE", "channel": channel, "ts": ts, "user": "U0GCPMON",
             "subtype": "bot_message", "app_id": app, "bot_id": bot, "username": "Google Cloud Monitoring",
             "text": body}
    if blocks:  # 닫힘 원문의 blocks(같은 글자 · 판독은 text 로)
        event["blocks"] = [{"type": "section", "text": {"type": "mrkdwn", "text": body.split(" Memory Usage", 1)[0]}},
                           {"type": "context", "elements": [{"type": "image", "alt_text": "Alert status"},
                                                            {"type": "plain_text",
                                                             "text": "Alert closed" if state == "닫힘" else "Alert open"}]}]
    return event


def human(ts, channel=CH):
    return {"type": "message", "team": "TFAKE", "channel": channel, "ts": ts, "user": HUMAN, "text": "사람 글"}


def _load(base, rel, tag):
    spec = importlib.util.spec_from_file_location("r2337_%s_%s" % (tag, os.path.basename(rel)), os.path.join(base, rel))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


M = _load(FT2, "adapters/slack/alert_intake.py", "base")
RE = _load(FT2, "adapters/slack/receive.py", "base")
SOCK = None


def sock_module(base=FT2):
    return _load(base, "adapters/slack/socket.py", "sock")


def conf(**extra):
    return dict({"channels": [CH], "app_id": APP, "bot_id": BOT, "to": TO, "suggest": "harness"}, **extra)


def make(tmp, mod=M, clock=None, sender=None, **kw):
    clock = clock or Clock()
    sender = sender if sender is not None else Sender(clock)
    kw.setdefault("conf", conf())
    opened = mod.AlertIntake(str(tmp), team=TEAM, send=sender, now=clock.now, clock=clock.iso, **kw)
    return opened, clock, sender


def pump(m, clock, seconds=0.0, step=1.0):
    """큐를 비우고 마감 지난 것을 처리 — 시계를 step 씩 감으며 tick(실 sleep 0)."""
    end = clock.t + float(seconds)
    while True:
        m.tick()
        if not m.queue.empty():
            continue
        if clock.t >= end:
            break
        clock.t = min(end, clock.t + step)
    m.tick()


def rows(tmp):
    path = os.path.join(str(tmp), ".fable-team", "state", "alert-intake", "incidents.jsonl")
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip()]


def incs(tmp):
    return [r for r in rows(tmp) if r.get("t") == "inc"]


def inc_of(tmp, inc_id=INC):
    found = [r for r in incs(tmp) if r["id"] == inc_id]
    return found[-1] if found else {}


def notes(sender):
    return [n["body"] for n in sender.notes]


# ── 반례
def case_01(tmp, mod=M):
    """① 새 사건 열림 글 1 → 쪽지 1 · 사건 1줄."""
    m, clock, sender = make(tmp, mod)
    assert m.feed(post("1700000001.000100")) is True
    pump(m, clock)
    assert len(notes(sender)) == 1
    assert sender.notes[0]["to"] == TO and sender.notes[0]["sender"] == "ft2-alert-intake"
    body = notes(sender)[0]
    assert "새 사건" in body and INC in body and "제안 팀 harness" in body
    # 실측 꼴 판독 확인 — 정책 = 링크 이름 칸(escape 그대로) · 값 = «with a value of»
    assert POLICY in body and "값 0.313" in body and INC in (inc_of(tmp)["link"] or "")
    assert {r["id"] for r in incs(tmp)} == {INC} and inc_of(tmp)["sent"] is True
    assert inc_of(tmp)["policy"] == POLICY and inc_of(tmp)["value"] == "0.313"


def case_02(tmp, mod=M):
    """② 같은 사건 재알림 글 2 → 쪽지 0 · 횟수 3."""
    m, clock, sender = make(tmp, mod)
    for n, ts in enumerate(("1700000001.000100", "1700000002.000100", "1700000003.000100")):
        assert m.feed(post(ts)) is True
        clock.go(10)
        pump(m, clock)
    assert len(notes(sender)) == 1  # 열림 글 1통뿐
    assert inc_of(tmp)["count"] == 3


def case_03(tmp, mod=M):
    """③ 닫힘 글 → 그때 0 · 30분 지난 루프 «닫힘» 1통."""
    m, clock, sender = make(tmp, mod)
    m.feed(post("1700000001.000100"))
    pump(m, clock)
    m.feed(post("1700000101.000100", state="닫힘", blocks=True))  # 닫힘 원문 = blocks 동봉(같은 글자)
    pump(m, clock)
    assert len(notes(sender)) == 1 and inc_of(tmp)["closed_at"] is not None
    pump(m, clock, 1799)
    assert len(notes(sender)) == 1
    pump(m, clock, 2)
    assert len(notes(sender)) == 2 and "닫힘" in notes(sender)[1]


def _folded(tmp, mod=M):
    """④ 준비 — A 닫힘 20분 뒤 같은 정책 새 id B."""
    m, clock, sender = make(tmp, mod)
    m.feed(post("1700000001.000100"))
    pump(m, clock)
    m.feed(post("1700000061.000100", state="닫힘"))
    pump(m, clock)
    clock.go(1200)
    m.feed(post("1700000161.000100", inc="0.beef000011112222"))
    pump(m, clock)
    return m, clock, sender


def case_04(tmp, mod=M):
    """④ 닫힘 20분 뒤 같은 정책 새 사건 → 쪽지 0 · «다시 열림 1» · 새 id 줄 1."""
    m, clock, sender = _folded(tmp, mod)
    assert len(notes(sender)) == 1  # 열림 글 1통뿐(닫힘·재열림 0)
    assert inc_of(tmp)["reopened"] == 1
    new = inc_of(tmp, "0.beef000011112222")
    assert new["prev"] == INC and new["sent"] is True
    pump(m, clock, 1800)
    assert len(notes(sender)) == 1  # 앞 닫힘 통보 취소


def case_04b(tmp, mod=M):
    """④b ④의 접힌 새 id 재알림 3회 → «오래 열림» 1통."""
    m, clock, sender = _folded(tmp, mod)
    for step in (1, 2, 3):
        m.feed(post("1700000%d61.000100" % (3 + step), inc="0.beef000011112222"))
        clock.go(10)
        pump(m, clock)
    assert len(notes(sender)) == 2 and "오래 열림" in notes(sender)[1]
    m.feed(post("1700000961.000100", inc="0.beef000011112222"))
    pump(m, clock)
    assert len(notes(sender)) == 2  # 4회째 0


def case_04c(tmp, mod=M):
    """④c ④의 접힌 새 id 닫힘 → 그때 0 · 30분 뒤 «닫힘» 1통."""
    m, clock, sender = _folded(tmp, mod)
    m.feed(post("1700000261.000100", inc="0.beef000011112222", state="닫힘"))
    pump(m, clock)
    assert len(notes(sender)) == 1
    pump(m, clock, 1799)
    assert len(notes(sender)) == 1
    pump(m, clock, 2)
    assert len(notes(sender)) == 2 and "닫힘" in notes(sender)[1]


def case_05(tmp, mod=M):
    """⑤ 닫힘 40분 뒤 같은 정책 새 사건 → 쪽지 1."""
    m, clock, sender = make(tmp, mod)
    m.feed(post("1700000001.000100"))
    pump(m, clock)
    m.feed(post("1700000061.000100", state="닫힘"))
    pump(m, clock)
    pump(m, clock, 2400)  # 닫힘 통보 1통
    assert len(notes(sender)) == 2
    m.feed(post("1700002461.000100", inc="0.beef000011112222"))
    pump(m, clock)
    assert len(notes(sender)) == 3 and "새 사건" in notes(sender)[2]


def case_06(tmp, mod=M):
    """⑥ 5분 안 새 사건 5 → 묶음 쪽지 1(창 끝) · 앞 3 = 바로 1통씩."""
    m, clock, sender = make(tmp, mod)
    for i in range(5):
        m.feed(post("17000000%02d.000100" % (1 + i), inc="0.inc%d" % i))
        clock.go(10)
        pump(m, clock)
    assert len(notes(sender)) == 3  # 창 안 첫 3 = 바로
    pump(m, clock, 300)
    assert len(notes(sender)) == 4 and "묶음 새 사건" in notes(sender)[3]
    assert all(inc_id in notes(sender)[3] for inc_id in ("0.inc3", "0.inc4"))


def case_07(tmp, mod=M):
    """⑦ 한 시간 새 사건 9 → 쪽지 6(6번째 끝 «상한 닿음») · 남은 3 = 다음 정시 첫 통."""
    clock = Clock(1800000000.0 - (1800000000.0 % 3600) + 10)
    m, clock, sender = make(tmp, mod, clock=clock)
    for i in range(9):
        m.feed(post("1700000%03d.000100" % (i * 360), inc="0.inc%d" % i))
        clock.go(360)
        pump(m, clock)
    assert len(notes(sender)) == 6 and "상한 닿음" in notes(sender)[5]
    clock.t = clock.t - (clock.t % 3600) + 3600 + 5  # 다음 정시
    pump(m, clock, 5)
    assert len(notes(sender)) == 7 and "지난 시간 상한 넘침" in notes(sender)[6]


def case_08(tmp, mod=M):
    """⑧ 다른 앱 bot · 사람 글 · 경보 채널 밖 → 갈래 0 · receive 결과 지금과 같음 · 장부·쪽지 0."""
    m, clock, sender = make(tmp, mod)
    assert m.feed(post("1700000001.000100", app="A0OTHER")) is False
    assert m.feed(post("1700000002.000100", bot="B0OTHER")) is False
    assert m.feed(human("1700000003.000100")) is False
    assert m.feed(post("1700000004.000100", channel="COTHER")) is False
    rx = RE.SlackReceive(str(tmp), ack=lambda e: None, team=TEAM, allowed_users=(HUMAN,), allowed_channels=(CH,),
                         bot_users=(BOT,), alert=m.feed)
    assert rx.handle(post("1700000001.000100", app="A0OTHER"))["state"] == "ignored"  # receive 결과 그대로
    assert m.feed(post("1700000007.000100")) is True and rx.handle(post("1700000007.000100"))["state"] == "ignored"
    pump(m, clock)
    assert len(notes(sender)) == 1 and {r["id"] for r in incs(tmp)} == {INC}  # 경보 글 1건만 갈래
    assert mod.load_config(str(tmp), TEAM) is None  # 설정 파일 없음 = 갈래 0
    off = mod.AlertIntake(str(tmp), team=TEAM, conf=None, send=sender, now=clock.now, clock=clock.iso)
    assert off.enabled is False and off.feed(post("1700000008.000100")) is False


def case_09(tmp, mod=M):
    """⑨ 꼴 다른 경보 글 → «판독 불가 글» 1통 · 같은 시간 둘째 = 0."""
    m, clock, sender = make(tmp, mod)
    m.feed(post("1700000001.000100", text="*<https://console.cloud.google.com/monitoring/alerting/alerts/?project=x|"
                "꼴 다른 글>* Alert status Alert open"))  # 사건 id 없음
    pump(m, clock)
    assert len(notes(sender)) == 1 and "판독 불가" in notes(sender)[0]
    clock.go(60)
    m.feed(post("1700000002.000100", text="[FIRING] 또 꼴 다름"))
    pump(m, clock)
    assert len(notes(sender)) == 1


def case_10(tmp, mod=M):
    """⑩ 같은 event 두 번 전달(Socket 재전달·Backfill 재생) → 쪽지 1(중복 0)."""
    m, clock, sender = make(tmp, mod)
    one = post("1700000001.000100")
    m.feed(one), m.feed(dict(one))
    pump(m, clock)
    assert len(notes(sender)) == 1 and inc_of(tmp)["count"] == 1


def case_11(tmp, mod=M):
    """⑪ 재알림 3회 → «오래 열림» 1통 · 4회째 = 0."""
    m, clock, sender = make(tmp, mod)
    m.feed(post("1700000001.000100"))
    pump(m, clock)
    for n in range(3):
        m.feed(post("17000000%d1.000100" % (2 + n)))
        clock.go(10)
        pump(m, clock)
    assert len(notes(sender)) == 2 and "오래 열림" in notes(sender)[1]
    m.feed(post("1700000091.000100"))
    pump(m, clock)
    assert len(notes(sender)) == 2


def case_12(tmp, mod=M):
    """⑫ 새 사건 send rc≠0 → 그때 0 · 다음 마감 루프 1통(유실 0 · 중복 0)."""
    clock = Clock()
    m, clock, sender = make(tmp, mod, clock, Sender(clock, fails=[1]))
    m.feed(post("1700000001.000100"))
    pump(m, clock)
    assert len(notes(sender)) == 0 and inc_of(tmp)["sent"] is False
    clock.go(61)
    pump(m, clock)
    assert len(notes(sender)) == 1 and inc_of(tmp)["sent"] is True
    pump(m, clock, 300)
    assert len(notes(sender)) == 1  # 중복 0


LEG = {"t": "inc", "id": INC, "policy": "dev Redis 메모리", "count": 1, "sent": True, "prev": "",
       "closed_at": None, "stale": False, "reopened": 0, "ts": 1700000001.0001, "value": "92% > 85%",
       "link": "", "opened_at": 1700000000.0}


def _legacy(tmp, clock, mails, extra=()):
    """장부를 손으로 만든다 — 재시작 사건(⑬)용."""
    os.makedirs(os.path.join(str(tmp), ".fable-team", "state", "alert-intake"), exist_ok=True)
    path = os.path.join(str(tmp), ".fable-team", "state", "alert-intake", "incidents.jsonl")
    with open(path, "w", encoding="utf-8") as handle:
        for row in list(extra) + mails:
            handle.write(json.dumps(dict(row, at="2026-11-20T00:00:00", at_epoch=clock.t), ensure_ascii=False) + "\n")


def case_13(tmp, mod=M):
    """⑬ 재시작 — 보류 닫힘 1 · 미발송 1 · 이 시간 쪽지 5통 · 판독 불가 1통을 장부에서 다시 만든다."""
    clock = Clock(1800000000.0 - 1800000000.0 % 3600 + 600)
    os.makedirs(os.path.join(str(tmp), ".fable-team", "state", "alert-intake"), exist_ok=True)
    path = os.path.join(str(tmp), ".fable-team", "state", "alert-intake", "incidents.jsonl")
    closed, unsent = dict(LEG, id="0.closed0001"), dict(LEG, id="0.unsent0001", sent=False)
    mails = [{"t": "mail", "mid": i, "kind": "new", "ids": ["0.sent%04d" % i], "sent": True, "at_epoch": clock.t - 60}
             for i in range(1, 6)]
    mails += [{"t": "mail", "mid": 6, "kind": "new", "ids": ["0.unsent0001"], "sent": False, "at_epoch": clock.t - 30}]
    marks = [{"t": "mark", "kind": "unreadable", "count": 1, "at_epoch": clock.t - 300}]
    with open(path, "w", encoding="utf-8") as handle:
        for row in [dict(LEG), dict(closed, closed_at=clock.t - 1900), dict(unsent)] + mails + marks:
            handle.write(json.dumps(dict(row, at="2026-11-20T00:00:00"), ensure_ascii=False) + "\n")
    sender = Sender(clock)
    m = mod.AlertIntake(str(tmp), team=TEAM, conf=conf(), send=sender, now=clock.now, clock=clock.iso)
    m.prepare()
    assert m.stats["read"] >= 1 and sorted(x["kind"] for x in m.pending) == ["close", "new"]
    pump(m, clock)
    assert len(notes(sender)) == 1 and "상한 닿음" in notes(sender)[0]  # 이 시간 6번째
    m.feed(post("1700000002.000100", text="[FIRING] 꼴 다름 — 판독 불가"))
    pump(m, clock)
    assert len(notes(sender)) == 1  # 판독 불가 둘째 = 0(첫 통은 이 시간 이미 감)
    pump(m, clock, 3601)  # 다음 시간 = 남은 보류 닫힘 1통 · 판독 불가 1시간 셈도 풀림
    assert len(notes(sender)) == 2 and "닫힘" in notes(sender)[1]
    m.feed(post("1700000003.000100", text="[FIRING] 꼴 다름 둘째 시간"))
    pump(m, clock)
    assert len(notes(sender)) == 3 and "판독 불가" in notes(sender)[2]


def case_14(tmp, mod=M):
    """⑭ 이벤트 0 인 1시간 → 장부 쓰기 0 · 읽기 0 · 쪽지 0·Web 호출 0."""
    m, clock, sender = make(tmp, mod)
    m.feed(post("1700000001.000100"))
    pump(m, clock)
    before = (m.stats["write"], m.stats["read"], len(notes(sender)))
    for _ in range(3600):
        clock.go(1)
        m.tick()
    assert (m.stats["write"], m.stats["read"], len(notes(sender))) == before


def case_15(tmp, mod=M):
    """⑮ 열림 글 유실 뒤 처음 온 글이 같은 id 재알림 → 새 사건 쪽지 1."""
    m, clock, sender = make(tmp, mod)
    m.feed(post("1700000001.000100"))  # 열림 글 = 한 번도 못 본 사건 id(끊김 동안 유실)
    pump(m, clock)
    assert len(notes(sender)) == 1 and "새 사건" in notes(sender)[0]


class Band:
    """대역 — ws 서버(연결마다 대본 1개) + Web API(호출 계수 · history 는 oldest 뒤 글만)."""

    def __init__(self, scripts, alert_rows):
        self.scripts, self.alert_rows, self.calls, self.oldest = list(scripts), list(alert_rows), [], []
        self.fail_history = 0  # 첫 호출 실패 횟수(재시도 1 확인용)
        self.server = serve(self._handler, "127.0.0.1", 0)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.url = "ws://127.0.0.1:%d" % self.server.socket.getsockname()[1]

    def _handler(self, ws):
        for frame in (self.scripts.pop(0) if self.scripts else []):
            ws.send(json.dumps(frame))
            if frame.get("envelope_id") or frame.get("type") == "hello":
                ws.recv(timeout=10) if frame.get("envelope_id") else None

    def web(self, method, token, params=None, retry=True, **budget):
        self.calls.append(method)
        if method == "apps.connections.open":
            return {"ok": True, "url": self.url}
        if method == "conversations.history":
            if self.fail_history:
                self.fail_history -= 1
                raise RuntimeError("slack_down")
            oldest = float((params or {}).get("oldest") or 0)
            self.oldest.append(oldest)
            return {"ok": True, "has_more": False,
                    "messages": [r for r in self.alert_rows if float(r["ts"]) > oldest]}
        if method == "users.conversations":
            return {"ok": True, "channels": []}
        return {"ok": True, "messages": [], "has_more": False}

    def close(self):
        self.server.shutdown()


@pytest.fixture
def band_of():
    made = []

    def make_band(scripts, rows=()):
        made.append(Band(scripts, rows))
        return made[-1]

    yield make_band
    for band in made:
        band.close()


def _listen(sock, tmp, band, alert, channel=CH):
    return sock.Listener(str(tmp), channel=channel, app_token="xapp-FAKE", bot_token="xoxb-FAKE",
                         master="byz-harness-master#0", users=(HUMAN,), bot_users=(BOT,), web=band.web,
                         sleep=lambda seconds: None, mono=lambda: 0.0, clock=lambda: "2026-11-20T00:00:00",
                         alert=alert)


def _config(tmp):
    path = os.path.join(str(tmp), ".fable-team", "teams", TEAM, "slack", "ALERT_INTAKE.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(json.dumps(conf()))


def _seed(tmp, mod=M, ts="1700000001.000100"):
    m, clock, sender = make(tmp, mod)
    m.feed(post(ts))
    pump(m, clock)
    return m, sender, clock


def _manual(mod, tmp, clock):
    """일꾼 스레드 없이 손으로 tick 하는 갈래(⑯⑱ · Socket 루프만 돌린다)."""
    opened = mod.AlertIntake(str(tmp), team=TEAM, conf=conf(), send=Sender(clock), now=clock.now, clock=clock.iso)
    opened._spawn = lambda: None
    return opened


def case_16(tmp, mod=M, band_of=None, base=FT2):
    """⑯ 끊김 동안 닫힘 글 1 · 새 열림 글 1 → 재연결 hello 뒤 history 1쪽 → 닫힘 반영 · 새 사건 1통."""
    _config(tmp)
    seed, _sender, clock = _seed(tmp, mod)
    sock, alert = sock_module(base), None
    alert = _manual(mod, tmp, clock)
    band = band_of([[HELLO, {"type": "disconnect", "reason": "refresh"}], [HELLO]],
                   [post("1700000100.000100", state="닫힘"),
                    post("1700000101.000100", inc="0.beef000011112222", policy="[TEST r2337] byz-redis cpu &gt; 0 시험")])
    band.fail_history = 1  # 첫 호출 실패 → 재시도 1로 잇는다
    listener = _listen(sock, tmp, band, alert)
    assert listener.run(sessions=2) == 0
    assert band.calls.count("conversations.history") == 3  # 연결 2번 = 1쪽씩 + 재시도 1
    assert band.oldest[0] == pytest.approx(1700000001.0001)  # oldest = 장부 마지막 글 ts
    pump(alert, clock)
    assert inc_of(tmp)["closed_at"] is not None  # 끊김 동안 닫힘 반영
    assert inc_of(tmp, "0.beef000011112222")["sent"] is True
    assert len([r for r in rows(tmp) if r.get("t") == "mail" and r.get("sent")]) == 2  # 새 사건 1(중복 0)
    pump(alert, clock, 1800)
    assert any("닫힘" in body for body in notes(alert.send))
    assert band.calls.count("conversations.history") == 3  # 그 뒤 이벤트 0 = 호출 0


def case_17(tmp, mod=M):
    """⑰ send 가짜 9초 → 7초에 끊고 «발송 안 됨» · 수신 루프 다음 envelope 받음 · 다음 마감 1통."""
    clock = Clock()
    sender = Sender(clock, timeout=True)
    m, clock, sender = make(tmp, mod, clock, sender)
    m.feed(post("1700000001.000100"))
    m.feed(post("1700000002.000100", inc="0.beef000011112222"))
    pump(m, clock)
    assert notes(sender) == [] and m.stats["send"] >= 1
    assert inc_of(tmp)["sent"] is False and inc_of(tmp, "0.beef000011112222")["sent"] is False
    sender.timeout = False
    clock.go(61)
    pump(m, clock)
    assert len(notes(sender)) == 2


def case_18(tmp, mod=M, band_of=None, base=FT2):
    """⑱ 빈 장부 첫 기동 · 채널에 옛 열림 글 5 → history 보충 0 · 쪽지 0."""
    _config(tmp)
    sock = sock_module(base)
    old = [post("160000000%d.000100" % n, inc="0.old00000%d" % n) for n in range(5)]
    clock = Clock()
    alert = _manual(mod, tmp, clock)
    band = band_of([[HELLO]], old)
    assert _listen(sock, tmp, band, alert).run(sessions=1) == 0
    pump(alert, clock)
    assert band.calls.count("conversations.history") == 1 and band.oldest[0] == pytest.approx(clock.t)
    assert notes(alert.send) == [] and rows(tmp) == []  # 옛 열림 글 5 = 보충 0 · 쪽지 0


def case_19(tmp, mod=M):
    """⑲ 처리 가짜 5초 → 갈래 반환 0.1초 안 · 바로 다음 envelope · 처리 끝나면 쪽지 1."""
    clock = Clock()
    sender = Sender(clock, slow=5)
    m, clock, sender = make(tmp, mod, clock, sender)
    started = time.perf_counter()
    assert m.feed(post("1700000001.000100")) is True
    assert m.feed(post("1700000002.000100", inc="0.beef000011112222")) is True
    assert time.perf_counter() - started < 0.1  # 처리(5초)를 기다리지 않는다
    assert m.queue.qsize() == 2 and notes(sender) == []
    pump(m, clock)
    assert len(notes(sender)) == 2


def case_20(tmp, mod=M):
    """⑳ 큐 가득(상한 1000 자리에 2) → «받기 넘침» 장부 1줄 · 1시간 1통 · 수신 루프 막힘 0."""
    m, clock, sender = make(tmp, mod, queue_max=2)
    started = time.perf_counter()
    for n in range(5):
        m.feed(post("170000000%d.000100" % (n + 1), inc="0.inc%d" % n))
    assert time.perf_counter() - started < 0.1 and m.overflow == 3
    pump(m, clock)
    assert [r["kind"] for r in rows(tmp) if r.get("t") == "mark"] == ["overflow"]
    assert len(notes(sender)) == 3 and any("받기 넘침" in body for body in notes(sender))
    clock.go(60)
    for n in range(6, 11):  # 큐 다시 가득 = overflow 3
        m.feed(post("17000000%d1.000100" % n, inc="0.inc%d" % n))
    pump(m, clock)
    assert len([r for r in rows(tmp) if r.get("t") == "mark"]) == 1  # 장부 1줄 그대로
    assert len([body for body in notes(sender) if "받기 넘침" in body]) == 1  # 1시간 1통


def case_h1(tmp, mod=M):
    """H1(DA #354590) 쪽지 실패 = 시도 2회에서 멈춤 — 3시간 pump 도 시도 2 · mail 줄 ≤ 5 · 재기동 뒤 1회 더."""
    clock = Clock()
    sender = Sender(clock, fails=[1] * 5000)  # 늘 실패
    m, clock, sender = make(tmp, mod, clock, sender)
    m.feed(post("1700000001.000100"))
    pump(m, clock, 3 * 3600)
    assert len(sender.tries) == 2  # 끝없는 재시도 0(DA 재현 = 181회)
    assert len([r for r in rows(tmp) if r.get("t") == "mail"]) <= 5
    assert [r["kind"] for r in rows(tmp) if r.get("t") == "mark"] == ["발송 멈춤"]
    assert notes(sender) == [] and m.pending == []
    pump(m, clock, 3600)
    assert len(sender.tries) == 2  # 멈춘 뒤 시계만 흘러도 다시 안 보낸다
    restarted = mod.AlertIntake(str(tmp), team=TEAM, conf=conf(), send=sender, now=clock.now, clock=clock.iso)
    restarted.prepare()  # 수신기 재기동 = 한 번 더
    assert [x["kind"] for x in restarted.pending] == ["new"] and restarted.pending[0]["tries"] == 1
    pump(restarted, clock, 1800)
    assert len(sender.tries) == 3 and restarted.pending == []  # 재기동 뒤 1회 더 = 또 멈춤


class Dead:
    def is_alive(self):
        return False


def case_21(tmp, mod=M):
    """㉑ 일꾼 죽음 · 그 뒤 이벤트 0 → on_idle 에서 다시 띄움 · 장부로 마감 표 재구성 · 30분 뒤 «닫힘» 1통."""
    clock = Clock()
    sender = Sender(clock)
    m, clock, sender = make(tmp, mod, clock, sender)
    m.feed(post("1700000001.000100"))
    pump(m, clock)
    m.feed(post("1700000061.000100", state="닫힘"))
    pump(m, clock)
    assert len(notes(sender)) == 1 and inc_of(tmp)["closed_at"] is not None
    m.worker = Dead()  # 죽음
    spawned = []
    m._spawn = lambda: spawned.append(1)
    m.on_idle()
    assert spawned == [1] and sorted(x["kind"] for x in m.pending) == ["close"]
    clock.go(1799)
    pump(m, clock)
    assert len(notes(sender)) == 1
    pump(m, clock, 2)
    assert len(notes(sender)) == 2 and "닫힘" in notes(sender)[1]


def case_22(tmp, mod=M):
    """㉒ 큐 가득 · 재연결 history · 보통 이벤트가 섞임 → 장부를 쓴 스레드 = 일꾼 하나."""
    m, clock, sender = make(tmp, mod, queue_max=2)
    for n in range(4):
        m.feed(post("170000000%d.000100" % (n + 1), inc="0.inc%d" % n))
    m.ingest([post("1700000100.000100", inc="0.hist0001", state="닫힘")], more=True)
    m.feed(post("1700000009.000100", inc="0.inc9"))  # 큐 가득
    m.prepare()  # 읽기만(쓰기 0)

    def run():
        while True:
            try:
                item = m.queue.get_nowait()
            except Exception:
                break
            m._work(item)

    worker = threading.Thread(target=run)
    worker.start()
    worker.join()
    assert len(m.writers) == 1 and threading.get_ident() not in m.writers
    assert m.writers == {worker.ident}
    assert {r["kind"] for r in rows(tmp) if r.get("t") == "mark"} == {"overflow"}


def test_01_new_case_one_note(tmp_path):
    case_01(tmp_path)


def test_02_renotify_count_only(tmp_path):
    case_02(tmp_path)


def test_03_close_held_30_min(tmp_path):
    case_03(tmp_path)


def test_04_fold_new_id_quiet(tmp_path):
    case_04(tmp_path)


def test_04b_folded_renotify_3_stale(tmp_path):
    case_04b(tmp_path)


def test_04c_folded_close_30_min(tmp_path):
    case_04c(tmp_path)


def test_05_after_30_min_new_note(tmp_path):
    case_05(tmp_path)


def test_06_five_in_5_min_one_bundle(tmp_path):
    case_06(tmp_path)


def test_07_hour_cap_six(tmp_path):
    case_07(tmp_path)


def test_08_other_bot_human_outside_zero(tmp_path):
    case_08(tmp_path)


def test_09_unreadable_once_per_hour(tmp_path):
    case_09(tmp_path)


def test_10_same_event_twice_one_note(tmp_path):
    case_10(tmp_path)


def test_11_renotify_three_stale_once(tmp_path):
    case_11(tmp_path)


def test_12_send_fail_retry_next_deadline(tmp_path):
    case_12(tmp_path)


def test_13_restart_rebuild_deadline_table(tmp_path):
    case_13(tmp_path)


def test_14_quiet_hour_no_io(tmp_path):
    case_14(tmp_path)


def test_15_unknown_id_renotify_is_new(tmp_path):
    case_15(tmp_path)


def test_16_reconnect_history_once(tmp_path, band_of):
    case_16(tmp_path, M, band_of)


def test_17_send_timeout_7s(tmp_path):
    case_17(tmp_path)


def test_18_empty_ledger_no_backfill(tmp_path, band_of):
    case_18(tmp_path, M, band_of)


def test_19_fire_and_forget(tmp_path):
    case_19(tmp_path)


def test_20_queue_full_overflow(tmp_path):
    case_20(tmp_path)


def test_21_worker_dead_revive_rebuild(tmp_path):
    case_21(tmp_path)


def test_h1_send_retry_bounded(tmp_path):
    case_h1(tmp_path)


def case_restart_gate(tmp, mod=M):
    """메모(DA #354590) — 같은 자리에서 늘 죽어도 재기동은 60초에 1회(장부 읽기 폭주 0)."""
    m, clock, sender = make(tmp, mod)
    spawned, m._spawn = [], lambda: spawned.append(clock.t)
    m.worker = Dead()
    for _ in range(10):  # 1초 idle 10회 = 늘 죽어 있음
        clock.go(1)
        m.on_idle()
    assert len(spawned) == 1
    clock.go(60)
    m.on_idle()
    assert len(spawned) == 2


def test_restart_gate_60s(tmp_path):
    case_restart_gate(tmp_path)


def test_22_single_writer_thread(tmp_path):
    case_22(tmp_path)


# ── 변이 (사본에서만 · 변이마다 원본으로 같은 사례 1회 더)
MUTANTS = {
    "M1": ("adapters/slack/alert_intake.py", 'inc = self.inc.get(got["id"])', "inc = self.inc.get(ts)", case_02),
    "M2": ("adapters/slack/alert_intake.py", 'now - inc["closed_at"] <= HOLD_S', "False", case_04),
    "M3": ("adapters/slack/alert_intake.py", "if sent >= HOUR_MAX:", "if False:", case_07),
    "M4": ("adapters/slack/alert_intake.py", 'and str(event.get("app_id") or "") == self.app_id', "and True", case_08),
    "M5": ("adapters/slack/alert_intake.py", 'if stamp in inc["seen"]:', "if False:", case_10),
    "M6": ("adapters/slack/alert_intake.py", "self._apply(row, mails, marks)", "pass", case_13),
    "M7": ("adapters/slack/alert_intake.py", 'inc.update(sent=prior["sent"], prev=prior["id"], count=prior["count"])',
           'inc.update(prev=prior["id"], count=prior["count"])', case_04c),
    "M8": ("adapters/slack/alert_intake.py", "self._queued_new(inc, now)", "self._write_inc(inc)", case_15),
    "M9": ("adapters/slack/socket.py", "self._alert_history(deadline)  # r2337", "pass  # r2337", case_16),
    "M10": ("adapters/slack/alert_intake.py", 'self.queue.put_nowait(("event", event))',
            'self._work(("event", event))', case_19),
}


def _mutant(tmp, name):
    rel, needle, replacement, _case = MUTANTS[name]
    dest = os.path.join(str(tmp), "mutant", "feature-pack", "fable-team", "ft2")
    shutil.copytree(FT2, dest, ignore=shutil.ignore_patterns("__pycache__"))
    target = os.path.join(dest, rel)
    with open(target, encoding="utf-8") as handle:
        text = handle.read()
    if text.count(needle) != 1:
        raise RuntimeError("%s 치환 %d — needle 불일치" % (name, text.count(needle)))
    with open(target, "w", encoding="utf-8") as handle:
        handle.write(text.replace(needle, replacement))
    return dest


@pytest.mark.parametrize("name", sorted(MUTANTS))
def test_mutants(tmp_path, name, band_of):
    """변이 = 그 사례 빨강 · 같은 사례를 원본으로 1회 더 = 초록."""
    base = _mutant(tmp_path, name)
    rel, _needle, _replacement, case = MUTANTS[name]
    with pytest.raises(AssertionError):
        if rel.endswith("alert_intake.py"):
            case(tmp_path / ("%s-mutant" % name), _load(base, rel, "mut"))
        else:
            case(tmp_path / ("%s-mutant" % name), band_of=band_of, base=base)
    if rel.endswith("alert_intake.py"):
        case(tmp_path / ("%s-orig" % name), M)
    else:
        case(tmp_path / ("%s-orig" % name), band_of=band_of)
