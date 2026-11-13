"""r1886 ft2 꽉 참 = 크리티컬 알림 — 반례 ①~⑦ · 변이 M1(서명 기억 빼기 → ②) · M2(정상 관측 빼기 → ③⑥⑦).
임시 root · 가짜 mbox(<root>/.fable-team/comm/mbox.sh = 인자 기록) · 가짜 명부(desk·harness master) · 실 Intake·Dispatch·Journal.
실 우편함·실 Slack·실 명부·실 tmux·설치 0 · sleep 0 · 기준판(full_alert 없음) = 전 사례 Red."""
import importlib.util, json, os, types  # noqa: E401
import pytest

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESK, MASTER, W, C = "byz-planner-desk-pi#9", "byz-harness-master-pi#9", "TFAKE", "CFAKE"
MBOX = '#!/bin/sh\nprintf "%s\\t%s\\t%s\\n" "$2" "$3" "$(printf "%s" "$4" | head -1)" >> "$0.log"\n'


def _load(rel, alias):
    spec = importlib.util.spec_from_file_location("r1886_" + alias, os.path.join(FT2, rel))
    spec.loader.exec_module(module := importlib.util.module_from_spec(spec))
    return module


keeper, kn, wiring = (_load(p, a) for p, a in (("adapters/pi/keeper.py", "keeper"), ("adapters/pi/keeper_next.py", "kn"),
                                                ("adapters/slack/wiring.py", "wiring")))
dispatch = _load("core/dispatch.py", "dispatch")


@pytest.fixture
def root(tmp_path, monkeypatch):
    fable = tmp_path / ".fable-team"
    (fable / "comm").mkdir(parents=True)
    (fable / "seats-planner.json").write_text(json.dumps({"_desk": DESK}), encoding="utf-8")
    (fable / "seats-harness.json").write_text(json.dumps({"_master": MASTER}), encoding="utf-8")
    (fable / "comm" / "mbox.sh").write_text(MBOX, encoding="utf-8")
    monkeypatch.delenv("FT2_FULL_ALERT_WAKE", raising=False)
    monkeypatch.setenv("FT2_SLACK_WAKE", "true")   # 기존 A4 command 깨움 = 대역 0(이 시험은 크리티컬만 센다)
    return tmp_path


def sent(root, word="★크리티컬★"):
    path = root / ".fable-team" / "comm" / "mbox.sh.log"
    return [ln.split("\t") for ln in (path.read_text(encoding="utf-8").splitlines() if path.exists() else []) if word in ln]


def fill(root, team, n, tag="w"):   # 실 Intake 에 n 건 접수(남은 일 n)
    dp = dispatch.Dispatch(str(root), team)
    for i in range(n):
        assert dp.rs.submit("%s%d" % (tag, i), "body", "%s%d" % (tag.upper(), i)).result == "접수 성공"
    return dp


def finish(dp, work):   # 실 assign → deliver → complete = 남은 일 1 줄임
    seat = "byz-planner-nano-r1886#0"
    assert [dp.assign(work, seat, evidence=("v1", "v2")).result, dp.deliver(work, "a1").result,
            dp.complete(work, "a1").result] == ["접수 성공"] * 3


def slack(root, team="planner"):
    rx = wiring.receive.SlackReceive(str(root), ack=lambda e: None, team=team, allowed_users=("U",), allowed_channels=(C,))
    wiring.wire(str(root), receive=rx, bindings=wiring.binding.ThreadBinding(str(root), team="planner"), team="planner")
    seq = iter(range(1, 99))
    return lambda: rx.handle({"type": "message", "user": "U", "channel": C, "team": W, "ts": "18.%03d" % next(seq), "text": "글"})


def keeper_at(root, **env):
    k = keeper.Keeper(str(root), env=dict(os.environ, **env), now=lambda: 1794000000.0)
    k.git = lambda *a, **kw: (0, "", "")
    return k


def test_c1_c2_c3_slack_full_once_then_release_and_new(root):
    dp, post = fill(root, "planner", 8), slack(root)
    post()                                                   # ① 남은 일 8 + 글 1 → desk·master 각 1
    assert sorted(r[0] for r in sent(root)) == sorted([DESK, MASTER]) and "남은 일 planner 8/8" in sent(root)[0][2]
    post(), post()                                           # ② 같은 상태 글 2 → 추가 0
    assert len(sent(root)) == 2
    finish(dp, "W0"), finish(dp, "W1")
    post()                                                   # ③ 접수 성공 관측 7 = 풀림 1
    assert len(sent(root, "풀림")) == 2 and len(sent(root)) == 2
    post()                                                   # 다시 8 = 새 크리티컬 1
    assert len(sent(root)) == 4 and len(sent(root, "풀림")) == 2


def test_c4_keeper_submit_same_signature_merged_other_team_one(root, monkeypatch):
    fill(root, "planner", 8), fill(root, "harness", 8, "h")
    slack(root)()
    assert len(sent(root)) == 2
    k = keeper_at(root)
    k.receipt = lambda *a, **kw: types.SimpleNamespace(result="접수 성공", next=None, reason="")
    monkeypatch.setattr(kn, "gates", lambda k, t: True)
    monkeypatch.setattr(kn, "choose", lambda k, t: ("r9001-x", "repo", "base"))
    kn.close(k, "planner", "W0", "a1", "h#0", 1)             # 같은 서명(남은 일 · planner) = 0
    assert len(sent(root)) == 2 and any("submit 용량 부족" in x for x in k.lines)
    kn.close(k, "harness", "H0", "a1", "h#0", 1)             # 다른 팀 = 1(desk·master 각 1)
    assert len(sent(root)) == 4 and "남은 일 harness 8/8" in sent(root)[-1][2]


def test_c5_next_hold_nano_cap(root):
    (root / ".fable-team" / "teams" / "harness").mkdir(parents=True)
    (root / ".fable-team" / "teams" / "harness" / "CLOSE-NEXT.enabled").write_text("", encoding="utf-8")
    k = keeper_at(root, FT2_TEAM_NANO_MAX="4")
    k.call = lambda argv, *a, **kw: (0, "\n".join("byz-harness-nano-r%d#0" % i for i in range(4)), "")
    assert kn.gates(k, "harness") is None and len(sent(root)) == 2 and "나노 정원 harness 4/4" in sent(root)[0][2]
    k.call = lambda argv, *a, **kw: (0, "byz-harness-nano-r0#0", "")
    assert kn.gates(k, "harness") is True and len(sent(root, "풀림")) == 2


def test_c6_round_cap_then_release(root, monkeypatch):
    k, ticks = keeper_at(root), iter([0, 100, 200, 1000, 1001, 1002, 1003])
    monkeypatch.setattr(keeper, "time", types.SimpleNamespace(monotonic=lambda: next(ticks), time=__import__("time").time))
    k.teams, k.team_round, k.retired, k.report = lambda: ["harness"], lambda t: None, lambda: None, lambda: None
    k.run_once()                                             # ROUND-CAP → 1통(desk·master 각 1)
    assert any(x.startswith("ROUND-CAP") for x in k.lines) and len(sent(root)) == 2
    k.run_once()                                             # 다음 바퀴 60초 안 끝 = 풀림 1
    assert len(sent(root, "풀림")) == 2 and len(sent(root)) == 2


def test_c7_journal_refused_then_release(root):
    dp = fill(root, "harness", 1, "j")
    assert [dp.assign("J0", "byz-harness-nano-r1886#0", evidence=("v1", "v2")).result,
            dp.deliver("J0", "a1").result] == ["접수 성공"] * 2
    big = root / ".fable-team" / "teams" / "harness" / "runtime" / "big.bin"
    big.write_bytes(b"0" * 8388608)                          # 총량 한계 넘김 = 실 Journal.reserve 가 «용량 부족»
    k = keeper_at(root)
    assert k.complete("harness", "J0", "a1", ("ab" * 20, "pack:main", "")) is None
    assert len(sent(root)) == 2 and "journal harness" in sent(root)[0][2]
    big.unlink()                                             # 다음 쓰기 성공 = 풀림 1
    assert k.complete("harness", "J0", "a1", ("ab" * 20, "pack:main", "")) is True
    assert len(sent(root, "풀림")) == 2 and len(sent(root)) == 2
