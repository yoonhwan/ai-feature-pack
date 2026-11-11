"""ft2 package 시험 — ⓐ패키지 꼴 · ⓑ결정성 · ⓒcheck 3사례 · ⓓ판정 불가 · ⓔ덮어쓰기 0 · 크기·stdlib · 변이 M1·M2·M3 을 나눠 맡는다."""
import ast, hashlib, json, shutil, subprocess, sys
from pathlib import Path

FT2 = Path(__file__).resolve().parents[1]
TOOL, VERSION = FT2 / "tools" / "package.py", "2.0.0"
TREE = {"core/loader.py": "print('hi')\n", "contracts/kinds.tsv": "a\tb\n", "tests/test_x.py": "x = 1\n",
        "README.md": "# ft2\n", "docs/guide.md": "# g\n"}
NOISE = {"__pycache__/junk.pyc": b"\0", ".hidden": b"x\n"}
PACKAGE_FILES = ("MANIFEST.json", "PACKAGE.json")


def run(*args, script=TOOL):
    proc = subprocess.run([sys.executable, str(script), *map(str, args)], capture_output=True, text=True, timeout=60)
    return proc.returncode, proc.stdout, proc.stderr


def make_source(root):
    for rel, data in {**{key: text.encode() for key, text in TREE.items()}, **NOISE}.items():
        (root / rel).parent.mkdir(parents=True, exist_ok=True)
        (root / rel).write_bytes(data)
    return root


def built(src, out, version=VERSION):
    rc, stdout, stderr = run("build", src, out, "--version", version)
    return rc, out / f"ft2-{version}", stdout, stderr


def refused(*args, script=TOOL):
    rc, stdout, stderr = run(*args, script=script)
    assert (rc, stdout, stderr.count("판정 불가"), stderr.count("\n"), "Traceback" in stderr) == (2, "", 1, 1, False), (args, rc, stdout, stderr)


def test_a_build_package_shape(tmp_path):
    src, out = make_source(tmp_path / "src"), tmp_path / "out"
    rc, pkg, stdout, stderr = built(src, out)
    doc, info = [json.loads((pkg / name).read_text(encoding="utf-8")) for name in PACKAGE_FILES]
    assert (rc, stderr, stdout.count("\n"), sorted(out.iterdir())) == (0, "", 1, [pkg])
    assert (sorted(info), info["schema"], info["name"], info["version"], info["files"]) == (
        ["files", "manifest_sha256", "name", "schema", "source", "version"], 1, "ft2", VERSION, len(TREE))
    assert info["manifest_sha256"] == hashlib.sha256((pkg / "MANIFEST.json").read_bytes()).hexdigest()
    assert stdout.startswith("PACKAGE ") and f"files={len(TREE)}" in stdout and info["manifest_sha256"] in stdout
    assert sorted(str(path.relative_to(pkg)) for path in pkg.rglob("*") if path.is_file()) == sorted([*TREE, *PACKAGE_FILES])
    assert all(hashlib.sha256((pkg / item["path"]).read_bytes()).hexdigest() == item["sha256"] for item in doc["files"])


def test_b_same_source_same_package(tmp_path):
    src = make_source(tmp_path / "src")
    assert (built(src, tmp_path / "o1")[0], built(src, tmp_path / "o2")[0]) == (0, 0)
    read = [[(tmp_path / side / f"ft2-{VERSION}" / name).read_bytes() for name in PACKAGE_FILES] for side in ("o1", "o2")]
    assert read[0] == read[1]


def test_c_check_same_different_missing_hidden(tmp_path):
    src = make_source(tmp_path / "src")
    _, pkg, _, _ = built(src, tmp_path / "out")
    assert run("check", src, pkg)[:2] == (0, f"SAME {pkg} files={len(TREE)}\n")
    changed, missing, hidden = tmp_path / "changed", tmp_path / "missing", tmp_path / "hidden"
    shutil.copytree(src, changed), shutil.copytree(pkg, missing), shutil.copytree(pkg, hidden)
    (changed / "core/loader.py").write_text("print('HI')\n", encoding="utf-8")
    (missing / "core/loader.py").unlink()
    (hidden / ".env").write_text("k=1\n", encoding="utf-8")
    assert (run("check", changed, pkg)[:2], run("check", src, missing)[:2], run("check", src, hidden)[:2]) == (
        (1, "다름 1\n"), (1, "빠짐 1\n"), (1, "숨은 파일 1\n"))


def test_d_refuse_when_unreadable(tmp_path):
    src = make_source(tmp_path / "src")
    _, pkg, _, _ = built(src, tmp_path / "out")
    broken, nokey = tmp_path / "broken", tmp_path / "nokey"
    shutil.copytree(pkg, broken), shutil.copytree(pkg, nokey)
    (broken / "MANIFEST.json").write_text("{oops", encoding="utf-8")
    info = json.loads((nokey / "PACKAGE.json").read_text(encoding="utf-8"))
    (nokey / "PACKAGE.json").write_text(json.dumps({k: v for k, v in info.items() if k != "files"}), encoding="utf-8")
    for args in ((tmp_path / "nodir", pkg), (src, tmp_path / "nodir"), (src, broken), (src, nokey), (src, pkg / "MANIFEST.json")):
        refused("check", *args)


def test_e_no_overwrite(tmp_path):
    src = make_source(tmp_path / "src")
    _, pkg, _, _ = built(src, tmp_path / "out")
    names = (*PACKAGE_FILES, "core/loader.py")
    before = {name: (pkg / name).read_bytes() for name in names}
    rc, stdout, stderr = run("build", src, tmp_path / "out", "--version", VERSION)
    assert (rc, stdout, stderr.count("판정 불가"), "이미 있음" in stderr, "Traceback" in stderr) == (2, "", 1, True, False)
    assert before == {name: (pkg / name).read_bytes() for name in names}


def test_f_budget_and_stdlib_only():
    source = TOOL.read_text(encoding="utf-8")
    modules = {(node.module if isinstance(node, ast.ImportFrom) else node.names[0].name).split(".")[0]
               for node in ast.walk(ast.parse(source)) if isinstance(node, (ast.Import, ast.ImportFrom))}
    assert (modules, "subprocess" in source, len(source.splitlines()) <= 150) == ({"hashlib", "json", "os", "shutil", "sys", "manifest"}, False, True)


def mutant(tmp_path, name, old, new):
    tools = tmp_path / "tools"
    tools.mkdir(exist_ok=True)
    shutil.copyfile(FT2 / "tools" / "manifest.py", tools / "manifest.py")  # 같은 폴더 import 유지
    source = TOOL.read_text(encoding="utf-8")
    assert old in source, old
    (tools / (name + ".py")).write_text(source.replace(old, new), encoding="utf-8")
    return tools / (name + ".py")


def test_m1_m2_m3_mutants_fail_their_own_case(tmp_path):
    src = make_source(tmp_path / "src")
    _, pkg, _, _ = built(src, tmp_path / "out")
    changed, hidden = tmp_path / "changed", tmp_path / "hidden"
    shutil.copytree(src, changed), shutil.copytree(pkg, hidden)
    (changed / "core/loader.py").write_text("print('HI')\n", encoding="utf-8")
    (hidden / ".env").write_text("k=1\n", encoding="utf-8")
    m1 = mutant(tmp_path, "m1", "if rel not in (MANIFEST_FILE, PACKAGE_FILE) and manifest.skip_entry(rel)", "if False")
    m2 = mutant(tmp_path, "m2", "    fresh = manifest.build(src)", "    fresh = manifest.build(pkg)")
    m3 = mutant(tmp_path, "m3", "    if os.path.exists(dest):", "    if False:")
    assert run("check", src, hidden, script=m1)[:2] == (0, f"SAME {hidden} files={len(TREE)}\n")  # M1 = 숨은 파일 통과
    assert run("check", changed, pkg, script=m2)[:2] != (1, "다름 1\n") == run("check", changed, pkg)[:2]  # M2 = 소스 바뀜 못 봄
    again = run("build", src, tmp_path / "out", "--version", VERSION, script=m3)  # M3 = 덮어쓰기 허용 → «이미 있음» 사라짐
    assert (again[0], "이미 있음" in again[2]) == (2, False) and run("build", src, tmp_path / "out", "--version", VERSION)[0] == 2
