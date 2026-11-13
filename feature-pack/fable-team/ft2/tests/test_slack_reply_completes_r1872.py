"""r1872 Slack 답글 게시 확정 = 그 thread 앞 글 완료 + «용량 부족» 글 다시 접수 — 카드 반례 ①~⑪ · 변이 M1~M5.
임시 root · 가짜 post · 실 Slack·실 장부 0 · sleep 0. 기준판(팩 origin/main = 완료 손 0)에서 ① ⑥~⑪ Red · 변이 = 사본 한 줄 바꿔 같은 시나리오."""
import importlib.util, os, shutil  # noqa: E401
import pytest

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEAM, W, C, SEAT, T, T2 = "harness", "TFAKE", "CFAKE", "seat-a", "1800000000.000100", "1800000000.000900"
A, B, X = "1800000000.000200", "1800000000.000300", "1800000000.000250"

def _mods(base=FT2, tag="base"):
    out = {}
    for name, rel in (("publish", "adapters/slack/publish.py"), ("binding", "adapters/slack/binding.py"),
                      ("receive", "adapters/slack/receive.py"), ("dispatch", "core/dispatch.py")):
        spec = importlib.util.spec_from_file_location("ft2_r1872_%s_%s" % (tag, name), os.path.join(base, rel))
        spec.loader.exec_module(out.setdefault(name, importlib.util.module_from_spec(spec)))
    return type("M", (), out)

M = _mods()

def _mutant(tmp, rel, edits):
    base = tmp / "ft2m"
    for part in ("core", "adapters"):
        shutil.copytree(os.path.join(FT2, part), base / part)
    path, text = base / rel, (base / rel).read_text(encoding="utf-8")
    for old, new in edits:
        assert text.count(old) == 1, old  # 변이 자리가 정확히 1곳
        text = text.replace(old, new)
    path.write_text(text, encoding="utf-8")
    return _mods(str(base), tag=tmp.name)

def cmd(ts):
    return "slack:%s:%s:%s" % (W, C, ts)

def accept(m, root, ts, thread=T):
    work = {"slack": {"workspace": W, "channel": C, "ts": ts, "attempts": 1},
            "route": {"thread": thread, "workspace": W, "channel": C}}
    return m.dispatch.intake.Intake(str(root), TEAM).submit(cmd(ts), "글 " + ts, work)

def ledger(m, root):
    rs = m.dispatch.intake.Intake(str(root), TEAM)
    records, state = rs.records(), m.dispatch.record.recover_state(rs._state(), rs.records())
    return set(state.get("done") or {}), m.dispatch.record.remaining(state, records), len(records)

class Band:  # Slack 전송 대역 — post 결과·조회 응답을 시험이 정한다
    def __init__(self, actions=(), answers=()):
        self.actions, self.answers, self.posts, self.lost = list(actions), list(answers), 0, Exception

    def post(self, root, text, marker, metadata):
        self.posts += 1
        if (self.actions.pop(0) if self.actions else "ok") == "lost":
            raise self.lost("응답 유실")
        return "1800000009.000100"

    def lookup(self, marker):
        return self.answers.pop(0) if self.answers else "undecidable"

def pub(m, root, band, thread=T, on_step=None):
    key = m.binding.thread_key(W, C, thread)
    m.binding.ThreadBinding(str(root), TEAM).bind(key, SEAT)
    band.lost = m.publish.ResponseLost  # 변이 사본이면 그 사본의 예외
    return m.publish.SlackPublish(str(root), post=band.post, lookup=band.lookup, team=TEAM, on_step=on_step), key

def s_thread(m, root):  # ①②③ — thread T 의 a·b 접수 · 답글 뒤 글 c · 다른 thread 글 x(ts 가 b 보다 앞)
    for ts, thread in ((A, T), (X, T2), (B, T), ("1800000000.000400", T)):
        accept(m, root, ts, thread)
    publisher, key = pub(m, root, Band())
    publisher.reply(key, cmd(B), "답", SEAT, 1)
    return ledger(m, root)[0]

def s_owned(m, root):  # ④ — 배정 계보(dispatch 줄)가 있는 글 = 손 0
    accept(m, root, A)
    rs = m.dispatch.intake.Intake(str(root), TEAM)
    rs._append_journal(m.dispatch.record.build(TEAM, 2, cmd(A), cmd(A) + "#a1", "2026-11-13T00:00:00", cmd(A),
                                               cmd(A), kind="dispatch", holder="nano#0", gen=1))
    publisher, key = pub(m, root, Band())
    publisher.reply(key, cmd(A), "답", SEAT, 1)
    return ledger(m, root)[0]

def s_found(m, root):  # ⑨ — 응답 유실 → UNCERTAIN → resolve 조회 FOUND → POSTED(via lookup)
    accept(m, root, B)
    publisher, key = pub(m, root, band := Band(actions=["lost"], answers=["found"]))
    first, mid = publisher.reply(key, cmd(B), "답", SEAT, 1)["state"], ledger(m, root)[0]
    row = publisher.resolve(key)
    return first, mid, (row["state"], row.get("via")), ledger(m, root)[0], band.posts

def s_crash(m, root, retry=False):  # ⑩⑪ — POSTED 줄 직후 after_posted 에서 중단 → resolve · 같은 답글 재시도
    accept(m, root, B)
    band = Band()
    def stop(step):  # POSTED 줄 직후 중단
        if step == "after_posted":
            raise KeyboardInterrupt(step)
    publisher, key = pub(m, root, band, on_step=stop)
    with pytest.raises(KeyboardInterrupt):
        publisher.reply(key, cmd(B), "답", SEAT, 1)
    crashed, (again, _) = ledger(m, root)[0], pub(m, root, band)
    if retry:
        verdict = again.reply(key, cmd(B), "답", SEAT, 1)
        return crashed, (verdict["state"], verdict.get("k")), ledger(m, root)[0], band.posts
    return crashed, again.resolve(key)["state"], ledger(m, root)[0], band.posts

def test_1_2_3_thread_reply_completes_earlier_posts_only(tmp_path):
    """① a·b 완료 2 · ② 답글 뒤 c 완료 0 · ③ 다른 thread x 완료 0."""
    assert s_thread(M, tmp_path) == {cmd(A), cmd(B)}
    assert ledger(M, tmp_path)[1] == [cmd(X), cmd("1800000000.000400")]

def test_4_assigned_work_untouched(tmp_path):
    assert s_owned(M, tmp_path) == set()  # 배정된 일 = 손 0

def test_5_root_post_completes_nothing(tmp_path):
    accept(M, tmp_path, A)
    publisher, _ = pub(M, tmp_path, Band())
    assert publisher.post_root(M.binding.thread_key(W, C, ""), "post:%s:desk:1" % C, "새 글")["state"] == "posted"
    assert ledger(M, tmp_path)[0] == set()

def test_6_resent_same_reply_already_done_writes_nothing(tmp_path):
    accept(M, tmp_path, A)
    publisher, key = pub(M, tmp_path, Band())
    row = publisher.reply(key, cmd(A), "답", SEAT, 1)
    lines = ledger(M, tmp_path)[2]
    assert publisher._settle(dict(row, state="resent")) == dict(row, state="resent")  # 게시 결과 그대로
    assert (publisher.settled["state"], ledger(M, tmp_path)[2]) == ("완료 0", lines)

def eight(root):  # 남은 일 8 = 상한 8 — thread T 글 1 + 다른 thread 글 7
    accept(M, root, A)
    for n in range(7):
        accept(M, root, "1800000001.00010%d" % n, thread="1800000001.00010%d" % n)
    return pub(M, root, Band())

def test_7_reply_frees_capacity_for_next_post(tmp_path):
    publisher, key = eight(tmp_path)
    assert accept(M, tmp_path, "1800000003.000100").result == "용량 부족"
    publisher.reply(key, cmd(A), "답", SEAT, 1)
    assert accept(M, tmp_path, "1800000003.000100").result == "접수 성공"

def test_8_full_posts_requeued_oldest_first_by_open_room(tmp_path):
    """⑧ full 3 + 칸 1 → 가장 오래된 1개만 다시 접수 · 나머지 2 그대로 full."""
    publisher, key = eight(tmp_path)
    inbox = M.receive.SlackReceive(str(tmp_path), ack=lambda e: 0, team=TEAM, allowed_users={"U1"}, allowed_channels={C})
    fulls = ["1800000002.000300", "1800000002.000100", "1800000002.000200"]
    for ts in fulls:
        assert inbox.handle({"type": "message", "team": W, "channel": C, "ts": ts, "user": "U1",
                             "text": "글"})["state"] == "full"
    publisher.reply(key, cmd(A), "답", SEAT, 1)
    latest = {c: e["state"] for c, e in inbox.latest().items()}
    assert [latest[cmd(ts)] for ts in sorted(fulls)] == ["dispatched", "full", "full"]
    assert publisher.settled["requeued"] == [cmd("1800000002.000100")]

def test_9_resolve_found_completes_once(tmp_path):
    assert s_found(M, tmp_path) == ("uncertain", set(), ("posted", "lookup"), {cmd(B)}, 1)

@pytest.mark.parametrize("name", ["resolve", "retry"])
def test_10_11_crash_after_posted_recovers_without_repost(tmp_path, name):
    want = "posted" if name == "resolve" else ("refused", "same_intent")  # post 호출 1 그대로
    assert s_crash(M, tmp_path / name, name == "retry") == (set(), want, {cmd(B)}, 1)

PUB, DONE = "adapters/slack/publish.py", "adapters/slack/reply_done.py"
RECHECK = [("return self._settle(entry)", "return entry"), ("self._settle(posted)", "None")]
MUTANTS = [  # (변이, 파일, 바꿀 줄 목록, 시나리오, 깨짐 판정)
    ("M1", DONE, [("_ts(own) > _ts(ts)", "False")], s_thread, lambda got: cmd("1800000000.000400") in got),
    ("M2", DONE, [("thread != key[2]", "False")], s_thread, lambda got: cmd(X) in got),
    ("M3", DONE, [("command in owners or command in assigned", "False")], s_owned, lambda got: cmd(A) in got),
    ("M4", PUB, [("return self._settle(self._append(dict(settled, state=POSTED",
                  "return (self._append(dict(settled, state=POSTED")], s_found, lambda got: got[3] == set()),
    ("M5-resolve", PUB, RECHECK, s_crash, lambda got: got[2] == set()),
    ("M5-retry", PUB, RECHECK, lambda m, root: s_crash(m, root, True), lambda got: got[2] == set()),
]

@pytest.mark.parametrize("mid,rel,edits,scenario,broken", MUTANTS, ids=[m[0] for m in MUTANTS])
def test_mutants_caught(tmp_path, mid, rel, edits, scenario, broken):
    assert broken(scenario(_mutant(tmp_path, rel, edits), tmp_path / "world")), mid
    assert not broken(scenario(M, tmp_path / "base")), mid  # 같은 시나리오가 원판에서는 통과

ROUTE = importlib.util.spec_from_file_location("ft2_r1872_route", os.path.join(FT2, "adapters/slack/route.py"))
ROUTE.loader.exec_module(route := importlib.util.module_from_spec(ROUTE))

def thread_full(root):  # R1 — thread T 의 답글 글 1개가 실제 SlackRoute 길로 «용량 부족»
    publisher, key = eight(root)
    inbox = M.receive.SlackReceive(str(root), ack=lambda e: 0, team=TEAM, allowed_users={"U1"}, allowed_channels={C})
    router = route.SlackRoute(str(root), receive=inbox, team=TEAM)
    assert router.route({"type": "message", "team": W, "channel": C, "thread_ts": T, "ts": "1800000002.000100",
                         "user": "U1", "text": "thread 답글"})["state"] == "full"
    return publisher, key, inbox, cmd("1800000002.000100")

def test_r1a_requeued_post_keeps_route_and_completes_in_its_thread(tmp_path):
    publisher, key, inbox, late = thread_full(tmp_path)
    publisher.reply(key, cmd(A), "답", SEAT, 1)
    accepted = [r for r in M.dispatch.intake.Intake(str(tmp_path), TEAM).records() if r["command"] == late][-1]
    assert (accepted["work"]["route"]["thread"], inbox.latest()[late]["state"]) == (T, "dispatched")
    publisher.reply(key, late, "밀렸던 글 답", SEAT, 1)  # 원래 thread T 에서 그 글에 답
    assert (publisher.settled["completed"], late in ledger(M, tmp_path)[0]) == ([late], True)

def test_r1b_requeue_failure_recovered_by_same_post_recheck(tmp_path, monkeypatch, capsys):
    publisher, key, inbox, late = thread_full(tmp_path)
    with monkeypatch.context() as patch:
        patch.setattr(M.publish.reply_done, "_requeue", lambda *a: (_ for _ in ()).throw(RuntimeError("주입")))
        assert publisher.reply(key, cmd(A), "답", SEAT, 1)["state"] == "posted"  # 게시 결과 그대로
    assert (publisher.settled["state"], inbox.latest()[late]["state"], len(ledger(M, tmp_path)[1])) == ("판정 불가", "full", 7)
    assert "판정 불가" in capsys.readouterr().err
    assert publisher.resolve(key)["state"] == "posted"  # 새 post 0 · 새 완료 0 · 남은 재접수만
    assert (publisher.settled["requeued"], inbox.latest()[late]["state"], len(ledger(M, tmp_path)[1])) == ([late], "dispatched", 8)
