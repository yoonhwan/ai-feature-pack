"""ft2 Slack 팀 도구 배선 (r1807 · S-2) — 어댑터 주입점(deliver·notify·post)에 좌석 깨움·issues 기록·게시를 꽂는다.
A2 deliver = 깨움 명령 1회(FT2_SLACK_WAKE · 기본 <root>/.fable-team/comm/mbox.sh send) · A3 «새 업무» = issues Intake
같은 command 기록만 · A4 notify = desk 깨움(같은 command·사유 재알림 0) · A5/A6 `slack reply`·`slack notify` = SlackPublish
1회. 어댑터 5파일·route 규칙은 손대지 않는다 · 모델 호출 0 · 실패는 rc≠0 기록 1줄(조용한 성공 0)."""

import hashlib, importlib.util, json, os, shlex, subprocess, sys, time  # noqa: E401

_HERE = os.path.dirname(os.path.abspath(__file__))
for _name in ("route", "publish", "receive"):  # 경로로 읽기만(수정 0)
    _spec = importlib.util.spec_from_file_location("ft2_wire_" + _name, os.path.join(_HERE, _name + ".py"))
    globals()[_name] = importlib.util.module_from_spec(_spec)
    _spec.loader.exec_module(globals()[_name])
binding, SENDER, USAGE, UNDECIDED = route.binding, "ft2-slack-listen", 2, 3


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

    def wake(self, to, body, command):  # 깨움 1회 · 7초(하드 룰 12) · 실패 = rc≠0 기록 1줄
        try:
            rc = subprocess.run(self.wake_argv + ["send", str(to), SENDER, body], capture_output=True,
                                timeout=7).returncode
        except (OSError, subprocess.SubprocessError) as exc:
            rc = self.log("깨움 실패 %s" % type(exc).__name__) or -1
        self._append({"t": "wake", "to": to, "command": command, "rc": rc, "head": body.splitlines()[0]})
        return rc

    def deliver(self, to, kind, lines):  # route 가 dispatched 뒤에만 부른다(A7) — 방금 쓴 route 행이 그 사건이다
        row = self.router.entries(route.ROUTE)[-1]
        command, thread = row.get("command"), row["key"][2]
        if kind == route.NEW:
            self.record_issue(command)
        body = "\n".join(["[Slack] %s · thread %s · command %s" % (kind, thread, command)] + list(lines))
        if self.wake(to, body, command) != 0:
            self.alert(dict(row, reason="깨움 실패"), quiet=True)

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
    hub.receive, receive.notify = receive, alert
    hub.router = route.SlackRoute(root, receive=receive, bindings=bindings, notify=alert, deliver=hub.deliver,
                                  team=team, clock=clock)
    return hub.router, alert


def _token(path):
    try:
        with open(path, encoding="utf-8") as handle:
            pairs = [l.strip().split("=", 1) for l in handle if "=" in l and not l.lstrip().startswith("#")]
    except (OSError, TypeError):  # 경로 없음 = 환경변수
        return os.environ.get("SLACK_BOT_TOKEN")
    return {k.replace("export ", "", 1).strip(): v.strip().strip("'\"") for k, v in pairs}.get("SLACK_BOT_TOKEN")


def slack_post(token):  # chat.postMessage · 7초 · 재시도는 publish MAX_POSTS 몫(여기 0) · 응답 유실 = ResponseLost
    spec = importlib.util.spec_from_file_location("ft2_wire_socket", os.path.join(_HERE, "socket.py"))
    spec.loader.exec_module(socket := importlib.util.module_from_spec(spec))  # 늦게 읽음 = 순환 import 0
    def post(channel, thread_ts, text):
        try:
            return socket.web_api("chat.postMessage", token, dict(channel=channel, thread_ts=thread_ts, text=text),
                                  retry=False)["ts"]
        except socket.publish.RateLimited as exc:
            raise publish.RateLimited(exc.retry_after)
        except OSError as exc:
            raise publish.ResponseLost(type(exc).__name__)
    return post


def say(state, ts="", rc=0, reason=""):
    sys.stdout.write(("state=%s ts=%s" % (state, ts or "")) + (" reason=%s" % reason if reason else "") + "\n")
    return rc


def main(argv, post=None, sleep=None):
    """`reply|notify --root R --team T --thread TS --seat S --body-file F [--command C] [--env E]` → 출력 1줄."""
    verb, need = (argv or [""])[0], {"reply": ("command",), "notify": ()}.get((argv or [""])[0])
    opts = {k[2:]: v for k, v in zip(argv[1::2], argv[2::2]) if k.startswith("--")}
    known = {"root", "team", "thread", "seat", "body-file", "env"} | set(need or ())
    if need is None or len(argv) % 2 == 0 or len(opts) * 2 != len(argv) - 1 or set(opts) - known \
            or known - {"env"} - set(opts) or opts.get("command", "").startswith("receipt:"):
        return say("usage", rc=USAGE, reason="reply|notify --root --team --thread --seat --body-file [--command]")
    try:
        body = open(opts["body-file"], encoding="utf-8").read()
    except OSError:
        return say("usage", rc=USAGE, reason="body-file 판독 불가")
    ledger = binding.ThreadBinding(opts["root"], opts["team"])
    rows = [r for r in ledger.settled().values() if r["key"][2] == opts["thread"]]
    now = rows and ledger.get(binding.thread_key(*rows[-1]["key"]))
    if not now or not now.open:  # binding 없음·닫힘 = 게시 0(새 root 를 만드는 길 0)
        return say("refused", rc=USAGE, reason="binding 없음" if not now else "닫힘")
    if post is None:
        token = _token(opts.get("env") or os.environ.get("FT2_SLACK_ENV"))
        if not token:
            return say("판정불가", rc=UNDECIDED, reason="SLACK_BOT_TOKEN 없음")
        post = slack_post(token)
    key = binding.thread_key(now.workspace, now.channel, now.root)
    pub = publish.SlackPublish(opts["root"], team=opts["team"], bindings=ledger,
                               post=lambda root_ts, text, marker: post(key.channel, root_ts, text),
                               sleep=sleep or (lambda s: time.sleep(min(float(s), 7))))
    if verb == "reply":  # 역할 답 의도 키 = 업무 command 그대로 · gen = binding 에서
        intent, seat, gen = opts["command"], opts["seat"], now.gen
    else:  # notify — 의도 키 = notify:<root>:<본문 sha12> · 담당 검사 대신 열린 binding 만
        intent, seat, gen = "notify:%s:%s" % (key.root, hashlib.sha256(body.encode()).hexdigest()[:12]), None, None
    try:
        row = pub.reply(key, intent, body, seat, gen)
    except Exception as exc:  # 429 두 번(post_failed)·Slack 오류 응답 = 보이는 실패 1줄(하드 룰 20)
        return say("failed", rc=1, reason=(getattr(exc, "row", None) or {}).get("k") or type(exc).__name__)
    if row["state"] == publish.REFUSED:
        if row.get("k") == "same_intent_unsettled":  # 같은 의도 결과 불명 = 보류(재송 0)
            return say(publish.UNCERTAIN, rc=1, reason=row.get("k"))
        same = row.get("k") == "same_intent"
        return say("duplicate" if same else "refused", row.get("ts"), 0 if same else USAGE, "" if same else row.get("k"))
    return say(row["state"], row.get("ts"), 0 if row["state"] == publish.POSTED else 1)
