"""ft2 install 시험 — ⓐ설치·숨은 파일 0·MANIFEST 1바이트 · ⓑ대조 다름 = 전환 0 · ⓒ되돌림 · ⓓverify/status · ⓔ루트 밖 무변경 · ⓕ재설치·판정 불가 · 변이 M1~M6."""
import hashlib, json, os, shutil, subprocess, sys  # noqa: E401
from pathlib import Path

FT2 = Path(__file__).resolve().parents[1]
TOOL, MANIFEST_TOOL = FT2 / "tools" / "install.py", FT2 / "tools" / "manifest.py"
os.environ.setdefault("FT2_LLM_GATE", str(FT2.parent / "legacy/1.x/harness/bin/ft_launchd_llm_gate.py"))  # r1838: 변이 사본(tmp/tools)도 같은 판정기 1개를 부른다
SOURCE = {"core/loader.py": "print('hi')\n", "tests/test_x.py": "x = 1\n", "README.md": "# ft2\n"}


def run(*args, script=TOOL, verdict=False):
    proc = subprocess.run([sys.executable, str(script), *map(str, args)], capture_output=True, text=True, timeout=60)
    return ((proc.returncode, proc.stdout, proc.stderr.count("판정 불가"), "Traceback" in proc.stderr) if verdict
            else (proc.returncode, proc.stdout, proc.stderr))


def make_package(root, version, extra=None, drift=False, pad=False, drop=None, broken=False):
    folder = root / f"ft2-{version}"
    shutil.rmtree(folder, ignore_errors=True)  # 앞서 만든 MANIFEST·PACKAGE 가 지문에 섞이지 않게
    for rel, text in {**SOURCE, **(extra or {})}.items():
        (folder / rel).parent.mkdir(parents=True, exist_ok=True)
        (folder / rel).write_text(text, encoding="utf-8")
    rc, stdout, stderr = run("build", folder, script=MANIFEST_TOOL)
    assert rc == 0, stderr
    (folder / "MANIFEST.json").write_text(stdout + ("\n" if pad else ""), encoding="utf-8")  # pad = 바이트만 바뀜
    doc = json.loads(stdout)
    info = {"schema": 1, "name": "ft2", "version": version, "source": doc["source"], "files": doc["count"],  # files = 개수(r1613 꼴)
            "manifest_sha256": hashlib.sha256(stdout.encode()).hexdigest()}
    (folder / "PACKAGE.json").write_text(json.dumps({key: value for key, value in info.items() if key != drop}), encoding="utf-8")
    if broken:  # MANIFEST 항목 필드가 빠짐 = load_manifest 가 None
        (folder / "MANIFEST.json").write_text(json.dumps({"schema": 1, "files": [{"path": "core/loader.py"}]}), encoding="utf-8")
    if drift:  # MANIFEST 를 만든 뒤 소스 1파일을 바꾼다 = «복사 뒤 1파일 다름»
        (folder / "core" / "loader.py").write_text("print('HI')\n", encoding="utf-8")
    return folder


def installed(tmp_path, name, versions=("V1",)):
    (root := tmp_path / name).mkdir()
    assert [(run("install", make_package(tmp_path, version), root)[0], tail(root)) for version in versions] == [(0, v) for v in versions]
    return root


def tail(root):
    return (root / "CURRENT").read_text().strip()


def log_of(root):
    return [json.loads(line) for line in (root / "install-log.jsonl").read_text().splitlines()]


def test_a_b_d_install_switch_mismatch_and_verify(tmp_path):
    root = installed(tmp_path, "abd")
    assert json.loads(run("status", root)[1]) == {"current": "V1", "versions": ["V1"], "last_op": "install"} and run("verify", root)[0] == 0
    for version, kwargs, needle, kept in (("V2", {"extra": {".DS_Store": "x\n"}}, "숨은 파일 1개", 1), ("V3", {"drift": True}, "전환 0", 2), ("V4", {"pad": True}, "바이트 sha", 3), ("V5", {"extra": {"x.pyc": "x\n"}}, "숨은 파일", 4), ("V6", {"extra": {"__pycache__/notes.txt": "n\n", "__pycache__/evil.py": "x = 1\n"}}, "숨은 파일", 5), ("V7", {"extra": {"__pycache__/x.cpython-311.pyc/evil.py": "x = 1\n"}}, "숨은 파일", 6)):
        rc, out, err = run("install", make_package(tmp_path, version, **kwargs), root)
        assert (rc, needle in out, err, tail(root), len(list((root / "versions").glob("*.bad-*"))), (root / "versions" / version).exists()) == (1, True, "", "V1", kept, False)  # rename 만
    assert [(line["op"], line["version"], line["prev"], line["rc"]) for line in log_of(root)] == [("install", "V1", None, 0)] + [("install", v, "V1", 1) for v in ("V2", "V3", "V4", "V5", "V6", "V7")]
    assert log_of(root)[0]["manifest_sha256"] == hashlib.sha256((root / "versions" / "V1" / "MANIFEST.json").read_bytes()).hexdigest()
    assert sorted(entry.name for entry in root.iterdir()) == ["CURRENT", "install-log.jsonl", "versions"]  # tmp 잔여물 0
    assert (not subprocess.run([sys.executable, "-c", f"import sys; sys.path.insert(0, {str(root / 'versions' / 'V1')!r}); import core.loader"]).returncode, run("verify", root)[0], not (root / "versions" / "V1" / "__pycache__" / "e.cpython-311.pyc").mkdir(parents=True), run("verify", root)[0]) == (True, 0, True, 1)  # import 뒤 rc0 · pyc 이름 «폴더» 는 rc1
    (root / "versions" / "V1" / "core" / "loader.py").write_text("print('HI')\n", encoding="utf-8")
    assert run("verify", root)[0] == 1
    (root / "CURRENT").unlink()
    assert run("verify", root, verdict=True) == (2, "", 1, False)


def test_c_e_f_rollback_outside_root_and_unjudgeable(tmp_path):
    root, runtime = installed(tmp_path, "ce", ("V1", "V2")), tmp_path / "runtime"
    (runtime / "state").mkdir(parents=True)
    (runtime / "state" / "seat.json").write_text('{"seat": 1}\n', encoding="utf-8")
    watch = {path.name: path.read_bytes() for path in runtime.rglob("*") if path.is_file()}
    assert not subprocess.run([sys.executable, "-c", f"import sys; sys.path.insert(0, {str(root / 'versions' / 'V1')!r}); import core.loader"]).returncode
    broken = root / "versions" / "V1" / "core" / "loader.py"
    broken.write_text("print('BROKEN')\n", encoding="utf-8")
    assert (run("rollback", root, verdict=True), tail(root)) == ((2, "", 1, False), "V2")
    broken.write_text("print('hi')\n", encoding="utf-8")
    assert (run("rollback", root)[0], tail(root), log_of(root)[-1]["op"]) == (0, "V1", "rollback")
    assert (run("rollback", root, verdict=True), tail(root)) == ((2, "", 1, False), "V1")
    assert {path.name: path.read_bytes() for path in runtime.rglob("*") if path.is_file()} == watch  # 루트 밖 무변경
    assert (run("install", tmp_path / "ft2-V1", root, verdict=True), tail(root)) == ((2, "", 1, False), "V1")  # 같은 판 재설치 = 이미 있음
    for version, text in (("V3", "{oops"), ("V4", None)):
        folder = make_package(tmp_path, version)  # text=None 이면 manifest_sha256 칸을 뺀다
        text = text or json.dumps({key: value for key, value in json.loads((folder / "PACKAGE.json").read_text()).items() if key != "manifest_sha256"})
        (folder / "PACKAGE.json").write_text(text, encoding="utf-8")
        assert run("install", folder, root, verdict=True) == (2, "", 1, False)
    (tmp_path / "notadir").write_text("x\n", encoding="utf-8")  # 루트가 일반 파일이면 쓰기 실패 = 판정 불가
    assert run("install", make_package(tmp_path, "V5"), tmp_path / "notadir", verdict=True) == (2, "", 1, False)
    assert run("install", make_package(tmp_path, "V6", drop="source"), installed(tmp_path, "b2"), verdict=True) == (2, "", 1, False)  # source 칸 빠짐 = rc2
    assert run("install", make_package(tmp_path, "V7", broken=True), installed(tmp_path, "c2"), verdict=True) == (2, "", 1, False)  # MANIFEST 손상 = 복사 전 판정 불가


def mutant(tmp_path, name, old, new):
    tools = tmp_path / "tools"  # 변이는 tools 사본에서만 — install.py 가 이웃 manifest 를 import 한다
    shutil.copytree(FT2 / "tools", tools, dirs_exist_ok=True)
    source = TOOL.read_text(encoding="utf-8")
    assert old in source, (name, old)
    (tools / f"{name}.py").write_text(source.replace(old, new), encoding="utf-8")
    return tools / f"{name}.py"


def test_m1_to_m6_mutants_switch_what_the_cases_forbid(tmp_path):
    cases = (("m1", "    ok, reason = consistent(target)", "    set_current(root, version)\n    ok, reason = consistent(target)"),
             ("m2", "    stray = hidden_files(folder, manifest.load_manifest(man) or {})", "    stray = []"),
             ("m3", "    ok, reason = consistent(folder)", "    ok, reason = True, ''"),
             ("m4", 'if hashlib.sha256(open(man, "rb").read()).hexdigest() != doc["manifest_sha256"]:', "if False:"),
             ("m5", '    os.replace(tmp, os.path.join(root, "CURRENT"))', '    open(os.path.join(root, "CURRENT"), "w", encoding="utf-8").write(version + "\\n")'),
             ("m6", '    if cur is None:\n        return 2, f"판정 불가 {root}: CURRENT 판이 없다"\n', ""),
             ("m7", "        os.replace(target, bad)", "        shutil.rmtree(target)"), ("m8", "        os.replace(target, bad)", "        pass"))
    m = {name: mutant(tmp_path, name, old, new) for name, old, new in cases}
    roots, pair = [installed(tmp_path, name) for name in ("a", "b", "c", "d")], [installed(tmp_path, name, ("V1", "V2")) for name in ("e", "f")]
    drift, hidden, pad = make_package(tmp_path, "V2", drift=True), make_package(tmp_path, "V9", extra={".DS_Store": "x\n"}), make_package(tmp_path, "V10", pad=True)
    assert (run("install", drift, roots[0], script=m["m1"])[0], tail(roots[0])) == (1, "V2")  # M1 이 전환을 먼저 했다
    assert (run("install", hidden, roots[1], script=m["m2"])[0], run("install", hidden, roots[2])[0]) == (0, 1)
    assert (run("install", pad, roots[3], script=m["m4"])[0], run("install", pad, installed(tmp_path, "d2"))[0]) == (0, 1)
    [(root / "versions" / "V1" / "core" / "loader.py").write_text("print('BROKEN')\n", encoding="utf-8") for root in pair]
    assert (run("rollback", pair[0], script=m["m3"])[0], run("rollback", pair[1])[0], tail(pair[0]), tail(pair[1])) == (0, 2, "V1", "V2")
    m5, m6 = installed(tmp_path, "m5"), installed(tmp_path, "m6")
    (m6 / "CURRENT").unlink()
    assert (run("install", make_package(tmp_path, "V20"), m5, script=m["m5"])[0], sorted(entry.name for entry in m5.iterdir())) == (0, ["CURRENT", "CURRENT.tmp", "install-log.jsonl", "versions"])
    assert (run("verify", m6, script=m["m6"], verdict=True)[0], run("verify", m6, verdict=True)[0]) == (1, 2)  # M6 은 traceback 으로 rc1
    assert [(run("install", make_package(tmp_path, v, drift=True), r, script=m[n])[0], sorted(e.name for e in (r / "versions").iterdir())) for n, v, r in (("m7", "V30", installed(tmp_path, "m7")), ("m8", "V31", installed(tmp_path, "m8")))] == [(1, ["V1"]), (1, ["V1", "V31"])]
