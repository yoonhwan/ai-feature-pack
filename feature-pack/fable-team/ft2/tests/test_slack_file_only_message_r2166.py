"""r2166 — 본문 없이 파일만 올린 Slack 글도 새 업무로 넘어간다(반례 ①~⑨ · ⑪ · ⑫ · 계약 T1~T4).

대역 = 가짜 client(submit 본문 기록) · 임시 state 폴더 · 대역 사건 dict · 고정 시계. 실 Slack · token · 네트워크 0.
«기준판» = 채움 함수를 «그대로 돌려줌» 으로 바꾼 같은 판(이 카드가 바꾸는 곳은 채움 1곳뿐이다).
파일 사건 꼴 = Slack 공개 문서 꼴(subtype file_share · files[].id · name) — 실사건 대조는 설치 뒤 master 몫.
"""

import copy
import importlib.util
import os
from types import SimpleNamespace

import pytest

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADAPTER_DIR = os.path.join(FT2, "adapters", "slack")
TEAM, W, C, DESK = "harness", "TFAKE", "CFAKE", "@team-desk"
TS, T2, T3, T4, T5 = ("1800000001.000100", "1800000002.000100", "1800000003.000100",
                      "1800000004.000100", "1800000005.000100")


def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_r2166_" + name, os.path.join(ADAPTER_DIR, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


slack, route_mod, binding = _load("receive"), _load("route"), _load("binding")


class _Client:
    """가짜 입구 — submit 본문만 기록하고 «접수 성공» 영수를 돌려준다."""
    def __init__(self):
        self.bodies = []

    def submit(self, command, body, work=None):
        self.bodies.append(body)
        return SimpleNamespace(result=slack.RESULT_OK, command=command, attempt=command + "#a1",
                               revision=len(self.bodies), written=True, body_ref=None, reason="")

    def lookup(self, command):
        return None


def _env(tmp, baseline=False, monkeypatch=None):
    if baseline:  # 기준판 = 채움 0
        monkeypatch.setattr(slack.SlackReceive, "with_file_text", lambda self, event: event, raising=False)
    acks, notes, delivered, client = [], [], [], _Client()
    receive = slack.SlackReceive(str(tmp), ack=acks.append, client=client, team=TEAM, allowed_users={"U1"},
                                 allowed_channels={C}, bot_users={"UB"}, clock=lambda: "T")
    binder = binding.ThreadBinding(str(tmp), TEAM, clock=lambda: "T")
    route = route_mod.SlackRoute(str(tmp), receive=receive, bindings=binder, team=TEAM, clock=lambda: "T",
                                 notify=notes.append,
                                 deliver=lambda to, kind, lines: delivered.append({"to": to, "lines": list(lines)}))
    return SimpleNamespace(route=route, receive=receive, binder=binder, client=client, notes=notes,
                           delivered=delivered, acks=acks)


def _event(**extra):
    return dict({"type": "message", "team": W, "channel": C, "ts": TS, "user": "U1", "text": "안녕"}, **extra)


def _files(*pairs):
    return [{"id": fid, "name": name, "filetype": "zip", "size": 10} for fid, name in pairs]


def _file_event(files, **extra):
    return _event(**dict({"text": "", "subtype": "file_share", "files": files}, **extra))


def _rows(env):
    return [r.get("state") for r in env.receive.entries()]


def _bytes(tmp):
    folder = os.path.join(str(tmp), ".fable-team", "teams", TEAM, "slack")
    return {name: open(os.path.join(folder, name), encoding="utf-8").read()
            for name in sorted(os.listdir(folder)) if name.endswith(".jsonl")}


def _asked(env, request_id="Q7"):
    """요청이 등록된 열린 thread — 질문 root 1건이 dispatched 된 상태."""
    env.binder.bind(route_mod.thread_key(_event()), "seat-a")
    assert env.route.route(_event(request_id=request_id, text="질문"))["state"] == "dispatched"


# ── T1 넘김 ────────────────────────────────────────────────────────────────
def test_1_root_file_only_dispatched_to_desk(tmp_path):
    env = _env(tmp_path)
    row = env.route.route(_file_event(_files(("F1", "report.zip"))))
    assert row["state"] == "dispatched" and (row["kind"], row["to"]) == ("재개 필요", DESK)
    assert _rows(env) == ["received", "dispatched"]
    assert env.client.bodies == ["[파일 1개 · 본문 없음] report.zip(F1)"]
    assert env.receive.entries()[0]["text"] == "[파일 1개 · 본문 없음] report.zip(F1)"
    assert len(env.route.entries("route")) == 1 and len(env.notes) == 1


def test_2_open_thread_reply_reaches_seat_with_file_line(tmp_path):
    env = _env(tmp_path)
    env.binder.bind(route_mod.thread_key(_event()), "seat-a")
    env.route.route(_event(text="첫 글"))
    seen = len(env.delivered)
    row = env.route.route(_file_event(_files(("F1", "a.zip"), ("F2", "b.png")), ts=T2, thread_ts=TS, text=" "))
    assert row["state"] == "dispatched" and len(env.delivered) - seen == 1
    assert env.delivered[-1]["to"] == "seat-a"
    assert env.delivered[-1]["lines"][-1] == "%s U1 [파일 2개 · 본문 없음] a.zip(F1) · b.png(F2)" % T2


def test_3_file_line_shape(tmp_path):
    receive = _env(tmp_path).receive
    many = _files(*[("F%d" % n, "r%d.zip" % n) for n in range(1, 13)])
    text = receive.with_file_text(_file_event(many))["text"]
    assert text == ("[파일 12개 · 본문 없음] " + " · ".join("r%d.zip(F%d)" % (n, n) for n in range(1, 11))
                    + " · 외 2개(F11 · F12)")
    odd = [{"id": "F 1\n2", "name": "a\nb\tc.zip"}, {"name": "x" * 100}, {"id": "F3"}]
    text = receive.with_file_text(_file_event(odd))["text"]
    assert text == "[파일 3개 · 본문 없음] a b c.zip(F 1 2) · %s(id 없음) · 이름 없음(F3)" % ("x" * 80)


# ── T2 버림 유지 ───────────────────────────────────────────────────────────
DROPS = [({"bot_id": "BOT"}, "bot"), ({"user": "UB"}, "bot"), ({"user": "UX"}, "미인가 사용자"),
         ({"channel": "COTHER"}, "허용 밖 채널"), ({"type": "file_shared"}, "message 아님")]


@pytest.mark.parametrize("extra,reason", DROPS)
def test_4_filtered_file_posts_stay_ignored(tmp_path, monkeypatch, extra, reason):
    event = _file_event(_files(("F1", "report.zip")), **extra)
    env = _env(tmp_path / "new")
    row = env.route.route(copy.deepcopy(event))
    assert (row["state"], row["why"], env.client.bodies) == ("ignored", reason, [])
    base = _env(tmp_path / "base", baseline=True, monkeypatch=monkeypatch)
    base.route.route(copy.deepcopy(event))
    assert _bytes(tmp_path / "new") == _bytes(tmp_path / "base")


def test_5_message_changed_same_as_baseline(tmp_path, monkeypatch):
    event = _event(subtype="message_changed", text="", user=None,
                   message={"user": "U1", "text": "", "files": _files(("F1", "report.zip"))})
    env = _env(tmp_path / "new")
    env.route.route(copy.deepcopy(event))
    base = _env(tmp_path / "base", baseline=True, monkeypatch=monkeypatch)
    base.route.route(copy.deepcopy(event))
    assert _bytes(tmp_path / "new") == _bytes(tmp_path / "base") and env.client.bodies == []


@pytest.mark.parametrize("files", ["absent", [], "x", [None, "x"]])
def test_6_no_dict_files_stays_no_change(tmp_path, files):
    env = _env(tmp_path)
    event = _event(text="") if files == "absent" else _event(text="", files=files)
    row = env.route.route(event)
    assert (row["state"], row["why"], env.client.bodies) == ("ignored", "무변화", [])


def test_6_empty_dict_file_named_absent(tmp_path):
    env = _env(tmp_path)
    assert env.route.route(_event(text="", files=[{}]))["state"] == "dispatched"
    assert env.client.bodies == ["[파일 1개 · 본문 없음] 이름 없음(id 없음)"]


# ── T3 중복 ────────────────────────────────────────────────────────────────
def test_7_same_key_twice_and_ignored_key_stays(tmp_path):
    env = _env(tmp_path / "a")
    event = _file_event(_files(("F1", "report.zip")))
    first, again = env.route.route(copy.deepcopy(event)), env.route.route(copy.deepcopy(event))
    assert (first["state"], again["state"], len(env.client.bodies)) == ("dispatched", "duplicate", 1)
    env = _env(tmp_path / "b")
    assert env.route.route(_event(text=""))["why"] == "무변화"
    again = env.route.route(_file_event(_files(("F1", "report.zip"))))
    assert (again["state"], env.client.bodies) == ("ignored", [])


def _two_answers(env, first, second):
    _asked(env)
    a = env.route.route(_file_event(first, ts=T2, thread_ts=TS))
    b = env.route.route(_file_event(second, ts=T3, thread_ts=TS))
    return a, b


def test_8_two_file_answers_same_name_other_id(tmp_path):
    env = _env(tmp_path)
    a, b = _two_answers(env, _files(("F1", "report.zip")), _files(("F2", "report.zip")))
    assert (a["state"], b["state"], len(env.client.bodies)) == ("dispatched", "dispatched", 3)
    env = _env(tmp_path / "same")
    a, b = _two_answers(env, _files(("F1", "report.zip")), _files(("F1", "report.zip")))
    assert (a["state"], b["state"], len(env.client.bodies)) == ("dispatched", "duplicate", 2)


# ── T4 불변 ────────────────────────────────────────────────────────────────
def test_9_text_with_files_unchanged(tmp_path, monkeypatch):
    event = _event(text="보고서", files=_files(("F1", "report.zip")))
    frozen = copy.deepcopy(event)
    env = _env(tmp_path / "new")
    row = env.route.route(event)
    assert event == frozen
    assert (env.client.bodies, row["digest"]) == (["보고서"], "보고서")
    base = _env(tmp_path / "base", baseline=True, monkeypatch=monkeypatch)
    base.route.route(copy.deepcopy(frozen))
    assert _bytes(tmp_path / "new") == _bytes(tmp_path / "base")
    monkeypatch.undo()
    receive = _env(tmp_path / "pure").receive
    bare = _file_event(_files(("F1", "report.zip")))
    once = receive.with_file_text(bare)
    assert receive.with_file_text(once) == once and bare["text"] == "" and once is not bare
    assert receive.with_file_text(frozen) == frozen


# ── 사전 DA R1 · R2 ─────────────────────────────────────────────────────────
def test_11_eleven_files_last_id_differs(tmp_path):
    env = _env(tmp_path)
    common = [("F%d" % n, "r%d.zip" % n) for n in range(1, 11)]
    seen = len(env.delivered)
    a, b = _two_answers(env, _files(*common, ("F11", "last.zip")), _files(*common, ("F12", "last.zip")))
    assert (a["state"], b["state"]) == ("dispatched", "dispatched")
    assert len(env.client.bodies) == 3 and len(env.delivered) - seen == 3  # 질문 1 + 답 2
    assert env.client.bodies[1] != env.client.bodies[2]


def test_12_filtered_copies_after_answer_stay_ignored(tmp_path):
    env = _env(tmp_path)
    _asked(env)
    first = env.route.route(_file_event(_files(("F1", "report.zip")), ts=T2, thread_ts=TS))
    assert first["state"] == "dispatched"
    bodies, delivered = len(env.client.bodies), len(env.delivered)
    rows = [env.route.route(_file_event(_files(("F1", "report.zip")), ts=ts, thread_ts=TS, **extra))
            for ts, extra in ((T3, {"bot_id": "BOT"}), (T4, {"user": "UB"}), (T5, {"user": "UX"}))]
    assert [(r["state"], r["why"]) for r in rows] == [("ignored", "bot"), ("ignored", "bot"),
                                                      ("ignored", "미인가 사용자")]
    assert [r.get("reason") for r in env.receive.entries()[-3:]] == ["bot", "bot", "미인가 사용자"]
    assert (len(env.client.bodies), len(env.delivered)) == (bodies, delivered)
