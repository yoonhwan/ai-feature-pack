"""ft2 역할 기본 모델·effort 시험 — ⓐ 세션 medium·팀장 high · ⓑ effort 누락 0 · ⓒ 모르는 역할 대입 0 · ⓔ guard·기존 불변 · M1 변이."""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

FT2 = Path(__file__).resolve().parents[1]
TOOL = FT2 / "tools" / "models.py"
TABLES = FT2 / "contracts" / "models"
TABLE = TABLES / "role-defaults.tsv"
EFFORTS = ("off", "minimal", "low", "medium", "high", "xhigh", "max")
SESSION_ROW = "session\tclaude-opus-5-5\tmedium"
MASTER_ROW = "master\tclaude-opus-5-5\thigh"
MASTER_ROW_M1 = "master\tclaude-opus-5-5\tmedium"
SESSION_ANSWER = {"role": "session", "model": "claude-opus-5-5", "effort": "medium",
                  "argv": ["--model", "claude-opus-5-5", "--thinking", "medium"]}
# 손상 3종 — 빈 effort 칸 · pi 7낱말 밖 · effort 칸 자체가 없다
MUTANTS = {"empty": SESSION_ROW[:-len("medium")],
           "unknown": SESSION_ROW[:-len("medium")] + "ultra",
           "column": SESSION_ROW[:-len("\tmedium")]}


def one_line(payload):
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def run(*args, models_dir=None):
    env = dict(os.environ)
    env.pop("FT2_MODELS_DIR", None)
    if models_dir is not None:
        env["FT2_MODELS_DIR"] = str(models_dir)
    proc = subprocess.run([sys.executable, str(TOOL), *args],
                          capture_output=True, text=True, timeout=70, env=env)
    return proc.returncode, proc.stdout.strip(), proc.stderr.strip()


def table_rows():
    """역할 표의 데이터 행(주석·빈 줄 제외)을 칸 목록으로."""
    lines = TABLE.read_text(encoding="utf-8").splitlines()
    return [line.split("\t") for line in lines
            if line.strip() and not line.lstrip().startswith("#")]


def mutant_tables(root, kind):
    """표 폴더 사본 하나에 손상 1종을 넣는다."""
    target = root / "models"
    target.mkdir()
    for path in TABLES.iterdir():
        if path.is_file():
            shutil.copy(path, target / path.name)
    path = target / "role-defaults.tsv"
    before = path.read_text(encoding="utf-8")
    path.write_text(before.replace(SESSION_ROW, MUTANTS[kind]), encoding="utf-8")
    assert path.read_text(encoding="utf-8") != before, kind
    return target


def test_a_session_medium_and_master_high():
    """ⓐ 기본 세션 = medium · 팀장 = high — 인자 한 쌍으로."""
    assert run("role", "session") == (0, one_line(SESSION_ANSWER), "")
    rc, out, err = run("role", "master")
    assert (rc, err) == (0, "")
    answer = json.loads(out)
    assert (answer["role"], answer["model"], answer["effort"]) == ("master", "claude-opus-5-5", "high")
    assert answer["argv"] == ["--model", "claude-opus-5-5", "--thinking", "high"]


def test_b_every_row_has_effort_and_argv_pairs():
    """ⓑ 표 전 행에 effort 칸 · argv 는 --model 과 --thinking 을 «함께» 낸다."""
    rows = table_rows()
    assert rows, "역할 표가 비었다"
    for cells in rows:
        assert len(cells) == 3, cells
        assert cells[2] in EFFORTS, cells
    for cells in rows:
        rc, out, err = run("role", cells[0])
        assert (rc, err) == (0, "")
        argv = json.loads(out)["argv"]
        assert argv.count("--model") == 1 and argv.count("--thinking") == 1, cells[0]
        assert argv[argv.index("--model") + 1] == cells[1], cells[0]
        assert argv[argv.index("--thinking") + 1] == cells[2], cells[0]
        assert "--thinking" in argv, cells[0]


def test_b_broken_effort_is_rc2_and_writes_nothing(tmp_path):
    """ⓑ 빈 칸·모르는 낱말·칸 없음 = rc2 «표 손상» · 제품 표는 그대로."""
    before = (TABLE.read_bytes(), TABLE.stat().st_mtime_ns)
    for kind in MUTANTS:
        root = tmp_path / kind
        root.mkdir()
        rc, out, err = run("role", "session", models_dir=mutant_tables(root, kind))
        assert (rc, out) == (2, ""), kind
        assert "표 손상" in err, kind
    assert (TABLE.read_bytes(), TABLE.stat().st_mtime_ns) == before


def test_c_unknown_role_has_no_default(tmp_path):
    """ⓒ 표에 없는 역할 = rc1 · session 행으로 대신하지 않는다 · 표를 고치지 않는다."""
    before = (TABLE.read_bytes(), TABLE.stat().st_mtime_ns)
    for name in ("deploy", "Session", "master2"):
        rc, out, err = run("role", name)
        assert (rc, err) == (1, ""), name
        assert out == f"기본값 없음(역할 {name})", name
        assert "claude-opus-5-5" not in out, name
    assert (TABLE.read_bytes(), TABLE.stat().st_mtime_ns) == before


def test_d_real_generation_argv_comes_from_role():
    """ⓓ 실생성은 arch 인수 때 잰다 — 여기서는 그 argv 가 표에서만 나오는지 본다."""
    for cells in table_rows():
        argv = json.loads(run("role", cells[0])[1])["argv"]
        assert argv == ["--model", cells[1], "--thinking", cells[2]], cells[0]


def test_e_guard_and_existing_models_tests_unchanged():
    """ⓔ legacy guard rc0 · r1602 시험 rc 불변."""
    guard = subprocess.run([sys.executable, str(FT2 / "tools" / "legacy_guard.py"), str(FT2)],
                           capture_output=True, text=True, timeout=70)
    assert (guard.returncode, guard.stdout.strip()) == (0, "")
    proc = subprocess.run([sys.executable, "-m", "pytest", "-q", "tests/test_models_tables.py"],
                          capture_output=True, text=True, timeout=70, cwd=str(FT2))
    assert proc.returncode == 0, proc.stdout[-2000:]


def test_m1_master_medium_breaks_default(tmp_path):
    """M1 변이 — master 행 effort 를 medium 으로 바꾸면 ⓐ 가 FAIL 한다."""
    root = tmp_path / "m1"
    root.mkdir()
    target = root / "models"
    target.mkdir()
    for path in TABLES.iterdir():
        if path.is_file():
            shutil.copy(path, target / path.name)
    path = target / "role-defaults.tsv"
    mutated = path.read_text(encoding="utf-8").replace(MASTER_ROW, MASTER_ROW_M1)
    assert mutated != path.read_text(encoding="utf-8")
    path.write_text(mutated, encoding="utf-8")
    rc, out, err = run("role", "master", models_dir=target)
    assert (rc, err) == (0, "")
    assert json.loads(out)["effort"] != "high"
