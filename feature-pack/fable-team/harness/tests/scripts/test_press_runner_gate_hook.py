"""R106c 훅 press-runner-gate — PreToolUse:Bash. press 러너 실행 → ft-press-gate 경유 · 막힘 → deny · 읽기 명령·무관 명령 → 게이트 호출 0."""
import json
import os
import subprocess
from pathlib import Path

import pytest
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

ROOT = Path(__file__).resolve().parents[3]
HOOK = ROOT / "harness/kit/fable-team/templates/hooks/press-runner-gate.sh"
RUNNER = "tests/e2e/realtime_multi_e2e.py"
STUB = '#!/bin/bash\necho "$@" > "$STUB_OUT"\nenv | grep -E "^(FT_PRESS_CARD|TMUX_PANE|BYZ_PRESS_HUMAN)=" | sort >> "$STUB_OUT"\n[ "${STUB_RC:-0}" = "0" ] || echo "✗ ⑦ 역할 nano — press 는 tester·checker 만(R15)"\nexit "${STUB_RC:-0}"\n'
EXEC_FORMS = [
    f"python3 {RUNNER} --quick",
    f"cd /x/wt && .venv/bin/python /x/wt/{RUNNER} --n 3",
    f"bash -lc 'cd /x && python3 {RUNNER}'",
    f"echo hi && python3 {RUNNER}",
    f"timeout 100 .venv/bin/python {RUNNER}",
    f"nohup python3 {RUNNER} > /tmp/o.log 2>&1 &",
]
READ_FORMS = [f"grep -n main {RUNNER}", f"cat {RUNNER}", f"git show HEAD:{RUNNER}", f"sed -n '1,40p' {RUNNER}", f"rg press {RUNNER} | head", f"bash -lc 'grep -n main {RUNNER}'"]


def make_stub(tmp_path):
    stub = tmp_path / "ft-press-gate.sh"
    stub.write_text(STUB, encoding="utf-8")
    stub.chmod(0o755)
    return stub


def run(cmd, tmp_path, rc=0, stdin=None, gate=True, extra_env=None):
    env = {k: v for k, v in os.environ.items() if not k.startswith(("FT_PRESS_", "BYZ_PRESS_", "TMUX_PANE"))}
    env.update({"FT_PRESS_GATE_BIN": str(make_stub(tmp_path) if gate else tmp_path / "nope.sh"), "STUB_RC": str(rc),
                "STUB_OUT": str(tmp_path / "stub.out"), "FT_PRESS_RUNNER_GATE_LOG": str(tmp_path / "gate.log")})
    env.update(extra_env or {})
    if stdin is None:
        stdin = json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}}, ensure_ascii=False)
    return subprocess.run(["bash", str(HOOK)], input=stdin, capture_output=True, text=True, env=env)


def called(tmp_path):
    return (tmp_path / "stub.out").exists()


def test_exec_forms_blocked_gate_denies_with_x_lines(tmp_path):
    for i, cmd in enumerate(EXEC_FORMS):
        d = tmp_path / str(i)
        d.mkdir()
        r = run(cmd, d, rc=1)
        out = json.loads(r.stdout)["hookSpecificOutput"]
        assert r.returncode == 0 and out["permissionDecision"] == "deny", cmd
        assert "✗ ⑦ 역할 nano" in out["permissionDecisionReason"] and "FT_PRESS_CARD=<카드>" in out["permissionDecisionReason"], cmd
        assert called(d)


def test_exec_forms_pass_gate_allows(tmp_path):
    for i, cmd in enumerate(EXEC_FORMS):
        d = tmp_path / str(i)
        d.mkdir()
        r = run(cmd, d, rc=0)
        assert r.returncode == 0 and r.stdout.strip() == "", cmd
        assert called(d), cmd


def test_read_commands_do_not_call_gate(tmp_path):
    for i, cmd in enumerate(READ_FORMS):
        d = tmp_path / str(i)
        d.mkdir()
        r = run(cmd, d, rc=1)
        assert r.returncode == 0 and r.stdout.strip() == "" and not called(d), cmd


def test_command_without_runner_does_not_call_gate(tmp_path):
    r = run("git status && pytest tests/scripts -q", tmp_path, rc=1)
    assert r.returncode == 0 and r.stdout.strip() == "" and not called(tmp_path)


def test_non_bash_tool_does_not_call_gate(tmp_path):
    stdin = json.dumps({"tool_name": "Read", "tool_input": {"command": f"python3 {RUNNER}"}})
    r = run("", tmp_path, rc=1, stdin=stdin)
    assert r.returncode == 0 and r.stdout.strip() == "" and not called(tmp_path)


def test_gate_missing_denies(tmp_path):
    r = run(f"python3 {RUNNER}", tmp_path, gate=False)
    out = json.loads(r.stdout)["hookSpecificOutput"]
    assert r.returncode == 0 and out["permissionDecision"] == "deny" and "nope.sh" in out["permissionDecisionReason"]


def test_unparsable_stdin_fail_open_with_log(tmp_path):
    r = run("", tmp_path, rc=1, stdin="{not json")
    assert r.returncode == 0 and r.stdout.strip() == "" and not called(tmp_path)
    assert "fail-open" in (tmp_path / "gate.log").read_text(encoding="utf-8")


def test_env_forwarded_to_gate(tmp_path):
    run(f"python3 {RUNNER}", tmp_path, extra_env={"FT_PRESS_CARD": "card.md", "TMUX_PANE": "%7", "BYZ_PRESS_HUMAN": "1"})
    seen = (tmp_path / "stub.out").read_text(encoding="utf-8")
    assert "FT_PRESS_CARD=card.md" in seen and "TMUX_PANE=%7" in seen and "BYZ_PRESS_HUMAN=1" in seen


def test_inline_assignment_forwarded_over_env(tmp_path):
    run(f"FT_PRESS_CARD=inline.md python3 {RUNNER}", tmp_path, extra_env={"FT_PRESS_CARD": "env.md"})
    seen = (tmp_path / "stub.out").read_text(encoding="utf-8")
    assert "FT_PRESS_CARD=inline.md" in seen and "env.md" not in seen


# arch#39 반송 표(staged-r106c-rework-arch39.md) 11줄 — 실행 꼴 양성 일치: 부분 문자열·쪽지 본문·린트·pgrep 은 allow, 모듈 실행(-m)은 deny
PROBES = [
    ('bash .fable-team/comm/mbox.sh send x y "press 는 realtime_multi_e2e.py 로"', False),
    ("pytest tests/e2e/test_realtime_multi_e2e.py -q", False),
    ("ruff check tests/e2e/realtime_multi_e2e.py", False),
    ("find tests -name realtime_multi_e2e.py", False),
    ("pgrep -f realtime_multi_e2e.py", False),
    ("echo realtime_multi_e2e.py", False),
    ('awk "/x/" tests/e2e/realtime_multi_e2e.py', False),
    ("python3 -m py_compile tests/e2e/realtime_multi_e2e.py", False),
    ("python3 tests/e2e/realtime_multi_e2e.py --quick", True),
    ("cd tests/e2e && python3 realtime_multi_e2e.py", True),
    ("python3 -m tests.e2e.realtime_multi_e2e", True),
    ("uv run python tests/e2e/realtime_multi_e2e.py", True),
    ("tests/e2e/realtime_multi_e2e.py --quick", True),
    ("caffeinate -i python3 tests/e2e/realtime_multi_e2e.py", True),
    ("python3 -m pytest tests/e2e/realtime_multi_e2e.py", False),
    # DA⑥ HOLD(2차 반송) — 옵션 «값»(dev·ignore·5·60·.)을 실행 파일 자리로 읽어 빠져나가던 5꼴 + 래퍼 직접 실행 · 인자 속 python 언급은 allow
    ("python3 -X dev tests/e2e/realtime_multi_e2e.py", True),
    ("python3 -W ignore tests/e2e/realtime_multi_e2e.py", True),
    ("nice -n 5 python3 tests/e2e/realtime_multi_e2e.py", True),
    ("caffeinate -t 60 python3 tests/e2e/realtime_multi_e2e.py", True),
    ("uv run --project . python3 tests/e2e/realtime_multi_e2e.py", True),
    ("nohup tests/e2e/realtime_multi_e2e.py --quick", True),
    ("echo python3 tests/e2e/realtime_multi_e2e.py", False),
    ("python3 -c 'print(1)' tests/e2e/realtime_multi_e2e.py", False),
]


@pytest.mark.parametrize("cmd,blocked", PROBES)
def test_probe_table(cmd, blocked, tmp_path):
    r = run(cmd, tmp_path, rc=1)
    assert r.returncode == 0
    assert bool(r.stdout.strip()) is blocked and called(tmp_path) is blocked, cmd
