"""R135a 비밀 출력 경로 판정기 ft_secret_judge — 비밀을 stdout 으로 내는 명령이 화면·파이프로 가면 reject.
값은 전부 가짜(FAKE…·***) — 실제 gcloud·op·security 호출 0 (판정기는 문자열만 본다)."""
import importlib.util
import json
import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
BIN = ROOT / "harness/bin"
TPL = ROOT / "harness/kit/fable-team/templates/hooks"
KIT_BIN = ROOT / "harness/kit/fable-team/bin"
JUDGE = BIN / "ft_secret_judge.py"
GATE_ENV = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}


def _load(path=JUDGE):
    spec = importlib.util.spec_from_file_location("ft_secret_judge_t", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


J = _load()

REJECT = [
    'gcloud secrets versions access x 2>&1 >/dev/null | head',  # ① 이번 사고 모양
    "gcloud secrets versions access x",  # ② 맨 실행
    "gcloud secrets versions access latest --secret=x --project=p",
    "gcloud secrets versions access x | tee f",  # ③
    "op read op://v/i/f",  # ④
    "op item get i --reveal",
    "security find-generic-password -s x -w",  # ⑤
    "gh auth token",  # ⑥
    "echo $SLACK_WEBHOOK_URL",  # R307 범위 2 — webhook 주소도 비밀 이름
    "printenv OPS_ADMIN_SLACK_WEBHOOK",
    "printenv",  # ⑦
    "env",
    "env -i",  # R307 — 실행할 명령 없이 옵션·대입만 붙은 env 도 전체 출력
    "env $=U",
    "env FOO=1",
    "env FOO=1 BAR=2",
    "env -u GIT_DIR",
    "env -u GIT_DIR -u GIT_WORK_TREE",
    "env --unset=GIT_DIR",
    "env -uGIT_DIR",
    "env -C /tmp",
    "env -0",
    "env $X",
    "env ${X}",
    "env -u GIT_DIR $CMD",  # 첫 낱말이 순수 변수 펼침
    "env -u GIT_DIR FOO=1 $CMD -q",
    "sudo env FOO=1",
    "cat secrets/x",  # ⑧
    "cat a.cred",
    "cat .env",
    "head -c 4 ./secrets/db",
    "grep -v '^#' .env.local",
    "echo $PGPASSWORD",  # ⑨
    'printf %s "$API_TOKEN"',
    "echo ${DB_DSN}",
    "secret x",  # ⑩ 래퍼 맨 호출
    "secret x | head",
    "cd /tmp && gcloud secrets versions access x",  # 뒷 구간도 본다
    'echo "$(gcloud secrets versions access x)"',  # 치환이 인자로 새어 나감
    "sudo gh auth token",
    "gcloud secrets versions access x 2>&1 >/tmp/f",  # 2>&1 이 > 보다 앞이면 항상
    "gcloud secrets versions access x > /dev/stdout",
    "cat <<EOF\n$(gcloud secrets versions access FAKE)\nEOF",  # C1 비인용 heredoc 본문의 치환은 실행된다
    "cat <<EOF | head\n`gh auth token`\nEOF",
    "cat <<-EOF\n  $(secret x)\nEOF",
    "cat <<EOF\n$API_TOKEN\nEOF",  # 교정 2 — 비인용 본문의 비밀 변수 확장
    "cat <<EOF\nkey=${API_TOKEN}\nEOF",
    "cat <<EOF\n${PGPASSWORD:-none}\nEOF",
    "diff .env .env.example",  # R219 — 기준값 ② 7줄
    "sed -n 1,20p .env",
    "awk -F= '{print}' secrets/x.cred",
    "python3 -c 'import os; print(os.environ)'",
    "python3 -c 'import os;print(dict(os.environ))'",
    "git diff -- .env",
    "git show HEAD:.env",
    "cmp -l .env .env.bak",  # R219 ⓐ 모양별 양성
    "paste .env",
    "sort secrets/db | head",
    "sed 's/a/b/' .env",
    "sed -n '/KEY/p' .env.local",
    "awk '{print $0}' a.cred",
    "awk '/TOKEN/' .env",
    "awk '{print $1}' .env",  # -F= 없이는 첫 칸에 값이 섞인다
    "python3 -c 'from os import environ; print(environ.items())'",
    "python3 -c 'print(open(\".env\").read())'",
    "python3 -c 'import sys;print(open(sys.argv[1]).read())' .env",
    "node -e 'console.log(process.env)'",
    "node -e 'console.log(JSON.stringify(process.env))'",
    "ruby -e 'puts ENV.to_h'",
    "perl -e 'print %ENV'",
    "git log -p -- .env",
    "git cat-file -p HEAD:secrets/x",
    "git blame .env",
    "git -C /tmp/r diff -- .env",
    "cut -f2 .env",  # R219 교정 1 ⓔ — 첫 칸 외 필드·글자
    "cut -d= -f1- .env",
    "cut -c1-5 secrets/x",
    "cut -f2 < .env",
    "base64 .env",  # ⓕ
    "base64 -i secrets/x",
    "jq . secrets/x.json",
    "yq . .env.local",
    "hexdump -C .env",
    "iconv -f utf-8 -t ascii .env",
    "cat < .env",  # ⓖ 입력 재지정
    "sed p < .env",
    "export -p",  # ⓗ
    "declare -p",
    "declare -px",
    "declare -x",
    "typeset -p",
    "set",
    "declare -p API_TOKEN",
    "bash -c 'cat .env'",  # ⓘ
    "sh -c 'echo $API_TOKEN'",
    "zsh -c 'env'",
    "eval cat .env",
    "bash -c \"bash -c 'cat .env'\"",
    "tee < .env",  # R219 교정 2 ⓙ — 안전 목록 밖 전부 거절
    "tee /tmp/f < .env",
    "dd < .env",
    "cp .env /dev/stdout",  # ⓚ
    "cp .env -",
    "install secrets/x /dev/stderr",
    "cp .env /dev/fd/1",
    "dd if=.env",  # ⓛ
    "dd if=secrets/x of=/dev/stdout",
    "sed -n -ep .env",  # R219 교정 3 H1 — sed -e 붙임·분리·= 형식
    "sed -n --expression=p ./.env",
    "sed -n -e p .env",
    "sed -ne p .env",
    "sed -n --expression p .env",
    "sed -n -f s.sed .env",
    "awk -F= '{print $1}1' .env",  # H2 — 키 전용 한 꼴 밖은 거절
    "awk -F= '{print $1} {print $2}' .env",
    "awk -F= '{print $1;print}' .env",
    "awk -F= '{print NR}' .env",
    "python3 -c 'print(len([]));print(open(\".env\").read())'",  # H3 — len 등으로 면제 0
    "python3 -c 'print(sorted(json.load(open(\"a.cred\"))))'",
    "python3 -c 'print(len([]));print(open(sys.argv[1]).read())' .env",
    "sed -n -f./print.sed .env",  # R219 교정 4 H1 — -f 붙임·분리·복합 옵션
    "sed -n -f/tmp/print.sed .env",
    "sed -nf x .env",
    "sed -n --file=x .env",
    "awk -Ffoo= '{print $1}' .env",  # H2 — 유효 FS 가 정확히 `=` 아닐 때
    "awk -F= -F: '{print $1}' .env",
    "awk -v FS=: '{print $1}' .env",
    "awk -F= '{print $1}' FS=: .env",
]

OK = [
    'X="$(gcloud secrets versions access x 2>/dev/null)"',  # ⓐ
    'X="$(secret x)" || exit 1',  # ⓑ
    "gcloud secrets versions access x >/tmp/f 2>/dev/null",  # ⓒ
    "gcloud secrets versions access x >/dev/null 2>&1",
    "gcloud secrets versions access x &>/tmp/f",
    "cut -d= -f1 .env",  # ⓓ
    "wc -c secrets/x",  # ⓔ
    'curl -sS -X POST --data @p.json "$SLACK_WEBHOOK_URL"',  # R307 범위 2 — 값을 인자로 쓰는 것은 출력이 아니다
    "bash scripts/ops/credit-burn-notify.sh",  # 스크립트 안의 $WEBHOOK 은 판정 대상 아님
    "test -s a.cred",
    "echo ${#PW}",  # ⓕ
    '[ -n "$PW" ]',
    "python3 -c 'import json,sys;print(sorted(json.load(open(sys.argv[1]))))' a.cred",  # ⓖ
    "gcloud secrets list",  # ⓗ
    'export PGPASSWORD="$(secret x)"',
    'PW="$(secret x)" psql -c "select 1"',
    "X=$(op read op://v/i/f)",
    "cat .env.example",
    "grep -c TOKEN secrets/x",
    "echo 'password=$PGPASSWORD'",  # 작은따옴표 안은 글자
    "mbox.sh send a b \"gcloud secrets versions access x 는 쓰지 말 것\"",  # 쪽지 본문 글자
    "git commit -m 'gh auth token 거절 추가'",
    "cat <<'EOF' > /tmp/n.md\ngcloud secrets versions access x\nEOF",  # heredoc 본문은 글자
    "cat <<EOF > /tmp/f\n$(gcloud secrets versions access FAKE)\nEOF",  # 파일로만 가면 허용
    "cat <<'EOF'\n$(gcloud secrets versions access FAKE)\nEOF",  # 인용 delimiter 본문은 글자
    'cat <<"EOF"\n`gh auth token`\nEOF',
    "cat <<\\EOF\n$(gcloud secrets versions access FAKE)\nEOF",
    "cat <<EOF\nplain text gh auth token \\$(gh auth token)\nEOF",  # 비인용이어도 \\$( 는 글자
    "cat <<EOF > /tmp/f\n$API_TOKEN\nEOF",  # 파일로만
    "cat <<'EOF'\n$API_TOKEN\nEOF",  # 인용 본문은 글자
    "cat <<EOF\nhome=$HOME n=$1 pid=$$ \\$API_TOKEN\nEOF",  # 비밀 아닌 변수·\\$ 는 글자
    "secret() {\n  X=$(gcloud secrets versions access latest --secret=\"$1\" 2>\"$e\")\n}",  # 래퍼 정의
    "diff -q .env .env.bak",  # R219 — 통과가 맞는 것
    "diff --brief .env .env.bak",
    "diff .env.example .env.sample",
    "cmp -s .env .env.bak",
    "git diff --stat",
    "git diff --name-only -- .env",
    "git diff -- src/app.py",
    "git show HEAD:.env.example",
    "git log --oneline -- .env",
    "git cat-file -t HEAD:.env",
    "python3 -c 'import os; print(os.environ.get(\"HOME\"))'",
    "python3 -c 'import os; print(os.environ[\"HOME\"])'",
    "python3 -c 'import os; print(sorted(os.environ))'",
    "python3 -c 'import os; print(len(os.environ))'",
    "node -e 'console.log(process.env.NODE_ENV)'",
    "node -e 'console.log(Object.keys(process.env))'",
    "ruby -e 'puts ENV[\"HOME\"]'",
    "perl -e 'print $ENV{HOME}'",
    "awk -F= '{print $1}' .env",
    "awk -F= '{print $1}' secrets/x.cred",
    "sed -n 1,5p README.md",
    "sed -n '/KEY/d' .env",
    "sed -i 's/a/b/' .env",
    "sed 's/a/b/' .env > /tmp/f",
    "diff .env .env.bak > /dev/null",
    "python3 script.py .env",
    "cut -d= -f1 < .env",  # R219 교정 1 — 통과가 맞는 것
    "wc -c < .env",
    "read X < .env",
    "jq 'keys' secrets/x.json",
    "jq 'keys[]' secrets/x.json",
    "jq . package.json",
    "base64 README.md",
    "env -u GIT_DIR pytest -q",  # R307 — 글자 명령이 있으면 그 명령을 판정(정상 시험 머리)
    "env FOO=1 pytest -q",
    "env -u GIT_DIR -u GIT_WORK_TREE /path/python -m pytest -q",
    "env -i FOO=1 pytest -q",
    "env --unset=GIT_DIR pytest -q",
    "env -C /tmp make",
    "env -S 'pytest -q'",
    "set -e",
    "set -euo pipefail",
    "export FOO=bar",
    "declare -x API_KEY=abc",
    "declare -p PATH",
    "bash -c 'ls'",
    "bash -lc 'ls -la'",
    "bash -c 'cat .env' > /tmp/f",
    "eval \"$(ssh-agent -s)\"",
    "cp .env .env.bak",  # R219 교정 2 — 통과가 맞는 것
    "dd if=.env of=/tmp/b",
    "grep -c KEY < .env",
    "shasum .env",
    "shasum < .env",
    "tee < README.md",
    "tee < .env > /tmp/f",
    "cp README.md /dev/stdout",
    "sed -n -e 1d .env",  # R219 교정 3 — 통과가 맞는 것
    "sed -n -e '/K/d' .env",
    "sed -i -e p .env",
    "awk -F = '{ print $1 }' .env",
    "awk -F: -F= '{print $1}' .env",  # R219 교정 4 — 마지막 -F 가 `=` 면 통과
    "sed -i.bak p .env",
    "sed -s -n '$d' .env",
    "sed -l 5 -n 1d .env",
]

ORDINARY = [  # 오탐 표본 — 평범한 명령 20개
    "git log --oneline -5", "pytest -q tests/scripts/test_x.py", "grep TOKEN_ src/app.py", "echo $HOME", "ls -la",
    "git status --short", "ruff check .", "rg -n 'secret' scripts/", "cat README.md", "head -20 docs/token-rotation.md",
    "tail -f /tmp/byz-gateway.log", "python3 -m pytest -x", "npm run build", "echo hello && echo done", "cd src && ls",
    "docker ps --filter name=redis", "gcloud run services list", "gh pr view 12", "printenv HOME", "git diff HEAD~1 -- a.py",
]

# R307 r2 (DA⑥ r1 HOLD) — «env 가 실제로 실행할 명령» 을 글자로 확정할 수 없으면 거절
WRAPPERS_T = ["nice -n 5", "timeout 5", "timeout -s KILL 5", "stdbuf -oL", "xargs", "caffeinate -i", "script -q /dev/null",
              "unbuffer", "chronic", "ionice -c 3", "taskset -c 0", "taskset 0x1", "exec -a x"]  # H1 — 래퍼 뒤 env·printenv·set·export -p
REJECT += [w + " " + c for w in WRAPPERS_T for c in ("env", "printenv", "set", "export -p")] + [
    "timeout 5 env -u GIT_DIR",  # H1 — 래퍼 뒤 env 접두도 같은 판정
    "env $(which python) -V",  # H2 — 치환·백틱·$@·${X:-}·$X$Y·$1 로 시작하면 글자 명령이 아니다
    "env FOO=1 $(which python) -V",
    "env `which python`",
    'env "$@"',
    "env ${CMD:-}",
    "env $X$Y",
    "env $1",
    'env "$PY" -m pytest',
    'env -u GIT_DIR "$@"',
    "env $(true)",
    "env -S \"\"",  # H3 — -S 값은 명령 본문: 비면 전체 출력 · 있으면 재판정
    'env -S "printenv"',
    'env -S "env -u X"',
    "env -Sprintenv",
    "env --split-string=printenv",
    "env --split-string printenv",
    'env -S "$CMD"',
]
OK += [
    'env -S "python -V"',  # H3 — 글자 명령 본문은 통과
    "env -- -u X",  # H4 — -- 뒤는 옵션이 아니라 명령
    "env -- pytest -q",
    "timeout 5 pytest -q",  # H1 — 래퍼 뒤가 글자 명령이면 통과
    "nice -n 5 python -V",
    "xargs -n1 echo",
    "exec -a x pytest -q",
    "taskset -c 0 pytest -q",
]


@pytest.mark.parametrize("cmd", REJECT)
def test_reject(cmd):
    verdict, why = J.judge(cmd)
    assert verdict == "reject" and why


@pytest.mark.parametrize("cmd", OK + ORDINARY)
def test_ok(cmd):
    assert J.judge(cmd) == ("ok", "")


def test_plan_rejects_unresolvable_env_command_lines():  # H2 — --plan 도 같은 판정
    found = J.plan('echo start\nenv $X\nenv "$@"\nenv ${CMD:-}\nenv -u GIT_DIR pytest -q\n')
    assert [ln for ln, _ in found] == [2, 3, 4]


def test_reject_reason_never_quotes_command_text():
    _, why = J.judge("gcloud secrets versions access FAKEVALUE123 | head")
    assert "FAKEVALUE123" not in why and "head" not in why


def test_judge_is_fast_enough_for_every_bash_call():  # R219 — 훅은 모든 Bash 앞에서 돈다: 1회 ≤ 0.2 s (100회 평균)
    import time
    cmds = (REJECT + OK + ORDINARY) * 2
    t0 = time.monotonic()
    for c in cmds[:100]:
        J.judge(c)
    assert (time.monotonic() - t0) / 100 <= 0.2


def _judge_without(tmp_path, missing):  # 동봉 모듈 하나가 빠진 설치를 흉내 낸 판정기 사본
    d = tmp_path / "jx"
    d.mkdir()
    for name in ("ft_secret_judge.py", "ft_secret_lex.py", "ft_secret_targets.py", "ft_secret_sinks.py"):
        if name != missing:
            (d / name).write_bytes((BIN / name).read_bytes())
    return d / "ft_secret_judge.py"


@pytest.mark.parametrize("missing", ["ft_secret_sinks.py", "ft_secret_targets.py", "ft_secret_lex.py"])
def test_missing_module_is_internal_error_rc2_not_reject_rc1(tmp_path, missing):  # H4 — judge 단독 CLI
    r = subprocess.run(["python3", "-I", str(_judge_without(tmp_path, missing)), "ls"], capture_output=True, text=True, env=GATE_ENV)
    assert r.returncode == 2 and r.stdout == "" and "내부 오류" in r.stderr


def test_missing_module_keeps_hook_wrapper_fail_open(tmp_path):  # H4 — 기존 wrapper 는 rc2 도 통과(rc0)+원장 1줄
    r = _hook("gh auth token", tmp_path, judge=_judge_without(tmp_path, "ft_secret_sinks.py"))
    assert r.returncode == 0 and r.stdout.strip() == "" and "판정기 실패(rc=2)" in stderr_of(r)
    assert "rc=2" in (tmp_path / "guard.log").read_text()


def test_cli_ok_and_reject():
    def run(*a, **k):
        return subprocess.run(["python3", "-I", str(JUDGE), *a], capture_output=True, text=True, env=GATE_ENV, **k)

    r = run("git status")
    assert (r.returncode, r.stdout.strip()) == (0, "ok")
    r = run("gh auth token")
    assert r.returncode == 1 and r.stdout.startswith("reject ")
    r = run("-", input="gh auth token")
    assert r.returncode == 1 and r.stdout.startswith("reject ")


def stderr_of(r):
    """LC_ALL 이 이 머신에 없으면 bash 가 첫 줄에 setlocale 경고를 붙인다 — 그 줄만 뺀다(다른 stderr 는 그대로)."""
    return "".join(ln for ln in r.stderr.splitlines(keepends=True) if not ln.startswith("bash: warning: setlocale"))


def _fake_gcloud(tmp_path, body):
    d = tmp_path / "bin"
    d.mkdir()
    (d / "gcloud").write_text("#!/bin/sh\n" + body + "\n")
    (d / "gcloud").chmod(0o755)
    return {**GATE_ENV, "PATH": f"{d}:{os.environ['PATH']}", "LIB": str(BIN / "ft-secret-lib.sh")}


def _secret(tmp_path, body, name="x"):
    env = _fake_gcloud(tmp_path, body)
    return subprocess.run(["bash", "-c", f'. "$LIB"; V="$(secret {name})"; rc=$?; echo "rc=$rc len=${{#V}}"'],
                          capture_output=True, text=True, env=env)


def test_lib_secret_success_returns_value_in_variable_only(tmp_path):
    r = _secret(tmp_path, "printf FAKEVALUE")
    assert r.stdout.strip() == "rc=0 len=9" and "FAKEVALUE" not in stderr_of(r)


def test_lib_secret_failure_is_nonzero_with_short_reason(tmp_path):
    r = _secret(tmp_path, "echo 'FAKEERR '$(printf 'e%.0s' $(seq 1 300)) >&2; exit 1")
    assert r.stdout.strip() == "rc=1 len=0" and 0 < len(stderr_of(r)) < 220 and "FAKEVALUE" not in stderr_of(r)


def test_lib_secret_empty_value_is_nonzero(tmp_path):
    assert _secret(tmp_path, "printf ''").stdout.strip() == "rc=1 len=0"


def _hook(cmd, tmp_path, judge=None):
    env = {**GATE_ENV, "FT_SECRET_GUARD_LOG": str(tmp_path / "guard.log")}
    if judge is not None:
        env["FT_SECRET_JUDGE"] = str(judge)
    stdin = json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}}, ensure_ascii=False)
    return subprocess.run(["bash", str(TPL / "secret-output-guard.sh")], input=stdin, capture_output=True, text=True, env=env)


def test_hook_denies_incident_shape_with_message(tmp_path):
    r = _hook("gcloud secrets versions access FAKEVALUE123 2>&1 >/dev/null | head", tmp_path)
    out = json.loads(r.stdout)["hookSpecificOutput"]
    assert r.returncode == 0 and out["permissionDecision"] == "deny"
    assert out["permissionDecisionReason"].startswith("REJECT 비밀 출력 경로") and "FAKEVALUE123" not in r.stdout
    assert '${#X}' in out["permissionDecisionReason"] and "BOOT 22" in out["permissionDecisionReason"]


def test_hook_ok_command_is_silent(tmp_path):
    r = _hook('X="$(secret x)" || exit 1', tmp_path)
    assert r.returncode == 0 and r.stdout.strip() == ""


def test_hook_judge_crash_fails_open_and_logs(tmp_path):
    bad = tmp_path / "bad.py"
    bad.write_text("raise SystemExit(7)\n")
    r = _hook("gh auth token", tmp_path, judge=bad)
    assert r.returncode == 0 and r.stdout.strip() == "" and "판정기 실패" in stderr_of(r)
    assert (tmp_path / "guard.log").read_text().strip() != ""


def test_hook_unparsable_stdin_fails_open(tmp_path):
    env = {**GATE_ENV, "FT_SECRET_GUARD_LOG": str(tmp_path / "guard.log")}
    r = subprocess.run(["bash", str(TPL / "secret-output-guard.sh")], input="not json", capture_output=True, text=True, env=env)
    assert r.returncode == 0 and r.stdout.strip() == ""


def test_kit_copies_are_byte_identical():
    for name in ("ft_secret_judge.py", "ft_secret_lex.py", "ft_secret_targets.py", "ft_secret_sinks.py"):
        assert (BIN / name).read_bytes() == (TPL / name).read_bytes() == (KIT_BIN / name).read_bytes()
    for name in ("ft-secret-lib.sh", "ft-hil.sh"):
        assert (BIN / name).read_bytes() == (KIT_BIN / name).read_bytes()


def _secret_timed(tmp_path, body, **env_extra):
    import time
    env = {**_fake_gcloud(tmp_path, body), **env_extra}
    t0 = time.monotonic()
    r = subprocess.run(["bash", "-c", '. "$LIB"; V="$(secret x)"; rc=$?; echo "rc=$rc len=${#V}"'], capture_output=True, text=True, env=env, timeout=40)
    return r, time.monotonic() - t0


def test_lib_secret_hung_gcloud_times_out_at_7s_with_one_retry(tmp_path):  # C2 — 7초 attempt + retry 1
    r, took = _secret_timed(tmp_path, "sleep 8; printf FAKE_ONLY")
    assert r.stdout.strip() == "rc=1 len=0" and "FAKE_ONLY" not in r.stdout + stderr_of(r)
    assert "시간 초과" in stderr_of(r) and 13.5 < took < 16.5  # 7초 + 7초(재시도 1회), 8초에 성공하는 호출은 기다리지 않는다


def test_lib_secret_retry_recovers_after_a_hang(tmp_path):
    body = f'if [ -e "{tmp_path}/seen" ]; then printf FAKEVALUE; else : >"{tmp_path}/seen"; sleep 8; fi'
    r, took = _secret_timed(tmp_path, body, FT_SECRET_TIMEOUT_S="1")
    assert r.stdout.strip() == "rc=0 len=9" and took < 5


def test_lib_secret_timeout_env_can_only_shrink(tmp_path):
    r, took = _secret_timed(tmp_path, "sleep 30", FT_SECRET_TIMEOUT_S="600")
    assert r.stdout.strip() == "rc=1 len=0" and took < 16.5


def test_lib_secret_term_ignoring_gcloud_returns_within_limit_plus_grace(tmp_path):  # 교정 2 — 반환 마감 ≤ limit+1초
    r, took = _secret_timed(tmp_path, 'trap "" TERM; sleep 4; printf FAKE_ONLY', FT_SECRET_TIMEOUT_S="1")
    assert r.stdout.strip() == "rc=1 len=0" and "FAKE_ONLY" not in r.stdout + stderr_of(r)
    assert took < 6.5  # 2시도 × (1 + 1 유예) ≈ 4초 — TERM 을 무시해도 wait 가 4초×2 를 기다리지 않는다
    assert subprocess.run(["pgrep", "-f", f"{tmp_path}/bin"], capture_output=True).returncode != 0  # 남은 자식 0
