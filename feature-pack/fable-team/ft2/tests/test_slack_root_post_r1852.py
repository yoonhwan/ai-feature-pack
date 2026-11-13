"""r1852 desk 채널 새 root 게시 시험 — 카드 반례 ①~③ · 임시 root · post 대역 · 실 Slack·실 장부 0 · sleep 0.
기준판(팩 origin/main = post 동사 없음 usage)에서 ① ③ Red."""
import importlib.util, io, json, os, urllib.parse, urllib.request  # noqa: E401

SLACK = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "adapters", "slack")
W, C, SEAT, BODY, TAG = "TFAKE", "C0DESK", "byz-planner-desk-pi#149", "desk 새 글\n\n근거: #1", "보낸이 planner-desk"


def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_r1852_" + name, os.path.join(SLACK, name + ".py"))
    spec.loader.exec_module(module := importlib.util.module_from_spec(spec))
    return module


def _heard(root, channel=C):  # 수신기가 그 채널 글을 받아들인 증거 1행(임시 root)
    path = root / ".fable-team" / "teams" / "planner" / "slack" / "receive.jsonl"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"key": [W, channel, "1800000001.000100"], "state": "received"}) + "\n", encoding="utf-8")


def _post(root, post, wiring=None, channel=C):
    (body := root / "body.txt").write_text(BODY, encoding="utf-8")
    argv = ["post", "--root", str(root), "--team", "planner", "--channel", channel, "--seat", SEAT,
            "--body-file", str(body)]
    return (wiring or _load("wiring")).main(argv, post=post, sleep=lambda s: None)


def _ledger(root):
    path = root / ".fable-team" / "teams" / "planner" / "slack" / "publish.jsonl"
    return [json.loads(ln) for ln in path.read_text(encoding="utf-8").splitlines()] if path.exists() else []


def test_1_desk_channel_new_root_has_tag(tmp_path, capsys):
    _heard(tmp_path)
    posts = []
    assert _post(tmp_path, lambda ch, ts, text, meta: posts.append((ch, ts, text)) or "1.9") == 0
    assert posts == [(C, "", BODY + "\n\n" + TAG)] and capsys.readouterr().out == "state=posted ts=1.9\n"
    rows = _ledger(tmp_path)
    assert [r["state"] for r in rows if r["state"] != "attempt"] == ["intent", "posted"]
    assert rows[0]["key"] == [W, C, ""] and rows[0]["command"].startswith("post:%s:%s:" % (C, SEAT))
    assert _load("binding").ThreadBinding(str(tmp_path), "planner").settled() == {}  # binding 자동 열기 0


def test_1b_slack_post_omits_empty_thread_ts(monkeypatch):  # 가짜 urlopen · 실 Slack 0
    sent = []
    def fake(req, timeout):
        sent.append(dict(urllib.parse.parse_qsl(req.data.decode(), keep_blank_values=True)))
        return io.BytesIO(b'{"ok": true, "ts": "1.9"}')
    monkeypatch.setattr(urllib.request, "urlopen", fake)
    post = _load("wiring").slack_post("xoxb-fake")
    assert post(C, "", "t", {}) == "1.9" and post(C, "1.1", "t", {}) == "1.9"
    assert "thread_ts" not in sent[0] and sent[1]["thread_ts"] == "1.1"


def test_2_unheard_channel_refused(tmp_path, capsys):
    _heard(tmp_path)
    posts = []
    assert _post(tmp_path, lambda *a: posts.append(a) or "1.9", channel="C0OTHER") == 2
    assert posts == [] and capsys.readouterr().out.startswith("state=refused ") and _ledger(tmp_path) == []


def test_3_same_body_duplicate_and_lost_not_resent(tmp_path, capsys):
    _heard(tmp_path)
    posts = []
    assert _post(tmp_path, lambda *a: posts.append(a) or "1.9") == 0
    assert _post(tmp_path, lambda *a: posts.append(a) or "2.9") == 0
    assert len(posts) == 1 and capsys.readouterr().out.splitlines()[-1] == "state=duplicate ts=1.9"
    other, wiring = tmp_path / "lost", _load("wiring")
    other.mkdir()
    _heard(other)
    def lost(*a):
        posts.append(a)
        raise wiring.publish.ResponseLost("timeout")
    assert _post(other, lost, wiring=wiring) == 1 and _post(other, lost, wiring=wiring) == 1
    assert len(posts) == 2 and capsys.readouterr().out.splitlines()[-1].startswith("state=uncertain ")
