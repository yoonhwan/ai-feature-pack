"""R135a ft-hil.sh --add 계획 파일 비밀 출력 경로 검사 — 걸리면 등록 0·계획 파일 수정 0. 값은 전부 가짜."""
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HIL = ROOT / "harness/bin/ft-hil.sh"
GATE_ENV = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}

HEAD = "#!/usr/bin/env bash\nset -euo pipefail\n"
LOOKUP = 'SEC="$(gcloud secrets versions access latest --secret=fake-name)"\n'
CREATE = 'gcloud scheduler jobs create http fake-job --uri=https://example.invalid --headers="X-Token=$SEC"'


def stderr_of(r):
    """LC_ALL 이 이 머신에 없으면 bash 가 첫 줄에 setlocale 경고를 붙인다 — 그 줄만 뺀다(다른 stderr 는 그대로)."""
    return "".join(ln for ln in r.stderr.splitlines(keepends=True) if not ln.startswith("bash: warning: setlocale"))


def add(tmp_path, body, judge=None):
    plan = tmp_path / "plan.sh.hil"
    plan.write_text(body)
    hil = tmp_path / "hil"
    env = {**GATE_ENV, "HIL_DIR": str(hil), "HIL_CLIP": "0"}
    if judge is not None:
        env["FT_SECRET_JUDGE"] = str(judge)
    r = subprocess.run(["bash", str(HIL), "--add", str(plan)], capture_output=True, text=True, env=env)
    links = sorted(p.name for p in hil.glob("h[0-9]*")) if hil.exists() else []
    return r, links, plan


def test_arg_passing_with_output_to_screen_is_rejected_and_not_registered(tmp_path):  # 1365 꼴
    body = HEAD + LOOKUP + CREATE + "\nunset SEC\n"
    r, links, plan = add(tmp_path, body)
    assert r.returncode != 0 and links == [] and plan.read_text() == body
    assert stderr_of(r).startswith("REJECT 계획 파일 비밀 출력 경로 — 4 ")
    assert "fake-name" not in stderr_of(r) and "X-Token" not in stderr_of(r)


def test_same_plan_with_devnull_is_registered(tmp_path):
    r, links, _ = add(tmp_path, HEAD + LOOKUP + CREATE + " >/dev/null\nunset SEC\n")
    assert r.returncode == 0 and links == ["h1"] and r.stdout.strip() == f"! bash {tmp_path}/hil/h1"


def test_format_flag_narrows_output_and_is_registered(tmp_path):
    r, links, _ = add(tmp_path, HEAD + LOOKUP + CREATE + " --format='value(name)'\nunset SEC\n")
    assert r.returncode == 0 and links == ["h1"]


def test_incident_shape_line_number_is_reported(tmp_path):
    r, links, _ = add(tmp_path, HEAD + "echo start\ngcloud secrets versions access x 2>&1 >/dev/null | head\n")
    assert r.returncode != 0 and links == [] and stderr_of(r).startswith("REJECT 계획 파일 비밀 출력 경로 — 4 ")


def test_set_x_is_rejected(tmp_path):
    r, links, _ = add(tmp_path, HEAD + "set -x\n" + LOOKUP + "unset SEC\n")
    assert r.returncode != 0 and links == [] and "set -x" in stderr_of(r)


def test_echo_of_tracked_secret_variable_is_rejected(tmp_path):
    r, links, _ = add(tmp_path, HEAD + LOOKUP + 'echo "got $SEC"\nunset SEC\n')
    assert r.returncode != 0 and links == []


def test_safe_header_template_is_registered(tmp_path):
    body = (HEAD + "source /x/ft-secret-lib.sh\nset +x\n" + 'PW="$(secret fake-name)" || exit 1\n'
            + 'export PGPASSWORD="$PW"\n[ -n "$PW" ] || exit 1\necho "len=${#PW}"\npsql -c "select 1" >/dev/null\nunset PW\n')
    r, links, _ = add(tmp_path, body)
    assert r.returncode == 0 and links == ["h1"]


def test_own_secret_function_body_is_not_flagged(tmp_path):  # 옛 계획(1295·1454)의 secret() 정의
    body = (HEAD + 'secret() {\n  local out\n  out="$(gcloud secrets versions access latest --secret="$1" 2>/dev/null)" || return 1\n'
            + "  printf '%s' \"$out\"\n}\nPW=\"$(secret fake-name)\" || exit 1\nunset PW\n")
    r, links, _ = add(tmp_path, body)
    assert r.returncode == 0 and links == ["h1"]


def test_missing_judge_warns_and_registers(tmp_path):
    r, links, _ = add(tmp_path, HEAD + LOOKUP + CREATE + "\n", judge=tmp_path / "nope.py")
    assert r.returncode == 0 and links == ["h1"] and "WARN" in stderr_of(r)


def test_cmd_form_goes_through_same_check(tmp_path):
    env = {**GATE_ENV, "HIL_DIR": str(tmp_path / "hil"), "HIL_CLIP": "0"}
    r = subprocess.run(["bash", str(HIL), "--cmd", "gh auth token"], capture_output=True, text=True, env=env)
    assert r.returncode != 0 and stderr_of(r).startswith("REJECT 계획 파일 비밀 출력 경로")


PLAN = ROOT / "harness/design/harness/PLAN-r135a-install-20261013.sh.hil"
TPL_REL = "harness/kit/fable-team/templates/hooks"
HOOKS = ROOT / TPL_REL


def test_install_plan_passes_its_own_lint(tmp_path):
    r, links, _ = add(tmp_path, PLAN.read_text())
    assert r.returncode == 0 and links == ["h1"]


def _git(repo, *a):
    return subprocess.run(["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@t", *a], capture_output=True, text=True, env=GATE_ENV, check=True).stdout.strip()


def _fake_repo(tmp_path):  # 랜딩 커밋을 흉내 내는 가짜 저장소 — 훅 3파일만 담는다
    repo = tmp_path / "repo"
    (repo / TPL_REL).mkdir(parents=True)
    for name in ("secret-output-guard.sh", "ft_secret_judge.py", "ft_secret_lex.py"):
        (repo / TPL_REL / name).write_bytes((HOOKS / name).read_bytes())
    _git(repo, "init", "-q")
    _git(repo, "add", ".")
    _git(repo, "commit", "-qm", "landed")
    return repo, _git(repo, "rev-parse", "HEAD")


def _install(home, repo, landed):
    env = {**GATE_ENV, "HOME": str(home), "R135A_REPO": str(repo)}
    if landed:
        env["R135A_LANDED"] = landed
    return subprocess.run(["bash", str(PLAN)], capture_output=True, text=True, env=env)


def _fake_home(tmp_path):
    (tmp_path / ".claude/hooks").mkdir(parents=True)
    s = tmp_path / ".claude/settings.json"
    s.write_text(json.dumps({"env": {"A": "1"}, "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "x"}]}]}}))
    return s


def test_install_plan_stops_without_or_with_unknown_landed_sha(tmp_path):  # 진짜 ~/.claude 는 건드리지 않는다
    repo, _ = _fake_repo(tmp_path)
    s = _fake_home(tmp_path)
    before = s.read_text()
    for landed in ("", "not-a-sha", "0" * 40):
        r = _install(tmp_path, repo, landed)
        assert r.returncode != 0 and "STOP" in r.stderr
    assert s.read_text() == before and not (tmp_path / ".claude/settings.json.bak-r135").exists()
    assert list((tmp_path / ".claude/hooks").iterdir()) == []


def test_install_plan_installs_three_files_and_one_entry_once_from_landed_sha(tmp_path):
    repo, sha = _fake_repo(tmp_path)
    s = _fake_home(tmp_path)
    (repo / TPL_REL / "ft_secret_lex.py").write_text("# 랜딩 뒤 루트 체크아웃에서 바뀐 파일\n")  # 루트의 «현재 파일» 은 설치본이 아니다
    assert _install(tmp_path, repo, sha).returncode == 0
    assert _install(tmp_path, repo, sha).returncode == 0  # 두 번째는 건너뜀
    d = json.loads(s.read_text())
    cmds = [h["command"] for e in d["hooks"]["PreToolUse"] for h in e["hooks"]]
    assert cmds == ["x", "$HOME/.claude/hooks/secret-output-guard.sh"] and d["env"] == {"A": "1"}
    assert json.loads((tmp_path / ".claude/settings.json.bak-r135").read_text())["hooks"]["PreToolUse"][0]["hooks"][0]["command"] == "x"
    for name in ("secret-output-guard.sh", "ft_secret_judge.py", "ft_secret_lex.py"):
        assert (tmp_path / ".claude/hooks" / name).read_bytes() == (HOOKS / name).read_bytes()
