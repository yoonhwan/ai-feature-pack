"""ft2 코어 — 완료된 일(done) 의 claim = 접수 거부 · 쓰기 0 (r1901 · 실사건 planner r1778 done∧owner 잔존).
① 접수 → 배정 → result → complete → 같은/다른 holder claim = 거부 · runtime 바이트 불변 · owners 에 work 없음.
② 정상 길(접수 → 배정 → result → complete) 그대로 · ③ done 아닌 work 의 rotation claim 그대로.
④ 잔존 모형(complete 뒤 owner 남음) → 같은 holder·gen 으로 result 1회 → done=true · owner 없음(정리 h 의 코어 동사).
변이 M1 = 거절 줄 삭제 → ① 빨강(claim 성공 · owner 남음). 격리 tmp · 고정 시계 · sleep 0."""
import importlib.util
import os
from pathlib import Path

CORE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "core")
TEAM, NOW, H1, H2, EV = "t1", "2026-11-14T00:00:00", "byz-t1-nano-a#1", "byz-t1-nano-b#1", ("v1", "v2")
OK, REFUSED, WHY = "접수 성공", "접수 거부", "완료된 일 = 실행권 0 · 새 일은 새 접수"


def _mod(name):
    spec = importlib.util.spec_from_file_location("ft2_r1901_" + name, os.path.join(CORE, name + ".py"))
    out = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(out)
    return out


DP = _mod("dispatch")


def _done(root):
    """W1 접수 → 배정(gen1) → result → complete(정상 길)."""
    d = DP.Dispatch(str(root), TEAM, clock=lambda: NOW)
    assert [d.rs.submit("c-W1", "x" * 8, "W1").result, d.assign("W1", H1, evidence=EV).result,
            d.ex.result("W1", H1, 1, OK).result, d.complete("W1", "a1").result] == [OK] * 4
    return d


def _snap(d):
    return tuple(Path(p).read_bytes() for p in (d.rs.state_path, d.rs.journal_path))


def _project(d):
    state = d.ex._state_records()[0]
    return "W1" in (state.get("done") or {}), (state.get("owners") or {}).get("W1")


def test_1_claim_on_done_work_is_refused(tmp_path):
    d = _done(tmp_path / "t")
    before = _snap(d)
    for holder in (H1, H2):
        grant = d.ex.claim("W1", holder)
        assert (grant.result, grant.written, grant.gen, grant.reason) == (REFUSED, False, None, WHY)
    assert _snap(d) == before and _project(d) == (True, None)


def test_2_normal_path_unchanged(tmp_path):
    assert _project(_done(tmp_path / "t")) == (True, None)


def test_3_rotation_on_open_work_unchanged(tmp_path):
    d = DP.Dispatch(str(tmp_path / "t"), TEAM, clock=lambda: NOW)
    assert d.rs.submit("c-W2", "x" * 8, "W2").result == OK
    first = d.ex.claim("W2", H1)
    assert d.ex.start("W2", H1, first.gen).result == OK
    assert (d.ex.claim("W2", H2, rotation=True).result, d.ex._state_records()[0]["owners"]["W2"]["gen"]) == (OK, 2)


def _old_code(tmp_path):
    """M1 사본 = 소스에서 거절 줄(«완료된 일» 2줄)을 지운 core 사본의 Execution(옛 코드 claim)."""
    lines = Path(CORE, "execution.py").read_text(encoding="utf-8").splitlines(True)
    cut = next(i for i, line in enumerate(lines) if 'state.get("done")' in line and "if work in" in line)
    mutant = tmp_path / "core"
    mutant.mkdir()
    for name in (n for n in os.listdir(CORE) if n.endswith(".py")):
        (mutant / name).write_bytes(Path(CORE, name).read_bytes())
    (mutant / "execution.py").write_text("".join(lines[:cut] + lines[cut + 2:]), encoding="utf-8")
    spec = importlib.util.spec_from_file_location("ft2_r1901_m1", str(mutant / "execution.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.Execution


def test_4_residue_cleared_by_one_result(tmp_path):
    """④ 옛 코드 claim gen2 → start(실사건 seq171·172) = done∧owner → 같은 holder·gen result 1회 → owner 없음."""
    d = _done(tmp_path / "t")
    old = _old_code(tmp_path)(str(tmp_path / "t"), TEAM, clock=lambda: NOW)
    grant = old.claim("W1", H2)
    assert (grant.result, old.start("W1", H2, grant.gen).result) == (OK, OK)
    done, owner = _project(d)
    assert (done, owner["holder"], owner["gen"]) == (True, H2, 2)        # done∧owner = 실사건 모형
    assert d.ex.result("W1", H2, grant.gen, OK).result == OK
    assert _project(d) == (True, None)


def test_m1_refusal_removed_is_red(tmp_path):
    """M1 거절 줄 삭제 → ① 빨강(claim 성공 · owner 남음)."""
    d = _done(tmp_path / "m1")
    old = _old_code(tmp_path)(str(tmp_path / "m1"), TEAM, clock=lambda: NOW)
    assert (old.claim("W1", H2).result, _project(d)[1] is not None) == (OK, True)
