"""r1850 Slack 글 보낸이 표시 시험 — 설계 §5 ①~③ · 임시 root · post 대역 · 실 Slack·실 우편함 0 · sleep 0.
기준판(팩 origin/main = sender_tag.py 없음)에서 ① ② ③ Red."""
import importlib.util, os  # noqa: E401
import pytest

SLACK = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "adapters", "slack")
W, C, TS, SEAT, BODY = "TFAKE", "CFAKE", "1800000001.000100", "byz-planner-desk-pi#147", "사람이 읽을 답\n\n근거: #1"
CMD, TAG = "slack:%s:%s:%s" % (W, C, TS), "보낸이 planner-desk"


def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_r1850_" + name, os.path.join(SLACK, name + ".py"))
    spec.loader.exec_module(module := importlib.util.module_from_spec(spec))
    return module


@pytest.mark.parametrize("seat, want", [
    ("byz-planner-desk-pi#147", "보낸이 planner-desk"),
    ("byz-planner-master-pi#287", "보낸이 planner-master"),
    ("byz-planner-arch-claude#3", "보낸이 planner-arch"),
    ("byz-cfo-nano-cfo-pub-turnkey-atom-it-planner-rate#0", "보낸이 cfo-nano"),
    ("byz-planner-desk-gpt#1", None),  # lint 실패(에이전트 낱말 밖) = 표시 0
    ("byz-cfo-nano#0", None),  # lint 실패(nano slug 꼬리 없음) = 표시 0 (DA HOLD R1)
])
def test_1_sender_tag_table(seat, want):
    assert _load("sender_tag").sender_tag(seat) == want


def _bind(root):
    binding = _load("binding")
    binding.ThreadBinding(str(root), "planner").bind(binding.thread_key(W, C, TS), SEAT)


def _reply(root, post, seat=SEAT, wiring=None):
    (body := root / "body.txt").write_text(BODY, encoding="utf-8")
    argv = ["reply", "--root", str(root), "--team", "planner", "--thread", TS, "--seat", seat,
            "--body-file", str(body), "--command", CMD]
    return (wiring or _load("wiring")).main(argv, post=post, sleep=lambda s: None)


def test_2_wiring_body_last_line_is_tag(tmp_path, capsys):
    _bind(tmp_path)
    posts = []
    assert _reply(tmp_path, lambda ch, ts, text, meta: posts.append(text) or "1.1") == 0
    assert posts == [BODY + "\n\n" + TAG] and posts[0].splitlines()[-1] == TAG  # 원문 그대로 · 근거 줄 뒤 · 맨 끝


@pytest.mark.parametrize("bad", ["byz-planner-desk-gpt#1", "byz-planner-nano#0"])
def test_2b_lint_fail_posts_without_tag(tmp_path, capsys, bad):
    binding = _load("binding")
    binding.ThreadBinding(str(tmp_path), "planner").bind(binding.thread_key(W, C, TS), bad)
    posts = []
    assert _reply(tmp_path, lambda ch, ts, text, meta: posts.append(text) or "1.1", seat=bad) == 0
    assert posts == [BODY] and len(capsys.readouterr().err.strip().splitlines()) == 1  # 게시 rc0 · stderr 1줄


def test_3_resend_after_lost_has_tag_once(tmp_path, capsys):
    _bind(tmp_path)
    wiring, publish, sent = _load("wiring"), _load("publish"), []
    def lost(ch, ts, text, meta):
        sent.append(text)
        raise wiring.publish.ResponseLost("timeout")  # wiring 이 잡는 그 클래스
    assert _reply(tmp_path, lost, wiring=wiring) == 1 and "state=uncertain" in capsys.readouterr().out
    revive = publish.SlackPublish(str(tmp_path), team="planner", lookup=lambda marker: publish.ABSENT,
                                  post=lambda root_ts, text, marker, meta: sent.append(text) or "1.2")
    key = _load("binding").thread_key(W, C, TS)
    assert revive.resolve(key)["state"] == publish.RESENT  # 되살림 = 장부 본문 그대로 재송
    assert sent[0] == sent[1] == BODY + "\n\n" + TAG and sent[1].count(TAG) == 1
