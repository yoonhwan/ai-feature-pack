"""ft2 manifest 시험 — 한 파일이 ⓐⓑR1(결정성·지문·제외 파생·packed-refs) · ⓒ(3목록·rc2·소실) · ⓓⓔ(실 트리·stdlib) · 변이 M1·M2·M3 을 나눠 맡는다."""
import ast, hashlib, importlib.util, json, shutil, subprocess, sys
from pathlib import Path

import pytest

FT2 = Path(__file__).resolve().parents[1]
TOOL = FT2 / "tools" / "manifest.py"
TREE = {"core/loader.py": "print('hi')\n", "contracts/kinds.tsv": "a\tb\n", "tests/test_x.py": "x = 1\n", "README.md": "# ft2\n"}

def run(*args, script=TOOL):
    proc = subprocess.run([sys.executable, str(script), *map(str, args)], capture_output=True, text=True, timeout=60)
    return proc.returncode, proc.stdout, proc.stderr

def load_tool(script=TOOL):
    module = importlib.util.module_from_spec(importlib.util.spec_from_file_location("m_" + script.stem, script))
    module.__spec__.loader.exec_module(module); return module

def make_source(root):
    noise = {"__pycache__/junk.pyc": b"\0", ".keep": b"x\n", ".hidden": b"x\n"}
    for rel, data in {**{key: text.encode() for key, text in TREE.items()}, **noise}.items():
        (root / rel).parent.mkdir(parents=True, exist_ok=True)
        (root / rel).write_bytes(data)
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
    shutil.copytree(src, root / name)
    return root / name

def refused(*args):
    rc, stdout, stderr = run(*args)
    assert (rc, stdout, stderr.count("판정 불가"), "Traceback" in stderr) == (2, "", 1, False), args

def test_a_b_build_fingerprint_exclude_and_packed_ref(tmp_path):
    src = make_source(tmp_path / "src")
    twice = [build(src, tmp_path / f"m{index}.json") for index in (1, 2)]
    assert (tmp_path / "m1.json").read_bytes() == (tmp_path / "m2.json").read_bytes() and twice[0] == twice[1]
    first = twice[0]
    assert (first["schema"], first["count"]) == (1, len(TREE)) and [item["path"] for item in first["files"]] == sorted(TREE)
    one = next(item for item in first["files"] if item["path"] == "core/loader.py")
    assert (one["kind"], one["sha256"], one["bytes"]) == ("code", hashlib.sha256(b"print('hi')\n").hexdigest(), 12)
    mod = load_tool()
    assert [mod.skip_entry(rel) for rel in ("core/__pycache__", "core/a.pyc", "core/.keep", ".git", "core/a.py", "docs/a.md")] == [True, True, True, True, False, False] and first["exclude"] == list(mod.EXCLUDE)
    packed = make_source(tmp_path / "packed")
    (packed / ".git").mkdir()
    (packed / ".git" / "HEAD").write_text("ref: refs/heads/main\n", encoding="utf-8")
    (packed / ".git" / "packed-refs").write_text("35fe11bdd25fc0acbb7df00addae604f0486cd48 refs/heads/main\n", encoding="utf-8")
    assert build(packed, tmp_path / "p.json")["source"]["sha"] == "35fe11bdd25fc0acbb7df00addae604f0486cd48"

def test_c_verify_reports_and_refuses(tmp_path, monkeypatch, capsys):
    src, manifest = make_source(tmp_path / "src"), tmp_path / "m.json"
    base = build(src, manifest)
    rc, doc, stderr = verify(manifest, src)
    assert (rc, stderr) == (0, "") and not any(doc["count"][key] for key in ("missing", "extra", "different"))
    cases = {"missing": ("core/loader.py", None), "extra": ("core/new.py", "y = 2\n"), "different": ("core/loader.py", "print('HI')\n")}
    for key, (rel, text) in cases.items():
        folder = copied(src, tmp_path, key)
        (folder / rel).unlink() if text is None else (folder / rel).write_text(text, encoding="utf-8")
        rc, doc, _ = verify(manifest, folder)
        assert (rc, doc["missing"] + doc["extra"] + doc["different"]) == (1, [rel])
    item = base["files"][0]
    bads = (dict(item, sha256="abc"), dict(item, kind="진짜"), dict(item, bytes="4"), dict(item, bytes=-1),
            dict(item, path=""), dict(item, path="/etc/x"), dict(item, path=7),
            {key: value for key, value in item.items() if key != "sha256"})
    for index, bad in enumerate(bads):
        path = tmp_path / f"bad{index}.json"
        path.write_text(json.dumps(dict(base, files=[bad])), encoding="utf-8")
        refused("verify", path, src)
    broken = tmp_path / "broken.json"; broken.write_text("{oops", encoding="utf-8")  # JSON 손상
    for args in ((tmp_path / "nope.json", src), (broken, src), (manifest, tmp_path / "nodir")):
        refused("verify", *args)
    mod = load_tool()
    real = mod.walk_files
    monkeypatch.setattr(mod, "walk_files", lambda root: real(root) + ["ghost.py"])
    assert (mod.main(["x", "build", str(src)]), mod.main(["x", "verify", str(manifest), str(src)])) == (2, 2)
    err = capsys.readouterr().err
    assert err.count("판정 불가") == 2 and "Traceback" not in err

def test_d_e_real_tree_and_stdlib_only(tmp_path):
    doc = build(FT2, tmp_path / "real.json")
    assert doc["count"] > 40 and "tools/manifest.py" in [item["path"] for item in doc["files"]] and verify(tmp_path / "real.json", FT2)[0] == 0
    source = TOOL.read_text(encoding="utf-8")
    modules = {(getattr(node, "module", None) or node.names[0].name).split(".")[0] for node in ast.walk(ast.parse(source)) if isinstance(node, (ast.Import, ast.ImportFrom))}
    assert len(source.splitlines()) <= 150 and "subprocess" not in source and modules <= {"fnmatch", "hashlib", "json", "os", "sys"}

def mutant(tmp_path, name, old, new):
    source = TOOL.read_text(encoding="utf-8")
    assert old in source, old
    (tmp_path / (name + ".py")).write_text(source.replace(old, new), encoding="utf-8")
    return tmp_path / (name + ".py")

def test_m1_m2_m3_m4_mutants_miss_their_own_case(tmp_path, monkeypatch):
    src, manifest = make_source(tmp_path / "src"), tmp_path / "m.json"
    build(src, manifest)
    added, same = copied(src, tmp_path, "added"), copied(src, tmp_path, "same")
    (added / "core" / "new.py").write_text("y = 2\n", encoding="utf-8")
    (same / "core" / "loader.py").write_text("print('HI')\n", encoding="utf-8")
    m1 = mutant(tmp_path, "m1", "    extra = sorted(path for path in have if path not in want)", "    extra = []")
    m2 = mutant(tmp_path, "m2", '(want[path]["sha256"], want[path]["bytes"]) != (have[path]["sha256"], have[path]["bytes"])',
                'want[path]["bytes"] != have[path]["bytes"]')
    m3 = load_tool(mutant(tmp_path, "m3", "        return 2  # 못 읽음 = 판정 불가", "        raise"))
    monkeypatch.setattr(m3, "walk_files", lambda root: ["ghost.py"])
    assert (run("verify", manifest, added, script=m1)[0], run("verify", manifest, added)[0]) == (0, 1)
    assert (run("verify", manifest, same, script=m2)[0], run("verify", manifest, same)[0]) == (0, 1)
    with pytest.raises(OSError):
        m3.main(["x", "build", str(src)])
    plain = json.loads(manifest.read_text(encoding="utf-8"))
    absolute = tmp_path / "abs.json"; absolute.write_text(json.dumps(dict(plain, files=[dict(plain["files"][0], path="/etc/x")])), encoding="utf-8")
    m4 = mutant(tmp_path, "m4", "path and not os.path.isabs(path)", "True")
    assert (run("verify", absolute, src, script=m4)[0], run("verify", absolute, src)[0]) == (1, 2)
