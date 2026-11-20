"""ft2 Slack Socket Mode 상주 수신기 (r1806 · S-1) — 계약 줄 1 «Socket Mode 수신 · 주기 폴링 0».
connections.open(7초·재시도 1) → ws → hello(num_connections > 1 = 경쟁 수신 rc 4) → envelope 1개 = 판정 1개 → receive·route.
시작 1회 recover · 재연결 사건마다 Backfill 1회 · 간격 1·2·4…60초 · 유휴 = Web API·기록·모델 0 · 자격 값 출력 0.
r2341 — 보충 대상 = 끊긴 창(마지막 처리 글 ts − 60초) 활동 thread ∪ open binding · 보충·깨움·쪽지·Web 호출은
수신 스레드 밖 일꾼(slack_worker)이 한다 · 자르는 자리 = route 장부까지(ack 는 수신 스레드)."""

import importlib.util, json, logging.handlers, os, re, sys, time, urllib.parse, urllib.request  # noqa: E401

NAMES, NEED, OPTS = ("SLACK_APP_TOKEN", "SLACK_BOT_TOKEN"), ("root", "env", "owner-seats"), ("team", "users", "channel")
SEG, TOTAL = 65536, 8388608  # core journal.py:70 과 같은 상한 — listen.log 에만
USAGE, UNDECIDED, RIVAL = 64, 3, 4
def _adapter(name):  # 어댑터 5파일 = 경로로 읽기만(수정 0) · wiring = r1807
    spec = importlib.util.spec_from_file_location(
        "ft2_slack_" + name, os.path.join(os.path.dirname(os.path.abspath(__file__)), name + ".py"))
    spec.loader.exec_module(module := importlib.util.module_from_spec(spec))
    return module
receive, route, publish, binding, backfill, wiring, channels = map(_adapter, (
    "receive", "route", "publish", "binding", "backfill", "wiring", "channels"))
alert_intake = _adapter("alert_intake")  # r2337 — 경보 갈래(설정 파일 없으면 갈래 0)
slack_worker = _adapter("slack_worker")  # r2341 — 수신 스레드 밖 일꾼(보충·깨움·쪽지)
JOIN_LOOKBACK = 600.0  # S4 — 새로 붙은 채널 보충 창(가입 시각 − 600초)
AUTO = object()  # Listener(alert=AUTO) = 설정에서 만든다 · 시험은 만든 것을 꽂는다

class Undecided(Exception):
    """판정 불가(rc 3) — 메시지에는 이름만 담는다(하드 룰 20)."""

def read_inputs(env_path, seats_path):  # 자격 파일 → 이름별 값(돌려주기만) · owner-seats → _master·_desk(없음 None · r1861) · _master 못 읽음 = Undecided
    try:
        with open(env_path, encoding="utf-8") as handle:
            pairs = [line.strip().split("=", 1) for line in handle if "=" in line and not line.lstrip().startswith("#")]
    except OSError:
        raise Undecided("자격 파일 없음")
    names = {k.strip().replace("export ", "", 1).strip(): v.strip().strip("'\"") for k, v in pairs}
    missing = ",".join(name for name in NAMES if not names.get(name))
    if missing:
        raise Undecided("이름 없음: " + missing)
    try:
        with open(seats_path, encoding="utf-8") as handle:
            master, desk = map(json.load(handle).get, ("_master", "_desk"))
    except (OSError, ValueError, AttributeError):
        master = None
    if not master:
        raise Undecided("owner-seats _master 판독 불가")
    return names, str(master), str(desk) if desk else None

def reply_users_of(names):  # r1985 — SLACK_REPLY_BOT_USER_IDS(쉼표 목록 · 공백·빈 항목 제외 · user 정확 일치) = 답 완료 판정에만
    return tuple(u for u in (v.strip() for v in (names.get("SLACK_REPLY_BOT_USER_IDS") or "").split(",")) if u)

def current_desk(seats_path):  # owner-seats 의 지금 _desk · 칸 없음·판독 불가 = None(r1861 R1)
    try:
        with open(seats_path, encoding="utf-8") as handle:
            desk = json.load(handle).get("_desk")
    except (OSError, ValueError, AttributeError):
        return None
    return str(desk) if desk else None

def web_api(method, token, params=None, retry=True, deadline=None, mono=time.monotonic):  # 7초 + 재시도 1(하드 룰 12) · 게시는 retry=False(유실 = 재송 0)
    req = urllib.request.Request("https://slack.com/api/" + method, headers={"Authorization": "Bearer " + token},
                                 data=urllib.parse.urlencode(params or {}).encode("utf-8"))
    for left in ((1, 0) if retry else (0,)):
        wait = 7 if deadline is None else min(7, deadline - mono())  # r1899 — 배치 deadline 안에서만
        if wait <= 0:
            raise TimeoutError("예산 끝")
        try:
            with urllib.request.urlopen(req, timeout=wait) as resp:
                out = json.loads(resp.read().decode("utf-8"))
        except OSError as exc:  # HTTPError 도 여기 — 429 만 Retry-After 로 넘긴다
            if getattr(exc, "code", None) == 429:
                raise publish.RateLimited(exc.headers.get("Retry-After") or 1)
            if left and (deadline is None or deadline - mono() >= 7):  # 재시도 = 남은 초 ≥ 7 일 때만
                continue
            raise
        if not out.get("ok"):  # Slack 오류 응답 = 보이는 실패(재시도 0)
            raise RuntimeError("%s %s" % (method, out.get("error")))
        return out

def listen_log(data):  # listen.log 1곳 — segment SEG 에서 회전 · 회전본 TOTAL // SEG - 1 개 = 합계 TOTAL 이하
    logger = logging.getLogger("ft2.slack.listen:" + data)
    if not logger.handlers:
        handler = logging.handlers.RotatingFileHandler(os.path.join(data, "listen.log"), maxBytes=SEG,
                                                       backupCount=TOTAL // SEG - 1, encoding="utf-8")
        handler.setFormatter(logging.Formatter("%(asctime)s %(message)s"))
        logger.addHandler(handler)
        logger.setLevel(logging.INFO)
    return logger.info

def _ws_connect(url):
    from websockets.sync.client import connect
    return connect(url, open_timeout=7, max_size=2 ** 22)

class Listener:  # 상주 수신기 1개 = 연결 1개 · 허용 = CHANNELS on 줄(r1923 · --channel = 파일 없을 때 씨앗 1회) · 팀 1곳
    def __init__(self, root, *, channel=None, app_token, bot_token, master, desk=None, seats=None, team="planner", users=(), bot_users=(),
                 reply_users=(), web=web_api, connect=_ws_connect, sleep=time.sleep, mono=time.monotonic, notify=None, clock=None,
                 alert=AUTO, now=None):
        self.root, self.master, self.desk, self.web, self.connect, self.sleep = root, master, desk, web, connect, sleep
        self.now = now or time.time  # S2·일꾼 — 초 단위 시계(hello 시각·넘침 알림 간격)
        self.tank = set(bot_users)  # r1985 — 가입·탈퇴(자동 채널) 신원 = 탱크만 · reply_users = 답 완료에만
        self.seats = seats  # owner-seats 경로 · desk 교대를 재기동 없이 따라감(r1861 R1)
        self.app_token, self.bot_token, self.mono, self.ws, self.envelope = app_token, bot_token, mono, None, None
        self.deadline = mono() + 60  # r1899 — recover full 갈래 배치 예산(고정비 포함 70초 안)
        same = dict(team=team, clock=clock)
        self.bindings = binding.ThreadBinding(root, **same)  # slack 폴더를 만든다
        self.log = listen_log(os.path.dirname(self.bindings.path))
        self.chan = channels.Channels(channels.path_of(root, team), channel, self.log)  # 깨짐·없음 = Corrupt(수신 시작 0)
        self.channel = self.chan.role("main")  # 게시 = 주 채널만 · 묶기 = 허용 전부(주 = master · 그 밖 = desk 또는 owner 칸)
        self.notify = notify or (lambda row: self.log("[notify] " + json.dumps(row, ensure_ascii=False)))
        self.alert = (alert_intake.AlertIntake(root, team=team, conf=alert_intake.load_config(root, team), log=self.log)
                      if alert is AUTO else alert)  # r2337 — 설정 없음 = None(수신 결과 지금 그대로)
        self.receive = receive.SlackReceive(root, ack=self._ack, allowed_users=users, allowed_channels=(),
                                            bot_users=tuple(bot_users) + tuple(reply_users), notify=self.notify, replies=self._replies,
                                            deadline=self.deadline, mono=mono, log=self.log,
                                            alert=self.alert.feed if self.alert is not None else None, **same)
        self.receive.allowed_channels = self.chan.allowed  # 같은 set 객체 — 발견·등록·삭제가 재기동 없이 반영
        self.router, self.notify = wiring.wire(root, receive=self.receive, bindings=self.bindings, notify=notify,
                                               log=self.log, team=team, clock=clock, now=self.now)  # r1807 깨움·issues·desk 배선
        self.worker = slack_worker.Worker(log=self.log, notify=self.notify, now=self.now)  # S3 — 수신 스레드 밖 일꾼 1개
        self.router.deliver = self.worker.wrap(self.router.deliver)  # 깨움·쪽지 통통 = 일꾼(route.py·wiring.py 손 0)
        self.router.notify = self.notify = self.worker.wrap(self.notify)
        self.receive.notify = self.notify
        if getattr(self.receive, "resend", None) is not None:  # G2 유휴 재전송도 일꾼 — 후보 표를 만지는 스레드는 1개뿐
            self.receive.resend = self.worker.wrap(self.receive.resend)
        self.watermark, self.backfill_left = None, []  # S2 — 끊긴 시각(마지막 처리 글 Slack ts) · 예산에 남은 대상
        self.slowest, self.backfilled = 0.0, 0  # S6 — 이 연결의 수신 스레드 최장 처리 초 · 끊긴 창 보충 글 수
        self.publish = publish.SlackPublish(root, post=self._post, bindings=self.bindings, notify=self.notify, **same)
        self.backfill = backfill.Backfill(root, route=self, fetch=self._fetch, notify=self.notify, mono=mono, **same)
    def run(self, sessions=None):  # 상주 루프 — 반환 = rc(경쟁 수신 4) · sessions = 시험용 연결 횟수 상한
        if self.alert is not None:  # r2337 — 일꾼 스레드 1 시작(장부 1회 읽어 마감 표 재구성)
            self.alert.start()
        self.worker.start()  # r2341 S3 — 수신 스레드 밖 일꾼 1개
        try:
            return self._run(sessions)
        finally:
            self.worker.stop()  # 남은 일감은 다 하고 끝난다(유실 0)
            if self.alert is not None:
                self.alert.stop()
    def _run(self, sessions):
        for verdict in self.receive.recover():  # 재기동 1회 복구(A4) — dispatched 면 영수도 같은 길(R1)
            self.router.recovered(verdict)  # r1807 보정1 R2 — 복구 dispatched 도 입구 기록·좌석 깨움
            rows = [r["key"] for r in self.router.entries("route") if r.get("command") == verdict.get("command")]
            self._receipt(route.binding.thread_key(*(rows or [verdict["key"]])[-1]), verdict)
        count = fails = 0
        while sessions is None or count < sessions:
            count += 1
            try:
                outcome = self._session(reconnect=count > 1)
            except Exception as exc:  # 연결·Web API 실패·hello 10초 없음 = 재연결 사건
                outcome = "실패 %s" % type(exc).__name__
            if outcome == RIVAL:
                return RIVAL
            self.log("연결 끝 %s · 최장 처리 %d초 · 큐 최대 %d · 끊긴 시각 %s · 보충 글 %d" % (
                outcome if isinstance(outcome, str) else "정상", self.slowest, self.worker.max_queue,
                self.watermark or "-", self.backfilled))  # S6 — 4칸 = 관측만(값 판정 0)
            if sessions is None or count < sessions:
                fails = 0 if outcome is True else min(fails + 1, 7)
                self.sleep(min(2 ** max(fails - 1, 0), 60))  # 정상 끝 뒤 1 · 연속 실패 1·2·4·…·60초(R2)
        return 0
    def _session(self, reconnect):  # 연결 1번 — 반환 = True(disconnect·끊김 = 재연결 사건) 또는 RIVAL
        self.slowest, self.backfilled = 0.0, 0  # S6 — 칸은 이 연결 것만
        self.worker.reset_stats()
        deadline = self.mono() + 50  # R1 — 연결 1번의 Web 호출 전체 예산 1개(apps.connections.open 부터 · 고정비 포함 70초 안)
        with self.connect(self.web("apps.connections.open", self.app_token, deadline=deadline, mono=self.mono)["url"]) as self.ws:
            self.envelope, out = None, self._hello(json.loads(self.ws.recv(timeout=10)), reconnect, deadline)
            while out is None:
                try:
                    out = self._frame(json.loads(self.ws.recv(timeout=1)))
                except TimeoutError:
                    self.on_idle()
                except Exception:  # 끊김·처리 실패 = 재연결 사건(미확인 envelope 는 Slack 이 재전달 → duplicate)
                    out = True
            return out
    def on_idle(self):  # envelope 0 인 1초 — Slack 읽기·기록 증가·모델 호출 0(타이머로 Slack 을 읽는 코드 0)
        self.receive.pass_idle()
        self.worker.on_idle()  # S3 · ⑬ — 일꾼 수명 is_alive 1줄(입출력 0) · 죽었으면 다시 띄움
        if self.alert is not None:  # r2337 G4 — 일꾼 수명 is_alive 1줄(입출력 0)
            self.alert.on_idle()
    def _alert_history(self, deadline):  # r2337 G1 — 연결 1번(hello)마다 경보 채널 history 1쪽 1회(폴링 아님)
        if self.alert is None:
            return
        oldest = self.alert.oldest()
        for channel in self.alert.channels:
            for attempt in (1, 2):  # 7초 상한 · 재시도 1 · 남은 예산 ≤0 = 호출 0
                if deadline - self.mono() <= 0:
                    return self.log("판정 불가 경보 history 예산 끝 — 보충 중단")
                try:
                    out = self._web("conversations.history",
                                    {"channel": channel, "oldest": oldest, "limit": 200}, deadline)
                    break
                except Exception as exc:
                    if attempt == 2:
                        self.log("판정 불가 경보 history %s — %s" % (channel, type(exc).__name__))
                        out = None
            if out is None:
                continue
            self.alert.ingest(out.get("messages") or [], bool(out.get("has_more")))
    def _hello(self, env, reconnect, deadline):
        if env.get("type") != "hello":
            raise RuntimeError("hello 없음")
        if int(env.get("num_connections") or 1) > 1:  # 경쟁 소비자 — 연결 닫고 알림 1 · xclaw Tank 수신을 켜지 않는다
            self.notify({"state": "rival", "num_connections": env.get("num_connections")})
            return RIVAL
        try:  # A — 가입 채널 발견 · 완전 성공만 auto 줄 교체(R2) · 실패 = 판정 불가 1줄 · 지금 허용으로 수신 계속
            done, seen = self._discover(deadline)
            self._added(self.chan.snapshot(seen)) if done else self.log("판정 불가 자동 채널 — 3쪽 뒤 cursor")
        except Exception as exc:
            self.log("판정 불가 자동 채널 — %s" % type(exc).__name__)
        if len(self.chan.explicit()) > 1:  # r1833 C2 — 참여 확인 = main·admin·req 줄만(채널 1개 = 2ea518 그대로 · C4)
            self._members(deadline)
        self._alert_history(deadline)  # r2337 — 재연결·재시작 사건마다 1회(첫 세션 포함 · 첫 세션 reconnect=False)
        if reconnect:  # 재연결 사건 1회 = 보충 1회(주기 폴링 0) — 보충은 일꾼 몫(수신 스레드 밖 · S3)
            self.worker.submit(self._backfill_job)
    def _web(self, method, params, deadline):  # R1 — 남은 초 ≤ 0 = 호출 0 · 호출마다 min(7, 남은 초)
        if deadline - self.mono() <= 0:
            raise TimeoutError("예산 끝")
        return self.web(method, self.bot_token, params, deadline=deadline, mono=self.mono)

    # ── S2·S4 — 보충은 일꾼 몫(Web 호출·route 장부 모두 수신 스레드 밖)
    def _backfill_job(self):
        """재연결 사건 1회 = 보충 1회. 예산 50초(연결 예산과 따로 · 메모 2)를 넘기면 남은 대상을 들고 멈춘다(⑩)."""
        budget = self.mono() + backfill.BUDGET
        left, self.backfill_left = list(self.backfill_left), []
        try:
            targets, floor = self._window_scan(left, budget)
        except Exception as exc:  # 판독 불가 = 1줄 · 수신 계속(다음 재연결이 다시 본다)
            return self.log("판정 불가 끊긴 창 보충 — %s" % type(exc).__name__)
        row = self.backfill.run(backfill.RECONNECT, targets, deadline=budget, floor=floor)
        self.backfilled += int(row.get("routed") or 0)
        if row.get("left"):
            self.backfill_left = [tuple(item) for item in row["left"]]
            self.log("보충 미완 — 남은 %d thread(다음 재연결)" % len(self.backfill_left))

    def _scan_order(self):  # 메모 2 차례 — 사람 채널(main·admin·req) → auto
        people = [r[0] for r in self.chan.rows if r[2] == "on" and r[3] != "auto"]
        auto = [r[0] for r in self.chan.rows if r[2] == "on" and r[3] == "auto"]
        return [c for c in people + auto if c in self.chan.allowed]

    def _seat_of(self, channel, thread):  # 그 thread 의 좌석(binding) · 없으면 ""(커서만 따로 센다)
        return next((r["seat"] for r in self.bindings.settled().values()
                     if r["key"][1:] == [channel, thread]), "")

    def _window_scan(self, left, budget):
        """끊긴 창 = (끊긴 시각 − 60초, 지금] 활동 thread ∪ open binding — 새 root 글은 그 자리에서 route.

        차례 = 남은 것(⑩) → 사람 채널(main·admin·req) → auto(메모 2) → open binding. 반환 = (targets, floor).
        """
        targets, seen = [], set()

        def add(seat, channel, thread):
            if (channel, thread) not in seen:
                seen.add((channel, thread))
                targets.append((seat, channel, thread))

        for seat, channel, thread in left:  # ⑩ 다음 재연결이 남은 것부터
            add(seat, channel, thread)
        oldest = max((float(self.watermark) if self.watermark else self.now()) - 60.0, 0.0)  # H3 — 받은 시각 아님(⑳)
        floor = "%.6f" % oldest
        for channel in self._scan_order():
            if self.mono() >= budget:
                self.log("보충 미완 — 예산 끝 · 남은 채널 %s" % channel)
                break
            try:
                messages = self._web("conversations.history", {"channel": channel, "oldest": oldest, "limit": 200},
                                     budget).get("messages") or []
            except Exception as exc:
                self.log("판정 불가 끊긴 창 %s — %s" % (channel, type(exc).__name__))
                continue
            for message in sorted(messages, key=lambda m: float(m.get("ts") or 0)):
                thread = str(message.get("thread_ts") or message.get("ts") or "")
                ts = float(message.get("ts") or 0)
                if not thread or not (self.watermark is None or ts > float(self.watermark)):
                    continue  # 끊긴 창 밖 = 보충 0(⑥)
                if thread == str(message.get("ts")):  # 새 root 글 = 이 자리에서 route(⑤ · ⑦ duplicate)
                    self.route(dict(message, channel=channel, team=message.get("team") or ""))
                    self.backfilled += 1
                    if float(message.get("latest_reply") or 0) > ts:  # 이 thread 답글도 보충(⑧)
                        add(self._seat_of(channel, thread), channel, thread)
                    continue
                add(self._seat_of(channel, thread), channel, thread)
        for row in self.bindings.settled().values():  # open binding thread = 마지막(⑧ · 지금 동작 유지)
            if row.get("open"):
                add(row["seat"], row["key"][1], row["key"][2])
        return targets, floor

    def _join_backfill(self, channel, at):
        """S4 — 새로 붙은 채널 history 1쪽(oldest = 가입 시각 − 600초) 보충 1회(일꾼 · 폴링 0 · ⑪)."""
        oldest = max(float(at or self.now()) - JOIN_LOOKBACK, 0.0)
        try:
            out = self._web("conversations.history", {"channel": channel, "oldest": oldest, "limit": 200},
                            self.mono() + backfill.BUDGET)
        except Exception as exc:
            return self.log("판정 불가 가입 보충 %s — %s" % (channel, type(exc).__name__))
        rows = out.get("messages") or []
        for message in reversed(rows):  # 옛 글부터 차례
            self.route(dict(message, channel=channel, team=message.get("team") or ""))
            self.backfilled += 1
        self.log("가입 보충 %s — %d글" % (channel, len(rows)))
    def _discover(self, deadline):  # users.conversations 3쪽 안 → (완전 성공, {ID: 이름}) · DM/MPDM 0
        seen, cursor = {}, ""
        for _page in range(3):
            out = self._web("users.conversations", dict(types="public_channel,private_channel", exclude_archived="true",
                                                         limit=200, **({"cursor": cursor} if cursor else {})), deadline)
            seen.update({c["id"]: c.get("name") or "" for c in out.get("channels") or []})
            if not (cursor := (out.get("response_metadata") or {}).get("next_cursor") or ""):
                return True, seen
        return False, seen
    def _added(self, ids):  # 새로 더한 채널마다 listen.log 1줄 + notify 1 · history 1쪽 보충 1회(일꾼 · S4)
        for channel in ids:
            self.log("자동 채널 +%s" % channel)
            self.notify({"state": "auto", "channel": channel, "reason": "자동 채널 +%s" % channel})
            self.worker.submit(self._join_backfill, channel, self.now())

    def _archived(self, event):  # S5 — 보관 = auto on 줄만 지운다(고정 main·admin·req = 손 0 · ⑫)
        channel = event.get("channel")
        if self.chan.drop_auto(channel):
            self.log("자동 채널 −%s (보관)" % channel)
    def _joined(self, event):  # B — 봇 가입 = conversations.info 로 종류 확인(ID 접두사 판정 0) 뒤 auto 줄 · 봇 탈퇴 = auto 줄 지움
        channel, bot = event.get("channel"), event.get("user") in self.tank
        if event.get("type") == "member_joined_channel" and bot:
            try:
                info = self.web("conversations.info", self.bot_token, {"channel": channel}).get("channel") or {}
            except Exception as exc:
                return self.log("판정 불가 자동 채널 %s — %s" % (channel, type(exc).__name__))
            if not (info.get("is_channel") or info.get("is_group")) or info.get("is_mpim") or info.get("is_im"):
                return self.log("자동 채널 제외 %s — 종류 밖" % channel)
            return self._added([channel] if self.chan.add_auto(channel, info.get("name")) else [])
        if (event.get("type") == "channel_left" or bot) and not self.chan.drop_auto(channel) and channel in self.chan.allowed:
            self.log("수신 불가 채널 %s — 봇 미참여(/invite 필요)" % channel)
    def _members(self, deadline):  # 미참여·판정 불가 = listen.log + notify 1줄 · 수신은 계속 · 자격 값 출력 0
        for channel in self.chan.explicit():
            if deadline - self.mono() <= 0:  # R1 — 예산 끝 = 그 뒤 Web 0 · 1줄 · 수신 계속
                return self.log("판정 불가 hello 예산 끝 — 참여 확인 중단")
            try:
                ok = (self._web("conversations.info", {"channel": channel}, deadline).get("channel") or {}).get("is_member")
                line = None if ok else "수신 불가 채널 %s — 봇 미참여(/invite 필요)" % channel
            except Exception as exc:  # OSError·web_api RuntimeError(ok:false)·429 = 판정 불가(루프 종료 0)
                line = "판정 불가 채널 %s — %s" % (channel, type(exc).__name__)
            if line:
                self.log(line)
                self.notify({"state": "member", "channel": channel, "reason": line})
    def _frame(self, env):
        """envelope 1개 처리 — 처리 초는 여기서 잰다(S6·«최장 처리» 칸 · 관측만)."""
        started = self.mono()
        try:
            return self._frame_of(env)
        finally:
            self.slowest = max(self.slowest, self.mono() - started)

    def _frame_of(self, env):
        if env.get("type") == "disconnect":
            return True
        self.envelope, event = env.get("envelope_id"), (payload := env.get("payload") or {}).get("event") or {}
        if env.get("type") == "events_api" and event.get("type") == "message":
            event = dict(event, team=event.get("team") or payload.get("team_id") or "")
            self._admin(event) or self.route(event)
            if event.get("ts"):  # S2 — 끊긴 시각 = 마지막으로 처리한 글의 Slack ts(받은 시각 아님 · H3)
                self.watermark = str(event["ts"])
        elif env.get("type") == "events_api" and event.get("type") in ("member_joined_channel", "channel_left", "member_left_channel"):
            self._joined(event)
        elif env.get("type") == "events_api" and event.get("type") in ("channel_archive", "group_archive"):
            self._archived(event)  # S5 — 보관 사건 = auto on 줄만 지움(지금 판은 버림 · 변이 M6)
        else:
            self.log("버림 %s %s" % (env.get("type"), event.get("type") or ""))
        return self._ack(None)  # receive 가 이미 확인했으면 0회
    def _admin(self, event):  # ⑦ 공식 채널 · 허용 사용자 · root 글 «등록|삭제 #채널» = 명령(router 0) · 아니면 False
        if event.get("channel") != self.chan.role("admin") or event.get("thread_ts") or event.get("bot_id") or event.get(
                "subtype") or event.get("user") not in self.receive.allowed_users or not channels.parse(event.get("text")):
            return False
        word = self.chan.command(route.thread_key(event), event.get("text"), self._lookup, lambda text: self.web(
            "chat.postMessage", self.bot_token, dict(channel=event["channel"], thread_ts=event["ts"], text=text), retry=False)["ts"])
        return self.log("명령 %s" % (word or "재전달 — 다시 0")) or True
    def _lookup(self, target):  # 채널 글자 → (ID, 이름, 봇 가입 여부|None) · 맨 이름 = 목록 이름 → users.conversations
        tag = re.fullmatch(r"<#([A-Z0-9]+)(?:\|([^>]*))?>", target)
        try:
            done, seen = self._discover(self.mono() + 7)
        except Exception:
            done, seen = False, {}
        name = tag.group(2) or seen.get(tag.group(1)) or "" if tag else target.lstrip("#")
        cid = tag.group(1) if tag else next((r[0] for r in self.chan.rows if r[1] == name), None) or next(
            (c for c, n in seen.items() if n == name), None)
        return cid and (cid, name, (cid in seen) if done else None)
    def _ack(self, event):
        if self.envelope and self.ws is not None:
            self.ws.send(json.dumps({"envelope_id": self.envelope}))
            self.envelope = None  # envelope 1개 = 확인 1회 · 확인 ≠ 접수
    def route(self, event):  # 새 envelope·보충(Backfill 이 부름) 모두 이 길 — bind → route → dispatched 영수(R1)
        key = event and route.thread_key(event)
        human = event and not (event.get("bot_id") or event.get("subtype")) and event.get("user") in self.receive.allowed_users
        if human and event.get("channel") in self.chan.allowed and not event.get("thread_ts") and not [
                row for row in self.bindings.entries() if row.get("key") == list(key)] and (owner := self._owner(event)):
            self.bindings.bind(key, owner)  # 새 root 첫 binding(A5b) — 닫힌 적 있으면 묶지 않는다
        return self._receipt(key, self.router.route(event)) if event else self.router.route(None)
    def _owner(self, event):  # owner 칸 ≠ - = 묶기 직전 그 명부 역할 키 · 주 채널 = master · 그 밖 = 현재 _desk · None = 묶기 0
        owner = (self.chan.row(event.get("channel")) or ["-"] * 5)[4]
        if owner != "-":  # 명부 못 읽음 = 묶기 0 + 판정 불가 1줄(router 가 desk 알림 1 · planner 대체 0)
            return channels.resolve(owner) or self.log("판정 불가 채널 주인 %s — 명부 판독 불가" % event.get("channel"))
        return self.master if event.get("channel") == self.channel else current_desk(self.seats) if self.seats else self.desk
    def _receipt(self, key, row):  # r1818 E3 — 접수 = receive 장부 기록만 · Slack 게시 0(역할 답이 첫 반응)
        return row
    def _post(self, root_ts, text, marker, metadata):
        try:  # 응답 유실 = 결과 불명 · 재송 0(publish 계약 11) · metadata = JSON 문자열(form 의 dict repr 0)
            return self.web("chat.postMessage", self.bot_token, dict(channel=self.channel, thread_ts=root_ts, text=text,
                            metadata=json.dumps(metadata, ensure_ascii=False)), retry=False)["ts"]
        except OSError as exc:
            raise publish.ResponseLost(type(exc).__name__)
    def _replies(self, channel, thread):  # r1899 — 기동 recover 의 답 확인 1회 · 200 넘침 = 판정 불가
        out = self.web("conversations.replies", self.bot_token, dict(channel=channel, ts=thread, limit=200),
                       deadline=self.deadline, mono=self.mono)
        if out.get("has_more"):
            raise RuntimeError("넘침")
        return out.get("messages") or []
    def _fetch(self, channel, thread, after, limit):
        team = next((r["key"][0] for r in self.bindings.settled().values() if r["key"][1:] == [channel, thread]), "")
        out = self.web("conversations.replies", self.bot_token,
                       dict(channel=channel, ts=thread, limit=limit, **({"oldest": after} if after else {})))
        rows = [dict(m, team=team, root=m.get("ts") == thread) for m in out.get("messages") or []]
        return {"rows": rows, "next": out.get("has_more") and (out.get("response_metadata") or {}).get("next_cursor") or ""}

def record_env_path(root, team, env):  # r1818 E4 — 읽은 --env 절대경로 1줄(토큰 값 0) · 같으면 쓰기 0 · 임시→mv
    path, line = os.path.join(os.path.abspath(root), ".fable-team", "teams", team, "slack", "ENV_PATH"), os.path.abspath(env) + "\n"
    try:
        with open(path, encoding="utf-8") if os.path.exists(path) else open(os.devnull) as handle:
            if handle.read() == line:
                return
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path + ".tmp", "w", encoding="utf-8") as handle:
            handle.write(line)
        os.replace(path + ".tmp", path)
    except (OSError, ValueError) as exc:  # 기록 실패 = 수신은 계속 · 보이는 줄 1(좌석은 --env 로 우회)
        sys.stderr.write("ENV_PATH 기록 실패 %s\n" % type(exc).__name__)

def say(word, reason, rc):
    sys.stdout.write(json.dumps({"result": word, "reason": reason}, ensure_ascii=False) + "\n")
    return rc

def main(argv):
    opts = {key[2:]: value for key, value in zip(argv[::2], argv[1::2]) if key.startswith("--")}
    if len(argv) % 2 or len(opts) * 2 != len(argv) or set(opts) - set(NEED + OPTS) or set(NEED) - set(opts):
        return say("사용법", "--root --env --owner-seats [--team --users --channel(CHANNELS 없을 때 씨앗)]", USAGE)
    try:
        names, master, desk = read_inputs(opts["env"], opts["owner-seats"])
    except Undecided as exc:
        return say("판정 불가", str(exc), UNDECIDED)
    record_env_path(opts["root"], opts.get("team", "planner"), opts["env"])
    try:
        listener = Listener(opts["root"], channel=opts.get("channel"), app_token=names["SLACK_APP_TOKEN"],
                        bot_token=names["SLACK_BOT_TOKEN"], master=master, desk=desk, seats=opts["owner-seats"], team=opts.get("team", "planner"),
                        users=tuple(u for u in opts.get("users", "").split(",") if u),
                        bot_users=tuple(u for u in (names.get("SLACK_BOT_USER_ID"),) if u), reply_users=reply_users_of(names))
    except channels.Corrupt as exc:  # CHANNELS 깨짐 · 파일 없음 ∧ --channel 없음 = 수신 시작 0
        return say("판정 불가", str(exc), UNDECIDED)
    return say("경쟁 수신 있음", "hello num_connections > 1", RIVAL) if listener.run() == RIVAL else 0
