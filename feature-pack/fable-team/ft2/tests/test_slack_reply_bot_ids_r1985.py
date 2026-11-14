"""r1985 desk 신원 thread 답 = 앞 글 접수 완료 — SLACK_REPLY_BOT_USER_IDS(--env 쉼표 목록)는 답 완료 판정에만 더함.
반례 ①~⑤ + HOLD R1(추가 신원의 가입·탈퇴 = 자동 채널 손 0) · 변이 M1~M4. ENV 파일 → socket.main → 실 Listener(run 대신 잡기)
· 실 SlackReceive·Channels·Intake·Dispatch · 가짜 web·ACK · 실 Slack 0 · sleep 0."""
import importlib.util, json, os, shutil  # noqa: E401
import pytest

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEAM, W, C, TANK, DESK, U, A = "planner", "TFAKE", "CFAKE", "UTANK", "UDESK", "U1", "1800000000.000100"
CMD, SOCK, RX, IDS = "slack:%s:%s:%s" % (W, C, A), "adapters/slack/socket.py", "adapters/slack/receive.py", "SLACK_REPLY_BOT_USER_IDS"


def _load(rel, base=FT2, tag="base"):
    spec = importlib.util.spec_from_file_location("r1985_%s_%s" % (tag, os.path.basename(rel)[:-3]), os.path.join(base, rel))
    spec.loader.exec_module(module := importlib.util.module_from_spec(spec))
    return module


S, D = _load(SOCK), _load("core/dispatch.py")


@pytest.fixture
def root(tmp_path, monkeypatch):
    for name in ("FT2_SLACK_WAKE", "FT2_FULL_ALERT_WAKE"):
        monkeypatch.setenv(name, "true")
    return tmp_path


def boot(s, root, extra):  # ENV 파일 → main → 실 Listener
    os.makedirs(root, exist_ok=True), (root / "seats.json").write_text(json.dumps({"_master": "m#1"}), encoding="utf-8")
    (root / "x.env").write_text("SLACK_APP_TOKEN=xapp-F\nSLACK_BOT_TOKEN=xoxb-F\nSLACK_BOT_USER_ID=%s\n%s" % (TANK, extra), encoding="utf-8")
    got, run = [], s.Listener.run
    s.Listener.run = lambda self: got.append(self) or 0
    try:
        assert s.main(["--root", str(root), "--env", str(root / "x.env"), "--owner-seats", str(root / "seats.json"),
                       "--channel", C, "--users", U]) == 0
    finally:
        s.Listener.run = run
    got[0].web = lambda *a, **kw: {"ok": True, "channel": {"is_channel": True, "name": "auto"}}
    got[0].ws = type("WS", (), {"send": lambda self, message: None})()
    return got[0]


def scenario(s, root, extra="%s= UOTHER2 ,, %s \n" % (IDS, DESK), user=DESK, thread=A, owned=False):
    rx = boot(s, root, extra).receive
    rx.handle({"type": "message", "team": W, "channel": C, "ts": A, "user": U, "text": "글"})
    rs = D.intake.Intake(str(root), TEAM)
    if owned:  # 배정 계보(dispatch 줄) = r1927 test_4 와 같은 꼴
        rs._append_journal(D.record.build(TEAM, len(rs.records()) + 1, CMD, CMD + "#a1", "2026-11-14T00:00:00",
                                          CMD, CMD, kind="dispatch", holder="nano#0", gen=1))
    event = {"type": "message", "team": W, "channel": C, "ts": "1800000005.000100", "user": user, "bot_id": "BX", "text": "답"}
    row = rx.handle(dict(event, **({"thread_ts": thread} if thread else {})))
    state = D.record.recover_state(rs._state(), rs.records())
    return "settle" in row, (row.get("settle") or {}).get("completed", 0), len(D.record.remaining(state, rs.records()))


def test_1_desk_thread_reply_completes(root):
    assert scenario(S, root) == (True, 1, 0)


@pytest.mark.parametrize("extra", ["", "%s=\n" % IDS, "%s= , \n" % IDS])
def test_2_no_or_empty_setting_same_as_now(root, extra):
    assert (sorted(boot(S, root, extra).receive.bot_users), scenario(S, root, extra)) == ([TANK], (False, 0, 1))


@pytest.mark.parametrize("kw", [({"user": "UOTHER"}, False), ({"thread": None}, False), ({"owned": True}, True)],
                         ids=["3_other", "4_root", "5_owned"])
def test_3_4_5_other_bot_root_post_owned_untouched(root, kw):  # ⑤ = settle 시도 · 배정 계보 = 완료 0
    assert scenario(S, root, **kw[0]) == (kw[1], 0, 1)


def membership(s, root, user=DESK):  # HOLD R1 — 추가 신원 탈퇴(CAUTO)·가입(CNEW) → 자동 채널 · 다음 사람 글
    li = boot(s, root, "%s=%s\n" % (IDS, DESK))
    li.chan.add_auto("CAUTO", "auto")
    for n, (kind, channel) in enumerate((("member_left_channel", "CAUTO"), ("member_joined_channel", "CNEW"))):
        li._frame({"type": "events_api", "envelope_id": "E%d" % n, "payload": {"event": {"type": kind, "channel": channel, "user": user}}})
    row = li.receive.handle({"type": "message", "team": W, "channel": "CAUTO", "ts": "1800000030.000100", "user": U, "text": "새 글"})
    return sorted(li.chan.allowed), row["state"]


def test_r1_reply_identity_join_leave_keeps_auto_channels(root):
    assert membership(S, root) == (sorted([C, "CAUTO"]), "dispatched")
    assert membership(S, root / "tank", TANK) == (sorted([C, "CNEW"]), "ignored")  # 탱크 가입·탈퇴 = 지금과 같음


MUTANTS = [("M1", SOCK, '(names.get("%s") or "")' % IDS, '""', scenario, {}, (True, 1, 0)),  # ① 깨짐
           ("M2", RX, 'event.get("user") in self.bot_users and ', "", scenario, {"user": "UOTHER"}, (False, 0, 1)),  # ③ 깨짐
           ("M3", RX, 'and event.get("thread_ts") \\', "\\", scenario, {"thread": None}, (False, 0, 1)),  # ④ 깨짐
           ("M4", SOCK, 'event.get("user") in self.tank', 'event.get("user") in self.receive.bot_users', membership, {},
            (sorted([C, "CAUTO"]), "dispatched"))]  # R1 깨짐


@pytest.mark.parametrize("mid,rel,old,new,run,kw,want", MUTANTS, ids=[m[0] for m in MUTANTS])
def test_mutants_caught(root, tmp_path, mid, rel, old, new, run, kw, want):
    for part in ("core", "adapters"):
        shutil.copytree(os.path.join(FT2, part), tmp_path / "ft2m" / part)
    text = (tmp_path / "ft2m" / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, old
    (tmp_path / "ft2m" / rel).write_text(text.replace(old, new), encoding="utf-8")
    assert run(_load(SOCK, str(tmp_path / "ft2m"), mid), root, **kw) != want, mid
