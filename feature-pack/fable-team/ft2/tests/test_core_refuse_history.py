"""ft2 회수 거절 처리 이력 키 시험 (카드 r1724 · 계획 PLAN-ft20-reclaim-refuse-history-key-20261112 · R1 보정).
사례 = 계획 2절 H1~H10 + 중단 결속 H3c·H4c·H6c·H7c (함수 이름 = 사례 번호). 중단 = on_step 예외(kill·sleep 0).
시험 입력 = 격리 tmp 루트 · FT_NOW 고정 시계 · 파일 1개 70초 안 · 실 .fable-team 0. 재진입 표지 = 없음.
변이(core 사본에서만 · 하나씩): M1 사건 멱등 → H4·H4c · M2 PROJ_FIELDS refusals → H7·H7c ·
M3 requested 검사 → H2·H3c · M4 by 를 키에 → H5 · M5 recover_state 분기 → H3c·H6c·H7c."""
import importlib.util
import json
import os
import shutil
import subprocess
import sys
from types import SimpleNamespace

import pytest

CORE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "core")
TEAM, NOW, MASTER = "harness", "2026-11-12T11:00:00", "byz-harness-master-pi#210"
OK, HOLD, REFUSED, BUSY, CORRUPT = "접수 성공", "완료 유보", "접수 거부", "BUSY", "복구 필요"
AUTO, RETRY, HELD = "자동 해소", "재시도", "유보"
KEY = ("W1", "byz-harness-nano-r1-x#0", 0, "정리 차례 무응답", "abc123")
Boom = type("Boom", (RuntimeError,), {})


def _core(path=CORE, alias="ft2_test_rh_"):
    out = {}
    for name in ("refuse_history", "dispatch"):
        spec = importlib.util.spec_from_file_location(alias + name, os.path.join(path, name + ".py"))
        out[name] = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(out[name])
    return SimpleNamespace(rh=out["refuse_history"], dispatch=out["dispatch"])


M = _core()


def _node(root, m=M, stop=None, seg=None):
    def step(name):
        if name == stop:
            raise Boom(name)
    node = m.rh.RefuseHistory(str(root), TEAM, clock=lambda: NOW, on_step=step)
    if seg:
        node.rs.journal.segment_cap = seg
    return node


def _ref(node, event, by=None, key=KEY):
    return node.refuse(*key, event, by=by)


def _row(root, m=M, key=KEY):
    node = _node(root, m)
    state = node.rs.journal.rec.recover_state(node.rs._state(), node.rs.records())
    return state["refusals"].get(node.key_of(*key))


def _lines(root, m=M):
    return len(_node(root, m).rs.records())


def _brief(out):
    return out.result, out.next, out.request_human


def _h1(root, m=M):
    node = _node(root, m)
    assert [_brief(_ref(node, e)) for e in ("e1", "e2", "e3")] \
        == [(OK, AUTO, False), (OK, RETRY, False), (HOLD, HELD, True)]
    return node


def _h2(root, m=M):
    assert _brief(_ref(_h1(root, m), "e4")) == (HOLD, HELD, False)


def _crash_e3(root, m=M):
    node = _node(root, m)
    _ref(node, "e1"), _ref(node, "e2")
    with pytest.raises(Boom):
        _ref(_node(root, m, stop="after_refuse_journal"), "e3")


def _h3c(root, m=M):
    _crash_e3(root, m)
    row = _row(root, m)
    assert (row["attempts"], row["requested"], row["held"], row["events"]) == (3, True, True, ["e1", "e2", "e3"])
    assert _brief(_ref(_node(root, m), "e4")) == (HOLD, HELD, False)


def _h4(root, m=M):
    node = _h1(root, m)
    before = (_lines(root, m), _row(root, m))
    out = _ref(node, "e2")
    assert (out.written, out.request_human, (_lines(root, m), _row(root, m))) == (False, False, before)


def _h4c(root, m=M):
    _crash_e3(root, m)
    lines = _lines(root, m)
    out = _ref(_node(root, m), "e3")
    assert (out.written, out.attempts, out.request_human, _lines(root, m)) == (False, 3, False, lines)


def _h5(root, m=M):
    out = _ref(_h1(root, m), "e4", by=MASTER)
    assert (out.attempts, out.result, out.key) == (4, HOLD, _node(root, m).key_of(*KEY))


def _h6c(root, m=M):
    _h1(root, m)
    with pytest.raises(Boom):
        _node(root, m, stop="after_resolve_journal").resolve(*KEY, "r1", "새 근거")
    node = _node(root, m)
    assert [_brief(_ref(node, e))[:2] for e in ("e5", "e6")] == [(OK, RETRY), (HOLD, HELD)]
    assert len(_row(root, m)["resolutions"]) == 1 and node.resolve(*KEY, "r1", "새 근거").written is False


def _close(d, work):
    assert d.rs.submit("c-" + work, "x" * 8, work).result == OK
    assert d.assign(work, "h-" + work.lower(), evidence=("v1", "v2")).result == OK
    assert d.ex.result(work, "h-" + work.lower(), 1, OK).result == OK
    assert d.deliver(work, "a1").result == OK and d.complete(work, "a1").result == OK


def _h7(root, m=M, crash=False):
    d = m.dispatch.Dispatch(str(root), TEAM, clock=lambda: NOW)
    d.rs.journal.segment_cap = 1024
    _close(d, "W1")
    last = _h1(root, m).rs.records()[-1]["seq"]
    for work in ("W2", "W3", "W4"):
        _close(d, work)
    before = _row(root, m)
    assert d.rs.journal.reclaim()["result"] == "회수 결과"
    assert d.rs.journal.state()["journal_base"]["upto"] >= last       # refuse 줄이 checkpoint 안
    assert _row(root, m) == before
    if not crash:
        return
    assert _node(root, m).resolve(*KEY, "r1", "새 근거").result == OK
    with pytest.raises(Boom):
        _ref(_node(root, m, stop="after_refuse_journal"), "e4")
    row = _row(root, m)
    assert (row["attempts"], row["requested"], row["open_retries"], row["last"]["next"]) == (4, True, 0, RETRY)
    assert d.rs.journal.recover()["result"] == OK and d.rs.journal.state()["refusals"][_node(root, m).key_of(*KEY)] == row


def test_h1_auto_then_retry_then_hold(tmp_path):
    _h1(tmp_path)


def test_h2_human_request_once(tmp_path):
    _h2(tmp_path)


def test_h3_restart_and_cli_process_keep_count(tmp_path):
    _h1(tmp_path)
    rc, out = _cli(tmp_path, "refuse", "e4")
    assert (rc, out["result"], out["attempts"], out["request_human"]) == (1, HOLD, 4, False)
    assert (_row(tmp_path)["attempts"], _row(tmp_path)["requested"]) == (4, True)


def test_h3c_interrupted_third_refusal_replays(tmp_path):
    _h3c(tmp_path)


def test_h4_same_event_writes_nothing(tmp_path):
    _h4(tmp_path)


def test_h4c_resubmit_after_interrupt_writes_nothing(tmp_path):
    _h4c(tmp_path)


def test_h5_successor_by_keeps_key(tmp_path):
    _h5(tmp_path)


def test_h6_resolution_reopens_one_retry(tmp_path):
    node = _h1(tmp_path)
    assert node.resolve(*KEY, "r1", "권한 결정").result == OK
    assert [_brief(_ref(node, e))[:2] for e in ("e5", "e6")] == [(OK, RETRY), (HOLD, HELD)]
    assert node.resolve(*KEY, "r2", "새 판본").result == REFUSED


def test_h6c_interrupted_resolution_replays(tmp_path):
    _h6c(tmp_path)


def test_h7_reclaim_keeps_refusals(tmp_path):
    _h7(tmp_path)


def test_h7c_checkpoint_plus_suffix(tmp_path):
    _h7(tmp_path, crash=True)


def test_h8_new_artifact_is_new_key_and_empty_part_refused(tmp_path):
    node = _h1(tmp_path)
    out = _ref(node, "f1", key=KEY[:4] + ("def456",))
    assert (out.attempts, out.next) == (1, AUTO)
    lines = _lines(tmp_path)
    for bad in (("", *KEY[1:]), KEY[:3] + ("",) + KEY[4:], KEY[:2] + (None,) + KEY[3:]):
        assert (_ref(node, "z", key=bad).result, _lines(tmp_path)) == (REFUSED, lines)


def test_h9_busy_and_corrupt_write_nothing(tmp_path):
    node = _h1(tmp_path)
    lock = node.rs._try_lock()
    try:
        assert (_ref(_node(tmp_path), "e4").result, _lines(tmp_path)) == (BUSY, 3)
    finally:
        node.rs._unlock(lock)
    with open(node.rs.state_path, "w", encoding="utf-8") as handle:
        handle.write("{")
    out = _ref(_node(tmp_path), "e4")
    assert (out.result, out.written, open(node.rs.state_path).read()) == (CORRUPT, False, "{")


def _cli(root, verb, event, *extra):
    argv = ["--root", str(root), "--team", TEAM, "--work", KEY[0], "--place", KEY[1], "--gen", str(KEY[2]),
            "--cause", KEY[3], "--artifact", KEY[4], "--event", event, *extra]
    proc = subprocess.run([sys.executable, os.path.join(CORE, "cli.py"), verb, *argv], capture_output=True,
                          text=True, timeout=30, env=dict(os.environ, FT_NOW=NOW))
    return proc.returncode, json.loads(proc.stdout)


def test_h10_cli_rc(tmp_path):
    assert [_cli(tmp_path, "refuse", e)[0] for e in ("e1", "e2", "e3")] == [0, 0, 1]
    assert _cli(tmp_path, "resolve", "r1", "--why", "새 근거")[0] == 0
    assert _cli(tmp_path, "resolve", "r2", "--why", "모름")[0] == 1
    assert _cli(tmp_path, "resolve", "r3")[0] == 64 and _cli(tmp_path, "refuse", "e9", "--gen", "x")[0] == 64


MUTANTS = (
    ("M1", "record.py", 'if event in row["events"]:', "if False:", (_h4, _h4c)),
    ("M2", "journal.py", ', "refusals")', ")", (_h7, lambda r, m: _h7(r, m, crash=True))),
    ("M3", "record.py", 'request = not row["requested"]', "request = True", (_h2, _h3c)),
    ("M4", "refuse_history.py", "return self.key_of(work, place, gen, cause, artifact)",
     "return self.key_of(work, place, gen, cause, artifact) + '|' + str(by)", (_h5,)),
    ("M5", "record.py", 'elif kind in ("refuse", "resolve") and work:', "elif False:", (_h3c, _h6c, _h7)),
)


@pytest.mark.parametrize("label,name,old,new,cases", MUTANTS, ids=[m[0] for m in MUTANTS])
def test_mutants_break_their_cases(tmp_path, label, name, old, new, cases):
    copy = tmp_path / "core"
    shutil.copytree(CORE, copy)
    text = (copy / name).read_text(encoding="utf-8")
    assert old in text, label
    (copy / name).write_text(text.replace(old, new, 1), encoding="utf-8")
    mutant = _core(str(copy), "ft2_mut_%s_" % label)
    for idx, case in enumerate(cases):
        with pytest.raises((AssertionError, KeyError, TypeError)):
            case(tmp_path / ("run%d" % idx), mutant)
