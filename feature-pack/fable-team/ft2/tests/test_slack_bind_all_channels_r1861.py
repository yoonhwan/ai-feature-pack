"""r1861 r1 받는 채널 목록 «채널별 주인» binding 시험 — 반례 ①~⑤ · 변이 M1·M2·M3 · 주 채널 = _master · 그 밖 = _desk.
임시 root · 가짜 web·깨움 · post 대역 · 실 Slack·실 장부·설치 0 · sleep 0 · 기준판에서 ① ⑤ Red."""
import importlib.util, json, os, sys  # noqa: E401
import pytest

SLACK = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "adapters", "slack")
W, A, B, C, U = "TFAKE", "CMAIN", "CDESK", "COTHER", "UOPPA"
MASTER, DESK = "byz-planner-master-pi#1", "byz-planner-desk-pi#1"
WAKE = "import json, os, sys\nopen(os.environ['FAKE_WAKE_OUT'], 'a').write(json.dumps(sys.argv[1:]) + '\\n')\n"


def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_r1861_" + name, os.path.join(SLACK, name + ".py"))
    spec.loader.exec_module(module := importlib.util.module_from_spec(spec))
    return module


@pytest.fixture
def env(tmp_path, monkeypatch):
    (fable := tmp_path / ".fable-team").mkdir()
    for team, seats in (("planner", {"_master": MASTER, "_desk": DESK}), ("issues", {"_master": "byz-issues-master-sol#1"})):
        (fable / ("seats-%s.json" % team)).write_text(json.dumps(seats), encoding="utf-8")
    (script := tmp_path / "wake.py").write_text(WAKE, encoding="utf-8")
    monkeypatch.setenv("FT2_SLACK_WAKE", "%s %s" % (sys.executable, script))
    monkeypatch.setenv("FAKE_WAKE_OUT", str(tmp_path / "wakes.jsonl"))
    return tmp_path


def _route(root, event, desk=DESK):  # 수신기 1개로 가짜 글 1개 — 반환 = Slack 게시 호출 수
    sent = []
    _load("socket").Listener(str(root), channel="%s,%s" % (A, B), app_token="xapp-F", bot_token="xoxb-F", master=MASTER,
                             desk=desk, users=(U,), web=lambda method, *a, **k: sent.append(method) or {"ok": True},
                             connect=None, clock=lambda: "2026-11-13T00:00:00").route(event)
    return len([m for m in sent if m == "chat.postMessage"])


def _msg(ts, channel, **extra):
    return dict({"type": "message", "user": U, "channel": channel, "ts": ts, "team": W, "text": "글 " + ts}, **extra)


def _rows(root, name):
    path = root / ("wakes.jsonl" if name == "wakes" else ".fable-team/teams/planner/slack/" + name)
    return [json.loads(ln) for ln in path.read_text(encoding="utf-8").splitlines()] if path.exists() else []


def _state(root):  # (binding (채널, 좌석), master 깨움 수, desk 깨움 수)
    wakes = [r[1] for r in _rows(root, "wakes")]
    return [(r["key"][1], r["seat"]) for r in _rows(root, "bindings.jsonl")], wakes.count(MASTER), wakes.count(DESK)


def _send(root, verb, where, posts, seat=DESK):
    (body := root / "body.txt").write_text("답", encoding="utf-8")
    argv = [verb, "--root", str(root), "--team", "planner", "--seat", seat, "--body-file", str(body)] + where
    return _load("wiring").main(argv, post=lambda ch, ts, text, meta: posts.append((ch, ts)) or "1.9", sleep=lambda s: None)


def test_1_second_channel_root_desk_owner_desk_reply_posted(env, capsys):  # ① B → desk 주인 · desk 깨움 1 · 게시 B
    posts, ts = [], "1800000001.000100"
    assert _route(env, _msg(ts, B)) == 0 and _state(env) == ([(B, DESK)], 0, 1)
    assert _send(env, "reply", ["--thread", ts, "--command", "slack:%s:%s:%s:a" % (W, B, ts)], posts) == 0
    assert capsys.readouterr().out.startswith("state=posted ") and posts == [(B, ts)]


def test_2_main_channel_root_master_owner(env):  # ② A 새 root = 그대로 master 주인
    assert _route(env, _msg("1800000002.000100", A)) == 0 and _state(env) == ([(A, MASTER)], 1, 0)


def test_3_outside_channel_no_binding_post_refused(env, capsys):  # ③ 목록 밖 C = binding 0 · post refused
    posts = []
    assert _route(env, _msg("1800000003.000100", C)) == 0 and _state(env)[0] == []
    assert _send(env, "post", ["--channel", C], posts) == 2 and posts == []
    assert capsys.readouterr().out.endswith("state=refused ts= reason=수신 증거 없는 채널\n")


@pytest.mark.parametrize("extra", [{"thread_ts": "1800000004.000100"}, {"bot_id": "BF"}, {"subtype": "bot_message"}])
def test_4_second_channel_thread_reply_or_bot_no_binding(env, extra):  # ④ B thread 답글·봇 글 = binding 0
    assert _route(env, _msg("1800000004.000200", B, **extra)) == 0 and _state(env)[0] == []


def test_5_no_desk_seat_keeps_desk_door(env):  # ⑤ 명부 _desk 칸 없음 → desk=None · B 묶기 0 · 재개 필요 → @team-desk
    (creds := env / "slack.env").write_text("SLACK_APP_TOKEN=xapp-F\nSLACK_BOT_TOKEN=xoxb-F\n", encoding="utf-8")
    for seats, want in (({"_master": MASTER}, None), ({"_master": MASTER, "_desk": DESK}, DESK)):
        (owner := env / "owner.json").write_text(json.dumps(seats), encoding="utf-8")
        assert _load("socket").read_inputs(str(creds), str(owner))[1:] == (MASTER, want)
    assert _route(env, _msg("1800000005.000100", B), desk=None) == 0 and _state(env) == ([], 0, 1)
    assert [(r["kind"], r["to"]) for r in _rows(env, "route.jsonl") if r["t"] == "route"] == [("재개 필요", "@team-desk")]
