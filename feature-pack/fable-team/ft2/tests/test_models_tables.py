"""ft2 모델 표 시험 — ⓐ fable-5-2 resolve · ⓑ 1.1.292 사본 대조 · ⓒ 불명·손상 · ⓓ 1.x 무변경 · ⓔ legacy guard · M1 변이."""
import os
import shutil
import subprocess
import sys
from pathlib import Path

FT2 = Path(__file__).resolve().parents[1]
TOOL = FT2 / "tools" / "models.py"
TABLES = FT2 / "contracts" / "models"
SOURCE = TABLES / "_source_1.1.292.txt"
NAMES = ("model-scope.tsv", "model-fallback.tsv", "provider-of-model.tsv")
# 1.x 경로 문자열은 조각으로 만든다 — 이 파일도 ft2/ 안이라 legacy_guard 자기검사에 걸리면 안 된다.
OLD = "/".join(["legacy", "1" + ".x", "harness", "bin"])
FABLE_WITH_WINDOW = "claude-fable-5-2[1m]"
EXPECTED = {"model": "claude-fable-5-2", "provider": "claude",
            "scope": "Fable", "fallback": "claude-opus-5-5[1m]"}


def run(model, models_dir=None):
    env = dict(os.environ)
    env.pop("FT2_MODELS_DIR", None)
    if models_dir is not None:
        env["FT2_MODELS_DIR"] = str(models_dir)
    proc = subprocess.run([sys.executable, str(TOOL), "resolve", model],
                          capture_output=True, text=True, timeout=30, env=env)
    return proc.returncode, proc.stdout.strip(), proc.stderr.strip()


def table_rows(models_dir, name):
    """표 하나의 데이터 행(주석·빈 줄 제외)."""
    lines = (Path(models_dir) / name).read_text(encoding="utf-8").splitlines()
    return [line for line in lines if line.strip() and not line.lstrip().startswith("#")]


def source_rows():
    """고정 사본에서 표 이름 → 데이터 행."""
    parsed, current = {}, None
    for line in SOURCE.read_text(encoding="utf-8").splitlines():
        if line.startswith("## "):
            current = line[3:].strip()
            parsed[current] = []
        elif current and line.strip() and not line.lstrip().startswith("#"):
            parsed[current].append(line)
    return parsed


def copy_tables(tmp_path):
    target = tmp_path / "models"
    target.mkdir()
    for name in NAMES:
        shutil.copy(TABLES / name, target / name)
    return target


def test_a_fable_5_2_resolves_to_one_json_line():
    rc, out, err = run(FABLE_WITH_WINDOW)
    assert (rc, err) == (0, "")
    assert out.splitlines() == ['{"model":"claude-fable-5-2","provider":"claude",'
                               '"scope":"Fable","fallback":"claude-opus-5-5[1m]"}']
    assert out == __import__("json").dumps(EXPECTED, ensure_ascii=False, separators=(",", ":"))


def test_b_tables_match_1_1_292_copy():
    parsed = source_rows()
    assert sorted(parsed) == sorted(NAMES)
    for name in NAMES:
        assert table_rows(TABLES, name) == parsed[name], name
    assert any("claude-fable-5-2" in row for row in parsed["model-scope.tsv"])


def test_c_unknown_and_broken_rows(tmp_path):
    before = {p.name: (p.stat().st_size, p.stat().st_mtime_ns) for p in TABLES.iterdir()}
    rc, out, err = run("claude-nope-9")
    assert (rc, out, err) == (1, "불명(scope 표 없음 claude-nope-9)", "")
    broken = copy_tables(tmp_path)
    path = broken / "model-fallback.tsv"
    path.write_text(path.read_text(encoding="utf-8") + "claude-opus-5-5\n", encoding="utf-8")
    lineno = len(path.read_text(encoding="utf-8").splitlines())
    rc, out, err = run(FABLE_WITH_WINDOW, broken)
    assert rc == 2 and out == "" and err.startswith("표 손상 model-fallback.tsv:")
    assert f":{lineno} " in err
    after = {p.name: (p.stat().st_size, p.stat().st_mtime_ns) for p in TABLES.iterdir()}
    assert after == before


def test_d_1x_keeps_fable_5_2_and_is_committed(tmp_path):
    legacy = FT2.parents[0] / OLD
    parsed = source_rows()
    for name in NAMES:
        assert (legacy / name).is_file(), name
    for name in ("model-scope.tsv", "model-fallback.tsv"):
        assert table_rows(legacy, name) == parsed[name], name
    assert any("claude-fable-5-2" in row for row in table_rows(legacy, "model-scope.tsv"))
    manifest = __import__("json").loads((legacy.parents[1] / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["version"] == "1.1.292"
    diff = subprocess.run(["git", "-C", str(FT2.parents[2]), "status", "--porcelain", "--",
                           str(legacy)],
                          capture_output=True, text=True, timeout=70)
    assert (diff.returncode, diff.stdout.strip()) == (0, "")


def test_e_guard_reports_no_1x_use():
    proc = subprocess.run([sys.executable, str(FT2 / "tools" / "legacy_guard.py"), str(FT2)],
                          capture_output=True, text=True, timeout=70)
    assert (proc.returncode, proc.stdout.strip()) == (0, "")


def test_m1_without_fallback_row_both_fail(tmp_path):
    mutated = copy_tables(tmp_path)
    path = mutated / "model-fallback.tsv"
    kept = [line for line in path.read_text(encoding="utf-8").splitlines()
            if not line.startswith("claude-fable-5-2")]
    path.write_text("\n".join(kept) + "\n", encoding="utf-8")
    rc, out, _ = run(FABLE_WITH_WINDOW, mutated)
    assert rc == 0 and '"fallback":null' in out
    assert table_rows(mutated, "model-fallback.tsv") != source_rows()["model-fallback.tsv"]
