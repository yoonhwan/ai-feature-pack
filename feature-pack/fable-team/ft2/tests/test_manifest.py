"""ft2 manifest 시험 — ⓐ 결정성·정렬·지문 · ⓑ 제외 규칙 1곳 · ⓒ verify 3목록·rc · ⓓ 실 ft2 트리 · ⓔ stdlib·크기 · M1·M2 변이."""
import ast
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

FT2 = Path(__file__).resolve().parents[1]
TOOL = FT2 / "tools" / "manifest.py"
TREE = {"core/loader.py": "print('hi')\n", "contracts/kinds.tsv": "a\tb\n",
        "tests/test_x.py": "x = 1\n", "README.md": "# ft2\n"}

def run(*args, script=TOOL):
    proc = subprocess.run([sys.executable, str(script), *map(str, args)],
                          capture_output=True, text=True, timeout=60)
    return proc.returncode, proc.stdout, proc.stderr

def make_source(root):
    for rel, text in TREE.items():
        (root / rel).parent.mkdir(parents=True, exist_ok=True)
        (root / rel).write_text(text, encoding="utf-8")
    (root / "__pycache__").mkdir()
    (root / "__pycache__" / "junk.pyc").write_bytes(b"\0")
    for name in (".keep", ".hidden"):
        (root / name).write_text("x\n", encoding="utf-8")
    return root

def build(src, out):
    rc, stdout, stderr = run("build", src)
    assert rc == 0, stderr
    out.write_text(stdout, encoding="utf-8")
    return json.loads(stdout)

def verify(*args):
    rc, stdout, stderr = run("verify", *args)
    return rc, (json.loads(stdout) if stdout else {}), stderr

def copied(src, root, name):
    folder = root / name
    shutil.copytree(src, folder)
    return folder

def test_a_build_is_deterministic_and_fingerprinted(tmp_path):
    src = make_source(tmp_path / "src")
    first = build(src, tmp_path / "m1.json")
    build(src, tmp_path / "m2.json")
    assert (tmp_path / "m1.json").read_bytes() == (tmp_path / "m2.json").read_bytes()
    assert (first["schema"], first["count"]) == (1, len(TREE))
    assert [item["path"] for item in first["files"]] == sorted(TREE)
    kinds = {item["path"]: item["kind"] for item in first["files"]}
    assert (kinds["core/loader.py"], kinds["tests/test_x.py"]) == ("code", "test")
    one = [item for item in first["files"] if item["path"] == "core/loader.py"][0]
    raw = TREE["core/loader.py"].encode()
    assert (one["sha256"], one["bytes"]) == (hashlib.sha256(raw).hexdigest(), len(raw))
    assert first["source"]["sha"] is None or len(first["source"]["sha"]) == 40

def test_b_exclude_rules_live_in_one_place(tmp_path):
    doc = build(make_source(tmp_path / "src"), tmp_path / "m.json")
    assert doc["exclude"] == ["__pycache__/", "*.pyc", "*.pyo", ".*"] and [item["path"] for item in doc["files"]] == sorted(TREE)
    source = TOOL.read_text(encoding="utf-8")
    assert (source.count("EXCLUDE = ("), source.count("__pycache__")) == (1, 2)

def test_c_verify_reports_missing_extra_different(tmp_path):
    src = make_source(tmp_path / "src")
    manifest = tmp_path / "m.json"
    build(src, manifest)
    rc, doc, stderr = verify(manifest, src)
    assert (rc, stderr, [doc["count"][k] for k in ("missing", "extra", "different")]) == (0, "", [0, 0, 0])
    cases = (("missing", "missing", "core/loader.py", lambda folder: (folder / "core" / "loader.py").unlink()),
             ("extra", "extra", "core/new.py", lambda folder: (folder / "core" / "new.py").write_text("y = 2\n", encoding="utf-8")),
             ("different", "different", "core/loader.py", lambda folder: (folder / "core" / "loader.py").write_text("print('HI')\n", encoding="utf-8")))
    for name, key, want, change in cases:
        folder = copied(src, tmp_path, name)
        change(folder)
        rc, doc, _ = verify(manifest, folder)
        other = doc["missing"] + doc["extra"] + doc["different"]
        assert (rc, other) == (1, [want])
    broken = tmp_path / "broken.json"
    broken.write_text("{oops", encoding="utf-8")
    locked = copied(src, tmp_path, "locked")
    (locked / "core" / "loader.py").chmod(0)
    for args in (("verify", tmp_path / "nope.json", src), ("verify", broken, src), ("verify", manifest, tmp_path / "nodir"),
                 ("build", locked), ("verify", manifest, locked)):
        rc, stdout, stderr = run(*args)
        assert (rc, stdout, stderr.count("판정 불가"), "Traceback" in stderr) == (2, "", 1, False)

def test_d_real_ft2_tree_is_measured(tmp_path):
    assert (doc := build(FT2, tmp_path / "real.json"))["count"] > 40
    assert "tools/manifest.py" in [item["path"] for item in doc["files"]] and verify(tmp_path / "real.json", FT2)[0] == 0

def test_e_stdlib_only_and_small():
    source = TOOL.read_text(encoding="utf-8")
    modules = {(getattr(node, "module", None) or node.names[0].name).split(".")[0]
               for node in ast.walk(ast.parse(source)) if isinstance(node, (ast.Import, ast.ImportFrom))}
    assert len(source.splitlines()) <= 150 and "subprocess" not in source and modules <= {"hashlib", "json", "os", "sys"}

def mutant(tmp_path, name, old, new):
    source = TOOL.read_text(encoding="utf-8")
    assert old in source, old
    (tmp_path / (name + ".py")).write_text(source.replace(old, new), encoding="utf-8")
    return tmp_path / (name + ".py")

def test_m1_m2_mutants_miss_their_own_case(tmp_path):
    src = make_source(tmp_path / "src")
    manifest = tmp_path / "m.json"
    build(src, manifest)
    added = copied(src, tmp_path, "added")
    (added / "core" / "new.py").write_text("y = 2\n", encoding="utf-8")
    same = copied(src, tmp_path, "same")
    (same / "core" / "loader.py").write_text("print('HI')\n", encoding="utf-8")
    locked = copied(src, tmp_path, "locked")
    (locked / "core" / "loader.py").chmod(0)
    m1 = mutant(tmp_path, "m1", "    extra = sorted(path for path in have if path not in want)\n", "    extra = []\n")
    m2 = mutant(tmp_path, "m2", 'before["sha256"] != after["sha256"] or ', "")
    m3 = mutant(tmp_path, "m3", "        return 2  # 못 읽음 = 판정 불가\n", "        raise\n")
    assert (run("verify", manifest, added, script=m1)[0], run("verify", manifest, added)[0]) == (0, 1)
    assert (run("verify", manifest, same, script=m2)[0], run("verify", manifest, same)[0]) == (0, 1)
    assert (run("verify", manifest, locked, script=m3)[0], run("verify", manifest, locked)[0]) == (1, 2)
