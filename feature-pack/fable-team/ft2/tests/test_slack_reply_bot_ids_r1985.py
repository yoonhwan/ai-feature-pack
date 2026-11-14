"""r1985 desk 신원 thread 답 = 앞 글 접수 완료 — SLACK_REPLY_BOT_USER_IDS(--env 쉼표 목록)를 탱크 신원에 더함.
반례 ①~⑤ · 변이 M1~M3. 임시 root · ENV 파일 → socket 판독 → 실 SlackReceive·Intake·Dispatch · 실 Slack 0 · sleep 0."""
import importlib.util, json, os, shutil  # noqa: E401
import pytest

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEAM, W, C, TANK, DESK, U, A = "planner", "TFAKE", "CFAKE", "UTANK", "UDESK", "U1", "1800000000.000100"
CMD, SOCK, RX = "slack:%s:%s:%s" % (W, C, A), "adapters/slack/socket.py", "adapters/slack/receive.py"


def _load(rel, base=FT2, tag="base"):
    spec = importlib.util.spec_from_file_location("r1985_%s_%s" % (tag, os.path.basename(rel)[:-3]), os.path.join(base, rel))
    spec.loader.exec_module(module := importlib.util.module_from_spec(spec))
    return module


S, D = _load(SOCK), _load("core/dispatch.py")


@pytest.fixture
def root(tmp_path):
    (tmp_path / "seats.json").write_text(json.dumps({"_master": "m#1"}), encoding="utf-8")
    return tmp_path


def bots(s, root, extra):  # ENV 파일 → socket 판독 → bot_users
    env = "SLACK_APP_TOKEN=xapp-F\nSLACK_BOT_TOKEN=xoxb-F\nSLACK_BOT_USER_ID=%s\n%s" % (TANK, extra)
    (root / "x.env").write_text(env, encoding="utf-8")
    return s.bot_users_of(s.read_inputs(str(root / "x.env"), str(root / "seats.json"))[0])


def scenario(s, root, extra="SLACK_REPLY_BOT_USER_IDS= UOTHER2 ,, %s \n" % DESK, user=DESK, thread=A, owned=False):
    rx = s.receive.SlackReceive(str(root), ack=lambda e: 0, team=TEAM, allowed_users={U}, allowed_channels={C},
                                bot_users=bots(s, root, extra), log=[].append)
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


@pytest.mark.parametrize("extra", ["", "SLACK_REPLY_BOT_USER_IDS=\n", "SLACK_REPLY_BOT_USER_IDS= , \n"])
def test_2_no_or_empty_setting_same_as_now(root, extra):
    assert (bots(S, root, extra), scenario(S, root, extra)) == ((TANK,), (False, 0, 1))


@pytest.mark.parametrize("kw", [({"user": "UOTHER"}, False), ({"thread": None}, False), ({"owned": True}, True)],
                         ids=["3_other", "4_root", "5_owned"])
def test_3_4_5_other_bot_root_post_owned_untouched(root, kw):  # ⑤ = settle 시도 · 배정 계보 = 완료 0
    assert scenario(S, root, **kw[0]) == (kw[1], 0, 1)


def test_main_passes_parsed_ids_to_listener(root, monkeypatch):
    seen = {"ids": bots(S, root, "SLACK_REPLY_BOT_USER_IDS=%s\n" % DESK)}
    monkeypatch.setattr(S, "Listener", lambda *a, **kw: seen.update(kw) or type("L", (), {"run": lambda self: 0})())
    assert S.main(["--root", str(root), "--env", str(root / "x.env"), "--owner-seats", str(root / "seats.json"),
                   "--channel", C]) == 0 and seen["bot_users"] == (TANK, DESK)


MUTANTS = [("M1", SOCK, '+ (names.get("SLACK_REPLY_BOT_USER_IDS") or "").split(",")', "", {}, (True, 1, 0)),  # ① 깨짐
           ("M2", RX, 'event.get("user") in self.bot_users and ', "", {"user": "UOTHER"}, (False, 0, 1)),  # ③ 깨짐
           ("M3", RX, 'and event.get("thread_ts") \\', "\\", {"thread": None}, (False, 0, 1))]  # ④ 깨짐


@pytest.mark.parametrize("mid,rel,old,new,kw,want", MUTANTS, ids=[m[0] for m in MUTANTS])
def test_mutants_caught(root, tmp_path, mid, rel, old, new, kw, want):
    for part in ("core", "adapters"):
        shutil.copytree(os.path.join(FT2, part), tmp_path / "ft2m" / part)
    text = (tmp_path / "ft2m" / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, old
    (tmp_path / "ft2m" / rel).write_text(text.replace(old, new), encoding="utf-8")
    assert scenario(_load(SOCK, str(tmp_path / "ft2m"), mid), root, **kw) != want, mid
