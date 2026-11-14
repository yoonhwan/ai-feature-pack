"""r1927 탱크 봇 thread 답 = 앞 글 완료 · 칸 열림 = full 재접수(처리 기록 대조) · 꽉 참 [긴급] 받는 곳 · desk 알림 회차당 1 · 표 거절.
반례 ①~⑪ + DA 보강 · 변이 M1~M4·M6~M9. 임시 root · 가짜 mbox · 실 Intake·Dispatch · 실 Slack·실 장부 0 · sleep 0."""
import importlib.util, json, os, shutil  # noqa: E401
import pytest

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEAM, W, C, BOT, U = "planner", "TFAKE", "CFAKE", "UTANK", "U1"
PMASTER, HMASTER, DESK = "byz-planner-master-pi#9", "byz-harness-master-pi#9", "byz-planner-desk-pi#9"
A, F, G = "1800000000.000100", "1800000002.000100", "1800000002.000200"
MBOX = '#!/bin/sh\nprintf "%s\\t%s\\t%s\\n" "$2" "$3" "$(printf "%s" "$4" | head -1)" >> "$0.log"\n'
FILES = {"receive": "adapters/slack/receive.py", "wiring": "adapters/slack/wiring.py", "fa": "adapters/pi/full_alert.py",
         "dispatch": "core/dispatch.py"}


def _mods(base=FT2, tag="base"):
    out = {}
    for name, rel in FILES.items():
        spec = importlib.util.spec_from_file_location("r1927_%s_%s" % (tag, name), os.path.join(base, rel))
        spec.loader.exec_module(out.setdefault(name, importlib.util.module_from_spec(spec)))
    return type("M", (), out)


M = _mods()


def _mutant(tmp, rel, old, new):
    base = tmp / "ft2m"
    for part in ("core", "adapters"):
        shutil.copytree(os.path.join(FT2, part), base / part)
    text = (base / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, old  # 변이 자리 정확히 1곳
    (base / rel).write_text(text.replace(old, new), encoding="utf-8")
    return _mods(str(base), tag=tmp.name)


@pytest.fixture
def root(tmp_path, monkeypatch):
    fable = tmp_path / ".fable-team"
    (fable / "comm").mkdir(parents=True)
    (fable / "seats-planner.json").write_text(json.dumps({"_desk": DESK, "_master": PMASTER}), encoding="utf-8")
    (fable / "seats-harness.json").write_text(json.dumps({"_master": HMASTER}), encoding="utf-8")
    (fable / "comm" / "mbox.sh").write_text(MBOX, encoding="utf-8")
    monkeypatch.delenv("FT2_FULL_ALERT_WAKE", raising=False)
    monkeypatch.setenv("FT2_SLACK_WAKE", "sh %s" % (fable / "comm" / "mbox.sh"))
    return tmp_path


def cmd(ts):
    return "slack:%s:%s:%s" % (W, C, ts)


def inbox(m, root, bots=(BOT,), log=None):
    return m.receive.SlackReceive(str(root), ack=lambda e: 0, team=TEAM, allowed_users={U}, allowed_channels={C},
                                  bot_users=bots, log=(log if log is not None else []).append)


def human(m, rx, ts):
    return rx.handle({"type": "message", "team": W, "channel": C, "ts": ts, "user": U, "text": "글 " + ts})


def bot(rx, ts="1800000005.000100", thread=A, user=BOT, bot_id="BTANK", channel=C):
    event = {"type": "message", "team": W, "channel": channel, "ts": ts, "user": user, "bot_id": bot_id, "text": "답"}
    return rx.handle(dict(event, **({"thread_ts": thread} if thread else {})))


def ledger(m, root):
    rs = m.dispatch.intake.Intake(str(root), TEAM)
    state = m.dispatch.record.recover_state(rs._state(), rs.records())
    return set(state.get("done") or {}), len(m.dispatch.record.remaining(state, rs.records()))


def eight(m, root, rx):  # A + 다른 root 7 = 남은 일 8/8
    for ts in [A] + ["1800000001.00010%d" % n for n in range(7)]:
        assert human(m, rx, ts)["state"] == "dispatched"


def s_one(m, root):  # ① 오빠 글 A → 탱크 thread 답
    rx = inbox(m, root)
    human(m, rx, A)
    return bot(rx).get("settle"), ledger(m, root)


def test_1_tank_thread_reply_completes_earlier_post(root):
    assert s_one(M, root) == ({"state": "완료", "completed": 1, "requeued": 0}, ({cmd(A)}, 0))


def s_full(m, root, settle_lines=(), fulls=(F,)):  # ② 8/8 + full → 탱크 답 → 칸 1 열림
    rx = inbox(m, root)
    eight(m, root, rx)
    for ts in fulls:
        assert human(m, rx, ts)["state"] == "full"
    (root / ".fable-team" / "teams" / TEAM / "slack" / "settle.jsonl").write_text("".join(settle_lines), encoding="utf-8")
    first = bot(rx)
    return rx, first.get("settle"), {ts: rx.latest()[cmd(ts)]["state"] for ts in fulls}


def test_2_full_post_requeued_without_restart(root):
    assert s_full(M, root)[1:] == ({"state": "완료", "completed": 1, "requeued": 1}, {F: "dispatched"})


def ask(ts):
    return json.dumps({"command": cmd(ts), "by": "desk", "why": "처리함"}) + "\n"


def test_2b_settle_asked_full_settled_next_full_dispatched(root):  # DA R1
    assert s_full(M, root, [ask(F)], (F, G))[2] == {F: "settled", G: "dispatched"}


def test_5b_broken_settle_line_requeues_nothing(root, capsys):  # DA 2회차 R1 ⓐ'
    rx, got, states = s_full(M, root, [ask(G), "{broken\n"])
    assert (got["requeued"], states, "판정 불가" in capsys.readouterr().err) == (0, {F: "full"}, True)
    assert set(M.receive.read_settle(rx.settle_path)) == {cmd(G)}  # 기본 판독 = 깨진 줄 건너뜀(지금 동작)


def s_root_bot(m, root):  # ③ thread 없는 봇 root 글
    rx = inbox(m, root)
    human(m, rx, A)
    return bot(rx, thread=None), ledger(m, root)[0]


def test_3_root_bot_post_touches_nothing(root):
    row, done = s_root_bot(M, root)
    assert (row["state"], "settle" in row, done) == ("ignored", False, set())


def test_4_assigned_post_untouched(root):
    rx = inbox(M, root)
    human(M, rx, A)
    rs = M.dispatch.intake.Intake(str(root), TEAM)  # 배정 계보(dispatch 줄) = r1872 s_owned 와 같은 꼴
    rs._append_journal(M.dispatch.record.build(TEAM, len(rs.records()) + 1, cmd(A), cmd(A) + "#a1", "2026-11-14T00:00:00",
                                               cmd(A), cmd(A), kind="dispatch", holder="nano#0", gen=1))
    assert (bot(rx)["settle"]["completed"], ledger(M, root)[0]) == (0, set())


def test_5_same_envelope_twice_completes_and_requeues_once(root):
    rx, first, _ = s_full(M, root)
    again = bot(rx)["settle"]
    rows = [r for r in rx.entries() if r.get("command") == cmd(F) and r["state"] == "dispatched"]
    assert ((first["completed"], first["requeued"]), (again["completed"], again["requeued"]), len(rows)) == ((1, 1), (0, 0), 1)


def s_strangers(m, root):  # ⑥ 허용 밖 채널 · R2 다른 앱 봇 · bot_id 만
    rx = inbox(m, root)
    human(m, rx, A)
    rows = [bot(rx, "1800000005.00010%d" % i, **kw) for i, kw in enumerate(
        ({"channel": "COTHER"}, {"user": "UOTHER", "bot_id": "B_OTHER"}, {"user": None}))]
    return [("settle" in r) for r in rows], ledger(m, root)[0]


def test_6_r2_other_channel_other_app_bot_id_only_touch_nothing(root):
    assert s_strangers(M, root) == ([False, False, False], set())


def test_r2_empty_tank_identity_logs_once_completes_nothing(root):
    log = []
    rx = inbox(M, root, bots=(), log=log)
    human(M, rx, A)
    assert ("settle" in bot(rx), ledger(M, root)[0], log) == (False, set(), ["탱크 신원 없음 · 봇 답 완료 0"])


def test_7_settle_failure_logs_and_receiving_continues(root, monkeypatch, capsys):
    log = []
    rx = inbox(M, root, log=log)
    human(M, rx, A)
    done = M.receive._reply_done()
    monkeypatch.setattr(done.dispatch, "Dispatch", lambda *a: (_ for _ in ()).throw(RuntimeError("장부 깨짐")))
    assert bot(rx)["settle"]["state"] == "판정 불가" and len([x for x in log if "판정 불가" in x]) == 1
    assert human(M, rx, "1800000006.000100")["state"] == "dispatched"


def sent(root, word):
    path = root / ".fable-team" / "comm" / "mbox.sh.log"
    return [ln.split("\t") for ln in (path.read_text(encoding="utf-8").splitlines() if path.exists() else []) if word in ln]


def s_alert(m, root):  # ⑧ 남은 일 처음 8/8
    m.fa.observe(str(root), "남은 일", TEAM, 8, 8)
    return sorted((r[0], r[2].split()[0]) for r in sent(root, "★크리티컬★"))


def test_8_full_alert_goes_to_team_master_and_harness_master_urgent(root):
    assert s_alert(M, root) == sorted([(PMASTER, "[긴급]"), (HMASTER, "[긴급]")])


def s_wake(m, root):  # ⑨ 꽉 찬 동안 full 3 → desk 깨움 1 · 풀림 뒤 다시 꽉 참 → 1 더
    rx = inbox(m, root)
    m.wiring.wire(str(root), receive=rx, bindings=m.wiring.binding.ThreadBinding(str(root), team=TEAM), team=TEAM)
    eight(m, root, rx)
    for ts in ("1800000002.00010%d" % n for n in range(3)):
        human(m, rx, ts)
    first, dp = len(sent(root, "알림 용량 부족")), m.dispatch.Dispatch(str(root), TEAM)
    for work in (cmd(A), cmd("1800000001.000100")):  # reply_done 과 같은 complete(command) = 남은 일 2 줄임
        assert dp.complete(work).result == "접수 성공"
    for ts in ("1800000003.00010%d" % n for n in range(4)):  # 7 → 풀림 · 8 → 꽉 참 · 용량 부족 2
        human(m, rx, ts)
    return first, len(sent(root, "알림 용량 부족"))


def test_9_desk_full_wake_once_per_episode(root):
    assert s_wake(M, root) == (1, 2)


def s_table(m, root, body):  # ⑪ ft2 slack reply 본문 표 → refused · publish 장부 0
    path = root / "body.txt"
    path.write_text(body, encoding="utf-8")
    rc = m.wiring.main(["reply", "--root", str(root), "--team", TEAM, "--thread", A, "--seat", "s",
                        "--body-file", str(path), "--command", cmd(A)], post=lambda *a: "1800000009.000100")
    return rc, (root / ".fable-team" / "teams" / TEAM / "slack" / "publish.jsonl").exists()


TABLE, FENCED = "요약\n| a | b |\n|---|---|\n| 1 | 2 |\n", "요약\n```\n| a | b |\n|---|---|\n```\n"


def test_11_markdown_table_refused_code_block_not(root, capsys):
    assert s_table(M, root, TABLE) == (2, False) and "reason=마크다운 표" in capsys.readouterr().out
    assert M.wiring.has_table(TABLE) and not M.wiring.has_table(FENCED)
    assert s_table(M, root, FENCED)[0] == 2 and "binding 없음" in capsys.readouterr().out  # 표 검사 통과 → 다음 검사


RX, RD, FA, WI = FILES["receive"], "adapters/slack/reply_done.py", FILES["fa"], FILES["wiring"]
MUTANTS = [  # (변이, 파일, 바꿀 글, 새 글, 시나리오, 깨짐 판정)
    ("M1", RX, 'row["settle"] = self._reply_settle(command, key, event)', "pass", s_one, lambda g: g[1][0] == set()),
    ("M2", RX, 'and event.get("thread_ts") \\', "\\", s_root_bot, lambda g: "settle" in g[0]),
    ("M3", FA, 'for t in (team, "harness")', 'for t in ("harness",)', s_alert, lambda g: (PMASTER, "[긴급]") not in g),
    ("M4", WI, "if again:", "if False:", s_wake, lambda g: g[0] > 1),
    ("M6", WI, 'FENCE.sub("", str(text))', "str(text)", lambda m, r: m.wiring.has_table(FENCED), lambda g: g),
    ("M7", RD, "if entry[\"command\"] in asked:", "if False:", lambda m, r: s_full(m, r, [ask(F)], (F, G))[2],
     lambda g: g != {F: "settled", G: "dispatched"}),
    ("M8", RX, 'event.get("user") in self.bot_users and ', "", s_strangers, lambda g: any(g[0])),
    ("M9", RD, "strict=True", "strict=False", lambda m, r: s_full(m, r, [ask(G), "{broken\n"])[2], lambda g: g != {F: "full"}),
]


@pytest.mark.parametrize("mid,rel,old,new,scenario,broken", MUTANTS, ids=[m[0] for m in MUTANTS])
def test_mutants_caught(root, tmp_path, mid, rel, old, new, scenario, broken):
    assert broken(scenario(_mutant(tmp_path, rel, old, new), root)), mid
    shutil.rmtree(root / ".fable-team" / "teams", ignore_errors=True)
    shutil.rmtree(root / ".fable-team" / "state", ignore_errors=True)
    (root / ".fable-team" / "comm" / "mbox.sh.log").unlink(missing_ok=True)
    assert not broken(scenario(M, root)), mid  # 같은 시나리오가 원판에서는 통과
