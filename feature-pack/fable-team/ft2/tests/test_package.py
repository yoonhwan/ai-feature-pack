"""ft2 package 시험 — ⓐ꼴·ⓑ결정성·크기 · ⓒcheck 5사례 · ⓓ판정 불가·ⓔ덮어쓰기 0 · 변이 M1·M2·M3·X1·X2 를 나눠 맡는다."""
import ast, hashlib, json, shutil, subprocess, sys
from pathlib import Path

FT2 = Path(__file__).resolve().parents[1]
TOOL, VERSION = FT2 / "tools" / "package.py", "2.0.0"
TREE = {"core/loader.py": "print('hi')\n", "contracts/kinds.tsv": "a\tb\n", "tests/test_x.py": "x = 1\n", "README.md": "# ft2\n", "docs/guide.md": "# g\n"}
NOISE = {"__pycache__/junk.pyc": b"\0", ".hidden": b"x\n", ".git/HEAD": b"ref: refs/heads/main\n", ".git/refs/heads/main": b"1" * 40 + b"\n"}
FILES = ("MANIFEST.json", "PACKAGE.json")  # .git 은 EXCLUDE(".*") 로 패키지에 안 들어간다 — source.sha 픽스처


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


def copies(pkg, root, tag):
    """ⓒ 사본 4종 — 파일 내용 바뀜 · source.sha 바뀜 · MANIFEST 밖 파일 추가 · manifest_sha256 위조."""
    edited, resha, added, forged = (root / f"{tag}-{name}" for name in ("edited", "resha", "added", "forged"))
    for side in (edited, resha, added, forged):
        shutil.copytree(pkg, side)
    (edited / "README.md").write_text("# changed\n", encoding="utf-8")
    meta = json.loads((resha / "PACKAGE.json").read_text(encoding="utf-8"))
    (resha / "PACKAGE.json").write_text(json.dumps({**meta, "source": {"sha": "2" * 40}}), encoding="utf-8")
    (added / "core/new.py").write_text("y = 2\n", encoding="utf-8")
    (forged / "PACKAGE.json").write_text(json.dumps({**meta, "manifest_sha256": "0" * 64}), encoding="utf-8")
    return edited, resha, added, forged


def test_a_build_shape_determinism_budget(tmp_path):
    src, out = make_source(tmp_path / "src"), tmp_path / "out"
    rc, pkg, stdout, stderr = built(src, out)
    doc, info = [json.loads((pkg / name).read_text(encoding="utf-8")) for name in FILES]
    assert (rc, stderr, stdout.count("\n"), sorted(out.iterdir())) == (0, "", 1, [pkg])
    assert (sorted(info), info["schema"], info["name"], info["version"], info["files"], info["source"]["sha"]) == (
        ["files", "manifest_sha256", "name", "schema", "source", "version"], 1, "ft2", VERSION, len(TREE), doc["source"]["sha"])
    assert info["manifest_sha256"] == hashlib.sha256((pkg / "MANIFEST.json").read_bytes()).hexdigest() and info["source"]["sha"] == "1" * 40
    assert stdout.startswith("PACKAGE ") and f"files={len(TREE)}" in stdout and info["manifest_sha256"] in stdout
    assert sorted(str(path.relative_to(pkg)) for path in pkg.rglob("*") if path.is_file()) == sorted([*TREE, *FILES])
    assert all(hashlib.sha256((pkg / item["path"]).read_bytes()).hexdigest() == item["sha256"] for item in doc["files"])
    assert [built(src, tmp_path / f"o{index}")[0] for index in (1, 2)] == [0, 0]  # ⓑ 같은 소스 = 같은 바이트
    read = [[(tmp_path / f"o{index}" / f"ft2-{VERSION}" / name).read_bytes() for name in FILES] for index in (1, 2)]
    source = TOOL.read_text(encoding="utf-8")
    modules = {(node.module if isinstance(node, ast.ImportFrom) else node.names[0].name).split(".")[0] for node in ast.walk(ast.parse(source)) if isinstance(node, (ast.Import, ast.ImportFrom))}
    assert (read[0] == read[1], modules, "subprocess" in source, len(source.splitlines()) <= 150) == (
        True, {"hashlib", "json", "os", "shutil", "sys", "manifest"}, False, True)


def test_b_check_five_cases(tmp_path):
    src = make_source(tmp_path / "src")
    _, pkg, _, _ = built(src, tmp_path / "out")
    assert run("check", src, pkg)[:2] == (0, f"SAME {pkg} files={len(TREE)}\n")
    changed, missing, hidden = tmp_path / "changed", tmp_path / "missing", tmp_path / "hidden"
    shutil.copytree(src, changed), shutil.copytree(pkg, missing), shutil.copytree(pkg, hidden)
    (changed / "core/loader.py").write_text("print('HI')\n", encoding="utf-8")
    (missing / "core/loader.py").unlink()
    (hidden / ".env").write_text("k=1\n", encoding="utf-8")
    edited, resha, added, forged = copies(pkg, tmp_path, "c")
    pairs = ((changed, pkg), (src, missing), (src, hidden), (src, edited), (src, resha), (src, added), (src, forged))
    assert [run("check", *pair)[:2] for pair in pairs] == [
        (1, "다름 1\n"), (1, "빠짐 1\n"), (1, "숨은 파일 1\n"), (1, "내용 다름 1\n"), (1, "다름 1\n"), (1, "다름 1\n"), (1, "다름 1\n")]


def test_c_refuse_and_no_overwrite(tmp_path):
    src = make_source(tmp_path / "src")
    _, pkg, _, _ = built(src, tmp_path / "out")
    broken, nokey = tmp_path / "broken", tmp_path / "nokey"
    shutil.copytree(pkg, broken), shutil.copytree(pkg, nokey)
    (broken / "MANIFEST.json").write_text("{oops", encoding="utf-8")
    info = json.loads((nokey / "PACKAGE.json").read_text(encoding="utf-8"))
    (nokey / "PACKAGE.json").write_text(json.dumps({k: v for k, v in info.items() if k != "files"}), encoding="utf-8")
    for args in ((tmp_path / "nodir", pkg), (src, tmp_path / "nodir"), (src, broken), (src, nokey), (src, pkg / "MANIFEST.json")):
        rc, stdout, stderr = run("check", *args)
        assert (rc, stdout, stderr.count("판정 불가"), stderr.count("\n"), "Traceback" in stderr) == (2, "", 1, 1, False), args
    before = {name: (pkg / name).read_bytes() for name in (*FILES, "core/loader.py")}
    rc, stdout, stderr = run("build", src, tmp_path / "out", "--version", VERSION)
    assert (rc, stdout, stderr.count("판정 불가"), "이미 있음" in stderr, "Traceback" in stderr) == (2, "", 1, True, False)
    assert before == {name: (pkg / name).read_bytes() for name in before}


def mutant(tmp_path, name, old, new):
    tools = tmp_path / "tools"
    tools.mkdir(exist_ok=True), shutil.copyfile(FT2 / "tools" / "manifest.py", tools / "manifest.py")  # 같은 폴더 import 유지
    source = TOOL.read_text(encoding="utf-8")
    assert old in source, old
    (tools / (name + ".py")).write_text(source.replace(old, new), encoding="utf-8")
    return tools / (name + ".py")


def test_mutants_m1_m2_m3_x1_x2_fail_their_own_case(tmp_path):
    src = make_source(tmp_path / "src")
    _, pkg, _, _ = built(src, tmp_path / "out")
    changed, hidden = tmp_path / "m-changed", tmp_path / "m-hidden"
    shutil.copytree(src, changed), shutil.copytree(pkg, hidden)
    (changed / "core/loader.py").write_text("print('HI')\n", encoding="utf-8")
    (hidden / ".env").write_text("k=1\n", encoding="utf-8")
    edited, resha, *_ = copies(pkg, tmp_path, "m")
    m2 = mutant(tmp_path, "m2", "    fresh = manifest.build(src)", "    fresh = manifest.build(pkg)")
    m3 = mutant(tmp_path, "m3", "    if os.path.exists(dest):", "    if False:")
    x1 = mutant(tmp_path, "x1", 'if fresh["source"]["sha"] != info["source"]["sha"]:', "if False:")
    x2 = mutant(tmp_path, "x2", 'changed = sorted(rel for rel in have if rel in want and want[rel]["sha256"] != have[rel]["sha256"])', "changed = []")
    m1 = mutant(tmp_path, "m1", "if rel not in (MANIFEST_FILE, PACKAGE_FILE) and manifest.skip_entry(rel)", "if False")
    assert run("check", src, hidden, script=m1)[:2] == (0, f"SAME {hidden} files={len(TREE)}\n")  # M1 = 숨은 파일 통과
    assert run("check", changed, pkg, script=m2)[:2] != (1, "다름 1\n") == run("check", changed, pkg)[:2]  # M2 = 소스 바뀜 못 봄
    assert run("check", src, edited, script=x2)[:2] == (0, f"SAME {edited} files={len(TREE)}\n")  # X2 = «내용 다름» 판정 뺌
    assert run("check", src, resha, script=x1)[:2] == (0, f"SAME {resha} files={len(TREE)}\n")  # X1 = source.sha 대조 뺌
    again = run("build", src, tmp_path / "out", "--version", VERSION, script=m3)  # M3 = 덮어쓰기 허용 → «이미 있음» 사라짐
    assert (again[0], "이미 있음" in again[2]) == (2, False) and run("build", src, tmp_path / "out", "--version", VERSION)[0] == 2
