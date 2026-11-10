"""ft2 doctor 복구·재검증·기억 환류 시험 (r1612 · PR④ 둘째 장 · 보정 1 = claim --rotation).

카드 사례 ⓐ~ⓖ 를 그대로 시험한다 — ⓐ 진단 보고가 계약 8필드로 통과(work·holder·revision 근거) ·
ⓑ 허용 복구는 `cli.claim --rotation` 1회뿐(그 밖의 쓰기 0 · core 는 report 만 import) ·
ⓒ' 회전 성공 = project 의 그 일 holder 가 `--to` 이고 gen 이 늘면 `reverified.done=true` + revision ·
ⓒ'' 체인에 effect 가 있고 결과가 없으면 claim 이 «완료 유보» = `done=false` + `unresolved.open=true` +
owner · ⓒ''' 새 holder(`--to`)가 없거나 목록 밖이면 복구 0(쓰기 0) · ⓓ 판독 불가는 `undetermined` +
사유 + 복구 0 · 보고는 냄 · ⓔ 보고 1개당 기억 1줄 + 다음 진단이 그 줄을 evidence 로 참조(파일 없음 =
이전 0) · ⓕ holder 가 살아 있으면 증상 0 · 쓰기 0 · ⓖ 1.x 의존 0 · legacy_guard rc0 · 외부 호출 1회
7초 · 제품 ≤150줄. 세 갈래 모두 «실 흐름»(cli submit→assign→deliver→claim→start[→effect]) 이고
가짜 투영은 쓰지 않는다. 변이 M1(재검증 생략 done=true)·M2(판정불가에서도 복구)·M3(기억 줄 쓰기
빼기)·M4(rotation 빼기 → claim 거절 → ⓒ' 빨강)를 이 시험이 실제로 잡는지 본다.
격리 tmp 루트·좌석 목록은 시험 인자로만 준다 — 실 runtime·실 tmux·press 0.
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
TEAM, NOW, SHA, EV, OWNER = "harness", "2026-11-11T03:00:00", "b" * 40, "v1,v2", "desk"
ENV = dict(os.environ, FT_NOW=NOW)
OK, HOLD, SYMPTOM = "접수 성공", "완료 유보", "seat.absent.holding"
RECOVERY = "cli.claim --rotation"
MEMORY = ".fable-team/teams/harness/doctor/memory.jsonl"
RUNTIME = ".fable-team/teams/harness/runtime/"
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
    """카드 ⓐ 의 사슬 — claim·start 까지 간 일 1건(실행권을 쥔 채로 둔다). claim 세대를 돌려준다."""
    _ok(root, "submit", "--command", "c-" + work, "--body", "본문-" + work, "--work", work)
    _ok(root, "assign", "--work", work, "--holder", holder, "--evidence", EV)
    _ok(root, "deliver", "--work", work)
    gen = str(_ok(root, "claim", "--work", work, "--holder", holder)["gen"])
    _ok(root, "start", "--work", work, "--holder", holder, "--gen", gen)
    return int(gen)


def _held_effect(root, work="W1", holder="seatA"):
    """effect 의도까지만 있고 결과가 없는 일 — claim 이 «완료 유보» 로 재실행을 막는 자리(PLAN 213)."""
    gen = _held(root, work, holder)
    _ok(root, "effect", "--work", work, "--holder", holder, "--gen", str(gen), "--effect", "e-" + work)


def _doctor(root, *args):
    """doctor 1회 — 살아 있는 좌석 목록·새 holder 는 인자로만 준다(실 tmux 조회 0)."""
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


def _changed(root, before):
    after = _snapshot(root)
    return {name for name in set(before) | set(after) if before.get(name) != after.get(name)}


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
    """state 판독 불가 루트 — runtime 은 있는데 state.json 이 깨졌다(문면 그대로 유지)."""
    runtime = Path(tmp_path, ".fable-team", "teams", TEAM, "runtime")
    runtime.mkdir(parents=True)
    (runtime / "state.json").write_text('{"schema": 1, "revision": 2, ', encoding="utf-8")
    return Path(tmp_path), runtime


def test_a_diagnose_reports_absent_seat_holding(tmp_path):
    """ⓐ — claim·start 한 일의 holder 가 살아 있는 목록에 없으면 관측 보고 1개(근거 work·holder·revision)."""
    root = tmp_path / "a"
    _held(root)
    revision = _project(root)["revision"]
    out, rc = _doctor(root, "--live-seat", "seatB", "--to", "seatB")
    assert (out["result"], rc) == (OK, 0)
    one, = out["reports"]
    assert sorted(one) == sorted(CANON)
    assert one["symptom_key"] == SYMPTOM and one["observation"] == {"verdict": "observed"}
    assert one["state_revision"] == revision and one["install_sha"] == SHA
    assert any("seatA" in row["ref"] for row in one["evidence"])            # holder
    assert any("W1" in row["ref"] for row in one["evidence"])               # work
    assert any(row["ref"] == "revision=%d" % revision for row in one["evidence"])
    assert _schema(one) == []


def test_b_recovery_is_one_claim_rotation(tmp_path):
    """ⓑ — allowed_recovery=[cli.claim --rotation] · 1회 · 쓰기는 팀 runtime 과 기억 줄 밖으로 안 나간다."""
    root = tmp_path / "b"
    _held(root)
    before = _snapshot(root)
    out, _rc = _doctor(root, "--live-seat", "seatB", "--to", "seatB")
    one, = out["reports"]
    assert one["allowed_recovery"] == [RECOVERY]
    assert out["recovery"] == {"verb": RECOVERY, "calls": 1, "result": OK}
    changed = _changed(root, before)
    assert MEMORY in changed                                                # 기억 1줄은 남는다
    allowed = {MEMORY} | {RUNTIME + name for name in
                          ("state.json", "journal.jsonl", "ops.jsonl", "writer.lock")}
    assert changed <= allowed, changed - allowed                            # 직접 쓰기 0 = 코어 동사만
    source = Path(RECOVER).read_text(encoding="utf-8")
    assert re.findall(r'_load\("([a-z_]+)"', source) == ["report"]          # state 쓰는 모듈 import 0


def test_c_prime_rotation_hands_the_work_to_new_holder(tmp_path):
    """ⓒ' — 회전 성공: project 의 holder 가 --to 이고 gen 이 늘면 done=true + evidence_ref(revision)."""
    root = tmp_path / "c1"
    was = _held(root)
    out, rc = _doctor(root, "--live-seat", "seatB", "--to", "seatB")
    assert (out["result"], rc) == (OK, 0)
    one, = out["reports"]
    project, row = _project(root), _project(root)["works"]["W1"]
    assert (row["owner"] or {})["holder"] == "seatB" and row["gen"] > was   # 실행권이 옮겨졌다
    assert one["reverified"] == {"done": True,
                                 "evidence_ref": "cli/project revision=%d" % project["revision"]}
    assert one["unresolved"] == {"open": False} and one["allowed_recovery"] == [RECOVERY]
    assert one["state_revision"] < project["revision"]                      # 복구 전 revision 을 적는다
    assert _schema(one) == []


def test_c_double_uncertain_keeps_it_open_with_owner(tmp_path):
    """ⓒ'' — effect 뒤 결과 없는 일은 claim 이 «완료 유보»(재실행 0) → done=false + open + owner."""
    root = tmp_path / "c2"
    _held_effect(root)
    out, _rc = _doctor(root, "--live-seat", "seatB", "--to", "seatB")
    one, = out["reports"]
    row = _project(root)["works"]["W1"]
    assert out["recovery"] == {"verb": RECOVERY, "calls": 1, "result": HOLD}
    assert one["reverified"] == {"done": False}
    assert one["unresolved"] == {"open": True, "owner": OWNER}
    assert (row["owner"] or {})["holder"] == "seatA" and row["uncertain"] is True  # 재실행 0
    assert _schema(one) == []


def test_c_triple_no_live_target_keeps_recovery_zero(tmp_path):
    """ⓒ''' — 새 holder 가 없거나 살아 있는 목록 밖이면 복구 0(코어 동사 0 · 기억 1줄만)."""
    root = tmp_path / "c3"
    _held(root)
    before = _snapshot(root)
    out, _rc = _doctor(root, "--live-seat", "seatB")                        # --to 없음
    one, = out["reports"]
    assert out["recovery"] == {"verb": "", "calls": 0, "result": ""}
    assert one["reverified"] == {"done": False}
    assert one["unresolved"] == {"open": True, "owner": OWNER}
    assert _changed(root, before) == {MEMORY}
    outside, _rc = _doctor(root, "--live-seat", "seatB", "--to", "seatC")   # 목록 밖 좌석
    assert outside["recovery"]["calls"] == 0
    assert (_project(root)["works"]["W1"]["owner"] or {})["holder"] == "seatA"


def test_d_undetermined_keeps_recovery_zero(tmp_path):
    """ⓓ — state 판독 불가 = undetermined + 사유 · 복구 0(코어 동사 0) · 보고는 낸다."""
    root, runtime = _corrupt(tmp_path)
    out, rc = _doctor(root, "--live-seat", "seatB", "--to", "seatB")
    assert (out["result"], rc) == ("복구 필요", 0)
    one, = out["reports"]
    assert one["observation"]["verdict"] == "undetermined" and one["observation"]["reason"]
    assert one["allowed_recovery"] == [] and one["reverified"] == {"done": False}
    assert one["unresolved"]["open"] is True
    assert out["recovery"] == {"verb": "", "calls": 0, "result": ""}
    assert not (runtime / "writer.lock").exists()                           # 복구 0 = 코어 동사 0
    assert _schema(one) == []


def test_e_memory_line_and_previous_reference(tmp_path):
    """ⓔ — 보고 1개 = 기억 1줄 · 같은 증상의 다음 진단이 그 줄을 evidence 로 1개 단다."""
    root = tmp_path / "e"
    _held(root)
    path, seen = Path(root, MEMORY), Path(root, MEMORY)
    assert not seen.exists()                                               # 이전 0 = 오류 아님
    first, _rc = _doctor(root, "--live-seat", "seatB")
    one, = first["reports"]
    assert not [row for row in one["evidence"] if row["source"].endswith("memory.jsonl")]
    line, = path.read_text(encoding="utf-8").splitlines()
    row = json.loads(line)
    assert (row["symptom_key"], row["work"], row["holder"]) == (SYMPTOM, "W1", "seatA")
    assert row["revision"] == one["state_revision"] and row["reverified"] is False
    second, _rc = _doctor(root, "--live-seat", "seatB")
    refs = [row for row in second["reports"][0]["evidence"] if row["source"].endswith("memory.jsonl")]
    assert refs == [{"source": MEMORY, "ref": "line=1"}]
    assert len(path.read_text(encoding="utf-8").splitlines()) == 2


def test_f_no_symptom_writes_nothing(tmp_path):
    """ⓕ — holder 가 살아 있으면 증상 0 · 복구 0 · 쓰기 0(기억 줄도 0)."""
    root = tmp_path / "f"
    _held(root)
    before = _snapshot(root)
    out, rc = _doctor(root, "--live-seat", "seatA", "--live-seat", "seatB", "--to", "seatB")
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


def _mutant(old, new, name):
    """제품 1곳만 바꾼 사본 — doctor 폴더에 두어 경로(_HERE·_FT2)가 정본과 같게 만든다."""
    source = Path(RECOVER).read_text(encoding="utf-8")
    assert old in source, old
    path = Path(DOCTOR, name)
    path.write_text(source.replace(old, new), encoding="utf-8")
    return path


def test_m1_reverify_skipped_makes_c_double_red(tmp_path):
    """M1 — released 를 True 로 고정하면 완료 유보인데 done=true 가 되어 ⓒ'' 가 빨강."""
    root = tmp_path / "m1"
    _held_effect(root)
    mut = _mutant("released=rotated, after=after.get", "released=True, after=after.get", "_recover_m1.py")
    try:
        real, _rc = _doctor(root, "--live-seat", "seatB", "--to", "seatB")
        assert real["reports"][0]["reverified"] == {"done": False}          # 정본 = ⓒ'' 통과
        out = _module(mut, "ft2_doctor_recover_m1").diagnose(
            str(root), TEAM, ["seatB"], SHA, OWNER, "seatB")
        assert out["reports"][0]["reverified"]["done"] is True              # 변이 = ⓒ'' 위반
        assert out["reports"][0]["unresolved"] == {"open": False}
    finally:
        mut.unlink()


def test_m2_recovery_in_undetermined_makes_d_red(tmp_path):
    """M2 — 판정불가에서도 복구를 부르면 코어 동사 흔적(writer.lock)이 남아 ⓓ 가 빨강."""
    root, runtime = _corrupt(tmp_path)
    old = '    if before.get("result") != OK:                       # 판정 불가 = 복구 0 · 보고는 낸다'
    mut = _mutant(old, '    run_cli("claim", root, team, "--work", "W1", "--holder", "seatB",\n'
                       '             "--rotation", "1")\n' + old, "_recover_m2.py")
    try:
        _doctor(root, "--live-seat", "seatB", "--to", "seatB")
        assert not (runtime / "writer.lock").exists()                       # 정본 = ⓓ 통과
        out = _module(mut, "ft2_doctor_recover_m2").diagnose(
            str(root), TEAM, ["seatB"], SHA, OWNER, "seatB")
        assert out["reports"][0]["observation"]["verdict"] == "undetermined"
        assert (runtime / "writer.lock").exists()                           # 변이 = ⓓ 위반(복구 흔적)
    finally:
        mut.unlink()


def test_m3_memory_write_dropped_makes_e_red(tmp_path):
    """M3 — 기억 줄 쓰기를 빼면 memory.jsonl 이 없어 ⓔ 가 빨강."""
    root = tmp_path / "m3"
    _held(root)
    old = '    with open(path, "a", encoding="utf-8") as handle:\n' \
          '        handle.write(json.dumps(line, ensure_ascii=False, sort_keys=True) + "\\n")'
    mut = _mutant(old, "    return line", "_recover_m3.py")
    try:
        _doctor(root, "--live-seat", "seatB")
        path = Path(root, MEMORY)
        assert len(path.read_text(encoding="utf-8").splitlines()) == 1       # 정본 = ⓔ 통과
        path.unlink()
        _module(mut, "ft2_doctor_recover_m3").diagnose(str(root), TEAM, ["seatB"], SHA, OWNER)
        assert not path.exists()                                            # 변이 = ⓔ 위반
    finally:
        mut.unlink()


def test_m4_rotation_dropped_makes_c_prime_red(tmp_path):
    """M4 — --rotation 을 빼면 claim 이 «완료 유보» 로 막혀 실행권이 안 옮겨지고 ⓒ' 가 빨강."""
    root = tmp_path / "m4"
    _held(root)
    mut = _mutant('"--rotation", "1")', ")", "_recover_m4.py")
    try:
        real, _rc = _doctor(root, "--live-seat", "seatB", "--to", "seatB")
        assert real["recovery"]["result"] == OK                             # 정본 = ⓒ' 통과
        assert real["reports"][0]["reverified"]["done"] is True
        assert real["reports"][0]["reverified"]["done"] is True
        fresh = tmp_path / "m4b"
        _held(fresh)
        out = _module(mut, "ft2_doctor_recover_m4").diagnose(
            str(fresh), TEAM, ["seatB"], SHA, OWNER, "seatB")
        assert out["recovery"]["result"] == HOLD                            # 변이 = claim 거절
        assert out["reports"][0]["reverified"] == {"done": False}           # 변이 = ⓒ' 위반
        assert out["reports"][0]["unresolved"] == {"open": True, "owner": OWNER}
    finally:
        mut.unlink()
