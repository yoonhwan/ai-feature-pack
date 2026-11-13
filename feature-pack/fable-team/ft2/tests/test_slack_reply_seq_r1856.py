"""r1856 Slack 보낸이 줄 끝 요청 번호(BYZ mbox seq) 시험 — 설계 §6 1~4 · 임시 root·임시 우편함 기록 · post 대역 · sleep 0.
기준판(팩 origin/main = --seq 모름 usage · 숫자 0)에서 ① ② ④ Red."""
import importlib.util, json, os  # noqa: E401
import pytest

SLACK = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "adapters", "slack")
W, C, TS, SEAT, BODY = "TFAKE", "CFAKE", "1800000001.000100", "byz-planner-desk-pi#147", "사람이 읽을 답\n\n근거: #1"
HUMAN, OTHER, TAG, SEQ = "1800000002.000200", "1800000003.000300", "보낸이 planner-desk", "295767"


def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_r1856_" + name, os.path.join(SLACK, name + ".py"))
    spec.loader.exec_module(module := importlib.util.module_from_spec(spec))
    return module


def _root(root):  # 열린 binding 1개 + 임시 우편함 기록(돌린 파일 .1 에 SEQ)
    binding = _load("binding")
    binding.ThreadBinding(str(root), "planner").bind(binding.thread_key(W, C, TS), SEAT)
    comm = root / ".fable-team" / "comm"
    comm.mkdir(parents=True)
    (comm / "mailbox.log.jsonl").write_text(json.dumps({"seq": 295800, "body": "x"}) + "\n", encoding="utf-8")
    (comm / "mailbox.log.jsonl.1").write_text("깨진 줄\n" + json.dumps({"seq": int(SEQ)}) + "\n", encoding="utf-8")
    receive = root / ".fable-team" / "teams" / "planner" / "slack" / "receive.jsonl"
    receive.write_text(json.dumps({"key": [W, C, TS], "state": "received"}) + "\n", encoding="utf-8")


def _run(root, post, human=HUMAN, tail="a", seq=None, verb="reply", wiring=None):
    (body := root / "body.txt").write_text(BODY, encoding="utf-8")
    argv = [verb, "--root", str(root), "--team", "planner", "--seat", SEAT, "--body-file", str(body)]
    argv += ["--channel", C] if verb == "post" else ["--thread", TS, "--command", "slack:%s:%s:%s:%s" % (W, C, human, tail)]
    argv += ["--seq", seq] if seq is not None else []
    return (wiring or _load("wiring")).main(argv, post=post, sleep=lambda s: None)


@pytest.mark.parametrize("verb", ["reply", "post"])  # post 동사 = --seq 명시만(r1852 겹침 맞춤)
def test_1_seq_on_sender_line(tmp_path, capsys, verb):
    _root(tmp_path)
    posts = []
    assert _run(tmp_path, lambda ch, ts, text, meta: posts.append(text) or "1.1", seq=SEQ, verb=verb) == 0
    assert posts == [BODY + "\n\n" + TAG + " " + SEQ] and capsys.readouterr().err == ""


def test_2_same_human_ts_reuses_number(tmp_path, capsys):
    _root(tmp_path)
    posts = []
    assert _run(tmp_path, lambda ch, ts, text, meta: posts.append(text) or "1.1", seq=SEQ) == 0
    assert _run(tmp_path, lambda ch, ts, text, meta: posts.append(text) or "1.2", tail="b") == 0
    assert [p.splitlines()[-1] for p in posts] == [TAG + " " + SEQ] * 2


def test_2_1_other_human_ts_same_thread_no_number(tmp_path, capsys):
    _root(tmp_path)
    posts = []
    assert _run(tmp_path, lambda ch, ts, text, meta: posts.append(text) or "1.1", human=OTHER, seq=SEQ) == 0
    capsys.readouterr()
    assert _run(tmp_path, lambda ch, ts, text, meta: posts.append(text) or "1.2", tail="b") == 0
    assert posts[1] == BODY + "\n\n" + TAG and len(capsys.readouterr().err.strip().splitlines()) == 1


@pytest.mark.parametrize("bad", ["abc", "295999", "-1", "２９５７６７", ""])
def test_3_bad_seq_posts_without_number(tmp_path, capsys, bad):
    _root(tmp_path)
    posts = []
    assert _run(tmp_path, lambda ch, ts, text, meta: posts.append(text) or "1.1", seq=bad) == 0
    assert posts == [BODY + "\n\n" + TAG] and len(capsys.readouterr().err.strip().splitlines()) == 1


def test_4_resend_after_lost_has_number_once(tmp_path, capsys):
    _root(tmp_path)
    wiring, publish, sent = _load("wiring"), _load("publish"), []
    def lost(ch, ts, text, meta):
        sent.append(text)
        raise wiring.publish.ResponseLost("timeout")
    assert _run(tmp_path, lost, seq=SEQ, wiring=wiring) == 1
    assert _run(tmp_path, lost, wiring=wiring) == 1 and len(sent) == 1  # 같은 의도 결과 불명 = 보류
    revive = publish.SlackPublish(str(tmp_path), team="planner", lookup=lambda marker: publish.ABSENT,
                                  post=lambda root_ts, text, marker, meta: sent.append(text) or "1.2")
    assert revive.resolve(_load("binding").thread_key(W, C, TS))["state"] == publish.RESENT
    assert sent[0] == sent[1] == BODY + "\n\n" + TAG + " " + SEQ and sent[1].count(SEQ) == 1
