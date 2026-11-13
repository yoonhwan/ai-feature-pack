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
route, publish, receive, sender_tag = map(_adapter, ("route", "publish", "receive", "sender_tag"))
binding, SENDER, USAGE, UNDECIDED = route.binding, "ft2-slack-listen", 2, 3
_fa = importlib.util.spec_from_file_location("ft2_wire_full_alert", os.path.join(os.path.dirname(_HERE), "pi", "full_alert.py"))
_fa.loader.exec_module(full_alert := importlib.util.module_from_spec(_fa))  # r1886 ⓐ


class Wiring:
    def __init__(self, root, *, team="planner", log=None, clock=None, wake=None):
        self.root, self.team = os.path.abspath(str(root)), team
        self.log, self.clock = log or (lambda line: None), clock or (lambda: time.strftime("%Y-%m-%dT%H:%M:%S"))
        default = "bash %s" % shlex.quote(os.path.join(self.root, ".fable-team", "comm", "mbox.sh"))
        self.wake_argv = shlex.split(wake or os.environ.get("FT2_SLACK_WAKE") or default)
        self.path = os.path.join(self.root, ".fable-team", "teams", team, "slack", "wire.jsonl")

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

    def wake(self, to, body, command):  # 깨움 1회 · 상한 25초(하드 룰 12 로컬 하네스 · r1833 C3) · 실패 = rc≠0 기록 1줄 · 재시도 0
        row, head = {}, body.splitlines()[0]
        try:
            rc = subprocess.run(self.wake_argv + ["send", str(to), SENDER, body], capture_output=True,
                                timeout=float(os.environ.get("FT2_SLACK_WAKE_TIMEOUT") or 25)).returncode
        except (OSError, subprocess.SubprocessError) as exc:
            rc = self.log("깨움 실패 %s" % type(exc).__name__) or -1
            if isinstance(exc, subprocess.TimeoutExpired):  # 잘린 send = 적재 3값 판정 1줄(조용한 유실 0)
                row = {"why": "상한 초과 · 적재 " + self.landed(head)}
        self._append(dict({"t": "wake", "to": to, "command": command, "rc": rc, "head": head}, **row))
        return rc

    def landed(self, head):  # 우편함 log 끝 200줄에 그 본문 첫 줄이 있나(읽기만) · 못 읽음 = 판정 불가
        try:
            with open(os.path.join(self.root, ".fable-team", "comm", "mailbox.log.jsonl"), encoding="utf-8") as handle:
                tail = collections.deque(handle, 200)
        except (OSError, ValueError):
            return "판정 불가"
        for line in tail:
            try:
                if (json.loads(line).get("body") or "").splitlines()[:1] == [head]:
                    return "있음"
            except (ValueError, AttributeError):
                continue
        return "없음"

    def deliver(self, to, kind, lines, row=None):  # route 가 dispatched 뒤에만 부른다(A7) — 방금 쓴 route 행이 그 사건이다
        row = row or self.router.entries(route.ROUTE)[-1]
        command, thread = row.get("command"), row["key"][2]
        if kind == route.NEW:
            self.record_issue(command)
        body = "\n".join(["[Slack] %s · thread %s · command %s" % (kind, thread, command)] + list(lines))
        if self.wake(to, body, command) != 0:
            self.alert(dict(row, reason="깨움 실패"), quiet=True)

    def recovered(self, verdict):  # 보정1 R2 — 재기동 복구 dispatched 도 정상 길처럼 입구 기록·좌석 깨움 1회
        command, router = verdict.get("command"), self.router
        if verdict.get("state") != route.DISPATCHED or any(  # 이미 좌석에 넘긴 글 = 깨움 0
                r.get("command") == command and not r["head"].startswith("[Slack] 알림") for r in self.entries("wake")):
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
        if command and any(r.get("command") == command and r.get("why") == why for r in self.entries("alert")):
            return
        self._append({"t": "alert", "command": command, "why": why})
        desk, key = self.seat("_desk"), row.get("key") or [None] * 3
        if not desk:
            return self.log("[notify] desk 없음 " + json.dumps(row, ensure_ascii=False))
        self.wake(desk, "[Slack] 알림 %s · thread %s · command %s" % (why, key[2], command), command)


def wire(root, *, receive, bindings, notify=None, log=None, team="planner", clock=None, wake=None):
    """S-1 route 생성 1곳 대체 — (route, notify). notify 를 주입받았으면 그대로 쓴다(시험·대역)."""
    hub = Wiring(root, team=team, log=log, clock=clock, wake=wake)
    alert = notify or hub.alert
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
