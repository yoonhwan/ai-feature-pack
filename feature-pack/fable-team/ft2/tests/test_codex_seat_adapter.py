"""ft2 codex 좌석 어댑터 시험 (r1611 · 조건 14 «Codex 실행·진단») — ⓐ~ⓔ·ⓖ = 카드 수용 기준 그대로.
지침(`adapters/codex/AGENTS.ft2.md`)의 «실행 줄» 을 <PLACEHOLDER> 만 바꿔 실제 `core/cli.py` · `doctor/report.py`
하위 프로세스를 돌린다(래퍼 0 · press 0 · 입력 = tmp_path 격리 · ⓕ는 시험 밖 관측이라 카드 상태에 적는다).
"""
import importlib.util
import json
import os
import re
import shlex
import subprocess
import sys
import time
from pathlib import Path

import pytest

FT2 = Path(__file__).resolve().parents[1]
GUIDE = FT2 / "adapters" / "codex" / "AGENTS.ft2.md"
CLI, GUARD = FT2 / "core" / "cli.py", FT2 / "tools" / "legacy_guard.py"
TEAM, HOLDER, WORK, NOW, GEN, EFFECT = "harness", "codex-seat#0", "W1", "2026-11-11T03:00:00", 2, "e1"
ALLOWED = ("claim", "start", "effect", "result")
CLI_LINE = re.compile(r"^python3 core/cli\.py (\S+) (.+)$")
DOC_LINE = re.compile(r"^python3 doctor/report\.py (.+)$")
PLACE = re.compile(r"<([A-Z_]+)>")
FAIL_RULE = re.compile(r"rc\s*(?:≠|!=)\s*0[^\n]*(?:실패로|멈춘다)")
FORBIDDEN = ("setInterval", "setTimeout", "crontab", "launchd", "tmux", "while True", "sleep ", "spawn(")
BASE = (["submit", "--command", "do it", "--body", "본문", "--work", WORK],
        ["assign", "--work", WORK, "--holder", HOLDER, "--evidence", "v1,v2"],
        ["deliver", "--work", WORK])
VALUES = {"TEAM": TEAM, "WORK": WORK, "HOLDER": HOLDER, "GEN": str(GEN), "EFFECT": EFFECT, "OWNER": HOLDER,
          "SYMPTOM_KEY": "codex.seat", "SOURCE": "journal", "REF": "runtime",
          "INSTALL_SHA": "0123456789abcdef0123456789abcdef01234567"}


def core(name, folder="core"):
    spec = importlib.util.spec_from_file_location("ft2_test_codex_seat_" + name, FT2 / folder / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def guide_commands(path=GUIDE):
    rows = [one.strip() for one in path.read_text(encoding="utf-8").splitlines() if one.strip().startswith("python3")]
    cli = [{"verb": CLI_LINE.match(r).group(1), "args": CLI_LINE.match(r).group(2).split(), "line": r}
           for r in rows if CLI_LINE.match(r)]
    doctor = [{"args": DOC_LINE.match(r).group(1).split(), "line": r} for r in rows if DOC_LINE.match(r)]
    return {"cli": cli, "doctor": doctor,
            "others": [r for r in rows if not CLI_LINE.match(r) and not DOC_LINE.match(r)]}


def run(cmd, timeout=20):
    argv = shlex.split(cmd) if isinstance(cmd, str) else cmd
    return subprocess.run(argv, cwd=str(FT2), capture_output=True, text=True, timeout=timeout,
                          env=dict(os.environ, FT_NOW=NOW))


def cli(root, *args):
    return run([sys.executable, str(CLI), *args, "--root", str(root), "--team", TEAM])


def fill(line, root, **over):
    values = dict(VALUES, ROOT=str(root), **{key.upper(): str(value) for key, value in over.items()})
    return PLACE.sub(lambda match: values[match.group(1)], line)


def check_verbs(path=GUIDE):
    """ⓐ 지침 = 코어 동사 그대로(동사 이름·필수 인자가 cli VERBS 와 같다 · 그 밖 줄 0)."""
    table, got = core("cli").VERBS, guide_commands(path)
    assert [one["verb"] for one in got["cli"]] == list(ALLOWED), got["cli"]
    assert len(got["doctor"]) == 1 and got["others"] == [], got
    for one in got["cli"]:
        _cls, _method, required, optional = table[one["verb"]]
        names = [token[2:] for token in one["args"][0::2]]
        assert set(required) | {"root", "team"} <= set(names) <= set(required) | set(optional) | {"root", "team"}, one
        assert all(PLACE.match(token) for token in one["args"][1::2]), (one, "고칠 칸 = <PLACEHOLDER> 뿐")
    names = {token[2:] for token in got["doctor"][0]["args"][0::2]}
    assert {"root", "team", "symptom-key", "install-sha", "evidence", "owner"} <= names, got


def check_failure_rule(path=GUIDE):
    """ⓑ 지침은 rc≠0 을 «실패로 멈춤» 으로 적는다(성공으로 감싸지 않는다)."""
    assert FAIL_RULE.search(path.read_text(encoding="utf-8")), "rc≠0 = 실패로 멈춘다 규칙 줄이 없다"


@pytest.fixture(autouse=True)
def budget():
    started = time.monotonic()
    yield
    assert time.monotonic() - started < 70, "시험 1개 = 70초 안(하드 룰 22)"


@pytest.fixture
def root(tmp_path):
    box = tmp_path / "root"
    box.mkdir()
    procs = [(args, cli(box, *args)) for args in BASE]
    assert [proc.returncode for _args, proc in procs] == [0, 0, 0], [(args, proc.stdout) for args, proc in procs]
    return box


def test_a_guide_calls_only_the_four_core_verbs():
    check_verbs()
    assert len(GUIDE.read_text(encoding="utf-8").splitlines()) <= 60, "지침 ≤60줄"

def test_b_lines_are_verbatim_cli_and_failures_stop(root):
    procs = [run(fill(one["line"], root)) for one in guide_commands()["cli"]]
    assert [proc.returncode for proc in procs] == [0] * 4, [proc.stdout for proc in procs]   # 지침 줄 그대로
    assert [json.loads(proc.stdout)["result"] for proc in procs] == ["접수 성공"] * 4, procs
    assert all(len(proc.stdout.strip().splitlines()) == 1 for proc in procs), "stdout = JSON 1줄"
    start = [one for one in guide_commands()["cli"] if one["verb"] == "start"][0]
    bad = run(fill(start["line"], root, gen=99))               # 낡은 실행권 = rc1
    assert bad.returncode == 1 and json.loads(bad.stdout)["result"] == "낡은 실행권", bad.stdout
    assert "성공으로" not in bad.stdout, "rc≠0 을 감싸지 않는다"
    check_failure_rule()

def test_c_codex_seat_finishes_one_work(root):
    for one in guide_commands()["cli"]:
        assert run(fill(one["line"], root)).returncode == 0, one
    works = core("projection").project(root, TEAM)["works"]
    assert list(works) == [WORK] and works[WORK]["gen"] == GEN, works
    records = core("journal").Journal(root / ".fable-team" / "teams" / TEAM / "runtime", rec=core("record")).records()
    assert [one["kind"] for one in records if one["work"] == WORK and one["kind"] == "result"] == ["result"], "결과 1건"

def test_d_doctor_report_is_read_only(root):
    state = root / ".fable-team" / "teams" / TEAM / "runtime" / "state.json"
    before = (state.read_bytes(), state.stat().st_mtime_ns)
    proc = run(fill(guide_commands()["doctor"][0]["line"], root))
    assert proc.returncode == 0, proc.stderr[-400:]
    report, schema = json.loads(proc.stdout), core("schema_check", "contracts/doctor")
    assert schema.check(report, schema.read(FT2 / "contracts" / "doctor" / "doctor-io.schema.json")) == [], report
    assert report["allowed_recovery"] == [] and report["reverified"]["done"] is False and report["state_revision"] > 0
    assert (state.read_bytes(), state.stat().st_mtime_ns) == before, "진단은 읽기만(쓰기 0)"

def test_e_compat_layer_only():
    assert (guard := run([sys.executable, str(GUARD), str(FT2)], timeout=60)).returncode == 0, guard.stderr
    body = GUIDE.read_text(encoding="utf-8").split("## 하지 않는다")[0]   # 금지 절은 «하지 않는다» 를 적는 자리
    assert [token for token in FORBIDDEN if token in body] == [] and "7초" in body, "상주·폴링·tmux 0 · 호출 7초"
    got = guide_commands()
    assert len(got["cli"]) == 4 and len(got["doctor"]) == 1 and got["others"] == [], "실행 줄 = 코어 4 + 진단 1"

def test_f_mutants_break_their_cases(tmp_path):
    source = GUIDE.read_text(encoding="utf-8")
    result_line = [one for one in guide_commands()["cli"] if one["verb"] == "result"][0]["line"]
    extra = "\npython3 core/cli.py complete --work <WORK> --root <ROOT> --team <TEAM>"
    (tmp_path / "m1.md").write_text(source.replace(result_line, result_line + extra, 1), encoding="utf-8")
    (tmp_path / "m2.md").write_text(source.replace("rc≠0 이면 실패로 멈춘다", "rc≠0 이면 성공으로 넘어간다", 1),
                                    encoding="utf-8")
    for name, check in (("m1.md", check_verbs), ("m2.md", check_failure_rule)):   # M1 → ⓐ · M2 → ⓑ 빨강
        with pytest.raises(AssertionError):
            check(tmp_path / name)
