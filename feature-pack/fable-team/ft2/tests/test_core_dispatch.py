"""ft2 코어 배정·전달·완료 재평가 시험 (r1581 · PR② 셋째 장).

계약 사례 = `ft2/contracts/dispatch/CASES.md` · 사례표 = `ft2/contracts/dispatch/cases/*.json`.
«given 1줄 = 호출 1개»: E1 `assign(pre=…)` · E2 `assign(resources=[…])`(경합 = 자식 2·barrier) ·
E3 `assign`→`deliver`(crash = 자식 `on_step=after_journal`→`recover`) · E4 `complete`(crash =
자식 `on_step=after_complete`→`recover`). 관측 이름은 원자료 `counts` → 이 코어로 옮겼다:
`dispatch`(전달 사건) = `dispatch_journal` = deliver 기록 수 · `delivery_rows` = `dispatch_state` ·
`owner` = 배정된 작업 중 owner 칸이 남은 수(실행권 장의 claim owner 는 배정 기록이 없어 안 센다) ·
`reassess`/`release`/`owner_recover` = reassess 기록·state 칸. `journal_ops`(원자료 log op 문자열)는
우리 기록 꼴이 kind 라 대조하지 않는다. 수신 업무 = «대역 계수기»(같은 (work, attempt) = 실행 1·억제 1).
변이 검출 위치: M1 test_m1 · M2 ⓑ · M3 ⓓ·test_m3 · M4 ⓕ·test_m4 · M5 test_m5 · M6 ⓗ·test_m6 ·
M7 test_m7 · M8 ⓙ · M9 ⓚ①·test_m9 · M10 ⓚ②·test_m10 · M13 test_m13. 재진입 표지 = `FT2_DISPATCH_CHILD`.
"""
import collections
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
CORE = os.path.join(FT2, "core")
GUARD = os.path.join(FT2, "tools", "legacy_guard.py")
CASES = os.path.join(FT2, "contracts", "dispatch", "cases")
TEAM, EV, WORKS = "harness", ("v1", "v2"), ("W1", "W2", "W3", "W4")
OK, HOLD, REFUSED, BUSY, STALE = "접수 성공", "완료 유보", "접수 거부", "BUSY", "낡은 실행권"
REQUIRED = ("dispatch_journal", "dispatch_state", "owner", "reserved", "delivery", "reassess_journal",
            "release_journal", "uncertain_release", "run", "suppressed", "deliver_attempts")
CHILD_ENV = dict(os.environ, FT2_DISPATCH_CHILD="1")


def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_core_" + name, os.path.join(CORE, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


record, intake, execution, dispatch = _load("record"), _load("intake"), _load("execution"), _load("dispatch")
projection = _load("projection")
Grant, Dispatch = dispatch.Grant, dispatch.Dispatch


def _d(root, cls=None, on_step=None):
    return (cls or Dispatch)(str(root), TEAM, on_step=on_step)


def _accept(root, *works):
    """접수 영수 — r1616 부터 assign 은 같은 work 를 남긴 accept 줄을 요구한다(submit 1줄)."""
    for work in works:
        assert _accept_cmd(root, "c-" + work, work)
    return root


def _accept_cmd(root, command, work):
    """command 이름을 지정한 접수 1줄 — 접수 자식(`submit` 역할)과 같은 명령을 미리 접수할 때 쓴다."""
    return intake.Intake(str(root), TEAM).submit(command, "본문-" + work, work).written


def _ex(root):
    return execution.Execution(str(root), TEAM)


def _taker():
    """수신 업무 대역 계수기 — 전송 횟수가 아니라 «같은 attempt 실행 1회» 를 센다(ⓔⓕ)."""
    seen, count = set(), collections.Counter()

    def take(work, attempt):
        count["suppressed" if (work, attempt) in seen else "run"] += 1
        seen.add((work, attempt))
    return count, take


def _obs(node, granted=0, reject=None, refused=0, count=None):
    """사례표의 7수 + run·suppressed·deliver_attempts + 사례별 보조 칸(원자료 이름 그대로)."""
    state, records = node.ex._state_records()
    delivers = [rec for rec in records if rec["kind"] == "deliver"]
    reassess = [rec for rec in records if rec["kind"] == "reassess"]
    by_task = collections.Counter(rec["work"] for rec in delivers)
    dispatched = {rec["work"] for rec in records if rec["kind"] == "dispatch"}
    released, taken = state["released"], (count or collections.Counter())
    sent = sum(len(value) for value in state["deliveries"].values())
    return {
        "dispatch_journal": len(delivers), "dispatch_state": sent, "delivery": sent,
        "owner": len([work for work in state["owners"] if work in dispatched]),
        "reserved": len(state["reservations"]),
        "reassess_journal": len(reassess),
        "release_journal": len([rec for rec in reassess if rec.get("released")]),
        "uncertain_release": len([rec for rec in reassess if rec["work"] in state["uncertain"]]),
        "owner_recover_journal": len([rec for rec in reassess if rec.get("owner_recovered")]),
        "run": taken["run"], "suppressed": taken["suppressed"],
        "deliver_attempts": list(dict.fromkeys(rec["attempt"] for rec in delivers)),
        "deliver_by_task": dict(by_task), "done_tasks": sorted(state["done"]),
        "claim_granted": granted, "claim_reject": dict(reject or {}), "refused": refused,
        "reservations": [{"attempt": row["attempt"], "res": res, "task": row["work"]}
                         for res, row in sorted(state["reservations"].items())],
        "reassess_state": sorted(state["reassess_done"]),
        "release_state": sorted(work for work, row in released.items() if row["count"]),
        "owner_recover_state": sorted(state["owners_recovered"]),
        "released_without_need": sorted(work for work, row in released.items() if not row["res"]),
        "task_attempt": {work: next((rec["attempt"] for rec in reversed(records)
                                    if rec["work"] == work and rec["kind"] == "dispatch"), None)
                         for work in WORKS},
        "task_state": {work: ("완료" if work in state["done"] else "대기") for work in WORKS},
    }


def _check(obs, row):
    """사례표 대조 — arm 행은 필수 11칸, 접두 스냅숏 행(`stop_op`)은 dispatch_journal·deliver_by_task 만."""
    want = row["값"]
    for key in REQUIRED if "stop_op" not in want else ("dispatch_journal", "deliver_by_task"):
        assert obs[key] == want[key], (row["키"], key, obs[key], want[key])
    for key, value in want.items():
        if key in obs:
            assert obs[key] == value, (row["키"], key, obs[key], value)


def _want(name, index=0):
    return json.loads(Path(CASES, name).read_text(encoding="utf-8"))["expect"]["관측"][index]


def _bytes(node):
    """state·journal 바이트 — «쓰기 0» 을 바이트로 대조한다(ⓚ③)."""
    return tuple(Path(path).read_bytes() if os.path.exists(path) else b""
                 for path in (node.rs.state_path, node.rs.journal_path))


def _wait(path, seconds=20.0):
    deadline = time.monotonic() + seconds
    while not os.path.exists(str(path)) and time.monotonic() < deadline:
        time.sleep(0.002)
    assert os.path.exists(str(path)), "기다리다 지남: " + str(path)


def _retry(call, tries=400):
    out = call()
    for _ in range(tries):
        if out.result != BUSY:
            return out
        time.sleep(0.002)
        out = call()
    return out


def _deliver_until(node, work, attempt, tries=400):
    """전달 재시도 — BUSY(잠금 점유 · 계약상 «다음 tick») 일 때만 다시 부른다. 그 밖 결과는 그대로."""
    out = node.deliver(work, attempt)
    for _ in range(tries):
        if out.result != BUSY:
            return out
        out = node.deliver(work, attempt)
    return out


class _UnlockAfterBusy:                                    # 첫 BUSY 직후 잠금을 놓는다 = 재시도 1회가 필요한 순서
    def __init__(self, node, unlock):
        self.node, self.unlock = node, unlock

    def deliver(self, work, attempt, *args, **kwargs):
        out = self.node.deliver(work, attempt, *args, **kwargs)
        if out.result == BUSY and self.unlock:
            unlock, self.unlock = self.unlock, None
            unlock()
        return out


def _spawn(*args):
    return subprocess.Popen([sys.executable, os.path.abspath(__file__)] + [str(a) for a in args], env=CHILD_ENV)


def _child(*args):
    return subprocess.run([sys.executable, os.path.abspath(__file__)] + [str(a) for a in args],
                          env=CHILD_ENV, capture_output=True, timeout=25)


def _seed(root, w3=True):
    """사례 배치 — 다른 팀 완료 통보 W2 · 독립 W3 배정+전달 · W4 거절(pre-all)."""
    node, reject = _d(_accept(root, *WORKS)), collections.Counter()
    node.complete("W2")
    granted = 0
    if w3:
        granted = int(node.assign("W3", "h1", evidence=EV, resources=["shared-slot"]).written)
        node.deliver("W3", "a1")
    reject[node.assign("W4", "h2", pre=["W1"], evidence=EV).reason] += 1
    return node, granted, reject


def _delivered(root):
    node = _d(_accept(root, *WORKS))
    node.assign("W3", "h1", evidence=EV, resources=["shared-slot"])
    node.deliver("W3", "a1")
    return node


def _race(root, cls=None, tag=""):
    """자식 2 · barrier — 같은 공유 자원에 두 claimant."""
    root = str(root)
    roles = ("W1", "W3")
    _d(_accept(root, *roles), cls)
    procs = [_spawn("work", root, "race", role, *_mutant_name(cls)) for role in roles]
    [_wait(os.path.join(root, "ready-" + role)) for role in roles]
    open(os.path.join(root, "go"), "w", encoding="utf-8").close()
    assert [proc.wait(timeout=25) for proc in procs] == [0, 0]
    outs = {role: json.loads(Path(root, "out-" + role + ".json").read_text()) for role in roles}
    return _obs(_d(root, cls), sum(1 for out in outs.values() if out["written"])), outs


def test_a_case_01_allof_allows_independent_and_blocks_unmet(tmp_path):
    node, granted, reject = _seed(tmp_path / "e1")
    _check(_obs(node, granted, reject), _want("01-e1n-normal-allof.json", 1))       # E1n_mid
    assert dict(reject) == {"pre-all": 1}                                          # A 대기 = pre-all
    claim = _ex(tmp_path / "e1").claim("W1", "h1")
    _ex(tmp_path / "e1").mark_uncertain("W1", "h1", claim.gen, "무응답")
    refused = int(node.reassess("W1").result == REFUSED)                           # UNCERTAIN 반환 거부
    assert (refused, _obs(node)["uncertain_release"]) == (1, 0)
    _check(_obs(node, granted, reject, refused), _want("01-e1n-normal-allof.json", 0))   # E1nn
    tail = _d(_accept(tmp_path / "after", *WORKS))
    [tail.complete(work) for work in ("W1", "W2", "W3")]
    assert tail.assign("W4", "h1", pre=["W1"], evidence=EV).written
    tail.deliver("W4", "a1")
    _check(_obs(tail, 1), _want("01-e1n-normal-allof.json", 2))                    # E1n-after
    _check(_obs(tail, 1), _want("01-e1n-normal-allof.json", 3))                    # E1n_after_all


def test_b_case_02_team_close_is_not_evidence(tmp_path):
    gate = _d(_accept(tmp_path / "v", "W4"), _TeamCloseGate)
    gate.complete("W2")
    mutant = gate.assign("W4", "h1", pre=["W1"], evidence=EV, gate="team-close")
    gate.deliver("W4", mutant.attempt)
    assert mutant.written and "W1" not in _obs(gate, 1)["done_tasks"]              # M2 = 계약 극성 FAIL
    _check(_obs(gate, 1), _want("02-e1v-teamclose-gate.json", 0))                  # E1vv
    ctrl, _, reject = _seed(tmp_path / "c", w3=False)
    assert _d(tmp_path / "c").assign("W4", "h1", pre=["W1"], evidence=EV).result == REFUSED
    _check(_obs(ctrl, 0, reject), _want("02-e1v-teamclose-gate.json", 1))          # E1v-ctrl


def test_c_case_03_single_claim_gives_one_owner_and_reservation(tmp_path):
    node = _delivered(tmp_path / "e2")
    state = node.ex._state_records()[0]
    assert (state["owners"]["W3"]["gen"], state["generations"]["W3"]) == (1, 1)
    _check(_obs(node, 1), _want("03-e2n-single-claim.json", 0))                    # E2nn


def test_d_case_04_race_grants_once_and_stale_snapshot_double_grants(tmp_path):
    obs, outs = _race(tmp_path / "atomic")
    winner = next(role for role, out in outs.items() if out["written"])
    assert (obs["claim_granted"], obs["reserved"], obs["owner"]) == (1, 1, 1)      # 승자 1
    row = _want("04-e2v-race-two-claimants.json", 0)
    _check(obs, dict(row, 값=dict(row["값"], reservations=[{"attempt": "a1", "res": "shared-slot",
                                                            "task": winner}])))     # E2v-atomic
    stale, stale_outs = _race(tmp_path / "stale", _StaleSnapshot)
    assert sorted(role for role, out in stale_outs.items() if out["written"]) == ["W1", "W3"]
    assert (stale["claim_granted"], stale["reserved"]) == (2, 1)                    # M3 = 승자 2
    assert (stale["dispatch_journal"], stale["delivery"]) == (0, 0)                 # 변이 검출


def test_d2_winner_deliver_busy_then_retried(tmp_path):
    """ⓐ 부모 두 번째 노드가 잠금을 쥔 동안 승자 deliver = BUSY·쓰기 0 → BUSY 를 본 뒤 재시도 = 전달 1."""
    root = str(tmp_path / "d2")
    node = _d(_accept(root, "W3"))                     # r1616: 배정 앞 접수 1줄(병합 뒤 1줄 고침)
    grant = node.assign("W3", "h1", evidence=EV, resources=["shared-slot"])
    assert grant.written
    own = _d(root).rs._try_lock()                            # 부모 두 번째 노드가 같은 팀 잠금을 쥔다
    assert own is not None                                   # 점유 중이면 None = 잠금 없이 진행하지 않는다
    before = _bytes(node)
    busy = node.deliver(grant.work, grant.attempt)
    assert (busy.result, busy.written) == (BUSY, False) and _bytes(node) == before   # BUSY = 쓰기 0
    assert _deliver_until(node, grant.work, grant.attempt, tries=0).result == BUSY   # M1 = 재시도 0회
    written = _deliver_until(_UnlockAfterBusy(node, lambda: node.rs._unlock(own)),
                             grant.work, grant.attempt)
    assert (written.result, written.written) == (OK, True)                           # BUSY 뒤 재시도 = 전달
    assert _obs(node, 1)["dispatch_journal"] == 1                                    # 전달 줄 1


def test_e_case_05_delivery_runs_once(tmp_path):
    node, count, take = _delivered(tmp_path / "e3"), *_taker()
    take("W3", "a1")
    _check(_obs(node, 1, count=count), _want("05-e3n-claim-deliver.json", 0))       # E3nn


def test_f_case_06_crash_before_delivery_redelivers_same_attempt(tmp_path):
    root, count, take = str(tmp_path / "e3v"), *_taker()
    _d(_accept(root, "W3"))
    assert _child("crash", root, "after_journal", "assign").returncode == 9
    node = _d(root)
    take("W3", node.recover()["delivered"][0])                                     # 복구 전달 → 실행 1
    node.deliver("W3", "a1", mode="scan")                                          # 같은 attempt 재전달
    take("W3", "a1")                                                               # 중복 실행 억제 1
    assert node.recover()["delivered"] == []                                       # 멱등
    _check(_obs(node, 1, count=count), _want("06-e3v-crash-before-delivery.json", 0))   # E3v-contract
    lost_root = str(tmp_path / "nointent")
    _d(_accept(lost_root, "W3"))
    assert _child("crash", lost_root, "after_journal", "assign").returncode == 9
    lost = _d(lost_root, _LostIntent)                                              # M4 = 의도 미기록
    assert lost.recover()["delivered"] == []                                       # 복구 전달 0
    lost.deliver("W3", "a1", mode="scan")
    _check(_obs(lost, 1), _want("06-e3v-crash-before-delivery.json", 1))           # E3v-nointent


def test_g_case_07_completion_reassesses_releases_and_recovers_owner(tmp_path):
    node = _delivered(tmp_path / "e4")
    assert node.complete("W3", "a1").released == ["shared-slot"]
    out = node.recover()                                                          # 멱등
    assert out.pop("result") == OK and out == {"delivered": [], "reassessed": []}
    _check(_obs(node, 1), _want("07-e4n-complete-reassess.json", 0))               # E4nn


def test_h_case_08_crash_before_reassess_recovers_only_marked_completions(tmp_path):
    root = str(tmp_path / "e4v")
    node = _delivered(root)
    node.complete("W2")                                                            # 다른 팀 완료(표식 0)
    assert _child("crash", root, "after_complete", "complete").returncode == 9
    node = _d(root)
    assert _obs(node, 1)["reassess_journal"] == 0                                  # crash 직후 재평가 0
    assert node.recover()["reassessed"] == ["W3"]                                  # 표식 있는 complete 만
    assert node.recover()["reassessed"] == []                                      # 멱등
    obs = _obs(node, 1)
    assert (obs["released_without_need"], obs["owner_recover_state"]) == ([], ["W3"])
    _check(obs, _want("08-e4v-crash-before-reassess.json", 2))                     # E4v-evidenceonly(보정)
    scan = str(tmp_path / "scan")
    mutant = _d(_accept(scan, "W3"), _ScanAll)                                      # M6 = 표식 없이 전부 훑기
    mutant.complete("W2")
    mutant.assign("W3", "h1", evidence=EV, resources=["shared-slot"])
    mutant.deliver("W3", "a1")
    assert mutant.complete("W3", "a1").written
    _d(scan, _ScanAll).recover()
    stale = _obs(_d(scan, _ScanAll), 1)
    assert (stale["reassess_journal"], stale["reassess_state"]) == (2, ["W2", "W3"])   # 판1 관측
    assert (stale["owner_recover_state"], stale["released_without_need"]) == (["W2", "W3"], ["W2"])


def test_i_replay_table_shape_fits_core_observation(tmp_path):
    """ⓘ 재생 대조 — 8사례 표의 arm 행이 필수 11칸을 다 선언하고, 관측 이름이 코어 관측에 실재한다.
    값 대조는 ⓐ~ⓗ 가 각 사례표 행에서 한다(정본 arm 8 + 대조·변이·보정 arm 8)."""
    names = sorted(os.listdir(CASES))
    assert len(names) == 8
    obs = _obs(_delivered(tmp_path / "i"), 1)
    for name in names:
        for row in json.loads(Path(CASES, name).read_text(encoding="utf-8"))["expect"]["관측"]:
            keys = ("dispatch_journal", "deliver_by_task") if "stop_op" in row["값"] else REQUIRED
            assert set(keys) <= set(row["값"]), (name, row["키"])                  # DA R1 필수 관측 집합
            assert set(row["값"]) <= set(obs) | {"stop_op", "lines_used", "journal_ops"}, (name, row["키"])


def test_j_public_faces_and_contract_words(tmp_path):
    """ⓙ 불변 — 입구·실행권 공개 면 · Grant 9칸 · schema 1 · 결과 8낱말 · legacy_guard · 앞 장 24. (+M8)"""
    assert tuple(inspect.signature(intake.Intake.submit).parameters) == ("self", "command", "body", "work")
    assert tuple(inspect.signature(intake.Intake.lookup).parameters) == ("self", "command")
    assert intake.Receipt._fields == ("result", "command", "attempt", "revision", "written", "body_ref", "reason")
    assert tuple(inspect.signature(execution.Execution.claim).parameters) == \
        ("self", "work", "holder", "rotation", "confirm_by")
    assert execution.Grant._fields == ("result", "work", "gen", "holder", "revision", "written", "stage",
                                       "confirm_by", "reason")
    assert (record.SCHEMA_VERSION, len(record.KINDS)) == (1, 17)   # r1594: progress · close · r1724: refuse · resolve · r1725: close_receipt · r1727: reopen
    node = _d(tmp_path / "j")
    words = {node.assign("W3", "h1", evidence=EV).result, node.deliver("W3", "a1").result,
             node.complete("W3", "a1").result, node.reassess("W3").result,
             node.assign("W4", "h1", pre=["W1"], evidence=EV).result}
    assert all(record.is_contract_result(word) for word in words)
    assert subprocess.run([sys.executable, "-I", GUARD], capture_output=True, timeout=25).returncode == 0
    legacy = subprocess.run([sys.executable, "-m", "pytest", os.path.join(HERE, "test_core_execution.py"),
                             "-q"], capture_output=True, timeout=70, cwd=FT2)
    assert legacy.returncode == 0 and b"24 passed" in legacy.stdout
    assert intake.Intake(str(tmp_path / "j"), TEAM, capacity=1).lookup("W3") is None   # kind=accept 만
    original = intake.Intake._prior_receipt
    intake.Intake._prior_receipt = lambda self, records, command: next(             # M8
        (rec for rec in reversed(records) if rec["command"] == command), None)
    try:
        assert intake.Intake(str(tmp_path / "j"), TEAM).lookup("W3") is not None   # 판독이 바뀐다 = FAIL
    finally:
        intake.Intake._prior_receipt = original


def test_k1_assignment_never_calls_public_claim(tmp_path):
    """ⓚ① 경쟁자 없음 → 배정 성공 · Execution.claim 공개 호출 0."""
    node, calls = _d(_accept(tmp_path / "k1", "W3")), []
    real = node.ex.claim
    node.ex.claim = lambda *args, **kwargs: (calls.append(args), real(*args, **kwargs))[1]
    assert node.assign("W3", "h1", evidence=EV, resources=["shared-slot"]).result == OK
    assert calls == []
    assert _d(_accept(tmp_path / "k1m", "W3"), _PublicClaim).assign(                 # M9
        "W3", "h1", evidence=EV, resources=["shared-slot"]).result == BUSY


def test_k2_generation_and_delivery_intent_survive_checkpoint_crash(tmp_path):
    """ⓚ② dispatch 줄 journal 내구화 직후·checkpoint 전 crash → 세대·예약·의도 복구."""
    root = str(tmp_path / "k2")
    _d(_accept(root, "W3"))
    assert _child("crash", root, "after_journal", "assign").returncode == 9
    node = _d(root)
    assert node.ex.start("W3", "h1", 2).result == STALE                             # 옛 gen = 낡은 실행권
    assert node.ex.start("W3", "h1", 1).result == OK                                # journal 세대 유효본
    out = node.recover()
    assert out.pop("result") == OK and out == {"delivered": ["a1"], "reassessed": []}
    state = node.ex._state_records()[0]
    assert (state["reservations"]["shared-slot"]["attempt"], state["deliveries"]["W3"]) == ("a1", ["a1"])
    assert node.recover()["delivered"] == []
    split = str(tmp_path / "k2m")
    _d(_accept(split, "W3"))
    assert _child("crash", split, "after_journal", "assign", "split").returncode == 9   # M10
    assert _d(split).recover()["delivered"] == []                                   # 예약·의도 없음 = 전달 0


def test_k3_assignment_is_busy_while_lock_held(tmp_path):
    """ⓚ③ 대역 프로세스가 writer.lock 점유 중 assign = BUSY · journal·state 쓰기 0."""
    root = str(tmp_path / "k3")
    node = _d(root)
    holder = _spawn("hold", root, 0.4)
    _wait(os.path.join(root, "held"))
    before = _bytes(node)
    busy = node.assign("W3", "h1", evidence=EV, resources=["shared-slot"])
    assert holder.wait(timeout=25) == 0 and (busy.result, busy.written) == (BUSY, False)
    assert _bytes(node) == before


def test_k4_assign_submit_and_claim_interleave_with_strict_revision(tmp_path):
    """ⓚ④ 배정 ∥ 접수 ∥ 실행권 교차(자식 3) → revision 엄격 증가 · 서로의 확장 칸 보존."""
    root = str(tmp_path / "k4")
    node = _d(root)
    assert [_accept_cmd(root, "cmd-%d" % index, "M%d" % index) for index in range(3)]
    _accept(root, "C0", "C1", "C2")                    # r1632 ⓐ: 실행권(claim)도 접수 영수 필요
    roles = ("assign", "submit", "claim")
    procs = [_spawn("work", root, "mix", role) for role in roles]
    [_wait(os.path.join(root, "ready-" + role)) for role in roles]
    open(os.path.join(root, "go"), "w", encoding="utf-8").close()
    assert [proc.wait(timeout=25) for proc in procs] == [0, 0, 0]
    state, records = node.ex._state_records()
    assert state["revision"] == len(records)                                        # 엄격 증가
    assert sorted(state["reservations"]) == ["slot-0", "slot-1", "slot-2"]          # 배정 몫 보존
    assert sorted(state["pending"]) == ["c-C0", "c-C1", "c-C2", "cmd-0", "cmd-1", "cmd-2"]   # 접수 몫 보존
    assert [work for work in ("M0", "M1", "M2") if state["generations"].get(work)] == ["M0", "M1", "M2"]
    assert [work for work in ("C0", "C1", "C2") if work in state["owners"]] == ["C0", "C1", "C2"]


def test_m1_any_of_assigns_before_all_predecessors(tmp_path):
    node = _d(_accept(tmp_path / "m1", "W4"), _AnyOf)
    node.complete("W2")
    assert node.assign("W4", "h1", pre=["W1", "W2"], evidence=EV).written          # 조기 배정 = FAIL
    assert "W1" not in _obs(node, 1)["done_tasks"]


def test_m5_new_attempt_on_redelivery_runs_twice(tmp_path):
    root = str(tmp_path / "m5")
    _d(_accept(root, "W3"))
    assert _child("crash", root, "after_journal", "assign").returncode == 9
    node, count, take = _d(root, _NewAttempt), *_taker()
    take("W3", node.recover()["delivered"][0])
    take("W3", node.deliver("W3", "a1", mode="scan").attempt)
    assert (count["run"], count["suppressed"]) == (2, 0)                           # 실행 2 = FAIL


def test_g1_allof_needs_every_predecessor(tmp_path):
    """NG②-ⓐ 선행 2개 중 1개만 완료 = 미충족(all-of→any-of 변이 검출)."""
    node = _d(tmp_path / "g1")
    node.complete("W2")
    grant = node.assign("W4", "h1", pre=["W1", "W2"], evidence=EV)
    assert (grant.result, grant.reason, grant.written) == (REFUSED, "pre-all", False)


def test_g2_second_assign_for_same_resource_is_refused(tmp_path):
    """NG②-ⓑ 같은 공유 자원 순차 배정 = 거절(resource) — 경합 BUSY 가 아니라 예약 판정을 본다."""
    node = _d(_accept(tmp_path / "g2", "W3"))
    assert node.assign("W3", "h1", evidence=EV, resources=["shared-slot"]).written
    second = node.assign("W4", "h2", evidence=EV, resources=["shared-slot"])
    assert (second.result, second.reason) == (REFUSED, "resource")
    assert _obs(node, 1)["reservations"] == [{"attempt": "a1", "res": "shared-slot", "task": "W3"}]


def test_g3_uncertain_reassess_is_refused_by_uncertainty(tmp_path):
    """NG②-ⓒ 표식 있는 완료라도 미확정이면 재평가 거절 — «표식 없음» 거부에 가려지지 않는다."""
    root = str(tmp_path / "g3")
    _delivered(root)
    assert _child("crash", root, "after_complete_journal", "complete").returncode == 9
    node = _d(root)
    assert _obs(node, 1)["done_tasks"] == ["W3"]                                   # 표식 있는 완료 복구
    assert _ex(root).mark_uncertain("W3", "h1", 1, "무응답").result == HOLD
    refused = node.reassess("W3")
    assert (refused.result, "미확정" in refused.reason) == (REFUSED, True)          # 결함 = OK(반환)
    obs = _obs(node, 1)
    assert (obs["reassess_journal"], obs["reserved"]) == (0, 1)                     # 반환 0 · 예약 유지


def test_c07a_complete_on_uncertain_work_is_held_with_no_write(tmp_path):
    """r1624 ⓐ — 미확정 작업 complete = HOLD(«결과 미확정 = 완료 유보») · journal 새 행 0 · done 없음."""
    root = str(tmp_path / "c07a")
    node = _delivered(root)
    assert _ex(root).mark_uncertain("W3", "h1", 1, "무응답").result == HOLD
    before, grant = len(node.ex._state_records()[1]), node.complete("W3", "a1")
    state, records = node.ex._state_records()
    assert (grant.result, grant.reason, grant.written) == (HOLD, "결과 미확정 = 완료 유보", False)
    assert (len(records), "W3" in state["done"]) == (before, False)


def test_c07b_projection_keeps_uncertain_holder_busy(tmp_path):
    """ⓑ 같은 순서 뒤 project — holder 는 가용이 아니고, 그 작업 행은 done=false·uncertain=true."""
    root = str(tmp_path / "c07b")
    node = _delivered(root)
    assert _ex(root).mark_uncertain("W3", "h1", 1, "무응답").result == HOLD
    assert node.complete("W3", "a1").result == HOLD
    out = projection.project(root, TEAM)
    assert out["holders"]["h1"] == {"free": False, "works": ["W3"]}
    assert (out["works"]["W3"]["done"], out["works"]["W3"]["uncertain"]) == (False, True)


def test_c07c_confirmed_work_completes_and_releases(tmp_path):
    """ⓒ 미확정이 아닌 작업 완료 = 지금처럼 OK + 재평가(예약 반환)."""
    node = _delivered(tmp_path / "c07c")
    grant = node.complete("W3", "a1")
    assert (grant.result, grant.written, grant.released) == (OK, True, ["shared-slot"])
    assert _obs(node, 1)["done_tasks"] == ["W3"]


def test_m13_without_guard_uncertain_work_is_completed(tmp_path):
    """M13(새 판정 줄 제거) — ⓐ·ⓑ 가 무너진다(done=true · h1 free=true)."""
    root = str(tmp_path / "m13")
    node = _d(_accept(root, "W3"), _NoUncertainGuard)
    node.assign("W3", "h1", evidence=EV, resources=["shared-slot"])
    node.deliver("W3", "a1")
    assert _ex(root).mark_uncertain("W3", "h1", 1, "무응답").result == HOLD
    assert node.complete("W3", "a1").written                                  # 판정 0 = ⓐ FAIL
    out = projection.project(root, TEAM)
    assert (out["works"]["W3"]["done"], out["holders"]["h1"]["free"]) == (True, True)   # ⓑ FAIL

def test_r1_deliver_checkpoint_crash_keeps_journal_and_state_equal(tmp_path):
    """DA R1① deliver journal 내구화 직후·checkpoint 전 crash — state 전달 0 이던 결함."""
    root = str(tmp_path / "r1a")
    _d(_accept(root, "W3")).assign("W3", "h1", evidence=EV, resources=["shared-slot"])
    assert _child("crash", root, "after_deliver_journal", "deliver").returncode == 9
    node, obs = _d(root), None
    obs = _obs(node, 1)
    assert (obs["dispatch_journal"], obs["dispatch_state"]) == (1, 1)        # 결함 = 1 / 0
    assert node.deliver("W3", "a1").result == HOLD                          # 내구화된 전달 = 재전달 0


def test_r1_complete_checkpoint_crash_reassesses_from_journal(tmp_path):
    """DA R1② complete journal 내구화 직후 crash — done·표식이 없어 재평가 0 이던 결함."""
    root = str(tmp_path / "r1b")
    _delivered(root)
    assert _child("crash", root, "after_complete_journal", "complete").returncode == 9
    node = _d(root)
    assert _obs(node, 1)["done_tasks"] == ["W3"]                            # 결함 = []
    assert node.complete("W3", "a1").result == HOLD                         # 두 번째 complete = 쓰기 0
    assert len([r for r in node.ex._state_records()[1] if r["kind"] == "complete"]) == 1
    assert node.recover()["reassessed"] == ["W3"]
    obs = _obs(node, 1)
    assert (obs["reassess_journal"], obs["release_state"], obs["owner_recover_state"]) == (1, ["W3"], ["W3"])
    assert (obs["reserved"], obs["owner"]) == (0, 0)                        # 예약 반환 · owner 복구
    assert node.recover()["reassessed"] == []


def test_r1_reassess_checkpoint_crash_does_not_duplicate(tmp_path):
    """DA R1③ reassess journal 내구화 직후 crash — 재평가가 2행이 되던 결함."""
    root = str(tmp_path / "r1c")
    _delivered(root)
    assert _child("crash", root, "after_reassess_journal", "complete").returncode == 9
    node = _d(root)
    assert node.recover()["reassessed"] == []                               # 이미 내구화 = 중복 0
    assert _obs(node, 1)["reassess_journal"] == 1                           # 결함 = 2


def test_r1_reservation_is_seen_without_calling_recover(tmp_path):
    """DA R1·arch NG①-ⓐ — recover 를 부르지 않아도 잠금 안 판독이 배정 줄의 예약을 겹쳐 읽는다."""
    root = str(tmp_path / "r1d")
    _d(_accept(root, "W3"))
    assert _child("crash", root, "after_journal", "assign").returncode == 9
    node = _d(root)
    second = node.assign("W4", "h2", evidence=EV, resources=["shared-slot"])   # recover 호출 0
    assert (second.result, second.reason) == (REFUSED, "resource")             # 결함 = 접수 성공(승자 2)
    assert _obs(node)["reservations"] == [{"attempt": "a1", "res": "shared-slot", "task": "W3"}]


def test_r2_owner_without_dispatch_lineage_is_refused(tmp_path):
    """DA R2 — 정상 공개 Execution.claim 으로 owner 만 있는 W2 완료 = 거절 · 쓰기 0(ⓗ W2 불변)."""
    root = str(tmp_path / "r2")
    node = _d(root)
    _accept(root, "W2")                                    # r1632 ⓐ: 실행권도 접수 영수 필요
    assert _ex(root).claim("W2", "independent-holder").result == OK
    before = _bytes(node)
    refused = node.complete("W2")
    assert (refused.result, refused.written) == (REFUSED, False)            # 결함 = OK · owner 삭제
    assert _bytes(node) == before
    state = node.ex._state_records()[0]
    assert (state["owners"]["W2"]["holder"], state["released"], state["reassess_done"]) == \
        ("independent-holder", {}, {})
    node.complete("W3")                                                     # 배정 계보 없는 빈 작업 = 외부 완료
    assert _obs(node, 0)["done_tasks"] == ["W3"]


def test_m7_uncertain_release_is_allowed(tmp_path):
    root = str(tmp_path / "m7")
    _accept(root, "W1")
    claim = _ex(root).claim("W1", "h1")
    _ex(root).mark_uncertain("W1", "h1", claim.gen, "무응답")
    assert _d(root).reassess("W1").result == REFUSED
    mutant = _d(root, _AllowUncertain)
    assert mutant.reassess("W1").result == OK                                       # 반환 허용 = FAIL
    assert _obs(mutant)["uncertain_release"] == 1


def test_m11_legacy_read_without_journal_state_restore(tmp_path):
    root = str(tmp_path / "m11")
    _d(_accept(root, "W3")).assign("W3", "h1", evidence=EV, resources=["shared-slot"])
    assert _child("crash", root, "after_deliver_journal", "deliver").returncode == 9
    legacy = Dispatch(root, TEAM, execution_cls=_LegacyExecution)          # M11 = 종전 판독
    assert _obs(legacy, 1)["dispatch_state"] == 0                          # 전달 복구 0 = FAIL


def test_m12_marker_from_owner_deletes_execution_owner(tmp_path):
    node = _d(tmp_path / "m12", _OwnerMarker)
    _accept(tmp_path / "m12", "W2")
    _ex(tmp_path / "m12").claim("W2", "independent-holder")
    assert node.complete("W2").written                                     # 배정 계보 무시 = FAIL
    state = node.ex._state_records()[0]
    assert ("W2" in state["owners"], state["released"].get("W2", {}).get("count")) == (False, 0)


class _AnyOf(Dispatch):                                    # M1: all-of → any-of
    def _eligible(self, state, work, pre, evidence, resources=()):
        done = state.get("done") or {}
        return super()._eligible(state, work, () if any(name in done for name in pre) else pre,
                                 evidence, resources)


class _TeamCloseGate(Dispatch):                            # M2: 팀 마감 «잔여 0» 을 배정 증거로
    def _eligible(self, state, work, pre, evidence, resources=()):
        if state.get("done"):
            return super()._eligible(state, work, (), self.REQUIRED_EVIDENCE, resources)
        return super()._eligible(state, work, pre, evidence, resources)


class _BlockingIntake(intake.Intake):                      # M3 결선: 잠금을 «기다린다»
    def _try_lock(self):
        handle = open(self._lock_file_path(), "a+", encoding="utf-8")
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        return handle


class _BlockingExecution(execution.Execution):
    CLIENT = _BlockingIntake


class _StaleSnapshot(Dispatch):                            # M3: 잠금 «밖» 스냅숏 판정
    def __init__(self, root, team, **kwargs):
        super().__init__(root, team, execution_cls=_BlockingExecution, **kwargs)
        self._snapshot = self.ex._state_records()[0]      # barrier «전» 스냅숏

    def _eligible(self, state, work, pre, evidence, resources=()):
        return super()._eligible(self._snapshot, work, pre, evidence, resources)


class _LostIntent(Dispatch):                               # M4: 의도를 배정 기록 밖에 둔다
    def _intent(self, records, work):
        rec = next((r for r in reversed(records) if r["work"] == work and r["kind"] == "dispatch"), None)
        return {"attempt": rec["attempt"], "gen": rec["gen"], "holder": rec["holder"]} if rec else {}


class _NewAttempt(Dispatch):                               # M5: 재전달 때 새 attempt
    def deliver(self, work, attempt=None, mode="intent"):
        if mode == "scan":
            records = self.ex._state_records()[1]
            attempt = "a%d" % (len([r for r in records if r["kind"] == "dispatch"]) + 1)
        return super().deliver(work, attempt, mode)


class _ScanAll(Dispatch):                                  # M6: 표식 없이 완료 전체를 훑는다
    def _pending_reassess(self, state):
        return [work for work in (state.get("done") or {}) if work not in (state.get("reassess_done") or {})]

    def _reassess(self, context, work, mode="marker"):
        state = dict(context[0], done={**context[0]["done"],
                                      work: {**context[0]["done"][work], "marker": "required"}})
        return super()._reassess((state, context[1]), work, mode)


class _AllowUncertain(Dispatch):                           # M7: UNCERTAIN 반환 허용
    def _reassess(self, context, work, mode="marker"):
        state, records = context
        if work not in (state.get("uncertain") or {}):
            return super()._reassess(context, work, mode)
        rec = record.build(self.team, (records[-1]["seq"] if records else 0) + 1, work, "a1",
                           self.clock(), "", work, kind="reassess",
                           extra={"after": None, "mode": mode, "released": [], "owner_recovered": False})
        rev = self._write(state, records, rec, {"reassess_done": {work: {"after": None, "mode": mode}}})
        return Grant(OK, work, "reassess", revision=rev, written=True)


class _PublicClaim(Dispatch):                              # M9: 잠금 안 공개 claim 호출
    def _assign(self, context, work, holder, *args):
        if self.ex.claim(work, holder).result != OK:
            return Grant(BUSY, work, "dispatched", reason="공개 claim 이 같은 잠금을 다시 잡는다")
        return super()._assign(context, work, holder, *args)


class _LegacyExecution(execution.Execution):               # M11: 세 kind 를 state 로 겹쳐 읽지 않던 종전 판
    def _state_records(self):
        state, records = super()._state_records()
        return dict(state, deliveries={}, done={}, reassess_done={}), records


class _OwnerMarker(Dispatch):                              # M12: owner 만 보고 표식을 만든다
    def _assigned(self, records, work):
        return True


class _NoUncertainGuard(Dispatch):                         # M13: 새 판정 줄 제거(r1624)
    def _complete(self, context, work, attempt):
        state, records = context
        return super()._complete((dict(state, uncertain={}), records), work, attempt)


class _SplitWrite(Dispatch):                               # M10: claim 줄과 배정 줄을 따로
    def _write(self, state, records, rec, extra=None, replace=None):
        if rec["kind"] == "dispatch":
            self.rs._append_journal(record.build(self.team, rec["seq"], rec["work"], rec["attempt"],
                                                 rec["at"], "", rec["work"], kind="claim",
                                                 holder=rec["holder"], gen=rec["gen"]))
            self.on_step("after_journal")
        return super()._write(state, records, rec, extra, replace)


_MUTANTS = {"stale": _StaleSnapshot, "split": _SplitWrite}


def _mutant_name(cls):
    return (next(name for name, mutant in _MUTANTS.items() if mutant is cls),) if cls else ()


def _mix(root, node, role):
    """교차 자식 — 배정 · 접수 · 실행권을 같은 runtime 에서 섞는다(BUSY 는 다음 tick)."""
    if role == "assign":
        for index in range(3):
            grant = _retry(lambda index=index: node.assign("M%d" % index, "h1", evidence=EV,
                                                           resources=["slot-%d" % index]))
            if grant.written:
                _retry(lambda grant=grant: node.deliver(grant.work, grant.attempt))
    elif role == "submit":
        entry = intake.Intake(root, TEAM)
        for index in range(3):
            _retry(lambda index=index: entry.submit("cmd-%d" % index, "본문"))
    else:
        for index in range(3):
            _retry(lambda index=index: node.ex.claim("C%d" % index, "h1"))


def _child_main(argv):
    mode, root, rest = argv[0], argv[1], argv[2:]
    if mode == "crash":
        def boom(step):
            if step == rest[0]:
                os._exit(9)
        node = _d(root, _MUTANTS.get(rest[2]) if len(rest) > 2 else None, on_step=boom)
        {"assign": lambda: node.assign("W3", "h1", evidence=EV, resources=["shared-slot"]),
         "deliver": lambda: node.deliver("W3", "a1"),
         "complete": lambda: node.complete("W3", "a1")}[rest[1]]()
        os._exit(7)                                        # crash 지점을 못 만났다
    if mode == "hold":
        node = _d(root)
        handle = node.rs._try_lock()
        open(os.path.join(root, "held"), "w", encoding="utf-8").close()
        time.sleep(float(rest[0]))
        return node.rs._unlock(handle) or 0
    role = rest[1]
    node = _d(root, _MUTANTS.get(rest[2]) if len(rest) > 2 else None)   # 스냅숏 변이는 barrier 전
    open(os.path.join(root, "ready-" + role), "w", encoding="utf-8").close()
    _wait(os.path.join(root, "go"))
    out = {"written": False}
    if rest[0] == "race":
        grant = node.assign(role, "h1", evidence=EV, resources=["shared-slot"])
        out = {"written": bool(grant.written), "result": grant.result}
        if grant.written and not rest[2:]:                     # 변이 arm 은 전달하지 않는다
            delivered = _deliver_until(node, grant.work, grant.attempt)
            out["deliver"] = {"result": delivered.result, "written": bool(delivered.written)}
    else:
        _mix(root, node, role)
    Path(root, "out-" + role + ".json").write_text(json.dumps(out), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(0 if os.environ.get("FT2_DISPATCH_CHILD") != "1" else _child_main(sys.argv[1:]))
