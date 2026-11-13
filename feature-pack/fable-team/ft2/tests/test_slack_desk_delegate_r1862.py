"""r1862 desk 대신 답 시험 — 카드 반례 ①~④ · 임시 root · post 대역 · 실 Slack·실 명부·실 장부 0 · sleep 0.
명부 `_desk` 현역 좌석 = binding 주인(planner master) 대신 같은 gen 으로 답 · binding 쓰기 0.
기준판(팩 origin/main = delegate 없음)에서 ① Red(stale_owner rc2)."""
import importlib.util, json, os  # noqa: E401

SLACK = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "adapters", "slack")
W, C, TS = "TFAKE", "CFAKE", "1800000001.000100"
CMD, MASTER = "slack:%s:%s:%s" % (W, C, TS), "byz-planner-master-pi#288"
DESK, OLD_DESK = "byz-planner-desk-pi#2", "byz-planner-desk-pi#1"


def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_r1862_" + name, os.path.join(SLACK, name + ".py"))
    spec.loader.exec_module(module := importlib.util.module_from_spec(spec))
    return module


def _setup(root, roster=True, close=False):
    binding = _load("binding")
    ledger, key = binding.ThreadBinding(str(root), "planner"), binding.thread_key(W, C, TS)
    ledger.bind(key, MASTER)
    for _ in range(4):  # 교대 이어받기 → gen5 (실사건 planner master gen5)
        ledger.handover(key, MASTER)
    if close:
        ledger.close(key)
    if roster:
        (root / ".fable-team" / "seats-planner.json").write_text(json.dumps({"_desk": DESK}), encoding="utf-8")
    return ledger


def _reply(root, seat, posts):
    (body := root / "body.txt").write_text("사람이 읽을 답", encoding="utf-8")
    argv = ["reply", "--root", str(root), "--team", "planner", "--thread", TS, "--seat", seat,
            "--body-file", str(body), "--command", CMD]
    post = lambda ch, ts, text, meta: posts.append(text) or "1.5"  # noqa: E731
    return _load("wiring").main(argv, post=post, sleep=lambda s: None)


def _lines(ledger):
    with open(ledger.path, encoding="utf-8") as handle:
        return handle.read().splitlines()


def test_1_roster_desk_posts_without_binding_write(tmp_path, capsys):
    ledger, posts = _setup(tmp_path), []
    before = _lines(ledger)
    assert _reply(tmp_path, DESK, posts) == 0
    assert capsys.readouterr().out.startswith("state=posted ts=1.5")
    assert len(posts) == 1 and _lines(ledger) == before  # binding 줄 수·내용 그대로(handover 0)
    now = ledger.get(_load("binding").thread_key(W, C, TS))
    assert (now.seat, now.gen) == (MASTER, 5)
    pub = _load("publish").SlackPublish(str(tmp_path), team="planner", post=None)
    intent = [r for r in pub.entries() if r["state"] == "intent"]
    assert [r["owner"] for r in intent] == [DESK + "#5"]  # 누가 답했는지 장부에 남김


def test_2_old_desk_still_stale_owner(tmp_path, capsys):
    _setup(tmp_path)
    posts = []
    assert _reply(tmp_path, OLD_DESK, posts) == 2
    assert "reason=stale_owner" in capsys.readouterr().out and posts == []


def test_3_no_roster_desk_stale_owner(tmp_path, capsys):
    _setup(tmp_path, roster=False)
    posts = []
    assert _reply(tmp_path, DESK, posts) == 2
    assert "reason=stale_owner" in capsys.readouterr().out and posts == []


def test_4_closed_binding_refused_first(tmp_path, capsys):
    _setup(tmp_path, close=True)
    posts = []
    assert _reply(tmp_path, DESK, posts) == 2
    assert capsys.readouterr().out.startswith("state=refused") and posts == []
    publish, binding = _load("publish"), _load("binding")
    pub = publish.SlackPublish(str(tmp_path), team="planner", post=posts.append, delegate=DESK)
    row = pub.reply(binding.thread_key(W, C, TS), CMD + ":x", "답", DESK, 5)
    assert row["k"] == "reply_refused" and posts == []  # 닫힘 우선


def _rotate_reply(root, during, posts):  # R1 — 첫 post 429 · 대기 callback 사이 명부 바꿈 → 재시도 직전 재판독
    (body := root / "body.txt").write_text("사람이 읽을 답", encoding="utf-8")
    wiring = _load("wiring")
    def post(ch, ts, text, meta):
        posts.append(text)
        if len(posts) == 1:
            raise wiring.publish.RateLimited(0)
        return "1.6"
    argv = ["reply", "--root", str(root), "--team", "planner", "--thread", TS, "--seat", DESK,
            "--body-file", str(body), "--command", CMD]
    return wiring.main(argv, post=post, sleep=lambda s: during(root / ".fable-team" / "seats-planner.json"))


def test_5_desk_rotated_during_429_wait_no_post(tmp_path, capsys):
    _setup(tmp_path)
    posts = []
    rotate = lambda roster: roster.write_text(json.dumps({"_desk": "byz-planner-desk-pi#3"}))  # noqa: E731
    assert _rotate_reply(tmp_path, rotate, posts) == 2
    assert "reason=stale_owner" in capsys.readouterr().out and len(posts) == 1  # 옛 desk 두 번째 post 0


def test_6_roster_unreadable_on_reread_no_post(tmp_path, capsys):
    _setup(tmp_path)
    posts = []
    assert _rotate_reply(tmp_path, lambda roster: roster.write_text("{깨짐"), posts) == 2
    assert "reason=stale_owner" in capsys.readouterr().out and len(posts) == 1  # 못 읽음 = 대신 답 0
