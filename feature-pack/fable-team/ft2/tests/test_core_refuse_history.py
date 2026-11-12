"""ft2 회수 거절 처리 이력 키 시험 (카드 r1724 · 계획 PLAN-ft20-reclaim-refuse-history-key-20261112 · R1 보정).
사례 = 계획 2절 H1~H10 + 중단 결속 H3c·H4c·H6c·H7c(id = 사례 번호) · 중단 = on_step 예외(kill·sleep 0) · 격리 tmp 루트 ·
FT_NOW 고정 시계 · 파일 1개 70초 안 · 실 .fable-team 0 · 재진입 표지 = 없음.
변이(core 사본에서만 · 하나씩): M1 사건 멱등 → H4·H4c · M2 PROJ_FIELDS refusals → H7·H7c ·
M3 requested 검사 → H2·H3c · M4 by 를 키에 → H5 · M5 recover_state 분기 → H3c·H6c·H7c."""
import functools
import importlib.util
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
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


def _node(root, m=M, stop=None):
    def step(name):
        if name == stop:
            raise Boom(name)
    return m.rh.RefuseHistory(str(root), TEAM, clock=lambda: NOW, on_step=step)


def _ref(node, event, by=None, key=KEY):
    return node.refuse(*key, event, by=by)


def _seen(root, m=M, key=KEY):                     # (journal 줄 수, 키 행) — 새 인스턴스가 recover_state 로 읽은 값
    node = _node(root, m)
    records = node.rs.records()
    return len(records), node.rs.journal.rec.recover_state(node.rs._state(), records)["refusals"].get(node.key_of(*key))


def _brief(out):
    return out.result, out.next, out.request_human


def _h1(root, m=M):
    node = _node(root, m)
    assert [_brief(_ref(node, e)) for e in ("e1", "e2", "e3")] \
        == [(OK, AUTO, False), (OK, RETRY, False), (HOLD, HELD, True)]
    return node


def _h2(root, m=M):                                # H2 요청 1회 + H5 후계 교체(by 만 다름 = 같은 키 · 초기화 0)
    out = _ref(_h1(root, m), "e4", by=MASTER)
    assert (_brief(out), out.attempts, out.key) == ((HOLD, HELD, False), 4, _node(root, m).key_of(*KEY))


def _crash_e3(root, m=M):
    node = _node(root, m)
    _ref(node, "e1"), _ref(node, "e2")
    with pytest.raises(Boom):
        _ref(_node(root, m, stop="after_refuse_journal"), "e3")


def _h3c(root, m=M):
    _crash_e3(root, m)
    row = _seen(root, m)[1]
    assert (row["attempts"], row["requested"], row["held"], row["events"]) == (3, True, True, ["e1", "e2", "e3"])
    assert _brief(_ref(_node(root, m), "e4")) == (HOLD, HELD, False)


def _h4(root, m=M, crash=False):                   # H4 = e2 재접수 · H4c = 중단된 e3 재접수
    (_crash_e3 if crash else _h1)(root, m)
    before = _seen(root, m)
    out = _ref(_node(root, m), "e3" if crash else "e2")
    assert (out.written, out.attempts, out.request_human, _seen(root, m)) == (False, 3, False, before)


def _h6(root, m=M, crash=False):
    node = _h1(root, m)
    if crash:                                      # H6c: 해소 줄 내구화 뒤 state 전 중단 → 새 인스턴스
        with pytest.raises(Boom):
            _node(root, m, stop="after_resolve_journal").resolve(*KEY, "r1", "새 근거")
        node = _node(root, m)
    assert crash or node.resolve(*KEY, "r1", "권한 결정").result == OK
    assert [_brief(_ref(node, e))[:2] for e in ("e5", "e6")] == [(OK, RETRY), (HOLD, HELD)]
    assert len(_seen(root, m)[1]["resolutions"]) == 1 and node.resolve(*KEY, "r1", "새 근거").written is False
    assert node.resolve(*KEY, "r2", "새 판본").result == REFUSED


def _close(d, work, holder="h1"):
    assert [d.rs.submit("c-" + work, "x" * 8, work).result, d.assign(work, holder, evidence=("v1", "v2")).result,
            d.ex.result(work, holder, 1, OK).result, d.deliver(work, "a1").result,
            d.complete(work, "a1").result] == [OK] * 5


def _h7(root, m=M, crash=False):
    d = m.dispatch.Dispatch(str(root), TEAM, clock=lambda: NOW)
    d.rs.journal.segment_cap = 1024
    _close(d, "W1")
    last = _h1(root, m).rs.records()[-1]["seq"]
    for work in ("W2", "W3", "W4"):
        _close(d, work)
    before = _seen(root, m)[1]
    assert d.rs.journal.reclaim()["result"] == "회수 결과"
    assert d.rs.journal.state()["journal_base"]["upto"] >= last       # refuse 줄이 checkpoint 안
    assert _seen(root, m)[1] == before
    if not crash:
        return
    assert _node(root, m).resolve(*KEY, "r1", "새 근거").result == OK
    with pytest.raises(Boom):
        _ref(_node(root, m, stop="after_refuse_journal"), "e4")
    row = _seen(root, m)[1]
    assert (row["attempts"], row["requested"], row["open_retries"], row["last"]["next"]) == (4, True, 0, RETRY)
    assert d.rs.journal.recover()["result"] == OK and d.rs.journal.state()["refusals"][_node(root, m).key_of(*KEY)] == row


_h4c, _h6c, _h7c = (functools.partial(case, crash=True) for case in (_h4, _h6, _h7))
SCENARIOS = {"H1": _h1, "H2·H5": _h2, "H3c": _h3c, "H4": _h4, "H4c": _h4c, "H6": _h6, "H6c": _h6c,
             "H7": _h7, "H7c": _h7c}


@pytest.mark.parametrize("case", SCENARIOS.values(), ids=SCENARIOS.keys())
def test_scenarios(tmp_path, case):
    case(tmp_path)


def test_h8_new_artifact_is_new_key_and_empty_part_refused(tmp_path):
    node = _h1(tmp_path)
    out = _ref(node, "f1", key=KEY[:4] + ("def456",))
    assert (out.attempts, out.next) == (1, AUTO)
    lines = _seen(tmp_path)[0]
    for bad in (("", *KEY[1:]), KEY[:3] + ("",) + KEY[4:], KEY[:2] + (None,) + KEY[3:]):
        assert (_ref(node, "z", key=bad).result, _seen(tmp_path)[0]) == (REFUSED, lines)


def test_h9_busy_and_corrupt_write_nothing(tmp_path):
    node = _h1(tmp_path)
    lock = node.rs._try_lock()
    assert (_ref(_node(tmp_path), "e4").result, _seen(tmp_path)[0]) == (BUSY, 3)
    node.rs._unlock(lock)
    state = Path(node.rs.state_path)
    state.write_text("{", encoding="utf-8")
    out = _ref(_node(tmp_path), "e4")
    assert (out.result, out.written, state.read_text(encoding="utf-8")) == (CORRUPT, False, "{")


def _cli(root, verb, event, *extra):
    argv = ["--root", str(root), "--team", TEAM, "--work", KEY[0], "--place", KEY[1], "--gen", str(KEY[2]),
            "--cause", KEY[3], "--artifact", KEY[4], "--event", event, *extra]
    proc = subprocess.run([sys.executable, os.path.join(CORE, "cli.py"), verb, *argv], capture_output=True,
                          text=True, timeout=30, env=dict(os.environ, FT_NOW=NOW))
    return proc.returncode, json.loads(proc.stdout)


def test_h3_h10_restart_cli_process_and_rc(tmp_path):
    _h1(tmp_path / "h3")                              # H3: 새 인스턴스 + CLI 별 프로세스 = 이어서 셈
    rc, out = _cli(tmp_path / "h3", "refuse", "e4")
    assert (rc, out["result"], out["attempts"], out["request_human"]) == (1, HOLD, 4, False)
    assert (_seen(tmp_path / "h3")[1]["attempts"], _seen(tmp_path / "h3")[1]["requested"]) == (4, True)
    assert [_cli(tmp_path, "refuse", e)[0] for e in ("e1", "e2", "e3")] == [0, 0, 1]
    assert _cli(tmp_path, "resolve", "r1", "--why", "새 근거")[0] == 0
    assert _cli(tmp_path, "resolve", "r2", "--why", "모름")[0] == 1
    assert _cli(tmp_path, "resolve", "r3")[0] == 64 and _cli(tmp_path, "refuse", "e9", "--gen", "x")[0] == 64


MUTANTS = (
    ("M1", "record.py", 'if event in row["events"]:', "if False:", (_h4, _h4c)),
    ("M2", "journal.py", ', "refusals")', ")", (_h7, _h7c)),
    ("M3", "record.py", 'not row["requested"]', "True", (_h2, _h3c)),          # H2
    ("M4", "refuse_history.py", "return self.key_of(work, place, gen, cause, artifact)",
     "return self.key_of(work, place, gen, cause, artifact) + '|' + str(by)", (_h2,)),   # H5
    ("M5", "record.py", 'elif kind in ("refuse", "resolve") and work:', "elif False:", (_h3c, _h6c, _h7c)),
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
