"""ft2 legacy_guard 시험 — ⓐ 뼈대 · ⓑ 자기검사 · ⓒ 가짜 트리 3사례 · ⓓ 허용 목록 · ⓔ 가벼움 · M1·M2 변이."""
import ast
import subprocess
import sys
from pathlib import Path

FT2 = Path(__file__).resolve().parents[1]
GUARD = FT2 / "tools" / "legacy_guard.py"
FOLDERS = ("core", "adapters/slack", "adapters/codex", "adapters/pi", "doctor", "contracts", "tools", "tests")
PR = {"core": "PR②", "contracts": "PR②", "adapters/slack": "PR③",
      "adapters/codex": "PR④", "adapters/pi": "PR④", "doctor": "PR④"}
# 패턴 문자열은 조각으로 만든다 — 이 시험 파일도 ft2/ 안이라 자기검사에 걸리면 안 된다.
OLD = "legacy" + "/1" + ".x"
BIN = "harness" + "/bin"
FABLE = "." + "fable-team" + "/bin"
CASES = (
    ("core/loader.py", "sys.path.insert(0, '" + OLD + "/tools'); import runner", OLD),
    ("adapters/pi/hook.sh", 'source "$PACK/' + BIN + '/runner.sh"', BIN),
    ("doctor/config.json", '{"tool": "' + FABLE + '/ft-doctor.sh"}', FABLE),
)


def run_on(script, root):
    proc = subprocess.run([sys.executable, str(script), str(root)],
                          capture_output=True, text=True, timeout=30)
    return proc.returncode, [line for line in proc.stdout.splitlines() if line.strip()]



def fake(root, name, line):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(line + "\n", encoding="utf-8")
    return path


def test_a_skeleton_and_readme():
    readme = (FT2 / "README.md").read_text(encoding="utf-8")
    rows = readme.splitlines()
    for folder in FOLDERS:
        assert (FT2 / folder).is_dir(), folder
        assert (FT2 / folder / ".keep").is_file(), folder
        assert any(folder + "/" in row for row in rows), folder
    for folder, tag in PR.items():
        assert any(folder + "/" in row and tag in row for row in rows), (folder, tag)


def test_b_self_scan_clean():
    assert run_on(GUARD, FT2) == (0, [])


def test_c_each_case_fails_with_one_line(tmp_path):
    for name, line, pattern in CASES:
        root = tmp_path / name.replace("/", "_")
        fake(root, name, line)
        assert run_on(GUARD, root) == (1, [f"{name}:1: {pattern}"]), name


def test_d_md_allowed_comments_not(tmp_path):
    root = tmp_path / "d"
    fake(root, "notes/readme.md", "1.x = " + OLD + " 참고만 한다")
    assert run_on(GUARD, root) == (0, [])
    fake(root, "core/loader.py", "# 폐기: " + OLD)
    assert run_on(GUARD, root) == (1, ["core/loader.py:1: " + OLD])


def test_e_guard_is_small_and_stdlib_only():
    source = GUARD.read_text(encoding="utf-8")
    assert len(source.splitlines()) <= 120
    names = set()
    for node in ast.walk(ast.parse(source)):
        if isinstance(node, ast.Import):
            names |= {alias.name.split(".")[0] for alias in node.names}
        elif isinstance(node, ast.ImportFrom):
            names.add((node.module or "").split(".")[0])
    assert names <= {"os", "sys"}


def mutant(tmp_path, old, new):
    source = GUARD.read_text(encoding="utf-8")
    assert old in source, old
    path = tmp_path / "mutant.py"
    path.write_text(source.replace(old, new), encoding="utf-8")
    return path


def test_m1_m2_mutants_miss_their_own_case(tmp_path):
    root = tmp_path / "m"
    fake(root, CASES[1][0], CASES[1][1])
    fake(root, CASES[2][0], CASES[2][1])
    m1 = mutant(tmp_path, '    "' + BIN + '",\n', "")
    assert run_on(m1, root) == (1, [f"{CASES[2][0]}:1: {FABLE}"])
    m2 = mutant(tmp_path, '".json")', ")")
    assert run_on(m2, root) == (1, [f"{CASES[1][0]}:1: {BIN}"])
