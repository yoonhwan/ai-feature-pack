"""ft2 complete 의 풀리지 않은 거절 유보 시험 (카드 r2183 · 반례 ②~⑫ · 변이 M1~M5).
풀리지 않음 = 키 `<work>|…` 의 마지막 거절 뒤 해소 0 · 유보 = «완료 유보» · 쓰기 0. 격리 tmp 루트 · 고정 시계 ·
외부 호출 0 · sleep 0 · 실 .fable-team 0. 변이 = core 사본에서만 · 변이마다 원본으로 같은 사례 1회 더(반대 결과)."""
import importlib.util
import json
import os
import shutil
import subprocess
import sys
from types import SimpleNamespace

import pytest

CORE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "core")
TEAM, NOW = "harness", "2026-11-17T12:00:00"
OK, HOLD, REFUSED = "접수 성공", "완료 유보", "접수 거부"
PLACE, CAUSE = "byz-ops-nano-x#0", "선행 미충족"


def _core(path=CORE, alias="ft2_test_r2183_"):
    out = {}
    for name in ("refuse_history", "dispatch", "execution"):
        spec = importlib.util.spec_from_file_location(alias + name, os.path.join(path, name + ".py"))
        out[name] = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(out[name])
    return SimpleNamespace(**out)


M = _core()


def _rh(root, m):
    return m.refuse_history.RefuseHistory(str(root), TEAM, clock=lambda: NOW)


def _d(root, m):
    return m.dispatch.Dispatch(str(root), TEAM, clock=lambda: NOW)


def _key(work="W1", artifact="0"):
    return (work, PLACE, 2, CAUSE, artifact)


def _ks(key):                          # 키 글자 = <work>|<자리>#<세대>|<사유>|<산출물>
    return "%s|%s#%s|%s|%s" % key


def _ref(root, m, event, key=None):
    return _rh(root, m).refuse(*(key or _key()), event)


def _res(root, m, event, why="새 근거", key=None):
    assert _rh(root, m).resolve(*(key or _key()), event, why).result == OK


def _snap(root, m):                     # (journal 줄 수, done 칸들, revision) — 새 인스턴스가 다시 읽은 값
    state, records = _d(root, m).ex._state_records()
    return len(records), sorted(state.get("done") or {}), state["revision"]


def _held(root, m, work="W1", attempt=None):
    before = _snap(root, m)
    grant = _d(root, m).complete(work, attempt)
    assert (grant.result, grant.written, "거절 미해소" in grant.reason) == (HOLD, False, True), grant
    assert _snap(root, m) == before                                   # 쓰기 0
    return grant


def _done(root, m, work="W1", attempt=None):
    grant = _d(root, m).complete(work, attempt)
    assert (grant.result, grant.written) == (OK, True), grant
    assert work in _snap(root, m)[1]


def _c2(root, m=M):                     # ② 거절 1 · 해소 0 → attempt 없는 complete
    _ref(root, m, "e1")
    _held(root, m)


def _c3(root, m=M):                     # ③ 배정된 work · attempt 있는 complete(keeper 착지 꼴)
    d = _d(root, m)
    assert [d.rs.submit("c-W1", "x" * 8, "W1").result, d.assign("W1", "h1", evidence=("v1", "v2")).result,
            d.ex.result("W1", "h1", 1, OK).result, d.deliver("W1", "a1").result] == [OK] * 4
    _ref(root, m, "e1")
    _held(root, m, attempt="a1")


def _c4(root, m=M):                     # ④ 거절 1 → 해소 1 → 완료
    _ref(root, m, "e1")
    _res(root, m, "r1")
    _done(root, m)


def _c5(root, m=M):                     # ⑤ 거절 3(셋째 = 유보) → 해소 1(권한 결정) → 완료
    assert [_ref(root, m, e).result for e in ("e1", "e2", "e3")] == [OK, OK, HOLD]
    _res(root, m, "r1", "권한 결정")
    _done(root, m)


def _c6(root, m=M):                     # ⑥ 거절 → 해소 → 새 거절 → 유보
    _ref(root, m, "e1")
    _res(root, m, "r1")
    _ref(root, m, "e2")
    _held(root, m)


def _c7(root, m=M):                     # ⑦ 산출물만 다른 키 2개 · 1개만 해소 → 유보(안 풀린 키) · 둘 다 → 완료
    ka, kb = _key(artifact="aaa"), _key(artifact="bbb")
    _ref(root, m, "e1", key=ka)
    _ref(root, m, "e2", key=kb)
    _res(root, m, "r1", key=ka)
    assert _ks(kb) in _held(root, m).reason
    _res(root, m, "r2", key=kb)
    _done(root, m)


def _c8(root, m=M):                     # ⑧ work «x-2» 의 거절은 work «x» 를 막지 않는다
    _ref(root, m, "e1", key=_key("x-2"))
    _done(root, m, "x")


def _uncertain(root, m):
    d = _d(root, m)
    assert [d.rs.submit("c-W1", "x" * 8, "W1").result, d.assign("W1", "h1", evidence=("v1", "v2")).result,
            d.deliver("W1", "a1").result] == [OK] * 3
    assert d.ex.mark_uncertain("W1", "h1", 1, "무응답").result == HOLD
    return "결과 미확정 = 완료 유보", HOLD


def _already_done(root, m):
    assert _d(root, m).complete("W1").result == OK
    return "이미 완료 기록", HOLD


def _no_lineage(root, m):
    d = _d(root, m)
    assert (d.rs.submit("c-W1", "x" * 8, "W1").result, d.ex.claim("W1", "h1").result) == (OK, OK)
    return "배정 계보 없는 실행권 owner = 완료 거절(쓰기 0)", REFUSED


def _c10(root, m=M):                    # ⑩ 앞 판정(미확정 · done · 계보 없는 owner)이 먼저 · 글과 결과 기준판과 같음
    for idx, setup in enumerate((_uncertain, _already_done, _no_lineage)):
        sub = root / ("s%d" % idx)
        reason, word = setup(sub, m)
        _ref(sub, m, "e1")
        before = _snap(sub, m)
        grant = _d(sub, m).complete("W1", "a1")
        assert (grant.result, grant.reason, grant.written, _snap(sub, m)) == (word, reason, False, before)


def _cli(root, verb, *argv):
    proc = subprocess.run([sys.executable, os.path.join(CORE, "cli.py"), verb, "--root", str(root), "--team", TEAM,
                           *argv], capture_output=True, text=True, timeout=30, env=dict(os.environ, FT_NOW=NOW))
    return proc.returncode, json.loads(proc.stdout)


def _c11(root, m=M):                    # ⑪ 키 3개 → 이름순 첫 키 + «외 2» + resolve · 해소 사유 둘 · cli rc = 미확정 유보 rc
    for event, artifact in (("e1", "c3"), ("e2", "a1"), ("e3", "b2")):
        _ref(root, m, event, key=_key(artifact=artifact))
    reason = _held(root, m).reason
    first = _ks(_key(artifact="a1"))
    assert all(word in reason for word in (first, "외 2", "resolve", "새 근거", "권한 결정")), reason
    assert _ks(_key(artifact="b2")) not in reason
    if m is M:
        rc, out = _cli(root, "complete", "--work", "W1")
        assert (rc, out["result"], out["written"]) == (1, HOLD, False)
        assert _cli(root / "u", "complete", "--work", "W1")[0] == 0                 # 대조 = 거절 없는 work


def _c9(root, m=M):                     # ⑨ 재시작: ②④⑥ 의 거절·해소를 적은 뒤 별 프로세스(journal 재생)에서 complete
    for name, steps, want in (("r2", (), 1), ("r4", (("res", "r1"),), 0), ("r6", (("res", "r1"), ("ref", "e2")), 1)):
        sub = root / name
        _ref(sub, m, "e1")
        for kind, event in steps:
            _res(sub, m, event) if kind == "res" else _ref(sub, m, event)
        if m is M:
            rc, out = _cli(sub, "complete", "--work", "W1")
            assert (rc, out["result"]) == (want, [OK, HOLD][want])
        else:
            assert _d(sub, m).complete("W1").result == [OK, HOLD][want]


def _checkpoint_old_rows(root, m, resolve):
    """⑫ 옛 판 state — 순서 칸(open) 없는 거절 행이 checkpoint(journal_base.proj)에 든 state 로 시작한다.
    열린 work 의 거절 줄은 회수가 보존해 실제 회수로는 못 만든다 → 옛 판 행 꼴 그대로 state 에 적는다."""
    d = _d(root, m)
    assert d.rs.submit("c-Z", "x" * 8, "Z").result == OK
    state, records = d.ex._state_records()
    row = {"attempts": 1, "auto_done": True, "requested": False, "held": False, "events": ["e1"],
           "resolutions": [{"event": "r1", "why": "새 근거"}] if resolve else [], "open_retries": int(resolve),
           "last": {"event": "e1", "next": "자동 해소", "request_human": False}}
    base = {"upto": records[-1]["seq"], "count": len(records), "receipts": {},
            "proj": {"refusals": {_ks(_key("R1")): row}}}
    d.rs._write_state(dict(state, journal_base=base, revision=state["revision"] + 1))
    seen = d.ex._state_records()[0]["refusals"]
    assert list(seen) == list(base["proj"]["refusals"]) and "open" not in seen[_ks(_key("R1"))]


def _c12(root, m=M):                    # ⑫ 순서 칸 없는 옛 행 = 해소 0 → 유보 · 해소 1+ → 완료
    _checkpoint_old_rows(root / "a", m, False)
    _held(root / "a", m, "R1")
    _checkpoint_old_rows(root / "b", m, True)
    _done(root / "b", m, "R1")


CASES = {"②": _c2, "③": _c3, "④": _c4, "⑤": _c5, "⑥": _c6, "⑦": _c7, "⑧": _c8, "⑨": _c9, "⑩": _c10,
         "⑪": _c11, "⑫": _c12}


@pytest.mark.parametrize("case", CASES.values(), ids=CASES.keys())
def test_cases(tmp_path, case):
    case(tmp_path)


MUTANTS = (
    ("M1", "dispatch.py", "        if held:\n", "        if False:\n", (_c2,)),
    ("M2", "dispatch.py", 'key.split("|", 1)[0] == work', "key.startswith(work)", (_c8,)),
    ("M3", "dispatch.py", 'row.get("open", not row.get("resolutions"))', 'not row.get("resolutions")', (_c6,)),
    ("M4", "dispatch.py", 'row.get("open", not row.get("resolutions"))',
     'len(row["events"]) > len(row["resolutions"])', (_c5,)),
    ("M5", "dispatch.py", "attempt):\n        state, records = context\n        if work in (state.get(\"uncertain\")",
     "attempt):\n        state, records = context\n        held = self._refusal_hold(state, work, attempt)\n"
     "        if held:\n            return held\n        if work in (state.get(\"uncertain\")", (_c10,)),
)


@pytest.mark.parametrize("label,name,old,new,cases", MUTANTS, ids=[m[0] for m in MUTANTS])
def test_mutants_break_their_cases(tmp_path, label, name, old, new, cases):
    copy = tmp_path / "core"
    shutil.copytree(CORE, copy)
    text = (copy / name).read_text(encoding="utf-8")
    assert text.count(old) == 1, label
    (copy / name).write_text(text.replace(old, new, 1), encoding="utf-8")
    mutant = _core(str(copy), "ft2_mut_r2183_%s_" % label)
    for idx, case in enumerate(cases):
        with pytest.raises(AssertionError):
            case(tmp_path / ("mut%d" % idx), mutant)
        case(tmp_path / ("orig%d" % idx), M)                          # 원본 대조 = 같은 사례가 선다
