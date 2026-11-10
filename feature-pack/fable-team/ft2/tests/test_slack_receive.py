"""ft2 Slack 수신 어댑터 시험 (r1580 · PR③ 첫 장).
사례 대조(ⓖ): `contracts/slack/cases/*.json` 21건 중 이 장은 8건(c1 c2 c3 d1 d2 t4 t1 t5)을 본다 — 계약 낱말은
`CONTRACT-18.md` 대응표 원문과, 결과 수치는 사례 `expect.observed.checks` 와 대조한다. R1·R2 = DA #279756 반례.
차이 1 = d2 «entrance_rows»: 모형 3행 vs 우리 1행 — 같은 command 재부여 0, DA R1 §2(조회 성공 = 완료)의 결과다.

다음 장(초안 · 지우지 않는다): c4 c5 c6 c7 c8 d3 d4 t2 t3 f1 f2 f3 f4 — 계약 1·7~14·17·18 줄.
"""

import importlib.util
import json
import os
import re
import subprocess
import sys
from pathlib import Path

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADAPTER = os.path.join(FT2, "adapters", "slack", "receive.py")
CASES = Path(FT2, "contracts", "slack", "cases")
CONTRACT = Path(FT2, "contracts", "slack", "CONTRACT-18.md")
GUARD = os.path.join(FT2, "tools", "legacy_guard.py")
TEAM, W, C, TS = "harness", "TFAKE", "CFAKE", "1800000001.000100"
OK, HOLD, FULL, BUSY = "접수 성공", "완료 유보", "용량 부족", "BUSY"
ORDER = ["filter", "key", "record", "ack", "submit", "receipt"]
HANDLED = ("c1", "c2", "c3", "d1", "d2", "t4", "t1", "t5")
REST = ("c4", "c5", "c6", "c7", "c8", "d3", "d4", "t2", "t3", "f1", "f2", "f3", "f4")
REST_LINES = {1, 7, 8, 9, 10, 11, 12, 13, 14, 17, 18}

def _load(name, path):
    spec = importlib.util.spec_from_file_location("ft2_" + name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

slack = _load("slack_receive", ADAPTER)
intake = _load("core_intake", os.path.join(FT2, "core", "intake.py"))
CASES_BY_ID = {p.stem.split("-")[1].split("_")[0]: json.loads(p.read_text(encoding="utf-8"))
               for p in sorted(CASES.glob("*.json"))}

def _contract_rows():
    md = CONTRACT.read_text(encoding="utf-8").split("## 대응표", 1)[1].split("\n## ", 1)[0]
    return {int(number): text for number, text in re.findall(r"^\| (\d+) \| (.*?) \|", md, re.M)}

def _case(cid):
    """사례 1건 — 계약 낱말이 18줄 원문에 있고, 그 줄은 우리 COVERS 또는 다음 장 줄이다."""
    case, rows = CASES_BY_ID[cid], _contract_rows()
    assert [w for w in case["expect"]["words"] if w not in " ".join(rows.values())] == []
    assert set(case["contract"]) - REST_LINES <= set(slack.COVERS)  # 이 장 몫인 줄만 덮는다
    return case["expect"]["observed"]["checks"]

class _Band:
    def __init__(self):
        self.acks, self.notify = [], []
    def ack(self, event):
        self.acks.append(event)
    def on_notify(self, verdict):
        self.notify.append(verdict)

class _Counted:
    """실 Intake 위임 + 호출 계수 — 판정값은 꾸미지 않는다."""
    def __init__(self, inner):
        self.inner, self.submits, self.lookups = inner, 0, 0
    def submit(self, *args, **kwargs):
        self.submits += 1
        return self.inner.submit(*args, **kwargs)
    def lookup(self, command):
        self.lookups += 1
        return self.inner.lookup(command)
    def records(self):
        return self.inner.records()

def _event(channel=C, ts=TS, user="U1", text="안녕", **extra):
    return dict({"type": "message", "team": W, "channel": channel, "ts": ts, "user": user,
                 "text": text}, **extra)

def _receiver(root, band, **kwargs):
    cls, channels = kwargs.pop("cls", slack.SlackReceive), kwargs.pop("channels", (C,))
    client = _Counted(intake.Intake(str(root), TEAM, capacity=kwargs.pop("capacity", 8)))
    return cls(str(root), ack=band.ack, client=client, team=TEAM, allowed_users={"U1"},
               allowed_channels=set(channels), notify=band.on_notify), client

def test_a_c1_order_confirmation_then_submit_completion(tmp_path):
    band, seen = _Band(), {}
    receiver, client = _receiver(tmp_path, band)

    def ack(event):
        band.ack(event)
        seen.update(log=[entry["state"] for entry in receiver.entries()], journal=client.records())

    receiver.ack = ack
    verdict = receiver.handle(_event())
    assert receiver.steps == ORDER and seen == {"log": ["received"], "journal": []}
    assert (verdict["state"], verdict["receipt"]) == (
        "dispatched", {"result": OK, "attempt": "slack:%s:%s:%s#a1" % (W, C, TS), "written": True})
    dropped = receiver.handle(_event(user="U2"))
    assert (dropped["state"], dropped["reason"], len(band.acks)) == ("ignored", "미인가 사용자", 2)
    _case("c1")

def test_a_crash_after_ack_recovers_by_lookup_before_submit(tmp_path):
    assert _crash_run(tmp_path, "ack").returncode == 9
    receiver, client = _receiver(tmp_path, _Band())
    assert [entry["state"] for entry in receiver.entries()] == ["received"]
    assert [v["state"] for v in receiver.recover()] == ["dispatched"]
    assert receiver.steps.index("lookup") < receiver.steps.index("submit")
    assert (client.lookups, client.submits) == (1, 1)

def test_b_c2_and_d1_three_part_key_one_message(tmp_path):
    receiver, client = _receiver(tmp_path / "c2", _Band())
    states = [receiver.handle(_event(event_id=name))["state"] for name in ("Ev1", "Ev1", "Ev2")]
    assert sorted(states) == sorted(_case("c2")["states"])  # 모형은 첫 사건을 duplicate 로 적었다
    assert (client.submits, len(client.records())) == (1, 1)
    receiver, client = _receiver(tmp_path / "d1", _Band(), channels=(C, "C2"))
    states = [receiver.handle(_event(channel=channel))["state"] for channel in (C, "C2")]
    assert (states, client.submits, len(_case("d1")["states"])) == (["dispatched", "dispatched"], 2, 2)

def test_c_d2_and_i1_crash_before_receipt_completes_via_lookup(tmp_path):
    assert [_crash_run(tmp_path, step).returncode for step in ("ack", "submit")] == [9, 9]
    receiver, client = _receiver(tmp_path, _Band())
    (entry,) = receiver.latest().values()
    body = Path(client.inner.body_path(entry["command"])).read_text(encoding="utf-8")
    assert (entry["state"], entry["attempts"]) == ("received", 2)
    assert body.startswith("[[slack-key %s/%s/%s]] 재송 1" % (W, C, TS))
    (verdict,) = receiver.recover()
    assert (verdict["state"], verdict["via"], verdict["receipt"]["written"]) == ("dispatched", "lookup", False)
    assert (client.submits, client.lookups, len(client.records())) == (0, 1, _case("d2")["seat_reads"])

def test_i2_body_only_interruption_stays_unfinished(tmp_path):
    assert _crash_run(tmp_path, "", "after_body").returncode == 9
    receiver, client = _receiver(tmp_path, _Band())
    (verdict,) = receiver.recover()
    assert (verdict["state"], verdict["receipt"]["result"], client.submits) == ("hold", HOLD, 0)

def test_d_t4_full_keeps_record_and_notifies(tmp_path):
    band = _Band()
    receiver, client = _receiver(tmp_path, band, capacity=2)
    stamps = ["180000000%d.000100" % number for number in (1, 2, 3)]
    states = [receiver.handle(_event(ts=stamp))["state"] for stamp in stamps]
    last = receiver.latest()["slack:%s:%s:%s" % (W, C, stamps[2])]
    assert (states, len(band.notify), len(client.records())) == (_case("t4")["states"], 1, 2)
    assert (last["state"], last["receipt"]["result"], last["receipt"]["written"]) == ("full", FULL, False)
    assert len(receiver.entries()) == 6  # 기록 보존 — 미완·가득 각 두 줄
    again, _ = _receiver(tmp_path, _Band())  # 용량 해제 = r1579 실행권 몫(대역: capacity 상향)
    assert [v["state"] for v in again.recover()] == ["dispatched"]

def test_e_t1_bot_unauthorized_channel_are_confirmed_and_dropped(tmp_path):
    band = _Band()
    receiver, client = _receiver(tmp_path, band)
    states = [receiver.handle(event)["state"] for event in (
        _event(bot_id="B1"), _event(subtype="bot_message"), _event(user="U9"), _event(channel="CX"))]
    assert (states, len(band.acks), len(client.records()), client.submits) == (
        _case("t1")["states"], len(states), 0, 0)

def test_f_t5_idle_duplicate_and_no_change_stay_inside_the_tool(tmp_path):
    receiver, client = _receiver(tmp_path, _Band())
    first, duplicate, dropped = (receiver.handle(event)["state"] for event in (
        _event(event_id="Ev-1"), _event(event_id="Ev-again"), _event(text="   ")))
    idle = [receiver.pass_idle()["state"] for _ in range(2)]
    assert (first, idle, duplicate, dropped) == ("dispatched", ["idle", "idle"], "duplicate", "ignored")
    assert sorted([first, duplicate, dropped]) == sorted(_case("t5")["states"])
    assert (client.submits, len(client.records())) == (1, 1)
    size = os.path.getsize(receiver.path)
    assert (receiver.pass_idle()["state"], os.path.getsize(receiver.path)) == ("idle", size)
    source = Path(ADAPTER).read_text(encoding="utf-8")
    assert [name for name in ("subprocess", "urllib", "requests", "socket") if name in source] == []

def test_r1_full_recovery_keeps_the_original_text(tmp_path):
    receiver, _ = _receiver(tmp_path, _Band(), capacity=1)  # 두 번째 글 = FULL, 원문은 received 행에 남는다
    assert [receiver.handle(_event(ts=ts, text=text))["state"] for ts, text in (
        ("1800000001.000100", "첫 글"), ("1800000002.000100", "반드시 보존할 업무 원문"))] == ["dispatched", "full"]
    again, counted = _receiver(tmp_path, _Band(), capacity=2)  # 용량 해제 = 격리 입력(r1579 몫)
    (verdict,) = again.recover()
    body = Path(counted.inner.body_path(verdict["command"])).read_text(encoding="utf-8")
    assert (verdict["state"], "반드시 보존할 업무 원문" in body, body.startswith("[[slack-key")) == ("dispatched", True, True)


def test_r2_redelivered_unfinished_message_is_acked(tmp_path):
    assert _crash_run(tmp_path, "submit").returncode == 9
    band = _Band()
    receiver, client = _receiver(tmp_path, band)
    verdict = receiver.handle(_event())  # 같은 사건 재전달 — 확인은 lookup 결과와 무관
    assert (verdict["state"], verdict["via"], len(band.acks), client.submits) == ("dispatched", "lookup", 1, 0)


def test_g_remaining_13_cases_are_listed_not_dropped():
    header = Path(__file__).read_text(encoding="utf-8").split('"""')[1]
    assert sorted(HANDLED + REST) == sorted(CASES_BY_ID) and len(CASES_BY_ID) == 21
    assert [cid for cid in HANDLED + REST if cid not in header] == []  # 지우면 여기서 깨진다

def test_h_core_untouched_guard_rc0_and_no_secret():
    changed = subprocess.run(["git", "-C", FT2, "status", "--porcelain", "--", "core"], capture_output=True,
                             text=True, timeout=25)
    guard = subprocess.run([sys.executable, "-I", GUARD], capture_output=True, timeout=25)
    source = Path(ADAPTER).read_text(encoding="utf-8")
    assert (changed.stdout.strip(), guard.returncode, re.compile(r"xox[abposre]-|xapp-\d").search(source)) == ("", 0, None)

def _judge_variant(check):
    """변이 M4·M7·M8·M9 — `check` 가 값을 내면 그 판정, 아니면 정본 판정."""
    def judge(self, receipt, via="submit"):
        return check(receipt, via) or slack.SlackReceive._judge(self, receipt, via)
    return judge

# M4 «용량 부족» 을 완료로 · M7 조회에 written True 요구 · M8 객체 있음만으로 완료 · M9 BUSY 를 완료로
_m4 = _judge_variant(lambda receipt, via: ("dispatched", "FULL") if receipt and receipt.result == FULL else 0)
_m7 = _judge_variant(lambda receipt, via: ("hold", "written") if via == "lookup" and receipt
                     and not receipt.written else None)
_m8 = _judge_variant(lambda receipt, via: ("dispatched", "객체 있음") if via == "lookup" and receipt else None)
_m9 = _judge_variant(lambda receipt, via: ("dispatched", "BUSY") if receipt and receipt.result == BUSY else None)
_M9 = type("_Mutant", (slack.SlackReceive,), {"_judge": _m9})
_m2_no_channel_key = lambda self, event: slack.SlackReceive._key(event)._replace(channel="")  # noqa: E731
_m3_budget_reset = lambda self, command: 1  # noqa: E731  재기동마다 예산 0

def _m1_ack_after_submit(self, command, key, event, attempts, confirm=True):  # 확인이 입구 뒤로
    verdict = slack.SlackReceive._dispatch(self, command, key, event, attempts, confirm=False)
    self.ack(event)
    self._step("ack")
    return verdict

def _m5_no_bot_filter(self, event):  # bot 사건을 입구로
    reason = slack.SlackReceive._drop_reason(self, event)
    return "" if reason == "bot" else reason
def _m6_idle_wakes(self):  # 무변화 사건에 좌석 깨움 1회
    self.client.submit("slack:idle", "무변화")
    return slack.SlackReceive.pass_idle(self)
def _mutant(root, **methods):
    return _receiver(root, _Band(), cls=type("_Mutant", (slack.SlackReceive,), methods))
def test_m1_m9_mutations_are_caught(tmp_path):
    receiver, _ = _mutant(tmp_path / "m1", _dispatch=_m1_ack_after_submit)
    assert receiver.handle(_event()) and receiver.steps != ORDER
    receiver, client = _mutant(tmp_path / "m2", channels=(C, "C2"), _key=_m2_no_channel_key)
    [receiver.handle(_event(channel=channel)) for channel in (C, "C2")]
    assert (len(receiver.latest()), client.submits) == (1, 1)
    assert _crash_run(tmp_path / "m3", "ack").returncode == 9
    receiver, client = _mutant(tmp_path / "m3", _next_attempt=_m3_budget_reset)
    receiver.recover()
    assert "[[slack-key" not in Path(client.inner.body_path("slack:%s:%s:%s" % (W, C, TS))).read_text("utf-8")
    receiver, _ = _mutant(tmp_path / "m4", capacity=2, _judge=_m4)
    states = [receiver.handle(_event(ts="180000000%d.000100" % number))["state"] for number in (1, 2, 3)]
    assert states != ["dispatched", "dispatched", "full"]
    receiver, client = _mutant(tmp_path / "m5", _drop_reason=_m5_no_bot_filter)
    assert (receiver.handle(_event(bot_id="B1"))["state"], client.submits) == ("dispatched", 1)
    receiver, client = _mutant(tmp_path / "m6", pass_idle=_m6_idle_wakes)
    assert (receiver.pass_idle()["state"], len(client.records()), len(receiver.entries())) != ("idle", 0, 0)
    assert _crash_run(tmp_path / "m7", "submit").returncode == 9
    receiver, _ = _mutant(tmp_path / "m7", _judge=_m7)
    assert [v["state"] for v in receiver.recover()] != ["dispatched"]
    assert _crash_run(tmp_path / "m8", "", "after_body").returncode == 9
    receiver, _ = _mutant(tmp_path / "m8", _judge=_m8)
    assert [v["state"] for v in receiver.recover()] != ["hold"]
    for cls, want in ((slack.SlackReceive, "hold"), (_M9, "dispatched")):
        inner = intake.Intake(str(tmp_path / "m9" / want), TEAM)
        receiver = cls(str(tmp_path / "m9" / want), ack=_Band().ack, client=_BusyOnce(inner), team=TEAM,
                       allowed_users={"U1"}, allowed_channels={C})
        verdict = receiver.handle(_event())
        assert (verdict["state"], verdict["receipt"]["result"], len(inner.records())) == (want, BUSY, 0)

class _BusyOnce:
    """r1579 실행권 대역 — 잠금 점유 중 submit 은 BUSY(아직 착지 전)."""
    def __init__(self, inner):
        self.inner = inner
    def submit(self, command, body, work=None):
        return intake.Receipt(BUSY, command, None, 0, False, None, "실행권 점유")
    def lookup(self, command):
        return self.inner.lookup(command)

def _crash_run(root, slack_step, core_step=""):
    return subprocess.run([sys.executable, os.path.abspath(__file__), str(root), slack_step, core_step],
                          env=dict(os.environ, FT2_SLACK_CHILD="1"), capture_output=True, timeout=25)

def _child_main(argv):
    root, slack_step, core_step = argv[0], argv[1], argv[2]
    def exit_at(step):
        if step in (slack_step, core_step):
            os._exit(9)
    receiver, _ = _receiver(root, _Band())
    receiver.client, receiver.on_step = _Counted(intake.Intake(root, TEAM, on_step=exit_at)), exit_at
    receiver.handle(_event())
    return 0

if __name__ == "__main__":
    sys.exit(0 if os.environ.get("FT2_SLACK_CHILD") != "1" else _child_main(sys.argv[1:]))
