"""ft2 닫기 영수 다음 카드 고르기 · Slack 접수 accept(work = dict) 섞임 시험 (r1881).
실사건 = planner 닫기 영수 → `_pick_next` 의 `dict.fromkeys` 가 dict work 를 key 로 써 TypeError · keeper 바퀴 정지.
반례 ①~④ = 카드 그대로 · 격리 tmp · 고정 시계 · 가짜 probe · 실 장부·명부·pane 0 · 변이 M1(isinstance 빼기) → ①② FAIL."""
import importlib.util
import json
import os

import pytest

CORE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "core")
TEAM, NOW, NANO, NEXT = "feature", "2026-11-13T22:00:00", "byz-feature-nano-r1-x#1", "byz-feature-nano-r2-y#1"
OK, REFUSED, NONE_NEXT, EV = "접수 성공", "접수 거부", "[다음 없음]", ("v1", "v2")
ALL = dict.fromkeys(("산출 완료", "원격 보존", "팀장 인수", "남은 일 팀장 몫"), True)

def _mod(name):
    spec = importlib.util.spec_from_file_location("ft2_test_r1881_" + name, os.path.join(CORE, name + ".py"))
    out = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(out)
    return out

CN, DP = _mod("close_next"), _mod("dispatch")

def _slack(ts):
    where = {"workspace": "T0", "channel": "C0", "ts": ts}
    return {"route": {"channel": "C0", "id": None, "kind": "새 업무", "thread": ts, "to": "byz-feature-master-pi#1",
                      "workspace": "T0"}, "slack": dict(where, attempts=1)}

def _node(root):
    return CN.CloseNext(str(root), TEAM, clock=lambda: NOW, probe=lambda seat: "absent")

def _base(root, cards=(), slacks=0):
    """W1 닫힘(배정·완료) → 카드 accept(str) cards + Slack accept(dict) slacks 건 → 켜기 표식."""
    d = DP.Dispatch(str(root), TEAM, clock=lambda: NOW)
    assert [d.rs.submit("c-W1", "x" * 8, "W1").result, d.assign("W1", NANO, evidence=EV).result,
            d.ex.result("W1", NANO, 1, OK).result, d.deliver("W1", "a1").result,
            d.complete("W1", "a1").result] == [OK] * 5
    for i in range(slacks):
        assert d.rs.submit("slack:T0:C0:%d.1" % i, "x" * 8, _slack("%d.1" % i)).result == OK
    assert [d.rs.submit("c-%d-%s" % (i, w), "x" * 8, w).result for i, w in enumerate(cards)] == [OK] * len(cards)
    (root / "facts.json").write_text(json.dumps({NANO: ALL}), encoding="utf-8")
    assert _node(root).enable(str(root / "facts.json")).result == OK
    return d


def _go(root, next_work=None):
    return _node(root).receipt(NANO, 1, "W1", "e1", NEXT, EV, next_work=next_work)


def _kinds(root):
    return [rec["kind"] for rec in _node(root).rs.records()]


def test_1_card_and_two_slack_dicts_picks_card(tmp_path):
    _base(tmp_path, cards=("W2",), slacks=2)
    out = _go(tmp_path)
    assert (out.result, out.next, out.attempt, out.holder) == (OK, "W2", "a1", NEXT)
    assert _kinds(tmp_path)[-3:] == ["close_receipt", "dispatch", "deliver"]


def test_2_only_slack_dicts_gives_none(tmp_path):
    _base(tmp_path, slacks=2)
    out = _go(tmp_path)
    assert (out.result, out.next, _kinds(tmp_path).count("close_receipt")) == (OK, NONE_NEXT, 1)


@pytest.mark.parametrize("named, want", [("W2", (OK, "W2")), ("W9", (REFUSED, None))])
def test_3_named_card_with_slack_dicts_same_verdict(tmp_path, named, want):
    _base(tmp_path, cards=("W2",), slacks=2)
    lines, out = len(_kinds(tmp_path)), _go(tmp_path, next_work=named)
    assert (out.result, out.next) == want
    assert named == "W2" or (out.reason == "배정 불가 대기 카드 아님: 'W9'" and len(_kinds(tmp_path)) == lines)


def test_4_only_str_cards_unchanged(tmp_path):
    _base(tmp_path, cards=("W2", "W3", "W2"))
    out = _go(tmp_path)
    assert (out.result, out.next, out.attempt) == (OK, "W2", "a1")
    assert _kinds(tmp_path).count("dispatch") == 2
