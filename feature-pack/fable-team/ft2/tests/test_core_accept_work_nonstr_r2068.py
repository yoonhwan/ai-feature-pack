"""ft2 코어 세 자리 · accept work 가 str 이 아니면 «work 없는 접수» 시험 (r2068).
계약 A1~A5 · 반례 ①~⑥ = 카드 순서 · 세 자리 = reopen `_load_list` · lifecycle `_pending_works` · journal `_segment_closed`.
세계 3벌(mode): dict = submit 뒤 journal 의 그 accept 줄 work 칸만 실제 Slack 꼴로 바꿈(r2055 ㉕ c25_journal 방법) ·
none = work 없이 submit · str = 같은 이름 str work. ⑥ = none·str 세계(dict 0)에서 기준판과 같은 값.
격리 tmp · 고정 시계 · 실 runtime 0 · sleep 0. 변이(사본만) M1 재개 → ① · M2 마감 → ③ · M3 회수 → ⑤ 첫 칸 · 원본 대조 1회."""
import importlib.util
import json
import os
import shutil
from pathlib import Path

import pytest

_SPEC = importlib.util.spec_from_file_location("ft2_test_r2068_ro", os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "test_core_team_reopen.py"))
_C = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_C)
CORE, M, LEAD, EV, OK, HOLD, NOW = _C.CORE, _C.M, _C.LEAD, _C.EV, _C.OK, _C.HOLD, _C.NOW
TEAM, RECLAIMED = _C.TEAM, "회수 결과"
CAPS = dict(total_cap=65536, reserve_bytes=4096, segment_cap=1024, state_slack=512, line_max=512)
DICT_WORK = {"d1": {"slack": {"team": "planner"}},     # 실 journal accept 의 work 꼴 2개(Slack 접수)
             "d2": {"route": {"channel": "C0C9GRFHJE5", "id": "post:x", "thread": "1794578093.789539",
                              "to": "byz-planner-desk-pi#154"},
                    "slack": {"attempts": 2, "channel": "C0C9GRFHJE5", "ts": "1794580640.715179"}}}
MODES = ("dict", "none", "str")


def _put(d, mode, command, tag):
    """접수 1줄 — dict·none 세계는 work 없는 접수 · str 세계는 work=tag."""
    assert d.rs.submit(command, "x" * 8, None if mode == "none" else tag).result == OK


def _dictify(d, mode):
    """dict 세계만 — runtime 의 모든 journal 파일에서 work d1·d2 인 accept 줄의 work 칸을 실제 꼴로 바꾼다."""
    if mode != "dict":
        return
    for path in Path(d.rs.runtime).glob("journal*.jsonl"):
        rows = [json.loads(x) for x in path.read_text(encoding="utf-8").splitlines() if x.strip()]
        for rec in rows:
            if rec["kind"] == "accept" and isinstance(rec.get("work"), str) and rec["work"] in DICT_WORK:
                rec["work"] = DICT_WORK[rec["work"]]
        path.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")


def _row(command, work, sent=False):
    return {"command": command, "work": work, "dispatched": sent}


def _qd(mode, n):
    """d1·d2 행 — str 세계면 work = 그 이름 · 아니면 None(seat 단위 = command)."""
    return ("d%d" % n if mode == "str" else None), ("d%d" % n if mode == "str" else "q-d%d" % n)


# ①② 재개 ------------------------------------------------------------------------------------------
def _queue(root, m, mode, works=("W1",)):
    d = _C._dormant(root, m)
    for n in (1, 2):
        _put(d, mode, "q-d%d" % n, "d%d" % n)
    for w in works:
        assert d.rs.submit("q-" + w, "x" * 8, w).result == OK
    _dictify(d, mode)
    return d


def case_1(root, m=M, mode="dict"):     # 큐 = d1·d2 + W1 → 접수 성공 · 3행 · seats = [command 2 · W1]
    _queue(root, m, mode)
    out = _C._go(root, m)
    (w1, s1), (w2, s2) = _qd(mode, 1), _qd(mode, 2)
    assert (out.result, out.open) == (OK, True)
    assert out.load["queue"] == [_row("q-d1", w1), _row("q-d2", w2), _row("q-W1", "W1")]
    assert out.seats_needed == [s1, s2, "W1"]


def case_2(root, m=M, mode="dict"):     # W2 만 dispatch → W2 행만 dispatched · seats 에 W2 없음 / dict 만 큐
    d = _queue(root, m, mode, works=("W1", "W2"))
    assert _C._go(root, m).result == OK
    assert d.assign("W2", LEAD + "-W2", evidence=EV).result == OK
    again = _C._go(root, m)
    (w1, s1), (w2, s2) = _qd(mode, 1), _qd(mode, 2)
    assert again.load["queue"] == [_row("q-d1", w1), _row("q-d2", w2), _row("q-W1", "W1"), _row("q-W2", "W2", True)]
    assert again.seats_needed == [s1, s2, "W1"]
    _queue(root / "only", m, mode, works=())
    only = _C._go(root / "only", m)
    assert (only.result, only.seats_needed) == (OK, [s1, s2])


# ③④ 마감·휴면 ---------------------------------------------------------------------------------------
def _team(root, m, mode):
    os.makedirs(str(root), exist_ok=True)
    d = m.dispatch.Dispatch(str(root), TEAM, clock=lambda: NOW)
    for n in (1, 2):
        _put(d, mode, "c-d%d" % n, "d%d" % n)
    return d


def _done(d, work):
    assert d.rs.submit("c-" + work, "x" * 8, work).result == OK
    assert d.assign(work, "h-" + work, evidence=EV).result == OK
    assert d.ex.result(work, "h-" + work, 1, OK).result == OK
    assert d.deliver(work, "a1").result == OK and d.complete(work, "a1").result == OK


def _close(root, m):
    lc = m.lc.Lifecycle(str(root), TEAM, clock=lambda: NOW)
    before = lc._state_records()
    out = lc.close("g", before[0]["revision"])
    assert len(lc._state_records()[1]) == len(before[1])        # 거절 = 쓰기 0
    return out


def case_3(root, m=M, mode="dict"):     # 남은 일 = d1·d2 → REFUSED · PENDING_NOT_ZERO:2 · dormant 도 같은 줄
    _dictify(_team(root, m, mode), mode)
    out = _close(root, m)
    assert (out.result, out.status, out.blockers, out.written) == (HOLD, "REFUSED", ["PENDING_NOT_ZERO:2"], False)
    board = {"mail": 0, "ownership": 0, "cards": 0, "lands": 0, "hil": 0, "cron": 0, "dirty": [], "arch_da": "APPROVE",
             "team_record": {"revision": 5, "generation": "g", "last_step": "team-lead", "resume": "runtime/"}}
    sleep = m.lc.Lifecycle(str(root), TEAM, clock=lambda: NOW).dormant(board)
    assert (sleep.status, "PENDING_NOT_ZERO:2" in sleep.blockers) == ("NOT_DORMANT", True)


def case_4(root, m=M, mode="dict"):     # d1·d2 + str S(열림) → 3 / S done → 2
    d = _team(root / "open", m, mode)
    assert d.rs.submit("c-S", "x" * 8, "S").result == OK
    _dictify(d, mode)
    assert _close(root / "open", m).blockers == ["PENDING_NOT_ZERO:3"]
    d = _team(root / "done", m, mode)
    _done(d, "S")
    _dictify(d, mode)
    assert _close(root / "done", m).blockers == ["PENDING_NOT_ZERO:2"]


# ⑤ journal 회수 ------------------------------------------------------------------------------------
def _seg(root, m):
    os.makedirs(str(root), exist_ok=True)
    d = m.dispatch.Dispatch(str(root), TEAM, clock=lambda: NOW)
    for key, value in CAPS.items():
        setattr(d.rs.journal, key, value)
    d.rs.capacity = 1000
    return d


def _fill(d, names, segments):
    while len(d.rs.journal.closed()) < segments:
        _done(d, names.pop(0))


def _holder(d):
    """d1 accept 줄이 든 닫힌 segment 의 basename."""
    for _n, path in d.rs.journal.closed():
        if [rec for rec in d.rs.journal._records_of(path) if rec["kind"] == "accept" and rec["command"] == "c-d1"]:
            return os.path.basename(path)
    raise AssertionError("d1 segment 없음")


def case_5a(root, m=M, mode="dict"):    # 첫 segment 에 d1 → 회수 결과 · reclaimed [] · 예외 0
    d, names = _seg(root, m), ["W%d" % n for n in range(1, 40)]
    _put(d, mode, "c-d1", "d1")
    _fill(d, names, 3)
    assert _holder(d) == os.path.basename(d.rs.journal.closed()[0][1])
    _dictify(d, mode)
    out = d.rs.journal.reclaim()
    assert (out["result"], out["reclaimed"]) == (RECLAIMED, [])


def case_5b(root, m=M, mode="dict"):    # 첫 segment = 닫힌 str work 만 · 뒤 segment 에 d1 → 그 앞 segment 만 회수
    d, names = _seg(root, m), ["W%d" % n for n in range(1, 60)]
    _fill(d, names, 1)
    _put(d, mode, "c-d1", "d1")
    _fill(d, names, 4)
    hold = _holder(d)
    before = [os.path.basename(p) for _n, p in d.rs.journal.closed()]
    _dictify(d, mode)
    out = d.rs.journal.reclaim()
    assert before.index(hold) >= 1
    assert (out["result"], out["reclaimed"]) == (RECLAIMED, before[:before.index(hold)])


CASES = {"1": case_1, "2": case_2, "3": case_3, "4": case_4, "5a": case_5a, "5b": case_5b}


@pytest.mark.parametrize("mode", MODES)
@pytest.mark.parametrize("name", CASES)
def test_cases(tmp_path, name, mode):   # mode=dict = ①~⑤ · none·str = ⑥ 불변(기준판도 통과)
    CASES[name](tmp_path, M, mode)


MUTANTS = (
    ("M1", "reopen.py", "works = {cmd: work for cmd, work in works.items() if isinstance(work, str)}", "pass", case_1),
    ("M2", "lifecycle.py", "by_command.items() if isinstance(work, str)}", "by_command.items()}", case_3),
    ("M3", "journal.py", 'rec.get("work") if isinstance(rec.get("work"), str) else None for rec in seg',
     'rec.get("work") for rec in seg', case_5a),
)


@pytest.mark.parametrize("label,name,old,new,case", MUTANTS, ids=[m[0] for m in MUTANTS])
def test_mutants_break_their_case(tmp_path, label, name, old, new, case):
    copy = Path(shutil.copytree(CORE, tmp_path / "core"))
    text = (copy / name).read_text(encoding="utf-8")
    assert text.count(old) == 1, label
    (copy / name).write_text(text.replace(old, new, 1), encoding="utf-8")
    with pytest.raises((AssertionError, TypeError)):
        case(tmp_path / "mut", _C._core(str(copy), "ft2_mut_r2068_%s_" % label), "dict")
    case(tmp_path / "orig", _C._core(CORE, "ft2_orig_r2068_%s_" % label), "dict")   # 원본 대조 = 같은 사례 통과
