"""R106 판정기 bang_command_check — 오빠 `!` 명령 줄만 검사(≤60자 · /tmp/h<N> 밖 절대경로 0 · 따옴표 밖 &&·;·| 0)."""
import importlib.util
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MOD = ROOT / "harness" / "comm" / "bang_command_check.py"
spec = importlib.util.spec_from_file_location("bang_command_check", MOD)
bcc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bcc)

REAL_CASE = "! bash /private/tmp/claude-501/-Users-yoonhwan-Project-Agent-BYZ-Work-BYZ-Agents--worktrees-ops/94158d4c/scratchpad/d6-apply.sh"


def test_standard_form_passes():
    assert bcc.violations("! bash /tmp/h12") == []
    assert bcc.violations("! bash /tmp/h7   ") == []


def test_wrappers_stripped_before_judging():
    assert bcc.violations("`! bash /tmp/h3`") == []
    assert bcc.violations("> ! bash /tmp/h3") == []
    assert bcc.violations("  - ! bash /tmp/h3") == []
    assert bcc.violations("2. ! bash /tmp/h3") == []


def test_blocked_command_original_line_is_not_checked():
    assert bcc.violations("①막힌 명령: cd /Users/x && rm -rf /tmp/y") == []
    assert bcc.violations("조건을 보고; 그 뒤에 | 다음 && 진행") == []


def test_real_case_is_rejected():
    assert len(REAL_CASE) > 100
    assert len(bcc.violations(REAL_CASE)) == 1


def test_abs_path_other_than_tmp_h_rejected():
    assert bcc.violations("! bash ~/x.sh")
    assert bcc.violations("! bash /tmp/x12")
    assert bcc.violations("! ls /etc")


def test_chain_rejected():
    assert bcc.violations("! cd /x && ln -s a b")
    assert bcc.violations("! cat a | b")
    assert bcc.violations("! a; b")


def test_long_short_path_command_rejected():
    line = "! " + "echo " + "x" * 60
    assert len(line) > 60 and bcc.violations(line)


def test_semicolon_inside_quotes_is_not_chain():
    assert bcc.violations('! echo "a;b"') == []
    assert bcc.violations("! echo 'a && b'") == []


def test_multi_line_body_reports_only_bang_lines():
    body = "[HIL] 막힘\n①막힌 명령: cd /x && rm y\n! bash /tmp/h9\n" + REAL_CASE
    got = bcc.violations(body)
    assert len(got) == 1 and got[0].startswith("! bash /private/tmp")


def test_cli_rc():
    run = lambda s: subprocess.run([sys.executable, str(MOD)], input=s, capture_output=True, text=True)
    ok, bad = run("! bash /tmp/h12"), run(REAL_CASE)
    assert ok.returncode == 0 and ok.stdout == ""
    assert bad.returncode == 1 and "ft-hil.sh --add" in bad.stdout and "! bash /private/tmp" in bad.stdout
