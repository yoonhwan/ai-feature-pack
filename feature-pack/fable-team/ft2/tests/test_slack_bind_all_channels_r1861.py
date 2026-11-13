"""r1861 받는 채널 목록 안 «어느 채널» 이든 오빠 새 root = binding 1 시험 — 카드 반례 ①~④ · 변이 M1·M2.
임시 root · 가짜 web·ws · post 대역 · 실 Slack·실 장부·설치 0 · sleep 0 · 기준판(주 채널만 묶음)에서 ① Red."""
import importlib.util, json, os, sys  # noqa: E401
import pytest

SLACK = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "adapters", "slack")
W, A, B, C, U, BOT = "TFAKE", "CMAIN", "CDESK", "COTHER", "UOPPA", "BFAKE"
MASTER, DESK = "byz-planner-master-pi#1", "byz-planner-desk-pi#1"


def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_r1861_" + name, os.path.join(SLACK, name + ".py"))
    spec.loader.exec_module(module := importlib.util.module_from_spec(spec))
    return module


@pytest.fixture
def env(tmp_path, monkeypatch):
    (fable := tmp_path / ".fable-team").mkdir()
    (fable / "seats-planner.json").write_text(json.dumps({"_master": MASTER, "_desk": DESK}), encoding="utf-8")
    (fable / "seats-issues.json").write_text(json.dumps({"_master": "byz-issues-master-sol#1"}), encoding="utf-8")
    (script := tmp_path / "wake.py").write_text("import sys\n", encoding="utf-8")
    monkeypatch.setenv("FT2_SLACK_WAKE", "%s %s" % (sys.executable, script))
    return tmp_path


def _listener(root, web_posts):
    def web(method, token, params=None, retry=True):
        web_posts.append(method) if method == "chat.postMessage" else None
        return {"ok": True, "messages": [], "has_more": False}
    return _load("socket").Listener(str(root), channel="%s,%s" % (A, B), app_token="xapp-FAKE", bot_token="xoxb-FAKE",
                                    master=MASTER, users=(U,), web=web, connect=None, sleep=lambda s: None,
                                    clock=lambda: "2026-11-13T00:00:00")


def _msg(ts, channel, **extra):
    return dict({"type": "message", "user": U, "channel": channel, "ts": ts, "team": W, "text": "글 " + ts}, **extra)


def _bound(root):
    path = root / ".fable-team" / "teams" / "planner" / "slack" / "bindings.jsonl"
    rows = [json.loads(ln) for ln in path.read_text(encoding="utf-8").splitlines()] if path.exists() else []
    return [(r["state"], r["key"][1]) for r in rows]


def _send(root, verb, where, posts, seat=MASTER):  # reply = binding 담당 좌석만(publish stale_owner 그대로)
    (body := root / "body.txt").write_text("답", encoding="utf-8")
    argv = [verb, "--root", str(root), "--team", "planner", "--seat", seat, "--body-file", str(body)] + where
    return _load("wiring").main(argv, post=lambda ch, ts, text, meta: posts.append((ch, ts)) or "1.9",
                                sleep=lambda s: None)


def test_1_second_channel_root_bound_reply_posted(env, capsys):  # ① B 새 root → bound B · reply 게시 채널 = B
    sent, posts, ts = [], [], "1800000001.000100"
    _listener(env, sent).route(_msg(ts, B))
    assert _bound(env) == [("bound", B)] and sent == []
    capsys.readouterr()
    assert _send(env, "reply", ["--thread", ts, "--command", "slack:%s:%s:%s:a" % (W, B, ts)], posts) == 0
    assert capsys.readouterr().out.startswith("state=posted ") and posts == [(B, ts)]


def test_2_main_channel_root_bound_as_before(env):  # ② A 새 root = 그대로 bound A
    sent = []
    _listener(env, sent).route(_msg("1800000002.000100", A))
    assert _bound(env) == [("bound", A)] and sent == []


def test_3_outside_channel_no_binding_post_refused(env, capsys):  # ③ 목록 밖 C = binding 0 · post refused
    sent, posts = [], []
    _listener(env, sent).route(_msg("1800000003.000100", C))
    assert _bound(env) == [] and sent == []
    capsys.readouterr()
    assert _send(env, "post", ["--channel", C], posts, DESK) == 2 and posts == []
    assert capsys.readouterr().out == "state=refused ts= reason=수신 증거 없는 채널\n"


@pytest.mark.parametrize("extra", [{"thread_ts": "1800000004.000100"}, {"bot_id": BOT}, {"subtype": "bot_message"}])
def test_4_second_channel_thread_reply_or_bot_no_binding(env, extra):  # ④ B thread 답글·봇 글 = binding 0
    sent = []
    _listener(env, sent).route(_msg("1800000004.000200", B, **extra))
    assert _bound(env) == [] and sent == []
