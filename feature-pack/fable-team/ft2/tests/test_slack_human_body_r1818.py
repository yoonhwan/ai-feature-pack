"""r1818 ft2 Slack 사람 본문 시험 — 반례 ①~⑤(⑤′~⑤⁗) · 임시 root · 가짜 env · post·urlopen 대역(HTTP form 까지).
실 Slack·실 launchd·실 장부 0 · sleep 0 · 기준판(팩 origin/main)에서 ① ③ ④ ⑤ Red."""
import importlib.util, io, json, os, sys, urllib.parse, urllib.request  # noqa: E401
import pytest

SLACK = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "adapters", "slack")
W, C, U, MASTER, TS, BODY = "TFAKE", "CFAKE", "UOPPA", "byz-planner-master-pi#1", "1800000001.000100", "사람이 읽을 답"
CMD = "slack:%s:%s:%s" % (W, C, TS)
MACHINE = ("receipt:", "[[slack-reply", "접수 ", CMD)

def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_r1818_" + name, os.path.join(SLACK, name + ".py"))
    spec.loader.exec_module(module := importlib.util.module_from_spec(spec))
    return module

def _slack(root, *parts):
    return os.path.join(str(root), ".fable-team", "teams", "planner", "slack", *parts)

def _rows(root, name):
    path = _slack(root, name)
    with open(path, encoding="utf-8") if os.path.exists(path) else open(os.devnull) as handle:
        return [json.loads(line) for line in handle if line.strip()]

@pytest.fixture
def http(monkeypatch):
    """urlopen 대역 — 실제 web_api 가 만든 form 을 그대로 받는다(DA: dict repr 이 아닌 JSON 인지 HTTP 경계에서 본다)."""
    calls = []
    def urlopen(req, timeout=None):
        form = {k: v[0] for k, v in urllib.parse.parse_qs(req.data.decode("utf-8")).items()}
        calls.append(dict(form, auth=req.get_header("Authorization")))
        return io.BytesIO(json.dumps({"ok": True, "ts": "1800000099.%06d" % len(calls)}).encode("utf-8"))
    monkeypatch.setattr(urllib.request, "urlopen", urlopen)
    for name in ("FT2_SLACK_ENV", "SLACK_BOT_TOKEN"):
        monkeypatch.delenv(name, raising=False)
    monkeypatch.setenv("FT2_SLACK_WAKE", "%s -c pass" % sys.executable)  # 깨움 대역 — 실 우편함 0
    return calls

def _human(text, metadata, want=BODY):  # wiring 경로 = 사람 글 + 맨 끝 보낸이 줄 1개(r1850 설계 §4)
    meta = json.loads(metadata)  # Python repr(작은따옴표)이면 여기서 깨진다
    assert text == want and not [m for m in MACHINE if m in text], text
    assert meta["event_type"] == "ft2_reply" and meta["event_payload"]["command"] == CMD
    return meta

def _bind(root):
    binding = _load("binding")
    binding.ThreadBinding(str(root), "planner").bind(binding.thread_key(W, C, TS), MASTER)
    return binding.thread_key(W, C, TS)

def test_1_2_publish_body_only_metadata_and_same_intent(tmp_path):
    publish, posts = _load("publish"), []
    pub = publish.SlackPublish(str(tmp_path), team="planner", sleep=lambda s: None,
                               post=lambda root_ts, text, marker, metadata: posts.append((text, marker, metadata)) or "1.1")
    key = _bind(tmp_path)
    assert pub.reply(key, CMD, BODY, MASTER, 1)["state"] == "posted"  # ①
    text, marker, metadata = posts[0]
    assert text == BODY and marker == publish.marker_for(key, CMD)
    assert metadata == {"event_type": "ft2_reply", "event_payload": {"command": CMD, "marker": marker}}
    again = pub.reply(key, CMD, BODY, MASTER, 1)  # ② 재게시 막기 = 장부 그대로
    assert (again["state"], again["k"], len(posts)) == ("refused", "same_intent", 1)
    assert [r["command"] for r in pub.entries() if r["state"] == "posted"] == [CMD]

def _listener(root):
    return _load("socket").Listener(str(root), channel=C, app_token="xapp-FAKE", bot_token="xoxb-FAKE", master=MASTER,
                                    users=(U,), team="planner", clock=lambda: "2026-11-13T00:00:00")

def test_1_socket_http_metadata_json(tmp_path, http):
    listener, key = _listener(tmp_path), _bind(tmp_path)
    assert listener.publish.reply(key, CMD, BODY, MASTER, 1)["state"] == "posted"
    assert [(c["channel"], c["thread_ts"]) for c in http] == [(C, TS)]
    _human(http[0]["text"], http[0]["metadata"])

def test_3_dispatched_no_receipt_post(tmp_path, http):
    listener = _listener(tmp_path)
    row = listener.route({"type": "message", "user": U, "channel": C, "ts": TS, "team": W, "text": "새 업무"})
    assert row["state"] == "dispatched" and http == [] and _rows(tmp_path, "publish.jsonl") == []
    assert len([r for r in _rows(tmp_path, "receive.jsonl") if r.get("receipt")]) == 1

def _env(path, token):
    path.write_text("export SLACK_BOT_TOKEN='%s'\nSLACK_APP_TOKEN=xapp-FAKE\n" % token, encoding="utf-8")
    return path

def test_4_listen_records_env_path_once(tmp_path, monkeypatch):
    sock = _load("socket")
    monkeypatch.setattr(sock, "Listener", lambda *a, **k: type("L", (), {"run": lambda self: 0})())
    (seats := tmp_path / "seats.json").write_text(json.dumps({"_master": MASTER}), encoding="utf-8")
    monkeypatch.chdir(tmp_path)
    _env(tmp_path / "x.env", "xoxb-SECRET-4")
    argv = ["--root", str(tmp_path), "--team", "planner", "--channel", C, "--env", "x.env", "--owner-seats", str(seats)]
    assert sock.main(argv[:-4] + ["--env", "none.env", "--owner-seats", str(seats)]) == 3
    assert not os.path.exists(_slack(tmp_path, "ENV_PATH"))  # 판독 실패한 env 는 기록 0
    assert sock.main(argv) == 0
    text = open(path := _slack(tmp_path, "ENV_PATH"), encoding="utf-8").read()
    assert text == str(tmp_path / "x.env") + "\n" and "xoxb" not in text and os.path.isfile(path)
    os.utime(path, (1, 1))
    assert sock.main(argv) == 0 and os.stat(path).st_mtime == 1  # 같은 값 = 쓰기 0
    assert [n for n in os.listdir(_slack(tmp_path)) if n.startswith("ENV_PATH")] == ["ENV_PATH"]  # 임시 파일 잔류 0

def _reply(root, capsys, *extra):
    (body := root / "body.txt").write_text(BODY, encoding="utf-8")
    argv = ["reply", "--root", str(root), "--team", "planner", "--thread", TS, "--seat", MASTER,
            "--body-file", str(body), "--command", CMD] + list(extra)
    rc = _load("wiring").main(argv, sleep=lambda s: None)
    return rc, capsys.readouterr().out.strip()

def _point(root, target):
    os.makedirs(_slack(root), exist_ok=True)
    with open(_slack(root, "ENV_PATH"), "w", encoding="utf-8") as handle:
        handle.write(target)

def test_5_env_path_default_posts_http(tmp_path, http, capsys):
    _bind(tmp_path), _point(tmp_path, str(_env(tmp_path / "x.env", "xoxb-ENVPATH")) + "\n")
    rc, out = _reply(tmp_path, capsys)
    assert (rc, out.split()[0]) == (0, "state=posted") and "xoxb" not in out
    assert [c["auth"] for c in http] == ["Bearer xoxb-ENVPATH"]
    _human(http[0]["text"], http[0]["metadata"], BODY + "\n\n보낸이 planner-master")  # wiring lambda·slack_post 경로도 JSON metadata

@pytest.mark.parametrize("case", ["arg", "ft2_env"])
def test_5b_explicit_env_wins(tmp_path, http, capsys, monkeypatch, case):
    _bind(tmp_path), _point(tmp_path, str(_env(tmp_path / "b.env", "xoxb-ENVPATH")))
    first = str(_env(tmp_path / "a.env", "xoxb-FIRST"))
    extra = ["--env", first] if case == "arg" else monkeypatch.setenv("FT2_SLACK_ENV", first) or []
    assert _reply(tmp_path, capsys, *extra)[0] == 0 and [c["auth"] for c in http] == ["Bearer xoxb-FIRST"]

@pytest.mark.parametrize("target", ["missing.env", ""])
def test_5c_env_path_unreadable_rc3_no_fallthrough(tmp_path, http, capsys, monkeypatch, target):
    _bind(tmp_path), _point(tmp_path, str(tmp_path / target) if target else "\n")
    monkeypatch.setenv("SLACK_BOT_TOKEN", "xoxb-SHELL")  # 판독 실패를 셸 토큰으로 덮지 않는다
    rc, out = _reply(tmp_path, capsys)
    assert rc == 3 and "ENV_PATH" in out and "판독 불가" in out and http == [] and "xoxb" not in out

def test_5d_no_env_path(tmp_path, http, capsys, monkeypatch):
    _bind(tmp_path)
    rc, out = _reply(tmp_path, capsys)
    assert rc == 3 and "SLACK_BOT_TOKEN 없음" in out and http == []  # ⑤⁗ 셋 다 없음 = 지금과 같은 rc3
    monkeypatch.setenv("SLACK_BOT_TOKEN", "xoxb-SHELL")  # ENV_PATH 자체 없음 = 다음 단계(셸 env)
    assert _reply(tmp_path, capsys)[0] == 0 and [c["auth"] for c in http] == ["Bearer xoxb-SHELL"]
