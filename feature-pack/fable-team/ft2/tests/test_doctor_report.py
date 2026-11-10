"""ft2 doctor 보고 시험 (r1586 · PR④ 첫 장).

카드 사례 ⓐ~ⓓ 를 그대로 시험한다 — ⓐ 정상 보고가 계약 8필드로 통과 · ⓑ 판독 불가(깨진 state ·
runtime 없음)가 `undetermined` + 사유로 드러남 · ⓒ 미해결 owner·근거·sha 거절(rc1 · stdout 0) ·
ⓓ 쓰기 0(runtime 폴더 목록·크기·mtime 동일 · 1.x guard rc0 · core 는 record 만 import).
변이 M1(CorruptStateError 를 revision 0 + observed 로 삼킴)·M2(owner 검사 빼기)·M3(runtime 없을 때
state 를 새로 씀)을 이 시험이 실제로 잡는지 본다. 격리 tmp 팀 데이터 루트만 쓴다 — 실 runtime 0.
"""
import importlib.util
import json
import os
import re
import subprocess
import sys

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCTOR = os.path.join(FT2, "doctor")
GUARD = os.path.join(FT2, "tools", "legacy_guard.py")
TEAM = "harness"
SHA = "a" * 40
SYMPTOM = "doctor.state.unreadable"
EVIDENCE = [{"source": "runtime/state.json", "ref": "revision=2"}]
CANON = ("symptom_key", "install_sha", "state_revision", "evidence",
         "observation", "allowed_recovery", "reverified", "unresolved")
AUDIO = ("intake", "execution", "dispatch")


def _load(name, folder, alias):
    spec = importlib.util.spec_from_file_location(alias, os.path.join(folder, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


report = _load("report", DOCTOR, "ft2_doctor_report_under_test")
schema_check = _load("schema_check", os.path.join(FT2, "contracts", "doctor"), "ft2_doctor_schema")
SCHEMA = schema_check.read(os.path.join(FT2, "contracts", "doctor", "doctor-io.schema.json"))


def _root(tmp_path, revision=2, raw=None):
    """격리 팀 데이터 루트 1개 — runtime/state.json 만 깐다."""
    runtime = os.path.join(str(tmp_path), ".fable-team", "teams", TEAM, "runtime")
    os.makedirs(runtime, exist_ok=True)
    with open(os.path.join(runtime, "state.json"), "w", encoding="utf-8") as handle:
        handle.write(raw if raw is not None else json.dumps(
            {"schema": 1, "revision": revision, "pending": [], "attempts": {}}))
    return str(tmp_path)


def _snapshot(root):
    """runtime 폴더의 파일 목록·크기·mtime — 쓰기 0 판정용."""
    found = {}
    for where, _dirs, names in os.walk(os.path.join(root, ".fable-team")):
        for name in sorted(names):
            path = os.path.join(where, name)
            stat = os.stat(path)
            found[os.path.relpath(path, root)] = (stat.st_size, stat.st_mtime_ns)
    return found


def test_doctor_report_ok_passes_contract(tmp_path):
    """ⓐ 정상: 8필드 · revision 반영 · observed · 복구 0 · 재검증 false · 계약 통과."""
    root = _root(tmp_path, revision=7)
    done = report.build(root, TEAM, SYMPTOM, SHA, EVIDENCE, "desk")
    assert sorted(done) == sorted(CANON)
    assert done["state_revision"] == 7
    assert done["observation"] == {"verdict": "observed"}
    assert done["allowed_recovery"] == []
    assert done["reverified"]["done"] is False
    assert done["unresolved"] == {"open": True, "owner": "desk"}
    assert schema_check.check(done, SCHEMA) == []
    assert report.main(["--root", root, "--team", TEAM, "--symptom-key", SYMPTOM,
                        "--install-sha", SHA, "--evidence", "runtime/state.json=revision=2",
                        "--owner", "desk"]) == 0


def test_doctor_report_corrupt_state_is_undetermined_with_reason(tmp_path):
    """ⓑ · M1: 깨진 state 와 runtime 없음 = undetermined + 사유 · revision 0 · 보고는 나감."""
    broken = report.build(_root(tmp_path / "broken", raw='{"schema": 1, "revision": 2, '),
                          TEAM, SYMPTOM, SHA, EVIDENCE, "desk")
    assert broken["observation"]["verdict"] == "undetermined"
    assert broken["state_revision"] == 0
    assert "state 판독 불가" in broken["observation"]["reason"]
    assert schema_check.check(broken, SCHEMA) == []
    absent = report.build(str(tmp_path / "absent"), TEAM, SYMPTOM, SHA, EVIDENCE, "desk")
    assert absent["observation"]["verdict"] == "undetermined"
    assert absent["state_revision"] == 0
    assert absent["observation"]["reason"].startswith("runtime 없음")
    assert schema_check.check(absent, SCHEMA) == []


def test_doctor_report_refuses_open_without_owner(tmp_path, capsys):
    """ⓒ · M2: owner 없음·근거 0건·sha 형식 위반 = rc1 + 사유 1줄 · stdout 보고 0."""
    root = _root(tmp_path)
    base = ["--root", root, "--team", TEAM, "--symptom-key", SYMPTOM, "--install-sha", SHA,
            "--evidence", "runtime/state.json=revision=2"]
    assert report.main(base) == 1
    out, err = capsys.readouterr()
    assert out == ""
    assert len(err.strip().splitlines()) == 1 and "미해결 owner" in err
    assert report.main(["--root", root, "--team", TEAM, "--symptom-key", SYMPTOM,
                        "--install-sha", SHA, "--owner", "desk"]) == 1
    out, err = capsys.readouterr()
    assert out == "" and "evidence 0건" in err
    assert report.main(["--root", root, "--team", TEAM, "--symptom-key", SYMPTOM,
                        "--install-sha", "a" * 39, "--evidence", "s=r", "--owner", "desk"]) == 1
    out, err = capsys.readouterr()
    # 입력 검사가 먼저 거절해야 한다 — schema 위반으로 흘러가면 검사가 빠진 것이다(변이 M2).
    assert out == "" and "install_sha" in err and "계약 위반" not in err


def test_doctor_report_writes_nothing(tmp_path):
    """ⓓ · M3: 실행 전후 runtime 동일 · runtime 없음에 새 파일 0 · guard rc0 · core 는 record 만."""
    root = _root(tmp_path)
    before = _snapshot(root)
    report.build(root, TEAM, SYMPTOM, SHA, EVIDENCE, "desk")
    report.build(root, TEAM, SYMPTOM, SHA, EVIDENCE, "desk")
    assert _snapshot(root) == before
    absent = str(tmp_path / "absent")
    assert report.build(absent, TEAM, SYMPTOM, SHA, EVIDENCE, "desk")["state_revision"] == 0
    assert not os.path.exists(os.path.join(absent, ".fable-team"))
    done = subprocess.run([sys.executable, "-I", GUARD], capture_output=True, timeout=25)
    assert done.returncode == 0, done.stdout.decode("utf-8", "replace")
    with open(os.path.join(DOCTOR, "report.py"), encoding="utf-8") as handle:
        source = handle.read()
    assert re.findall(r'_load\("([a-z_]+)"', source) == ["record", "schema_check"]
    assert not [name for name in AUDIO if name in source]
