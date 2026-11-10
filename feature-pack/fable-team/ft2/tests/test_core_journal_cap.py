"""ft2 코어 journal 회전·회수·총량 cap 시험 (r1584 · PR② 넷째 장).

계약 사례 = `ft2/contracts/cap/CASES.md` 4건 + DA #280016 R1·R2 보정. 시험 인자(후보값과 비율 대조 0):
total_cap=65,536 B · reserve=4,096 B · segment_cap=1,024 B · state_slack=512 B · line_max=512 B.
ⓐ 회전·순서 판독 · ⓑ 닫힌 segment 만 회수(본문 먼저) · ⓒ 회수 중 crash 복원·멱등 · ⓓ 포화=용량 부족 ·
ⓔ append 경계 공존 peak · ⓕ 사례 낱말 재생 · ⓖ 공개 면 불변. 변이 M1~M12 = 제품 자리 1곳 변이.
crash = 자식 프로세스 SIGKILL(정지점) · 격리 tmp 팀 데이터 루트만 · 실 runtime·press 0.
"""

import fcntl
import importlib.util
import inspect
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FT2 = os.path.dirname(HERE)
CORE = os.path.join(FT2, "core")
GUARD = os.path.join(FT2, "tools", "legacy_guard.py")
CASES = os.path.join(FT2, "contracts", "cap", "cases")
TEAM, EV = "harness", ("v1", "v2")
OK, HOLD, FULL, CORRUPT, BUSY = "접수 성공", "완료 유보", "용량 부족", "복구 필요", "BUSY"
RECLAIMED = "회수 결과"
CAPS = dict(total_cap=65536, reserve=4096, segment_cap=1024, state_slack=512, line_max=512)
CHILD_ENV = dict(os.environ, FT2_JOURNAL_CAP_CHILD="1")


def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_core_" + name, os.path.join(CORE, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


intake, execution, dispatch, journal = (_load(name) for name in ("intake", "execution", "dispatch", "journal"))
record = intake.record          # 예외 클래스 동일성 = 입구가 쓰는 그 모듈(따로 load 하면 except 가 빗나간다)


def _i(root, capacity=8, cls=None, on_step=None, **caps):
    return (cls or intake.Intake)(str(root), TEAM, capacity=capacity, on_step=on_step, **{**CAPS, **caps})


def _rs(node):
    return node if isinstance(node, intake.Intake) else node.rs


def _caps(node, **caps):
    """Execution·Dispatch 는 Intake 기본값을 쓴다 — 시험 인자를 journal 에 직접 걸어 조인다."""
    rs, names = _rs(node), dict(reserve="reserve_bytes")
    for key, value in {**CAPS, **caps}.items():
        setattr(rs.journal, names.get(key, key), value)
    if "capacity" in caps:
        rs.capacity = caps["capacity"]
    return node


def _d(root, cls=None, on_step=None, **caps):
    return _caps((cls or dispatch.Dispatch)(str(root), TEAM, on_step=on_step), **caps)


def _swap_journal(node, cls):
    """제품 journal 객체를 변이 클래스로 갈아 끼운다(제품 파일 1곳 변이와 같은 자리)."""
    rs, old = _rs(node), _rs(node).journal
    rs.journal = cls(rs.runtime, segment_cap=old.segment_cap, total_cap=old.total_cap,
                     reserve=old.reserve_bytes, state_slack=old.state_slack, line_max=old.line_max,
                     ops=rs._ops, on_step=rs.on_step, rec=old.rec)
    return node


def _usage(node):
    return _rs(node).journal.usage()


def _files(node):
    rs, out = _rs(node), {}
    for root, _dirs, names in os.walk(rs.runtime):
        for name in names:
            full = os.path.join(root, name)
            out[os.path.relpath(full, rs.runtime)] = os.path.getsize(full)
    return out


def _ops(node):
    path, out = os.path.join(_rs(node).journal.runtime, "ops.jsonl"), []
    if os.path.exists(path):
        with open(path, encoding="utf-8") as handle:
            out = [json.loads(line)["op"] for line in handle if line.strip()]
    return out


def _state(node):
    rs = _rs(node)
    return rs.journal.rec.recover_state(rs.journal.state(), rs.records())


def _root_of(node):
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(_rs(node).runtime))))


def _close(node, work, holder=None):
    """닫힌 work — 배정 → 결과 → 전달 → 완료(+재평가). 회수 조건 4개를 만족시키는 최소 흐름."""
    holder = holder or work.lower()
    assert node.assign(work, holder, evidence=EV).result == OK
    assert node.ex.result(work, holder, 1, OK).result == OK
    assert node.deliver(work, "a1").result == OK
    assert node.complete(work, "a1").result == OK


def _rotate_scenario(root, cards=40, size=300):
    client = _i(root, capacity=100)
    for n in range(1, cards + 1):
        assert client.submit("c-%d" % n, "x" * size).result == OK
    return client


def _reclaim_scenario(root, cls=None):
    """회전 4 이상 · journal.1 = 닫힌 work 만 · 미처리 U1 = journal.2 — ⓑ·ⓒ 대조 고정 입력."""
    node, queue = _d(root, cls=cls), ["W1", "W2", "W3", "W4", "W5", "W6", "W7", "W8"]
    rs = node.rs
    assert rs.submit("card-w1", "x" * 60, work="W1").result == OK
    while not rs.journal.closed():                       # 회전 1회까지 닫힌 work 만 쌓는다
        _close(node, queue.pop(0))
    assert node.assign("U1", "h9", evidence=EV).result == OK
    assert node.deliver("U1", "a1").result == OK          # 전달 의도는 닫고 work 는 열어 둔다(회수 금지)
    assert rs.submit("card-u1", "x" * 60, work="U1").result == OK
    while len(rs.journal.closed()) < 4:
        _close(node, queue.pop(0))
    return node


def _rotation_failures(node):
    """ⓐ — 회전 4 이상 · seq 1..N 무결 · 닫힌 segment 뒤의 접수도 조회된다(M7 자리)."""
    rs, found = _rs(node), []
    if len(rs.journal.closed()) < 4:
        found.append("회전 %d < 4" % len(rs.journal.closed()))
    seqs = [rec["seq"] for rec in rs.records()]
    if seqs != list(range(1, len(seqs) + 1)):
        found.append("seq 무결 위반 %r" % (seqs[:6],))
    for command in ("c-1", "c-2"):
        look = rs.lookup(command)
        if look is None or look.result != OK:
            found.append("조회 실패 %s" % command)
    return found


def _reclaim_failures(node, runs=2):
    """ⓑ — 지운 segment 는 모두 닫힌 work · 미처리 든 segment·본문 보존 · 본문 먼저 · 두 번째 삭제 0."""
    rs, found = _rs(node), []
    segments = {path: rs.journal._records_of(path) for _n, path in rs.journal.closed()}
    done = _state(node).get("done") or {}
    bodies = {rec["body"] for seg in segments.values() for rec in seg if rec.get("kind") == "accept"}
    first = rs.journal.reclaim()
    if first["result"] != RECLAIMED:
        found.append("회수 결과 %r" % (first["result"],))
    if len(segments) < 4:
        found.append("회전 %d < 4" % len(segments))
    if first["reclaimed"] != ["journal.1.jsonl"]:
        found.append("지운 segment %r" % (first["reclaimed"],))
    for name in first["reclaimed"]:
        if os.path.exists(os.path.join(rs.runtime, name)):
            found.append("남은 segment %s" % name)
        for rec in segments.get(os.path.join(rs.runtime, name)) or [{"work": None}]:
            if rec.get("work") not in done:
                found.append("열린 work 를 회수: %r" % (rec.get("work"),))
    kept = {rec["body"] for rec in rs.records() if rec.get("kind") == "accept"}
    if "bodies/card-u1.body" not in kept:
        found.append("미처리 본문 유실")
    for body in bodies - kept:
        if os.path.exists(os.path.join(rs.runtime, body)):
            found.append("회수한 본문 잔여 %s" % body)
    ops = _ops(node)
    if "body_unlink" in ops and "seg_unlink" in ops and ops.index("seg_unlink") < ops.index("body_unlink"):
        found.append("삭제 순서 위반(segment 먼저)")
    usage, files = _usage(node), _files(node)
    for _ in range(max(0, runs - 1)):
        again = rs.journal.reclaim()
        if again["reclaimed"] or _usage(node) != usage:
            found.append("재실행 삭제 %r" % (again["reclaimed"],))
        if files != _files(node):
            found.append("재실행 파일 변화")
    return found


def _strip(value):
    """대조용 정규화 — 시각(at)은 사건 시각이라 값 대조에서 뺀다(구조·횟수만 본다)."""
    if isinstance(value, dict):
        return {key: _strip(item) for key, item in value.items() if key != "at"}
    return [_strip(item) for item in value] if isinstance(value, list) else value


def _contrast(node):
    """보정 R1 회수 전후 대조 6항 — ⓐ 9칸·revision ⓑ lookup ⓒ 재submit 낱말 ⓓ 재assign ⓔ recover ⓕ claim gen."""
    rs, state = _rs(node), _state(node)
    return {"nine": _strip({name: state.get(name) for name in journal.PROJ_FIELDS}),
            "revision": state["revision"], "lookup": (rs.lookup("card-u1") or (None,)).result
            if rs.lookup("card-u1") else None, "resubmit": rs.submit("card-u1", "x" * 40).result,
            "assign": node.assign("W1", "h7", evidence=EV).reason, "recover": node.recover(),
            "claim": node.ex._claim_plan(state, rs.records(), "U1", "h1")[0]}


def _crash_run(root, kind, step, size=300):
    return subprocess.run([sys.executable, os.path.abspath(__file__), str(root), kind, step, str(size)],
                          env=CHILD_ENV, capture_output=True, timeout=25)


def _child_main(argv):
    root, kind, step = argv[0], argv[1], argv[2]

    def hook(point):
        if point == step:
            os._exit(9)

    if kind == "reclaim":
        _d(root, on_step=hook).rs.journal.reclaim()
        return 0
    if kind == "submit":
        _i(root, capacity=1000, on_step=hook).submit("crash-1", "x" * int(argv[3]))
        return 0
    return 2


def _fill(node, body=6000):
    """큰 본문으로 채운다 — 남은 여유는 «여유 + 100» 본문 판정으로 확인한다(ⓓ)."""
    rs, n = _rs(node), 0
    while rs.submit("p-%d" % n, "x" * body).result == OK:
        n += 1
        if n > 200:
            break
    return n


def _room(node):
    return _rs(node).journal._limit() - _usage(node)


def test_a_rotation_keeps_one_order_and_reads_single_file_runtime(tmp_path):
    client = _rotate_scenario(tmp_path / "a")
    assert _rotation_failures(client) == []
    assert [n for n, _p in client.journal.closed()] == list(range(1, len(client.journal.closed()) + 1))
    legacy = tmp_path / "legacy" / ".fable-team" / "teams" / TEAM / "runtime"
    legacy.mkdir(parents=True)
    rec = record.build(TEAM, 1, "old-1", "old-1#a1", "2026-11-10T00:00:00", "bodies/old-1.body")
    with open(legacy / "journal.jsonl", "w", encoding="utf-8") as handle:
        handle.write(json.dumps(rec, ensure_ascii=False, sort_keys=True) + "\n")
    assert [r["command"] for r in _i(tmp_path / "legacy").records()] == ["old-1"]


def test_b_reclaim_closed_segments_only_bodies_first_and_idempotent(tmp_path):
    node = _reclaim_scenario(tmp_path / "b")
    assert _reclaim_failures(node) == []


def test_b2_last_seq_segment_is_never_reclaimed(tmp_path):
    """R1 ⑤ — 열린 work 가 없어도 마지막 seq 를 담은 segment 는 남는다(seq 되감김 0 · M9)."""
    node = _d(tmp_path / "b2")
    for work in ("W1", "W2", "W3", "W4", "W5"):
        _close(node, work)
    top, bounds = node.rs.records()[-1]["seq"], node.rs.journal.closed()
    first = node.rs.journal.reclaim()
    assert first["result"] == RECLAIMED and len(first["reclaimed"]) == len(bounds) - 1
    assert len(node.rs.journal.closed()) == 1                        # 마지막 segment 는 남는다
    assert node.rs.records()[-1]["seq"] == top                       # seq 되감김 0


def test_c_reclaim_crash_resume_is_idempotent(tmp_path):
    """ⓒ — K1(본문 삭제 뒤)·K2(첫 segment 삭제 직후) SIGKILL → base + suffix 복원 · 재실행 삭제 0."""
    ref = _reclaim_scenario(tmp_path / "ref")
    before = _contrast(ref)
    ref.rs.journal.reclaim()
    assert _contrast(ref) == before                                  # 회수 전후 대조 6항이 같다
    for step, name in (("reclaim_after_bodies", "K1"), ("reclaim_after_seg", "K2")):
        root = tmp_path / step
        _reclaim_scenario(root)
        assert _crash_run(root, "reclaim", step).returncode == 9, name
        node = _d(root)
        assert _contrast(node) == before, name                       # 복원 = 크래시 전 상태
        assert [rec["work"] for rec in node.rs.records() if rec.get("work") == "U1"], name
        first = node.rs.journal.reclaim()["reclaimed"]                 # K1 = segment 삭제 전(남은 회수)
        assert first == (["journal.1.jsonl"] if step == "reclaim_after_bodies" else []), name
        assert node.rs.journal.reclaim()["reclaimed"] == [], name      # 두 번째 삭제 0


def _saturation_failures(node):
    """ⓓ — 포화면 «용량 부족»·written False·쓰기 0 · 여유보다 큰 본문도 쓰기 0 · 지워서 자리 0."""
    rs, found, files = _rs(node), [], _files(node)
    over = rs.submit("over-1", "x" * (_room(node) + 100))    # 여유보다 큰 본문 = 쓰기 0
    if (over.result, over.written) != (FULL, False):
        found.append("포화 응답 %r/%r" % (over.result, over.written))
    if _files(node) != files:
        found.append("포화인데 파일 변화")
    huge = rs.submit("over-2", "x" * rs.journal.total_cap)
    if (huge.result, huge.written) != (FULL, False):
        found.append("큰 본문 응답 %r/%r" % (huge.result, huge.written))
    if any(_files(node).get(name, 0) < size for name, size in files.items()):
        found.append("지워서 자리를 만들었다")
    return found


def test_d_full_refuses_then_recovers_inside_reserve(tmp_path):
    node = _d(tmp_path / "d", capacity=1000)
    assert _fill(node) >= 3
    assert _saturation_failures(node) == []
    pending = list(_state(node)["pending"])
    body = max(10, _room(node) // 3)                       # 여유 안에서 state tmp 경계 크래시
    assert _crash_run(tmp_path / "d", "submit", "state_tmp_written", body).returncode == 9
    crashed = _d(tmp_path / "d", capacity=1000)
    probe = "x" * (_room(crashed) + 100)                                       # 여유보다 큰 본문
    assert crashed.rs.submit("probe-1", probe).result == CORRUPT               # 복구 필요 중 접수 0
    before, reserve = _files(crashed), node.rs.journal.reserve_bytes
    out = crashed.rs.journal.recover()
    written = sum(max(0, size - before.get(name, 0)) for name, size in _files(crashed).items())
    assert (out["result"], out["written"], written <= reserve) == (OK, True, True)
    assert not os.path.exists(os.path.join(crashed.rs.journal.tmp_path, "state.json.tmp"))
    assert _state(crashed)["pending"] == pending                              # 미처리 보존
    assert crashed.rs.lookup("p-0").result == OK                              # 영수 보존
    assert crashed.rs.submit("probe-2", probe).result == FULL                  # 복구 뒤에도 성공 0
    assert _ops(crashed).count("body_unlink") == 0 and "reclaim_checkpoint" not in _ops(crashed)


def test_e_append_boundary_peak_and_words(tmp_path):
    """ⓔ — 세 writer 모두 첫 쓰기 전 판정 · 정지점 peak < 총 cap · 거절 낱말 «용량 부족»."""
    samples = []
    node = _d(tmp_path / "e", capacity=1000,
              on_step=lambda step: samples.append((step, _usage(node), _files(node))))
    rs = node.rs
    assert node.assign("W1", "h1", evidence=EV, resources=["R1"]).result == OK
    assert node.deliver("W1", "a1").result == OK
    while rs.submit("q-%d" % len(samples), "x" * 5000).result == OK:
        if len(samples) > 400:
            break
    journal_rows, files, total = len(rs.records()), _files(node), rs.journal.total_cap
    refused = node.complete("W1", "a1")                            # k=2 합산 예약 = 첫 쓰기 전 거절
    assert refused.result == FULL and len(rs.records()) == journal_rows and _files(node) == files
    claims = [node.ex.claim("Q%d" % n, "h") for n in range(40)]     # 예약을 소진하면 k=1 도 거절
    assert claims[-1].result == FULL
    assert len(rs.records()) == journal_rows + len([g for g in claims if g.result == OK])   # 거절 = 쓰기 0
    assert all(_files(node).get(name, 0) >= size for name, size in files.items()
               if name != "journal.jsonl" and not name.startswith("tmp/"))   # 줄거나 사라진 파일 0
    usages = [usage for _step, usage, _files_at in samples]
    assert usages and max(usages) <= total - 1                       # 정지점 공존 peak < 총 cap
    assert all(_files(node).get(name, 0) >= size for _step, _u, at in samples
               for name, size in at.items() if name != "journal.jsonl" and not name.startswith("tmp/"))


def _case_word(name):
    with open(os.path.join(CASES, name), encoding="utf-8") as handle:
        return json.load(handle)["expect"]["처리 결과"]


def test_f_case_words_replay(tmp_path):
    """ⓕ — 4사례 결과 낱말이 계약 expect.처리 결과와 같다(회수 결과·복구 필요·용량 부족·접수 성공)."""
    names = sorted(n for n in os.listdir(CASES) if n.endswith(".json") and not n.startswith("_"))
    reclaimed = _rs(_reclaim_scenario(tmp_path / "f1")).journal.reclaim()["result"]
    _i(tmp_path / "f2").submit("card-1", "x" * 60)
    _crash_run(tmp_path / "f2", "submit", "state_tmp_written")       # K0 = state tmp 크래시
    crashed = _i(tmp_path / "f2").submit("after", "x" * 100).result   # «복구 필요»
    full = _i(tmp_path / "f3", capacity=1)
    full.submit("p-1", "x" * 10)
    assert [reclaimed, crashed, full.submit("p-2", "x" * 10).result,
            _i(tmp_path / "f4").submit("p-1", "x" * 10).result] == [_case_word(name) for name in names]


def test_g_public_faces_and_legacy_guard(tmp_path):
    assert intake.Receipt._fields == ("result", "command", "attempt", "revision", "written", "body_ref", "reason")
    assert tuple(inspect.signature(intake.Intake.submit).parameters) == ("self", "command", "body", "work")
    assert tuple(inspect.signature(intake.Intake.lookup).parameters) == ("self", "command")
    assert execution.Grant._fields == ("result", "work", "gen", "holder", "revision", "written", "stage",
                                       "confirm_by", "reason")
    assert dispatch.Grant._fields == ("result", "work", "stage", "attempt", "gen", "holder", "revision",
                                      "written", "released", "reason")
    assert (record.SCHEMA_VERSION, len(record.RESULT_WORDS), len(record.KINDS)) == (1, 8, 11)
    assert subprocess.run([sys.executable, "-I", GUARD], capture_output=True, timeout=25).returncode == 0
    suite = [os.path.join(HERE, name) for name in ("test_core_intake.py", "test_core_execution.py",
                                                   "test_core_dispatch.py")]
    done = subprocess.run([sys.executable, "-m", "pytest", "-q"] + suite, capture_output=True, timeout=60)
    assert done.returncode == 0, done.stdout.decode("utf-8", "replace")[-600:]


def test_r2_1_complete_second_append_refused_writes_nothing(tmp_path):
    """DA probe «complete_second_append_refusal» — k=2 예약이 거절하면 journal·state 변화 0."""
    node = _d(tmp_path / "r21", capacity=1000)
    assert node.assign("W1", "h1", evidence=EV, resources=["R"]).result == OK
    assert node.deliver("W1", "a1").result == OK
    rs = node.rs
    while rs.submit("p-%d" % len(rs.records()), "x" * 2000).result == OK:
        if len(rs.records()) > 200:
            break
    rows, files = len(rs.records()), _files(node)
    refused = node.complete("W1", "a1")
    assert (refused.result, refused.written) == (FULL, False)
    assert len(rs.records()) == rows and _files(node) == files
    fresh = _state(node)
    assert "W1" not in (fresh.get("done") or {}) and (fresh.get("reservations") or {}).get("R")


def test_r2_2_refusal_word_and_written_match_durable(tmp_path):
    """DA probe — (낱말, written) 이 이 호출의 journal 줄 수 변화와 일치한다."""
    node = _swap_journal(_d(tmp_path / "r22"), _StateOverflow)
    assert node.assign("W1", "h1", evidence=EV).result == OK
    rows, out = len(node.rs.records()), node.complete("W1", "a1")
    assert (out.result, out.written) == (HOLD, True) and len(node.rs.records()) == rows + 1
    node.rs.journal.total_cap = _usage(node) + 10             # 앞경우: 예약 판정 거절 = journal 0줄
    rows2 = len(node.rs.records())
    refused = node.ex.start("W1", "h1", 1)
    assert (refused.result, refused.written) == (FULL, False) and len(node.rs.records()) == rows2


def test_r2_3_recover_capacity_vs_busy_words(tmp_path):
    """DA probe «recover_refusal» — BUSY(잠금) · «용량 부족»(예약) · «복구 필요»(판독 불가)를 가른다."""
    node = _d(tmp_path / "r23")
    assert node.assign("W1", "h1", evidence=EV).result == OK
    assert node.recover() == {"delivered": ["a1"], "reassessed": []}      # 성공 모양 = ⓖ 기존 시험 그대로
    handle = open(node.rs.journal.lock_path, "a+", encoding="utf-8")
    fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    try:
        assert node.recover()["result"] == BUSY
    finally:
        fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
        handle.close()
    node.rs.journal.total_cap = _usage(node) + 10                 # 내부 한계 소진 = 예약 거절
    assert node.recover()["result"] == FULL
    node.rs.journal.total_cap = CAPS["total_cap"]
    with open(os.path.join(node.rs.runtime, "journal.jsonl"), "a", encoding="utf-8") as broken:
        broken.write("{broken\n")
    assert node.recover()["result"] == CORRUPT


class _ClosedAlways(journal.Journal):  # M1: 미처리 든 segment 도 회수
    _segment_closed = lambda self, seg, records, state: True  # noqa: E731


class _SegmentFirst(journal.Journal):  # M2: segment 먼저 · 본문 나중 삭제
    def _unlink(self, rel, op):
        if op == "body_unlink":
            self._held = getattr(self, "_held", []) + [rel]
            return
        super()._unlink(rel, op)
        for name in getattr(self, "_held", []):
            journal.Journal._unlink(self, name, "body_unlink")
        self._held = []


class _GhostClosed(journal.Journal):  # M3: 이미 지운 segment 를 다시 지우려다 오류
    def closed(self):
        real = super().closed()
        top, known = (real[-1][0] if real else 0), {n for n, _p in real}
        ghosts = [(n, os.path.join(self.runtime, "journal.%d.jsonl" % n))
                  for n in range(1, top) if n not in known]
        return sorted(real + ghosts)

    def _drop(self, path):
        os.unlink(path)
        self.ops("seg_unlink")
        return True


class _LateCap(journal.Journal):  # M6: cap 판정을 append «뒤» 로
    def _write_line(self, rec):
        super()._write_line(rec)
        self._reserve_line(rec, self.envelope)


class _NoLastKeep(journal.Journal):  # M9: 마지막 seq segment 도 회수
    _keep_last = lambda self, top, last: False  # noqa: E731


class _BodyFree(journal.Journal):  # M11: 새 접수 필요량에서 본문 byte 를 뺀다
    def admits_submit(self, body, rec, envelope):
        needed = journal.line_bytes(rec) + envelope + journal.ops_bytes(journal.SUBMIT_OPS)
        return self.usage() + needed <= self._limit()


class _NoWord(journal.Journal):  # M12: 거절 예외에서 낱말 칸을 뺀다(= «복구 필요» 로 보인다)
    def _reserve_line(self, rec, envelope):
        raise self.rec.CorruptStateError(FULL)


class _StateOverflow(journal.Journal):  # R2-② 뒷경우: 두 번째 호출 = journal 줄은 이미 내구화
    def write_state(self, state):
        self._writes = getattr(self, "_writes", 0) + 1
        if self._writes > 1:
            raise self.rec.WriterRefused(HOLD, "state 실측 초과", written=True)
        super().write_state(state)


def test_mutation_m1_reclaim_open_segment(tmp_path):
    assert _reclaim_failures(_swap_journal(_reclaim_scenario(tmp_path / "m1"), _ClosedAlways)) != []


def test_mutation_m2_segment_before_bodies(tmp_path):
    assert _reclaim_failures(_swap_journal(_reclaim_scenario(tmp_path / "m2"), _SegmentFirst)) != []


def test_mutation_m3_redrop_deleted_segment(tmp_path):
    try:
        found = _reclaim_failures(_swap_journal(_reclaim_scenario(tmp_path / "m3"), _GhostClosed))
    except OSError as exc:
        found = ["회수 재실행 오류: %s" % exc]
    assert found != []


def test_mutation_m4_make_room_when_full(tmp_path):
    node = _d(tmp_path / "m4", capacity=1000)
    assert _fill(node) >= 3
    node.rs.journal.admits_submit = lambda *args: True
    assert _saturation_failures(node) != []


def test_mutation_m5_submit_while_recovery_needed(tmp_path):
    _i(tmp_path / "m5").submit("card-1", "x" * 60)
    assert _crash_run(tmp_path / "m5", "submit", "state_tmp_written").returncode == 9
    mutated = _i(tmp_path / "m5")
    mutated._state = lambda: {"schema": 1, "revision": 0, "pending": [], "attempts": {}, "journal_base": {}}
    assert mutated.submit("card-2", "x" * 60).result == OK      # 변이 = «복구 필요» 를 건너뛴다


def test_mutation_m6_cap_after_append(tmp_path):
    node = _swap_journal(_d(tmp_path / "m6", capacity=1000), _LateCap)
    assert _fill(node) >= 3
    rows = len(node.rs.records())
    claims = [node.ex.claim("Q%d" % n, "h") for n in range(40)]
    ok = len([grant for grant in claims if grant.result == OK])
    assert claims[-1].result == FULL
    assert len(node.rs.records()) == rows + ok + 1     # 변이 = 거절인데 줄이 하나 더 있다


def test_mutation_m7_records_active_only(tmp_path):
    client = _i(tmp_path / "m7", capacity=100)
    for n in range(1, 13):
        assert client.submit("c-%d" % n, "x" * 300).result == OK
    client.records = lambda: client.journal._records_of(client.journal.active_path)
    assert _rotation_failures(client) != []


def test_mutation_m8_recover_state_ignores_base(tmp_path):
    node = _reclaim_scenario(tmp_path / "m8")
    before = _contrast(node)
    node.rs.journal.reclaim()
    node.rs.journal.rec = _NoBase(node.rs.journal.rec)
    assert _contrast(node) != before


def test_mutation_m9_reclaim_last_segment(tmp_path):
    """열린 work 가 없는 runtime = 유일한 보호가 «마지막 seq segment 보존» 뿐이다."""
    node = _d(tmp_path / "m9")
    for work in ("W1", "W2", "W3", "W4", "W5"):
        _close(node, work)
    node = _swap_journal(node, _NoLastKeep)
    top = node.rs.records()[-1]["seq"]
    out = node.rs.journal.reclaim()
    assert out["reclaimed"] and top > 0
    assert not node.rs.records() or node.rs.records()[-1]["seq"] < top   # 변이 = seq 되감김


def test_mutation_m10_receipt_not_read_from_base(tmp_path):
    node = _reclaim_scenario(tmp_path / "m10")
    node.rs.journal.reclaim()
    before = node.rs.lookup("card-w1")
    assert before is not None and before.result == OK                    # 영수 = base 에서 읽힌다
    node.rs._prior_receipt = lambda records, command: next(
        (rec for rec in reversed(records) if rec["command"] == command and rec["kind"] == "accept"), None)
    again = node.rs.submit("card-w1", "x" * 40)
    assert (again.result, again.written) == (OK, True)                   # 변이 = 같은 command 재접수


def test_mutation_m11_submit_needed_without_body(tmp_path):
    node = _d(tmp_path / "m11", capacity=1000)
    assert _fill(node) >= 3
    assert _saturation_failures(_swap_journal(node, _BodyFree)) != []


def test_mutation_m12_refusal_word_without_field(tmp_path):
    node = _swap_journal(_d(tmp_path / "m12"), _NoWord)
    assert node.ex.claim("W1", "h1").result == CORRUPT


class _NoBase:  # M8: recover_state 가 journal_base 를 무시
    def __init__(self, rec):
        self._rec = rec

    def __getattr__(self, name):
        return getattr(self._rec, name)

    def recover_state(self, state, records):
        return self._rec.recover_state(dict(state, journal_base={}), records)


if __name__ == "__main__":
    if os.environ.get("FT2_JOURNAL_CAP_CHILD") != "1":
        sys.exit(0)
    sys.exit(_child_main(sys.argv[1:]))
