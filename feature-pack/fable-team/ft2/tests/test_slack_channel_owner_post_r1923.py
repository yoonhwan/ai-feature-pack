"""r1923 보강 3차 — cli `slack post` 진입 + 채널 주인(owner) 좌석만 새 root 게시 시험 · 반례 ⑱~㉑ · 변이 M11·M12.
임시 root · post 대역 · 실 Slack·실 장부 0 · sleep 0."""
import importlib.util, json, os  # noqa: E401
import pytest

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SLACK = os.path.join(FT2, "adapters", "slack")
W, C, D, AIFP, OTHER = "TFAKE", "C0CHFFHSN4S", "C0C9GRFHJE5", "aifp-ft-master-pi#13", "byz-planner-desk-pi#7"


def _load(path, name):
    spec = importlib.util.spec_from_file_location("ft2_r1923p_" + name, path)
    spec.loader.exec_module(module := importlib.util.module_from_spec(spec))
    return module


@pytest.fixture
def root(tmp_path):
    slack = tmp_path / ".fable-team" / "teams" / "planner" / "slack"
    slack.mkdir(parents=True)
    (tmp_path / "aifp.json").write_text(json.dumps({"_master": AIFP}), encoding="utf-8")
    owner = str(tmp_path / "aifp.json") + "#_master"
    (slack / "CHANNELS").write_text("CMAIN\t\ton\tmain\t-\n%s\t\ton\tadmin\t-\n%s\taifp\ton\treq\t%s\n" % (D, C, owner), encoding="utf-8")
    (slack / "receive.jsonl").write_text("".join(json.dumps({"key": [W, ch, "1800000001.000100"], "state": "received"}) + "\n"
                                                 for ch in (C, D)), encoding="utf-8")
    (tmp_path / "body.txt").write_text("aifp 새 글", encoding="utf-8")
    return tmp_path


def _post(root, seat, channel=C):
    posts = []
    argv = ["post", "--root", str(root), "--team", "planner", "--channel", channel, "--seat", seat, "--body-file", str(root / "body.txt")]
    rc = _load(os.path.join(SLACK, "wiring.py"), "wiring").main(argv, post=lambda ch, ts, text, meta: posts.append((ch, text)) or "1.9",
                                                                 sleep=lambda s: None)
    return rc, posts


def _ledger(root):
    path = root / ".fable-team" / "teams" / "planner" / "slack" / "publish.jsonl"
    return [json.loads(ln) for ln in path.read_text(encoding="utf-8").splitlines()] if path.exists() else []


def test_18_owner_seat_posts_into_receiver_ledger(root, capsys):  # ⑱
    rc, posts = _post(root, AIFP)
    assert rc == 0 and capsys.readouterr().out.startswith("state=posted ts=1.9")
    assert [ch for ch, _ in posts] == [C] and posts[0][1].splitlines()[-1].startswith("보낸이 ft-master")
    assert [r["state"] for r in _ledger(root) if r["state"] == "posted"] == ["posted"]


def test_19_other_seat_refused_not_owner(root, capsys):  # ⑲ + M12
    assert _post(root, OTHER) == (2, []) and "채널 주인 아님" in capsys.readouterr().out and _ledger(root) == []


def test_20_owner_roster_unreadable_undecided(root, capsys):  # ⑳
    os.remove(root / "aifp.json")
    assert _post(root, AIFP) == (3, []) and "판정불가" in capsys.readouterr().out


def test_21_dash_owner_channel_unchanged(root, capsys):  # ㉑ owner `-` = 지금 규칙(수신 증거만)
    rc, posts = _post(root, OTHER, channel=D)
    assert rc == 0 and [ch for ch, _ in posts] == [D]


def test_cli_slack_post_enters_wiring(root, monkeypatch, capsys):  # ⑧ + M11 — 사용법 rc 64 아님(토큰 없음 = 판정불가 3)
    monkeypatch.delenv("SLACK_BOT_TOKEN", raising=False)
    monkeypatch.delenv("FT2_SLACK_ENV", raising=False)
    cli = _load(os.path.join(FT2, "core", "cli.py"), "cli")
    argv = ["slack", "post", "--root", str(root), "--team", "planner", "--channel", C, "--seat", AIFP, "--body-file", str(root / "body.txt")]
    assert cli.main(argv) == 3 and "SLACK_BOT_TOKEN 없음" in capsys.readouterr().out
