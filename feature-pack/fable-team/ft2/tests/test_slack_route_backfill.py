"""ft2 Slack 수신 경로·보충 회차 시험 (r1585 · PR③ 셋째 장).

사례 대조(ⓕ): 21건 중 이 장은 6건(c5 c6 c8 d3 d4 f4) — 계약 낱말은 `CONTRACT-18.md` 대응표 원문, 결과 수치는
사례 `expect.observed.checks` 의 해당 칸과 대조한다(c6·d4 는 «수신 몫» 칸만 · 모형 현재값과의 차이는 각 시험의
단언에 적었다). 변이(M1~M7): **제품 파일 1곳을 직접 바꾼 사본**으로 돌린다(변이 클래스로 셈하지 않는다).
DA #280027 R1~R5 회귀 = 영수 없는 전달 0 · 입구 영수의 목적지 · 기존 영수 뒤 재개 · 요청 상태 보존 · 글 단위 표식.
DA #280022 ① = 실 Intake 영수까지, ② = M3 을 «커서 독립 · 새 글 보존» 직접 관측으로. 다음 장 = f1 f2 f3 · 줄 1 · 줄 18.
"""

import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADAPTER_DIR = os.path.join(FT2, "adapters", "slack")
ROUTE, BACKFILL = os.path.join(ADAPTER_DIR, "route.py"), os.path.join(ADAPTER_DIR, "backfill.py")
CASES = Path(FT2, "contracts", "slack", "cases")
CONTRACT = Path(FT2, "contracts", "slack", "CONTRACT-18.md")
GUARD = os.path.join(FT2, "tools", "legacy_guard.py")
TEAM, W, C = "harness", "TFAKE", "CFAKE"
DESK = "@team-desk"
TS, T2, T3, T4, T5 = ("1800000001.000100", "1800000002.000100", "1800000003.000100",
                      "1800000004.000100", "1800000005.000100")
CASE_IDS = ("c1", "c2", "c3", "c4", "c5", "c6", "c7", "c8", "d1", "d2", "d3", "d4",
            "t1", "t2", "t3", "t4", "t5", "f1", "f2", "f3", "f4")
HANDLED = ("c5", "c6", "c8", "d3", "d4", "f4")


def _load(name, path):
    spec = importlib.util.spec_from_file_location("ft2_" + name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

route_mod = _load("slack_route", ROUTE)
backfill = _load("slack_backfill", BACKFILL)
slack = _load("slack_receive", os.path.join(ADAPTER_DIR, "receive.py"))
binding = _load("slack_binding", os.path.join(ADAPTER_DIR, "binding.py"))
intake = _load("core_intake", os.path.join(FT2, "core", "intake.py"))
COVERS = dict(route_mod.COVERS)
COVERS.update(backfill.COVERS)
CASES_BY_ID = {p.stem.split("-")[1].split("_")[0]: json.loads(p.read_text(encoding="utf-8"))
               for p in sorted(CASES.glob("*.json"))}


def _contract_rows():
    md = CONTRACT.read_text(encoding="utf-8").split("## 대응표", 1)[1].split("\n## ", 1)[0]
    return {int(number): text for number, text in re.findall(r"^\| (\d+) \| (.*?) \|", md, re.M)}


def _case(cid):
    """사례 1건 — 계약 낱말이 18줄 원문에 있고, 그 사례 줄은 이 장 몫이다."""
    case, rows = CASES_BY_ID[cid], _contract_rows()
    assert [w for w in case["expect"]["words"] if w not in " ".join(rows.values())] == []
    assert set(case["contract"]) - set(COVERS) == set()
    return case["expect"]["observed"]["checks"]


def _expect(checks, cid, *names):
    """사례 expect.observed.checks 의 그 칸과 그대로 대조한다(ⓕ)."""
    expect = _case(cid)
    assert {name: checks[name] for name in names} == {name: expect[name] for name in names}


def _event(**extra):
    return dict({"type": "message", "team": W, "channel": C, "ts": TS, "user": "U1", "text": "안녕"}, **extra)


def _reply(ts, text, root=TS):
    return _event(ts=ts, thread_ts=root, text=text)


def _slack_ts(index, serial):
    """thread 별로 겹치지 않는 ts — 10자리.초6자리 꼴(Slack ts 와 같은 모양)."""
    return "%010d.%06d" % (1800000000 + index * 10, serial)


class _Band:
    """Slack 확인·알림 대역. 실제 Intake 는 `_Counted` 가 그대로 부른다."""
    def __init__(self):
        self.acks, self.notify = [], []

    def ack(self, event):
        self.acks.append(event)


class _Counted:
    """실 Intake 위임 + 호출 계수 — 판정값은 꾸미지 않는다(DA #280022 ①)."""
    def __init__(self, inner):
        self.inner = inner

    def submit(self, *args, **kwargs):
        return self.inner.submit(*args, **kwargs)

    def lookup(self, command):
        return self.inner.lookup(command)

    def records(self):
        return self.inner.records()


def _env(root, route_cls=route_mod.SlackRoute, capacity=64):
    """route 1좌석 — 실 Intake 까지 배선. `delivered` = 좌석 전달(모델 호출 1회) 기록."""
    band = _Band()
    client = _Counted(intake.Intake(str(root), TEAM, capacity=capacity))
    receive = slack.SlackReceive(str(root), ack=band.ack, client=client, team=TEAM, allowed_users={"U1"},
                                 allowed_channels={C}, notify=band.notify.append)
    binder = binding.ThreadBinding(str(root), TEAM)
    delivered = []
    route = route_cls(str(root), receive=receive, bindings=binder, team=TEAM, notify=band.notify.append,
                      deliver=lambda to, kind, lines: delivered.append({"to": to, "kind": kind,
                                                                        "lines": list(lines)}))
    return route, binder, delivered, client, band


def _commands(client):
    return sorted(record["command"] for record in client.records())


def _intake_route(client, index=-1):
    return (client.records()[index]["work"] or {}).get("route") or {}


# ── ⓐ c6·d4: 닫힌 thread 새 글 = 재개 필요 @team-desk ────────────────────────
def _scenario_c6(tmp, route_cls=route_mod.SlackRoute):
    route, binder, delivered, client, _band = _env(tmp, route_cls)
    key = route_mod.thread_key(_event())
    binder.bind(key, "seat-a")
    first = route.route(_event(text="첫 글"))
    binder.close(key)
    owner_after_close, seen = binder.get(key).owner, len(delivered)
    last = route.route(_reply(T2, "닫힌 뒤 새 글"))
    route.pending("seat-next")  # 다음 좌석이 그 미처리 1건을 본다
    return {"binding_open": binder.get(key).open, "owner_after_close": owner_after_close,
            "states": [first["state"], last["state"]],
            "last_entrance": {"to": last["to"], "kind": last["kind"]},
            "old_seat_wakes": len([d for d in delivered[seen:] if d["to"] == "seat-a"]),
            "pending_seen_by_next": route.seen_by_next(), "intake_commands": len(_commands(client))}


def _check_c6(checks):
    _expect(checks, "c6", "binding_open", "owner_after_close", "states", "last_entrance", "pending_seen_by_next")
    assert (checks["old_seat_wakes"], checks["intake_commands"]) == (0, 2)  # 옛 owner 깨움 0 · 실 Intake 영수 2


def _scenario_d4(tmp, route_cls=route_mod.SlackRoute):
    route, binder, delivered, _client, _band = _env(tmp, route_cls)
    key = route_mod.thread_key(_event())
    binder.bind(key, "seat-a")
    route.route(_event(text="첫 글"))
    binder.close(key)
    owner_after_close, seen = binder.get(key).owner, len(delivered)
    last = route.route(_reply(T2, "닫힌 뒤 새 글"))
    reopened = binder.reopen(key, "seat-b")
    again = route.route(_reply(T3, "재개 뒤 새 글"))
    return {"owner_after_close": owner_after_close, "states": [last["state"], again["state"]],
            "last_kind": last["kind"], "last_to": last["to"],
            "old_owner_reply": bool([d for d in delivered[seen:] if d["to"] == "seat-a"]),
            "reopen_gen": reopened["gen"], "new_owner_posted": delivered[-1]["to"] == "seat-b"}


def _check_d4(checks):
    _expect(checks, "d4", "owner_after_close", "states", "last_kind", "last_to", "old_owner_reply",
            "reopen_gen", "new_owner_posted")


def _scenario_c5(tmp, route_cls=route_mod.SlackRoute):
    route, binder, delivered, _client, _band = _env(tmp, route_cls)
    roots = (_slack_ts(1, 1), _slack_ts(9, 1))
    for index, root in enumerate(roots):
        binder.bind(route_mod.thread_key(_event(ts=root)), "seat-a")
        for step in range(4):
            route.route(_event(ts=_slack_ts(index + 1, step + 2), thread_ts=root,
                               text="thread %d 줄 %d" % (index, step + 1)))
    ctx_a, ctx_b = (route.context(route_mod.thread_key(_event(ts=root))) for root in roots)
    return {"ctx_a": len(ctx_a), "ctx_b": len(ctx_b), "cross_injection": len(set(ctx_a) & set(ctx_b)),
            "mixed_to": sorted({d["to"] for d in delivered})}


def _check_c5(checks):
    _expect(checks, "c5", "ctx_a", "ctx_b", "cross_injection")
    assert checks["mixed_to"] == ["seat-a"]  # 목적지는 binding 이 정한다(모델 분류기 0)


# ── ⓒ c8: 좌석·thread 커서 ────────────────────────────────────────────────
class _History:
    """conversations.history/replies 대역 — 커서 뒤만, 쪽 단위로, 읽은 byte 를 센다."""
    def __init__(self, rows):
        self.rows, self.calls, self.bytes = list(rows), [], 0

    def add(self, row):
        self.rows.append(row)

    def fetch(self, channel, thread, after, limit):
        pool = [r for r in self.rows if r["thread"] == thread and (not after or r["ts"] > after)]
        page = pool[:limit]
        self.calls.append({"thread": thread, "after": after, "rows": len(page)})
        self.bytes += sum(len(json.dumps(r, ensure_ascii=False)) for r in page)
        return {"rows": page, "next": pool[limit]["ts"] if len(pool) > limit else None}


def _c8_band(roots, replies):
    rows, targets = [], []
    for index in range(roots):
        thread = _slack_ts(index + 1, 1)
        rows.append({"team": W, "thread": thread, "ts": thread, "root": True, "user": "U1",
                     "text": "root %d" % index})
        rows += [{"team": W, "thread": thread, "ts": _slack_ts(index + 1, step + 1), "user": "U1",
                  "text": "답 %d" % step} for step in range(1, replies + 1)]
        targets.append(("seat-a", C, thread))
    return _History(rows), targets


def _scenario_c8(tmp, route_cls=route_mod.SlackRoute, cursor_cls=None):
    shape = _case("c8")["shape"]
    route, binder, delivered, client, _band = _env(tmp, route_cls, capacity=4096)
    history, targets = _c8_band(shape["roots"], shape["replies_per_root"])
    for _seat, _channel, thread in targets:
        binder.bind(route_mod.thread_key(_event(ts=thread)), "seat-a")
    cursors = (cursor_cls or backfill.Cursors)(str(tmp), TEAM)
    worker = backfill.Backfill(str(tmp), route=route, fetch=history.fetch, cursors=cursors, team=TEAM, limit=15)
    boot = worker.run(backfill.RESTART, targets)
    calls, size, idle = len(delivered), history.bytes, {"calls": 0, "bytes": 0, "rows": 0}
    for step in range(2, 11):  # pass 2~10 (짝수 pass 에만 새 답 1건 · 홀수 pass = 새 글 0)
        if step % 2 == 0:
            history.add({"team": W, "thread": targets[step - 2][2], "ts": _slack_ts(step - 1, 20),
                         "user": "U1", "text": "새 답 %d" % step})
        before, _calls = (len(delivered), history.bytes), history.calls.clear()
        worker.run(backfill.RESTART, targets)
        if step % 2 == 1:
            idle["calls"] += len(delivered) - before[0]
            idle["bytes"] += history.bytes - before[1]
            idle["rows"] += sum(call["rows"] for call in history.calls)
    return {"boot_dispatched": boot["dispatched"], "steady_calls": len(delivered) - calls,
            "steady_bytes": history.bytes - size, "idle_pass": idle,
            "new_post": _c8_new_post(worker, cursors, history, targets, client),
            "cursor_keys": len(cursors.of()), "cursor_threads": sorted(thread for _s, thread in cursors.of())}


def _c8_new_post(worker, cursors, history, targets, client):
    """M3 을 byte 가 아니라 «그 thread 커서만 전진 · 다른 thread 그대로 · 새 글이 Intake 까지» 로 잡는다."""
    thread, other, fresh = targets[6][2], targets[7][2], _slack_ts(7, 40)
    history.add({"team": W, "thread": thread, "ts": fresh, "user": "U1", "text": "새 글 1건"})
    before = (cursors.get("seat-a", thread), cursors.get("seat-a", other))
    run = worker.run(backfill.RESTART, [targets[6], targets[7]])
    return {"dispatched": run["dispatched"], "only_that_thread": cursors.get("seat-a", other) == before[1],
            "advanced": cursors.get("seat-a", thread) > before[0],
            "reached_intake": ("slack:%s:%s:%s" % (W, C, fresh)) in _commands(client)}


def _check_c8(checks):
    contract, shape = _case("c8")["contract"], _case("c8")["shape"]
    assert checks["boot_dispatched"] == shape["roots"] * shape["replies_per_root"]
    assert checks["steady_calls"] <= contract["model_calls_after_boot"]  # 계약 5 (모형 현재 14)
    assert checks["steady_bytes"] <= contract["reread_bytes_after_boot"]  # 계약 655 (모형 현재 136583)
    assert checks["idle_pass"] == {"calls": 0, "bytes": 0, "rows": 0}  # 새 글 0 pass = 호출 0 · 재로드 0
    assert len(set(checks["cursor_threads"])) == checks["cursor_keys"] == shape["roots"]  # 좌석·thread 별 커서
    assert checks["new_post"] == {"dispatched": 1, "only_that_thread": True, "advanced": True,
                                 "reached_intake": True}


def _scenario_d3(tmp, worker_cls=None):
    route, binder, _delivered, client, _band = _env(tmp)
    thread = TS
    binder.bind(route_mod.thread_key(_event(ts=thread)), "seat-a")
    rows = [{"team": W, "thread": thread, "ts": thread, "root": True, "user": "U1", "text": "root"}]
    rows += [{"team": W, "thread": thread, "ts": "18000000%02d.000100" % step, "user": "U1", "text": "글 %d" % step}
             for step in range(2, 18)]  # 사람 글 16건 = 1800000002 ~ 1800000017
    history, cursors = _History(rows), backfill.Cursors(str(tmp), TEAM)
    worker = (worker_cls or backfill.Backfill)(str(tmp), route=route, fetch=history.fetch, cursors=cursors,
                                               team=TEAM, limit=15)
    rounds = []
    for _ in range(3):  # 재시작 1회 → 보충 회차 3회(1쪽 limit 15)
        row = worker.run(backfill.RESTART, [("seat-a", C, thread)])
        rounds.append({"state": row["state"], "dispatched": row["dispatched"], "pages": row["pages"],
                       "cursor": cursors.get("seat-a", thread)})
    fetches, commands = len(history.calls), _commands(client)
    poll = worker.run("poll", [("seat-a", C, thread)])
    return {"round1": rounds[0], "round2": rounds[1], "round3": rounds[2],
            "cursor1_index": sum(1 for step in range(2, 18)
                                 if "18000000%02d.000100" % step <= rounds[0]["cursor"]),
            "entrance_rows": len(commands), "unique": len(set(commands)),
            "poll": {"state": poll["state"], "pages": poll["pages"], "dispatched": poll["dispatched"],
                     "fetches": len(history.calls) - fetches}}


def _check_d3(checks):
    expect = _case("d3")
    for name in ("round1", "round2", "round3"):
        assert {key: checks[name][key] for key in expect[name]} == expect[name], name
    _expect(checks, "d3", "cursor1_index", "entrance_rows", "unique")
    assert checks["poll"] == {"state": "건너뜀", "pages": 0, "dispatched": 0, "fetches": 0}  # 주기 폴링 0


def _scenario_f4(tmp, route_cls=route_mod.SlackRoute):
    route, binder, _delivered, _client, _band = _env(tmp, route_cls)
    key = route_mod.thread_key(_event())
    binder.bind(key, "seat-a")
    pairs = []

    def visit(event):
        row = route.route(event)
        pairs.append((row["kind"], row["state"]))

    visit(_event(text="인터뷰 질문", request_id="Q7"))
    route.route(_reply(T2, "첫 답"))  # 사례 밖 회차 — 재전달 판정의 기준
    visit(_reply(T3, "첫 답"))  # 같은 답 재전달 = duplicate
    visit(_reply(T4, "추가 답"))
    route.close(key)  # 질문 닫힘
    rebooted, _binder, _d2, _c2, _band2 = _env(tmp, route_cls)  # 재기동(기록에서 복원)
    late = rebooted.route(_reply(T5, "늦은 답"))
    pairs.append((late["kind"], late["state"]))
    return {"states": [state for _kind, state in pairs], "kinds": [kind for kind, _state in pairs],
            "after_restart_q": {"%s:%s" % (key[1], key[2]): {"id": value["id"], "state": value["state"]}
                                for key, value in rebooted.requests().items()}}


def _check_f4(checks):
    _expect(checks, "f4", "states", "kinds", "after_restart_q")


# ── 시험 5개 ──────────────────────────────────────────────────────────────
def test_a_closed_thread_and_thread_context(tmp_path):
    """ⓐ c6·d4 · ⓑ c5 — 사례 6건 중 셋."""
    _check_c6(_scenario_c6(tmp_path / "c6"))
    _check_d4(_scenario_d4(tmp_path / "d4"))
    _check_c5(_scenario_c5(tmp_path / "c5"))


def test_b_cursor_and_backfill_pages(tmp_path):
    """ⓒ c8 · ⓓ d3 — 좌석·thread 커서와 쪽 단위 재개."""
    _check_c8(_scenario_c8(tmp_path / "c8"))
    _check_d3(_scenario_d3(tmp_path / "d3"))


def test_c_interview_answers_survive_restart(tmp_path):
    """ⓔ f4 — 인터뷰 답·중복·늦은 답·재기동."""
    _check_f4(_scenario_f4(tmp_path / "f4"))


# ── DA #280027 R1~R5 회귀 ────────────────────────────────────────────────
def test_r1_receipt_gates_seat_delivery(tmp_path):
    """R1 — 영수 없는 사건(중복·full·이미 넘긴 답)은 좌석 전달 0 · 컨텍스트 0 · 접수 0."""
    route, binder, delivered, client, _band = _env(tmp_path / "dup")
    key = route_mod.thread_key(_event())
    binder.bind(key, "seat-a")
    first, again = route.route(_event()), route.route(_event())
    assert (first["state"], again["state"]) == ("dispatched", "duplicate")
    assert (len(delivered), len(route.context(key)), len(_commands(client))) == (1, 1, 1)

    route, binder, delivered, client, _band = _env(tmp_path / "full", capacity=1)
    binder.bind(route_mod.thread_key(_event()), "seat-a")
    route.route(_event())
    held = route.route(_reply(T2, "용량 밖"))
    assert (held["state"], len(delivered), len(_commands(client))) == ("full", 1, 1)

    route, binder, delivered, client, _band = _env(tmp_path / "answer")
    binder.bind(route_mod.thread_key(_event()), "seat-a")
    route.route(_event(request_id="Q7", text="질문"))
    route.route(_reply(T2, "같은 답"))
    twice = route.route(_reply(T3, "같은 답"))
    assert (twice["state"], len(delivered), len(_commands(client))) == ("duplicate", 2, 2)


def test_r2_routing_metadata_reaches_intake(tmp_path):
    """R2 — 목적지·kind 가 그 command 의 입구 영수에 남고, 전달 직전 닫힘을 다시 본다."""
    route, binder, delivered, client, _band = _env(tmp_path / "meta")
    key = route_mod.thread_key(_event())
    binder.bind(key, "seat-a")
    binder.close(key)
    row = route.route(_reply(T2, "닫힌 thread 글"))
    meta = _intake_route(client)
    assert (row["to"], row["kind"]) == (DESK, "재개 필요")
    assert (meta.get("to"), meta.get("kind"), meta.get("thread")) == (DESK, "재개 필요", key.root)

    route, binder, delivered, _client, _band = _env(tmp_path / "ack_close")
    key = route_mod.thread_key(_event())
    binder.bind(key, "seat-a")
    route.receive.ack = lambda event: binder.close(key)  # ack 안에서 닫힘 교차
    row = route.route(_event())
    assert (row["open"], row["to"], row["kind"]) == (False, DESK, "재개 필요")
    assert [item for item in delivered if item["to"] == "seat-a"] == []


def test_r3_backfill_skips_existing_receipts(tmp_path):
    """R3 — 기존 영수는 gap 이 아니라 «이미 처리» 다. 위치를 복원하고 새 글로 간다."""
    root = tmp_path / "r3"
    route, binder, _delivered, client, _band = _env(root)
    binder.bind(route_mod.thread_key(_event()), "seat-a")
    route.route(_reply(T2, "이미 접수된 글"))  # live 영수 존재 · 커서는 아직 없다
    history = _History([{"team": W, "thread": TS, "ts": T2, "user": "U1", "text": "이미 접수된 글"},
                        {"team": W, "thread": TS, "ts": T3, "user": "U1", "text": "영수 뒤 새 글"}])
    worker = backfill.Backfill(str(root), route=route, fetch=history.fetch, cursors=backfill.Cursors(str(root), TEAM),
                               team=TEAM)
    first = worker.run(backfill.RESTART, [("seat-a", C, TS)])
    second = worker.run(backfill.RECONNECT, [("seat-a", C, TS)])
    assert (first["dispatched"], first["state"], second["dispatched"]) == (1, "done", 0)
    assert worker.cursors.get("seat-a", TS) == T3
    assert ("slack:%s:%s:%s" % (W, C, T3)) in _commands(client)

    empty = backfill.Backfill(str(tmp_path / "r3b"), route=route, fetch=lambda *args: {"rows": [], "next": "page2"},
                              cursors=backfill.Cursors(str(tmp_path / "r3b"), TEAM), team=TEAM)
    assert empty.run(backfill.RESTART, [("seat-a", C, TS)])["state"] == "미완"  # 빈 쪽 + 다음 쪽 = 위치 보존


def test_r4_request_state_and_kind(tmp_path):
    """R4 — 질문 재전달이 닫힘을 되돌리지 않고, 거른 사건은 요청을 만들지 않으며, kind 는 그 id 다."""
    route, binder, _delivered, _client, _band = _env(tmp_path / "r4")
    key = route_mod.thread_key(_event())
    binder.bind(key, "seat-a")
    route.route(_event(request_id="Q8", text="질문"))
    answer = route.route(_reply(T2, "답"))
    route.close(key)
    route.route(_event(request_id="Q8", text="질문"))  # 재기동·재전달
    late = route.route(_reply(T3, "늦은 답"))
    assert (answer["kind"], late["kind"]) == ("답 Q8", "늦은 답 Q8")
    assert route.request(key) == {"id": "Q8", "state": "closed"}
    ignored = route.route(_event(user="UNAUTHORIZED", request_id="Q9", ts=T4))
    assert (ignored["state"], route.request(route_mod.thread_key(_event(ts=T4)))) == ("ignored", None)


def test_r5_pending_is_per_message(tmp_path):
    """R5 — pending 읽음 표식은 thread 가 아니라 그 글(메시지)만 소비한다."""
    route, binder, _delivered, _client, _band = _env(tmp_path / "r5")
    key = route_mod.thread_key(_event())
    binder.bind(key, "seat-a")
    binder.close(key)
    route.route(_reply(T2, "닫힌 글 1"))
    assert len(route.pending("seat-next")) == 1
    route.route(_reply(T3, "닫힌 글 2"))
    assert [row["command"].rsplit(":", 1)[-1] for row in route.pending("seat-next")] == [T3]


# ── 변이 M1~M7: 제품 파일 1곳을 직접 바꾼 사본 ───────────────────────────────
MUTATIONS = {
    "m1": (ROUTE, "            return REOPEN, DESK, False",
           "            return REOPEN, (now.seat or 'seat-a') if now is not None else 'seat-a', False"),
    "m2": (ROUTE, '        lines = [row["line"] for row in self.entries(NOTE) if tuple(row["key"]) == tuple(key)]',
           '        lines = [row["line"] for row in self.entries(NOTE) if tuple(row["key"][:2]) == tuple(key[:2])]'),
    "m3": (BACKFILL, '        return self.of().get((str(seat), str(thread)), "")',
           '        values = sorted(self.of().values())\n        return values[-1] if values else ""'),
    "m4": (ROUTE, "        if not event:  # 무변화 pass = 도구 안에서 끝난다",
           '        if not event:\n            self.deliver(None, "무변화", [])\n            # 무변화 pass'),
    "m5": (BACKFILL, "        if more:",
           '        if more:\n            self.cursors.advance(seat, thread, more)'),
    "m6": (BACKFILL, "        if reason not in REASONS:", "        if False:"),
    "m7": (ROUTE, '                return LATE % asked["id"], DESK, False',
           "                return NEW, DESK, False"),
}


def _mutant(root, name, source, old, new):
    """`source` 사본에서 `old` → `new` 1곳만 바꾼 모듈(치환 1회를 보증한다)."""
    text = Path(source).read_text(encoding="utf-8")
    assert text.count(old) == 1, "변이 자리를 못 찾음: %s" % name
    folder = Path(str(root), name)
    folder.mkdir(parents=True, exist_ok=True)
    target = folder / os.path.basename(source)
    target.write_text(text.replace(old, new), encoding="utf-8")
    shutil.copy(Path(source).parent / "binding.py", folder / "binding.py")
    return _load("mut_" + name, str(target))


def test_m1_m7_product_file_mutations_break_the_checks(tmp_path):
    muts = {name: _mutant(tmp_path / "mut", name, *spec) for name, spec in MUTATIONS.items()}
    cases = (
        ("m1", lambda root: _check_c6(_scenario_c6(root, muts["m1"].SlackRoute))),
        ("m2", lambda root: _check_c5(_scenario_c5(root, muts["m2"].SlackRoute))),
        ("m3", lambda root: _check_c8(_scenario_c8(root, cursor_cls=muts["m3"].Cursors))),
        ("m4", lambda root: _check_c8(_scenario_c8(root, route_cls=muts["m4"].SlackRoute))),
        ("m5", lambda root: _check_d3(_scenario_d3(root, worker_cls=muts["m5"].Backfill))),
        ("m6", lambda root: _check_d3(_scenario_d3(root, worker_cls=muts["m6"].Backfill))),
        ("m7", lambda root: _check_f4(_scenario_f4(root, muts["m7"].SlackRoute))),
    )
    for name, run in cases:
        with pytest.raises(AssertionError):
            run(tmp_path / ("case-" + name))


def test_f_cases_listed_and_invariants():
    header = Path(__file__).read_text(encoding="utf-8").split('"""')[1]
    assert sorted(CASE_IDS) == sorted(CASES_BY_ID) and len(CASES_BY_ID) == 21
    assert [cid for cid in HANDLED if cid not in header] == []
    assert {7, 8, 9, 10, 14, 16, 17} <= set(COVERS) <= set(_contract_rows())
    assert [_case(cid) for cid in HANDLED]  # 사례 expect 를 실제로 읽는다
    changed = subprocess.run(["git", "-C", FT2, "status", "--porcelain", "--", "core",
                              "adapters/slack/receive.py", "adapters/slack/binding.py",
                              "adapters/slack/publish.py", "tests/test_slack_receive.py",
                              "tests/test_slack_publish.py"], capture_output=True, text=True, timeout=25)
    guard = subprocess.run([sys.executable, "-I", GUARD], capture_output=True, timeout=25)
    source = Path(ROUTE).read_text(encoding="utf-8") + Path(BACKFILL).read_text(encoding="utf-8")
    assert (changed.stdout.strip(), guard.returncode) == ("", 0)  # 기존 공개 면·시험 무변경 · legacy_guard
    assert re.compile(r"xox[abposre]-|xapp-\d").search(source) is None
    network = r"^\s*(?:import|from)\s+(?:subprocess|urllib|requests|socket|http)\b"
    assert re.compile(network, re.M).search(source) is None  # 외부 호출 0(대역 주입만)
