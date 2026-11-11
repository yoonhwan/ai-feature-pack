"""ft2 install 시험 — ⓐ설치·숨은 파일 0 · ⓑ대조 다름 = 전환 0 · ⓒ되돌림 · ⓓverify/status · ⓔ루트 밖 무변경 · ⓕ재설치·판정 불가 · 변이 M1·M2·M3."""
import hashlib, json, shutil, subprocess, sys
from pathlib import Path

FT2 = Path(__file__).resolve().parents[1]
TOOL, MANIFEST_TOOL = FT2 / "tools" / "install.py", FT2 / "tools" / "manifest.py"
SOURCE = {"core/loader.py": "print('hi')\n", "tests/test_x.py": "x = 1\n", "README.md": "# ft2\n"}


def run(*args, script=TOOL):
    proc = subprocess.run([sys.executable, str(script), *map(str, args)], capture_output=True, text=True, timeout=60)
    return proc.returncode, proc.stdout, proc.stderr


def make_package(root, version, extra=None, drift=False, pad=False):
    folder = root / f"ft2-{version}"
    shutil.rmtree(folder, ignore_errors=True)  # 앞서 만든 MANIFEST·PACKAGE 가 지문에 섞이지 않게
    for rel, text in {**SOURCE, **(extra or {})}.items():
        (folder / rel).parent.mkdir(parents=True, exist_ok=True)
        (folder / rel).write_text(text, encoding="utf-8")
    rc, stdout, stderr = run("build", folder, script=MANIFEST_TOOL)
    assert rc == 0, stderr
    (folder / "MANIFEST.json").write_text(stdout + ("\n" if pad else ""), encoding="utf-8")  # pad = 바이트만 바뀜
    doc = json.loads(stdout)
    (folder / "PACKAGE.json").write_text(json.dumps({"schema": 1, "name": "ft2", "version": version, "source": doc["source"], "files":
        doc["count"], "manifest_sha256": hashlib.sha256(stdout.encode()).hexdigest()}), encoding="utf-8")  # files = 개수(r1613 꼴)
    if drift:  # MANIFEST 를 만든 뒤 소스 1파일을 바꾼다 = «복사 뒤 1파일 다름»
        (folder / "core" / "loader.py").write_text("print('HI')\n", encoding="utf-8")
    return folder


def installed(tmp_path, name, versions=("V1",)):
    root = tmp_path / name
    root.mkdir()
    for version in versions:
        assert (run("install", make_package(tmp_path, version), root)[0], tail(root)) == (0, version)
    return root


def tail(root):
    return (root / "CURRENT").read_text().strip()


def log_of(root):
    return [json.loads(line) for line in (root / "install-log.jsonl").read_text().splitlines()]


def refused(*args, script=TOOL):
    rc, stdout, stderr = run(*args, script=script)
    return (rc, stdout, stderr.count("판정 불가"), "Traceback" in stderr)


def test_a_b_d_install_switch_mismatch_and_verify(tmp_path):
    root = installed(tmp_path, "abd")
    assert json.loads(run("status", root)[1]) == {"current": "V1", "versions": ["V1"], "last_op": "install"} and run("verify", root)[0] == 0
    rc, out, err = run("install", make_package(tmp_path, "V2", extra={".DS_Store": "x\n"}), root)
    assert (rc, "숨은 파일 1개" in out, err, tail(root), len(list((root / "versions").glob("*.bad-*")))) == (1, True, "", "V1", 1)
    rc, out, err = run("install", make_package(tmp_path, "V3", drift=True), root)
    assert (rc, "전환 0" in out, tail(root), len(list((root / "versions").glob("*.bad-*"))), (root / "versions" / "V3").exists()) == (1, True, "V1", 2, False)
    assert (run("install", make_package(tmp_path, "V4", pad=True), root)[0], tail(root)) == (1, "V1")  # MANIFEST 1바이트 바뀜 → 전환 0
    assert [(line["op"], line["version"], line["prev"], line["rc"]) for line in log_of(root)] == [("install", "V1", None, 0)] + [
        ("install", version, "V1", 1) for version in ("V2", "V3", "V4")]
    assert log_of(root)[0]["manifest_sha256"] == hashlib.sha256((root / "versions" / "V1" / "MANIFEST.json").read_bytes()).hexdigest()
    (root / "versions" / "V1" / "core" / "loader.py").write_text("print('HI')\n", encoding="utf-8")
    assert run("verify", root)[0] == 1
    assert len(TOOL.read_text(encoding="utf-8").splitlines()) <= 160  # 카드 크기 한도


def test_c_e_rollback_and_nothing_outside_the_root(tmp_path):
    root, runtime = installed(tmp_path, "ce", ("V1", "V2")), tmp_path / "runtime"
    (runtime / "state").mkdir(parents=True)
    (runtime / "state" / "seat.json").write_text('{"seat": 1}\n', encoding="utf-8")
    watch = {path.name: path.read_bytes() for path in runtime.rglob("*") if path.is_file()}
    broken = root / "versions" / "V1" / "core" / "loader.py"
    broken.write_text("print('BROKEN')\n", encoding="utf-8")
    assert (refused("rollback", root), tail(root)) == ((2, "", 1, False), "V2")
    broken.write_text("print('hi')\n", encoding="utf-8")
    assert (run("rollback", root)[0], tail(root), log_of(root)[-1]["op"]) == (0, "V1", "rollback")
    assert (refused("rollback", root), tail(root)) == ((2, "", 1, False), "V1")
    assert {path.name: path.read_bytes() for path in runtime.rglob("*") if path.is_file()} == watch  # 루트 밖 무변경


def test_f_reinstall_and_unjudgeable_are_one_line(tmp_path):
    root, package = installed(tmp_path, "f"), tmp_path / "ft2-V1"
    assert (refused("install", package, root), tail(root)) == ((2, "", 1, False), "V1")
    for version, text in (("V3", "{oops"), ("V4", None)):
        folder = make_package(tmp_path, version)  # text=None 이면 manifest_sha256 칸을 뺀다
        text = text or json.dumps({key: value for key, value in json.loads((folder / "PACKAGE.json").read_text()).items() if key != "manifest_sha256"})
        (folder / "PACKAGE.json").write_text(text, encoding="utf-8")
        assert refused("install", folder, root) == (2, "", 1, False)
    (tmp_path / "notadir").write_text("x\n", encoding="utf-8")  # 루트가 일반 파일이면 쓰기 실패 = 판정 불가
    assert refused("install", make_package(tmp_path, "V5"), tmp_path / "notadir") == (2, "", 1, False)
    assert (tail(root), sorted(entry.name for entry in (root / "versions").iterdir())) == ("V1", ["V1"])


def mutant(tmp_path, name, old, new):
    tools = tmp_path / "tools"  # 변이는 tools 사본에서만 — install.py 가 이웃 manifest 를 import 한다
    shutil.copytree(FT2 / "tools", tools, dirs_exist_ok=True)
    source = TOOL.read_text(encoding="utf-8")
    assert old in source, old
    (tools / f"{name}.py").write_text(source.replace(old, new), encoding="utf-8")
    return tools / f"{name}.py"


def test_m1_m2_m3_mutants_switch_what_the_case_forbids(tmp_path):
    m1 = mutant(tmp_path, "m1", "    ok, reason = consistent(target)", "    set_current(root, version)\n    ok, reason = consistent(target)")
    m2 = mutant(tmp_path, "m2", "    stray = hidden_files(folder)", "    stray = []")
    m3 = mutant(tmp_path, "m3", "    ok, reason = consistent(folder)", "    ok, reason = True, ''")
    drift, hidden = make_package(tmp_path, "V2", drift=True), make_package(tmp_path, "V9", extra={".DS_Store": "x\n"})
    roots = [installed(tmp_path, name) for name in ("a", "b", "c", "d", "g", "h")]
    assert (run("install", drift, roots[0], script=m1)[0], tail(roots[0])) == (1, "V2")  # M1 이 전환을 먼저 했다
    assert (run("install", drift, roots[1])[0], tail(roots[1])) == (1, "V1")
    assert (run("install", hidden, roots[2], script=m2)[0], run("install", hidden, roots[3])[0]) == (0, 1)
    pair = [installed(tmp_path, name, ("V1", "V2")) for name in ("e", "f")]
    for root in pair:
        (root / "versions" / "V1" / "core" / "loader.py").write_text("print('BROKEN')\n", encoding="utf-8")
    assert (run("rollback", pair[0], script=m3)[0], run("rollback", pair[1])[0]) == (0, 2)
    assert (tail(pair[0]), tail(pair[1])) == ("V1", "V2")
    m4 = mutant(tmp_path, "m4", 'if hashlib.sha256(open(man, "rb").read()).hexdigest() != doc["manifest_sha256"]:', "if False:")
    assert (run("install", make_package(tmp_path, "V10", pad=True), roots[4], script=m4)[0], run("install", make_package(tmp_path, "V10", pad=True), roots[5])[0]) == (0, 1)
