"""ft2 Slack 접수(dict-work)는 용량 칸을 쥐지 않는다 — 카드 ft2-slack-accept-capacity · 사례 ㉖가~바 · 변이 M7·M8·M9.

계약: S0 accept 줄의 work 가 dict 이면 «글 영수» — 용량 단위 0(S1 record.capacity) · S2 remaining 손 0 ·
S3 reply_done._requeue = FULL 글마다 그때의 실제 용량 + 입구 영수(영수 «용량 부족» = 그 뒤 미요청 건너뜀) ·
S4 full_alert.remaining() 값 = 투영 capacity 칸(없으면 remaining).
임시 root · 시험 안에서 만든 journal(실 runtime·실 Slack·네트워크 0) · 가짜 mbox · sleep 0 · 사례 1개 70초 안.
기준판(origin/main 731bc236)에서 ㉖가·㉖나·㉖다·㉖마·㉖바 = Red · ㉖라만 통과(work None 은 그대로 = 계약 보존 확인).
"""
import importlib.util
import json
import os
import shutil
import types  # noqa: E401

import pytest

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEAM, W, C, T = "harness", "TFAKE", "CFAKE", "1800000000.000100"
OK, FULL = "접수 성공", "용량 부족"
MBOX = '#!/bin/sh\nprintf "%s\\t%s\\t%s\\n" "$2" "$3" "$(printf "%s" "$4" | head -1)" >> "$0.log"\n'


def _mods(base=FT2, tag="base"):
    """사본까지 같은 방식으로 읽는다 — 각 장이 자기 폴더의 이웃을 스스로 _load 한다."""
    out = {}
    for name, rel in (("record", "core/record.py"), ("intake", "core/intake.py"), ("dispatch", "core/dispatch.py"),
                      ("projection", "core/projection.py"), ("receive", "adapters/slack/receive.py"),
                      ("reply_done", "adapters/slack/reply_done.py"), ("full_alert", "adapters/pi/full_alert.py")):
        spec = importlib.util.spec_from_file_location("ft2_accept_%s_%s" % (tag, name), os.path.join(base, rel))
        spec.loader.exec_module(out.setdefault(name, importlib.util.module_from_spec(spec)))
    return types.SimpleNamespace(**out)


M = _mods()


def cmd(ts):
    return "slack:%s:%s:%s" % (W, C, ts)


def planner_work(ts, thread):
    """planner 꼴 — route(thread·kind) + slack(workspace·channel·ts)."""
    return {"route": {"channel": C, "id": None, "kind": "새 업무", "thread": thread},
            "slack": {"workspace": W, "channel": C, "ts": ts}}


def issue_work():
    """issues 꼴 — slack.team 만 있는 dict work(배정·답글 길 0)."""
    return {"slack": {"team": "planner"}}


class World:
    def __init__(self, tmp, mods):
        self.root, self.m = tmp / "root", mods
        self.root.mkdir(parents=True, exist_ok=True)

    def intake(self):
        return self.m.intake.Intake(str(self.root), TEAM)

    def submit(self, command, work=None, capacity=8):  # capacity = 그 접수 1회의 문턱(픽스처 쌓기만 16)
        gate = self.m.intake.Intake(str(self.root), TEAM, capacity=capacity)
        return gate.submit(command, "본문 " + command.split(":")[-1], work)

    def proj(self):
        return self.m.projection.project(str(self.root), TEAM)

    def records(self):
        return self.intake().records()

    def state(self):
        return self.intake()._state()

    def complete(self, work):
        return self.m.dispatch.Dispatch(str(self.root), TEAM).complete(work)

    @property
    def runtime(self):
        return self.root / ".fable-team" / "teams" / TEAM / "runtime"

    def journal(self):
        return [json.loads(line) for path in sorted(self.runtime.glob("journal*.jsonl"))
                for line in path.read_text(encoding="utf-8").splitlines()]

    def alert(self):  # ㉖바 — 실 full_alert.remaining · 받는 곳 = 가짜 mbox
        return self.m.full_alert.remaining(str(self.root), TEAM, OK)

    def fake_alert(self):
        fable = self.root / ".fable-team"
        (fable / "comm").mkdir(parents=True, exist_ok=True)
        (fable / ("seats-%s.json" % TEAM)).write_text(json.dumps({"_master": "byz-harness-master-pi#9"}), encoding="utf-8")
        (fable / "comm" / "mbox.sh").write_text(MBOX, encoding="utf-8")

    def sent(self, word=""):
        path = self.root / ".fable-team" / "comm" / "mbox.sh.log"
        rows = [ln.split("\t") for ln in path.read_text(encoding="utf-8").splitlines()] if path.exists() else []
        return [row for row in rows if word in row[2]]


def c_ga(t):   # ㉖가 planner 꼴 dict-work 8 → 9번째 Slack 접수 = 접수 성공 · 앞뒤 capacity 0 · remaining 8→9
    tses = ["1800000001.%06d" % n for n in range(8)]
    for ts in tses:
        assert t.submit(cmd(ts), planner_work(ts, ts)).result == OK
    before = t.proj()
    out = t.submit(cmd("1800000002.000001"), planner_work("1800000002.000001", "1800000002.000001"))
    after = t.proj()
    assert (before["capacity"], before["remaining"]) == (0, 8), before
    assert (out.result, out.written) == (OK, True), out
    assert (after["capacity"], after["remaining"]) == (0, 9), after


def c_na(t):   # ㉖나 issues 꼴 dict-work 8 → str-work 접수 1 = 접수 성공 · capacity 0→1 · remaining 8→9 · complete 손 0
    for n in range(8):
        assert t.submit("issue-%d" % n, issue_work()).result == OK
    before = t.proj()
    out = t.submit("keeper-next-card-x", "w-card")
    after = t.proj()
    assert (before["capacity"], before["remaining"]) == (0, 8), before
    assert out.result == OK, out
    assert (after["capacity"], after["remaining"]) == (1, 9), after
    assert [rec for rec in t.records() if rec["kind"] == "complete"] == []


def c_da(t):   # ㉖다 dict-work 8 + str-work 8 → 다음 str-work = 용량 부족 · 문구의 남은 일 8(기준판 = 16)
    for n in range(8):
        assert t.submit("issue-%d" % n, issue_work(), capacity=16).result == OK  # 픽스처만 문턱 16
        assert t.submit("card-%d" % n, "w%d" % n, capacity=16).result == OK
    out = t.submit("card-8", "w8")
    assert out.result == FULL, out
    assert "남은 일 8 >= 상한 8" in out.reason, out.reason


def c_ra(t):   # ㉖라 work None 접수 8 → 다음 접수 = 용량 부족(r2055 §4.1 그대로)
    for n in range(8):
        assert t.submit("none-%d" % n, None).result == OK
    assert t.submit("none-8", None).result == FULL


def c_ma(t):   # ㉖마 str-work 8 포화 · thread T 에 dict-work 1 → Slack 글 9건 full → 1칸 열림 → 답글 = 9건 전부 재접수
    assert t.submit(cmd(T), planner_work(T, T), capacity=16).result == OK      # 픽스처만 문턱 16
    for n in range(8):
        assert t.submit("card-%d" % n, "w%d" % n, capacity=16).result == OK
    inbox = t.m.receive.SlackReceive(str(t.root), ack=lambda event: None, team=TEAM,
                                     allowed_users={"U1"}, allowed_channels={C})
    order = ["1800000005.00030", "1800000005.00010", "1800000005.00050", "1800000005.00020", "1800000005.00090",
             "1800000005.00040", "1800000005.00060", "1800000005.00080", "1800000005.00070"]
    for ts in order:
        assert inbox.handle({"type": "message", "team": W, "channel": C, "ts": ts, "user": "U1",
                             "text": "글 " + ts})["state"] == "full"
    assert t.proj()["capacity"] == 8
    assert t.complete("w0").result == OK                               # 여유 1칸
    out = t.m.reply_done.settle(str(t.root), TEAM, {"command": cmd("1800000006.000900"), "key": [W, C, T]})
    assert out["requeued"] == [cmd(ts) for ts in sorted(order)], out       # ts 오래된 순 · 여유 1칸보다 많음
    assert [inbox.latest()[cmd(ts)]["state"] for ts in sorted(order)] == ["dispatched"] * 9
    assert (out["completed"], t.proj()["capacity"]) == ([cmd(T)], 7), out
    again = t.m.reply_done.settle(str(t.root), TEAM, {"command": cmd("1800000006.000901"), "key": [W, C, T]})
    assert again["requeued"] == [], again                              # 같은 settle 한 번 더 = 재접수 0(멱등)


def c_ba(t):   # ㉖바 알림 값 = capacity 칸 — dict-work 8 = 0/8 알림 0 · str-work 8 = 꽉 참 1 · complete 1 = 풀림 1
    t.fake_alert()
    for n in range(8):
        assert t.submit("issue-%d" % n, issue_work()).result == OK
    assert t.alert() is None and t.sent() == []                        # 기준판 = 꽉 참 알림 1통
    for n in range(8):
        assert t.submit("card-%d" % n, "w%d" % n).result == OK
    assert t.alert() is not None and len(t.sent()) == 1
    assert "8/8" in t.sent()[0][2] and "★크리티컬★" in t.sent()[0][2], t.sent()
    assert t.complete("w0").result == OK
    assert t.alert() is not None and len(t.sent("풀림")) == 1 and len(t.sent()) == 2
    assert t.alert() is None and len(t.sent()) == 2                    # 같은 값 다시 = 0통


CASES = {"㉖가": c_ga, "㉖나": c_na, "㉖다": c_da, "㉖라": c_ra, "㉖마": c_ma, "㉖바": c_ba}


def _mutant(tmp, edits):
    """ft2 사본 1곳(시험 폴더 제외) — edits = [(상대경로, [(바꿀 줄, 새 줄), …])] · 각 줄은 정확히 1곳."""
    tree = tmp / "ft2m"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    for rel, pairs in edits:
        path, text = tree / rel, (tree / rel).read_text(encoding="utf-8")
        for old, new in pairs:
            assert text.count(old) == 1, (rel, old)
            text = text.replace(old, new)
        path.write_text(text, encoding="utf-8")
    return _mods(str(tree), tag=tmp.name.replace("-", "_"))


REQUEUE_SEAM = ("        state, records = desk.ex._state_records()\n"
                "        room = desk.rs.capacity - len(dispatch.record.capacity(state, records))\n"
                "        if blocked or room <= 0:\n"
                "            continue  # 여유 0 = 재접수 0(r1938) · 영수 «용량 부족» = 그 뒤 미요청 글 건너뜀(r2089)\n"
                "        verdict = inbox._recover(entry[\"command\"], entry=entry)\n"
                "        if verdict.get(\"state\") == receive.DISPATCHED:\n"
                "            out = out + [entry[\"command\"]]")

MUTANTS = {
    "M7": ([("core/record.py", [("units = {works[cmd] if isinstance(works[cmd], str) else \"cmd:\" + cmd\n"
                                 "             for cmd in works if not isinstance(works[cmd], dict)}",
                                 "units = {works[cmd] if isinstance(works[cmd], str) else \"cmd:\" + cmd\n"
                                 "             for cmd in works}")])], [c_ga, c_na, c_ma]),
    "M8": ([("adapters/slack/reply_done.py", [
        ("out, blocked = [], False",
         "out, blocked = [], False\n    room = desk.rs.capacity - len(dispatch.record.capacity(*desk.ex._state_records()))"),
        (REQUEUE_SEAM, "        if blocked or room <= 0:\n"
                       "            continue\n"
                       "        room -= 1\n"
                       "        verdict = inbox._recover(entry[\"command\"], entry=entry)\n"
                       "        if verdict.get(\"state\") == receive.DISPATCHED:\n"
                       "            out = out + [entry[\"command\"]]")])], [c_ma]),
    "M9": ([("adapters/pi/full_alert.py", [('value = proj.get("capacity", proj.get("remaining")) if proj.get("result") == "접수 성공" else None',
                                            'value = proj.get("remaining") if proj.get("result") == "접수 성공" else None')])], [c_ba]),
}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path):
    CASES[name](World(tmp_path, M))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path):
    edits, cases = MUTANTS[name]
    mutated = _mutant(tmp_path, edits)
    for index, case in enumerate(cases):
        with pytest.raises(AssertionError):
            case(World(tmp_path / ("m%d" % index), mutated))
        case(World(tmp_path / ("b%d" % index), M))   # 같은 사례가 원판에서는 통과
