"""R106 훅 bang-command-gate — PreToolUse:AskUserQuestion. 위반 → deny · 정상 → allow · 파싱 불가 → allow(fail-open) + 로그."""
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HOOK = ROOT / "harness/kit/fable-team/templates/hooks/bang-command-gate.sh"
CHECKER = ROOT / "harness/comm/bang_command_check.py"
BAD = "! bash /private/tmp/claude-501/x/scratchpad/d6-apply.sh"


def run(stdin, tmp_path):
    env = {**os.environ, "FT_BANG_COMMAND_CHECK": str(CHECKER), "FT_BANG_COMMAND_LOG": str(tmp_path / "gate.log")}
    return subprocess.run(["bash", str(HOOK)], input=stdin, capture_output=True, text=True, env=env)


def ask(**fields):
    q = {"question": "승인할까요?", "header": "승인", "options": [{"label": "예", "description": ""}, {"label": "아니오", "description": ""}]}
    q.update(fields)
    return json.dumps({"tool_name": "AskUserQuestion", "tool_input": {"questions": [q]}}, ensure_ascii=False)


def test_standard_form_allows(tmp_path):
    r = run(ask(question="이 한 줄만 치세요:\n! bash /tmp/h12"), tmp_path)
    assert r.returncode == 0 and r.stdout.strip() == ""


def test_violation_in_question_denies(tmp_path):
    r = run(ask(question="실행해 주세요:\n" + BAD), tmp_path)
    out = json.loads(r.stdout)["hookSpecificOutput"]
    assert r.returncode == 0 and out["permissionDecision"] == "deny"
    assert "ft-hil.sh --add" in out["permissionDecisionReason"] and "/tmp/h<N>" in out["permissionDecisionReason"]


def test_violation_in_option_preview_denies(tmp_path):
    q = ask()
    d = json.loads(q)
    d["tool_input"]["questions"][0]["options"][0]["preview"] = "`" + BAD + "`"
    out = json.loads(run(json.dumps(d, ensure_ascii=False), tmp_path).stdout)
    assert out["hookSpecificOutput"]["permissionDecision"] == "deny"


def test_blocked_command_original_line_allows(tmp_path):
    r = run(ask(question="①막힌 명령: cd /Users/x && rm -rf y"), tmp_path)
    assert r.returncode == 0 and r.stdout.strip() == ""


def test_unparsable_stdin_fail_open_with_log(tmp_path):
    r = run("{not json", tmp_path)
    assert r.returncode == 0 and r.stdout.strip() == ""
    assert "fail-open" in (tmp_path / "gate.log").read_text(encoding="utf-8")


def test_checker_missing_fail_open(tmp_path):
    env = {**os.environ, "FT_BANG_COMMAND_CHECK": str(tmp_path / "nope.py"), "FT_BANG_COMMAND_LOG": str(tmp_path / "gate.log")}
    r = subprocess.run(["bash", str(HOOK)], input=ask(question=BAD), capture_output=True, text=True, env=env)
    assert r.returncode == 0 and r.stdout.strip() == ""


def test_checker_missing_warns_on_stderr(tmp_path):
    env = {**os.environ, "FT_BANG_COMMAND_CHECK": str(tmp_path / "nope.py"), "FT_BANG_COMMAND_LOG": str(tmp_path / "gate.log")}
    r = subprocess.run(["bash", str(HOOK)], input=ask(question=BAD), capture_output=True, text=True, env=env)
    warns = [ln for ln in r.stderr.splitlines() if ln.startswith("WARN bang-command-gate:")]
    assert r.returncode == 0 and r.stdout.strip() == "" and len(warns) == 1
    assert "nope.py" in warns[0] and "검사 없이 허용(R106)" in warns[0]


def test_checker_broken_import_warns_on_stderr(tmp_path):
    broken = tmp_path / "broken.py"
    broken.write_text("def violations(:\n", encoding="utf-8")
    env = {**os.environ, "FT_BANG_COMMAND_CHECK": str(broken), "FT_BANG_COMMAND_LOG": str(tmp_path / "gate.log")}
    r = subprocess.run(["bash", str(HOOK)], input=ask(question=BAD), capture_output=True, text=True, env=env)
    warns = [ln for ln in r.stderr.splitlines() if ln.startswith("WARN bang-command-gate:")]
    assert r.returncode == 0 and r.stdout.strip() == "" and len(warns) == 1 and "broken.py" in warns[0]


def test_unparsable_stdin_warns_on_stderr(tmp_path):
    r = run("{not json", tmp_path)
    warns = [ln for ln in r.stderr.splitlines() if ln.startswith("WARN bang-command-gate:")]
    assert r.returncode == 0 and r.stdout.strip() == "" and len(warns) == 1
