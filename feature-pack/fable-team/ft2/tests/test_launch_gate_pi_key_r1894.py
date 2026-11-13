"""r1894 launch plan 키 "pi" → "pi_bin" — 설치 글자 관문(check --root-dir)의 dict 첨자 오탐 0 (반례 ①·③ · 변이 M1).
① package.py build → list-dyncalls 로 만든 임시 기준선(동적 지점 전부 · 이 시험 안에서만) + 빈 allow → check = ALLOW rc0
③ adapters·tools 의 «[ + 따옴표 + LLM 낱말 + 따옴표» 꼴 0줄 · M1 launch.py 읽는 쪽만 옛 키 → ① 같은 REJECT · no_pi KeyError
관문·allow 장부·실 기준선 손 0 · 실 설치·명부·장부 0 · sleep 0. ② = test_pi_launch_pi_path_r1892 그대로.
"""
import importlib.util, re, subprocess, sys  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
FT2 = HERE.parent
GATE = FT2.parent / "legacy" / "1.x" / "harness" / "bin" / "ft_launchd_llm_gate.py"
_spec = importlib.util.spec_from_file_location("pi_path_r1894", str(HERE / "test_pi_launch_pi_path_r1892.py"))
pp = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pp)
LITERAL = "글자 그대로 LLM 호출"
HIT = re.compile(r"""\[['"](claude|codex|opencode|pi|hermes|gemini|llm|aider|ollama)['"]""")
OLD_READ = 'plan["p' + 'i"] is None'
pp.pl.MUTANTS["K1"] = ("launch.py", 'plan["pi_bin"] is None', OLD_READ)


def run(*argv):
    done = subprocess.run([sys.executable, *map(str, argv)], capture_output=True, text=True, timeout=30)
    return done.returncode, (done.stdout + done.stderr).strip()


def gate(src, tmp):
    """src 로 패키지 1개 → 그 패키지의 동적 지점 전부를 임시 기준선에 → check 1회 = (rc, 줄)."""
    assert run(FT2 / "tools" / "package.py", "build", src, tmp, "--version", "0.0.0")[0] == 0
    pkg = Path(tmp) / "ft2-0.0.0"
    rc, rows = run(GATE, "list-dyncalls", "--root-dir", pkg)
    assert rc == 0, rows
    base, allow = Path(tmp) / "baseline.tsv", Path(tmp) / "allow.tsv"
    base.write_text("".join("\t".join(row.split("\t")[:3] + ["r1894 시험"]) + "\n" for row in rows.splitlines()), encoding="utf-8")
    allow.write_text("", encoding="utf-8")
    return run(GATE, "check", "--root-dir", pkg, "--baseline", base, "--allow", allow)


def test_gate_allow(tmp_path):
    rc, line = gate(FT2, tmp_path)
    assert (rc, LITERAL in line, line.startswith("ALLOW")) == (0, False, True), line


def test_no_subscript_hit():
    rows = ["%s:%d" % (p, n) for top in ("adapters", "tools") for p in sorted((FT2 / top).rglob("*.py"))
            for n, text in enumerate(p.read_text(encoding="utf-8").splitlines(), 1) if HIT.search(text)]
    assert rows == [], rows


def test_mutant_old_read_key(tmp_path):
    """M1 → 관문 REJECT(같은 줄 꼴) · no_pi 사례 FAIL(KeyError) · 원본은 no_pi PASS."""
    launcher = pp.pl._mutant(tmp_path, "K1")
    rc, line = gate(launcher.parents[2], tmp_path / "pkg")
    assert rc == 1 and LITERAL in line and line.endswith("adapters/pi/launch.py:152"), line
    with pytest.raises(AssertionError, match="KeyError"):
        pp.case_no_pi(tmp_path / "bad", launcher)
    pp.case_no_pi(tmp_path / "good")
