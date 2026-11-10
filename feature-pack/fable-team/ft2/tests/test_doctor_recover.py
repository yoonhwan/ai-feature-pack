"""ft2 doctor 복구·재검증·기억 환류 시험 (r1612 · PR④ 둘째 장).

카드 사례 ⓐ~ⓖ 를 그대로 시험한다 — ⓐ 진단 보고가 계약 8필드로 통과(work·holder·revision 근거) ·
ⓑ 복구는 `cli recover` 1회뿐(그 밖의 쓰기 0 · core 는 report 만 import) · ⓒ 복구 뒤 holder 가 놓이면
`done=true` + revision, 아니면 `done=false` + `unresolved.open=true` + owner · ⓓ 판독 불가는
`undetermined` + 사유 · 복구 0 · 보고는 냄 · ⓔ 보고 1개당 기억 1줄 + 다음 진단이 그 줄을 evidence 로
참조(파일 없음 = 이전 0 · 오류 아님) · ⓕ holder 가 살아 있으면 증상 0 · 쓰기 0 · ⓖ 1.x 의존 0 ·
legacy_guard rc0 · 외부 호출 1회 7초 · 제품 ≤150줄.
변이 M1(재검증 생략하고 done=true)·M2(판정불가에서도 복구)·M3(기억 줄 쓰기 빼기)을 이 시험이 실제로
잡는지 본다. 격리 tmp 루트·좌석 목록은 시험 인자로만 준다 — 실 runtime·실 tmux·press 0.
"""
import ast
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys
from pathlib import Path

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORE, DOCTOR = os.path.join(FT2, "core"), os.path.join(FT2, "doctor")
CLI, RECOVER = os.path.join(CORE, "cli.py"), os.path.join(DOCTOR, "recover.py")
GUARD = os.path.join(FT2, "tools", "legacy_guard.py")
SCHEMA = os.path.join(FT2, "contracts", "doctor", "doctor-io.schema.json")
TEAM, NOW, SHA, EV, OWNER = "harness", "2026-11-11T02:00:00", "b" * 40, "v1,v2", "desk"
ENV = dict(os.environ, FT_NOW=NOW)
OK, SYMPTOM = "접수 성공", "seat.absent.holding"
MEMORY = ".fable-team/teams/harness/doctor/memory.jsonl"
CANON = ("symptom_key", "install_sha", "state_revision", "evidence",
         "observation", "allowed_recovery", "reverified", "unresolved")


def _cli(root, *args):
    """CLI 1회 = 동사 1개 — stdout JSON 1줄, rc 는 계약값 그대로."""
    done = subprocess.run([sys.executable, CLI] + list(args) + ["--root", str(root), "--team", TEAM],
                          cwd=FT2, env=ENV, capture_output=True, text=True, timeout=25)
    assert "Traceback" not in done.stderr, done.stderr
    return json.loads(done.stdout), done.returncode


def _ok(root, *args):
    out, rc = _cli(root, *args)
    assert (out["result"], rc) == (OK, 0), (args, out, rc)
    return out


def _project(root):
    return _ok(root, "project")


def _held(root, work="W1", holder="seatA"):
    """카드 ⓐ 의 사슬 — claim·start 까지 간 일 1건(실행권을 쥔 채로 둔다)."""
    _ok(root, "submit", "--command", "c-" + work, "--body", "본문-" + work, "--work", work)
    _ok(root, "assign", "--work", work, "--holder", holder, "--evidence", EV)
    _ok(root, "deliver", "--work", work)
    gen = str(_ok(root, "claim", "--work", work, "--holder", holder)["gen"])
    _ok(root, "start", "--work", work, "--holder", holder, "--gen", gen)


def _doctor(root, *args):
    """doctor 1회 — 살아 있는 좌석 목록은 인자로만 준다(실 tmux 조회 0)."""
    done = subprocess.run([sys.executable, RECOVER, "--root", str(root), "--team", TEAM,
                           "--install-sha", SHA, "--owner", OWNER] + list(args),
                          cwd=FT2, env=ENV, capture_output=True, text=True, timeout=25)
    assert "Traceback" not in done.stderr, done.stderr
    return json.loads(done.stdout), done.returncode


def _snapshot(root):
    """루트 아래 모든 파일의 sha256 — 쓰기 0·«코어 동사 밖 쓰기 0» 판정용."""
    base = os.path.abspath(str(root))
    paths = [(os.path.relpath(os.path.join(where, name), base), os.path.join(where, name))
             for where, _dirs, names in os.walk(base) for name in names]
    return {rel: hashlib.sha256(open(path, "rb").read()).hexdigest() for rel, path in paths}


def _module(path, alias):
    spec = importlib.util.spec_from_file_location(alias, str(path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _schema(one):
    """계약 검사 — 보고 1개가 8필드 schema 를 통과하는가(위반 목록)."""
    check = _module(os.path.join(DOCTOR, "report.py"), "ft2_doctor_report_schema")
    return check.schema_check.check(one, check.schema_check.read(SCHEMA))


def _corrupt(tmp_path):
    """state 판독 불가 루트 — runtime 은 있는데 state.json 이 깨졌다."""
    runtime = Path(tmp_path, ".fable-team", "teams", TEAM, "runtime")
    runtime.mkdir(parents=True)
    (runtime / "state.json").write_text('{"schema": 1, "revision": 2, ', encoding="utf-8")
    return Path(tmp_path), runtime


def test_a_diagnose_reports_absent_seat_holding(tmp_path):
    """ⓐ — claim·start 한 일의 holder 가 살아 있는 목록에 없으면 관측 보고 1개(근거 work·holder·revision)."""
    root = tmp_path / "a"
    _held(root)
    revision = _project(root)["revision"]
    out, rc = _doctor(root, "--live-seat", "seatB")
    assert (out["result"], rc) == (OK, 0)
    one, = out["reports"]
    assert sorted(one) == sorted(CANON)
    assert one["symptom_key"] == SYMPTOM and one["observation"] == {"verdict": "observed"}
    assert one["state_revision"] == revision and one["install_sha"] == SHA
    assert any("seatA" in row["ref"] for row in one["evidence"])          # holder
    assert any("W1" in row["ref"] for row in one["evidence"])             # work
    assert any("revision=%d" % revision == row["ref"] for row in one["evidence"])
    assert _schema(one) == []


def test_b_recovery_is_one_core_verb_only(tmp_path):
    """ⓑ — allowed_recovery=[cli.recover] · 1회 · 쓰기는 팀 runtime 과 기억 줄 밖으로 나가지 않는다."""
    root = tmp_path / "b"
    _held(root)
    before = _snapshot(root)
    out, _rc = _doctor(root, "--live-seat", "seatB")
    one, = out["reports"]
    assert one["allowed_recovery"] == ["cli.recover"]
    assert out["recovery"] == {"verb": "cli.recover", "calls": 1, "result": OK}
    changed = {name for name in set(before) | set(_snapshot(root))
               if before.get(name) != _snapshot(root).get(name)}
    assert MEMORY in changed and {MEMORY} <= changed                      # 기억 1줄은 남는다
    allowed = {MEMORY} | {".fable-team/teams/%s/runtime/%s" % (TEAM, name)
                          for name in ("state.json", "journal.jsonl", "ops.jsonl", "writer.lock")}
    assert changed <= allowed, changed - allowed                          # 직접 쓰기 0
    source = Path(RECOVER).read_text(encoding="utf-8")
    assert re.findall(r'_load\("([a-z_]+)"', source) == ["report"]        # state 쓰는 모듈 import 0


def test_c_reverify_true_when_holder_released(tmp_path):
    """ⓒ 참 — 복구 뒤 투영에 holder 가 없으면 done=true + evidence_ref(project revision) · 미해결 0."""
    root = tmp_path / "c-true"
    _held(root)
    module = _module(RECOVER, "ft2_doctor_recover_true")
    before = _project(root)
    freed = dict(before, revision=before["revision"] + 1, holders={},
                 works={"W1": {"owner": None, "gen": 2, "deliveries": ["a1"], "done": False,
                               "uncertain": False}})
    calls = []

    def fake(verb, _root, _team):
        calls.append(verb)
        return freed if "recover" in calls else before

    module.run_cli = fake
    out = module.diagnose(str(root), TEAM, ["seatB"], SHA, OWNER)
    one, = out["reports"]
    assert calls == ["project", "recover", "project"]
    assert one["reverified"] == {"done": True,
                                 "evidence_ref": "cli/project revision=%d" % freed["revision"]}
    assert one["unresolved"] == {"open": False} and one["allowed_recovery"] == ["cli.recover"]
    assert _schema(one) == []


def test_c_reverify_false_when_execution_right_stays(tmp_path):
    """ⓒ 거짓 — 실 `cli recover` 는 claim 실행권을 놓지 않는다(전달 의도·재평가만) = 미해결 owner 있다."""
    root = tmp_path / "c-false"
    _held(root)
    out, _rc = _doctor(root, "--live-seat", "seatB")
    one, = out["reports"]
    assert one["reverified"] == {"done": False}
    assert one["unresolved"] == {"open": True, "owner": OWNER}            # 숨기지 않는다
    assert (_project(root)["works"]["W1"]["owner"] or {}).get("holder") == "seatA"
    assert out["recovery"]["calls"] == 1
    assert _schema(one) == []


def test_d_undetermined_keeps_recovery_zero(tmp_path):
    """ⓓ — state 판독 불가 = undetermined + 사유 · 복구 0(코어 동사 0) · 보고는 낸다."""
    root, runtime = _corrupt(tmp_path)
    out, rc = _doctor(root, "--live-seat", "seatA")
    assert (out["result"], rc) == ("복구 필요", 0)
    one, = out["reports"]
    assert one["observation"]["verdict"] == "undetermined" and one["observation"]["reason"]
    assert one["allowed_recovery"] == [] and one["reverified"] == {"done": False}
    assert one["unresolved"]["open"] is True
    assert out["recovery"] == {"verb": "", "calls": 0, "result": ""}
    assert not (runtime / "writer.lock").exists()                        # 복구 0 = 코어 동사 0
    assert _schema(one) == []


def test_e_memory_line_and_previous_reference(tmp_path):
    """ⓔ — 보고 1개 = 기억 1줄 · 같은 증상의 다음 진단이 그 줄을 evidence 로 1개 단다."""
    root = tmp_path / "e"
    _held(root)
    path = Path(root, MEMORY)
    assert not path.exists()                                            # 이전 0 = 오류 아님
    first, _rc = _doctor(root, "--live-seat", "seatB")
    one, = first["reports"]
    assert not [row for row in one["evidence"] if row["source"].endswith("memory.jsonl")]
    line, = path.read_text(encoding="utf-8").splitlines()
    row = json.loads(line)
    assert (row["symptom_key"], row["work"], row["holder"]) == (SYMPTOM, "W1", "seatA")
    assert row["revision"] == one["state_revision"] and row["reverified"] is False
    second, _rc = _doctor(root, "--live-seat", "seatB")
    refs = [row for row in second["reports"][0]["evidence"] if row["source"].endswith("memory.jsonl")]
    assert len(refs) == 1 and refs[0] == {"source": MEMORY, "ref": "line=1"}
    assert len(path.read_text(encoding="utf-8").splitlines()) == 2


def test_f_no_symptom_writes_nothing(tmp_path):
    """ⓕ — holder 가 살아 있으면 증상 0 · 복구 0 · 쓰기 0(기억 줄도 0)."""
    root = tmp_path / "f"
    _held(root)
    before = _snapshot(root)
    out, rc = _doctor(root, "--live-seat", "seatA", "--live-seat", "seatB")
    assert (out["result"], rc) == ("증상 없음", 0)
    assert (out["reports"], out["recovery"]["calls"]) == ([], 0)
    assert _snapshot(root) == before
    assert not Path(root, MEMORY).exists()


def test_g_guard_size_and_timeout(tmp_path):
    """ⓖ — 제품 ≤150줄 · 표준 라이브러리만 · 외부 호출 1회 7초 · legacy_guard rc0."""
    source = Path(RECOVER).read_text(encoding="utf-8")
    assert len(source.splitlines()) <= 150
    assert _module(RECOVER, "ft2_doctor_recover_g").TIMEOUT == 7
    names = set()
    for node in ast.walk(ast.parse(source)):
        if isinstance(node, ast.Import):
            names |= {alias.name.split(".")[0] for alias in node.names}
        elif isinstance(node, ast.ImportFrom):
            names.add((node.module or "").split(".")[0])
    assert names <= {"argparse", "importlib", "json", "os", "subprocess", "sys", "time"}
    done = subprocess.run([sys.executable, "-I", GUARD], capture_output=True, timeout=25)
    assert done.returncode == 0, done.stdout.decode("utf-8", "replace")


def _mutant(tmp_path, old, new, name):
    """제품 1곳만 바꾼 사본 — doctor 폴더에 두어 경로(_HERE)가 정본과 같게 만든다."""
    source = Path(RECOVER).read_text(encoding="utf-8")
    assert old in source, old
    path = Path(DOCTOR, name)
    path.write_text(source.replace(old, new), encoding="utf-8")
    return path


def test_m1_reverify_skipped_makes_c_red(tmp_path):
    """M1 — released 를 True 로 고정하면 실행권이 남았는데 done=true 가 되어 ⓒ 가 빨강."""
    root = tmp_path / "m1"
    _held(root)
    old = '        released = not row.get("done") and not (row.get("owner") or {}).get("holder")'
    mut = _mutant(tmp_path, old, "        released = True", "_recover_m1.py")
    try:
        real, _rc = _doctor(root, "--live-seat", "seatB")
        assert real["reports"][0]["reverified"] == {"done": False}       # 정본 = ⓒ 통과
        out = _module(mut, "ft2_doctor_recover_m1", ).diagnose(str(root), TEAM, ["seatB"], SHA, OWNER)
        assert out["reports"][0]["reverified"]["done"] is True           # 변이 = ⓒ 위반
        assert out["reports"][0]["unresolved"] == {"open": False}
    finally:
        mut.unlink()


def test_m2_recovery_in_undetermined_makes_d_red(tmp_path):
    """M2 — 판정불가에서도 복구를 부르면 코어 동사 흔적(writer.lock)이 남아 ⓓ 가 빨강."""
    root, runtime = _corrupt(tmp_path)
    old = '    if before.get("result") != OK:                       # 판정 불가 = 복구 0 · 보고는 낸다'
    mut = _mutant(tmp_path, old, '    run_cli("recover", root, team)\n' + old, "_recover_m2.py")
    try:
        _doctor(root, "--live-seat", "seatA")
        assert not (runtime / "writer.lock").exists()                    # 정본 = ⓓ 통과
        out = _module(mut, "ft2_doctor_recover_m2").diagnose(str(root), TEAM, ["seatA"], SHA, OWNER)
        assert out["reports"][0]["observation"]["verdict"] == "undetermined"
        assert (runtime / "writer.lock").exists()                        # 변이 = ⓓ 위반(복구 흔적)
    finally:
        mut.unlink()


def test_m3_memory_write_dropped_makes_e_red(tmp_path):
    """M3 — 기억 줄 쓰기를 빼면 memory.jsonl 이 없어 ⓔ 가 빨강."""
    root = tmp_path / "m3"
    _held(root)
    old = '    with open(path, "a", encoding="utf-8") as handle:\n' \
          '        handle.write(json.dumps(line, ensure_ascii=False, sort_keys=True) + "\\n")'
    mut = _mutant(tmp_path, old, "    return line", "_recover_m3.py")
    try:
        _doctor(root, "--live-seat", "seatB")
        path = Path(root, MEMORY)
        assert len(path.read_text(encoding="utf-8").splitlines()) == 1    # 정본 = ⓔ 통과
        path.unlink()
        _module(mut, "ft2_doctor_recover_m3").diagnose(str(root), TEAM, ["seatB"], SHA, OWNER)
        assert not path.exists()                                        # 변이 = ⓔ 위반
    finally:
        mut.unlink()
