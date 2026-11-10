"""ft-op-token.sh 시험 (판정 675) — 실 Supabase 호출 0 · 로컬 스텁 서버 + 임시 secrets."""
import base64
import json
import os
import stat
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
KIT_BIN = ROOT / "harness/kit/fable-team/bin"
TOOL = KIT_BIN / "ft-op-token.sh"
STAGED = ROOT / "harness/design/harness/staged-675"
EMAIL = "tester@example.test"
PASSWORD = "Pw-fake-12345"
KEY = "fake-publishable-key"


def b64(obj):
    return base64.urlsafe_b64encode(json.dumps(obj).encode()).rstrip(b"=").decode()


def fake_jwt(exp):
    return f"{b64({'alg': 'none'})}.{b64({'exp': int(exp)})}.sig"


class Stub(ThreadingHTTPServer):
    daemon_threads = True
    mode = "200"
    calls = 0
    token = ""
    delay = 0.0  # r614: 동시 두 등록 시험이 로그인 응답을 겹치게 한다


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        srv = self.server
        srv.calls += 1
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if srv.delay:
            time.sleep(srv.delay)
        if srv.mode == "400":
            code, body = 400, json.dumps({"error": "bad", "password": PASSWORD, "hint": fake_jwt(1)})
        elif srv.mode == "nonjson":
            code, body = 200, "<html>not json</html>"
        elif srv.mode == "500":
            code, body = 500, "boom"
        elif srv.mode == "slow":
            time.sleep(8)
            code, body = 200, json.dumps({"access_token": srv.token})
        else:
            code, body = 200, json.dumps({"access_token": srv.token})
        self.send_response(code)
        self.end_headers()
        self.wfile.write(body.encode())

    def log_message(self, *a):
        pass


@pytest.fixture
def stub():
    s = Stub(("127.0.0.1", 0), Handler)
    s.token = fake_jwt(time.time() + 3600)
    threading.Thread(target=s.serve_forever, daemon=True).start()
    yield s
    s.shutdown()


@pytest.fixture
def env(tmp_path, stub):
    sdir = tmp_path / "secrets"
    sdir.mkdir(mode=0o700)
    sdir.chmod(0o700)
    files = {
        "op-auth.conf": f"SUPABASE_URL=http://127.0.0.1:{stub.server_address[1]}\nSUPABASE_PUBLISHABLE_KEY={KEY}\n",
        "op-accounts.tsv": f"{EMAIL}\tacct.cred\tacct.token\nother@example.test\tother.cred\tother.token\n",
        "acct.cred": json.dumps({"email": EMAIL, "password": PASSWORD}),
    }
    for name, text in files.items():
        (sdir / name).write_text(text)
        (sdir / name).chmod(0o600)
    bin_dir = tmp_path / "stubbin"
    bin_dir.mkdir()
    clip = tmp_path / "clip.txt"
    clip.write_text(PASSWORD + "\n")
    (bin_dir / "pbpaste").write_text(f'#!/bin/sh\ncat "{clip}"\n')
    (bin_dir / "pbcopy").write_text(f'#!/bin/sh\ncat > "{clip}"\n')
    for n in ("pbpaste", "pbcopy"):
        (bin_dir / n).chmod(0o755)
    e = dict(os.environ, FT_OP_SECRETS_DIR=str(sdir), PATH=f"{bin_dir}:{os.environ['PATH']}", FT_OP_TOKEN_ALLOW_HTTP_LOOPBACK="1")
    return {"env": e, "sdir": sdir, "clip": clip}


def run(env, *args, timeout=60):
    return subprocess.run(["bash", str(TOOL), *args], env=env["env"], capture_output=True, text=True, timeout=timeout)


def mode(p):
    return stat.S_IMODE(p.stat().st_mode)


def assert_no_secret(r, stub):
    out = r.stdout + r.stderr
    assert PASSWORD not in out and stub.token not in out and "eyJ" not in out


def test_t1_success_replaces_token(env, stub):
    tf = env["sdir"] / "acct.token"
    tf.write_text("old-token")
    tf.chmod(0o600)
    r = run(env, EMAIL)
    assert r.returncode == 0 and r.stdout.startswith(f"OK {EMAIL} exp=") and "file=acct.token" in r.stdout
    assert tf.read_text() == stub.token and mode(tf) == 0o600
    assert_no_secret(r, stub)


def test_t2_400_no_retry_keeps_old_token(env, stub):
    stub.mode = "400"
    tf = env["sdir"] / "acct.token"
    tf.write_text("old-token")
    tf.chmod(0o600)
    r = run(env, EMAIL)
    assert r.returncode == 1 and r.stdout.startswith(f"ERR {EMAIL} http=400")
    assert stub.calls == 1 and tf.read_text() == "old-token"
    assert_no_secret(r, stub)


def test_t3_500_retries_once(env, stub):
    stub.mode = "500"
    r = run(env, EMAIL)
    assert r.returncode == 1 and "http=500" in r.stdout and stub.calls == 2
    assert not (env["sdir"] / "acct.token").exists()


def test_t4_timeout_7s_then_retry_then_net_err(env, stub):
    stub.mode = "slow"
    t0 = time.time()
    r = run(env, EMAIL)
    assert r.returncode == 1 and "http=net" in r.stdout and stub.calls == 2
    assert time.time() - t0 < 16


def test_t5_no_cred_exits_2_with_init_hint(env):
    (env["sdir"] / "acct.cred").unlink()
    r = run(env, EMAIL)
    assert r.returncode == 2 and "--init" in r.stdout and "acct.cred" in r.stdout


def test_t6_init_success_writes_cred_and_clears_clipboard(env, stub):
    (env["sdir"] / "acct.cred").unlink()
    r = run(env, "--init", EMAIL)
    assert r.returncode == 0 and r.stdout.startswith("OK ")
    cred, tok = env["sdir"] / "acct.cred", env["sdir"] / "acct.token"
    assert json.loads(cred.read_text())["password"] == PASSWORD and mode(cred) == 0o600 and mode(tok) == 0o600
    assert env["clip"].read_text() == ""
    assert_no_secret(r, stub)


def test_t6b_init_failure_writes_no_cred(env, stub):
    (env["sdir"] / "acct.cred").unlink()
    stub.mode = "400"
    r = run(env, "--init", EMAIL)
    assert r.returncode == 1 and not (env["sdir"] / "acct.cred").exists()
    assert not (env["sdir"] / "acct.token").exists() and env["clip"].read_text() == ""  # 실패여도 클립보드 비움(T12)


def test_t6c_init_unknown_email_rejected(env):
    r = run(env, "--init", "nobody@example.test")
    assert r.returncode == 2 and "계정 표에 없음" in r.stdout


def test_t8_loose_secrets_dir_is_err(env):
    env["sdir"].chmod(0o755)
    r = run(env, EMAIL)
    assert r.returncode == 1 and r.stdout.startswith("ERR") and "0700" in r.stdout
    assert mode(env["sdir"]) == 0o755  # 조용한 수정 0


def test_t9_list_shows_remaining_minutes_without_token(env, stub):
    for name, exp in (("acct.token", time.time() + 1800), ("other.token", time.time() - 60)):
        p = env["sdir"] / name
        p.write_text(fake_jwt(exp))
        p.chmod(0o600)
    r = run(env, "--list")
    rows = [ln.split("\t") for ln in r.stdout.strip().splitlines()]
    assert r.returncode == 0 and rows[0][0] == EMAIL and rows[0][2] in ("29분", "30분") and rows[1][2] == "만료"
    assert "eyJ" not in r.stdout


def test_t10_no_real_values_in_tracked_files():
    needles = ["supabase" + ".co", "sb_publi" + "shable_", "@byo" + "urz.com"]
    targets = [KIT_BIN / "ft-op-token.sh", KIT_BIN / "ft_op_token.py"]
    targets += [STAGED / "op-auth.conf.example", STAGED / "op-accounts.tsv.example"]
    for t in targets:
        assert t.exists(), t
        text = t.read_text()
        assert not [n for n in needles if n in text], t


def test_t11_200_non_json_is_one_err_line(env, stub):
    stub.mode = "nonjson"
    tf = env["sdir"] / "acct.token"
    tf.write_text("old-token")
    tf.chmod(0o600)
    r = run(env, EMAIL)
    assert r.returncode == 1 and r.stdout == f"ERR {EMAIL} http=200 msg=응답 JSON 아님\n"
    assert "Traceback" not in r.stderr and "not json" not in r.stdout + r.stderr
    assert stub.calls == 1 and tf.read_text() == "old-token"


def test_t12_init_failure_clears_clipboard(env, stub):
    (env["sdir"] / "acct.cred").unlink()
    stub.mode = "400"
    r = run(env, "--init", EMAIL)
    assert r.returncode == 1 and r.stdout.startswith(f"ERR {EMAIL} http=400")
    assert env["clip"].read_text() == "" and PASSWORD not in r.stdout + r.stderr


def set_url(env, url):
    conf = env["sdir"] / "op-auth.conf"
    conf.write_text(f"SUPABASE_URL={url}\nSUPABASE_PUBLISHABLE_KEY={KEY}\n")
    conf.chmod(0o600)


def test_t13_non_https_url_is_err(env, stub):
    port = stub.server_address[1]
    set_url(env, "http://example.invalid")
    r = run(env, EMAIL)  # 우회 변수 있어도 비루프백 http 는 ERR
    assert r.returncode == 2 and r.stdout.startswith(f"ERR {EMAIL} op-auth.conf SUPABASE_URL 은 https:// 만")
    set_url(env, f"http://127.0.0.1:{port}")
    env["env"].pop("FT_OP_TOKEN_ALLOW_HTTP_LOOPBACK")
    r = run(env, EMAIL)  # 변수 없으면 루프백 http 도 ERR
    assert r.returncode == 2 and "https:// 만" in r.stdout and stub.calls == 0
    env["env"]["FT_OP_TOKEN_ALLOW_HTTP_LOOPBACK"] = "1"
    r = run(env, EMAIL)  # 변수 + 루프백 = 통과
    assert r.returncode == 0 and r.stdout.startswith("OK ") and stub.calls == 1


# ── r605 --init-from-op: 비밀번호를 1Password develop 볼트에서 프로세스 안으로만 ──
OP_ITEM = "opitem5r605"
OP_PASSWORD = "Op-Pw-fake-67890"
OP_DEVELOP_TOKEN = "develop-token-value"


@pytest.fixture
def opstub(tmp_path, env):
    """가짜 op 실행 파일 — argv·env·calls 를 파일로 남기고 body/rc/err/sleep 을 흉내낸다."""
    d = tmp_path / "opstub"
    d.mkdir()
    argv, envtok, body, rc, err, calls = (d / n for n in ("argv", "envtoken", "body", "rc", "err", "calls"))
    script = d / "op"
    script.write_text(
        "#!/bin/sh\n"
        f'echo run >> "{calls}"\n'
        f'printf "%s\\n" "$@" > "{argv}"\n'
        f'printf "%s" "${{OP_SERVICE_ACCOUNT_TOKEN:-}}" > "{envtok}"\n'
        f'[ -f "{d}/sleep" ] && sleep 30\n'
        f'case "$*" in *label=username*) if [ -n "${{STUB_USERNAME:-}}" ]; then printf "%s\\n" "$STUB_USERNAME"; '
        f'else cat "{d}/username" 2>/dev/null; fi ;; *) cat "{body}" 2>/dev/null ;; esac\n'
        f'[ -f "{err}" ] && cat "{err}" >&2\n'
        f'[ -f "{rc}" ] && exit $(cat "{rc}")\n'
        "exit 0\n"
    )
    script.chmod(0o755)
    body.write_text(OP_PASSWORD + "\n")
    (d / "username").write_text(EMAIL + "\n")
    env["env"]["FT_OP_BIN"] = str(script)
    env["env"]["OP_SERVICE_ACCOUNT_TOKEN"] = "kskill-default-token"
    env["env"]["OP_SERVICE_ACCOUNT_TOKEN_DEVELOP"] = OP_DEVELOP_TOKEN
    return {"argv": argv, "envtoken": envtok, "body": body, "rc": rc, "err": err, "calls": calls,
            "sleep": d / "sleep", "dir": d, "userbody": d / "username"}


def _texts(path, skip):
    for p in sorted(Path(path).rglob("*")):
        if p.is_file() and p not in skip:
            yield p, p.read_text(errors="replace")


def test_o1_init_from_op_success(env, stub, opstub):
    """ⓐ op argv·env 고정 · 로그인 OK → cred 저장 · stdout 1줄 OK."""
    (env["sdir"] / "acct.cred").unlink()
    r = run(env, "--init-from-op", OP_ITEM, EMAIL)
    assert r.returncode == 0, r.stdout + r.stderr
    assert r.stdout.startswith(f"OK {EMAIL} exp=") and "file=acct.token" in r.stdout
    assert opstub["argv"].read_text().splitlines() == [
        "item", "get", OP_ITEM, "--vault", "develop", "--fields", "label=password", "--reveal"]
    assert opstub["envtoken"].read_text() == OP_DEVELOP_TOKEN
    cred, tok = env["sdir"] / "acct.cred", env["sdir"] / "acct.token"
    assert json.loads(cred.read_text())["password"] == OP_PASSWORD
    assert mode(cred) == 0o600 and tok.read_text() == stub.token and mode(tok) == 0o600
    assert env["clip"].read_text() == PASSWORD + "\n"  # 클립보드 손 0 — pbpaste/pbcopy 안 부름


def test_o2_missing_develop_token(env, stub, opstub):
    """ⓑ develop 토큰 없음 → rc≠0 · 가짜 op 호출 0 (기본 kskill 토큰 대체 0)."""
    (env["sdir"] / "acct.cred").unlink()
    env["env"].pop("OP_SERVICE_ACCOUNT_TOKEN_DEVELOP")
    r = run(env, "--init-from-op", OP_ITEM, EMAIL)
    assert r.returncode != 0 and "develop 토큰 없음" in r.stdout
    assert not opstub["calls"].exists()
    assert not (env["sdir"] / "acct.cred").exists() and not (env["sdir"] / "acct.token").exists()


def test_o3_password_never_leaves_process(env, stub, opstub):
    """ⓒ 값이 stdout·stderr·cred 밖 파일 어디에도 0."""
    (env["sdir"] / "acct.cred").unlink()
    r = run(env, "--init-from-op", OP_ITEM, EMAIL)
    assert r.returncode == 0
    assert OP_PASSWORD not in r.stdout + r.stderr
    skip = {env["sdir"] / "acct.cred", opstub["body"]}
    leaks = [str(p) for p, t in _texts(env["sdir"].parent, skip) if OP_PASSWORD in t]
    assert leaks == []


def test_o4_op_failure_prints_no_stderr(env, stub, opstub):
    """ⓓ op rc≠0 + stderr 에 bare 비밀번호(패턴 없음)·토큰 꼴 → stdout 은 고정 문구만 · cred 쓰기 0."""
    (env["sdir"] / "acct.cred").unlink()
    bare_token = "optok-bare-1234567890"
    opstub["rc"].write_text("3")
    opstub["err"].write_text(f"read failed: {OP_PASSWORD}\nAuthorization: Bearer {bare_token}\n")
    r = run(env, "--init-from-op", OP_ITEM, EMAIL)
    assert r.returncode != 0
    nbytes = len(opstub["err"].read_text().encode("utf-8"))
    assert r.stdout == f"ERR op 읽기 실패 rc=3 (stderr {nbytes}바이트 · 원문 숨김)\n"
    assert OP_PASSWORD not in r.stdout + r.stderr and bare_token not in r.stdout + r.stderr
    assert "read failed" not in r.stdout + r.stderr and "Traceback" not in r.stderr
    assert opstub["calls"].read_text().count("run") == 1  # 재시도 0
    assert not (env["sdir"] / "acct.cred").exists() and not (env["sdir"] / "acct.token").exists()


def test_o5_op_empty_value(env, stub, opstub):
    """ⓔ op 빈 값 → ERR 빈 값 · cred 쓰기 0."""
    (env["sdir"] / "acct.cred").unlink()
    opstub["body"].write_text("\n")
    r = run(env, "--init-from-op", OP_ITEM, EMAIL)
    assert r.returncode != 0 and "빈 값" in r.stdout
    assert not (env["sdir"] / "acct.cred").exists() and not (env["sdir"] / "acct.token").exists()


def test_o6_op_timeout_no_retry(env, stub, opstub):
    """ⓕ op 가 10.5s 넘게 멈춤 → 시간 초과 ERR · 재시도 0 · cred 쓰기 0."""
    (env["sdir"] / "acct.cred").unlink()
    opstub["sleep"].write_text("")
    t0 = time.time()
    r = run(env, "--init-from-op", OP_ITEM, EMAIL, timeout=40)
    assert r.returncode != 0 and "시간 초과" in r.stdout and time.time() - t0 < 20
    assert opstub["calls"].read_text().count("run") == 1
    assert not (env["sdir"] / "acct.cred").exists() and not (env["sdir"] / "acct.token").exists()


def test_o7_login_fail_writes_no_cred(env, stub, opstub):
    """ⓖ 로그인 실패 → cred 쓰기 0 (값도 0)."""
    (env["sdir"] / "acct.cred").unlink()
    stub.mode = "400"
    r = run(env, "--init-from-op", OP_ITEM, EMAIL)
    assert r.returncode == 1 and r.stdout.startswith(f"ERR {EMAIL} http=400")
    assert OP_PASSWORD not in r.stdout + r.stderr
    assert not (env["sdir"] / "acct.cred").exists() and not (env["sdir"] / "acct.token").exists()


# ── r611 --init-from-op: 표에 없는 계정이면 도구가 표 줄까지 추가 (사용자 이름 = 이메일일 때만) ──
NEW_EMAIL = "new.user@x"
NEW_CRED = "byz_new_user.cred"
NEW_TOKEN = "byz_new_user_token_dev"


def table_text(env):
    return (env["sdir"] / "op-accounts.tsv").read_text()


def test_r611a_unknown_email_appends_row_after_login(env, stub, opstub):
    """ⓐ 표에 없는 이메일 + op username == 이메일 → 표 끝 1줄 + cred·token 생성 · stdout «(표 줄 추가)»."""
    opstub["userbody"].write_text(NEW_EMAIL + "\n")
    before = table_text(env)
    r = run(env, "--init-from-op", OP_ITEM, NEW_EMAIL)
    assert r.returncode == 0, r.stdout + r.stderr
    assert r.stdout.startswith(f"OK {NEW_EMAIL} exp=") and f"file={NEW_TOKEN}" in r.stdout
    assert r.stdout.rstrip("\n").endswith("(표 줄 추가)")
    assert table_text(env) == before + f"{NEW_EMAIL}\t{NEW_CRED}\t{NEW_TOKEN}\n"
    cred, tok = env["sdir"] / NEW_CRED, env["sdir"] / NEW_TOKEN
    assert json.loads(cred.read_text())["password"] == OP_PASSWORD
    assert tok.read_text() == stub.token and mode(cred) == 0o600 and mode(tok) == 0o600
    calls = opstub["calls"].read_text().count("run")
    assert calls == 2  # 표 줄용 username + 비밀번호, develop 고정 env 고정 argv('--reveal' 은 비밀번호만)
    assert opstub["argv"].read_text().splitlines() == [
        "item", "get", OP_ITEM, "--vault", "develop", "--fields", "label=password", "--reveal"]
    assert stub.calls == 1 and OP_PASSWORD not in r.stdout + r.stderr


def test_r611b_username_not_email_rejects(env, stub, opstub):
    """ⓑ op username ≠ 이메일 → ERR rc2 · 표·cred 쓰기 0."""
    before = table_text(env)
    opstub["userbody"].write_text("someone.else@x\n")
    r = run(env, "--init-from-op", OP_ITEM, NEW_EMAIL)
    assert r.returncode == 2 and r.stdout.startswith(f"ERR 항목 사용자 이름 ≠ {NEW_EMAIL}")
    assert table_text(env) == before and stub.calls == 0
    assert not (env["sdir"] / NEW_CRED).exists() and not (env["sdir"] / NEW_TOKEN).exists()


def test_r611b2_username_read_failure_fixed_line(env, stub, opstub):
    """ⓑ2 username 읽기 실패 → r605 와 같은 고정 문구 · 표 쓰기 0."""
    before = table_text(env)
    opstub["rc"].write_text("3")
    opstub["err"].write_text("denied\n")
    r = run(env, "--init-from-op", OP_ITEM, NEW_EMAIL)
    assert r.returncode != 0 and r.stdout.startswith("ERR op 읽기 실패 rc=3 (stderr ")
    assert "denied" not in r.stdout + r.stderr
    assert table_text(env) == before and not (env["sdir"] / NEW_CRED).exists()


def test_r611c_login_failure_writes_no_row(env, stub, opstub):
    """ⓒ 로그인 실패 → 표 줄 추가 0 (표는 로그인 성공 뒤에만)."""
    opstub["userbody"].write_text(NEW_EMAIL + "\n")
    before = table_text(env)
    stub.mode = "400"
    r = run(env, "--init-from-op", OP_ITEM, NEW_EMAIL)
    assert r.returncode == 1 and r.stdout.startswith(f"ERR {NEW_EMAIL} http=400")
    assert table_text(env) == before
    assert not (env["sdir"] / NEW_CRED).exists() and not (env["sdir"] / NEW_TOKEN).exists()


def test_r611d_name_collision_rejects(env, stub, opstub):
    """ⓓ 새 이름이 이미 있는 파일·표 줄과 겹침 → ERR · 쓰기 0."""
    opstub["userbody"].write_text(NEW_EMAIL + "\n")
    before = table_text(env)
    p = env["sdir"] / NEW_CRED
    p.write_text("{}")
    p.chmod(0o600)
    r = run(env, "--init-from-op", OP_ITEM, NEW_EMAIL)
    assert r.returncode == 2 and "이름 겹침" in r.stdout and NEW_CRED in r.stdout
    assert table_text(env) == before and stub.calls == 0
    p.unlink()
    tsv = env["sdir"] / "op-accounts.tsv"
    tsv.write_text(before + f"third@example.test\t{NEW_TOKEN}\tother.token\n")
    tsv.chmod(0o600)
    r2 = run(env, "--init-from-op", OP_ITEM, NEW_EMAIL)
    assert r2.returncode == 2 and "이름 겹침" in r2.stdout and NEW_TOKEN in r2.stdout
    assert table_text(env).endswith(f"third@example.test\t{NEW_TOKEN}\tother.token\n")


def test_r611e_table_write_is_atomic_and_keeps_bytes(env, stub, opstub):
    """ⓔ 표 = 원자 쓰기(임시 파일 잔여 0) · 권한 600 유지 · 기존 줄 바이트 불변."""
    opstub["userbody"].write_text(NEW_EMAIL + "\n")
    before = table_text(env)
    r = run(env, "--init-from-op", OP_ITEM, NEW_EMAIL)
    assert r.returncode == 0
    tsv = env["sdir"] / "op-accounts.tsv"
    assert mode(tsv) == 0o600
    assert table_text(env).startswith(before) and table_text(env).count("\n") == before.count("\n") + 1
    assert not [p for p in env["sdir"].iterdir() if p.name.startswith(".tmp-")]


def test_r611f_known_account_unchanged(env, stub, opstub):
    """ⓕ 이미 표에 있는 계정 → r605 동작 그대로(표 바이트 불변 · username 호출 0 · 꼬리 없음)."""
    before = table_text(env)
    (env["sdir"] / "acct.cred").unlink()
    r = run(env, "--init-from-op", OP_ITEM, EMAIL)
    assert r.returncode == 0 and "(표 줄 추가)" not in r.stdout
    assert table_text(env) == before
    assert opstub["argv"].read_text().splitlines()[-1] == "--reveal"
    assert opstub["calls"].read_text().count("run") == 1


# ── r614 --init-from-op 표 줄 추가: 동시 등록 잠금 · 제어문자 거절 · 기존 줄바꿈 바이트 보존 ──
def run_with(env, extra_env, *args):
    e = dict(env["env"], **extra_env)
    return subprocess.run(["bash", str(TOOL), *args], env=e, capture_output=True, text=True, timeout=120)


def spawn(env, extra_env, *args):
    e = dict(env["env"], **extra_env)
    return subprocess.Popen(["bash", str(TOOL), *args], env=e, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)


def alpha_beta_table(env):
    return [ln for ln in table_text(env).splitlines() if not ln.startswith("#")]


def test_r614a_concurrent_distinct_emails_keep_all_rows(env, stub, opstub):
    """ⓐ 다른 두 이메일 동시 등록 — 표에 셋 다 남고 둘 다 rc0 (r611 판은 한 줄 잃는다)."""
    stub.delay = 0.4
    before = alpha_beta_table(env)
    a, b = "alpha@x", "beta@x"
    p1 = spawn(env, {"STUB_USERNAME": a}, "--init-from-op", OP_ITEM, a)
    p2 = spawn(env, {"STUB_USERNAME": b}, "--init-from-op", OP_ITEM, b)
    o1, o2 = p1.communicate(timeout=120), p2.communicate(timeout=120)
    assert (p1.returncode, p2.returncode) == (0, 0), (o1, o2)
    rows = alpha_beta_table(env)
    assert rows[:2] == before
    assert sorted(rows[2:]) == sorted([f"{a}\tbyz_alpha.cred\tbyz_alpha_token_dev",
                                       f"{b}\tbyz_beta.cred\tbyz_beta_token_dev"])


def test_r614b_same_email_twice_one_row(env, stub, opstub):
    """ⓑ 같은 이메일 동시 두 번 — 표에 1줄 · 둘 다 rc0(늦은 쪽 = 이미 표에 있음 길)."""
    stub.delay = 0.4
    p1 = spawn(env, {"STUB_USERNAME": NEW_EMAIL}, "--init-from-op", OP_ITEM, NEW_EMAIL)
    p2 = spawn(env, {"STUB_USERNAME": NEW_EMAIL}, "--init-from-op", OP_ITEM, NEW_EMAIL)
    p1.communicate(timeout=120)
    p2.communicate(timeout=120)
    assert (p1.returncode, p2.returncode) == (0, 0)
    rows = [ln for ln in alpha_beta_table(env) if ln.startswith(NEW_EMAIL + "\t")]
    assert rows == [f"{NEW_EMAIL}\t{NEW_CRED}\t{NEW_TOKEN}"]
    assert json.loads((env["sdir"] / NEW_CRED).read_text())["password"] == OP_PASSWORD


def test_r614c_same_slug_other_email_one_row_and_collision(env, stub, opstub):
    """ⓒ slug 가 같은 다른 이메일 동시 — 한 줄만 · 다른 쪽 rc2 «이름 겹침» · cred 소유자 = 줄 가진 email."""
    stub.delay = 0.4
    a, b = "same@a", "same@b"
    p1 = spawn(env, {"STUB_USERNAME": a}, "--init-from-op", OP_ITEM, a)
    p2 = spawn(env, {"STUB_USERNAME": b}, "--init-from-op", OP_ITEM, b)
    o1, o2 = p1.communicate(timeout=120), p2.communicate(timeout=120)
    rcs = sorted([p1.returncode, p2.returncode])
    assert rcs == [0, 2], (o1, o2)
    rows = [ln for ln in alpha_beta_table(env) if ln.startswith("same@")]
    assert len(rows) == 1
    owner = rows[0].split("\t")[0]
    loser = o1 if owner == b else o2
    assert "이름 겹침" in loser[0] or "이름 겹침" in loser[1], (o1, o2)
    assert table_text(env).count("byz_same.cred") == 1


@pytest.mark.parametrize("bad", ["bad\tmail@x", "bad\nmail@x", "bad\rmail@x"])
def test_r614d_email_control_chars_rejected(env, stub, opstub, bad):
    """ⓓ-1 이메일에 TAB·LF·CR → rc2 «제어문자» · op 호출 0 · 표 쓰기 0."""
    before = table_text(env)
    r = run_with(env, {"STUB_USERNAME": bad}, "--init-from-op", OP_ITEM, bad)  # op 사용자 이름도 같은 값
    assert r.returncode == 2 and "제어문자" in r.stdout, r.stdout
    assert table_text(env) == before
    assert not opstub["calls"].exists() and stub.calls == 0


def test_r614d2_username_control_chars_rejected(env, stub, opstub):
    """ⓓ-2 op 사용자 이름에 TAB → rc2 «제어문자» · 비밀번호 조회 전 거절(calls=1) · 표 쓰기 0."""
    opstub["userbody"].write_text(NEW_EMAIL + "\t\n")
    before = table_text(env)
    r = run(env, "--init-from-op", OP_ITEM, NEW_EMAIL)
    assert r.returncode == 2 and "제어문자" in r.stdout, r.stdout
    assert table_text(env) == before and stub.calls == 0
    assert opstub["calls"].read_text().count("run") == 1


def test_r614e_crlf_table_bytes_preserved(env, stub, opstub):
    """ⓔ-1 기존 표가 CRLF → 성공 뒤 기존 바이트 전부 그대로 · 새 줄도 CRLF."""
    opstub["userbody"].write_text(NEW_EMAIL + "\n")
    tsv = env["sdir"] / "op-accounts.tsv"
    crlf = table_text(env).replace("\n", "\r\n").encode()
    tsv.write_bytes(crlf)
    tsv.chmod(0o600)
    r = run(env, "--init-from-op", OP_ITEM, NEW_EMAIL)
    assert r.returncode == 0, r.stdout + r.stderr
    after = tsv.read_bytes()
    assert after.startswith(crlf)
    assert after == crlf + f"{NEW_EMAIL}\t{NEW_CRED}\t{NEW_TOKEN}\r\n".encode()


def test_r614e2_no_trailing_newline_gets_lf(env, stub, opstub):
    """ⓔ-2 마지막 줄에 개행 없음 → 기존 바이트 + LF 1개 + 새 줄(LF) — 지금처럼."""
    opstub["userbody"].write_text(NEW_EMAIL + "\n")
    tsv = env["sdir"] / "op-accounts.tsv"
    head = f"{EMAIL}\tacct.cred\tacct.token".encode()
    tsv.write_bytes(head)
    tsv.chmod(0o600)
    r = run(env, "--init-from-op", OP_ITEM, NEW_EMAIL)
    assert r.returncode == 0, r.stdout + r.stderr
    assert tsv.read_bytes() == head + b"\n" + f"{NEW_EMAIL}\t{NEW_CRED}\t{NEW_TOKEN}\n".encode()


def test_r614e3_crlf_table_existing_account_reads_and_stays(env, stub, opstub):
    """ⓔ-3 CRLF 표를 read_table 이 지금처럼 읽는다(표에 있는 계정 → 표 줄 추가 0 · 바이트 불변)."""
    tsv = env["sdir"] / "op-accounts.tsv"
    crlf = table_text(env).replace("\n", "\r\n").encode()
    tsv.write_bytes(crlf)
    tsv.chmod(0o600)
    (env["sdir"] / "acct.cred").unlink()
    r = run(env, "--init-from-op", OP_ITEM, EMAIL)
    assert r.returncode == 0, r.stdout + r.stderr
    assert "(표 줄 추가)" not in r.stdout
    assert tsv.read_bytes() == crlf


def test_r614_lock_waits_for_holder(env, stub, opstub):
    """ⓐ-2 다른 등록이 잠금을 쥐고 있으면 기다렸다가 성공(잠금 실재)."""
    opstub["userbody"].write_text(NEW_EMAIL + "\n")
    lock = env["sdir"] / "op-accounts.tsv.lock"
    holder = subprocess.Popen(
        ["python3", "-c", "import fcntl,time,sys\n"
                          f"f=open({str(lock)!r},'w')\nfcntl.flock(f,fcntl.LOCK_EX)\n"
                          "time.sleep(1.5)\n"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    time.sleep(0.3)
    t0 = time.time()
    try:
        r = run(env, "--init-from-op", OP_ITEM, NEW_EMAIL)
    finally:
        holder.communicate(timeout=30)
    waited = time.time() - t0
    assert r.returncode == 0, r.stdout + r.stderr
    assert waited >= 1.0, waited
    assert mode(lock) == 0o600 and lock.read_text() == ""


def test_r614_lock_timeout_err(env, stub, opstub):
    """ⓐ-3 잠금을 20초 넘게 못 얻으면 rc2 «잠금 대기 초과» — op 호출 0 · 표 쓰기 0."""
    opstub["userbody"].write_text(NEW_EMAIL + "\n")
    before = table_text(env)
    lock = env["sdir"] / "op-accounts.tsv.lock"
    holder = subprocess.Popen(
        ["python3", "-c", "import fcntl,time\n"
                          f"f=open({str(lock)!r},'w')\nfcntl.flock(f,fcntl.LOCK_EX)\n"
                          "time.sleep(30)\n"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    time.sleep(0.3)
    try:
        r = run(env, "--init-from-op", OP_ITEM, NEW_EMAIL, timeout=40)
    finally:
        holder.kill()
        holder.communicate(timeout=30)
    assert r.returncode == 2 and "잠금 대기 초과" in r.stdout, r.stdout
    assert table_text(env) == before and stub.calls == 0


# ---- r1237: --path 길 + 받기 경고 (R1~R5) ----
WARN_HEAD = "WARN ft-op-token: stdout 은 상태 줄이다"


def run_pty(env, *args, timeout=60):
    """stdout 을 pty(터미널)로 받는 호출 — (rc, 출력, stderr). stderr 는 파이프."""
    import pty
    import select
    master, slave = pty.openpty()
    out = b""
    try:
        p = subprocess.Popen(["bash", str(TOOL), *args], env=env["env"], stdout=slave, stderr=subprocess.PIPE, text=True)
        os.close(slave)  # 자식만 slave 를 쥐게 한다 — macOS 는 slave 가 닫히기 전에 master 를 읽어야 출력이 남는다
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if select.select([master], [], [], 0.1)[0]:
                try:
                    chunk = os.read(master, 4096)
                except OSError:
                    break
                if not chunk:
                    break
                out += chunk
            elif p.poll() is not None:
                break
        err = p.stderr.read()
        p.wait(timeout=5)
    finally:
        os.close(master)
    return p.returncode, out.decode("utf-8", "replace"), err


def test_r1237_r1_path_prints_token_file_abs_path_only(env, stub):
    r = run(env, "--path", EMAIL)
    lines = r.stdout.splitlines()
    tf = env["sdir"] / "acct.token"
    assert r.returncode == 0 and lines == [str(tf)], r.stdout
    assert os.path.isabs(lines[0]) and tf.read_text() == stub.token
    assert r.stderr.startswith(f"OK {EMAIL} exp=") and WARN_HEAD not in r.stderr
    assert_no_secret(r, stub)


def test_r1237_r2_pipe_default_keeps_status_line_and_warns(env, stub):
    r = run(env, EMAIL)
    tf = env["sdir"] / "acct.token"
    assert r.returncode == 0 and r.stdout.startswith(f"OK {EMAIL} exp=") and f"path={tf}" in r.stdout
    warns = [ln for ln in r.stderr.splitlines() if ln.startswith(WARN_HEAD)]
    assert len(warns) == 1 and "--path" in warns[0], r.stderr
    assert_no_secret(r, stub)


def test_r1237_r3_pty_default_has_no_warn(env, stub):
    rc, out, err = run_pty(env, EMAIL)
    assert rc == 0 and out.startswith(f"OK {EMAIL} exp=") and "file=acct.token" in out, out
    assert WARN_HEAD not in err and WARN_HEAD not in out
    assert stub.token not in out + err and PASSWORD not in out + err


def test_r1237_r4_path_unknown_account_same_fail_line_no_path(env, stub):
    default = run(env, "nobody@example.test")
    r = run(env, "--path", "nobody@example.test")
    assert r.returncode == default.returncode == 2
    assert r.stdout == default.stdout and "계정 표에 없음" in r.stdout
    assert str(env["sdir"]) not in r.stdout and stub.calls == 0


def test_r1237_r5_regression_init_and_list_unchanged(env, stub):
    (env["sdir"] / "acct.cred").unlink()
    ri = run(env, "--init", EMAIL)
    assert ri.returncode == 0 and ri.stdout.startswith("OK ") and WARN_HEAD not in ri.stderr
    rl = run(env, "--list")
    assert rl.returncode == 0 and rl.stdout.startswith(EMAIL + "\t") and WARN_HEAD not in rl.stderr
    assert_no_secret(ri, stub)


def test_r1237_path_usage_needs_one_email(env):
    r = run(env, "--path")
    assert r.returncode == 2 and "--path <email>" in r.stderr
