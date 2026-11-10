"""ft2 코어 실행권·세대 시험 (r1579 · PR② 둘째 장).

계약 사례 = `ft2/contracts/core/CASES.md`. 이 장이 닿는 5건의 «given 1줄 = 호출 1개» 대응표:

| 사례 | given 1줄 | 호출 1개 |
|---|---|---|
| case_04_stale_owner | gen1 착수 뒤 세대 교체(gen2) | `claim("card-a","h2",rotation=True)` |
| case_05_inflight | owner 무응답 · A 카드 보존 | `mark_uncertain(...)` → `claim(...)` |
| case_07_effect_crash | 효과 전 / 효과 후 결과 확정 전 crash | 자식 `claim→start→(effect)→_exit(9)` |
| case_02_concurrent_4x300 | 다른 카드 4개 동시 갱신 | 자식 4 × `claim·start·effect·result` |
| case_09_slow_team | A 잠금 점유 중 claim | 잠금 점유 자식 + `claim("card-a",...)` |

시험 상한(70초·동시 4) 축소값: case_02 는 적용 300/카드가 아니라 ROUNDS=3 라운드/카드 · 자식 4개다.
BUSY 상한식 `BUSY ≤ tick×(자식−1)` 은 축소값 그대로 대조한다. 변이 M1~M9 는 «검사기가 잡는가» 만 본다.
격리 tmp 팀 데이터 루트만 쓰고 실 runtime·실 우편함은 0.
"""
import fcntl
import importlib.util
import inspect
import json
import os
import subprocess
import sys
import time
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
FT2 = os.path.dirname(HERE)
CORE, GUARD = os.path.join(FT2, "core"), os.path.join(FT2, "tools", "legacy_guard.py")
TEAM, CHILDREN, ROUNDS, TICK = "harness", 4, 3, 0.05
OK, HOLD, STALE, BUSY = "접수 성공", "완료 유보", "낡은 실행권", "BUSY"
PUBLIC = {"submit", "lookup", "records", "body_path"}
RECEIPT_FIELDS = ("result", "command", "attempt", "revision", "written", "body_ref", "reason")
CHILD_ENV = dict(os.environ, FT2_EXEC_CHILD="1")

def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_core_" + name, os.path.join(CORE, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

record, intake, execution = _load("record"), _load("intake"), _load("execution")

def _ex(root, team=TEAM, cls=None, client=None, on_step=None):
    """시험용 결선 — 잠금·state 계열 변이는 client(Intake), 검사·판정 변이는 cls(Execution)."""
    render = cls or execution.Execution
    if client is None:
        return render(str(root), team, on_step=on_step)

    class _Wired(render):
        CLIENT = client
    return _Wired(str(root), team, on_step=on_step)

def _intake(root, capacity=8, cls=None):
    return (cls or intake.Intake)(str(root), TEAM, capacity=capacity)

def _state(node):
    return json.loads(Path(node.rs.state_path).read_text(encoding="utf-8"))

def _snap(node):
    """state·journal·bodies 스냅샷 — «쓰기 0» 을 바이트로 대조한다(ⓐⓑⓗ)."""
    paths = (node.rs.state_path, node.rs.journal_path)
    return tuple(Path(p).read_bytes() if os.path.exists(p) else b"" for p in paths) \
        + tuple(sorted(os.listdir(node.rs.bodies)))

def _effects(root, tag=None):
    """효과 대역 재계수 — 자식이 남긴 effects.txt 로 «재실행 0» 을 센다."""
    path = os.path.join(str(root), "effects.txt")
    if tag is None:
        return Path(path).read_text(encoding="utf-8").split() if os.path.exists(path) else []
    with open(path, "a", encoding="utf-8") as handle:
        handle.write(tag + "\n")

def _retry(call, tries=400):
    """BUSY = 같은 writer 의 «다음 tick» 사건 — 잠금이 풀릴 때까지 다시 부른다."""
    out = call()
    for _ in range(tries):
        if out.result != BUSY:
            return out
        time.sleep(0.002)
        out = call()
    return out

def _wait(path, seconds=10.0):
    deadline = time.monotonic() + seconds
    while not os.path.exists(str(path)) and time.monotonic() < deadline:
        time.sleep(0.002)
    assert os.path.exists(str(path)), "기다리다 지남: " + str(path)

def _spawn(*args):
    return subprocess.Popen([sys.executable, os.path.abspath(__file__)] + [str(a) for a in args], env=CHILD_ENV)

def _child(*args):
    return subprocess.run([sys.executable, os.path.abspath(__file__)] + [str(a) for a in args],
                          env=CHILD_ENV, capture_output=True, timeout=25)

def _steps(node, work, holder, gen, index=0):
    return [lambda: node.start(work, holder, gen), lambda: node.effect(work, holder, gen, "e%d" % index),
            lambda: node.result(work, holder, gen)]

def test_a_stale_generation_write_is_refused(tmp_path):
    node, entry = _ex(tmp_path / "t"), _intake(tmp_path / "t")
    g1 = node.claim("card-a", "h1")
    assert node.start("card-a", "h1", g1.gen).result == OK
    g2 = node.claim("card-a", "h2", rotation=True)             # 구 실행자 종료·권한 회수 확인
    stale, before = [node.start("card-a", "h1", g1.gen), node.effect("card-a", "h1", g1.gen, "e1"),
                     node.result("card-a", "h1", g1.gen)], _snap(node)
    assert [(g.result, g.written) for g in stale] == [(STALE, False)] * 3 and _snap(node) == before
    assert (g1.gen, g2.result, g2.gen) == (1, OK, 2)
    assert (entry.submit("card-a", "본문").result, _state(node)["generations"]) == (OK, {"card-a": 2})

def test_b_no_response_is_uncertain_and_not_regranted(tmp_path):
    node = _ex(tmp_path / "t")
    grant = node.claim("card-a", "h1")
    node.start("card-a", "h1", grant.gen)
    held = node.mark_uncertain("card-a", "h1", grant.gen, "무응답", confirm_by="2026-11-10T10:10:00")
    before, revision = _snap(node), _state(node)["revision"]
    again = node.claim("card-a", "h2")
    assert (held.result, held.written, held.confirm_by) == (HOLD, True, "2026-11-10T10:10:00")
    assert (again.result, again.written, again.revision) == (HOLD, False, revision)
    assert (node.claim("card-a", "h3", rotation=True).result, _snap(node)) == (HOLD, before)
    assert node.claim("card-b", "h2").result == OK                             # 후계의 다른 효과
    assert _ex(tmp_path / "t", "other").claim("card-a", "h3").result == OK     # 다른 팀

def test_c_effect_crash_is_uncertain_without_rerun(tmp_path):
    for step, ran in (("pre_effect", 0), ("post_effect", 1)):
        root = tmp_path / step
        assert _child("crash", root, step).returncode == 9
        node = _ex(root)
        first = node.claim("card-a", "h2")
        assert (first.result, first.written, bool(first.confirm_by)) == (HOLD, True, True)
        assert (node.claim("card-a", "h3").result, node.effect("card-a", "h3", first.gen, "e1").result) \
            == (HOLD, HOLD)
        assert _effects(root).count("e1") == ran

def test_d_four_cards_busy_bound_and_strict_revision(tmp_path):
    root = str(tmp_path / "t")
    node = _ex(root)
    procs = [_spawn("concurrent", root, index, ROUNDS) for index in range(CHILDREN)]
    [_wait(os.path.join(root, "ready-%d" % index)) for index in range(CHILDREN)]
    lock = node.rs._try_lock()                  # 1회차 = 부모가 잠금 점유 → 결정적 BUSY
    open(os.path.join(root, "go"), "w", encoding="utf-8").close()
    time.sleep(0.02)
    node.rs._unlock(lock)
    assert [proc.wait(timeout=25) for proc in procs] == [0] * CHILDREN
    outs = [json.loads(Path(root, "out-%d.json" % index).read_text()) for index in range(CHILDREN)]
    state, records = _state(node), node.rs.records()
    assert all(1 <= out["busy"] <= ROUNDS * (CHILDREN - 1) for out in outs)
    assert (state["revision"], state["uncertain"]) == (len(records), {})
    for index, out in enumerate(outs):
        kinds = [rec["kind"] for rec in records if rec.get("work") == "card-%d" % index]
        assert kinds == ["claim", "start", "effect", "result"] * (ROUNDS - out["busy"])

def test_e_lock_is_per_team_while_claim_is_busy(tmp_path):
    root = str(tmp_path / "t")
    holder = _spawn("hold", root, "team-a", 0.4)
    _wait(os.path.join(root, "held"))
    node_a, node_b = _ex(root, "team-a"), _ex(root, "team-b")
    started, busy = time.monotonic(), None
    busy = node_a.claim("card-a", "h1")
    assert (busy.result, busy.written) == (BUSY, False) and time.monotonic() - started < 5
    grant = node_b.claim("card-a", "h1")        # 팀-b 는 자기 잠금이라 그대로 진행
    assert grant.result == OK and [c().result for c in _steps(node_b, "card-a", "h1", grant.gen)] == [OK] * 3
    assert holder.wait(timeout=25) == 0 and node_a.claim("card-a", "h1").result == OK
    assert os.path.exists(node_a.rs.lock_path) and os.path.exists(node_b.rs.lock_path)
    assert not os.path.exists(os.path.join(root, ".fable-team", "writer.lock"))

def test_f_result_words_stay_inside_contract(tmp_path):
    node = _ex(tmp_path / "t")
    grant = node.claim("card-w", "h1")
    words = {grant.result, node.claim("card-w", "h1").result,
             node.result("card-w", "h1", grant.gen, word="완료").result}
    words |= {c().result for c in _steps(node, "card-w", "h1", grant.gen)}
    assert all(record.is_contract_result(word) for word in words)
    assert (record.SCHEMA_VERSION, {"accept", "claim", "start", "effect", "result", "uncertain"}
            <= set(record.KINDS)) == (1, True)
    assert {rec["kind"] for rec in node.rs.records()} <= set(record.KINDS)

def _face_violations(cls=intake.Intake):
    """공개 면(ⓖ) 검사 — submit·lookup 시그니처 · Receipt 7칸 · 새 public 우회로 0."""
    found = []
    if tuple(inspect.signature(cls.submit).parameters) != ("self", "command", "body", "work"):
        found.append("submit 시그니처")
    if tuple(inspect.signature(cls.lookup).parameters) != ("self", "command"):
        found.append("lookup 시그니처")
    if intake.Receipt._fields != RECEIPT_FIELDS:
        found.append("Receipt 7칸")
    extra = [name for name in vars(cls) if not name.startswith("_") and name not in PUBLIC]
    return found + (["새 public: " + ",".join(sorted(extra))] if extra else [])

def test_g_intake_public_face_and_guard():
    assert _face_violations() == []
    done = subprocess.run([sys.executable, "-I", GUARD], capture_output=True, timeout=25)
    assert done.returncode == 0, done.stdout.decode("utf-8", "replace")

def test_h_submit_is_busy_while_writer_lock_held(tmp_path):
    node = _ex(tmp_path / "t")
    lock, before = node.rs._try_lock(), _snap(node)
    try:
        receipt = _intake(tmp_path / "t").submit("card-1", "본문-1")
    finally:
        node.rs._unlock(lock)
    assert (receipt.result, receipt.written) == (BUSY, False)
    assert _snap(node) == before and not os.path.exists(node.rs.body_path("card-1"))

def test_i_submit_merges_state_instead_of_replacing(tmp_path):
    node = _ex(tmp_path / "t")
    node.claim("card-a", "h1")
    revision = _state(node)["revision"]
    assert _intake(tmp_path / "t").submit("card-1", "본문-1").written
    state = _state(node)
    assert (state["generations"], "card-a" in state["owners"]) == ({"card-a": 1}, True)
    assert (state["pending"], state["revision"], len(node.rs.records())) == (["card-1"], revision + 1, revision + 1)

def test_j_intake_reads_only_accept_kind(tmp_path):
    root = tmp_path / "t"
    _ex(root).claim("work-x", "h1")
    entry = _intake(root, capacity=1)
    assert entry.lookup("work-x") is None                  # 실행권 줄은 영수가 아니다
    assert entry.submit("work-x", "본문").result == OK       # 용량도 실행권 줄을 세지 않는다
    assert _state(_ex(root))["pending"] == ["work-x"]

def test_k_submit_and_execution_interleave(tmp_path):
    root = str(tmp_path / "t")
    node, entry = _ex(root), _intake(root)
    grant = node.claim("card-a", "h1")
    node.start("card-a", "h1", grant.gen)
    node.mark_uncertain("card-a", "h1", grant.gen, "무응답", confirm_by="2026-11-10T10:10:00")
    holder = _spawn("hold", root, TEAM, 0.3)
    _wait(os.path.join(root, "held"))
    assert (entry.submit("cmd-1", "본문").result, node.claim("work-z", "h9").result) == (BUSY, BUSY)
    assert holder.wait(timeout=25) == 0 and _child("interleave", root).returncode == 0
    assert entry.submit("cmd-1", "본문").result == OK        # 잠금이 풀리면 같은 접수가 성공한다
    state, records = _state(node), node.rs.records()
    assert state["uncertain"]["card-a"]["confirm_by"] == "2026-11-10T10:10:00"
    assert (state["generations"], state["pending"]) == ({"card-a": 1, "work-z0": 1, "work-z1": 1},
                                                        ["cmd-2", "cmd-1"])
    assert [entry.lookup("cmd-%d" % index).result for index in (1, 2)] == [OK, OK]
    assert state["revision"] == len(records)

def test_l_receive_and_claim_share_one_runtime(tmp_path):
    root = str(tmp_path / "t")
    node = _ex(root)                              # runtime 폴더를 먼저 만든다(자식이 같은 곳을 쓴다)
    procs = [_spawn("receive", root, 2), _spawn("claim", root, 2)]
    [_wait(os.path.join(root, "ready-" + mode)) for mode in ("receive", "claim")]
    open(os.path.join(root, "go"), "w", encoding="utf-8").close()
    assert [proc.wait(timeout=25) for proc in procs] == [0, 0]
    state = _state(node)
    assert (state["revision"], sorted(state["pending"]), state["uncertain"]) == (
        len(node.rs.records()), ["cmd-0", "cmd-1"], {})
    assert state["generations"] == {"work-0": 1, "work-1": 1}
    assert [_intake(root).lookup("cmd-%d" % index).result for index in (0, 1)] == [OK, OK]

def test_r1_same_generation_effect_is_not_rerun(tmp_path):
    """DA R1: 같은 gen 으로 다시 들어온 효과는 결과 미확정 보존 · 효과 누계 1회."""
    root = tmp_path / "t"
    assert _child("crash", root, "post_effect").returncode == 9
    again = _ex(root).effect("card-a", "h1", 1, "e1", run=lambda: _effects(root, "e1"))
    assert (again.result, again.stage) == (HOLD, "uncertain")
    assert _effects(root).count("e1") == 1
    assert _ex(root).effect("card-a", "h1", 1, "e1", run=lambda: _effects(root, "e1")).written is False
    assert _effects(root).count("e1") == 1


def test_r2_journal_generation_survives_checkpoint_crash(tmp_path):
    """DA R2: claim 의 journal 내구화 뒤 checkpoint 전 crash → 옛 gen 쓰기 거절(0)."""
    root = tmp_path / "t"
    node = _ex(root)
    g1 = node.claim("card-a", "h1")
    node.start("card-a", "h1", g1.gen)
    assert _child("rotate", root, "after_journal").returncode == 9
    node = _ex(root)
    stale = node.result("card-a", "h1", g1.gen)
    assert (stale.result, stale.written) == (STALE, False)      # journal 의 gen2 가 유효본
    assert node.result("card-a", "h2", 2).result == OK
    assert (len(node.rs.records()), _state(node)["revision"]) == (4, 4)


def test_r2_intake_writer_keeps_recovered_revision(tmp_path):
    """DA R2 잔여: 같은 crash 뒤 «실제 Intake.submit» 도 journal 내구 revision·세대를 이어받는다."""
    root = tmp_path / "t"
    node = _ex(root)
    g1 = node.claim("card-a", "h1")
    node.start("card-a", "h1", g1.gen)
    assert _child("rotate", root, "after_journal").returncode == 9
    receipt = _intake(root).submit("c-1", "본문-1")
    state, records = _state(node), node.rs.records()
    assert (receipt.result, receipt.written) == (OK, True)
    assert (len(records), state["revision"]) == (4, 4)          # 내구 3줄 + submit 1줄
    assert (state["generations"], state["owners"]["card-a"]["gen"]) == ({"card-a": 2}, 2)
    assert node.result("card-a", "h1", g1.gen).result == STALE  # 이후에도 옛 gen 은 거절


class _NoGenCheck(execution.Execution):           # M1: 세대 검사 빼기
    _gen_matches = lambda self, state, work, gen: True  # noqa: E731

class _GrantOnUncertain(execution.Execution):     # M2: 무응답을 재부여로
    _hold = lambda self, *args, **kwargs: None  # noqa: E731

class _RerunAfterCrash(execution.Execution):      # M3: crash 뒤 효과 재실행
    def _hold(self, state, records, work, gen, rotation=False, closing=False):
        return self._field(state, "uncertain").get(work)

class _BlockingLock(intake.Intake):               # M4: 경합을 «기다림» 으로
    def _try_lock(self):
        handle = open(self._lock_file_path(), "a+", encoding="utf-8")
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        return handle

class _GlobalLock(intake.Intake):                 # M5: 팀 전역 잠금 1개
    def _lock_file_path(self):
        return os.path.join(os.path.dirname(os.path.dirname(self.runtime)), "writer.lock")

class _WideSubmit(intake.Intake):                 # M6: submit 시그니처 변경
    def submit(self, command, body, work=None, gen=None):
        return super().submit(command, body, work)

class _NoLock(intake.Intake):                     # M7: submit 의 잠금 빼기
    class _Null:
        def fileno(self):
            return -1
    _try_lock = lambda self: _NoLock._Null()  # noqa: E731
    _unlock = lambda self, handle: None  # noqa: E731

class _ReplaceState(intake.Intake):               # M8: state 를 새 dict 로 교체
    def _next_state(self, state, command, pending):
        return {"schema": record.SCHEMA_VERSION, "revision": state["revision"] + 1,
                "pending": pending + [command],
                "attempts": dict(state["attempts"], **{command: state["attempts"].get(command, 0) + 1})}

class _NoKindFilter(intake.Intake):               # M9: 입구 판독이 kind 를 안 가림
    _prior_receipt = lambda self, records, command: next(  # noqa: E731
        (rec for rec in reversed(records) if rec["command"] == command), None)
    _pending = lambda self, records, state: list(  # noqa: E731
        dict.fromkeys([rec["command"] for rec in records] + list(state["pending"])))

def test_m1_without_generation_check_old_owner_writes(tmp_path):
    node = _ex(tmp_path / "t", cls=_NoGenCheck)
    g1 = node.claim("card-a", "h1")
    node.claim("card-a", "h2", rotation=True)
    assert node.result("card-a", "h1", g1.gen).result == OK

def test_m2_uncertain_is_regranted(tmp_path):
    node = _ex(tmp_path / "t", cls=_GrantOnUncertain)
    grant = node.claim("card-a", "h1")
    node.start("card-a", "h1", grant.gen)
    node.mark_uncertain("card-a", "h1", grant.gen, "무응답", confirm_by="2026-11-10T10:10:00")
    assert node.claim("card-a", "h2").result == OK

def test_m3_crash_effect_runs_again(tmp_path):
    root = tmp_path / "t"
    assert _child("crash", root, "post_effect").returncode == 9
    node = _ex(root, cls=_RerunAfterCrash)
    grant = node.claim("card-a", "h2")
    node.effect("card-a", "h2", grant.gen, "e1", run=lambda: _effects(root, "e1"))
    assert _effects(root).count("e1") == 2

def test_m4_blocking_lock_loses_busy(tmp_path):
    root = str(tmp_path / "t")
    holder = _spawn("hold", root, TEAM, 0.3)
    _wait(os.path.join(root, "held"))
    grant = _ex(root, client=_BlockingLock).claim("card-a", "h1")
    assert holder.wait(timeout=25) == 0 and grant.result == OK

def test_m5_global_lock_blocks_other_team(tmp_path):
    root = str(tmp_path / "t")
    _ex(root)
    holder = _spawn("hold", root, "team-a", 0.3, "global")
    _wait(os.path.join(root, "held"))
    grant = _ex(root, "team-b", client=_GlobalLock).claim("card-a", "h1")
    assert holder.wait(timeout=25) == 0 and grant.result == BUSY

def test_m6_changed_submit_signature():
    assert _face_violations(_WideSubmit) != []

def test_m7_submit_without_lock_writes_during_hold(tmp_path):
    node = _ex(tmp_path / "t")
    lock = node.rs._try_lock()
    try:
        receipt = _intake(tmp_path / "t", cls=_NoLock).submit("card-1", "본문-1")
    finally:
        node.rs._unlock(lock)
    assert (receipt.result, receipt.written) == (OK, True)

def test_m8_state_replacement_drops_generation(tmp_path):
    root = tmp_path / "t"
    node = _ex(root)
    node.claim("card-a", "h1")
    _intake(root, cls=_ReplaceState).submit("card-1", "본문-1")
    assert "card-a" not in _state(node).get("generations", {})

def test_m9_execution_lines_count_as_accept(tmp_path):
    root = tmp_path / "t"
    _ex(root).claim("work-x", "h1")
    assert _intake(root, capacity=1, cls=_NoKindFilter).submit("work-x", "본문").result != OK

def _child_main(argv):
    mode, root, rest = argv[0], argv[1], argv[2:]
    if mode == "crash":
        node = _ex(root)
        grant = node.claim("card-a", "h1")
        node.start("card-a", "h1", grant.gen)
        if rest[0] == "pre_effect":
            os._exit(9)
        node.effect("card-a", "h1", grant.gen, "e1", run=lambda: _effects(root, "e1"))
        if rest[0] == "post_effect":
            os._exit(9)
        return int(node.result("card-a", "h1", grant.gen).result != OK)
    if mode == "rotate":
        node = _ex(root, on_step=lambda point: os._exit(9) if point == rest[0] else None)
        node.claim("card-a", "h2", rotation=True)
        return 0
    if mode == "hold":
        node = _ex(root, rest[0], client=_GlobalLock if rest[2:] == ["global"] else None)
        handle = node.rs._try_lock()
        open(os.path.join(root, "held"), "w", encoding="utf-8").close()
        time.sleep(float(rest[1]))
        node.rs._unlock(handle)
        return 0
    if mode == "interleave":
        entry, node = _intake(root), _ex(root)
        _retry(lambda: entry.submit("cmd-2", "본문-2"))
        grant = _retry(lambda: node.claim("work-z0", "h9"))
        [_retry(call) for call in _steps(node, "work-z0", "h9", grant.gen)]
        _retry(lambda: node.claim("work-z1", "h9"))
        return 0
    index = int(rest[0])
    name = "ready-%d" % index if mode == "concurrent" else "ready-" + mode
    open(os.path.join(root, name), "w", encoding="utf-8").close()
    _wait(os.path.join(root, "go"))
    node, entry = _ex(root), _intake(root)
    if mode == "concurrent":
        work, holder, busy = "card-%d" % index, "h%d" % index, 0
        for tick in range(int(rest[1])):
            grant = node.claim(work, holder)
            if grant.result == BUSY:                   # BUSY 는 «다음 tick» 사건이다
                busy += 1
                time.sleep(TICK)
                continue
            [_retry(call) for call in _steps(node, work, holder, grant.gen, tick)]
        Path(root, "out-%d.json" % index).write_text(json.dumps({"busy": busy}), encoding="utf-8")
        return 0
    for i in range(index):
        if mode == "receive":
            _retry(lambda i=i: entry.submit("cmd-%d" % i, "본문"))
            continue
        work, holder = "work-%d" % i, "h%d" % i
        grant = _retry(lambda work=work, holder=holder: node.claim(work, holder))
        [_retry(call) for call in _steps(node, work, holder, grant.gen)]
    return 0

if __name__ == "__main__":
    sys.exit(0 if os.environ.get("FT2_EXEC_CHILD") != "1" else _child_main(sys.argv[1:]))
